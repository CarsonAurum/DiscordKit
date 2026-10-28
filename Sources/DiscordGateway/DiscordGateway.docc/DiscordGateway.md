[//]: # "File: Sources/DiscordGateway/DiscordGateway.docc/DiscordGateway.md | Created by Carson Rau. | Copyright (c) 2026 Aurum Studios. | https://aurum-studios.com"

# ``DiscordGateway``

Supervise bounded Gateway v10 sessions, typed commands and ordered event delivery.

## Overview

DiscordGateway owns protocol state, heartbeat/resume policy, shared Identify/opcode admission, correlated requests and bounded raw/broadcast event interfaces. It does not choose a concrete WebSocket backend or infer intents. REST-only applications remain independent of it.

Start with <doc:GatewayLifecycle>, choose event ownership in <doc:GatewayEventsAndHandlers> and use <doc:GatewayCommandsAndRequests> for outbound work. DiscordClient composes this lower-level machinery when you want a supervised multi-shard consumer.

## Topics

### Gateway operation

- <doc:GatewayLifecycle>
- <doc:GatewayEventsAndHandlers>
- <doc:GatewayCommandsAndRequests>

### API reference

- <doc:APIReference>
