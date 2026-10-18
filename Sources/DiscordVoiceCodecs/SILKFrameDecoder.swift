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


/// One decoded ordinary SILK channel frame at its internal NB/MB/WB sample rate.
///
/// Samples are signed scalar PCM16 after gain/LPC/LTP synthesis. Packet flags,
/// stereo unmixing, final output-rate conversion, PLC, FEC selection and Opus
/// mode transitions are not implemented by this channel-level value.
public struct SILKDecodedFrame: Sendable, Equatable {
    public let parameters: SILKFrameParameters
    public let pulses: SILKPulseFrame
    public let pcm: [Int16]
}

/// Owned ordinary SILK channel decoding from compressed parameters through PCM16.
///
/// Combines complete channel syntax, scalar gain/LSF reconstruction, NLSF-to-LPC,
/// gain-adjusted persistent short-term history, rewhitened five-tap long-term
/// prediction, fixed-point saturation and final PCM rounding. The caller supplies
/// enclosing packet VAD/LBRR/conditional decisions and positions shared entropy.
/// This is an ordinary no-loss channel decoder: no packet header/stereo policy,
/// output resampling, CNG, PLC, post-loss transition or full Opus codec is claimed.
/// Arithmetic adapts libopus 1.6.1 decode_core.c and Inlines.h; no native runtime.
///
/// One instance owns one channel. It retains sixteen short-term samples, at most
/// 320 PCM history samples and sixteen previous LSFs. Per-call allocations/work
/// are bounded by the configured 10/20 ms frame. Construction starts no I/O/tasks.
/// Callers serialize mutation; failed calls commit neither entropy nor any history.
public struct SILKFrameDecoder: Sendable {
    public let sampleRate: Int
    public private(set) var frameDurationMilliseconds: Int
    /// Last successfully decoded gain in Q16, initially exactly one (65,536).
    public private(set) var previousGainQ16: Int32 = 65_536
    /// Last sixteen normalized LPC synthesis state samples in Q14, oldest first.
    public private(set) var shortTermHistoryQ14 = Array(repeating: Int32(0), count: 16)
    /// Last twenty milliseconds of PCM16 for voiced rewhitening, oldest first.
    public private(set) var outputHistory: [Int16]
    /// Last successful stabilized frequencies; reset state uses zeros and skips interpolation.
    public private(set) var previousNormalizedLSFsQ15: [Int16]
    /// True until the first successful frame, forcing that frame's interpolation to four.
    public private(set) var isFirstFrameAfterReset = true
    private var parameterDecoder: SILKFrameParameterDecoder

    /// Creates one zero-state internal-rate channel decoder without reading entropy.
    /// - Parameters:
    ///   - sampleRate: Exactly 8,000, 12,000 or 16,000 Hz; final resampling is separate.
    ///   - frameDurationMilliseconds: Exactly ten or twenty; longer packets contain
    ///     multiple internal frames and must supply their correct conditional choices.
    /// - Throws: `SILKFrameParameterError.invalidSampleRate` or `invalidFrameDuration`.
    ///   Only finite O(rate * 20 ms) history is allocated. No native codec/device work.
    public init(sampleRate: Int, frameDurationMilliseconds: Int) throws {
        let parameterDecoder = try SILKFrameParameterDecoder(sampleRate: sampleRate, frameDurationMilliseconds: frameDurationMilliseconds)
        self.sampleRate = sampleRate
        self.frameDurationMilliseconds = frameDurationMilliseconds
        self.parameterDecoder = parameterDecoder
        outputHistory = Array(repeating: 0, count: sampleRate / 50)
        previousNormalizedLSFsQ15 = Array(repeating: 0, count: parameterDecoder.normalizedLSFOrder)
    }

    /// Clears all entropy, gain, LPC, LSF and output histories at a stream/rate reset.
    /// Construction and reset do no I/O. The fixed rate/duration configuration remains.
    /// Existing output values are independent and are not changed by this operation.
    public mutating func reset() {
        parameterDecoder.reset()
        previousGainQ16 = 65_536
        shortTermHistoryQ14 = Array(repeating: 0, count: 16)
        outputHistory = Array(repeating: 0, count: sampleRate / 50)
        previousNormalizedLSFsQ15 = Array(repeating: 0, count: parameterDecoder.normalizedLSFOrder)
        isFirstFrameAfterReset = true
    }

