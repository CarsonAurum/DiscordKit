<!--
File: Docs/Parity/changes/2026-10-16-http-gateway.md
Created by Carson Rau.
Copyright (c) 2026 Aurum Studios.
https://aurum-studios.com
-->

# 2026-10-16 — HTTP execution and early sharded Gateway

Local support date and upstream verification date: **2026-10-16**. Upstream announcement/effective
dates for these pre-existing contracts: **unknown**. No local date is used as their
introduction date. Explicit versions remain REST 10, Gateway 10 and Voice Gateway 8;
voice support is unchanged and unsupported.

Previous behavior was portable values and generic owned transports without Discord
operations or sessions. Current behavior adds independent Models/HTTP/Gateway products:

- `DiscordEndpoints.currentUser()` retrieves GET /users/@me with bot or OAuth bearer
  authentication (`identify`; email visibility requires `email`). The User model is
  a partial typed projection preserving all unknown raw fields and exact numbers.
- `DiscordEndpoints.currentApplication()` retrieves GET /applications/@me with bot
  authentication. Nested/team/installation application fields remain partially typed.
- `GatewayEndpoints.bot()` retrieves GET /gateway/bot with bot authentication and
  validates the complete discovery URL/shard/session-start envelope. No intents or
  guild permissions are required for these discovery/read operations.
- `RESTClient` runs typed/raw operations through fixed-origin auth, bounded bodies,
  shared rate/order admission, finite safe retries, pagination/polling, scoped read
  coalescing and opt-in bounded freshness. Unsafe ambiguous mutation outcomes require
  reconciliation. Raw endpoints and bulk metadata create no catalog parity claim.
- `GatewayShard`/`GatewayBot` supervise JSON v10 Identify/Resume, Hello, heartbeats,
  ACKs, reconnect, invalid sessions, bounded raw dispatch ingestion, lease fencing and
  shared startup budgets. Privileged intents require the existing portal approvals.
  This is the early lifecycle slice, not complete dispatch/request/model support.

The written-reference endpoint inventory records current-user/application as **partial**
and Gateway bot discovery as **supported**. All other individually discovered records,
including duplicate preview representations, retain their prior statuses. Local runtime
and generic infrastructure support does not automatically mark whole resource pages,
protocol-state sections, opcodes, model fields, permissions or intents supported.

Official contracts verified:
[reference/versioning/errors](https://docs.discord.com/developers/reference),
[rate limits](https://docs.discord.com/developers/topics/rate-limits),
[users](https://docs.discord.com/developers/resources/user),
[applications](https://docs.discord.com/developers/resources/application),
[Gateway](https://docs.discord.com/developers/events/gateway),
[Gateway controls](https://docs.discord.com/developers/events/gateway-events),
[opcodes/close codes](https://docs.discord.com/developers/topics/opcodes-and-status-codes),
[change log](https://docs.discord.com/developers/change-log).
Source snapshot hashes/membership remain pinned to the original discovery baseline; current semantic
verification and implementation evidence are an overlay, not regenerated provenance.

Evidence is in root `HTTPContractTests`, `HTTPResourceTests`, `RESTClientTests`,
`ReadReuseTests`, `RateLimitTests`, `RateLimitStoreContractTests`, `GatewayProtocolTests`, `GatewayStartupTests` and
`GatewayRuntimeTests`, plus real Foundation/NIO WebSocket loopback close/abort suites.
The independent RESTOnly package is built without executing authenticated operations.
The local load package records bounded account cohorts and actual request savings;
none of these tests connects to Discord or requires real credentials.

Product adoption is additive: existing Transport connections still work. The optional
`WebSocketSessionConnection` capability preserves peer close codes and session-aware
reconnect behavior in owned adapters; generic connections conservatively re-Identify.
NIO upgrade request parts are now enqueued without a suspension between headers and
the end marker, fixing a connection failure when a fast peer starts its upgrade early.
Adopters must share opaque authorization identity and rate/order/startup authority
across clients/workers, honor bounds and close separately owned dependencies.
Exhaustive switches over `MutationUncertainty` must add
`serverErrorAfterSubmission`; unsafe HTTP 5xx outcomes can be indeterminate.
Ambiguous mutations are never automatically replayed.

Remaining gates: full typed REST/resource/event catalogs, live protocol conformance,
other hosts/devices/minimum OS qualification, durable coordinator adapters, complete
allocation traces and sustained-load capacity certification. See [HTTP](../../HTTP.md)
and [Gateway](../../Gateway.md); raw escape hatches do not close these gates.
