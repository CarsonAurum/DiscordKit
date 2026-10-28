[//]: # "File: Sources/DiscordTransport/DiscordTransport.docc/DiscordTransport.md | Created by Carson Rau. | Copyright (c) 2026 Aurum Studios. | https://aurum-studios.com"

# ``DiscordTransport``

Define bounded, injectable HTTP, WebSocket, datagram, ingress and IPC ownership contracts.

## Overview

DiscordTransport is the protocol boundary between portable policy and concrete I/O. It supplies pull-based bodies, clock/deadline contexts, explicit cleanup and shard ownership. Choose a Foundation, NIO, Unix or host adapter separately; importing this product does not select a backend or start I/O.

Start with <doc:TransportOwnership>, then use <doc:ImplementingAdapters> when supplying a backend or a deterministic test peer.

## Topics

### Transport design

- <doc:TransportOwnership>
- <doc:ImplementingAdapters>

### API reference

- <doc:APIReference>
