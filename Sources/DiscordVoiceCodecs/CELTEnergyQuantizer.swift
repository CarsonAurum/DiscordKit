// Energy probability tables and quantization adapted from libopus 1.6.1 celt/quant_bands.c and celt/laplace.c.
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

/// Rejections before any CELT energy context consumes caller-owned entropy.
public enum CELTEnergyQuantizerError: Error, Sendable, Equatable {
    case invalidFrameSize
    case invalidChannelCount
    case invalidBandRange
    case invalidEnergies
    case invalidBitAllocation
    case invalidDecay
    case invalidRemainingBits
}

/// The encoder's reconstructed logarithmic envelope and residual to refine later.
/// Both arrays are channel-major and contain `bandCount * channelCount` elements.
/// Values are log2 amplitudes relative to CELT's band means, not linear energy or PCM.
public struct CELTEnergyEncoding: Sendable, Equatable {
    public let energies: [Float]
    public let errors: [Float]
    /// Whether the admitted coarse-energy header selected independent prediction.
    public let intra: Bool
}

/// Coarse envelope reconstruction with the actually signaled prediction mode.
public struct CELTCoarseEnergyDecoding: Sendable, Equatable {
    public let energies: [Float]
    public let intra: Bool
}

/// Owned RFC 6716 section 4.3.2 CELT coarse, fine and final energy syntax.
///
/// Coarse coding uses the ordinary 48-kHz mode's exact 21-band Laplace contexts,
/// inter/intra prediction, and 15/2/1/0-bit fallbacks. Fine refinements and final
/// priority bits use Opus's backward raw-bit tail. Encoder output agrees with the
/// scalar float libopus 1.6.1 quantizer for caller-selected prediction/decay, with
/// the one-bit fallback explicitly clamped to its only decoded values (-1/0). The
/// optional previous fine precision also supports successive fine refinements.
///
/// This value owns only bounded immutable contexts. The caller owns cross-frame
/// energies, entropy, allocation and coarse/fine/final ordering. Band ranges allow
/// hybrid's nonzero start without implementing SILK/hybrid orchestration. No
/// transform, shape allocation, complete codec, PLC/FEC or PCM is provided here.
/// Construction and calls perform no I/O, create no tasks and are synchronous;
/// independent instances and value copies share no mutable state. Invalid inputs
/// preserve entropy. An entropy failure may consume part of its caller-owned stream;
/// discard that frame. Reconstruction arrays are returned only after success.
public struct CELTEnergyQuantizer: Sendable {
    public let frameSampleCount: Int
    public let channelCount: Int
    public let bandCount: Int
    public let startBand: Int
    public let endBand: Int
    private let durationIndex: Int
    private let models: [[OpusProbabilityModel]]
    private let deltas: [[[Int]]]
    private static let predictors: [Float] = [29440 / 32768, 26112 / 32768, 21248 / 32768, 16384 / 32768]
    private static let betas: [Float] = [30147 / 32768, 22282 / 32768, 12124 / 32768, 6554 / 32768]
    private static let intraBeta: Float = 4915 / 32768

    /// Creates the bounded ordinary-mode probability contexts without touching entropy.
    /// - Parameters:
    ///   - frameSampleCount: Exactly 120, 240, 480 or 960 per channel at 48 kHz.
    ///   - channelCount: One or two independent envelope channels; default one.
    ///   - bandCount: Channel stride in `1...21`; default the ordinary mode's 21.
    ///   - startBand: First active band in `0..<bandCount`; default zero.
    ///   - endBand: Exclusive active upper bound in `(startBand + 1)...bandCount`;
    ///     nil selects bandCount. Bands outside this range remain unchanged.
    /// - Throws: The corresponding configuration error before context allocation.
    public init(frameSampleCount: Int, channelCount: Int = 1, bandCount: Int = 21,
                startBand: Int = 0, endBand: Int? = nil) throws {
        guard let durationIndex = [120, 240, 480, 960].firstIndex(of: frameSampleCount) else {
            throw CELTEnergyQuantizerError.invalidFrameSize
        }
        guard (1...2).contains(channelCount) else { throw CELTEnergyQuantizerError.invalidChannelCount }
        let end = endBand ?? bandCount
        guard (1...21).contains(bandCount), startBand >= 0, startBand < end,
              end <= bandCount else { throw CELTEnergyQuantizerError.invalidBandRange }
        self.frameSampleCount = frameSampleCount
        self.channelCount = channelCount
        self.bandCount = bandCount
        self.startBand = startBand
        self.endBand = end
        self.durationIndex = durationIndex
        var models: [[OpusProbabilityModel]] = []
        var deltas: [[[Int]]] = []
        for intra in 0...1 {
            var channelModels: [OpusProbabilityModel] = []
            var channelDeltas: [[Int]] = []
            for band in 0..<bandCount {
                let parameters = Self.probabilityParameters[durationIndex][intra]
                let context = try Self.laplaceContext(zeroFrequency: parameters[2 * band] << 7,
                                                     decay: parameters[2 * band + 1] << 6)
                channelModels.append(context.0)
                channelDeltas.append(context.1)
            }
            models.append(channelModels)
            deltas.append(channelDeltas)
        }
        self.models = models
        self.deltas = deltas
    }

