// File: Tests/DiscordVoiceCodecsTests/SILKPulseCodingTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import Foundation
import Testing
@testable import DiscordVoiceCodecs

@Suite("SILK compressed pulse syntax")
struct SILKPulseCodingTests {
    /// Verifies independent reference bytes, rate selection, padding and every final
    /// entropy accounting value across all frame lengths and signal/offset contexts.
    @Test(arguments: SILKPulseOracleFixtures.all)
    func officialPulseFrames(_ fixture: SILKPulseOracleFixture) throws {
        let signal = try #require(SILKSignalType(rawValue: fixture.signal))
        let offset = try #require(SILKQuantizationOffset(rawValue: fixture.offset))
        let pulses = (0..<fixture.sampleCount).map { fixture.pattern[$0 % fixture.pattern.count] }
        var encoder = try OpusRangeEncoder(frameByteCount: fixture.bytes.count)
        let rate = try SILKPulseCoding.encode(pulses, to: &encoder, signalType: signal, quantizationOffset: offset)
        #expect(rate == fixture.rate)
        #expect(encoder.finalRange == fixture.range)
        #expect(encoder.bitsUsed == fixture.bits)
        #expect(encoder.fractionalBitsUsed == fixture.fractional)
        #expect(try Array(encoder.finalize()) == fixture.bytes)
        var decoder = try OpusRangeDecoder(frame: Data(fixture.bytes))
        let frame = try SILKPulseCoding.decode(from: &decoder, sampleCount: fixture.sampleCount, signalType: signal, quantizationOffset: offset)
        #expect(frame.signalType == signal)
        #expect(frame.quantizationOffset == offset)
        #expect(frame.rateLevel == fixture.rate)
        #expect(frame.signedPulses == pulses)
        #expect(frame.discardedPadding == (fixture.sampleCount == 120 ? Array(repeating: 0, count: 8) : []))
        #expect(decoder.finalRange == fixture.range)
        #expect(decoder.bitsUsed == fixture.bits)
        #expect(decoder.fractionalBitsUsed == fixture.fractional)
    }

    /// Exercises every legal explicit rate context with signed sparse pulses and
    /// exact encoder/decoder accounting, independently of automatic cost selection.
    @Test(arguments: Array(0...8), SILKSignalType.allCases)
    func explicitRateContexts(_ rate: Int, _ signal: SILKSignalType) throws {
        let pulses: [Int16] = (0..<80).map { $0 % 7 == 0 ? -3 : ($0 % 11 == 0 ? 4 : 0) }
        var encoder = try OpusRangeEncoder(frameByteCount: 160)
        #expect(try SILKPulseCoding.encode(pulses, to: &encoder, signalType: signal, quantizationOffset: .high, rateLevel: rate) == rate)
        let bytes = try encoder.finalize()
        var decoder = try OpusRangeDecoder(frame: bytes)
        let frame = try SILKPulseCoding.decode(from: &decoder, sampleCount: 80, signalType: signal, quantizationOffset: .high)
        #expect(frame.rateLevel == rate)
        #expect(frame.signedPulses == pulses)
        #expect(frame.shellPulseCounts.count == 5)
        #expect(frame.shellPulseCounts.allSatisfy { (0...16).contains($0) })
        #expect(frame.leastSignificantBitCounts.allSatisfy { (0...10).contains($0) })
        #expect(decoder.finalRange == encoder.finalRange)
        #expect(decoder.bitsUsed == encoder.bitsUsed)
        #expect(decoder.fractionalBitsUsed == encoder.fractionalBitsUsed)
    }

    /// Covers all eleven shell-normalization outcomes, including the tenth escape's
    /// shifted terminal context; signed extrema remain within representable pulses.
    @Test(arguments: Array(0...10), [Int16(1), Int16(-1)])
    func allLSBEscapeDepths(_ depth: Int, _ sign: Int16) throws {
        var pulses = Array(repeating: Int16(0), count: 80)
        pulses[0] = Int16(8 << depth) * sign
        var encoder = try OpusRangeEncoder(frameByteCount: 256)
        try SILKPulseCoding.encode(pulses, to: &encoder, signalType: .voiced, quantizationOffset: .low)
        var decoder = try OpusRangeDecoder(frame: encoder.finalize())
        let frame = try SILKPulseCoding.decode(from: &decoder, sampleCount: 80, signalType: .voiced, quantizationOffset: .low)
        #expect(frame.signedPulses == pulses)
        #expect(frame.leastSignificantBitCounts == [depth, 0, 0, 0, 0])
        #expect(frame.shellPulseCounts == [8, 0, 0, 0, 0])
        #expect(decoder.finalRange == encoder.finalRange)
        #expect(decoder.bitsUsed == encoder.bitsUsed)
    }

