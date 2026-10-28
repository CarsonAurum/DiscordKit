<!--
File: Docs/Parity/changes/2026-10-17-codecs-codec-loss-conformance.md
Created by Carson Rau.
Copyright (c) 2026 Aurum Studios.
https://aurum-studios.com
-->

# Ordinary Opus coding, mode ownership and loss recovery

Recorded **2026-10-17**. This continues the
[compressed-audio release](2026-10-17-codecs-compressed-audio.md), preserving its
historical evidence. Upstream announcement/effective dates for these normative
codec operations are **unknown**; local implementation dates do not establish them.
The protocol remains RFC 6716 with RFC 8251 corrections and 48,000Hz Opus timing.
Discord Voice Gateway v8, RTP v2 and transport encryption policy are unchanged.

## Resulting behavior

Previously the owned codec supported ordinary CELT and mono fixed-rate SILK
decoding, with explicit rejection of loss frames and no shared hybrid owner.
The following additions now compose actual compressed packets:

- Generalized SILK decodes coded/output mono/stereo, mid-only changes, predictor
  interpolation and internal NB/MB/WB rate changes. Mono output uses normative
  mid synthesis. Bounded scalar PLC, comfort noise, recovery glue and following
  packet LBRR selection preserve exact fixed-point synthesis state.
- Inverse SILK parameter entropy and bounded mono/stereo PCM encoders select
  quantized spectral/gain parameters, correlated pitch/five-tap LTP and exact
  synthesis-feedback excitation, and emit standard code-zero
  packets. Exact local reconstruction remains synchronized with native decoding.
  Shared entropy entry points leave the interval open for a following CELT layer.
  Optional LBRR carries preceding active channels in the following packet, bounded
  by the same configured budget; insufficient capacity fails atomically.
- Hybrid encoding combines resampled/delayed SILK and CELT bands 17 and above.
  Hybrid decoding preserves a common arithmetic interval, excludes separately
  coded redundant tails before backward raw-bit access and applies the normative
  five-millisecond CELT redundancy/fades.
- CELT owns periodic pitch/order-24-LPC concealment and shaped-noise fallback,
  retained loss histories and post-loss energy recovery. Coded/output channel
  conversion occurs before IMDCT. RFC 8251 phase inversion is disabled for mono
  output, including coded-stereo transition redundancy.
- `OpusAudioDecoder` coordinates all three modes, packed payloads, bandwidth/
  duration/channel changes, transition redundancy and squared-window fades.
  Explicit loss and subsequent-packet FEC are bounded to 120ms per call. Decode
  the following packet normally after recovering its preceding missing interval.
  Empty/one-byte payloads select prior-mode loss synthesis; cold loss emits zeros.

New value-type owners start no I/O or tasks; copying forks independent bounded
histories. Failed public operations commit no codec/entropy state. Unified/CELT/hybrid output
is fixed mono/stereo 48-kHz normalized float with unclipped finite peaks; SILK
owners separately return 48-kHz PCM16. No
native Opus runtime or new package dependency is introduced. Adapted source
retains upstream attribution; the reference C code remains a temporary development
input supplied separately to opt-in verifiers.

Existing primitive/packet entry points remain independently adopted. CELT packet
owners now conceal legal empty/one-byte frames instead of rejecting them. Raw
CELT frame entry points still require at least two bytes; callers choose explicit
loss behavior there. Existing fixed-mode owners retain their documented format
constraints; adopt `OpusAudioDecoder` for continuous mixed-mode streams.

## Independent evidence

All fixtures are public synthetic/reference data. No credentials, live Discord
requests, device capture or playback are used. Reports retain source/archive,
compiler, fixture and verifier fingerprints, exact counts and declared tolerances:

| Report in Docs/Parity | Boundary |
| --- | --- |
| codecs-silk-stereo-validation.json | Complete scalar PCM16 and arithmetic across ordinary generalized SILK streams |
| codecs-silk-loss-validation.json | Complete scalar normal/loss/CNG/FEC output and LBRR/accounting evidence |
| codecs-silk-encoder-validation.json | Owned PCM packets decoded independently, reconstructed PCM and budget rejection |
| codecs-hybrid-validation.json | Both native-to-owned and owned-to-native hybrid PCM/arithmetic |
| codecs-celt-synthesis-validation.json | Spectral conversion, IMDCT, overlap, postfilter and deemphasis |
| codecs-celt-plc-validation.json | Periodic/noise PLC pitch, envelopes, RNG and PCM |
| codecs-celt-packet-loss-validation.json | Compressed packets, burst loss and subsequent recovery |
| codecs-opus-audio-validation.json | Continuous ordinary modes, channel/rate changes, loss/FEC and redundant fades |
| codecs-opus-conformance-validation.json | All twelve complete official RFC 8251 streams at both output layouts |

The official corpus contains **40,150 packet decodes** and **46,171,440 output
scalar samples** across the 24 stream/layout runs. Acceptance requires every
nonzero expected final range, exact output length, complete stream consumption
and the official `opus_compare` rule from upstream `tests/run_vectors.sh`.
Both supplied reference variants are compared for each layout; either may pass.
This is ordinary 48kHz decoded-PCM conformance, without extension enhancement,
multistream/container, output gain or integer-output soft-clipping APIs.
See [verification commands and interpretation](../../VoiceVerification.md).

Exact integer/range comparisons are distinguished from floating PCM tolerances.
Repeated CELT PLC can amplify small transform differences through LPC; stress
reports expose sequence-peak/sample-scaled bounds and absolute maxima. The refreshed raw CELT frame fixture/report covers 37 current sequences / 138
frames / 214,560 samples. A separately built pinned scalar reference changed
native encoder decisions; all 36 fixed inputs and owned encoder bytes/ranges
remained unchanged. The current report records the actual reference library hash
and maximum owned/native error of 3.61e-7. Earlier larger-run evidence remains
historical. Reference numerical agreement is not a perceptual-quality or realtime-deadline measurement.
Root Swift Testing, the offline VoiceBot consumer, tooling, generation, inventory,
parity and Python checks validate the local graph within their recorded scope.

## Remaining qualification gates

Required Windows/Android native audio adapters
are still unimplemented. The [platform audit](../codecs-native-platform-audit.json)
records actual missing target standard libraries and AAudio/WASAPI headers,
available downloads and concrete implementation/test prerequisites. Apple native
permission, route, interruption and hot-unplug device qualification remains open.
Injected backend tests and cross-SDK emissions cannot substitute for those results.

Encoder analysis/rate policy remains conservative: fixed-format SILK/hybrid,
bounded spectral/excitation decisions and long-block CELT without perceptual
transient/VBR/prefilter search. Native reconstruction/interoperability does not
establish reference speech quality, corpus accuracy or realtime performance.
DTX policy, multistream or other negotiated requirements must be tracked explicitly
before claiming support for them. There is no network session, MLS/DAVE,
authorized Discord smoke, ten-minute duplex or broad hardware qualification.
Echo cancellation, noise suppression and automatic gain require separate processing
and device evidence.

Official sources: [RFC 6716](https://www.rfc-editor.org/rfc/rfc6716),
[RFC 8251](https://www.rfc-editor.org/rfc/rfc8251),
[Opus documentation and vectors](https://www.opus-codec.org/docs/),
[libopus 1.6.1 decoder](https://github.com/xiph/opus/blob/v1.6.1/src/opus_decoder.c),
[Discord voice reference](https://docs.discord.com/developers/topics/voice-connections)
and [Discord change log](https://docs.discord.com/developers/change-log).
