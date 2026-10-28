// File: Tests/DiscordVoiceCodecsTests/CELTShapeFrameCodingTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import Foundation
import Testing
@testable import DiscordVoiceCodecs

@Suite("CELT all-band shape orchestration and anti-collapse")
struct CELTShapeFrameCodingTests {
    /// Independently captured official all-band contexts; masks for anti-collapse are
    /// supplied separately to exercise missing short blocks even after dense PVQ coding.
    private struct Fixture: Decodable {
        let input: Input; let output: Output
        struct Input: Decodable {
            let lm: Int; let c: Int; let start: Int; let end: Int; let transient: Bool; let spread: Int; let disable: Bool
            let dual: Bool; let intensity: Int; let coded: Int; let bytes: Int; let total: Int; let balance: Int; let prefix: Int; let seed: UInt32
            let pulses: [Int]; let tf: [Int]; let energy: [Float]; let x: [Float]; let masks: [UInt8]
            let loge: [Float]; let prev: [Float]; let prev2: [Float]
        }
        struct Output: Decodable {
            let coefficients: [Float]; let masks: [UInt8]; let seed: UInt32; let range: UInt32; let bits: Int; let fraction: Int
            let decoded: [Float]; let decodedMasks: [UInt8]; let decodedSeed: UInt32; let decodedRange: UInt32; let decodedBits: Int; let decodedFraction: Int
            let antiEncoder: [Float]; let antiDecoder: [Float]; let bytes: [UInt8]
        }
    }

