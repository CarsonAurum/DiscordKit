import Foundation

/// Encoded media formats whose packetizer-visible prefixes DAVE v1 understands.
///
/// This identifies a complete encoded frame before RTP packetization. It does not
/// identify an RTP payload descriptor or select an encoder/decoder implementation.
public enum DAVECodec: String, CaseIterable, Sendable {
    case opus, vp8, vp9, h264, h265, av1
}

/// A contiguous, authenticated but unencrypted section of a normalized frame.
public struct DAVEClearRange: Equatable, Hashable, Sendable {
    public let offset: Int
    public let length: Int

    /// Creates an integer-safe nonempty range; frame-relative bounds are checked separately.
    /// - Parameters:
    ///   - offset: Zero-based byte position, greater than or equal to zero.
    ///   - length: Positive byte count that must not overflow when added to `offset`.
    /// - Throws: `DAVEError.malformedFrame` for negative, empty, or overflowing ranges.
    public init(offset: Int, length: Int) throws {
        guard offset >= 0, length > 0, offset <= Int.max - length else {
            throw DAVEError.malformedFrame
        }
        self.offset = offset
        self.length = length
    }
}

/// Canonical encoded bytes and the clear sections authenticated by the media cipher.
///
/// The complement of `clearRanges` is encrypted. H26x start-code normalization and
/// AV1 filtering mean `bytes` can differ from the original encoded frame. Receivers
/// recover these normalized bytes without needing to identify or parse the codec.
public struct DAVEPreparedFrame: Equatable, Sendable {
    public let bytes: Data
    public let clearRanges: [DAVEClearRange]

    /// Creates a frame with already determined packetizer-visible sections.
    /// - Parameters:
    ///   - bytes: Nonempty normalized frame. Its collection indices are normalized to zero.
    ///   - clearRanges: Ranges in ascending order, without overlap and contained in `bytes`.
    ///     Adjacent ranges are accepted; codec preparation normally coalesces them.
    /// - Throws: `DAVEError.malformedFrame` for an empty frame or invalid range ordering/bounds.
    /// - Complexity: O(number of ranges), plus a copy when needed to normalize a data slice.
    public init(bytes: Data, clearRanges: [DAVEClearRange]) throws {
        guard !bytes.isEmpty else { throw DAVEError.malformedFrame }
        var previousEnd = 0
        for range in clearRanges {
            guard range.offset >= previousEnd, range.offset <= bytes.count,
                  range.length <= bytes.count - range.offset else {
                throw DAVEError.malformedFrame
            }
            previousEnd = range.offset + range.length
        }
        self.bytes = Data(bytes)
        self.clearRanges = clearRanges
    }
}

