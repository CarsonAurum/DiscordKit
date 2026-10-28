// File: Tests/DiscordVoiceCodecsTests/OpusAudioDecoderTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import Foundation
import Testing
@testable import DiscordVoiceCodecs

/// Ordinary mode ownership, independent native PCM, explicit loss and FEC admission.
@Suite("Ordinary Opus audio decoding")
struct OpusAudioDecoderTests {
    /// Native shared-entropy hybrid streams retain their exact PCM and final ranges.
    @Test func independentHybridPackets() throws {
        for encoded in opusHybridOracleFixtures {
            let fixture = try JSONDecoder().decode(HybridFixture.self,
                from: #require(Data(base64Encoded: encoded)))
            var decoder = try OpusAudioDecoder(channelCount: fixture.channels)
            for packet in fixture.packets {
                let result = try decoder.decode(Data(packet.bytes))
                let samples = result.flatMap(\.samples)
                #expect(samples.count == packet.pcm.count)
                #expect(zip(samples, packet.pcm).allSatisfy { abs($0 - $1) < 3e-6 })
                #expect(result.last?.finalRange == packet.range && decoder.finalRange == packet.range)
                #expect(result.allSatisfy { $0.mode == .hybrid && $0.channelCount == fixture.channels })
                #expect(decoder.lastPacketDuration == samples.count / fixture.channels)
            }
        }
    }

    /// Continuous native SILK prefixes agree exactly until a short payload requires full Opus PLC.
    /// Component fixtures deliberately decode one-byte frames as SILK syntax, so
    /// comparisons stop before that different full-Opus loss policy is selected.
    @Test func independentSILKPackets() throws {
        for (fixtureIndex, fixture) in silkStereoOracleFixtures.enumerated() {
            let input = try JSONDecoder().decode(SILKInput.self, from: Data(fixture.input.utf8))
            let expected = try JSONDecoder().decode([SILKOutput].self, from: Data(fixture.expected.utf8))
            var decoder = try OpusAudioDecoder(channelCount: 2)
            for (packetIndex, pair) in zip(input.packets, expected).enumerated() {
                let (bytes, reference) = pair
                let parsed = try OpusPacket(Data(bytes))
                if parsed.frameRanges.contains(where: { $0.count <= 1 }) { break }
                let result = try decoder.decode(Data(bytes))
                #expect(result.flatMap(\.samples).elementsEqual(reference.pcm.map { Float($0) / 32768 }), "fixture \(fixtureIndex), packet \(packetIndex), redundancy \(result.map(\.redundancyByteCount))")
                #expect(result.map(\.finalRange) == reference.ranges, "fixture \(fixtureIndex), packet \(packetIndex)")
                #expect(result.allSatisfy { $0.mode == .silk })
            }
        }
    }

    /// Cold loss, empty payloads, repeated loss, duration boundaries and reset remain bounded and deterministic.
    @Test func coldAndRepeatedLoss() throws {
        for channels in 1...2 {
            var decoder = try OpusAudioDecoder(channelCount: channels)
            for count in stride(from: 120, through: 5_760, by: 120) {
                let cold = try decoder.conceal(frameSampleCount: count)
                #expect(cold.samples == Array(repeating: 0, count: count * channels))
                #expect(cold.mode == nil && cold.finalRange == 0 && cold.frameSampleCount == count)
                #expect(decoder.lastPacketDuration == count && decoder.channelCount == channels)
            }
            for toc: UInt8 in [0, 8, 16, 24, 96, 104, 128, 136, 144, 152] {
                let count = try OpusPacket(Data([toc])).frameSampleCount
                for payload in [Data([toc]), Data([toc, 0])] {
                    let cold = try decoder.decode(payload)
                    #expect(cold.count == 1 && cold[0].samples.count == count * channels)
                    #expect(cold[0].samples.allSatisfy { $0 == 0 } && cold[0].finalRange == 0)
                }
            }
            var encoder = try CELTPacketEncoder(frameSampleCount: 480, channelCount: channels)
            let packet = try encoder.encode(samples(count: 480, channels: channels), packetByteCount: 81)
            let first = try decoder.decode(packet)
            var copy = decoder
            for count in [120, 240, 360, 480, 600, 720, 840, 960, 1_080, 1_920, 5_760] {
                let loss = try decoder.conceal(frameSampleCount: count)
                #expect(try loss == copy.conceal(frameSampleCount: count))
                #expect(loss.frameSampleCount == count && loss.finalRange == 0)
                #expect(loss.samples.count == count * channels && loss.samples.allSatisfy(\.isFinite))
            }
            decoder.reset()
            #expect(decoder.finalRange == 0 && decoder.lastPacketDuration == 0)
            #expect(try decoder.decode(packet) == first)
        }
    }

    /// Fixed output channels accept every coded layout, mode switch, duration and bandwidth without losing bounds.
    @Test func allModeTransitionsAndChannelConversion() throws {
        for outputChannels in 1...2 {
            var decoder = try OpusAudioDecoder(channelCount: outputChannels)
            var packets: [Data] = []
            for codedChannels in 1...2 {
                for rate in [8_000, 12_000, 16_000] {
                    for duration in [10, 20] {
                        if codedChannels == 1 {
                            var encoder = try SILKMonoEncoder(sampleRate: rate, frameDurationMilliseconds: duration)
                            packets.append(try encoder.encode(Array(repeating: 100, count: rate * duration / 1_000)).packet.data)
                        } else {
                            var encoder = try SILKStereoEncoder(sampleRate: rate, frameDurationMilliseconds: duration)
                            packets.append(try encoder.encode(Array(repeating: 100, count: rate * duration / 1_000 * 2)).packet.data)
                        }
                    }
                }
                for count in [480, 960] {
                    for bandwidth in [OpusBandwidth.superwideband, .fullband] {
                        var encoder = try OpusHybridEncoder(frameSampleCount: count, channelCount: codedChannels, bandwidth: bandwidth)
                        packets.append(try encoder.encode(samples(count: count, channels: codedChannels), packetByteCount: 320))
                    }
                }
                for count in [120, 240, 480, 960] {
                    for bandwidth in [OpusBandwidth.narrowband, .wideband, .superwideband, .fullband] {
                        var encoder = try CELTPacketEncoder(frameSampleCount: count, channelCount: codedChannels, bandwidth: bandwidth)
                        packets.append(try encoder.encode(samples(count: count, channels: codedChannels), packetByteCount: 81))
                    }
                }
            }
            for packet in packets + packets.reversed() {
                let parsed = try OpusPacket(packet)
                let decoded = try decoder.decode(packet)
                #expect(decoded.flatMap(\.samples).count == parsed.sampleCount * outputChannels)
                #expect(decoded.allSatisfy { $0.mode == parsed.mode && $0.samples.allSatisfy(\.isFinite) })
                let loss = try decoder.conceal(frameSampleCount: 360)
                #expect(loss.samples.count == 360 * outputChannels && loss.samples.allSatisfy(\.isFinite))
            }
        }
    }

    /// Invalid inputs roll back state; CELT FEC falls back to the same explicit PLC and leaves packet audio available.
    @Test func recoveryAndAtomicFailures() throws {
        for channels in [-1, 0, 3, .max] {
            #expect(throws: CELTSynthesisError.invalidChannelCount) { try OpusAudioDecoder(channelCount: channels) }
        }
        var encoder = try CELTPacketEncoder(frameSampleCount: 480)
        let packet = try encoder.encode(samples(count: 480, channels: 1), packetByteCount: 81)
        var decoder = try OpusAudioDecoder()
        _ = try decoder.decode(packet)
        var baseline = decoder
        for count in [-1, 0, 1, 119, 121, 5_761, .max] {
            #expect(throws: OpusAudioDecoderError.invalidSampleCount) { try decoder.conceal(frameSampleCount: count) }
            #expect(throws: OpusAudioDecoderError.invalidSampleCount) { try decoder.recover(packet, frameSampleCount: count) }
        }
        for invalid in [Data(), Data([255]), Data([255, 0]), Data(repeating: 0, count: 65_537)] {
            #expect(throws: (any Error).self) { try decoder.decode(invalid) }
            #expect(throws: (any Error).self) { try decoder.recover(invalid, frameSampleCount: 480) }
        }
        #expect(try decoder.recover(packet, frameSampleCount: 720) == baseline.conceal(frameSampleCount: 720))
        #expect(try decoder.decode(packet) == baseline.decode(packet))
        // SILK without LBRR uses the same local concealment as the generalized owner.
        var silkEncoder = try SILKMonoEncoder(sampleRate: 16_000)
        let silkPacket = try silkEncoder.encode(Array(repeating: 100, count: 320)).packet.data
        var recovery = try OpusAudioDecoder()
        _ = try recovery.decode(silkPacket)
        var copy = recovery
        #expect(try recovery.recover(silkPacket, frameSampleCount: 960).samples
            == copy.conceal(frameSampleCount: 960).samples)
        #expect(try recovery.decode(silkPacket).flatMap(\.samples).count == 960)
    }

