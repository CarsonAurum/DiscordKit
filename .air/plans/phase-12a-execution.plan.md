# Phase 12A execution: portable media and owned codecs

Started **2026-10-17** from clean commit `1cb6ca6`. The requested target is the
**entire 12A milestone**. This record does not redefine its completion gate:
the implemented changes are prerequisites and **12A remains incomplete**.

## Plan and status

1. Preserve independent Media/VoiceCodecs adoption, deployment minima, Swift 6.4
   concurrency and dependency policy. No codec runtime is linked or vendored.
2. Implement terminal-aware bounded PCM AsyncSequence/sink ownership, cancellation,
   continuous resampling, exact media/sample clocks, caller-driven pacing and
   opaque codec/layer metadata. **Implemented with deterministic tests.**
3. Implement the owned range encoder/decoder from RFC 6716 sections 4.1/5.1 with
   verified erratum 4853. Bound frame storage, contexts and coding operations;
   compare every arithmetic/accounting state and output byte with an independent
   official oracle. **Implemented with independent entropy fixtures.**
4. Implement SILK parameter contexts/tables, excitation, LPC/LTP/synthesis,
   stereo/rate conversion and encoder analysis/quantization. **Unimplemented.**
5. Implement CELT band energies/allocation, PVQ, MDCT/overlap, pitch/postfilters,
   stereo and encoder analysis/quantization; compose hybrid/mode transitions,
   redundancy, PLC and in-band FEC. **Full codecs remain unimplemented.** Exact
   bounded signed integer PVQ enumeration is implemented as a separate prerequisite.
6. Run official RFC 8251 decoded-PCM vectors, all supported rate/channel/mode
   combinations and exact final-range checks. Add bandlimited conversion/speech
   VAD qualification; linear interpolation/RMS gating do not supply those claims.
   **Full codec implementation and conformance remain open.**
7. Implement actual Apple/Windows/Android microphone/playback routing, permission,
   interruption and hot-unplug handling; preserve injected Linux PCM. Qualify
   each adapter on its platform/devices. **Apple system-route capture/playback is
   partially implemented; explicit device selection and Windows/Android adapters
   remain unimplemented.** Native hardware qualification has not run. A portable
   injected controller alone would not fulfill this requirement.
8. Validate implemented components, build/run the offline consumer, regenerate
   reviewed docs, run root/tooling/parity checks, review and commit the full diff
   with the incomplete milestone explicit.

## Implemented contracts

- PCMFrameStream owns one shared FIFO with fail-fast writes, one parked iterator
  and terminal-only EOF. Iteration cancellation finishes/discards the stream.
- PCMStreamingResampler carries rational phase and exact aggregate floor counts,
  retaining one input frame plus at most one deferred output frame. Output blocks
  stay within 120ms. Linear interpolation has no antialias filter; finish/reset
  release retained history.
- MediaTime conversion/comparison uses full-width integers. PCMSampleClock rejects
  rollover atomically. PCMFramePacer carries fractional nanoseconds in an injected
  monotonic clock, queues no waiters and commits intervals only after successful
  waits. Consumers own lateness/drop decisions.
- H.265/spatial/temporal labels are opaque metadata, not codec or signaling support.
- Opus probability models and range encoder/decoder implement symbols, binary
  probabilities, uniform integers, raw tails, termination, zero extension and
  exact range/bit accounting. They contain no SILK/CELT audio syntax or PCM codec.

## Evidence and remaining qualification

Six committed fixtures originate from unmodified official **libopus 1.6.1**,
published 2026-01-14. The separately supplied archive has SHA256
`6ffcb593207be92584df15b32466ed64bbec99109f007c82205f0194572411a1`.
The opt-in offline verifier reproduces the fixtures and compares 2,000 mixed
streams using seed **67168251**, every-step range/whole-bit/eighth-bit state and
final bytes at minimal frame lengths. External sources/objects stay in temporary
storage and are never fetched or linked by consumer builds or normal tests.
This is entropy evidence, **not official full-codec conformance**.

Native codec/device implementation, full conformance, other-platform/minimum-OS
qualification and frame-budget/ten-minute duplex evidence remain open. No live
Discord call or device permission prompt is part of local validation.

## Validation record

Validated **2026-10-17**, arm64 macOS 27.0.1, Apple Swift 6.4
(`swiftlang-6.4.0.34.1`). These are local component checks, not milestone completion.

- Root `swift build` passed. Complete `SWIFTNIO_STRICT=1 swift test` passed
  **1,596 tests in 186 suites across 26 targets**, including **56 new test methods**.
  Sandbox-only socket bind failures in the first run were resolved by running the
  complete suite with permitted host loopback/Unix-socket access. Writable temporary
  caches and `--disable-sandbox` handled default-cache restrictions.
- Tools passed **93 tests in 7 suites**; Python discovery passed **23 tests**,
  including 13 new hermetic verifier tests with no archive/compiler/network dependency.
- Explicit `generate --write` changed only the two reviewed documentation artifacts.
  All five final artifacts passed `generate --check`; inventory and parity checks
  passed with 18,137 discovery records, 280 sources, 931 reviewed definitions and
  249 mapped implemented endpoints. These are offline counts, not API-parity claims.
