<!--
File: Docs/Scalability.md
Created by Carson Rau.
Copyright (c) 2026 Aurum Studios.
https://aurum-studios.com
-->

# Scalability and request efficiency

These requirements extend the [architecture](Architecture.md) and
[concurrency policy](Concurrency.md). Portable values, injected transports,
deterministic test support, bounded HTTP scheduling/read caches and a supervised
sharded Gateway provide the implementation foundations. Fleet coordination
contracts are injectable; durable adapters remain consumer-owned. This document
does not establish tested account or connection capacity.

## Capacity model and responsibility

Design DiscordKit as a bot library from the first runtime slice. Support growth
from hundreds to millions of Discord accounts served across a deployment, and
services operating many independent bot/application identities. Track end-user
accounts, bot credentials, guilds, shards, active sessions and concurrent requests
as separate workload dimensions; one million users does not imply one million
Gateway sessions. Application provisioning remains a Developer Portal concern.

Scale through partitioned workers and optional shared coordination. Provide an
in-process implementation for ordinary bots and injectable coordination/storage
contracts for deployments spanning processes or hosts. Consumers own deployment,
durable infrastructure and fleet placement. Do not require a particular database,
distributed actor runtime or production dependency for a single-process bot.

Partition hot mutable state by authentication identity, resource and shard rather
than funneling unrelated work through one global actor. Bound both each partition
and total process usage: queued count/bytes, active requests, connections, handler
tasks, subscriptions, cache entries/bytes, in-flight reads and coordination
metadata. Fleet adapters must enforce any shared admission budget they advertise.
Reject or backpressure excess admission explicitly; an account count must not
implicitly create an unbounded set of actors, sockets or timers.

## Rate admission and fairness

