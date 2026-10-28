// File: Tests/DiscordVoiceCodecsTests/OpusHybridCodecTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordMedia
import Foundation
import Testing
@testable import DiscordVoiceCodecs

/// Shared arithmetic composition, independent hybrid PCM and bounded encoder ownership.
@Suite("Owned hybrid Opus shared-entropy coding")
struct OpusHybridCodecTests {
    /// Every literal independently encoded mono/stereo SWB/FB sequence matches all PCM and final ranges.
    @Test func independentHybridPackets() throws {
        for encoded in opusHybridOracleFixtures {
            let data = try #require(Data(base64Encoded: encoded))
            let fixture = try JSONDecoder().decode(Fixture.self, from: data)
            var decoder = try OpusHybridDecoder(channelCount: fixture.channels)
            for packet in fixture.packets {
                let results = try decoder.decode(Data(packet.bytes))
                let pcm = results.flatMap(\.samples)
                #expect(pcm.count == packet.pcm.count)
                #expect(results.last?.finalRange == packet.range)
                #expect(zip(pcm, packet.pcm).allSatisfy { abs($0 - $1) < 3e-6 })
                #expect(results.allSatisfy { $0.channelCount == fixture.channels })
            }
        }
    }

    /// Every supported encoder format and optional LBRR policy produces bounded standard hybrid syntax.
    /// - Parameter enableInBandFEC: Both false and true exercise fresh and retained prior-frame policies.
    @Test(arguments: [false, true]) func ownedHybridEncoding(enableInBandFEC: Bool) throws {
        for count in [480, 960] {
            for channels in 1...2 {
                for bandwidth in [OpusBandwidth.superwideband, .fullband] {
                    var encoder = try OpusHybridEncoder(frameSampleCount: count, channelCount: channels,
                        bandwidth: bandwidth, enableInBandFEC: enableInBandFEC)
                    var decoder = try OpusHybridDecoder(channelCount: channels)
                    #expect(encoder.channelCount == channels && encoder.frameSampleCount == count && encoder.bandwidth == bandwidth)
                    #expect(encoder.enableInBandFEC == enableInBandFEC)
                    for phase in 0..<3 {
                        let pcm = samples(count: count, channels: channels, phase: phase)
                        let packet = try encoder.encode(pcm, packetByteCount: enableInBandFEC ? 640 : (channels == 1 ? 160 : 320))
                        let parsed = try OpusPacket(packet)
                        #expect(parsed.mode == .hybrid && parsed.channelCount == channels)
                        #expect(parsed.bandwidth == bandwidth && parsed.frameSampleCount == count)
                        let decoded = try decoder.decode(packet)
                        #expect(decoded.count == 1 && decoded[0].samples.count == pcm.count)
                        #expect(decoded[0].samples.allSatisfy { $0.isFinite })
                        #expect(decoded[0].samples.contains { abs($0) > 1e-6 })
                    }
                }
            }
        }
    }

    /// Failed format/PCM/budget admissions preserve encoder and decoder histories and independent copies.
    @Test func hybridAdmissionAndAtomicOwnership() throws {
        for count in [-1, 0, 120, 240, 481, .max] {
            #expect(throws: OpusHybridEncoderError.invalidDuration) { try OpusHybridEncoder(frameSampleCount: count) }
        }
        for channels in [-1, 0, 3, .max] {
            #expect(throws: CELTSynthesisError.invalidChannelCount) { try OpusHybridEncoder(channelCount: channels) }
            #expect(throws: CELTSynthesisError.invalidChannelCount) { try OpusHybridDecoder(channelCount: channels) }
        }
        for bandwidth in [OpusBandwidth.narrowband, .mediumband, .wideband] {
            #expect(throws: OpusHybridEncoderError.unsupportedBandwidth) { try OpusHybridEncoder(bandwidth: bandwidth) }
        }
        var encoder = try OpusHybridEncoder(frameSampleCount: 480)
        let pcm = samples(count: 480, channels: 1)
        let first = try encoder.encode(pcm)
        var baseline = encoder
        for bad in [[], [0], Array(repeating: Float.nan, count: 480), Array(repeating: Float.infinity, count: 480), Array(repeating: 1.01, count: 480)] {
            #expect(throws: OpusHybridEncoderError.invalidSamples) { try encoder.encode(bad) }
        }
        for bytes in [-1, 0, 64, 1_277, .max] {
            #expect(throws: OpusHybridEncoderError.invalidByteBudget) { try encoder.encode(pcm, packetByteCount: bytes) }
        }
        #expect(try encoder.encode(pcm) == baseline.encode(pcm))
        encoder.reset()
        #expect(try encoder.encode(pcm) == first)
        var decoder = try OpusHybridDecoder()
        let initial = try decoder.decode(first)
        var copied = decoder
        #expect(throws: OpusHybridDecoderError.unsupportedMode) { try decoder.decode(Data([0xf8, 0xff, 0xfe])) }
        #expect(throws: OpusHybridDecoderError.channelCountMismatch) { try decoder.decode(Data([first[0] | 4]) + first.dropFirst()) }
        #expect(throws: OpusHybridDecoderError.invalidPayloadSize) { try decoder.decode(Data([first[0]])) }
        // Earlier valid packed payload must also roll back if a final empty payload rejects.
        let payload = first.dropFirst()
        let size = payload.count
        let sizeHeader: [UInt8] = size < 252 ? [UInt8(size)] : [UInt8(252 + (size & 3)), UInt8((size - 252 - (size & 3)) / 4)]
        let failed = Data([first[0] | 2]) + Data(sizeHeader) + payload
        #expect(throws: OpusHybridDecoderError.invalidPayloadSize) { try decoder.decode(failed) }
        #expect(try decoder.decode(first) == copied.decode(first))
        decoder.reset()
        #expect(try decoder.decode(first) == initial)
    }

