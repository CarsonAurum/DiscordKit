# Phase 12 execution: initial media and voice protocol release

Started **2026-10-17** from the clean Phase 11 tree. The master roadmap explicitly
requires separate releases and conformance gates for 12A–12E. This first release
implements portable media, Opus packet structure, transport crypto and deterministic
voice protocol components. It does **not** complete Part 12 or provide a runnable
Discord voice session. The remaining implementation and qualification work below
stays in scope for subsequent releases.

## Plan

1. Reverify current Voice Gateway v8, binary/DAVE opcodes, RTP-size AEAD, UDP
   discovery, RTP and Opus framing. Record source fingerprints independently of
   historical discovery pins. Keep negotiated DAVE integers separate from document versions.
2. Add independent Media, VoiceCodecs and VoiceCrypto products with real bounded
   implementations. Keep REST, Gateway, Client and the umbrella free of these dependencies.
3. Implement bounded PCM/time/frame values, PCM16 conversion, gain/mixing, basic
   linear resampling and RMS detection; implement all Opus packing formats without
   implying that a framing parser encodes or decodes SILK/CELT.
4. Compose public Swift Crypto AEAD/AES primitives into owned XChaCha and an
   experimental truncated-tag adapter. Serialize transport nonce allocation,
   reject authentication failures/replays, bound receive streams and stop at exhaustion.
5. Implement RTP/extension/padding framing, Opus RTP counters/silence, discovery,
   reorder windows, generation-fenced join rendezvous and a pure Voice v8 reducer.
   No media authorization without separately validated nonzero DAVE state.
6. Test positive/boundary/malformed/cancellation/concurrent cases and published
   vectors. Build a separate offline VoiceBot consumer, run root build/tests and
   inventory/generation/parity/tooling checks, audit documentation and commit.

## Release boundary and next work

This table records the initial release boundary. The subsequent
[12A execution record](phase-12a-execution.plan.md) tracks streaming media and
entropy-coder additions; the complete owned codec/device milestone remains open.

| Roadmap package | This release | Remaining implementation and required evidence |
| --- | --- | --- |
| 12A media | Bounded portable values, PCM queue/processing, complete ordinary Opus packet framing | Owned range coder, SILK/CELT/hybrid encoder/decoder, official codec conformance vectors, PLC/FEC, streaming resampler, AEC/noise/AGC, paced AsyncSequence sources/sinks, device adapters and permissions/interruption/hot-unplug behavior |
| 12B crypto/MLS | XChaCha/HChaCha, AES256-GCM RTP-size, truncated AES128-GCM recomputation adapter, published primitive vectors | Independent external cryptographic review, implementation timing/usage-limit analysis, MLS binary codec/credentials/key packages/TreeKEM/key schedule/proposals/commits/Welcome/authentication/removal/recovery and interoperability vectors |
| 12C DAVE | Binary envelope admission and conservative transition suspension | Actual MLS backend, sender ratchets, transition coordination, identity verification, Opus/video frame transforms, replay/epoch/key-expiry behavior and interoperability |
| 12D sessions | Pure v8 reducer, main-Gateway rendezvous, discovery codec, RTP/Opus packetizer and bounded reorder buffer | Supervised per-guild network session/manager, socket ownership, deadlines/retries, SSRC/user routing, encode→DAVE→RTP pipeline, playback/recording, real local duplex and authorized Discord smoke |
| 12E Social/video | Opaque video metadata only | Public signaling/auth evidence, exact codec/provider work packages, multiple Social calls and controls, actual negotiated video send/receive; native SDK-only contracts remain blocked |

The RFC packet parser and low-level AEAD vectors do not establish Opus codec
conformance or MLS/DAVE interoperability. Injected E2EE readiness is an integration
boundary with no production backend in this release. Never advertise DAVE support
because a test validator succeeds. Discord requires E2EE for eligible voice since
**2026-03-01**; no transport-only downgrade fallback is implemented.

The ten-minute lossless duplex run, p99 below each frame duration on reference
hardware, zero library underruns/resource growth, independent crypto audit and
per-platform device qualification remain **not run**. No live Discord credentials,
calls, microphone/camera access or device permission prompts are part of validation.

## Validation record

Validated on **2026-10-17**, macOS 27.0.1 (26A434), arm64, Swift 6.4
(`swiftlang-6.4.0.34.1`). These results establish local component behavior only.

- Root `swift build` passed. The final complete `SWIFTNIO_STRICT=1 swift test`
  run passed **1,540 tests in 180 suites across 26 targets**, including **65 new
  test methods** for media, Opus framing, cryptography and voice protocol components.
  The final run used `--skip-build` after the same sources had compiled in the
  preceding full invocation.
- An intermediate full invocation stalled in the unchanged HTTP target and was
  interrupted. Its five pending test methods passed together in an isolated run;
  the subsequent complete strict run passed all targets. No HTTP source was changed
  and the cause of that transient wait remains unproven.
- `Tools/DiscordKitTools` passed **93 tests in 7 suites**. Its Python discovery
  suite passed **10 tests**. Inventory validation passed with **18,137 entries,
  280 sources, no unclassified entries, 931 reviewed entries and 249 mapped
  endpoints**. The three new reviewed groups remain explicitly partial.
- Explicit `generate --write` changed only two documentation artifacts; the
  generated runtime Swift files stayed unchanged. Final `generate --check`
  confirmed all five artifacts byte-identical, and `parity check` passed.
- The independent VoiceBot package built and ran offline: five synthetic Opus
  packets authenticated and drained across RTP counter rollover. Its selected
  compilation graph excludes HTTP, Gateway, Client, Cache, OAuth, Interactions,
  Commands, NIO and concrete network adapters. All seven resolved pins match the
  root package; no package version was changed.
- JSON syntax, capability source/test references, documentation links, method
  documentation and the final diff were reviewed. Source review added regressions
  for full E2EE connection identity, malformed IPv6 discovery addresses, dense
  packet ownership and authenticated-buffer indexing.

Sandbox-only default cache and CryptoExtras assembler temporary-file failures
required isolated writable caches and host build access. Validation used
`--disable-sandbox` with those caches; no live Discord service or device was used.
The codec, cryptographic audit, MLS/DAVE, session, platform and hardware gates above
remain open despite the passing local checks.
