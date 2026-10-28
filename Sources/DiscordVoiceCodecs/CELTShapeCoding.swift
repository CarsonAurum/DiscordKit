// File: Sources/DiscordVoiceCodecs/CELTShapeCoding.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

// Recursive shape coding and stereo adapted from libopus 1.6.1 celt/bands.c, celt/vq.c and celt/mathops.h.
// Copyright (c) 2007-2008 CSIRO
// Copyright (c) 2007-2009 Xiph.Org Foundation
// Written by Jean-Marc Valin
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
// - Redistributions of source code must retain the above copyright notice,
//   this list of conditions and the following disclaimer.
// - Redistributions in binary form must reproduce the above copyright notice,
//   this list of conditions and the following disclaimer in the documentation
//   and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
// IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
// ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
// LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
// CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
// SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
// INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
// CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
// ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
// POSSIBILITY OF SUCH DAMAGE.

import Foundation

/// Invalid context rejected before owned CELT band coding consumes caller entropy.
public enum CELTShapeCodingError: Error, Sendable, Equatable {
    case invalidFrameSize, invalidBandIndex, invalidChannelCount, invalidTimeFrequencyChange
    case invalidCoefficients, invalidFolding, invalidEnergy, invalidBudget, invalidFillMask
    case invalidIntensity, invalidThetaRounding, invalidBandRange, invalidAllocation, invalidCollapseMasks, invalidHistory
}

/// One reconstructed ordinary CELT band and caller-owned continuation state.
/// Spectra are channel-major normalized coefficients, not PCM. Folding uses the
/// reconstructed mono band or stereo mid, scaled by sqrt(dimensions), before stereo merge.
public struct CELTShapeCodingResult: Sendable, Equatable {
    public let coefficients: [Float]
    public let folding: [Float]
    public let collapseMask: UInt8
    public let remainingEighthBits: Int
    public let seed: UInt32
    /// Recursive partition splits, excluding the outer stereo theta split.
    public let recursiveSplits: Int
}

/// Owned RFC 6716 section 4.3.4 ordinary-mode recursive mono/stereo shape syntax.
///
/// This composes exact pulse cache selection, recursive theta partitions, scarce-bit
/// pulse reduction, scalar signs, PVQ, spreading, seeded zero-pulse noise/folding,
/// time/frequency Haar transforms, sample reordering, stereo angle/intensity/inversion
/// and mid/side reconstruction. Each call processes one of the standard 21 bands at
/// 120/240/480/960 internal 48-kHz frame samples. Custom modes/extensions are excluded.
///
/// The caller owns prior syntax, all-band allocation/rebalancing/folding selection,
/// band energies, seed and total-bit authority. This component supplies no complete
/// Opus packet codec, encoder psychoacoustics, anti-collapse across bands, PLC/FEC,
/// transform, PCM, tasks or I/O. Work/storage is bounded by 176 coefficients/channel,
/// at most four recursion levels and 128 pulses/leaf. Instances are immutable and
/// shareable; entropy owners are mutated synchronously. Invalid arguments preserve
/// entropy; coding failures may partially consume it, requiring frame discard.
public struct CELTShapeCoding: Sendable {
    public let frameSampleCount: Int
    public let bandIndex: Int
    public let channelCount: Int
    public let dimensions: Int
    public let transient: Bool
    public let timeFrequencyChange: Int
    public let spreading: CELTSpreading
    public let intensityBand: Int
    public let disableInversion: Bool
    public let avoidSplitNoise: Bool
    public let thetaRounding: Int
    private let durationIndex: Int
    private let blocks: Int

    /// Validates an ordinary-mode band and its explicitly decoded/selected decisions.
    /// - Parameters:
    ///   - frameSampleCount: Exactly 120, 240, 480 or 960 samples/channel at 48 kHz.
    ///   - bandIndex: Ordinary global band index in `0...20`.
    ///   - channelCount: One or two envelope/shape channels, default one.
    ///   - transient: Whether the enclosing frame uses 2.5-ms short transforms; default false.
    ///   - timeFrequencyChange: RFC TF resolution table output for this duration/transient
    ///     state; default zero. Values outside the actual table are rejected before shifts.
    ///   - spreading: Previously decoded/selected spreading decision; default normal.
    ///   - intensityBand: First intensity-stereo band in `0...21`; default 21 (none).
    ///   - disableInversion: Override stereo inversion for downmix compatibility; default false.
    ///   - avoidSplitNoise: Bias a partition endpoint when allocation would inject split
    ///     noise; the enclosing codec uses this for the first transient band; default false.
    ///   - thetaRounding: Stereo angle policy -1/down, 0/nearest, +1/up; default nearest.
    ///     RDO trial selection belongs to the caller, using independent entropy value copies.
    /// - Throws: The matching configuration error; no contexts, tasks or I/O are started.
    public init(frameSampleCount: Int, bandIndex: Int, channelCount: Int = 1,
                transient: Bool = false, timeFrequencyChange: Int = 0,
                spreading: CELTSpreading = .normal, intensityBand: Int = 21,
                disableInversion: Bool = false, avoidSplitNoise: Bool = false,
                thetaRounding: Int = 0) throws {
        guard let lm = [120, 240, 480, 960].firstIndex(of: frameSampleCount) else { throw CELTShapeCodingError.invalidFrameSize }
        guard (0...20).contains(bandIndex) else { throw CELTShapeCodingError.invalidBandIndex }
        guard (1...2).contains(channelCount) else { throw CELTShapeCodingError.invalidChannelCount }
        let normalChanges = [[0, -1], [0, -1, -2], [0, -2, -3], [0, -2, -3]]
        let transientChanges = [[0, -1], [1, 0, -1], [2, 0, 1, -1], [3, 0, 1, -1]]
        guard (transient ? transientChanges[lm] : normalChanges[lm]).contains(timeFrequencyChange) else {
            throw CELTShapeCodingError.invalidTimeFrequencyChange
        }
        guard (0...21).contains(intensityBand) else { throw CELTShapeCodingError.invalidIntensity }
        guard (-1...1).contains(thetaRounding) else { throw CELTShapeCodingError.invalidThetaRounding }
        self.frameSampleCount = frameSampleCount
        self.bandIndex = bandIndex
        self.channelCount = channelCount
        self.durationIndex = lm
        self.dimensions = (CELTAllocationTables.bandEdges[bandIndex + 1] - CELTAllocationTables.bandEdges[bandIndex]) << lm
        self.transient = transient
        self.timeFrequencyChange = timeFrequencyChange
        self.spreading = spreading
        self.intensityBand = intensityBand
        self.disableInversion = disableInversion
        self.avoidSplitNoise = avoidSplitNoise
        self.thetaRounding = thetaRounding
        blocks = transient ? 1 << lm : 1
    }

    /// Quantizes and writes one mono/stereo band using explicit eighth-bit allocation.
    /// - Parameters:
    ///   - coefficients: Exactly dimensions * channels finite channel-major values, each
    ///     channel's squared norm <= 1.001. Zero vectors use normative fallback search/noise.
    ///   - allocationEighthBits: Per-band shape allocation in `0...16_383`, not pulse count;
    ///     at most remainingEighthBits + 1, matching the ordinary all-band allocator.
    ///   - remainingEighthBits: Shared frame remainder in `0...81_600`, no greater than
    ///     the entropy frame's currently available fractional bits; leaf allocations may
    ///     be reduced to fit this stronger authority.
    ///   - seed: Caller-owned 32-bit CELT LCG state, default zero, consumed only for folding/noise.
    ///   - folding: Optional dimensions-sized finite lower-band vector, coefficients within
    ///     ±32; nil requests noise if fill permits. Input is copied before TF changes.
    ///   - fillMask: Prior-band occupancy across the original short blocks; nil means all.
    ///   - bandEnergies: Exactly channelCount finite amplitudes in `0...1_000_000`, default
    ///     one each; stereo uses these for intensity weighting and near-empty-channel policy.
    ///   - encoder: Active caller-owned Opus entropy frame; no packet TOC is added.
    /// - Returns: Reconstructed channels, folding data, occupancy and updated seed/remainder.
    /// - Throws: Configuration/data/budget validation errors before entropy, or range/codebook errors.
    public func encode(_ coefficients: [Float], allocationEighthBits: Int, remainingEighthBits: Int,
                       seed: UInt32 = 0, folding: [Float]? = nil, fillMask: UInt8? = nil,
                       bandEnergies: [Float]? = nil,
                       into encoder: inout OpusRangeEncoder) throws -> CELTShapeCodingResult {
        try validateCoefficients(coefficients)
        let energies = try validateContext(allocation: allocationEighthBits, remaining: remainingEighthBits,
            available: encoder.frameByteCount * 64 - encoder.fractionalBitsUsed, folding: folding,
            fill: fillMask, energies: bandEnergies)
        var context = try Context(plan: self, encoder: encoder, remaining: remainingEighthBits, seed: seed, energies: energies)
        defer { encoder = context.encoder }
        return try run(coefficients, allocation: allocationEighthBits, folding: folding,
                       fill: Int(fillMask ?? UInt8((1 << blocks) - 1)), context: &context)
    }