/// Pure, bounded DAVE v1 codec transformations over complete encoded frames.
///
/// The packetizer profile follows Discord's published `libdave` codec behavior:
/// Opus/VP9 are fully encrypted; VP8 retains its 1/10-byte prefix; Annex B H264/H265
/// retain packetizer-visible NAL data; AV1 retains OBU headers and rewrites sizes.
/// This is not a bitstream decoder or a claim of encoder, RTP, or device qualification.
public enum DAVECodecTransform {
    /// Normalizes a frame and identifies every section that must remain clear.
    ///
    /// H264/H265 require Annex B framing, and all start codes become four bytes.
    /// H264 slice prefixes cover the first three unsigned Exp-Golomb values,
    /// rounded up to include the final byte. H265 VCL payload is encrypted.
    /// H264 partitioned/auxiliary/extension slices and reserved or RTP-aggregation
    /// NAL types are rejected because this packetizer profile cannot safely classify
    /// their media prefixes. They are never mistaken for wholly clear metadata.
    /// AV1 temporal delimiters, tile lists, and padding are discarded. Retained
    /// sizes use minimal LEB128 and the final retained OBU omits its size field so
    /// that the protocol trailer can survive packetization.
    ///
    /// No state, tasks, I/O, or cryptographic operations are created. Malformed
    /// framing is rejected before a partial prepared frame can escape. Validating
    /// codec syntax beyond the required packetizer prefixes remains the decoder's job.
    /// - Parameters:
    ///   - frame: One complete, nonempty encoded frame, never an RTP packet.
    ///   - codec: Explicit codec used by the encoder and downstream packetizer.
    ///   - maximumFrameBytes: Inclusive input and normalized-output limit, default 16 MiB;
    ///     valid values are 1 through 64 MiB. Canonicalization can increase output size.
    ///   - maximumClearRanges: Maximum disjoint clear sections, default 64; valid values
    ///     are 1 through 4,096. The wire trailer can impose a smaller effective limit.
    /// - Returns: Normalized bytes and ordered, coalesced, nonoverlapping clear ranges.
    /// - Throws: `DAVEError.invalidConfiguration` for invalid limits,
    ///   `DAVEError.frameTooLarge` for byte/range limits, or `DAVEError.malformedFrame`
    ///   for empty, truncated, unsupported, or structurally invalid packetizer framing.
    /// - Complexity: O(frame bytes), with allocations bounded by the configured limits.
    public static func prepare(
        _ frame: Data, codec: DAVECodec, maximumFrameBytes: Int = 16_777_216,
        maximumClearRanges: Int = 64
    ) throws -> DAVEPreparedFrame {
        guard (1...67_108_864).contains(maximumFrameBytes),
              (1...4_096).contains(maximumClearRanges) else { throw DAVEError.invalidConfiguration }
        guard frame.count <= maximumFrameBytes else { throw DAVEError.frameTooLarge }
        guard !frame.isEmpty else { throw DAVEError.malformedFrame }
        let input = Array(frame)
        var builder = DAVEFrameBuilder(maximumBytes: maximumFrameBytes, maximumRanges: maximumClearRanges)
        switch codec {
        case .opus, .vp9:
            try builder.append(input[...], clear: false)
        case .vp8:
            let headerLength = input[0] & 1 == 0 ? 10 : 1
            guard input.count >= headerLength else { throw DAVEError.malformedFrame }
            try builder.append(input[..<headerLength], clear: true)
            try builder.append(input[headerLength...], clear: false)
        case .h264, .h265:
            try prepareAnnexB(input, codec: codec, builder: &builder)
        case .av1:
            try prepareAV1(input, builder: &builder)
        }
        return try DAVEPreparedFrame(bytes: Data(builder.bytes), clearRanges: builder.ranges)
    }

    /// Detects a packetizer-confusing H26x start code touching encrypted bytes.
    ///
    /// Call this after assembling the entire encrypted frame, including its trailer.
    /// An accidental `00 00 01` can straddle an encrypted/clear boundary, so scanning
    /// only ciphertext would be insufficient. Start codes wholly inside a clear
    /// section are intentional and accepted. The caller must reserve a fresh nonce
    /// and retry encryption when this returns `true`; retries must have a fixed limit.
    /// - Parameters:
    ///   - frame: Entire encrypted wire frame, including clear codec sections and trailer.
    ///   - clearRanges: Ordered, nonoverlapping clear sections within `frame`.
    ///   - codec: H264/H265 enable the check; other codecs always return `false` after validation.
    /// - Returns: Whether a three-byte start-code sequence touches any encrypted/trailer byte.
    /// - Throws: `DAVEError.malformedFrame` for invalid range bounds or ordering.
    /// - Complexity: O(frame bytes + clear ranges), with no frame-sized allocation.
    public static func containsUnexpectedStartCode(
        in frame: Data, clearRanges: [DAVEClearRange], codec: DAVECodec
    ) throws -> Bool {
        var previousEnd = 0
        for range in clearRanges {
            guard range.offset >= previousEnd, range.offset <= frame.count,
                  range.length <= frame.count - range.offset else { throw DAVEError.malformedFrame }
            previousEnd = range.offset + range.length
        }
        guard codec == .h264 || codec == .h265, frame.count >= 3 else { return false }
        var rangeIndex = 0
        let base = frame.startIndex
        for index in 0...(frame.count - 3) {
            guard frame[base + index] == 0, frame[base + index + 1] == 0,
                  frame[base + index + 2] == 1 else { continue }
            while rangeIndex < clearRanges.count,
                  clearRanges[rangeIndex].offset + clearRanges[rangeIndex].length <= index {
                rangeIndex += 1
            }
            guard rangeIndex < clearRanges.count else { return true }
            let range = clearRanges[rangeIndex]
            if range.offset > index { return true }
            var clearEnd = range.offset + range.length
            var adjacentIndex = rangeIndex + 1
            while clearEnd < index + 3, adjacentIndex < clearRanges.count,
                  clearRanges[adjacentIndex].offset == clearEnd {
                clearEnd += clearRanges[adjacentIndex].length
                adjacentIndex += 1
            }
            if clearEnd < index + 3 { return true }
        }
        return false
    }

