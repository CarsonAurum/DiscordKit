// File: Tests/DiscordVoiceCodecsTests/CELTEnergyQuantizerTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import Foundation
import Testing
@testable import DiscordVoiceCodecs

@Suite("CELT coarse, fine and final energies")
struct CELTEnergyQuantizerTests {
    /// Independent scalar libopus inputs and serialized all-pass outputs, never recomputed in tests.
    private struct Fixture: Decodable {
        let input: Input
        let output: Output
        struct Input: Decodable {
            let n: Int; let c: Int; let lm: Int; let start: Int; let end: Int; let bytes: Int
            let prefix: Int; let intra: Bool; let decay: Float; let lfe: Bool; let final: Int
            let old: [Float]; let target: [Float]; let fine: [Int]; let previous: [Int]; let priority: [Int]
        }
        struct Output: Decodable {
            let intra: Bool
            let coarse: [Float]; let coarseErrors: [Float]; let coarseBits: Int; let coarseRange: UInt32
            let fine: [Float]; let fineErrors: [Float]; let fineBits: Int; let fineRange: UInt32
            let final: [Float]; let finalErrors: [Float]; let bits: Int; let range: UInt32; let finalBudget: Int
            let decodedCoarse: [Float]; let decodedCoarseBits: Int; let decodedCoarseRange: UInt32
            let decodedFine: [Float]; let decoded: [Float]; let decodedBits: Int; let decodedRange: UInt32
            let bytes: [UInt8]
        }
    }

