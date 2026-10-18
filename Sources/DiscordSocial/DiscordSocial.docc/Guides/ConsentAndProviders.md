# Composing consent and providers

Bind one verified application/account consent domain to explicitly selected provider clients.

## Overview

### Establish authority before activation

The application validates an OAuth grant, account identity, application association and exact granted scopes before activating ``SocialClient``. ``SocialScope`` carries the application ID, account ID and a consent generation. These inputs are application assertions; activation does not exchange tokens or independently prove the grant.

Use a new consent generation whenever the account, visibility or consent changes. Explicitly qualify a desktop RPC or Activity host before supplying it in `availableHosts`. A bot/backend credential cannot manufacture consented user functionality.

```swift
import DiscordCore
import DiscordSocial

/// Creates local scoped observation state after the application has verified user consent.
func makeConsentedSocialState(
    applicationID: ApplicationID,
    accountID: UserID,
    consentGeneration: UInt64,
    exactScopes: Set<String>
) async throws -> SocialClient<ContinuousClock> {
    let client = try SocialClient(
        clock: ContinuousClock(),
        stateLimits: SocialStateLimits(),
        maximumOperations: 16
    )
    try await client.activate(
        scope: SocialScope(
            applicationID: applicationID,
            accountID: accountID,
            consentGeneration: consentGeneration
        ),
        grantedScopes: exactScopes
    )
    return client
}
```

This example supplies no network provider. Relationship state becomes locally available, while profile and presence remain missing until a new coordinator is constructed with the corresponding providers. Providers are fixed for a coordinator's lifetime; selecting a different host means creating a new owner.

### Select the provider that matches the feature

| Provider | Authority and purpose |
| --- | --- |
| ``SocialHTTPProvider`` | Consented bearer profile and public lobby/message operations through an injected REST client. |
| ``SocialHTTPApplicationProvider`` | Bot-authorized backend application identity/profile routes; no user consent is inferred. |
| ``SocialRPCProvider`` | Approved connected desktop host, scope-checked presence, desktop settings and channel selection. |
| ``SocialActivityProvider`` | Authorized Activity host, presence, participants, relationships, invite dialog and external links. |


The providers retain their own typed extended operations and authoritative upstream checks. Desktop voice settings configure Discord's desktop client; local PCM controls configure application-owned samples; Voice/DAVE is a separately adopted network session. A lobby message does not establish SDK direct messaging, call signaling or a native live-user handle.

`availability(for:)` checks local provider/scope/host prerequisites without I/O. It does not prove the host remains connected or Discord will accept the request. A profile reply must match the activated account or fails closed. Activity presence uses the immutable application name; a mismatch fails before I/O.

### Bound structured work and revoke correctly

`maximumOperations` admits finite concurrent common calls without an extra waiter queue. Presence allows one writer at a time, including across consent replacement. Callers own their async operations, deadlines and cancellation; submitted mutations are never replayed. Share the same monotonic clock and appropriate credential/rate authorities with injected clients.

`disconnect()` fences late results and clears private relationship observations. `close()` permanently disables the coordinator. Neither cancels/awaits caller tasks, revokes durable OAuth tokens nor closes shared provider clients. The app cancels and joins those tasks, revokes credentials when required, and closes resources it owns. An already transmitted mutation may still finish remotely.

The [offline Social example](https://github.com/CarsonAurum/DiscordKit/tree/main/Examples/SocialApp) demonstrates provider selection. Native SDK-only runtime, mobile/console integration and unpublished Social Commerce contracts remain explicit unsupported requirements rather than guessed wire behavior.
