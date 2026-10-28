// File: Tests/DiscordVoiceCodecsTests/CELTPacketCodecTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import Foundation
@testable import DiscordVoiceCodecs
import Testing

/// Complete packet adoption checks with continuous raw-frame baselines and native CELT fixtures.
@Suite("CELT ordinary Opus packet codec")
struct CELTPacketCodecTests {
    /// All 32 CELT TOCs declare the exact duration, bandwidth and channels and decode their owned PCM frames.
    @Test func everyStandardCELTConfiguration() throws {
        for (bandwidth, base, end) in formats {
            for (duration, size) in [120, 240, 480, 960].enumerated() {
                for channels in 1...2 {
                    var encoder = try CELTPacketEncoder(frameSampleCount: size, channelCount: channels, bandwidth: bandwidth)
                    #expect(encoder.frameSampleCount == size && encoder.channelCount == channels && encoder.bandwidth == bandwidth)
                    let packet = try encoder.encode(samples(size: size, channels: channels), packetByteCount: 81, intra: true)
                    let expectedTOC = UInt8((base + duration) * 8 + (channels == 2 ? 4 : 0))
                    #expect(packet.first == expectedTOC && packet.count == 81)
                    let parsed = try OpusPacket(packet)
                    #expect(parsed.mode == .celt && parsed.packingCode == 0)
                    #expect(parsed.frameSampleCount == size && parsed.channelCount == channels && parsed.bandwidth == bandwidth)
                    var decoder = try CELTPacketDecoder(channelCount: channels)
                    var raw = try CELTFrameDecoder(channelCount: channels)
                    #expect(decoder.channelCount == channels)
                    let decoded = try decoder.decode(packet)
                    #expect(decoded.count == 1)
                    #expect(decoded == [try raw.decode(Data(packet.dropFirst()), frameSampleCount: size, endBand: end)])
                }
            }
        }
    }

    /// All packing forms, one/two-byte VBR lengths and continued padding preserve frame order and continuous history.
    @Test func packingCodesVBRAndPadding() throws {
        let contexts: [(Int, [Int], Bool, Int, Bool)] = [
            (0,[252],false,0,false), (1,[252,252],false,0,false),
            (2,[251,252],true,0,false), (2,[252,1275],true,0,false), (2,[1275,2],true,0,false),
            (3,[80],false,0,true), (3,[80],true,0,false),
            (3,[40,40],false,1,false), (3,[20,20,20],false,254,false),
            (3,[20,20,20],false,255,false), (3,[20,20,20],false,508,false),
            (3,[3,251,252,1275],true,509,false),
        ]
        for (code, lengths, variable, padding, includePadding) in contexts {
            var encoder = try CELTFrameEncoder(frameSampleCount: 120, channelCount: 2)
            var frames: [Data] = []
            for (phase, length) in lengths.enumerated() {
                frames.append(try encoder.encode(samples(size: 120, channels: 2, phase: phase), frameByteCount: length).bytes)
            }
            let packet = pack(toc: 0xe4, code: code, frames: frames, variable: variable,
                              padding: padding, includePadding: includePadding)
            let parsed = try OpusPacket(packet)
            #expect(parsed.frameRanges.map { $0.count } == lengths && parsed.paddingByteCount == padding)
            #expect(parsed.packingCode == code)
            var raw = try CELTFrameDecoder(channelCount: 2)
            var expected: [CELTDecodedFrame] = []
            for frame in frames { expected.append(try raw.decode(frame, frameSampleCount: 120)) }
            var decoder = try CELTPacketDecoder(channelCount: 2)
            #expect(try decoder.decode(packet) == expected)
            let next = try encoder.encode(samples(size: 120, channels: 2, phase: lengths.count), frameByteCount: 80)
            #expect(try decoder.decode(Data([0xe4]) + next.bytes) == [try raw.decode(next.bytes, frameSampleCount: 120)])
        }
    }

