<!--
File: Docs/Parity/changes/2026-10-17-codecs-compressed-audio.md
Created by Carson Rau.
Copyright (c) 2026 Aurum Studios.
https://aurum-studios.com
-->

# Compressed audio and device startup

Verified **2026-10-17**. Ordinary compressed-audio paths have component-level
conformance evidence. Complete codec, platform and device qualification remains
separate; see the [voice guide](../../Voice.md).

## Upstream and compatibility

- Opus remains [RFC 6716](https://www.rfc-editor.org/rfc/rfc6716), with
  [RFC 8251](https://www.rfc-editor.org/rfc/rfc8251), applicable errata and ordinary
  48-kHz packet/RTP timing. There is no wire version change. Upstream introduction,
  announcement and effective dates for these grouped codec algorithms are unknown.
- Verification uses the official [libopus 1.6.1 release](https://opus-codec.org/release/stable/2026/01/14/libopus-1_6_1.html),
  published **2026-01-14**. The separately supplied archive is pinned by SHA256
  `6ffcb593207be92584df15b32466ed64bbec99109f007c82205f0194572411a1` and byte count.
  Verifiers validate the archive and retain COPYING while compiling unmodified
  reference routines/library in temporary storage. Nothing is fetched by tests or
  products. No native codec runtime, source package or binary is added to the graph.
- Current official sources were reviewed **2026-10-17**. Machine reports record
  their actual UTC verification date, compiler, deterministic seeds and file hashes.
  Full decoded-PCM RFC conformance vectors remain a distinct unpassed gate.
- Existing framing, primitive and platform APIs remain compatible. Probability
  contexts now admit **257** symbols for the ordinary maximum CELT theta alphabet.
  Prior entropy/PVQ/band checks were rerun against the changed shared coder source.

## Previous and current behavior

Previously, entropy/PVQ, isolated transforms and LPC/LTP/excitation primitives could
not reconstruct ordinary compressed audio. New independent APIs now compose them:

- SILK pulse coding includes shell counts/splits, escape planes/sign contexts and
  mediumband 10ms padding. Frame parameters include gain, NLSF residuals/stabilization,
  pitch/LTP and seeds. Fixed-point NLSF conversion/interpolation/stability and channel
  synthesis retain exact bounded gain/LPC/output history across no-loss frames.
- `SILKMonoDecoder` reads ordinary mono NB/MB/WB payloads/Opus packets, VAD/LBRR
  headers and redundant syntax, then produces 48-kHz PCM16 through owned resampling
  and mono alignment. Payload duration can change between 10/20/40/60ms. Internal
  rate is fixed. Redundancy availability is reported without recovering lost audio.
- CELT includes segmented headers, coarse/fine/final energies, caps/allocation/skips,
  recursive mono/stereo/intensity shapes, TF/Haar/folding/noise, all-band balance and
  anti-collapse. Synthesis owns variable-duration short/long overlap, delayed pitch
  postfilters and deemphasis. Floating reconstruction is tolerance-qualified.
- `CELTFrameDecoder` composes ordinary no-loss compressed frames into 48-kHz PCM.
  `CELTFrameEncoder` encodes long-block PCM with explicit fixed storage and basic
  allocation policy. `CELTPacketEncoder` adds standard single-frame TOCs;
  `CELTPacketDecoder` handles every ordinary packing/padding form. Failed frames or
  multi-frame packets commit no stream state. Value copies own independent streams.
- Apple macOS startup now checks selected devices' liveness after observer install
  and engine start. Listener-registration failure removes earlier registrations in
  reverse order; late callbacks remain generation-fenced. This closes a tested
  startup race, without guaranteeing hardware remains present after readback.

Owned Swift adaptations of upstream tables/algorithms retain applicable BSD notices.
The FFT is independently implemented. See [dependency provenance](../../Dependencies.md).

## Evidence boundaries and remaining gates

The committed `codecs-*-validation.json` reports distinguish exact integer/entropy
comparisons, tolerance-qualified spectra/PCM, authentic compressed reference input,
seeded contexts and compile-only Apple SDK results. Literal reference fixtures run
under Swift Testing without an archive, C compiler, network or native codec runtime.
Hermetic Python tests enforce verifier counts, domains and mismatch rejection.

Still required: full SILK/hybrid encoding, SILK stereo/internal-rate changes,
hybrid/mode transitions and redundant mixing, packet-loss concealment, in-band FEC,
DTX/loss recovery, multistream where required, official complete decoded-PCM
conformance and perceptual/realtime qualification. The basic CELT encoder selects
long blocks without perceptual VBR, transient or pitch analysis. Independent
interoperability is evidence for the exercised ordinary paths only.

Windows/Android microphone/playback adapters remain unimplemented; their SDKs/hosts
and device qualification are unavailable here. Apple SDK compilation and deterministic
injected tests do not qualify permission prompts, microphones, audible playback,
hot-unplug or minimum-OS runtime. No live Discord request, microphone permission,
recording or playback occurred. MLS/DAVE and supervised voice sessions remain later
phases. The published-hardware frame-budget and ten-minute duplex gates remain open.