    /// Quantizes coarse energy, including its independent-prediction header when it fits.
    ///
    /// Prediction rounds residuals to nearest integer with ties toward positive infinity.
    /// Low-budget fallbacks and decay constraints may enlarge residual errors. Unlike the
    /// upstream encoder helper, a one-bit residual is always clamped to -1/0 so extreme
    /// first-band inputs cannot make encoder reconstruction differ from its decoder. The actual
    /// admitted prediction is false if fewer than three header bits remain; callers use
    /// returned errors for later fine/final passes. Each active channel-band consumes at
    /// most one entropy operation. Inactive errors are zero and inactive energies retained.
    /// - Parameters:
    ///   - target: Channel-major finite log2 amplitudes in `-32_768...32_768` relative to band means.
    ///   - previous: Equally sized previous-frame energies in `-32_768...32_768`; history below -9
    ///     is clamped for prediction, independently per channel and active band.
    ///   - intra: Desired independent prediction; default false. Selection itself is caller policy.
    ///   - maximumDecay: Finite nonnegative log2 decay bound in `0...128`; default 16.
    ///   - lowFrequencyEffects: Suppress positive coarse deltas at bands >= 2; default false.
    ///   - encoder: Active frame owner, potentially already containing preceding syntax.
    /// - Returns: New reconstructed envelope, residual errors and actual prediction mode.
    /// - Throws: `invalidEnergies` or `invalidDecay` atomically; range coder failures propagate.
    public func encodeCoarse(target: [Float], previous: [Float], intra: Bool = false,
                             maximumDecay: Float = 16, lowFrequencyEffects: Bool = false,
                             into encoder: inout OpusRangeEncoder) throws -> CELTEnergyEncoding {
        try validateEnergies(target)
        try validateEnergies(previous)
        guard maximumDecay.isFinite, (0...128).contains(maximumDecay) else {
            throw CELTEnergyQuantizerError.invalidDecay
        }
        let budget = encoder.frameByteCount * 8
        let admittedIntra = encoder.bitsUsed + 3 <= budget && intra
        if encoder.bitsUsed + 3 <= budget { try encoder.encodeBit(admittedIntra, logProbability: 3) }
        let context = admittedIntra ? 1 : 0
        let coefficient = admittedIntra ? 0 : Self.predictors[durationIndex]
        let beta = admittedIntra ? Self.intraBeta : Self.betas[durationIndex]
        var energies = Array(previous)
        var errors = Array(repeating: Float(0), count: previous.count)
        var frequencyHistory = Array(repeating: Float(0), count: channelCount)
        let small = try OpusProbabilityModel(inverseCDF: [2, 1, 0], precision: 2)
        for band in startBand..<endBand {
            for channel in 0..<channelCount {
                let index = channel * bandCount + band
                let old = max(-9, previous[index])
                let residual = target[index] - coefficient * old - frequencyHistory[channel]
                var delta = Int(floor(0.5 + residual))
                let decayBound = max(-28, previous[index]) - maximumDecay
                if delta < 0 && target[index] < decayBound {
                    delta = min(0, delta + Int(decayBound - target[index]))
                }
                let remaining = budget - encoder.bitsUsed
                let safetyBits = remaining - 3 * channelCount * (endBand - band)
                if band != startBand && safetyBits < 30 {
                    if safetyBits < 24 { delta = min(1, delta) }
                    if safetyBits < 16 { delta = max(-1, delta) }
                }
                if lowFrequencyEffects && band >= 2 { delta = min(0, delta) }
                if remaining >= 15 {
                    let values = deltas[context][band]
                    let maximumMagnitude = delta < 0 ? -values.min()! : values.max()!
                    delta = min(maximumMagnitude, abs(delta)) * (delta < 0 ? -1 : 1)
                    let symbol = values.firstIndex(of: delta)!
                    try encoder.encodeSymbol(symbol, model: models[context][band])
                } else if remaining >= 2 {
                    delta = max(-1, min(1, delta))
                    try encoder.encodeSymbol(delta == 0 ? 0 : (delta < 0 ? 1 : 2), model: small)
                } else if remaining >= 1 {
                    delta = max(-1, min(0, delta))
                    try encoder.encodeBit(delta != 0, logProbability: 1)
                } else { delta = -1 }
                errors[index] = residual - Float(delta)
                energies[index] = coefficient * old + frequencyHistory[channel] + Float(delta)
                frequencyHistory[channel] = frequencyHistory[channel] + Float(delta) - beta * Float(delta)
            }
        }
        return CELTEnergyEncoding(energies: energies, errors: errors, intra: admittedIntra)
    }

