// File: Tests/DiscordVoiceCodecsTests/OpusMalformedAudioTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import Foundation
import Testing
@testable import DiscordVoiceCodecs

/// Deterministic arbitrary compressed syntax exercises the unified decoder's trust boundary.
@Suite("Bounded ordinary Opus arbitrary payloads")
struct OpusMalformedAudioTests {
    /// Every TOC configuration/layout and payload boundary either produces bounded finite PCM or rejects atomically.
    ///
    /// A valid CELT packet establishes nonempty history before each attempt. Accepted
    /// random syntax is not treated as authenticated audio; it must preserve declared
    /// duration/output bounds. Rejections must leave observable future PCM, range and
    /// loss history identical to an independent pre-call copy. No native codec or I/O
    /// is involved, and the fixed integer generator makes the corpus reproducible.
    /// - Parameter outputChannels: Both fixed output layouts exercise coded conversion.
    /// - Throws: Failure to construct the valid probe or a recovery-state regression;
    ///   arbitrary compressed-payload errors are intentionally classified as rejections.
    @Test(arguments: [1, 2])
    func arbitraryPayloadAdmissionAndRollback(outputChannels: Int) throws {
        var encoder = try CELTPacketEncoder(frameSampleCount: 480, channelCount: outputChannels)
        let probe = try encoder.encode(Array(repeating: 0.02, count: 480 * outputChannels), packetByteCount: 81)
        var initial = try OpusAudioDecoder(channelCount: outputChannels)
        _ = try initial.decode(probe)
        var random: UInt32 = 8_251
        for configuration in 0..<32 {
            for codedChannels in 1...2 {
                for byteCount in [0, 1, 2, 7, 31, 1_275] {
                    var bytes = Data([UInt8(configuration << 3 | (codedChannels == 2 ? 4 : 0))])
                    for _ in 0..<byteCount {
                        random = random &* 1_664_525 &+ 1_013_904_223
                        bytes.append(UInt8(truncatingIfNeeded: random >> 24))
                    }
                    let packet = try OpusPacket(bytes)
                    var decoder = initial
                    var baseline = initial
                    let result: [OpusAudioDecodedFrame]
                    do {
                        result = try decoder.decode(bytes)
                    } catch {
                        #expect(decoder.finalRange == baseline.finalRange)
                        #expect(decoder.lastPacketDuration == baseline.lastPacketDuration)
                        #expect(try decoder.decode(probe) == baseline.decode(probe))
                        #expect(try decoder.conceal(frameSampleCount: 360)
                            == baseline.conceal(frameSampleCount: 360))
                        continue
                    }
                    #expect(result.count == 1)
                    #expect(result[0].samples.count == packet.sampleCount * outputChannels)
                    #expect(result[0].samples.allSatisfy { $0.isFinite })
                    #expect(result[0].channelCount == outputChannels)
                    #expect(decoder.lastPacketDuration == packet.sampleCount)
                    #expect(decoder.finalRange == result[0].finalRange)
                }
            }
        }
    }
}