    /// Reads one band's recursive/stereo syntax using exactly matching caller context.
    /// - Parameters:
    ///   - allocationEighthBits: Per-band eighth-bit allocation in `0...16_383`,
    ///     at most remainingEighthBits + 1.
    ///   - remainingEighthBits: Shared eighth-bit remainder bounded by current entropy capacity.
    ///   - seed: Matching caller-owned LCG state, default zero.
    ///   - folding: Matching lower-band vector or nil, copied before internal transforms.
    ///   - fillMask: Original-block occupancy, default all blocks set.
    ///   - decoder: Active frame owner positioned after matching preceding syntax.
    /// - Returns: The decoded band, folding output, occupancy and new seed/remainder.
    /// - Throws: Context validation errors atomically, or range/codebook failures. Arithmetic
    ///     zero extension follows the entropy decoder; the enclosing codec validates frame syntax.
    public func decode(allocationEighthBits: Int, remainingEighthBits: Int, seed: UInt32 = 0,
                       folding: [Float]? = nil, fillMask: UInt8? = nil,
                       from decoder: inout OpusRangeDecoder) throws -> CELTShapeCodingResult {
        let energies = try validateContext(allocation: allocationEighthBits, remaining: remainingEighthBits,
            available: decoder.frame.count * 64 - decoder.fractionalBitsUsed, folding: folding,
            fill: fillMask, energies: nil)
        var context = try Context(plan: self, decoder: decoder, remaining: remainingEighthBits, seed: seed, energies: energies)
        defer { decoder = context.decoder }
        return try run(Array(repeating: 0, count: dimensions * channelCount), allocation: allocationEighthBits,
                       folding: folding, fill: Int(fillMask ?? UInt8((1 << blocks) - 1)), context: &context)
    }

    /// Applies common mono/stereo dispatch using dense private coefficient/folding copies.
    /// - Parameters:
    ///   - coefficients: Validated encoder input or zero decoder workspace.
    ///   - allocation: Validated per-band eighth-bit allocation.
    ///   - folding: Optional validated prior spectrum; never mutated in caller storage.
    ///   - fill: Occupancy within original short-block count.
    ///   - context: Frame-owned synchronous coding state, retained across recursive calls.
    /// - Returns: Complete band plus continuation state, only after successful syntax processing.
    /// - Throws: Propagates entropy/codebook errors without returning partial coefficient arrays.
    fileprivate func run(_ coefficients: [Float], allocation: Int, folding: [Float]?, fill: Int,
                     context: inout Context) throws -> CELTShapeCodingResult {
        var left = Array(coefficients.prefix(dimensions))
        var right = channelCount == 2 ? Array(coefficients.suffix(dimensions)) : []
        let result: Band
        if channelCount == 2 {
            result = try context.stereo(&left, &right, allocation: allocation, blocks: blocks,
                folding: folding, lm: durationIndex, fill: fill)
        } else {
            result = try context.band(&left, allocation: allocation, blocks: blocks,
                folding: folding, lm: durationIndex, gain: 1, fill: fill)
        }
        return CELTShapeCodingResult(coefficients: left + right, folding: result.folding,
            collapseMask: UInt8(result.mask), remainingEighthBits: context.remaining,
            seed: context.seed, recursiveSplits: context.splits)
    }

    /// Checks dense unit-envelope input before any quantizer or entropy state can change.
    /// - Parameter values: Candidate channel-major normalized input with the configured stride.
    /// - Throws: `invalidCoefficients` for length, nonfinite values or excessive channel norm.
    private func validateCoefficients(_ values: [Float]) throws {
        guard values.count == dimensions * channelCount, values.allSatisfy({ $0.isFinite }) else {
            throw CELTShapeCodingError.invalidCoefficients
        }
        for channel in 0..<channelCount {
            let start = channel * dimensions
            let norm = values[start..<(start + dimensions)].reduce(0.0) { $0 + Double($1) * Double($1) }
            guard norm <= 1.001 else { throw CELTShapeCodingError.invalidCoefficients }
        }
    }

    /// Validates caller budget, folding, occupancy and encoder-only channel amplitudes.
    /// - Parameters:
    ///   - allocation: Candidate shape allocation; bounded independently of frame remainder.
    ///   - remaining: Stronger shared fractional budget, capped to one maximum Opus frame.
    ///   - available: Current entropy remainder, potentially negative for an empty frame.
    ///   - folding: Optional exact-size prior spectrum, each component bounded to ±32.
    ///   - fill: Optional occupancy fitting original blocks, or nil for all.
    ///   - energies: Optional finite nonnegative per-channel amplitudes, bounded to one million.
    /// - Returns: Dense channel amplitudes, defaulting to one, with no retained caller arrays.
    /// - Throws: The matching context error before entropy or reconstruction changes.
    private func validateContext(allocation: Int, remaining: Int, available: Int, folding: [Float]?,
                                 fill: UInt8?, energies: [Float]?) throws -> [Float] {
        guard (0...16_383).contains(allocation), (0...81_600).contains(remaining), allocation <= remaining + 1, remaining <= max(0, available) else {
            throw CELTShapeCodingError.invalidBudget
        }
        if let folding {
            guard folding.count == dimensions, folding.allSatisfy({ $0.isFinite && abs($0) <= 32 }) else {
                throw CELTShapeCodingError.invalidFolding
            }
        }
        if let fill, Int(fill) >= 1 << blocks { throw CELTShapeCodingError.invalidFillMask }
        let amplitudes = energies ?? Array(repeating: Float(1), count: channelCount)
        guard amplitudes.count == channelCount, amplitudes.allSatisfy({ $0.isFinite && (0...1_000_000).contains($0) }) else {
            throw CELTShapeCodingError.invalidEnergy
        }
        return Array(amplitudes)
    }

    /// Private single-band reconstruction retained before any stereo merge.
    fileprivate struct Band { let mask: Int; let folding: [Float] }
    /// Quantized angle and the exact allocation/control results shared by both sides.
    fileprivate struct Theta { let inverse: Bool; let mid: Int; let side: Int; let delta: Int; let angle: Int; let cost: Int }