    /// Parses a legal nonzero pulse in mediumband's discarded tail. Every shell
    /// split and sign must still be consumed, and tail samples must not seed audio.
    @Test func nonzeroMediumbandPaddingIsParsedAndDiscarded() throws {
        var encoder = try OpusRangeEncoder(frameByteCount: 32)
        try encoder.encodeSymbol(0, model: OpusProbabilityModel(inverseCDF: SILKPulseTables.rate[0]))
        for block in 0..<8 {
            try encoder.encodeSymbol(block == 7 ? 1 : 0, model: OpusProbabilityModel(inverseCDF: SILKPulseTables.counts[0]))
        }
        // Choose the right half at every one-pulse split: sample 127 receives it.
        for table in [SILKPulseTables.shell3, SILKPulseTables.shell2, SILKPulseTables.shell1, SILKPulseTables.shell0] {
            try encoder.encodeSymbol(0, model: OpusProbabilityModel(inverseCDF: Array(table.prefix(2))))
        }
        try encoder.encodeSymbol(1, model: OpusProbabilityModel(inverseCDF: [49, 0]))
        var decoder = try OpusRangeDecoder(frame: encoder.finalize())
        let frame = try SILKPulseCoding.decode(from: &decoder, sampleCount: 120, signalType: .inactive, quantizationOffset: .low)
        #expect(frame.signedPulses == Array(repeating: 0, count: 120))
        #expect(frame.discardedPadding == [0, 0, 0, 0, 0, 0, 0, 1])
        #expect(decoder.finalRange == encoder.finalRange)
        #expect(decoder.bitsUsed == encoder.bitsUsed)
        var excitation = try SILKExcitationReconstructor(seed: 2, signalType: .inactive, quantizationOffset: .low)
        #expect(try frame.reconstructExcitation(seed: 2) == excitation.reconstruct(Array(repeating: 0, count: 120)))
    }

    /// Keeps the shell sum zero while LSBs make a nonzero coefficient; its negative
    /// sign uses shell-count-zero context rather than a recomputed magnitude sum.
    @Test func zeroShellWithNonzeroLSBsUsesOriginalSignContext() throws {
        var encoder = try OpusRangeEncoder(frameByteCount: 32)
        try encoder.encodeSymbol(0, model: OpusProbabilityModel(inverseCDF: SILKPulseTables.rate[0]))
        try encoder.encodeSymbol(17, model: OpusProbabilityModel(inverseCDF: SILKPulseTables.counts[0]))
        try encoder.encodeSymbol(0, model: OpusProbabilityModel(inverseCDF: SILKPulseTables.counts[9]))
        for _ in 0..<4 { try encoder.encodeSymbol(0, model: OpusProbabilityModel(inverseCDF: SILKPulseTables.counts[0])) }
        for sample in 0..<16 { try encoder.encodeSymbol(sample == 0 ? 1 : 0, model: OpusProbabilityModel(inverseCDF: [120, 0])) }
        try encoder.encodeSymbol(0, model: OpusProbabilityModel(inverseCDF: [254, 0]))
        var decoder = try OpusRangeDecoder(frame: encoder.finalize())
        let frame = try SILKPulseCoding.decode(from: &decoder, sampleCount: 80, signalType: .inactive, quantizationOffset: .low)
        #expect(frame.shellPulseCounts == [0, 0, 0, 0, 0])
        #expect(frame.leastSignificantBitCounts == [1, 0, 0, 0, 0])
        #expect(frame.signedPulses[0] == -1)
        #expect(frame.signedPulses.dropFirst().allSatisfy { $0 == 0 })
        #expect(decoder.finalRange == encoder.finalRange)
    }

    /// Verifies composition at an unaligned entropy position and preserves trailing
    /// symbols, so callers can share one range frame across channels/parameters.
    @Test func surroundingEntropySymbolsAndExcitationComposition() throws {
        let fixture = SILKPulseOracleFixtures.all[8]
        let pulses = (0..<fixture.sampleCount).map { fixture.pattern[$0 % fixture.pattern.count] }
        var encoder = try OpusRangeEncoder(frameByteCount: 256)
        try encoder.encodeBit(true, logProbability: 3)
        try SILKPulseCoding.encode(pulses, to: &encoder, signalType: .voiced, quantizationOffset: .high)
        try encoder.encodeUniform(19, total: 23)
        var decoder = try OpusRangeDecoder(frame: encoder.finalize())
        #expect(try decoder.decodeBit(logProbability: 3))
        let frame = try SILKPulseCoding.decode(from: &decoder, sampleCount: fixture.sampleCount, signalType: .voiced, quantizationOffset: .high)
        #expect(try decoder.decodeUniform(total: 23) == 19)
        #expect(frame.signedPulses == pulses)
        for seed in UInt8(0)...3 {
            var reconstruction = try SILKExcitationReconstructor(seed: seed, signalType: .voiced, quantizationOffset: .high)
            #expect(try frame.reconstructExcitation(seed: seed) == reconstruction.reconstruct(pulses))
        }
        #expect(throws: SILKExcitationError.invalidSeed) { try frame.reconstructExcitation(seed: 4) }
        #expect(decoder.finalRange == encoder.finalRange)
    }

