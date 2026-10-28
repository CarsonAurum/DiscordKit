[//]: # "File: Sources/DiscordRPC/DiscordRPC.docc/Guides/DesktopSessions.md | Created by Carson Rau. | Copyright (c) 2026 Aurum Studios. | https://aurum-studios.com"

# Connecting a desktop RPC session

Keep desktop discovery, application identity and user authorization separate.

## Overview

### Inject the local connection boundary

``RPCClient`` takes an ``RPCConnector`` and a monotonic clock. ``RPCIPCConnector`` supports bounded candidate selection through an injected opener; ``RPCWebSocketConnector`` takes an explicit approved loopback port and origin. A connector creates a fresh connection for each session generation. No remote Gateway connection substitutes for this local host.

```swift
import DiscordCore
import DiscordRPC

/// Builds an unconnected desktop RPC owner without opening native resources.
func makeDesktopClient(
    applicationID: ApplicationID,
    connector: any RPCConnector
) throws -> RPCClient<ContinuousClock> {
    try RPCClient(
        applicationID: applicationID,
        clock: ContinuousClock(),
        connector: connector,
        maximumPendingRequests: 32,
        maximumPendingBytes: 262_144,
        maximumEvents: 64,
        maximumEventBytes: 524_288
    )
}
```

``RPCDiscovery`` constructs candidate paths from explicit platform/environment inputs. On Unix, an application may implement ``RPCIPCOpening`` using its selected native Unix transport. Windows path discovery is not Windows named-pipe I/O; that host requires its own qualified opener. Do not treat a path existing or port answering as an authenticated user session.

### Separate READY from consent

`connect(context:)` sends an RPC v1 handshake and validates READY. READY proves the selected protocol exchange completed, not that requested OAuth scopes are granted. Project the result using ``RPCReady`` when nested schema validation is needed.

```swift
import DiscordRPC
import DiscordTransport

/// Connects once and returns validated READY data; the caller retains session ownership.
func connectDesktop(
    client: RPCClient<ContinuousClock>,
    clock: ContinuousClock
) async throws -> RPCReady {
    let context = TransportContext(
        clock: clock,
        deadline: clock.now.advanced(by: .seconds(10))
    )
    return try RPCReady(value: await client.connect(context: context))
}
```

Use ``RPCRequest`` authorization/authentication builders for the documented local user flow. A registered application ID is not a bot credential. OAuth code exchange and secure token storage are application/backend responsibilities; ``RPCUserAccessToken`` wraps an already obtained user token and redacts diagnostics. Scope names and desktop application approval remain operation-specific.

### Own reconnect and shutdown

After connecting, the client owns one reader and a demand-driven ordered writer. It bounds pending requests and queued events by both count and bytes. `close()` cancels owned runtime work, resolves waiters and awaits connection cleanup. Call it on every exit, including startup failure in a surrounding application owner.

`reconnect(context:)` creates a fresh generation. Authenticate and subscribe again; neither subscriptions nor ambiguous mutations are silently restored or replayed. A canceled request can have already executed in Discord, so refresh authoritative state before deciding whether to submit a replacement mutation.

Loopback scripted peers can verify handshake, bounded framing, mismatched READY, reconnect generations and cleanup. Desktop-host approval, actual Discord behavior and Windows pipe support remain separate qualification. See the [independent desktop example](https://github.com/CarsonAurum/DiscordKit/tree/main/Examples/RPCApp).
