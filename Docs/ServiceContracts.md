<!--
File: Docs/ServiceContracts.md
Created by Carson Rau.
Copyright (c) 2026 Aurum Studios.
https://aurum-studios.com
-->

# game and commerce contracts

Verified **2026-10-17** against the official sources below. API descriptors explicitly use
Discord **v10**. Local implementation date is 2026-10-17; upstream introduction and
effective dates are **unknown** unless separately stated by an upstream change-log entry.
The publisher guide records its initial release as **2026-02-18**; a separate upstream
effective date is unknown. This documentation date does not imply DiscordKit support before this change.
This record is an implementation/access boundary, not a claim of native Social SDK parity,
approved publisher access, production payment qualification or live-service validation.

## Provisional accounts and publisher linking

| Capability | Local implementation | Official contract / boundary |
| --- | --- | --- |
| Backend create/reauthenticate | `PartnerAccountEndpoints.provisionalBot` | Bot POST `/partner-sdk/token/bot`; exact external account key and optional preferred display name. Limited provisional identity only. |
| External proof exchange | `provisionalExternal` | Confidential JSON POST `/partner-sdk/token`; external provider must already be configured. |
| Initial naming | `preferredGlobalName` on bot creation | Server-selected `preferred_global_name`; provider-specific names remain upstream behavior. |
| Post-create naming | **Blocked: awaiting public wire schema** | The guide publishes native `UpdateProvisionalAccountDisplayName`; no corresponding REST route/schema is provided. |
| Public-client creation | **Blocked: awaiting public wire schema** | Native `GetProvisionalToken` is documented; DiscordKit does not wrap the native SDK or guess its wire protocol. |
| Code-based merge/linking | `OAuthEndpoints.authorizationCode` / `OAuthClient.exchange` external proof fields | Explicit OAuth code exchange with PKCE and paired external auth fields. Bot-issued proof means the returned provisional **access token**, never the external user ID. |
| Console merge | `mergeDeviceCode` | Explicit confidential OAuth device-code exchange with external proof. Host obtains the device code; no automatic polling. |
| Backend unmerge | `unmergeBot` / `unmergeExternal` | Explicit destructive POST; retains optional JSON acknowledgement. Guide omits exact success status/schema, so successful 2xx responses are accepted without inventing a token/user result. |
| Public-client unmerge | **Blocked: awaiting public wire schema** | Only native `UnmergeIntoProvisionalAccount` is documented. |
| Publisher child exchange | `publisherChild` | Confidential JSON POST `/partner-sdk/child-token`; parent-child hierarchy requires Discord approval. |
| Publisher hierarchy establishment | **Blocked: Discord-managed access/configuration** | No local migration API; Discord must establish the relationship. |

