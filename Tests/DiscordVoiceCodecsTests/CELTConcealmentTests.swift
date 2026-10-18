import Foundation
import Testing
@testable import DiscordVoiceCodecs

/// Deterministic loss synthesis, recovery and value ownership without packets, clocks or devices.
@Suite("CELT periodic and shaped-noise loss concealment")
struct CELTConcealmentTests {
    /// Compares complete independent float PCM plus exact loss paths, lags, envelopes and seeds.
    /// Fixtures cover mono/stereo, all four durations, changing postfilters, repeated losses,
    /// the 100-ms periodic/noise boundary, cold-start noise and recovery between losses.
    /// The fixed PCM allowance is 0.005% absolute plus 0.01% relative, accounting for
    /// the independently implemented float MDCT and its amplified LPC rounding.
    @Test func independentPeriodicNoiseAndRecoveryVectors() throws {
        let records = try JSONDecoder().decode([Record].self, from: Data(CELTConcealmentOracleFixtures.json.utf8))
        #expect(records.count == 14)
        var periodic = 0
        var noise = 0
        var compared = 0
        for record in records {
            var synthesis = try CELTSynthesis(channelCount: record.input.channels)
            var energies = Array(repeating: Float(0), count: 21 * record.input.channels)
            var seed: UInt32 = 0
            #expect(record.output.count == record.input.frames.count)
            for (frame, expected) in zip(record.input.frames, record.output) {
                let samples: [Float]
                if frame.lost {
                    let actual = try synthesis.conceal(frameSampleCount: 120 << frame.lm,
                        bandLogEnergies: energies,
                        backgroundLogEnergies: Array(repeating: -28, count: energies.count),
                        seed: seed, startBand: frame.start, endBand: frame.end, forceNoise: frame.force)
                    samples = actual.samples
                    energies = actual.bandLogEnergies
                    seed = actual.seed
                    #expect(actual.usesNoise == expected.noise)
                    #expect(actual.pitchPeriod == expected.pitch)
                    #expect(actual.lossDuration == expected.duration)
                    if actual.usesNoise { noise += 1 } else { periodic += 1 }
                } else {
                    let filter = frame.period == 0 ? nil : try CELTPostfilterParameters(
                        period: frame.period, gainIndex: frame.gainIndex, tapset: frame.tapset)
                    samples = try synthesis.synthesize(normalizedCoefficients: frame.coefficients,
                        bandLogEnergies: frame.energies, frameSampleCount: 120 << frame.lm,
                        startBand: frame.start, endBand: frame.end, isTransient: frame.transient,
                        postfilter: filter, silence: frame.silence)
                    energies = frame.energies
                    seed = frame.seed
                }
                #expect(energies == expected.energies)
                #expect(seed == expected.seed)
                let reference = try floatVector(expected.pcm)
                #expect(samples.count == reference.count)
                #expect(samples.count == (120 << frame.lm) * record.input.channels)
                for (actual, wanted) in zip(samples, reference) {
                    #expect(actual.isFinite && abs(actual - wanted) <= 0.00005 + 0.0001 * abs(wanted))
                }
                compared += samples.count
            }
        }
        #expect(periodic > 100 && noise > 10 && compared > 100_000)
    }

