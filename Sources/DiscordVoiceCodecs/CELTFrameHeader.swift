// File: Sources/DiscordVoiceCodecs/CELTFrameHeader.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

/* Copyright (c) 2007-2008 CSIRO
   Copyright (c) 2007-2010 Xiph.Org Foundation
   Copyright (c) 2008 Gregory Maxwell
   Written by Jean-Marc Valin and Gregory Maxwell */
/*
   Redistribution and use in source and binary forms, with or without
   modification, are permitted provided that the following conditions
   are met:

   - Redistributions of source code must retain the above copyright
   notice, this list of conditions and the following disclaimer.

   - Redistributions in binary form must reproduce the above copyright
   notice, this list of conditions and the following disclaimer in the
   documentation and/or other materials provided with the distribution.

   THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
   ``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
   LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
   A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER
   OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
   EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
   PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
   PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
   LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
   NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
   SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/

/// Invalid explicit CELT header choices, rejected before caller entropy changes.
public enum CELTFrameHeaderError: Error, Sendable, Equatable {
    case invalidPostfilter, invalidTimeFrequencyFlags, invalidBoostCounts, invalidTrim
    case invalidTransient, silenceUnavailable
}

/// A signaled CELT postfilter choice; this value performs no signal filtering itself.
public struct CELTPostfilterParameters: Sendable, Equatable {
    public let period: Int
    public let gainIndex: Int
    public let tapset: Int
    /// Exact ordinary floating-point gain, from 0.09375 through 0.75 inclusive.
    public var gain: Float { Float(gainIndex + 1) * 0.09375 }

    /// Validates the exact CELT octave/raw-period, gain and tapset syntax domains.
    /// - Parameters:
    ///   - period: Pitch delay in 48-kHz samples, in `15...1022`.
    ///   - gainIndex: Three-bit quantized gain index in `0...7`.
    ///   - tapset: One of the three ordinary filter tapsets, in `0...2`.
    /// - Throws: `invalidPostfilter` outside these bounds; no entropy or history is retained.
    public init(period: Int, gainIndex: Int, tapset: Int) throws {
        guard (15...1022).contains(period), (0...7).contains(gainIndex), (0...2).contains(tapset) else {
            throw CELTFrameHeaderError.invalidPostfilter
        }
        self.period = period
        self.gainIndex = gainIndex
        self.tapset = tapset
    }
}

/// CELT syntax preceding the intra-energy flag and coarse envelope.
/// Silence is terminal for this primitive: the orchestrator must bypass all subsequent
/// header/energy/shape parsing and apply its silence-history/output policy explicitly.
public struct CELTFramePrefix: Sendable, Equatable {
    public let silence: Bool
    public let postfilter: CELTPostfilterParameters?
    public let isTransient: Bool
}

/// CELT syntax after coarse energy and before ordinary allocation/fine energy/shapes.
/// TF changes use global band indices; positive values improve frequency resolution,
/// negative values improve temporal resolution. Inactive TF/offset entries are zero.
public struct CELTFrameAllocationHeader: Sendable, Equatable {
    public let timeFrequencyChanges: [Int]
    public let timeFrequencySelect: Bool
    public let spreading: CELTSpreading
    public let dynamicOffsets: [Int]
    public let allocationTrim: Int
    public let allocationEighthBits: Int
    public let antiCollapseReserved: Bool
}

/// Segmented owned CELT frame flags and bit-budget-dependent side information.
///
/// The normative order is prefix, coarse energy (including its intra flag), this
/// type's after-coarse segment, allocation, fine energy, shapes, any reserved raw
/// anti-collapse bit, then final fine energy. Combining the two header segments
/// without the intervening coarse symbols would parse a different bitstream.
/// Construction starts no tasks or I/O. Every call works on a private coder copy
/// and commits only on success; no partial syntax state escapes a throwing call.
/// At most 21 TF fields, three fixed contexts and frame-budget-bounded boost flags
/// are processed. There is no perceptual encoder analysis, filter or PCM codec here.
public struct CELTFrameHeader: Sendable {
    public let frameSampleCount: Int
    public let channelCount: Int
    public let startBand: Int
    public let endBand: Int
    private let durationIndex: Int
    private let caps: [Int]
    private let tapsetModel: OpusProbabilityModel
    private let spreadingModel: OpusProbabilityModel
    private let trimModel: OpusProbabilityModel
    private static let timeFrequencyTable: [[Int]] = [
        [0, -1, 0, -1, 0, -1, 0, -1],
        [0, -1, 0, -2, 1, 0, 1, -1],
        [0, -2, 0, -3, 2, 0, 1, -1],
        [0, -2, 0, -3, 3, 0, 1, -1],
    ]

    /// Selects an ordinary CELT frame mode and immutable bounded header contexts.
    /// - Parameters:
    ///   - frameSampleCount: Exactly 120, 240, 480 or 960 samples/channel at 48 kHz.
    ///   - channelCount: One or two coded channels; default one.
    ///   - startBand: First active global band in `0...20`; default zero; hybrid normally uses 17.
    ///   - endBand: Exclusive end in `(startBand + 1)...21`; default 21.
    /// - Throws: `CELTBitAllocationError` for invalid mode/range before native work (none is performed).
    public init(frameSampleCount: Int, channelCount: Int = 1, startBand: Int = 0, endBand: Int = 21) throws {
        let allocation = try CELTBitAllocation(frameSampleCount: frameSampleCount, channelCount: channelCount,
                                               startBand: startBand, endBand: endBand)
        self.frameSampleCount = frameSampleCount
        self.channelCount = channelCount
        self.startBand = startBand
        self.endBand = endBand
        durationIndex = frameSampleCount == 120 ? 0 : (frameSampleCount == 240 ? 1 : (frameSampleCount == 480 ? 2 : 3))
        caps = allocation.bandCaps
        tapsetModel = try OpusProbabilityModel(inverseCDF: [2, 1, 0], precision: 2)
        spreadingModel = try OpusProbabilityModel(inverseCDF: [25, 23, 2, 0], precision: 5)
        trimModel = try OpusProbabilityModel(inverseCDF: [126, 124, 119, 109, 87, 41, 19, 9, 4, 2, 0], precision: 7)
    }

    /// Reads silence, optional ordinary postfilter parameters and the transient flag, in that order.
    /// - Parameter decoder: Coder positioned at the CELT frame boundary, possibly after SILK in hybrid.
    /// - Returns: Prefix ending immediately before the intra-energy flag. Exhausted frames are silence;
    ///   silence coding is inspected only when the coder's whole-bit usage is exactly one. Silence
    ///   returns immediately without pretending to advance the coder's internal bit counter to EOF.
    /// - Throws: Range-coder errors; the caller's full coder state remains unchanged on failure.
    public func decodePrefix(from decoder: inout OpusRangeDecoder) throws -> CELTFramePrefix {
        var working = decoder
        let budget = working.frame.count * 8
        var tell = working.bitsUsed
        var silence = tell >= budget
        if !silence && tell == 1 { silence = try working.decodeBit(logProbability: 15) }
        if silence {
            decoder = working
            return CELTFramePrefix(silence: true, postfilter: nil, isTransient: false)
        }
        var postfilter: CELTPostfilterParameters?
        if startBand == 0 && tell + 16 <= budget {
            if try working.decodeBit(logProbability: 1) {
                let octave = Int(try working.decodeUniform(total: 6))
                let raw = Int(try working.decodeRawBits(count: 4 + octave))
                let gain = Int(try working.decodeRawBits(count: 3))
                let tapset = working.bitsUsed + 2 <= budget ? try working.decodeSymbol(model: tapsetModel) : 0
                postfilter = try CELTPostfilterParameters(period: (16 << octave) + raw - 1,
                                                          gainIndex: gain, tapset: tapset)
            }
            tell = working.bitsUsed
        }
        let transient = durationIndex > 0 && tell + 3 <= budget ? try working.decodeBit(logProbability: 3) : false
        decoder = working
        return CELTFramePrefix(silence: false, postfilter: postfilter, isTransient: transient)
    }

    /// Emits explicit prefix choices while honoring the decoder's exact admission/default rules.
    /// - Parameters:
    ///   - silence: Desired initial silence flag; default false. A true request after preceding
    ///     syntax cannot be signaled and throws unless the frame is already exhausted. Silence
    ///     returns without faking all remaining entropy usage; the caller bypasses later segments.
    ///   - postfilter: Desired validated filter, nil for disabled; unavailable fields become nil.
    ///     A tapset that cannot fit defaults to zero in the returned admitted parameters.
    ///   - isTransient: Desired short-block flag; defaults false and becomes false for LM=0/no budget.
    ///   - encoder: Frame coder at the CELT prefix boundary; preceding hybrid syntax is preserved.
    /// - Returns: Admitted choices, ending before the coarse-energy intra header.
    /// - Throws: `silenceUnavailable` or range-coder errors; all preserve the public encoder.
    public func encodePrefix(silence: Bool = false, postfilter: CELTPostfilterParameters? = nil,
                             isTransient: Bool = false, into encoder: inout OpusRangeEncoder) throws -> CELTFramePrefix {
        var working = encoder
        let budget = working.frameByteCount * 8
        var tell = working.bitsUsed
        var admittedSilence = tell >= budget
        if !admittedSilence && tell == 1 {
            try working.encodeBit(silence, logProbability: 15)
            admittedSilence = silence
        } else if silence && !admittedSilence { throw CELTFrameHeaderError.silenceUnavailable }
        if admittedSilence {
            encoder = working
            return CELTFramePrefix(silence: true, postfilter: nil, isTransient: false)
        }
        var admittedFilter: CELTPostfilterParameters?
        if startBand == 0 && tell + 16 <= budget {
            try working.encodeBit(postfilter != nil, logProbability: 1)
            if let postfilter {
                var octave = 0
                while octave < 5 && postfilter.period + 1 >= 32 << octave { octave += 1 }
                try working.encodeUniform(UInt32(octave), total: 6)
                try working.encodeRawBits(UInt32(postfilter.period + 1 - (16 << octave)), count: 4 + octave)
                try working.encodeRawBits(UInt32(postfilter.gainIndex), count: 3)
                let tapset: Int
                if working.bitsUsed + 2 <= budget {
                    try working.encodeSymbol(postfilter.tapset, model: tapsetModel)
                    tapset = postfilter.tapset
                } else { tapset = 0 }
                admittedFilter = try CELTPostfilterParameters(period: postfilter.period, gainIndex: postfilter.gainIndex, tapset: tapset)
            }
            tell = working.bitsUsed
        }
        let transient = durationIndex > 0 && tell + 3 <= budget && isTransient
        if durationIndex > 0 && tell + 3 <= budget { try working.encodeBit(transient, logProbability: 3) }
        encoder = working
        return CELTFramePrefix(silence: false, postfilter: admittedFilter, isTransient: transient)
    }

    /// Reads TF changes/select, spreading, dynamic boosts and trim after the complete coarse envelope.
    /// - Parameters:
    ///   - isTransient: Actual prefix flag; true is invalid for 120-sample frames.
    ///   - decoder: Coder immediately after coarse energy; do not call on a silent prefix.
    /// - Returns: Exact mapped TF/boost/trim fields and the remaining allocation authority. The signed
    ///   budget may be negative for malformed/exhausted input; CELTBitAllocation clamps it to zero.
    ///   A reserved anti-collapse bit must be read as one raw bit only after shape decoding.
    /// - Throws: `invalidTransient` or range-coder errors, preserving the entire public decoder.
    public func decodeAfterCoarse(isTransient: Bool, from decoder: inout OpusRangeDecoder) throws -> CELTFrameAllocationHeader {
        try validateTransient(isTransient)
        var coding = CELTHeaderDecoding(decoder: decoder)
        let result = try afterCoarse(isTransient: isTransient, choices: .defaults, coding: &coding)
        decoder = coding.decoder
        return result
    }

    /// Emits explicit TF/spreading/dynamic/trim choices after coarse energy, without analysis heuristics.
    /// - Parameters:
    ///   - isTransient: Actual admitted prefix flag; true is invalid for 120-sample frames.
    ///   - timeFrequencyFlags: Exactly 21 desired per-band binary TF states, default false. Only
    ///     active bands are used; budget exhaustion holds the previous admitted state.
    ///   - timeFrequencySelect: Desired alternative TF mapping, default false; ignored if it cannot
    ///     fit or would not alter the mapping. Returned changes use the actually admitted selection.
    ///   - spreading: Desired ordinary shape spreading, default normal; absent syntax defaults normal.
    ///   - dynamicBoostCounts: Exactly 21 desired positive boost-flag counts in `0...10_200`, default
    ///     zero. Caps, quanta and the remaining budget determine the actual eighth-bit offsets.
    ///   - allocationTrim: Desired tilt in `0...10`, default five; absent syntax defaults five.
    ///   - encoder: Coder immediately after complete coarse energy; never use on a silent prefix.
    /// - Returns: Actual admitted fields, signed allocation budget and anti-collapse reservation.
    /// - Throws: The matching header-validation or range-coder error, preserving public encoder.
    public func encodeAfterCoarse(isTransient: Bool, timeFrequencyFlags: [Bool] = Array(repeating: false, count: 21),
                                  timeFrequencySelect: Bool = false, spreading: CELTSpreading = .normal,
                                  dynamicBoostCounts: [Int] = Array(repeating: 0, count: 21), allocationTrim: Int = 5,
                                  into encoder: inout OpusRangeEncoder) throws -> CELTFrameAllocationHeader {
        try validateTransient(isTransient)
        guard timeFrequencyFlags.count == 21 else { throw CELTFrameHeaderError.invalidTimeFrequencyFlags }
        guard dynamicBoostCounts.count == 21, dynamicBoostCounts.allSatisfy({ (0...10_200).contains($0) }) else {
            throw CELTFrameHeaderError.invalidBoostCounts
        }
        guard (0...10).contains(allocationTrim) else { throw CELTFrameHeaderError.invalidTrim }
        let choices = CELTHeaderChoices(tf: timeFrequencyFlags, select: timeFrequencySelect,
            spreading: spreading.rawValue, boosts: dynamicBoostCounts, trim: allocationTrim)
        var coding = CELTHeaderEncoding(encoder: encoder)
        let result = try afterCoarse(isTransient: isTransient, choices: choices, coding: &coding)
        encoder = coding.encoder
        return result
    }

    /// Rejects an impossible transient flag before entering entropy work.
    /// - Parameter isTransient: Previously admitted flag; LM=0 has no transient syntax.
    /// - Throws: `invalidTransient` for a 120-sample transient request.
    private func validateTransient(_ isTransient: Bool) throws {
        guard !isTransient || durationIndex > 0 else { throw CELTFrameHeaderError.invalidTransient }
    }

    /// Shares exact TF and dynamic-allocation arithmetic between privately copied encoder/decoder owners.
    /// - Parameters:
    ///   - isTransient: Validated admitted prefix flag.
    ///   - choices: Validated encoder preferences; decoder ignores their desired symbol values.
    ///   - coding: Private entropy boundary, exposing current whole/eighth-bit authority after each symbol.
    /// - Returns: Bounded 21-entry metadata and exact residual allocation authority.
    /// - Throws: Range-coder errors; private partial work is discarded by the public wrapper.
    private func afterCoarse<Coding: CELTHeaderCoding>(isTransient: Bool, choices: CELTHeaderChoices,
                                                      coding: inout Coding) throws -> CELTFrameAllocationHeader {
        var budget = coding.frameBitCount
        var tell = coding.bitsUsed
        var logProbability = isTransient ? 2 : 4
        let selectReserved = durationIndex > 0 && tell + logProbability + 1 <= budget
        if selectReserved { budget -= 1 }
        var current = false
        var changed = false
        var states = Array(repeating: false, count: 21)
        for band in startBand..<endBand {
            if tell + logProbability <= budget {
                let toggle = try coding.flag(desired: choices.tf[band] != current, logProbability: logProbability)
                current = current != toggle
                tell = coding.bitsUsed
                changed = changed || current
            }
            states[band] = current
            logProbability = isTransient ? 4 : 5
        }
        let base = isTransient ? 4 : 0
        let changedIndex = changed ? 1 : 0
        var selected = false
        if selectReserved && Self.timeFrequencyTable[durationIndex][base + changedIndex]
            != Self.timeFrequencyTable[durationIndex][base + 2 + changedIndex] {
            selected = try coding.flag(desired: choices.select, logProbability: 1)
        }
        var changes = Array(repeating: 0, count: 21)
        for band in startBand..<endBand {
            changes[band] = Self.timeFrequencyTable[durationIndex][base + (selected ? 2 : 0) + (states[band] ? 1 : 0)]
        }
        var spread = CELTSpreading.normal
        if coding.bitsUsed + 4 <= coding.frameBitCount {
            let symbol = try coding.symbol(desired: choices.spreading, model: spreadingModel)
            if let decoded = CELTSpreading(rawValue: symbol) { spread = decoded }
        }
        var total = coding.frameBitCount << 3
        tell = coding.fractionalBitsUsed
        var dynamicLogProbability = 6
        var offsets = Array(repeating: 0, count: 21)
        for band in startBand..<endBand {
            let width = channelCount * (CELTAllocationTables.bandEdges[band + 1] - CELTAllocationTables.bandEdges[band]) << durationIndex
            let quantum = min(width << 3, max(48, width))
            var loopLogProbability = dynamicLogProbability
            var count = 0
            while tell + (loopLogProbability << 3) < total && offsets[band] < caps[band] {
                let flag = try coding.flag(desired: count < choices.boosts[band], logProbability: loopLogProbability)
                tell = coding.fractionalBitsUsed
                if !flag { break }
                offsets[band] += quantum
                total -= quantum
                loopLogProbability = 1
                count += 1
            }
            if offsets[band] > 0 { dynamicLogProbability = max(2, dynamicLogProbability - 1) }
        }
        let trim = tell + 48 <= total ? try coding.symbol(desired: choices.trim, model: trimModel) : 5
        var available = (coding.frameBitCount << 3) - coding.fractionalBitsUsed - 1
        let reserve = isTransient && durationIndex >= 2 && available >= (durationIndex + 2) << 3
        if reserve { available -= 8 }
        return CELTFrameAllocationHeader(timeFrequencyChanges: changes, timeFrequencySelect: selected,
            spreading: spread, dynamicOffsets: offsets, allocationTrim: trim,
            allocationEighthBits: available, antiCollapseReserved: reserve)
    }
}

/// Desired encoder states; defaults are inert placeholders when a decoder supplies the actual symbols.
private struct CELTHeaderChoices {
    let tf: [Bool]
    let select: Bool
    let spreading: Int
    let boosts: [Int]
    let trim: Int
    static let defaults = CELTHeaderChoices(tf: Array(repeating: false, count: 21), select: false,
                                           spreading: 2, boosts: Array(repeating: 0, count: 21), trim: 5)
}

/// Private side-information coder boundary retaining exact frame and current bit authority.
private protocol CELTHeaderCoding {
    /// Current whole-bit entropy accounting used by bounded side-information admission.
    var bitsUsed: Int {
        /// Reads the current coder's whole-bit tell without consuming or emitting a symbol.
        /// - Returns: The current nonnegative bit count, including range-coder accounting overhead.
        get
    }
    /// Current one-eighth-bit entropy accounting used by fractional CELT allocation.
    var fractionalBitsUsed: Int {
        /// Reads fractional tell without advancing the coder or mutating its private working copy.
        /// - Returns: The current nonnegative bit usage in units of one eighth of a bit.
        get
    }
    /// Complete fixed entropy frame capacity, independent of the current coding position.
    var frameBitCount: Int {
        /// Reads the bounded frame's total capacity without inspecting or changing encoded symbols.
        /// - Returns: The full frame size in bits, equal to its validated byte count multiplied by eight.
        get
    }
    /// Reads or writes one probability-weighted flag.
    /// - Parameters:
    ///   - desired: Encoder choice, ignored by the decoder.
    ///   - logProbability: Negative-log probability of true, within the range coder's valid domain.
    /// - Returns: Actual encoded/decoded flag.
    /// - Throws: Range-coder errors on the private working copy.
    mutating func flag(desired: Bool, logProbability: Int) throws -> Bool
    /// Reads or writes one symbol using an immutable exact context.
    /// - Parameters:
    ///   - desired: Encoder symbol, ignored by the decoder.
    ///   - model: Validated static spreading or trim probability table.
    /// - Returns: Actual encoded/decoded symbol.
    /// - Throws: Range-coder errors on the private working copy.
    mutating func symbol(desired: Int, model: OpusProbabilityModel) throws -> Int
}

/// Private encoder adapter; public wrappers alone commit its completed state.
private struct CELTHeaderEncoding: CELTHeaderCoding {
    var encoder: OpusRangeEncoder
    /// Reads the encoder's current whole-bit tell without emitting symbols or committing its copy.
    /// - Returns: Nonnegative whole-bit entropy accounting, including range-coder overhead.
    var bitsUsed: Int { encoder.bitsUsed }
    /// Reads the encoder's current fractional tell without changing arithmetic-coding state.
    /// - Returns: Nonnegative entropy usage in units of one eighth of a bit.
    var fractionalBitsUsed: Int { encoder.fractionalBitsUsed }
    /// Reads the encoder's fixed frame capacity rather than its remaining allocation budget.
    /// - Returns: Total bounded frame bytes multiplied by eight, in bits; no encoding state changes.
    var frameBitCount: Int { encoder.frameByteCount * 8 }
    /// Emits one explicit side-information flag.
    /// - Parameters:
    ///   - desired: Actual bit to emit.
    ///   - logProbability: Static or dynamic normative probability context.
    /// - Returns: The emitted bit.
    /// - Throws: Range-coder errors, isolated to the private copy.
    mutating func flag(desired: Bool, logProbability: Int) throws -> Bool {
        try encoder.encodeBit(desired, logProbability: logProbability)
        return desired
    }
    /// Emits one explicit spreading/trim symbol.
    /// - Parameters:
    ///   - desired: Validated symbol choice.
    ///   - model: Exact context used by the peer decoder.
    /// - Returns: The emitted symbol.
    /// - Throws: Range-coder errors, isolated to the private copy.
    mutating func symbol(desired: Int, model: OpusProbabilityModel) throws -> Int {
        try encoder.encodeSymbol(desired, model: model)
        return desired
    }
}

/// Private decoder adapter; desired encoder values never influence a decoded field.
private struct CELTHeaderDecoding: CELTHeaderCoding {
    var decoder: OpusRangeDecoder
    /// Reads the decoder's current whole-bit tell without consuming symbols or committing its copy.
    /// - Returns: Nonnegative whole-bit entropy accounting, including range-coder overhead.
    var bitsUsed: Int { decoder.bitsUsed }
    /// Reads the decoder's current fractional tell without advancing arithmetic-coding state.
    /// - Returns: Nonnegative entropy usage in units of one eighth of a bit.
    var fractionalBitsUsed: Int { decoder.fractionalBitsUsed }
    /// Reads the complete bounded input frame capacity without consuming packet bytes.
    /// - Returns: The immutable frame byte count multiplied by eight, in bits.
    var frameBitCount: Int { decoder.frame.count * 8 }
    /// Reads one exact probability-weighted side-information flag.
    /// - Parameters:
    ///   - desired: Unused encoder placeholder.
    ///   - logProbability: Exact current static/dynamic context.
    /// - Returns: The decoded bit.
    /// - Throws: Range-coder errors, isolated to the private copy.
    mutating func flag(desired: Bool, logProbability: Int) throws -> Bool { try decoder.decodeBit(logProbability: logProbability) }
    /// Reads one spreading/trim symbol from the exact fixed context.
    /// - Parameters:
    ///   - desired: Unused encoder placeholder.
    ///   - model: Current validated static context.
    /// - Returns: The decoded symbol index.
    /// - Throws: Range-coder errors, isolated to the private copy.
    mutating func symbol(desired: Int, model: OpusProbabilityModel) throws -> Int { try decoder.decodeSymbol(model: model) }
}
