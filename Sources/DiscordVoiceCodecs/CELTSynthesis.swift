// File: Sources/DiscordVoiceCodecs/CELTSynthesis.swift
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

import Foundation

/// Invalid synthesis inputs, rejected before overlap, pitch or deemphasis history changes.
public enum CELTSynthesisError: Error, Sendable, Equatable {
    case invalidChannelCount, invalidFrameSize, invalidBandRange, invalidCoefficients
    case invalidBandEnergies, invalidTransient
}

/// Stateful ordinary 48-kHz CELT synthesis in the floating-point Opus signal domain.
///
/// Normalized channel-major bands are restored with the normative band means and
/// exponential approximation, deinterleaved into long or 120-sample short MDCTs,
/// overlap-added, pitch postfiltered with the two-stage delayed filter transitions,
/// then deemphasized and divided by 32768 into interleaved floating-point PCM.
/// A common 120-sample tail supports duration/transient changes without resetting.
/// Value copies own independent histories; execution is synchronous and bounded.
/// Coded mono spectra can feed two independent output histories, and coded stereo
/// is downmixed to mono after per-channel denormalization. No entropy decoding,
/// clipping, resampling, device work or tasks occur here. Callers apply anti-collapse first.
public struct CELTSynthesis: Sendable {
    public let channelCount: Int
    private let transforms: [CELTTransform]
    private let window: [Float]
    private var overlap: [[Float]]
    private var pitchHistory: [[Float]]
    private var deemphasisMemory: [Float]
    private var filter: CELTPostfilterParameters?
    private var oldFilter: CELTPostfilterParameters?
    private static let historyCount = 2048
    private var periodicConcealment = CELTPeriodicConcealment()
    private var lossDuration = 0
    private var previousLossWasPeriodic = false
    private var skipPeriodicConcealment = true
    private var needsPredictionFold = false
    private static let means: [Float] = [6.4375, 6.25, 5.75, 5.3125, 5.0625,
        4.8125, 4.5, 4.375, 4.875, 4.6875, 4.5625, 4.4375, 4.875, 4.625,
        4.3125, 4.5, 4.375, 4.625, 4.75, 4.4375, 3.75]
    private static let taps: [[Float]] = [
        [0.3066406250, 0.2170410156, 0.1296386719],
        [0.4638671875, 0.2680664062, 0],
        [0.7998046875, 0.1000976562, 0],
    ]

    /// Precomputes every ordinary mono transform and initializes independent zero histories.
    /// - Parameter channelCount: Exactly one or two persistent output channels; default one.
    ///   Each frame may independently declare one or two coded channels when synthesizing.
    /// - Throws: `invalidChannelCount` outside `1...2`; transform validation errors cannot
    ///   occur for the four internal fixed modes. Construction starts no I/O or work tasks.
    public init(channelCount: Int = 1) throws {
        guard (1...2).contains(channelCount) else { throw CELTSynthesisError.invalidChannelCount }
        self.channelCount = channelCount
        transforms = try [120, 240, 480, 960].map { try CELTTransform(frameSampleCount: $0) }
        window = (0..<120).map { position in
            let inner = sin(0.5 * Double.pi * (Double(position) + 0.5) / 120)
            return Float(sin(0.5 * Double.pi * inner * inner))
        }
        overlap = Array(repeating: Array(repeating: 0, count: 120), count: channelCount)
        pitchHistory = Array(repeating: Array(repeating: 0, count: Self.historyCount), count: channelCount)
        deemphasisMemory = Array(repeating: 0, count: channelCount)
    }

