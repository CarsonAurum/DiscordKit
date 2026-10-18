# Authorization, installation and callback ownership

Generate fresh state and proof keys and consume only the initiating session's exact callback.

## Overview

### Create a single-session flow

``OAuthAuthorizationFlow`` builds a fixed-origin Discord authorization URL. Authorization code with S256 PKCE is the default. Fresh state and proof keys are generated unless explicitly supplied; custom values must meet bounds and the application remains responsible for entropy.

```swift
import DiscordCore
import DiscordOAuth
import Foundation

let flow = try OAuthAuthorizationFlow(
    clientID: ApplicationID(rawValue: 1),
    redirectURI: URL(string: "https://example.com/oauth/callback")!,
    scopes: ["identify", "applications.commands"],
    installationContext: .user)
let authorizationURL = flow.authorizationURL
// Present authorizationURL using your host's browser UI.
// let result = try await flow.consumeCallback(exactCallbackURL)
```

Replace the synthetic application and redirect with registered values before use. The raw URL can contain state and session metadata; do not log it. Bind the actor to the host's authenticated session and a finite timeout so another browser session cannot consume it.

### Validate the callback exactly

The flow requires the initiating redirect, state and Discord issuer. Wrong origins, duplicate fields, unexpected fragments, missing issuer and mixed success/error payloads fail closed. Registered static query parameters remain bound to exact spelling/order. A validated success or denial consumes the flow once; subsequent callbacks cannot exchange another code through that owner.

HTTPS, loopback HTTP and documented application callback schemes have specific validation. Redirect registration and allowlisting still belong to the application and Discord. A URL merely matching a broad suffix or containing the right code is insufficient.

``OAuthBrowserAdapter`` invokes an injected main-actor host operation and passes its returned URL through the same flow. The host owns OS presentation, callback registration, timeout/cancellation cleanup and session binding. The adapter is not an OS browser UI implementation and does not accept a confidential client secret.

### Separate installation from user authorization

``OAuthInstallationURL`` builds callbackless bot/application-command installation URLs. They acquire no user bearer token and have no response type, redirect, state or proof key to consume. Guild/user contexts must be enabled in the portal; bot permissions and preferred guild are explicit requests/hints, not proof the installer has authority.

```swift
let install = try OAuthInstallationURL(clientID: ApplicationID(rawValue: 1),
    scopes: ["applications.commands"], installationContext: .user)
_ = install.url
```

Open scope spellings preserve future values. Scope availability metadata is advisory and does not prove approval or a grant. Legacy implicit compatibility is explicit and returns no refresh token; prefer the default code flow for durable sessions.

### Test the security boundary locally

Use fixed valid state/proof values in fixtures and test wrong state, missing/wrong issuer, redirect mismatch, duplicate keys, denial, success consumed twice, mixed payloads, fragment rejection and cancellation cleanup. Never infer a user's consent or current permissions from installation configuration alone.
