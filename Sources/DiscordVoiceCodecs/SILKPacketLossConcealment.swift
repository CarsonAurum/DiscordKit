// File: Sources/DiscordVoiceCodecs/SILKPacketLossConcealment.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

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


/// Bounded scalar SILK packet-loss and comfort-noise state.
/// Adapted from libopus 1.6.1 PLC.c, CNG.c, sum_sqr_shift.c and Inlines.h;
/// neural enhancement is deliberately outside this normative scalar implementation.
struct SILKLossState: Sendable {
    private(set) var lossCount = 0
    private(set) var previousSignalType: SILKSignalType = .inactive
    private(set) var previousPitchLag = 100
    private var rate = 0
    private var pitchQ8: Int32 = 0
    private var ltpQ14 = Array(repeating: Int16(0), count: 5)
    private var lpcQ12 = Array(repeating: Int16(0), count: 16)
    private var previousScaleQ14: Int16 = 0
    private var previousGainsQ16: [Int32] = [65_536, 65_536]
    private var previousSubframeLength = 20
    private var previousSubframeCount = 2
    private var excitationQ14 = Array(repeating: Int32(0), count: 320)
    private var randomSeed: Int32 = 0
    private var randomScaleQ14: Int16 = 0
    private var concealedEnergy: Int32 = 0
    private var concealedShift = 0
    private var lastLost = false
    private var cngLSFs = Array(repeating: Int16(0), count: 16)
    private var cngGainQ16: Int32 = 0
    private var cngExcitation = Array(repeating: Int32(0), count: 320)
    private var cngState = Array(repeating: Int32(0), count: 16)
    private var cngSeed: Int32 = 3_176_576

    /// Clears decoder-side voiced recovery decisions at bandwidth/side prediction reset.
    /// Scalar PLC/CNG buffers reset lazily at their next configured-rate operation;
    /// loss count and gain/random histories remain under their normative owners.
    mutating func resetPrediction() {
        previousSignalType = .inactive
        previousPitchLag = 100
    }

    /// Lazily applies the normative rate-specific PLC/CNG reset without erasing
    /// unrelated entropy, random excitation or decoder-side synthesis ownership.
    /// - Parameters:
    ///   - sampleRate: Validated 8/12/16kHz internal rate.
    ///   - frameLength: Configured ten/twenty-millisecond internal sample count.
    private mutating func configure(sampleRate: Int, frameLength: Int) {
        guard rate != sampleRate else { return }
        rate = sampleRate
        pitchQ8 = Int32(frameLength) << 7
        previousGainsQ16 = [65_536, 65_536]
        previousSubframeLength = 20
        previousSubframeCount = 2
        let order = sampleRate == 16_000 ? 16 : 10
        for index in 0..<order { cngLSFs[index] = Int16((index + 1) * (32_767 / (order + 1))) }
        cngGainQ16 = 0
        cngSeed = 3_176_576
    }

