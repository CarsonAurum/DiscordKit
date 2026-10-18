/*
Copyright (c) 2006-2011, Skype Limited. All rights reserved.
Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions
are met:
- Redistributions of source code must retain the above copyright notice,
this list of conditions and the following disclaimer.
- Redistributions in binary form must reproduce the above copyright
notice, this list of conditions and the following disclaimer in the
documentation and/or other materials provided with the distribution.
- Neither the name of Internet Society, IETF or IETF Trust, nor the
names of specific contributors, may be used to endorse or promote
products derived from this software without specific prior written
permission.
THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
POSSIBILITY OF SUCH DAMAGE.
*/


/// Configuration failures before bounded SILK parameter entropy decoding starts.
public enum SILKFrameParameterError: Error, Sendable, Equatable {
    case invalidSampleRate
    case invalidFrameDuration
    case invalidPreviousGainIndex
}

/// Whether a SILK channel frame uses absolute or inter-frame parameter coding.
public enum SILKParameterCoding: Int, Sendable, CaseIterable {
    /// Independent gains/pitch and an explicit voiced LTP scaling symbol.
    case independent = 0
    /// Independent gains/pitch, omitting LTP scaling as required by its packet context.
    case independentWithoutLTPScaling = 1
    /// Conditional first gain and eligible voiced pitch delta; omits LTP scaling.
    case conditional = 2
}

/// Decoded SILK channel-frame parameters and normative fixed-point reconstructions.
///
/// This value supplies the gain, normalized LSF, pitch and LTP inputs to synthesis.
/// It retains the entropy indices for independent auditing. It contains no PCM,
/// previous LPC/output history, interpolation/reset policy, PLC or packet headers.
public struct SILKFrameParameters: Sendable, Equatable {
    public let signalType: SILKSignalType
    public let quantizationOffset: SILKQuantizationOffset
    /// Two or four gain symbols: an absolute first index unless coding conditionally.
    public let gainIndices: [Int]
    /// First-stage normalized LSF vector index in `0...31`.
    public let normalizedLSFCodebookIndex: Int
    /// Backward-predicted NLSF residual indices, each in `-10...10`.
    public let normalizedLSFResidualIndices: [Int]
    /// Quarter interpolation factor in `0...4`; ten-millisecond frames always use four.
    public let interpolationQ2: Int
    /// Unclamped primary lag index, preserving the reference's signed sixteen-bit state.
    public let pitchLagIndex: Int16?
    public let pitchContourIndex: Int?
    public let periodicityIndex: Int?
    public let longTermGainIndices: [Int]
    public let longTermScaleIndex: Int?
    /// Two-bit excitation seed in `0...3`.
    public let seed: UInt8
    /// Positive fixed-point subframe gains, exactly matching scalar `silk_gains_dequant`.
    public let gainsQ16: [Int32]
    /// Stabilized ordered normalized LSFs, in `0...32767`, with normative spacing.
    public let normalizedLSFsQ15: [Int16]
    /// Final contour-adjusted/clamped pitch per subframe, or zeros when unvoiced.
    public let pitchLags: [Int]
    /// Five signed Q7 prediction taps per subframe, zero-filled when unvoiced.
    public let longTermCoefficientsQ7: [[Int8]]
    /// Voiced LTP history scale in Q14; zero for inactive/unvoiced frames.
    public let longTermScaleQ14: Int16
}

/// One complete SILK channel's parameter/pulse syntax and exact Q23 excitation.
///
/// Enclosing packet flags, stereo side information, gain/LPC/LTP synthesis, output
/// rate conversion, PLC/FEC and full-codec conformance remain separate operations.
public struct SILKDecodedExcitation: Sendable, Equatable {
    public let parameters: SILKFrameParameters
    public let pulses: SILKPulseFrame
    public let excitationQ23: [Int32]
}

