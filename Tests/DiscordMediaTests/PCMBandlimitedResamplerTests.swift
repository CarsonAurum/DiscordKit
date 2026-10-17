import Foundation
import Testing
@testable import DiscordMedia

@Suite("Owned bounded bandlimited PCM conversion")
struct PCMBandlimitedResamplerTests {
    /// Rejects unsupported destination rates without coercion, including hostile integer extremes.
    /// - Parameter rate: A rate outside PCM's inclusive supported range.
    @Test(arguments: [7_999, 192_001, Int.min, Int.max])
    func invalidDestination(rate: Int) throws {
        #expect(throws: MediaError.invalidFormat) {
            try PCMBandlimitedResampler(inputFormat: PCMFormat(), outputSampleRate: rate)
        }
    }

    /// Proves identity conversion preserves exact samples and has no filter delay or storage.
    /// - Parameter channels: Both supported interleaved layouts, with distinct channel content.
    @Test(arguments: [1, 2])
    func equalRatesAreExactIdentity(channels: Int) throws {
        let format = try PCMFormat(sampleRate: 44_101, channelCount: channels)
        var converter = try PCMBandlimitedResampler(inputFormat: format, outputSampleRate: 44_101)
        let block = try PCMBuffer(format: format, samples: fixture(frames: 113, channels: channels))
        #expect(converter.inputFormat == format)
        #expect(converter.outputFormat == format)
        #expect(converter.lookaheadFrames == 0)
        #expect(converter.processingDelay == (try MediaTime(value: 0, timescale: 44_101)))
        #expect(converter.maximumRetainedFrameCount == 0)
        #expect(try converter.process(block) == [block])
        #expect(converter.retainedFrameCount == 0)
        #expect(converter.accountedRetainedBytes == 0)
        #expect(try converter.finish().isEmpty)
        #expect(converter.isFinished)
    }

    /// Verifies exact chunk-independent samples/counts for awkward rational and extreme ratios.
    /// Single-frame chunks, empty blocks and channel-distinct data exercise history compaction,
    /// rational carry, endpoint extension and independent channel filtering.
    /// - Parameters:
    ///   - sourceRate: Source frames per second, including storage-boundary extremes.
    ///   - destinationRate: Destination frames per second, including relatively prime rates.
    ///   - channels: Mono or stereo interleaving.
    @Test(arguments: [
        (8_000, 192_000, 1), (8_000, 192_000, 2),
        (192_000, 8_000, 1), (192_000, 8_000, 2),
        (44_101, 48_000, 1), (44_101, 48_000, 2),
        (48_000, 44_101, 1), (48_000, 44_101, 2)
    ])
    func chunkBoundariesPreservePhase(sourceRate: Int, destinationRate: Int, channels: Int) throws {
        let format = try PCMFormat(sampleRate: sourceRate, channelCount: channels)
        let samples = fixture(frames: 913, channels: channels)
        let expected = try convert(samples: samples, format: format, destinationRate: destinationRate, pattern: [913])
        #expect(expected.count == 913 * destinationRate / sourceRate * channels)
        for pattern in [[1], [1, 2, 3, 5, 8, 13, 21], [127, 1, 311]] {
            let actual = try convert(samples: samples, format: format, destinationRate: destinationRate, pattern: pattern)
            #expect(actual == expected)
        }
    }

    /// Checks the centered FIR against an independently indexed full-signal convolution.
    /// The reference has no streaming history or admission state, so a phase or retained-index
    /// error remains observable even when multiple streaming chunk patterns agree.
    @Test func matchesFullSignalConvolution() throws {
        let format = try PCMFormat(sampleRate: 44_100, channelCount: 2)
        let samples = fixture(frames: 257, channels: 2)
        let output = try convert(samples: samples, format: format, destinationRate: 48_000, pattern: [1, 97, 3])
        let cutoff = 0.9
        let radius = Int(ceil(32 / cutoff))
        for frame in 0..<(257 * 48_000 / 44_100) {
            let position = Double(frame * 44_100) / 48_000
            var coefficients = 0.0
            var values = [0.0, 0.0]
            // The full finite sequence is extended by both endpoints rather than compacted.
            for inputFrame in -radius..<(257 + radius) {
                let distance = Double(inputFrame) - position
                guard abs(distance) < Double(radius) else { continue }
                let x = Double.pi * cutoff * distance
                let sinc = abs(x) < 1e-12 ? 1 : sin(x) / x
                let angle = Double.pi * distance / Double(radius)
                let weight = cutoff * sinc * (0.42 + 0.5 * cos(angle) + 0.08 * cos(2 * angle))
                coefficients += weight
                let bounded = max(0, min(256, inputFrame))
                for channel in 0..<2 { values[channel] += Double(samples[bounded * 2 + channel]) * weight }
            }
            for channel in 0..<2 {
                let expected = Float(max(-1, min(1, values[channel] / coefficients)))
                #expect(abs(output[frame * 2 + channel] - expected) < 0.000_001)
            }
        }
    }

    /// Verifies documented lookahead and finish timing without shifting the output origin.
    /// A matching empty block cannot flush the boundary, while explicit finish releases the
    /// exact duration tail and clears all retained audio.
    @Test func delayAndEndpointExtensionAreExplicit() throws {
        let format = try PCMFormat(sampleRate: 8_000, channelCount: 2)
        var converter = try PCMBandlimitedResampler(inputFormat: format, outputSampleRate: 48_000)
        let radius = converter.lookaheadFrames
        #expect(radius == 36)
        #expect(converter.processingDelay == (try MediaTime(value: 36, timescale: 8_000)))
        let first = try PCMBuffer(format: format, samples: Array(repeating: [Float(0.25), Float(-0.5)], count: radius).flatMap { $0 })
        #expect(try converter.process(first).isEmpty)
        #expect(try converter.process(PCMBuffer(format: format, samples: [])).isEmpty)
        let ready = try converter.process(PCMBuffer(format: format, samples: [0.25, -0.5]))
        #expect(ready.flatMap(\.samples) == Array(repeating: [Float(0.25), Float(-0.5)], count: 6).flatMap { $0 })
        let tail = try converter.finish().flatMap(\.samples)
        #expect(tail == Array(repeating: [Float(0.25), Float(-0.5)], count: radius * 6).flatMap { $0 })
        #expect(converter.isFinished)
        #expect(converter.retainedFrameCount == 0)
        #expect(converter.accountedRetainedBytes == 0)
        #expect(try converter.finish().isEmpty)
    }

    /// Exercises one-frame startup and end extension at the maximum up/down ratio.
    /// A stream too short to earn one destination frame must remain empty after finishing.
    /// - Parameter channels: Mono or stereo, with independent constant channel levels.
    @Test(arguments: [1, 2])
    func shortestStreams(channels: Int) throws {
        let frame: [Float] = channels == 1 ? [0.25] : [0.25, -0.5]
        let low = try PCMFormat(sampleRate: 8_000, channelCount: channels)
        var up = try PCMBandlimitedResampler(inputFormat: low, outputSampleRate: 192_000)
        #expect(try up.process(PCMBuffer(format: low, samples: frame)).isEmpty)
        #expect(try up.finish().flatMap(\.samples) == Array(repeating: frame, count: 24).flatMap { $0 })
        let high = try PCMFormat(sampleRate: 192_000, channelCount: channels)
        var down = try PCMBandlimitedResampler(inputFormat: high, outputSampleRate: 8_000)
        #expect(try down.process(PCMBuffer(format: high, samples: frame)).isEmpty)
        #expect(try down.finish().isEmpty)
        #expect(down.retainedFrameCount == 0)
    }

    /// Measures passband preservation and stopband alias rejection away from the finite
    /// transition band using deterministic synthesized tones and independent RMS measurement.
    /// Discarding 64 output frames at either edge excludes constant-extension transients.
    /// - Parameters:
    ///   - sourceRate: Representative source rate, including the maximum downsampling ratio.
    ///   - destinationRate: Representative lower destination rate.
    ///   - passFrequency: Interior passband tone in hertz, compared with its exact new-clock value.
    ///   - stopFrequency: Tone above destination Nyquist that would alias under simple decimation.
    @Test(arguments: [
        (48_000, 16_000, 1_000.0, 12_000.0),
        (44_100, 16_000, 1_000.0, 12_000.0),
        (48_000, 44_100, 2_000.0, 23_000.0),
        (192_000, 8_000, 500.0, 19_000.0)
    ])
    func downsamplingRejectsAliasing(
        sourceRate: Int, destinationRate: Int, passFrequency: Double, stopFrequency: Double
    ) throws {
        let format = try PCMFormat(sampleRate: sourceRate, channelCount: 1)
        let frames = sourceRate * 100 / 1_000
        let passInput = tone(frames: frames, rate: sourceRate, frequency: passFrequency)
        let passOutput = try convert(samples: passInput, format: format, destinationRate: destinationRate, pattern: [1, 127, 311])
        var maximumError = 0.0
        for frame in 64..<(passOutput.count - 64) {
            let expected = 0.2 * sin(2 * Double.pi * passFrequency * Double(frame) / Double(destinationRate))
            maximumError = max(maximumError, abs(Double(passOutput[frame]) - expected))
        }
        #expect(maximumError < 0.000_2)
        let stopInput = tone(frames: frames, rate: sourceRate, frequency: stopFrequency)
        let stopOutput = try convert(samples: stopInput, format: format, destinationRate: destinationRate, pattern: [311, 1, 127])
        let interior = Array(stopOutput.dropFirst(64).dropLast(64))
        #expect(rms(interior) < 0.000_1)
        // Unfiltered conversion retains substantial aliased energy for each fixture.
        let raw = (64..<(stopOutput.count - 64)).map { frame in
            stopInput[frame * sourceRate / destinationRate]
        }
        #expect(rms(raw) > 0.05)
    }

    /// Checks interpolation-image suppression on a 6x upsampled low-frequency sinusoid.
    /// Projection onto 7kHz independently measures the first 8kHz-source spectral image.
    @Test func upsamplingSuppressesImages() throws {
        let format = try PCMFormat(sampleRate: 8_000, channelCount: 1)
        let input = tone(frames: 800, rate: 8_000, frequency: 1_000)
        let output = try convert(samples: input, format: format, destinationRate: 48_000, pattern: [13, 127, 1])
        let range = 300..<4_500
        var fundamental = 0.0
        var image = 0.0
        for frame in range {
            let sample = Double(output[frame])
            fundamental += sample * sin(2 * Double.pi * 1_000 * Double(frame) / 48_000)
            image += sample * sin(2 * Double.pi * 7_000 * Double(frame) / 48_000)
        }
        #expect(abs(2 * fundamental / Double(range.count) - 0.2) < 0.000_2)
        #expect(abs(2 * image / Double(range.count)) < 0.000_1)
    }

    /// Verifies fixed storage and exact counts through thousands of tiny awkward-rate calls.
    /// Both stereo channels have different DC values, exposing channel coupling while phase
    /// wraps repeatedly. The checked sample accounting excludes allocator/RSS claims.
    @Test func longStreamKeepsBoundedHistoryAndExactCounts() throws {
        let format = try PCMFormat(sampleRate: 44_101, channelCount: 2)
        var converter = try PCMBandlimitedResampler(inputFormat: format, outputSampleRate: 48_000)
        var inputFrames = 0
        var outputFrames = 0
        for index in 0..<2_048 {
            let frames = index % 17 + 1
            let samples = Array(repeating: [Float(0.25), Float(-0.5)], count: frames).flatMap { $0 }
            let output = try converter.process(PCMBuffer(format: format, samples: samples))
            inputFrames += frames
            outputFrames += output.reduce(0) { $0 + $1.frameCount }
            #expect(converter.retainedFrameCount <= converter.maximumRetainedFrameCount)
            #expect(converter.accountedRetainedBytes == converter.retainedFrameCount * 2 * MemoryLayout<Float>.stride)
            #expect(outputFrames <= inputFrames * 48_000 / 44_101)
            #expect(output.flatMap(\.samples) == Array(repeating: [Float(0.25), Float(-0.5)], count: output.reduce(0) { $0 + $1.frameCount }).flatMap { $0 })
        }
        outputFrames += try converter.finish().reduce(0) { $0 + $1.frameCount }
        #expect(outputFrames == inputFrames * 48_000 / 44_101)
        #expect(converter.retainedFrameCount == 0)
    }

    /// Exercises maximal input blocks, rational carry and normalized overshoot saturation.
    /// Output always respects PCM's 120ms cap, including finish; abrupt full-scale transitions
    /// cannot produce NaN, infinity or samples outside the public PCM storage contract.
    @Test func maximumBlocksAndRingingStayWithinBounds() throws {
        let format = try PCMFormat(sampleRate: 8_000, channelCount: 2)
        var converter = try PCMBandlimitedResampler(inputFormat: format, outputSampleRate: 8_001)
        var all: [PCMBuffer] = []
        for index in 0..<20 {
            let samples = (0..<960).flatMap { frame -> [Float] in
                let value: Float = (frame + index * 960) % 100 < 50 ? -1 : 1
                return [value, -value]
            }
            all.append(contentsOf: try converter.process(PCMBuffer(format: format, samples: samples)))
            #expect(converter.retainedFrameCount <= converter.maximumRetainedFrameCount)
        }
        all.append(contentsOf: try converter.finish())
        #expect(all.reduce(0) { $0 + $1.frameCount } == 20 * 960 * 8_001 / 8_000)
        #expect(all.allSatisfy { $0.frameCount > 0 && $0.frameCount <= 960 })
        #expect(all.flatMap(\.samples).allSatisfy { $0.isFinite && (-1...1).contains($0) })
        #expect(all.flatMap(\.samples).contains(1))
        #expect(all.flatMap(\.samples).contains(-1))
        for block in all {
            for frame in 0..<block.frameCount { #expect(block.samples[frame * 2] == -block.samples[frame * 2 + 1]) }
        }
    }

    /// Ensures format errors leave pending filter history and rational phase unchanged.
    /// Copying the converter provides an independently mutated comparison; the original input
    /// array can also be modified without changing retained or already returned audio.
    @Test func rejectionAndCopiesPreserveOwnership() throws {
        let format = try PCMFormat(sampleRate: 24_000, channelCount: 2)
        var samples = fixture(frames: 79, channels: 2)
        let block = try PCMBuffer(format: format, samples: samples)
        var converter = try PCMBandlimitedResampler(inputFormat: format, outputSampleRate: 48_000)
        let initial = try converter.process(block)
        var untouched = converter
        samples = Array(repeating: 1, count: samples.count)
        #expect(block.samples != samples)
        for wrong in [
            try PCMFormat(sampleRate: 24_001, channelCount: 2),
            try PCMFormat(sampleRate: 24_000, channelCount: 1)
        ] {
            #expect(throws: MediaError.incompatibleBuffers) {
                try converter.process(PCMBuffer(format: wrong, samples: []))
            }
            #expect(throws: MediaError.incompatibleBuffers) {
                try converter.process(PCMBuffer(format: wrong, samples: Array(repeating: 0, count: wrong.channelCount)))
            }
        }
        let next = try PCMBuffer(format: format, samples: fixture(frames: 101, channels: 2))
        #expect(try converter.process(next) == untouched.process(next))
        #expect(try converter.finish() == untouched.finish())
        #expect(initial.flatMap(\.samples).contains { $0 != 1 })
        untouched.reset()
        #expect(converter.isFinished)
        #expect(!untouched.isFinished)
    }

    /// Covers empty/idempotent finish, closed-check precedence and resetting pending audio.
    /// Reset preserves formats while intentionally discarding old unflushed filter support.
    @Test func finishAndResetLifecycle() throws {
        let format = try PCMFormat(sampleRate: 16_000, channelCount: 1)
        let empty = try PCMBuffer(format: format, samples: [])
        let block = try PCMBuffer(format: format, samples: [0.25, -0.5, 0.75])
        var converter = try PCMBandlimitedResampler(inputFormat: format, outputSampleRate: 48_000)
        converter.reset()
        #expect(try converter.process(empty).isEmpty)
        #expect(try converter.finish().isEmpty)
        #expect(try converter.finish().isEmpty)
        #expect(throws: MediaError.closed) { try converter.process(empty) }
        #expect(throws: MediaError.closed) { try converter.process(block) }
        #expect(throws: MediaError.closed) { try converter.process(PCMBuffer(format: PCMFormat(), samples: [])) }
        converter.reset()
        #expect(!converter.isFinished)
        #expect(try converter.process(block).isEmpty)
        #expect(converter.retainedFrameCount == 3)
        converter.reset()
        #expect(converter.retainedFrameCount == 0)
        #expect(converter.accountedRetainedBytes == 0)
        var fresh = try PCMBandlimitedResampler(inputFormat: format, outputSampleRate: 48_000)
        #expect(try converter.process(block) == fresh.process(block))
        #expect(try converter.finish() == fresh.finish())
        #expect(converter.inputFormat == format)
        #expect(converter.outputFormat == (try PCMFormat(sampleRate: 48_000, channelCount: 1)))
    }

    /// Produces deterministic finite PCM with deliberately different interleaved channels.
    /// - Parameters:
    ///   - frames: Nonnegative fixture frame count, bounded by the caller's test scenario.
    ///   - channels: One or two samples in each frame.
    /// - Returns: Owned normalized samples including full-scale signed values.
    private func fixture(frames: Int, channels: Int) -> [Float] {
        (0..<frames).flatMap { frame in
            (0..<channels).map { channel in Float((frame * 17 + channel * 31) % 257 - 128) / 128 }
        }
    }

    /// Synthesizes a sub-full-scale pure sinusoid with a known source-clock phase.
    /// - Parameters:
    ///   - frames: Positive bounded number of mono frames.
    ///   - rate: Source frames per second.
    ///   - frequency: Positive frequency in hertz below the source Nyquist frequency.
    /// - Returns: Dense mono samples with amplitude 0.2, leaving ample interpolation headroom.
    private func tone(frames: Int, rate: Int, frequency: Double) -> [Float] {
        (0..<frames).map { Float(0.2 * sin(2 * Double.pi * frequency * Double($0) / Double(rate))) }
    }

    /// Calculates independent RMS energy for a nonempty bounded mono sample array.
    /// - Parameter samples: Finite fixture samples, with edge transients already removed.
    /// - Returns: Nonnegative root-mean-square amplitude in normalized PCM units.
    private func rms(_ samples: [Float]) -> Double {
        sqrt(samples.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(samples.count))
    }

    /// Streams one fixture with a repeating bounded split pattern, including empty boundaries.
    /// Every returned block and retained-history bound is checked while collecting output.
    /// - Parameters:
    ///   - samples: Complete interleaved PCM in the given layout.
    ///   - format: Required source format; source length can exceed a single block.
    ///   - destinationRate: Valid target sample rate.
    ///   - pattern: Nonempty positive chunk sizes, each within the source PCM block duration cap.
    /// - Returns: Concatenated output samples including the explicit finish tail.
    /// - Throws: Propagates PCM fixture validation or resampler errors, failing the test.
    private func convert(samples: [Float], format: PCMFormat, destinationRate: Int, pattern: [Int]) throws -> [Float] {
        var converter = try PCMBandlimitedResampler(inputFormat: format, outputSampleRate: destinationRate)
        var output: [Float] = []
        let frames = samples.count / format.channelCount
        var start = 0
        var step = 0
        while start < frames {
            #expect(try converter.process(PCMBuffer(format: format, samples: [])).isEmpty)
            let count = min(pattern[step % pattern.count], frames - start)
            let lower = start * format.channelCount
            let upper = (start + count) * format.channelCount
            let blocks = try converter.process(PCMBuffer(format: format, samples: Array(samples[lower..<upper])))
            #expect(blocks.allSatisfy { $0.frameCount > 0 && $0.frameCount <= destinationRate * 120 / 1_000 })
            #expect(converter.retainedFrameCount <= converter.maximumRetainedFrameCount)
            output.append(contentsOf: blocks.flatMap(\.samples))
            start += count
            step += 1
        }
        let tail = try converter.finish()
        #expect(tail.allSatisfy { $0.frameCount > 0 && $0.frameCount <= destinationRate * 120 / 1_000 })
        output.append(contentsOf: tail.flatMap(\.samples))
        #expect(converter.retainedFrameCount == 0)
        return output
    }
}