    /// Restores one ordinary decoded frame and commits its signal histories atomically.
    /// - Parameters:
    ///   - normalizedCoefficients: Exactly `frameSampleCount * codedChannelCount` finite
    ///     channel-major coefficients with magnitude at most four. Active bands are
    ///     independently normalized; transient short-block bins are frequency-major
    ///     with the block index varying fastest, as emitted by CELT all-band decoding.
    ///   - bandLogEnergies: Exactly `21 * codedChannelCount` finite channel-major log2
    ///     amplitudes relative to CELT band means, in `-32768...32768`. All values,
    ///     including inactive entries, are validated; exponent gain caps at 32.
    ///   - frameSampleCount: Exactly 120, 240, 480 or 960 samples/channel at 48 kHz;
    ///     duration changes retain the common overlap and filter/deemphasis histories.
    ///   - startBand: First active global band in `0...20`; default zero.
    ///   - endBand: Exclusive active end in `(startBand + 1)...21`; default 21.
    ///   - isTransient: Selects `frameSampleCount / 120` short MDCTs; default false.
    ///     A 120-sample frame has no transient syntax and rejects true.
    ///   - postfilter: Newly signaled validated filter or nil for zero gain; the
    ///     first 120 samples transition previous filters and longer frames then
    ///     transition toward this filter, preserving normative 2.5-ms delay.
    ///   - silence: Ignores otherwise validated spectral values and synthesizes zero
    ///     MDCT input while draining previous overlap/filter/deemphasis history.
    ///   - codedChannelCount: One or two channels in the supplied spectra/envelopes;
    ///     nil defaults to the persistent output `channelCount`. Coded mono duplicates
    ///     denormalized spectra for stereo output while preserving separate signal
    ///     histories. Coded stereo feeding mono output averages the independently
    ///     denormalized frequencies before the inverse transform. Per-frame changes
    ///     retain overlap, postfilter and deemphasis histories for each output channel.
    /// - Returns: Exactly `frameSampleCount * channelCount` interleaved float PCM;
    ///   amplitude is normalized by 32768 and is deliberately not clipped to unity.
    /// - Throws: `CELTSynthesisError` for invalid shape/range/numeric values before
    ///   history mutation; internal transform errors also preserve all histories.
    /// Execution costs bounded O(C*N log N) work and O(C*N) scratch allocation.
    public mutating func synthesize(normalizedCoefficients: [Float], bandLogEnergies: [Float],
        frameSampleCount: Int, startBand: Int = 0, endBand: Int = 21,
        isTransient: Bool = false, postfilter: CELTPostfilterParameters? = nil,
        silence: Bool = false, codedChannelCount: Int? = nil) throws -> [Float] {
        guard let mode = [120, 240, 480, 960].firstIndex(of: frameSampleCount) else {
            throw CELTSynthesisError.invalidFrameSize
        }
        let codedChannels = codedChannelCount ?? channelCount
        guard (1...2).contains(codedChannels) else { throw CELTSynthesisError.invalidChannelCount }
        guard (0...20).contains(startBand), endBand > startBand, endBand <= 21 else {
            throw CELTSynthesisError.invalidBandRange
        }
        guard normalizedCoefficients.count == frameSampleCount * codedChannels,
              normalizedCoefficients.allSatisfy({ $0.isFinite && abs($0) <= 4 }) else {
            throw CELTSynthesisError.invalidCoefficients
        }
        guard bandLogEnergies.count == 21 * codedChannels,
              bandLogEnergies.allSatisfy({ $0.isFinite && abs($0) <= 32_768 }) else {
            throw CELTSynthesisError.invalidBandEnergies
        }
        guard !isTransient || mode > 0 else { throw CELTSynthesisError.invalidTransient }
        var working = self
        if working.lossDuration == 0 { working.skipPeriodicConcealment = false }
        working.foldPredictionOverlap()
        let multiple = 1 << mode
        let blockCount = isTransient ? multiple : 1
        let blockSize = frameSampleCount / blockCount
        let transform = transforms[isTransient ? 0 : mode]
        var output = Array(repeating: Float(0), count: frameSampleCount * channelCount)
        var codedFrequencies = Array(repeating: Array(repeating: Float(0), count: frameSampleCount), count: codedChannels)
        if !silence {
            for channel in 0..<codedChannels {
                for band in startBand..<endBand {
                    let gain = Self.exponential(min(32, bandLogEnergies[channel * 21 + band] + Self.means[band]))
                    let lower = multiple * CELTAllocationTables.bandEdges[band]
                    let upper = multiple * CELTAllocationTables.bandEdges[band + 1]
                    for bin in lower..<upper {
                        codedFrequencies[channel][bin] = normalizedCoefficients[channel * frameSampleCount + bin] * gain
                    }
                }
            }
        }
        for channel in 0..<channelCount {
            let frequencies: [Float]
            if channelCount == 1 && codedChannels == 2 {
                frequencies = zip(codedFrequencies[0], codedFrequencies[1]).map { 0.5 * $0 + 0.5 * $1 }
            } else {
                frequencies = codedFrequencies[codedChannels == 1 ? 0 : channel]
            }
            var signal = working.pitchHistory[channel]
            for block in 0..<blockCount {
                var coefficients = (0..<blockSize).map { frequencies[$0 * blockCount + block] }
                let maximum = coefficients.reduce(Float(0)) { max($0, abs($1)) }
                // Power-of-two scaling preserves float significands and the primitive's finite bound.
                var scale: Float = 1
                while maximum / scale > 4 { scale *= 2 }
                if scale != 1 { coefficients = coefficients.map { $0 / scale } }
                let inverse = try transform.inverse(coefficients).map { $0 * scale }
                for index in 0..<blockSize {
                    signal.append(inverse[index] + (index < 120 ? working.overlap[channel][index] : 0))
                }
                working.overlap[channel] = Array(inverse.suffix(120))
            }
            working.applyPostfilter(&signal, start: Self.historyCount, count: 120,
                                     previous: working.oldFilter, next: working.filter)
            if mode > 0 {
                working.applyPostfilter(&signal, start: Self.historyCount + 120, count: frameSampleCount - 120,
                                         previous: working.filter, next: postfilter)
            }
            working.pitchHistory[channel] = Array(signal.suffix(Self.historyCount))
            var memory = working.deemphasisMemory[channel]
            for index in 0..<frameSampleCount {
                let sample = signal[Self.historyCount + index] + 1e-30 + memory
                memory = 0.85000610 * sample
                output[index * channelCount + channel] = sample / 32768
            }
            working.deemphasisMemory[channel] = memory
        }
        working.oldFilter = mode > 0 ? postfilter : working.filter
        working.filter = postfilter
        working.lossDuration = 0
        working.previousLossWasPeriodic = false
        self = working
        return output
    }