    /// One synchronous frame's private entropy authority and recursive deterministic state.
    fileprivate struct Context {
        let plan: CELTShapeCoding
        let encode: Bool
        var encoder: OpusRangeEncoder
        var decoder: OpusRangeDecoder
        var remaining: Int
        var seed: UInt32
        let energies: [Float]
        var splits = 0

        /// Creates encoder-mode context; the unused zero-frame decoder starts no work.
        /// - Parameters:
        ///   - plan: Immutable validated band decisions.
        ///   - encoder: Current caller entropy value, restored to caller even on coding failure.
        ///   - remaining: Validated shared eighth-bit budget.
        ///   - seed: Caller-owned LCG continuation.
        ///   - energies: Validated per-channel intensity amplitudes.
        /// - Throws: Only failure to construct the compile-time-valid unused entropy owner.
        init(plan: CELTShapeCoding, encoder: OpusRangeEncoder, remaining: Int, seed: UInt32, energies: [Float]) throws {
            self.plan = plan; encode = true; self.encoder = encoder
            decoder = try OpusRangeDecoder(frame: Data())
            self.remaining = remaining; self.seed = seed; self.energies = energies
        }

        /// Creates decoder-mode context with a valid unused zero-frame encoder.
        /// - Parameters:
        ///   - plan: Immutable band decisions.
        ///   - decoder: Caller entropy state, restored to caller on success or error.
        ///   - remaining: Validated shared eighth-bit budget.
        ///   - seed: Matching LCG state.
        ///   - energies: Unused decoder amplitude defaults, retained only for shared implementation.
        /// - Throws: Only compile-time-valid unused entropy-owner construction errors.
        init(plan: CELTShapeCoding, decoder: OpusRangeDecoder, remaining: Int, seed: UInt32, energies: [Float]) throws {
            self.plan = plan; encode = false; self.decoder = decoder
            encoder = try OpusRangeEncoder(frameByteCount: 0)
            self.remaining = remaining; self.seed = seed; self.energies = energies
        }

        /// Reads current fractional entropy usage without modifying either owner.
        private var tell: Int { encode ? encoder.fractionalBitsUsed : decoder.fractionalBitsUsed }

        /// Codes one static-context symbol with exactly one matching entropy operation.
        /// - Parameters:
        ///   - value: Encoder's nonnegative symbol; ignored by a decoder.
        ///   - frequencies: Positive ordinary-mode angle counts, summing at most 65,535.
        /// - Returns: Encoder value or decoded symbol.
        /// - Throws: Probability validation or caller-owned range coding failures.
        mutating func symbol(_ value: Int, frequencies: [UInt32]) throws -> Int {
            let model = try OpusProbabilityModel(frequencies: frequencies)
            if encode { try encoder.encodeSymbol(value, model: model); return value }
            return try decoder.decodeSymbol(model: model)
        }

        /// Codes one uniform angle/rank using Opus's exact split-raw-tail integer syntax.
        /// - Parameters:
        ///   - value: Encoder value in zero..<total, ignored by decoder.
        ///   - total: Number of possibilities, at least two.
        /// - Returns: Matched uniform integer.
        /// - Throws: Existing entropy owner argument/state/budget failures.
        mutating func uniform(_ value: Int, total: Int) throws -> Int {
            if encode { try encoder.encodeUniform(UInt32(value), total: UInt32(total)); return value }
            return Int(try decoder.decodeUniform(total: UInt32(total)))
        }

        /// Codes one backwards raw sign bit without altering arithmetic range.
        /// - Parameter value: Encoder sign/inversion flag, ignored on decode.
        /// - Returns: Matched raw Boolean.
        /// - Throws: Existing entropy operation/raw-bit/state failures.
        mutating func raw(_ value: Bool) throws -> Bool {
            if encode { try encoder.encodeRawBits(value ? 1 : 0, count: 1); return value }
            return try decoder.decodeRawBits(count: 1) != 0
        }

        /// Codes one asymmetric arithmetic Boolean, preserving the required log probability.
        /// - Parameters:
        ///   - value: Encoder Boolean, ignored on decode.
        ///   - probability: Binary exponent, fixed to two for stereo inversion.
        /// - Returns: Matched Boolean.
        /// - Throws: Existing entropy operation/state failures.
        mutating func bit(_ value: Bool, probability: Int) throws -> Bool {
            if encode { try encoder.encodeBit(value, logProbability: probability); return value }
            return try decoder.decodeBit(logProbability: probability)
        }

        /// Quantizes/decodes one partition angle and its exact eighth-bit allocation skew.
        /// - Parameters:
        ///   - left: First partition or normalized left channel; encoder stereo split mutates it.
        ///   - right: Second partition/right channel, with the same validated positive length.
        ///   - allocation: Available eighth bits, reduced by this angle's actual entropy cost.
        ///   - blocks: Current blocks per child; at most sixteen for ordinary TF transforms.
        ///   - originalBlocks: Block count before a recursive split, controlling the angle PDF.
        ///   - lm: Current duration exponent after recursive division, in -1...3.
        ///   - stereo: True for the outer mid/side split, false for contiguous mono partitions.
        ///   - fill: Current occupancy, narrowed at angle endpoints to suppress collapsed branches.
        /// - Returns: Bit-exact gains/skew, endpoint angle, inverse flag and entropy cost.
        /// - Throws: Entropy/probability failures; both entropy and private arrays can be partial.
        mutating func theta(_ left: inout [Float], _ right: inout [Float], allocation: inout Int,
                            blocks: Int, originalBlocks: Int, lm: Int, stereo: Bool,
                            fill: inout Int) throws -> Theta {
            let n = left.count
            let pulseCap = CELTAllocationTables.logWidths[plan.bandIndex] + lm * 8
            let offset = (pulseCap >> 1) - (stereo && n == 2 ? 16 : 4)
            let divisor = 2 * n - 1 - (stereo && n == 2 ? 1 : 0)
            var precision = (allocation + divisor * offset) / divisor
            precision = min(allocation - pulseCap - 32, min(64, precision))
            let exponentTable = [16384, 17866, 19483, 21247, 23170, 25267, 27554, 30048]
            var resolution = precision < 4 ? 1 : (((exponentTable[precision & 7] >> (14 - (precision >> 3))) + 1) >> 1) << 1
            if stereo && plan.bandIndex >= plan.intensityBand { resolution = 1 }
            var angle = encode ? Self.angle(left, right, stereo: stereo) : 0
            let before = tell
            var inverse = false
            if resolution != 1 {
                if encode {
                    if !stereo || plan.thetaRounding == 0 {
                        angle = (angle * resolution + 8192) >> 14
                        if !stereo && plan.avoidSplitNoise && angle > 0 && angle < resolution {
                            let unquantized = angle * 16384 / resolution
                            let skew = Self.fractionMultiply((n - 1) << 7,
                                Self.logTangent(Self.cosine(16384 - unquantized), Self.cosine(unquantized)))
                            if skew > allocation { angle = resolution }
                            else if skew < -allocation { angle = 0 }
                        }
                    } else {
                        let bias = angle > 8192 ? 32767 / resolution : -32767 / resolution
                        let down = min(resolution - 1, max(0, (angle * resolution + bias) >> 14))
                        angle = plan.thetaRounding < 0 ? down : down + 1
                    }
                }
                if stereo && n > 2 {
                    angle = try symbol(angle, frequencies: (0...resolution).map { $0 <= resolution / 2 ? 3 : 1 })
                } else if originalBlocks > 1 || stereo {
                    angle = try uniform(angle, total: resolution + 1)
                } else {
                    angle = try symbol(angle, frequencies: (0...resolution).map { UInt32(min($0 + 1, resolution + 1 - $0)) })
                }
                angle = angle * 16384 / resolution
                if encode && stereo {
                    if angle == 0 { intensity(&left, right) }
                    else { Self.stereoSplit(&left, &right) }
                }
            } else if stereo {
                if encode {
                    inverse = angle > 8192 && !plan.disableInversion
                    if inverse { right = right.map { -$0 } }
                    intensity(&left, right)
                }
                if allocation > 16 && remaining > 16 { inverse = try bit(inverse, probability: 2) }
                else { inverse = false }
                if plan.disableInversion { inverse = false }
                angle = 0
            }
            let cost = tell - before
            allocation -= cost
            let mid: Int, side: Int, delta: Int
            if angle == 0 {
                mid = 32767; side = 0; delta = -16384
                fill &= (1 << blocks) - 1
            } else if angle == 16384 {
                mid = 0; side = 32767; delta = 16384
                fill &= ((1 << blocks) - 1) << blocks
            } else {
                mid = Self.cosine(angle); side = Self.cosine(16384 - angle)
                delta = Self.fractionMultiply((n - 1) << 7, Self.logTangent(side, mid))
            }
            return Theta(inverse: inverse, mid: mid, side: side, delta: delta, angle: angle, cost: cost)
        }

        /// Codes scalar mono/stereo signs, using no bit when shared remainder is exhausted.
        /// - Parameters:
        ///   - left: Exactly one coefficient, replaced with the reconstructed unit sign.
        ///   - right: Optional second scalar channel, represented by an empty or one-element array.
        /// - Returns: Noncollapsed scalar occupancy and the left scalar's folding output.
        /// - Throws: Entropy raw-bit errors; available eighth bits decrease only for coded signs.
        mutating func scalar(_ left: inout [Float], _ right: inout [Float]) throws -> Band {
            var negative = false
            if remaining >= 8 { negative = try raw(left[0] < 0); remaining -= 8 }
            left[0] = negative ? -1 : 1
            if !right.isEmpty {
                negative = false
                if remaining >= 8 { negative = try raw(right[0] < 0); remaining -= 8 }
                right[0] = negative ? -1 : 1
            }
            return Band(mask: 1, folding: [left[0]])
        }

        /// Recursively codes a contiguous mono partition, reducing leaf pulse counts to budget.
        /// - Parameters:
        ///   - values: Current partition input/reconstruction, two through 176 coefficients.
        ///   - allocation: Local eighth bits including potential angle syntax.
        ///   - blocks: Current contiguous short-block count, one through sixteen.
        ///   - folding: Matching prior partition or nil; split children use corresponding halves.
        ///   - lm: Ordinary cache row exponent, in -1...3; -1 disallows further partitioning.
        ///   - gain: Finite nonnegative parent gain, at most one.
        ///   - fill: Current occupancy including split-child block bits.
        /// - Returns: Pre-spreading pulse/noise/folding occupancy for the current block layout.
        /// - Throws: Owned codebook/probability/entropy failures, preserving no partial result authority.
        mutating func partition(_ values: inout [Float], allocation: Int, blocks: Int,
                                folding: [Float]?, lm: Int, gain: Float, fill: Int) throws -> Int {
            let n = values.count
            let cacheStart = CELTShapeTables.indices[(lm + 1) * 21 + plan.bandIndex]
            let cacheCount = CELTShapeTables.bits[cacheStart]
            if lm != -1 && allocation > CELTShapeTables.bits[cacheStart + cacheCount] + 12 && n > 2 {
                splits += 1
                let half = n >> 1
                var left = Array(values.prefix(half)), right = Array(values.suffix(half))
                let originalBlocks = blocks
                let childBlocks = (blocks + 1) >> 1
                var fill = blocks == 1 ? (fill & 1) | (fill << 1) : fill
                var bits = allocation
                let angle = try theta(&left, &right, allocation: &bits, blocks: childBlocks,
                    originalBlocks: originalBlocks, lm: lm - 1, stereo: false, fill: &fill)
                var delta = angle.delta
                if originalBlocks > 1 && (angle.angle & 0x3fff) != 0 {
                    if angle.angle > 8192 { delta -= delta >> (5 - lm) }
                    else { delta = min(0, delta + ((half << 3) >> (6 - lm))) }
                }
                var midBits = max(0, min(bits, (bits - delta) / 2))
                var sideBits = bits - midBits
                remaining -= angle.cost
                let before = remaining
                let lowLeft = folding.map { Array($0.prefix(half)) }
                let lowRight = folding.map { Array($0.suffix(half)) }
                let midGain = gain * (Float(angle.mid) / 32768)
                let sideGain = gain * (Float(angle.side) / 32768)
                let mask: Int
                if midBits >= sideBits {
                    let first = try partition(&left, allocation: midBits, blocks: childBlocks,
                        folding: lowLeft, lm: lm - 1, gain: midGain, fill: fill)
                    let rebalance = midBits - (before - remaining)
                    if rebalance > 24 && angle.angle != 0 { sideBits += rebalance - 24 }
                    let second = try partition(&right, allocation: sideBits, blocks: childBlocks,
                        folding: lowRight, lm: lm - 1, gain: sideGain, fill: fill >> childBlocks)
                    mask = first | (second << (originalBlocks >> 1))
                } else {
                    let second = try partition(&right, allocation: sideBits, blocks: childBlocks,
                        folding: lowRight, lm: lm - 1, gain: sideGain, fill: fill >> childBlocks)
                    let rebalance = sideBits - (before - remaining)
                    if rebalance > 24 && angle.angle != 16384 { midBits += rebalance - 24 }
                    let first = try partition(&left, allocation: midBits, blocks: childBlocks,
                        folding: lowLeft, lm: lm - 1, gain: midGain, fill: fill)
                    mask = first | (second << (originalBlocks >> 1))
                }
                values = left + right
                return mask
            }
            var low = 0, high = cacheCount
            let target = allocation - 1
            for _ in 0..<6 {
                let middle = (low + high + 1) >> 1
                if CELTShapeTables.bits[cacheStart + middle] >= target { high = middle }
                else { low = middle }
            }
            var pulseIndex = target - (low == 0 ? -1 : CELTShapeTables.bits[cacheStart + low]) <= CELTShapeTables.bits[cacheStart + high] - target ? low : high
            var cost = pulseIndex == 0 ? 0 : CELTShapeTables.bits[cacheStart + pulseIndex] + 1
            remaining -= cost
            while remaining < 0 && pulseIndex > 0 {
                remaining += cost; pulseIndex -= 1
                cost = pulseIndex == 0 ? 0 : CELTShapeTables.bits[cacheStart + pulseIndex] + 1
                remaining -= cost
            }
            if pulseIndex > 0 {
                let pulses = pulseIndex < 8 ? pulseIndex : (8 + (pulseIndex & 7)) << ((pulseIndex >> 3) - 1)
                let quantizer = try ShapePulseQuantizer(dimensions: n, pulseCount: pulses,
                    shortBlockCount: blocks, spreading: plan.spreading)
                if encode {
                    let result = try quantizer.encode(values, gain: gain, into: &encoder)
                    values = result.0
                    return result.1
                }
                let result = try quantizer.decode(from: &decoder, gain: gain)
                values = result.0
                return result.1
            }
            let mask = (1 << blocks) - 1
            let admittedFill = fill & mask
            guard admittedFill != 0 else { values = Array(repeating: 0, count: n); return 0 }
            if let folding {
                for index in 0..<n {
                    seed = seed &* 1664525 &+ 1013904223
                    values[index] = folding[index] + (seed & 0x8000 != 0 ? Float(1.0 / 256) : -Float(1.0 / 256))
                }
            } else {
                for index in 0..<n {
                    seed = seed &* 1664525 &+ 1013904223
                    values[index] = Float(Int32(bitPattern: seed) >> 20)
                }
            }
            Self.normalize(&values, gain: gain)
            return folding == nil ? mask : admittedFill
        }

        /// Applies one band's TF transforms/reordering, recursive coding and inverse transforms.
        /// - Parameters:
        ///   - values: Current mono or mid/side vector, unit or parent-scaled at reconstruction.
        ///   - allocation: Local eighth-bit budget.
        ///   - blocks: Original short-block count.
        ///   - folding: Optional lower-band spectrum, copied before any transform.
        ///   - lm: Ordinary duration exponent used by the recursive pulse cache.
        ///   - gain: Reconstruction gain, zero through one.
        ///   - fill: Prior occupancy in original block layout.
        /// - Returns: Restored-layout occupancy and sqrt(dimensions)-scaled pre-merge folding vector.
        /// - Throws: Propagated entropy/codebook failures; private workspace may be partial.
        mutating func band(_ values: inout [Float], allocation: Int, blocks: Int,
                           folding: [Float]?, lm: Int, gain: Float, fill: Int) throws -> Band {
            let n = values.count
            if n == 1 { var absent: [Float] = []; return try scalar(&values, &absent) }
            let longBlocks = blocks == 1
            let recombine = max(0, plan.timeFrequencyChange)
            var lowband = folding
            var fill = fill
            let interleaveBits = [0, 1, 1, 1, 2, 3, 3, 3, 2, 3, 3, 3, 2, 3, 3, 3]
            for stage in 0..<recombine {
                if encode { Self.haar(&values, count: n >> stage, stride: 1 << stage) }
                if var low = lowband { Self.haar(&low, count: n >> stage, stride: 1 << stage); lowband = low }
                fill = interleaveBits[fill & 15] | (interleaveBits[fill >> 4] << 2)
            }
            var currentBlocks = blocks >> recombine
            var width = (n / blocks) << recombine
            var change = plan.timeFrequencyChange
            var divisions = 0
            while width.isMultiple(of: 2) && change < 0 {
                if encode { Self.haar(&values, count: width, stride: currentBlocks) }
                if var low = lowband { Self.haar(&low, count: width, stride: currentBlocks); lowband = low }
                fill |= fill << currentBlocks
                currentBlocks <<= 1; width >>= 1; divisions += 1; change += 1
            }
            let savedBlocks = currentBlocks, savedWidth = width
            if savedBlocks > 1 {
                if encode { Self.reorder(&values, width: width >> recombine, blocks: savedBlocks << recombine, hadamard: longBlocks, inverse: false) }
                if var low = lowband {
                    Self.reorder(&low, width: width >> recombine, blocks: savedBlocks << recombine, hadamard: longBlocks, inverse: false)
                    lowband = low
                }
            }
            var mask = try partition(&values, allocation: allocation, blocks: currentBlocks,
                folding: lowband, lm: lm, gain: gain, fill: fill)
            if savedBlocks > 1 { Self.reorder(&values, width: width >> recombine,
                blocks: savedBlocks << recombine, hadamard: longBlocks, inverse: true) }
            currentBlocks = savedBlocks; width = savedWidth
            for _ in 0..<divisions {
                currentBlocks >>= 1; width <<= 1
                mask |= mask >> currentBlocks
                Self.haar(&values, count: width, stride: currentBlocks)
            }
            let deinterleaveBits = [0x00, 0x03, 0x0c, 0x0f, 0x30, 0x33, 0x3c, 0x3f,
                                    0xc0, 0xc3, 0xcc, 0xcf, 0xf0, 0xf3, 0xfc, 0xff]
            for stage in 0..<recombine {
                mask = deinterleaveBits[mask]
                Self.haar(&values, count: n >> stage, stride: 1 << stage)
            }
            currentBlocks <<= recombine
            let scale = Float(sqrt(Double(n)))
            return Band(mask: mask & ((1 << currentBlocks) - 1), folding: values.map { scale * $0 })
        }

        /// Codes one stereo band, including scalar/N=2 orthogonality and normal mid/side paths.
        /// - Parameters:
        ///   - left: Normalized left input and reconstructed left output.
        ///   - right: Matching normalized right input and reconstructed right output.
        ///   - allocation: Per-band shared eighth bits for both channels and theta.
        ///   - blocks: Original short-block count.
        ///   - folding: Optional lower-band mono/mid folding vector.
        ///   - lm: Ordinary duration exponent.
        ///   - fill: Union of prior left/right original-block occupancy.
        /// - Returns: Combined channel occupancy and pre-stereo-merge mid folding data.
        /// - Throws: Entropy/codebook errors, retaining partial private state only.
        mutating func stereo(_ left: inout [Float], _ right: inout [Float], allocation: Int,
                             blocks: Int, folding: [Float]?, lm: Int, fill: Int) throws -> Band {
            let n = left.count
            if n == 1 { return try scalar(&left, &right) }
            if encode && (energies[0] < 1e-10 || energies[1] < 1e-10) {
                if energies[0] > energies[1] { right = Array(left) }
                else { left = Array(right) }
            }
            var bits = allocation, currentFill = fill
            let angle = try theta(&left, &right, allocation: &bits, blocks: blocks,
                originalBlocks: blocks, lm: lm, stereo: true, fill: &currentFill)
            let mid = Float(angle.mid) / 32768, side = Float(angle.side) / 32768
            let result: Band
            if n == 2 {
                let sideBits = angle.angle != 0 && angle.angle != 16384 ? 8 : 0
                let swap = angle.angle > 8192
                remaining -= angle.cost + sideBits
                var primary = swap ? right : left
                var secondary = swap ? left : right
                var negative = false
                if sideBits != 0 {
                    negative = try raw(primary[0] * secondary[1] - primary[1] * secondary[0] < 0)
                }
                result = try band(&primary, allocation: bits - sideBits, blocks: blocks,
                    folding: folding, lm: lm, gain: 1, fill: fill)
                let sign: Float = negative ? -1 : 1
                secondary[0] = -sign * primary[1]; secondary[1] = sign * primary[0]
                if swap { right = primary; left = secondary }
                else { left = primary; right = secondary }
                for index in 0..<n {
                    let m = mid * left[index], s = side * right[index]
                    left[index] = m - s; right[index] = m + s
                }
            } else {
                var midBits = max(0, min(bits, (bits - angle.delta) / 2))
                var sideBits = bits - midBits
                remaining -= angle.cost
                let before = remaining
                if midBits >= sideBits {
                    let first = try band(&left, allocation: midBits, blocks: blocks,
                        folding: folding, lm: lm, gain: 1, fill: currentFill)
                    let rebalance = midBits - (before - remaining)
                    if rebalance > 24 && angle.angle != 0 { sideBits += rebalance - 24 }
                    let second = try band(&right, allocation: sideBits, blocks: blocks,
                        folding: nil, lm: lm, gain: side, fill: currentFill >> blocks)
                    result = Band(mask: first.mask | second.mask, folding: first.folding)
                } else {
                    let second = try band(&right, allocation: sideBits, blocks: blocks,
                        folding: nil, lm: lm, gain: side, fill: currentFill >> blocks)
                    let rebalance = sideBits - (before - remaining)
                    if rebalance > 24 && angle.angle != 16384 { midBits += rebalance - 24 }
                    let first = try band(&left, allocation: midBits, blocks: blocks,
                        folding: folding, lm: lm, gain: 1, fill: currentFill)
                    result = Band(mask: first.mask | second.mask, folding: first.folding)
                }
                Self.merge(&left, &right, mid: mid)
            }
            if angle.inverse { right = right.map { -$0 } }
            return result
        }

        /// Converts normalized left/right spectra to orthogonal mid and side with the RFC sign.
        /// - Parameters:
        ///   - left: Equal-length validated left vector, replaced by scaled left+right.
        ///   - right: Right vector, replaced by scaled right-left using original values.
        private static func stereoSplit(_ left: inout [Float], _ right: inout [Float]) {
            for index in left.indices {
                let l = Float(0.70710678) * left[index], r = Float(0.70710678) * right[index]
                left[index] = l + r; right[index] = r - l
            }
        }

        /// Merges channels for intensity coding using caller amplitudes and finite epsilon.
        /// - Parameters:
        ///   - left: First normalized vector, replaced by the amplitude-weighted merged vector.
        ///   - right: Matching second vector; not modified here.
        private func intensity(_ left: inout [Float], _ right: [Float]) {
            let norm = Float(1e-15) + Float(sqrt(Double(Float(1e-15) + energies[0] * energies[0] + energies[1] * energies[1])))
            let a = energies[0] / norm, b = energies[1] / norm
            for index in left.indices { left[index] = a * left[index] + b * right[index] }
        }

        /// Normalizes reconstructed stereo channels after preserving unit mid for later folding.
        /// - Parameters:
        ///   - left: Unit mid vector, replaced with normalized mid-side.
        ///   - right: Already side-gain-scaled vector, replaced with normalized mid+side.
        ///   - mid: Quantized cosine gain in zero through one.
        /// Near-degenerate left/right energy copies the mid to both channels, as libopus does.
        private static func merge(_ left: inout [Float], _ right: inout [Float], mid: Float) {
            var product: Float = 0, sideEnergy: Float = 0
            for index in left.indices { product += right[index] * left[index]; sideEnergy += right[index] * right[index] }
            product *= mid
            let leftEnergy = mid * mid + sideEnergy - 2 * product
            let rightEnergy = mid * mid + sideEnergy + 2 * product
            if leftEnergy < 6e-4 || rightEnergy < 6e-4 { right = Array(left); return }
            let leftGain = 1 / Float(sqrt(Double(leftEnergy))), rightGain = 1 / Float(sqrt(Double(rightEnergy)))
            for index in left.indices {
                let m = mid * left[index], s = right[index]
                left[index] = leftGain * (m - s); right[index] = rightGain * (m + s)
            }
        }

        /// Normalizes a finite private fold/noise vector with the official float epsilon.
        /// - Parameters:
        ///   - values: Current bounded partition, modified in place without entropy effects.
        ///   - gain: Desired finite norm, zero through one.
        private static func normalize(_ values: inout [Float], gain: Float) {
            let energy = values.reduce(Float(1e-15)) { $0 + $1 * $1 }
            let scale = (1 / Float(sqrt(Double(energy)))) * gain
            for index in values.indices { values[index] *= scale }
        }

        /// Computes exact signed-Q15 rounded multiplication used by allocation approximations.
        /// - Parameters:
        ///   - lhs: Integer interpreted with signed 16-bit truncation, as the reference macro.
        ///   - rhs: Second signed-16 operand, likewise truncated before widening.
        /// - Returns: `(16384 + lhs16 * rhs16) >> 15`, preserving negative arithmetic shifts.
        private static func fractionMultiply(_ lhs: Int, _ rhs: Int) -> Int {
            (16384 + Int(Int16(truncatingIfNeeded: lhs)) * Int(Int16(truncatingIfNeeded: rhs))) >> 15
        }

        /// Evaluates the bit-exact CELT cosine approximation used for gains and allocation.
        /// - Parameter angle: Quarter-cycle phase in zero through 16,384; endpoints are normally handled separately.
        /// - Returns: Positive signed-Q15 cosine approximation, with exact integer rounding.
        private static func cosine(_ angle: Int) -> Int {
            var square = (4096 + angle * angle) >> 13
            square = (32767 - square) + fractionMultiply(square,
                -7651 + fractionMultiply(square, 8277 + fractionMultiply(-626, square)))
            return 1 + square
        }

        /// Computes CELT's bit-exact signed log2(tangent) approximation for allocation skew.
        /// - Parameters:
        ///   - sine: Positive Q15 side gain, excluding zero endpoints.
        ///   - cosine: Positive Q15 mid gain.
        /// - Returns: Signed Q11 logarithmic gain ratio, independent of floating-point arithmetic.
        private static func logTangent(_ sine: Int, _ cosine: Int) -> Int {
            let ls = Int.bitWidth - sine.leadingZeroBitCount, lc = Int.bitWidth - cosine.leadingZeroBitCount
            let s = sine << (15 - ls), c = cosine << (15 - lc)
            return (ls - lc) * 2048 + fractionMultiply(s, fractionMultiply(s, -2597) + 7932)
                - fractionMultiply(c, fractionMultiply(c, -2597) + 7932)
        }

        /// Estimates quarter-cycle angle from two partition norms or stereo sum/difference norms.
        /// - Parameters:
        ///   - left: First finite normalized channel/partition.
        ///   - right: Equal-length second channel/partition.
        ///   - stereo: True uses sum/difference energies; false uses independent partition energies.
        /// - Returns: Integer quarter-cycle phase in zero through 16,384 using libopus 1.6.1's
        ///   float Remez atan polynomial and Q30 rounding before shifting to Q14.
        private static func angle(_ left: [Float], _ right: [Float], stereo: Bool) -> Int {
            var midEnergy: Float = 0, sideEnergy: Float = 0
            for index in left.indices {
                let m = stereo ? left[index] + right[index] : left[index]
                let s = stereo ? left[index] - right[index] : right[index]
                midEnergy += m * m; sideEnergy += s * s
            }
            let mid = Float(sqrt(Double(midEnergy))), side = Float(sqrt(Double(sideEnergy)))
            if mid * mid + side * side < 1e-18 { return 0 }
            let value = side < mid ? atan(side / mid) : 1 - atan(mid / side)
            return Int(floor(Float(0.5) + Float(1073741824) * value)) >> 16
        }

        /// Evaluates the reference scalar normalized atan polynomial on zero through one.
        /// - Parameter x: Nonnegative ratio no greater than one, produced from finite norms.
        /// - Returns: Approximation to atan(x)/(pi/2), with scalar Float operation ordering.
        private static func atan(_ x: Float) -> Float {
            let square = x * x
            var polynomial: Float = -4.3554059229791164398193359375e-03
            polynomial = 2.304013632237911224365234375e-02 + square * polynomial
            polynomial = -5.7773590087890625e-02 + square * polynomial
            polynomial = 9.7942344844341278076171875e-02 + square * polynomial
            polynomial = -1.397658288478851318359375e-01 + square * polynomial
            polynomial = 1.9962704181671142578125e-01 + square * polynomial
            polynomial = -3.333165943622589111328125e-01 + square * polynomial
            return Float(0.636619772367581) * (x + x * square * polynomial)
        }

        /// Applies an orthonormal two-point Haar stage over all coefficient lanes.
        /// - Parameters:
        ///   - values: Dense private vector, containing count * stride elements.
        ///   - count: Positive even elements per lane before the transform stage.
        ///   - stride: Lane count, a power of two no greater than sixteen.
        private static func haar(_ values: inout [Float], count: Int, stride: Int) {
            for lane in 0..<stride {
                for pair in 0..<(count >> 1) {
                    let first = stride * 2 * pair + lane, second = first + stride
                    let a = Float(0.70710678) * values[first], b = Float(0.70710678) * values[second]
                    values[first] = a + b; values[second] = a - b
                }
            }
        }

        /// Converts frequency-interleaved and contiguous-block layouts with optional ordered Hadamard lanes.
        /// - Parameters:
        ///   - values: Dense private vector of width * blocks finite coefficients.
        ///   - width: Positive coefficients per lane.
        ///   - blocks: Power-of-two lane count, at most sixteen.
        ///   - hadamard: Use the reference bit-reversed Gray lane order for long original blocks.
        ///   - inverse: Restore frequency-interleaved layout when true.
        private static func reorder(_ values: inout [Float], width: Int, blocks: Int, hadamard: Bool, inverse: Bool) {
            let order = [1, 0, 3, 0, 2, 1, 7, 0, 4, 3, 6, 1, 5, 2,
                         15, 0, 8, 7, 12, 3, 11, 4, 14, 1, 9, 6, 13, 2, 10, 5]
            var output = Array(repeating: Float(0), count: values.count)
            for lane in 0..<blocks {
                let targetLane = hadamard ? order[blocks - 2 + lane] : lane
                for coefficient in 0..<width {
                    let contiguous = targetLane * width + coefficient, interleaved = coefficient * blocks + lane
                    if inverse { output[interleaved] = values[contiguous] }
                    else { output[contiguous] = values[interleaved] }
                }
            }
            values = output
        }
    }

