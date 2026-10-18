# Authorizing features from authoritative entitlements

Fetch current server data and match the exact application, SKU and user or guild owner.

## Overview

### Define server-owned policy

``EntitlementRequirement`` describes an exact grant. The backend chooses the application, SKU, owner and environment policy from its own authenticated context and catalog, not from arbitrary client fields.

```swift
import DiscordCommerce
import DiscordCore
import DiscordModels

let requirement = EntitlementRequirement(
    applicationID: ApplicationID(rawValue: 1),
    skuID: SKUID(rawValue: 2),
    owner: .user(UserID(rawValue: 3)))
```

These synthetic values construct policy only. ``EntitlementOwner`` distinguishes user and guild grants. A guild grant still requires a separate check that the authenticated user is entitled to use that guild feature; matching a supplied guild ID is insufficient.

### Fetch and validate after the response

``EntitlementVerification`` builds an uncached authoritative get descriptor and applies the requirement after the server reply. Supply an authorized backend REST executor and trusted current timestamp closure. The clock runs after network completion so a grant expiring during the fetch cannot pass using an earlier time.

`validate` checks exact returned/requested entitlement ID, application, SKU, owner, deletion, known origin and time bounds. Start is inclusive; end is exclusive, with nanosecond precision. Null timestamps are open bounds, while missing timestamps fail closed except the explicitly allowed known test-mode case. Production rejects test purchases by default.

Consumable requirements additionally demand explicit unconsumed state. Unknown origin or absent consumption state must not be treated as a permissive fallback. ``EntitlementVerificationError`` reports closed matching, active-state and consumption categories without exposing purchase identifiers.

### Keep authorization and fulfillment distinct

Verification returns a snapshot and does not grant items, persist a receipt, consume a purchase or make authorization permanent. Revocation can occur immediately afterward. For long-lived access, choose a bounded freshness/invalidation policy and recheck authoritative state as the product requires.

A subscription lifecycle or client purchase acknowledgement does not independently establish access. Use the entitlement grant for the exact offering and owner. Never place bot tokens or confidential client secrets in an Activity iframe, game binary or browser to perform this verification locally.

### Test fail-closed policy

Build synthetic entitlement fixtures and table-test wrong receipt/application/SKU/owner, user-versus-guild substitution, deleted grants, unknown/test origins, missing/null timestamps, exact start/end instants and consumed/absent state. Assert verification uses a no-reuse descriptor and checks cancellation before and after the fetch. Keep clocks deterministic and never require a real purchase for unit tests.
