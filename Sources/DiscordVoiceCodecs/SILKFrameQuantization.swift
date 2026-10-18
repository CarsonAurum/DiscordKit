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


/// Bounded pulse search against the exact ordinary scalar SILK synthesis recurrence.
///
/// Analysis supplies stable LPC and already dequantized independent-frame indices.
/// This helper retains no history: it derives LPC/LTP state from the encoder's
/// decoder and searches five neighboring excitation pulses per target sample,
/// optionally including zero under an explicit scalar rate-distortion penalty.
/// Exact rewhitening, gain normalization, random signs, wrapping and PCM rounding
/// keep quantization synchronized with ordinary decoders for voiced/unvoiced input.
/// It does not implement the reference perceptual delayed-decision NSQ policy.
enum SILKFrameQuantization {
    /// Quantizes one target channel against a private exact synthesis simulation.
    /// - Parameters:
    ///   - pcm: Exactly one admitted ten/twenty-millisecond PCM16 target frame.
    ///   - coefficients: Stable Q12 LPC taps matching `parameters`, ten/sixteen taps.
    ///   - parameters: Exact decoded independent-frame gains and optional pitch/LTP,
    ///     low quantization offset, and interpolation four. All dimensions are trusted
    ///     internal encoder invariants rather than unvalidated public input.
    ///   - previousGainQ16: Decoder's preceding strictly positive scalar gain.
    ///   - shortTermHistoryQ14: Decoder's sixteen normalized LPC history values.
    ///   - outputHistory: Decoder's preceding twenty milliseconds of internal PCM16.
    ///   - ratePenalty: Nonnegative finite squared-PCM-error cost per absolute pulse,
    ///     default zero for nearest-sample quantization. Positive costs also admit
    ///     zero as a candidate, trading sample error for sparse ordinary excitation.
    ///     The encoder supplies one of seven bounded fallback costs; no bit guarantee
    ///     is inferred here, because final entropy admission remains its authority.
    /// - Returns: Exactly one bounded signed pulse in `-127...127` per target sample.
    ///   Every candidate is evaluated after the same integer rounding and saturation
    ///   as the decoder. Ties retain the first candidate: neighboring pulses are
    ///   considered in ascending order before an optional separately admitted zero. No caller
    ///   state is modified; successful final decoding owns persistent reconstruction.
    /// - Complexity: O(samples * (LPC order + at most six candidates + five LTP taps)),
    ///   with bounded arrays for at most 320 target samples; no tasks or I/O occur.
    static func quantize(
        _ pcm: [Int16], coefficients: [Int16], parameters: SILKFrameParameters,
        previousGainQ16: Int32, shortTermHistoryQ14: [Int32], outputHistory: [Int16],
        ratePenalty: Double = 0
    ) -> [Int16] {
        let subframeCount = parameters.gainsQ16.count
        let subframeLength = pcm.count / subframeCount
        let memoryLength = outputHistory.count
        let voiced = parameters.signalType == .voiced
        let offset: Int32 = voiced ? 8 : 25
        var lpcState = shortTermHistoryQ14 + Array(repeating: Int32(0), count: subframeLength)
        var ltpState = Array(repeating: Int32(0), count: memoryLength + pcm.count)
        var ltpPosition = memoryLength
        var precedingGain = previousGainQ16
        var seed = UInt32(parameters.seed)
        var pulses: [Int16] = []
        pulses.reserveCapacity(pcm.count)
        for subframe in 0..<subframeCount {
            let gain = parameters.gainsQ16[subframe]
            let gainQ10 = gain >> 6
            let adjustment = gain == precedingGain ? 65_536 : SILKFrameMath.divide(precedingGain, by: gain, resultQ: 16)
            if gain != precedingGain {
                for index in 0..<16 { lpcState[index] = SILKFrameMath.multiplyWW(adjustment, lpcState[index]) }
            }
            precedingGain = gain
            let lag = parameters.pitchLags[subframe]
            if voiced {
                if subframe == 0 {
                    let start = memoryLength - lag - coefficients.count - 2
                    let rewhitened = SILKFrameDecoder.rewhiten(Array(outputHistory[start...]), coefficients: coefficients)
                    var inverseGain = SILKFrameMath.inverse(gain, resultQ: 47)
                    inverseGain = SILKFrameMath.multiplyWB(inverseGain, Int32(parameters.longTermScaleQ14)) &<< 2
                    for index in 0..<(lag + 2) {
                        ltpState[ltpPosition - index - 1] = SILKFrameMath.multiplyWB(
                            inverseGain, Int32(rewhitened[memoryLength - index - 1 - start]))
                    }
                } else if adjustment != 65_536 {
                    for index in 0..<(lag + 2) {
                        let slot = ltpPosition - index - 1
                        ltpState[slot] = SILKFrameMath.multiplyWW(adjustment, ltpState[slot])
                    }
                }
            }
            for index in 0..<subframeLength {
                var longTermPrediction: Int32 = 0
                if voiced {
                    var prediction: Int32 = 2
                    for tap in 0..<5 {
                        prediction = prediction &+ SILKFrameMath.multiplyWB(
                            ltpState[ltpPosition - lag + 2 - tap], Int32(parameters.longTermCoefficientsQ7[subframe][tap]) * 128)
                    }
                    longTermPrediction = prediction &<< 1
                }
                var shortTermPrediction = Int32(coefficients.count >> 1)
                for tap in coefficients.indices {
                    shortTermPrediction = shortTermPrediction &+ SILKFrameMath.multiplyWB(
                        lpcState[16 + index - tap - 1], Int32(coefficients[tap]))
                }
                let lpcQ14 = SILKFrameMath.saturatingShift(shortTermPrediction, by: 4)
                let target = pcm[subframe * subframeLength + index]
                seed = seed &* 196_314_165 &+ 907_633_515
                let negative = seed & 0x8000_0000 != 0
                let sign = negative ? -1.0 : 1.0
                let desired = (Double(target) * 65_536 / Double(gain)
                    - Double(lpcQ14) / 16_384 - Double(longTermPrediction) / 16_384) * sign
                let estimate = Int((desired - Double(offset) / 256 + (desired < 0 ? -20.0 : 20.0) / 256).rounded())
                let center = min(127, max(-127, estimate))
                var bestPulse = center
                var bestResidual: Int32 = 0
                var bestSynthesis: Int32 = 0
                var bestError = Double.infinity
                let candidates = max(-127, center - 2)...min(127, center + 2)
                let includeZero = ratePenalty > 0 && !candidates.contains(0)
                for candidate in 0..<(candidates.count + (includeZero ? 1 : 0)) {
                    let pulse = candidate < candidates.count ? candidates.lowerBound + candidate : 0
                    let level = Int32(pulse * 256 - (pulse > 0 ? 20 : (pulse < 0 ? -20 : 0))) + offset
                    let excitation = (negative ? -level : level) &* 64
                    let residual = excitation &+ longTermPrediction
                    let synthesis = SILKFrameMath.saturate32(Int64(residual) + Int64(lpcQ14))
                    let scaled = SILKFrameMath.multiplyWW(synthesis, gainQ10)
                    let reconstructed = Int16(clamping: SILKFrameMath.rounded(scaled, by: 8))
                    let difference = Int64(target) - Int64(reconstructed)
                    let error = Double(difference * difference) + ratePenalty * Double(abs(pulse))
                    if error < bestError {
                        bestError = error
                        bestPulse = pulse
                        bestResidual = residual
                        bestSynthesis = synthesis
                    }
                }
                seed = seed &+ UInt32(bitPattern: Int32(bestPulse))
                pulses.append(Int16(bestPulse))
                lpcState[16 + index] = bestSynthesis
                if voiced {
                    ltpState[ltpPosition] = bestResidual &<< 1
                    ltpPosition += 1
                }
            }
            for index in 0..<16 { lpcState[index] = lpcState[subframeLength + index] }
        }
        return pulses
    }
}