    /// Decodes coarse energy with the normative header, prediction and budget fallbacks.
    /// - Parameters:
    ///   - previous: Channel-major finite history in `-32_768...32_768`, exactly channels * bands.
    ///   - decoder: Matching active frame owner; header defaults to inter when it cannot fit.
    /// - Returns: New energy history and admitted intra flag; inactive bands remain unchanged.
    /// - Throws: `invalidEnergies` before mutation, or range coding operation/state failures.
    public func decodeCoarse(previous: [Float], from decoder: inout OpusRangeDecoder) throws -> CELTCoarseEnergyDecoding {
        try validateEnergies(previous)
        let budget = decoder.frame.count * 8
        let intra = decoder.bitsUsed + 3 <= budget ? try decoder.decodeBit(logProbability: 3) : false
        let context = intra ? 1 : 0
        let coefficient = intra ? 0 : Self.predictors[durationIndex]
        let beta = intra ? Self.intraBeta : Self.betas[durationIndex]
        let small = try OpusProbabilityModel(inverseCDF: [2, 1, 0], precision: 2)
        var energies = Array(previous)
        var frequencyHistory = Array(repeating: Float(0), count: channelCount)
        for band in startBand..<endBand {
            for channel in 0..<channelCount {
                let delta: Int
                let remaining = budget - decoder.bitsUsed
                if remaining >= 15 {
                    delta = deltas[context][band][try decoder.decodeSymbol(model: models[context][band])]
                } else if remaining >= 2 {
                    let symbol = try decoder.decodeSymbol(model: small)
                    delta = symbol == 0 ? 0 : (symbol == 1 ? -1 : 1)
                } else if remaining >= 1 {
                    delta = try decoder.decodeBit(logProbability: 1) ? -1 : 0
                } else { delta = -1 }
                let index = channel * bandCount + band
                energies[index] = coefficient * max(-9, previous[index]) + frequencyHistory[channel] + Float(delta)
                frequencyHistory[channel] = frequencyHistory[channel] + Float(delta) - beta * Float(delta)
            }
        }
        return CELTCoarseEnergyDecoding(energies: energies, intra: intra)
    }

    /// Refines encoder residuals using allocated raw bits and optional previous precision.
    /// A band is skipped if all its channel fields cannot fit, matching libopus 1.6.1.
    /// - Parameters:
    ///   - state: Valid reconstruction/errors from this configuration's preceding pass.
    ///     Energies are bounded to ±32,768; residual errors to ±65,536.
    ///   - bitCounts: Per-band extra precision in `0...8`, exactly bandCount values.
    ///   - previousBitCounts: Per-band existing precision, default all zero; the sum of
    ///     existing and extra precision must not exceed eight for every band.
    ///   - encoder: Caller-owned active entropy frame; raw fields follow band/channel order.
    /// - Returns: Refined owned energies/errors with unchanged prediction mode.
    /// - Throws: `invalidEnergies` or `invalidBitAllocation` before entropy, or coder failures.
    public func encodeFine(_ state: CELTEnergyEncoding, bitCounts: [Int], previousBitCounts: [Int]? = nil,
                           into encoder: inout OpusRangeEncoder) throws -> CELTEnergyEncoding {
        try validateEnergies(state.energies)
        try validateEnergies(state.errors, limit: 65_536)
        let previous = try validateFine(bitCounts, previous: previousBitCounts)
        var energies = Array(state.energies)
        var errors = Array(state.errors)
        for band in startBand..<endBand {
            let count = bitCounts[band]
            guard count > 0, encoder.bitsUsed + channelCount * count <= encoder.frameByteCount * 8 else { continue }
            let levels = 1 << count
            for channel in 0..<channelCount {
                let index = channel * bandCount + band
                let value = max(0, min(levels - 1, Int(floor((errors[index] * Float(1 << previous[band]) + 0.5) * Float(levels)))))
                try encoder.encodeRawBits(UInt32(value), count: count)
                let offset = ((Float(value) + 0.5) / Float(levels) - 0.5) / Float(1 << previous[band])
                energies[index] += offset
                errors[index] -= offset
            }
        }
        return CELTEnergyEncoding(energies: energies, errors: errors, intra: state.intra)
    }

