<!--
File: Tools/AppleAudioQualification/README.md
Created by Carson Rau.
Copyright (c) 2026 Aurum Studios.
https://aurum-studios.com
-->

# Apple audio qualification

This separate macOS executable explicitly exercises real devices through
DiscordApplePlatform. Ordinary package tests never invoke it. It uses no Discord
credentials or network service, and writes no captured or decoded audio. The
executable embeds a microphone usage description; the responsible host app must
also allow microphone access under macOS privacy settings.
The executable sends SwiftLog diagnostics to stderr; JSON evidence goes to the required `--output` file.

Build with optimization before measuring frame budgets:

```sh
swift test --package-path Tools/AppleAudioQualification
swift build -c release --package-path Tools/AppleAudioQualification
swift run -c release --skip-build --package-path Tools/AppleAudioQualification AppleAudioQualification --output /tmp/apple-probe.json
```

Probe mode only enumerates copied endpoint metadata and reads authorization. It
opens no device and never requests permission. Indices are local to each direction
and may change between probes. Device UIDs and PCM samples are excluded from the
JSON report; human-readable endpoint names help the operator choose a route.

Run only when the operator is ready. Use headphones and a quiet monitoring volume;
the duplex path plays decoded microphone audio at gain **0.025**. Stop the process
if acoustic feedback occurs. Keep devices and system defaults unchanged throughout
the uninterrupted run. This example selects index zero independently for input/output;
omit the index flags to use current defaults:

```sh
swift run -c release --skip-build --package-path Tools/AppleAudioQualification AppleAudioQualification --mode duplex --seconds 600 --input-index 0 --output-index 0 --enable-device-io --request-permission --output /tmp/apple-duplex.json
```

The first microphone request may show a system prompt. `--request-permission` is
explicit and optional after authorization. Other native modes still require
`--enable-device-io`. Invalid/duplicate arguments fail before device access, and
duplex durations below 600 seconds are rejected.

The actual path is microphone capture, bandlimited mono conversion to 48 kHz,
owned 20 ms CELT encoding at a fixed 161-byte packet budget (64 kbps CELT payload,
64.4 kbps including the one-byte Opus TOC), owned Opus decoding,
attenuation, and native playback. No RTP, encryption, network loss, adaptive encoder
policy or live Discord session is involved. A pending input tail shorter than one
codec frame remains unencoded at stop; scheduled playback has a bounded two-second
drain. Capture and playback use separately bounded native queues.
Before consuming or encoding another frame, the runner respects native playback
backpressure with two-millisecond cooperative waits, bounded to 250 milliseconds
per admission. Wait counts, maximum wait and timeouts are reported separately.
A timeout or actual write rejection ends the failed run with partial measurements;
the runner does not discard encoded frames to keep capture moving. Cancellation
and codec/read failures likewise preserve partial counters and cleanup evidence.

Reports record actual capture/processed/played-buffer completion counts, capture
overflow, playback rejection, native invalidation, queue cleanup, a bounded codec
processing histogram and process RSS extrema. Codec timing covers synchronous
encode/decode only; resampling, read/write scheduling, rendering and OS latency are
excluded. RSS includes framework/system effects and is not a leak proof. Runtime
SHA256 fingerprints identify the source checkout and executable; preserve sources
between build and execution. A second source comparison detects changes during the
run. Runtime hashes are observed provenance, not compiler attestation.

`passed` assesses the documented local count/timing/cleanup checks. It requires
at least 99% of the requested capture/codec/played duration, nonzero microphone
energy, no admission drops/rejections/timeouts, no unexpected stop, no 20 ms codec deadline
miss, and empty queues after stop. **This cannot establish lossless audio delivery**:
AVAudioPlayerNode does not expose hardware render-underrun telemetry here, and
completion callbacks do not detect gaps between scheduled blocks. Every report
therefore preserves `nativeRenderUnderrunTelemetryAvailable: false` and
`losslessDuplexQualified: false`. Perceptual speech/music listening, acoustic latency,
minimum-OS/mobile runtime and live Discord qualification remain separate evidence.

Perform faults separately from the ten-minute run, with an operator taking the
physical action only after the observer has started:

```sh
# Change the system default input/output to another already connected device.
swift run -c release --skip-build --package-path Tools/AppleAudioQualification AppleAudioQualification --mode route --seconds 180 --enable-device-io --output /tmp/apple-route.json

# Physically disconnect the selected input or output (indices from a fresh probe).
swift run -c release --skip-build --package-path Tools/AppleAudioQualification AppleAudioQualification --mode unplug --seconds 180 --input-index 1 --output-index 0 --enable-device-io --output /tmp/apple-unplug.json
```

The observer opens native capture, discards audio and schedules no audible playback.
A native invalidation must clear queues; route mode additionally requires an actual
default-device change, and unplug mode requires removal of an explicitly selected
UID from the native catalog. Bounded metadata retries allow CoreAudio to finish
removing implicit engine aggregates during teardown. The runner never changes
global routing, posts synthetic notifications or automatically restarts a stopped
owner. A timeout or unrelated topology change cannot pass the intended check.

An interruption mode exists for explicit native interruption observations, but the
macOS backend has no AVAudioSession interruption signal. A route/configuration event
cannot be relabeled as one. Apple mobile permission/routing/interruption qualification
requires an appropriate native host/device and remains outside this macOS tool.