    /// Parses Annex B NAL boundaries and emits the packetizer profile's canonical clear prefixes.
    /// - Parameters:
    ///   - input: Nonempty, bounded encoded bytes.
    ///   - codec: H264 or H265 selected by the public dispatcher.
    ///   - builder: Exclusive output accumulator; no partial result is returned after failure.
    /// - Throws: `DAVEError.malformedFrame` for missing/empty NALs, invalid NAL headers,
    ///   or truncated H264 slice fields; builder errors enforce output byte/range limits.
    private static func prepareAnnexB(
        _ input: [UInt8], codec: DAVECodec, builder: inout DAVEFrameBuilder
    ) throws {
        guard var current = nextStartCode(input, from: 0),
              input[..<current.offset].allSatisfy({ $0 == 0 }) else { throw DAVEError.malformedFrame }
        let headerLength = codec == .h264 ? 1 : 2
        while true {
            let nalStart = current.offset + current.length
            let next = nextStartCode(input, from: nalStart)
            let nalEnd = next?.offset ?? input.count
            guard nalEnd - nalStart >= headerLength, input[nalStart] & 0x80 == 0 else {
                throw DAVEError.malformedFrame
            }
            let clearLength: Int
            if codec == .h264 {
                let type = input[nalStart] & 0x1F
                if type == 1 || type == 5 {
                    clearLength = headerLength + (try h264SlicePrefix(input, start: nalStart + 1, end: nalEnd))
                } else if (6...16).contains(type) {
                    clearLength = nalEnd - nalStart
                } else {
                    throw DAVEError.malformedFrame
                }
            } else {
                guard input[nalStart + 1] & 7 != 0 else { throw DAVEError.malformedFrame }
                clearLength = ((input[nalStart] & 0x7E) >> 1) < 32 ? headerLength : nalEnd - nalStart
            }
            try builder.append([UInt8(0), 0, 0, 1][...], clear: true)
            try builder.append(input[nalStart..<(nalStart + clearLength)], clear: true)
            try builder.append(input[(nalStart + clearLength)..<nalEnd], clear: false)
            guard let next else { break }
            current = next
        }
    }

    /// Finds the next complete short/long Annex B marker, preferring the long form.
    /// - Parameters:
    ///   - bytes: Whole frame, indexed from zero.
    ///   - from: Nonnegative first position to examine, at most the frame length.
    /// - Returns: Start and byte length of the marker, or `nil` when none remains.
    private static func nextStartCode(_ bytes: [UInt8], from: Int) -> (offset: Int, length: Int)? {
        guard from <= bytes.count, bytes.count - from >= 3 else { return nil }
        var index = from
        while index <= bytes.count - 3 {
            if bytes[index] == 0, bytes[index + 1] == 0 {
                if bytes[index + 2] == 1 { return (index, 3) }
                if bytes.count - index >= 4, bytes[index + 2] == 0, bytes[index + 3] == 1 {
                    return (index, 4)
                }
            }
            index += 1
        }
        return nil
    }

