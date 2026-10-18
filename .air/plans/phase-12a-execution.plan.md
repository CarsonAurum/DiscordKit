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

## Further codec and routing implementation

The repeated request to finish **all of 12A** retains the original completion
gate. The latest [dated record](../../Docs/Parity/changes/2026-10-17-phase12a-codec-routing.md)
adds real codec components and explicit Apple routing; it does not close the
remaining full-codec or per-platform/device requirements.

1. Implement owned bounded low-overlap CELT MDCT/IMDCT and streaming overlap at
   all four internal frame sizes, mono/stereo. **Implemented**, with independent
   scalar libopus comparisons and exact unquantized 120-sample delay checks.
2. Implement projected/greedy CELT pulse search, exponential spreading, short-block
   occupancy and normalized entropy reconstruction. **Implemented** for admitted
   single-codeword bands; recursive splitting remains open.
3. Implement SILK LPC stability/analysis/synthesis, five-tap LTP and exact Q23
   excitation/seed reconstruction. **Implemented** as independently adopted
   primitives; full syntax, parameter quantization and orchestration remain open.
4. Implement macOS exact UID input/output routing and supported mobile input
   preferences with bounded discovery/readback/cleanup. **Implemented**; watchOS
   preferred input and non-macOS arbitrary output selection are explicit public
   API limitations. Actual device/permission/hot-unplug evidence remains open.
5. Preserve the remaining SILK/CELT/hybrid, PLC/FEC, official decoded-PCM and
   Windows/Android implementation gates. They are **not completed** by this
   increment and cannot be inferred from passing component or cross-SDK tests.
6. Validate root/tooling/example graphs, pinned independent oracles, generation,
   parity and complete staged diff, then commit with the incomplete milestone
   explicit. **No advance to 12B.**

### Final validation of codec/routing components

Validated **2026-10-17** local macOS time (tooling audit **2026-10-18 UTC**),
arm64 macOS 27 / Apple Swift 6.4. This is component evidence, not full 12A completion.

- Final root build passed. Complete `SWIFTNIO_STRICT=1 swift test` passed
  **1,681 tests in 196 suites across 26 targets**, including **39 new methods**.
  Required existing loopback/Unix tests passed with host access after sandbox-only
  bind failures; fresh canonical temporary caches avoided a preexisting `/tmp`
  versus `/private/tmp` module-cache collision. No production source fix was
  inferred from those environment failures.
- Tooling passed **93 tests in seven suites**. Python passed **53 tests**,
  including 21 new hermetic component-verifier tests. Explicit regeneration changed
  only two reviewed documentation artifacts; all five generated artifacts passed
  byte-identity, inventory and parity checks. Offline inventory counts remain
  18,137 discovery records, 280 sources, 931 reviewed definitions and 249 mapped
  implemented endpoints, without a full API parity claim.
- Official libopus component comparisons passed **2,016 band-shape**, **244
  transform** and **1,116 SILK prediction/excitation** cases. Reports record
  source/fixture/compiler/verifier fingerprints and exact/tolerance boundaries;
  all current source fingerprints were checked. They do not establish official
  full-codec decoded-PCM conformance. Existing entropy/PVQ code is unchanged.
- The final Apple routing graph passed **25 selected-module SDK emissions**
  at all five minimum Apple targets. **26 Apple audio methods** pass locally;
  real device permissions, microphone/playback and route changes remain unrun.
- VoiceBot built and ran offline, checking exact filtered duration, VAD, spectral
  shape/entropy, 120-sample transform delay, predictor inversion and five encrypted
  RTP rollover packets. Its selected graph still excludes HTTP/Gateway/Client/
  Cache/OAuth/Commands/Interactions/concrete adapters. Package pins are unchanged.
- Independent source/claims reviews checked math, bounds, atomicity and lifecycle.
  They strengthened maximum excitation assertions, corrected occupancy wording,
  and added paired native-device readback after both selection and startup to
  detect coupled-node rebinding. Documentation links, JSON references, source
  fingerprints and final whitespace/scope were reviewed.

The full codec, PLC/FEC, conformance, Windows/Android adapters and hardware/corpus/
realtime gates listed above remain required. **12A is not complete.**


## Compressed audio implementation continuation

The next request is again **finish Phase 12A in full**, including implementation,
validation and a commit. The working tree was clean at `b6f82ad`. The entire
completion gate above remains in force; none of the following component work
changes the meaning of that gate or advances 12B.

1. Implement ordinary CELT coarse/fine/final energy syntax, allocation/reservations,
   recursive mono/stereo shape syntax and frame-header contexts. Preserve exact
   integer entropy decisions and independently compare against pinned libopus.
2. Implement complete SILK pulse entropy, frame-parameter contexts, stabilized
   NLSF reconstruction and exact fixed-point NLSF-to-LPC conversion. Compose
   channel reconstruction where the scalar predictor/history contracts are known.
3. Close the Apple selected-device startup liveness race and test atomic observer
   installation rollback, concurrent callbacks, restart fencing and teardown.
4. Extend the bounded probability model to 257 entries for the maximum triangular
   theta context. Retest prior entropy/PVQ/band outputs after that shared change.
