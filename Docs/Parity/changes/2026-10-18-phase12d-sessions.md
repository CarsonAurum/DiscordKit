# Supervised Voice v8 sessions and media

Verified and locally added **2026-10-18**, after `0a33835`. Voice Gateway **v8**,
DAVE **v1**, MLS **1.0/ciphersuite 2**, 48-kHz Opus and RTP-size transport AEAD
remain explicit. [Current official bytes](../phase12d-current-sources.json) are
separate from historical discovery pins. Grouped upstream announcement and
effective dates remain unknown. Eligible voice DAVE enforcement **2026-03-01**
is distinct from this local implementation date.

Previously Voice supplied pure framing/rendezvous/reducer components and DAVE
supplied an explicitly driven cryptographic owner. There was no supervised
network session, per-guild manager or composed PCM/Opus receive pipeline.
`VoiceSession`, `VoiceManager` and `VoiceMediaPipeline` now provide those bounded
owners. `DAVEVoiceSession` composes the actual cryptographic backend with bounded
control-priority admission and authenticated SSRC/account routing. No native
Discord runtime, new dependency, main-client import or reverse DAVE dependency
is introduced. Existing pure consumers remain independently adoptable.

The consumer opts into a run/join lifetime, shared main-Gateway opcode-4 authority,
fresh credential factory, TLS/UDP adapters, shared signing identity, trusted MLS
external sender and monotonic clock. Either-order event rendezvous, timeout,
cancellation, move/leave/null endpoint and token/session replacement are fenced.
Heartbeat debt/resume delivery order survives asynchronous readiness checks;
early DAVE messages are buffered under explicit byte/count bounds. Invalidating
close codes require fresh join credentials; retries never replay a mutation.

Media performs complete Opus/PCM encode -> DAVE -> RTP -> outer AEAD -> UDP and
the authenticated inverse. SSRC count, jitter storage, cryptographic attempts and
admission queues are bounded. Recording/playback are explicit caller-owned sinks.
Revocation fences in-flight media; sequence/timestamp wrap does not reset crypto
counters. New/restarted talkspurts reanchor pacing after idle instead of accumulating
arbitrary catch-up debt. Timestamp-aware jitter distinguishes omitted DTX media time from RTP
sequence loss. Speaking precedes sending; normal completion emits five securely
transformed silence frames. A bounded structural MLS delivery decoder supports
Commit plus optional Welcome separation without implying authentication.

[Ownership and migration](../../VoiceSessions.md) explains direct adoption and
composition with existing Gateway/Apple adapters. The local qualification harness
uses actual localhost UDP and owned codec/MLS/DAVE peers; independent client,
Discord SFU, consent/device and production evidence remain distinct. See
[the validation record](../phase12d-validation.json). Authorized Discord smoke,
independent cryptographic review and complete platform/device qualification are
explicitly unrun/open and are excluded from support claims.
