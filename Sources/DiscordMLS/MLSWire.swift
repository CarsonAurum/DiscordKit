// File: Sources/DiscordMLS/MLSWire.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import Foundation

/// Failures detected before MLS state may be published or plaintext released.
///
/// Errors contain no secrets, credential identities, or remote-controlled text.
/// Callers must discard the candidate operation on failure and may retain the
/// previously authenticated group state. Transport retry policy belongs to callers.
public enum MLSError: Error, Sendable, Equatable {
    case invalidConfiguration, malformedEncoding, unsupportedVersion, unsupportedCipherSuite
    case invalidSignature, authenticationFailed, invalidCredential, invalidKeyPackage
    case invalidTree, invalidProposal, invalidCommit, wrongEpoch, replayedMessage
    case capacityExceeded, closed, removed, staleGeneration, confirmationFailed
}

/// Bounded RFC 9420 presentation-language encoder using network byte order.
///
/// Vectors use the required shortest one-, two-, or four-byte length encoding.
/// The default one-MiB per-object limit is deliberately below the protocol's
/// theoretical one-GiB vector size; applications may select a lower budget.
public struct MLSWriter: Sendable {
    public private(set) var data = Data()
    public let maximumBytes: Int

    /// Creates an empty in-memory encoder; construction performs no I/O.
    /// - Parameter maximumBytes: Positive maximum encoded object bytes. A nonpositive
    ///   value allows no vector/raw writes and is rejected by those operations.
    public init(maximumBytes: Int = 1_048_576) { self.maximumBytes = maximumBytes }

    /// Appends an unsigned octet. Fixed-width scalar writes allocate at most eight
    /// bytes per invocation; surrounding vector/raw writes enforce object budgets.
    /// - Parameter value: The complete eight-bit wire value.
    public mutating func write(_ value: UInt8) { data.append(value) }

    /// Appends a network-order unsigned sixteen-bit value.
    /// - Parameter value: The complete sixteen-bit wire value.
    public mutating func write(_ value: UInt16) {
        data.append(UInt8(truncatingIfNeeded: value >> 8)); data.append(UInt8(truncatingIfNeeded: value))
    }

    /// Appends a network-order unsigned thirty-two-bit value.
    /// - Parameter value: The complete thirty-two-bit wire value.
    public mutating func write(_ value: UInt32) {
        for shift in stride(from: 24, through: 0, by: -8) { data.append(UInt8(truncatingIfNeeded: value >> shift)) }
    }

    /// Appends a network-order unsigned sixty-four-bit value.
    /// - Parameter value: The complete sixty-four-bit wire value.
    public mutating func write(_ value: UInt64) {
        for shift in stride(from: 56, through: 0, by: -8) { data.append(UInt8(truncatingIfNeeded: value >> shift)) }
    }

    /// Appends previously encoded fields without an additional length prefix.
    /// - Parameter bytes: Encoded fields to concatenate, including empty data.
    /// - Throws: `capacityExceeded` if the resulting object exceeds its budget.
    ///   The writer is unchanged when this check fails.
    public mutating func writeRaw(_ bytes: Data) throws {
        guard maximumBytes > 0, data.count <= maximumBytes, bytes.count <= maximumBytes - data.count else {
            throw MLSError.capacityExceeded
        }
        data.append(bytes)
    }

    /// Appends a variable-size vector with its canonical RFC 9420 length prefix.
    /// - Parameter bytes: Vector payload, bounded by the object budget and 30-bit length.
    /// - Throws: `capacityExceeded` before mutation if payload or result is too large.
    public mutating func writeVector(_ bytes: Data) throws {
        let count = bytes.count
        let header = count < 64 ? 1 : count < 16_384 ? 2 : 4
        guard count <= 0x3fff_ffff, maximumBytes > 0, data.count <= maximumBytes,
              header <= maximumBytes - data.count, count <= maximumBytes - data.count - header else {
            throw MLSError.capacityExceeded
        }
        switch header {
        case 1: write(UInt8(count))
        case 2: write(UInt16(count) | 0x4000)
        default: write(UInt32(count) | 0x8000_0000)
        }
        data.append(bytes)
    }
}

/// Cursor over a bounded immutable MLS object. Every read rejects truncation.
///
/// The cursor owns a value-semantic Data snapshot. Vector lengths are checked
/// before slicing or allocation, and overlong/noncanonical lengths are rejected.
public struct MLSReader: Sendable {
    private let data: Data
    private var offset = 0
    public let maximumBytes: Int
    /// Whether every byte has been consumed; inspection does not advance the cursor.
    public var isAtEnd: Bool { offset == data.count }
    /// Number of unread bytes, always nonnegative and within the input budget.
    public var remainingCount: Int { data.count - offset }

