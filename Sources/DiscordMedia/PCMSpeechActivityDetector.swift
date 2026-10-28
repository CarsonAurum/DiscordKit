// File: Sources/DiscordMedia/PCMSpeechActivityDetector.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import Foundation

/// One complete analysis frame's statistical speech decision, with inspectable diagnostics.
///
/// Diagnostics describe the qualifying channel with greatest estimated SNR, or the greatest
/// SNR channel when neither qualifies. They are signal features, not calibrated probabilities.
/// `isSpeech` includes a bounded post-speech hangover; `hasSpeechEvidence` does not.
public struct PCMSpeechActivityDecision: Sendable, Equatable {
    /// Whether either channel supplies speech evidence or the configured hangover is active.
    public let isSpeech: Bool

    /// Whether either channel currently satisfies the multi-feature speech decision.
    public let hasSpeechEvidence: Bool

    /// Whether fewer than five complete analysis frames preceded this decision.
    public let isWarmingUp: Bool

    /// Zero-based channel supplying the diagnostics; stereo channels are never summed.
    public let channelIndex: Int

    /// Estimated zero-mean analysis energy relative to the adaptive background, in decibels.
    public let signalToNoiseRatioDB: Double

    /// Maximum normalized autocorrelation over approximately 80–500Hz pitch periods, in 0...1.
    public let periodicity: Double

    /// Geometric/arithmetic spectral power ratio in 100–3900Hz, in 0...1; noise tends higher.
    public let spectralFlatness: Double

    /// Fraction of spectral power in the strongest three adjacent bins, in 0...1.
    public let strongestToneFraction: Double
}

/// A bounded, caller-driven statistical speech activity detector for normalized mono/stereo PCM.
///
/// Complete nonoverlapping frames contain `floor(sampleRate / 50)` input samples per channel,
/// approximately 20ms. Each channel is independently box-averaged to 160 analysis samples,
/// mean-subtracted and Hann-windowed. The detector combines adaptive background-relative
/// energy, normalized pitch autocorrelation, spectral flatness, occupied frequency bands,
/// rejection of isolated tones and short-term spectral/energy change. Recent voiced evidence
/// permits brief changing noise-like consonant bursts; a bounded hangover bridges short gaps.
/// This is an owned heuristic VAD, distinct from `PCMBuffer.passesEnergyGate(threshold:)`.
/// Its feature families follow subband/harmonic and temporal-SNR approaches described by
/// [Guo et al.](https://www.isca-archive.org/iscslp_2006/guo06b_iscslp.html) and
/// [Tan and Lindberg](https://www.isca-archive.org/interspeech_2009/tan09_interspeech.html),
/// without claiming either algorithm's implementation, standard conformance or accuracy.
///
/// Thresholds have deterministic synthetic regression coverage, not trained-corpus or human
/// speech accuracy qualification. Whispered/unvoiced-only or low-SNR speech can be missed;
/// music, changing harmonic machinery and competing speech can be accepted. Unchanged
/// harmonic material is suppressed after approximately 500ms, which can also suppress long
/// steady vowels. Box averaging is a coarse analysis reduction rather than a production
/// antialias resampler. No echo cancellation, denoising, pre-roll audio or speaker identity
/// is provided. A decision arrives only after its entire frame; no earlier result is revised.
///
/// Retained audio is less than one input analysis frame, at most 7,678 floats at 192kHz stereo,
/// plus fixed per-channel feature history. Work is linear in input samples plus fixed-size
/// per-frame analysis; each 120ms input produces at most seven decisions. Construction and
/// processing are synchronous, start no tasks or I/O and contain no suspension/cancellation
/// points. Copies have independent value state; callers serialize mutation of each value.
public struct PCMSpeechActivityDetector: Sendable {
    /// Exact input sample rate and mono/stereo layout required throughout the stream.
    public let format: PCMFormat

    /// Input sample frames in each decision, `floor(format.sampleRate / 50)`.
    public let analysisFrameCount: Int

    /// Number of no-evidence frames retained as speech after the last evidence, in 0...50.
    public let hangoverFrameCount: Int

    /// Number of complete interleaved input frames waiting for a full analysis window.
    public private(set) var bufferedFrameCount = 0

