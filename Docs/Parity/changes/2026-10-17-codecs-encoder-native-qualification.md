<!--
File: Docs/Parity/changes/2026-10-17-codecs-encoder-native-qualification.md
Created by Carson Rau.
Copyright (c) 2026 Aurum Studios.
https://aurum-studios.com
-->

# Encoder policies and native Apple qualification

Verified **2026-10-17**. Windows/Android platform implementations are excluded
from these results. Codec quality, Apple runtime, MLS and voice-session qualifications
require separate evidence.

Protocol remains Opus RFC 6716 with RFC 8251 corrections, 48kHz timing, Voice
Gateway v8 and RTP v2. Official voice/change-log references were checked on
2026-10-17; this change adds local codec/device behavior rather than a new Discord
endpoint. Upstream announcement/effective dates for these grouped codec operations
are unknown. The Opus encoder is nonnormative; interoperable syntax and decoder
conformance do not establish reference encoder quality.

## Implementation

- `OpusAudioEncoder` independently owns normalized 48kHz PCM conversion, fixed
  SILK/CELT/hybrid format, fractional bitrate accounting, atomic target updates,
  hard complete-packet caps and optional in-band FEC. Bounded RMS/hangover DTX
  omits transmission with ordinary refreshes at most 400ms apart. Analysis continues
  during suppression; receiver PLC/CNG need not reproduce discarded reconstruction.
- Adaptive CELT analysis uses masked temporal onsets, true short MDCTs, correct
  frequency/block ordering and anti-collapse. Rate/spectral trim selects ordinary
  allocation syntax. Fixed defaults preserve existing independently adopted APIs;
  the new top-level owner chooses adaptive analysis. Low budgets retain long blocks.
- SILK arithmetic storage is minimized before explicit Opus padding fills the
  target. Previously unused payload bytes could signal false CELT transition
  redundancy. SILK pitch search now excludes the 18ms upper endpoint, which could
  emit an out-of-range lag index. Rate admission tries at most 64 gains for the
  selected model and, if voiced coding cannot fit, up to 64 unvoiced gains. Seven
  final scalar rate-distortion candidates favor sparse unvoiced pulses, including
  zero pulse indices, at the initial unvoiced gain: at most 135 quantizations per
  channel/frame. All retries retain the input frame and VAD state, requested FEC
  obligation, exact decoder synthesis feedback and hard byte/bit ceiling; failure
  advances neither stream nor caller entropy. Sparse excitation can materially
  reduce fidelity. The measured external speech excerpt at 32kbps mono produced
  4.61dB delay-aligned waveform SNR, leaving a low-rate quality limitation rather
  than establishing perceptual acceptance.
  Exhausted shared CELT intervals reject without advancing histories.
- The opt-in Apple executable separates no-I/O discovery, permission requests,
  real local codec duplex, route changes, selected-device removal and interruption
  observation. It records failures explicitly. Root tests never open devices.

Construction starts no tasks, device access or network I/O. New codec APIs retain
value ownership, synchronous caller serialization and whole-operation rollback.
No native codec runtime or package dependency was added. Automatic mode selection,
reference delayed-decision noise shaping, perceptual equivalence, multistream and
enhancement extensions remain outside the supplied encoder policies.

## Reproducible evidence

The [verification guide](../../VoiceVerification.md) describes exact archive
admission, normal tests and opt-in measurements. Separate reports retain source,
fixture, verifier, compiler, hardware, input and tolerance fingerprints. Official
uncompressed speech/music excerpts remain external and are never committed.
Waveform SNR is diagnostic; no MOS or listening-panel acceptance is inferred.

The [adaptive CELT report](../codecs-celt-adaptive-validation.json) covers 292
sequences/1,162 frames/1,596,000 compared PCM values, including 553 owned transient
frames, exact final ranges and maximum absolute error 1.013e-6. Its six fixture
streams/30 frames reproduce byte for byte from the pinned scalar build.

The [encoder-policy report](../codecs-encoder-policy-validation.json) passes 28
synthetic/external cases with maximum ordinary independent PCM error 2.35e-7.
Four additional FEC/DTX replays pass eight selected-LBRR and four suppressed-PLC
recoveries, with maximum recovery error 6.4e-8 and exact final ranges. All 46 owned
source hashes and the verifier match the final codec source. Selected fixed 20ms
formats/rates and separately bounded recovery tolerances are recorded explicitly;
broader formats in unit tests are not silently treated as independent native cases.

The same optimized sequential run measures ten warmup frames followed by reset.
No other heavy validation or device run overlaps its measurement. Across 28 cases,
maximum sample round-trip p99 is 9.521ms. The external unmodified official sample
excerpts produce these diagnostics (five seconds plus 60ms silent tail):

| Input/layout | Mode/total bitrate | Delay-aligned waveform SNR | Encode/decode p99 |
| --- | --- | --- | --- |
| Speech/mono | SILK 32kbps | 4.61dB | 6.295ms |
| Speech/mono | Hybrid 64kbps | 10.48dB | 7.351ms |
| Speech/mono | CELT 64kbps | 21.65dB | 0.879ms |
| Music/stereo | SILK 64kbps | 11.96dB | 9.521ms |
| Music/stereo | Hybrid 128kbps | 29.94dB | 6.114ms |
| Music/stereo | CELT 128kbps | 33.12dB | 1.667ms |

