import Foundation
import Testing
@testable import DiscordMedia

@Suite("Portable bounded media")
struct MediaTests {
    /// Checks exact rational representation, zero/large timestamps and invalid clock domains.
    /// No wall clock is used; invalid input must throw before constructing a value.
    @Test func mediaTimeValidation() throws {
        let zero = try MediaTime(value: 0, timescale: 48_000)
        #expect(zero.value == 0)
        #expect(zero.timescale == 48_000)
        #expect(try MediaTime(value: .max, timescale: .max).value == .max)
        #expect(try MediaTime(value: 1, timescale: 2) != MediaTime(value: 2, timescale: 4))
        #expect(throws: MediaError.invalidTime) { try MediaTime(value: -1, timescale: 1) }
        #expect(throws: MediaError.invalidTime) { try MediaTime(value: 1, timescale: 0) }
        #expect(throws: MediaError.invalidTime) { try MediaTime(value: 1, timescale: -1) }
    }

    /// Exercises storage-rate and channel bounds, including hostile integer extremes.
    /// - Parameters:
    ///   - sampleRate: Invalid sample rate, including overflow-prone extreme values.
    ///   - channels: Invalid or otherwise valid channel count paired with that rate.
    @Test(arguments: [(7_999, 1), (192_001, 2), (Int.max, 2), (Int.min, 1), (48_000, 0), (48_000, 3)])
    func invalidFormat(sampleRate: Int, channels: Int) {
        #expect(throws: MediaError.invalidFormat) { try PCMFormat(sampleRate: sampleRate, channelCount: channels) }
    }