    /// Invalid raw/shared coded-channel admissions preserve both synthesis history and supplied arithmetic state.
    @Test func malformedCELTCodedChannelsAreAtomic() throws {
        for outputChannels in 1...2 {
            for codedChannels in 1...2 {
                var encoder = try CELTFrameEncoder(frameSampleCount: 480, channelCount: codedChannels)
                let encoded = try encoder.encode(samples(count: 480, channels: codedChannels), frameByteCount: 80)
                var raw = try CELTFrameDecoder(channelCount: outputChannels)
                _ = try raw.decode(encoded.bytes, frameSampleCount: 480, codedChannelCount: codedChannels)
                var baseline = raw
                for invalid in [Int.min, -1, 0, 3, Int.max] {
                    #expect(throws: (any Error).self) {
                        try raw.decode(encoded.bytes, frameSampleCount: 480, codedChannelCount: invalid)
                    }
                    var entropy = try OpusRangeDecoder(frame: encoded.bytes)
                    let before = (entropy.finalRange, entropy.bitsUsed, entropy.operationCount)
                    #expect(throws: (any Error).self) {
                        try raw.decode(from: &entropy, frameSampleCount: 480, codedChannelCount: invalid)
                    }
                    #expect(entropy.finalRange == before.0 && entropy.bitsUsed == before.1 && entropy.operationCount == before.2)
                }
                #expect(try raw.decode(encoded.bytes, frameSampleCount: 480, codedChannelCount: codedChannels)
                    == baseline.decode(encoded.bytes, frameSampleCount: 480, codedChannelCount: codedChannels))
            }
        }
    }

    /// Produces finite deterministic per-channel PCM for mode orchestration tests.
    /// - Parameters:
    ///   - count: Positive samples per channel in a standard Opus duration.
    ///   - channels: One or two interleaved channels.
    /// - Returns: Exactly count*channels normalized samples bounded by ±0.1.
    private func samples(count: Int, channels: Int) -> [Float] {
        (0..<(count * channels)).map { Float(sin(Double($0 / channels) * ($0 % channels == 0 ? 0.05 : 0.07))) * 0.1 }
    }

    private struct HybridFixture: Decodable { let channels: Int; let packets: [HybridPacket] }
    private struct HybridPacket: Decodable { let bytes: [UInt8]; let pcm: [Float]; let range: UInt32 }
    private struct SILKInput: Decodable { let packets: [[UInt8]] }
    private struct SILKOutput: Decodable { let pcm: [Int16]; let ranges: [UInt32] }
}