    /// Exactly 120 ms is admitted in each duration, while another frame fails before decoding and preserves state.
    @Test func maximumDurationAndFrameCardinality() throws {
        for (duration, size) in [120, 240, 480, 960].enumerated() {
            let count = 5760 / size
            var encoder = try CELTFrameEncoder(frameSampleCount: size)
            var frames: [Data] = []
            for phase in 0..<count {
                frames.append(try encoder.encode(samples(size: size, channels: 1, phase: phase), frameByteCount: 2).bytes)
            }
            let toc = UInt8((28 + duration) * 8)
            let packet = pack(toc: toc, code: 3, frames: frames)
            var decoder = try CELTPacketDecoder()
            let decoded = try decoder.decode(packet)
            #expect(decoded.count == count && decoded.reduce(0) { $0 + $1.frameSampleCount } == 5760)
            var baseline = decoder
            let excessive = pack(toc: toc, code: 3, frames: frames + [frames[0]])
            #expect(throws: OpusPacketError.excessiveDuration) { try decoder.decode(excessive) }
            let next = try encoder.encode(samples(size: size, channels: 1, phase: count), frameByteCount: 20).bytes
            #expect(try decoder.decode(Data([toc]) + next) == baseline.decode(Data([toc]) + next))
        }
    }

    /// A valid first frame followed by zero/one-byte frames uses explicit concealment in
    /// wire order. Subsequent compressed frames observe exactly the same recovery history
    /// as a raw-frame caller that selected each missing interval itself.
    @Test func shortPackedFramesUseConcealment() throws {
        var encoder = try CELTFrameEncoder(frameSampleCount: 240)
        let first = try encoder.encode(samples(size: 240, channels: 1), frameByteCount: 40).bytes
        let next = try encoder.encode(samples(size: 240, channels: 1, phase: 1), frameByteCount: 40).bytes
        let following = try encoder.encode(samples(size: 240, channels: 1, phase: 2), frameByteCount: 40).bytes
        for code in [2, 3] {
            for short in [Data(), Data([0]), Data([255])] {
                var decoder = try CELTPacketDecoder()
                var baseline = try CELTFrameDecoder()
                _ = try decoder.decode(Data([0xe8]) + first)
                _ = try baseline.decode(first, frameSampleCount: 240)
                let packet = pack(toc: 0xe8, code: code, frames: [next, short], variable: true)
                #expect(try OpusPacket(packet).frameRanges.count == 2)
                let expected = try baseline.decode(next, frameSampleCount: 240)
                let concealment = try baseline.conceal(frameSampleCount: 240)
                let actual = try decoder.decode(packet)
                #expect(actual.count == 2 && actual[0] == expected)
                #expect(actual[1].samples == concealment.samples)
                #expect(actual[1].finalRange == 0 && actual[1].bitsUsed == 0 && actual[1].fractionalBitsUsed == 0)
                #expect(!actual[1].isSilence && !actual[1].isTransient)
                #expect(try decoder.decode(Data([0xe8]) + following) == [baseline.decode(following, frameSampleCount: 240)])
            }
        }
    }

