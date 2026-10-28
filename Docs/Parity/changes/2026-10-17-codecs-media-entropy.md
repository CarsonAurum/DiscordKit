<!--
File: Docs/Parity/changes/2026-10-17-codecs-media-entropy.md
Created by Carson Rau.
Copyright (c) 2026 Aurum Studios.
https://aurum-studios.com
-->

# Media streaming and Opus entropy prerequisites

Verified **2026-10-17**. Full codec/device qualification remains separate;
see the [voice guide](../../Voice.md).
Upstream introduction/announcement/effective dates are unknown for the grouped
media APIs; local dates do not substitute for them. The unchanged Discord Voice
protocol remains v8, with an Opus 48kHz RTP clock.

Previously Media had immediate polling queues and per-block resampling;
VoiceCodecs had ordinary packet framing. This change adds terminal-aware bounded
PCM iteration/sinks, cross-block linear resampling, exact sample/media clocks,
caller-driven monotonic pacing and opaque H.265/spatial/temporal metadata.
Existing polling queues and representation-based MediaTime equality retain their
contracts; numeric comparison is explicit. Adding `.h265` requires downstream
exhaustive MediaCodec switches to handle that case. The video initializer's layer
defaults to nil, preserving existing calls. No video wire support is established.

The owned range coder follows [RFC 6716 sections 4.1/5.1](https://www.rfc-editor.org/rfc/rfc6716.html)
and [verified erratum 4853](https://www.rfc-editor.org/errata/eid4853). It includes
exact contexts, symbol/bit/uniform/raw operations, termination and forward zero
extension/backward raw overlap. Context storage is densely owned; frame bytes,
frequency totals, symbols and coding operations have explicit bounds. Invalid
arguments preserve state; frame/corruption failures make the instance unusable.
Encoder finalization is terminal.

Independent fixtures and a reproducible differential verifier use official
[libopus 1.6.1](https://opus-codec.org/release/stable/2026/01/14/libopus-1_6_1.html),
published 2026-01-14. Its archive fingerprint is in the [source record](../voice-media-current-sources.json).
Only an opt-in development tool compiles the separately supplied archive; product
and ordinary test builds never fetch or link it. The six fixtures record bytes
and range/whole-bit/eighth-bit state after each operation, including carry and raw
overlap. These are not [RFC 8251 decoded-PCM conformance vectors](https://www.rfc-editor.org/rfc/rfc8251.html#section-11).
The [entropy validation report](../codecs-entropy-validation.json) ties the
2,000-stream run to exact owned-source/fixture/compiler/Python fingerprints.

SILK/CELT/hybrid audio processing, PLC/FEC, speech classification, bandlimited
resampling and native audio device routing/lifecycle implementation remain absent.
Other-platform/minimum-OS/device qualification, full codec conformance and duplex/
frame-budget gates remain unrun. Existing crypto/MLS/DAVE/session limits are unchanged.

The reviewed media group stays partial. The [capability inventory](../voice-media-capabilities.json)
keeps full codecs/native devices unsupported. Adopt components explicitly, respect
capacity/cleanup rules, and distinguish empty polling reads from terminal sequence
EOF. See [Voice](../../Voice.md).
