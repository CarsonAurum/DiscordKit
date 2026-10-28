<!--
File: Docs/Parity/changes/2026-10-17-voice-media.md
Created by Carson Rau.
Copyright (c) 2026 Aurum Studios.
https://aurum-studios.com
-->

# Initial media and voice protocol release

Verified **2026-10-17**. Voice Gateway is explicitly **v8**;
main Gateway/REST remain v10. RTP uses v2 and audio timestamps use 48 kHz.
The [current fingerprints](../voice-media-current-sources.json) preserve original
discovery pins; three new reviewed groups are explicitly **partial**. The
[capability inventory](../voice-media-capabilities.json) separates component code
from unsupported full voice/media products. Full voice qualification remains separate from these component results.

Previously voice had REST state/region operations, main-Gateway dispatches and
primitive feasibility probes. Independent Media/VoiceCodecs/VoiceCrypto/Voice
products now provide bounded PCM/time/frame values and processing, RFC 6716
ordinary Opus framing with RFC 8251 padding correction, AEAD compositions,
RTP/discovery/reorder, generation-fenced join rendezvous and a pure Voice v8
handshake/heartbeat/resume reducer. Existing HTTP/Gateway/Client/Kit do not select
voice. Constructors start no tasks or I/O.

The [voice reference](https://docs.discord.com/developers/topics/voice-connections)
requires XChaCha20-Poly1305 RTP-size support and prefers AES256-GCM when offered.
Deprecated XSalsa modes are rejected. Clear RTP headers include CSRCs and the
extension preamble; extension data stays encrypted. Counters never wrap within
a session key. Replays and failed authentication cannot advance receive state.
The [XChaCha revision 03 vectors](https://www.ietf.org/archive/id/draft-irtf-cfrg-xchacha-03.html)
and [NIST examples](https://csrc.nist.gov/CSRC/media/Projects/Cryptographic-Standards-and-Guidelines/documents/examples/AES_GCM.pdf)
exercise primitives; the expired draft is not a final RFC and passing vectors is
not an independent cryptographic audit.

The [change log](https://docs.discord.com/developers/change-log) introduced DAVE
documentation on **2024-09-17**, then announced non-E2EE call deprecation on
**2025-09-02**, effective **2026-03-01** for eligible conversations. Older downgrade
prose cannot establish permission to omit DAVE today. The reducer rejects version
zero and suspends media on DAVE changes. Its readiness contract requires actual
epoch/membership/external-sender/key validation; no production conformer is
provided. Opcode admission is not MLS/DAVE implementation. Other upstream
introduction dates remain unknown; local dates are never substituted for them.

Owned SILK/CELT/hybrid codecs, MLS/TreeKEM, sender ratchets, identity verification,
transition coordination, DAVE frame transforms, supervised sessions/pipelines,
device adapters and Social/video signaling remain unimplemented. The optional
truncated AES128-GCM adapter releases no candidate plaintext before tag acceptance,
but compiler timing, usage limits and external crypto review remain open.

Migration is additive: opt into the components and preserve their bounds. Never
reconstruct a sender with an existing key, parse encrypted padding/extensions
before authentication, or count synthetic validators as DAVE support. RTP wrap
does not reset AEAD nonces. VoiceBot runs offline with public test-only key material.

Deterministic suites use synthetic frames and published vectors without Discord
credentials or device access. All-host/minimum-OS builds, Opus/MLS/DAVE conformance,
independent crypto review, authorized Discord smoke, ten-minute duplex stability,
hardware p99/underrun/RSS measurements and real video negotiation remain open.
See [Voice](../../Voice.md) and the [technical guide](../../Voice.md).
