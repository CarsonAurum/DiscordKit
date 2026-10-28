// File: Tests/DiscordVoiceCodecsTests/OpusRangeCodingTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import Foundation
import Testing
@testable import DiscordVoiceCodecs

@Suite("Owned Opus entropy coding")
struct OpusRangeCodingTests {
    /// Compares owned encoding and independent decoding with pinned official libopus output.
    /// Every operation checks exact range and whole/eighth-bit accounting, then final bytes;
    /// this detects paired encoder/decoder defects that a self round trip would miss.
    /// - Parameter fixture: Compact oracle vector with exact contexts and fixed frame length.
    @Test(arguments: OpusEntropyOracleFixtures.all)
    func officialOracle(fixture: OpusEntropyFixture) throws {
        var encoder = try OpusRangeEncoder(frameByteCount: fixture.bytes.count)
        var decoder = try OpusRangeDecoder(frame: Data(fixture.bytes))
        #expect(encoder.bitsUsed == fixture.states[0].bits)
        #expect(encoder.fractionalBitsUsed == fixture.states[0].fractional)
        #expect(decoder.finalRange == fixture.states[0].range)
        for (index, operation) in fixture.operations.enumerated() {
            try encode(operation, using: &encoder)
            try decodeAndExpect(operation, using: &decoder)
            let state = fixture.states[index + 1]
            #expect(encoder.finalRange == state.range)
            #expect(encoder.bitsUsed == state.bits)
            #expect(encoder.fractionalBitsUsed == state.fractional)
            #expect(decoder.finalRange == state.range)
            #expect(decoder.bitsUsed == state.bits)
            #expect(decoder.fractionalBitsUsed == state.fractional)
            #expect(encoder.bitsUsed == (encoder.fractionalBitsUsed + 7) / 8)
            #expect(decoder.operationCount == index + 1)
        }
        let before = (encoder.finalRange, encoder.bitsUsed, encoder.fractionalBitsUsed)
        #expect(try encoder.finalize() == Data(fixture.bytes))
        #expect(encoder.finalRange == before.0 && encoder.bitsUsed == before.1)
        #expect(encoder.fractionalBitsUsed == before.2)
        #expect(encoder.operationCount == fixture.operations.count)
    }

