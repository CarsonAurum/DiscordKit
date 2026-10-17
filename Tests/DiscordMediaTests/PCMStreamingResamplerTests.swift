import Testing
@testable import DiscordMedia

@Suite("Bounded streaming linear PCM resampling")
struct PCMStreamingResamplerTests {
    /// Rejects invalid destination rates at both boundaries and hostile integer extremes.
    /// - Parameter rate: An out-of-range destination rate; source construction is valid.
    @Test(arguments: [7_999, 192_001, Int.min, Int.max])
    func invalidDestination(rate: Int) throws {
        let format = try PCMFormat()
        #expect(throws: MediaError.invalidFormat) {
            try PCMStreamingResampler(inputFormat: format, outputSampleRate: rate)
        }
    }

    /// Compares differently split streams with whole-block and existing stateless interpolation.
    /// Empty blocks and one-frame chunks must not alter phase, samples, channel order or count.
    /// - Parameters:
    ///   - sourceRate: Input rate, including awkward rational and extreme conversions.
    ///   - destinationRate: Output rate, including equal-rate identity and both rate extremes.
    ///   - channels: Mono or stereo layout; stereo samples deliberately differ by channel.
    @Test(arguments: [
        (8_000, 192_000, 1), (8_000, 192_000, 2),
        (192_000, 8_000, 1), (192_000, 8_000, 2),
        (44_101, 48_000, 1), (44_101, 48_000, 2),
        (48_000, 44_101, 1), (48_000, 44_101, 2),
        (48_000, 48_000, 1), (48_000, 48_000, 2)
    ])
    func splitMatchesWholeBlock(sourceRate: Int, destinationRate: Int, channels: Int) throws {
        let format = try PCMFormat(sampleRate: sourceRate, channelCount: channels)
        let samples = makeSamples(frames: 239, channels: channels)
        let whole = try PCMBuffer(format: format, samples: samples)
        let expected = try whole.resampled(to: destinationRate).samples
        var converter = try PCMStreamingResampler(inputFormat: format, outputSampleRate: destinationRate)
        let converted = try converter.process(whole) + converter.finish()
        #expect(converted.flatMap(\.samples) == expected)
        #expect(converter.inputFormat == format)
        #expect(converter.outputFormat == (try PCMFormat(sampleRate: destinationRate, channelCount: channels)))
        #expect(converter.isFinished)

        for pattern in [[1], [1, 2, 3, 5, 8, 13, 21], [127, 1, 111]] {
            var split = try PCMStreamingResampler(inputFormat: format, outputSampleRate: destinationRate)
            let actual = try convert(samples: samples, format: format, chunkPattern: pattern, using: &split)
            #expect(actual == expected)
        }
    }

    /// Ensures interpolation waits for the next block rather than holding an ordinary boundary.
    /// This also verifies exact endpoint values, stereo separation and the explicit held tail.
    @Test func interpolationCrossesBlockBoundaries() throws {
        let format = try PCMFormat(sampleRate: 24_000, channelCount: 2)
        var converter = try PCMStreamingResampler(inputFormat: format, outputSampleRate: 48_000)
        let first = try converter.process(PCMBuffer(format: format, samples: [0, 1]))
        #expect(first.flatMap(\.samples) == [0, 1])
        #expect(try converter.process(PCMBuffer(format: format, samples: [])).isEmpty)
        let second = try converter.process(PCMBuffer(format: format, samples: [1, -1]))
        #expect(second.flatMap(\.samples) == [0.5, 0, 1, -1])
        #expect(try converter.finish().flatMap(\.samples) == [1, -1])
        #expect(try converter.finish().isEmpty)
    }

    /// Verifies a single upsampling input emits one exact frame and only finish holds its tail.
    /// One-frame downsampling streams must emit nothing, including their deferred candidate.
    /// - Parameter channels: Both supported layouts, with a different right-channel sample.
    @Test(arguments: [1, 2])
    func oneFrameStreams(channels: Int) throws {
        let input = try PCMFormat(sampleRate: 8_000, channelCount: channels)
        let frame: [Float] = channels == 1 ? [0.25] : [0.25, -0.5]
        var up = try PCMStreamingResampler(inputFormat: input, outputSampleRate: 192_000)
        #expect(try up.process(PCMBuffer(format: input, samples: frame)).flatMap(\.samples) == frame)
        #expect(try up.finish().flatMap(\.samples) == Array(repeating: frame, count: 23).flatMap { $0 })
        #expect(up.isFinished)

        let high = try PCMFormat(sampleRate: 192_000, channelCount: channels)
        var down = try PCMStreamingResampler(inputFormat: high, outputSampleRate: 8_000)
        #expect(try down.process(PCMBuffer(format: high, samples: frame)).isEmpty)
        #expect(try down.finish().isEmpty)
        #expect(try down.finish().isEmpty)
        #expect(down.isFinished)
    }

    /// Preserves a downsampling sample captured before the aggregate duration earns its frame.
    /// Tiny blocks force that candidate to survive 23 later input frames without retaining them.
    @Test func downsamplingDefersCountWithoutLosingSample() throws {
        let format = try PCMFormat(sampleRate: 192_000, channelCount: 1)
        var converter = try PCMStreamingResampler(inputFormat: format, outputSampleRate: 8_000)
        #expect(try converter.process(PCMBuffer(format: format, samples: [1])).isEmpty)
        for _ in 0..<22 {
            #expect(try converter.process(PCMBuffer(format: format, samples: [-1])).isEmpty)
        }
        #expect(try converter.process(PCMBuffer(format: format, samples: [-1])).flatMap(\.samples) == [1])
        #expect(try converter.process(PCMBuffer(format: format, samples: [0.5])).isEmpty)
        for _ in 0..<22 {
            #expect(try converter.process(PCMBuffer(format: format, samples: [0])).isEmpty)
        }
        #expect(try converter.process(PCMBuffer(format: format, samples: [0])).flatMap(\.samples) == [0.5])
        #expect(try converter.finish().isEmpty)
    }

    /// Proves a fractional carry can yield two output blocks without violating the 120ms cap.
    /// A 960-frame 8kHz block sometimes produces 961 frames at 8001Hz after phase accumulates.
    @Test func maximumInputSplitsOutputAtDurationBound() throws {
        let format = try PCMFormat(sampleRate: 8_000, channelCount: 2)
        let maximum = try PCMBuffer(format: format, samples: Array(repeating: 0.5, count: 1_920))
        var converter = try PCMStreamingResampler(inputFormat: format, outputSampleRate: 8_001)
        var observedSplit = false
        var frames = 0
        for _ in 0..<20 {
            let blocks = try converter.process(maximum)
            #expect(blocks.count <= 2)
            if blocks.count == 2 {
                observedSplit = true
                #expect(blocks.map(\.frameCount) == [960, 1])
            }
            for block in blocks {
                #expect(block.frameCount > 0 && block.frameCount <= 960)
                #expect(block.samples.allSatisfy { $0 == 0.5 })
                #expect(block.accountedBytes == block.samples.count * MemoryLayout<Float>.stride)
            }
            frames += blocks.reduce(0) { $0 + $1.frameCount }
        }
        frames += try converter.finish().reduce(0) { $0 + $1.frameCount }
        #expect(observedSplit)
        #expect(frames == 20 * 960 * 8_001 / 8_000)
    }

    /// Checks count and interpolation continuity over thousands of awkward-rate boundaries.
    /// The independent full-stream reference uses integer positions, so no timing sleeps or
    /// floating-point cumulative clock can hide a dropped frame or drift in the converter.
    @Test func longStreamHasExactCountAndNoBoundaryDrift() throws {
        let format = try PCMFormat(sampleRate: 44_101, channelCount: 2)
        var converter = try PCMStreamingResampler(inputFormat: format, outputSampleRate: 48_000)
        var inputSamples: [Float] = []
        var outputSamples: [Float] = []
        var inputFrames = 0
        for index in 0..<4_096 {
            let count = index % 17 + 1
            let samples = makeSamples(frames: count, channels: 2, offset: inputFrames)
            inputSamples.append(contentsOf: samples)
            inputFrames += count
            outputSamples.append(contentsOf: try converter.process(PCMBuffer(format: format, samples: samples)).flatMap(\.samples))
            #expect(outputSamples.count / 2 <= inputFrames * 48_000 / 44_101)
        }
        outputSamples.append(contentsOf: try converter.finish().flatMap(\.samples))
        let expectedCount = inputFrames * 48_000 / 44_101
        #expect(outputSamples.count == expectedCount * 2)
        for index in 0..<expectedCount {
            let position = index * 44_101
            let lower = position / 48_000
            let upper = min(lower + 1, inputFrames - 1)
            let weight = Float(position % 48_000) / 48_000
            for channel in 0..<2 {
                let first = inputSamples[lower * 2 + channel]
                let second = inputSamples[upper * 2 + channel]
                #expect(outputSamples[index * 2 + channel] == max(-1, min(1, first + (second - first) * weight)))
            }
        }
    }

    /// Checks rejection atomicity for rate/channel mismatches, including empty wrong-format
    /// blocks, while interpolation is pending. A copied converter provides the expected state.
    @Test func rejectedFormatLeavesHistoryUnchanged() throws {
        let format = try PCMFormat(sampleRate: 24_000, channelCount: 2)
        var converter = try PCMStreamingResampler(inputFormat: format, outputSampleRate: 48_000)
        _ = try converter.process(PCMBuffer(format: format, samples: [0, 1]))
        var untouched = converter
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
        let next = try PCMBuffer(format: format, samples: [1, -1])
        #expect(try converter.process(next) == untouched.process(next))
        #expect(try converter.finish() == untouched.finish())
    }

    /// Covers empty finish, idempotence, closed admission precedence and reset before/after
    /// closure. Reset discards both a downsampling candidate and an upsampling interpolation tail.
    @Test func finishAndResetLifecycle() throws {
        let format = try PCMFormat(sampleRate: 8_000, channelCount: 1)
        let empty = try PCMBuffer(format: format, samples: [])
        let one = try PCMBuffer(format: format, samples: [-0.5])
        var converter = try PCMStreamingResampler(inputFormat: format, outputSampleRate: 16_000)
        converter.reset()
        #expect(!converter.isFinished)
        #expect(try converter.process(empty).isEmpty)
        #expect(try converter.finish().isEmpty)
        #expect(try converter.finish().isEmpty)
        #expect(throws: MediaError.closed) { try converter.process(empty) }
        #expect(throws: MediaError.closed) { try converter.process(one) }
        let wrong = try PCMBuffer(format: PCMFormat(), samples: [])
        #expect(throws: MediaError.closed) { try converter.process(wrong) }

        converter.reset()
        var fresh = try PCMStreamingResampler(inputFormat: format, outputSampleRate: 16_000)
        #expect(try converter.process(one) == fresh.process(one))
        converter.reset()
        fresh.reset()
        #expect(try converter.finish().isEmpty)
        #expect(try fresh.finish().isEmpty)
        converter.reset()
        fresh.reset()
        #expect(try converter.process(one) == fresh.process(one))
        #expect(try converter.finish() == fresh.finish())

        var down = try PCMStreamingResampler(inputFormat: format, outputSampleRate: 8_000)
        #expect(try down.process(one).flatMap(\.samples) == [-0.5])
        let high = try PCMFormat(sampleRate: 16_000, channelCount: 1)
        down = try PCMStreamingResampler(inputFormat: high, outputSampleRate: 8_000)
        #expect(try down.process(PCMBuffer(format: high, samples: [1])).isEmpty)
        down.reset()
        #expect(try down.process(PCMBuffer(format: high, samples: [-1, 0])).flatMap(\.samples) == [-1])
        #expect(try down.finish().isEmpty)
    }

    /// Supplies deterministic finite channel-distinct samples without random state or I/O.
    /// - Parameters:
    ///   - frames: Nonnegative frame count used only by bounded deterministic fixtures.
    ///   - channels: One or two interleaved samples per frame.
    ///   - offset: First global frame index, preserving the pattern across split blocks.
    /// - Returns: Dense normalized interleaved values spanning both signed endpoints.
    private func makeSamples(frames: Int, channels: Int, offset: Int = 0) -> [Float] {
        (0..<frames).flatMap { frame in
            (0..<channels).map { channel in
                Float(((frame + offset) * 17 + channel * 31) % 257 - 128) / 128
            }
        }
    }

    /// Converts fixture samples in a repeating chunk pattern with empty blocks interspersed.
    /// - Parameters:
    ///   - samples: Complete interleaved frames in the supplied format.
    ///   - format: Expected source layout, matching the converter.
    ///   - chunkPattern: Nonempty positive frame counts, clipped at the input's end.
    ///   - converter: Mutable fresh converter, finished before this helper returns.
    /// - Returns: Concatenated output samples including the explicit final tail.
    /// - Throws: Propagates fixture buffer construction or resampler processing errors.
    private func convert(
        samples: [Float], format: PCMFormat, chunkPattern: [Int],
        using converter: inout PCMStreamingResampler
    ) throws -> [Float] {
        var output: [Float] = []
        var start = 0
        var index = 0
        let empty = try PCMBuffer(format: format, samples: [])
        while start < samples.count {
            #expect(try converter.process(empty).isEmpty)
            let end = min(samples.count, start + chunkPattern[index % chunkPattern.count] * format.channelCount)
            let block = try PCMBuffer(format: format, samples: Array(samples[start..<end]))
            output.append(contentsOf: try converter.process(block).flatMap(\.samples))
            start = end
            index += 1
        }
        output.append(contentsOf: try converter.finish().flatMap(\.samples))
        return output
    }
}
