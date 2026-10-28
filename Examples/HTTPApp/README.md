<!--
File: Examples/HTTPApp/README.md
Created by Carson Rau.
Copyright (c) 2026 Aurum Studios.
https://aurum-studios.com
-->

# Signed HTTP application

This independently resolved example imports Commands/Interactions and a NIO ingress
adapter. It has no Gateway dependency, bot token, automatic command registration or
authenticated outbound request. Build without running:

```sh
swift build --package-path Examples/HTTPApp
```

Set `DISCORD_APPLICATION_ID`, `DISCORD_PUBLIC_KEY` and optionally `DISCORD_HTTP_PORT`
(default 8080), then run the example behind an HTTPS reverse proxy. Forward the
original body and both signature headers unchanged. Configure HTTP interaction
delivery in Discord and explicitly register the supplied `/ping` definition using
`CommandReconciler` from a separately authorized registration tool. This application
answers authenticated PING and replies to `/ping` with an ephemeral message.

At most 32 structured handler tasks and 64 accepted connections exist. Initial
acknowledgement has a separate 32-slot budget. The example uses immediate replies;
long-running consumers can configure explicit early auto-defer and inject REST
continuation mechanics. See [interaction contracts](../../Docs/Interactions.md).
Listener/body/response cleanup is explicit; deployment owns process supervision,
TLS, application keys and any durable duplicate authority. No live deployment or
other-host qualification is implied by a local build.
