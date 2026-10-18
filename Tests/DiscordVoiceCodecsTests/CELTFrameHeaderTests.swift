import Foundation
@testable import DiscordVoiceCodecs
import Testing

/// Independent exact side-information fixtures and validation/atomicity boundary regressions.
@Suite("CELT segmented frame header")
struct CELTFrameHeaderTests {
    /// Verifies exact C bytes, fields and entropy before/after synthetic intervening coarse symbols.
    @Test func independentHeaderAndArbitraryDecoderFixtures() throws {
        let records = try JSONDecoder().decode([HeaderFixture].self, from: Data(CELTHeaderOracleFixtures.json.utf8))
        #expect(records.count >= 70)
        for record in records {
            let x = record.input
            let h = try CELTFrameHeader(frameSampleCount: 120 << x.lm, channelCount: x.c,
                                       startBand: x.start, endBand: x.end)
            var encoder = try OpusRangeEncoder(frameByteCount: x.bytes)
            if x.preceding > 0 { try encoder.encodeRawBits(0, count: x.preceding) }
            let filter = x.period == 0 ? nil : try CELTPostfilterParameters(period: x.period,
                gainIndex: x.gainIndex, tapset: x.tapset)
            let p = try h.encodePrefix(silence: x.silence, postfilter: filter, isTransient: x.transient, into: &encoder)
            assertPrefix(p, expected: record.output.encoded.prefix)
            assertEntropy(encoder.bitsUsed, encoder.fractionalBitsUsed, encoder.finalRange,
                          expected: record.output.encoded.prefix.entropy)
            if !p.silence {
                if x.coarse > 0 { try encoder.encodeRawBits(0, count: x.coarse) }
                let s = try h.encodeAfterCoarse(isTransient: p.isTransient, timeFrequencyFlags: x.tf,
                    timeFrequencySelect: x.select, spreading: try #require(CELTSpreading(rawValue: x.spread)),
                    dynamicBoostCounts: x.boosts, allocationTrim: x.trim, into: &encoder)
                let e = try #require(record.output.encoded.suffix)
                assertSuffix(s, expected: e)
                assertEntropy(encoder.bitsUsed, encoder.fractionalBitsUsed, encoder.finalRange, expected: e.entropy)
            }
            let wire = try encoder.finalize()
            #expect(Array(wire) == record.output.bytes)
            try assertDecode(wire, x, h, expected: record.output.decoded)
            try assertDecode(Data(x.arbitrary), x, h, expected: record.output.arbitrary)
        }
    }