    /// Private ordinary leaf quantizer supporting the transient TF path's sixteen blocks.
    /// Unlike the independently exposed single-band primitive, its input may be a stereo
    /// mid with squared norm two. All context and storage bounds come from the enclosing plan.
    private struct ShapePulseQuantizer {
        let dimensions: Int
        let pulseCount: Int
        let shortBlockCount: Int
        let spreading: CELTSpreading
        let codebook: CELTPulseCodebook

        /// Builds the bounded exact leaf codebook selected by the ordinary pulse cache.
        /// - Parameters:
        ///   - dimensions: Leaf coefficients, two through 176.
        ///   - pulseCount: Cache-selected pulses, one through 128, fitting one UInt32 rank.
        ///   - shortBlockCount: Power-of-two contiguous blocks, one through sixteen, dividing dimensions.
        ///   - spreading: Enclosing frame's previously selected spreading mode.
        /// - Throws: Exact-codebook construction errors if compiled ordinary contexts are invalid.
        init(dimensions: Int, pulseCount: Int, shortBlockCount: Int, spreading: CELTSpreading) throws {
            self.dimensions = dimensions; self.pulseCount = pulseCount
            self.shortBlockCount = shortBlockCount; self.spreading = spreading
            codebook = try CELTPulseCodebook(dimensions: dimensions, pulseCount: pulseCount)
        }

