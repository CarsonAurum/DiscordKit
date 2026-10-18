import Foundation

/// Admission failures from the conservative ordinary mono SILK PCM encoder.
public enum SILKMonoEncoderError: Error, Sendable, Equatable {
    case invalidSampleCount
    case invalidPayloadByteLimit
    case invalidPayloadBitLimit
    case payloadBudgetExceeded
}

/// One retained active frame carried as next-packet low-bitrate redundancy.
/// Parameters and pulses use ordinary independent SILK channel syntax. The encoder
/// owns this bounded previous-frame value; it contains no native resources or PCM.
public struct SILKRedundantFrame: Sendable, Equatable {
    public let parameters: SILKFrameParameters
    public let signedPulses: [Int16]
}

/// One encoded mono SILK payload, before enclosing Opus framing or hybrid CELT data.
public struct SILKEncodedPayload: Sendable, Equatable {
    /// Active preceding frame carried before ordinary audio, or nil without LBRR.
    public let redundancy: SILKRedundantFrame?
    public let parameters: SILKFrameParameters
    public let signedPulses: [Int16]
    public let reconstructedPCM: [Int16]
    public let finalRange: UInt32
    public let bitsUsed: Int
}

/// One owned ordinary mono SILK packet and its exact local reconstruction evidence.
public struct SILKEncodedPacket: Sendable, Equatable {
    public let packet: OpusPacket
    public let parameters: SILKFrameParameters
    public let signedPulses: [Int16]
    /// Exact internal-rate scalar SILK reconstruction, before output-rate conversion.
    public let reconstructedPCM: [Int16]
    public let finalRange: UInt32
    public let bitsUsed: Int
}

/// Conservative owned PCM16-to-ordinary-SILK encoder with bounded rate admission.
///
/// Selects a stable quantized spectral vector by minimum prediction residual over
/// all 32 first-stage NLSF vectors, chooses scalar gain from the residual energy,
/// selects real voiced pitch/five-tap LTP codebooks from correlated LPC residuals,
/// and quantizes seeded excitation against exact integer LPC/LTP synthesis feedback.
/// The resulting Opus code-zero packet contains ordinary interoperable voiced,
/// unvoiced or inactive SILK syntax at 8/12/16 kHz and ten/twenty milliseconds.
/// Spectral residual indices are zero and interpolation is disabled. Stereo,
/// perceptual delayed-decision noise shaping and DTX are separate policies. Optional
/// FEC carries the preceding active frame as ordinary independent SILK LBRR.
/// This is a working restricted encoder, not full Opus encoder conformance or
/// reference speech-quality/rate-control equivalence. Input resampling is separate.
///
/// Each value owns one stream's finite gain and short-term synthesis history.
/// Construction caches 32 predictors and 64 gains without I/O, tasks or native
/// codec linkage. Mutation is synchronous and caller-serialized. Calls copy state
/// and commit only after complete framing and exact local decoding succeed.
public struct SILKMonoEncoder: Sendable {
    public let sampleRate: Int
    public let frameDurationMilliseconds: Int
    /// Maximum compressed SILK bytes, excluding the single-byte Opus TOC.
    public let maximumPayloadBytes: Int
    /// Carries the preceding active frame as independent next-packet SILK LBRR.
    public let enableInBandFEC: Bool
    /// Exactly 80/120/160/240/320 input samples, according to fixed rate/duration.
    public var sampleCount: Int { sampleRate * frameDurationMilliseconds / 1_000 }
    public private(set) var previousGainIndex = 0
    private var synthesis: SILKFrameDecoder
    private let predictors: [[Int16]]
    private let gains: [Double]
    private var analysisHistory: [Int16]
    private var redundantFrame: SILKRedundantFrame?

