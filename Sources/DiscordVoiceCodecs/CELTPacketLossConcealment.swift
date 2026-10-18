// Periodic PLC, pitch whitening and LPC prediction adapted from libopus 1.6.1
// celt/celt_decoder.c, celt/pitch.c and celt/celt_lpc.c.
// Copyright (c) 2007-2010 Xiph.Org Foundation
// Copyright (c) 2007-2008 CSIRO
// Copyright (c) 2008 Gregory Maxwell
// Written by Jean-Marc Valin and Gregory Maxwell.
// Redistribution and use in source and binary forms, with or without modification,
// are permitted provided that the copyright notice, this list of conditions and
// the following disclaimer are retained in source distributions and reproduced in
// the documentation and/or other materials provided with binary distributions.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
// IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
// DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
// ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
// (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
// LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
// ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
// SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

import Foundation

/// One missing CELT frame reconstructed from bounded decoder history.
///
/// No entropy bits are consumed and no FEC data is recovered. Samples use the same
/// interleaved, normalized, unclipped floating-point domain as ordinary synthesis.
/// The updated envelope and random seed must be retained by the enclosing decoder.
public struct CELTConcealedFrame: Sendable, Equatable {
    public let samples: [Float]
    public let bandLogEnergies: [Float]
    public let seed: UInt32
    public let usesNoise: Bool
    /// Saturating consecutive missing duration in 120-sample/2.5-ms units.
    public let lossDuration: Int
    /// Shared periodic predictor lag in 100...720 samples, or zero for noise PLC.
    public let pitchPeriod: Int
}

/// Bounded periodic excitation predictor for the ordinary floating-point CELT PLC.
/// Signal arrays are channel-major and use libopus's pre-deemphasis signal scale.
/// This internal helper neither owns overlap/deemphasis nor changes energy history.
struct CELTPeriodicConcealment: Sendable {
    private var coefficients: [[Float]] = []
    private(set) var pitchPeriod = 0
    private static let order = 24

    /// Predicts one loss and its 120-sample future overlap using shared pitch and per-channel LPC.
    /// - Parameters:
    ///   - history: One or two complete 2,048-sample histories, already postfiltered.
    ///   - frameSampleCount: One of 120, 240, 480 or 960 output samples per channel.
    ///   - window: The 120-sample rising CELT overlap window.
    ///   - continuing: True reuses pitch/LPC and applies the normative 0.8 repeat-loss fade.
    /// - Returns: Each channel's predicted `frameSampleCount + 120` pre-deemphasis samples.
    /// Histories and dimensions are validated by the synthesis owner. State/storage
    /// remain bounded; a numerical synthesis explosion is replaced with silence.
    mutating func predict(history: [[Float]], frameSampleCount: Int,
                          window: [Float], continuing: Bool) -> [[Float]] {
        if !continuing {
            pitchPeriod = Self.searchPitch(history)
            coefficients = history.map { channel in
                var correlation = Self.autocorrelation(Array(channel.suffix(1_024)), order: Self.order, window: window)
                correlation[0] *= 1.0001
                for lag in 1...Self.order {
                    correlation[lag] -= correlation[lag] * (0.008 * 0.008) * Float(lag) * Float(lag)
                }
                return Self.lpc(correlation, order: Self.order)
            }
        }
        let length = min(2 * pitchPeriod, 1_024)
        let count = frameSampleCount + 120
        var result: [[Float]] = []
        result.reserveCapacity(history.count)
        for channel in history.indices {
            let source = Array(history[channel].suffix(1_024 + Self.order))
            var excitation = Array(source.suffix(1_024))
            // The analysis FIR reads original input, including its preceding LPC history.
            for position in (1_024 - length)..<1_024 {
                var value = source[Self.order + position]
                for lag in 0..<Self.order {
                    value += coefficients[channel][Self.order - lag - 1] * source[position + lag]
                }
                excitation[position] = value
            }
            let half = length / 2
            var recent: Float = 1
            var earlier: Float = 1
            for position in 0..<half {
                let a = excitation[1_024 - half + position]
                let b = excitation[1_024 - 2 * half + position]
                recent += a * a
                earlier += b * b
            }
            let decay = sqrt(min(recent, earlier) / earlier)
            var attenuation = (continuing ? Float(0.8) : 1) * decay
            var prediction = Array(repeating: Float(0), count: count)
            var expectedEnergy: Float = 0
            var position = 0
            for index in 0..<count {
                if position >= pitchPeriod {
                    position -= pitchPeriod
                    attenuation *= decay
                }
                prediction[index] = attenuation * excitation[1_024 - pitchPeriod + position]
                let original = history[channel][2_048 - pitchPeriod + position]
                expectedEnergy += original * original
                position += 1
            }
            prediction = Self.synthesis(prediction, coefficients: coefficients[channel], history: history[channel])
            var actualEnergy: Float = 0
            for value in prediction { actualEnergy += value * value }
            if !(expectedEnergy > 0.2 * actualEnergy) {
                prediction = Array(repeating: 0, count: count)
            } else if expectedEnergy < actualEnergy {
                let ratio = sqrt((expectedEnergy + 1) / (actualEnergy + 1))
                for index in 0..<count {
                    let gain = index < 120 ? 1 - window[index] * (1 - ratio) : ratio
                    prediction[index] *= gain
                }
            }
            result.append(prediction)
        }
        return result
    }