        /// Searches, codes and reconstructs one valid leaf with parent-provided gain.
        /// - Parameters:
        ///   - input: Finite private mono/stereo partition with bounded coefficient magnitudes.
        ///   - gain: Desired reconstructed norm in zero through one.
        ///   - encoder: Active caller entropy authority, consuming one uniform rank.
        /// - Returns: Reconstructed coefficients and contiguous short-block occupancy.
        /// - Throws: Codebook/range failures; quantizer itself remains immutable.
        func encode(_ input: [Float], gain: Float, into encoder: inout OpusRangeEncoder) throws -> ([Float], Int) {
            var rotated = Array(input)
            rotate(&rotated, inverse: false)
            let pulses = search(rotated)
            try codebook.encode(pulses, into: &encoder)
            return reconstruct(pulses, gain: gain)
        }

        /// Decodes and reconstructs one cache-selected leaf from an exact uniform rank.
        /// - Parameters:
        ///   - decoder: Caller entropy authority, consuming one uniform rank.
        ///   - gain: Parent angle gain, matching the encoder.
        /// - Returns: Coefficients and occupancy, independent of any encoder search data.
        /// - Throws: Caller-owned range errors or corrupt uniform values.
        func decode(from decoder: inout OpusRangeDecoder, gain: Float) throws -> ([Float], Int) {
            reconstruct(try codebook.decode(from: &decoder), gain: gain)
        }

