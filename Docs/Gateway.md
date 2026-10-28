<!--
File: Docs/Gateway.md
Created by Carson Rau.
Copyright (c) 2026 Aurum Studios.
https://aurum-studios.com
-->

# Sharded Gateway lifecycle, dispatches and requests

Implemented 2026-10-16 against the current
[Gateway reference](https://docs.discord.com/developers/events/gateway),
[event controls](https://docs.discord.com/developers/events/gateway-events) and
[close codes](https://docs.discord.com/developers/topics/opcodes-and-status-codes).
The protocol is explicitly **v10**, JSON and uncompressed. DiscordKit provides the early
lifecycle with typed recognition of all **79 documented opcode-zero dispatch names**,
all **13 documented Gateway opcode values**, **21 named intents**, Identify
capabilities and bounded member/soundboard/channel-info requests. Named catalog
coverage does not imply complete typed child-resource schemas: related partial
projections and raw unknown payloads remain explicit. Current official source hashes
are [recorded separately](Parity/gateway-current-sources.json) from historical pins.

`GatewayEndpoints.bot()` uses the HTTP pipeline for authenticated discovery.
`GatewayDiscovery` validates the trusted WSS URL and recommended shard/session-start
metadata. Completed discovery snapshots are not cached as live startup allowances.
Negative reset delays and delays above 30 days are rejected as explicit implementation
bounds before untrusted values reach monotonic-clock arithmetic. A zero delay is
accepted with conservative local quota accounting, as described below; the official
session-start reference does not specify that edge case.
Build the selected `ShardIdentity` subset from discovery, sharing one lease store
and startup coordinator per bot across every local worker. The discovery shard
count and `(guildID >> 22) % count` routing are separate from REST guild-list partitions.
Non-guild dispatches are delivered on shard zero by Discord's protocol.

`GatewaySessionState` is a pure transition core. `GatewayShard` owns socket generation,
session ID, sequence, resume URL, heartbeat state and bounded raw events. Its `run`
operation supervises socket receive, authentication, heartbeat and lease renewal.
`GatewayBot.run` supervises the finite selected subset in a task group; failure
cancels and awaits sibling cleanup. Construction launches no tasks or socket work.

DiscordKit provides [consumer composition, broadcast and handlers](Client.md). Existing raw
consumers can keep `drainEvents`; the client instead owns `nextEvents`, a bounded
single-consumer wake-up API. Public `GatewayEvent` construction supports bounded
offline replay and exposes local socket-generation provenance. It authenticates
neither supplied data nor the caller. Multi-shard cancellation drains every child
result so late ownership-release failures remain observable.

Heartbeats use injected jitter and monotonic time, respond to requested beats and
reconnect after a missed scheduled ACK. Control processing never invokes handlers
or awaits a cache/subscriber. Consumers call `drainEvents` for bounded ordered batches;
overflow ends the run with a resynchronization requirement. Per-shard ingestion order
is preserved, while duplicates and replay remain possible. There is no global order
or exactly-once claim. New dispatches/opcodes survive as raw bounded JSON where the
control contract permits. Outgoing application commands use the finite typed
`GatewayCommand` contract.

Disconnects use a finite lifetime retry budget and capped jittered backoff. Session
IDs, last sequence and trusted resume URLs support Resume; invalid sessions choose
Resume or fresh Identify according to the server's boolean. Fatal authentication,
intent, version and shard configuration close codes terminate instead of consuming
starts indefinitely. Unknown codes follow conservative reconnect behavior.

The optional transport `WebSocketSessionConnection` exposes peer numeric close codes
and reconnect closure. Foundation and NIO implement it and preserve peer codes through
cleanup. NIO aborts TCP without a normal/going-away frame; Foundation uses a nonnormal
close plus native cancellation. Generic injected connections use fresh Identify after
ordinary graceful cleanup. Foundation peer-code delivery remains subject to native
callback behavior; loopback tests cover representative Discord codes. NIO tests cover
all documented Discord codes.

## Coordination and budgets

`InProcessGatewayStartupCoordinator` atomically reserves server-reported remaining
starts and shard-index modulo max-concurrency buckets. Identify reservations consume
quota before writes and are never refunded on cancellation or ambiguous sends.
Resume has its own protocol semantics and consumes no Identify start. The known
server reset replenishes once; later exhaustion requires refreshed discovery rather
than assuming `reset_after` is a recurring period. Refresh preserves active bucket
windows and conservatively combines snapshots. A concurrency topology change needs
a drain and controlled coordinator replacement, without resetting remaining starts.

A discovery response with `reset_after: 0` permits the reported remaining starts but
does not schedule automatic replenishment. Identify still consumes one start and
obeys the five-second concurrency buckets; depletion requires fresh discovery.
Repeated zero-delay snapshots cannot restore locally spent starts. A zero-delay
refresh clears any previous reset deadline; a later positive delay establishes a
future reset without immediately restoring spent starts. This is local compatibility
behavior, not a newly documented upstream reset contract.

`GatewayStartupCoordinator` is injectable for cross-process atomic admission.
`ShardLeaseStore` supplies ownership, expiry and monotonic generation fencing.
Checks around suspension points reject stale generations; loss of authority stops
new sends and closes the session. Cleanup awaits local children/socket/queue release
and reports remote lease-release failures. External fencing cannot recall a write
already in flight. Coordinators must fail closed on outage, never invent independent
startup budgets. No distributed storage adapter is shipped or certified.
Known closed failures remain typed; arbitrary injected error descriptions are replaced
with fixed coordinator-unavailability errors before leaving the public runtime.

Default shard limits are 1 MiB per JSON frame, 128 queued events and 4 MiB queued
wire bytes. GatewayBot allows at most 256 local shards; operators should configure
lower workload-specific totals. Lease metadata is separately bounded by the injected
store. Per-shard limits multiplied by the configured finite shard count give the
aggregate queue ceiling; parser/index/allocator overhead is additional. Queue overflow
requires resynchronization. Stop requests drain; await run completion before handoff.
Changing total shard count requires a new topology generation and resynchronization.

Deterministic suites cover transition guards, every documented close-code class,
Identify contention, reset/bucket boundaries, reconnect/resume/invalid sessions,
heartbeat ACKs, event order/duplicates/overflow, lease loss and cancellation cleanup.
Real local WebSocket adapter tests verify numeric close codes and abort ownership.
No live Discord connection, complete typed child-resource parity,
cross-platform session qualification or sharded runtime capacity is established by
these tests.

## Typed dispatch and command contracts

`GatewayDispatchName` enumerates the complete written receive catalog after separating
Hello, Reconnect and Invalid Session, which use their own control opcodes.
`GatewayDispatch` carries the matching typed payload and retains its exact JSON.
Unknown names survive as raw data; unknown resource fields, enum values and large
snowflakes retain their original representations. Consumers can decode a drained
`GatewayEvent` without coupling the heartbeat loop to user handlers.

Sparse updates are presence-aware. An unavailable `GUILD_CREATE`/`GUILD_DELETE`
is distinct from a full guild snapshot or permanent removal. A `MESSAGE_UPDATE`
does not replace omitted fields with default values. Member chunks expose their
nonce/index/count, and RATE_LIMITED preserves opcode/retry metadata. Voice channel
status and start time are ephemeral event data, separate from persistent Channel
fields. Existing nested resources may remain partial typed projections; their exact
raw values are still available and no cache merge policy is invented here.

`GatewayIntents` and `GatewayCapabilities` are distinct bitfields. Privileged member,
presence and message-content intents still require the documented Developer Portal
configuration/approval. Setting a bit cannot obtain permission or guarantee delivery.
The CHANNEL_OBFUSCATION capability (`1 << 15`) is a temporary testing opt-in,
verified 2026-10-16. The official 2026-08-12 announcement schedules mandatory bot
obfuscation for **2026-11-16**. Channels may contain redacted names, null/reduced
metadata and the CHANNEL_OBFUSCATED flag (`1 << 17`); a later Channel Update may
restore visible data. Preserve these payloads and do not infer current authorization
from a prior full snapshot. [Official change log](https://docs.discord.com/developers/change-log).

Commands validate documented payload shapes before sending, including the 32-byte
UTF-8 member nonce, query/user-ID choices, requested presences/intents and finite
local array/frame bounds. Local safety bounds are implementation choices, not new
Discord quotas. Identify optionally carries capabilities, large-threshold and initial
presence while retaining explicit JSON/uncompressed negotiation. Presence/voice
updates remain main-Gateway control operations; they do not implement voice media.

## Bounded requests and outgoing admission

`GatewayShard.send` sends a validated application command only while the current
session is ready and owns its fenced lease. `GatewayShard.request` additionally
awaits a finite response set and returns the original `GatewayEvent` values.
Member requests require a nonce and track unique chunk indices without assuming
wire order. Duplicate chunks do not count twice; conflicting metadata, invalid
bounds and request overflow fail explicitly. Unrelated guild/nonce observations
remain raw events without completing the request.
Successful member results use chunk-index order and soundboard results use the
requested guild order; failure partial events retain bounded observations.

Soundboard and channel-info commands have **no documented response nonce**. They
use exclusive guild/family ownership within the socket generation. A failed or
directly sent correlation key cannot be reused in that generation: a late response cannot safely
be distinguished from a replacement request. Successful keys may be reused after
completion, but upstream duplicate or unsolicited responses remain ambiguous and
can be mistaken for the replacement response; establish a new generation when this
ambiguity is unacceptable. Soundboard completes after one response per requested
guild; channel-info completes after its guild response. These rules deliberately
avoid inventing a protocol nonce or promising exactly-once correlation.

Requests use caller-selected finite deadlines through one day (30 seconds by
default). Defaults allow 16 pending requests, 4,096 response events per request,
8 MiB retained response bytes across pending requests and 4,096 active/retired
correlation keys per shard. Cancellation, stop and connection-generation changes
clean up registrations and retained results. Cancellation throws `CancellationError`;
timeout/disconnect/invalid-response/capacity/rate failures carry bounded partial
observations in `GatewayRequestFailure`. They are never replayed automatically after reconnect;
callers decide whether to issue a new read using a fresh correlation identity.
Ordinary drained events remain independently available, so request assembly does
not consume the consumer's event stream or await handlers. Awaiting a request does
not drain raw ingestion: keep a consumer draining the configured raw queue (128
events by default), or that independent queue can overflow before a large request
reaches its own response bound.

Gateway send admission is separate from REST scheduling and Identify/startup budgets.
Application admission stops when the rolling 60-second total reaches 110 events,
reserving ten control slots within Discord's 120-event connection limit. Control
messages also count toward the hard 120-event ceiling. Presence updates
have their documented five-per-20-second bound. All-members requests honor the
per-bot/per-guild one-per-30-second scope. That full-list request means an empty
query with limit zero. Local and server-reported opcode-8 full-list cooldowns do
not block prefix or targeted-user reads; generic opcode limits retain their wider
scope. RATE_LIMITED supplies validated server cooldowns.
Failed or ambiguous submitted writes are not refunded or retried blindly. Shared
admission authority must accompany shared bot identities; process-local defaults do
not certify an external distributed coordinator.

## Local control and ownership evidence

The independent [load harness](../Tools/DiscordKitLoadTests/README.md) includes an
offline Gateway script using the production shard actors and in-process coordinators.
Profiles for 100, 10,000 and 1,000,000 logical served users select **1/4/16 actual
local sessions** across **1/2/4 synthetic bot identities**, respectively. They process
10,000/100,000/100,000 dispatches without allocating the logical user population.
No socket, real credential or live Discord request is involved.

Each session reconnects twice at gated source thirds and resumes from retained
sequence/session state. All three ready generations send presence and voice-state
updates and complete one request from each of the member, soundboard and
channel-info families. That is three completions per family, 12 typed response
events and 15 application writes per selected shard. An isolated startup storm offers 2× or 10× the bucket count
and admits exactly one start per bucket. Consumers yield between batches; source
credits of 8/16 bound undrained dispatch metadata. Control requests and ACKs bypass
these credits. Each socket generation issues at most one requested heartbeat,
which keeps the fixture within the newly enforced connection event allowance;
control sampling therefore retains at most three requested-beat observations per
shard. Queue limits are 32 events and 65,536 wire bytes per selected shard.
Both control delay and event lag retain the first 4,096 samples, with CPU/RSS measured
for the complete client process. Sampled queue peaks can miss transient peaks; the
configured aggregate ceilings are also reported.

Release evidence and hardware/toolchain context are preserved in
[Gateway baselines](../Tools/DiscordKitLoadTests/Baselines/gateway-environment.json).
The 2026-10-16 release captures used an Apple M3 Max, macOS 27.0.1 and Swift 6.4.
Every refreshed run delivered its exact synthetic dispatch target,
completed two Resumes per selected session and retained zero connections, pending
requests, application writes or leases after shutdown. Compare measurements only
when fixture, workload and toolchain match. CPU is relative to
one core and can exceed 100%; peak RSS is an un-settled process high-water mark.

| Logical users | Mode | Sessions / bots | Control p99, ms | Event lag p99, ms | CPU, one-core % | Peak RSS, MiB |
| ---: | --- | ---: | ---: | ---: | ---: | ---: |
| 100 | Normal | 1 / 1 | 0.038 | 0.070 | 211.7 | 9.84 |
| 100 | Burst | 1 / 1 | 0.031 | 0.143 | 211.7 | 9.83 |
| 10,000 | Normal | 4 / 2 | 0.052 | 0.320 | 323.4 | 11.91 |
| 10,000 | Burst | 4 / 2 | 0.043 | 1.161 | 333.2 | 11.66 |
| 1,000,000 | Normal | 16 / 4 | 0.486 | 2.655 | 409.3 | 12.80 |
| 1,000,000 | Burst | 16 / 4 | 0.423 | 3.128 | 430.2 | 13.25 |

Reproduce all six serial captures after building release:

```sh
python3 Tools/DiscordKitLoadTests/scripts/record_gateway_baseline.py
```

This finite scripted workload measures lifecycle, bounded ingestion and control
isolation. It establishes no network throughput, real Discord quota, distributed
coordination, sustained soak or runtime capacity claim.
