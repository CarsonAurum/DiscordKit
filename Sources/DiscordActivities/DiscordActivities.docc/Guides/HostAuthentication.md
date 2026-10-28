[//]: # "File: Sources/DiscordActivities/DiscordActivities.docc/Guides/HostAuthentication.md | Created by Carson Rau. | Copyright (c) 2026 Aurum Studios. | https://aurum-studios.com"

# Authenticating an Activity host and user

Separate authenticated postMessage transport, host readiness and scoped user authorization.

## Overview

### Validate the transport sender

``ActivityHostParameters`` validates Discord-injected iframe URL context. That context is configuration; it does not prove the source of an incoming message. An ``ActivityTransport`` implementation must verify both the exact expected window/source object and exact origin before delivering frames. Avoid wildcard target origins and string-only source checks.

The repository's [owned browser bridge](https://github.com/CarsonAurum/DiscordKit/tree/main/Browser/DiscordActivityBridge) performs that browser-side boundary without npm runtime dependencies. Binding Swift and JavaScript is an explicit application integration. A standalone web page, native WebView or fake test window does not itself become a Discord Activity host.

```swift
import DiscordActivities
import DiscordCore

/// Creates an inert Activity owner after the app has authenticated its message adapter.
func makeActivityClient(
    applicationID: ApplicationID,
    host: ActivityHostParameters,
    authenticatedTransport: any ActivityTransport
) throws -> ActivityClient<ContinuousClock> {
    try ActivityClient(
        applicationID: applicationID,
        host: host,
        transport: authenticatedTransport,
        clock: ContinuousClock(),
        limits: ActivityClientLimits(maximumPending: 32)
    )
}
```

`start(timeout:)` owns one handshake/READY exchange and starts a reader and ordered writer. READY confirms protocol readiness, not OAuth consent. A failed startup closes the exclusively owned transport. Close is terminal; create a fresh client/transport after host reload rather than trying to restore a stale browser source.

### Exchange authorization codes on a backend

Request only the scopes required by your feature. The host returns a code; exchange it on an authenticated backend that binds the request to this application/session. Keep confidential client and refresh secrets on that backend. Return only the permitted user access token over a protected channel.

```swift
import DiscordActivities
import DiscordCore

/// Authorizes identify, exchanges the code on an authenticated backend and authenticates the host.
func authenticateActivity<C: Clock>(
    client: ActivityClient<C>,
    applicationID: ApplicationID,
    exchange: @Sendable (String) async throws -> ActivityUserAccessToken
) async throws -> ActivityAuthentication where C.Duration == Duration {
    let authorization = try await client.execute(
        ActivityRequests.authorize(clientID: applicationID.description, scopes: ["identify"])
    )
    try Task.checkCancellation()
    let token = try await exchange(authorization.code)
    try Task.checkCancellation()
    return try await client.execute(
        ActivityRequests.authenticate(accessToken: .value(token))
    )
}
```

The caller must explicitly start the client first. Backend exchange errors do not trigger an automatic second code exchange. Redacted wrappers prevent ordinary token logging; raw user/profile fields still need application privacy policy. Each later command retains its own scope and host-platform requirements.

### Test each boundary independently

Use a simulated host for startup, malformed envelopes, canceled exchanges, wrong nonce/command and teardown. Browser tests must reject a correct origin paired with a wrong source, and a correct source paired with a wrong origin. These are local protocol checks. Approved Discord Web/iOS/Android launches, authorization, navigation and platform behavior require real host qualification. See the [Activity example](https://github.com/CarsonAurum/DiscordKit/tree/main/Examples/ActivityHost) for backend composition.