    /// Dense incomplete interleaved analysis window; no input array or slice is retained.
    private var pendingSamples: [Float] = []

    /// Independent background, temporal and speech-context history for each input channel.
    private var channels: [ChannelState]

    /// Saturating warmup counter; it never grows with stream lifetime.
    private var warmupFrames = 0

    /// Remaining complete no-evidence frames admitted by the global stereo-OR hangover.
    private var hangoverRemaining = 0

    /// Fixed-size adaptive feature history for one channel; no audio is retained here.
    private struct ChannelState: Sendable {
        var noiseEnergy = 0.000_001
        var hasNoiseObservation = false
        var previousEnergy = 0.000_001
        var previousBands = Array(repeating: 0.0, count: 8)
        var stationaryFrames = 0
        var voicedContext = 0
    }

    /// Current channel features used to select the diagnostic channel and combine decisions.
    private struct ChannelDecision {
        let evidence: Bool
        let snr: Double
        let periodicity: Double
        let flatness: Double
        let toneFraction: Double
    }

    /// Creates an empty detector without consuming audio, starting work or acquiring resources.
    /// - Parameters:
    ///   - format: Validated PCM format; every supported PCM rate and layout is accepted.
    ///     Analysis duration is slightly below 20ms for rates not divisible by 50.
    ///   - hangoverFrameCount: Complete no-evidence frames following evidence to mark as speech,
    ///     in `0...50`, default five (approximately 100ms). Zero disables hangover.
    /// - Throws: `MediaError.invalidCapacity` for negative or greater-than-50 hangover counts.
    public init(format: PCMFormat, hangoverFrameCount: Int = 5) throws {
        guard (0...50).contains(hangoverFrameCount) else { throw MediaError.invalidCapacity }
        self.format = format
        self.analysisFrameCount = format.sampleRate / 50
        self.hangoverFrameCount = hangoverFrameCount
        self.channels = Array(repeating: ChannelState(), count: format.channelCount)
        pendingSamples.reserveCapacity(analysisFrameCount * format.channelCount)
    }

    /// Consumes contiguous PCM and emits ordered decisions for every newly complete frame.
    ///
    /// Chunking never changes framing or decisions. Empty matching input is a no-op; partial
    /// frames wait for the next call and do not advance warmup, background or hangover. Strong
    /// structured speech can be detected during the first five warmup frames, using a stricter
    /// SNR threshold; there is no requirement that the stream start with silence. Background
    /// adapts only on non-speech decisions and is frozen during evidence and hangover. Stereo
    /// classification is OR over independently analyzed channels, so opposite-polarity speech
    /// cannot cancel. No input storage is retained after return beyond copied partial samples.
    /// - Parameter buffer: Next at-most-120ms block, exactly matching `format`.
    /// - Returns: Zero through seven complete-frame decisions; no timestamps or audio ownership.
    /// - Throws: `MediaError.incompatibleBuffers` for a different sample rate or channel count,
    ///   including empty buffers. Validation precedes mutation, preserving all prior state.
    public mutating func process(_ buffer: PCMBuffer) throws -> [PCMSpeechActivityDecision] {
        guard buffer.format == format else { throw MediaError.incompatibleBuffers }
        guard buffer.frameCount > 0 else { return [] }
        let target = analysisFrameCount * format.channelCount
        var results: [PCMSpeechActivityDecision] = []
        results.reserveCapacity((pendingSamples.count + buffer.samples.count) / target)
        var offset = 0
        while offset < buffer.samples.count {
            let end = min(buffer.samples.count, offset + target - pendingSamples.count)
            pendingSamples.append(contentsOf: buffer.samples[offset..<end])
            offset = end
            if pendingSamples.count == target {
                results.append(analyzeFrame())
                pendingSamples.removeAll(keepingCapacity: true)
            }
        }
        bufferedFrameCount = pendingSamples.count / format.channelCount
        return results
    }

    /// Discards partial audio, learned background, warmup and hangover for a discontinuity.
    ///
    /// Format and configuration remain fixed. Repeated resets and reset before processing are
    /// valid. A partial final frame is intentionally abandoned; it is never padded or classified.
    /// The next sample starts a new framing origin. No task, resource or I/O requires cleanup.
    public mutating func reset() {
        pendingSamples.removeAll(keepingCapacity: true)
        bufferedFrameCount = 0
        channels = Array(repeating: ChannelState(), count: format.channelCount)
        warmupFrames = 0
        hangoverRemaining = 0
    }