    /// Reads allocated fine-energy raw fields with optional successive-refinement scaling.
    /// - Parameters:
    ///   - energies: Valid channel-major reconstructed envelope from the preceding pass.
    ///   - bitCounts: Extra per-band precision in `0...8`, exactly bandCount values.
    ///   - previousBitCounts: Existing precision, default zero, with total precision <= eight.
    ///   - decoder: Matching active entropy frame; insufficient complete channel fields skip a band.
    /// - Returns: Refined owned envelope, retaining inactive bands and skipped refinements.
    /// - Throws: Energy/allocation errors atomically, or caller-owned range decoder failures.
    public func decodeFine(energies: [Float], bitCounts: [Int], previousBitCounts: [Int]? = nil,
                           from decoder: inout OpusRangeDecoder) throws -> [Float] {
        try validateEnergies(energies)
        let previous = try validateFine(bitCounts, previous: previousBitCounts)
        var result = Array(energies)
        for band in startBand..<endBand {
            let count = bitCounts[band]
            guard count > 0, decoder.bitsUsed + channelCount * count <= decoder.frame.count * 8 else { continue }
            for channel in 0..<channelCount {
                let value = try decoder.decodeRawBits(count: count)
                let offset = ((Float(value) + 0.5) / Float(1 << count) - 0.5) / Float(1 << previous[band])
                result[channel * bandCount + band] += offset
            }
        }
        return result
    }

    /// Uses remaining raw bits to refine eligible bands once, priority zero before one.
    /// - Parameters:
    ///   - state: Valid encoder energies/residuals from the fine/shape pass; energies
    ///     are bounded to ±32,768 and residual errors to ±65,536.
    ///   - fineBitCounts: Allocated fine precision in `0...8`; bands at eight are skipped.
    ///   - priorities: Per-band final priority zero or one; lower bands first within a priority.
    ///   - remainingBits: Caller-computed spare whole bits in `0...frame bits`; must fit the
    ///     current entropy budget. Fewer than channelCount bits leave the current band untouched.
    ///   - encoder: Active entropy owner after shape coding; consumes at most one bit per
    ///     active channel/band, preserving the encoded residual's sign.
    /// - Returns: Refined envelope/residuals; callers derive used bits from entropy accounting.
    /// - Throws: Energy/allocation/remaining-bit errors before entropy or coder failures.
    public func encodeFinal(_ state: CELTEnergyEncoding, fineBitCounts: [Int], priorities: [Int],
                            remainingBits: Int, into encoder: inout OpusRangeEncoder) throws -> CELTEnergyEncoding {
        try validateEnergies(state.energies)
        try validateEnergies(state.errors, limit: 65_536)
        try validateFinal(fineBitCounts, priorities: priorities, remaining: remainingBits,
                          budget: max(0, encoder.frameByteCount * 8 - encoder.bitsUsed))
        var energies = Array(state.energies)
        var errors = Array(state.errors)
        var remaining = remainingBits
        for priority in 0...1 {
            for band in startBand..<endBand {
                guard remaining >= channelCount, fineBitCounts[band] < 8, priorities[band] == priority else { continue }
                for channel in 0..<channelCount {
                    let index = channel * bandCount + band
                    let positive = errors[index] >= 0
                    try encoder.encodeRawBits(positive ? 1 : 0, count: 1)
                    let offset = (positive ? Float(0.5) : -0.5) / Float(1 << (fineBitCounts[band] + 1))
                    energies[index] += offset
                    errors[index] -= offset
                    remaining -= 1
                }
            }
        }
        return CELTEnergyEncoding(energies: energies, errors: errors, intra: state.intra)
    }

