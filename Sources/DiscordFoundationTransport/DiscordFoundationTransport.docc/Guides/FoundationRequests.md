[//]: # "File: Sources/DiscordFoundationTransport/DiscordFoundationTransport.docc/Guides/FoundationRequests.md | Created by Carson Rau. | Copyright (c) 2026 Aurum Studios. | https://aurum-studios.com"

# Sending requests with an owned Foundation adapter

Create the adapter explicitly, consume response bodies and await session cleanup.

## Overview

### Configure before performing I/O

``FoundationTransportConfiguration`` validates finite operation, body, chunk, message and timeout limits. ``FoundationHTTPTransport`` stores configuration; actual requests begin through its transport operation. The product does not implement Discord authentication, rate admission or REST retries.

```swift
import DiscordFoundationTransport
import DiscordTransport
import Foundation

let configuration = try FoundationTransportConfiguration(
    maximumConcurrentOperations: 8,
    maximumResponseBodyBytes: 1_024 * 1_024,
    responseChunkBytes: 8 * 1_024)
let transport = FoundationHTTPTransport(configuration: configuration)
let clock = ContinuousClock()
do {
    let response = try await transport.execute(
        HTTPRequest(method: "GET", url: URL(string: "https://example.com/")!),
        context: TransportContext(clock: clock,
            deadline: clock.now.advanced(by: .seconds(10))))
    if let body = response.body {
        do {
            for try await chunk in body { _ = chunk.count }
            await body.close()
        } catch {
            await body.close()
            throw error
        }
    }
} catch {
    await transport.close()
    throw error
}
await transport.close()
```

Running this snippet sends one public example request. It carries no credentials. The application decides how to interpret the status before consuming bytes. Use the separate DiscordHTTP RESTClient for Discord API requests instead of adding bot headers to arbitrary URLs.

### Inject into a REST consumer

The [RESTOnly example](https://github.com/CarsonAurum/DiscordKit/tree/main/Examples/RESTOnly) constructs a bot credential, one shared rate authority and this adapter, then executes typed current-user/application descriptors. Its host owns the transport and coordinator and closes both after all clients finish. Building the example does not execute authenticated requests.

A returned body retains its operation admission slot until EOF or close. Do not retain unconsumed responses while issuing more requests: those bodies are live resources and can exhaust the configured operation budget. On early exit, explicitly await `body.close()`.

### WebSocket ownership

``FoundationWebSocketTransport`` is a separate adapter over native complete-message framing. Close every transferred connection and then close the adapter. Supply protocol framing, authentication and session supervision in the higher product. Ordinary watchOS socket use is rejected where the required capability is unavailable.

### Test the integration locally

Use local HTTP/WebSocket peers to verify requests, redirects, oversize bodies, cancellation and repeated close without a Discord token. A successful loopback exchange does not qualify every platform's Foundation implementation or physical device policy.
