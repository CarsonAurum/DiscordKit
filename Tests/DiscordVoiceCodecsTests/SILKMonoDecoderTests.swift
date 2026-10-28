// File: Tests/DiscordVoiceCodecsTests/SILKMonoDecoderTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import Foundation
import Testing
@testable import DiscordVoiceCodecs

@Suite("Ordinary mono SILK packet decoding")
struct SILKMonoDecoderTests {
    private struct Input: Decodable { let rate: Int; let packets: [[UInt8]] }
    private struct Output: Decodable, Equatable {
        let pcm: [Int16]
        let ranges: [UInt32]
        let bits: [Int]
        let activity: [[Bool]]
        let redundancy: [[Bool]]
    }

    /// Verifies every PCM16 sample and range/header result against full independent SILK
    /// API decoding, covering all rates/durations, switches, gain/filter continuity and
    /// single/two/three-frame LBRR skip contexts. No encoder or native library runs here.
    @Test(arguments: silkMonoOracleFixtures.indices)
    func independentPacketPCM(index: Int) throws {
        let fixture = silkMonoOracleFixtures[index]
        let input = try JSONDecoder().decode(Input.self, from: Data(fixture.input.utf8))
        let expected = try JSONDecoder().decode([Output].self, from: Data(fixture.expected.utf8))
        var decoder = try SILKMonoDecoder(sampleRate: input.rate)
        for (bytes, reference) in zip(input.packets, expected) {
            let packet = try OpusPacket(Data(bytes))
            let output = try decoder.decode(packet)
            #expect(output.pcm48k == reference.pcm)
            #expect(output.pcm48k.count == packet.sampleCount)
            #expect(output.payloads.map(\.finalRange) == reference.ranges)
            #expect(output.payloads.map(\.bitsUsed) == reference.bits)
            #expect(output.payloads.map(\.voiceActivity) == reference.activity)
            #expect(output.payloads.map(\.redundancy) == reference.redundancy)
            #expect(output.payloads.allSatisfy { $0.frames.count == $0.voiceActivity.count })
        }
    }

