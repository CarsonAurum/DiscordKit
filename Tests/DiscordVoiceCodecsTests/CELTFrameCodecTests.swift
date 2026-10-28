// File: Tests/DiscordVoiceCodecsTests/CELTFrameCodecTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import Foundation
@testable import DiscordVoiceCodecs
import Testing

/// Full owned ordinary-frame API validation, independent stream ownership and entropy consistency.
@Suite("CELT ordinary frame orchestration")
struct CELTFrameCodecTests {
    /// Every ordinary mode/bandwidth pairs continuous encoding with exact decoder range and accounting.
    @Test func ordinaryModesChannelsAndBandwidths() throws {
        for size in [120, 240, 480, 960] {
            for channels in 1...2 {
                for end in [13, 17, 19, 21] {
                    var encoder = try CELTFrameEncoder(frameSampleCount: size, channelCount: channels, endBand: end)
                    var decoder = try CELTFrameDecoder(channelCount: channels)
                    #expect(encoder.frameSampleCount == size && encoder.channelCount == channels && encoder.endBand == end)
                    #expect(decoder.channelCount == channels)
                    for phase in 0..<3 {
                        let input = samples(size: size, channels: channels, phase: phase)
                        let encoded = try encoder.encode(input, frameByteCount: 80, intra: phase == 1)
                        #expect(encoded.bytes.count == 80 && encoded.bitsUsed <= 640)
                        let decoded = try decoder.decode(encoded.bytes, frameSampleCount: size, endBand: end)
                        #expect(decoded.samples.count == size * channels && decoded.samples.allSatisfy { $0.isFinite })
                        #expect(decoded.finalRange == encoded.finalRange)
                        #expect(decoded.bitsUsed == encoded.bitsUsed && decoded.fractionalBitsUsed == encoded.fractionalBitsUsed)
                        #expect(decoded.frameSampleCount == size && decoded.channelCount == channels)
                        #expect(!decoded.isSilence && !decoded.isTransient)
                        #expect(decoded.samples.contains { abs($0) > 0.00001 })
                    }
                }
            }
        }
    }

    /// Physical byte limits, zero PCM and full-scale input exercise normalization and capped allocation excess.
    @Test func storageAndSampleExtremes() throws {
        for (size, channels, end) in [(120,1,1),(120,1,20),(960,2,21)] {
            for bytes in [2, 1275] {
                var encoder = try CELTFrameEncoder(frameSampleCount: size, channelCount: channels, endBand: end)
                var decoder = try CELTFrameDecoder(channelCount: channels)
                for mode in 0..<4 {
                    let input = (0..<(size * channels)).map { index -> Float in
                        switch mode {
                        case 0: return 0
                        case 1: return 1
                        case 2: return -1
                        default: return index.isMultiple(of: 2) ? -1 : 1
                        }
                    }
                    let encoded = try encoder.encode(input, frameByteCount: bytes)
                    let decoded = try decoder.decode(encoded.bytes, frameSampleCount: size, endBand: end)
                    #expect(encoded.bytes.count == bytes && encoded.bitsUsed <= bytes * 8)
                    #expect(decoded.samples.count == input.count && decoded.samples.allSatisfy { $0.isFinite })
                    #expect(decoded.finalRange == encoded.finalRange && decoded.fractionalBitsUsed == encoded.fractionalBitsUsed)
                }
            }
        }
    }