    /// Records one successful channel frame for future pitch/noise extrapolation.
    /// - Parameters:
    ///   - decoded: Complete syntax and Q23 excitation from the channel decoder.
    ///   - coefficients: Final-half Q12 LPC, including post-loss bandwidth expansion.
    ///   - sampleRate: Validated current internal rate.
    ///   - frameDuration: Ten or twenty milliseconds; determines two/four subframes.
    /// - Throws: No current failures; throwing contract permits future audited LPC
    ///   checks while the enclosing channel retains copy-and-commit ownership.
    mutating func record(_ decoded: SILKDecodedExcitation, coefficients: [Int16], sampleRate: Int, frameDuration: Int) throws {
        let p = decoded.parameters
        let subframes = frameDuration / 5
        let length = sampleRate / 200
        configure(sampleRate: sampleRate, frameLength: length * subframes)
        if !(lossCount > 0 && previousSignalType == .voiced && p.signalType != .voiced && subframes == 2) {
            previousPitchLag = p.pitchLags.last!
        }
        previousSignalType = p.signalType
        var gain: Int32 = 0
        if p.signalType == .voiced {
            for offset in 0..<subframes where offset * length < p.pitchLags.last! {
                let index = subframes - 1 - offset
                let candidate = p.longTermCoefficientsQ7[index].reduce(Int32(0)) { $0 + Int32($1) * 128 }
                if candidate > gain { gain = candidate; pitchQ8 = Int32(p.pitchLags[index]) << 8 }
            }
            ltpQ14 = [0, 0, Int16(truncatingIfNeeded: gain), 0, 0]
            if gain < 11_469 {
                let scale = Int16(truncatingIfNeeded: (Int32(11_469) << 10) / max(gain, 1))
                ltpQ14[2] = Int16(truncatingIfNeeded: (Int32(ltpQ14[2]) * Int32(scale)) >> 10)
            } else if gain > 15_565 {
                let scale = Int16(truncatingIfNeeded: (Int32(15_565) << 14) / max(gain, 1))
                ltpQ14[2] = Int16(truncatingIfNeeded: (Int32(ltpQ14[2]) * Int32(scale)) >> 14)
            }
        } else {
            pitchQ8 = Int32(sampleRate / 1_000 * 18) << 8
            ltpQ14 = [0, 0, 0, 0, 0]
        }
        for index in coefficients.indices { lpcQ12[index] = coefficients[index] }
        previousScaleQ14 = p.longTermScaleQ14
        previousGainsQ16 = Array(p.gainsQ16.suffix(2))
        previousSubframeLength = length
        previousSubframeCount = subframes
        for index in decoded.excitationQ23.indices { excitationQ14[index] = decoded.excitationQ23[index] &* 64 }
        lossCount = 0
        if p.signalType == .inactive {
            for index in coefficients.indices {
                cngLSFs[index] = Int16(truncatingIfNeeded: Int32(cngLSFs[index]) + SILKFrameMath.multiplyWB(Int32(p.normalizedLSFsQ15[index]) - Int32(cngLSFs[index]), 16_348))
            }
            let best = p.gainsQ16.indices.max { p.gainsQ16[$0] < p.gainsQ16[$1] }!
            // Equal maxima select the first subframe, as the reference's strict >.
            let selected = p.gainsQ16.firstIndex(of: p.gainsQ16[best])!
            for index in stride(from: (subframes - 1) * length - 1, through: 0, by: -1) { cngExcitation[length + index] = cngExcitation[index] }
            for index in 0..<length { cngExcitation[index] = excitationQ14[selected * length + index] }
            for gain in p.gainsQ16 {
                cngGainQ16 = cngGainQ16 &+ SILKFrameMath.multiplyWB(gain &- cngGainQ16, 4_634)
                if SILKFrameMath.multiplyWW(cngGainQ16, 46_396) > gain { cngGainQ16 = gain }
            }
        }
    }