    /// Decodes final priority refinement after all shape entropy operations.
    /// - Parameters:
    ///   - energies: Valid current channel-major envelope, copied into returned storage.
    ///   - fineBitCounts: Per-band fine precision in `0...8`, matching the encoder.
    ///   - priorities: Exactly bandCount priorities, each zero or one.
    ///   - remainingBits: Spare raw-bit budget computed by the enclosing decoder; nonnegative
    ///     and no greater than remaining frame bits. Incomplete channel groups remain unused.
    ///   - decoder: Matching entropy owner after shape syntax.
    /// - Returns: Refined owned envelope; no cross-frame history is retained by this value.
    /// - Throws: Validation errors atomically or caller-owned range decoder failures.
    public func decodeFinal(energies: [Float], fineBitCounts: [Int], priorities: [Int],
                            remainingBits: Int, from decoder: inout OpusRangeDecoder) throws -> [Float] {
        try validateEnergies(energies)
        try validateFinal(fineBitCounts, priorities: priorities, remaining: remainingBits,
                          budget: max(0, decoder.frame.count * 8 - decoder.bitsUsed))
        var result = Array(energies)
        var remaining = remainingBits
        for priority in 0...1 {
            for band in startBand..<endBand {
                guard remaining >= channelCount, fineBitCounts[band] < 8, priorities[band] == priority else { continue }
                for channel in 0..<channelCount {
                    let bit = try decoder.decodeRawBits(count: 1)
                    let offset = (Float(bit) - 0.5) / Float(1 << (fineBitCounts[band] + 1))
                    result[channel * bandCount + band] += offset
                    remaining -= 1
                }
            }
        }
        return result
    }

    /// Rejects malformed lengths, nonfinite values and unreasonable log-domain magnitudes.
    /// - Parameters:
    ///   - values: Channel-major energy or residual array with exact configured stride.
    ///   - limit: Inclusive absolute magnitude, default 32,768 for energies; encoder
    ///     residuals use 65,536 so every admitted coarse input can proceed to refinement.
    /// - Throws: `invalidEnergies` without entropy changes; bounded inputs keep integer rounding safe.
    private func validateEnergies(_ values: [Float], limit: Float = 32_768) throws {
        guard values.count == channelCount * bandCount,
              values.allSatisfy({ $0.isFinite && (-limit...limit).contains($0) }) else {
            throw CELTEnergyQuantizerError.invalidEnergies
        }
    }

    /// Validates complete per-band successive fine precision before any field is read/written.
    /// - Parameters:
    ///   - counts: Extra fine bits per band in zero through eight.
    ///   - previous: Optional previous precision, with sums bounded to eight.
    /// - Returns: Dense existing precision, defaulting to zero for every band.
    /// - Throws: `invalidBitAllocation` for malformed lengths, values or precision sums.
    private func validateFine(_ counts: [Int], previous: [Int]?) throws -> [Int] {
        let prior = previous ?? Array(repeating: 0, count: bandCount)
        guard counts.count == bandCount, prior.count == bandCount,
              counts.allSatisfy({ (0...8).contains($0) }), prior.allSatisfy({ (0...8).contains($0) }),
              zip(counts, prior).allSatisfy({ $0 + $1 <= 8 }) else {
            throw CELTEnergyQuantizerError.invalidBitAllocation
        }
        return prior
    }

    /// Validates final precision/priority and spare-budget context before entropy mutation.
    /// - Parameters:
    ///   - counts: Per-band accumulated fine precision in zero through eight.
    ///   - priorities: Per-band zero/one priorities.
    ///   - remaining: Spare raw bits supplied by the enclosing shape allocator.
    ///   - budget: Nonnegative current whole-bit budget derived from the entropy frame.
    /// - Throws: `invalidBitAllocation` or `invalidRemainingBits`, with no side effects.
    private func validateFinal(_ counts: [Int], priorities: [Int], remaining: Int, budget: Int) throws {
        _ = try validateFine(counts, previous: nil)
        guard priorities.count == bandCount, priorities.allSatisfy({ (0...1).contains($0) }) else {
            throw CELTEnergyQuantizerError.invalidBitAllocation
        }
        guard remaining >= 0, remaining <= budget else { throw CELTEnergyQuantizerError.invalidRemainingBits }
    }