    /// Computes a windowed autocorrelation in scalar reference order.
    /// - Parameters:
    ///   - input: Nonempty finite signal history with more samples than `order`.
    ///   - order: LPC order, either four or 24 for the two admitted callers.
    ///   - window: Optional symmetric endpoint window, no larger than half the input.
    /// - Returns: Exactly `order + 1` finite autocorrelation sums for lag zero onward.
    private static func autocorrelation(_ input: [Float], order: Int, window: [Float] = []) -> [Float] {
        var signal = input
        for index in window.indices {
            signal[index] *= window[index]
            signal[signal.count - 1 - index] *= window[index]
        }
        let fastCount = signal.count - order
        return (0...order).map { lag in
            var value: Float = 0
            for index in 0..<fastCount { value += signal[index] * signal[index + lag] }
            var tail: Float = 0
            for index in (lag + fastCount)..<signal.count { tail += signal[index] * signal[index - lag] }
            return value + tail
        }
    }

    /// Solves the reference floating-point Levinson-Durbin recursion with its 30-dB stop.
    /// - Parameters:
    ///   - correlation: `order + 1` autocorrelation values with stabilized lag-zero energy.
    ///   - order: Four or 24 predictor coefficients requested by the validated caller.
    /// - Returns: Exactly `order` coefficients; near-silence returns the all-zero filter.
    private static func lpc(_ correlation: [Float], order: Int) -> [Float] {
        var result = Array(repeating: Float(0), count: order)
        var error = correlation[0]
        guard error > 1e-10 else { return result }
        for index in 0..<order {
            var sum: Float = 0
            for prior in 0..<index { sum += result[prior] * correlation[index - prior] }
            sum += correlation[index + 1]
            let reflection = -sum / error
            result[index] = reflection
            for prior in 0..<((index + 1) / 2) {
                let first = result[prior]
                let last = result[index - 1 - prior]
                result[prior] = first + reflection * last
                result[index - 1 - prior] = last + reflection * first
            }
            error -= (reflection * reflection) * error
            if error <= 0.001 * correlation[0] { break }
        }
        return result
    }

    /// Reconstructs signal from excitation with the reference four-sample IIR update order.
    /// - Parameters:
    ///   - input: Missing-frame excitation including 120 future overlap samples.
    ///   - coefficients: Exactly 24 LPC denominator coefficients.
    ///   - history: Exactly 2,048 preceding signal samples; the latest 24 initialize memory.
    /// - Returns: Complete reconstructed signal without changing caller-owned history.
    private static func synthesis(_ input: [Float], coefficients: [Float], history: [Float]) -> [Float] {
        let order = Self.order
        let reversed = Array(coefficients.reversed())
        var negative = history.suffix(order).map { -$0 }
        negative += Array(repeating: 0, count: input.count)
        var result = input
        for start in stride(from: 0, to: input.count, by: 4) {
            var sums = Array(input[start..<(start + 4)])
            for tap in 0..<order {
                for lane in 0..<4 { sums[lane] += reversed[tap] * negative[start + lane + tap] }
            }
            for lane in 0..<4 {
                for prior in 0..<lane {
                    sums[lane] += negative[start + order + lane - 1 - prior] * coefficients[prior]
                }
                negative[start + order + lane] = -sums[lane]
                result[start + lane] = sums[lane]
            }
        }
        return result
    }