    /// Every period octave/gain/tapset boundary is accepted; extremes fail before any signal or coder work.
    @Test func postfilterDomainAndConfiguration() throws {
        for period in [15, 30, 31, 62, 63, 126, 127, 254, 255, 510, 511, 1022] {
            for gain in 0...7 {
                for tapset in 0...2 {
                    let filter = try CELTPostfilterParameters(period: period, gainIndex: gain, tapset: tapset)
                    #expect(filter.period == period && filter.gainIndex == gain && filter.tapset == tapset)
                    #expect(filter.gain == Float(gain + 1) * 0.09375)
                }
            }
        }
        for (period, gain, tapset) in [(Int.min,0,0),(14,0,0),(1023,0,0),(Int.max,0,0),
                                     (15,-1,0),(15,8,0),(15,Int.max,0),(15,0,-1),(15,0,3),(15,0,Int.min)] {
            #expect(throws: CELTFrameHeaderError.invalidPostfilter) {
                try CELTPostfilterParameters(period: period, gainIndex: gain, tapset: tapset)
            }
        }
        #expect(throws: CELTBitAllocationError.invalidFrameSize) { try CELTFrameHeader(frameSampleCount: Int.max) }
        #expect(throws: CELTBitAllocationError.invalidChannelCount) { try CELTFrameHeader(frameSampleCount: 120, channelCount: 0) }
        #expect(throws: CELTBitAllocationError.invalidBandRange) { try CELTFrameHeader(frameSampleCount: 120, startBand: -1) }
        let h = try CELTFrameHeader(frameSampleCount: 960, channelCount: 2, startBand: 17, endBand: 19)
        #expect(h.frameSampleCount == 960 && h.channelCount == 2 && h.startBand == 17 && h.endBand == 19)
    }

    /// Invalid after-coarse preferences preserve encoder and decoder entropy exactly, including inactive storage.
    @Test func malformedInputsAreAtomic() throws {
        let h = try CELTFrameHeader(frameSampleCount: 120)
        var encoder = try OpusRangeEncoder(frameByteCount: 16)
        var decoder = try OpusRangeDecoder(frame: Data(repeating: 0, count: 16))
        #expect(throws: CELTFrameHeaderError.invalidTransient) { try h.decodeAfterCoarse(isTransient: true, from: &decoder) }
        #expect(throws: CELTFrameHeaderError.invalidTransient) { try h.encodeAfterCoarse(isTransient: true, into: &encoder) }
        for count in [0, 1, 20, 22, 128] {
            #expect(throws: CELTFrameHeaderError.invalidTimeFrequencyFlags) {
                try h.encodeAfterCoarse(isTransient: false, timeFrequencyFlags: Array(repeating: false, count: count), into: &encoder)
            }
            #expect(throws: CELTFrameHeaderError.invalidBoostCounts) {
                try h.encodeAfterCoarse(isTransient: false, dynamicBoostCounts: Array(repeating: 0, count: count), into: &encoder)
            }
        }
        for invalid in [Int.min, -1, 10_201, Int.max] {
            var boosts = Array(repeating: 0, count: 21)
            boosts[20] = invalid
            #expect(throws: CELTFrameHeaderError.invalidBoostCounts) {
                try h.encodeAfterCoarse(isTransient: false, dynamicBoostCounts: boosts, into: &encoder)
            }
        }
        for invalid in [Int.min, -1, 11, Int.max] {
            #expect(throws: CELTFrameHeaderError.invalidTrim) {
                try h.encodeAfterCoarse(isTransient: false, allocationTrim: invalid, into: &encoder)
            }
        }
        #expect(encoder.operationCount == 0 && encoder.bitsUsed == 1 && encoder.finalRange == 0x8000_0000)
        #expect(decoder.operationCount == 0 && decoder.bitsUsed == 1 && decoder.finalRange == 0x8000_0000)
    }

    /// Silence is terminal, accepts empty frames and cannot be retroactively signaled after preceding hybrid syntax.
    @Test func silenceAndUnavailableHeaderDefaults() throws {
        let h = try CELTFrameHeader(frameSampleCount: 120, startBand: 17)
        var empty = try OpusRangeEncoder(frameByteCount: 0)
        let ep = try h.encodePrefix(into: &empty)
        #expect(ep.silence && ep.postfilter == nil && !ep.isTransient && empty.operationCount == 0)
        var ed = try OpusRangeDecoder(frame: Data())
        #expect(try h.decodePrefix(from: &ed) == ep)
        var encoder = try OpusRangeEncoder(frameByteCount: 8)
        try encoder.encodeRawBits(0, count: 3)
        let snapshot = encoder.fractionalBitsUsed
        #expect(throws: CELTFrameHeaderError.silenceUnavailable) { try h.encodePrefix(silence: true, into: &encoder) }
        #expect(encoder.operationCount == 1 && encoder.fractionalBitsUsed == snapshot)
        let filter = try CELTPostfilterParameters(period: 15, gainIndex: 7, tapset: 2)
        let p = try h.encodePrefix(postfilter: filter, isTransient: true, into: &encoder)
        #expect(!p.silence && p.postfilter == nil && !p.isTransient)
        var tiny = try OpusRangeEncoder(frameByteCount: 1)
        try tiny.encodeRawBits(0, count: 6)
        let tail = try h.encodeAfterCoarse(isTransient: false, allocationTrim: 0, into: &tiny)
        #expect(tail.timeFrequencyChanges.allSatisfy { $0 == 0 })
        #expect(tail.dynamicOffsets.allSatisfy { $0 == 0 } && tail.allocationTrim == 5)
        #expect(tail.spreading == .normal && !tail.antiCollapseReserved)
    }

    /// Failures after private partial prefix/TF operations roll back all externally visible coder state.
    @Test func entropyFailuresRollbackPrefixAndSuffix() throws {
        let h = try CELTFrameHeader(frameSampleCount: 960)
        let filter = try CELTPostfilterParameters(period: 1022, gainIndex: 7, tapset: 2)
        var encoder = try OpusRangeEncoder(frameByteCount: 32, maximumOperations: 1)
        #expect(throws: OpusRangeCodingError.operationLimitExceeded) {
            try h.encodePrefix(postfilter: filter, isTransient: true, into: &encoder)
        }
        #expect(encoder.operationCount == 0 && encoder.bitsUsed == 1)
        #expect(throws: OpusRangeCodingError.operationLimitExceeded) {
            try h.encodeAfterCoarse(isTransient: true, into: &encoder)
        }
        #expect(encoder.operationCount == 0 && encoder.finalRange == 0x8000_0000)
        var decoder = try OpusRangeDecoder(frame: Data(repeating: 0, count: 32), maximumOperations: 1)
        #expect(throws: OpusRangeCodingError.operationLimitExceeded) { try h.decodePrefix(from: &decoder) }
        #expect(decoder.operationCount == 0 && decoder.bitsUsed == 1)
        #expect(throws: OpusRangeCodingError.operationLimitExceeded) { try h.decodeAfterCoarse(isTransient: true, from: &decoder) }
        #expect(decoder.operationCount == 0 && decoder.finalRange == 0x8000_0000)
        try encoder.encodeBit(false, logProbability: 1)
        #expect(try decoder.decodeBit(logProbability: 1) == false)
        #expect(encoder.operationCount == 1 && decoder.operationCount == 1)
    }

    /// Decodes either reference wire or unrelated bytes while checking each exact segmented checkpoint.
    /// - Parameters:
    ///   - wire: Bounded synthetic frame bytes.
    ///   - x: Independent mode and interposed raw-bit count.
    ///   - h: Immutable validated header plan.
    ///   - expected: Literal reference snapshots at both boundaries; nil suffix means terminal silence.
    private func assertDecode(_ wire: Data, _ x: HeaderFixture.Input, _ h: CELTFrameHeader,
                              expected: HeaderFixture.State) throws {
        var decoder = try OpusRangeDecoder(frame: wire)
        if x.preceding > 0 { _ = try decoder.decodeRawBits(count: x.preceding) }
        let p = try h.decodePrefix(from: &decoder)
        assertPrefix(p, expected: expected.prefix)
        assertEntropy(decoder.bitsUsed, decoder.fractionalBitsUsed, decoder.finalRange, expected: expected.prefix.entropy)
        if p.silence { #expect(expected.suffix == nil); return }
        if x.coarse > 0 { _ = try decoder.decodeRawBits(count: x.coarse) }
        let s = try h.decodeAfterCoarse(isTransient: p.isTransient, from: &decoder)
        let e = try #require(expected.suffix)
        assertSuffix(s, expected: e)
        assertEntropy(decoder.bitsUsed, decoder.fractionalBitsUsed, decoder.finalRange, expected: e.entropy)
    }

    /// Checks every admitted prefix field without depending on synthesized signal behavior.
    /// - Parameters:
    ///   - actual: Owned decoded/encoded prefix.
    ///   - expected: Independent exact C fields.
    private func assertPrefix(_ actual: CELTFramePrefix, expected: HeaderFixture.Prefix) {
        #expect(actual.silence == expected.silence && actual.isTransient == expected.transient)
        #expect((actual.postfilter?.period ?? 0) == expected.period)
        #expect((actual.postfilter?.gainIndex ?? -1) == expected.gainIndex)
        #expect((actual.postfilter?.tapset ?? 0) == expected.tapset)
    }

    /// Checks mapped TF, spreading, boosts, trim and both bit reservations exactly.
    /// - Parameters:
    ///   - actual: Owned completed suffix.
    ///   - expected: Independent exact C output.
    private func assertSuffix(_ actual: CELTFrameAllocationHeader, expected: HeaderFixture.Suffix) {
        #expect(actual.timeFrequencyChanges == expected.tf && actual.spreading.rawValue == expected.spread)
        #expect(actual.dynamicOffsets == expected.offsets && actual.allocationTrim == expected.trim)
        #expect(actual.allocationEighthBits == expected.allocation && actual.antiCollapseReserved == expected.anti)
    }

    /// Checks range normalization plus exact whole/eighth-bit snapshots at a syntax boundary.
    /// - Parameters:
    ///   - bits: Owned whole-bit count.
    ///   - fraction: Owned eighth-bit count.
    ///   - range: Owned arithmetic range.
    ///   - expected: Independent corresponding triple.
    private func assertEntropy(_ bits: Int, _ fraction: Int, _ range: UInt32, expected: (Int, Int, UInt32)) {
        #expect(bits == expected.0 && fraction == expected.1 && range == expected.2)
    }
}