    /// Expands one ordinary CELT Laplace density to its exact finite signed-symbol context.
    ///
    /// A total of 32,768 reproduces range>>15 interval arithmetic. Symbols are ordered
    /// 0,-1,+1,-2,+2,..., including the minimum-frequency tail and any final partial pair.
    /// Ordinary parameters produce fewer than 256 symbols; no arbitrary contexts are admitted.
    /// - Parameters:
    ///   - zeroFrequency: Ordinary model's positive zero frequency, scaled from Q8 to Q15.
    ///   - decay: Ordinary model's positive decay scaled from Q8 to Q14.
    /// - Returns: Exact immutable frequency model and matching signed integer residuals.
    /// - Throws: Probability validation errors if the compiled normative tables are invalid.
    private static func laplaceContext(zeroFrequency: Int, decay: Int) throws -> (OpusProbabilityModel, [Int]) {
        var frequencies = [UInt32(zeroFrequency)]
        var deltas = [0]
        var remaining = 32768 - zeroFrequency
        var frequency = ((32768 - 32 - zeroFrequency) * (16384 - decay)) >> 15
        frequency += 1
        var magnitude = 1
        while remaining > 0 {
            for sign in [-1, 1] where remaining > 0 {
                let admitted = min(frequency, remaining)
                frequencies.append(UInt32(admitted))
                deltas.append(sign * magnitude)
                remaining -= admitted
            }
            frequency = (((frequency * 2 - 2) * decay) >> 15) + 1
            magnitude += 1
        }
        return (try OpusProbabilityModel(frequencies: frequencies), deltas)
    }
    private static let probabilityParameters: [[[Int]]] = [
        [
            [72, 127, 65, 129, 66, 128, 65, 128, 64, 128, 62, 128, 64, 128, 64, 128, 92, 78, 92, 79, 92, 78, 90, 79, 116, 41, 115, 40, 114, 40, 132, 26, 132, 26, 145, 17, 161, 12, 176, 10, 177, 11],
            [24, 179, 48, 138, 54, 135, 54, 132, 53, 134, 56, 133, 55, 132, 55, 132, 61, 114, 70, 96, 74, 88, 75, 88, 87, 74, 89, 66, 91, 67, 100, 59, 108, 50, 120, 40, 122, 37, 97, 43, 78, 50]
        ],
        [
            [83, 78, 84, 81, 88, 75, 86, 74, 87, 71, 90, 73, 93, 74, 93, 74, 109, 40, 114, 36, 117, 34, 117, 34, 143, 17, 145, 18, 146, 19, 162, 12, 165, 10, 178, 7, 189, 6, 190, 8, 177, 9],
            [23, 178, 54, 115, 63, 102, 66, 98, 69, 99, 74, 89, 71, 91, 73, 91, 78, 89, 86, 80, 92, 66, 93, 64, 102, 59, 103, 60, 104, 60, 117, 52, 123, 44, 138, 35, 133, 31, 97, 38, 77, 45]
        ],
        [
            [61, 90, 93, 60, 105, 42, 107, 41, 110, 45, 116, 38, 113, 38, 112, 38, 124, 26, 132, 27, 136, 19, 140, 20, 155, 14, 159, 16, 158, 18, 170, 13, 177, 10, 187, 8, 192, 6, 175, 9, 159, 10],
            [21, 178, 59, 110, 71, 86, 75, 85, 84, 83, 91, 66, 88, 73, 87, 72, 92, 75, 98, 72, 105, 58, 107, 54, 115, 52, 114, 55, 112, 56, 129, 51, 132, 40, 150, 33, 140, 29, 98, 35, 77, 42]
        ],
        [
            [42, 121, 96, 66, 108, 43, 111, 40, 117, 44, 123, 32, 120, 36, 119, 33, 127, 33, 134, 34, 139, 21, 147, 23, 152, 20, 158, 25, 154, 26, 166, 21, 173, 16, 184, 13, 184, 10, 150, 13, 139, 15],
            [22, 178, 63, 114, 74, 82, 84, 83, 92, 82, 103, 62, 96, 72, 96, 67, 101, 73, 107, 72, 113, 55, 118, 52, 125, 52, 118, 52, 117, 55, 135, 49, 137, 39, 157, 32, 145, 29, 97, 33, 77, 40]
        ]
    ]

}
