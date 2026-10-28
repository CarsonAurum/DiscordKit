// File: Tests/DiscordVoiceCodecsTests/SILKStereoEncoderTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import Foundation
import Testing
@testable import DiscordVoiceCodecs

@Suite("Owned conservative stereo SILK encoding")
struct SILKStereoEncoderTests {
    /// Selects owned stereo LBRR after actual packet loss for all rates/durations and
    /// every active-channel mask: neither, mid only, side only, and both. Present
    /// redundant channels retain the original exact indices, pulses and synthesis.
    /// Both-active recovery then matches ordinary following-packet decoding; absent
    /// channels deliberately invoke normative concealment instead of invented data.
    /// Budget failure and reset retain or clear the previous-frame evidence atomically.
    @Test
    func channelRedundancySelectionAndAtomicity() throws {
        for rate in [8_000, 12_000, 16_000] {
            for duration in [10, 20] {
                for pattern in 0..<4 {
                    var encoder = try SILKStereoEncoder(sampleRate: rate, frameDurationMilliseconds: duration, enableInBandFEC: true)
                    #expect(encoder.enableInBandFEC)
                    var ordinary = try SILKStereoDecoder(sampleRate: rate)
                    var missing = ordinary
                    let pcm = samples(count: encoder.sampleCount, pattern: pattern)
                    let first = try encoder.encode(pcm)
                    #expect(try ordinary.decode(first.packet).payloads[0].redundancy == [[false], [false]])
                    let before = encoder
                    var failed = try OpusRangeEncoder(frameByteCount: 1_275)
                    #expect(throws: SILKMonoEncoderError.payloadBudgetExceeded) {
                        try encoder.encodePayload(pcm, to: &failed, maximumBits: 64)
                    }
                    #expect(failed.operationCount == 0)
                    var copy = before
                    let following = try encoder.encode(pcm.map { $0 / 3 })
                    #expect(try copy.encode(pcm.map { $0 / 3 }) == following)
                    let payload = Data(following.packet.data[following.packet.frameRanges[0]])
                    let recovered = try missing.recoverPayload(payload, durationMilliseconds: duration)
                    let channels = [first.payload.mid, first.payload.side]
                    for channel in 0..<2 {
                        let active = channels[channel].parameters.signalType != .inactive
                        #expect(recovered.redundancy[channel] == [active])
                        let frame = recovered.channelFrames[0][channel]
                        if active {
                            #expect(frame?.parameters == channels[channel].parameters)
                            #expect(frame?.pulses.signedPulses == channels[channel].signedPulses)
                            #expect(frame?.pcm == channels[channel].reconstructedPCM)
                        } else { #expect(frame == nil) }
                    }
                    if pattern == 1 { #expect(try missing.decode(following.packet) == ordinary.decode(following.packet)) }
                    encoder.reset()
                    var fresh = try SILKStereoEncoder(sampleRate: rate, frameDurationMilliseconds: duration, enableInBandFEC: true)
                    #expect(try encoder.encode(pcm) == fresh.encode(pcm))
                }
            }
        }
    }

    /// Round-trips all rates/durations over independent, identical, opposite and silent
    /// channels. Ordinary stereo parsing must reproduce both quantized channels exactly,
    /// including inactive side syntax, zero predictor contexts and persistent history.
    @Test
    func ordinaryStereoPackets() throws {
        for rate in [8_000, 12_000, 16_000] {
            for duration in [10, 20] {
                var encoder = try SILKStereoEncoder(sampleRate: rate, frameDurationMilliseconds: duration)
                var decoder = try SILKStereoDecoder(sampleRate: rate)
                for pattern in 0..<5 {
                    let pcm = samples(count: encoder.sampleCount, pattern: pattern)
                    let output = try encoder.encode(pcm)
                    let decoded = try decoder.decode(output.packet)
                    let payload = try #require(decoded.payloads.first)
                    #expect(output.packet.channelCount == 2)
                    #expect(output.packet.frameSampleCount == duration * 48)
                    #expect(output.packet.data.count <= 1_276)
                    #expect(payload.midFrames[0].pcm == output.payload.mid.reconstructedPCM)
                    #expect(payload.sideFrames[0]?.pcm == output.payload.side.reconstructedPCM)
                    #expect(payload.midFrames[0].parameters == output.payload.mid.parameters)
                    #expect(payload.sideFrames[0]?.parameters == output.payload.side.parameters)
                    #expect(payload.midOnly == [false])
                    #expect(payload.finalRange == output.payload.finalRange)
                    #expect(payload.bitsUsed == output.payload.bitsUsed)
                    #expect(decoded.pcm48k.count == duration * 96)
                    if pattern == 0 || pattern == 2 { #expect(payload.voiceActivity[1] == [false]) }
                    if pattern == 3 { #expect(payload.voiceActivity[0] == [false]) }
                }
            }
        }
    }

    /// Verifies shared entropy remains open for surrounding symbols, with exact decoder
    /// endpoint accounting. Copy/reset behavior and every admission failure preserve both
    /// channel histories so independent callers can safely retry or reset their streams.
    @Test
    func sharedEntropyValidationAndOwnedState() throws {
        #expect(throws: SILKFrameParameterError.invalidSampleRate) { try SILKStereoEncoder(sampleRate: 48_000) }
        #expect(throws: SILKFrameParameterError.invalidFrameDuration) { try SILKStereoEncoder(sampleRate: 8_000, frameDurationMilliseconds: 40) }
        for cap in [0, 31, 1_276, Int.max] {
            #expect(throws: SILKMonoEncoderError.invalidPayloadByteLimit) { try SILKStereoEncoder(sampleRate: 8_000, maximumPayloadBytes: cap) }
        }
        var encoder = try SILKStereoEncoder(sampleRate: 16_000)
        let fresh = encoder
        let pcm = samples(count: encoder.sampleCount, pattern: 1)
        var entropy = try OpusRangeEncoder(frameByteCount: 512)
        #expect(throws: SILKMonoEncoderError.invalidSampleCount) { try encoder.encode([]) }
        for cap in [-1, 0, 4_097, Int.max] {
            #expect(throws: SILKMonoEncoderError.invalidPayloadBitLimit) { try encoder.encodePayload(pcm, to: &entropy, maximumBits: cap) }
        }
        #expect(throws: SILKMonoEncoderError.payloadBudgetExceeded) { try encoder.encodePayload(pcm, to: &entropy, maximumBits: 32) }
        #expect(entropy.operationCount == 0)
        let output = try encoder.encodePayload(pcm, to: &entropy, maximumBits: 3_000)
        #expect(output.bitsUsed <= 3_000)
        try entropy.encodeRawBits(19, count: 5)
        var reader = try OpusRangeDecoder(frame: entropy.finalize())
        var decoder = try SILKStereoDecoder(sampleRate: 16_000)
        let decoded = try decoder.decodePayload(from: &reader, durationMilliseconds: 20, codedChannelCount: 2)
        #expect(decoded.midFrames[0].pcm == output.mid.reconstructedPCM)
        #expect(decoded.sideFrames[0]?.pcm == output.side.reconstructedPCM)
        #expect(try reader.decodeRawBits(count: 5) == 19)
        var copy = encoder
        #expect(try copy.encode(pcm) == encoder.encode(pcm))
        encoder.reset()
        encoder.reset()
        var reference = fresh
        #expect(try encoder.encode(pcm) == reference.encode(pcm))
        var referenceEntropy = try OpusRangeEncoder(frameByteCount: 512)
        reference = fresh
        #expect(try reference.encodePayload(pcm, to: &referenceEntropy, maximumBits: 3_000) == output)
    }

    /// Builds deterministic input channels with correlation and full-scale edge coverage.
    /// - Parameters:
    ///   - count: Even count of interleaved left/right values in one configured frame.
    ///   - pattern: Zero silence, one independent ramps, two identical, three opposed,
    ///     four alternating extrema; no device, entropy generator or clock is involved.
    /// - Returns: Exactly `count` PCM16 values with bounded integer arithmetic.
    private func samples(count: Int, pattern: Int) -> [Int16] {
        var output: [Int16] = []
        for sample in 0..<(count / 2) {
            let left = Int16(clamping: (sample * 257) % 40_000 - 20_000)
            let right = Int16(clamping: (sample * 631) % 40_000 - 20_000)
            switch pattern {
            case 0: output += [0, 0]
            case 1: output += [left, right]
            case 2: output += [left, left]
            case 3: output += [left, -left]
            default: output += sample.isMultiple(of: 2) ? [.min, .max] : [.max, .min]
            }
        }
        return output
    }
}