/// Bounded literal independent reference JSON schema; optional suffix encodes terminal silence.
private struct HeaderFixture: Decodable {
    let input: Input
    let output: Output
    struct Input: Decodable {
        let lm: Int; let c: Int; let start: Int; let end: Int; let bytes: Int; let preceding: Int; let coarse: Int
        let silence: Bool; let period: Int; let gainIndex: Int; let tapset: Int; let transient: Bool
        let select: Bool; let spread: Int; let trim: Int; let tf: [Bool]; let boosts: [Int]; let arbitrary: [UInt8]
    }
    struct Prefix: Decodable {
        let silence: Bool; let period: Int; let gainIndex: Int; let tapset: Int; let transient: Bool
        let bits: Int; let frac: Int; let range: UInt32
        var entropy: (Int, Int, UInt32) { (bits, frac, range) }
    }
    struct Suffix: Decodable {
        let tf: [Int]; let spread: Int; let offsets: [Int]; let trim: Int; let allocation: Int; let anti: Bool
        let bits: Int; let frac: Int; let range: UInt32
        var entropy: (Int, Int, UInt32) { (bits, frac, range) }
    }
    struct State: Decodable { let prefix: Prefix; let suffix: Suffix? }
    struct Output: Decodable { let encoded: State; let decoded: State; let arbitrary: State; let bytes: [UInt8] }
}