    /// Analyzes exactly one complete retained frame and advances bounded decision history.
    /// - Returns: Stereo-OR evidence, global hangover and diagnostics from a selected channel.
    ///   All diagnostic values are finite; no clock, task or external state is consulted.
    private mutating func analyzeFrame() -> PCMSpeechActivityDecision {
        let warming = warmupFrames < 5
        var selected: ChannelDecision?
        var selectedIndex = 0
        var hasEvidence = false
        for channel in 0..<format.channelCount {
            let samples = Self.analysisSamples(
                pendingSamples, channel: channel, channels: format.channelCount,
                frameCount: analysisFrameCount
            )
            let decision = Self.classify(
                samples, state: &channels[channel], warming: warming,
                backgroundFrozen: hangoverRemaining > 0
            )
            hasEvidence = hasEvidence || decision.evidence
            if selected == nil || (decision.evidence && !selected!.evidence)
                || (decision.evidence == selected!.evidence && decision.snr > selected!.snr) {
                selected = decision
                selectedIndex = channel
            }
        }
        let features = selected!
        let speech = hasEvidence || hangoverRemaining > 0
        if hasEvidence { hangoverRemaining = hangoverFrameCount }
        else { hangoverRemaining = max(0, hangoverRemaining - 1) }
        warmupFrames = min(5, warmupFrames + 1)
        return PCMSpeechActivityDecision(
            isSpeech: speech, hasSpeechEvidence: hasEvidence, isWarmingUp: warming,
            channelIndex: selectedIndex, signalToNoiseRatioDB: features.snr,
            periodicity: features.periodicity, spectralFlatness: features.flatness,
            strongestToneFraction: features.toneFraction
        )
    }

    /// Reduces a complete input channel to 160 zero-mean samples using interval box averages.
    ///
    /// Fractional box boundaries cover every source sample exactly once by weight, including
    /// unusual sample rates. The reduced rate is approximately 8kHz. Averaging attenuates but
    /// does not eliminate aliasing; this analysis helper is not an audio-output resampler.
    /// - Parameters:
    ///   - input: Complete interleaved analysis window, containing no partial channel frames.
    ///   - channel: Valid zero-based channel index to inspect without stereo summation.
    ///   - channels: Validated mono/stereo channel count.
    ///   - frameCount: Input frames in the window, at least 160 and at most 3,840.
    /// - Returns: Exactly 160 finite mean-subtracted samples with no retained input storage.
    private static func analysisSamples(
        _ input: [Float], channel: Int, channels: Int, frameCount: Int
    ) -> [Double] {
        var result = Array(repeating: 0.0, count: 160)
        for index in 0..<160 {
            // Integer sub-sample ticks avoid a rounded final endpoint stalling the loop.
            let end = (index + 1) * frameCount
            var position = index * frameCount
            var sum = 0.0
            while position < end {
                let source = position / 160
                let next = min(end, (source + 1) * 160)
                sum += Double(input[source * channels + channel]) * Double(next - position)
                position = next
            }
            result[index] = sum / Double(frameCount)
        }
        let mean = result.reduce(0, +) / 160
        for index in result.indices { result[index] -= mean }
        return result
    }

