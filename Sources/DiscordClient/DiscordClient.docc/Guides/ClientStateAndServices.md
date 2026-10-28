[//]: # "File: Sources/DiscordClient/DiscordClient.docc/Guides/ClientStateAndServices.md | Created by Carson Rau. | Copyright (c) 2026 Aurum Studios. | https://aurum-studios.com"

# Composing services, projections and event consumers

Keep request policy, optional observations and user handlers under separate bounded owners.

## Overview

### Share credential authority across clients

``ClientAuthority`` retains one bot's startup ledger and opcode authority. Reuse it across client instances and topology handoffs. Inject common external coordinators and leases for multiple processes; coordinator failure must not create fresh independent budgets. ``ClientResourceBudget`` can span different bot identities and bounds clients, actual sessions and raw queue ceilings.

REST rate authority remains a separate shared owner. Sharding does not raise its quotas. ``ServiceContext`` executes typed REST descriptors before or after Gateway readiness and preserves their ordinary authentication, retry, deadline and invalidation behavior.

### Add entity state only when useful

``ClientCacheProjection`` bridges selected Gateway and interaction observations into DiscordCache without giving the cache an upward dependency. It projects bounded partial guild/channel/thread/member/role/user/message facts and explicit unavailability/deletion observations. Unknown events remain available to consumers even when the optional reducer ignores them.

Scope includes credential generation, intents and visibility generation. Without MESSAGE_CONTENT, protected message fields are conservatively redacted rather than treating an old cached field as newly authorized. Explicit usable exception data can satisfy an eligible read without a redundant fetch. Child arrays do not become complete guild state by assumption.

Use the projection's service wrapper for conservative invalidation before and after local writes, including failed or uncertain writes. Direct REST calls need explicit entity invalidation. A bot write and another bearer scope do not automatically share visibility or invalidate one another's HTTP snapshots.

### Give features separate subscriptions

The event hub gives each feature a finite queue. Use independent subscriptions for metrics, business handlers and state observers rather than several iterators into one raw ingestion queue. Publication never invokes application callbacks and preserves per-shard order without a global exactly-once promise.

A handler dispatcher can serialize callbacks per complete shard identity while allowing different shards to progress. Bound callback count and pending bytes and share aggregate handler authority when several dispatchers coexist. A callback that spawns unbounded application tasks defeats those bounds; own additional work in the caller's structured lifetime.

### Recover from lost continuity

Overflow terminates a subscription by default with a resynchronization requirement. Fetch the authoritative state needed by that feature, reconcile it and deliberately subscribe again. Duplicate or missed upstream events remain possible even when local buffers never overflow. Persistent business actions require application-owned idempotency and durable state.

### Observe limits without leaking identities

Client, hub and cache snapshots expose bounded aggregate accounting. Raw bytes, event copies, retained payload bytes and real process RSS measure different things. Measure each before capacity claims, and avoid high-cardinality credential/resource labels. A deterministic local soak proves its measured working set only; it does not certify live fleet behavior.

Test service access without READY, sparse projection ordering, redaction, invalidation racing reads, independent slow consumers, handler failure and shared aggregate limits. The [client contract](https://github.com/CarsonAurum/DiscordKit/blob/main/Docs/Client.md) describes detailed defaults and refresh semantics.
