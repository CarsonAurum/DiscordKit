# 2026-10-15: Part 2 owned transport slice

Previous behavior: portable I/O contracts and deterministic scripted implementations,
without production network adapters. Current behavior: independently adopted
Foundation HTTP/WebSocket, owned NIO HTTP/TLS/WebSocket/UDP/ingress, Unix-domain IPC,
app-driven Apple lifecycle ownership and injectable fenced shard coordination.

Affected symbols and generic wire behavior are documented in
[Transport](../../Transport.md). This is a macOS arm64 / Swift 6.4 implementation
slice. No Discord endpoint, Gateway session, rate limiter, interaction, OAuth,
voice or RPC framing is implemented. Discovery inventory operation statuses stay
unsupported; protocol support counts stay zero.

The official [reference](https://docs.discord.com/developers/reference),
[Gateway sharding formula](https://docs.discord.com/developers/events/gateway#sharding)
and [change log](https://docs.discord.com/developers/change-log) were verified on
2026-10-15. The existing REST v10 / Gateway v10 / Voice Gateway v8 baseline is
unchanged. Shard routing follows `(guild_id >> 22) % num_shards`, but assignment
and fencing do not establish a running Gateway lifecycle or distributed storage.
Upstream announcement/effective dates for these underlying contracts are
**unknown**. Local implementation date is **2026-10-15**; release and commit
remain **unknown** until assigned.

Compatibility: no existing protocol signature changes. Choose a concrete adapter
product explicitly and inject through DiscordTransport. Consume or close response
bodies; close connections, responders and adapters. Admission is bounded and
fail-fast. Requests send once, redirects are not followed, and ambiguous writes
are never silently retried. Private-PKI anchors do not bypass hostname verification.
The portable products and Foundation adapter do not link NIO. The approved
[dependency graph and license audit](../../Dependencies.md) records compatible
manifest requirements, exact tested revisions and bundled native components.

Regression work also fixes native response abandonment and shutdown, stalled
upload cleanup, bodyless representation-length metadata, failed WebSocket
negotiation, frame/control-write budgets and concurrent close ownership.
Scripted HTTP execution, response completion and ingress acceptance recheck
cancellation and deadlines after suspension before transferring ownership.
Continuous-clock deadlines now use 100 ms checkpoints to limit stale cancelled
timer retention while preserving suspension-aware time and injected clock behavior.

## Validation and limits

Final executed checks on macOS arm64 / Swift 6.4:

| Check | Result |
| --- | --- |
| Root `swift build` | Passed; all eight products preserve the declared concurrency settings and deployment baselines. |
| Root `swift test` with `SWIFTNIO_STRICT=1` | Passed, 193 test methods in 25 suites from the staged snapshot, independently of unrelated working-tree edits. Includes 50 NIO, 22 Foundation and 11 Unix methods; strict mode rejects submissions after event-loop shutdown. |
| Inventory-tool Swift tests | Passed, 38 methods. |
| Offline inventory validator | Passed, 18,137 entries / 280 sources; zero unclassified IDs or implemented operation records. |
| Inventory extraction Python tests | Passed, 10 tests. |
| Independent load-package release build and Swift tests | Passed, 10 tests. |
| Local load-peer Python tests | Passed, 2 tests. |
| Six release load profiles | Passed their versioned numeric gates; exact evidence is linked below. |
| Declaration comments, local Markdown links and diff review | Passed; generated build output remains excluded. |

The managed sandbox blocks native compiler temp/cache access and local socket
execution. Swift checks used approved host access. Initial regression failures
were fixed before these successful final runs. Feasibility fixture packages were
not modified or rerun; their earlier results remain historical.

The root suites exercise real local peers, native Foundation behavior, fully
verified TLS and trust/hostname rejection for NIO, malformed input, fragmented
frames/control handling, limits, cancellations/deadlines, overload and cleanup.
A shared HTTP contract runs against both HTTP backends. Platform lifecycle and
shard ownership tests use deterministic barriers and virtual clocks. No Discord
credentials or live Discord requests are used.

The independent [load report](../../../Tools/DiscordKitLoadTests/README.md) records
six release profiles on the reference host. Normal 100/10,000/1,000,000 logical
account profiles use bounded cohorts and 8/16/32 physical sockets, with all
client pool slots released after close. Normal results were 16,560–20,134
exchanges/s, p99 1.386–4.018 ms and peak client RSS 15.17–17.52 MiB. Burst runs
exercise refusal without exceeding socket budgets; burst latency and throughput
are recorded separately without a service-level gate. These are local workload results, not account,
fleet or simultaneous-connection capacity promises.

The whole-platform Part 2 gate remains open: Windows pipes, Android integration,
unavailable hosts/devices and minimum-OS runs, extended connect/write cancellation,
expired/native TLS rejection scenarios, live network replacement and a 30-minute
soak/allocation trace still need evidence. Foundation's private socket buffers and
normalized response headers remain explicit limitations. UI/auth/media adapters
remain with their actual feature implementations; no empty products count as support.
See [current platform evidence](../../PlatformSupport.md) and the detailed
[remaining gates](../../Transport.md#qualification-and-remaining-gates).