Keep rate policy in HTTP/Gateway, above the send-once transport contract. Derive
REST admission from learned bucket and resource scopes, respect retry delays,
and account for applicable credential, shared-resource and egress limits.
Interaction operations retain their documented distinct global treatment.
Monitor invalid-request pressure at shared egress and stop repeated invalid
credentials or unusable webhooks. Official behavior was checked on 2026-10-15;
reverify changing limits before implementation. [Discord rate limits](https://docs.discord.com/developers/topics/rate-limits).

Use opaque authentication partitions; raw tokens must not become cache keys,
coordination identifiers or diagnostic labels. Clients and workers using the same
credential must share its admission authority. Credential rotation must not reset
still-applicable resource or egress limits. Each reservation needs a documented
atomicity, expiry, cancellation and uncertain-send contract. Releasing a waiter
must not refund a request that may already have reached Discord.

Provide bounded scheduling classes with FIFO within each identity/resource
partition and a documented fairness policy across eligible identities. Preserve
required mutation ordering. Reserve control/deadline capacity
without letting priority traffic indefinitely starve ordinary work. A blocked
bucket must not cause head-of-line blocking for unrelated eligible resources.
Retries consume rate, concurrency and retry budgets; preserve unknown mutation
outcomes and prevent unbounded retry work.

Distributed coordination requires atomic reservations and ownership generations.
On unavailable coordination or lost ownership, stop new shared admissions until
authority is restored; do not silently fall back to independent local budgets.
Evict inactive metadata only when doing so cannot forget live reservations or
reset a depleted budget. A consumer storage adapter must pass the same contract
suite as the in-process implementation before claiming coordinated operation.

## Make each request useful

Define freshness, deduplication, replayability and bulk semantics per operation.
HTTP exposes these policies without depending on Gateway or the entity-cache
product. Direct fetch and no-cache modes remain available.

- Coalesce equivalent eligible in-flight reads into one exchange. Keys include
  the opaque authentication/authorization partition, API version, method, route,
  query, representation and relevant headers. Different identities or scopes
  cannot share private results. Bound keys and waiters; canceling one waiter must
  leave others intact, and the last waiter releases owned work.
- Make HTTP response reuse opt-in with explicit freshness and invalidation;
  do not infer that every GET is cacheable. Bound entry count and accounted bytes,
  TTLs and in-flight refreshes. Honor relevant server cache controls. Do not cache
  transient or authentication failures as resource absence. Observed permission
  or visibility changes, credential/scope changes and local writes invalidate
  affected partitions or entries. Document TTL/revalidation limits for unobserved
  external changes; a cached snapshot cannot establish current authorization.
- Use event or interaction payload data when its completeness and freshness meet
  the caller's requirements; avoid fetching each related object separately.
  Deduplicate missing IDs before bounded fetches. Minimal intent selection and
  lazy member loading avoid automatic full-guild hydration.
- Pack work only through documented bulk endpoints with explicit helper policy.
  Validate item and encoded-byte limits, compatibility and endpoint constraints;
  split legal chunks, retain item correlation and report partial or indeterminate
  outcomes. Mutation merging or delaying requires caller opt-in and a documented
  equivalence rule. Do not invent a generic Discord batch API.
- Keep pagination lazy with operation-specific termination and bounded prefetch.
  Choose page sizes within documented limits based on the caller's need. Stop
  after cancellation or early iterator termination. Reconcile unchanged commands
  without writes. Use conditional requests only where supported.
- Reuse connection pools with bounded total/per-origin connections and in-flight
  exchanges. Stream attachments and large bodies rather than duplicating buffers.
  Measure bandwidth/CPU costs before selecting supported compression policies.

The optional entity cache remains a model projection, separate from HTTP response
reuse. Offer no-cache/minimal/bounded policies and explicit persistent-adapter
contracts when implemented. Isolate visibility by identity, scope and intent;
track provenance, partial data, deletion and availability. Apply sparse event
updates without erasing omitted fields; prevent older fetches from replacing
newer observations. TTL/eviction/invalidation and overload must be observable.
Entry/byte accounting bounds retained payloads; also measure actual process RSS,
including allocator, index and runtime overhead.

## Sharding in the first Gateway slice

Define shard identity, routing, assigned subsets and startup coordination during
architecture/transport work. Implement a minimal multi-shard lifecycle alongside
the first HTTP slice, using only the required models and discovery endpoints;
do not wait for the full REST catalog, cache or command framework.

Use Discord's guild routing and discovery-provided shard/session-start metadata.
Coordinate Identify concurrency and remaining starts across workers for each bot;
Resume, outbound Gateway messages and REST retain their separate rules. Keep
discovery URL reuse separate from refreshing startup allowances. Sharding
distributes events; it does not increase a bot's REST quota. [Gateway guidance](https://docs.discord.com/developers/events/gateway), checked 2026-10-15.

Give every shard an owner and generation. Provide in-process ownership plus an
injectable lease store for external coordination. Loss of a lease stops new
sends and closes/drains the old session; revalidate ownership around suspension
points and reject stale generations at coordination boundaries. Document that
external fencing cannot recall a network write already in flight. Never claim
exactly-once event or mutation delivery during failover.

Test simultaneous worker startup, expired leases, lost workers, coordinator
outages, stale completions and reconnect storms. Define drain, handoff and
restart procedures, bounded jitter and session-budget exhaustion behavior.
Changing total shard count requires a controlled topology generation and cache
resynchronization; do not promise transparent live resharding. Preserve per-shard
event ordering with explicit overflow/resync; handlers and cache I/O cannot delay
heartbeat/control work. Optional compression must bound decompressed output.

Large-bot REST guild-list partitions differ from Gateway shard IDs. Cover the
required `shard` query independently when implementing that operation; do not
reuse Gateway routing. The requirement was announced on 2026-09-15; a separate
effective date is unknown. [Discord change log](https://docs.discord.com/developers/change-log#shard-param-required-for-get-current-user-guilds-with-large-bot-sharding).

## Evidence before capacity claims

Use the independent load harness for transport, HTTP and sharded Gateway
measurements, and rerun affected scenarios when their runtime changes. Keep the harness separate from runtime products and deterministic Swift
Testing suites. It uses scripted/loopback peers, never a Discord load test.

Version workload profiles for 100, 10,000 and 1,000,000 logical accounts across
simulated workers. Specify whether accounts mean end users or bot identities;
also record guild distribution, active fraction, shards, request/event mix,
payload sizes, bursts, cache working set and subscriber speed. Stream large
logical populations through bounded active cohorts; separately qualify real
concurrent local sockets and active identities on named hardware. A simulated
million-account profile is not evidence of a million live connections.

Define numeric workload-specific budgets for each runtime change
for admitted concurrency, queued count/bytes, cache count/bytes, metadata,
connections and maximum queue age. Establish measured baseline throughput,
p50/p95/p99 latency, control delay, CPU, allocations and peak/steady RSS. Select
latency/throughput targets from those measurements and the workload requirement;
do not defer budget selection to final release. Report toolchain, hardware,
configuration, duration, offered versus admitted load and saturation point.

Correctness gates use virtual time and controlled barriers:

1. With coalescing enabled, 100 equivalent concurrent eligible reads produce one
   exchange; another identity cannot consume that result. A fresh opted-in cache
   hit produces zero exchanges; expiry/invalidation triggers the documented fetch.
2. Multiple workers sharing one credential never admit beyond injected limits.
   An unrelated eligible identity proceeds within the configured maximum
   scheduling delay even when another identity saturates its queue.
3. Queue, cache, task, connection, metadata and refresh counters never exceed
   configured per-partition or aggregate caps under ten times offered admission
   capacity. Cancellation/shutdown leaves zero owned tasks, waiters and sockets;
   retained caches/metadata follow their explicit ownership/expiry policy.
4. Bulk helpers never exceed endpoint item/byte limits, preserve required ordering
   and item correlation, and expose partial failure and ambiguous send outcomes.
5. Competing workers cannot reserve the same shard lease generation; expired
   owners cannot obtain new admission. Restart storms respect startup budgets,
   and control work meets injected deadlines during handler/cache overload.

Performance runs additionally include a 30-minute fixed-working-set local soak
with overload/recovery cycles. Owned resource counters must return to baseline
after shutdown. Record RSS samples and explain retained allocator/pool memory;
unexplained sustained growth blocks the corresponding capacity claim. Compare
throughput, latency, CPU and RSS against the versioned baseline on matching
hardware; investigate a regression greater than 10% reproduced in three runs
before accepting it or explicitly revising the documented budget.

Expose request/cache/coalescing/bulk counts, admission delay, retries, invalid
responses, queue saturation, event lag, heartbeat delay, startup-budget use and
ownership loss through consumer-configured diagnostics. Keep default metric
labels bounded (operation family/status/worker class); never label every account,
guild, request or secret. Attribute tenant details only through opt-in bounded
diagnostic sampling. Publish tested profiles and remaining bottlenecks with each
runtime release, separating design goals from measured deployment capacity.

## Transport evidence

[Owned adapters](Transport.md) now implement fail-fast bounded transport admission,
explicit body/frame/queue limits and cleanup. The optional in-process shard lease
store bounds metadata and rejects stale fences, but is not distributed storage or
a running Gateway lifecycle. Rate/cache/coalescing policies remain above transport.

The independent [local load package](../Tools/DiscordKitLoadTests/README.md) versions
100/10,000/1,000,000 logical-account profiles with finite active cohorts, operation
counts, byte/concurrency budgets and reference-host results. It measures actual
local HTTP exchanges and sampled owned slots, separately from simulated accounts.
Tenfold offered concurrency exercises refusal and subsequent recovery. No metric
uses a credential or per-account label, and no request goes to Discord.

Load diagnostics exposed native cancelled ContinuousClock sleepers retained until
their original deadline. `TransportContext.run` now uses 100 ms continuous-clock
checkpoints, preserving suspension-aware time while limiting that runtime's stale
timer history to a short interval. Generic/injected clocks are unchanged. Active
long deadlines incur up to ten checkpoint wakeups/second; settled live heap and
RSS are recorded separately, since allocators need not return freed pages at once.
The load report includes before/after diagnostic evidence. No fixed-working-set
30-minute soak, comprehensive allocation trace, cross-host scale result or
millions-of-connections capacity is inferred from this initial baseline.

## HTTP and shard implementation

[HTTP execution](HTTP.md) now implements finite rate/order admission and retry budgets,
scoped single-flight reads, opt-in payload-bounded caches, lazy pagination and explicit
invalidation. [Minimal Gateway shards](Gateway.md) deliver shared startup allowances,
fenced ownership and supervised heartbeat/control with bounded raw event ingestion.
All per-identity owners must share the documented authority; distributed atomic
contracts are injectable without shipping a durable adapter. The independent load
package extends local profiles, separating logical accounts from physical exchanges.
No broad deployment capacity or 30-minute sustained-load qualification follows from
short scripted/local measurements; the evidence requirements above remain in force.

## Request admission and retained results

[Gateway requests](Gateway.md) keep application sends, presence updates, all-member
requests and server opcode cooldowns separate from REST and Identify scheduling.
Per-connection control headroom protects heartbeat processing; pending requests,
retained response events/bytes and correlation/admission metadata are finite.
Shared bot identities require shared authority for per-bot/per-guild member quotas.
Nonces and generation fencing reject stale keyed work; failed or directly sent
no-nonce soundboard/channel-info keys cannot be reused within a generation. A
successfully completed no-nonce key may be reused, with an explicit duplicate/
unsolicited-response ambiguity because Discord supplies no correlation nonce.
Timeout, cancellation and disconnect preserve bounded partial results and never
imply that a submitted command was withdrawn from Discord. These finite policies
and synthetic load observations do not establish production sharded capacity.

## Consumer bounds and measured scope

[Consumer composition](Client.md) adds independently bounded broadcast queues,
per-shard ordered handler execution and shared client/session reservation ceilings.
Optional cache retention and refresh admission are scoped by credential, intents
and visibility generation, with both per-identity and aggregate limits. Local
mutations and observed visibility changes fence old refreshes; cached data and
permission calculations never establish current authorization.

The [load harness](../Tools/DiscordKitLoadTests/README.md) uses fixed sets of 20
entity keys per scope, at most four actual opaque scopes and 64 offered refresh
callers per scope. These are bounded process-local cohorts. The logical million
served-user profile does not create a million identities, tasks or connections.
Finite normal/burst cache and recovery runs retain actual process RSS separately
from accounted projection bytes, and repeated Gateway scripts remain a separate
lifecycle measurement. Handler/reducer/network throughput and distributed fairness
require their own measurements; no whole-client capacity follows from the cache
and broadcast subset.

The [thirty-minute cache/broadcast run](../Tools/DiscordKitLoadTests/Baselines/soak-accounts-1000000-1800s-burst.json)
completed 238,427 rounds in 1,800.004 seconds, with 64 peak retained entries,
72,512 accounted bytes and zero owned cache/refresh/subscription/queue resources
after shutdown. All 20 RSS samples in the final five minutes were 8,781,824 bytes;
process peak RSS was 9,715,712 bytes. Completed refresh reads used 87.5% fewer
loaders through coalescing, with overload refusals reported separately. The
[environment record](../Tools/DiscordKitLoadTests/Baselines/soak-1800s-environment.json)
states source drift and unmeasured paths. This qualifies the recorded local subset
and working set; broader runtime and deployment gates above remain independent.
