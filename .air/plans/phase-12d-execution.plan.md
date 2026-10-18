# Phase 12D execution: supervised voice sessions

Started **2026-10-18** from clean commit `0a33835`. Scope is the master roadmap's
12D voice control, packet transport and consumer API. Full release qualification
is tracked independently from local implementation; no test peer implies live
Discord, independent crypto review or device qualification.

## Plan

1. Reverify official Voice Gateway **v8**, heartbeat/resume/close policy, UDP
   discovery, Speaking/silence and required DAVE **v1**. Fingerprint current sources.
2. Reuse owned bounded UDP and WebSocket adapters. Add an inert `VoiceSession`
   supervising connection, handshake/ACK deadlines, finite resume attempts,
   discovery, transport keys, authenticated participant mapping and cleanup.
3. Add an account-scoped `VoiceManager` with bounded per-guild slots, either-order
   main-Gateway rendezvous, join/move/leave, timeout/cancellation, unique connection
   identities and immediate invalidation on credential replacement.
4. Add a bounded independent media actor for PCM/encoded Opus, pacing, complete
   frame E2EE, RTP, outer AEAD, SSRC jitter/PLC and receive/playback/recording.
   Keep heartbeat/control independent of user media sources and sinks.
5. Compose actual DAVE through injected protocols in Voice and the concrete
   `DAVEVoiceSession` in DAVE. Keep the existing DAVE -> Voice dependency direction,
   share signing identities and nonce authorities, prioritize bounded control
   admission, and fail closed across revocation, removal and recovery.
6. Add deterministic lifecycle/race/loss/reorder/duplicate/playback/source-removal
   tests and actual local UDP duplex qualification. Run root, tooling, generation,
   parity and example validation; review the full diff and commit the phase.

## Validation boundary

The separate localhost qualification executable measures actual paced UDP with
owned Opus, real two-member MLS/DAVE and transport AEAD. Synthetic PCM and local
signaling do not exercise a microphone, sound output, an independent complete
client, Discord's SFU or the main Gateway. The reference-hardware timing/RSS
report is retained separately from unit tests. Failure to meet a measured gate
must remain visible and cannot be relabeled as a pass.

Authorized Discord smoke requires application-owned credentials, explicit guild/
channel permission, expected participant identity keys and trusted external sender,
plus an approved peer. Those are not present in this checkout. Native hot-unplug
is separately qualified through the Apple audio harness; injected source failure
only establishes supervised cleanup. Independent crypto review, complete-peer/live
interoperability and platform/device gates remain open.

Final check commands and measured results are recorded in
[phase12d-validation.json](../../Docs/Parity/phase12d-validation.json) and
[VoiceSessions.md](../../Docs/VoiceSessions.md).

## Delivery and gate status (2026-10-18)

The software implementation and local validation steps are complete: root build,
2,046 strict Swift tests in 254 suites across 28 test targets, 93 tooling tests,
173 Python tests, offline VoiceBot build/run and inventory/generation/parity checks
passed. Final source and executable fingerprints remained unchanged throughout the
600-second real localhost UDP measurement. All 60,000 packets passed integrity,
57,600,000 sample frames decoded, no packets were concealed, and all reported
owners closed. Tick p99 was 18.473ms; three ticks exceeded 20ms. Actual resident
memory grew 4,702,208 bytes after warmup. Zero resource growth was not established;
no cause or CPU regression is inferred from wall-time/RSS observations.

**The full Phase 12D qualification is incomplete.** Authorized Discord smoke,
actual device hot-unplug/duplex telemetry, independent complete-client/crypto
qualification and the zero-resource-growth gate remain open. No local integrity
success substitutes for these gates. Raw failed/intermediate/final evidence is
retained rather than relabeled as passing full qualification.
