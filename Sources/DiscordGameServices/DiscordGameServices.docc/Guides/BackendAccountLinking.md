[//]: # "File: Sources/DiscordGameServices/DiscordGameServices.docc/Guides/BackendAccountLinking.md | Created by Carson Rau. | Copyright (c) 2026 Aurum Studios. | https://aurum-studios.com"

# Backend account provisioning and publisher linking

Bind approved account operations to an authenticated external identity and backend-held credentials.

## Overview

### Provision only the intended account

``PartnerAccountEndpoints`` describes published bot-created and externally proven provisional account flows. The host must authenticate its game/external user before selecting the opaque account key. A provisional account is a limited identity, not an implicit full Discord account or proof of every user consent.

```swift
import DiscordGameServices

let endpoint = try PartnerAccountEndpoints.provisionalBot(
    externalUserID: "synthetic-game-account-42",
    preferredGlobalName: "Player")
// Execute using the owning application's authorized backend bot REST client.
```

Constructing this synthetic descriptor performs no I/O. Provider keys remain exact strings and must not be parsed as snowflakes. Externally proven flows use fresh configured provider proof plus confidential client credentials on the backend. A proof token is not interchangeable with the external account key.

``PartnerTokenResponse`` and secret wrappers redact ordinary diagnostics. Unsafe field access deliberately exposes sensitive data; retain it only through authorized storage/adapter boundaries. Reauthenticate explicitly using the original documented method when provisional credentials expire. Do not invent an OAuth refresh grant for a provisional account.

### Link and unmerge deliberately

Code-based account linking uses the validated OAuth flow and explicit paired external proof. Console/device merge uses the published confidential exchange. The backend authenticates both the host session and intended account association before initiating migration.

Unmerge is an explicit destructive request that invalidates access/refresh credentials and sessions upstream. Its acknowledgement does not establish migration completion. Descriptor construction does not mutate your local token storage; the application must invoke invalidation and fence stale sessions when it observes unlink/deauthorization outcomes.

Post-create native-only naming, public-client provisional creation/unmerge and other unpublished native contracts are not synthesized from guessed endpoints. Require the approved published wire contract or a separate supported integration before exposing those actions in a product.

### Retain publisher lineage

Publisher child exchange requires the approved parent/child relationship and appropriate confidential credentials. Child credentials have another application audience and no direct refresh. Their expiry is capped to the original parent's remaining grant; refreshing the parent does not silently extend existing children.

Use DiscordOAuth's storage/coordinator contracts for atomic lineage checks and root invalidation. Removing a root must invalidate descendants durably. Publisher hierarchy changes and migrations can affect account data beyond a token, so the backend must coordinate its actual application state and external access configuration.

### Preserve uncertain outcomes

All account mutations are unsafe after uncertain submission. A network failure can occur after provisioning or migration began; reconcile using documented state instead of resubmitting automatically. Bound requests, retry budgets, store work and host sessions independently.

Use scripted REST peers and synthetic proof tokens to test credential category, exact opaque keys, malformed responses, redaction, 429 behavior, account-already-linked errors, cancellation and indeterminate submission. These tests do not establish approved publisher access or live migration qualification.