/// Owned stateful decoding of RFC 6716 sections 4.2.7.3 through 4.2.7.7.
///
/// Decodes frame type, gain/NLSF/pitch/LTP indices and seed; reconstructs exact
/// scalar gains, stabilized Q15 LSFs, contour pitch and Q7 LTP taps. Optional
/// composition also parses all pulses and produces exact Q23 excitation. A caller
/// positions entropy after the enclosing packet/stereo flags and supplies its VAD,
/// LBRR and conditional-coding decisions. This does not infer those packet policies.
///
/// Each instance owns one channel's bounded previous gain/type/lag state. Mutations
/// are synchronous and serialized by the caller. Every decoding operation copies
/// both state and entropy, committing only on full success. Construction/reset start
/// no I/O/tasks, use no native codec, and retain no PCM or unbounded stream history.
public struct SILKFrameParameterDecoder: Sendable {
    /// Internal SILK channel rate: exactly 8,000, 12,000 or 16,000 Hz.
    public let sampleRate: Int
    /// Internal channel frame length: exactly ten or twenty milliseconds.
    public let frameDurationMilliseconds: Int
    /// Number of five-millisecond subframes, either two or four.
    public var subframeCount: Int { frameDurationMilliseconds / 5 }
    /// Number of output channel samples, excluding mediumband shell padding.
    public var sampleCount: Int { sampleRate * frameDurationMilliseconds / 1_000 }
    /// Normative LPC/NLSF order: ten for NB/MB and sixteen for WB.
    public var normalizedLSFOrder: Int { sampleRate == 16_000 ? 16 : 10 }
    /// Last dequantized gain index in `0...63`, carried across independent frames too.
    public private(set) var previousGainIndex: Int
    public private(set) var previousSignalType: SILKSignalType
    /// Last voiced primary lag index. Unvoiced frames preserve this previous lag.
    public private(set) var previousPitchLagIndex: Int16

    /// Creates one explicitly configured channel's parameter state, without entropy work.
    /// - Parameters:
    ///   - sampleRate: Internal 8,000/12,000/16,000 Hz rate, not the final PCM rate.
    ///   - frameDurationMilliseconds: Ten or twenty; 40/60 ms packets contain multiple
    ///     internal frames whose headers and coding conditions are handled above this type.
    ///   - previousGainIndex: Previous scalar gain index in `0...63`, default zero.
    ///   - previousSignalType: Previous entropy frame category, default inactive.
    ///   - previousPitchLagIndex: Previous signed sixteen-bit voiced lag index, default
    ///     zero; final pitch reconstruction clamps even malformed relative lag histories.
    /// - Throws: `invalidSampleRate`, `invalidFrameDuration` or `invalidPreviousGainIndex`
    ///   before allocating state. Instances never share mutable tables or history.
    public init(
        sampleRate: Int,
        frameDurationMilliseconds: Int,
        previousGainIndex: Int = 0,
        previousSignalType: SILKSignalType = .inactive,
        previousPitchLagIndex: Int16 = 0
    ) throws {
        guard [8_000, 12_000, 16_000].contains(sampleRate) else { throw SILKFrameParameterError.invalidSampleRate }
        guard frameDurationMilliseconds == 10 || frameDurationMilliseconds == 20 else {
            throw SILKFrameParameterError.invalidFrameDuration
        }
        guard (0...63).contains(previousGainIndex) else { throw SILKFrameParameterError.invalidPreviousGainIndex }
        self.sampleRate = sampleRate
        self.frameDurationMilliseconds = frameDurationMilliseconds
        self.previousGainIndex = previousGainIndex
        self.previousSignalType = previousSignalType
        self.previousPitchLagIndex = previousPitchLagIndex
    }

    /// Clears inter-frame entropy/gain history while preserving rate and frame duration.
    /// The caller resets its associated synthesis/stereo/resampling histories separately.
    /// This synchronous no-failure operation performs no I/O or decoding.
    public mutating func reset() {
        previousGainIndex = 0
        previousSignalType = .inactive
        previousPitchLagIndex = 0
    }

