[//]: # "File: Sources/DiscordVoice/DiscordVoice.docc/Guides/MediaAndPlayout.md | Created by Carson Rau. | Copyright (c) 2026 Aurum Studios. | https://aurum-studios.com"

# Sending, playout and recording

Transform complete frames before packetization and retain independent receive histories.

## Overview

### Send only while the secure session is ready

`VoiceSession.mediaPipeline()` returns an owner only during authenticated ready state. Before outgoing media, the session publishes Speaking for its local SSRC. `setSpeaking(false)` gates sending independently of receive/playout; publish true for a later talkspurt.

The send path is PCM validation/encoding or complete Opus parsing, then complete-frame E2EE, RTP packetization, transport AEAD and one UDP send. ``VoiceFrameTransformer`` must reject unavailable keys and unauthorized senders; a plaintext or transport-only fallback is forbidden. Cryptographic counters do not reset when RTP sequence/timestamps wrap.

```swift
import DiscordTransport
import DiscordVoice
import Foundation

/// Sends one complete encoded packet through a ready session's owned, paced pipeline.
func sendEncodedOpus(
    _ opus: Data,
    pipeline: VoiceMediaPipeline<ContinuousClock>,
    clock: ContinuousClock
) async throws {
    try await pipeline.sendOpus(
        opus,
        context: TransportContext(
            clock: clock,
            deadline: clock.now.advanced(by: .seconds(5))
        )
    )
}
```

The application must obtain `pipeline` from a ready supervisor and observe its speaking policy. `sendOpus` accepts a complete ordinary packet and paces its parsed duration. PCM sends require 48-kHz normalized PCM matching the owned encoder's channels and frame count. One send and one receive may be in flight; additional callers fail immediately.

Pacing anchors the first/restarted talkspurt to the current monotonic instant. A full packet of lateness reanchors the next slot, preventing a long idle period from producing a catch-up burst. Failed or ambiguous writes may consume codec, RTP and crypto state and are not replayed.

### Observe encoding and dispatch timing

``VoiceMediaPipeline/snapshot()`` returns fixed-size counters and maxima without retaining per-packet history. ``VoiceMediaPipelineSnapshot/encodedFrameCount`` includes successful synchronous PCM encoding calls, including DTX suppression. ``VoiceMediaPipelineSnapshot/maximumEncodingDurationMilliseconds`` measures monotonic elapsed time around the encoder alone; input waits, pacing, encryption and UDP work are outside that measurement. ``VoiceMediaPipelineSnapshot/encodingDeadlineMissCount`` counts encodes that exceed the exact PCM duration, such as twenty milliseconds for a 960-frame block. This is elapsed time, which includes any scheduling interruption during encoding, rather than process CPU time.

``VoiceMediaPipelineSnapshot/maximumSendIntervalMilliseconds`` measures the interval between successful UDP dispatch starts using the injected monotonic clock. ``VoiceMediaPipelineSnapshot/sendIntervalOverrunCount`` counts intervals strictly longer than forty milliseconds. Failed sends do not replace the previous successful dispatch instant. Secure admission revocation and speaking-off clear that instant, so a later talkspurt does not count intentional stopped time. Complete encoded packets, PCM packets and termination silence share these send observations; long encoded packets and DTX can intentionally exceed forty milliseconds.

The aggregate counters and maxima survive ``VoiceMediaPipeline/close()``. Sampling starts no tasks and changes no scheduling policy. These local observations can distinguish an expensive encoder from delayed dispatch, but cannot establish UDP receipt, listener audibility or a hard realtime guarantee. An application measuring source starvation must separately observe its bounded source queue.

### Own one cancellation-aware playback source

`VoiceSession.play` consumes a Sendable AsyncSequence with a Sendable iterator. The source must cooperate with cancellation. A bounded PCMFrameStream from DiscordMedia can feed a device/file producer, but its upstream queues still need independent budgets.

On normal completion, the session sends five securely transformed 20ms Opus silence frames and clears Speaking. Source cancellation or disappearance closes the session. Session shutdown cancels and awaits its one owned playback task; it cannot forcibly interrupt arbitrary noncooperative user code.

### Inject a fresh fixed-format encoder

``VoiceSession/init(credentials:webSocket:makeDatagram:e2ee:clock:configuration:encoder:now:makeEncoder:)`` accepts an optional synchronous encoder factory. Existing calls retain the default owned Swift 48-kHz stereo CELT encoder. When supplied, the factory takes precedence over the value encoder argument and creates an exclusive `DiscordVoiceCodecs.OpusPCMEncoding` owner when secure media configuration begins. Native reference state must be newly allocated for each invocation; a lock does not turn shared codec history into separate streams.

The media pipeline freezes the encoder's initial mono/stereo layout and 120/240/480/960-sample duration. Each complete result must retain that geometry, use consistent transmission/DTX flags and fit a declared allocation through 1,276 bytes. ``VoiceMediaPipelineError/invalidEncoderOutput`` rejects malformed, oversized, over-budget or geometry-changing output before RTP/crypto state is consumed. Codec and pacing work may already have advanced; supervised playback treats the error as terminal and closes its owners.

The existing ``VoiceSession/play(_:)`` lifecycle, source cancellation, readiness suspension, silence termination and generation fences remain responsible for injected encoders. ``VoiceMediaPipeline/close()`` resets its exclusive encoder exactly once; the implementation releases any native allocation when that owner is deinitialized. Choosing a native encoder adds no package dependency or platform backend to DiscordKit by itself. Applications link and qualify their own implementation separately, including optimized frame timing under actual host load.

### Authenticate before jitter and codec state

Authenticated Ready/Speaking controls establish SSRC-to-participant bindings. RTP packets cannot create membership. The receive path checks peer and payload type, authenticates transport bytes, opens complete E2EE frames and admits only validated ordinary Opus. Unknown sources, tampering, replay and malformed input yield no plaintext delivery.

Every registered source has independent bounded jitter and decoder state. ``VoiceJitterBuffer`` reorders with wrapping RTP sequence arithmetic and explicit missing-slot output. ``VoiceMediaPipeline`` additionally caps aggregate streams and buffered bytes. Register sources from authenticated signaling and remove them on authenticated departure; a removed source's late async result cannot recreate it.

### Pace playout and record with consent

Call `playout(ssrc:)` at the intended sample cadence. ``VoicePCMPlayout`` contains normalized 48-kHz PCM, a concealed flag and authenticated encoded Opus when a packet exists. A missing slot invokes PLC; its encoded recording value is nil rather than fabricated compressed bytes. Optional playback and recording sinks are caller-owned bounded consumers, and their suspension does not block protocol heartbeats.

```swift
import DiscordVoice

/// Obtains one caller-paced slot without inferring recording consent or retention policy.
func nextPlayout(
    ssrc: UInt32,
    pipeline: VoiceMediaPipeline<ContinuousClock>
) async throws -> VoicePCMPlayout? {
    try await pipeline.playout(ssrc: ssrc)
}
```

Recording permission, user consent, storage format, retention and file I/O are application policy. Bound encoded storage separately from jitter buffers. Statistics expose aggregate counts and bytes without media, addresses or participant labels.

Test reorder, duplicate/replay, wrong peer/source, loss bursts, DTX gaps, stream replacement, stalled sink, revoked readiness, canceled source and exact queue caps. The [offline Voice example](https://github.com/CarsonAurum/DiscordKit/tree/main/Examples/VoiceBot) and local qualification harness use synthetic media; real Discord, physical duplex, perceptual quality and independent cryptographic review remain separate evidence.