    /// Checks default format, both rate extremes, finite normalization and the exact 120ms cap.
    @Test func pcmBoundariesAndAccounting() throws {
        let standard = try PCMFormat()
        #expect(standard.sampleRate == 48_000 && standard.channelCount == 2)
        let empty = try PCMBuffer(format: standard, samples: [])
        #expect(empty.frameCount == 0 && empty.accountedBytes == 0)
        #expect(empty.duration == (try MediaTime(value: 0, timescale: 48_000)))
        var overallocated: [Float] = []
        overallocated.reserveCapacity(1_000_000)
        overallocated.append(contentsOf: [-1, 1])
        let dense = try PCMBuffer(format: standard, samples: overallocated)
        #expect(dense.samples == [-1, 1] && dense.samples.capacity < overallocated.capacity)
        for rate in [8_000, 44_101, 48_000, 192_000] {
            for channels in [1, 2] {
                let format = try PCMFormat(sampleRate: rate, channelCount: channels)
                let frames = rate * 120 / 1_000
                let block = try PCMBuffer(format: format, samples: Array(repeating: -1, count: frames * channels))
                #expect(block.frameCount == frames)
                #expect(block.accountedBytes == frames * channels * 4)
                #expect(block.duration == (try MediaTime(value: Int64(frames), timescale: Int32(rate))))
                #expect(throws: MediaError.bufferTooLarge) {
                    try PCMBuffer(format: format, samples: Array(repeating: 0, count: (frames + 1) * channels))
                }
            }
        }
        #expect(throws: MediaError.invalidSamples) { try PCMBuffer(format: standard, samples: [0]) }
    }

    /// Rejects nonfinite and nonnormalized samples before they can reach gain, mixing or VAD.
    /// - Parameter sample: One invalid sample within a complete stereo frame.
    @Test(arguments: [Float.nan, .infinity, -.infinity, 1.001, -1.001])
    func invalidSamples(sample: Float) throws {
        #expect(throws: MediaError.invalidSamples) {
            try PCMBuffer(format: PCMFormat(), samples: [sample, 0])
        }
    }

    /// Round-trips every signed PCM16 value through normalized Float storage in bounded chunks.
    /// This verifies endian order, both signed extremes and quantization without tolerances.
    @Test func pcm16ExhaustiveRoundTrip() throws {
        let format = try PCMFormat(sampleRate: 192_000, channelCount: 1)
        for start in stride(from: 0, to: 65_536, by: 16_384) {
            var bytes: [UInt8] = []
            for bits in start..<(start + 16_384) {
                bytes.append(UInt8(truncatingIfNeeded: bits))
                bytes.append(UInt8(truncatingIfNeeded: bits >> 8))
            }
            let decoded = try PCMBuffer(format: format, pcm16LittleEndian: bytes)
            #expect(decoded.pcm16LittleEndian() == bytes)
        }
        let stereo = try PCMFormat()
        #expect(try PCMBuffer(format: stereo, pcm16LittleEndian: []).samples.isEmpty)
        #expect(throws: MediaError.invalidSamples) { try PCMBuffer(format: stereo, pcm16LittleEndian: [0]) }
        #expect(throws: MediaError.invalidSamples) { try PCMBuffer(format: stereo, pcm16LittleEndian: [0, 0]) }
        #expect(throws: MediaError.bufferTooLarge) {
            try PCMBuffer(format: stereo, pcm16LittleEndian: Array(repeating: 0, count: 23_044))
        }
        #expect(try PCMBuffer(format: stereo, samples: [-1, 1]).pcm16LittleEndian() == [0, 128, 255, 127])
        #expect(try PCMBuffer(format: stereo, samples: [0.5 / 32_768, -0.5 / 32_768]).pcm16LittleEndian() == [1, 0, 255, 255])
    }

    /// Verifies zero/unity/max gain, clipping and nonmutating aligned mixing across channels.
    @Test func gainAndMixing() throws {
        let format = try PCMFormat()
        let block = try PCMBuffer(format: format, samples: [-1, 0.5, 0.25, -0.25])
        #expect(try block.applyingGain(0).samples == [0, 0, 0, 0])
        #expect(try block.applyingGain(1) == block)
        #expect(try block.applyingGain(64).samples == [-1, 1, 1, -1])
        let other = try PCMBuffer(format: format, samples: [0.5, 0.75, -0.5, -1])
        #expect(try block.mixing(other).samples == [-0.5, 1, -0.25, -1])
        #expect(block.samples == [-1, 0.5, 0.25, -0.25])
        #expect(try PCMBuffer(format: format, samples: []).mixing(PCMBuffer(format: format, samples: [])).samples.isEmpty)
        #expect(throws: MediaError.incompatibleBuffers) { try block.mixing(PCMBuffer(format: format, samples: [0, 0])) }
        #expect(throws: MediaError.incompatibleBuffers) {
            try block.mixing(PCMBuffer(format: PCMFormat(sampleRate: 24_000), samples: block.samples))
        }
    }

    /// Rejects each invalid gain class, including extremes that could otherwise overflow samples.
    /// - Parameter gain: Nonfinite, negative or above the admitted finite multiplier range.
    @Test(arguments: [Float.nan, .infinity, -.infinity, -0.1, 64.001])
    func invalidGain(gain: Float) throws {
        let block = try PCMBuffer(format: PCMFormat(), samples: [0, 0])
        #expect(throws: MediaError.invalidGain) { try block.applyingGain(gain) }
    }

    /// Checks channel-independent interpolation, downsampling, final-sample hold and floor counts.
    /// Empty/one-frame inputs and a maximum-duration conversion exercise index/allocation bounds.
    @Test func linearResampling() throws {
        let source = try PCMBuffer(format: PCMFormat(sampleRate: 24_000), samples: [0, 1, 1, -1])
        #expect(try source.resampled(to: 48_000).samples == [0, 1, 0.5, 0, 1, -1, 1, -1])
        #expect(try source.resampled(to: 24_000) == source)
        #expect(try source.resampled(to: 12_000).samples == [0, 1])
        #expect(try source.resampled(to: 8_000).samples.isEmpty)
        let single = try PCMBuffer(format: PCMFormat(sampleRate: 8_000, channelCount: 1), samples: [-0.5])
        #expect(try single.resampled(to: 16_000).samples == [-0.5, -0.5])
        #expect(try PCMBuffer(format: PCMFormat(), samples: []).resampled(to: 192_000).samples.isEmpty)
        let maximum = try PCMBuffer(format: PCMFormat(sampleRate: 192_000), samples: Array(repeating: 1, count: 46_080))
        #expect(try maximum.resampled(to: 8_000).frameCount == 960)
        #expect(throws: MediaError.invalidFormat) { try source.resampled(to: Int.max) }
    }

    /// Checks RMS threshold equality, cross-channel aggregation and always-false empty blocks.
    @Test func energyGate() throws {
        let format = try PCMFormat()
        let block = try PCMBuffer(format: format, samples: [0.5, -0.5])
        #expect(try block.passesEnergyGate(threshold: 0.5))
        #expect(try !block.passesEnergyGate(threshold: 0.51))
        #expect(try block.passesEnergyGate(threshold: 0))
        #expect(try !PCMBuffer(format: format, samples: []).passesEnergyGate(threshold: 0))
        #expect(try PCMBuffer(format: format, samples: [-1, 1]).passesEnergyGate(threshold: 1))
        for invalid in [Float.nan, .infinity, -0.1, 1.1] {
            #expect(throws: MediaError.invalidThreshold) { try block.passesEnergyGate(threshold: invalid) }
        }
    }

    /// Validates encoded-audio timing/layout and video metadata at normal and maximum bounds.
    /// Payload bytes remain opaque; tests deliberately make no codec decoding claim.
    @Test func encodedFrames() throws {
        let time = try MediaTime(value: .max, timescale: .max)
        let duration = try MediaTime(value: 5_760, timescale: 48_000)
        let audio = try EncodedAudioFrame(bytes: Data([0]), timestamp: time, duration: duration)
        #expect(audio.codec == .opus && audio.sampleRate == 48_000 && audio.channelCount == 2)
        #expect(audio.bytes == Data([0]) && audio.duration == duration && audio.timestamp == time)
        #expect(try EncodedAudioFrame(bytes: Data(repeating: 0, count: 65_536), timestamp: time, duration: duration).bytes.count == 65_536)
        for codec: MediaCodec in [.h264, .vp8, .vp9, .av1] {
            let frame = try EncodedVideoFrame(codec: codec, bytes: Data([1]), timestamp: time, width: 8_192, height: 1, isKeyFrame: true)
            #expect(frame.codec == codec && frame.width == 8_192 && frame.height == 1)
            #expect(frame.isKeyFrame && frame.timestamp == time && frame.bytes == Data([1]))
            #expect(throws: MediaError.invalidEncodedFrame) {
                try EncodedAudioFrame(codec: codec, bytes: Data([1]), timestamp: time, duration: duration)
            }
        }
        for count in [0, 65_537] {
            #expect(throws: MediaError.invalidEncodedFrame) {
                try EncodedAudioFrame(bytes: Data(repeating: 0, count: count), timestamp: time, duration: duration)
            }
        }
        for invalid in [try MediaTime(value: 0, timescale: 1), try MediaTime(value: 5_761, timescale: 48_000), time] {
            #expect(throws: MediaError.invalidEncodedFrame) {
                try EncodedAudioFrame(bytes: Data([0]), timestamp: time, duration: invalid)
            }
        }
        #expect(throws: MediaError.invalidFormat) {
            try EncodedAudioFrame(bytes: Data([0]), timestamp: time, duration: duration, channelCount: 3)
        }
        #expect(try EncodedVideoFrame(codec: .av1, bytes: Data(repeating: 0, count: 4_194_304), timestamp: time, width: 1, height: 8_192, isKeyFrame: false).bytes.count == 4_194_304)
        for (codec, count, width, height) in [(MediaCodec.opus, 1, 1, 1), (.vp8, 0, 1, 1), (.vp9, 4_194_305, 1, 1), (.av1, 1, 0, 1), (.h264, 1, 1, 8_193)] {
            #expect(throws: MediaError.invalidEncodedFrame) {
                try EncodedVideoFrame(codec: codec, bytes: Data(repeating: 0, count: count), timestamp: time, width: width, height: height, isKeyFrame: false)
            }
        }
    }

    /// Exercises both queue budgets, FIFO source/sink existential calls, draining and discard.
    /// Every operation completes synchronously within actor isolation without timing assumptions.
    @Test func queueLifecycleAndBudgets() async throws {
        let format = try PCMFormat()
        let first = try PCMBuffer(format: format, samples: [0, 0])
        let second = try PCMBuffer(format: format, samples: [1, -1])
        let queue = try PCMFrameQueue(maximumBlocks: 2, maximumBytes: 16)
        let source: any PCMSource = queue
        let sink: any PCMSink = queue
        #expect(try await source.read() == nil)
        try await sink.write(first)
        try await sink.write(second)
        #expect(await queue.accountedBytes == 16)
        await #expect(throws: MediaError.queueFull) { try await queue.write(first) }
        #expect(try await source.read() == first)
        #expect(await queue.accountedBytes == 8)
        await queue.finish()
        #expect(await queue.isFinished)
        await #expect(throws: MediaError.closed) { try await sink.write(first) }
        #expect(try await source.read() == second)
        #expect(try await source.read() == nil)
        #expect(await queue.accountedBytes == 0)
        await queue.finish(discardingBuffered: true)
        let bytes = try PCMFrameQueue(maximumBlocks: 8, maximumBytes: 7)
        await #expect(throws: MediaError.queueFull) { try await bytes.write(first) }
        #expect(await bytes.accountedBytes == 0)
        let emptyBound = try PCMFrameQueue(maximumBlocks: 1, maximumBytes: 1)
        try await emptyBound.write(PCMBuffer(format: format, samples: []))
        await #expect(throws: MediaError.queueFull) { try await emptyBound.write(PCMBuffer(format: format, samples: [])) }
        await emptyBound.finish(discardingBuffered: true)
        #expect(try await emptyBound.read() == nil)
        for (blocks, capacity) in [(0, 1), (4_097, 1), (1, 0), (1, 67_108_865)] {
            #expect(throws: MediaError.invalidCapacity) { try PCMFrameQueue(maximumBlocks: blocks, maximumBytes: capacity) }
        }
    }

    /// Competes 32 producers for eight slots, proving atomic admission and byte accounting.
    /// Self-cancelled tasks then prove cancelled reads/writes leave the queued block unchanged.
    @Test func concurrentQueueAndCancellation() async throws {
        let block = try PCMBuffer(format: PCMFormat(), samples: [0.25, -0.25])
        let queue = try PCMFrameQueue(maximumBlocks: 8, maximumBytes: 64)
        let admitted = await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<32 {
                group.addTask {
                    do { try await queue.write(block); return true }
                    catch { return false }
                }
            }
            var successes = 0
            for await accepted in group { if accepted { successes += 1 } }
            return successes
        }
        #expect(admitted == 8)
        #expect(await queue.accountedBytes == 64)
        await queue.finish(discardingBuffered: true)
        #expect(await queue.accountedBytes == 0)
        let active = try PCMFrameQueue()
        try await active.write(block)
        let cancelledRead = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await active.read()
        }
        await #expect(throws: CancellationError.self) { try await cancelledRead.value }
        let cancelledWrite = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await active.write(block)
        }
        await #expect(throws: CancellationError.self) { try await cancelledWrite.value }
        #expect(await active.accountedBytes == 8)
        #expect(try await active.read() == block)
        #expect(try await active.read() == nil)
        try await active.write(block)
        await active.finish()
        await active.finish(discardingBuffered: true)
        await active.finish(discardingBuffered: true)
        #expect(await active.accountedBytes == 0)
        #expect(try await active.read() == nil)
    }
}
