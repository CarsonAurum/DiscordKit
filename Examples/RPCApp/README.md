<!--
File: Examples/RPCApp/README.md
Created by Carson Rau.
Copyright (c) 2026 Aurum Studios.
https://aurum-studios.com
-->

# Independent desktop RPC adoption

Build with `swift build --package-path Examples/RPCApp`. The executable only
constructs local request/device values and prints redacted descriptions. It opens
no socket, approval dialog or authenticated session. Its selected source graph
contains Core, Transport, RPC and CertifiedDevices, without HTTP, Gateway,
Client, Cache, OAuth, Interactions, Commands or concrete platform transports.

Inject an `RPCConnector` into `RPCApp.makeClient` in a desktop composition root.
For native Unix sockets, adopt DiscordUnixPlatform separately and implement
`RPCIPCOpening.open(path:context:)` by calling `UnixIPCTransport.connect` with
the supplied path/context. Construct `RPCIPCConnector` with that opener and an
explicit environment/index budget. Windows names are modeled, but the owned
Windows named-pipe I/O provider remains unimplemented; inject a separately
qualified provider before advertising Windows operation.

Await `client.connect(context:)`, perform the documented AUTHORIZE/OAuth code
exchange/AUTHENTICATE sequence with approved local user scopes, then call
`client.request` and pull `client.nextEvent`. OAuth/backend code exchange is a
separate adoption decision. Always await `client.close()` on success or error.
Explicit reconnect rejects old pending calls and requires fresh authentication
and subscriptions. No bot token can stand in for local user authorization.

See [RPC ownership and host limits](../../Docs/RPC.md) and
[Certified Devices publication](../../Docs/CertifiedDevices.md). Deprecated
WebSocket access requires legacy beta approval and a registered Origin. The
port-range discrepancy remains open; select a documented surface-specific port.