    /// Rejects invalid frame sizes before reading or writing entropy. The caller can
    /// retry safely because all state and operation accounting remain unchanged.
    @Test(arguments: [0, 1, 79, 81, 119, 121, 239, 319, 321, 960])
    func invalidSampleCountsPreserveCoders(_ count: Int) throws {
        var encoder = try OpusRangeEncoder(frameByteCount: 32)
        var decoder = try OpusRangeDecoder(frame: Data([53, 196]))
        let initialRange = decoder.finalRange
        #expect(throws: SILKPulseCodingError.invalidSampleCount) {
            try SILKPulseCoding.encode(Array(repeating: 0, count: count), to: &encoder, signalType: .inactive, quantizationOffset: .low)
        }
        #expect(throws: SILKPulseCodingError.invalidSampleCount) {
            try SILKPulseCoding.decode(from: &decoder, sampleCount: count, signalType: .inactive, quantizationOffset: .low)
        }
        #expect(encoder.operationCount == 0)
        #expect(encoder.finalRange == 0x8000_0000)
        #expect(decoder.operationCount == 0)
        #expect(decoder.finalRange == initialRange)
    }

    /// Covers invalid context indices and pulse magnitudes requiring an eleventh
    /// escape, including Int16.min whose absolute value must never overflow.
    @Test func encoderValidationAndAtomicBudgetFailures() throws {
        for rate in [-1, 9, Int.min, Int.max] {
            var encoder = try OpusRangeEncoder(frameByteCount: 32)
            #expect(throws: SILKPulseCodingError.invalidRateLevel) {
                try SILKPulseCoding.encode(Array(repeating: 0, count: 80), to: &encoder, signalType: .voiced, quantizationOffset: .low, rateLevel: rate)
            }
            #expect(encoder.operationCount == 0)
        }
        for pulse in [Int16.min, Int16.max, Int16(9_216), Int16(-9_216)] {
            var encoder = try OpusRangeEncoder(frameByteCount: 32)
            var pulses = Array(repeating: Int16(0), count: 80)
            pulses[0] = pulse
            #expect(throws: SILKPulseCodingError.pulseMagnitudeExceeded) {
                try SILKPulseCoding.encode(pulses, to: &encoder, signalType: .voiced, quantizationOffset: .low)
            }
            #expect(encoder.operationCount == 0)
        }
        var bounded = try OpusRangeEncoder(frameByteCount: 32, maximumOperations: 3)
        #expect(throws: OpusRangeCodingError.operationLimitExceeded) {
            try SILKPulseCoding.encode(Array(repeating: 0, count: 80), to: &bounded, signalType: .inactive, quantizationOffset: .low)
        }
        #expect(bounded.operationCount == 0)
        var tooSmall = try OpusRangeEncoder(frameByteCount: 1)
        #expect(throws: OpusRangeCodingError.frameBudgetExceeded) {
            try SILKPulseCoding.encode(Array(repeating: 127, count: 320), to: &tooSmall, signalType: .voiced, quantizationOffset: .high)
        }
        #expect(tooSmall.operationCount == 0)
        #expect(tooSmall.finalRange == 0x8000_0000)
    }

    /// Exhausts operation admission mid-frame without consuming caller entropy, and
    /// confirms specified zero extension stays bounded for empty or arbitrary data.
    @Test func decoderOperationFailureIsAtomicAndMalformedWorkIsBounded() throws {
        var bounded = try OpusRangeDecoder(frame: Data([0xff]), maximumOperations: 3)
        let initialRange = bounded.finalRange
        #expect(throws: OpusRangeCodingError.operationLimitExceeded) {
            try SILKPulseCoding.decode(from: &bounded, sampleCount: 320, signalType: .voiced, quantizationOffset: .high)
        }
        #expect(bounded.operationCount == 0)
        #expect(bounded.finalRange == initialRange)
        for bytes in [Data(), Data([0xff]), Data(repeating: 0xff, count: 512), Data(repeating: 0, count: 512)] {
            var decoder = try OpusRangeDecoder(frame: bytes)
            let frame = try SILKPulseCoding.decode(from: &decoder, sampleCount: 320, signalType: .voiced, quantizationOffset: .high)
            #expect(frame.signedPulses.count == 320)
            #expect(frame.leastSignificantBitCounts.allSatisfy { (0...10).contains($0) })
            #expect(frame.signedPulses.allSatisfy { (-17_407...17_407).contains(Int($0)) })
            #expect(decoder.operationCount <= 3_861)
        }
    }
}
