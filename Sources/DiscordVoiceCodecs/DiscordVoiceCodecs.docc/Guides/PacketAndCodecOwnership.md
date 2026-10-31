[//]: # "File: Sources/DiscordVoiceCodecs/DiscordVoiceCodecs.docc/Guides/PacketAndCodecOwnership.md | Created by Carson Rau. | Copyright (c) 2026 Aurum Studios. | https://aurum-studios.com"

# Ordinary Opus packets and codec ownership

Select a fixed encoder policy and retain per-stream decoding history.

## Overview

### Parse framing separately from audio

``OpusPacket`` validates the ordinary RFC 6716 packet layout: TOC, all four packing codes, VBR lengths, frame boundaries, optional padding and total duration. It has a local 65,536-byte packet cap, at most 48 ranges, 1,275 bytes per compressed payload and 120 milliseconds per packet.

A structurally valid packet can still contain invalid entropy syntax. Parsing does not synthesize audio, authenticate a sender or establish codec interoperability. The parser handles an ordinary packet, not Ogg, multistream concatenation or self-delimiting container framing.

```swift
import DiscordVoiceCodecs
import Foundation

let silence = Data([0xF8, 0xFF, 0xFE])
let packet = try OpusPacket(silence)
assert(packet.sampleCount == 960)
assert(packet.channelCount == 1)
assert(packet.frameRanges.count == 1)
```

`sampleCount` is samples per channel on the mandatory 48-kHz Opus/RTP clock. The TOC's nominal bandwidth is independent of that output clock. A zero-byte payload is valid loss/DTX framing; empty packet data lacks the required TOC and is invalid.

### Own one encoder per stream

``OpusAudioEncoder`` takes normalized 48-kHz interleaved PCM. Mode, bandwidth, frame duration and channel layout remain fixed. CELT accepts 120/240/480/960 samples per channel; SILK/hybrid accept 480/960. Reconfiguration that changes those invariants needs a fresh encoder owner, rather than copying a live history between unrelated streams.

```swift
import DiscordVoiceCodecs

var encoder = try OpusAudioEncoder(
    mode: .celt,
    bandwidth: .fullband,
    frameSampleCount: 960,
    channelCount: 1,
    targetBitrate: 64_000
)
let pcm = Array(repeating: Float(0), count: 960)
let encoded = try encoder.encode(pcm)
let packet = try OpusPacket(encoded.data)
assert(packet.sampleCount == 960)
```

Encoder calls are synchronous and stateful. Serialize mutation; a value copy forks predictor, resampling, rate-carry and DTX history. Failed calls commit no codec state. Construction opens no device, creates no tasks and links no native codec.

The high-level policy bounds packet allocation and exposes specific admission failures. It does not guarantee every SILK signal fits every small bitrate, automatic encoder mode switching, psychoacoustic equivalence to libopus, multistream support or hard realtime behavior.

### Supply an application-owned encoder

``OpusPCMEncoding`` is the synchronous boundary for an application-provided encoder, including a separately linked native implementation. Its immutable geometry is one or two channels and 120, 240, 480 or 960 samples per channel at 48 kHz. ``OpusAudioEncoder`` conforms, preserving the ordinary default and its transactional value semantics.

```swift
import DiscordVoiceCodecs

/// Constructs one independent stream owner without I/O or background work.
func makeStreamEncoder() throws -> any OpusPCMEncoding {
    try OpusAudioEncoder(channelCount: 2, targetBitrate: 128_000)
}

var streamEncoder = try makeStreamEncoder()
let output = try streamEncoder.encode(Array(repeating: 0.1, count: 1_920))
let validated = try OpusPacket(output.data)
assert(validated.channelCount == 2 && validated.sampleCount == 960)
streamEncoder.reset()
```

Return a fresh owner for every stream. A reference-backed implementation must own its native allocation, serialize mutation and free it after its last use; copying its Swift wrapper does not create an independent codec history. A Voice session's encoder factory is invoked when its secure media pipeline is composed, and session teardown resets the pipeline's exclusive encoder. Factory failure terminates the session and joins acquired resources.

``OpusAudioEncodedPacket/init(data:shouldTransmit:isDTX:packetByteBudget:finalRange:)`` describes externally produced output. A transmitted complete packet must match the fixed duration and channel geometry and fit its declared allocation of at most 1,276 bytes. Deliberately suppressed DTX uses `shouldTransmit: false` and `isDTX: true`, retaining a matching nonempty TOC. The Voice pipeline validates those bounds and framing before consuming RTP or cryptographic counters; invalid output is terminal for supervised playback and is never replayed.

Injecting a different codec leaves pacing, authorization, secure transport and joined source ownership with the existing Voice session. It does not establish a CPU-time bound, real-time scheduling, perceptual quality or listener delivery. Measure optimized builds on the actual host under representative concurrent load and distinguish encoding time from source starvation, packet gaps and network latency.

### Retain decoder history across ordinary changes

``OpusAudioDecoder`` has a fixed one- or two-channel output layout at 48 kHz while accepting ordinary coded-channel, mode, bandwidth and duration changes. It retains SILK/CELT history and coordinates transition redundancy. Decode returns one result per packed payload; concatenate the samples in wire order for the complete packet.

```swift
import DiscordVoiceCodecs

var encoder = try OpusAudioEncoder(channelCount: 1)
var decoder = try OpusAudioDecoder(channelCount: 1)
let encoded = try encoder.encode(Array(repeating: Float(0), count: 960))
let frames = try decoder.decode(encoded.data)
assert(frames.reduce(0) { $0 + $1.frameSampleCount } == 960)
assert(frames.allSatisfy { $0.channelCount == 1 })
```

Each decode is atomic across the packet; failure in its last packed payload preserves earlier pre-call state too. Decoder output is normalized floating point but can exceed `-1...1` before a sink boundary. Apply an explicit saturation policy before constructing a normalized PCM buffer. `reset()` discards prediction, overlap, format and loss history; it is a stream discontinuity, not a way to process reordered packets.

Use lower-level SILK/CELT/range APIs only when you intend to own all required syntax and history. A transform coefficient or entropy round trip alone does not constitute a complete Opus codec. The [offline codec example](https://github.com/CarsonAurum/DiscordKit/tree/main/Examples/VoiceBot) exercises both complete packets and isolated components.
