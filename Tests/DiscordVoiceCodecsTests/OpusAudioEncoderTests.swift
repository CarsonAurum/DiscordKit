// File: Tests/DiscordVoiceCodecsTests/OpusAudioEncoderTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import Foundation
import Testing
@testable import DiscordVoiceCodecs

/// Fixed-format rate admission, ordinary wire decoding and DTX ownership regressions.
@Suite("Owned Opus encoder rate and DTX policies")
struct OpusAudioEncoderTests {
    /// Every mode/layout accepts its documented durations/bandwidths and decodes finite
    /// audio with exactly matching entropy state, including adaptive CELT composition.
    /// - Parameters:
    ///   - mode: SILK, hybrid and CELT select independent implementation branches.
    ///   - channels: Mono and stereo exercise converter/interleaving and wire TOCs.
    @Test(arguments: [OpusMode.silk, .hybrid, .celt], [1, 2])
    func ordinaryFormats(mode: OpusMode, channels: Int) throws {
        let bandwidths: [OpusBandwidth] = mode == .silk ? [.narrowband, .mediumband, .wideband]
            : (mode == .hybrid ? [.superwideband, .fullband] : [.narrowband, .wideband, .superwideband, .fullband])
        for duration in mode == .celt ? [120, 240, 480, 960] : [480, 960] {
            for bandwidth in bandwidths {
                var encoder = try OpusAudioEncoder(mode: mode, bandwidth: bandwidth, frameSampleCount: duration,
                                                   channelCount: channels, targetBitrate: 256_000)
                var decoder = try OpusAudioDecoder(channelCount: channels)
                #expect(encoder.mode == mode && encoder.bandwidth == bandwidth)
                #expect(encoder.frameSampleCount == duration && encoder.channelCount == channels)
                #expect(encoder.maximumPacketByteCount == 1_276 && encoder.dtx == nil && !encoder.enableInBandFEC)
                for phase in 0..<2 {
                    let input = samples(count: duration, channels: channels, phase: phase)
                    let output = try encoder.encode(input)
                    let packet = try OpusPacket(output.data)
                    #expect(packet.mode == mode && packet.bandwidth == bandwidth)
                    #expect(packet.frameSampleCount == duration && packet.channelCount == channels)
                    #expect(output.data.count == output.packetByteBudget)
                    #expect(output.shouldTransmit && !output.isDTX)
                    let decoded = try decoder.decode(output.data)
                    #expect(decoded.count == 1 && decoded[0].samples.count == input.count)
                    #expect(decoded[0].samples.allSatisfy { $0.isFinite })
                    #expect(decoded[0].finalRange == output.finalRange)
                    #expect(decoded[0].redundancyByteCount == 0)
                }
            }
        }
    }

    /// The coarsest legal SILK pitch lag stops one sample before 18ms; a repeated
    /// waveform at the formerly admitted endpoint must never produce index 32 in
    /// the 32-symbol absolute pitch codebook, including sustained stream history.
    @Test func silkPitchUpperEndpointRegression() throws {
        for rate in [8_000, 12_000, 16_000] {
            for duration in [10, 20] {
                var encoder = try SILKMonoEncoder(sampleRate: rate, frameDurationMilliseconds: duration)
                var decoder = try SILKMonoDecoder(sampleRate: rate)
                for frame in 0..<5 {
                    let pcm = (0..<encoder.sampleCount).map { index in
                        Int16(12_000 * sin(Double(frame * encoder.sampleCount + index) * 2 * .pi / (Double(rate) * 0.018)))
                    }
                    let output = try encoder.encode(pcm)
                    if let lag = output.parameters.pitchLagIndex {
                        #expect((0..<(32 * rate / 2_000)).contains(Int(lag)))
                    }
                    #expect(try decoder.decode(output.packet).payloads[0].frames[0].pcm == output.reconstructedPCM)
                }
            }
        }
    }

    /// Fractional byte entitlements never drift or exceed the cap, reset replays the
    /// startup packet, and a rate update starts the explicitly documented new interval.
    @Test func fractionalRateUpdateAndReset() throws {
        var encoder = try OpusAudioEncoder(frameSampleCount: 120, targetBitrate: 64_200, maximumPacketByteCount: 21)
        let input = samples(count: 120)
        var bytes = 0
        let first = try encoder.encode(input)
        bytes += first.data.count
        for _ in 1..<16 {
            let output = try encoder.encode(input)
            #expect((20...21).contains(output.data.count))
            bytes += output.data.count
        }
        #expect(bytes == 321)
        var baseline = encoder
        for bitrate in [Int.min, -1, 0, 5_999, 512_001, .max, 80_000] {
            #expect(throws: OpusAudioEncoderError.invalidBitrate) { try encoder.updateTargetBitrate(bitrate) }
        }
        #expect(try encoder.encode(input) == baseline.encode(input))
        try encoder.updateTargetBitrate(64_000)
        #expect(encoder.targetBitrate == 64_000)
        #expect(try encoder.encode(input).data.count == 20)
        try encoder.updateTargetBitrate(64_200)
        encoder.reset()
        #expect(try encoder.encode(input) == first)
        encoder.reset()
        encoder.reset()
        #expect(try encoder.encode(input) == first)
    }