    /// Raw CELT frame entry points preserve zero-band behavior and compose a real preceding interval.
    @Test func sharedCELTCompositionAndAtomicity() throws {
        for channels in 1...2 {
            for start in [0, 17] {
                let pcm = samples(count: 480, channels: channels)
                var encoder = try CELTFrameEncoder(frameSampleCount: 480, channelCount: channels, startBand: start)
                var entropy = try OpusRangeEncoder(frameByteCount: 120)
                try entropy.encodeBit(true, logProbability: 2)
                let encoded = try encoder.encode(pcm, into: &entropy)
                var input = try OpusRangeDecoder(frame: encoded.bytes)
                #expect(try input.decodeBit(logProbability: 2))
                var decoder = try CELTFrameDecoder(channelCount: channels)
                let result = try decoder.decode(from: &input, frameSampleCount: 480, startBand: start)
                #expect(result.finalRange == encoded.finalRange && result.fractionalBitsUsed == encoded.fractionalBitsUsed)
                #expect(result.samples.count == pcm.count && result.samples.allSatisfy { $0.isFinite })
                var baseline = decoder
                let before = (input.finalRange, input.bitsUsed, input.operationCount)
                #expect(throws: CELTBitAllocationError.invalidBandRange) {
                    try decoder.decode(from: &input, frameSampleCount: 480, startBand: 21)
                }
                #expect(input.finalRange == before.0 && input.bitsUsed == before.1 && input.operationCount == before.2)
                var firstInput = try OpusRangeDecoder(frame: encoded.bytes)
                var secondInput = firstInput
                _ = try firstInput.decodeBit(logProbability: 2)
                _ = try secondInput.decodeBit(logProbability: 2)
                #expect(try decoder.decode(from: &firstInput, frameSampleCount: 480, startBand: start)
                    == baseline.decode(from: &secondInput, frameSampleCount: 480, startBand: start))
                let finalState = (entropy.finalRange, entropy.bitsUsed, entropy.operationCount)
                #expect(throws: CELTFrameEncoderError.invalidSamples) { try encoder.encode([], into: &entropy) }
                #expect(entropy.finalRange == finalState.0 && entropy.bitsUsed == finalState.1 && entropy.operationCount == finalState.2)
            }
        }
    }

    /// Produces deterministic bounded independent-channel PCM for coding/ownership checks.
    /// - Parameters:
    ///   - count: Per-channel frame length, fixed at 480 or 960 in these tests.
    ///   - channels: One or two interleaved channels.
    ///   - phase: Successive frame index; defaults to startup zero.
    /// - Returns: Exactly count*channels finite samples bounded by ±0.2.
    private func samples(count: Int, channels: Int, phase: Int = 0) -> [Float] {
        (0..<(count * channels)).map { index in
            Float(sin(Double(index / channels + phase * count) * (index % channels == 0 ? 0.051 : 0.077))) * 0.2
        }
    }

    private struct Fixture: Decodable {
        let channels: Int
        let packets: [Packet]
    }
    private struct Packet: Decodable {
        let bytes: [UInt8]
        let pcm: [Float]
        let range: UInt32
    }
}