    /// Validates an input object's budget without interpreting its fields.
    /// - Parameters:
    ///   - data: Complete object bytes, including an empty object when its schema permits.
    ///   - maximumBytes: Positive maximum object size in bytes; defaults to one MiB.
    /// - Throws: `capacityExceeded` for excessive input or `invalidConfiguration`
    ///   for a nonpositive budget. No I/O or asynchronous work occurs.
    public init(_ data: Data, maximumBytes: Int = 1_048_576) throws {
        guard maximumBytes > 0 else { throw MLSError.invalidConfiguration }
        guard data.count <= maximumBytes else { throw MLSError.capacityExceeded }
        self.data = Data(data); self.maximumBytes = maximumBytes
    }

    /// Consumes one octet.
    /// - Returns: The next unsigned byte.
    /// - Throws: `malformedEncoding` on truncation.
    public mutating func readUInt8() throws -> UInt8 {
        guard offset < data.count else { throw MLSError.malformedEncoding }
        defer { offset += 1 }; return data[offset]
    }

    /// Consumes a sixteen-bit network-order integer.
    /// - Returns: The decoded unsigned integer.
    /// - Throws: `malformedEncoding` on truncation.
    public mutating func readUInt16() throws -> UInt16 {
        let bytes = try readRaw(count: 2)
        return bytes.reduce(UInt16(0)) { ($0 << 8) | UInt16($1) }
    }

    /// Consumes a thirty-two-bit network-order integer.
    /// - Returns: The decoded unsigned integer.
    /// - Throws: `malformedEncoding` on truncation.
    public mutating func readUInt32() throws -> UInt32 {
        let bytes = try readRaw(count: 4)
        return bytes.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }

    /// Consumes a sixty-four-bit network-order integer.
    /// - Returns: The decoded unsigned integer.
    /// - Throws: `malformedEncoding` on truncation.
    public mutating func readUInt64() throws -> UInt64 {
        let bytes = try readRaw(count: 8)
        return bytes.reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
    }

    /// Copies an exact number of bytes after validating remaining input.
    /// - Parameter count: Nonnegative number of bytes to consume.
    /// - Returns: Exactly `count` bytes, including empty data for zero.
    /// - Throws: `malformedEncoding` for negative counts or truncation. Cursor
    ///   position is unchanged when validation fails.
    public mutating func readRaw(count: Int) throws -> Data {
        guard count >= 0, count <= remainingCount else { throw MLSError.malformedEncoding }
        defer { offset += count }; return data.subdata(in: offset..<(offset + count))
    }

    /// Consumes one canonically encoded variable-size vector.
    /// - Returns: Its payload without the length prefix.
    /// - Throws: `malformedEncoding` for prefix `11`, an overlong integer, or
    ///   truncated input; `capacityExceeded` if its claimed length exceeds budget.
    public mutating func readVector() throws -> Data {
        let first = try readUInt8()
        let prefix = first >> 6
        guard prefix < 3 else { throw MLSError.malformedEncoding }
        let width = 1 << Int(prefix)
        var count = Int(first & 0x3f)
        for _ in 1..<width { count = (count << 8) | Int(try readUInt8()) }
        guard (width != 2 || count >= 64), (width != 4 || count >= 16_384) else {
            throw MLSError.malformedEncoding
        }
        guard count <= maximumBytes else { throw MLSError.capacityExceeded }
        return try readRaw(count: count)
    }

    /// Rejects extra bytes after a complete schema was decoded.
    /// - Throws: `malformedEncoding` when any input remains.
    public func requireEnd() throws {
        guard isAtEnd else { throw MLSError.malformedEncoding }
    }
}

/// Extensible RFC 9420 type-and-byte payload, preserving unknown extension IDs.
public struct MLSExtension: Sendable, Equatable {
    public let type: UInt16
    public let data: Data

    /// Creates an extension whose syntax is interpreted by its enclosing context.
    /// - Parameters:
    ///   - type: IANA extension code point; unknown values remain representable.
    ///   - data: Opaque extension-specific encoding, limited to 64 KiB.
    /// - Throws: `capacityExceeded` when the extension data is too large.
    public init(type: UInt16, data: Data) throws {
        guard data.count <= 65_536 else { throw MLSError.capacityExceeded }
        self.type = type; self.data = data
    }

    /// Serializes the type code and canonical opaque vector.
    /// - Returns: RFC 9420 Extension bytes.
    /// - Throws: Encoder capacity errors for excessive aggregate data.
    public func encoded() throws -> Data {
        var writer = MLSWriter(); writer.write(type); try writer.writeVector(data); return writer.data
    }

    /// Decodes one extension from an enclosing bounded reader.
    /// - Parameter reader: Cursor advanced past this extension on success.
    /// - Returns: Preserved code point and payload.
    /// - Throws: Wire/capacity errors on malformed, truncated, or excessive input.
    public static func decode(_ reader: inout MLSReader) throws -> Self {
        try Self(type: reader.readUInt16(), data: reader.readVector())
    }

