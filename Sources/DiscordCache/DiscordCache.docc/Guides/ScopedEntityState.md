# Maintaining scoped entity state

Treat cached resources as bounded observations with explicit visibility and freshness.

## Overview

### Choose a finite policy and scope

``EntityCache`` is an actor with an injected clock. Its default `.minimal` policy retains up to 64 entries/256 KiB aggregate, 16 entries/64 KiB per identity and a maximum 30-second TTL. `.noCache` retains no entity state, while `.bounded` permits deliberately larger finite limits.

``CacheScope`` includes an opaque credential-generation identity, exact intents and visibility generation. Reuse a scope only for the same authorization interpretation. Rotate visibility generation for a fresh client sequence domain, and rotate identity when credentials change.

```swift
import DiscordCache

let clock = ContinuousClock()
let cache = try EntityCache(clock: clock, policy: .minimal)
let scope = CacheScope(identity: "synthetic-grant-generation-1", intents: 0)
let key = EntityKey(kind: .user, id: 42)
let observation = EntitySnapshot(fields: ["username": .string("reader")])
_ = try await cache.apply(observation, for: key, scope: scope)
let snapshot = await cache.value(for: key, scope: scope)
assert(snapshot?.fields["username"] == .string("reader"))
await cache.close()
```

This local example starts no loader or network work. It is a partial observation, not a complete User or proof that the caller can see a live user.

### Preserve sparse, nullable and redacted state

``EntitySnapshot`` records completeness, nullable keys, redacted keys, availability, provenance and optional shard-local ordering. A partial patch preserves omitted keys; a complete replacement replaces the field set. Nested JSON is replaced as one value, not deep-merged. Explicit null is accepted only for declared nullable keys. Redaction removes old retained content instead of preserving data the current scope can no longer see.

Duplicate/stale observations are ignored while their ordering evidence remains retained. Eviction and expiry can remove that evidence. Socket generation and shard sequence belong to their source domain; never compare arbitrary sequences across unrelated clients or shards as one global order.

### Refresh explicitly and fence stale completions

`refresh` uses eligible fresh event/interaction data before invoking an injected loader. Equivalent scoped reads share finite refresh work. Defaults cap 32 aggregate/eight per-identity refreshes and 512 aggregate/128 per-refresh waiters. One cancelled waiter does not cancel others; the last cancellation and `close` join loader cleanup. Loaders must cooperate with cancellation.

Newer observations/invalidation fence old fetch completion, including after eviction. An unrelated accepted observation can conservatively supersede a fetch; the caller decides whether to retry. Errors are not cached as absence and no background refresh loop starts automatically.

### Invalidate before stale authorization leaks

Invalidate on observed permission, membership, guild availability, channel deletion, credential or visibility changes. Direct REST writes require explicit entity invalidation; DiscordClient's optional projection service wrapper supplies conservative before/after invalidation for local writes. HTTP response-byte reuse is a separate owner and policy.

TTL only limits unobserved staleness. Cache hits never establish current authorization. Accounted bytes include serialized data and bounded metadata, while allocator/index/task overhead requires real RSS measurement. Optional persistence is an injected contract; monotonic expiry cannot simply survive process restart.

Test sparse patches, valid/invalid nulls, redaction, tombstones, LRU/TTL boundaries, competing scopes, stale completion, cancelled waiters and aggregate limits using virtual clocks and barriers.
