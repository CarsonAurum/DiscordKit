<!--
File: Docs/OAuth.md
Created by Carson Rau.
Copyright (c) 2026 Aurum Studios.
https://aurum-studios.com
-->

# OAuth2, installations and token ownership

DiscordKit provides independently adopted `DiscordOAuth`, `DiscordGameServices` and
`DiscordCommerce` products. Construction starts no tasks, browser sessions or
network I/O. OAuth imports HTTP, Models, Core, Transport and the already selected
Swift Crypto product for RFC 7636 S256. HTTP remains independently usable without
OAuth or Crypto; none of these three products imports Gateway, Client or Cache.

The [OAuth reference](https://docs.discord.com/developers/topics/oauth2),
[mobile account-linking guide](https://docs.discord.com/developers/discord-social-sdk/development-guides/account-linking-on-mobile),
[publisher guide](https://docs.discord.com/developers/discord-social-sdk/development-guides/publisher-level-account-linking),
[API reference](https://docs.discord.com/developers/reference) and
[change log](https://docs.discord.com/developers/change-log) were verified **2026-10-17**.
[Source fingerprints](Parity/oauth-game-commerce-current-sources.json) retain current
verification independently from original discovery pins. REST uses explicit **v10**;
OAuth browser authorization is unversioned. Unknown upstream announcement/effective
dates remain unknown. Native SDK and unpublished Commerce contracts remain
[explicit blockers](ServiceContracts.md).

## Authorization and installation

`OAuthAuthorizationFlow` builds a fixed-origin Discord authorization URL. It generates
fresh 256-bit state and S256 proof keys by default; supplied nonces/verifiers must
meet documented syntax and bounds, and the caller remains responsible for entropy.
The host binds each flow actor to its authenticated session and timeout policy.
`OAuthInstallationURL` also builds callbackless bot/command-only permission URLs
without a response type, redirect, state or token exchange.
Scopes retain open spellings; `OAuthScopeAvailability` is advisory approval metadata,
not evidence of a grant. Requested permissions are arbitrary-width decimal strings.

```swift
let flow = try OAuthAuthorizationFlow(
    clientID: applicationID,
    redirectURI: registeredRedirect,
    scopes: ["identify", "applications.commands"],
    installationContext: .user
)
// Present flow.authorizationURL through your host's browser UI; never log it.
let result = try await flow.consumeCallback(exactCallbackURL)
```

Guild/user installation contexts require matching portal configuration. Bot
permissions, guild selection and incoming-webhook authorization remain explicit.
The token response exposes a typed webhook or partial advanced bot guild when
returned; obtaining a webhook does not change the credential type of its token.

Callbacks require the exact initiating redirect, state and Discord issuer
`https://discord.com`. Duplicate response fields, wrong origins, unexpected
fragments, missing issuer and mixed success/error payloads fail closed. A validated
success or denial consumes the actor once before another callback can be admitted.
Registered static query parameters remain bound to their exact spelling/order.
HTTPS, loopback HTTP and documented `discord-<applicationID>:/authorize/callback`
redirects are supported. Redirect allowlisting/registration still belongs to the
application and Discord.

`OAuthBrowserAdapter` invokes an injected main-actor host operation and passes the
returned URL through the same flow owner. The host supplies its presentation anchor,
OS session, callback registration, timeout and cancellation cleanup. The adapter
checks the fixed authorization origin and callback scheme, sanitizes host errors,
and never accepts client secrets. This is an integration boundary, not an OS UI
implementation or physical-device qualification. The independent
[OAuthApp example](../Examples/OAuthApp/README.md) compiles this adoption without
Gateway, Client, Cache, Commands, Interactions or concrete network adapters.

## Explicit backend device authorization

Verified **2026-10-18** against the published
[console account-linking flow](https://docs.discord.com/developers/discord-social-sdk/development-guides/account-linking-on-consoles)
and [RFC 8628](https://www.rfc-editor.org/rfc/rfc8628.html).
`OAuthDeviceAuthorizationEndpoints` owns API v10 device authorization and device-code
token descriptors, including the documented optional paired provisional merge proof.
It uses the existing confidential client's form-encoded token authentication and
suppresses ambient bearer/bot authorization. The client secret remains on the backend.
Native public-client device authorization and console host integrations remain separate.

`OAuthDeviceAuthorizationFlow` is inert and single-session. Explicit `start` returns
redacted challenge instructions for the application's UI; explicit `poll` performs at
most one due token request. Calls before the next permitted time return waiting without
I/O. Pending preserves the interval; slow_down adds a persistent five seconds. Local
request-start expiry, terminal grant errors, a finite poll budget, concurrent busy
admission and cancel/result fencing prevent unbounded or overlapping work. No background
loop, sleep or browser starts automatically. Rate policy and uncertain submitted requests
retain the existing REST ownership rules. The application owns scheduled polling,
presentation, server session binding, token persistence and revocation.

Legacy implicit support requires `.implicitCompatibility`. It accepts a fragment
bearer with no refresh token and rejects incompatible scopes; code flow with S256
is the default. Implicit fragment tokens are unsuitable for durable server sessions.
Public PKCE token exchange is explicit and requires a Public Client-enabled
application. Discord's [authorization-server metadata](https://discord.com/.well-known/oauth-authorization-server)
explicitly advertises S256, issuer identification and `none` token/revocation
authentication alongside confidential authentication. This does not imply native
Social SDK support or live public-client qualification. Confidential clients keep
their secret on the backend and authenticate with form fields. No client secret is placed
in a browser URL, query, diagnostic identifier or route template.

## Token operations and request policy

`OAuthEndpoints` provides code exchange, refresh, client credentials, access/refresh
revocation and current authorization/application information. `OAuthClient` executes
token operations through a separately owned `RESTClient`. Reuse application/credential
rate identities and coordinated authorities across workers; independent instances
do not create new upstream quotas. The injected REST pipeline bounds queues, bytes,
response bodies and exchange lifetimes. Use a header-free REST client for form-authenticated
token operations; bearer reads and bot reads use their own credential categories.

Token/revocation requests use `application/x-www-form-urlencoded`, fixed versioned
Discord origin, bounded bodies, no response caching/coalescing and unsafe replay
semantics. Explicit rejected 429 handling retains the REST client's finite policy;
ambiguous submission and unsafe 5xx failures are not replayed. Token exchange
`invalid_grant` maps to a closed OAuth error, never a raw server description.
Token bodies, codes, refresh credentials and optional webhook data redact ordinary
formatting and reflection. Unsafe accessors and raw URL properties can intentionally
expose sensitive values; consumers must keep them out of logs and metrics.

DiscordKit provides `OAuthEndpoints.activityAuthorizationCode` for the confidential
backend exchange of a code returned by an Activity iframe AUTHORIZE command.
The [official Activity tutorial](https://docs.discord.com/developers/activities/building-an-activity)
uses a form grant with client authentication and no redirect URI. This separate API
accepts an optional verifier when the Activity requested PKCE, rejects public-client
authentication and preserves the ordinary redirect-bound flow API. Keep secrets on
the backend; authenticate the caller/session before accepting its code and never
grant entitlements from client-supplied purchase data. See [Activities](Activities.md)
and its [current source fingerprints](Parity/activities-current-sources.json).

## Refresh coordination and storage

`OAuthTokenCoordinator` owns one local refresh flight per application/audience and
opaque authorization grant. Defaults bound concurrent identities/mutations to **128**,
aggregate waiters to **1,024**, and waiters per identity to **128**. The expiry skew
defaults to **30 seconds**. These finite local bounds are configurable; no fleet
capacity is claimed. Construction starts no refresh timer. Fresh tokens are returned
without a request, and refresh happens only through explicit access.

Inject `OAuthTokenStorage`: there is no insecure default runtime store. Its transaction
must atomically compare generations, validate publisher parent freshness/lineage,
replace complete credentials, and remove publisher children when their parent is
removed. The implementation owns encryption, authorization, durability and bounded
record/lineage retention. Production secure-storage qualification is separate from
the deterministic test store. CAS prevents stale writes; distributed deployments
also need a single refresh owner or an injected external lease per grant.

UTC expiry persists across process lifetimes, so the injected clock must be trusted.
Acquisition time conservatively anchors expiry before network work, future install
times fail, and positive lifetime/nonnegative skew checks precede use. Refresh omission preserves
the previous refresh token; rotated credentials replace it atomically. Definitive
invalid-grant invalidates local storage; transient/ambiguous failures retain state
without automatic replay. Do not restart an ambiguous rotation blindly.

Each canceled waiter returns independently. Once a refresh is admitted it continues
even if every waiter cancels, allowing a rotated credential to be persisted.
`close()` rejects admission, releases waiters, cancels and joins owned exchanges;
refresh/storage operations must cooperate with cancellation. Install/invalidate/revoke operations
remain caller-owned and must also be awaited before disposing shared storage.

Publisher children share the root's authorization identifier and have another application
audience. Their lifetime is capped to the original parent's remaining expiry and they
cannot refresh directly. Refreshing the parent preserves the original child expiry;
obtain a new child through an explicit exchange. Root revocation durably removes its
children before one remote attempt. Revoking an individual child selects that child's
application credentials. Local invalidation does not prove a failed remote revocation
succeeded. Observe external deauthorization/unmerge and invalidate the corresponding
store lineage explicitly through `invalidateToken(for:)`; no listener or destructive migration starts automatically.

## Validation and remaining gates

Swift Testing covers scope/form encoding, S256 vectors, exact redirect/state/issuer,
legacy compatibility, one-use/concurrent callbacks, safe diagnostics, token variants,
errors, bounded admission, concurrent refresh/cancellation, expiry, CAS replacement,
invalid grants and publisher cascades. Game/Commerce suites cover public descriptors,
silent lobby partial results, full-replacement stats and authoritative entitlement
ownership/expiry/consumption. These are offline checks using injected dependencies.

Local macOS compilation/deterministic tests do not establish live Discord consent,
OS browser-session behavior, remote secure-storage durability, approval-gated publisher
access, native Social SDK interoperability, Social Commerce fulfillment, physical-device
or other-host support, or fleet capacity.