    /// Locates the H264 slice PPS identifier without decoding or retaining media payload.
    ///
    /// Emulation-prevention bytes are skipped while reading both Exp-Golomb prefix
    /// and suffix bits. Each value is limited to 31 leading zero bits. Parsing never
    /// crosses the current NAL boundary, even when a later NAL contains a valid prefix.
    /// - Parameters:
    ///   - input: Complete original Annex B frame.
    ///   - start: First slice payload byte, immediately after its one-byte NAL header.
    ///   - end: Exclusive NAL boundary.
    /// - Returns: Number of original payload bytes to authenticate without encryption.
    /// - Throws: `DAVEError.malformedFrame` for missing fields, oversized fields, or invalid
    ///   emulation prevention inside the required prefix.
    private static func h264SlicePrefix(_ input: [UInt8], start: Int, end: Int) throws -> Int {
        var cursor = DAVEH264BitCursor(bytes: input, start: start, end: end)
        for _ in 0..<3 {
            var leadingZeros = 0
            while try cursor.readBit() == 0 {
                leadingZeros += 1
                guard leadingZeros < 32 else { throw DAVEError.malformedFrame }
            }
            for _ in 0..<leadingZeros { _ = try cursor.readBit() }
        }
        let count = cursor.byteIndex - start + 1
        guard count <= end - start else { throw DAVEError.malformedFrame }
        return count
    }

    /// Parses AV1 low-overhead OBUs and emits only packetizer-retained units.
    /// - Parameters:
    ///   - input: Complete encoded frame, with optional OBU extension/size fields.
    ///   - builder: Exclusive bounded output accumulator.
    /// - Throws: `DAVEError.malformedFrame` for invalid headers, extension bits, sizes,
    ///   truncated payloads, or frames containing only discarded OBU types; builder
    ///   errors enforce byte/range budgets.
    private static func prepareAV1(_ input: [UInt8], builder: inout DAVEFrameBuilder) throws {
        var index = 0
        var pending: DAVEAV1Unit?
        while index < input.count {
            let header = input[index]
            index += 1
            guard header & 0x81 == 0 else { throw DAVEError.malformedFrame }
            let extensionByte: UInt8?
            if header & 4 != 0 {
                guard index < input.count, input[index] & 7 == 0 else { throw DAVEError.malformedFrame }
                extensionByte = input[index]
                index += 1
            } else {
                extensionByte = nil
            }
            let payloadCount: Int
            if header & 2 != 0 {
                payloadCount = try readAV1Size(input, index: &index)
            } else {
                payloadCount = input.count - index
            }
            guard payloadCount <= input.count - index else { throw DAVEError.malformedFrame }
            let unit = DAVEAV1Unit(header: header, extensionByte: extensionByte, payload: index..<(index + payloadCount))
            index += payloadCount
            let type = (header & 0x78) >> 3
            if type != 2, type != 8, type != 15 {
                if let pending { try appendAV1(pending, input: input, last: false, builder: &builder) }
                pending = unit
            }
        }
        guard let pending else { throw DAVEError.malformedFrame }
        try appendAV1(pending, input: input, last: true, builder: &builder)
    }

    /// Decodes an AV1 unsigned size with the specification's eight-byte LEB128 bound.
    ///
    /// Accumulation uses UInt64 independently of the host word size. The decoded
    /// value must fit both native Int and the remaining frame before conversion,
    /// so malformed sizes cannot wrap negative or create an invalid range on
    /// 32-bit hosts such as arm64_32 watchOS. Up to 56 wire bits are examined.
    /// - Parameters:
    ///   - input: Whole frame.
    ///   - index: Cursor advanced after each consumed byte, including before a failure.
    /// - Returns: Nonnegative native byte count within the remaining input bounds.
    /// - Throws: `DAVEError.malformedFrame` for truncation, an overlong encoding,
    ///   a size outside native Int, or a payload size exceeding the remaining frame.
    private static func readAV1Size(_ input: [UInt8], index: inout Int) throws -> Int {
        var value: UInt64 = 0
        for shift in stride(from: 0, to: 56, by: 7) {
            guard index < input.count else { throw DAVEError.malformedFrame }
            let byte = input[index]
            index += 1
            value |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 {
                guard value <= UInt64(Int.max), value <= UInt64(input.count - index) else {
                    throw DAVEError.malformedFrame
                }
                return Int(value)
            }
        }
        throw DAVEError.malformedFrame
    }