    /// Creates one stream's fixed-rate encoder and bounded predictor/gain tables.
    /// - Parameters:
    ///   - sampleRate: Exactly 8,000, 12,000 or 16,000 Hz PCM16 input rate.
    ///   - frameDurationMilliseconds: Exactly ten or twenty milliseconds.
    ///   - maximumPayloadBytes: Hard compressed payload cap in `16...1275`, default
    ///     1,275. Larger gains are tried on budget exhaustion, with at most 64 trials.
    ///     Extremely small caps can reject input rather than emit partial packets.
    ///   - enableInBandFEC: Default false. True retains one active frame and emits
    ///     it before the next packet as ordinary independent LBRR. This doubles
    ///     worst-case excitation storage/entropy work; byte/bit caps still apply.
    ///     Insufficient budgets reject atomically rather than silently dropping FEC.
    /// - Throws: `SILKFrameParameterError` for rate/duration, `invalidPayloadByteLimit`
    ///   outside the finite cap, or audited table/NLSF/range errors during caching.
    ///   Initialization starts no background or external work.
    public init(sampleRate: Int, frameDurationMilliseconds: Int = 20, maximumPayloadBytes: Int = 1_275, enableInBandFEC: Bool = false) throws {
        synthesis = try SILKFrameDecoder(sampleRate: sampleRate, frameDurationMilliseconds: frameDurationMilliseconds)
        guard (16...1_275).contains(maximumPayloadBytes) else { throw SILKMonoEncoderError.invalidPayloadByteLimit }
        self.sampleRate = sampleRate
        self.frameDurationMilliseconds = frameDurationMilliseconds
        self.maximumPayloadBytes = maximumPayloadBytes
        self.enableInBandFEC = enableInBandFEC
        var predictors: [[Int16]] = []
        for index in 0..<32 {
            let parameters = try Self.reconstructParameters(
                rate: sampleRate, duration: frameDurationMilliseconds, gain: 0,
                previousGain: 0, spectralIndex: index, active: true
            )
            predictors.append(try SILKNLSFCoefficients(q15: parameters.normalizedLSFsQ15).lpcQ12)
        }
        self.predictors = predictors
        var gains: [Double] = []
        for index in 0..<64 {
            let parameters = try Self.reconstructParameters(
                rate: sampleRate, duration: frameDurationMilliseconds, gain: index,
                previousGain: 0, spectralIndex: 0, active: true
            )
            gains.append(Double(parameters.gainsQ16[0]) / 65_536)
        }
        self.gains = gains
        analysisHistory = Array(repeating: 0, count: sampleRate / 50)
    }

    /// Clears stream gain, LPC/LSF and reconstruction history; cached tables remain.
    /// This idempotent synchronous operation performs no entropy work or I/O. The
    /// next successful frame is byte-identical to a fresh encoder's corresponding input.
    public mutating func reset() {
        synthesis.reset()
        previousGainIndex = 0
        analysisHistory = Array(repeating: 0, count: sampleRate / 50)
        redundantFrame = nil
    }

