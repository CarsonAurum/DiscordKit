[//]: # "File: Sources/DiscordKit/DiscordKit.docc/DesktopRPC.md | Created by Carson Rau. | Copyright (c) 2026 Aurum Studios. | https://aurum-studios.com"

# Compose a desktop RPC application

Use a real local Discord host with explicitly injected IPC ownership.

```sh
swift build --package-path Examples/RPCApp
```

The [RPCApp consumer](https://github.com/CarsonAurum/DiscordKit/tree/main/Examples/RPCApp)
constructs request/device values and prints redacted descriptions only. It opens
no IPC endpoint, user authorization dialog or authenticated session. Its selected
Core/Transport/RPC/CertifiedDevices graph excludes HTTP/Gateway/OAuth and adapters.

Inject RPCConnector and explicitly connect. Native Unix consumers may separately
adopt DiscordUnixPlatform; Windows named-pipe path modeling does not implement
owned Windows named-pipe I/O. Perform the documented local user authorization and
fresh authentication before sending applicable commands. A bot token does not
grant local user consent. Close the client on success/error/cancellation; explicit
reconnect rejects stale pending calls and requires fresh subscriptions.

Certified-device publication replaces complete arrays with bounded prioritized
ownership. Real desktop/hardware qualification, legacy WebSocket beta access,
port-range clarification and presence-clearing semantics remain gates. Mobile or
browser compilation does not create a desktop Discord host. See the
[RPC contract](https://github.com/CarsonAurum/DiscordKit/blob/main/Docs/RPC.md).
