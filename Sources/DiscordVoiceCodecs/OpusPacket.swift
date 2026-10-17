import Foundation
import DiscordMedia

/// Structural validation failures for one ordinary, non-self-delimiting Opus packet.
public enum OpusPacketError: Error, Sendable, Equatable {
    case packetTooLarge
    case missingTOC
    case truncatedHeader
    case invalidFrameCount
    case excessiveDuration
    case invalidPadding
    case invalidFrameLength
    case unequalCBRFrames
}

/// Opus coding mode declared by the five-bit TOC configuration.
public enum OpusMode: Sendable, Equatable {
    case silk
    case hybrid
    case celt
}

/// Nominal audio bandwidth declared by the Opus TOC; independent of output sample rate.
public enum OpusBandwidth: Sendable, Equatable {
    case narrowband
    case mediumband
    case wideband
    case superwideband
    case fullband
}

/// An owned, structurally validated RFC 6716 section 3 Opus packet and its frame boundaries.
///
/// All four packing codes, VBR lengths, zero-byte DTX/loss frames and optional padding are
/// supported. This parser does not decode SILK/CELT entropy data, validate compressed audio,
/// perform PLC/FEC, or establish encoder/decoder conformance. It handles one ordinary packet,
/// not Ogg framing, multistream concatenation or Appendix B self-delimiting framing.
///
/// Parsing has a local 65,536-byte policy cap (including padding), at most 48 frame ranges,
/// and no tasks, dependencies on a native Opus binary, or global state. RFC 8251 section 4's
/// padding-overflow correction is applied by decrementing a checked remaining-data boundary.
/// See https://www.rfc-editor.org/rfc/rfc6716#section-3 and
/// https://www.rfc-editor.org/rfc/rfc8251#section-4 (verified 2026-10-17).
public struct OpusPacket: Sendable, Equatable {
    public let data: Data
    public let configuration: Int
    public let packingCode: Int
    public let mode: OpusMode
    public let bandwidth: OpusBandwidth
    public let channelCount: Int
    public let frameSampleCount: Int
    /// Total decoded samples per channel on the mandatory 48kHz Opus/RTP clock, at most 5,760.
    public let sampleCount: Int
    public let duration: MediaTime
    /// Zero-based byte offsets in `data`; ranges exclude headers and trailing Opus padding.
    public let frameRanges: [Range<Int>]
    /// Number of trailing padding bytes, excluding bytes that encode the padding length.
    public let paddingByteCount: Int