    /// Encodes exactly one fixed-format PCM16 channel frame into an ordinary Opus packet.
    /// - Parameter pcm: Exactly `sampleCount` signed PCM16 samples at `sampleRate`.
    ///   Every Int16 value, including both extrema, is admissible. Caller input is copied
    ///   only into bounded working arrays; no input/history is retained beyond this frame.
    /// - Returns: Code-zero mono SILK packet, exact indices/pulses, internal-rate PCM16
    ///   reconstruction and entropy accounting. Payload size adapts to the signal and
    ///   never exceeds `maximumPayloadBytes`; this is bounded VBR, not a bitrate promise.
    /// - Throws: `invalidSampleCount` before analysis, `payloadBudgetExceeded` when no
    ///   gain fits the cap, or range/table/NLSF/framing errors. Failure changes no stream
    ///   history. No partial packet, fallback private format, task or I/O is produced.
    /// - Complexity: O(32 * samples * LPC order + 64 * samples) worst-case bounded
    ///   analysis/quantization, plus bounded pitch/codebook analysis, with at most 320 samples and sixteen
    ///   LPC taps. This method
    ///   has no suspension point and makes no realtime deadline guarantee.
    public mutating func encode(_ pcm: [Int16]) throws -> SILKEncodedPacket {
        var working = self
        var sizing = try OpusRangeEncoder(frameByteCount: maximumPayloadBytes)
        let encoded = try working.encodePayload(pcm, to: &sizing)
        let byteCount = max(1, (sizing.bitsUsed + 7) / 8)
        var entropy = try OpusRangeEncoder(frameByteCount: byteCount)
        try writePayload(encoded.parameters, pulses: encoded.signedPulses, to: &entropy)
        let payload = try entropy.finalize()
        let bandwidth = sampleRate == 8_000 ? 0 : (sampleRate == 12_000 ? 4 : 8)
        let configuration = bandwidth + (frameDurationMilliseconds == 10 ? 0 : 1)
        let packet = try OpusPacket(Data([UInt8(configuration << 3)]) + payload)
        self = working
        return SILKEncodedPacket(
            packet: packet, parameters: encoded.parameters, signedPulses: encoded.signedPulses,
            reconstructedPCM: encoded.reconstructedPCM, finalRange: encoded.finalRange,
            bitsUsed: encoded.bitsUsed
        )
    }

    /// Appends one mono SILK payload to a shared Opus entropy stream without finalizing it.
    /// - Parameters:
    ///   - pcm: Exactly `sampleCount` PCM16 input samples at this encoder's internal rate.
    ///   - encoder: Active bounded shared entropy coder. SILK flags/parameters/pulses are
    ///     appended; an enclosing hybrid owner can subsequently write CELT symbols/raw
    ///     bits. Stream positioning and protocol-correct mode composition belong to it.
    ///   - maximumBits: Optional total conservative bit-use ceiling after SILK, including
    ///     any symbols already present. Defaults to the smaller of the shared frame size
    ///     and this encoder's payload cap. Supply a lower bound to reserve CELT capacity.
    /// - Returns: Exact local internal-rate reconstruction and the shared coder's SILK
    ///   endpoint accounting. It contains no TOC and does not finalize the shared stream.
    /// - Throws: `invalidSampleCount`, `invalidPayloadBitLimit` unless the effective cap
    ///   is `1...min(frameByteCount, maximumPayloadBytes) * 8`, `payloadBudgetExceeded`
    ///   if no gain fits, or range/parameter/pulse errors. Failed calls preserve both
    ///   this stream's complete synthesis history and the supplied entropy coder.
    /// - Complexity: At most 64 bounded gain trials after spectral/pitch/codebook analysis, without
    ///   suspension, shared mutable state, background work or external/native calls.
    public mutating func encodePayload(
        _ pcm: [Int16],
        to encoder: inout OpusRangeEncoder,
        maximumBits: Int? = nil
    ) throws -> SILKEncodedPayload {
        guard pcm.count == sampleCount else { throw SILKMonoEncoderError.invalidSampleCount }
        let fullBudget = min(maximumPayloadBytes, encoder.frameByteCount) * 8
        let bitLimit = maximumBits ?? fullBudget
        guard (1...max(1, fullBudget)).contains(bitLimit), fullBudget > 0
        else { throw SILKMonoEncoderError.invalidPayloadBitLimit }
        let analysis = selectPredictor(pcm)
        let active = pcm.contains { $0 != 0 }
        let pitch = active ? selectPitch(pcm, coefficients: predictors[analysis.index], energy: analysis.energy) : nil
        let targetGain = sqrt((pitch?.energy ?? analysis.energy) / Double(sampleCount)) / 3
        let initialGain = gains.firstIndex { $0 >= targetGain } ?? 63
        for gainIndex in initialGain..<64 {
            let parameters = try Self.reconstructParameters(
                rate: sampleRate, duration: frameDurationMilliseconds, gain: gainIndex,
                previousGain: previousGainIndex, spectralIndex: analysis.index, active: active, pitch: pitch
            )
            let pulses = SILKFrameQuantization.quantize(
                pcm, coefficients: predictors[analysis.index], parameters: parameters,
                previousGainQ16: synthesis.previousGainQ16, shortTermHistoryQ14: synthesis.shortTermHistoryQ14,
                outputHistory: synthesis.outputHistory
            )
            do {
                var entropy = encoder
                try writePayload(parameters, pulses: pulses, to: &entropy)
                guard entropy.bitsUsed <= bitLimit else { continue }
                // Reconstruct from a separate bounded stream, so a hybrid caller's
                // preceding/following entropy never becomes synthesis state input.
                var local = try OpusRangeEncoder(frameByteCount: 1_275)
                try writeChannel(parameters, pulses: pulses, to: &local)
                var decoder = try OpusRangeDecoder(frame: local.finalize())
                var working = synthesis
                let reconstructed = try working.decode(from: &decoder, voiceActivity: active)
                let redundant = redundantFrame
                redundantFrame = enableInBandFEC && active
                    ? SILKRedundantFrame(parameters: reconstructed.parameters, signedPulses: reconstructed.pulses.signedPulses) : nil
                synthesis = working
                analysisHistory = Array((analysisHistory + pcm).suffix(sampleRate / 50))
                previousGainIndex = max(gainIndex, previousGainIndex - 16)
                encoder = entropy
                return SILKEncodedPayload(
                    redundancy: redundant, parameters: reconstructed.parameters, signedPulses: reconstructed.pulses.signedPulses,
                    reconstructedPCM: reconstructed.pcm, finalRange: entropy.finalRange,
                    bitsUsed: entropy.bitsUsed
                )
            } catch OpusRangeCodingError.frameBudgetExceeded {
                continue
            }
        }
        throw SILKMonoEncoderError.payloadBudgetExceeded
    }

