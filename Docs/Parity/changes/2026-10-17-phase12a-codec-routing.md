# Phase 12A codec components and explicit Apple routing

Verified and locally added **2026-10-17**. This continues the requested full
[12A milestone](../../../.air/plans/phase-12a-execution.plan.md), which **remains
incomplete**. The previous [DSP/pulse/Apple release](2026-10-17-phase12a-dsp-apple-pvq.md)
had no transform, shape search, SILK reconstruction or explicit device selection.
This increment adds those components without substituting them for full codecs.
Voice Gateway v8, RTP 48kHz and package pins are unchanged. Upstream announcement,
introduction and effective dates for these grouped local APIs are unknown.

## Implemented behavior

- `CELTTransform` implements the [RFC 6716 section 4.3.7](https://www.rfc-editor.org/rfc/rfc6716#section-4.3.7)
  low-overlap MDCT/IMDCT with an independently implemented mixed-radix FFT.
  Frame sizes are 120/240/480/960 at 48kHz, mono/stereo. Plans and workspaces are
  bounded; `CELTTransformStream` owns analysis/synthesis overlap independently,
  supports atomic validation/reset and has exactly 120 samples of unquantized delay.
- `CELTBandQuantizer` composes the existing pulse codebook/range coder with
  projected/greedy pulse search, all four spreading levels, 1/2/4/8 short blocks,
  pulse-domain occupancy masks and normalized spectral reconstruction.
  Search/rotation adapts [official libopus 1.6.1 vq.c](https://github.com/xiph/opus/blob/v1.6.1/celt/vq.c);
  its BSD notice is retained in the Swift source. A band must fit one 32-bit
  uniform codeword; recursive splitting remains a required separate codec path.
- `SILKLinearPredictionCoefficients` provides bounded Q12 LPC validation and
  floating-point reflection/gain diagnostics. `SILKShortTermFilter` provides
  streaming analysis/all-pole synthesis with unclipped recursive history;
  `SILKLongTermSynthesisFilter` adds causal five-tap voiced residual prediction
  at all three internal SILK rates. Callers supply rewhitened/gain-normalized
  history. Floating reconstruction follows [section 4.2.7.9](https://www.rfc-editor.org/rfc/rfc6716#section-4.2.7.9);
  stability classification is conservative local policy, not the normative fixed-point test.
- `SILKExcitationReconstructor` implements exact signed-pulse adjustment,
  all six quantization offsets, modulo seed/sign updates and Q23 excitation from
  [section 4.2.7.8.6](https://www.rfc-editor.org/rfc/rfc6716#section-4.2.7.8.6).
  It does not decode pulse entropy or infer frame parameters.
- `AppleAudioDevice.availableDevices()` explicitly queries bounded native
  UID/name/direction metadata. macOS resolves exact input/output UIDs at start,
  binds the engine I/O AudioUnits and verifies both configured bindings after
  selection and startup. Device-alive/topology changes invalidate the owner.
  iOS/tvOS/visionOS support available preferred inputs with ownership-aware
  restoration. watchOS preferred-input and arbitrary non-macOS output selection
  fail explicitly. See [AVAudioIONode](https://developer.apple.com/documentation/avfaudio/avaudioionode),
  [CurrentDevice](https://developer.apple.com/documentation/audiotoolbox/kaudiooutputunitproperty_currentdevice),
  [preferred input](https://developer.apple.com/documentation/avfaudio/avaudiosession/preferredinput)
  and [QA1631](https://developer.apple.com/library/archive/qa/qa1631/_index.html).

All construction remains inert; portable products select no platform framework
or native codec dependency. The existing Apple configuration initializer remains
source-compatible through default nil UIDs. Selection errors never fall back to
another device; actual OS notification timing still cannot promise zero transient
rerouting. Applications retain permission/session ownership obligations. No device
is opened or permission requested by normal tests. The offline VoiceBot now checks
transform delay, a band-shape entropy round trip and predictor analysis/synthesis.
Those artificial spectral contexts are never represented as complete Opus packets.

## Independent evidence and reproduction

All native reference sources come from the separately supplied official libopus
**1.6.1** archive, SHA256
`6ffcb593207be92584df15b32466ed64bbec99109f007c82205f0194572411a1`.
Each opt-in verifier validates archive size/hash/member safety before compiling
unmodified sources in temporary storage with their notices intact. Consumer and
normal test builds never download, vendor or link libopus. The scripts and their
hermetic Python tests are committed; the archive and native objects are not.

```sh
python3 Tools/DiscordKitTools/scripts/verify_celt_band_oracle.py \
  --source-archive /path/to/opus-1.6.1.tar.gz --cases 2000 --report /path/to/bands.json
python3 Tools/DiscordKitTools/scripts/verify_celt_transform_oracle.py \
  --source-archive /path/to/opus-1.6.1.tar.gz --cases 200 --report /path/to/transforms.json
python3 Tools/DiscordKitTools/scripts/verify_silk_prediction_oracle.py \
  --source-archive /path/to/opus-1.6.1.tar.gz --cases 1000 --report /path/to/silk.json
```

The [band report](../phase12a-band-validation.json) records **2,016** cases:
16 committed fixtures and 2,000 seeded admitted bands, comparing exact signed
pulses, bytes, ranges, collapse masks and tolerance-qualified coefficients.
The [transform report](../phase12a-transform-validation.json) records **244**
cases: four complete float32 fixture pairs, 40 boundaries and 200 seeded inputs,
comparing every frequency bin and zero-state inverse sample. Maximum absolute
errors were approximately 1.6e-7 forward and 4.987e-5 inverse.
The [SILK report](../phase12a-silk-prediction-validation.json) records **1,116**
cases: 26 fixtures, 90 boundaries and 1,000 seeded streams. Unmodified official
LPC routines and full `decode_core.c` supply independent LPC/excitation results;
LTP is covered by separate analytical/full-history unit references.

The [Apple routing compile report](../phase12a-routing-compile-validation.json)
records 25 selected-module emissions at macOS13/iOS16/tvOS16/watchOS9/visionOS1
deployment targets, with exact Swift settings and current source hashes. It
does not establish complete-package or minimum-OS/device runtime qualification.

## Required remaining work

| Full 12A requirement | Current boundary and remaining work |
| --- | --- |
| Complete SILK encoder/decoder | LPC/LTP/excitation exist; parameter contexts/tables, NLSF conversion, pitch/gain/pulse decoding, encoder analysis/quantization, stereo/rate conversion and orchestration remain absent. |
| Complete CELT encoder/decoder | Transform and single-band shapes exist; energy quantization, bit allocation, recursive splitting, folding, stereo/theta, anti-collapse, transient handling, pre/de-emphasis and pitch/postfilters remain absent. |
| Hybrid/mode transitions | Complete SILK/CELT composition, redundancy, bandwidth/rate changes and state transitions remain absent. |
| Packet-loss handling | Jitter reporting exists; actual codec PLC and in-band FEC remain absent. |
| Official codec conformance | Component oracle fixtures are not the official RFC8251 decoded-PCM vectors or all-mode/rate/channel final-range conformance; that suite remains unrun. |
| Platform devices | Supported Apple routing is implemented but hardware-unqualified; Windows/Android implementations and per-host permission/interruption/hot-unplug tests remain absent. Linux PCM stays injected. |
| Quality/realtime | Real speech corpus, reference-hardware frame-budget/RSS and ten-minute lossless duplex evidence remain open. |

No `OpusEncoder`/`OpusDecoder` facade or completed milestone is advertised by
this change. The [RFC8251 conformance gate](https://www.rfc-editor.org/rfc/rfc8251#section-11)
and the existing full scope remain authoritative. **12B is not advanced.**

## Local validation

Final root build and the complete strict suite passed **1,681 tests in 196 suites
across 26 targets** on arm64 macOS 27 / Swift 6.4, including 39 new methods.
Tooling passed 93 tests; Python passed 53. Explicit regeneration changed only two
reviewed documentation artifacts; all five artifacts then passed byte-identity,
inventory and parity checks. The tooling audit date is **2026-10-18 UTC** while
the local implementation date remains **2026-10-17**; no historical `--as-of`
override was used. Offline counts do not establish API parity.

Final Apple audio coverage comprises 26 methods, including coupled-device and
startup-rebinding regressions. The offline VoiceBot built and ran without a device
or Discord connection. Default-cache collisions and sandbox-only socket bind
restrictions were handled with fresh canonical temporary caches, `--disable-sandbox`
and permitted host socket access. The passing local checks do not close any
remaining codec, hardware, other-platform or realtime gate above.
