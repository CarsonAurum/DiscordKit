[//]: # "File: Sources/DiscordClient/DiscordClient.docc/Guides/SupervisedClient.md | Created by Carson Rau. | Copyright (c) 2026 Aurum Studios. | https://aurum-studios.com"

# Running a supervised consumer client

Give one structured owner responsibility for discovery, shard tasks and final cleanup.

## Overview

### Configure explicitly

``ClientConfiguration`` requires explicit Gateway intents and validates topology, shard and ingestion limits. No intent is enabled implicitly; privileged intents still require the application's portal configuration and approval. ``DiscordClient`` receives the bot token, services, WebSocket transport, clock, leases, shared ``ClientAuthority`` and event hub.

```swift
import DiscordClient
import DiscordGateway

let configuration = try ClientConfiguration(
    intents: [.guilds], maximumShards: 16, ingestionBatchSize: 32)
let budget = try ClientResourceBudget(maximumClients: 4,
    maximumShards: 16, maximumRawEvents: 8_192,
    maximumRawBytes: 64 * 1_024 * 1_024)
```

These values start no work. Select raw queue ceilings so the complete discovered topology can fit the shared budget. Counts describe actual clients and sessions, not logical users served by a bot.

### Subscribe, run and join

Subscribe to the injected event hub before starting `run` when initial READY and guild observations matter. Run the client and application consumers as children of one structured task group. When a consumer finishes or fails, request `shutdown`, then await the run task and observe its result. The [complete example](https://github.com/CarsonAurum/DiscordKit/blob/main/Examples/GatewayBot/Sources/GatewayBot/GatewayBot.swift) shows this composition with optional cache projection.

`run` reserves a client slot before discovery, fetches current Gateway discovery, validates selected topology, reserves raw queue ceilings and supervises selected shards and ingestion children. `snapshot` returns bounded phase/queue/request observations; readiness can change immediately afterward, so a snapshot cannot promise a later send will succeed.

The client is single-use. A stopped or failed client cannot run again. Construct a replacement while preserving credential startup/opcode/rate authorities and choosing a fresh cache visibility domain. A re-created client must not reset consumed Identify budget.

### Await shutdown on every exit

`shutdown` is idempotent and waits for discovery cancellation, socket closure, child completion, lease release, subscription cleanup and the optional owner cleanup closure. Cancelling a shutdown caller does not abandon the shared cleanup. Calling shutdown before run performs no discovery or leasing.

A noncancellation cleanup failure remains observable through run even if another child cancelled first. Inspect that result before transferring work to another worker. A state reducer or cleanup callback must not await shutdown of its own run, because that would await itself. Handler tasks are separate consumers and may request shutdown.

### Own shared resources carefully

The client owns active socket connections. Injected transports, REST authorities, caches and connectors can be shared. Supply a cleanup closure only when this client owns those dependencies' full lifetime. The closure and refresh loaders must cooperate with cancellation; do not hide cleanup in detached tasks.

Test inert construction, shutdown-before-run, repeated shutdown, discovery failure, lease loss, fatal shard failure, cancelled callers, concurrent cleanup and replacement preserving shared authority with local scripted peers.