    /// Packet padding at small and maximum caps remains external to SILK entropy,
    /// including 255 continuation headers; decoded ranges never include false CELT
    /// transition redundancy. Tight budgets may reject and must remain bounded.
    @Test func silkPaddingBudgetBoundaries() throws {
        var admitted = 0
        var sawLongPadding = false
        for bytes in Array(17...80) + [255, 256, 257, 258, 511, 512, 513, 1_025, 1_276] {
            var encoder = try OpusAudioEncoder(mode: .silk, bandwidth: .narrowband,
                                               targetBitrate: bytes * 400, maximumPacketByteCount: bytes)
            let output: OpusAudioEncodedPacket
            do {
                output = try encoder.encode(samples(count: 960))
            } catch SILKMonoEncoderError.payloadBudgetExceeded {
                continue
            }
            admitted += 1
            #expect(output.data.count == bytes && output.packetByteBudget == bytes)
            let packet = try OpusPacket(output.data)
            #expect(packet.frameRanges.count == 1 && packet.frameRanges[0].count >= 2)
            sawLongPadding = sawLongPadding || packet.paddingByteCount > 254
            var decoder = try OpusAudioDecoder()
            let decoded = try decoder.decode(output.data)
            #expect(decoded[0].redundancyByteCount == 0)
            #expect(decoded[0].finalRange == output.finalRange)
        }
        #expect(admitted >= 9)
        #expect(sawLongPadding)
    }