    /// Extracts speech features, classifies one channel and updates its adaptive history.
    /// - Parameters:
    ///   - samples: Exactly 160 finite mean-subtracted analysis samples.
    ///   - state: Exclusively owned channel history, mutated synchronously with bounded counts.
    ///   - warming: Whether to require nine rather than six decibels above background.
    ///   - backgroundFrozen: Whether preceding speech's hangover freezes background learning.
    /// - Returns: Current unextended evidence and finite diagnostic features. Pure silence,
    ///   DC, isolated tones and flat stationary noise fail independent structural criteria.
    private static func classify(
        _ samples: [Double], state: inout ChannelState, warming: Bool, backgroundFrozen: Bool
    ) -> ChannelDecision {
        let energy = samples.reduce(0) { $0 + $1 * $1 } / 160
        let spectrum = spectralPower(samples)
        let total = spectrum.reduce(0, +)
        let floor = max(1e-20, total * 1e-12)
        let flatness = min(1, exp(spectrum.reduce(0) { $0 + log(max(floor, $1)) } / 77)
            / max(floor, total / 77))
        var bands = Array(repeating: 0.0, count: 8)
        var strongest = 0.0
        for index in spectrum.indices {
            bands[min(7, (index + 2) / 10)] += spectrum[index]
            let start = max(0, index - 1)
            let end = min(spectrum.count - 1, index + 1)
            strongest = max(strongest, spectrum[start...end].reduce(0, +))
        }
        for index in bands.indices { bands[index] /= max(1e-20, total) }
        let toneFraction = min(1, strongest / max(1e-20, total))
        let occupiedBands = bands.filter { $0 > 0.025 }.count
        let flux = zip(bands, state.previousBands).reduce(0) { $0 + abs($1.0 - $1.1) } / 2
        let energyChange = abs(log10((energy + 1e-12) / (state.previousEnergy + 1e-12)))
        if flux < 0.035 && energyChange < 0.06 {
            state.stationaryFrames = min(25, state.stationaryFrames + 1)
        } else { state.stationaryFrames = 0 }
        let snr = 10 * log10((energy + 1e-12) / (state.noiseEnergy + 1e-12))
        let pitch = periodicity(samples)
        let audible = energy >= 0.000_004 && snr >= (warming ? 9 : 6)
        let voiced = audible && pitch >= 0.55 && flatness < 0.35
            && toneFraction < 0.75 && occupiedBands >= 3 && state.stationaryFrames < 25
        let consonant = audible && state.voicedContext > 0 && occupiedBands >= 3
            && toneFraction < 0.75 && flux > 0.15 && energyChange > 0.15
        let evidence = voiced || consonant
        if voiced { state.voicedContext = 3 }
        else { state.voicedContext = max(0, state.voicedContext - 1) }
        if !evidence && !backgroundFrozen {
            let observed = max(1e-8, energy)
            if !state.hasNoiseObservation {
                state.noiseEnergy = observed
                state.hasNoiseObservation = true
            } else {
                let weight = observed < state.noiseEnergy ? 0.2 : 0.05
                state.noiseEnergy += weight * (observed - state.noiseEnergy)
            }
        }
        state.previousBands = bands
        state.previousEnergy = energy
        return ChannelDecision(
            evidence: evidence, snr: snr, periodicity: pitch,
            flatness: flatness, toneFraction: toneFraction
        )
    }

    /// Computes Hann-windowed DFT-bin powers using bounded Goertzel recurrences.
    /// - Parameter samples: Exactly 160 finite real analysis samples; mean already removed.
    /// - Returns: Seventy-seven nonnegative finite powers for bins 2...78, approximately
    ///   100...3900Hz. Only this temporary fixed-size array is allocated; no state changes.
    private static func spectralPower(_ samples: [Double]) -> [Double] {
        let windowed = samples.enumerated().map {
            $0.element * (0.5 - 0.5 * cos(2 * Double.pi * Double($0.offset) / 159))
        }
        return (2...78).map { bin in
            let coefficient = 2 * cos(2 * Double.pi * Double(bin) / 160)
            var previous = 0.0
            var older = 0.0
            for sample in windowed {
                let current = sample + coefficient * previous - older
                older = previous
                previous = current
            }
            return max(0, previous * previous + older * older - coefficient * previous * older)
        }
    }

    /// Measures normalized positive autocorrelation over plausible voiced pitch periods.
    /// - Parameter samples: Exactly 160 finite zero-mean real samples.
    /// - Returns: Maximum correlation in `0...1` for lags 16...100, approximately 80...500Hz.
    ///   Zero-energy segments return zero; denominator floors prevent nonfinite values.
    private static func periodicity(_ samples: [Double]) -> Double {
        var maximum = 0.0
        for lag in 16...100 {
            var correlation = 0.0
            var firstEnergy = 0.0
            var secondEnergy = 0.0
            for index in lag..<160 {
                let first = samples[index]
                let second = samples[index - lag]
                correlation += first * second
                firstEnergy += first * first
                secondEnergy += second * second
            }
            maximum = max(maximum, correlation / max(1e-20, sqrt(firstEnergy * secondEnergy)))
        }
        return min(1, maximum)
    }
}