    /// Chooses a quantized spectral predictor by input-domain squared residual energy.
    /// - Parameter pcm: One validated fixed-format frame, at most 320 PCM16 samples.
    /// - Returns: Lowest-error vector with deterministic lowest-index tie breaking,
    ///   plus its finite nonnegative residual energy for conservative gain selection.
    ///   Prior reconstruction supplies sixteen history samples; input supplies the rest.
    private func selectPredictor(_ pcm: [Int16]) -> (index: Int, energy: Double) {
        let history = Array(synthesis.outputHistory.suffix(16)) + pcm
        var best = (index: 0, energy: Double.infinity)
        for (index, coefficients) in predictors.enumerated() {
            var energy = 0.0
            for sample in pcm.indices {
                var prediction = 0.0
                for tap in coefficients.indices {
                    prediction += Double(history[16 + sample - tap - 1]) * Double(coefficients[tap]) / 4_096
                }
                let residual = Double(pcm[sample]) - prediction
                energy += residual * residual
            }
            if energy < best.energy { best = (index, energy) }
        }
        return best
    }

    /// Selects voiced pitch and quantized five-tap prediction from real LPC residuals.
    /// - Parameters:
    ///   - pcm: One validated internal-rate target frame, with at most 320 samples.
    ///   - coefficients: Stable selected Q12 LPC predictor, with ten/sixteen taps.
    ///   - energy: Unvoiced residual energy used to require an actual coding benefit.
    /// - Returns: Nil for weak, constant or uncorrelated input; otherwise a primary
    ///   pitch lag, common periodicity category and minimum-error tap vector for each
    ///   subframe. The target residual energy then drives gain/budget selection.
    ///   Analysis searches the normative 2...18ms pitch interval and every quantized
    ///   LTP vector. It is a deterministic bounded analysis policy, not the reference
    ///   multistage pitch estimator or perceptual rate/distortion optimization.
    private func selectPitch(_ pcm: [Int16], coefficients: [Int16], energy: Double) -> SILKPitchAnalysis? {
        let mean = pcm.reduce(0.0) { $0 + Double($1) } / Double(pcm.count)
        let variance = pcm.reduce(0.0) { $0 + (Double($1) - mean) * (Double($1) - mean) }
        guard variance > Double(pcm.count) * 10_000, energy > 0 else { return nil }
        let input = analysisHistory + pcm
        let memory = analysisHistory.count
        var residual = Array(repeating: 0.0, count: input.count)
        for index in coefficients.count..<input.count {
            var prediction = 0.0
            for tap in coefficients.indices {
                prediction += Double(input[index - tap - 1]) * Double(coefficients[tap]) / 4_096
            }
            residual[index] = Double(input[index]) - prediction
        }
        let targetEnergy = residual[memory...].reduce(0.0) { $0 + $1 * $1 }
        guard targetEnergy > 0 else { return nil }
        let minimumLag = sampleRate * 2 / 1_000
        var bestLag = minimumLag
        var bestCorrelation = 0.0
        for lag in minimumLag...(sampleRate * 18 / 1_000) {
            var correlation = 0.0
            var delayedEnergy = 0.0
            for index in memory..<input.count {
                let delayed = residual[index - lag]
                correlation += residual[index] * delayed
                delayedEnergy += delayed * delayed
            }
            let score = correlation > 0 ? correlation * correlation / max(1, targetEnergy * delayedEnergy) : 0
            if score > bestCorrelation { bestCorrelation = score; bestLag = lag }
        }
        guard bestCorrelation >= 0.65 else { return nil }
        let vectors = [SILKParameterTables.ltpVector0, SILKParameterTables.ltpVector1, SILKParameterTables.ltpVector2]
        let subframeLength = sampleRate / 200
        var best: SILKPitchAnalysis?
        for category in vectors.indices {
            let codebook = vectors[category]
            var indices: [Int] = []
            var totalEnergy = 0.0
            for subframe in 0..<(frameDurationMilliseconds / 5) {
                var bestIndex = 0
                var bestEnergy = Double.infinity
                for vector in 0..<(codebook.count / 5) {
                    var errorEnergy = 0.0
                    for offset in 0..<subframeLength {
                        let index = memory + subframe * subframeLength + offset
                        var prediction = 0.0
                        for tap in 0..<5 {
                            prediction += residual[index - bestLag + 2 - tap] * Double(codebook[vector * 5 + tap]) / 128
                        }
                        let error = residual[index] - prediction
                        errorEnergy += error * error
                    }
                    if errorEnergy < bestEnergy { bestEnergy = errorEnergy; bestIndex = vector }
                }
                indices.append(bestIndex)
                totalEnergy += bestEnergy
            }
            if best == nil || totalEnergy < best!.energy {
                best = SILKPitchAnalysis(lagIndex: Int16(bestLag - minimumLag), periodicity: category,
                                         gainIndices: indices, energy: totalEnergy)
            }
        }
        guard let best, best.energy < energy * 0.9 else { return nil }
        return best
    }