    /// Independent exact bytes/control and bounded scalar spectra cover all durations,
    /// mono/stereo, dual-to-intensity, long/short blocks, zero/scarce/recursive budgets,
    /// folding occupancy, partial and hybrid ranges, TF scratch isolation, missing-block
    /// noise, mono history transition and approximate stereo merge above unit norm.
    @Test func officialAllBandAndAntiCollapseOracle() throws {
        let fixtures = try JSONDecoder().decode([Fixture].self, from: Data(CELTShapeFrameOracleFixtures.json.utf8))
        #expect(fixtures.count == 70)
        var historyDifferences = 0
        for fixture in fixtures {
            let x = fixture.input, e = fixture.output
            let q = try CELTShapeFrameCoding(frameSampleCount: 120 << x.lm, channelCount: x.c,
                startBand: x.start, endBand: x.end, transient: x.transient, timeFrequencyChanges: x.tf,
                spreading: try #require(CELTSpreading(rawValue: x.spread)), disableInversion: x.disable)
            #expect(q.frameSampleCount == 120 << x.lm && q.channelCount == x.c)
            #expect(q.startBand == x.start && q.endBand == x.end && q.transient == x.transient)
            #expect(q.timeFrequencyChanges == x.tf && q.spreading.rawValue == x.spread && q.disableInversion == x.disable)
            let a = allocation(pulses: x.pulses, balance: x.balance, coded: x.coded, intensity: x.intensity, dual: x.dual)
            var encoder = try OpusRangeEncoder(frameByteCount: x.bytes)
            let prefix = UInt32(12_345 & ((1 << x.prefix) - 1))
            if x.prefix > 0 { try encoder.encodeRawBits(prefix, count: x.prefix) }
            let v = try q.encode(x.x, allocation: a, totalEighthBits: x.total,
                seed: x.seed, bandEnergies: x.energy, into: &encoder)
            assertFloats(v.coefficients, e.coefficients)
            #expect(v.collapseMasks == e.masks && v.seed == e.seed)
            #expect(encoder.finalRange == e.range && encoder.bitsUsed == e.bits && encoder.fractionalBitsUsed == e.fraction)
            #expect(Array(try encoder.finalize()) == e.bytes)
            var decoder = try OpusRangeDecoder(frame: Data(e.bytes))
            if x.prefix > 0 { #expect(try decoder.decodeRawBits(count: x.prefix) == prefix) }
            let d = try q.decode(allocation: a, totalEighthBits: x.total, seed: x.seed, from: &decoder)
            assertFloats(d.coefficients, e.decoded)
            #expect(d.collapseMasks == e.decodedMasks && d.seed == e.decodedSeed)
            #expect(decoder.finalRange == e.decodedRange && decoder.bitsUsed == e.decodedBits && decoder.fractionalBitsUsed == e.decodedFraction)
            if x.transient {
                let ae = try q.applyAntiCollapse(d.coefficients, collapseMasks: x.masks, energies: x.loge,
                    previous: x.prev, previous2: x.prev2, allocation: a, seed: d.seed, isEncoder: true)
                let ad = try q.applyAntiCollapse(d.coefficients, collapseMasks: x.masks, energies: x.loge,
                    previous: x.prev, previous2: x.prev2, allocation: a, seed: d.seed)
                assertFloats(ae, e.antiEncoder); assertFloats(ad, e.antiDecoder)
                #expect(ad == (try q.applyAntiCollapse(d.coefficients, collapseMasks: x.masks, energies: x.loge,
                    previous: x.prev, previous2: x.prev2, allocation: a, seed: d.seed)))
                if zip(ae, ad).contains(where: { abs($0 - $1) > 0.001 }) { historyDifferences += 1 }
            }
        }
        #expect(historyDifferences > 0)
    }

    /// Every mode/range/TF rejection happens before untrusted values enter shifts or arrays.
    @Test func invalidConfiguration() throws {
        for n in [Int.min, 0, 119, 121, 1920, Int.max] {
            #expect(throws: CELTShapeCodingError.invalidFrameSize) { try CELTShapeFrameCoding(frameSampleCount: n) }
        }
        for c in [Int.min, 0, 3, Int.max] {
            #expect(throws: CELTShapeCodingError.invalidChannelCount) { try CELTShapeFrameCoding(frameSampleCount: 120, channelCount: c) }
        }
        for (lo, hi) in [(-1, 21), (0, 0), (20, 20), (0, 22), (Int.max, Int.max)] {
            #expect(throws: CELTShapeCodingError.invalidBandRange) { try CELTShapeFrameCoding(frameSampleCount: 120, startBand: lo, endBand: hi) }
        }
        for tf in [[], [0], Array(repeating: 0, count: 22), Array(repeating: Int.max, count: 21)] {
            #expect(throws: CELTShapeCodingError.invalidTimeFrequencyChange) { try CELTShapeFrameCoding(frameSampleCount: 120, timeFrequencyChanges: tf) }
        }
    }

    /// Malformed allocation metadata and extremes cannot cause overflow, invalid band
    /// access or entropy mutation. Both encode and decode reject the same authority.
    @Test func allocationAndInputRejectionsAreAtomic() throws {
        let q = try CELTShapeFrameCoding(frameSampleCount: 120)
        let zero = Array(repeating: Float(0), count: 120)
        let energy = Array(repeating: Float(1), count: 21)
        let invalid = [allocation(pulses: []), allocation(pulses: Array(repeating: Int.max, count: 21)),
            allocation(pulses: Array(repeating: -1, count: 21)), allocation(fine: [0]),
            allocation(fine: Array(repeating: 9, count: 21)), allocation(priorities: [0]),
            allocation(priorities: Array(repeating: 2, count: 21)), allocation(balance: Int.min),
            allocation(balance: Int.max), allocation(coded: 0), allocation(coded: 22),
            allocation(intensity: -1), allocation(intensity: 22), allocation(dual: true)]
        var encoder = try OpusRangeEncoder(frameByteCount: 16)
        let original = encoder
        for a in invalid {
            #expect(throws: CELTShapeCodingError.invalidAllocation) {
                try q.encode(zero, allocation: a, totalEighthBits: 100, bandEnergies: energy, into: &encoder)
            }
            var decoder = try OpusRangeDecoder(frame: Data(repeating: 0, count: 16))
            let saved = decoder
            #expect(throws: CELTShapeCodingError.invalidAllocation) { try q.decode(allocation: a, totalEighthBits: 100, from: &decoder) }
            #expect(decoder.bitsUsed == saved.bitsUsed && decoder.finalRange == saved.finalRange)
        }
        for total in [Int.min, -1, 1025, Int.max] {
            #expect(throws: CELTShapeCodingError.invalidBudget) {
                try q.encode(zero, allocation: allocation(), totalEighthBits: total, bandEnergies: energy, into: &encoder)
            }
        }
        for values in [[], [Float.nan] + zero.dropFirst(), [Float.infinity] + zero.dropFirst(), [33] + zero.dropFirst(), [2] + zero.dropFirst()] {
            #expect(throws: CELTShapeCodingError.invalidCoefficients) {
                try q.encode(values, allocation: allocation(), totalEighthBits: 100, bandEnergies: energy, into: &encoder)
            }
        }
        for values in [[], [Float.nan] + energy.dropFirst(), [-1] + energy.dropFirst(), [1_000_001] + energy.dropFirst()] {
            #expect(throws: CELTShapeCodingError.invalidEnergy) {
                try q.encode(zero, allocation: allocation(), totalEighthBits: 100, bandEnergies: values, into: &encoder)
            }
        }
        #expect(encoder.bitsUsed == original.bitsUsed && encoder.finalRange == original.finalRange && encoder.fractionalBitsUsed == original.fractionalBitsUsed)
    }

    /// Anti-collapse validates histories and occupancy separately, retains untouched
    /// bands exactly, bounds underflow, and keeps the caller's seed/history immutable.
    @Test func antiCollapseValidationAndIdentity() throws {
        let q = try CELTShapeFrameCoding(frameSampleCount: 960, transient: true)
        let zero = Array(repeating: Float(0), count: 960), energies = Array(repeating: Float(0), count: 21)
        let history = Array(repeating: Float(0), count: 42), masks = Array(repeating: UInt8(255), count: 21)
        let a = allocation()
        #expect(try q.applyAntiCollapse(zero, collapseMasks: masks, energies: energies,
            previous: history, previous2: history, allocation: a, seed: 42) == zero)
        #expect(throws: CELTShapeCodingError.invalidCollapseMasks) {
            try q.applyAntiCollapse(zero, collapseMasks: [], energies: energies, previous: history, previous2: history, allocation: a, seed: 0)
        }
        let small = try CELTShapeFrameCoding(frameSampleCount: 120, transient: true)
        #expect(throws: CELTShapeCodingError.invalidCollapseMasks) {
            try small.applyAntiCollapse(Array(zero.prefix(120)), collapseMasks: masks, energies: energies, previous: history, previous2: history, allocation: a, seed: 0)
        }
        for bad in [[], [Float.nan] + energies.dropFirst(), [Float.infinity] + energies.dropFirst(), [32769] + energies.dropFirst()] {
            #expect(throws: CELTShapeCodingError.invalidEnergy) {
                try q.applyAntiCollapse(zero, collapseMasks: masks, energies: bad, previous: history, previous2: history, allocation: a, seed: 0)
            }
        }
        for bad in [[], [Float.nan] + history.dropFirst(), [-32769] + history.dropFirst()] {
            #expect(throws: CELTShapeCodingError.invalidHistory) {
                try q.applyAntiCollapse(zero, collapseMasks: masks, energies: energies, previous: bad, previous2: history, allocation: a, seed: 0)
            }
            #expect(throws: CELTShapeCodingError.invalidHistory) {
                try q.applyAntiCollapse(zero, collapseMasks: masks, energies: energies, previous: history, previous2: bad, allocation: a, seed: 0)
            }
        }
        let long = try CELTShapeFrameCoding(frameSampleCount: 960)
        #expect(throws: CELTShapeCodingError.invalidTimeFrequencyChange) {
            try long.applyAntiCollapse(zero, collapseMasks: masks, energies: energies, previous: history, previous2: history, allocation: a, seed: 0)
        }
        let quiet = try q.applyAntiCollapse(zero, collapseMasks: Array(repeating: 0, count: 21),
            energies: Array(repeating: 32768, count: 21), previous: Array(repeating: -32768, count: 42),
            previous2: history, allocation: a, seed: 0)
        #expect(quiet == zero && quiet.allSatisfy(\.isFinite))
    }

    /// Zero authority still reconstructs ordinary folding/noise deterministically;
    /// inactive encoder samples survive while the decoder guarantees zero outside range.
    @Test func emptyFrameAndInactiveBandContract() throws {
        let q = try CELTShapeFrameCoding(frameSampleCount: 120, startBand: 17, endBand: 18)
        let a = allocation(coded: 18, intensity: 18)
        var input = Array(repeating: Float(0), count: 120)
        input[0] = 0.75
        var encoder = try OpusRangeEncoder(frameByteCount: 0)
        let v = try q.encode(input, allocation: a, totalEighthBits: 0,
            bandEnergies: Array(repeating: 1, count: 21), into: &encoder)
        var decoder = try OpusRangeDecoder(frame: Data())
        let d = try q.decode(allocation: a, totalEighthBits: 0, from: &decoder)
        #expect(v.coefficients[0] == 0.75 && d.coefficients[0] == 0)
        #expect(v.seed == d.seed && v.seed != 0 && v.collapseMasks == d.collapseMasks)
        #expect(d.collapseMasks[17] == 1 && d.collapseMasks.filter { $0 != 0 }.count == 1)
        assertFloats(Array(v.coefficients[40..<48]), Array(d.coefficients[40..<48]))
    }

    /// Constructs bounded allocation test data while allowing one deliberately invalid field.
    /// - Parameters:
    ///   - pulses: Global shape eighth-bit budgets; nil supplies 21 zeros.
    ///   - fine: Per-channel fine bit counts; nil supplies 21 zeros.
    ///   - priorities: Fine pass priority flags; nil supplies 21 zeros.
    ///   - balance: Signed fractional excess, default zero.
    ///   - coded: Exclusive coded-band end, default 21.
    ///   - intensity: First intensity band, default 21.
    ///   - dual: Whether channels initially code independently, default false.
    /// - Returns: A direct allocator result, including deliberate malformed test candidates.
    private func allocation(pulses: [Int]? = nil, fine: [Int]? = nil, priorities: [Int]? = nil,
                            balance: Int = 0, coded: Int = 21, intensity: Int = 21,
                            dual: Bool = false) -> CELTBitAllocationResult {
        CELTBitAllocationResult(shapeEighthBits: pulses ?? Array(repeating: 0, count: 21),
            fineEnergyBits: fine ?? Array(repeating: 0, count: 21),
            finePriorities: priorities ?? Array(repeating: 0, count: 21), balanceEighthBits: balance,
            codedBandEnd: coded, intensityBand: intensity, dualStereo: dual)
    }

    /// Requires full array dimensions and bounded independent scalar-float reconstruction.
    /// - Parameters:
    ///   - actual: Owned reconstructed spectrum or anti-collapse result.
    ///   - expected: Official scalar result, tolerance 5e-5 absolute per coefficient.
    private func assertFloats(_ actual: [Float], _ expected: [Float]) {
        #expect(actual.count == expected.count)
        #expect(zip(actual, expected).allSatisfy { abs($0 - $1) <= 0.00005 })
    }
}
