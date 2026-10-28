// File: Tests/DiscordVoiceCodecsTests/OpusRangeStorageTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import Foundation
import Testing
@testable import DiscordVoiceCodecs

/// Redundancy suffix exclusion preserves shared entropy while relocating backward raw reads.
@Suite("Opus shared-frame redundancy storage")
struct OpusRangeStorageTests {
    /// A valid entropy prefix plus unrelated suffix keeps arithmetic accounting and correct raw anchoring.
    @Test func suffixReductionPreservesIntervalAndRawAnchor() throws {
        var encoder = try OpusRangeEncoder(frameByteCount: 8)
        try encoder.encodeBit(true, logProbability: 3)
        try encoder.encodeSymbol(2, model: OpusProbabilityModel(frequencies: [1, 3, 5]))
        try encoder.encodeRawBits(0x1ab, count: 9)
        let frame = try encoder.finalize()
        var decoder = try OpusRangeDecoder(frame: frame + Data([255, 127, 91]))
        #expect(try decoder.decodeBit(logProbability: 3))
        #expect(try decoder.decodeSymbol(model: OpusProbabilityModel(frequencies: [1, 3, 5])) == 2)
        let before = (decoder.finalRange, decoder.bitsUsed, decoder.fractionalBitsUsed, decoder.operationCount)
        try decoder.reduceStorage(to: 8)
        #expect(decoder.frame == frame && decoder.frame.startIndex == 0)
        #expect(decoder.finalRange == before.0 && decoder.bitsUsed == before.1)
        #expect(decoder.fractionalBitsUsed == before.2 && decoder.operationCount == before.3)
        #expect(try decoder.decodeRawBits(count: 9) == 0x1ab)
        #expect(decoder.finalRange == encoder.finalRange && decoder.bitsUsed == encoder.bitsUsed)
    }

    /// Invalid bounds, exhausted physical budget, prior raw bits and terminal failure reject without mutation.
    @Test func invalidReductionIsAtomic() throws {
        var decoder = try OpusRangeDecoder(frame: Data([0, 0, 0, 0]))
        for count in [-1, 0, 5, .max] {
            #expect(throws: OpusRangeCodingError.invalidStorageReduction) { try decoder.reduceStorage(to: count) }
            #expect(decoder.frame.count == 4 && decoder.operationCount == 0 && decoder.bitsUsed == 1)
        }
        try decoder.reduceStorage(to: 4)
        _ = try decoder.decodeRawBits(count: 0)
        try decoder.reduceStorage(to: 3)
        #expect(decoder.frame.count == 3)
        _ = try decoder.decodeRawBits(count: 1)
        #expect(throws: OpusRangeCodingError.invalidStorageReduction) { try decoder.reduceStorage(to: 2) }
        #expect(decoder.frame.count == 3)
        #expect(throws: OpusRangeCodingError.frameBudgetExceeded) { try decoder.decodeRawBits(count: 25) }
        #expect(throws: OpusRangeCodingError.unusableState) { try decoder.reduceStorage(to: 3) }
        #expect(decoder.frame.count == 3)
    }
}
