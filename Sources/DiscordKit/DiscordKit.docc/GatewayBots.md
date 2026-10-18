# Own a supervised Gateway bot

Select explicit intents, bounded subscriptions and shared startup ownership.

```sh
swift build --package-path Examples/GatewayBot
```

The [GatewayBot consumer](https://github.com/CarsonAurum/DiscordKit/tree/main/Examples/GatewayBot)
uses DiscordClient, an optional scoped cache, HTTP discovery and owned adapters.
Its configuration selects the guilds intent. Request privileged member, presence
or message-content data only with the portal configuration and Discord approval
required by the [Gateway reference](https://docs.discord.com/developers/events/gateway).
Build checks do not run this credential-bearing example.

Subscribe before run starts. Bound handlers, subscriber queues and cache bytes;
handle overflow/resync signals before reading state as current. Inject shared
credential/startup/opcode budgets and shard leases. In-process authorities do not
establish cross-worker coordination or fleet failover.

The example receives READY, performs one current-user service read, and awaits
shutdown and adapter cleanup. A mobile foreground compile cannot promise an
unconditional background heartbeat. Resume/reconnect may invalidate freshness;
use an explicit bounded refresh. See <doc:DeploymentState> and the
[client contract](https://github.com/CarsonAurum/DiscordKit/blob/main/Docs/Client.md).
