// File: Tests/DiscordVoiceCodecsTests/SILKFrameParameterTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import Foundation
import Testing
@testable import DiscordVoiceCodecs

@Suite("Complete SILK channel parameter and pulse syntax")
struct SILKFrameParameterTests {
    private struct Input: Decodable {
        let rate: Int
        let milliseconds: Int
        let vad: Bool
        let lbrr: Bool
        let coding: Int
        let previousGain: Int
        let previousType: Int
        let previousLag: Int16
        let bytes: [UInt8]
    }

    private struct Reference: Decodable {
        let signal: Int
        let offset: Int
        let seed: UInt8
        let interpolation: Int
        let stage1: Int
        let gainIndices: [Int]
        let residualIndices: [Int]
        let gains: [Int32]
        let nlsfs: [Int16]
        let pitches: [Int]
        let ltpIndices: [Int]
        let coefficients: [[Int8]]
        let ltpScale: Int16
        let previousGain: Int
        let previousType: Int
        let previousLag: Int16
        let range: UInt32
        let bits: Int
        let fractional: Int
        let lagIndex: Int16?
        let contour: Int?
        let periodicity: Int?
        let scaleIndex: Int?
        let pulses: [Int16]
        let completeRange: UInt32
        let completeBits: Int
        let completeFractional: Int
    }

    /// Matches complete independently encoded channel frames across all three rates,
    /// both durations and signal categories. Every index, dequantized parameter,
    /// previous state, pulse/padding and intermediate/final entropy state is asserted.
    @Test(arguments: SILKParameterOracleFixtures.all)
    func officialCompleteChannelFrames(_ fixture: SILKParameterOracleFixture) throws {
        let input = try JSONDecoder().decode(Input.self, from: Data(fixture.input.utf8))
        let expected = try JSONDecoder().decode(Reference.self, from: Data(fixture.expected.utf8))
        var channel = try makeChannel(input)
        var entropy = try OpusRangeDecoder(frame: Data(input.bytes))
        let coding = try #require(SILKParameterCoding(rawValue: input.coding))
        let p = try channel.decode(from: &entropy, voiceActivity: input.vad, lowBitrateRedundancy: input.lbrr, coding: coding)
        #expect(p.signalType.rawValue == expected.signal)
        #expect(p.quantizationOffset.rawValue == expected.offset)
        #expect(p.seed == expected.seed)
        #expect(p.interpolationQ2 == expected.interpolation)
        #expect(p.normalizedLSFCodebookIndex == expected.stage1)
        #expect(p.gainIndices == expected.gainIndices)
        #expect(p.normalizedLSFResidualIndices == expected.residualIndices)
        #expect(p.gainsQ16 == expected.gains)
        #expect(p.normalizedLSFsQ15 == expected.nlsfs)
        #expect(p.pitchLags == expected.pitches)
        #expect(p.longTermGainIndices == expected.ltpIndices)
        #expect(p.longTermCoefficientsQ7 == expected.coefficients)
        #expect(p.longTermScaleQ14 == expected.ltpScale)
        #expect(p.pitchLagIndex == expected.lagIndex)
        #expect(p.pitchContourIndex == expected.contour)
        #expect(p.periodicityIndex == expected.periodicity)
        #expect(p.longTermScaleIndex == expected.scaleIndex)
        #expect(channel.previousGainIndex == expected.previousGain)
        #expect(channel.previousSignalType.rawValue == expected.previousType)
        #expect(channel.previousPitchLagIndex == expected.previousLag)
        #expect(entropy.finalRange == expected.range)
        #expect(entropy.bitsUsed == expected.bits)
        #expect(entropy.fractionalBitsUsed == expected.fractional)
        let pulses = try SILKPulseCoding.decode(from: &entropy, sampleCount: channel.sampleCount, signalType: p.signalType, quantizationOffset: p.quantizationOffset)
        #expect(pulses.signedPulses + pulses.discardedPadding == expected.pulses)
        #expect(entropy.finalRange == expected.completeRange)
        #expect(entropy.bitsUsed == expected.completeBits)
        #expect(entropy.fractionalBitsUsed == expected.completeFractional)
        var combinedChannel = try makeChannel(input)
        var combinedEntropy = try OpusRangeDecoder(frame: Data(input.bytes))
        let combined = try combinedChannel.decodeExcitation(from: &combinedEntropy, voiceActivity: input.vad, lowBitrateRedundancy: input.lbrr, coding: coding)
        #expect(combined.parameters == p)
        #expect(combined.pulses == pulses)
        #expect(try combined.excitationQ23 == pulses.reconstructExcitation(seed: p.seed))
        #expect(combinedEntropy.finalRange == entropy.finalRange)
        #expect(combinedEntropy.operationCount == entropy.operationCount)
        #expect(combinedChannel.previousGainIndex == channel.previousGainIndex)
    }