    /// Extrapolates one missing internal frame using retained excitation and pitch.
    /// - Parameters:
    ///   - sampleRate: Validated 8/12/16kHz rate.
    ///   - frameDuration: Ten or twenty milliseconds.
    ///   - firstFrame: True when no successful frame followed the latest rate/reset.
    ///   - outputHistory: Exactly twenty milliseconds of pre-CNG/glue channel PCM.
    ///   - shortTermHistory: Sixteen normalized Q14 LPC samples, updated in place.
    /// - Returns: Bounded frame PCM before CNG and energy glue; increments loss count.
    /// - Throws: Audited LPC inverse-gain validation errors; caller commits atomically.
    mutating func conceal(sampleRate: Int, frameDuration: Int, firstFrame: Bool, outputHistory: [Int16], shortTermHistory: inout [Int32]) throws -> [Int16] {
        let length = sampleRate / 200
        let subframes = frameDuration / 5
        let count = length * subframes
        let memory = outputHistory.count
        let order = sampleRate == 16_000 ? 16 : 10
        configure(sampleRate: sampleRate, frameLength: count)
        if firstFrame { lpcQ12 = Array(repeating: 0, count: 16) }
        let gains = previousGainsQ16.map { $0 >> 6 }
        var scaled: [Int16] = []
        for subframe in 0..<2 {
            for index in 0..<length {
                scaled.append(Int16(clamping: SILKFrameMath.multiplyWW(excitationQ14[index + (subframe + subframes - 2) * length], gains[subframe]) >> 8))
            }
        }
        let firstEnergy = Self.energy(Array(scaled.prefix(length)))
        let secondEnergy = Self.energy(Array(scaled.suffix(length)))
        let start = max(0, (firstEnergy.0 >> secondEnergy.1 < secondEnergy.0 >> firstEnergy.1
            ? previousSubframeCount - 1 : previousSubframeCount) * previousSubframeLength - 128)
        let attenuation = min(1, lossCount)
        let harmonicGain: Int32 = [32_440, 31_130][attenuation]
        var noiseGain: Int32 = previousSignalType == .voiced ? [31_130, 26_214][attenuation] : [32_440, 29_491][attenuation]
        var coefficients = Array(lpcQ12.prefix(order))
        Self.expand(&coefficients, chirp: 64_881)
        for index in 0..<order { lpcQ12[index] = coefficients[index] }
        var scale = Int32(randomScaleQ14)
        if lossCount == 0 {
            scale = 16_384
            if previousSignalType == .voiced {
                scale -= ltpQ14.reduce(Int32(0)) { $0 + Int32($1) }
                scale = (max(3_277, scale) * Int32(previousScaleQ14)) >> 14
            } else {
                let inverse = try SILKNLSFCoefficients.inversePredictionGain(q12: coefficients)
                let down = min(Int32(1 << 27), max(Int32(1 << 22), inverse)) << 3
                noiseGain = SILKFrameMath.multiplyWB(down, noiseGain) >> 14
            }
        }
        var lag = Int(SILKFrameMath.rounded(pitchQ8, by: 8))
        let analysisStart = memory - lag - order - 2
        let white = SILKFrameDecoder.rewhiten(Array(outputHistory[analysisStart...]), coefficients: coefficients)
        let inverseGain = min(SILKFrameMath.inverse(previousGainsQ16[1], resultQ: 46), Int32.max >> 1)
        var ltp = Array(repeating: Int32(0), count: memory + count)
        for index in (analysisStart + order)..<memory { ltp[index] = SILKFrameMath.multiplyWB(inverseGain, Int32(white[index - analysisStart])) }
        var position = memory
        for _ in 0..<subframes {
            for _ in 0..<length {
                var prediction: Int32 = 2
                for tap in 0..<5 { prediction = prediction &+ SILKFrameMath.multiplyWB(ltp[position - lag + 2 - tap], Int32(ltpQ14[tap])) }
                randomSeed = randomSeed &* 196_314_165 &+ 907_633_515
                let index = Int((randomSeed >> 25) & 127)
                ltp[position] = (prediction &+ SILKFrameMath.multiplyWB(excitationQ14[start + index], scale)) &<< 2
                position += 1
            }
            for index in 0..<5 { ltpQ14[index] = Int16(truncatingIfNeeded: (harmonicGain * Int32(ltpQ14[index])) >> 15) }
            scale = (scale * noiseGain) >> 15
            pitchQ8 = min(pitchQ8 &+ SILKFrameMath.multiplyWB(pitchQ8, 655), Int32(sampleRate / 1_000 * 18) << 8)
            lag = Int(SILKFrameMath.rounded(pitchQ8, by: 8))
        }
        var signal = shortTermHistory + Array(ltp[memory...])
        var pcm = Array(repeating: Int16(0), count: count)
        for index in 0..<count {
            var prediction = Int32(order / 2)
            for tap in 0..<order { prediction = prediction &+ SILKFrameMath.multiplyWB(signal[16 + index - tap - 1], Int32(coefficients[tap])) }
            signal[16 + index] = SILKFrameMath.saturate32(Int64(signal[16 + index]) + Int64(SILKFrameMath.saturatingShift(prediction, by: 4)))
            pcm[index] = Int16(clamping: SILKFrameMath.rounded(SILKFrameMath.multiplyWW(signal[16 + index], gains[1]), by: 8))
        }
        shortTermHistory = Array(signal[count..<(count + 16)])
        randomScaleQ14 = Int16(truncatingIfNeeded: scale)
        previousPitchLag = lag
        lossCount += 1
        return pcm
    }