    /// Conceals one missing ordinary CELT frame with periodic LPC or shaped-noise synthesis.
    ///
    /// The first 100ms of eligible losses use shared pitch search, per-channel 24th-order
    /// LPC excitation extrapolation, decay/fading and explosion protection. Cold-start,
    /// hybrid high-band or long-loss output instead uses deterministic random normalized
    /// bands and a decaying envelope bounded below by the supplied background. Prediction
    /// overlap is prefiltered and TDAC-folded before the next ordinary/noise MDCT frame.
    /// Two received frames are required after noise PLC before periodic PLC is eligible.
    /// This is loss synthesis, not entropy decoding, FEC or a complete Opus loss policy.
    /// - Parameters:
    ///   - frameSampleCount: Exactly 120, 240, 480 or 960 samples/channel at 48 kHz.
    ///   - bandLogEnergies: Current channel-major 21-band predictor, finite in -32768...32768.
    ///   - backgroundLogEnergies: Same-shaped learned lower envelope; every entry must be
    ///     finite in -32768...32768. The enclosing decoder owns background adaptation.
    ///   - seed: Current range/random seed; noise PLC advances the normative wrapping LCG.
    ///   - startBand: First active band in 0...20; nonzero forces noise PLC for hybrid use.
    ///   - endBand: Exclusive active upper band in `(startBand + 1)...21`; default 21.
    ///   - forceNoise: Explicitly selects noise PLC when the enclosing decoder requires it.
    /// - Returns: Exactly `frameSampleCount * channelCount` PCM samples, updated envelope,
    ///   random seed, bounded loss duration and selected loss path diagnostics.
    /// - Throws: Synthesis validation errors for bad dimensions/ranges/numeric values.
    ///   All validation and synthesis use a private value copy; failure changes no history.
    /// The call is synchronous, has bounded O(C*N) scratch plus fixed pitch-search work,
    /// starts no tasks/I/O and contains no suspension or cancellation point.
    public mutating func conceal(frameSampleCount: Int, bandLogEnergies: [Float],
        backgroundLogEnergies: [Float], seed: UInt32, startBand: Int = 0,
        endBand: Int = 21, forceNoise: Bool = false) throws -> CELTConcealedFrame {
        guard let mode = [120, 240, 480, 960].firstIndex(of: frameSampleCount) else {
            throw CELTSynthesisError.invalidFrameSize
        }
        guard (0...20).contains(startBand), endBand > startBand, endBand <= 21 else {
            throw CELTSynthesisError.invalidBandRange
        }
        guard bandLogEnergies.count == channelCount * 21,
              backgroundLogEnergies.count == channelCount * 21,
              (bandLogEnergies + backgroundLogEnergies).allSatisfy({ $0.isFinite && abs($0) <= 32_768 }) else {
            throw CELTSynthesisError.invalidBandEnergies
        }
        var working = self
        let noise = forceNoise || startBand != 0 || lossDuration >= 40 || skipPeriodicConcealment
        let duration = min(10_000, lossDuration + (1 << mode))
        var energies = bandLogEnergies
        var nextSeed = seed
        let output: [Float]
        if noise {
            var coefficients = Array(repeating: Float(0), count: frameSampleCount * channelCount)
            for channel in 0..<channelCount {
                for band in startBand..<endBand {
                    let energyIndex = channel * 21 + band
                    energies[energyIndex] = max(backgroundLogEnergies[energyIndex], energies[energyIndex] - (lossDuration == 0 ? 1.5 : 0.5))
                    let lower = (CELTAllocationTables.bandEdges[band] << mode) + channel * frameSampleCount
                    let upper = (CELTAllocationTables.bandEdges[band + 1] << mode) + channel * frameSampleCount
                    var energy: Float = 1e-15
                    for bin in lower..<upper {
                        nextSeed = nextSeed &* 1_664_525 &+ 1_013_904_223
                        let value = Float(Int32(bitPattern: nextSeed) >> 20)
                        coefficients[bin] = value
                        energy += value * value
                    }
                    let gain = 1 / sqrt(energy)
                    for bin in lower..<upper { coefficients[bin] *= gain }
                }
            }
            output = try working.synthesize(normalizedCoefficients: coefficients, bandLogEnergies: energies,
                frameSampleCount: frameSampleCount, startBand: startBand, endBand: endBand, postfilter: filter)
            working.skipPeriodicConcealment = true
        } else {
            let prediction = working.periodicConcealment.predict(history: pitchHistory,
                frameSampleCount: frameSampleCount, window: window, continuing: previousLossWasPeriodic)
            var samples = Array(repeating: Float(0), count: frameSampleCount * channelCount)
            for channel in 0..<channelCount {
                working.pitchHistory[channel] = Array((pitchHistory[channel] + prediction[channel].prefix(frameSampleCount)).suffix(Self.historyCount))
                working.overlap[channel] = Array(prediction[channel].suffix(120))
                var memory = deemphasisMemory[channel]
                for index in 0..<frameSampleCount {
                    let sample = prediction[channel][index] + 1e-30 + memory
                    memory = 0.85000610 * sample
                    samples[index * channelCount + channel] = sample / 32768
                }
                working.deemphasisMemory[channel] = memory
            }
            working.needsPredictionFold = true
            output = samples
        }
        working.lossDuration = duration
        working.previousLossWasPeriodic = !noise
        self = working
        return CELTConcealedFrame(samples: output, bandLogEnergies: energies, seed: nextSeed,
            usesNoise: noise, lossDuration: duration,
            pitchPeriod: noise ? 0 : periodicConcealment.pitchPeriod)
    }