    /// Changes between ten- and twenty-millisecond internal frames without resetting history.
    ///
    /// SILK packets may change their duration while retaining the same internal rate.
    /// This reconstructs only the syntax configuration and preserves prior gain/type/lag,
    /// PCM, LPC and LSF histories. A failed validation leaves the complete decoder intact.
    /// - Parameter milliseconds: Exactly ten or twenty milliseconds.
    /// - Throws: `SILKFrameParameterError.invalidFrameDuration` for any other value.
    public mutating func updateFrameDuration(milliseconds: Int) throws {
        let replacement = try SILKFrameParameterDecoder(
            sampleRate: sampleRate, frameDurationMilliseconds: milliseconds,
            previousGainIndex: parameterDecoder.previousGainIndex,
            previousSignalType: parameterDecoder.previousSignalType,
            previousPitchLagIndex: parameterDecoder.previousPitchLagIndex
        )
        parameterDecoder = replacement
        frameDurationMilliseconds = milliseconds
    }

    /// Decodes one ordinary channel frame, atomically advancing bounded synthesis history.
    /// - Parameters:
    ///   - decoder: Shared Opus range state positioned at this frame's type symbol,
    ///     after packet/stereo headers. Success leaves it after every pulse sign.
    ///   - voiceActivity: Previously parsed packet VAD flag for this channel/frame.
    ///   - lowBitrateRedundancy: Selects the active LBRR parameter context, default
    ///     false. A true value decodes supplied redundant syntax normally; packet FEC
    ///     selection and preceding loss recovery are not provided by this type.
    ///   - coding: Enclosing packet's gain/pitch conditional choice, default independent.
    /// - Returns: Exactly 80/120/160/240/320 PCM samples plus decoded parameter/pulse
    ///   evidence. First-frame LPC interpolation is suppressed, matching scalar SILK.
    /// - Throws: Parameter/pulse/range errors or `SILKNLSFError` if audited reconstruction
    ///   invariants fail. Every failure preserves caller entropy and all channel history.
    ///   Normative arithmetic zero extension permits finite decoded audio from damaged
    ///   or truncated nonempty syntax; this is not compressed-packet authentication.
    /// - Complexity: O(frameSamples * LPCOrder) bounded synchronous work, at most
    ///   sixteen taps and 320 output samples. No tasks, suspension or external work.
    public mutating func decode(
        from decoder: inout OpusRangeDecoder,
        voiceActivity: Bool,
        lowBitrateRedundancy: Bool = false,
        coding: SILKParameterCoding = .independent
    ) throws -> SILKDecodedFrame {
        var working = self
        var entropy = decoder
        let decoded = try working.parameterDecoder.decodeExcitation(
            from: &entropy, voiceActivity: voiceActivity, lowBitrateRedundancy: lowBitrateRedundancy, coding: coding
        )
        let samples = try working.synthesize(decoded)
        let result = SILKDecodedFrame(parameters: decoded.parameters, pulses: decoded.pulses, pcm: samples)
        self = working
        decoder = entropy
        return result
    }