    /// Exercises all 168 ordinary coarse contexts, durations, channels, inter/intra,
    /// scarce-budget header/15/2/1/0-bit fallbacks, active subranges, decay/LFE,
    /// eight-bit and successive fine precision and final priority/skip ordering.
    /// Exact wire and accounting agreement plus independently checked reconstruction
    /// excludes a merely self-inverting alternate energy syntax. This is not full PCM conformance.
    @Test func officialEnergyOracle() throws {
        let fixtures = try JSONDecoder().decode([Fixture].self, from: Data(CELTEnergyOracleFixtures.json.utf8))
        #expect(fixtures.count == 33)
        for fixture in fixtures {
            let x = fixture.input
            let e = fixture.output
            let q = try CELTEnergyQuantizer(frameSampleCount: 120 << x.lm, channelCount: x.c,
                bandCount: x.n, startBand: x.start, endBand: x.end)
            #expect(q.frameSampleCount == 120 << x.lm && q.channelCount == x.c)
            #expect(q.bandCount == x.n && q.startBand == x.start && q.endBand == x.end)
            var encoder = try OpusRangeEncoder(frameByteCount: x.bytes)
            if x.prefix > 0 { try encoder.encodeRawBits(0, count: x.prefix) }
            let coarse = try q.encodeCoarse(target: x.target, previous: x.old, intra: x.intra,
                maximumDecay: x.decay, lowFrequencyEffects: x.lfe, into: &encoder)
            #expect(coarse.intra == e.intra)
            assertFloats(coarse.energies, e.coarse)
            assertFloats(coarse.errors, e.coarseErrors)
            #expect(encoder.bitsUsed == e.coarseBits && encoder.finalRange == e.coarseRange)
            let fine = try q.encodeFine(coarse, bitCounts: x.fine, previousBitCounts: x.previous, into: &encoder)
            assertFloats(fine.energies, e.fine)
            assertFloats(fine.errors, e.fineErrors)
            #expect(encoder.bitsUsed == e.fineBits && encoder.finalRange == e.fineRange)
            let count = zip(x.fine, x.previous).map(+)
            let final = try q.encodeFinal(fine, fineBitCounts: count, priorities: x.priority,
                remainingBits: e.finalBudget, into: &encoder)
            assertFloats(final.energies, e.final)
            assertFloats(final.errors, e.finalErrors)
            #expect(encoder.bitsUsed == e.bits && encoder.finalRange == e.range)
            #expect(Array(try encoder.finalize()) == e.bytes)
            var decoder = try OpusRangeDecoder(frame: Data(e.bytes))
            if x.prefix > 0 { #expect(try decoder.decodeRawBits(count: x.prefix) == 0) }
            let decodedCoarse = try q.decodeCoarse(previous: x.old, from: &decoder)
            #expect(decodedCoarse.intra == e.intra)
            assertFloats(decodedCoarse.energies, e.decodedCoarse)
            #expect(decoder.bitsUsed == e.decodedCoarseBits && decoder.finalRange == e.decodedCoarseRange)
            let decodedFine = try q.decodeFine(energies: decodedCoarse.energies, bitCounts: x.fine,
                previousBitCounts: x.previous, from: &decoder)
            assertFloats(decodedFine, e.decodedFine)
            let decoded = try q.decodeFinal(energies: decodedFine, fineBitCounts: count,
                priorities: x.priority, remainingBits: e.finalBudget, from: &decoder)
            assertFloats(decoded, e.decoded)
            #expect(decoded == final.energies)
            #expect(decoder.bitsUsed == e.decodedBits && decoder.finalRange == e.decodedRange)
            #expect(final.intra == coarse.intra && fine.intra == coarse.intra)
        }
    }

    /// Rejects every configuration boundary before constructing or indexing static contexts.
    @Test func invalidConfiguration() throws {
        for samples in [Int.min, -1, 0, 119, 121, 1_920, Int.max] {
            #expect(throws: CELTEnergyQuantizerError.invalidFrameSize) {
                try CELTEnergyQuantizer(frameSampleCount: samples)
            }
        }
        for channels in [Int.min, -1, 0, 3, Int.max] {
            #expect(throws: CELTEnergyQuantizerError.invalidChannelCount) {
                try CELTEnergyQuantizer(frameSampleCount: 120, channelCount: channels)
            }
        }
        for bands in [Int.min, -1, 0, 22, Int.max] {
            #expect(throws: CELTEnergyQuantizerError.invalidBandRange) {
                try CELTEnergyQuantizer(frameSampleCount: 120, bandCount: bands)
            }
        }
        for bounds in [(Int.min, 1), (-1, 1), (0, 0), (1, 1), (2, 1), (0, 22), (21, 22), (Int.max, Int.max)] {
            #expect(throws: CELTEnergyQuantizerError.invalidBandRange) {
                try CELTEnergyQuantizer(frameSampleCount: 120, startBand: bounds.0, endBand: bounds.1)
            }
        }
        let defaultValue = try CELTEnergyQuantizer(frameSampleCount: 960)
        #expect(defaultValue.channelCount == 1 && defaultValue.bandCount == 21)
        #expect(defaultValue.startBand == 0 && defaultValue.endBand == 21)
        let one = try CELTEnergyQuantizer(frameSampleCount: 120, bandCount: 1)
        #expect(one.startBand == 0 && one.endBand == 1)
    }

    /// Validates target/history lengths, finiteness and documented log-domain bounds
    /// before header emission. Decoder rejects the same malformed histories atomically.
    @Test func invalidEnergiesPreserveEntropy() throws {
        let q = try CELTEnergyQuantizer(frameSampleCount: 120, bandCount: 2)
        var encoder = try OpusRangeEncoder(frameByteCount: 16)
        var decoder = try OpusRangeDecoder(frame: Data(repeating: 0, count: 16))
        for values: [Float] in [[], [0], [0, 0, 0], [.nan, 0], [.infinity, 0], [-.infinity, 0],
                               [-32_769, 0], [32_769, 0], [.greatestFiniteMagnitude, 0]] {
            #expect(throws: CELTEnergyQuantizerError.invalidEnergies) {
                try q.encodeCoarse(target: values, previous: [0, 0], into: &encoder)
            }
            #expect(throws: CELTEnergyQuantizerError.invalidEnergies) {
                try q.encodeCoarse(target: [0, 0], previous: values, into: &encoder)
            }
            #expect(throws: CELTEnergyQuantizerError.invalidEnergies) {
                try q.decodeCoarse(previous: values, from: &decoder)
            }
            #expect(encoder.operationCount == 0 && decoder.operationCount == 0)
        }
        for decay: Float in [-1, 129, .nan, .infinity] {
            #expect(throws: CELTEnergyQuantizerError.invalidDecay) {
                try q.encodeCoarse(target: [0, 0], previous: [0, 0], maximumDecay: decay, into: &encoder)
            }
            #expect(encoder.operationCount == 0)
        }
        let encoded = try q.encodeCoarse(target: [-128, 128], previous: [-128, 128], intra: true, into: &encoder)
        #expect(encoded.energies.allSatisfy { $0.isFinite })
    }

    /// Zero-byte syntax has no header/entropy symbols: every active channel-band uses
    /// the exact -1 coarse fallback and frequency prediction; inactive bands are retained.
    @Test func emptyFramesHaveBoundedPredictorFallback() throws {
        let q = try CELTEnergyQuantizer(frameSampleCount: 960, channelCount: 2, bandCount: 3, startBand: 1)
        let old: [Float] = [123, -20, 2, -123, -9, 4]
        var encoder = try OpusRangeEncoder(frameByteCount: 0)
        let coarse = try q.encodeCoarse(target: [0, 0, 0, 0, 0, 0], previous: old, intra: true, into: &encoder)
        #expect(!coarse.intra && encoder.operationCount == 0)
        #expect(coarse.energies == [123, -5.5, -0.7999878, -123, -5.5, 0.2000122])
        let fine = try q.encodeFine(coarse, bitCounts: [8, 8, 8], into: &encoder)
        #expect(fine == coarse && encoder.operationCount == 0)
        let final = try q.encodeFinal(fine, fineBitCounts: [0, 0, 0], priorities: [0, 1, 0], remainingBits: 0, into: &encoder)
        #expect(final == coarse)
        var decoder = try OpusRangeDecoder(frame: encoder.finalize())
        let decoded = try q.decodeCoarse(previous: old, from: &decoder)
        #expect(decoded.energies == coarse.energies && !decoded.intra && decoder.operationCount == 0)
        #expect(try q.decodeFine(energies: decoded.energies, bitCounts: [8, 8, 8], from: &decoder) == decoded.energies)
        #expect(try q.decodeFinal(energies: decoded.energies, fineBitCounts: [0, 0, 0], priorities: [0, 1, 0],
            remainingBits: 0, from: &decoder) == decoded.energies)
    }

    /// A coarse call entered with exactly one usable bit must reconstruct -1 or zero,
    /// including extreme negative residuals. The external decoder's one-bit syntax
    /// admits no other values, so encoder bookkeeping clamps to that canonical symbol.
    @Test func oneBitFallbackCanonicalizesExtremeResiduals() throws {
        let q = try CELTEnergyQuantizer(frameSampleCount: 120, bandCount: 1)
        for target: Float in [-128, -10, -1, -0.5, 0, 128] {
            var encoder = try OpusRangeEncoder(frameByteCount: 1)
            try encoder.encodeRawBits(0, count: 6)
            #expect(encoder.bitsUsed == 7)
            let result = try q.encodeCoarse(target: [target], previous: [0], intra: true, into: &encoder)
            #expect(!result.intra)
            #expect(result.energies[0] == (target < -0.5 ? -1 : 0))
            let wire = try encoder.finalize()
            #expect(Array(wire) == [target < -0.5 ? 128 : 0])
            #expect(encoder.finalRange == 0x4000_0000)
            var decoder = try OpusRangeDecoder(frame: wire)
            #expect(try decoder.decodeRawBits(count: 6) == 0)
            let decoded = try q.decodeCoarse(previous: [0], from: &decoder)
            #expect(decoded.energies == result.energies)
            #expect(decoder.finalRange == encoder.finalRange && decoder.bitsUsed == encoder.bitsUsed)
        }
    }

    /// Coarse inter prediction clamps history below -9 but intra prediction discards it.
    /// Stereo frequency accumulators remain independent; copies retain no hidden history.
    @Test func predictionAndValueOwnership() throws {
        let q = try CELTEnergyQuantizer(frameSampleCount: 480, channelCount: 2, bandCount: 2)
        var old: [Float] = [-20, 2, -9, -4]
        var encoder = try OpusRangeEncoder(frameByteCount: 32)
        let value = try q.encodeCoarse(target: [0, 3, 0, -2], previous: old, into: &encoder)
        old[0] = 99
        var repeated = try OpusRangeEncoder(frameByteCount: 32)
        let again = try q.encodeCoarse(target: [0, 3, 0, -2], previous: [-9, 2, -9, -4], into: &repeated)
        #expect(value == again)
        #expect(value.energies[0] == value.energies[2])
        #expect(value.energies[1] != value.energies[3])
        #expect(try encoder.finalize() == repeated.finalize())
        var firstIntra = try OpusRangeEncoder(frameByteCount: 32)
        var secondIntra = try OpusRangeEncoder(frameByteCount: 32)
        let independent = try q.encodeCoarse(target: [1, -2, 3, -4], previous: old, intra: true, into: &firstIntra)
        let independentAgain = try q.encodeCoarse(target: [1, -2, 3, -4], previous: [0, 0, 0, 0], intra: true, into: &secondIntra)
        #expect(independent == independentAgain && independent.intra)
        #expect(try firstIntra.finalize() == secondIntra.finalize())
    }

    /// Fine precision/previous precision reject malformed arrays and overflowing integer
    /// values before any raw-bit consumption. Both direction APIs validate identically.
    @Test func fineAllocationValidationIsAtomic() throws {
        let q = try CELTEnergyQuantizer(frameSampleCount: 120, bandCount: 2)
        let state = CELTEnergyEncoding(energies: [0, 0], errors: [0, 0], intra: true)
        var encoder = try OpusRangeEncoder(frameByteCount: 8)
        var decoder = try OpusRangeDecoder(frame: Data(repeating: 0, count: 8))
        for counts in [[], [0], [0, 0, 0], [-1, 0], [9, 0], [Int.min, 0], [Int.max, 0]] {
            #expect(throws: CELTEnergyQuantizerError.invalidBitAllocation) {
                try q.encodeFine(state, bitCounts: counts, into: &encoder)
            }
            #expect(throws: CELTEnergyQuantizerError.invalidBitAllocation) {
                try q.decodeFine(energies: [0, 0], bitCounts: counts, from: &decoder)
            }
            #expect(throws: CELTEnergyQuantizerError.invalidBitAllocation) {
                try q.encodeFine(state, bitCounts: [0, 0], previousBitCounts: counts, into: &encoder)
            }
            #expect(throws: CELTEnergyQuantizerError.invalidBitAllocation) {
                try q.decodeFine(energies: [0, 0], bitCounts: [0, 0], previousBitCounts: counts, from: &decoder)
            }
            #expect(encoder.operationCount == 0 && decoder.operationCount == 0)
        }
        #expect(throws: CELTEnergyQuantizerError.invalidBitAllocation) {
            try q.encodeFine(state, bitCounts: [8, 1], previousBitCounts: [1, 0], into: &encoder)
        }
        #expect(throws: CELTEnergyQuantizerError.invalidBitAllocation) {
            try q.decodeFine(energies: [0, 0], bitCounts: [8, 1], previousBitCounts: [1, 0], from: &decoder)
        }
        for bad in [CELTEnergyEncoding(energies: [], errors: [0, 0], intra: false),
                    CELTEnergyEncoding(energies: [0, 0], errors: [.nan, 0], intra: false)] {
            #expect(throws: CELTEnergyQuantizerError.invalidEnergies) { try q.encodeFine(bad, bitCounts: [0, 0], into: &encoder) }
        }
        #expect(throws: CELTEnergyQuantizerError.invalidEnergies) {
            try q.decodeFine(energies: [], bitCounts: [0, 0], from: &decoder)
        }
        #expect(encoder.operationCount == 0 && decoder.operationCount == 0)
    }

    /// Fine raw fields saturate residual bins at both ends, preserve inactive values and
    /// refine already allocated precision. Zero allocation admits no entropy operation.
    @Test func fineSaturationAndSuccessivePrecision() throws {
        let q = try CELTEnergyQuantizer(frameSampleCount: 120, channelCount: 2, bandCount: 3, startBand: 1)
        let state = CELTEnergyEncoding(energies: [10, 0, 0, -10, 0, 0], errors: [0, -4, 4, 0, 0, -0.125], intra: false)
        var encoder = try OpusRangeEncoder(frameByteCount: 16)
        let refined = try q.encodeFine(state, bitCounts: [8, 2, 1], previousBitCounts: [0, 1, 2], into: &encoder)
        #expect(refined.energies == [10, -0.1875, 0.0625, -10, 0.0625, -0.0625])
        #expect(refined.errors == [0, -3.8125, 3.9375, 0, -0.0625, -0.0625])
        #expect(encoder.operationCount == 4 && encoder.bitsUsed == 7)
        var decoder = try OpusRangeDecoder(frame: encoder.finalize())
        #expect(try q.decodeFine(energies: state.energies, bitCounts: [8, 2, 1],
            previousBitCounts: [0, 1, 2], from: &decoder) == refined.energies)
        var emptyEncoder = try OpusRangeEncoder(frameByteCount: 16)
        #expect(try q.encodeFine(state, bitCounts: [0, 0, 0], into: &emptyEncoder) == state)
        #expect(emptyEncoder.operationCount == 0)
    }

    /// Stereo fine allocation is admitted as a complete channel group: a band needing
    /// eight bits is skipped with seven remaining, then a smaller two-bit band proceeds.
    @Test func fineAdmissionSkipsWholeBands() throws {
        let q = try CELTEnergyQuantizer(frameSampleCount: 120, channelCount: 2, bandCount: 2)
        let state = CELTEnergyEncoding(energies: [0, 0, 0, 0], errors: [0.4, 0.4, -0.4, -0.4], intra: false)
        var encoder = try OpusRangeEncoder(frameByteCount: 1)
        let fine = try q.encodeFine(state, bitCounts: [4, 1], into: &encoder)
        #expect(fine.energies == [0, 0.25, 0, -0.25])
        #expect(encoder.operationCount == 2 && encoder.bitsUsed == 3)
        var decoder = try OpusRangeDecoder(frame: encoder.finalize())
        #expect(try q.decodeFine(energies: state.energies, bitCounts: [4, 1], from: &decoder) == fine.energies)
    }

    /// Final allocation validates fine bits/priorities and caller-provided spare bits,
    /// including Int extremes, before either direction consumes even one raw bit.
    @Test func finalValidationIsAtomic() throws {
        let q = try CELTEnergyQuantizer(frameSampleCount: 120, bandCount: 2)
        let state = CELTEnergyEncoding(energies: [0, 0], errors: [0, 0], intra: false)
        var encoder = try OpusRangeEncoder(frameByteCount: 8)
        var decoder = try OpusRangeDecoder(frame: Data(repeating: 0, count: 8))
        for priorities in [[], [0], [0, 0, 0], [-1, 0], [2, 0], [Int.min, Int.max]] {
            #expect(throws: CELTEnergyQuantizerError.invalidBitAllocation) {
                try q.encodeFinal(state, fineBitCounts: [0, 0], priorities: priorities, remainingBits: 0, into: &encoder)
            }
            #expect(throws: CELTEnergyQuantizerError.invalidBitAllocation) {
                try q.decodeFinal(energies: [0, 0], fineBitCounts: [0, 0], priorities: priorities, remainingBits: 0, from: &decoder)
            }
        }
        for remaining in [Int.min, -1, 64, Int.max] {
            #expect(throws: CELTEnergyQuantizerError.invalidRemainingBits) {
                try q.encodeFinal(state, fineBitCounts: [0, 0], priorities: [0, 1], remainingBits: remaining, into: &encoder)
            }
            #expect(throws: CELTEnergyQuantizerError.invalidRemainingBits) {
                try q.decodeFinal(energies: [0, 0], fineBitCounts: [0, 0], priorities: [0, 1], remainingBits: remaining, from: &decoder)
            }
        }
        #expect(throws: CELTEnergyQuantizerError.invalidBitAllocation) {
            try q.encodeFinal(state, fineBitCounts: [9, 0], priorities: [0, 1], remainingBits: 0, into: &encoder)
        }
        #expect(throws: CELTEnergyQuantizerError.invalidBitAllocation) {
            try q.decodeFinal(energies: [0, 0], fineBitCounts: [9, 0], priorities: [0, 1], remainingBits: 0, from: &decoder)
        }
        for bad in [CELTEnergyEncoding(energies: [], errors: [0, 0], intra: false),
                    CELTEnergyEncoding(energies: [0, 0], errors: [.infinity, 0], intra: false)] {
            #expect(throws: CELTEnergyQuantizerError.invalidEnergies) {
                try q.encodeFinal(bad, fineBitCounts: [0, 0], priorities: [0, 1], remainingBits: 0, into: &encoder)
            }
        }
        #expect(throws: CELTEnergyQuantizerError.invalidEnergies) {
            try q.decodeFinal(energies: [], fineBitCounts: [0, 0], priorities: [0, 1], remainingBits: 0, from: &decoder)
        }
        #expect(encoder.operationCount == 0 && decoder.operationCount == 0)
    }

    /// Final priority zero precedes one, saturated precision is skipped, and an odd
    /// spare bit never partially updates a stereo band. Zero residual chooses positive.
    @Test func finalPrioritiesAndStereoRemainders() throws {
        let q = try CELTEnergyQuantizer(frameSampleCount: 120, channelCount: 2, bandCount: 4)
        let state = CELTEnergyEncoding(energies: Array(repeating: 0, count: 8),
            errors: [0, -1, 1, -1, 0, 1, -1, 1], intra: true)
        var encoder = try OpusRangeEncoder(frameByteCount: 8)
        let final = try q.encodeFinal(state, fineBitCounts: [0, 0, 8, 2], priorities: [1, 0, 0, 0],
            remainingBits: 5, into: &encoder)
        #expect(final.energies == [0, -0.25, 0, -0.0625, 0, 0.25, 0, 0.0625])
        #expect(final.errors == [0, -0.75, 1, -0.9375, 0, 0.75, -1, 0.9375])
        #expect(encoder.operationCount == 4 && final.intra)
        var decoder = try OpusRangeDecoder(frame: encoder.finalize())
        #expect(try q.decodeFinal(energies: state.energies, fineBitCounts: [0, 0, 8, 2], priorities: [1, 0, 0, 0],
            remainingBits: 5, from: &decoder) == final.energies)
        var oneEncoder = try OpusRangeEncoder(frameByteCount: 8)
        #expect(try q.encodeFinal(state, fineBitCounts: [0, 0, 0, 0], priorities: [0, 0, 0, 0],
            remainingBits: 1, into: &oneEncoder) == state)
        #expect(oneEncoder.operationCount == 0)
        var zeroEncoder = try OpusRangeEncoder(frameByteCount: 8)
        let zeroSign = try q.encodeFinal(state, fineBitCounts: [0, 0, 0, 0], priorities: [0, 0, 0, 0],
            remainingBits: 2, into: &zeroEncoder)
        #expect(zeroSign.energies == [0.25, 0, 0, 0, 0.25, 0, 0, 0])
        #expect(zeroSign.errors[0] == -0.25 && zeroSign.errors[4] == -0.25)
        var zeroDecoder = try OpusRangeDecoder(frame: zeroEncoder.finalize())
        #expect(try q.decodeFinal(energies: state.energies, fineBitCounts: [0, 0, 0, 0], priorities: [0, 0, 0, 0],
            remainingBits: 2, from: &zeroDecoder) == zeroSign.energies)
    }

    /// Operation exhaustion propagates for coarse/fine/final entry points in both
    /// directions. Returned arrays are values, so unsuccessful calls cannot mutate
    /// previously returned states; the caller discards the partially consumed frame.
    @Test func entropyFailuresPropagate() throws {
        let q = try CELTEnergyQuantizer(frameSampleCount: 120, bandCount: 2)
        let state = CELTEnergyEncoding(energies: [0, 0], errors: [0, 0], intra: false)
        for kind in 0..<3 {
            var encoder = try OpusRangeEncoder(frameByteCount: 16, maximumOperations: 1)
            try encoder.encodeRawBits(0, count: 0)
            var decoder = try OpusRangeDecoder(frame: Data(repeating: 0, count: 16), maximumOperations: 1)
            _ = try decoder.decodeRawBits(count: 0)
            if kind == 0 {
                #expect(throws: OpusRangeCodingError.operationLimitExceeded) {
                    try q.encodeCoarse(target: [0, 0], previous: [0, 0], into: &encoder)
                }
                #expect(throws: OpusRangeCodingError.operationLimitExceeded) { try q.decodeCoarse(previous: [0, 0], from: &decoder) }
            } else if kind == 1 {
                #expect(throws: OpusRangeCodingError.operationLimitExceeded) { try q.encodeFine(state, bitCounts: [1, 1], into: &encoder) }
                #expect(throws: OpusRangeCodingError.operationLimitExceeded) {
                    try q.decodeFine(energies: [0, 0], bitCounts: [1, 1], from: &decoder)
                }
            } else {
                #expect(throws: OpusRangeCodingError.operationLimitExceeded) {
                    try q.encodeFinal(state, fineBitCounts: [0, 0], priorities: [0, 0], remainingBits: 2, into: &encoder)
                }
                #expect(throws: OpusRangeCodingError.operationLimitExceeded) {
                    try q.decodeFinal(energies: [0, 0], fineBitCounts: [0, 0], priorities: [0, 0], remainingBits: 2, from: &decoder)
                }
            }
        }
        #expect(state.energies == [0, 0] && state.errors == [0, 0])
        var finalized = try OpusRangeEncoder(frameByteCount: 16)
        _ = try finalized.finalize()
        #expect(throws: OpusRangeCodingError.finalized) {
            try q.encodeCoarse(target: [0, 0], previous: [0, 0], into: &finalized)
        }
    }

    /// Extreme admitted log energies saturate to finite Laplace symbols and retain
    /// residuals within the larger refinement bound. All durations/modes/channel counts
    /// can complete fine coding and decode without an integer conversion trap or an
    /// artificial rejection of a state that the same quantizer just produced.
    @Test func coarseBoundaryStatesRemainRefinable() throws {
        for samples in [120, 240, 480, 960] {
            for channels in 1...2 {
                for intra in [false, true] {
                    let q = try CELTEnergyQuantizer(frameSampleCount: samples, channelCount: channels)
                    let target = (0..<(21 * channels)).map { $0.isMultiple(of: 2) ? Float(-32_768) : 32_768 }
                    let previous = target.map { -$0 }
                    var encoder = try OpusRangeEncoder(frameByteCount: 1_275)
                    let coarse = try q.encodeCoarse(target: target, previous: previous, intra: intra,
                        maximumDecay: 128, into: &encoder)
                    #expect(coarse.energies.allSatisfy { $0.isFinite && abs($0) <= 32_768 })
                    #expect(coarse.errors.allSatisfy { $0.isFinite && abs($0) <= 65_536 })
                    let fine = try q.encodeFine(coarse, bitCounts: Array(repeating: 8, count: 21), into: &encoder)
                    var decoder = try OpusRangeDecoder(frame: encoder.finalize())
                    let decodedCoarse = try q.decodeCoarse(previous: previous, from: &decoder)
                    #expect(decodedCoarse.energies == coarse.energies)
                    let decoded = try q.decodeFine(energies: decodedCoarse.energies,
                        bitCounts: Array(repeating: 8, count: 21), from: &decoder)
                    #expect(decoded == fine.energies)
                    #expect(decoder.bitsUsed == encoder.bitsUsed && decoder.finalRange == encoder.finalRange)
                }
            }
        }
    }

    /// Compares bounded float envelopes with the independent oracle's scalar rounding tolerance.
    /// - Parameters:
    ///   - actual: Swift channel-major reconstruction or quantization residual.
    ///   - expected: Unmodified official scalar float oracle output in identical order.
    /// Every value must be finite and agree within 2e-5; lengths must match before indexing.
    private func assertFloats(_ actual: [Float], _ expected: [Float]) {
        #expect(actual.count == expected.count)
        for (a, e) in zip(actual, expected) { #expect(a.isFinite && abs(a - e) <= 2e-5) }
    }
}