    /// Decodes parameter syntax through the seed, leaving entropy at the pulse rate level.
    /// - Parameters:
    ///   - decoder: Opus entropy state positioned at this channel frame's type symbol.
    ///   - voiceActivity: Previously decoded packet VAD flag for this frame/channel.
    ///   - lowBitrateRedundancy: Whether this is LBRR syntax; true forces active type
    ///     context regardless of VAD. Defaults false; this parses parameters, not FEC policy.
    ///   - coding: Packet-selected parameter coding mode, default independent.
    /// - Returns: Exact indices and bounded reconstructed synthesis inputs. Frame reset,
    ///   NLSF interpolation with prior frames and post-loss bandwidth expansion are not
    ///   applied here, because they depend on the enclosing synthesis lifecycle.
    /// - Throws: Range operation/state or internal table-validation errors. Failed calls
    ///   preserve the caller's coder and every previous-channel-state field atomically.
    ///   Entropy zero extension is normative; finite output does not authenticate data
    ///   or reliably identify truncated syntax.
    /// - Complexity: O(order squared + subframes) work with at most sixteen LSFs,
    ///   twenty stabilization passes and fixed fallback sort/storage; no suspension.
    public mutating func decode(
        from decoder: inout OpusRangeDecoder,
        voiceActivity: Bool,
        lowBitrateRedundancy: Bool = false,
        coding: SILKParameterCoding = .independent
    ) throws -> SILKFrameParameters {
        var entropy = decoder
        let typeOffset = try entropy.decodeSymbol(model: Self.model(
            voiceActivity || lowBitrateRedundancy ? SILKParameterTables.typeActive : SILKParameterTables.typeInactive
        )) + (voiceActivity || lowBitrateRedundancy ? 2 : 0)
        let signal = SILKSignalType(rawValue: typeOffset >> 1)!
        let offset = SILKQuantizationOffset(rawValue: typeOffset & 1)!
        var gains: [Int] = []
        if coding == .conditional {
            gains.append(try entropy.decodeSymbol(model: Self.model(SILKParameterTables.gainDelta)))
        } else {
            let high = try entropy.decodeSymbol(model: Self.model(Array(SILKParameterTables.gain[(signal.rawValue * 8)..<(signal.rawValue * 8 + 8)])))
            let low = try entropy.decodeSymbol(model: Self.model(SILKParameterTables.uniform8))
            gains.append(high * 8 + low)
        }
        for _ in 1..<subframeCount {
            gains.append(try entropy.decodeSymbol(model: Self.model(SILKParameterTables.gainDelta)))
        }
        let wide = sampleRate == 16_000
        let firstTable = wide ? SILKParameterTables.wideStage1 : SILKParameterTables.narrowStage1
        let firstOffset = (signal.rawValue >> 1) * 32
        let first = try entropy.decodeSymbol(model: Self.model(Array(firstTable[firstOffset..<(firstOffset + 32)])))
        let unpacked = unpackNLSF(firstStage: first)
        let residualTable = wide ? SILKParameterTables.wideStage2 : SILKParameterTables.narrowStage2
        var residuals: [Int] = []
        for context in unpacked.contexts {
            var symbol = try entropy.decodeSymbol(model: Self.model(Array(residualTable[context..<(context + 9)])))
            if symbol == 0 {
                symbol -= try entropy.decodeSymbol(model: Self.model(SILKParameterTables.nlsfExtension))
            } else if symbol == 8 {
                symbol += try entropy.decodeSymbol(model: Self.model(SILKParameterTables.nlsfExtension))
            }
            residuals.append(symbol - 4)
        }
        let interpolation = subframeCount == 4
            ? try entropy.decodeSymbol(model: Self.model(SILKParameterTables.interpolation)) : 4
        var lagIndex: Int16?
        var contour: Int?
        var periodicity: Int?
        var ltpIndices: [Int] = []
        var scale: Int?
        if signal == .voiced {
            if coding == .conditional, previousSignalType == .voiced {
                let delta = try entropy.decodeSymbol(model: Self.model(SILKParameterTables.pitchDelta))
                if delta > 0 { lagIndex = Int16(truncatingIfNeeded: Int(previousPitchLagIndex) + delta - 9) }
            }
            if lagIndex == nil {
                let high = try entropy.decodeSymbol(model: Self.model(SILKParameterTables.pitchLag))
                let low = try entropy.decodeSymbol(model: Self.model(pitchLowTable()))
                lagIndex = Int16(high * (sampleRate / 2_000) + low)
            }
            contour = try entropy.decodeSymbol(model: Self.model(pitchContourTable()))
            let category = try entropy.decodeSymbol(model: Self.model(SILKParameterTables.periodicity))
            periodicity = category
            let ltp = category == 0 ? SILKParameterTables.ltp0 : (category == 1 ? SILKParameterTables.ltp1 : SILKParameterTables.ltp2)
            for _ in 0..<subframeCount { ltpIndices.append(try entropy.decodeSymbol(model: Self.model(ltp))) }
            scale = coding == .independent ? try entropy.decodeSymbol(model: Self.model(SILKParameterTables.ltpScale)) : 0
        }
        let seed = try entropy.decodeSymbol(model: Self.model(SILKParameterTables.uniform4))
        let dequantizedGains = dequantizeGains(gains, conditional: coding == .conditional)
        let nlsfs = reconstructNLSF(firstStage: first, residuals: residuals, prediction: unpacked.prediction)
        var pitch = Array(repeating: 0, count: subframeCount)
        var coefficients = Array(repeating: Array(repeating: Int8(0), count: 5), count: subframeCount)
        if let lagIndex, let contour, let periodicity {
            let contourValues = pitchContourValues()
            let columns = contourValues.count / subframeCount
            let minimum = sampleRate * 2 / 1_000
            let maximum = sampleRate * 18 / 1_000
            let ltpVectors = periodicity == 0 ? SILKParameterTables.ltpVector0
                : (periodicity == 1 ? SILKParameterTables.ltpVector1 : SILKParameterTables.ltpVector2)
            for subframe in 0..<subframeCount {
                pitch[subframe] = min(maximum, max(minimum, minimum + Int(lagIndex) + contourValues[subframe * columns + contour]))
                coefficients[subframe] = ltpVectors[(ltpIndices[subframe] * 5)..<(ltpIndices[subframe] * 5 + 5)].map { Int8($0) }
            }
        }
        let result = SILKFrameParameters(
            signalType: signal, quantizationOffset: offset, gainIndices: gains,
            normalizedLSFCodebookIndex: first, normalizedLSFResidualIndices: residuals, interpolationQ2: interpolation,
            pitchLagIndex: lagIndex, pitchContourIndex: contour, periodicityIndex: periodicity,
            longTermGainIndices: ltpIndices, longTermScaleIndex: scale, seed: UInt8(seed),
            gainsQ16: dequantizedGains.values, normalizedLSFsQ15: nlsfs, pitchLags: pitch,
            longTermCoefficientsQ7: coefficients, longTermScaleQ14: scale.map { Int16([15_565, 12_288, 8_192][$0]) } ?? 0
        )
        previousGainIndex = dequantizedGains.last
        previousSignalType = signal
        if let lagIndex { previousPitchLagIndex = lagIndex }
        decoder = entropy
        return result
    }