    /// DTX sends a startup/400ms refresh, emits ordinary zero-payload TOCs for the
    /// omitted intervals, and immediately resumes finite independently decoded audio.
    /// - Parameter mode: All three codecs exercise suppressed analysis and resumption.
    @Test(arguments: [OpusMode.silk, .hybrid, .celt])
    func dtxRefreshAndResumption(mode: OpusMode) throws {
        let policy = try OpusDTXPolicy(hangoverMilliseconds: 0)
        var encoder = try OpusAudioEncoder(mode: mode, bandwidth: mode == .silk ? .wideband : .fullband,
                                           targetBitrate: 128_000, dtx: policy)
        var decoder = try OpusAudioDecoder()
        let silence = Array(repeating: Float.zero, count: 960)
        for index in 0..<43 {
            let result = try encoder.encode(silence)
            #expect(result.shouldTransmit == (index % 20 == 0))
            #expect(result.isDTX == !result.shouldTransmit)
            #expect(result.data.count == (result.shouldTransmit ? 320 : 1))
            #expect(result.packetByteBudget == 320)
            if !result.shouldTransmit { #expect(result.finalRange == 0) }
            let packet = try OpusPacket(result.data)
            if !result.shouldTransmit { #expect(packet.frameRanges[0].count == 0) }
            let decoded = try decoder.decode(result.data)
            #expect(decoded[0].samples.count == 960 && decoded[0].samples.allSatisfy { $0.isFinite })
        }
        var copied = encoder
        let input = samples(count: 960)
        let resumed = try encoder.encode(input)
        #expect(resumed.shouldTransmit && !resumed.isDTX && resumed.data.count == 320)
        #expect(try copied.encode(input) == resumed)
        let decoded = try decoder.decode(resumed.data)
        #expect(decoded[0].samples.allSatisfy { $0.isFinite })
        #expect(decoded[0].samples.contains { abs($0) > 1e-6 })
        encoder.reset()
        #expect(try encoder.encode(silence).shouldTransmit)
    }

    /// Activity in one stereo channel cannot cancel the other channel in the level
    /// gate; whole-frame hangover and malformed input preserve exact future decisions.
    @Test func dtxHangoverChannelsAndAtomicity() throws {
        let policy = try OpusDTXPolicy(thresholdDBFS: -60, hangoverMilliseconds: 40)
        #expect(policy.thresholdDBFS == -60 && policy.hangoverMilliseconds == 40)
        var encoder = try OpusAudioEncoder(channelCount: 2, targetBitrate: 128_000, dtx: policy)
        let opposite = (0..<960).flatMap { _ in [Float(0.1), Float(-0.1)] }
        #expect(try encoder.encode(opposite).shouldTransmit)
        let silence = Array(repeating: Float.zero, count: 1_920)
        #expect(try encoder.encode(silence).shouldTransmit)
        #expect(try encoder.encode(silence).shouldTransmit)
        var baseline = encoder
        for bad in [[], [0], Array(repeating: Float.nan, count: 1_920),
                    Array(repeating: Float.infinity, count: 1_920), Array(repeating: Float(1.01), count: 1_920)] {
            #expect(throws: OpusAudioEncoderError.invalidSamples) { try encoder.encode(bad) }
        }
        let suppressed = try encoder.encode(silence)
        #expect(suppressed.isDTX)
        #expect(try baseline.encode(silence) == suppressed)
        #expect(try encoder.encode(opposite).shouldTransmit)
        var rounded = try OpusAudioEncoder(channelCount: 2, targetBitrate: 128_000,
                                           dtx: OpusDTXPolicy(hangoverMilliseconds: 1))
        _ = try rounded.encode(opposite)
        #expect(try rounded.encode(silence).shouldTransmit)
        #expect(try rounded.encode(silence).isDTX)
    }

    /// Tight SILK caps reject atomically instead of violating the bit target; a later
    /// explicit rate update retries the exact frame with preserved converter/FEC state.
    /// - Parameter channels: Both direct mono and mid/side quantization branches.
    @Test(arguments: [1, 2]) func silkBudgetRollback(channels: Int) throws {
        var encoder = try OpusAudioEncoder(mode: .silk, bandwidth: .wideband, channelCount: channels,
                                           targetBitrate: 256_000, enableInBandFEC: true)
        let input = samples(count: 960, channels: channels)
        _ = try encoder.encode(input)
        var baseline = encoder
        try encoder.updateTargetBitrate(channels == 1 ? 6_800 : 13_200)
        #expect(throws: SILKMonoEncoderError.payloadBudgetExceeded) { try encoder.encode(input) }
        try encoder.updateTargetBitrate(256_000)
        try baseline.updateTargetBitrate(256_000)
        #expect(try encoder.encode(input) == baseline.encode(input))
        #expect(encoder.enableInBandFEC)
    }

    /// Invalid dimensions, protocol combinations, rate extremes and DTX values fail
    /// before any partial owner is exposed, including arithmetic-overflow adversaries.
    @Test func configurationAdmission() throws {
        for count in [Int.min, -1, 0, 121, 5_760, .max] {
            #expect(throws: OpusAudioEncoderError.invalidConfiguration) { try OpusAudioEncoder(frameSampleCount: count) }
        }
        for channels in [Int.min, -1, 0, 3, .max] {
            #expect(throws: OpusAudioEncoderError.invalidConfiguration) { try OpusAudioEncoder(channelCount: channels) }
        }
        for cap in [Int.min, -1, 0, 2, 1_277, .max] {
            #expect(throws: OpusAudioEncoderError.invalidPacketByteLimit) { try OpusAudioEncoder(maximumPacketByteCount: cap) }
        }
        for rate in [Int.min, 0, 5_999, 512_001, .max] {
            #expect(throws: OpusAudioEncoderError.invalidBitrate) { try OpusAudioEncoder(targetBitrate: rate) }
        }
        #expect(throws: OpusAudioEncoderError.invalidBitrate) { try OpusAudioEncoder(targetBitrate: 64_000, maximumPacketByteCount: 159) }
        #expect(throws: OpusAudioEncoderError.invalidBitrate) { try OpusAudioEncoder(mode: .hybrid, targetBitrate: 6_000) }
        #expect(throws: OpusAudioEncoderError.invalidConfiguration) { try OpusAudioEncoder(enableInBandFEC: true) }
        #expect(throws: OpusAudioEncoderError.invalidConfiguration) { try OpusAudioEncoder(mode: .silk, frameSampleCount: 240) }
        #expect(throws: OpusAudioEncoderError.invalidConfiguration) { try OpusAudioEncoder(mode: .silk, bandwidth: .fullband) }
        #expect(throws: CELTPacketCodecError.unsupportedBandwidth) { try OpusAudioEncoder(bandwidth: .mediumband) }
        #expect(throws: OpusHybridEncoderError.unsupportedBandwidth) { try OpusAudioEncoder(mode: .hybrid, bandwidth: .narrowband) }
        for threshold in [Double.nan, .infinity, -.infinity, -120.01, -19.99] {
            #expect(throws: OpusAudioEncoderError.invalidDTXPolicy) { try OpusDTXPolicy(thresholdDBFS: threshold) }
        }
        for hangover in [Int.min, -1, 1_001, .max] {
            #expect(throws: OpusAudioEncoderError.invalidDTXPolicy) { try OpusDTXPolicy(hangoverMilliseconds: hangover) }
        }
        #expect(try OpusDTXPolicy(thresholdDBFS: -120, hangoverMilliseconds: 1_000).hangoverMilliseconds == 1_000)
        #expect(try OpusDTXPolicy(thresholdDBFS: -20, hangoverMilliseconds: 0).thresholdDBFS == -20)
    }

    /// Generates a continuous low-amplitude multitone with independent stereo phase.
    /// - Parameters:
    ///   - count: Per-channel frame length at the mandatory 48kHz input clock.
    ///   - channels: One or two output channels; default one.
    ///   - phase: Frame offset, default zero, for contiguous signal histories.
    /// - Returns: Exactly count*channels interleaved finite samples bounded by ±0.18.
    private func samples(count: Int, channels: Int = 1, phase: Int = 0) -> [Float] {
        (0..<count).flatMap { index in
            (0..<channels).map { channel in
                let t = Double(index + phase * count) / 48_000
                return Float(0.12 * sin(2 * .pi * (240 + Double(channel) * 90) * t)
                    + 0.06 * sin(2 * .pi * (840 + Double(channel) * 170) * t))
            }
        }
    }
}