    /// Adds independently estimated comfort noise during loss, otherwise clearing
    /// the active LPC CNG synthesis history without changing decoded PCM.
    /// - Parameters:
    ///   - pcm: One frame of pre-CNG PCM, replaced with saturated noise-added PCM.
    ///   - sampleRate: Validated internal rate determining order ten or sixteen.
    /// - Throws: CNG smoothed-frequency LPC validation errors, propagated atomically.
    mutating func applyComfortNoise(to pcm: inout [Int16], sampleRate: Int) throws {
        let order = sampleRate == 16_000 ? 16 : 10
        guard lossCount > 0 else { for index in 0..<order { cngState[index] = 0 }; return }
        var gain = SILKFrameMath.multiplyWW(Int32(randomScaleQ14), previousGainsQ16[1])
        if gain >= 1 << 21 || cngGainQ16 > 1 << 23 {
            gain = (gain >> 16) &* (gain >> 16)
            gain = ((cngGainQ16 >> 16) &* (cngGainQ16 >> 16)) &- (gain &<< 5)
            gain = Self.sqrtApprox(gain) &<< 16
        } else {
            gain = SILKFrameMath.multiplyWW(gain, gain)
            gain = SILKFrameMath.multiplyWW(cngGainQ16, cngGainQ16) &- (gain &<< 5)
            gain = Self.sqrtApprox(gain) &<< 8
        }
        let gainQ10 = gain >> 6
        var mask = 255
        while mask > pcm.count { mask >>= 1 }
        var signal = cngState + Array(repeating: Int32(0), count: pcm.count)
        for index in pcm.indices {
            cngSeed = cngSeed &* 196_314_165 &+ 907_633_515
            signal[16 + index] = cngExcitation[Int((cngSeed >> 24) & Int32(mask))]
        }
        let coefficients = try SILKNLSFCoefficients(q15: Array(cngLSFs.prefix(order))).lpcQ12
        for index in pcm.indices {
            var prediction = Int32(order / 2)
            for tap in 0..<order { prediction = prediction &+ SILKFrameMath.multiplyWB(signal[16 + index - tap - 1], Int32(coefficients[tap])) }
            signal[16 + index] = SILKFrameMath.saturate32(Int64(signal[16 + index]) + Int64(SILKFrameMath.saturatingShift(prediction, by: 4)))
            let noise = Int16(clamping: SILKFrameMath.rounded(SILKFrameMath.multiplyWW(signal[16 + index], gainQ10), by: 8))
            pcm[index] = Int16(clamping: Int32(pcm[index]) + Int32(noise))
        }
        cngState = Array(signal[pcm.count..<(pcm.count + 16)])
    }

    /// Records concealed energy, then ramps the next successful frame's gain when
    /// its energy exceeds that concealed predecessor. Operates after CNG addition.
    /// - Parameter pcm: Current bounded PCM frame, modified only on normal recovery.
    mutating func glue(_ pcm: inout [Int16]) {
        if lossCount > 0 {
            (concealedEnergy, concealedShift) = Self.energy(pcm)
            lastLost = true
            return
        }
        defer { lastLost = false }
        guard lastLost else { return }
        let measured = Self.energy(pcm)
        var energy = measured.0
        let shift = measured.1
        if shift > concealedShift { concealedEnergy >>= shift - concealedShift }
        else if shift < concealedShift { energy >>= concealedShift - shift }
        guard energy > concealedEnergy else { return }
        let zeros = concealedEnergy.leadingZeroBitCount - 1
        concealedEnergy = concealedEnergy &<< zeros
        energy >>= max(24 - zeros, 0)
        let fraction = concealedEnergy / max(energy, 1)
        var gain = Self.sqrtApprox(fraction) << 4
        let slope = ((65_536 - gain) / Int32(pcm.count)) << 2
        for index in pcm.indices {
            pcm[index] = Int16(truncatingIfNeeded: SILKFrameMath.multiplyWB(gain, Int32(pcm[index])))
            gain += slope
            if gain > 65_536 { break }
        }
    }