    /// Emits one independent mono frame after VAD and optional preceding-frame LBRR.
    /// - Parameters:
    ///   - parameters: Internally generated valid indices and exact dequantized gains.
    ///   - pulses: One frame's bounded signed excitation pulses, without MB padding.
    ///   - encoder: Temporary stream receiving flags, parameters and complete pulses.
    /// - Throws: Range byte/operation/state, parameter encoding or pulse errors.
    ///   The caller discards all temporary state when a candidate exceeds its budget.
    private func writePayload(_ parameters: SILKFrameParameters, pulses: [Int16], to encoder: inout OpusRangeEncoder) throws {
        try encoder.encodeBit(parameters.signalType != .inactive, logProbability: 1)
        try encoder.encodeBit(redundantFrame != nil, logProbability: 1)
        if let redundantFrame {
            try writeChannel(redundantFrame.parameters, pulses: redundantFrame.signedPulses, to: &encoder)
        }
        try writeChannel(parameters, pulses: pulses, to: &encoder)
    }

    /// Emits one already validated independent channel frame without enclosing flags.
    /// - Parameters:
    ///   - parameters: Exact ordinary indices for normal or active redundant audio.
    ///   - pulses: One frame of signed bounded excitation pulses matching the indices.
    ///   - encoder: Bounded private entropy stream receiving indices then pulse syntax.
    /// - Throws: Parameter/pulse/range errors; callers discard temporary mutation.
    private func writeChannel(_ parameters: SILKFrameParameters, pulses: [Int16], to encoder: inout OpusRangeEncoder) throws {
        try SILKFrameParameterEncoding.encode(
            parameters, to: &encoder, sampleRate: sampleRate,
            frameDurationMilliseconds: frameDurationMilliseconds
        )
        try SILKPulseCoding.encode(pulses, to: &encoder, signalType: parameters.signalType, quantizationOffset: .low)
    }