    /// Integer extremes fail initialization rather than overflowing sample products or table indices.
    @Test func configurationBounds() throws {
        for size in [Int.min, -1, 0, 119, 121, 1920, Int.max] {
            #expect(throws: CELTTransformError.invalidFrameSize) { try CELTFrameEncoder(frameSampleCount: size) }
        }
        for channels in [Int.min, -1, 0, 3, Int.max] {
            #expect(throws: CELTTransformError.invalidChannelCount) {
                try CELTFrameEncoder(frameSampleCount: 120, channelCount: channels)
            }
            #expect(throws: CELTSynthesisError.invalidChannelCount) { try CELTFrameDecoder(channelCount: channels) }
        }
        for end in [Int.min, -1, 0, 22, Int.max] {
            #expect(throws: CELTBitAllocationError.invalidBandRange) { try CELTFrameEncoder(frameSampleCount: 120, endBand: end) }
        }
        for (start, end) in [(Int.min,21),(-1,21),(20,20),(21,21),(Int.max,Int.max),(17,16)] {
            #expect(throws: CELTBitAllocationError.invalidBandRange) {
                try CELTFrameEncoder(frameSampleCount: 120, startBand: start, endBand: end)
            }
        }
    }

    /// Shared encoding rejects too-small storage, finalized coders and operation exhaustion atomically.
    /// A failure after spectral analysis must preserve both the caller's arithmetic state and the
    /// encoder's warm overlap/preemphasis/envelope history, including hybrid high-band configurations.
    /// - Throws: Valid setup or recovery coding failures indicate an implementation regression.
    @Test func sharedEncoderFailurePreservesCallerAndSignalState() throws {
        for channels in 1...2 {
            for start in [0, 17] {
                var encoder = try CELTFrameEncoder(frameSampleCount: 480, channelCount: channels, startBand: start)
                let pcm = samples(size: 480, channels: channels)
                _ = try encoder.encode(pcm, frameByteCount: 80)
                var baseline = encoder
                for count in [0, 1] {
                    var entropy = try OpusRangeEncoder(frameByteCount: count)
                    #expect(throws: CELTFrameEncoderError.invalidFrameByteCount) {
                        try encoder.encode(pcm, into: &entropy)
                    }
                    #expect(entropy.operationCount == 0 && entropy.bitsUsed == 1)
                }
                var finalized = try OpusRangeEncoder(frameByteCount: 80)
                _ = try finalized.finalize()
                let before = (finalized.finalRange, finalized.bitsUsed, finalized.operationCount)
                #expect(throws: OpusRangeCodingError.finalized) {
                    try encoder.encode(pcm, into: &finalized)
                }
                #expect(finalized.finalRange == before.0 && finalized.bitsUsed == before.1
                    && finalized.operationCount == before.2)
                var limited = try OpusRangeEncoder(frameByteCount: 80, maximumOperations: 1)
                #expect(throws: OpusRangeCodingError.operationLimitExceeded) {
                    try encoder.encode(pcm, into: &limited)
                }
                #expect(limited.operationCount == 0 && limited.bitsUsed == 1)
                try limited.encodeBit(false, logProbability: 1)
                #expect(limited.operationCount == 1)
                var valid = try OpusRangeEncoder(frameByteCount: 80)
                var control = valid
                #expect(try encoder.encode(pcm, into: &valid) == baseline.encode(pcm, into: &control))
                #expect(valid.finalRange == control.finalRange && valid.bitsUsed == control.bitsUsed)
            }
        }
    }

    /// Validation and entropy failures after a warm frame preserve every encoder predictor/history field.
    @Test func encoderFailureRollbackAndRecovery() throws {
        var encoder = try CELTFrameEncoder(frameSampleCount: 240, channelCount: 2)
        let valid = samples(size: 240, channels: 2)
        _ = try encoder.encode(valid, frameByteCount: 80)
        var baseline = encoder
        for count in [0, 1, 479, 481, 1921] {
            #expect(throws: CELTFrameEncoderError.invalidSamples) {
                try encoder.encode(Array(repeating: 0, count: count), frameByteCount: 80)
            }
        }
        for invalid in [Float.nan, .infinity, -.infinity, -1.0001, 1.0001, .greatestFiniteMagnitude] {
            var input = valid
            input[479] = invalid
            #expect(throws: CELTFrameEncoderError.invalidSamples) { try encoder.encode(input, frameByteCount: 80) }
        }
        for bytes in [Int.min, -1, 0, 1, 1276, Int.max] {
            #expect(throws: CELTFrameEncoderError.invalidFrameByteCount) { try encoder.encode(valid, frameByteCount: bytes) }
        }
        let next = samples(size: 240, channels: 2, phase: 1)
        #expect(try encoder.encode(next, frameByteCount: 80) == baseline.encode(next, frameByteCount: 80))
    }

    /// Invalid frame/mode/bandwidth calls preserve all previous decoder envelope and signal state.
    @Test func decoderFailureRollbackAndRecovery() throws {
        var encoder = try CELTFrameEncoder(frameSampleCount: 240)
        let first = try encoder.encode(samples(size: 240, channels: 1), frameByteCount: 80)
        let next = try encoder.encode(samples(size: 240, channels: 1, phase: 1), frameByteCount: 80)
        var decoder = try CELTFrameDecoder()
        _ = try decoder.decode(first.bytes, frameSampleCount: 240)
        var baseline = decoder
        for count in [0, 1, 1276, 4096] {
            #expect(throws: CELTFrameDecoderError.invalidFrame) {
                try decoder.decode(Data(repeating: 0, count: count), frameSampleCount: 240)
            }
        }
        for size in [Int.min, -1, 0, 119, 121, 1920, Int.max] {
            #expect(throws: CELTBitAllocationError.invalidFrameSize) { try decoder.decode(next.bytes, frameSampleCount: size) }
        }
        for end in [Int.min, -1, 0, 22, Int.max] {
            #expect(throws: CELTBitAllocationError.invalidBandRange) {
                try decoder.decode(next.bytes, frameSampleCount: 240, endBand: end)
            }
        }
        #expect(try decoder.decode(next.bytes, frameSampleCount: 240) == baseline.decode(next.bytes, frameSampleCount: 240))
    }

    /// Copying streams forks independent histories, while reset restores exact bytes/range/PCM at startup.
    @Test func streamCopyAndReset() throws {
        let input = samples(size: 480, channels: 2)
        var encoder = try CELTFrameEncoder(frameSampleCount: 480, channelCount: 2)
        let first = try encoder.encode(input, frameByteCount: 100)
        var encoderCopy = encoder
        let continued = try encoder.encode(input, frameByteCount: 100)
        #expect(try encoderCopy.encode(input, frameByteCount: 100) == continued)
        encoder.reset()
        #expect(try encoder.encode(input, frameByteCount: 100) == first)
        var decoder = try CELTFrameDecoder(channelCount: 2)
        let startup = try decoder.decode(first.bytes, frameSampleCount: 480)
        var decoderCopy = decoder
        let second = try decoder.decode(continued.bytes, frameSampleCount: 480)
        #expect(try decoderCopy.decode(continued.bytes, frameSampleCount: 480) == second)
        decoder.reset()
        #expect(try decoder.decode(first.bytes, frameSampleCount: 480) == startup)
    }

    /// Terminal silence bypasses coarse/shape entropy while draining signal history across changed durations/bands.
    @Test func silenceDurationBandwidthTransitionsAndArbitraryFrames() throws {
        var encoder = try CELTFrameEncoder(frameSampleCount: 240)
        let ordinary = try encoder.encode(samples(size: 240, channels: 1), frameByteCount: 80)
        var decoder = try CELTFrameDecoder()
        _ = try decoder.decode(ordinary.bytes, frameSampleCount: 240)
        var entropy = try OpusRangeEncoder(frameByteCount: 2)
        let header = try CELTFrameHeader(frameSampleCount: 120)
        _ = try header.encodePrefix(silence: true, into: &entropy)
        let silence = try entropy.finalize()
        for (size, end) in [(120,13),(960,21),(240,17),(480,19)] {
            let result = try decoder.decode(silence, frameSampleCount: size, endBand: end)
            #expect(result.isSilence && !result.isTransient && result.samples.count == size)
            #expect(result.finalRange == entropy.finalRange && result.samples.allSatisfy { $0.isFinite })
        }
        // Unauthenticated CELT entropy has no checksum: all these unrelated tiny
        // frames can describe admitted low-rate spectra. Validate bounded output
        // on independent copies without labeling valid syntax as corrupted audio.
        var admitted = 0
        for byte in UInt8.min...UInt8.max {
            var candidate = decoder
            let result = try candidate.decode(Data([byte, byte ^ 0xa5]), frameSampleCount: 960)
            #expect(result.samples.count == 960 && result.samples.allSatisfy { $0.isFinite })
            #expect(result.bitsUsed <= 16)
            admitted += 1
        }
        #expect(admitted == 256)
    }

    /// Supplies bounded nonzero deterministic interleaved PCM with independent stereo channels.
    /// - Parameters:
    ///   - size: Validated ordinary per-channel frame duration.
    ///   - channels: One or two interleaved channels.
    ///   - phase: Integer fixture phase; default zero selects startup input.
    /// - Returns: Exactly size * channels finite samples within ±0.2, independent of any codec algorithm.
    private func samples(size: Int, channels: Int, phase: Int = 0) -> [Float] {
        (0..<(size * channels)).map { index in
            Float(sin(Double(index / channels + phase * size) * (index % channels == 0 ? 0.051 : 0.093))) * 0.2
        }
    }
}
