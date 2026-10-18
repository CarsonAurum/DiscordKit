# PCM samples, frames and exact media time

Keep channel layout, duration and physical scheduling separate.

## Overview

### Count frames rather than scalar samples

``PCMFormat`` describes one or two interleaved channels at an integer rate from 8,000 through 192,000 sample frames per second. Those storage bounds do not promise that every codec or native device supports every rate. A frame contains one sample per channel: 20 milliseconds at 48 kHz is 960 frames, or 1,920 Float values for stereo.

``PCMBuffer`` validates finite normalized samples in `-1...1`, whole interleaved frames and a maximum block duration of 120 milliseconds. Empty buffers are valid. Construction makes a dense owned copy so excess reserved array capacity is not retained.

```swift
import DiscordMedia

let format = try PCMFormat(sampleRate: 48_000, channelCount: 2)
let silence = try PCMBuffer(
    format: format,
    samples: Array(repeating: 0, count: 960 * format.channelCount)
)
assert(silence.frameCount == 960)
assert(silence.accountedBytes == 1_920 * MemoryLayout<Float>.stride)
```

The byte count accounts for PCM payload rather than complete process RSS or Swift object overhead. Pair byte budgets with block counts when bounding a queue.

Use `pcm16LittleEndian()` for signed 16-bit little-endian interchange. Conversion saturates positive full scale at 32767 and negative full scale at -32768, with no dithering. The inverse initializer rejects incomplete scalar samples and partial channel frames.

### Apply gain and mix aligned blocks

`applyingGain` takes a finite linear multiplier in `0...64`, not decibels; zero produces silence. `mixing` requires identical format and frame count. Both are synchronous, linear in the bounded block and return new values. Mixing clips once after summing aligned samples; it does not align timestamps, normalize loudness or change channels.

```swift
import DiscordMedia

let format = try PCMFormat(sampleRate: 48_000, channelCount: 1)
let input = try PCMBuffer(format: format, samples: Array(repeating: 0.25, count: 960))
let quieter = try input.applyingGain(0.5)
let mixed = try input.mixing(quieter)
assert(mixed.samples.allSatisfy { $0 == 0.375 })
```

Choose application-specific clipping, gain automation and recording policy outside this value layer. A speech decision is also separate from loudness: ``PCMSpeechActivityDetector`` applies bounded statistical analysis with explicit format and hangover, not a guarantee of speech recognition or semantic content classification.

### Preserve exact clock units

``MediaTime`` stores nonnegative integer ticks over a positive timescale. Equality compares the stored representation, so `1/2` and `2/4` differ as values. Use `compare(to:)` for mathematical ordering or `converted(to:rounding:)` for an explicit target clock.

``PCMSampleClock`` advances in sample frames independent of channel count. It has no system clock or task. Advance after admitting a block, and retain the returned start timestamp with that block. A different stream or discontinuity needs an explicit reset.

```swift
import DiscordMedia

var clock = try PCMSampleClock(sampleRate: 48_000)
let start = try clock.advance(by: 960)
let next = clock.timestamp
assert(start.value == 0)
assert(next.value == 960)
let milliseconds = try next.converted(to: 1_000)
assert(milliseconds.value == 20)
```

Integer conversion checks overflow and gives explicit rounding. Do not repeatedly round each small block into milliseconds and add those rounded values; retain cumulative sample positions to avoid drift. Physical audio clocks, monotonic deadlines and wall time remain distinct.

``EncodedAudioFrame`` and ``EncodedVideoFrame`` attach bounded metadata to encoded bytes. Their codec labels do not validate compressed syntax or implement packetization. Use a codec parser and protocol layer for those responsibilities.