    /// Verifies all configuration combinations and rejects unsupported rates, frame
    /// durations and gain indices before any state or entropy resource exists.
    @Test func configurationBoundsAndReset() throws {
        for rate in [8_000, 12_000, 16_000] {
            for duration in [10, 20] {
                var channel = try SILKFrameParameterDecoder(sampleRate: rate, frameDurationMilliseconds: duration, previousGainIndex: 63, previousSignalType: .voiced, previousPitchLagIndex: -17)
                #expect(channel.sampleCount == rate * duration / 1_000)
                #expect(channel.subframeCount == duration / 5)
                #expect(channel.normalizedLSFOrder == (rate == 16_000 ? 16 : 10))
                channel.reset()
                #expect(channel.previousGainIndex == 0)
                #expect(channel.previousSignalType == .inactive)
                #expect(channel.previousPitchLagIndex == 0)
                channel.reset()
                #expect(channel.previousGainIndex == 0)
            }
        }
        for rate in [0, 7_999, 24_000, 48_000, Int.max] {
            #expect(throws: SILKFrameParameterError.invalidSampleRate) { try SILKFrameParameterDecoder(sampleRate: rate, frameDurationMilliseconds: 20) }
        }
        for duration in [0, 5, 11, 40, 60, Int.max] {
            #expect(throws: SILKFrameParameterError.invalidFrameDuration) { try SILKFrameParameterDecoder(sampleRate: 16_000, frameDurationMilliseconds: duration) }
        }
        for gain in [-1, 64, Int.max] {
            #expect(throws: SILKFrameParameterError.invalidPreviousGainIndex) { try SILKFrameParameterDecoder(sampleRate: 16_000, frameDurationMilliseconds: 20, previousGainIndex: gain) }
        }
    }

    /// Distinguishes VAD from LBRR's forced-active context, then checks deterministic
    /// parameter/excitation bounds under specified zero extension and arbitrary bytes.
    @Test func VADAndLBRRContextSelectionAndBoundedMalformedInput() throws {
        for bytes in [Data(), Data([0]), Data([255]), Data(repeating: 255, count: 64), Data((0..<255).map { UInt8($0) })] {
            var active = try SILKFrameParameterDecoder(sampleRate: 16_000, frameDurationMilliseconds: 20)
            var redundancy = active
            var inactive = active
            var a = try OpusRangeDecoder(frame: bytes)
            var b = a
            var c = a
            let activeFrame = try active.decodeExcitation(from: &a, voiceActivity: true)
            let redundancyFrame = try redundancy.decodeExcitation(from: &b, voiceActivity: false, lowBitrateRedundancy: true)
            let inactiveFrame = try inactive.decodeExcitation(from: &c, voiceActivity: false)
            #expect(activeFrame == redundancyFrame)
            #expect(a.finalRange == b.finalRange)
            #expect(inactiveFrame.parameters.signalType == .inactive)
            for result in [activeFrame, inactiveFrame] {
                #expect(result.parameters.normalizedLSFsQ15.count == 16)
                #expect(zip(result.parameters.normalizedLSFsQ15, result.parameters.normalizedLSFsQ15.dropFirst()).allSatisfy { $0 < $1 })
                #expect(result.parameters.gainsQ16.allSatisfy { $0 > 0 })
                #expect(result.excitationQ23.count == 320)
                #expect(result.parameters.normalizedLSFResidualIndices.allSatisfy { (-10...10).contains($0) })
                #expect(result.parameters.pitchLags.allSatisfy { $0 == 0 || (32...288).contains($0) })
            }
            #expect(a.operationCount <= 4_000)
        }
    }