    /// Reconstructs exact scalar parameters by parsing a bounded owned index stream.
    /// - Parameters:
    ///   - rate: Validated internal sample rate in 8/12/16 kHz.
    ///   - duration: Validated ten/twenty-millisecond internal frame length.
    ///   - gain: Absolute first gain index in `0...63`; remaining delta symbols are four.
    ///   - previousGain: Previous exact gain index, enforcing independent-frame fall limits.
    ///   - spectralIndex: First-stage NLSF vector in `0...31`; residual indices are zero.
    ///   - active: True selects active unvoiced/voiced; false selects inactive.
    ///   - pitch: Optional validated analysis selecting voiced lag and LTP indices;
    ///     nil, the default, selects unvoiced/inactive syntax with no pitch symbols.
    /// - Returns: Audited decoder's exact gain and stable NLSF reconstructions; no PCM.
    /// - Throws: Range/table/format errors, indicating an internally violated invariant.
    ///   This shared reconstruction avoids a separate drifting gain/NLSF quantizer copy.
    private static func reconstructParameters(rate: Int, duration: Int, gain: Int, previousGain: Int, spectralIndex: Int, active: Bool, pitch: SILKPitchAnalysis? = nil) throws -> SILKFrameParameters {
        let subframes = duration / 5
        let indices = SILKFrameParameters(
            signalType: active ? (pitch == nil ? .unvoiced : .voiced) : .inactive, quantizationOffset: .low,
            gainIndices: [gain] + Array(repeating: 4, count: subframes - 1),
            normalizedLSFCodebookIndex: spectralIndex,
            normalizedLSFResidualIndices: Array(repeating: 0, count: rate == 16_000 ? 16 : 10),
            interpolationQ2: 4, pitchLagIndex: pitch?.lagIndex, pitchContourIndex: pitch == nil ? nil : 0,
            periodicityIndex: pitch?.periodicity, longTermGainIndices: pitch?.gainIndices ?? [], longTermScaleIndex: pitch == nil ? nil : 0,
            seed: 0, gainsQ16: [], normalizedLSFsQ15: [], pitchLags: [],
            longTermCoefficientsQ7: [], longTermScaleQ14: 0
        )
        var encoder = try OpusRangeEncoder(frameByteCount: 128)
        try SILKFrameParameterEncoding.encode(indices, to: &encoder, sampleRate: rate, frameDurationMilliseconds: duration)
        var entropy = try OpusRangeDecoder(frame: encoder.finalize())
        var decoder = try SILKFrameParameterDecoder(sampleRate: rate, frameDurationMilliseconds: duration, previousGainIndex: previousGain)
        return try decoder.decode(from: &entropy, voiceActivity: active)
    }
}

/// One bounded voiced-analysis choice; reconstructed taps come from audited decoding.
private struct SILKPitchAnalysis {
    let lagIndex: Int16
    let periodicity: Int
    let gainIndices: [Int]
    let energy: Double
}