    /// Applies scalar rounded bandwidth expansion to a bounded Q12 LPC vector.
    /// - Parameters:
    ///   - coefficients: Ten/sixteen Q12 coefficients, replaced in place.
    ///   - chirp: Initial positive Q16 bandwidth factor, below 65,536.
    static func expand(_ coefficients: inout [Int16], chirp: Int32) {
        var factor = chirp
        for index in coefficients.indices {
            coefficients[index] = Int16(truncatingIfNeeded: SILKFrameMath.rounded(factor &* Int32(coefficients[index]), by: 16))
            if index + 1 < coefficients.count { factor = factor &+ SILKFrameMath.rounded(factor &* (chirp - 65_536), by: 16) }
        }
    }

    /// Computes the reference's bounded pairwise squared-energy and shift estimate.
    /// - Parameter pcm: Nonempty bounded PCM16 vector no longer than 320 samples.
    /// - Returns: Positive signed energy with two headroom bits and its right shift.
    private static func energy(_ pcm: [Int16]) -> (Int32, Int) {
        var shift = 31 - Int32(pcm.count).leadingZeroBitCount
        var energy = UInt32(pcm.count)
        for index in stride(from: 0, to: pcm.count, by: 2) {
            var pair = UInt32(Int32(pcm[index]) * Int32(pcm[index]))
            if index + 1 < pcm.count { pair = pair &+ UInt32(Int32(pcm[index + 1]) * Int32(pcm[index + 1])) }
            energy = energy &+ (pair >> shift)
        }
        shift = max(0, shift + 3 - energy.leadingZeroBitCount)
        energy = 0
        for index in stride(from: 0, to: pcm.count, by: 2) {
            var pair = UInt32(Int32(pcm[index]) * Int32(pcm[index]))
            if index + 1 < pcm.count { pair = pair &+ UInt32(Int32(pcm[index + 1]) * Int32(pcm[index + 1])) }
            energy = energy &+ (pair >> shift)
        }
        return (Int32(energy), shift)
    }

    /// Approximates a nonnegative integer square root using the normative Q7 table-free step.
    /// - Parameter value: Signed integer; nonpositive values return zero.
    /// - Returns: Reference integer approximation, including CLZ/fraction rounding.
    private static func sqrtApprox(_ value: Int32) -> Int32 {
        guard value > 0 else { return 0 }
        let zeros = value.leadingZeroBitCount
        let rotation = 24 - zeros
        let bits = UInt32(bitPattern: value)
        let fraction = Int32((rotation >= 0 ? (bits >> rotation) | (bits &<< (32 - rotation)) : (bits &<< -rotation) | (bits >> (32 + rotation))) & 127)
        var result: Int32 = (zeros & 1 == 1 ? 32_768 : 46_214) >> (zeros >> 1)
        result = result &+ SILKFrameMath.multiplyWB(result, 213 * fraction)
        return result
    }
}

/// Exact-duration concealed PCM plus internal-rate frames for independent auditing.
/// PCM is mono or interleaved stereo according to the owning decoder; channelFrames
/// stores internal frames first, then mid/side channels before stereo unmixing.
public struct SILKConcealedPayload: Sendable, Equatable {
    public let pcm48k: [Int16]
    public let channelFrames: [[[Int16]]]
}

/// One missing payload recovered from available in-band redundancy or scalar PLC.
/// `channelFrames` is internal-frame-major; nil indicates concealment/omitted side.
/// Activity/redundancy are channel-major. Final entropy describes only the selected
/// LBRR prefix, since the ordinary current payload remains to be decoded separately.
public struct SILKRecoveredPayload: Sendable, Equatable {
    public let pcm48k: [Int16]
    public let channelFrames: [[SILKDecodedFrame?]]
    public let voiceActivity: [[Bool]]
    public let redundancy: [[Bool]]
    public let midOnly: [Bool]
    public let finalRange: UInt32
    public let bitsUsed: Int
}
