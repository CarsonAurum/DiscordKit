# Voice primitive feasibility

Verified on 2026-10-15. This is a feasibility baseline for roadmap Part 0 and work breakdown for Part 12. DiscordKit implements no voice transport, codecs, MLS or DAVE yet. Passing these small public-API probes does not establish cryptographic interoperability or production readiness.

## Evidence and executed probe

The standalone [VoiceProbe package](../../Tests/Fixtures/VoiceProbe/Package.swift) adds no dependencies to the root library. Its lockfile resolves Swift Crypto **5.0.1** at `1c80d3aff53fedc445b60692980cb4f19a618657` and its Apple-origin transitive dependency Swift ASN.1 **1.7.3** at `3b6410f7dee09eb33cdd26260c5fd47fda19b0e2`. The official [Crypto release](https://github.com/apple/swift-crypto/releases/tag/5.0.1) was published 2026-10-12. Its [manifest](https://github.com/apple/swift-crypto/blob/1c80d3aff53fedc445b60692980cb4f19a618657/Package.swift) exposes `Crypto` and `CryptoExtras`; `_CryptoExtras` is retained upstream for compatibility and is unnecessary here.

Executed with Apple Swift 6.4 (`swiftlang-6.4.0.34.1`), arm64 macOS 27.0.1 build 26A434:

```sh
swift test --package-path Tests/Fixtures/VoiceProbe
```

All **5 Swift Testing tests / 10 parameterized invocations** passed. The first isolated source-path experiment passed, then the committed URL-based exact-version package resolved and passed independently. The final run also includes explicit nonisolated default isolation and ApproachableConcurrency. There were no live Discord calls, timing sleeps or user credentials. Tests use fixed test key/nonce fixtures where the API accepts them; HPKE internally generates an ephemeral sender key. No other operating system or device runtime was tested.

| Public API exercised | Observed result | Limit of the evidence |
| --- | --- | --- |
| `AES.GCM.seal/open`, AAD, `SealedBox` | 128-bit key round trip succeeds; wrong AAD fails; returned tag has 16 bytes; an 8-byte supplied tag is rejected | Does not implement DAVE's truncated-tag decryption |
| `ChaChaPoly.Nonce`, `seal/open` | 12-byte nonce succeeds, 0/8/24-byte nonce inputs fail, tampered tag fails | Does not supply XChaCha20 or HChaCha20 |
| `Insecure.ChaCha20CTR.Nonce` | 12-byte nonce succeeds; 0/8/24-byte inputs fail | An unauthenticated stream cipher is not an AEAD or HChaCha20 |
| `AES.permute` from CryptoExtras | FIPS 197 AES-128 known answer matches `69c4e0d86a7b0430d8cdb78070b4c55a`; 0/15/17-byte blocks fail | Only proves the public AES block primitive; no GHASH construction is tested |
| `HPKE.Ciphersuite(kem: .P256_HKDF_SHA256, kdf: .HKDF_SHA256, aead: .AES_GCM_128)` | Public Sender/Recipient round trip succeeds | Exact primitive tuple is callable; MLS is not implemented or certified |

Re-run on every promised platform before assigning runtime qualification. On this host SwiftPM initially could not write its default module cache and then could not nest its sandbox; the successful run used temporary cache/scratch paths and the environment's approved build escalation. These are tooling constraints, not protocol failures.

## Transport AEAD

Discord's [voice protocol](https://docs.discord.com/developers/topics/voice-connections) requires `aead_xchacha20_poly1305_rtpsize` support and describes `aead_aes256_gcm_rtpsize` as an alternative when available. Keep voice Gateway protocol version **8** separate from REST/Gateway version 10, transport mode names and the negotiated DAVE version. RTP header length, nonce construction, authenticated header ranges and packet counters belong to the owned transport layer; an AEAD round trip does not establish correct packet framing.

The pinned [ChaChaPoly implementation](https://github.com/apple/swift-crypto/blob/1c80d3aff53fedc445b60692980cb4f19a618657/Sources/Crypto/AEADs/ChachaPoly/ChaChaPoly.swift) fixes its nonce at 12 bytes and tag at 16. Source review found no public XChaCha20/HChaCha20 API in Crypto or CryptoExtras. [CryptoExtras ChaCha20CTR](https://github.com/apple/swift-crypto/blob/1c80d3aff53fedc445b60692980cb4f19a618657/Sources/CryptoExtras/ChaCha20CTR/ChaCha20CTR.swift) also accepts only a 12-byte nonce. It does not fill that gap.

Owned work: implement and independently review **HChaCha20**, then compose the XChaCha subkey and 96-bit nonce with public `ChaChaPoly`. Follow the [IETF XChaCha construction and test vectors](https://www.ietf.org/archive/id/draft-irtf-cfrg-xchacha-03.html): derive the subkey from the first 16 nonce bytes and use four zero bytes followed by the last eight nonce bytes for the underlying ChaCha nonce. This source is an expired Internet-Draft, not a final RFC; pin its revision and verify compatibility against Discord's selected construction. Test counter/nonce boundaries, malformed lengths, known vectors, authentication failure and tampering. Do not call internal BoringSSL symbols or import a transitive C target as if it were a supported Crypto API.

## Truncated AES-GCM tags

The pinned [AES-GCM public implementation](https://github.com/apple/swift-crypto/blob/1c80d3aff53fedc445b60692980cb4f19a618657/Sources/Crypto/AEADs/AES/GCM/AES-GCM.swift) requires 16 tag bytes when constructing a sealed box. Its public open API has no tag-size parameter. [CryptoExtras AES-GCM-SIV](https://github.com/apple/swift-crypto/blob/1c80d3aff53fedc445b60692980cb4f19a618657/Sources/CryptoExtras/AES/AES_GCM_SIV.swift) also fixes its tag size at 16 and uses a different construction; it is not a DAVE substitute.

DAVE's [frame-transform specification](https://daveprotocol.com/#truncated-authentication-tag) requires an **8-byte AES128-GCM authentication tag**. Standard sealing can produce the full tag and truncate it for transmission, but the public sealed-box API cannot authenticate the received truncated tag. Padding the missing tag bytes or decrypting through an unchecked escape hatch cannot satisfy authenticated decryption.

Owned work: a narrowly scoped truncated-tag GCM authenticator using public [AES block permutation](https://github.com/apple/swift-crypto/blob/1c80d3aff53fedc445b60692980cb4f19a618657/Sources/CryptoExtras/AES/Block%20Function.swift), owned GHASH, GCM's 32-bit counter increment/GCTR and constant-time tag comparison. Authenticate the AAD, ciphertext and lengths, enforce nonce/key/counter limits, and expose no plaintext on failure. CryptoExtras CTR mode is not assumed to have the same counter semantics as GCM. Require independent review plus published known-answer and negative vectors before claiming support. The current probe validates only the underlying AES block call and standard tag rejection.

## MLS and DAVE session state

[DAVE MLS parameters](https://daveprotocol.com/#mls-parameters) specify MLS 1.0, ciphersuite 2 (`DHKEMP256_AES128GCM_SHA256_P256`), basic credentials and a voice-Gateway external sender. The callable HPKE tuple above matches the required primitive components. Crypto also provides P-256 signing/key agreement, SHA-256 and HKDF. These primitives avoid implementing their cryptographic algorithms locally; they provide no complete MLS group implementation.

Owned work according to [RFC 9420](https://www.rfc-editor.org/rfc/rfc9420): TLS presentation-language encodings; credentials/key packages; TreeKEM and tree validation; MLS labels/transcripts/key schedules/secret trees; signed proposals, commits and Welcome; external proposals; membership/epoch transitions; exporter secrets; bounded pending state; authentication-service checks and recovery. DAVE additionally needs negotiated version handling, binary voice opcodes, participant identity validation, sender ratchets, transition acknowledgments and expiry/cleanup rules. Test these independently from the primitive API probes. MLS and media AES-GCM have different purposes and must not share unreviewed nonce/key state.

The whitepaper identifies itself as protocol text version 1.1 while its ciphersuite sections discuss protocol 1/1.0. Store the actual Gateway-negotiated integer separately; do not manufacture a wire version from the document heading. Discord's [change log](https://docs.discord.com/developers/change-log) announced E2EE enforcement for eligible sessions on **2026-03-01**. Older transitory-downgrade text in the whitepaper is not evidence that current voice can omit DAVE. Stage-channel and future protocol exceptions must be checked against their own current contracts.

## Codecs and media processing

Swift Crypto is not a codec or media engine. Under the approved dependency policy, author the portable Opus parser, encoder/decoder, range coder and SILK/CELT/hybrid work, PCM conversion/resampling/mixing, bounded buffers, jitter/pacing, gain/VAD and packet-loss handling. Use the [Opus specification](https://www.rfc-editor.org/rfc/rfc6716), its errata and updates, and separately obtained official conformance vectors. Those codec tests and performance measurements have **not** run in Part 0.

The pinned [Discord codec-transform source](https://github.com/discord/libdave/blob/8de72b1f8a2ac3c5a5270755bb8091a62e3c6169/cpp/src/codec_utils.cpp) has handlers for Opus, VP8, VP9, H.264, H.265 and AV1. It is protocol evidence only; no implementation is copied or linked. Frame transform/parsing, encoding/decoding, RTP packetization, video signaling, hardware providers and end-to-end Discord camera/Go Live behavior are separate capabilities. A working DAVE transform cannot certify a codec or a publishable video session. Concrete video codec/provider work remains gated on established negotiated signaling and format requirements.

## Release gate and remaining evidence

All voice functionality remains unsupported. Before a voice support claim, require public-protocol fixtures and vectors; malformed/tampered/replayed data rejection; independent crypto review; cancellation and resource cleanup; real negotiated send/receive on each advertised surface; per-platform codec qualification; frame-budget measurements and the roadmap's ten-minute duplex stability run. None of those results may be inferred from this probe's success. No Discord native runtime, prohibited package or handwritten cryptographic primitive was added in Part 0.