    /// Clears overlap, pitch/filter and deemphasis histories while retaining immutable transform plans.
    /// The next frame starts from exact zero signal state; pending overlap is discarded.
    /// This synchronous operation starts no work and cannot fail.
    public mutating func reset() {
        overlap = Array(repeating: Array(repeating: 0, count: 120), count: channelCount)
        pitchHistory = Array(repeating: Array(repeating: 0, count: Self.historyCount), count: channelCount)
        deemphasisMemory = Array(repeating: 0, count: channelCount)
        filter = nil
        oldFilter = nil
        periodicConcealment = CELTPeriodicConcealment()
        lossDuration = 0
        previousLossWasPeriodic = false
        skipPeriodicConcealment = true
        needsPredictionFold = false
    }

    /// Converts predicted postfiltered future audio into the compact MDCT overlap representation.
    ///
    /// The negative comb prefilter reads the unchanged input rather than feeding its
    /// output back recursively. Symmetric tail folding is the full-120-sample equivalent
    /// of the reference decoder's 60-sample TDAC folded overlap. No work occurs unless
    /// a preceding periodic loss supplied raw future prediction samples.
    private mutating func foldPredictionOverlap() {
        guard needsPredictionFold else { return }
        for channel in 0..<channelCount {
            let source = pitchHistory[channel] + overlap[channel]
            var filtered = overlap[channel]
            let next = filter
            let coefficients1 = Self.taps[next?.tapset ?? 0].map { -(next?.gain ?? 0) * $0 }
            let period1 = next?.period ?? 15
            for index in 0..<120 {
                let position = Self.historyCount + index
                // prefilter_and_fold uses a zero-length transition window: use the latest filter.
                var value = source[position] + coefficients1[0] * source[position - period1]
                value += coefficients1[1] * (source[position - period1 + 1] + source[position - period1 - 1])
                value += coefficients1[2] * (source[position - period1 + 2] + source[position - period1 - 2])
                filtered[index] = value
            }
            for index in 0..<120 {
                let falling = window[119 - index]
                overlap[channel][index] = falling * (falling * filtered[index] + window[index] * filtered[119 - index])
            }
        }
        needsPredictionFold = false
    }

