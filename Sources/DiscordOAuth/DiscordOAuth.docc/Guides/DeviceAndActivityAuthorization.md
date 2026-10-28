[//]: # "File: Sources/DiscordOAuth/DiscordOAuth.docc/Guides/DeviceAndActivityAuthorization.md | Created by Carson Rau. | Copyright (c) 2026 Aurum Studios. | https://aurum-studios.com"

# Device grants and Activity code exchange

Drive specialized authorization explicitly and retain backend ownership of secrets and polling.

## Overview

### Start one confidential device session

``OAuthDeviceAuthorizationEndpoints`` implements the published backend device-authorization and device-code token descriptors. ``OAuthDeviceAuthorizationFlow`` is inert until `start` and single-session. The host authenticates its user session, supplies the confidential client and separately presents the returned challenge instructions.

Explicit `poll` performs at most one due token request. A call before the next permitted instant returns waiting without I/O. Pending retains the interval; slow-down adds a persistent five seconds. Request-start expiry, finite poll budget, terminal grant errors, busy admission and cancel/result fencing prevent overlapping or unbounded work.

The actor starts no polling loop, sleep or browser automatically. Your scheduler owns when to call poll, how to stop when the user leaves, and how to persist/revoke a successful token. Cancel the flow when that session ends. Do not treat a displayed code or verification URL as a token or expose device credentials in diagnostics.

Public native-device authorization and console host integration are separate capabilities. A confidential backend flow must not move its client secret into a game binary or browser merely to share a code path.

### Exchange an Activity code on the backend

``OAuthEndpoints`` has a separate `activityAuthorizationCode` descriptor for the code returned by an Activity host AUTHORIZE command. It uses confidential authentication and the Activity-specific grant shape without a redirect URI. An optional verifier is accepted when the Activity requested PKCE; the ordinary redirect-bound flow API remains separate.

Authenticate the client/backend session before accepting a code. Keep the client secret exclusively on the backend. A returned access token permits only the granted scopes; an Activity host purchase hint must still be verified against authoritative entitlement data through DiscordCommerce.

### Treat provisional merge proof explicitly

The backend device exchange can carry paired documented provisional merge proof. The proof token is not an external account ID. The host must establish which external/game account is authenticated before requesting a merge. Account migration is asynchronous and can invalidate credentials/sessions; synchronize storage invalidation separately from descriptor construction.

### Test scheduling and terminal ownership

Inject clocks and scripted REST replies. Assert start-once, poll-before-due sends nothing, pending retains schedule, slow-down accumulates, expiry is anchored at request start, terminal errors stop, finite budget exhausts and cancellation fences late results. For Activity exchange, assert confidential-only authentication, omitted redirect, bounded optional verifier and no automatic ambiguous replay.

The [OAuth contract](https://github.com/CarsonAurum/DiscordKit/blob/main/Docs/OAuth.md) and [Activities example](https://github.com/CarsonAurum/DiscordKit/tree/main/Examples/ActivityHost) describe host/backend composition without embedding secrets in iframe code.