SNR uses bounded delay alignment without gain fitting. These values show a
material low-rate SILK speech limitation, not a perceptual pass threshold or
reference encoder equivalence. Timing excludes device/resampling/scheduling,
offers no worst-case realtime guarantee and applies only to the recorded host.

Fresh [complete RFC8251 decoding](../codecs-encoder-conformance-validation.json)
passes all 12 official streams at both output layouts: 24 cases, 40,150 packets,
46,171,440 scalar samples and zero range mismatches. The report records no source
or verifier drift. It qualifies ordinary decoding only, independently of encoding
quality or native device behavior.

Final deterministic validation passed root `swift build` and strict SwiftNIO
`swift test`: 1,849 tests/228 suites across 26 test binaries. Existing local socket
fixtures used local loopback; none used Discord credentials or audio I/O.
Tools passed 93 Swift tests/seven suites, Python passed 173 tests, and VoiceBot built
and ran offline. Explicit generation was followed by inventory validation,
nonwriting byte identity for all five artifacts and parity checks. Offline counts
remain 18,137 discovery entries/280 sources/931 definitions/249 mapped endpoints;
these counts do not certify complete API parity. The standalone qualification
support suite separately passes 10 tests, including admission/cancellation/timeout
boundaries. Runner-specific native cleanup and partial-counter paths also received
independent code review; not every native API failure is injected by those tests.

Native permission, routing, interruption, hot-unplug, device duplex, minimum-OS
runtime and all-Apple-device qualification are separate observations. A failed
run is retained as failed; callback counts alone do not measure hardware underruns.
Windows/Android implementations remain deferred by the user's explicit scope.

## Observed Apple checks

The actual host is macOS 27.0.1 (build 26A434); native machine timestamps are UTC
2026-10-18, while this work is dated 2026-10-17 in the local session. The
[initial permission/startup report](../codecs-apple-permission-startup-failure.json)
records microphone authorization changing from undetermined to granted. That
explicit-device startup then failed before I/O, exposing the shared duplex binding
bug fixed in this change. It is retained as a failed run.

The [physical route check](../codecs-apple-route-validation.json) started native
capture and observed the operator change the default input from an iPhone to the
MacBook microphone. The adapter stopped with `routeChanged`, discovery verified
the actual default change, and queues were cleared. The
[selected-device removal check](../codecs-apple-unplug-validation.json) started
with explicit MacBook microphone/AirPods output, observed the operator disconnect
the AirPods, stopped with `routeChanged` and verified the selected UID had left
the native catalog. Both checks passed their specific physical-action criteria;
neither is relabeled as an interruption test.

Those fault-run binaries mistakenly retained the initial `audioPath: No device
I/O` description. Their mode, `nativeIOStarted`, observed stop and actual catalog
changes record native capture/discard with no audible playback. The original
reports and their fingerprints are preserved; the tool description is corrected
for future runs.

The earlier [debug duplex attempt](../codecs-apple-duplex-debug-failure.json)
failed after 485.44s: 3,360 capture drops, 17 playback rejections, 7,200 codec deadline
misses and an unexpected configuration stop. It ran without optimization and
alongside device diagnostics. It supplies no ten-minute or realtime qualification.
The selected Apple modules also passed
[25 cross-SDK emissions](../codecs-apple-directional-cross-sdk.json) at all five
declared Apple minimum targets; this is compile-only evidence.

Native reports fingerprint runtime source files and the executable, detect source
changes during observation and omit UIDs and captured samples. They do not attest
compiler inputs or fingerprint every dependency/manifest. Evidence review checks
provenance separately from the runner's count/timing/cleanup `passed` flag.

The isolated optimized [ten-minute duplex report](../codecs-apple-duplex-release-validation.json)
records 600s, 28,800,000 captured/processed samples, zero capture drops or unexpected
stops and cleared queues. It **failed** its unchanged strict gate: 33 playback
admission rejections and five codec wall-time calls at or above 20ms. Actual played
samples total 28,768,320 (599.34s). Codec p99 was 3.3ms and maximum 37.04ms across
30,000 frames; this excludes resampling/scheduling/device rendering. Native RSS
was sampled 61 times, initially 22.6MB, with 19.7MB minimum and 37.0MB maximum/final;
these process observations establish no leak or resource-growth guarantee.
Runtime source drift was false. The native path used the fixed-analysis component
encoder with 161-byte/20ms packets (64kbps payload, 64.4kbps including TOC), separate
from the adaptive top-level policy benchmark. It recorded no captured samples.

Playback rejection exposed a runner admission error: after a full native queue it
discarded the already encoded frame instead of applying caller-owned backpressure.
The follow-up uses bounded cancellation-aware admission waits before consuming
another frame; all wait/timeouts and actual rejections remain visible. This does
not reinterpret the recorded failure as success. Missing hardware render-underrun
telemetry keeps `losslessDuplexQualified` false even for passing count/timing runs.

## Completion boundary

**Full codec and platform qualification remains open.** Windows/Android
implementations are excluded by the user's scope. The encoder/Apple implementation
changes and deterministic checks above are delivered, but the optimized 600s device
run failed and the corrected admission runner requires another operator-ready
native observation. No unperformed rerun is counted as passing. True Apple
interruption, minimum-OS/mobile behavior, hardware render-underrun evidence and
perceptual acceptance remain open; low-rate SILK speech has a measured fidelity
limitation. No reference delayed-decision/noise-shaping equivalence, production
voice is claimed. MLS/DAVE/network-session qualifications remain separate.
