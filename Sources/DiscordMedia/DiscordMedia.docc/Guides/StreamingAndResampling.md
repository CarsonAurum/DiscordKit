# Streaming, resampling and pacing

Bound both producer memory and processing history while preserving a continuous timeline.

## Overview

### Choose polling or suspension

``PCMFrameQueue`` is a bounded polling source/sink: read returns nil when no block is currently available. ``PCMFrameStream`` is a single-consumer AsyncSequence: its reader suspends until a block or finish, and producer writes fail when capacity is exhausted. Neither creates a producer task or an unbounded backlog.

```swift
import DiscordMedia

/// Drains two buffered blocks with no device, network or unbounded producer queue.
func countBufferedFrames() async throws -> Int {
    let format = try PCMFormat(sampleRate: 24_000, channelCount: 1)
    let stream = try PCMFrameStream(maximumBlocks: 2, maximumBytes: 3_840)
    try await stream.write(PCMBuffer(format: format, samples: Array(repeating: 0.25, count: 480)))
    try await stream.write(PCMBuffer(format: format, samples: Array(repeating: -0.25, count: 480)))
    await stream.finish()
    var count = 0
    for try await block in stream {
        count += block.frameCount
    }
    return count
}
```

`finish()` normally drains buffered blocks and then yields EOF. Set `discardingBuffered` to release them immediately. Cancellation terminates the stream and releases a parked iterator rather than leaving a hidden waiter. Use one logical reader; additional application fan-out requires separately bounded consumers. `snapshot()` exposes retained counts and bytes without copying PCM.

An upstream microphone, decoder or file reader still needs its own queue/admission policy. Stream capacity does not bound work created before `write`, and fail-fast writes do not apply backpressure to an arbitrary external capture API.

### Preserve phase across chunks

`PCMBuffer.resampled(to:)` is a block-local linear converter with a held final sample. It has no antialias filter or continuity state. Use it for fixtures/previews where those limits are acceptable.

``PCMStreamingResampler`` retains interpolation phase/history across blocks. ``PCMBandlimitedResampler`` adds a bounded antialias filter and lookahead. Both preserve channels, require the exact input format and return zero or more bounded output blocks; the output count from one call is not necessarily proportional to only that call's input.

```swift
import DiscordMedia

/// Filters a finite 24-kHz stream into an exact 48-kHz sample timeline.
func resampledFrameCount() throws -> Int64 {
    let format = try PCMFormat(sampleRate: 24_000, channelCount: 1)
    var resampler = try PCMBandlimitedResampler(
        inputFormat: format,
        outputSampleRate: 48_000
    )
    var timeline = try PCMSampleClock(sampleRate: 48_000)
    for _ in 0..<2 {
        let input = try PCMBuffer(format: format, samples: Array(repeating: 0.25, count: 480))
        for output in try resampler.process(input) {
            _ = try timeline.advance(by: output.frameCount)
        }
    }
    for output in try resampler.finish() {
        _ = try timeline.advance(by: output.frameCount)
    }
    return timeline.samplePosition
}
```

Finishing flushes final lookahead under the owner's defined boundary policy. Do not drop that tail when exporting a finite recording. Reset or create a new converter on a discontinuity instead of carrying predictor/filter history into unrelated audio. Local deterministic filtering does not establish perceptual qualification for every source or device.

### Pace without confusing sample and wall clocks

``PCMFramePacer`` uses an injected Swift Clock at a fixed sample rate. `wait(frameCount:)` reserves a sample-derived slot and suspends cooperatively. It rejects overlapping waits and supports explicit reset at a new timeline. Skip empty blocks: `wait(frameCount:)` requires a positive frame count within the 120ms bound and rejects zero.

A pacer controls scheduling, not device drift or hardware realtime guarantees. A session-level sender also needs a policy for long idle periods and late wakeups so it does not burst accumulated slots. Voice session media has its own pacing owner; avoid layering another independent pacer that doubles the delay.

Test chunk-size independence, empty input, format mismatch, flush/repeated finish, time overflow, queue count/byte edges and cancellation of a parked reader with deterministic clocks. The [offline media example](https://github.com/CarsonAurum/DiscordKit/tree/main/Examples/VoiceBot) contains a continuous resampling exchange without opening devices.
