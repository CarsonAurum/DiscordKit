[//]: # "File: Sources/DiscordHTTP/DiscordHTTP.docc/Guides/RESTClientSetup.md | Created by Carson Rau. | Copyright (c) 2026 Aurum Studios. | https://aurum-studios.com"

# Setting up an independent REST client

Bind a typed credential to one shared rate authority and an explicitly owned transport.

## Overview

### Construct an inert execution pipeline

``Endpoint`` describes a request, including response decoding, accepted statuses, authentication, rate route, major resource, body, read policy and replay safety. Descriptor construction validates metadata but sends nothing. ``RESTClient`` also starts no tasks or network work until `execute` is called.

```swift
import DiscordCore
import DiscordFoundationTransport
import DiscordHTTP

let clock = ContinuousClock()
let transport = FoundationHTTPTransport(configuration: try .init())
let coordinator = RateLimitCoordinator(clock: clock)
let identity = RateLimitIdentity()
let token = try BotToken("replace-with-a-token-from-secure-host-configuration")
let client = RESTClient(credential: .bot(token), identity: identity,
    transport: transport, coordinator: coordinator, clock: clock)

do {
    let user = try await client.execute(DiscordEndpoints.currentUser(),
        deadline: clock.now.advanced(by: .seconds(15)))
    _ = user.id
} catch {
    await coordinator.close()
    await transport.close()
    throw error
}
await coordinator.close()
await transport.close()
```

Replace the placeholder credential before running this network example. Supply a secret from the host's secure configuration; never embed a production token in app binaries, browser code or version control. A bot token and OAuth bearer token have different endpoint permissions.

### Share authorities deliberately

Every client using the same credential must reuse the same opaque ``RateLimitIdentity`` and ``RateLimitCoordinator``. Reuse them across reconnects and client replacement. Independent client instances do not create new Discord quota. Across processes, inject a common atomic ``RateLimitStore`` and one application mutation-order authority where writes span workers.

A shared egress identifier coordinates outbound-IP invalid-response pressure across identities. Header-free globally limited webhook operations require the applicable egress identity. Keep that label opaque; credentials and user identifiers must not become metrics labels.

### Keep dependencies owned by the host

The client does not close injected transports, coordinators, read caches or coalescers implicitly. Stop client calls, await in-flight work, then close the owners whose full lifetime belongs to this host. A shared transport stays open until all clients finish. Release retained cache snapshots explicitly when discarding the scope.

Requests use the fixed Discord API v10 origin. Authentication and framing headers cannot override endpoint policy, and relative raw routes use the same pipeline without establishing typed parity. A transport must send once and return redirects rather than following them.

### Decode and recover deliberately

Descriptors choose empty/204 decoding explicitly. Successful but malformed data fails without entering a read cache. ``APIResponseError`` retains bounded structured API error information, including unknown codes and validation trees. Generic diagnostics redact sensitive request/response content; unsafe evidence inspectors transfer logging responsibility to the caller.

For a failed write, distinguish local validation, known server rejection and uncertain submission. The last case may already have changed Discord state. Reconcile before deciding whether another explicit request is safe.