        /// Applies scalar-float pulse normalization, contiguous occupancy and inverse spreading.
        /// - Parameters:
        ///   - pulses: Valid exact leaf vector with nonzero L1 norm.
        ///   - gain: Parent gain from decoded theta, zero through one.
        /// - Returns: Dense private reconstructed vector and up-to-sixteen-bit occupancy.
        private func reconstruct(_ pulses: [Int], gain: Float) -> ([Float], Int) {
            let energy = pulses.reduce(Float(0)) { $0 + Float($1 * $1) }
            let scale = (1 / Float(sqrt(Double(energy)))) * gain
            var coefficients = pulses.map { Float($0) * scale }
            var mask = 0
            let width = dimensions / shortBlockCount
            for block in 0..<shortBlockCount {
                if pulses[(block * width)..<((block + 1) * width)].contains(where: { $0 != 0 }) { mask |= 1 << block }
            }
            rotate(&coefficients, inverse: true)
            return (coefficients, mask)
        }
        /// Performs the scalar CELT projected/greedy pulse search with deterministic sign/tie rules.
        /// - Parameter input: Validated, spread band; copied into bounded absolute-value workspaces.
        /// - Returns: Exactly dimensions integer components with L1 norm pulseCount.
        ///   All products/sums are finite under the public normalization/storage bounds.
        private func search(_ input: [Float]) -> [Int] {
            var magnitudes = input.map { abs($0) }
            var pulses = Array(repeating: 0, count: dimensions)
            var doubled = Array(repeating: Float(0), count: dimensions)
            var correlation: Float = 0
            var energy: Float = 0
            var remaining = pulseCount
            if pulseCount > dimensions / 2 {
                var sum = magnitudes.reduce(Float(0), +)
                if !(sum > 1e-15 && sum < 64) {
                    magnitudes = Array(repeating: 0, count: dimensions)
                    magnitudes[0] = 1
                    sum = 1
                }
                let projection = (Float(pulseCount) + 0.8) * (1 / sum)
                for index in 0..<dimensions {
                    pulses[index] = Int(floor(projection * magnitudes[index]))
                    let value = Float(pulses[index])
                    energy += value * value
                    correlation += magnitudes[index] * value
                    doubled[index] = 2 * value
                    remaining -= pulses[index]
                }
            }
            // The pre-search leaves only a bounded greedy tail; the fallback also covers silence.
            if remaining > dimensions + 3 {
                let value = Float(remaining)
                energy += value * value
                energy += value * doubled[0]
                pulses[0] += remaining
                remaining = 0
            }
            for _ in 0..<remaining {
                energy += 1
                var best = 0
                var numerator = correlation + magnitudes[0]
                numerator *= numerator
                var denominator = energy + doubled[0]
                for index in 1..<dimensions {
                    var candidate = correlation + magnitudes[index]
                    candidate *= candidate
                    let candidateEnergy = energy + doubled[index]
                    if denominator * candidate > candidateEnergy * numerator {
                        best = index
                        numerator = candidate
                        denominator = candidateEnergy
                    }
                }
                correlation += magnitudes[best]
                energy += doubled[best]
                doubled[best] += 2
                pulses[best] += 1
            }
            for index in 0..<dimensions where input[index] < 0 { pulses[index] = -pulses[index] }
            return pulses
        }

        /// Applies CELT's energy-preserving exponential spreading rotation or its exact inverse order.
        /// - Parameters:
        ///   - values: Owned dimensions-sized band, mutated synchronously in place.
        ///   - inverse: True to reverse both the Givens signs and pass ordering after reconstruction.
        /// Dense pulse allocations (2K >= N) and `.none` skip all rotation, as in libopus.
        private func rotate(_ values: inout [Float], inverse: Bool) {
            guard spreading != .none, 2 * pulseCount < dimensions else { return }
            let factor = [15, 10, 5][spreading.rawValue - 1]
            let rotationGain = Float(dimensions) / Float(dimensions + factor * pulseCount)
            let theta = 0.5 * rotationGain * rotationGain
            let c = Float(cos(0.5 * Double.pi * Double(theta)))
            let s = Float(cos(0.5 * Double.pi * Double(1 - theta)))
            var secondStride = 0
            if dimensions >= 8 * shortBlockCount {
                secondStride = 1
                while (secondStride * secondStride + secondStride) * shortBlockCount + shortBlockCount / 4 < dimensions {
                    secondStride += 1
                }
            }
            let width = dimensions / shortBlockCount
            for block in 0..<shortBlockCount {
                let offset = block * width
                if inverse {
                    if secondStride > 0 {
                        rotatePass(&values, offset: offset, width: width, stride: secondStride, c: s, s: c)
                    }
                    rotatePass(&values, offset: offset, width: width, stride: 1, c: c, s: s)
                } else {
                    rotatePass(&values, offset: offset, width: width, stride: 1, c: c, s: -s)
                    if secondStride > 0 {
                        rotatePass(&values, offset: offset, width: width, stride: secondStride, c: s, s: -c)
                    }
                }
            }
        }

        /// Executes the forward then reverse triangular Givens sweep for one contiguous short block.
        /// - Parameters:
        ///   - values: Owned full band storage; only the selected block is modified.
        ///   - offset: First coefficient of this block, within the validated dimensions.
        ///   - width: Positive dimensions per block; all pair indices stay within the block.
        ///   - stride: Pair spacing, either one or CELT's rounded square-root secondary stride.
        ///   - c: Cosine-like finite unit rotation coefficient.
        ///   - s: Signed sine-like finite unit rotation coefficient.
        /// Zero-length reverse sweeps are skipped explicitly; storage/work stay bounded.
        private func rotatePass(_ values: inout [Float], offset: Int, width: Int, stride: Int, c: Float, s: Float) {
            for index in 0..<(width - stride) {
                let first = values[offset + index]
                let second = values[offset + index + stride]
                values[offset + index + stride] = c * second + s * first
                values[offset + index] = c * first - s * second
            }
            let last = width - 2 * stride - 1
            if last >= 0 {
                for index in Swift.stride(from: last, through: 0, by: -1) {
                    let first = values[offset + index]
                    let second = values[offset + index + stride]
                    values[offset + index + stride] = c * second + s * first
                    values[offset + index] = c * first - s * second
                }
            }
        }
    }
}

/// A reconstructed ordinary CELT spectrum and its deterministic frame continuation.
/// Coefficients are channel-major with a frameSampleCount stride. Occupancy uses
/// global band-major indices `band * channelCount + channel`; inactive masks are zero.
public struct CELTShapeFrameResult: Sendable, Equatable {
    public let coefficients: [Float]
    public let collapseMasks: [UInt8]
    public let seed: UInt32
}

/// Owned ordinary CELT all-band recursive shape coding and transient anti-collapse.
///
/// This follows RFC 6716 section 4.3.4 with exact allocation rebalancing, conservative
/// occupancy selection, low-band folding, hybrid first-band duplication and the
/// dual-to-intensity transition. Encoding uses the nearest stereo theta policy;
/// perceptual analysis and optional complexity-eight angle RDO remain caller policy.
/// It owns no PCM transforms, previous-frame history, tasks, I/O or entropy lifetime.
/// Immutable instances are shareable. Calls synchronously process at most 21 bands
/// and 1,920 coefficients. Invalid arguments preserve caller entropy; an entropy
/// failure may partially consume it and requires discarding the enclosing frame.
public struct CELTShapeFrameCoding: Sendable {
    public let frameSampleCount: Int
    public let channelCount: Int
    public let startBand: Int
    public let endBand: Int
    public let transient: Bool
    public let timeFrequencyChanges: [Int]
    public let spreading: CELTSpreading
    public let disableInversion: Bool
    private let durationIndex: Int