    /// Verifies exact model identity, inverse-CDF conversion, impossible symbols and total limits.
    /// Proportional counts remain distinct because their finite-precision streams may differ.
    @Test func probabilityModels() throws {
        let frequencies = try OpusProbabilityModel(frequencies: [56, 100, 0, 100])
        let inverse = try OpusProbabilityModel(inverseCDF: [200, 100, 100, 0])
        #expect(frequencies == inverse && inverse.total == 256)
        #expect(inverse.frequencies == [56, 100, 0, 100])
        #expect(try OpusProbabilityModel(inverseCDF: [3, 1, 0], precision: 2)
            == OpusProbabilityModel(frequencies: [1, 2, 1]))
        #expect(try OpusProbabilityModel(inverseCDF: [1, 0], precision: 1)
            == OpusProbabilityModel(frequencies: [1, 1]))
        #expect(try OpusProbabilityModel(inverseCDF: Array(repeating: 0, count: 256)).frequencies
            == [256] + Array(repeating: 0, count: 255))
        #expect(try OpusProbabilityModel(frequencies: [1]).total == 1)
        #expect(try OpusProbabilityModel(frequencies: [65_535]).total == 65_535)
        #expect(try OpusProbabilityModel(frequencies: Array(repeating: 1, count: 256)).total == 256)
        #expect(try OpusProbabilityModel(frequencies: [1, 1]) != OpusProbabilityModel(frequencies: [2, 2]))
        var oversizedReservation: [UInt32] = []
        oversizedReservation.reserveCapacity(1_000_000)
        oversizedReservation.append(contentsOf: [2, 3])
        let dense = try OpusProbabilityModel(frequencies: oversizedReservation)
        #expect(dense.frequencies == [2, 3] && dense.frequencies.capacity < 256)
        #expect(oversizedReservation.capacity >= 1_000_000)
        var encoder = try OpusRangeEncoder(frameByteCount: 1)
        var decoder = try OpusRangeDecoder(frame: Data([0]))
        let certain = try OpusProbabilityModel(frequencies: [0, 1, 0])
        try encoder.encodeSymbol(1, model: certain)
        #expect(try decoder.decodeSymbol(model: certain) == 1)
        #expect(encoder.bitsUsed == 1 && decoder.bitsUsed == 1)
        #expect(try encoder.finalize() == Data([0]))
    }

    /// Exercises all 257 symbols needed by the maximum CELT theta context and retains zero
    /// frequencies in a 257-entry inverse CDF. The extra symbol must be a real encodable
    /// index, with matching final range/accounting; the following invalid-model test checks
    /// that 258 entries remain rejected. No whole-codec conformance is implied.
    @Test func maximumThetaProbabilityContext() throws {
        let model = try OpusProbabilityModel(frequencies: Array(repeating: 1, count: 257))
        #expect(model.total == 257 && model.frequencies.count == 257)
        var encoder = try OpusRangeEncoder(frameByteCount: 512)
        for symbol in 0...256 { try encoder.encodeSymbol(symbol, model: model) }
        let range = encoder.finalRange
        let usage = encoder.fractionalBitsUsed
        var decoder = try OpusRangeDecoder(frame: encoder.finalize())
        for symbol in 0...256 { #expect(try decoder.decodeSymbol(model: model) == symbol) }
        #expect(decoder.finalRange == range && decoder.fractionalBitsUsed == usage)
        let inverse = try OpusProbabilityModel(inverseCDF: Array(repeating: 255, count: 256) + [0])
        #expect(inverse.frequencies == [1] + Array(repeating: 0, count: 255) + [255])
        var sparseEncoder = try OpusRangeEncoder(frameByteCount: 4)
        try sparseEncoder.encodeSymbol(256, model: inverse)
        #expect(throws: OpusRangeCodingError.invalidSymbol) {
            try sparseEncoder.encodeSymbol(255, model: inverse)
        }
        #expect(sparseEncoder.operationCount == 1)
        var sparseDecoder = try OpusRangeDecoder(frame: sparseEncoder.finalize())
        #expect(try sparseDecoder.decodeSymbol(model: inverse) == 256)
    }

    /// Covers every malformed probability-table category without allocating unbounded context state.
    @Test func invalidProbabilityModels() {
        let tables: [[UInt32]] = [[], [0], [0, 0], [65_536], [.max], [65_535, 1], Array(repeating: 1, count: 258)]
        for table in tables {
            #expect(throws: OpusRangeCodingError.invalidProbabilityModel) {
                try OpusProbabilityModel(frequencies: table)
            }
        }
        let inverseTables: [([UInt8], Int)] = [([], 8), ([0], 0), ([0], 9), ([1], 8),
            ([4, 0], 2), ([1, 2, 0], 8), (Array(repeating: 0, count: 258), 8)]
        for (table, precision) in inverseTables {
            #expect(throws: OpusRangeCodingError.invalidProbabilityModel) {
                try OpusProbabilityModel(inverseCDF: table, precision: precision)
            }
        }
    }

    /// Exercises constructor bounds and validates dense ownership of sliced frame data.
    @Test func constructionAndSlicedFrames() throws {
        for count in [-1, 1_276, .max] {
            #expect(throws: OpusRangeCodingError.invalidFrameByteCount) {
                try OpusRangeEncoder(frameByteCount: count)
            }
        }
        #expect(throws: OpusRangeCodingError.invalidFrameByteCount) {
            try OpusRangeDecoder(frame: Data(repeating: 0, count: 1_276))
        }
        for limit in [-1, 0, 1_000_001, .max] {
            #expect(throws: OpusRangeCodingError.invalidMaximumOperations) {
                try OpusRangeEncoder(frameByteCount: 0, maximumOperations: limit)
            }
            #expect(throws: OpusRangeCodingError.invalidMaximumOperations) {
                try OpusRangeDecoder(frame: Data(), maximumOperations: limit)
            }
        }
        var backing = Data([9, 9, 0xab, 9])
        let slice = backing[2..<3]
        var decoder = try OpusRangeDecoder(frame: slice, maximumOperations: 1_000_000)
        backing[2] = 0
        #expect(decoder.frame == Data([0xab]) && decoder.frame.startIndex == 0)
        #expect(try decoder.decodeBit(logProbability: 1))
        #expect(try decoder.decodeRawBits(count: 6) == 43)
        let encoder = try OpusRangeEncoder(frameByteCount: 1_275, maximumOperations: 1_000_000)
        #expect(encoder.frameByteCount == 1_275 && encoder.maximumOperations == 1_000_000)
        #expect(decoder.maximumOperations == 1_000_000)
    }

    /// Proves argument failures leave stream accounting and operation admission unchanged.
    @Test func invalidCodingArgumentsPreserveState() throws {
        var encoder = try OpusRangeEncoder(frameByteCount: 32)
        var decoder = try OpusRangeDecoder(frame: Data(repeating: 0, count: 32))
        let model = try OpusProbabilityModel(frequencies: [1, 0, 1])
        for symbol in [-1, 1, 3, .max] {
            #expect(throws: OpusRangeCodingError.invalidSymbol) { try encoder.encodeSymbol(symbol, model: model) }
        }
        for exponent in [-1, 0, 16, .max] {
            #expect(throws: OpusRangeCodingError.invalidLogProbability) {
                try encoder.encodeBit(false, logProbability: exponent)
            }
            #expect(throws: OpusRangeCodingError.invalidLogProbability) {
                try decoder.decodeBit(logProbability: exponent)
            }
        }
        for count in [-1, 26, .max] {
            #expect(throws: OpusRangeCodingError.invalidRawBitCount) { try encoder.encodeRawBits(0, count: count) }
            #expect(throws: OpusRangeCodingError.invalidRawBitCount) { try decoder.decodeRawBits(count: count) }
        }
        for (value, count): (UInt32, Int) in [(1, 0), (2, 1), (1 << 25, 25), (.max, 25)] {
            #expect(throws: OpusRangeCodingError.invalidRawValue) { try encoder.encodeRawBits(value, count: count) }
        }
        for total: UInt32 in [0, 1] {
            #expect(throws: OpusRangeCodingError.invalidUniformTotal) { try encoder.encodeUniform(0, total: total) }
            #expect(throws: OpusRangeCodingError.invalidUniformTotal) { try decoder.decodeUniform(total: total) }
        }
        for (value, total): (UInt32, UInt32) in [(2, 2), (4, 3), (.max, .max)] {
            #expect(throws: OpusRangeCodingError.invalidUniformValue) { try encoder.encodeUniform(value, total: total) }
        }
        #expect(encoder.operationCount == 0 && decoder.operationCount == 0)
        #expect(encoder.bitsUsed == 1 && decoder.bitsUsed == 1)
        #expect(encoder.finalRange == 0x8000_0000 && decoder.finalRange == 0x8000_0000)
        try encoder.encodeBit(false, logProbability: 1)
        #expect(try decoder.decodeBit(logProbability: 1) == false)
        #expect(try encoder.finalize() == Data(repeating: 0, count: 32))
    }

    /// Bounds probability-one and zero-bit calls even when they consume no entropy budget.
    @Test func operationLimitsAndFinalization() throws {
        var encoder = try OpusRangeEncoder(frameByteCount: 1, maximumOperations: 2)
        var decoder = try OpusRangeDecoder(frame: Data([0]), maximumOperations: 2)
        let model = try OpusProbabilityModel(frequencies: [1])
        try encoder.encodeSymbol(0, model: model)
        try encoder.encodeRawBits(0, count: 0)
        #expect(try decoder.decodeSymbol(model: model) == 0)
        #expect(try decoder.decodeRawBits(count: 0) == 0)
        #expect(throws: OpusRangeCodingError.operationLimitExceeded) { try encoder.encodeBit(false, logProbability: 1) }
        #expect(throws: OpusRangeCodingError.operationLimitExceeded) { try decoder.decodeBit(logProbability: 1) }
        #expect(encoder.operationCount == 2 && decoder.operationCount == 2)
        #expect(encoder.bitsUsed == 1 && decoder.bitsUsed == 1)
        #expect(try encoder.finalize() == Data([0]))
        #expect(throws: OpusRangeCodingError.finalized) { try encoder.finalize() }
        #expect(throws: OpusRangeCodingError.finalized) { try encoder.encodeRawBits(0, count: 0) }
        #expect(throws: OpusRangeCodingError.finalized) { try encoder.encodeSymbol(0, model: model) }
        #expect(throws: OpusRangeCodingError.finalized) { try encoder.encodeUniform(0, total: 2) }
    }

    /// Rejects whole-frame raw overflow and conservative combined-bit exhaustion, then fails closed.
    @Test func encoderBudgetFailures() throws {
        var raw = try OpusRangeEncoder(frameByteCount: 1)
        #expect(throws: OpusRangeCodingError.frameBudgetExceeded) { try raw.encodeRawBits(0, count: 9) }
        #expect(throws: OpusRangeCodingError.unusableState) { try raw.finalize() }
        #expect(throws: OpusRangeCodingError.unusableState) { try raw.encodeBit(false, logProbability: 1) }
        var combined = try OpusRangeEncoder(frameByteCount: 1)
        #expect(throws: OpusRangeCodingError.frameBudgetExceeded) { try combined.encodeRawBits(0, count: 8) }
        #expect(throws: OpusRangeCodingError.unusableState) { try combined.finalize() }
        var arithmetic = try OpusRangeEncoder(frameByteCount: 0)
        #expect(throws: OpusRangeCodingError.frameBudgetExceeded) { try arithmetic.encodeBit(true, logProbability: 15) }
        #expect(throws: OpusRangeCodingError.unusableState) { try arithmetic.finalize() }
        var resolvedBytes = try OpusRangeEncoder(frameByteCount: 0)
        let rare = try OpusProbabilityModel(frequencies: [1, 65_534])
        #expect(throws: OpusRangeCodingError.frameBudgetExceeded) { try resolvedBytes.encodeSymbol(0, model: rare) }
        #expect(throws: OpusRangeCodingError.unusableState) { try resolvedBytes.finalize() }
        var empty = try OpusRangeEncoder(frameByteCount: 0)
        try empty.encodeRawBits(0, count: 0)
        try empty.encodeSymbol(0, model: OpusProbabilityModel(frequencies: [1]))
        #expect(try empty.finalize().isEmpty)
    }

    /// Verifies empty-frame entropy zero extension and explicit rejection of impossible raw fields.
    /// Exhaustion never reads bytes belonging to another packet frame or backing Data prefix/suffix.
    @Test func decoderZeroExtensionAndBudgetFailures() throws {
        var empty = try OpusRangeDecoder(frame: Data(), maximumOperations: 32)
        for _ in 0..<16 {
            #expect(try empty.decodeBit(logProbability: 15) == false)
        }
        #expect(empty.bitsUsed >= 1 && empty.frame.isEmpty)
        #expect(throws: OpusRangeCodingError.frameBudgetExceeded) { try empty.decodeRawBits(count: 1) }
        #expect(throws: OpusRangeCodingError.unusableState) { try empty.decodeBit(logProbability: 1) }
        var split = try OpusRangeDecoder(frame: Data())
        #expect(throws: OpusRangeCodingError.frameBudgetExceeded) { try split.decodeUniform(total: .max) }
        #expect(throws: OpusRangeCodingError.unusableState) { try split.decodeRawBits(count: 0) }
        var actual = try OpusRangeDecoder(frame: Data([0xff]))
        #expect(try actual.decodeRawBits(count: 8) == 255)
        #expect(throws: OpusRangeCodingError.frameBudgetExceeded) { try actual.decodeRawBits(count: 1) }
        var repeatedlyExtended = try OpusRangeDecoder(frame: Data(), maximumOperations: 64)
        for _ in 0..<64 { #expect(try repeatedlyExtended.decodeBit(logProbability: 1) == false) }
        #expect(repeatedlyExtended.bitsUsed == 65 && repeatedlyExtended.operationCount == 64)
    }

    /// Detects an unused large-uniform split codepoint instead of returning an out-of-domain value.
    @Test func corruptUniformValue() throws {
        var decoder = try OpusRangeDecoder(frame: Data([255, 255]))
        #expect(throws: OpusRangeCodingError.corruptUniformValue) { try decoder.decodeUniform(total: 257) }
        #expect(decoder.operationCount == 1)
        #expect(throws: OpusRangeCodingError.unusableState) { try decoder.decodeUniform(total: 2) }
    }

    /// Exhausts all raw widths and extreme values, including overlap with arithmetic read-ahead.
    /// - Parameter count: Valid raw-field width in `0...25`, including zero and the maximum.
    @Test(arguments: 0...25)
    func rawWidths(count: Int) throws {
        let maximum = (UInt32(1) << count) - 1
        for value in [UInt32(0), maximum, maximum / 2] {
            var encoder = try OpusRangeEncoder(frameByteCount: 8)
            try encoder.encodeRawBits(value, count: count)
            let frame = try encoder.finalize()
            var decoder = try OpusRangeDecoder(frame: frame)
            #expect(try decoder.decodeRawBits(count: count) == value)
            #expect(encoder.bitsUsed == count + 1 && decoder.bitsUsed == count + 1)
            #expect(encoder.fractionalBitsUsed == (count + 1) * 8)
            #expect(decoder.finalRange == encoder.finalRange)
        }
    }

    /// Exhausts valid binary exponents in both branches and matches their equivalent exact contexts.
    /// - Parameter exponent: Valid logarithmic true-probability exponent in `1...15`.
    @Test(arguments: 1...15)
    func binaryContexts(exponent: Int) throws {
        let total = UInt32(1) << exponent
        let model = try OpusProbabilityModel(frequencies: [total - 1, 1])
        var specialized = try OpusRangeEncoder(frameByteCount: 8)
        var general = try OpusRangeEncoder(frameByteCount: 8)
        for bit in [false, true, false] {
            try specialized.encodeBit(bit, logProbability: exponent)
            try general.encodeSymbol(bit ? 1 : 0, model: model)
            #expect(specialized.finalRange == general.finalRange)
            #expect(specialized.fractionalBitsUsed == general.fractionalBitsUsed)
        }
        let bytes = try specialized.finalize()
        #expect(try general.finalize() == bytes)
        var decoder = try OpusRangeDecoder(frame: bytes)
        for bit in [false, true, false] { #expect(try decoder.decodeBit(logProbability: exponent) == bit) }
    }

    /// Exercises exact total/split boundaries with low/high values and per-step range agreement.
    /// - Parameter total: Boundary total spanning direct contexts and large raw-bit splits.
    @Test(arguments: [UInt32(2), 3, 255, 256, 257, 511, 512, 65_535, 65_536, 65_537, .max])
    func uniformBoundaries(total: UInt32) throws {
        var encoder = try OpusRangeEncoder(frameByteCount: 32)
        let values: [UInt32] = [0, total / 2, total - 1]
        for value in values { try encoder.encodeUniform(value, total: total) }
        let frame = try encoder.finalize()
        var decoder = try OpusRangeDecoder(frame: frame)
        for value in values { #expect(try decoder.decodeUniform(total: total) == value) }
        #expect(decoder.finalRange == encoder.finalRange)
        #expect(decoder.bitsUsed == encoder.bitsUsed)
        #expect(decoder.fractionalBitsUsed == encoder.fractionalBitsUsed)
    }

    /// Fills the maximum frame to its last usable raw bit and checks the explicit bit pattern.
    /// The initial termination reserve leaves 10,199 raw bits in a 1,275-byte frame.
    @Test func maximumFrameAndValueOwnership() throws {
        var encoder = try OpusRangeEncoder(frameByteCount: 1_275)
        for _ in 0..<407 { try encoder.encodeRawBits((1 << 25) - 1, count: 25) }
        try encoder.encodeRawBits((1 << 24) - 1, count: 24)
        let frame = try encoder.finalize()
        #expect(frame.count == 1_275 && frame.first == 127)
        #expect(frame.dropFirst().allSatisfy { $0 == 255 })
        #expect(encoder.bitsUsed == 10_200)
        var decoder = try OpusRangeDecoder(frame: frame)
        for _ in 0..<407 { #expect(try decoder.decodeRawBits(count: 25) == (1 << 25) - 1) }
        #expect(try decoder.decodeRawBits(count: 24) == (1 << 24) - 1)
        #expect(decoder.bitsUsed == encoder.bitsUsed)
        var first = try OpusRangeEncoder(frameByteCount: 1)
        var second = first
        try first.encodeBit(false, logProbability: 1)
        try second.encodeBit(true, logProbability: 1)
        #expect(try first.finalize() == Data([0]))
        #expect(try second.finalize() == Data([128]))
        var originalDecoder = try OpusRangeDecoder(frame: Data([128]))
        var copiedDecoder = originalDecoder
        #expect(try originalDecoder.decodeBit(logProbability: 1))
        #expect(copiedDecoder.operationCount == 0 && copiedDecoder.bitsUsed == 1)
        #expect(try copiedDecoder.decodeBit(logProbability: 1))
    }

    /// Codes deterministic mixed streams through every context API without clocks or global randomness.
    /// Different frame sizes exercise termination boundaries, raw overlap and long carry histories.
    @Test func deterministicMixedStreams() throws {
        for seed in 1...64 {
            var generator = UInt32(seed)
            var operations: [OpusEntropyOperation] = []
            for index in 0..<64 {
                generator = generator &* 1_664_525 &+ 1_013_904_223
                switch index % 4 {
                case 0: operations.append(.symbol(Int(generator % 4), [1, 3, 5, 7]))
                case 1: operations.append(.bit(generator & 1 == 1, Int(generator % 15) + 1))
                case 2: operations.append(.uniform(generator % 65_537, 65_537))
                default: operations.append(.raw(generator & 0x1fff, 13))
                }
            }
            var encoder = try OpusRangeEncoder(frameByteCount: 128)
            for operation in operations { try encode(operation, using: &encoder) }
            let frame = try encoder.finalize()
            var decoder = try OpusRangeDecoder(frame: frame)
            for operation in operations { try decodeAndExpect(operation, using: &decoder) }
            #expect(decoder.finalRange == encoder.finalRange)
            #expect(decoder.fractionalBitsUsed == encoder.fractionalBitsUsed)
        }
    }

    /// Dispatches one fixture operation through its public encoder API.
    /// - Parameters:
    ///   - operation: Model/symbol, binary, uniform or raw-bit operation to encode.
    ///   - encoder: Caller-owned mutable stream, advanced only through the selected API.
    /// - Throws: Model validation or encoder errors, failing the fixture test immediately.
    private func encode(_ operation: OpusEntropyOperation, using encoder: inout OpusRangeEncoder) throws {
        switch operation {
        case .symbol(let symbol, let frequencies):
            try encoder.encodeSymbol(symbol, model: OpusProbabilityModel(frequencies: frequencies))
        case .bit(let value, let exponent): try encoder.encodeBit(value, logProbability: exponent)
        case .uniform(let value, let total): try encoder.encodeUniform(value, total: total)
        case .raw(let value, let count): try encoder.encodeRawBits(value, count: count)
        }
    }

    /// Decodes a fixture operation and asserts its expected public semantic value.
    /// - Parameters:
    ///   - operation: Matching encoder context and expected value.
    ///   - decoder: Caller-owned stream, advanced once by the matching public API.
    /// - Throws: Model validation or decoder errors, failing the fixture test immediately.
    private func decodeAndExpect(_ operation: OpusEntropyOperation, using decoder: inout OpusRangeDecoder) throws {
        switch operation {
        case .symbol(let symbol, let frequencies):
            #expect(try decoder.decodeSymbol(model: OpusProbabilityModel(frequencies: frequencies)) == symbol)
        case .bit(let value, let exponent): #expect(try decoder.decodeBit(logProbability: exponent) == value)
        case .uniform(let value, let total): #expect(try decoder.decodeUniform(total: total) == value)
        case .raw(let value, let count): #expect(try decoder.decodeRawBits(count: count) == value)
        }
    }
}