    /// Parses complete parameter/pulse syntax and reconstructs exact seeded excitation.
    /// - Parameters:
    ///   - decoder: Range coder positioned after enclosing packet/stereo side information.
    ///   - voiceActivity: This channel frame's previously parsed VAD flag.
    ///   - lowBitrateRedundancy: LBRR parameter syntax selection, default false.
    ///   - coding: Enclosing packet's independent/conditional coding choice.
    /// - Returns: Parameters, signed pulse metadata and one Q23 excitation per sample.
    /// - Throws: Parameter/range/pulse errors. No caller entropy or channel state changes
    ///   unless both syntax sections and excitation reconstruction succeed. This method
    ///   supplies residual input, not audible PCM, packet-loss concealment or FEC policy.
    public mutating func decodeExcitation(
        from decoder: inout OpusRangeDecoder,
        voiceActivity: Bool,
        lowBitrateRedundancy: Bool = false,
        coding: SILKParameterCoding = .independent
    ) throws -> SILKDecodedExcitation {
        var channel = self
        var entropy = decoder
        let parameters = try channel.decode(from: &entropy, voiceActivity: voiceActivity, lowBitrateRedundancy: lowBitrateRedundancy, coding: coding)
        let pulses = try SILKPulseCoding.decode(from: &entropy, sampleCount: sampleCount, signalType: parameters.signalType, quantizationOffset: parameters.quantizationOffset)
        let result = SILKDecodedExcitation(parameters: parameters, pulses: pulses, excitationQ23: try pulses.reconstructExcitation(seed: parameters.seed))
        self = channel
        decoder = entropy
        return result
    }