    /// Validates the ordinary mode and all previously decoded or selected TF decisions.
    /// - Parameters:
    ///   - frameSampleCount: Exactly 120, 240, 480 or 960 samples/channel at 48 kHz.
    ///   - channelCount: One or two coded shape channels; default one.
    ///   - startBand: First active global band, default zero, in `0...20`.
    ///   - endBand: Exclusive end, default 21, greater than startBand and at most 21.
    ///   - transient: Whether short transforms are selected; default false.
    ///   - timeFrequencyChanges: Exactly 21 ordinary TF table outputs. Defaults to zero.
    ///   - spreading: Shared spreading decision, default normal.
    ///   - disableInversion: Whether stereo inversion is suppressed, default false.
    /// - Throws: Matching configuration errors before retaining bounded decisions.
    public init(frameSampleCount: Int, channelCount: Int = 1, startBand: Int = 0,
                endBand: Int = 21, transient: Bool = false,
                timeFrequencyChanges: [Int] = Array(repeating: 0, count: 21),
                spreading: CELTSpreading = .normal, disableInversion: Bool = false) throws {
        guard let lm = [120, 240, 480, 960].firstIndex(of: frameSampleCount) else { throw CELTShapeCodingError.invalidFrameSize }
        guard (1...2).contains(channelCount) else { throw CELTShapeCodingError.invalidChannelCount }
        guard (0...20).contains(startBand), endBand > startBand, endBand <= 21 else { throw CELTShapeCodingError.invalidBandRange }
        guard timeFrequencyChanges.count == 21 else { throw CELTShapeCodingError.invalidTimeFrequencyChange }
        for i in 0..<21 {
            _ = try CELTShapeCoding(frameSampleCount: frameSampleCount, bandIndex: i,
                transient: transient, timeFrequencyChange: timeFrequencyChanges[i])
        }
        self.frameSampleCount = frameSampleCount; self.channelCount = channelCount
        self.startBand = startBand; self.endBand = endBand; self.transient = transient
        self.timeFrequencyChanges = timeFrequencyChanges; self.spreading = spreading
        self.disableInversion = disableInversion; durationIndex = lm
    }

    /// Quantizes active bands with explicit encoder analysis and allocation decisions.
    /// - Parameters:
    ///   - coefficients: Exactly frameSampleCount * channels finite channel-major values;
    ///     each active band's channel squared norm is at most 1.001. Inactive values survive.
    ///   - allocation: Matching ordinary allocator output; budgets are eighth-bits.
    ///   - totalEighthBits: Total frame authority after anti-collapse reservation, in
    ///     `0...(frameByteCount * 64)`. This is not the remaining budget after prior syntax.
    ///   - seed: Caller-owned CELT noise continuation, default zero.
    ///   - bandEnergies: Exactly 21 * channels nonnegative finite amplitudes at most one
    ///     million, in channel-major order, used for stereo intensity weighting.
    ///   - encoder: Active entropy frame after coarse/fine energy and allocation syntax.
    /// - Returns: Reconstructed spectrum, all-band occupancy and updated noise seed.
    /// - Throws: Invalid inputs before entropy mutation, or propagated coding failures.
    public func encode(_ coefficients: [Float], allocation: CELTBitAllocationResult,
                       totalEighthBits: Int, seed: UInt32 = 0, bandEnergies: [Float],
                       into encoder: inout OpusRangeEncoder) throws -> CELTShapeFrameResult {
        try validate(coefficients: coefficients, allocation: allocation, total: totalEighthBits,
                     capacity: encoder.frameByteCount * 64)
        guard bandEnergies.count == 21 * channelCount,
              bandEnergies.allSatisfy({ $0.isFinite && (0...1_000_000).contains($0) }) else { throw CELTShapeCodingError.invalidEnergy }
        var decoder = try OpusRangeDecoder(frame: Data())
        return try process(coefficients, allocation: allocation, total: totalEighthBits, seed: seed,
                           energies: bandEnergies, encoding: true, encoder: &encoder, decoder: &decoder)
    }

    /// Decodes the full active normalized spectrum after fine energy and allocation.
    /// - Parameters:
    ///   - allocation: Matching owned ordinary allocation output.
    ///   - totalEighthBits: Full frame eighth-bit capacity less the anti-collapse reserve.
    ///   - seed: Previous frame's CELT seed, default zero; must match the encoder.
    ///   - decoder: Active entropy authority, advanced synchronously in band order.
    /// - Returns: Dense coefficients, zero inactive bands, occupancy and new seed.
    /// - Throws: Invalid allocation or budget before entropy mutation, or coding failures.
    public func decode(allocation: CELTBitAllocationResult, totalEighthBits: Int,
                       seed: UInt32 = 0, from decoder: inout OpusRangeDecoder) throws -> CELTShapeFrameResult {
        let coefficients = Array(repeating: Float(0), count: frameSampleCount * channelCount)
        try validate(coefficients: coefficients, allocation: allocation, total: totalEighthBits,
                     capacity: decoder.frame.count * 64)
        var encoder = try OpusRangeEncoder(frameByteCount: 0)
        return try process(coefficients, allocation: allocation, total: totalEighthBits, seed: seed,
            energies: Array(repeating: 1, count: 21 * channelCount), encoding: false,
            encoder: &encoder, decoder: &decoder)
    }

    /// Restores missing transient blocks after the final fine-energy pass.
    ///
    /// The seed is a local copy, as required by the codec; anti-collapse does not alter
    /// the frame's seed continuation. Noncollapsed bands and inactive samples survive.
    /// - Parameters:
    ///   - coefficients: Dense reconstructed spectrum, frameSampleCount * channels, finite
    ///     and within ±32. Native stereo merging can exceed a unit norm slightly; this
    ///     pass accepts that approximation before affected bands are renormalized.
    ///   - collapseMasks: Exactly 21 * channels band-major occupancy masks; only configured
    ///     short-block bits may be set. Call only for a transient frame with its raw flag set.
    ///   - energies: Final log2 energies, channel-major 21 * channels, finite within ±32768.
    ///   - previous: Previous log2-energy history, exactly 42 entries including both channels.
    ///   - previous2: Second previous history, exactly 42 entries, with the same bounds.
    ///   - allocation: Matching ordinary allocation, used for noise depth.
    ///   - seed: Frame shape seed; copied locally and never returned or retained.
    ///   - isEncoder: Default false; a mono decoder takes the maximum of both history
    ///     channels to preserve stereo-to-mono transitions. Encoder mode uses its own channel.
    /// - Returns: Reconstructed spectrum with seeded noise in missing short blocks and
    ///     each affected band renormalized. Work and storage are bounded to one frame.
    /// - Throws: Invalid transient context, coefficient, occupancy, energy/history or allocation.
    public func applyAntiCollapse(_ coefficients: [Float], collapseMasks: [UInt8],
                                  energies: [Float], previous: [Float], previous2: [Float],
                                  allocation: CELTBitAllocationResult, seed: UInt32,
                                  isEncoder: Bool = false) throws -> [Float] {
        try validate(coefficients: coefficients, allocation: allocation, total: 0, capacity: 0, checkNorm: false)
        guard transient else { throw CELTShapeCodingError.invalidTimeFrequencyChange }
        let blocks = 1 << durationIndex
        guard collapseMasks.count == 21 * channelCount,
              collapseMasks.allSatisfy({ Int($0) < 1 << blocks }) else { throw CELTShapeCodingError.invalidCollapseMasks }
        guard energies.count == 21 * channelCount,
              energies.allSatisfy({ $0.isFinite && abs($0) <= 32768 }) else { throw CELTShapeCodingError.invalidEnergy }
        guard previous.count == 42, previous2.count == 42,
              previous.allSatisfy({ $0.isFinite && abs($0) <= 32768 }),
              previous2.allSatisfy({ $0.isFinite && abs($0) <= 32768 }) else { throw CELTShapeCodingError.invalidHistory }
        var values = coefficients
        var noiseSeed = seed
        for band in startBand..<endBand {
            let width = CELTAllocationTables.bandEdges[band + 1] - CELTAllocationTables.bandEdges[band]
            let dimensions = width << durationIndex
            let depth = ((1 + allocation.shapeEighthBits[band]) / width) >> durationIndex
            let threshold = Float(0.5) * Float(exp(Double(Float(-0.125) * Float(depth)) * 0.6931471805599453094))
            let inverseRoot = Float(1) / Float(sqrt(Double(dimensions)))
            for channel in 0..<channelCount {
                let energyIndex = channel * 21 + band
                var prior = previous[energyIndex], prior2 = previous2[energyIndex]
                if !isEncoder && channelCount == 1 {
                    prior = max(prior, previous[21 + band]); prior2 = max(prior2, previous2[21 + band])
                }
                let difference = max(0, energies[energyIndex] - min(prior, prior2))
                var amplitude = Float(2) * Float(exp(Double(-difference) * 0.6931471805599453094))
                if durationIndex == 3 { amplitude *= 1.41421356 }
                amplitude = min(threshold, amplitude) * inverseRoot
                let base = channel * frameSampleCount + (CELTAllocationTables.bandEdges[band] << durationIndex)
                var changed = false
                for block in 0..<blocks where Int(collapseMasks[band * channelCount + channel]) & (1 << block) == 0 {
                    for j in 0..<width {
                        noiseSeed = noiseSeed &* 1_664_525 &+ 1_013_904_223
                        values[base + (j << durationIndex) + block] = noiseSeed & 0x8000 != 0 ? amplitude : -amplitude
                    }
                    changed = true
                }
                if changed {
                    var energy: Float = 1e-15
                    for j in 0..<dimensions { energy += values[base + j] * values[base + j] }
                    let scale = Float(1) / Float(sqrt(Double(energy)))
                    for j in 0..<dimensions { values[base + j] *= scale }
                }
            }
        }
        return values
    }

