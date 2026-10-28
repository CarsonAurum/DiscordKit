[//]: # "File: Sources/DiscordKit/DiscordKit.docc/RESTOnly.md | Created by Carson Rau. | Copyright (c) 2026 Aurum Studios. | https://aurum-studios.com"

# Build a REST-only consumer

Adopt DiscordHTTP without starting a Gateway session.

The [RESTOnly consumer](https://github.com/CarsonAurum/DiscordKit/tree/main/Examples/RESTOnly)
selects Core/Models/Transport/HTTP and FoundationTransport. Build it independently:

```sh
swift build --package-path Examples/RESTOnly
```

Building executes no request. Running this particular example reads
DISCORD_BOT_TOKEN and, when present, performs current-user/current-application
reads over API v10. Supply credentials only in an explicitly authorized environment.
Create/install the application through the Developer Portal; select the bot
permissions actually required by your resource operations.

Share the opaque credential identity, rate coordinator and aggregate resource
authority across clients using the same credential. Bound request/body queues,
coalescing and retry budgets; pagination is lazy and explicitly bounded. Sharding
does not increase REST quotas. Keep mutation ordering and indeterminate outcomes
observable; a timeout after an ambiguous send does not authorize replay.

The executable closes its coordinator and transport. A deployment that shares
adapters needs one separate cleanup owner. See the repository's
[HTTP contract](https://github.com/CarsonAurum/DiscordKit/blob/main/Docs/HTTP.md)
for actual rate admission and retry behavior, and <doc:DeploymentState> for freshness.
