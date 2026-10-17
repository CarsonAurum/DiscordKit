# Media and voice protocol foundations

Verified and locally added **2026-10-17**. This is the first release of the
multi-release [Part 12 plan](../.air/plans/phase-12-execution.plan.md), with four
independently adopted products. **Complete Discord voice is not implemented.**
No `VoiceSession`/`VoiceManager`, owned Opus encoder/decoder, MLS group, DAVE
backend or native device adapter is shipped yet.

## Products and ownership

| Product | Implemented behavior | Dependency boundary |
| --- | --- | --- |
| DiscordMedia | Rational nonnegative time, bounded PCM/audio/video values, PCM16 conversion, gain/mixing, basic per-block linear resampling, RMS gate and finite immediate-pull queue | Foundation; no codecs/network/platform capture |
| DiscordVoiceCodecs | Owned RFC 6716 ordinary Opus packet parser: all four packing codes, CBR/VBR sizes, padding, TOC mode/bandwidth/stereo/duration and frame ranges | Media; no native Opus library, entropy decoder or encoder |
| DiscordVoiceCrypto | XChaCha20-Poly1305, owned HChaCha20, public AES256-GCM, experimental truncated AES128-GCM adapter and actor-owned RTP-size packet protection | Existing Swift Crypto and its public CryptoExtras product |
| DiscordVoice | Bounded Voice v8 JSON/binary frames/opcodes, pure handshake/heartbeat/resume reducer, main-Gateway join rendezvous, discovery, RTP framing, Opus packetization and reorder window | Core/Models/Transport and the three media products; no Client/Gateway/facade ownership |

Constructors start no I/O or tasks. A caller drives each reducer, clock, transport
and cleanup boundary. HTTP, Gateway, Client and the umbrella do not depend on the
voice products. The narrow join inputs use existing immutable Gateway dispatch
models; owning the main client is unnecessary. The [VoiceBot example](../Examples/VoiceBot/README.md)
exercises an offline encoded packet round trip without connecting to Discord.

## Media and Opus limits

PCM uses finite normalized interleaved floats, mono/stereo, 8–192 kHz and at most
120 ms per block. PCM16 little-endian conversion handles every signed sample,
including the asymmetric -32768/+32767 bounds. Mixing and gain clip to the
normalized range. Linear resampling is explicitly per block with no anti-alias
filter or cross-block phase history; it is not a production bandlimited resampler.
The RMS gate is an energy threshold, not speech classification, AEC or denoising.
Queue writes reject overflow without partial retention; immediate reads return
nil for an empty queue, with caller-owned scheduling and completion observation.

