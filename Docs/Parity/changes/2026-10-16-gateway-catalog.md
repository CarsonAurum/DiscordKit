# Gateway dispatch, outgoing commands and correlated requests: Phase 6

Verified and locally added **2026-10-16**, Gateway API **v10**, JSON/uncompressed.
Local release and commit are unknown until creation. [Current source fingerprints](../gateway-current-sources.json)
remain separate from unchanged historical discovery provenance and membership.

## Previous and current behavior

The Part 3 slice provided sharded Identify/Resume, heartbeats, raw ordered dispatch
ingestion, leases and coordinated starts. It did not expose a typed receive catalog,
validated application commands or request completion. This phase adds all 79 written
opcode-zero dispatch names, the 13 documented opcode values, all 21 named intents,
Identify capabilities and typed presence/voice/member/soundboard/channel-info sends.
Exact raw unknown values remain available; related partial-resource projections
continue to be classified separately from event-name recognition.

Bounded member requests assemble nonce-correlated chunks and preserve partial
results. Soundboard/channel-info responses do not have a protocol nonce; exclusive
guild/family keys are poisoned after failures/direct sends for that generation.
Successful-key reuse remains subject to duplicate/unsolicited-response ambiguity. Timeout, cancellation,
disconnect, overflow and rate-limit outcomes clean up pending work without automatic
replay. Gateway opcode admission remains independent of REST and session starts.

## Known upstream chronology

| Behavior | Announced | Effective | Adopted behavior |
| --- | --- | --- | --- |
| All-members opcode rate limit and RATE_LIMITED | 2025-08-14 | 2025-10-01 general rollout; earlier selected rollout | One all-members request per guild per bot per 30 seconds; metadata/nonce preserved |
| Soundboard public API | 2024-09-20 | unknown | Soundboard request/response and update event contracts |
| Voice channel status/start-time documentation | 2026-04-20 | unknown; pre-existing availability stated | Opcode 43 Channel Info and ephemeral status/timing events |
| Channel obfuscation | 2026-08-12 | 2026-11-16 mandatory bot behavior announced | Temporary capability bit15 and redacted Channel payload preservation |

Dates come from the [official change log](https://docs.discord.com/developers/change-log).
The voice entry explicitly documents pre-existing behavior rather than establishing
its introduction date. Other event/intent/opcode announcement and effective dates
remain unknown. The local support date does not establish upstream introduction.

## Compatibility and migration

The APIs are additive. Existing raw `drainEvents` consumers can adopt typed decoding
incrementally. Sparse updates retain absence/null differences and raw unknown fields;
consumers must not treat partial data as a complete replacement or authorization.
Privileged intents require Discord approval/configuration. CHANNEL_OBFUSCATION is a
temporary test mechanism, not a permanent availability guarantee.

Only documented JSON/uncompressed sessions are implemented; compression and alternate
encodings remain separate qualified protocol choices. Native voice media, caches,
handler routing, distributed storage adapters, live Discord, other-host/device and
sustained-capacity qualification remain separate. See the [Gateway guide](../../Gateway.md)
and [execution record](../../../.air/plans/phase-6-execution.plan.md) for bounds and checks.