    /// Reconstructs LPC/LTP and gain synthesis from bounded, already decoded syntax.
    /// - Parameter decoded: A complete channel frame matching this decoder's format.
    /// - Returns: Saturated PCM16 while updating only the temporary decoder copy.
    /// - Throws: NLSF validation errors; no external caller observes this temporary state.
    private mutating func synthesize(_ decoded: SILKDecodedExcitation) throws -> [Int16] {
        let parameters = decoded.parameters
        let order = parameterDecoder.normalizedLSFOrder
        let subframeLength = sampleRate / 200
        let frameLength = parameterDecoder.sampleCount
        let memoryLength = outputHistory.count
        let interpolation = isFirstFrameAfterReset ? 4 : parameters.interpolationQ2
        let current = try SILKNLSFCoefficients(q15: parameters.normalizedLSFsQ15).lpcQ12
        let first = interpolation < 4
            ? try SILKNLSFCoefficients(q15: SILKNLSFCoefficients.interpolate(
                previous: previousNormalizedLSFsQ15, current: parameters.normalizedLSFsQ15, weight: interpolation
            )).lpcQ12 : current
        let coefficientSets = [first, current]
        var lpcState = shortTermHistoryQ14 + Array(repeating: 0, count: subframeLength)
        var outputBuffer = outputHistory + Array(repeating: Int16(0), count: frameLength)
        var ltpState = Array(repeating: Int32(0), count: memoryLength + frameLength)
        var ltpPosition = memoryLength
        var pcm = Array(repeating: Int16(0), count: frameLength)
        for subframe in 0..<parameterDecoder.subframeCount {
            let coefficients = coefficientSets[subframe >> 1]
            let gain = parameters.gainsQ16[subframe]
            let gainQ10 = gain >> 6
            var inverseGain = SILKFrameMath.inverse(gain, resultQ: 47)
            let adjustment = gain == previousGainQ16 ? 65_536 : SILKFrameMath.divide(previousGainQ16, by: gain, resultQ: 16)
            if gain != previousGainQ16 {
                for index in 0..<16 { lpcState[index] = SILKFrameMath.multiplyWW(adjustment, lpcState[index]) }
            }
            previousGainQ16 = gain
            let lag = parameters.pitchLags[subframe]
            if parameters.signalType == .voiced {
                if subframe == 0 || (subframe == 2 && interpolation < 4) {
                    let start = memoryLength - lag - order - 2
                    if subframe == 2 {
                        for index in 0..<(2 * subframeLength) { outputBuffer[memoryLength + index] = pcm[index] }
                    }
                    let rewhitened = Self.rewhiten(
                        Array(outputBuffer[(start + subframe * subframeLength)..<(memoryLength + subframe * subframeLength)]),
                        coefficients: coefficients
                    )
                    if subframe == 0 {
                        inverseGain = SILKFrameMath.multiplyWB(inverseGain, Int32(parameters.longTermScaleQ14)) &<< 2
                    }
                    for index in 0..<(lag + 2) {
                        ltpState[ltpPosition - index - 1] = SILKFrameMath.multiplyWB(inverseGain, Int32(rewhitened[memoryLength - index - 1 - start]))
                    }
                } else if adjustment != 65_536 {
                    for index in 0..<(lag + 2) {
                        let slot = ltpPosition - index - 1
                        ltpState[slot] = SILKFrameMath.multiplyWW(adjustment, ltpState[slot])
                    }
                }
            }
            for index in 0..<subframeLength {
                let frameIndex = subframe * subframeLength + index
                // The independently exposed excitation's integer scale is 1/64 of
                // the scalar core's Q14 signal; multiplying exactly preserves it.
                var residual = decoded.excitationQ23[frameIndex] &* 64
                if parameters.signalType == .voiced {
                    var prediction: Int32 = 2
                    for tap in 0..<5 {
                        let coefficient = Int32(parameters.longTermCoefficientsQ7[subframe][tap]) * 128
                        prediction = prediction &+ SILKFrameMath.multiplyWB(ltpState[ltpPosition - lag + 2 - tap], coefficient)
                    }
                    residual = residual &+ (prediction &<< 1)
                    ltpState[ltpPosition] = residual &<< 1
                    ltpPosition += 1
                }
                var prediction = Int32(order >> 1)
                for tap in 0..<order {
                    prediction = prediction &+ SILKFrameMath.multiplyWB(lpcState[16 + index - tap - 1], Int32(coefficients[tap]))
                }
                lpcState[16 + index] = SILKFrameMath.saturate32(Int64(residual) + Int64(SILKFrameMath.saturatingShift(prediction, by: 4)))
                let scaled = SILKFrameMath.multiplyWW(lpcState[16 + index], gainQ10)
                pcm[frameIndex] = Int16(clamping: SILKFrameMath.rounded(scaled, by: 8))
            }
            for index in 0..<16 { lpcState[index] = lpcState[subframeLength + index] }
        }
        shortTermHistoryQ14 = Array(lpcState.prefix(16))
        outputHistory = Array(outputHistory.dropFirst(frameLength)) + pcm
        previousNormalizedLSFsQ15 = parameters.normalizedLSFsQ15
        isFirstFrameAfterReset = false
        return pcm
    }

    /// Applies the scalar Q12 LPC analysis filter used to rewhiten prior PCM.
    /// - Parameters:
    ///   - input: Bounded contiguous PCM history at least as long as the predictor.
    ///   - coefficients: Ten or sixteen signed Q12 predictor taps.
    /// - Returns: PCM16 residuals; first `order` samples are explicitly zero because
    ///   this analysis starts without earlier history. Intermediate sums wrap modulo
    ///   2^32 before rounded shifting and Int16 saturation, as scalar SILK specifies.
    private static func rewhiten(_ input: [Int16], coefficients: [Int16]) -> [Int16] {
        let order = coefficients.count
        var output = Array(repeating: Int16(0), count: input.count)
        for index in order..<input.count {
            var prediction: Int32 = 0
            for tap in 0..<order { prediction = prediction &+ Int32(input[index - tap - 1]) * Int32(coefficients[tap]) }
            let residual = (Int32(input[index]) &<< 12) &- prediction
            output[index] = Int16(clamping: SILKFrameMath.rounded(residual, by: 12))
        }
        return output
    }
}

