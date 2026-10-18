# ``DiscordClient``

Compose REST services, supervised shards, optional projections and independent event consumers.

## Overview

DiscordClient supplies a single-use consumer runtime over independently adopted HTTP and Gateway products. Construction stores injected owners and starts no tasks, discovery or sockets. Explicit `run` owns the session; `shutdown` awaits cleanup. Cache projection is optional, and services remain usable without Gateway readiness.

Follow <doc:SupervisedClient> for application lifetime and <doc:ClientStateAndServices> for authority sharing, projection and event consumers. The [GatewayBot example](https://github.com/CarsonAurum/DiscordKit/tree/main/Examples/GatewayBot) contains a complete composed host.

## Topics

### Consumer runtime

- <doc:SupervisedClient>
- <doc:ClientStateAndServices>

### API reference

- <doc:APIReference>