    /// Preserves every caller state field if entropy admission fails within parameters
    /// or after successful parameters during pulse decoding, allowing a safe retry.
    @Test func atomicParameterAndCombinedFailures() throws {
        let fixture = SILKParameterOracleFixtures.all[17]
        let input = try JSONDecoder().decode(Input.self, from: Data(fixture.input.utf8))
        var measurement = try makeChannel(input)
        var complete = try OpusRangeDecoder(frame: Data(input.bytes))
        _ = try measurement.decode(from: &complete, voiceActivity: input.vad, coding: SILKParameterCoding(rawValue: input.coding)!)
        for operations in [1, complete.operationCount + 1] {
            var channel = try makeChannel(input)
            var entropy = try OpusRangeDecoder(frame: Data(input.bytes), maximumOperations: operations)
            let range = entropy.finalRange
            #expect(throws: OpusRangeCodingError.operationLimitExceeded) {
                try channel.decodeExcitation(from: &entropy, voiceActivity: input.vad, coding: SILKParameterCoding(rawValue: input.coding)!)
            }
            #expect(channel.previousGainIndex == input.previousGain)
            #expect(channel.previousSignalType.rawValue == input.previousType)
            #expect(channel.previousPitchLagIndex == input.previousLag)
            #expect(entropy.operationCount == 0)
            #expect(entropy.finalRange == range)
        }
        var channel = try makeChannel(input)
        var entropy = try OpusRangeDecoder(frame: Data(input.bytes), maximumOperations: 1)
        #expect(throws: OpusRangeCodingError.operationLimitExceeded) { try channel.decode(from: &entropy, voiceActivity: input.vad) }
        #expect(channel.previousGainIndex == input.previousGain)
        #expect(entropy.operationCount == 0)
    }

    /// Keeps long conditional lag histories bounded to signed sixteen-bit storage and
    /// clamps the actual pitch, matching reference wrap semantics on malformed input.
    @Test func conditionalLagWrapAndRepeatedGainState() throws {
        var channel = try SILKFrameParameterDecoder(sampleRate: 8_000, frameDurationMilliseconds: 10, previousGainIndex: 63, previousSignalType: .voiced, previousPitchLagIndex: Int16.max)
        for _ in 0..<30 {
            var entropy = try OpusRangeDecoder(frame: Data(repeating: 255, count: 64))
            let parameters = try channel.decode(from: &entropy, voiceActivity: true, coding: .conditional)
            #expect(parameters.interpolationQ2 == 4)
            #expect(parameters.gainsQ16.count == 2)
            #expect((0...63).contains(channel.previousGainIndex))
            #expect(parameters.pitchLags.allSatisfy { (16...144).contains($0) })
            #expect(parameters.longTermScaleIndex == 0)
        }
        #expect(channel.previousPitchLagIndex < 0)
        channel.reset()
        #expect(channel.previousPitchLagIndex == 0)
    }

    /// Constructs a channel from independently encoded fixture metadata without work.
    /// - Parameter input: Valid internal rate/duration and previous reference state.
    /// - Returns: A fresh parameter decoder, independent of every other fixture.
    /// - Throws: Configuration errors if fixture metadata becomes invalid.
    private func makeChannel(_ input: Input) throws -> SILKFrameParameterDecoder {
        try SILKFrameParameterDecoder(
            sampleRate: input.rate, frameDurationMilliseconds: input.milliseconds,
            previousGainIndex: input.previousGain, previousSignalType: SILKSignalType(rawValue: input.previousType)!, previousPitchLagIndex: input.previousLag
        )
    }
}
