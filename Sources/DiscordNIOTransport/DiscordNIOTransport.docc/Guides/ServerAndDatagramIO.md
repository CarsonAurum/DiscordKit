[//]: # "File: Sources/DiscordNIOTransport/DiscordNIOTransport.docc/Guides/ServerAndDatagramIO.md | Created by Carson Rau. | Copyright (c) 2026 Aurum Studios. | https://aurum-studios.com"

# Serving requests and preserving datagrams

Adopt native UDP and HTTP listeners with bounded admission and explicit resource transfer.

## Overview

### Bind UDP with literal addresses

``NIODatagramTransport`` preserves complete datagrams, including empty payloads. It accepts literal IPv4/IPv6 addresses and does not resolve DNS. Port zero selects an ephemeral local port. Each bound socket owns one event-loop thread.

```swift
import DiscordNIOTransport
import DiscordTransport

/// Binds an ephemeral loopback socket; its caller must await close after use.
func openLocalDatagrams() async throws -> NIODatagramTransport {
    let clock = ContinuousClock()
    let context = TransportContext(
        clock: clock,
        deadline: clock.now.advanced(by: .seconds(5))
    )
    return try await NIODatagramTransport.bind(
        maximumDatagramBytes: 1_500,
        maximumPendingDatagrams: 32,
        maximumPendingBytes: 48_000,
        context: context
    )
}
```

The policy admits at most 65,507 payload bytes, but operating-system limits can be lower. Select a realistic MTU-level application bound and handle send failure. One writer and one reader may be active. A second writer fails immediately; concurrent reads are rejected. Cancellation of an admitted operation closes the socket. Overflow or oversized input terminates it rather than truncating or silently dropping packets.

A successful send means the local write completed, not that the peer received the datagram. There are no retries or delivery guarantees. Authenticate the expected remote address in the protocol layer; a received address alone does not prove application identity.

### Transfer HTTP response ownership deliberately

``NIOHTTPIngress`` accepts one HTTP/1.1 request per connection. Its aggregate connection cap includes sockets still parsing, queued complete requests and exchanges already transferred to application code. It separately bounds pending requests, headers and request/response bodies.

```swift
import DiscordNIOTransport
import DiscordTransport

/// Opens a local bounded listener; accepted exchanges have separate cleanup ownership.
func openLocalIngress() async throws -> NIOHTTPIngress {
    let clock = ContinuousClock()
    return try await NIOHTTPIngress.bind(
        maximumConnections: 32,
        maximumPendingRequests: 16,
        maximumBodyBytes: 1_048_576,
        context: TransportContext(
            clock: clock,
            deadline: clock.now.advanced(by: .seconds(5))
        )
    )
}
```

Accepting transfers an exchange with an exactly-once responder. Application work runs outside the listener's event loop. The application must either send one response or close the responder, including when signature verification or routing fails. Closing the listener closes unaccepted connections and ends acceptance; exchanges already handed to the application remain separately owned and must be drained or closed by their handlers.

The listener buffers within explicit body limits. It does not terminate TLS, support keep-alive reuse, handle upgrades/trailers or accept `Expect`. A deployment may place a configured TLS reverse proxy in front of it, preserving the exact signed request bytes required by an interaction ingress verifier. Avoid an unbounded task per accepted request: reserve application handler capacity before transferring more exchanges.

### Exercise boundaries locally

Test empty UDP messages, wrong peers, oversized packets, count/byte exhaustion, EOF, canceled receives and concurrent close. For ingress, test malformed framing, incomplete bodies, duplicate responses, canceled handlers and listener shutdown while a transferred response remains live. Local socket tests require loopback permission; they make no Discord requests.