    /// Exercises every ordinary packing code plus code-three VBR/padding; decoding one
    /// or two identical 10ms payloads must equal successive raw-payload calls exactly.
    /// A 120ms two-by-60ms packet additionally reaches the normative duration boundary.
    @Test
    func packingAndMaximumDuration() throws {
        let fixture = try JSONDecoder().decode(Input.self, from: Data(silkMonoOracleFixtures[0].input.utf8))
        for packetIndex in [0, 6] {
            let original = try OpusPacket(Data(fixture.packets[packetIndex]))
            let payload = [UInt8](original.data.subdata(in: original.frameRanges[0]))
            let toc = UInt8(original.configuration << 3)
            let length = encodedLength(payload.count)
            let forms: [[UInt8]] = [
                [toc] + payload,
                [toc | 1] + payload + payload,
                [toc | 2] + length + payload + payload,
                [toc | 3, 2] + payload + payload,
                [toc | 3, 0x82] + length + payload + payload,
                [toc | 3, 0xc2, 3] + length + payload + payload + [0xff, 0, 0x7f]
            ]
            for bytes in forms {
                let packet = try OpusPacket(Data(bytes))
                var packed = try SILKMonoDecoder(sampleRate: fixture.rate)
                let output = try packed.decode(packet)
                var reference = try SILKMonoDecoder(sampleRate: fixture.rate)
                var expected: [Int16] = []
                for _ in packet.frameRanges {
                    expected += try reference.decodePayload(Data(payload), durationMilliseconds: original.frameSampleCount / 48).pcm48k
                }
                #expect(output.pcm48k == expected)
                #expect(output.pcm48k.count == packet.sampleCount)
                if packetIndex == 6 && packet.frameRanges.count == 2 { #expect(output.pcm48k.count == 5_760) }
            }
        }
    }

    /// Validates all admission errors and proves a later empty payload rolls back earlier
    /// successful packed-frame synthesis, mono alignment, entropy and resampler history.
    /// Reset/copy equivalence establishes complete bounded-state ownership by value.
    @Test
    func validationAtomicityResetAndCopies() throws {
        #expect(throws: SILKFrameParameterError.invalidSampleRate) { try SILKMonoDecoder(sampleRate: 48_000) }
        let fixture = try JSONDecoder().decode(Input.self, from: Data(silkMonoOracleFixtures[0].input.utf8))
        let packet = try OpusPacket(Data(fixture.packets[0]))
        let payload = packet.data.subdata(in: packet.frameRanges[0])
        var decoder = try SILKMonoDecoder(sampleRate: fixture.rate)
        for duration in [0, 5, 15, 80, 120] {
            #expect(throws: SILKMonoDecoderError.invalidPayloadDuration) { try decoder.decodePayload(payload, durationMilliseconds: duration) }
        }
        for bytes in [Data(), Data(repeating: 0, count: 1_276)] {
            #expect(throws: SILKMonoDecoderError.invalidPayloadSize) { try decoder.decodePayload(bytes, durationMilliseconds: 10) }
        }
        #expect(throws: SILKMonoDecoderError.unsupportedMode) { try decoder.decode(OpusPacket(Data([128, 0]))) }
        #expect(throws: SILKMonoDecoderError.unsupportedChannels) { try decoder.decode(OpusPacket(Data([4, 0]))) }
        #expect(throws: SILKMonoDecoderError.sampleRateMismatch) { try decoder.decode(OpusPacket(Data([32, 0]))) }
        let partial = try OpusPacket(Data([2] + encodedLength(payload.count)) + payload)
        #expect(partial.frameRanges.count == 2)
        #expect(partial.frameRanges[1].isEmpty)
        #expect(throws: SILKMonoDecoderError.invalidPayloadSize) { try decoder.decode(partial) }
        var pristine = try SILKMonoDecoder(sampleRate: fixture.rate)
        #expect(try decoder.decode(packet) == pristine.decode(packet))
        var copied = decoder
        #expect(try copied.decode(packet) == decoder.decode(packet))
        decoder.reset()
        pristine.reset()
        #expect(try decoder.decode(packet) == pristine.decode(packet))
    }

    /// Documents normative entropy zero extension: bounded nonempty damaged syntax can
    /// still produce finite audio. Exercise all header bit patterns at all rates and
    /// durations, proving output dimensions and retained state remain bounded on repeats.
    @Test
    func boundedArbitraryPayloads() throws {
        for rate in [8_000, 12_000, 16_000] {
            for duration in [10, 20, 40, 60] {
                var decoder = try SILKMonoDecoder(sampleRate: rate)
                for byte in [UInt8(0), 1, 63, 127, 128, 191, 254, 255] {
                    let output = try decoder.decodePayload(Data([byte]), durationMilliseconds: duration)
                    #expect(output.pcm48k.count == duration * 48)
                    #expect(output.frames.count == (duration == 10 ? 1 : duration / 20))
                    #expect(output.frames.allSatisfy { $0.pcm.count <= 320 })
                }
            }
        }
    }

    /// Covers duration validation without damaging any entropy or synthesis history;
    /// valid duration changes are independently exercised by complete packet fixtures.
    @Test
    func channelDurationValidation() throws {
        var channel = try SILKFrameDecoder(sampleRate: 16_000, frameDurationMilliseconds: 20)
        #expect(throws: SILKFrameParameterError.invalidFrameDuration) { try channel.updateFrameDuration(milliseconds: 40) }
        #expect(channel.frameDurationMilliseconds == 20)
        try channel.updateFrameDuration(milliseconds: 10)
        #expect(channel.frameDurationMilliseconds == 10)
        #expect(channel.isFirstFrameAfterReset)
        #expect(channel.previousGainQ16 == 65_536)
        #expect(channel.outputHistory == Array(repeating: 0, count: 320))
    }

    /// Encodes one bounded RFC 6716 frame length for deterministic packing fixtures.
    /// - Parameter count: Nonnegative compressed payload count no greater than 1,275.
    /// - Returns: The normative one- or two-byte length field; no state is retained.
    private func encodedLength(_ count: Int) -> [UInt8] {
        if count < 252 { return [UInt8(count)] }
        let first = 252 + (count & 3)
        return [UInt8(first), UInt8((count - first) / 4)]
    }
}