Sources: [bot provisioning](https://docs.discord.com/developers/discord-social-sdk/development-guides/provisional-accounts/bot-token-endpoint),
[external exchange](https://docs.discord.com/developers/discord-social-sdk/development-guides/provisional-accounts/external-credentials-exchange),
[management and naming](https://docs.discord.com/developers/discord-social-sdk/development-guides/provisional-accounts/managing-accounts),
[merging](https://docs.discord.com/developers/discord-social-sdk/development-guides/provisional-accounts/merging-accounts),
[unmerging](https://docs.discord.com/developers/discord-social-sdk/development-guides/provisional-accounts/unmerging-accounts),
[publisher linking](https://docs.discord.com/developers/discord-social-sdk/development-guides/publisher-level-account-linking).

Expiry and revocation are explicit lifecycle inputs. Backend provisional tokens last seven
days; documented native public-client tokens last one hour. Reauthenticate using the original
method with fresh proof; the OIDC OAuth refresh grant is deprecated. Treat provisional tokens
separately from full-account tokens in any injected secure store.

Publisher children receive no refresh token and expire with the original parent grant.
Refreshing the parent preserves existing child expiry; re-exchange to obtain a newer child.
Parent revocation invalidates all descendants, while individual child revocation uses that
child's application credentials. `OAuthTokenCoordinator` enforces local lineage expiry and
durable cascades; the embedding backend must invoke invalidation for unmerge/deauthorization
and other externally observed revocation. Descriptor construction never mutates token storage.

Merge/unmerge migration is asynchronous. Unmerge invalidates user access/refresh credentials
and sessions; acknowledgement does not prove completed migration. Publisher hierarchy changes
can irreversibly delete child tokens, lobbies, identities, provisional accounts and relationships.
No migration or link request occurs at construction/startup. Approved native-client protocols
remain outside DiscordKit's portable library boundary.

## Typed lobby and game profile conveniences

`GameServiceOperations` reuses the typed HTTP catalog. Matching channel snapshots avoid
redundant linking writes. Profile comparison examines only explicitly requested root fields;
supplied stats data remains a **full replacement**, including an empty object that clears data.
It never merges old nested stats. External identity keys are validated even for no-op requests.

Linked-lobby member plans retain the existing 25-item request chunks, input correlation,
silently omitted upserts and partial failure progress. Acknowledged lobby delivery does not
prove linked-channel forwarding succeeded. No invisible retry repairs silent omissions.
Snapshots can race upstream changes and never prove current consent or permissions.

Sources: [Application Identity Profile](https://docs.discord.com/developers/resources/application-identity-profile),
[Lobby](https://docs.discord.com/developers/resources/lobby),
[sending game data](https://docs.discord.com/developers/social-layer/game-stats-widgets/sending-game-data).

## Premium entitlements and Activity purchasing

`EntitlementVerification` performs an uncached server read and checks exact receipt,
application, SKU, user/guild owner, deletion, known origin, exact start/end instants and explicit
unused consumption state when required. Start is inclusive and end exclusive. Production
rejects test-mode purchases; missing dates fail closed except explicit known test-mode policy.
Null dates remain open bounds. Subscription status alone is never authorization.

Consumption is an explicit verification followed by the existing consume endpoint, without
automatic ambiguous replay or game delivery. Durable receipt ownership/idempotent delivery
belongs to the backend; verification cannot make concurrent consumption exactly once.

`ActivityPurchasing.purchase` accepts an injected web host `startPurchase` operation and
independently verifies each returned ID through the backend. Nil/empty acknowledgements remain
distinct; later `ENTITLEMENT_CREATE` hints need separate server verification. The portable Swift
library does not embed the JavaScript SDK, own the purchase UI, or expose backend secrets in
the host. Current `startPurchase` is documented for web, with iOS/Android unsupported.

Sources: [Entitlement](https://docs.discord.com/developers/resources/entitlement),
[Embedded App SDK](https://docs.discord.com/developers/developer-tools/embedded-app-sdk#startpurchase),
[current IAP guide](https://docs.discord.com/developers/monetization/implementing-iap-for-activities).
DiscordKit uses current v10 entitlement descriptors.

## Social Commerce capability inventory

The public [Social Commerce overview](https://docs.discord.com/developers/social-commerce/overview)
describes early access and the capabilities below, but publishes no complete operation schemas.
Every blocked row remains excluded from implemented coverage. Upstream introduction/effective
dates are unknown; verification date is 2026-10-17.

| Capability | Status | Required contract/access |
| --- | --- | --- |
| Catalog/SKU creation, update and removal | **Blocked: awaiting schema/access** | Approved item, cosmetic, consumable and bundle management endpoints. |
| Storefront/availability/metadata | **Blocked: awaiting schema/access** | Storefront and publication schemas, ownership and limits. |
| Pricing/currency | **Blocked: awaiting schema/access** | Price writes, currency rules and purchase consistency. |
| Gifting | **Blocked: awaiting schema/access** | Gift creation/redemption, sender/recipient and eligibility contracts. |
| Wishlists | **Blocked: awaiting schema/access** | Read/write, visibility, identity and item schemas. |
| Commerce purchase/entitlement management | **Blocked: awaiting schema/access** | Commerce-specific grant and purchase contracts; ordinary entitlement reads do not establish broad commerce parity. |
| Fulfillment webhooks | **Blocked: awaiting schema/access** | Event payloads, delivery identity, replay and acknowledgement contracts. |
| Fulfillment acknowledgement | **Blocked: awaiting schema/access** | Mark-fulfilled endpoint and failure/idempotency semantics. Ordinary consumable consumption is not fulfillment. |
| Eligibility/onboarding | **Blocked: awaiting Discord approval** | Early-access approval and approved partner specifications. No interest form is submitted by tooling. |

All new validation uses synthetic offline fixtures with no credentials or Discord purchases.
No production, live API, browser purchase or native SDK integration is implied by local tests.