    /// Checks all untrusted indices and arithmetic bounds before entropy or spectral work.
    /// - Parameters:
    ///   - coefficients: Dense candidate normalized spectrum.
    ///   - allocation: Candidate allocator result with global 21-band arrays.
    ///   - total: Full fractional authority, not a remaining budget.
    ///   - capacity: Maximum current frame capacity, zero for standalone anti-collapse.
    ///   - checkNorm: Default true for encoder inputs; false accepts reconstructed stereo
    ///     approximation ripple while still bounding each finite coefficient to ±32.
    /// - Throws: The matching validation error; all integer additions are bounded first.
    private func validate(coefficients: [Float], allocation: CELTBitAllocationResult, total: Int, capacity: Int, checkNorm: Bool = true) throws {
        guard coefficients.count == frameSampleCount * channelCount,
              coefficients.allSatisfy({ $0.isFinite && abs($0) <= 32 }) else { throw CELTShapeCodingError.invalidCoefficients }
        if checkNorm { for channel in 0..<channelCount {
            for band in startBand..<endBand {
                let lo = channel * frameSampleCount + (CELTAllocationTables.bandEdges[band] << durationIndex)
                let hi = channel * frameSampleCount + (CELTAllocationTables.bandEdges[band + 1] << durationIndex)
                let norm = coefficients[lo..<hi].reduce(0.0) { $0 + Double($1) * Double($1) }
                guard norm <= 1.001 else { throw CELTShapeCodingError.invalidCoefficients }
            }
        }
        }
        guard allocation.shapeEighthBits.count == 21, allocation.fineEnergyBits.count == 21,
              allocation.finePriorities.count == 21,
              allocation.shapeEighthBits.allSatisfy({ (0...16_383).contains($0) }),
              allocation.fineEnergyBits.allSatisfy({ (0...8).contains($0) }),
              allocation.finePriorities.allSatisfy({ (0...1).contains($0) }),
              (-81_600...81_600).contains(allocation.balanceEighthBits),
              ((startBand + 1)...endBand).contains(allocation.codedBandEnd),
              (0...endBand).contains(allocation.intensityBand),
              channelCount == 2 || !allocation.dualStereo else { throw CELTShapeCodingError.invalidAllocation }
        guard total >= 0, total <= capacity else { throw CELTShapeCodingError.invalidBudget }
    }

    /// Processes bounded bands with shared entropy, noise, occupancy and folding state.
    /// - Parameters:
    ///   - input: Validated dense encoder input or zero decoder workspace.
    ///   - allocation: Validated ordinary mode allocation.
    ///   - total: Full frame fractional authority after reservation.
    ///   - seed: Starting noise state, returned after the final band.
    ///   - energies: Validated channel-major intensity amplitudes.
    ///   - encoding: Selects entropy direction; unused entropy owner remains inert.
    ///   - encoder: Caller encoder, advanced even if an internal coding error occurs.
    ///   - decoder: Caller decoder, advanced even if an internal coding error occurs.
    /// - Returns: Dense reconstructed coefficients and frame continuation.
    /// - Throws: Propagates validated plan construction and entropy/codebook errors.
    private func process(_ input: [Float], allocation: CELTBitAllocationResult, total: Int,
                         seed: UInt32, energies: [Float], encoding: Bool,
                         encoder: inout OpusRangeEncoder, decoder: inout OpusRangeDecoder) throws -> CELTShapeFrameResult {
        let m = 1 << durationIndex
        let blocks = transient ? m : 1
        let offset = m * CELTAllocationTables.bandEdges[startBand]
        var values = input
        var masks = Array(repeating: UInt8(0), count: 21 * channelCount)
        var norm = Array(repeating: Float(0), count: frameSampleCount)
        var norm2 = norm
        var lowBand = 0, updateLowBand = true
        var balance = allocation.balanceEighthBits
        var dual = allocation.dualStereo
        var noiseSeed = seed
        for band in startBand..<endBand {
            let position = m * CELTAllocationTables.bandEdges[band]
            let dimensions = m * (CELTAllocationTables.bandEdges[band + 1] - CELTAllocationTables.bandEdges[band])
            let tell = encoding ? encoder.fractionalBitsUsed : decoder.fractionalBitsUsed
            if band != startBand { balance -= tell }
            var remaining = total - tell - 1
            let budget: Int
            if band < allocation.codedBandEnd {
                let adjustment = balance / min(3, allocation.codedBandEnd - band)
                budget = max(0, min(16_383, min(remaining + 1, allocation.shapeEighthBits[band] + adjustment)))
            } else { budget = 0 }
            if (position - dimensions >= offset || band == startBand + 1) && (updateLowBand || lowBand == 0) { lowBand = band }
            if band == startBand + 1 {
                let first = m * (CELTAllocationTables.bandEdges[startBand + 1] - CELTAllocationTables.bandEdges[startBand])
                let second = dimensions
                if second > first {
                    for j in 0..<(second - first) {
                        norm[first + j] = norm[2 * first - second + j]
                        if dual { norm2[first + j] = norm2[2 * first - second + j] }
                    }
                }
            }
            var effective: Int? = nil
            var leftMask = (1 << blocks) - 1, rightMask = leftMask
            if lowBand != 0 && (spreading != .aggressive || blocks > 1 || timeFrequencyChanges[band] < 0) {
                let lower = max(0, m * CELTAllocationTables.bandEdges[lowBand] - offset - dimensions)
                effective = lower
                var first = lowBand - 1
                while m * CELTAllocationTables.bandEdges[first] > lower + offset { first -= 1 }
                var last = lowBand
                while last < band && m * CELTAllocationTables.bandEdges[last] < lower + offset + dimensions { last += 1 }
                leftMask = 0; rightMask = 0
                for source in first..<max(first + 1, last) {
                    leftMask |= Int(masks[source * channelCount]); rightMask |= Int(masks[source * channelCount + channelCount - 1])
                }
            }
            if dual && band == allocation.intensityBand {
                dual = false
                for j in 0..<(position - offset) { norm[j] = Float(0.5) * (norm[j] + norm2[j]) }
            }
            let calls = dual ? 2 : 1
            for call in 0..<calls {
                let channels = dual ? 1 : channelCount
                let plan = try CELTShapeCoding(frameSampleCount: frameSampleCount, bandIndex: band,
                    channelCount: channels, transient: transient, timeFrequencyChange: timeFrequencyChanges[band],
                    spreading: spreading, intensityBand: allocation.intensityBand,
                    disableInversion: disableInversion, avoidSplitNoise: band == startBand && blocks > 1)
                var source = Array(values[(call * frameSampleCount + position)..<(call * frameSampleCount + position + dimensions)])
                if channels == 2 { source += values[(frameSampleCount + position)..<(frameSampleCount + position + dimensions)] }
                let low: [Float]?
                if let effective { low = Array((call == 1 ? norm2 : norm)[effective..<(effective + dimensions)]) }
                else { low = nil }
                let amplitudes = channels == 2 ? [energies[band], energies[21 + band]] : [energies[call * 21 + band]]
                var context = encoding
                    ? try CELTShapeCoding.Context(plan: plan, encoder: encoder, remaining: remaining, seed: noiseSeed, energies: amplitudes)
                    : try CELTShapeCoding.Context(plan: plan, decoder: decoder, remaining: remaining, seed: noiseSeed, energies: amplitudes)
                let result: CELTShapeCodingResult
                do {
                    result = try plan.run(source, allocation: dual ? budget / 2 : budget, folding: low,
                        fill: dual ? (call == 0 ? leftMask : rightMask) : leftMask | rightMask, context: &context)
                } catch { encoder = context.encoder; decoder = context.decoder; throw error }
                if encoding { encoder = context.encoder } else { decoder = context.decoder }
                remaining = result.remainingEighthBits; noiseSeed = result.seed
                values.replaceSubrange((call * frameSampleCount + position)..<(call * frameSampleCount + position + dimensions),
                                       with: result.coefficients.prefix(dimensions))
                if channels == 2 { values.replaceSubrange((frameSampleCount + position)..<(frameSampleCount + position + dimensions), with: result.coefficients.suffix(dimensions)) }
                if band != endBand - 1 {
                    if call == 0 { norm.replaceSubrange((position - offset)..<(position - offset + dimensions), with: result.folding) }
                    else { norm2.replaceSubrange((position - offset)..<(position - offset + dimensions), with: result.folding) }
                }
                masks[band * channelCount + call] = result.collapseMask
                if !dual && channelCount == 2 { masks[band * channelCount + 1] = result.collapseMask }
            }
            balance += allocation.shapeEighthBits[band] + tell
            updateLowBand = budget > dimensions * 8
        }
        return CELTShapeFrameResult(coefficients: values, collapseMasks: masks, seed: noiseSeed)
    }
}
