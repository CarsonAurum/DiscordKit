// File: Tests/DiscordVoiceCodecsTests/CELTBandQuantizerTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import Foundation
import Testing
@testable import DiscordVoiceCodecs

@Suite("CELT single-band quantization")
struct CELTBandQuantizerTests {
    /// Independent serialized contexts/results from unmodified libopus 1.6.1 scalar float code.
    private struct Fixture: Decodable {
        let input: Input
        let output: Output
        struct Input: Decodable {
            let n: Int
            let k: Int
            let blocks: Int
            let spread: Int
            let gain: Float
            let x: [Float]
        }
        struct Output: Decodable {
            let mask: UInt8
            let decodedMask: UInt8
            let range: UInt32
            let decodedRange: UInt32
            let pulses: [Int]
            let coefficients: [Float]
            let decoded: [Float]
            let bytes: [UInt8]
        }
    }

    /// Checks all spreading levels, dense/sparse pulses, secondary rotations, silence fallback,
    /// extreme gains and 1/2/4/8 short blocks against independently compiled official code.
    /// Exact pulse/entropy/range/mask agreement prevents an internally invertible substitute;
    /// spectral floats use a gain-scaled tolerance. This is not decoded-PCM conformance.
    @Test func officialBandOracle() throws {
        let fixtures = try JSONDecoder().decode([Fixture].self, from: Data(CELTBandOracleFixtures.json.utf8))
        #expect(fixtures.count == 16)
        for fixture in fixtures {
            let input = fixture.input
            let expected = fixture.output
            let quantizer = try CELTBandQuantizer(dimensions: input.n, pulseCount: input.k,
                shortBlockCount: input.blocks, spreading: #require(CELTSpreading(rawValue: input.spread)))
            #expect(quantizer.dimensions == input.n && quantizer.pulseCount == input.k)
            #expect(quantizer.shortBlockCount == input.blocks && quantizer.spreading.rawValue == input.spread)
            let searched = try quantizer.quantize(input.x, gain: input.gain)
            var encoder = try OpusRangeEncoder(frameByteCount: 8)
            let encoded = try quantizer.encode(input.x, gain: input.gain, into: &encoder)
            #expect(searched == encoded)
            #expect(encoded.pulses == expected.pulses)
            #expect(encoded.pulses.reduce(0) { $0 + abs($1) } == input.k)
            #expect(encoded.collapseMask == expected.mask)
            #expect(Array(try encoder.finalize()) == expected.bytes)
            #expect(encoder.finalRange == expected.range)
            var decoder = try OpusRangeDecoder(frame: Data(expected.bytes))
            let decoded = try quantizer.decode(from: &decoder, gain: input.gain)
            #expect(decoded == encoded)
            #expect(decoded.collapseMask == expected.decodedMask)
            #expect(decoder.finalRange == expected.decodedRange)
            for index in 0..<input.n {
                #expect(abs(encoded.coefficients[index] - expected.coefficients[index]) <= 2e-6 * max(1, input.gain))
                #expect(abs(decoded.coefficients[index] - expected.decoded[index]) <= 2e-6 * max(1, input.gain))
            }
            let energy = encoded.coefficients.reduce(0.0) { $0 + Double($1) * Double($1) }
            #expect(abs(energy - Double(input.gain) * Double(input.gain)) <= 2e-5 * max(1, Double(input.gain) * Double(input.gain)))
        }
    }

    /// Rejects configuration extremes before allocating a codebook or calculating unsafe divisors.
    @Test func invalidConfiguration() throws {
        for n in [Int.min, -1, 0, 1, 177, Int.max] {
            #expect(throws: CELTBandQuantizerError.invalidDimensions) {
                try CELTBandQuantizer(dimensions: n, pulseCount: 1)
            }
        }
        for k in [Int.min, -1, 0, 129, Int.max] {
            #expect(throws: CELTBandQuantizerError.invalidPulseCount) {
                try CELTBandQuantizer(dimensions: 8, pulseCount: k)
            }
        }
        for blocks in [Int.min, -1, 0, 3, 5, 16, Int.max] {
            #expect(throws: CELTBandQuantizerError.invalidBlockCount) {
                try CELTBandQuantizer(dimensions: 8, pulseCount: 1, shortBlockCount: blocks)
            }
        }
        #expect(throws: CELTBandQuantizerError.invalidBlockCount) {
            try CELTBandQuantizer(dimensions: 3, pulseCount: 1, shortBlockCount: 2)
        }
        #expect(throws: CELTPulseCodebookError.codebookTooLarge) {
            try CELTBandQuantizer(dimensions: 176, pulseCount: 128)
        }
        #expect(CELTSpreading.allCases.map(\.rawValue) == [0, 1, 2, 3])
    }

    /// Invalid shape/norm/finite values leave the caller's usable entropy encoder unchanged.
    /// Empty/extra arrays are checked before access; negative zero remains a legal zero band.
    @Test func invalidCoefficientsDoNotConsumeEntropy() throws {
        let q = try CELTBandQuantizer(dimensions: 2, pulseCount: 3)
        var encoder = try OpusRangeEncoder(frameByteCount: 8)
        for values: [Float] in [[], [0], [0, 0, 0], [1, 1], [.nan, 0], [.infinity, 0],
                               [-.infinity, 0], [.greatestFiniteMagnitude, 0]] {
            #expect(throws: CELTBandQuantizerError.invalidCoefficients) { try q.quantize(values) }
            #expect(throws: CELTBandQuantizerError.invalidCoefficients) { try q.encode(values, into: &encoder) }
            #expect(encoder.operationCount == 0)
        }
        #expect(try q.quantize([-0.0, 0.0]).pulses == [3, 0])
    }

    /// Gain validation is atomic for both entropy directions and the standalone search.
    /// A later valid call proves rejected arguments do not close or otherwise consume owners.
    @Test func invalidGainPreservesEncoderAndDecoder() throws {
        let q = try CELTBandQuantizer(dimensions: 4, pulseCount: 2)
        var encoder = try OpusRangeEncoder(frameByteCount: 8)
        var decoder = try OpusRangeDecoder(frame: Data(repeating: 0, count: 8))
        for gain: Float in [-1, 65, .nan, .infinity, -.infinity] {
            #expect(throws: CELTBandQuantizerError.invalidGain) { try q.quantize([1, 0, 0, 0], gain: gain) }
            #expect(throws: CELTBandQuantizerError.invalidGain) { try q.encode([1, 0, 0, 0], gain: gain, into: &encoder) }
            #expect(throws: CELTBandQuantizerError.invalidGain) { try q.decode(from: &decoder, gain: gain) }
            #expect(encoder.operationCount == 0 && decoder.operationCount == 0)
        }
        #expect(try q.encode([1, 0, 0, 0], into: &encoder).pulses == [2, 0, 0, 0])
        #expect(try q.decode(from: &decoder).pulses == [2, 0, 0, 0])
    }

    /// Shows gain never affects pulse selection, sparse occupancy is measured before spreading,
    /// independent repeated calls agree, and returned values own their pulse/float storage.
    @Test func deterministicTiesAndGainIndependence() throws {
        let q = try CELTBandQuantizer(dimensions: 4, pulseCount: 1, shortBlockCount: 4, spreading: .none)
        let first = try q.quantize([0.5, 0.5, -0.5, -0.5])
        #expect(first.pulses == [1, 0, 0, 0] && first.collapseMask == 1)
        #expect(first.coefficients == [1, 0, 0, 0])
        let silentGain = try q.quantize([0.5, 0.5, -0.5, -0.5], gain: 0)
        #expect(silentGain.pulses == first.pulses && silentGain.collapseMask == first.collapseMask)
        #expect(silentGain.coefficients == [0, 0, 0, 0])
        #expect(try q.quantize([0.5, 0.5, -0.5, -0.5]) == first)
        var source: [Float] = [0, 0, 0, -1]
        let last = try q.quantize(source, gain: 64)
        source[3] = 1
        #expect(last.pulses == [0, 0, 0, -1] && last.collapseMask == 8)
        #expect(last.coefficients == [0, 0, 0, -64])
    }

    /// Propagates existing closed/exhausted entropy failures without inventing partial packets.
    /// The quantizer itself is immutable and remains usable after either owner's failure.
    @Test func entropyErrorsPropagate() throws {
        let q = try CELTBandQuantizer(dimensions: 2, pulseCount: 1)
        var encoder = try OpusRangeEncoder(frameByteCount: 8, maximumOperations: 1)
        _ = try q.encode([1, 0], into: &encoder)
        #expect(throws: OpusRangeCodingError.operationLimitExceeded) { try q.encode([0, 1], into: &encoder) }
        var decoder = try OpusRangeDecoder(frame: Data(repeating: 0, count: 8), maximumOperations: 1)
        _ = try q.decode(from: &decoder)
        #expect(throws: OpusRangeCodingError.operationLimitExceeded) { try q.decode(from: &decoder) }
        #expect(try q.quantize([0, -1]).pulses == [0, -1])
    }
}