5. Validate each complete implementation using independent fixtures and seeded
   differential checks, then run root build/strict tests, the offline example,
   tooling/Python tests, explicit generation, inventory/parity and staged scope
   checks. Record full-codec and hardware gates separately from passing components.

Windows/Android SDK bundles, hosts and devices are unavailable on this macOS
host. No microphone, speaker, permission prompt or Discord call is used by
deterministic validation. Native host qualification cannot be inferred from
cross-SDK compilation. Full encoder/decoder composition, mode transitions,
PLC/FEC and official decoded-PCM conformance remain tracked until implemented
and independently passed.

### Compressed-audio result and final validation

Implemented ordinary CELT frame/packet encoding and decoding, including complete
header/energy/allocation/shape/synthesis composition and atomic packed-frame
admission. The basic encoder selects long blocks, normal spreading and explicit
storage; it provides no perceptual VBR/transient/pitch analysis. Implemented mono
SILK packet decoding through exact 48-kHz PCM16, VAD/LBRR skipping, all ordinary
packing forms and owned resampling at a fixed internal NB/MB/WB rate. Duration
changes preserve history. The Apple startup race and atomic observer rollback
are covered by injected property/listener tests.

Validated locally **2026-10-17** (machine reports use actual UTC **2026-10-18**):

- Root build passed; final complete `SWIFTNIO_STRICT=1 swift test` passed **1,774
  tests in 211 suites across 26 targets**, including **93 new test methods**.
  Permitted host access was used for existing loopback/Unix adapter tests after
  sandbox-only bind failures; no Discord or audio-device calls occurred.
- Tools passed **93 tests in 7 suites**; hermetic Python discovery passed **124
  tests**. Explicit regeneration changed two reviewed documentation artifacts;
  all five artifacts then passed nonwriting byte identity. Inventory/parity passed
  with 18,137 discovery records, 280 sources, 931 reviewed definitions and 249
  mapped implemented endpoints. These offline counts do not establish API parity.
- Fresh pinned scalar libopus comparison passed **1,036 CELT sequences / 4,086
  frames / 5,746,560 PCM samples**, in both directions, with exact final ranges
  and maximum absolute float PCM error **8.38e-7**. It exercised 2,636 transient,
  201 silence and 373 postfilter frames. This is ordinary-path interoperability,
  not the official full conformance corpus or perceptual qualification.
- Mono SILK comparison passed **133 streams / 1,055 packets / 1,721,760 exact
  PCM16 samples**, including **325 skipped redundant frames**, all rates/durations,
  packing, silence and successive duration changes. Redundancy was not recovered.
- Independent component checks passed pulse 1,443, parameters 2,414, NLSF 2,030,
  channel synthesis 1,393 frames, energy 2,033, allocation 2,097 (plus 2,097 unrelated
  decoded frames), headers 2,078 (plus 2,078 unrelated frames), recursive shapes
  6,058, all-band/anti-collapse 1,070 and synthesis 8,943 frames. Shared entropy,
  PVQ and band oracles were rerun after the 257-symbol extension. Current reports
  fingerprint owned sources/fixtures/verifiers; previous Apple reports remain historical.
- Apple liveness/routing and its dependency graph passed **25 selected-module
  emissions** at the five minimum Apple SDK targets. This remains compile-only;
  device, permission, hot-unplug and minimum-OS runtime qualification did not run.
- VoiceBot built and ran offline: 1,920 filtered PCM frames, actual owned CELT
  packets yielding 2,880 samples, a reference SILK packet yielding 480 exact samples,
  and five authenticated RTP rollover packets. Its independent graph and package
  pins are unchanged. No native codec runtime or package dependency was introduced.
- Independent cross-reviews checked bounds, history/atomicity, entropy, malformed
  input, API/docs and evidence claims. They clarified actual silence-header bit
  accounting versus the reference's virtual EOF advance; final ranges/PCM agree.

**12A is still incomplete.** Required work includes full SILK/hybrid encoding,
SILK stereo/internal-rate changes, hybrid/mode transitions/redundant mixing,
PLC/CNG-after-loss/FEC/DTX, official complete decoded-PCM conformance and quality/
realtime qualification. Windows/Android audio adapters and all native device
qualification remain open. No scope gate was waived and 12B has not advanced.

## Full-milestone closure pass

The user again requested all of 12A, including implementation, validation and a
commit, from clean `f6306c5`. The original milestone gate remains authoritative.
The implementation is being advanced in parallel without substituting another
component milestone for completion:

1. Complete ordinary SILK stereo, mid-only transitions, mono/stereo and internal
   rate changes; retain exact scalar PCM and shared arithmetic state for hybrid.
2. Implement inverse SILK parameter entropy and bounded real PCM encoders; compose
   mono/stereo SILK with CELT in a common hybrid frame and independently decode
   owned packets using pinned libopus.
3. Implement actual CELT periodic/noise concealment, safe energy prediction after
   loss, packet-level loss admission and reference lost/recovered streams.
4. Implement ordinary hybrid decoding with shared entropy, bounded redundancy
   storage and normative transition mixing; verify both bandwidths/layouts.