    /// Rejects every invalid duration, envelope dimension, nonfinite value and band boundary
    /// before touching pending predicted overlap, LPC, random or deemphasis state.
    @Test func malformedConcealmentIsAtomic() throws {
        var synthesis = try CELTSynthesis()
        let energies = Array(repeating: Float(3), count: 21)
        try prime(&synthesis)
        _ = try synthesis.conceal(frameSampleCount: 240, bandLogEnergies: energies,
            backgroundLogEnergies: energies, seed: 100)
        var reference = synthesis
        for size in [Int.min, -1, 0, 119, 121, 1920, Int.max] {
            #expect(throws: CELTSynthesisError.invalidFrameSize) {
                try synthesis.conceal(frameSampleCount: size, bandLogEnergies: energies,
                    backgroundLogEnergies: energies, seed: 0)
            }
        }
        for (start, end) in [(Int.min, 21), (-1, 21), (0, 0), (20, 20), (21, 21), (0, 22), (0, Int.max)] {
            #expect(throws: CELTSynthesisError.invalidBandRange) {
                try synthesis.conceal(frameSampleCount: 240, bandLogEnergies: energies,
                    backgroundLogEnergies: energies, seed: 0, startBand: start, endBand: end)
            }
        }
        for count in [0, 1, 20, 22, 42] {
            let wrong = Array(repeating: Float(0), count: count)
            #expect(throws: CELTSynthesisError.invalidBandEnergies) {
                try synthesis.conceal(frameSampleCount: 240, bandLogEnergies: wrong,
                    backgroundLogEnergies: energies, seed: 0)
            }
            #expect(throws: CELTSynthesisError.invalidBandEnergies) {
                try synthesis.conceal(frameSampleCount: 240, bandLogEnergies: energies,
                    backgroundLogEnergies: wrong, seed: 0)
            }
        }
        for invalid in [Float.nan, .infinity, -.infinity, -32_769, 32_769] {
            var wrong = energies
            wrong[20] = invalid
            #expect(throws: CELTSynthesisError.invalidBandEnergies) {
                try synthesis.conceal(frameSampleCount: 240, bandLogEnergies: wrong,
                    backgroundLogEnergies: energies, seed: 0)
            }
            #expect(throws: CELTSynthesisError.invalidBandEnergies) {
                try synthesis.conceal(frameSampleCount: 240, bandLogEnergies: energies,
                    backgroundLogEnergies: wrong, seed: 0)
            }
        }
        #expect(try synthesis.conceal(frameSampleCount: 120, bandLogEnergies: energies,
            backgroundLogEnergies: energies, seed: 1) == reference.conceal(frameSampleCount: 120,
                bandLogEnergies: energies, backgroundLogEnergies: energies, seed: 1))
        #expect(try receivedFrame(&synthesis) == receivedFrame(&reference))
    }

    /// Cold/hybrid/explicit-noise paths have exact deterministic seeds and decay only active
    /// bands by 1.5 then 0.5 log2 units, never below the caller-supplied background.
    @Test func noiseEnvelopeSeedAndInactiveBands() throws {
        var synthesis = try CELTSynthesis(channelCount: 2)
        var energies = Array(repeating: Float(3), count: 42)
        let background = Array(repeating: Float(1), count: 42)
        var seed: UInt32 = .max
        for iteration in 0..<10 {
            let result = try synthesis.conceal(frameSampleCount: 120, bandLogEnergies: energies,
                backgroundLogEnergies: background, seed: seed, startBand: 17, endBand: 19)
            #expect(result.usesNoise && result.pitchPeriod == 0)
            #expect(result.lossDuration == iteration + 1)
            #expect(result.samples.count == 240 && result.samples.allSatisfy(\.isFinite))
            let expected = iteration == 0 ? Float(1.5) : 1
            for channel in 0..<2 {
                for band in 0..<21 {
                    #expect(result.bandLogEnergies[channel * 21 + band] == ((17..<19).contains(band) ? expected : 3))
                }
            }
            var expectedSeed = seed
            let bins = CELTAllocationTables.bandEdges[19] - CELTAllocationTables.bandEdges[17]
            for _ in 0..<(2 * bins) { expectedSeed = expectedSeed &* 1_664_525 &+ 1_013_904_223 }
            #expect(result.seed == expectedSeed)
            energies = result.bandLogEnergies
            seed = result.seed
        }
    }

    /// The duration counter uses exact 2.5-ms units across changing frame sizes. Periodic
    /// losses stop only on a subsequent frame after 100ms and noise then persists until
    /// two consecutive received frames re-enable periodic extrapolation.
    @Test func periodicNoiseBoundaryAndTwoGoodFrameRecovery() throws {
        var synthesis = try CELTSynthesis()
        try prime(&synthesis)
        var energies = Array(repeating: Float(3), count: 21)
        let background = Array(repeating: Float(-28), count: 21)
        var duration = 0
        for size in [960, 480, 240, 120, 960, 480, 240, 120, 960, 960, 960] {
            let prior = duration
            let result = try synthesis.conceal(frameSampleCount: size, bandLogEnergies: energies,
                backgroundLogEnergies: background, seed: 0)
            duration += size / 120
            #expect(result.lossDuration == duration)
            #expect(result.usesNoise == (prior >= 40))
            #expect(result.usesNoise || (100...720).contains(result.pitchPeriod))
            energies = result.bandLogEnergies
        }
        _ = try receivedFrame(&synthesis)
        let afterOne = try synthesis.conceal(frameSampleCount: 120, bandLogEnergies: energies,
            backgroundLogEnergies: background, seed: 0)
        #expect(afterOne.usesNoise && afterOne.lossDuration == 1)
        _ = try receivedFrame(&synthesis)
        _ = try receivedFrame(&synthesis)
        let afterTwo = try synthesis.conceal(frameSampleCount: 120, bandLogEnergies: energies,
            backgroundLogEnergies: background, seed: 0)
        #expect(!afterTwo.usesNoise && afterTwo.lossDuration == 1)
    }

    /// Empty signal yields finite silent periodic prediction; copies fork all histories and
    /// repeated resets restore the exact cold-noise startup, even after pending folded overlap.
    @Test func zeroSignalCopyResetAndForcedNoise() throws {
        let energies = Array(repeating: Float(-28), count: 21)
        var synthesis = try CELTSynthesis()
        _ = try synthesis.synthesize(normalizedCoefficients: Array(repeating: 0, count: 120),
            bandLogEnergies: energies, frameSampleCount: 120)
        let silence = try synthesis.conceal(frameSampleCount: 960, bandLogEnergies: energies,
            backgroundLogEnergies: energies, seed: 0)
        #expect(!silence.usesNoise && silence.samples.allSatisfy { abs($0) < 1e-28 })
        var copy = synthesis
        let first = try synthesis.conceal(frameSampleCount: 240, bandLogEnergies: energies,
            backgroundLogEnergies: energies, seed: 55)
        #expect(first == (try copy.conceal(frameSampleCount: 240, bandLogEnergies: energies,
            backgroundLogEnergies: energies, seed: 55)))
        _ = try receivedFrame(&synthesis)
        let forced = try synthesis.conceal(frameSampleCount: 120, bandLogEnergies: energies,
            backgroundLogEnergies: energies, seed: 0, forceNoise: true)
        #expect(forced.usesNoise)
        synthesis.reset()
        synthesis.reset()
        var fresh = try CELTSynthesis()
        #expect(try synthesis.conceal(frameSampleCount: 480, bandLogEnergies: energies,
            backgroundLogEnergies: energies, seed: 1) == fresh.conceal(frameSampleCount: 480,
                bandLogEnergies: energies, backgroundLogEnergies: energies, seed: 1))
    }

    /// Produces three received frames with nonzero overlap and predictor history.
    /// - Parameter synthesis: Mono synthesis value to advance with deterministic spectra.
    /// - Throws: A synthesis error if the fixed valid fixture is no longer admitted.
    private func prime(_ synthesis: inout CELTSynthesis) throws {
        for _ in 0..<3 { _ = try receivedFrame(&synthesis) }
    }

    /// Synthesizes a valid deterministic mono frame to exercise recovery and normal history.
    /// - Parameter synthesis: Mono synthesis state, possibly containing a predicted overlap.
    /// - Returns: Exactly 240 normalized, unclipped finite output samples.
    /// - Throws: A synthesis error if the fixed valid fixture is no longer admitted.
    private func receivedFrame(_ synthesis: inout CELTSynthesis) throws -> [Float] {
        try synthesis.synthesize(normalizedCoefficients: (0..<240).map { Float(($0 * 37) % 101 - 50) / 512 },
            bandLogEnergies: Array(repeating: 3, count: 21), frameSampleCount: 240)
    }

    /// Decodes little-endian independent float32 PCM without alignment assumptions.
    /// - Parameter encoded: Base64 containing a complete vector of four-byte IEEE-754 floats.
    /// - Returns: Every reference float in source order.
    /// - Throws: A Swift Testing requirement failure for missing or malformed fixture bytes.
    private func floatVector(_ encoded: String) throws -> [Float] {
        let data = try #require(Data(base64Encoded: encoded))
        #expect(data.count.isMultiple(of: 4))
        return stride(from: 0, to: data.count, by: 4).map { offset in
            let bits = UInt32(data[offset]) | UInt32(data[offset + 1]) << 8
                | UInt32(data[offset + 2]) << 16 | UInt32(data[offset + 3]) << 24
            return Float(bitPattern: bits)
        }
    }

    private struct Record: Decodable {
        let input: Input
        let output: [Output]
    }
    private struct Input: Decodable {
        let channels: Int
        let frames: [Frame]
    }
    private struct Frame: Decodable {
        let lm: Int, start: Int, end: Int, period: Int, gainIndex: Int, tapset: Int
        let transient: Bool, silence: Bool, lost: Bool, force: Bool
        let seed: UInt32
        let coefficients: [Float], energies: [Float]
    }
    private struct Output: Decodable {
        let pcm: String
        let energies: [Float]
        let seed: UInt32
        let duration: Int, pitch: Int
        let noise: Bool
    }
}