    /// Whitens a shared stereo-summed half-rate signal and runs coarse/fine pitch search.
    /// - Parameter history: One or two 2,048-sample pre-deemphasis channel histories.
    /// - Returns: Reference periodic PLC lag in 100...720 samples at 48 kHz.
    private static func searchPitch(_ history: [[Float]]) -> Int {
        var low = Array(repeating: Float(0), count: 1_024)
        for channel in history {
            low[0] += 0.25 * channel[1] + 0.5 * channel[0]
            for index in 1..<1_024 {
                low[index] += 0.25 * channel[2 * index - 1] + 0.25 * channel[2 * index + 1] + 0.5 * channel[2 * index]
            }
        }
        var correlation = autocorrelation(low, order: 4)
        correlation[0] *= 1.0001
        for lag in 1...4 { correlation[lag] -= correlation[lag] * (0.008 * Float(lag)) * (0.008 * Float(lag)) }
        var filter = lpc(correlation, order: 4)
        var expansion: Float = 1
        for index in 0..<4 {
            expansion *= 0.9
            filter[index] *= expansion
        }
        let taps = [filter[0] + 0.8, filter[1] + 0.8 * filter[0],
                    filter[2] + 0.8 * filter[1], filter[3] + 0.8 * filter[2], 0.8 * filter[3]]
        let original = low
        for index in low.indices {
            var value = original[index]
            for lag in 0..<min(index, 5) { value += taps[lag] * original[index - 1 - lag] }
            low[index] = value
        }
        let length = 2_048 - 720
        let maximum = 720 - 100
        let reference = Array(low[360...])
        let coarseX = (0..<(length / 4)).map { reference[2 * $0] }
        let coarseY = (0..<((length + maximum) / 4)).map { low[2 * $0] }
        let coarse = correlations(coarseX, coarseY, count: maximum / 4)
        let candidates = bestPitch(coarse, signal: coarseY, length: length / 4)
        var fine = Array(repeating: Float(0), count: maximum / 2)
        for lag in fine.indices where abs(lag - 2 * candidates[0]) <= 2 || abs(lag - 2 * candidates[1]) <= 2 {
            var sum: Float = 0
            for index in 0..<(length / 2) { sum += reference[index] * low[lag + index] }
            fine[lag] = max(-1, sum)
        }
        let best = bestPitch(fine, signal: low, length: length / 2)[0]
        var offset = 0
        if best > 0 && best < maximum / 2 - 1 {
            let a = fine[best - 1], b = fine[best], c = fine[best + 1]
            if c - a > 0.7 * (b - a) { offset = 1 }
            else if a - c > 0.7 * (b - c) { offset = -1 }
        }
        return 720 - (2 * best - offset)
    }

    /// Evaluates scalar cross-correlation at consecutive lags for the coarse pitch search.
    /// - Parameters:
    ///   - reference: Complete decimated correlation window.
    ///   - signal: Search signal containing `reference.count + count - 1` or more samples.
    ///   - count: Positive number of consecutive candidate lags.
    /// - Returns: Exactly `count` correlation values in increasing lag order.
    private static func correlations(_ reference: [Float], _ signal: [Float], count: Int) -> [Float] {
        (0..<count).map { lag in
            var sum: Float = 0
            for index in reference.indices { sum += reference[index] * signal[index + lag] }
            return sum
        }
    }

    /// Selects two pitch lags by positive squared correlation divided by sliding energy.
    /// - Parameters:
    ///   - correlation: Nonempty consecutive lag correlations, including zero for skipped lags.
    ///   - signal: Search signal with enough samples for every lag and energy update.
    ///   - length: Positive reference window length at the current decimation rate.
    /// - Returns: The best and runner-up lag, preserving reference tie order.
    private static func bestPitch(_ correlation: [Float], signal: [Float], length: Int) -> [Int] {
        var energy: Float = 1
        for value in signal.prefix(length) { energy += value * value }
        var numerators: [Float] = [-1, -1]
        var denominators: [Float] = [0, 0]
        var result = [0, 1]
        for index in correlation.indices {
            if correlation[index] > 0 {
                let scaled = correlation[index] * 1e-12
                let numerator = scaled * scaled
                if numerator * denominators[1] > numerators[1] * energy {
                    if numerator * denominators[0] > numerators[0] * energy {
                        numerators[1] = numerators[0]
                        denominators[1] = denominators[0]
                        result[1] = result[0]
                        numerators[0] = numerator
                        denominators[0] = energy
                        result[0] = index
                    } else {
                        numerators[1] = numerator
                        denominators[1] = energy
                        result[1] = index
                    }
                }
            }
            energy += signal[index + length] * signal[index + length] - signal[index] * signal[index]
            energy = max(1, energy)
        }
        return result
    }
}