5. Continue remaining SILK loss/CNG/FEC and full mode transitions; run official
   decoded-PCM conformance rather than infer it from component interoperability.
6. Preserve required native Windows/Android routing and per-host/device gates.
   The macOS host has Apple SDKs only; Windows/Android hosts/SDKs/devices are not
   available. Do not add empty adapters or claim hardware qualification.
7. Run root strict build/tests, independent codec comparisons, offline consumer,
   tools/Python/generation/parity, source/evidence/diff audit and commit with exact
   achieved scope and every remaining gate explicit.

The master roadmap assigns echo cancellation, noise reduction and automatic gain
to 12E, so this pass does not pull those later DSP policies into 12A based on the
earlier execution table's overly broad shorthand. No advance to 12B is implied.


### Closure-pass validation and completion boundary

The connection interruptions preserved the implementation; work resumed from the
same diff rather than restarting. Local validation completed on **2026-10-17**
(machine evidence uses actual UTC **2026-10-18**):

- Root `swift build` passed. Final `SWIFTNIO_STRICT=1 swift test` passed **1,825
  tests in 224 suites across 26 test binaries**, including the full native operation
  fixtures, voiced/FEC encoder regressions and 768 seeded arbitrary-payload
  admissions. Host access was used for existing loopback/Unix socket fixtures;
  tests used no live credentials or device capture/playback.
- All twelve official RFC 8251 streams at both fixed output layouts passed
  `opus_compare` and exact nonzero final-range/sample-count checks: **40,150
  packet decodes / 46,171,440 scalar samples**. The complete report fingerprints
  the compiled source snapshot; no full encoder-quality or hardware claim follows.
- Generalized SILK: **313 streams / 3,336 packets / 7,924,320 exact PCM16 values**.
  Independent SILK normal/loss/CNG/FEC comparison: **313 streams / 9,053 operations /
  21,063,840 exact PCM16 values**, including 4,668 concealed and 1,161 FEC selections.
- Owned SILK encoding covers real voiced pitch/LTP, exact synthesis-feedback
  excitation and optional prior-active-channel LBRR. Native comparisons cover
  72 format/policy streams, bounded budget rejections, actual selected LBRR and
  subsequent ordinary decoding. Exact current packet/recovery counts are retained
  in phase12a-silk-encoder-validation.json.
- Hybrid comparison passed in both directions: 128 native packets / 138,240 samples,
  and 256 owned packets / 276,480 samples across both bandwidths/layouts/durations
  and false/true FEC. Native selected-FEC checks covered 64 operations, including
  32 present LBRR selections; compressed ranges match exactly.
- Unified ordinary mode ownership passed eight independent streams / 370 operations /
  528,120 PCM values, including loss/FEC and both redundancy directions. Ordinary
  maximum error is 1.23e-7; paths invoking periodic PLC use the separately declared
  scalar CELT loss tolerance. RFC8251 mono-output phase-inversion and hybrid FEC
  final-range fixes have literal independent regressions.
- CELT packet loss passed 206 sequences / 5,022 frames / 3,553,080 samples with
  3,065 withheld packets; raw PLC and spectral channel-conversion comparisons also
  passed with explicit report-specific floating tolerances. Component reports
  preserve exact arithmetic versus tolerance-qualified PCM distinctions.
- VoiceBot built and ran offline through bounded media, actual CELT/SILK/hybrid,
  unified transitions/conceal/recovery and five authenticated RTP rollover packets.
  No native codec dependency, new package dependency or adapter graph was selected.
- Tools passed 93 tests in seven suites; Python discovery passed 158 tests.
  Explicit generation updated the reviewed documentation, then all five outputs
  passed byte identity. Inventory/parity checks retain 18,137 discovery entries,
  280 sources, 931 reviewed definitions and 249 mapped endpoints; these counts
  do not certify complete API parity. The final diff/whitespace audit is clean.

**Phase 12A remains incomplete.** Required Windows/Android native microphone and
playback adapters are unimplemented; actual target-library/header probes and
concrete WASAPI/AAudio/JNI prerequisites are recorded in the native platform audit.
Apple permission/routing/interruption/hot-unplug device qualification also remains
open. Download availability does not establish a working native execution path.
Encoder analysis remains conservative (no reference delayed-decision shaping,
perceptual CELT transient/VBR/prefilter search or DTX policy), and perceptual/corpus/
realtime/device qualification is not inferred from native numerical agreement.
The original completion gate was not waived; no advance to 12B is implied. The
commit records the implemented and validated scope without labeling it full 12A.


Final fixture audit: raw CELT frame fixtures/report were refreshed against the
actual pinned scalar library build (37 sequences / 138 frames / 214,560 samples,
maximum owned/native error 3.61e-7). Different reference compiler flags changed
native encoder decisions; fixed inputs and owned bytes/ranges were unchanged.
Both affected Swift interoperability tests passed. The late owned-hybrid LBRR
fixture adds eight independently expected streams (16 selected recoveries), all
passing strict 3e-6 PCM/range checks; the earlier full 1,825-test run is supplemented
by this focused fixture test. No production source changed after the full run.
