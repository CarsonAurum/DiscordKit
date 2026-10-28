// File: Tests/DiscordMediaTests/PCMSpeechActivityDetectorTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import Foundation
import Testing
@testable import DiscordMedia

@Suite("Bounded statistical PCM speech activity")
struct PCMSpeechActivityDetectorTests {
    /// Rejects hostile hangover capacities before constructing detector state.
    /// - Parameter count: An invalid negative, overflowing or greater-than-50 frame count.
    @Test(arguments: [Int.min, -1, 51, Int.max])
    func rejectsInvalidHangover(count: Int) throws {
        let format = try PCMFormat()
        #expect(throws: MediaError.invalidCapacity) {
            try PCMSpeechActivityDetector(format: format, hangoverFrameCount: count)
        }
    }

    /// Confirms supported PCM rate extremes and fractional box boundaries produce useful
    /// synthetic voiced evidence; diagnostics stay finite and dimensionless ratios bounded.
    /// These fixtures exercise implementation behavior, not human-speech accuracy.
    /// - Parameters:
    ///   - rate: Valid rate, including awkward rates not divisible by 50 or 8,000.
    ///   - channelCount: One or two identical input channels.
    @Test(arguments: [8_000, 8_001, 16_000, 44_101, 48_000, 192_000], [1, 2])
    func supportedRatesAndDiagnostics(rate: Int, channelCount: Int) throws {
        let format = try PCMFormat(sampleRate: rate, channelCount: channelCount)
        var detector = try PCMSpeechActivityDetector(format: format)
        #expect(detector.format == format)
        #expect(detector.analysisFrameCount == rate / 50)
        #expect(detector.hangoverFrameCount == 5)
        #expect(detector.bufferedFrameCount == 0)
        for index in 0..<8 {
            let decision = try #require(detector.process(speech(format: format, index: index)).first)
            #expect(decision.hasSpeechEvidence)
            #expect(decision.isSpeech)
            #expect(decision.isWarmingUp == (index < 5))
            #expect(decision.channelIndex == 0)
            #expect(decision.signalToNoiseRatioDB.isFinite)
            #expect(decision.signalToNoiseRatioDB > 6)
            #expect((0.55...1).contains(decision.periodicity))
            #expect((0...0.35).contains(decision.spectralFlatness))
            #expect((0...0.75).contains(decision.strongestToneFraction))
            #expect(detector.bufferedFrameCount == 0)
        }
    }

    /// Shows empty chunks and one-frame fragments do not change frame boundaries or adaptive
    /// decisions. All chunk patterns deliver identical audio and preserve the unclassified tail.
    @Test func chunkingIsInvariantAndPartialFramesWait() throws {
        let format = try PCMFormat(sampleRate: 44_101, channelCount: 2)
        let frameCount = format.sampleRate / 50
        let complete = try (0..<5).flatMap { try speech(format: format, index: $0).samples }
        let tail = Array(try speech(format: format, index: 5).samples.prefix(frameCount))
        let samples = complete + tail
        var reference = try PCMSpeechActivityDetector(format: format)
        let expected = try reference.process(PCMBuffer(format: format, samples: samples))
        #expect(expected.count == 5)
        #expect(reference.bufferedFrameCount == frameCount / 2)

        for pattern in [[1], [1, 3, 79, 501], [frameCount - 1, 2, frameCount]] {
            var detector = try PCMSpeechActivityDetector(format: format)
            var actual: [PCMSpeechActivityDecision] = []
            var offset = 0
            var step = 0
            while offset < samples.count {
                #expect(try detector.process(PCMBuffer(format: format, samples: [])).isEmpty)
                let end = min(samples.count, offset + pattern[step % pattern.count] * 2)
                actual += try detector.process(PCMBuffer(format: format, samples: Array(samples[offset..<end])))
                #expect(detector.bufferedFrameCount < frameCount)
                offset = end
                step += 1
            }
            #expect(actual == expected)
            #expect(detector.bufferedFrameCount == reference.bufferedFrameCount)
        }
    }

    /// Verifies rejection atomicity while a partial stereo frame and prior hangover exist.
    /// Empty wrong-format buffers must fail before they can affect framing or learned history.
    @Test func formatMismatchIsAtomic() throws {
        let format = try PCMFormat(sampleRate: 48_000, channelCount: 2)
        let voiced = try speech(format: format, index: 0)
        var detector = try PCMSpeechActivityDetector(format: format)
        _ = try detector.process(voiced)
        let split = voiced.samples.count / 2
        #expect(try detector.process(PCMBuffer(format: format, samples: Array(voiced.samples[..<split]))).isEmpty)
        var reference = detector
        for wrong in [
            try PCMFormat(sampleRate: 48_001, channelCount: 2),
            try PCMFormat(sampleRate: 48_000, channelCount: 1)
        ] {
            #expect(throws: MediaError.incompatibleBuffers) {
                try detector.process(PCMBuffer(format: wrong, samples: []))
            }
            #expect(throws: MediaError.incompatibleBuffers) {
                try detector.process(PCMBuffer(format: wrong, samples: Array(repeating: 0, count: wrong.channelCount)))
            }
        }
        let continuation = try PCMBuffer(format: format, samples: Array(voiced.samples[split...]))
        #expect(try detector.process(continuation) == reference.process(continuation))
    }

    /// Rejects silence, constant DC, integer/noninteger-bin tones and isolated impulses at cold
    /// start and after adaptation, even when their RMS passes a separate energy gate.
    /// - Parameter kind: Deterministic non-speech fixture variant, from zero through four.
    @Test(arguments: 0..<5)
    func rejectsNonSpeechStructure(kind: Int) throws {
        let format = try PCMFormat(sampleRate: 8_000, channelCount: 1)
        let samples = (0..<160).map { index -> Float in
            switch kind {
            case 0: return 0
            case 1: return 0.5
            case 2: return Float(0.5 * sin(2 * Double.pi * 1_000 * Double(index) / 8_000))
            case 3: return Float(0.5 * sin(2 * Double.pi * 1_234 * Double(index) / 8_000))
            default: return index == 50 ? 1 : 0
            }
        }
        let buffer = try PCMBuffer(format: format, samples: samples)
        #expect(try buffer.passesEnergyGate(threshold: 0.01) == (kind != 0))
        var detector = try PCMSpeechActivityDetector(format: format)
        for _ in 0..<40 {
            let result = try #require(detector.process(buffer).first)
            #expect(!result.hasSpeechEvidence)
            #expect(!result.isSpeech)
            #expect(result.signalToNoiseRatioDB.isFinite)
            #expect(result.periodicity.isFinite)
            #expect((0...1).contains(result.spectralFlatness))
            #expect((0...1).contains(result.strongestToneFraction))
            if kind == 2 || kind == 3 { #expect(result.strongestToneFraction > 0.75) }
        }
    }

    /// Tracks quiet, loud and falling stationary broadband noise without classifying its
    /// amplitude steps as speech. The posterior SNR must approach zero at each new background.
    @Test func stationaryNoiseAdaptsAcrossLevelChanges() throws {
        let format = try PCMFormat(sampleRate: 8_000, channelCount: 1)
        var detector = try PCMSpeechActivityDetector(format: format)
        var seed: UInt64 = 0x96c7_f199_ac40_d677
        for amplitude: Float in [0.004, 0.2, 0.01] {
            var ending: [Double] = []
            for index in 0..<100 {
                let input = try noise(format: format, amplitude: amplitude, seed: &seed)
                let result = try #require(detector.process(input).first)
                #expect(!result.hasSpeechEvidence)
                #expect(!result.isSpeech)
                #expect(result.isWarmingUp == (amplitude == 0.004 && index < 5))
                if index >= 90 { ending.append(result.signalToNoiseRatioDB) }
            }
            #expect(abs(ending.reduce(0, +) / Double(ending.count)) < 2)
        }
    }

    /// Detects a changing harmonic speech-like envelope after noise calibration and freezes
    /// background during those voiced frames. Quiet fixtures below the absolute floor fail.
    @Test func voicedOnsetAfterBackgroundAndAbsoluteFloor() throws {
        let format = try PCMFormat(sampleRate: 16_000, channelCount: 1)
        var detector = try PCMSpeechActivityDetector(format: format)
        var seed: UInt64 = 0x7aac_4cf1_aa77_4444
        for _ in 0..<15 {
            _ = try detector.process(noise(format: format, amplitude: 0.01, seed: &seed))
        }
        for index in 0..<20 {
            let result = try #require(detector.process(speech(format: format, index: index)).first)
            #expect(result.hasSpeechEvidence)
            #expect(result.isSpeech)
            #expect(!result.isWarmingUp)
            #expect(result.signalToNoiseRatioDB > 20)
        }
        detector.reset()
        for index in 0..<10 {
            let result = try #require(detector.process(speech(format: format, index: index, gain: 0.001)).first)
            #expect(!result.isSpeech)
        }
    }

    /// Suppresses unchanging harmonic background after the documented 25-frame stationarity
    /// horizon, including the eventual expiration of hangover and background adaptation.
    @Test func stationaryHarmonicBackgroundEventuallyStops() throws {
        let format = try PCMFormat(sampleRate: 8_000, channelCount: 1)
        let stationary = try speech(format: format, index: 0)
        var detector = try PCMSpeechActivityDetector(format: format)
        let results = try (0..<80).flatMap { _ in try detector.process(stationary) }
        #expect(results.first?.hasSpeechEvidence == true)
        #expect(results.suffix(40).allSatisfy { !$0.hasSpeechEvidence && !$0.isSpeech })
        #expect(abs(try #require(results.last).signalToNoiseRatioDB) < 2)
    }

    /// Requires recent voiced context for a synthetic broadband plosive-like onset. An
    /// isolated burst fails structural voicing; the same burst immediately after voicing
    /// supplies consonant evidence, without treating every subsequent noise frame as speech.
    @Test func changingConsonantBurstNeedsVoicedContext() throws {
        let format = try PCMFormat(sampleRate: 8_000, channelCount: 1)
        var seed: UInt64 = 0x96c7_f199_ac40_d677
        let burst = try noise(format: format, amplitude: 0.8, seed: &seed)
        var cold = try PCMSpeechActivityDetector(format: format)
        #expect(try cold.process(burst).first?.hasSpeechEvidence == false)
        var contextual = try PCMSpeechActivityDetector(format: format)
        _ = try contextual.process(speech(format: format, index: 0))
        let result = try #require(contextual.process(burst).first)
        #expect(result.hasSpeechEvidence)
        #expect(result.periodicity < 0.55)
        let results = try (0..<12).flatMap { _ in try contextual.process(burst) }
        #expect(results.suffix(3).allSatisfy { !$0.hasSpeechEvidence && !$0.isSpeech })
    }

    /// Counts exact complete-frame hangover at zero, ordinary and maximum configurations.
    /// No-evidence silence is explicitly distinguished from current speech evidence.
    /// - Parameter count: Valid configured hangover frame count, including both boundaries.
    @Test(arguments: [0, 1, 5, 50])
    func hangoverExpiresExactly(count: Int) throws {
        let format = try PCMFormat(sampleRate: 8_000, channelCount: 1)
        var detector = try PCMSpeechActivityDetector(format: format, hangoverFrameCount: count)
        #expect(try detector.process(speech(format: format, index: 0)).first?.hasSpeechEvidence == true)
        let silence = try PCMBuffer(format: format, samples: Array(repeating: 0, count: 160))
        for index in 0..<(count + 2) {
            let decision = try #require(detector.process(silence).first)
            #expect(!decision.hasSpeechEvidence)
            #expect(decision.isSpeech == (index < count))
        }
    }

    /// Classifies each channel independently: antiphase speech cannot cancel, and either
    /// single populated channel supplies evidence and its own channel-index diagnostics.
    /// - Parameter layout: Zero for antiphase, one for left-only, two for right-only speech.
    @Test(arguments: [0, 1, 2])
    func stereoDoesNotCancelOrDiluteSpeech(layout: Int) throws {
        let mono = try PCMFormat(sampleRate: 48_000, channelCount: 1)
        let stereo = try PCMFormat(sampleRate: 48_000, channelCount: 2)
        let source = try speech(format: mono, index: 2).samples
        let samples = source.flatMap { sample -> [Float] in
            switch layout {
            case 0: return [sample, -sample]
            case 1: return [sample, 0]
            default: return [0, sample]
            }
        }
        var detector = try PCMSpeechActivityDetector(format: stereo)
        let result = try #require(detector.process(PCMBuffer(format: stereo, samples: samples)).first)
        #expect(result.hasSpeechEvidence)
        #expect(result.isSpeech)
        #expect(result.channelIndex == (layout == 2 ? 1 : 0))
    }

    /// Reset discards partial samples, warmup, background and hangover. Value copies preserve
    /// independent audio and learned state, so resetting one does not reset a copied detector.
    @Test func resetAndValueCopiesAreIndependent() throws {
        let format = try PCMFormat(sampleRate: 8_000, channelCount: 1)
        let voiced = try speech(format: format, index: 1)
        let partial = try PCMBuffer(format: format, samples: Array(voiced.samples.prefix(57)))
        let silence = try PCMBuffer(format: format, samples: Array(repeating: 0, count: 160))
        var detector = try PCMSpeechActivityDetector(format: format)
        detector.reset()
        #expect(try detector.process(PCMBuffer(format: format, samples: [])).isEmpty)
        _ = try detector.process(voiced)
        #expect(try detector.process(partial).isEmpty)
        #expect(detector.bufferedFrameCount == 57)
        var copy = detector
        detector.reset()
        detector.reset()
        #expect(detector.bufferedFrameCount == 0)
        var fresh = try PCMSpeechActivityDetector(format: format)
        #expect(try detector.process(silence) == fresh.process(silence))
        #expect(copy.bufferedFrameCount == 57)
        let remainder = try PCMBuffer(format: format, samples: Array(repeating: 0, count: 103))
        #expect(try copy.process(remainder).first?.isSpeech == true)
        #expect(copy.bufferedFrameCount == 0)
        #expect(try detector.process(voiced) == fresh.process(voiced))
    }

    /// Checks long awkward-rate framing and the per-call seven-decision bound with repeated
    /// maximum blocks. Retained audio always stays strictly below one complete analysis frame.
    @Test func boundedFramingOverLongInput() throws {
        let format = try PCMFormat(sampleRate: 8_049, channelCount: 2)
        var detector = try PCMSpeechActivityDetector(format: format)
        var inputFrames = 0
        var decisionCount = 0
        for index in 0..<300 {
            let count = index % 3 == 0 ? format.sampleRate * 120 / 1_000 : index % 31
            let buffer = try PCMBuffer(format: format, samples: Array(repeating: 0.3, count: count * 2))
            let decisions = try detector.process(buffer)
            #expect(decisions.count <= 7)
            #expect(decisions.allSatisfy { !$0.isSpeech })
            inputFrames += count
            decisionCount += decisions.count
            #expect(decisionCount == inputFrames / detector.analysisFrameCount)
            #expect(detector.bufferedFrameCount == inputFrames % detector.analysisFrameCount)
        }
    }

    /// Creates a deterministic voiced-like harmonic fixture with changing pitch and envelope.
    /// This is a structural DSP fixture; it is not a recorded or trained human speech corpus.
    /// - Parameters:
    ///   - format: Required rate/layout; each channel receives the same normalized waveform.
    ///   - index: Nonnegative synthetic frame index controlling pitch and amplitude changes.
    ///   - gain: Nonnegative amplitude multiplier, default one; tests keep peaks within unity.
    /// - Returns: Exactly one analysis frame with five harmonics spanning several speech bands.
    /// - Throws: Propagates `PCMBuffer` validation if a test violates amplitude/layout bounds.
    private func speech(format: PCMFormat, index: Int, gain: Float = 1) throws -> PCMBuffer {
        let frequency = 150.0 + Double(index % 6) * 9
        let envelope = 0.75 + 0.25 * sin(Double(index) * 0.7)
        let harmonics = [1, 3, 7, 11, 17]
        let weights = [0.7, 1.0, 0.8, 0.6, 0.4]
        let samples = (0..<(format.sampleRate / 50)).flatMap { frame -> [Float] in
            let time = Double(frame) / Double(format.sampleRate)
            var value = 0.0
            for (harmonic, weight) in zip(harmonics, weights) {
                value += sin(2 * Double.pi * frequency * Double(harmonic) * time) * weight
            }
            return Array(repeating: Float(0.2 * envelope * value) * gain, count: format.channelCount)
        }
        return try PCMBuffer(format: format, samples: samples)
    }

    /// Produces reproducible uniform broadband noise without wall-clock or shared RNG state.
    /// - Parameters:
    ///   - format: Required PCM layout/rate; exactly one complete analysis frame is produced.
    ///   - amplitude: Normalized peak bound in `0...1`, supplied by these deterministic tests.
    ///   - seed: Nonzero xorshift state, exclusively mutated once per interleaved sample.
    /// - Returns: One dense normalized input block; channels have independent noise samples.
    /// - Throws: Propagates `PCMBuffer` validation for invalid test-supplied bounds.
    private func noise(format: PCMFormat, amplitude: Float, seed: inout UInt64) throws -> PCMBuffer {
        let samples = (0..<(format.sampleRate / 50 * format.channelCount)).map { _ -> Float in
            seed ^= seed << 13
            seed ^= seed >> 7
            seed ^= seed << 17
            return Float(Double(seed >> 11) / Double(UInt64(1) << 53) * 2 - 1) * amplitude
        }
        return try PCMBuffer(format: format, samples: samples)
    }
}
