import Foundation

/// Failures from bounded RTP, discovery and packet scheduling. No media bytes are included.
public enum VoicePacketError: Error, Sendable, Equatable {
    case malformedPacket
    case packetTooLarge
    case invalidConfiguration
    case wrongStream
    case duplicateOrLate
    case capacityExceeded
}

/// An owned RTP v2 extension. Extension data remains encrypted in Discord's rtpsize modes.
public struct RTPExtension: Sendable, Equatable {
    public let profile: UInt16
    public let bytes: Data

    /// Stores complete extension words without interpreting codec-specific elements.
    /// - Parameters:
    ///   - profile: RFC 3550 extension profile identifier.
    ///   - bytes: A multiple of four bytes, at most 65,535 words. The packet's tighter
    ///     UDP size limit is checked separately by `RTPPacket`.
    /// - Throws: `VoicePacketError.malformedPacket` for an invalid word count.
    public init(profile: UInt16, bytes: Data) throws {
        guard bytes.count.isMultiple(of: 4), bytes.count / 4 <= Int(UInt16.max) else {
            throw VoicePacketError.malformedPacket
        }
        self.profile = profile
        self.bytes = bytes.withUnsafeBytes { Data($0) }
    }
}

/// Complete plaintext RTP v2 packet with preserved CSRCs, extension data and padding.
///
/// This value does not authenticate packets. Use `authenticatedHeaderLength(in:)`
/// to separate clear AAD from ciphertext, authenticate first, then parse plaintext.
/// All packets are capped at 65,507 bytes, the IPv4 UDP payload maximum. RTP time
/// and sequence numbers wrap independently from cryptographic nonce counters.
public struct RTPPacket: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let payloadType: UInt8
    public let marker: Bool
    public let sequence: UInt16
    public let timestamp: UInt32
    public let ssrc: UInt32
    public let contributingSources: [UInt32]
    public let headerExtension: RTPExtension?
    public let payload: Data
    public let paddingCount: UInt8

    /// Validates a plaintext RTP packet without I/O or codec interpretation.
    /// - Parameters:
    ///   - payloadType: Seven-bit negotiated media type; Discord Opus uses 120.
    ///   - marker: Negotiated RTP marker bit, false by default.
    ///   - sequence: Sixteen-bit packet sequence, including zero and rollover.
    ///   - timestamp: Thirty-two-bit media clock tick count; audio uses 48 kHz.
    ///   - ssrc: Negotiated synchronization source, not a user identifier.
    ///   - contributingSources: At most fifteen CSRC identifiers, in wire order.
    ///   - headerExtension: Optional profile and complete four-byte extension words.
    ///   - payload: Complete media payload, possibly empty; copied into dense owned storage.
    ///   - paddingCount: Total padding bytes, zero for none; final byte carries this count.
    /// - Throws: `VoicePacketError.malformedPacket` for an invalid type/CSRC count;
    ///   `.packetTooLarge` if serialization exceeds 65,507 bytes.
    public init(payloadType: UInt8 = 120, marker: Bool = false, sequence: UInt16,
                timestamp: UInt32, ssrc: UInt32, contributingSources: [UInt32] = [],
                headerExtension: RTPExtension? = nil, payload: Data, paddingCount: UInt8 = 0) throws {
        guard payloadType < 128, contributingSources.count <= 15 else { throw VoicePacketError.malformedPacket }
        let overhead = 12 + contributingSources.count * 4 + (headerExtension.map { 4 + $0.bytes.count } ?? 0) + Int(paddingCount)
        guard payload.count <= 65_507 - overhead else { throw VoicePacketError.packetTooLarge }
        self.payloadType = payloadType
        self.marker = marker
        self.sequence = sequence
        self.timestamp = timestamp
        self.ssrc = ssrc
        self.contributingSources = contributingSources
        self.headerExtension = headerExtension
        self.payload = payload.withUnsafeBytes { Data($0) }
        self.paddingCount = paddingCount
    }

    /// Parses a complete, already authenticated plaintext packet, including RTP padding.
    /// - Parameter bytes: A complete packet of at most 65,507 bytes. Slices are accepted.
    /// - Throws: `VoicePacketError` for wrong RTP version, truncation, impossible
    ///   extension/padding lengths or excess size. No partial packet is returned.
    public init(bytes: Data) throws {
        let clearLength = try Self.authenticatedHeaderLength(in: bytes)
        let wire = Array(bytes)
        let count = Int(wire[0] & 15)
        var sources: [UInt32] = []
        for index in 0..<count { sources.append(Self.read32(wire, at: 12 + 4 * index)) }
        var cursor = clearLength
        var ext: RTPExtension?
        if wire[0] & 0x10 != 0 {
            let preamble = 12 + count * 4
            let length = Int(Self.read16(wire, at: preamble + 2)) * 4
            guard length <= wire.count - cursor else { throw VoicePacketError.malformedPacket }
            ext = try RTPExtension(profile: Self.read16(wire, at: preamble), bytes: Data(wire[cursor..<(cursor + length)]))
            cursor += length
        }
        var padding: UInt8 = 0
        if wire[0] & 0x20 != 0 {
            guard wire.count > cursor, let last = wire.last, last > 0, Int(last) <= wire.count - cursor else {
                throw VoicePacketError.malformedPacket
            }
            padding = last
        }
        try self.init(payloadType: wire[1] & 0x7f, marker: wire[1] & 0x80 != 0,
                      sequence: Self.read16(wire, at: 2), timestamp: Self.read32(wire, at: 4),
                      ssrc: Self.read32(wire, at: 8), contributingSources: sources,
                      headerExtension: ext, payload: Data(wire[cursor..<(wire.count - Int(padding))]), paddingCount: padding)
    }

    /// Determines the clear header authenticated by Discord's rtpsize AEAD modes.
    /// - Parameter bytes: RTP header followed by ciphertext or plaintext, bounded to 65,507 bytes.
    /// - Returns: Twelve fixed bytes, CSRC words and, when present, the four-byte
    ///   extension preamble. The extension's content is **not** included in AAD.
    /// - Throws: `VoicePacketError` for size, wrong version or truncated clear header.
    ///   Ciphertext, extension content and padding cannot be validated before authentication.
    public static func authenticatedHeaderLength(in bytes: Data) throws -> Int {
        guard bytes.count <= 65_507 else { throw VoicePacketError.packetTooLarge }
        guard bytes.count >= 12 else { throw VoicePacketError.malformedPacket }
        let first = bytes[bytes.startIndex]
        guard first >> 6 == 2 else { throw VoicePacketError.malformedPacket }
        let length = 12 + Int(first & 15) * 4 + (first & 0x10 != 0 ? 4 : 0)
        guard length <= bytes.count else { throw VoicePacketError.malformedPacket }
        return length
    }

    /// Serializes network-order fields, extension words, media and canonical zero padding.
    /// - Returns: A complete plaintext packet. Padding bytes other than the last are zero;
    ///   parsing and rewriting arbitrary padding therefore canonicalizes those bytes.
    public func serialized() -> Data {
        var wire: [UInt8] = [0x80 | (paddingCount > 0 ? 0x20 : 0) | (headerExtension != nil ? 0x10 : 0) | UInt8(contributingSources.count), payloadType | (marker ? 0x80 : 0)]
        wire += Self.networkBytes(UInt32(sequence), count: 2)
        wire += Self.networkBytes(timestamp, count: 4)
        wire += Self.networkBytes(ssrc, count: 4)
        for source in contributingSources { wire += Self.networkBytes(source, count: 4) }
        if let ext = headerExtension {
            wire += Self.networkBytes(UInt32(ext.profile), count: 2)
            wire += Self.networkBytes(UInt32(ext.bytes.count / 4), count: 2)
            wire += ext.bytes
        }
        wire += payload
        if paddingCount > 0 { wire += Array(repeating: 0, count: Int(paddingCount) - 1); wire.append(paddingCount) }
        return Data(wire)
    }

    /// Hides media, participants and packet metadata from ordinary diagnostics.
    public var description: String { "RTPPacket(redacted)" }
    /// Uses the same safe representation for debug output.
    public var debugDescription: String { description }
    /// Prevents generic reflection from exposing retained media.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }

    /// Reads a network-order two-byte integer from an already validated local array.
    /// - Parameters:
    ///   - bytes: Bytes whose bounds have been checked by the parser.
    ///   - offset: Index with two readable bytes.
    /// - Returns: The represented integer without host-endian assumptions.
    private static func read16(_ bytes: [UInt8], at offset: Int) -> UInt16 {
        UInt16(bytes[offset]) << 8 | UInt16(bytes[offset + 1])
    }

    /// Reads four network-order bytes after the caller checks bounds.
    /// - Parameters:
    ///   - bytes: Complete parser-local bytes.
    ///   - offset: Index with four readable bytes.
    /// - Returns: The represented unsigned integer.
    private static func read32(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        UInt32(read16(bytes, at: offset)) << 16 | UInt32(read16(bytes, at: offset + 2))
    }

    /// Emits the low two or four bytes of a value in network order.
    /// - Parameters:
    ///   - value: An unsigned field already validated by its typed representation.
    ///   - count: Two or four, as used by RTP field encodings.
    /// - Returns: Exactly `count` network-order bytes.
    private static func networkBytes(_ value: UInt32, count: Int) -> [UInt8] {
        (0..<count).reversed().map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) }
    }
}
