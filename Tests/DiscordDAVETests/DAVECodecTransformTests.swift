import Foundation
import Testing
@testable import DiscordDAVE

/// Offline codec fixtures verify normalized bytes and authenticated clear-range boundaries.
@Suite struct DAVECodecTransformTests {
    /// Covers range constructor overflow and prepared-frame ordering/bounds, including data slices.
    @Test func rangeAndPreparedFrameValidation() throws {
        for (offset, length) in [(-1, 1), (0, 0), (0, -1), (Int.max, 1), (1, Int.max)] {
            #expect(throws: DAVEError.malformedFrame) { try DAVEClearRange(offset: offset, length: length) }
        }
        let maximal = try DAVEClearRange(offset: Int.max - 1, length: 1)
        #expect(maximal.offset == Int.max - 1)
        #expect(maximal.length == 1)
        let first = try DAVEClearRange(offset: 0, length: 2)
        let adjacent = try DAVEClearRange(offset: 2, length: 1)
        let overlap = try DAVEClearRange(offset: 1, length: 1)
        let outside = try DAVEClearRange(offset: 3, length: 1)
        let bytes = Data([77, 1, 2, 3]).dropFirst()
        let prepared = try DAVEPreparedFrame(bytes: bytes, clearRanges: [first, adjacent])
        #expect(prepared.bytes == Data([1, 2, 3]))
        #expect(prepared.bytes.startIndex == 0)
        #expect(prepared.clearRanges == [first, adjacent])
        #expect(Set([first, first, adjacent]).count == 2)
        #expect(throws: DAVEError.malformedFrame) { try DAVEPreparedFrame(bytes: Data(), clearRanges: []) }
        for ranges in [[first, overlap], [adjacent, first], [outside], [maximal]] {
            #expect(throws: DAVEError.malformedFrame) { try DAVEPreparedFrame(bytes: bytes, clearRanges: ranges) }
        }
    }

