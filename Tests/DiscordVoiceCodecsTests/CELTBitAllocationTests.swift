import Foundation
@testable import DiscordVoiceCodecs
import Testing

/// Exact independent ordinary allocation/entropy fixtures plus malformed-input and atomicity regressions.
@Suite("CELT ordinary bit allocation")
struct CELTBitAllocationTests {
    /// Independent C fixtures check all allocation fields and arbitrary-byte decoding without trusting round trips.
    @Test func officialAllocationAndArbitraryDecoderFixtures() throws {
        let records = try JSONDecoder().decode([AllocationFixture].self, from: Data(CELTAllocationOracleFixtures.json.utf8))
        #expect(records.count == 97)
        for record in records {
            let x = record.input
            let e = record.output
            let allocation = try CELTBitAllocation(frameSampleCount: 120 << x.lm, channelCount: x.c,
                startBand: x.start, endBand: x.end, allocationTrim: x.trim)
            #expect(allocation.bandCaps == e.caps)
            var encoder = try OpusRangeEncoder(frameByteCount: x.bytes)
            if x.prefix > 0 { try encoder.encodeRawBits(0, count: x.prefix) }
            let encoded = try allocation.encode(totalEighthBits: x.total, dynamicOffsets: x.offsets,
                codedBandLimit: e.encoded.coded, intensityBand: x.intensity, dualStereo: x.dual, into: &encoder)
            assertAllocation(encoded, equals: e.encoded)
            #expect(encoder.finalRange == e.encoded.range)
            #expect(encoder.bitsUsed == e.encoded.bits && encoder.fractionalBitsUsed == e.encoded.frac)
            let wire = try encoder.finalize()
            #expect(Array(wire) == e.bytes)
            var decoder = try OpusRangeDecoder(frame: Data(e.bytes))
            if x.prefix > 0 { _ = try decoder.decodeRawBits(count: x.prefix) }
            let decoded = try allocation.decode(totalEighthBits: x.total, dynamicOffsets: x.offsets, from: &decoder)
            assertAllocation(decoded, equals: e.decoded)
            #expect(decoded == encoded)
            #expect(decoder.finalRange == e.decoded.range)
            #expect(decoder.bitsUsed == e.decoded.bits && decoder.fractionalBitsUsed == e.decoded.frac)
            var arbitrary = try OpusRangeDecoder(frame: Data(x.arbitrary))
            if x.prefix > 0 { _ = try arbitrary.decodeRawBits(count: x.prefix) }
            let arbitraryResult = try allocation.decode(totalEighthBits: x.total, dynamicOffsets: x.offsets, from: &arbitrary)
            assertAllocation(arbitraryResult, equals: e.arbitrary)
            #expect(arbitrary.finalRange == e.arbitrary.range)
            #expect(arbitrary.bitsUsed == e.arbitrary.bits && arbitrary.fractionalBitsUsed == e.arbitrary.frac)
            #expect(encoded.shapeEighthBits.allSatisfy { $0 >= 0 })
            #expect(encoded.fineEnergyBits.allSatisfy { (0...8).contains($0) })
            #expect(encoded.finePriorities.allSatisfy { $0 == 0 || $0 == 1 })
            #expect(encoded.shapeEighthBits.reduce(0, +) + x.c * 8 * encoded.fineEnergyBits.reduce(0, +)
                    + encoded.balanceEighthBits <= max(0, x.total))
            for band in 0..<21 where band < x.start || band >= x.end {
                #expect(encoded.shapeEighthBits[band] == 0 && encoded.fineEnergyBits[band] == 0)
                #expect(encoded.finePriorities[band] == 0)
            }
        }
    }

    /// All modes/trims/ranges accept exact valid bounds and reject integer extremes before indexing/shifting.
    @Test func configurationValidationAndStandardCaps() throws {
        for size in [Int.min, -1, 0, 119, 121, 1920, Int.max] {
            #expect(throws: CELTBitAllocationError.invalidFrameSize) { try CELTBitAllocation(frameSampleCount: size) }
        }
        for channels in [Int.min, -1, 0, 3, Int.max] {
            #expect(throws: CELTBitAllocationError.invalidChannelCount) {
                try CELTBitAllocation(frameSampleCount: 120, channelCount: channels)
            }
        }
        for (start, end) in [(Int.min, 21), (-1, 21), (0, 0), (20, 20), (21, 21), (0, 22), (0, Int.max), (Int.max, Int.min)] {
            #expect(throws: CELTBitAllocationError.invalidBandRange) {
                try CELTBitAllocation(frameSampleCount: 120, startBand: start, endBand: end)
            }
        }
        for trim in [Int.min, -1, 11, Int.max] {
            #expect(throws: CELTBitAllocationError.invalidTrim) {
                try CELTBitAllocation(frameSampleCount: 120, allocationTrim: trim)
            }
        }
        let mono = try CELTBitAllocation(frameSampleCount: 120)
        #expect(mono.bandCaps.count == 21 && mono.bandCaps[0] == 72 && mono.bandCaps[20] == 555)
        let stereo = try CELTBitAllocation(frameSampleCount: 960, channelCount: 2, startBand: 20, allocationTrim: 10)
        #expect(stereo.frameSampleCount == 960 && stereo.channelCount == 2)
        #expect(stereo.startBand == 20 && stereo.endBand == 21 && stereo.allocationTrim == 10)
        #expect(stereo.bandCaps[20] == 9152)
    }

    /// Negative/zero budgets preserve empty entropy and force the last retained band without stereo symbols.
    /// - Parameter budget: Extreme negative, negative-one or zero budget to normalize before allocation.
    @Test(arguments: [Int.min, -1, 0])
    func emptyAndNegativeBudgetClamping(_ budget: Int) throws {
        let allocation = try CELTBitAllocation(frameSampleCount: 120, channelCount: 2, startBand: 17)
        var encoder = try OpusRangeEncoder(frameByteCount: 0)
        let result = try allocation.encode(totalEighthBits: budget, codedBandLimit: 21,
            intensityBand: 20, dualStereo: true, into: &encoder)
        #expect(result.codedBandEnd == 18 && result.intensityBand == 0 && !result.dualStereo)
        #expect(result.shapeEighthBits == Array(repeating: 0, count: 21))
        #expect(result.fineEnergyBits == Array(repeating: 0, count: 21))
        #expect(result.balanceEighthBits == 0)
        #expect(encoder.operationCount == 0 && encoder.bitsUsed == 1 && encoder.fractionalBitsUsed == 8)
        let wire = try encoder.finalize()
        #expect(wire.isEmpty)
        var decoder = try OpusRangeDecoder(frame: wire)
        #expect(try allocation.decode(totalEighthBits: budget, from: &decoder) == result)
        #expect(decoder.operationCount == 0 && decoder.bitsUsed == 1)
    }

    /// Invalid boosts/budgets/choices are rejected atomically; unused boost entries are validated but ignored.
    @Test func inputValidationPreservesBothCoders() throws {
        let allocation = try CELTBitAllocation(frameSampleCount: 120, channelCount: 2, startBand: 17)
        var encoder = try OpusRangeEncoder(frameByteCount: 16)
        var decoder = try OpusRangeDecoder(frame: Data(repeating: 0x5a, count: 16))
        for count in [0, 1, 20, 22, 128] {
            let offsets = Array(repeating: 0, count: count)
            #expect(throws: CELTBitAllocationError.invalidOffsets) {
                try allocation.encode(totalEighthBits: 1024, dynamicOffsets: offsets, into: &encoder)
            }
            #expect(throws: CELTBitAllocationError.invalidOffsets) {
                try allocation.decode(totalEighthBits: 1024, dynamicOffsets: offsets, from: &decoder)
            }
        }
        for invalid in [Int.min, -1, 81_601, Int.max] {
            var offsets = Array(repeating: 0, count: 21)
            offsets[0] = invalid // Inactive storage still has to satisfy the declared finite bounds.
            #expect(throws: CELTBitAllocationError.invalidOffsets) {
                try allocation.encode(totalEighthBits: 1024, dynamicOffsets: offsets, into: &encoder)
            }
            #expect(throws: CELTBitAllocationError.invalidOffsets) {
                try allocation.decode(totalEighthBits: 1024, dynamicOffsets: offsets, from: &decoder)
            }
        }
        for budget in [81_601, Int.max] {
            #expect(throws: CELTBitAllocationError.invalidBudget) { try allocation.encode(totalEighthBits: budget, into: &encoder) }
            #expect(throws: CELTBitAllocationError.invalidBudget) { try allocation.decode(totalEighthBits: budget, from: &decoder) }
        }
        for end in [Int.min, 0, 17, 22, Int.max] {
            #expect(throws: CELTBitAllocationError.invalidCodedBandLimit) {
                try allocation.encode(totalEighthBits: 1024, codedBandLimit: end, into: &encoder)
            }
        }
        for intensity in [Int.min, 0, 16, 22, Int.max] {
            #expect(throws: CELTBitAllocationError.invalidIntensity) {
                try allocation.encode(totalEighthBits: 1024, intensityBand: intensity, into: &encoder)
            }
        }
        #expect(encoder.operationCount == 0 && encoder.finalRange == 0x8000_0000 && encoder.bitsUsed == 1)
        #expect(decoder.operationCount == 0 && decoder.bitsUsed == 1)
        var baseline = encoder
        var ignored = Array(repeating: 0, count: 21)
        ignored[0] = 81_600
        let first = try allocation.encode(totalEighthBits: 1024, dynamicOffsets: ignored, into: &encoder)
        let second = try allocation.encode(totalEighthBits: 1024, into: &baseline)
        #expect(first == second)
        #expect(try encoder.finalize() == baseline.finalize())
    }

    /// Explicit skip limits, boosted protection and stereo cancellation are observable codec decisions.
    @Test func explicitSkipPolicyBoostProtectionAndIntensityCancellation() throws {
        let allocation = try CELTBitAllocation(frameSampleCount: 120, channelCount: 2)
        var encoder = try OpusRangeEncoder(frameByteCount: 16)
        let skipped = try allocation.encode(totalEighthBits: 4096, codedBandLimit: 2,
            intensityBand: 0, dualStereo: true, into: &encoder)
        #expect(skipped.codedBandEnd == 2 && skipped.intensityBand == 0 && !skipped.dualStereo)
        #expect(skipped.shapeEighthBits.dropFirst(2).allSatisfy { $0 == 0 })
        #expect(skipped.fineEnergyBits.dropFirst(2).allSatisfy { $0 <= 1 })
        var offsets = Array(repeating: 0, count: 21)
        offsets[20] = 384
        var boostedEncoder = try OpusRangeEncoder(frameByteCount: 16)
        let boosted = try allocation.encode(totalEighthBits: 4096, dynamicOffsets: offsets, codedBandLimit: 2,
            intensityBand: 21, dualStereo: true, into: &boostedEncoder)
        #expect(boosted.codedBandEnd == 21 && boosted.intensityBand == 21 && boosted.dualStereo)
        var decoder = try OpusRangeDecoder(frame: boostedEncoder.finalize())
        #expect(try allocation.decode(totalEighthBits: 4096, dynamicOffsets: offsets, from: &decoder) == boosted)
    }

    /// Fine precision is bounded at eight, excess carries across bands and single coefficients retain sign budgets.
    @Test func finePrecisionCapsAndExcessBalance() throws {
        let allocation = try CELTBitAllocation(frameSampleCount: 120)
        var encoder = try OpusRangeEncoder(frameByteCount: 16)
        let result = try allocation.encode(totalEighthBits: 81_600, into: &encoder)
        #expect(result.codedBandEnd == 21)
        #expect(result.shapeEighthBits.prefix(8).allSatisfy { $0 == 8 })
        #expect(result.fineEnergyBits.allSatisfy { $0 == 8 })
        #expect(result.balanceEighthBits > 0)
        #expect(result.finePriorities.allSatisfy { $0 == 0 })
        var mediumEncoder = try OpusRangeEncoder(frameByteCount: 16)
        let medium = try allocation.encode(totalEighthBits: 500, into: &mediumEncoder)
        #expect(medium.finePriorities.contains(0) && medium.finePriorities.contains(1))
        let narrow = try CELTBitAllocation(frameSampleCount: 120, channelCount: 2, startBand: 20)
        var narrowEncoder = try OpusRangeEncoder(frameByteCount: 16)
        let single = try narrow.encode(totalEighthBits: 81_600, intensityBand: 20,
            dualStereo: true, into: &narrowEncoder)
        #expect(single.codedBandEnd == 21 && single.intensityBand == 20 && !single.dualStereo)
        #expect(single.fineEnergyBits[20] == 8 && single.balanceEighthBits > 0)
    }

    /// Operation exhaustion after partial skip/stereo syntax rolls back every public entropy field and remains reusable.
    @Test func entropyFailureAtomicityAndContinuedUse() throws {
        let allocation = try CELTBitAllocation(frameSampleCount: 120, channelCount: 2)
        var encoder = try OpusRangeEncoder(frameByteCount: 16, maximumOperations: 1)
        var baseline = encoder
        #expect(throws: OpusRangeCodingError.operationLimitExceeded) {
            try allocation.encode(totalEighthBits: 4096, codedBandLimit: 2, into: &encoder)
        }
        #expect(encoder.operationCount == 0 && encoder.finalRange == baseline.finalRange)
        #expect(encoder.bitsUsed == baseline.bitsUsed && encoder.fractionalBitsUsed == baseline.fractionalBitsUsed)
        try encoder.encodeBit(true, logProbability: 1)
        try baseline.encodeBit(true, logProbability: 1)
        #expect(try encoder.finalize() == baseline.finalize())
        var decoder = try OpusRangeDecoder(frame: Data(repeating: 0xff, count: 16), maximumOperations: 1)
        var original = decoder
        #expect(throws: OpusRangeCodingError.operationLimitExceeded) {
            try allocation.decode(totalEighthBits: 4096, from: &decoder)
        }
        #expect(decoder.operationCount == 0 && decoder.finalRange == original.finalRange)
        #expect(decoder.bitsUsed == original.bitsUsed && decoder.fractionalBitsUsed == original.fractionalBitsUsed)
        #expect(try decoder.decodeBit(logProbability: 1) == original.decodeBit(logProbability: 1))
        #expect(decoder.finalRange == original.finalRange && decoder.operationCount == 1)
        var empty = try OpusRangeEncoder(frameByteCount: 0)
        #expect(throws: OpusRangeCodingError.frameBudgetExceeded) {
            try allocation.encode(totalEighthBits: 4096, into: &empty)
        }
        #expect(empty.operationCount == 0 && empty.bitsUsed == 1)
        #expect(try empty.finalize().isEmpty)
    }

    /// Checks every public result field against a separately compiled independent reference value.
    /// - Parameters:
    ///   - actual: Owned Swift allocation under test.
    ///   - expected: Literal official C allocation captured before entropy finalization.
    private func assertAllocation(_ actual: CELTBitAllocationResult, equals expected: AllocationFixture.State) {
        #expect(actual.shapeEighthBits == expected.shape)
        #expect(actual.fineEnergyBits == expected.fine)
        #expect(actual.finePriorities == expected.priorities)
        #expect(actual.balanceEighthBits == expected.balance)
        #expect(actual.codedBandEnd == expected.coded)
        #expect(actual.intensityBand == expected.intensity)
        #expect(actual.dualStereo == expected.dual)
    }
}

/// Decodes immutable development fixtures without importing a native library or reading external files.
private struct AllocationFixture: Decodable {
    let input: Input
    let output: Output
    struct Input: Decodable {
        let lm: Int; let c: Int; let start: Int; let end: Int; let trim: Int; let total: Int; let bytes: Int
        let prefix: Int; let intensity: Int; let dual: Bool; let offsets: [Int]; let arbitrary: [UInt8]
    }
    struct State: Decodable {
        let shape: [Int]; let fine: [Int]; let priorities: [Int]; let balance: Int; let coded: Int
        let intensity: Int; let dual: Bool; let bits: Int; let frac: Int; let range: UInt32
    }
    struct Output: Decodable {
        let caps: [Int]; let encoded: State; let decoded: State; let arbitrary: State; let bytes: [UInt8]
    }
}