The Opus parser applies the [RFC 6716 framing rules](https://www.rfc-editor.org/rfc/rfc6716#section-3),
the [RFC 8251 padding correction](https://www.rfc-editor.org/rfc/rfc8251#section-4)
and the [inline errata](https://www.rfc-editor.org/rfc/inline-errata/rfc6716.html).
Packets are capped at 65,536 bytes, frames at 1,275 bytes, and total duration at
120 ms (5,760 samples per channel at 48 kHz). Zero-byte frames are legal. Frame
ranges exclude packing headers/padding. Structural acceptance cannot validate
compressed SILK/CELT data, produce PCM, qualify FEC/PLC or imply codec conformance.

Encoded video values retain opaque codec/keyframe/dimension metadata only. No
video codec, RTP video packetization, fragmentation, Go Live or camera signaling
is implemented. H.265 and further layer metadata remain subsequent work.

## Transport encryption and RTP

The current [voice reference](https://docs.discord.com/developers/topics/voice-connections)
uses **Voice Gateway v8**, independently of main Gateway/REST v10. It requires
`aead_xchacha20_poly1305_rtpsize` and prefers `aead_aes256_gcm_rtpsize` when offered.
Deprecated XSalsa modes are rejected. A 32-byte negotiated transport key protects
the packet body with a unique 32-bit incremental counter appended in network order.
The counter is placed first in the expanded nonce and followed by zeros. RTP
sequence and timestamp rollover must never reset this cryptographic counter.

`RTPPacket.authenticatedHeaderLength(in:)` splits the fixed header, CSRCs and
optional four-byte extension preamble from the encrypted body. Extension content
and RTP padding stay inside encryption. Authenticate before parsing their lengths,
routing decoded media or inserting packets into `VoiceJitterBuffer`. This buffer
has a finite byte budget and a window below half the RTP sequence space; its
caller-paced pop explicitly reports missing packets without manufacturing PCM.
Resetting playout never resets replay state. `VoiceDiscovery` validates the
74-byte response and SSRC; the socket owner must separately validate its UDP peer.

`OpusRTPPacketizer` validates packet duration, increments sequences and 48 kHz
timestamps only on success and supports the documented five termination-silence
frames. It neither encrypts nor transmits. RTP uses payload type 120. Speaking
state must be announced before actual media; that network orchestration is not
part of this release.

`VoiceTransportCipher` is an actor so copied Swift values cannot duplicate its
transmit nonce allocator. All producers sharing a session key must share that
owner. Never construct another sender with the same key or reset a key's nonce
space; this local actor cannot police cross-process reuse. Counter reservation
precedes encryption, including failures; exhaustion requires a fresh key.
Receive replay windows retain 64 counters per authenticated SSRC with a configured
stream limit, no silent eviction and no state advancement on failed authentication.
Close drops key references and metadata; Swift/Crypto storage is not guaranteed
to be securely erased. Diagnostics redact keys, credentials, payloads and endpoints.

The [expired XChaCha draft revision 03](https://www.ietf.org/archive/id/draft-irtf-cfrg-xchacha-03.html)
supplies HChaCha and full AEAD known-answer vectors. The truncated AES128-GCM
adapter uses public AES block permutation for private candidate decryption and
public full-tag GCM resealing to recompute authentication; candidate plaintext
does not escape unless its eight-byte tag is accepted. It does not implement MLS,
DAVE ratchets, verification-attempt limits or nonce ownership. NIST vectors and
negative tests exercise the adapter, but **external independent crypto review,
compiler timing analysis and protocol usage-limit review remain open**.

## Control and E2EE gates

The main-Gateway `VOICE_STATE_UPDATE` and `VOICE_SERVER_UPDATE` rendezvous accepts
either arrival order and matches guild/user/channel plus a caller-carried local
generation. Replacement/leave/null endpoint invalidates old state. The Gateway
wire itself carries no local generation, so the integration owner must associate
incoming events with its current join and enforce timeout/cancellation ownership.

`VoiceGatewaySessionState` is a pure protocol reducer, not a running session. It
uses HELLO's heartbeat interval, exact v8 `seq_ack` values, matching ACK nonces and
explicit reconnect/resume/close state transitions. Callers schedule deadlines and close
sockets. Valid DAVE controls for the negotiated version suspend media and are
surfaced to a backend. Different-version transitions, downgrade or malformed
protocol-version fields close the reducer and require replacement; automatic
version migration is not implemented. Other DAVE fields and MLS bytes remain
opaque for backend validation. A separately
implemented `VoiceE2EEReadiness` backend must validate actual epoch, membership,
external sender, version, keys, transitions and the full guild/user/channel/session
identity plus generation. A matching generation alone cannot authorize another
session. No such production
backend is included. DAVE version zero fails closed.

Discord's [E2EE requirement](https://docs.discord.com/developers/topics/voice-connections#end-to-end-encryption-dave-protocol)
took effect for eligible conversations **2026-03-01**. Transport encryption cannot
replace DAVE. MLS 1.0/ciphersuite 2, sender ratchets, frame transformations and
identity verification remain required work. Unknown introduction/announcement
dates are recorded as unknown; local implementation dates are separate.

## Validation and remaining release gates

The deterministic suites use synthetic packets, published primitive vectors and
no live credentials. They cover PCM boundaries, malformed Opus/RTP, extension and
padding splits, both AEAD modes, tamper/replay, concurrent nonce allocation,
cancellation, byte/stream limits, counter exhaustion, generation fencing and
heartbeat/resume/E2EE suspension. They establish local component behavior only.

MLS/DAVE/Opus interoperability, an owned supervised network/media pipeline,
microphone/playback adapters, all non-macOS platforms, minimum-OS testing, authorized
Discord voice smoke, a ten-minute lossless duplex run and per-frame p99 budgets
remain open. No production voice, video, cross-platform or fleet-capacity claim
follows from this release. See [source fingerprints](Parity/voice-media-current-sources.json),
[chronological parity](Parity/changes/2026-10-17-voice-media.md) and
[capability inventory](Parity/voice-media-capabilities.json).