    /// Exercises all dispatcher cases, nonzero-based inputs, byte limits, and invalid configuration.
    /// - Parameter codec: Each supported encoded codec, including formats whose empty header is invalid.
    @Test(arguments: DAVECodec.allCases)
    func commonBounds(codec: DAVECodec) throws {
        #expect(DAVECodec(rawValue: codec.rawValue) == codec)
        #expect(throws: DAVEError.malformedFrame) { try DAVECodecTransform.prepare(Data(), codec: codec) }
        #expect(throws: DAVEError.frameTooLarge) {
            try DAVECodecTransform.prepare(Data([1, 2]), codec: codec, maximumFrameBytes: 1)
        }
        for maximum in [-1, 0, 67_108_865, Int.max] {
            #expect(throws: DAVEError.invalidConfiguration) {
                try DAVECodecTransform.prepare(Data([1]), codec: codec, maximumFrameBytes: maximum)
            }
        }
        for maximum in [-1, 0, 4_097, Int.max] {
            #expect(throws: DAVEError.invalidConfiguration) {
                try DAVECodecTransform.prepare(Data([1]), codec: codec, maximumClearRanges: maximum)
            }
        }
    }

    /// Confirms Opus and VP9 expose no clear media bytes, including binary/marker-like payload.
    /// - Parameter codec: Both fully encrypted codecs.
    @Test(arguments: [DAVECodec.opus, .vp9])
    func fullEncryption(codec: DAVECodec) throws {
        let input = Data([99, 0, 0, 1, 0xFF, 0xFA, 0xFA]).dropFirst()
        let result = try DAVECodecTransform.prepare(input, codec: codec, maximumFrameBytes: input.count)
        #expect(result.bytes == input)
        #expect(result.bytes.startIndex == 0)
        #expect(result.clearRanges.isEmpty)
        #expect(try DAVECodecTransform.prepare(Data([0]), codec: codec, maximumFrameBytes: 1).bytes == Data([0]))
    }

    /// Verifies VP8's inverse key-frame flag and exact 1/10-byte clear boundaries.
    @Test func vp8HeaderBoundaries() throws {
        for flag in [UInt8(1), 3, 127, 255] {
            let input = Data([flag, 9, 8, 7])
            let result = try DAVECodecTransform.prepare(input, codec: .vp8)
            #expect(result.bytes == input)
            #expect(result.clearRanges == [try DAVEClearRange(offset: 0, length: 1)])
            #expect(try DAVECodecTransform.prepare(Data([flag]), codec: .vp8).clearRanges == result.clearRanges)
        }
        for count in 1..<10 {
            #expect(throws: DAVEError.malformedFrame) { try DAVECodecTransform.prepare(Data(count: count), codec: .vp8) }
        }
        for flag in [UInt8(0), 2, 126, 254] {
            let input = Data([flag] + Array(repeating: 9, count: 15))
            let result = try DAVECodecTransform.prepare(input, codec: .vp8)
            #expect(result.bytes == input)
            #expect(result.clearRanges == [try DAVEClearRange(offset: 0, length: 10)])
        }
        #expect(try DAVECodecTransform.prepare(Data(count: 10), codec: .vp8).clearRanges.first?.length == 10)
    }

    /// Checks mixed short/long H264 markers, non-VCL retention, and both slice NAL types.
    @Test func h264CanonicalNALs() throws {
        let input = Data([0, 0, 1, 0x67, 0x64, 0xAA, 0, 0, 0, 1, 0x65, 0xE0, 0x99,
                          0, 0, 1, 0x61, 0xE0, 0x88, 0x77])
        let expected = Data([0, 0, 0, 1, 0x67, 0x64, 0xAA, 0, 0, 0, 1, 0x65, 0xE0, 0x99,
                             0, 0, 0, 1, 0x61, 0xE0, 0x88, 0x77])
        let result = try DAVECodecTransform.prepare(input, codec: .h264)
        #expect(result.bytes == expected)
        #expect(result.clearRanges == [try DAVEClearRange(offset: 0, length: 13),
                                       try DAVEClearRange(offset: 14, length: 6)])
        #expect(throws: DAVEError.frameTooLarge) {
            try DAVECodecTransform.prepare(input, codec: .h264, maximumFrameBytes: input.count)
        }
        #expect(throws: DAVEError.frameTooLarge) {
            try DAVECodecTransform.prepare(input, codec: .h264, maximumClearRanges: 1)
        }
        let leadingZero = try DAVECodecTransform.prepare(Data([0, 0, 0]) + input, codec: .h264)
        #expect(leadingZero == result)
    }

    /// Independently builds slice Exp-Golomb fields across byte boundaries and RBSP escapes.
    /// Clear ranges cover the final field byte; parser limits do not expose later media.
    @Test func h264ExpGolombBoundariesAndEscapes() throws {
        for values: [UInt32] in [[0, 0, 0], [0, 0, 31], [1, 2, 3], [255, 65_535, 7], [16_777_215, 0, 0]] {
            let fixture = encodedSlice(values)
            let input = Data([0, 0, 1, 0x65] + fixture.bytes)
            let prepared = try DAVECodecTransform.prepare(input, codec: .h264)
            #expect(prepared.bytes == Data([0, 0, 0, 1, 0x65] + fixture.bytes))
            #expect(prepared.clearRanges == [try DAVEClearRange(offset: 0, length: 5 + fixture.coveredBytes)])
            #expect(prepared.bytes.count > 5 + fixture.coveredBytes)
        }
        let escaped = encodedSlice([16_777_215, 0, 0])
        #expect(escaped.bytes.contains(3))
        let byteBoundary = encodedSlice([0, 0, 31])
        #expect(byteBoundary.coveredBytes == 2)
        let oversized = Data([0, 0, 1, 0x65] + Array(repeating: UInt8(0), count: 5) + [0x80, 0xE0])
        #expect(throws: DAVEError.malformedFrame) { try DAVECodecTransform.prepare(oversized, codec: .h264) }
    }

    /// Rejects malformed Annex B, invalid NAL headers, and slice parsing that would cross a NAL.
    /// - Parameter codec: Both Annex B profiles.
    @Test(arguments: [DAVECodec.h264, .h265])
    func annexBMalformed(codec: DAVECodec) throws {
        let shared: [[UInt8]] = [[0], [0, 0, 1], [1, 2, 3, 4], [9, 0, 0, 1, 0x67, 1],
                                 [0, 0, 1, 0xFF, 1], [0, 0, 1, 0, 0, 1, 0x67, 1]]
        for input in shared {
            #expect(throws: DAVEError.malformedFrame) { try DAVECodecTransform.prepare(Data(input), codec: codec) }
        }
        if codec == .h264 {
            for type: UInt8 in [0, 2, 3, 4, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31] {
                #expect(throws: DAVEError.malformedFrame) {
                    try DAVECodecTransform.prepare(Data([0, 0, 1, type, 0xE0, 0x99]), codec: codec)
                }
            }
            for input: [UInt8] in [[0, 0, 1, 0], [0, 0, 1, 0x65], [0, 0, 1, 0x65, 0],
                                   [0, 0, 1, 0x65, 0, 0, 1, 0x67, 0xFF],
                                   [0, 0, 1, 0x65, 0, 0, 3], [0, 0, 1, 0x65, 0, 0, 3, 4]] {
                #expect(throws: DAVEError.malformedFrame) { try DAVECodecTransform.prepare(Data(input), codec: codec) }
            }
        } else {
            for input: [UInt8] in [[0, 0, 1, 0x02], [0, 0, 1, 0x02, 0], [0, 0, 1, 0x80, 1]] {
                #expect(throws: DAVEError.malformedFrame) { try DAVECodecTransform.prepare(Data(input), codec: codec) }
            }
        }
    }

    /// Verifies H265's two-byte clear header, VCL cutoff at type 32, and clear-range coalescing.
    @Test func h265CanonicalNALs() throws {
        let input = Data([0, 0, 1, 0x40, 1, 0xAA, 0, 0, 1, 0x3E, 1, 0xBB,
                          0, 0, 0, 1, 0x02, 1, 0xCC])
        let result = try DAVECodecTransform.prepare(input, codec: .h265)
        #expect(result.bytes == Data([0, 0, 0, 1, 0x40, 1, 0xAA, 0, 0, 0, 1, 0x3E, 1, 0xBB,
                                     0, 0, 0, 1, 0x02, 1, 0xCC]))
        #expect(result.clearRanges == [try DAVEClearRange(offset: 0, length: 13),
                                       try DAVEClearRange(offset: 14, length: 6)])
        #expect(throws: DAVEError.frameTooLarge) {
            try DAVECodecTransform.prepare(input, codec: .h265, maximumFrameBytes: input.count)
        }
        let allClear = try DAVECodecTransform.prepare(Data([0, 0, 1, 0x40, 1]), codec: .h265)
        #expect(allClear.clearRanges == [try DAVEClearRange(offset: 0, length: 6)])
    }

    /// Covers AV1 filtering, minimal size rewrites, extensions, and final retained OBU normalization.
    @Test func av1Normalization() throws {
        let input = Data([0x12, 0, 0x0E, 0x28, 0x82, 0, 0xA1, 0xA2,
                          0x42, 1, 0xBB, 0x32, 0x81, 0, 0xC1, 0x7A, 2, 0xCC, 0xDD])
        let result = try DAVECodecTransform.prepare(input, codec: .av1)
        #expect(result.bytes == Data([0x0E, 0x28, 2, 0xA1, 0xA2, 0x30, 0xC1]))
        #expect(result.clearRanges == [try DAVEClearRange(offset: 0, length: 3),
                                       try DAVEClearRange(offset: 5, length: 1)])
        #expect(throws: DAVEError.frameTooLarge) {
            try DAVECodecTransform.prepare(input, codec: .av1, maximumClearRanges: 1)
        }
        let unsized = Data([0x34, 0x20, 0xAA, 0xBB])
        #expect(try DAVECodecTransform.prepare(unsized, codec: .av1).bytes == unsized)
        #expect(try DAVECodecTransform.prepare(unsized, codec: .av1).clearRanges == [try DAVEClearRange(offset: 0, length: 2)])
        #expect(try DAVECodecTransform.prepare(Data([0x32, 0]), codec: .av1).bytes == Data([0x30]))
    }

    /// Checks multi-byte AV1 sizes and normalization of an eight-byte padded legal size.
    @Test func av1SizeBoundaries() throws {
        let payload = Array(repeating: UInt8(0xA5), count: 128)
        let input = Data([0x32, 0x80, 1] + payload + [0x32, 1, 0xBB])
        let result = try DAVECodecTransform.prepare(input, codec: .av1)
        #expect(result.bytes == Data([0x32, 0x80, 1] + payload + [0x30, 0xBB]))
        #expect(result.clearRanges == [try DAVEClearRange(offset: 0, length: 3),
                                       try DAVEClearRange(offset: 131, length: 1)])
        let padded = Data([0x32, 0x81, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0, 0xAA, 0x32, 1, 0xBB])
        #expect(try DAVECodecTransform.prepare(padded, codec: .av1).bytes == Data([0x32, 1, 0xAA, 0x30, 0xBB]))
    }

    /// Malformed AV1 fixture matrix covers forbidden/reserved bits, extension and LEB truncation,
    /// overflowing sizes, too many LEB bytes, and frames whose entire content is discarded.
    /// The 2^31/2^32/2^32+1 and 2^56 sizes guard native-word truncation on arm64_32;
    /// no oversized value may become a negative or wrapped-small payload range.
    @Test func av1Malformed() throws {
        let inputs: [[UInt8]] = [[0xB2, 1, 0], [0x33, 1, 0], [0x36], [0x36, 1, 0],
                                 [0x32], [0x32, 0x80], [0x32, 2, 0xAA],
                                 [0x32, 0x80, 0x80, 0x80, 0x80, 0x08],
                                 [0x32, 0x80, 0x80, 0x80, 0x80, 0x10],
                                 [0x32, 0x81, 0x80, 0x80, 0x80, 0x10, 0xAA],
                                 [0x32] + Array(repeating: 0x80, count: 8) + [1],
                                 [0x32] + Array(repeating: 0x80, count: 9) + [0],
                                 [0x32] + Array(repeating: 0xFF, count: 7) + [0x7F],
                                 [0x12, 0], [0x42, 0], [0x7A, 0]]
        for input in inputs {
            #expect(throws: DAVEError.malformedFrame) { try DAVECodecTransform.prepare(Data(input), codec: .av1) }
        }
    }

    /// Detects ciphertext start codes, both cross-boundary directions, trailer markers,
    /// and long codes; intentional markers and non-H26x payloads remain accepted.
    /// - Parameter codec: Both H26x packetizer profiles share this collision restriction.
    @Test(arguments: [DAVECodec.h264, .h265])
    func unexpectedCiphertextStartCodes(codec: DAVECodec) throws {
        let clear = try DAVEClearRange(offset: 0, length: 4)
        #expect(try !DAVECodecTransform.containsUnexpectedStartCode(in: Data([0, 0, 0, 1, 8, 8]), clearRanges: [clear], codec: codec))
        for frame: [UInt8] in [[0, 0, 1], [8, 0, 0, 1], [0, 0, 0, 1], [8, 8, 0, 0, 1]] {
            #expect(try DAVECodecTransform.containsUnexpectedStartCode(in: Data(frame), clearRanges: [], codec: codec))
        }
        #expect(try DAVECodecTransform.containsUnexpectedStartCode(in: Data([8, 0, 0, 1, 8]),
                                                                   clearRanges: [try DAVEClearRange(offset: 0, length: 3)], codec: codec))
        #expect(try DAVECodecTransform.containsUnexpectedStartCode(in: Data([8, 0, 0, 1, 8]),
                                                                   clearRanges: [try DAVEClearRange(offset: 2, length: 3)], codec: codec))
        #expect(try !DAVECodecTransform.containsUnexpectedStartCode(in: Data([8, 8]), clearRanges: [], codec: codec))
        #expect(try !DAVECodecTransform.containsUnexpectedStartCode(in: Data(), clearRanges: [], codec: codec))
        #expect(try !DAVECodecTransform.containsUnexpectedStartCode(in: Data([0, 0, 1]),
                                                                    clearRanges: [try DAVEClearRange(offset: 0, length: 1),
                                                                                  try DAVEClearRange(offset: 1, length: 2)], codec: codec))
        let sliced = Data([9, 0, 0, 1]).dropFirst()
        #expect(try DAVECodecTransform.containsUnexpectedStartCode(in: sliced, clearRanges: [], codec: codec))
        for other in [DAVECodec.opus, .vp8, .vp9, .av1] {
            #expect(try !DAVECodecTransform.containsUnexpectedStartCode(in: sliced, clearRanges: [], codec: other))
        }
        let late = try DAVEClearRange(offset: 4, length: 3)
        #expect(try !DAVECodecTransform.containsUnexpectedStartCode(in: Data([8, 8, 8, 8, 0, 0, 1]), clearRanges: [late], codec: codec))
        for ranges in [[try DAVEClearRange(offset: 6, length: 1)],
                       [clear, try DAVEClearRange(offset: 3, length: 1)]] {
            #expect(throws: DAVEError.malformedFrame) {
                try DAVECodecTransform.containsUnexpectedStartCode(in: Data([0, 0, 0, 1, 8]), clearRanges: ranges, codec: codec)
            }
        }
    }

    /// Integrates each real codec transform with media encryption and codec-unaware opening.
    ///
    /// Primitive/unit fixtures above assert the normalized bytes independently. This
    /// test checks their composition: clear codec bytes survive unchanged, footer
    /// ranges match, and the receiver reconstructs the complete normalized frame
    /// without being told its codec. The public exporter secret is a test fixture;
    /// repeated independent owners are never appropriate for a real transmit domain.
    /// - Parameter codec: Every implemented send-side codec, including AV1 with a filtered tail.
    @Test(arguments: DAVECodec.allCases)
    func codecMediaCipherComposition(codec: DAVECodec) async throws {
        let input: Data
        switch codec {
        case .opus: input = Data([0xF8, 0xAA, 0x55])
        case .vp8: input = Data([0] + Array(repeating: 0x99, count: 15))
        case .vp9: input = Data([0x12, 4, 5, 6])
        case .h264: input = Data([0, 0, 1, 0x67, 0x64, 0xAA, 0, 0, 1, 0x65, 0xE0, 0x99])
        case .h265: input = Data([0, 0, 1, 0x40, 1, 0xAA, 0, 0, 1, 0x02, 1, 0xBB])
        case .av1: input = Data([0x0E, 0x28, 0x82, 0, 0xA1, 0xA2, 0x32, 1, 0xC1, 0x7A, 1, 0xDD])
        }
        let prepared = try DAVECodecTransform.prepare(input, codec: codec)
        let sender = try DAVEFrameCipher(baseSecret: Data(0..<16))
        let receiver = try DAVEFrameCipher(baseSecret: Data(0..<16))
        let sealed = try await sender.seal(input, codec: codec)
        let envelope = try DAVEFrameEnvelope(frame: sealed)
        #expect(envelope.clearRanges == prepared.clearRanges)
        #expect(envelope.interleaved.count == prepared.bytes.count)
        for range in prepared.clearRanges {
            let indices = range.offset..<(range.offset + range.length)
            #expect(envelope.interleaved.subdata(in: indices) == prepared.bytes.subdata(in: indices))
        }
        #expect(try await receiver.open(sealed, mediaType: codec == .opus ? .audio : .video, now: 0) == prepared.bytes)
        #expect(try !DAVECodecTransform.containsUnexpectedStartCode(in: sealed, clearRanges: prepared.clearRanges, codec: codec))
        await sender.close(); await receiver.close()
    }

    /// Independently encodes three unsigned Exp-Golomb values with RBSP byte escaping.
    /// - Parameter values: Three values smaller than `UInt32.max`; all fixtures satisfy this.
    /// - Returns: Slice payload with extra media bytes, and upstream-profile clear-prefix length.
    private func encodedSlice(_ values: [UInt32]) -> (bytes: [UInt8], coveredBytes: Int) {
        var bits: [UInt8] = []
        for value in values {
            let binary = String(UInt64(value) + 1, radix: 2)
            bits += Array(repeating: UInt8(0), count: binary.count - 1)
            bits += binary.map { $0 == "1" ? UInt8(1) : UInt8(0) }
        }
        let fieldBits = bits.count
        while bits.count % 8 != 0 { bits.append(0) }
        var raw: [UInt8] = []
        for offset in stride(from: 0, to: bits.count, by: 8) {
            var byte: UInt8 = 0
            for bit in bits[offset..<(offset + 8)] { byte = (byte << 1) | bit }
            raw.append(byte)
        }
        raw += [0x5A, 0x99, 0x88]
        let rawCovered = fieldBits / 8 + 1
        var escaped: [UInt8] = []
        var covered = 0
        for (offset, byte) in raw.enumerated() {
            if escaped.count >= 2, escaped[escaped.count - 1] == 0,
               escaped[escaped.count - 2] == 0, byte <= 3 { escaped.append(3) }
            escaped.append(byte)
            if offset + 1 == rawCovered { covered = escaped.count }
        }
        return (escaped, covered)
    }
}