    /// Evaluates the ordinary floating-point libopus base-two exponential approximation.
    /// - Parameter exponent: Finite relative-plus-mean exponent, capped at 32 by the caller.
    /// - Returns: Zero below -50, otherwise the nonnegative fifth-order float approximation.
    /// Integer exponent insertion uses exact IEEE-754 Float bits and bounded shifts.
    private static func exponential(_ exponent: Float) -> Float {
        let integer = Int(floor(exponent))
        if integer < -50 { return 0 }
        let fraction = exponent - Float(integer)
        let polynomial: Float = 0.999999940395355224609375 + fraction * (0.693153083324432373046875
            + fraction * (0.240153610706329345703125 + fraction * (0.0558263175189495086669921875
            + fraction * (0.00898933969438076019287109375 + fraction * 0.001877576694823801517486572265625))))
        let adjusted = Int64(polynomial.bitPattern) + Int64(integer) * (1 << 23)
        return Float(bitPattern: UInt32(truncatingIfNeeded: adjusted) & 0x7fff_ffff)
    }

    /// Applies one exact in-place five-tap recursive comb filter with a 120-sample window crossfade.
    /// - Parameters:
    ///   - signal: Pitch history followed by current unfiltered synthesis, modified in place.
    ///   - start: First current sample, at least 2048 so the largest delayed tap is in bounds.
    ///   - count: Multiple of 120 samples, at least 120; all referenced samples exist.
    ///   - previous: Previous validated filter; nil has zero gain and period clamped to 15.
    ///   - next: Target validated filter; nil has zero gain and period clamped to 15.
    /// Float operation order follows the scalar source; no saturation/clipping applies.
    private func applyPostfilter(_ signal: inout [Float], start: Int, count: Int,
                                  previous: CELTPostfilterParameters?, next: CELTPostfilterParameters?) {
        let gain0 = previous?.gain ?? 0
        let gain1 = next?.gain ?? 0
        if gain0 == 0 && gain1 == 0 { return }
        let period0 = previous?.period ?? 15
        let period1 = next?.period ?? 15
        let coefficients0 = Self.taps[previous?.tapset ?? 0].map { gain0 * $0 }
        let coefficients1 = Self.taps[next?.tapset ?? 0].map { gain1 * $0 }
        let crossfade = previous == next ? 0 : 120
        for index in 0..<count {
            let position = start + index
            if index < crossfade {
                let fade = window[index] * window[index]
                var sample = signal[position] + ((1 - fade) * coefficients0[0]) * signal[position - period0]
                sample += ((1 - fade) * coefficients0[1]) * (signal[position - period0 + 1] + signal[position - period0 - 1])
                sample += ((1 - fade) * coefficients0[2]) * (signal[position - period0 + 2] + signal[position - period0 - 2])
                sample += (fade * coefficients1[0]) * signal[position - period1]
                sample += (fade * coefficients1[1]) * (signal[position - period1 + 1] + signal[position - period1 - 1])
                sample += (fade * coefficients1[2]) * (signal[position - period1 + 2] + signal[position - period1 - 2])
                signal[position] = sample
            } else if gain1 != 0 {
                var sample = signal[position] + coefficients1[0] * signal[position - period1]
                sample += coefficients1[1] * (signal[position - period1 + 1] + signal[position - period1 - 1])
                sample += coefficients1[2] * (signal[position - period1 + 2] + signal[position - period1 - 2])
                signal[position] = sample
            }
        }
    }
}
