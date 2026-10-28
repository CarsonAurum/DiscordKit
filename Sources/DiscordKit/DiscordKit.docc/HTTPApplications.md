[//]: # "File: Sources/DiscordKit/DiscordKit.docc/HTTPApplications.md | Created by Carson Rau. | Copyright (c) 2026 Aurum Studios. | https://aurum-studios.com"

# Receive signed HTTP interactions

Preserve exact request bytes and reserve independent acknowledgement capacity.

```sh
swift build --package-path Examples/HTTPApp
```

The [HTTPApp consumer](https://github.com/CarsonAurum/DiscordKit/tree/main/Examples/HTTPApp)
selects Commands/Interactions/HTTP with an injected NIO listener and no Gateway,
Client or Cache. It does not register its ping command when built or started.
For deployment, configure the application ID, public verification key, registered
command and public HTTPS Interactions Endpoint URL in the Developer Portal.

Forward the original timestamp/body/signature bytes unchanged. Authenticate before
decoding, answer PING, then route a normalized context. The example bounds
connections to 64, handlers to 32, and acknowledgement work to a separate 32 slots.
It binds loopback only when explicitly configured; routine CI never starts it.

The initial response window is three seconds from receipt. Defer slow work while
eligible and provide an explicit continuation sink and outer deadline; a defer
does not grant unlimited execution. One actor owns the acknowledgement and prevents
competing initial replies. Await listener/body/handler closure on cancellation.
See <doc:CommandsComponents> and the
[interaction contract](https://github.com/CarsonAurum/DiscordKit/blob/main/Docs/Interactions.md).
