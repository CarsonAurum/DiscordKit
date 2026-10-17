# Consumer runtime, state and event delivery: Phase 7

Verified and locally added **2026-10-16** using existing explicit REST/Gateway **v10**
contracts. Local release/commit remain unknown until creation. This local runtime
change introduces no new Discord endpoint, dispatch name or promotion of discovery
inventory records; reviewed child-resource classifications retain their prior scope.

Previously callers composed raw shard polling themselves. The new independent Client
product owns discovery, bounded topology/session reservations, shard supervision,
ingestion, service access, readiness diagnostics and awaited single-use shutdown.
Gateway adds independent bounded broadcast queues and optional ordered handler
execution; a slow consumer overflows only its subscription by default. Cancellation
now drains child results so a late lease-release failure cannot be hidden by an
earlier cancelled child or end-of-ingestion signal.

Cache is independent of HTTP/Gateway/Client. It adds optional identity/intent/visibility
scoped JSON projections, finite count/byte/TTL/LRU limits, explicit refresh coalescing,
sparse/null/redaction/availability/deletion state and stale-completion fencing.
Permission resolution uses arbitrary-width supplied facts and returns indeterminate
for missing/redacted inputs. Local writes and observed permission/visibility changes
invalidate old evidence; unobserved changes require TTL or explicit revalidation.

Sources verified: [API reference](https://docs.discord.com/developers/reference),
[Gateway](https://docs.discord.com/developers/events/gateway),
[Gateway Events](https://docs.discord.com/developers/events/gateway-events),
[Permissions](https://docs.discord.com/developers/topics/permissions),
[Threads](https://docs.discord.com/developers/topics/threads) and
[change log](https://docs.discord.com/developers/change-log). Upstream introduction
dates for existing semantics remain unknown. Channel obfuscation was announced
2026-08-12 with mandatory bot behavior scheduled for 2026-11-16; synthetic/redacted
overwrite state cannot establish permission. Local support dates do not establish
upstream introduction.

Migration is additive. Subscribe before run, use one raw consumer per shard, share
credential/aggregate authorities, rotate cache visibility for fresh sequence domains,
and await run for cleanup failures before handoff. No cache result establishes
current Discord authorization. Shared adapter/cache cleanup is explicitly owned;
construction creates no network operation or hidden task. Models retain immutable
snapshot semantics. The independent bot example receives READY, fetches a typed
resource and awaits cleanup; repository validation never supplies real credentials.

See the [client contracts](../../Client.md) and
[execution record](../../../.air/plans/phase-7-execution.plan.md) for numeric limits,
deterministic evidence, local RSS/accounted-byte measurements and qualification limits.
Live Discord, distributed stores, other hosts/devices and endpoint-specific
authorization remain separate gates.