    /// Parses and bounds an ordinary Opus packet, retaining canonical zero-based data indices.
    /// - Parameter data: Packet beginning with its TOC, including any Opus padding. Empty
    ///   input and packets above the local 65,536-byte admission bound are rejected before
    ///   copying. Arbitrary values in trailing padding are accepted as required for decoders.
    /// - Throws: `OpusPacketError.packetTooLarge`, `missingTOC`, `truncatedHeader`,
    ///   `invalidFrameCount`, `excessiveDuration`, `invalidPadding`, `invalidFrameLength`,
    ///   or `unequalCBRFrames` according to the violated framing invariant. Every frame is
    ///   bounded to 1,275 compressed bytes and total duration to 120ms. Zero-byte frames are
    ///   valid. Errors retain no packet and require the caller to discard malformed input.
    public init(_ data: Data) throws {
        guard data.count <= 65_536 else { throw OpusPacketError.packetTooLarge }
        guard !data.isEmpty else { throw OpusPacketError.missingTOC }
        let bytes = [UInt8](data)
        let toc = bytes[0]
        let config = Int(toc >> 3)
        let code = Int(toc & 3)
        let frameSamples: Int
        let declaredMode: OpusMode
        let declaredBandwidth: OpusBandwidth
        switch config {
        case 0...11:
            declaredMode = .silk
            declaredBandwidth = [.narrowband, .mediumband, .wideband][config / 4]
            frameSamples = [480, 960, 1_920, 2_880][config % 4]
        case 12...15:
            declaredMode = .hybrid
            declaredBandwidth = config < 14 ? .superwideband : .fullband
            frameSamples = [480, 960][config % 2]
        default:
            declaredMode = .celt
            declaredBandwidth = [.narrowband, .wideband, .superwideband, .fullband][(config - 16) / 4]
            frameSamples = [120, 240, 480, 960][config % 4]
        }
        var offset = 1
        var end = bytes.count
        var padding = 0
        var lengths: [Int]
        switch code {
        case 0:
            lengths = [end - offset]
        case 1:
            guard (end - offset).isMultiple(of: 2) else { throw OpusPacketError.unequalCBRFrames }
            lengths = Array(repeating: (end - offset) / 2, count: 2)
        case 2:
            let first = try Self.readLength(bytes, offset: &offset, end: end)
            guard first <= end - offset else { throw OpusPacketError.invalidFrameLength }
            lengths = [first, end - offset - first]
        default:
            guard offset < end else { throw OpusPacketError.truncatedHeader }
            let header = bytes[offset]
            offset += 1
            let count = Int(header & 0x3f)
            guard count > 0 else { throw OpusPacketError.invalidFrameCount }
            guard count * frameSamples <= 5_760 else { throw OpusPacketError.excessiveDuration }
            if header & 0x40 != 0 {
                var value: UInt8
                repeat {
                    guard offset < end else { throw OpusPacketError.invalidPadding }
                    value = bytes[offset]
                    offset += 1
                    let amount = value == 255 ? 254 : Int(value)
                    guard amount <= end - offset else { throw OpusPacketError.invalidPadding }
                    end -= amount
                    padding += amount
                } while value == 255
            }
            if header & 0x80 == 0 {
                guard (end - offset).isMultiple(of: count) else { throw OpusPacketError.unequalCBRFrames }
                lengths = Array(repeating: (end - offset) / count, count: count)
            } else {
                lengths = []
                lengths.reserveCapacity(count)
                var used = 0
                for _ in 0..<(count - 1) {
                    let length = try Self.readLength(bytes, offset: &offset, end: end)
                    used += length
                    guard used <= end - offset else { throw OpusPacketError.invalidFrameLength }
                    lengths.append(length)
                }
                lengths.append(end - offset - used)
            }
        }
        guard lengths.allSatisfy({ (0...1_275).contains($0) }) else {
            throw OpusPacketError.invalidFrameLength
        }
        let totalSamples = lengths.count * frameSamples
        guard totalSamples <= 5_760 else { throw OpusPacketError.excessiveDuration }
        var ranges: [Range<Int>] = []
        ranges.reserveCapacity(lengths.count)
        for length in lengths {
            ranges.append(offset..<(offset + length))
            offset += length
        }
        self.data = Data(bytes)
        self.configuration = config
        self.packingCode = code
        self.mode = declaredMode
        self.bandwidth = declaredBandwidth
        self.channelCount = toc & 4 == 0 ? 1 : 2
        self.frameSampleCount = frameSamples
        self.sampleCount = totalSamples
        self.duration = try MediaTime(value: Int64(totalSamples), timescale: 48_000)
        self.frameRanges = ranges
        self.paddingByteCount = padding
    }

    /// Reads one RFC 6716 section 3.2.1 length using the current unpadded byte boundary.
    /// - Parameters:
    ///   - bytes: Already bounded canonical packet bytes.
    ///   - offset: Header cursor, advanced by one or two bytes only as those bytes are read.
    ///   - end: Exclusive unpadded packet boundary; trailing padding cannot supply a length byte.
    /// - Returns: Compressed frame length in `0...1275`, including zero-byte DTX frames.
    /// - Throws: `OpusPacketError.truncatedHeader` if a required length byte is unavailable.
    ///   The caller discards its local cursor after a failure; no public state is mutated.
    private static func readLength(_ bytes: [UInt8], offset: inout Int, end: Int) throws -> Int {
        guard offset < end else { throw OpusPacketError.truncatedHeader }
        let first = Int(bytes[offset])
        offset += 1
        if first < 252 { return first }
        guard offset < end else { throw OpusPacketError.truncatedHeader }
        let length = first + Int(bytes[offset]) * 4
        offset += 1
        return length
    }
}