    /// Builds a validated exact 256-total model from fixed normative parameter tables.
    /// - Parameter table: Finite nonincreasing inverse CDF ending at zero.
    /// - Returns: Immutable counts preserving all normative probabilities.
    /// - Throws: Range-model errors if internally audited constants become corrupted.
    private static func model(_ table: [Int]) throws -> OpusProbabilityModel {
        try OpusProbabilityModel(inverseCDF: table.map { UInt8($0) })
    }

    /// Selects absolute pitch low-bit syntax for four, six or eight rate-dependent values.
    /// - Returns: Exact uniform iCDF, including mediumband's non-power-of-two context.
    private func pitchLowTable() -> [Int] {
        sampleRate == 8_000 ? SILKParameterTables.uniform4
            : (sampleRate == 12_000 ? SILKParameterTables.uniform6 : SILKParameterTables.uniform8)
    }

    /// Selects the exact contour symbol context for this channel rate/frame duration.
    /// - Returns: A three/eleven-symbol NB or twelve/thirty-four-symbol MB/WB iCDF.
    private func pitchContourTable() -> [Int] {
        if sampleRate == 8_000 {
            return subframeCount == 2 ? SILKParameterTables.contourNarrow10 : SILKParameterTables.contourNarrow20
        }
        return subframeCount == 2 ? SILKParameterTables.contourWide10 : SILKParameterTables.contourWide20
    }

    /// Selects subframe-major pitch-contour offsets in internal channel samples.
    /// - Returns: Flattened table whose column count matches `pitchContourTable()`.
    private func pitchContourValues() -> [Int] {
        if sampleRate == 8_000 {
            return subframeCount == 2 ? SILKParameterTables.pitchNarrow10 : SILKParameterTables.pitchNarrow20
        }
        return subframeCount == 2 ? SILKParameterTables.pitchWide10 : SILKParameterTables.pitchWide20
    }

    /// Unpacks two entropy contexts and backward predictors per packed codebook byte.
    /// - Parameter firstStage: A previously decoded first-stage vector index in `0...31`.
    /// - Returns: One stage-two iCDF start and Q8 predictor per NLSF coefficient.
    private func unpackNLSF(firstStage: Int) -> (contexts: [Int], prediction: [Int]) {
        let wide = sampleRate == 16_000
        let selection = wide ? SILKParameterTables.wideSelection : SILKParameterTables.narrowSelection
        let predictions = wide ? SILKParameterTables.widePrediction : SILKParameterTables.narrowPrediction
        let order = normalizedLSFOrder
        var contexts: [Int] = []
        var prediction: [Int] = []
        for pair in 0..<(order / 2) {
            let entry = selection[firstStage * order / 2 + pair]
            let index = pair * 2
            contexts.append(((entry >> 1) & 7) * 9)
            contexts.append(((entry >> 5) & 7) * 9)
            prediction.append(predictions[index + (entry & 1) * (order - 1)])
            prediction.append(predictions[index + ((entry >> 4) & 1) * (order - 1) + 1])
        }
        return (contexts, prediction)
    }

    /// Reconstructs normalized LSFs with exact residual prediction, weighting and spacing.
    /// - Parameters:
    ///   - firstStage: Codebook vector in `0...31`.
    ///   - residuals: Exactly `order` decoded values in `-10...10`.
    ///   - prediction: Corresponding order-length backward Q8 predictor array.
    /// - Returns: Stabilized ascending signed Q15 normalized frequencies.
    private func reconstructNLSF(firstStage: Int, residuals: [Int], prediction: [Int]) -> [Int16] {
        let wide = sampleRate == 16_000
        let order = normalizedLSFOrder
        let step = wide ? 9_830 : 11_796
        let vectors = wide ? SILKParameterTables.wideVectors : SILKParameterTables.narrowVectors
        let weights = wide ? SILKParameterTables.wideWeights : SILKParameterTables.narrowWeights
        let deltas = wide ? SILKParameterTables.wideDeltas : SILKParameterTables.narrowDeltas
        var values = Array(repeating: 0, count: order)
        var previous = 0
        for index in stride(from: order - 1, through: 0, by: -1) {
            let predicted = (previous * prediction[index]) >> 8
            var quantized = residuals[index] * 1_024
            if quantized > 0 { quantized -= 102 }
            if quantized < 0 { quantized += 102 }
            previous = predicted + ((quantized * step) >> 16)
            let slot = firstStage * order + index
            let value = (previous * 16_384) / weights[slot] + vectors[slot] * 128
            values[index] = min(32_767, max(0, value))
        }
        return Self.stabilize(values, minimumDistances: deltas).map { Int16($0) }
    }