    /// Appends an AV1 header, canonical size when needed, and encrypted payload.
    /// - Parameters:
    ///   - unit: Validated source-unit metadata without owned payload copies.
    ///   - input: Original frame backing the payload range.
    ///   - last: Whether this is the last retained unit, including after discarded padding.
    ///   - builder: Exclusive output accumulator.
    /// - Throws: Builder byte/range budget errors.
    private static func appendAV1(
        _ unit: DAVEAV1Unit, input: [UInt8], last: Bool, builder: inout DAVEFrameBuilder
    ) throws {
        let header = last ? unit.header & ~UInt8(2) : unit.header
        try builder.append([header][...], clear: true)
        if let extensionByte = unit.extensionByte { try builder.append([extensionByte][...], clear: true) }
        if !last, unit.header & 2 != 0 {
            var remaining = unit.payload.count
            repeat {
                var byte = UInt8(remaining & 0x7F)
                remaining >>= 7
                if remaining != 0 { byte |= 0x80 }
                try builder.append([byte][...], clear: true)
            } while remaining != 0
        }
        try builder.append(input[unit.payload], clear: false)
    }
}

/// Private bounded accumulator that coalesces adjacent authenticated clear sections.
private struct DAVEFrameBuilder {
    let maximumBytes: Int
    let maximumRanges: Int
    var bytes: [UInt8] = []
    var ranges: [DAVEClearRange] = []

    /// Appends a validated source slice while enforcing both independent allocation budgets.
    /// - Parameters:
    ///   - source: Contiguous source bytes; an empty slice has no effect.
    ///   - clear: Whether these bytes must remain unencrypted and become authenticated data.
    /// - Throws: `DAVEError.frameTooLarge` before exceeding byte/range limits.
    mutating func append(_ source: ArraySlice<UInt8>, clear: Bool) throws {
        guard !source.isEmpty else { return }
        guard source.count <= maximumBytes - bytes.count else { throw DAVEError.frameTooLarge }
        if clear {
            if let last = ranges.last, last.offset + last.length == bytes.count {
                ranges[ranges.count - 1] = try DAVEClearRange(offset: last.offset, length: last.length + source.count)
            } else {
                guard ranges.count < maximumRanges else { throw DAVEError.frameTooLarge }
                ranges.append(try DAVEClearRange(offset: bytes.count, length: source.count))
            }
        }
        bytes.append(contentsOf: source)
    }
}

/// Source locations of a parsed AV1 unit; payload remains in the bounded input array.
private struct DAVEAV1Unit {
    let header: UInt8
    let extensionByte: UInt8?
    let payload: Range<Int>
}

/// NAL-bounded H264 RBSP bit reader retaining original byte offsets for clear ranges.
private struct DAVEH264BitCursor {
    let bytes: [UInt8]
    let start: Int
    let end: Int
    var byteIndex: Int
    var bitOffset = 0

    /// Initializes a cursor without copying the frame's copy-on-write byte storage.
    /// - Parameters:
    ///   - bytes: Whole frame bytes.
    ///   - start: Inclusive slice payload start.
    ///   - end: Exclusive current NAL boundary; later NAL data is never read.
    init(bytes: [UInt8], start: Int, end: Int) {
        self.bytes = bytes
        self.start = start
        self.end = end
        self.byteIndex = start
    }

    /// Consumes one RBSP bit, skipping valid emulation-prevention bytes at byte boundaries.
    /// - Returns: Zero or one.
    /// - Throws: `DAVEError.malformedFrame` if the current field is truncated or an
    ///   encountered emulation-prevention byte lacks its required following byte.
    mutating func readBit() throws -> UInt8 {
        guard byteIndex < end else { throw DAVEError.malformedFrame }
        if bitOffset == 0, byteIndex - start >= 2, bytes[byteIndex] == 3,
           bytes[byteIndex - 1] == 0, bytes[byteIndex - 2] == 0 {
            guard byteIndex + 1 < end, bytes[byteIndex + 1] <= 3 else { throw DAVEError.malformedFrame }
            byteIndex += 1
        }
        let bit = (bytes[byteIndex] >> (7 - bitOffset)) & 1
        bitOffset += 1
        if bitOffset == 8 { byteIndex += 1; bitOffset = 0 }
        return bit
    }
}