/// Scalar two's-complement, saturation and reciprocal arithmetic for frame synthesis.
private enum SILKFrameMath {
    /// Multiplies a signed Int32 by the low signed sixteen bits of another value.
    /// - Parameters:
    ///   - lhs: Full signed multiplicand.
    ///   - rhs: Low signed sixteen-bit multiplier, regardless of its Int32 container.
    /// - Returns: Product arithmetic-shifted sixteen, preserving scalar Q-domain rules.
    static func multiplyWB(_ lhs: Int32, _ rhs: Int32) -> Int32 {
        Int32(truncatingIfNeeded: (Int64(lhs) * Int64(Int16(truncatingIfNeeded: rhs))) >> 16)
    }

    /// Multiplies two signed words and retains the low signed thirty-two shifted bits.
    /// - Parameters:
    ///   - lhs: First full signed multiplicand.
    ///   - rhs: Second full signed multiplicand.
    /// - Returns: Two's-complement result of the 64-bit product shifted sixteen.
    static func multiplyWW(_ lhs: Int32, _ rhs: Int32) -> Int32 {
        Int32(truncatingIfNeeded: (Int64(lhs) * Int64(rhs)) >> 16)
    }

    /// Rounds a signed arithmetic right shift with ties toward positive infinity.
    /// - Parameters:
    ///   - value: Signed scalar intermediate.
    ///   - count: Positive shift in `1...31`, supplied by fixed synthesis scales.
    /// - Returns: Exactly `((value >> (count - 1)) + 1) >> 1`, without overflow.
    static func rounded(_ value: Int32, by count: Int) -> Int32 {
        Int32(((Int64(value) >> (count - 1)) + 1) >> 1)
    }

    /// Clamps an extended intermediate into the full signed thirty-two-bit domain.
    /// - Parameter value: Exact Int64 sum/product intermediate.
    /// - Returns: Saturated Int32 value, preserving every representable input.
    static func saturate32(_ value: Int64) -> Int32 { Int32(clamping: value) }

    /// Left shifts a fixed-point scalar while saturating overflow before narrowing.
    /// - Parameters:
    ///   - value: Signed input intermediate.
    ///   - count: Nonnegative shift, at most thirty-one for admitted synthesis inputs.
    /// - Returns: Saturated Int32 shifted result. Zero shifts preserve the value.
    static func saturatingShift(_ value: Int32, by count: Int) -> Int32 {
        min(Int32.max >> count, max(Int32.min >> count, value)) &<< count
    }

    /// Computes SILK's refined bounded fixed-point positive gain ratio.
    /// - Parameters:
    ///   - numerator: Positive previous Q16 gain, never zero.
    ///   - denominator: Positive current Q16 gain, never zero.
    ///   - resultQ: Requested Q-domain, sixteen for gain history scaling.
    /// - Returns: Scalar reference reciprocal estimate, including saturated shifts.
    static func divide(_ numerator: Int32, by denominator: Int32, resultQ: Int) -> Int32 {
        let aHeadroom = numerator.leadingZeroBitCount - 1
        let bHeadroom = denominator.leadingZeroBitCount - 1
        var a = numerator &<< aHeadroom
        let b = denominator &<< bHeadroom
        let inverse = (Int32.max >> 2) / (b >> 16)
        var result = multiplyWB(a, inverse)
        a = a &- (Int32(truncatingIfNeeded: (Int64(b) * Int64(result)) >> 32) &<< 3)
        result = result &+ multiplyWB(a, inverse)
        let shift = 29 + aHeadroom - bHeadroom - resultQ
        if shift < 0 { return saturatingShift(result, by: -shift) }
        return shift < 32 ? result >> shift : 0
    }

    /// Computes SILK's refined fixed-point reciprocal of a positive scalar gain.
    /// - Parameters:
    ///   - denominator: Positive signed Q16 gain, never zero.
    ///   - resultQ: Requested reciprocal precision, forty-seven for voiced synthesis.
    /// - Returns: Scalar reference reciprocal estimate, using one residual refinement.
    static func inverse(_ denominator: Int32, resultQ: Int) -> Int32 {
        let headroom = denominator.leadingZeroBitCount - 1
        let normalized = denominator &<< headroom
        let inverse = (Int32.max >> 2) / (normalized >> 16)
        var result = inverse &<< 16
        let error = ((Int32(1) << 29) &- multiplyWB(normalized, inverse)) &<< 3
        result = result &+ multiplyWW(error, inverse)
        let shift = 61 - headroom - resultQ
        if shift <= 0 { return saturatingShift(result, by: -shift) }
        return shift < 32 ? result >> shift : 0
    }
}