    /// Enforces normative border/inter-frequency distances with bounded least movement.
    /// - Parameters:
    ///   - input: Ten or sixteen Q15 frequencies, initially clamped into `0...32767`.
    ///   - minimumDistances: Matching order-plus-one normative border/gap requirements.
    /// - Returns: Stable ordered frequencies. After twenty worst-gap repairs, bounded
    ///   sorting and forward/backward spacing provide the normative fallback.
    private static func stabilize(_ input: [Int], minimumDistances: [Int]) -> [Int] {
        var values = input
        let order = values.count
        for _ in 0..<20 {
            var worst = values[0] - minimumDistances[0]
            var position = 0
            for index in 1..<order {
                let gap = values[index] - values[index - 1] - minimumDistances[index]
                if gap < worst { worst = gap; position = index }
            }
            let upperGap = 32_768 - values[order - 1] - minimumDistances[order]
            if upperGap < worst { worst = upperGap; position = order }
            if worst >= 0 { return values }
            if position == 0 {
                values[0] = minimumDistances[0]
            } else if position == order {
                values[order - 1] = 32_768 - minimumDistances[order]
            } else {
                let halfGap = minimumDistances[position] >> 1
                let lower = minimumDistances[..<position].reduce(0, +) + halfGap
                let upper = 32_768 - minimumDistances[(position + 1)...order].reduce(0, +) - halfGap
                let center = min(upper, max(lower, (values[position - 1] + values[position] + 1) >> 1))
                values[position - 1] = center - halfGap
                values[position] = values[position - 1] + minimumDistances[position]
            }
        }
        values.sort()
        values[0] = max(values[0], minimumDistances[0])
        for index in 1..<order { values[index] = max(values[index], min(32_767, values[index - 1] + minimumDistances[index])) }
        values[order - 1] = min(values[order - 1], 32_768 - minimumDistances[order])
        for index in stride(from: order - 2, through: 0, by: -1) {
            values[index] = min(values[index], values[index + 1] - minimumDistances[index + 1])
        }
        return values
    }

    /// Applies absolute/delta scalar gain reconstruction with double-step large rises.
    /// - Parameters:
    ///   - indices: Two/four bounded gain symbols matching the coding choice.
    ///   - conditional: Whether the first symbol is delta rather than absolute.
    /// - Returns: Positive Q16 gains and the last clamped gain index for state commit.
    private func dequantizeGains(_ indices: [Int], conditional: Bool) -> (values: [Int32], last: Int) {
        var previous = previousGainIndex
        var values: [Int32] = []
        // Normative integer constants: OFFSET=(2*128)/6+16*128, INV_SCALE_Q16
        // =(65536*((88-2)*128/6))/63; truncation occurs in this exact order.
        let offset = 2_090
        let inverseScale = 1_907_825
        for (index, symbol) in indices.enumerated() {
            if index == 0, !conditional {
                previous = max(symbol, previous - 16)
            } else {
                let delta = symbol - 4
                let threshold = 8 + previous
                previous += delta > threshold ? 2 * delta - threshold : delta
            }
            previous = min(63, max(0, previous))
            values.append(Self.logToLinear(min((inverseScale * previous) >> 16, 3_967 - offset) + offset))
        }
        return (values, previous)
    }

    /// Evaluates SILK's exact bounded piecewise parabolic Q7-logarithm inverse.
    /// - Parameter logarithmQ7: Positive scalar gain logarithm capped at 3,967.
    /// - Returns: Saturated nonnegative signed Q16 gain, with scalar integer rounding.
    private static func logToLinear(_ logarithmQ7: Int) -> Int32 {
        if logarithmQ7 >= 3_967 { return Int32.max }
        let base = 1 << (logarithmQ7 >> 7)
        let fraction = logarithmQ7 & 127
        let curve = fraction + ((fraction * (128 - fraction) * -174) >> 16)
        let result = logarithmQ7 < 2_048 ? base + ((base * curve) >> 7) : base + (base >> 7) * curve
        return Int32(result)
    }
}
