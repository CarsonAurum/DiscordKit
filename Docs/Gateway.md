# Minimal sharded Gateway lifecycle

Implemented 2026-10-16 against the current
[Gateway reference](https://docs.discord.com/developers/events/gateway),
[event controls](https://docs.discord.com/developers/events/gateway-events) and
[close codes](https://docs.discord.com/developers/topics/opcodes-and-status-codes).
The protocol is explicitly **v10**, JSON and uncompressed. This delivers the early
Part 6 steps required alongside HTTP; full dispatch/model/request parity remains
Part 6 work. Raw unknown dispatch payloads are preserved without a typed-parity claim.

`GatewayEndpoints.bot()` uses the HTTP pipeline for authenticated discovery.
`GatewayDiscovery` validates the trusted WSS URL and recommended shard/session-start
metadata. Completed discovery snapshots are not cached as live startup allowances.
Reset delays above 30 days are rejected as an explicit implementation bound before
untrusted values reach monotonic-clock arithmetic.
Build the selected `ShardIdentity` subset from discovery, sharing one lease store
and startup coordinator per bot across every local worker. The discovery shard
count and `(guildID >> 22) % count` routing are separate from REST guild-list partitions.
Non-guild dispatches are delivered on shard zero by Discord's protocol.

`GatewaySessionState` is a pure transition core. `GatewayShard` owns socket generation,
session ID, sequence, resume URL, heartbeat state and bounded raw events. Its `run`
operation supervises socket receive, authentication, heartbeat and lease renewal.
`GatewayBot.run` supervises the finite selected subset in a task group; failure
cancels and awaits sibling cleanup. Construction launches no tasks or socket work.

Heartbeats use injected jitter and monotonic time, respond to requested beats and
reconnect after a missed scheduled ACK. Control processing never invokes handlers
or awaits a cache/subscriber. Consumers call `drainEvents` for bounded ordered batches;
overflow ends the run with a resynchronization requirement. Per-shard ingestion order
is preserved, while duplicates and replay remain possible. There is no global order
or exactly-once claim. New dispatches/opcodes survive as raw bounded JSON where the
control contract permits; arbitrary outbound opcode support is not implemented.

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
No live Discord connection, full dispatch catalog, handler framework, cross-platform
session qualification or sharded runtime capacity is established by these tests.

## Local control and ownership evidence

The independent [load harness](../Tools/DiscordKitLoadTests/README.md) includes an
offline Gateway script using the production shard actors and in-process coordinators.
Profiles for 100, 10,000 and 1,000,000 logical served users select **1/4/16 actual
local sessions** across **1/2/4 synthetic bot identities**, respectively. They process
10,000/100,000/100,000 dispatches without allocating the logical user population.
No socket, real credential or live Discord request is involved.

Each session reconnects once at its source midpoint and resumes from retained
sequence/session state. An isolated startup storm offers 2× or 10× the bucket count
and admits exactly one start per bucket. Consumers yield between batches; source
credits of 8/16 bound undrained dispatch metadata. Control requests and ACKs bypass
these credits. Queue limits are 32 events and 65,536 wire bytes per selected shard.
Both control delay and event lag retain the first 4,096 samples, with CPU/RSS measured
for the complete client process. Sampled queue peaks can miss transient peaks; the
configured aggregate ceilings are also reported.

Release evidence and hardware/toolchain context are preserved in
[Gateway baselines](../Tools/DiscordKitLoadTests/Baselines/gateway-environment.json).
The 2026-10-16 release captures used an Apple M3 Max, macOS 27.0.1 and Swift 6.4.
Every run delivered its exact dispatch target, completed one Resume per selected
session and retained zero connections or leases after shutdown. CPU is relative to
one core and can exceed 100%; peak RSS is an un-settled process high-water mark.

| Logical users | Mode | Sessions / bots | Control p99, ms | Event lag p99, ms | CPU, one-core % | Peak RSS, MiB |
| ---: | --- | ---: | ---: | ---: | ---: | ---: |
| 100 | Normal | 1 / 1 | 0.020 | 0.039 | 219.6 | 8.91 |
| 100 | Burst | 1 / 1 | 0.018 | 0.036 | 220.8 | 8.91 |
| 10,000 | Normal | 4 / 2 | 0.035 | 0.302 | 352.6 | 11.13 |
| 10,000 | Burst | 4 / 2 | 0.035 | 0.565 | 382.1 | 11.44 |
| 1,000,000 | Normal | 16 / 4 | 0.322 | 0.486 | 312.3 | 11.36 |
| 1,000,000 | Burst | 16 / 4 | 0.331 | 0.508 | 312.2 | 11.50 |

Reproduce all six serial captures after building release:

```sh
python3 Tools/DiscordKitLoadTests/scripts/record_gateway_baseline.py
```

This finite scripted workload measures lifecycle, bounded ingestion and control
isolation. It establishes no network throughput, real Discord quota, distributed
coordination, sustained soak or runtime capacity claim.