- The independent VoiceBot package built and ran offline, checking exactly 1,920
  resampled PCM frames, synthetic entropy symbols and five authenticated silence
  packets across RTP rollover. Its selected runtime graph still excludes HTTP,
  Gateway, Client, Cache, OAuth, Commands, Interactions and concrete network/device
  adapters. Root/example resolved pins remain unchanged.
- The opt-in official entropy unit/fixture/differential checks passed all six
  fixtures and **2,000 streams** with seed 67168251. The committed
  [evidence report](../../Docs/Parity/phase12a-entropy-validation.json) records source,
  fixture, compiler and Python fingerprints; it explicitly excludes full codec conformance.
- Independent source review checked continuation cleanup, relative resampling state,
  integer overflow and entropy boundaries. It found/fixed retained excess probability
  array capacity and added a regression. Method docs, source/evidence references,
  generated output and the staged whitespace/scope were reviewed before commit.

## Continuation toward the complete milestone

The 2026-10-17 prerequisite audit found 12A incomplete. The user explicitly selected
**Complete all of 12A**; 12B remains pending. The original full completion gate
above remains authoritative. This continuation does not redefine it.

1. Add an independently adopted finite windowed-sinc streaming converter with
   exact duration/phase and bounded lookahead; test alias/image rejection, chunk
   invariance, extreme ratios and ownership.
2. Add a statistical multi-feature speech detector with adaptive background,
   per-channel decisions and bounded hangover; document synthetic-only accuracy
   evidence and remaining real-speech/corpus qualification.
3. Implement exact CELT signed pulse enumeration and range-coder composition;
   compare official libopus codewords independently. This is a codec building
   block, not a complete CELT encoder or decoder.
4. Add real Apple capture/playback engine ownership behind a deterministic test
   backend, explicit permission/session policy, bounded callbacks and fail-closed
   interruption/route/configuration handling. Construction starts no device work.
5. Continue SILK/CELT/hybrid encoder/decoder, synthesis/analysis, band allocation,
   transforms, PLC/FEC and official decoded-PCM conformance. These remain required.
6. Complete explicit native device selection and Windows/Android implementations;
   qualify Apple/Windows/Android devices, permissions and hot-unplug on their hosts.
7. Run root build/tests, offline consumer, independent primitive checks, tooling,
   generation/parity, cross-SDK checks where available, and diff/scope audit before
   committing. Record any remaining gate explicitly; do not advance to 12B.

### Continuation validation and remaining work

Validated **2026-10-17**, arm64 macOS 27, Apple Swift 6.4. This remains a
prerequisite increment toward the full milestone, which is **not complete**.

- Root build passed. The complete final `SWIFTNIO_STRICT=1 swift test` suite passed
  **1,642 tests in 190 suites across 26 targets**, including **46 new test methods**.
  The sandbox denied existing adapter socket binds; permitted host loopback/Unix
  access resolved those failures. Final validation used the same writable temporary
  caches and `--disable-sandbox`; the final full run reused rebuilt test binaries.
- Tools passed **93 tests in 7 suites**; Python passed **32 tests**, including nine
  hermetic PVQ-verifier tests. Explicit generation changed two documentation artifacts;
  all five artifacts then passed byte-identity, inventory and parity checks. Inventory
  counts remain 18,137 discovery records, 280 sources, 931 reviewed definitions and
  249 mapped implemented endpoints; these offline counts do not establish API parity.
- Official libopus 1.6.1 PVQ verification passed **2,260 cases**: 40 literal fixtures,
  220 boundary cases across all 22 ordinary dimensions/exact official pulse maxima,
  and 2,000 seeded random admitted codebooks. Counts, vectors, ranks, entropy bytes
  and decoded integer vectors match. The report fingerprints owned/upstream sources,
  fixture file, archive, compiler and seed; it explicitly excludes decoded-PCM/full
  codec conformance. No native codec source enters a product or normal tests.
- Apple audio and its Bits/Core/Transport/Media graph compiled in **25 selected-module
  emissions** against macOS13/iOS16/tvOS16/watchOS9/visionOS1 SDK targets. The
  compile-only report records exact targets/settings/source hashes. Native permissions,
  microphones, audible playback, interruption/hot-unplug and min-OS runtime remain
  unqualified. No Windows/Android SDK, host or device is available here.
- VoiceBot built and ran offline with exact 1,920-frame filtered output, silence VAD,
  synthetic entropy/pulse checks and five authenticated rollover packets. Its selected
  runtime graph remains independent of ApplePlatform/concrete adapters and HTTP,
  Gateway, Client, Cache, OAuth, Commands and Interactions; resolved pins are unchanged.
- Independent reviews checked all new source/tests, bounds, phase/count arithmetic,
  PVQ ordering, actor/callback ownership and claims. They found and resolved tvOS
  permission availability, native notification teardown, same-format macOS default
  route monitoring and startup observer ordering. Final scope/whitespace checks passed.

Still required: owned SILK/CELT/hybrid full encoding/decoding, analysis/synthesis,
band allocation/splitting/transforms, PLC/FEC, official decoded-PCM conformance,
complete device selection, Windows/Android adapters and per-host/hardware/corpus/
realtime evidence. Cross-SDK compilation and synthetic fixtures do not close these
requirements. **12B remains pending.**
