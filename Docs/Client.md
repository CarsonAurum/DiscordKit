# Consumer client, state and event delivery

Implemented **2026-10-16** for the existing REST/Gateway **v10** JSON session.
`DiscordClient` and `DiscordCache` are independent SwiftPM products. The umbrella
exposes `BotClient`, `BotConfiguration` and `EventHub`. REST-only adoption remains
independent of Gateway, cache, client, handlers and concrete transports.

## Construction and lifetime

`DiscordClient` construction stores dependencies and starts no network operation or
task. `run()` reserves one shared client slot before discovery, fetches current
`GET /gateway/bot` data, validates the selected topology, reserves its raw queue
ceilings and supervises all selected shards and ingestion children. The caller
supplies explicit intents, a token matching the public bot ID, services, transport,
clock, leases and authorities. Privileged intents still require Discord approval.

`shutdown()` is idempotent and awaits discovery cancellation, socket close, child
completion, lease release, subscriber cleanup and the optional owner cleanup.
Cancelled shutdown callers cannot abandon shared cleanup. Noncancellation cleanup
failures remain visible through `run()`, including when another child cancelled
first. Await that run to inspect the failure before a worker handoff. A stopped or
failed client cannot run again; construct another client while retaining shared
admission authorities. Shutdown before run performs no discovery or leasing.

The client owns its active socket connections. Injected REST transports, rates,
caches and connectors may be shared; they close only through an explicitly supplied
cleanup closure when the client owns their complete lifetime. Cleanup and refresh
loaders must cooperate with cancellation. A state reducer or owner cleanup callback
must not await shutdown of its own run. Handler tasks are separate consumers and may
call shutdown.

`ClientAuthority` retains one startup ledger and opcode authority for one bot
credential. Reuse it across client instances and topology handoffs; discovery does
not reset consumed budgets. Share external startup/opcode coordinators and lease
stores across processes. Coordinator failure never creates replacement independent
budgets. Rotate cache identity when credentials change. `ClientResourceBudget` can
be shared across bot identities; defaults reserve at most 16 clients, 256 actual
sessions, 32,768 raw events and 1 GiB of raw wire queue ceilings. These are local
admission limits, not measured deployment capacity or Discord quotas.

`snapshot()` exposes client phase, per-shard phases/generations/sequences, resume
availability, pending requests/writes and queue accounting without secrets. Shard
snapshots are sequential observations; readiness may change immediately afterward.
`send`/`request` use explicit local shard indices and the existing typed Gateway
admission/correlation contracts. `services.execute` accepts every typed REST
descriptor before or after Gateway readiness. Models remain independent values.

## Broadcast subscriptions and handlers

Subscribe to `client.events` before `run` to receive initial events. Every
subscription owns its own queue. Default limits are 128 events/1 MiB per subscriber,
64 subscribers, 4,096 queued copies and 16 MiB per hub. Inject one
`GatewayEventHubAuthority` across hubs to impose process aggregate limits. Queue
bytes count each retained envelope copy; events already transferred to consumers
are consumer-owned and outside queue accounting. First-created subscribers have
priority when aggregate admission is exhausted.

Default overflow terminates only that subscription with
`resynchronizationRequired`; it discards queued data and retains a bounded terminal
metadata slot until observed, cancelled or finished. `.dropNewest` and `.dropOldest`
are explicit lossy alternatives. Abandoning an iterator requires `cancel()`. A
suspended cancelled `next()` removes its queue; overlapping iteration on one
subscription fails rather than accumulating waiters. `finish()` permanently closes
admission, terminates subscriptions and awaits racing registrations.