    /// Encodes a unique-type extension list as the enclosing vector.
    /// - Parameter extensions: At most 128 uniquely typed extensions, preserving order.
    /// - Returns: Canonical vector of encoded extensions.
    /// - Throws: `malformedEncoding` for duplicate types or capacity errors.
    public static func encodeList(_ extensions: [Self]) throws -> Data {
        guard extensions.count <= 128 else { throw MLSError.capacityExceeded }
        guard Set(extensions.map(\.type)).count == extensions.count else { throw MLSError.malformedEncoding }
        var body = MLSWriter()
        for item in extensions { try body.writeRaw(item.encoded()) }
        var outer = MLSWriter(); try outer.writeVector(body.data); return outer.data
    }

    /// Decodes an extension vector, rejecting duplicate types and excessive counts.
    /// - Parameter reader: Enclosing object cursor advanced through the vector.
    /// - Returns: Extensions in their original wire order, including unknown types.
    /// - Throws: Wire errors, duplicate-type `malformedEncoding`, or `capacityExceeded`.
    public static func decodeList(_ reader: inout MLSReader) throws -> [Self] {
        var body = try MLSReader(reader.readVector())
        var result: [Self] = []; var seen: Set<UInt16> = []
        while !body.isAtEnd {
            guard result.count < 128 else { throw MLSError.capacityExceeded }
            let item = try decode(&body)
            guard seen.insert(item.type).inserted else { throw MLSError.malformedEncoding }
            result.append(item)
        }
        return result
    }
}

/// Public MLS 1.0 ciphersuite-2 epoch state, signed through GroupInfo/commit framing.
public struct MLSGroupContext: Sendable, Equatable {
    public let groupID: Data
    public let epoch: UInt64
    public let treeHash: Data
    public let confirmedTranscriptHash: Data
    public let extensions: [MLSExtension]

    /// Creates context for a bounded group with explicit RFC 9420 version/suite.
    /// - Parameters:
    ///   - groupID: Nonempty application group identifier, up to 255 bytes.
    ///   - epoch: Unsigned epoch, with no wall-clock interpretation.
    ///   - treeHash: Thirty-two-byte SHA-256 ratchet-tree root hash.
    ///   - confirmedTranscriptHash: A thirty-two-byte hash, or empty for epoch zero
    ///     and provisional next-epoch contexts before their transcript is calculated.
    ///   - extensions: Unique context extensions; unknown types remain preserved.
    /// - Throws: `invalidConfiguration` for invalid identifiers/hash sizes or
    ///   extension wire/capacity errors. This does not authenticate the context.
    public init(groupID: Data, epoch: UInt64, treeHash: Data, confirmedTranscriptHash: Data,
                extensions: [MLSExtension] = []) throws {
        guard !groupID.isEmpty, groupID.count <= 255, treeHash.count == 32,
              confirmedTranscriptHash.count == 32 || confirmedTranscriptHash.isEmpty else {
            throw MLSError.invalidConfiguration
        }
        _ = try MLSExtension.encodeList(extensions)
        self.groupID = groupID; self.epoch = epoch; self.treeHash = treeHash
        self.confirmedTranscriptHash = confirmedTranscriptHash; self.extensions = extensions
    }

    /// Encodes the RFC 9420 GroupContext using version 1 and ciphersuite 2.
    /// - Returns: Context bytes suitable for signatures and KDF context inputs.
    /// - Throws: Wire capacity errors from aggregate extension data.
    public func encoded() throws -> Data {
        var writer = MLSWriter(); writer.write(UInt16(1)); writer.write(UInt16(2))
        try writer.writeVector(groupID); writer.write(epoch); try writer.writeVector(treeHash)
        try writer.writeVector(confirmedTranscriptHash); try writer.writeRaw(MLSExtension.encodeList(extensions))
        return writer.data
    }

    /// Decodes a complete context, rejecting unsupported versions/suites and suffixes.
    /// - Parameter data: One complete bounded RFC 9420 GroupContext.
    /// - Returns: Structurally validated context; authentication remains the caller's duty.
    /// - Throws: Unsupported-version/suite, malformed-wire, capacity, or field errors.
    public static func decode(_ data: Data) throws -> Self {
        var reader = try MLSReader(data); let result = try decode(&reader); try reader.requireEnd(); return result
    }

    /// Decodes a context embedded in another MLS object.
    /// - Parameter reader: Enclosing cursor advanced past the context.
    /// - Returns: Structurally validated, unauthenticated context.
    /// - Throws: Unsupported-version/suite, wire, capacity, or field errors.
    public static func decode(_ reader: inout MLSReader) throws -> Self {
        guard try reader.readUInt16() == 1 else { throw MLSError.unsupportedVersion }
        guard try reader.readUInt16() == 2 else { throw MLSError.unsupportedCipherSuite }
        return try Self(groupID: reader.readVector(), epoch: reader.readUInt64(), treeHash: reader.readVector(),
                        confirmedTranscriptHash: reader.readVector(), extensions: MLSExtension.decodeList(&reader))
    }
}
