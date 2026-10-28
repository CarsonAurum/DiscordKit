[//]: # "File: Sources/DiscordNIOTransport/DiscordNIOTransport.docc/Guides/NetworkAdapters.md | Created by Carson Rau. | Copyright (c) 2026 Aurum Studios. | https://aurum-studios.com"

# Owning HTTP and WebSocket adapters

Choose explicit transport budgets, retain response bodies correctly and shut down native resources.

## Overview

### Select one shared transport authority

``NIOHTTPTransport`` pools HTTP/1.1 connections within the total and per-origin limits in ``NIOHTTPConfiguration``. Reuse an instance when several clients must share the same connection budget. Separate instances have separate limits; a bot fleet still needs a shared rate coordinator above HTTP.

The following factory performs no network requests. It does allocate the transport's event loop and TLS context, so its eventual owner must await `close()`.

```swift
import DiscordNIOTransport

/// Creates one shared pool with explicit upload, response and connection limits.
func makeHTTPTransport() throws -> NIOHTTPTransport {
    let limits = try NIOHTTPConfiguration(
        maximumConnections: 16,
        maximumConnectionsPerOrigin: 4,
        maximumRequestBytes: 8_388_608,
        maximumResponseBytes: 8_388_608
    )
    return try NIOHTTPTransport(configuration: limits)
}
```

HTTP uploads are collected within the configured request bound before sending. A producer failure therefore sends no upload. Responses preserve duplicate headers and expose a single-use pull body. Consume that body to EOF or explicitly close it on every exit; an abandoned body retains its pool slot. Cancellation or expiration during body reading discards the connection. The deadline supplied to execution covers both the exchange and later response reads.

Redirect responses are returned to the caller. There is no automatic redirect, decompression, cookie jar, proxy configuration or retry. Higher-level code decides whether an operation is safe to repeat after a transport failure, especially when the server may have applied a mutation.

### Keep WebSocket control independent of consumers

``NIOWebSocketTransport`` validates an RFC 6455 upgrade and returns a connection over the portable WebSocket contract. ``NIOWebSocketConfiguration`` independently limits connections, full messages, pending application writes, control replies and upgrade headers. Count limits alone are insufficient: the receive queue also shares a total payload-byte cap.

```swift
import DiscordNIOTransport

/// Creates a bounded adapter; the caller later opens and closes its connections.
func makeWebSocketTransport() throws -> NIOWebSocketTransport {
    let limits = try NIOWebSocketConfiguration(
        maximumConnections: 4,
        maximumMessageBytes: 1_048_576,
        maximumBufferedMessages: 8,
        maximumPendingWrites: 4
    )
    return try NIOWebSocketTransport(configuration: limits)
}
```

Fragmented frames become one bounded message. Ping/pong processing remains independent of a slow application reader. If the bounded receive queue overflows, the connection closes; the adapter does not silently lose messages or accumulate producer tasks. Gateway compression, reconnect, resume and protocol heartbeat policy belong to their respective protocol clients.

A connect context covers connection and upgrade only. Every returned connection operation takes its own context. Await connection cleanup and then transport cleanup when retiring an owner; transport closure also drains its connecting work.

### Preserve certificate and hostname verification

``TLSPolicy`` performs full verification and uses default trust roots unless the caller explicitly supplies PEM roots. Despite the parameter name `additionalTrustRootsPEM`, supplied roots replace the defaults. Use that parameter only for a deliberately selected private PKI or controlled test trust store. It does not disable hostname verification, and there is no insecure verification setting.

Do not place bearer credentials in diagnostic URLs or manually supply adapter-owned Host, framing or WebSocket upgrade headers. Adapter failures are deliberately redacted because native errors can contain private request details.

### Test ownership, limits and failure

Use a local HTTP/WebSocket peer to verify duplicate headers, arbitrary body chunking, close-before-EOF, rejected upgrades, cancellation and terminal overflow. Use a private local trust root when testing TLS. A loopback test establishes behavior on that host; real proxy, mobile lifecycle, minimum OS and remote service behavior need their own evidence. See the [transport ownership guide](https://github.com/CarsonAurum/DiscordKit/blob/main/Docs/Transport.md) for the repository's current adapter scope.