Publication never runs user callbacks. Per-shard publication order survives; no
global order, completeness, durable delivery or exactly-once guarantee is offered.
Discord itself documents eventual consistency and missing/duplicate events in its
[API reference](https://docs.discord.com/developers/reference#consistency).
Raw `GatewayShard.nextEvents` is a single-consumer ingestion adapter, not broadcast;
do not mix it with `drainEvents`. It retains only one coalesced wake-up signal and
rejects overlapping consumers. The client is its sole owner.

`GatewayEventHandlerDispatcher.run` owns callback tasks in a structured group. Its
default caps are four concurrent handlers and 128 retained events/4 MiB including
active and pending work. Callbacks execute serially per complete shard identity;
different shards may overlap. A hot shard can fill the bounded lookahead and apply
backpressure to this subscription. Other subscribers and Gateway control work remain
independent. A shared `GatewayHandlerAuthority` bounds aggregate running callbacks
and FIFO permit waiters across dispatchers. Callback errors propagate to the owner;
concurrent completed side effects are not rolled back. Reentrant and MainActor
consumers are exercised deterministically.

## Optional entity projections

`EntityCache` imports models/core/bits and never Gateway, HTTP or concrete adapters.
One shared cache actor enforces aggregate limits across scopes. Scope equality
includes an opaque credential-generation label, exact intents and a visibility
generation. Per-identity limits include every intent/visibility partition. Rotate
visibility generation for fresh client sequence domains; the bridge uses local
socket generation and shard sequence within one client. A resumed session or a
replacement client must never make an old cached snapshot authoritative.

| Policy | Aggregate entries/bytes | Per-identity entries/bytes | Maximum TTL |
| --- | --- | --- | --- |
| `.noCache` | zero retained | zero retained | explicit reads only |
| `.minimal` | 64 / 256 KiB | 16 / 64 KiB | 30 seconds |
| `.bounded(CacheLimits)` defaults | 1,024 / 4 MiB | 256 / 1 MiB | five minutes |

Larger retention is opt-in through finite limits. TTL is positive and at most 30
days, expires inclusively and is pruned lazily. LRU eviction applies both per
identity and globally. Accounted bytes include serialized JSON, field metadata and
scope/key sizes; Swift heap/index/task/allocator overhead requires actual RSS
measurement. A missing, expired, evicted or oversized value yields a miss or an
explicit not-retained result; the cache never grows to satisfy a desired working set.

Snapshots record provenance, completeness, redacted fields, nullable fields,
availability/deletion and optional source ordering. Sparse patches preserve omitted
fields; explicit null is accepted only for declared nullable keys. Nested JSON is
replaced as a unit. Redaction removes old values. Duplicate/stale observations are
ignored while bounded ordering evidence remains retained. Eviction/expiry may remove
that evidence. Child arrays are not silently treated as complete guild state.

The Gateway reducer projects selected guild, channel/thread, member, role, user,
message and interaction observations. Unknown events remain available in broadcast
but are ignored by this optional reducer. Guild unavailability and removals clear
child projections and retain explicit tombstones. Protected message data is
conservatively redacted without MESSAGE_CONTENT; explicitly supplied usable exception
data can satisfy reads without a redundant fetch. These JSON projections are partial
and do not expand typed child-resource parity. See the current
[Gateway events](https://docs.discord.com/developers/events/gateway-events) contract.

`refresh` uses eligible fresh event/interaction data first. Otherwise equivalent
explicit scoped reads share one loader. Defaults cap 32 aggregate/eight per-identity
refreshes and 512 aggregate/128 per-refresh waiters. Overload fails immediately;
there is no automatic refresh loop. Cancelling one waiter preserves the others;
the last cancellation and `close()` await loader cleanup. Loader errors are not
cached. A conservative global revision prevents any older fetch completion from
overwriting newer accepted state/invalidation, including after eviction. Unrelated
observations can supersede a fetch; callers decide whether to retry explicitly.

Observed role/member/overwrite/ownership changes, guild loss/unavailability and
channel deletions invalidate the identity's other visibility projections.
`ClientCacheProjection.services` invalidates every partition
of that identity before and after local writes, including failed/ambiguous outcomes.
Direct `RESTClient` calls require explicit entity invalidation; HTTP response-byte
reuse retains its separate existing invalidation policy. Unobserved changes remain
possible until TTL or explicit revalidation. Cached data never establishes current
authorization. `EntityCachePersistence` is an opt-in adapter contract; no persistence
or disk I/O happens implicitly, and monotonic expiry cannot survive process restart.

## Permission resolution

`PermissionResolver` is synchronous and accepts explicit independently acquired guild,
member, channel and parent-thread facts. It unions arbitrary-width role bitsets,
recognizes owner/admin bypass without inventing a finite all-bits mask, applies
everyone/aggregate-role/member overwrites in order, then thread and implicit-denial/
timeout rules. Unknown high bits survive the supported calculation within finite
input bounds. Defaults cap 1,024 roles/overwrites, 65,536 bits per supplied mask and
1,048,576 supplied bits in total.

Missing ownership, roles, timeout state, complete overwrites, thread parent/member/
lock/archive facts, unsupported kinds or obfuscated metadata return a typed
indeterminate reason. An empty set of known permissions is distinct from unknown.
The caller supplies timeout state at its chosen instant and coherent source
freshness. The result models permission bits, not every endpoint-specific prerequisite,
account restriction or Discord's current authorization decision. Sources verified
2026-10-16: [Permissions](https://docs.discord.com/developers/topics/permissions),
[Threads](https://docs.discord.com/developers/topics/threads) and the
[change log](https://docs.discord.com/developers/change-log), including channel
obfuscation announced 2026-08-12 for mandatory behavior on 2026-11-16.

## Example and validation

The independent [Gateway bot example](../Examples/GatewayBot/README.md) starts,
receives READY, calls a typed service and awaits cleanup. Validation builds it
without real tokens or authenticated calls. [Phase 7 execution](../.air/plans/phase-7-execution.plan.md)
records exact test counts, local soak measurements and qualifications. The separate
[load harness](../Tools/DiscordKitLoadTests/README.md) records actual RSS alongside
accounted cache bytes. These local scripted tests and measurements do not establish
live Discord behavior, distributed storage conformance, other-host/device runtime,
background execution or a deployment serving millions of concurrent connections.