    /// SILK/hybrid, mismatched coded channels and malformed packing reject without advancing a warmed stream.
    @Test func modeChannelAndFramingRejection() throws {
        var encoder = try CELTPacketEncoder(frameSampleCount: 120)
        let first = try encoder.encode(samples(size: 120, channels: 1), packetByteCount: 41)
        let next = try encoder.encode(samples(size: 120, channels: 1, phase: 1), packetByteCount: 41)
        var decoder = try CELTPacketDecoder()
        _ = try decoder.decode(first)
        var baseline = decoder
        for configuration in 0..<16 {
            for stereo in [UInt8(0), 4] {
                let packet = Data([UInt8(configuration * 8) | stereo, 0, 0])
                #expect(throws: CELTPacketCodecError.unsupportedMode) { try decoder.decode(packet) }
            }
        }
        for configuration in 16..<32 {
            #expect(throws: CELTPacketCodecError.channelCountMismatch) {
                try decoder.decode(Data([UInt8(configuration * 8) | 4, 0, 0]))
            }
        }
        var stereo = try CELTPacketDecoder(channelCount: 2)
        #expect(throws: CELTPacketCodecError.channelCountMismatch) { try stereo.decode(first) }
        #expect(throws: OpusPacketError.missingTOC) { try decoder.decode(Data()) }
        #expect(throws: OpusPacketError.packetTooLarge) { try decoder.decode(Data(repeating: 0, count: 65_537)) }
        #expect(throws: OpusPacketError.truncatedHeader) { try decoder.decode(Data([0xe3])) }
        #expect(throws: OpusPacketError.invalidFrameCount) { try decoder.decode(Data([0xe3, 0])) }
        #expect(throws: OpusPacketError.invalidPadding) { try decoder.decode(Data([0xe3, 0x41, 0xff])) }
        #expect(throws: OpusPacketError.unequalCBRFrames) { try decoder.decode(Data([0xe1, 0, 0, 0])) }
        #expect(throws: OpusPacketError.invalidFrameLength) { try decoder.decode(Data([0xe2, 10, 0, 0])) }
        #expect(try decoder.decode(next) == baseline.decode(next))
    }

    /// Explicit missing intervals support every ordinary duration and preserve all stream
    /// state on bad configuration; reset returns the deterministic cold-start noise path.
    @Test func explicitPacketLossValidationCopyAndReset() throws {
        var decoder = try CELTPacketDecoder()
        var raw = try CELTFrameDecoder()
        for size in [120, 240, 480, 960] {
            for end in [13, 17, 19, 21] {
                var expected: [Float] = []
                var last: CELTConcealedFrame?
                for _ in 0..<(size / 120) {
                    let result = try raw.conceal(frameSampleCount: 120, endBand: end)
                    expected += result.samples
                    last = result
                }
                let actual = try decoder.conceal(frameSampleCount: size, endBand: end)
                #expect(actual.samples == expected)
                #expect(actual.seed == last?.seed && actual.lossDuration == last?.lossDuration)
                #expect(actual.bandLogEnergies == last?.bandLogEnergies)
            }
        }
        var baseline = decoder
        for size in [Int.min, -1, 0, 119, 121, 1920, Int.max] {
            #expect(throws: CELTSynthesisError.invalidFrameSize) { try decoder.conceal(frameSampleCount: size) }
        }
        for end in [Int.min, -1, 0, 22, Int.max] {
            #expect(throws: CELTSynthesisError.invalidBandRange) { try decoder.conceal(frameSampleCount: 120, endBand: end) }
        }
        #expect(try decoder.conceal(frameSampleCount: 120) == baseline.conceal(frameSampleCount: 120))
        decoder.reset()
        var fresh = try CELTPacketDecoder()
        #expect(try decoder.conceal(frameSampleCount: 120) == fresh.conceal(frameSampleCount: 120))
    }

    /// All constructor/sample/storage extremes fail predictably and packet failures retain encoding history.
    @Test func encoderValidationAndStorageBounds() throws {
        for size in [Int.min, -1, 0, 119, 121, 1920, Int.max] {
            #expect(throws: CELTTransformError.invalidFrameSize) { try CELTPacketEncoder(frameSampleCount: size) }
        }
        for channels in [Int.min, -1, 0, 3, Int.max] {
            #expect(throws: CELTTransformError.invalidChannelCount) { try CELTPacketEncoder(frameSampleCount: 120, channelCount: channels) }
            #expect(throws: CELTSynthesisError.invalidChannelCount) { try CELTPacketDecoder(channelCount: channels) }
        }
        #expect(throws: CELTPacketCodecError.unsupportedBandwidth) {
            try CELTPacketEncoder(frameSampleCount: 120, bandwidth: .mediumband)
        }
        var encoder = try CELTPacketEncoder(frameSampleCount: 120)
        _ = try encoder.encode(samples(size: 120, channels: 1), packetByteCount: 41)
        var baseline = encoder
        let input = samples(size: 120, channels: 1, phase: 1)
        for count in [Int.min, -1, 0, 1, 2, 1277, Int.max] {
            #expect(throws: CELTPacketCodecError.invalidPacketByteCount) { try encoder.encode(input, packetByteCount: count) }
        }
        for count in [0, 1, 119, 121, 1921] {
            #expect(throws: CELTFrameEncoderError.invalidSamples) {
                try encoder.encode(Array(repeating: 0, count: count), packetByteCount: 41)
            }
        }
        for invalid in [Float.nan, .infinity, -.infinity, 1.0001, -1.0001] {
            var malformed = input
            malformed[119] = invalid
            #expect(throws: CELTFrameEncoderError.invalidSamples) { try encoder.encode(malformed, packetByteCount: 41) }
        }
        #expect(try encoder.encode(input, packetByteCount: 41, intra: true) == baseline.encode(input, packetByteCount: 41, intra: true))
        for count in [3, 1276] {
            let packet = try encoder.encode(input, packetByteCount: count)
            #expect(packet.count == count && packet.first == 0xe0)
            #expect(try OpusPacket(packet).frameRanges.first?.count == count - 1)
        }
    }

    /// Value copies and resets preserve exact packets/PCM, and sliced data normalizes nonzero byte indices.
    @Test func resetCopyAndSlicedData() throws {
        let input = samples(size: 480, channels: 2)
        var encoder = try CELTPacketEncoder(frameSampleCount: 480, channelCount: 2, bandwidth: .wideband)
        let first = try encoder.encode(input, packetByteCount: 81)
        var encoderCopy = encoder
        let second = try encoder.encode(input, packetByteCount: 81)
        #expect(try encoderCopy.encode(input, packetByteCount: 81) == second)
        encoder.reset()
        #expect(try encoder.encode(input, packetByteCount: 81) == first)
        var decoder = try CELTPacketDecoder(channelCount: 2)
        let storage = Data([0x11, 0x22]) + first + Data([0x33])
        let slice = storage[2..<(2 + first.count)]
        #expect(slice.startIndex == 2)
        let startup = try decoder.decode(slice)
        var decoderCopy = decoder
        let continued = try decoder.decode(second)
        #expect(try decoderCopy.decode(second) == continued)
        decoder.reset()
        #expect(try decoder.decode(first) == startup)
    }

    /// Independently encoded native CELT frames become complete code-zero Opus packets with exact ranges and PCM.
    @Test func independentNativePacketsAndBandwidthDurationChanges() throws {
        let records = try JSONDecoder().decode([NativePacketSequence].self, from: Data(CELTFrameOracleFixtures.json.utf8))
        #expect(records.count >= 32)
        for record in records {
            var decoder = try CELTPacketDecoder(channelCount: record.input.c)
            #expect(record.input.frames.count == record.output.count)
            for (context, reference) in zip(record.input.frames, record.output) {
                let packet = Data([reference.toc & 0xfc]) + Data(reference.raw)
                let result = try #require(try decoder.decode(packet).first)
                #expect(result.frameSampleCount == context.n && result.channelCount == record.input.c)
                #expect(result.finalRange == reference.range)
                let expected = try floatVector(reference.pcm)
                #expect(result.samples.count == expected.count)
                let scale = max(1, expected.map { abs($0) }.max() ?? 0)
                for (actual, sample) in zip(result.samples, expected) {
                    #expect(abs(actual - sample) <= 0.000003 * scale + 0.000008 * abs(sample))
                }
            }
        }
    }

    /// Explicit RFC configuration groups used as independent TOC and bandwidth expectations.
    private var formats: [(OpusBandwidth, Int, Int)] {
        [(.narrowband,16,13),(.wideband,20,17),(.superwideband,24,19),(.fullband,28,21)]
    }

    /// Packs already owned bounded frame bytes using explicit test-only RFC packing decisions.
    /// - Parameters:
    ///   - toc: Configuration/channel byte; low packing bits are replaced.
    ///   - code: Packing code in `0...3`.
    ///   - frames: One frame for zero, two for one/two, one through 49 for three.
    ///     Equal length is required for CBR test contexts; zero/one-byte loss frames
    ///     intentionally exercise caller policy rejection after structural parsing.
    ///   - variable: Whether code three writes VBR lengths; default false.
    ///   - padding: Nonnegative trailing padding bytes; default zero. Continuations
    ///     use 255 for 254 bytes, following RFC 8251's corrected accounting.
    ///   - includePadding: Emits an explicit zero padding length when true; default false.
    /// - Returns: A complete synthetic packet with arbitrary nonzero trailing padding.
    /// Helper preconditions are enforced by fixed bounded test contexts, without I/O.
    private func pack(toc: UInt8, code: Int, frames: [Data], variable: Bool = false,
                      padding: Int = 0, includePadding: Bool = false) -> Data {
        var result = Data([(toc & 0xfc) | UInt8(code)])
        if code == 2 { result += length(frames[0].count) }
        if code == 3 {
            let padded = padding > 0 || includePadding
            result.append(UInt8(frames.count) | (variable ? 0x80 : 0) | (padded ? 0x40 : 0))
            if padded {
                var remaining = padding
                while remaining >= 254 { result.append(255); remaining -= 254 }
                result.append(UInt8(remaining))
            }
            if variable { for frame in frames.dropLast() { result += length(frame.count) } }
        }
        for frame in frames { result += frame }
        result += Data(repeating: 0xa7, count: padding)
        return result
    }

    /// Emits the independent RFC one/two-byte length representation used in VBR packet fixtures.
    /// - Parameter value: Known bounded fixture frame length in `0...1275`.
    /// - Returns: One byte below 252; otherwise the low two bits plus 252 and the quotient.
    private func length(_ value: Int) -> Data {
        if value < 252 { return Data([UInt8(value)]) }
        let first = 252 + value % 4
        return Data([UInt8(first), UInt8((value - first) / 4)])
    }

    /// Supplies deterministic finite interleaved audio independent of codec implementation details.
    /// - Parameters:
    ///   - size: Validated ordinary per-channel frame length.
    ///   - channels: One or two output channels.
    ///   - phase: Contiguous integer frame phase, default zero.
    /// - Returns: Exactly size * channels normalized samples in ±0.2.
    private func samples(size: Int, channels: Int, phase: Int = 0) -> [Float] {
        (0..<(size * channels)).map { index in
            Float(sin(Double(index / channels + size * phase) * (index % channels == 0 ? 0.051 : 0.093))) * 0.2
        }
    }

    /// Reads exact complete reference PCM without alignment assumptions, native code or fixture regeneration.
    /// - Parameter encoded: Valid base64 containing little-endian float32 samples.
    /// - Returns: Every independent native output sample in order.
    /// - Throws: Swift Testing requirement failures for malformed base64 or non-four-byte-aligned data.
    private func floatVector(_ encoded: String) throws -> [Float] {
        let bytes = Array(try #require(Data(base64Encoded: encoded)))
        try #require(bytes.count.isMultiple(of: 4))
        return stride(from: 0, to: bytes.count, by: 4).map { index in
            Float(bitPattern: UInt32(bytes[index]) | UInt32(bytes[index + 1]) << 8
                  | UInt32(bytes[index + 2]) << 16 | UInt32(bytes[index + 3]) << 24)
        }
    }
}

/// Only fields needed for complete independent native packet decoding are projected from the shared oracle schema.
private struct NativePacketSequence: Decodable {
    let input: Input
    let output: [Frame]
    struct Input: Decodable { let c: Int; let frames: [Context] }
    struct Context: Decodable { let n: Int }
    struct Frame: Decodable { let toc: UInt8; let raw: [UInt8]; let range: UInt32; let pcm: String }
}
