# SKUs, entitlements and subscriptions

Phase 5I implements **eight current written REST operations** in API **v10**:
one SKU read, five Entitlement operations and two Subscription reads. The current
[SKU](https://docs.discord.com/developers/resources/sku),
[Entitlement](https://docs.discord.com/developers/resources/entitlement),
[Subscription](https://docs.discord.com/developers/resources/subscription),
[interaction](https://docs.discord.com/developers/interactions/receiving-and-responding),
[reference](https://docs.discord.com/developers/reference) and
[change log](https://docs.discord.com/developers/change-log) contracts were verified
**2026-10-16**. [Current fingerprints](Parity/monetization-current-sources.json)
are separate from historical discovery pins. No dependencies or runtime products
are added. This is Premium Apps REST coverage; broader Social Commerce, SDK-only
purchase/fulfillment and missing public wire contracts remain separate blockers.

## Owned models and premium interaction data

SKU includes the six written fields, the four documented SKU types and the
AVAILABLE, GUILD_SUBSCRIPTION and USER_SUBSCRIPTION flag bits. Unknown type values,
flag bits, fields and exact numeric lexemes remain preserved. Subscription-group
SKUs are system-generated; Discord directs integrations to the type-5 subscription
SKU for purchases and test entitlements. Listing SKUs does not publish or edit them.

Entitlement includes ID, SKU/application/user/guild ownership, type, deletion,
nullable start/end timestamps and optional consumed state. The example's optional
subscription_id is projected as additive compatibility. Test creation explicitly
returns a partial perpetual entitlement without start/end/subscription timestamps;
missing timestamps remain distinct from null. Historical type 8 remains recognized,
while the 2024 migration changed Discord-managed subscription purchases to type 1.
No local model assumes that every subscription entitlement has an expiration date.

Subscription includes subscribed/renewal SKU IDs, entitlement IDs, period boundaries,
status, nullable cancellation time and optional country. Current status values are
ACTIVE=0, INACTIVE=1 and ENDING=2. Discord corrected previously swapped documentation
in 2026; the API values did not change. Country is absent without a private OAuth scope, while explicit null is retained
as an official-specification compatibility overlay;
decoding this field does not grant access or invent a public scope.

**Use entitlements to decide access to a SKU.** Discord explicitly says subscription
status must not grant perks: ACTIVE can remain outside the current period during
payment retry, and INACTIVE can occur within the period after refunds/chargebacks.
These immutable snapshots do not decide business authorization or prove freshness.
Callers own purchase eligibility, permissions and fulfillment policy.

Interaction.entitlements now contains typed Entitlement values instead of partial
MessageRelatedResource projections. Complete current fields are validated under
the same whole-document byte/depth/node bounds, with unknown data retained in raw
JSON. This tightens fixtures that supplied only an ID; supply the documented core
entitlement shape. Premium buttons and the deprecated PREMIUM_REQUIRED callback
retain their existing validation and compatibility behavior. Signature verification,
interaction routing/acknowledgement and entitlement/subscription event dispatch are
separate roadmap work.

## REST descriptors and authorization

| Namespace | Operations | Credential contract |
| --- | --- | --- |
| SKUEndpoints | list application SKUs | Bot |
| EntitlementEndpoints | list, get, consume, create test, delete test | Create test requires bot; other operations accept bot or applications.entitlements bearer |
| SubscriptionEndpoints | list SKU subscriptions, get subscription | Bot or authorized OAuth bearer; listing without user_id requires bearer |

Authorization categories are checked by the HTTP pipeline before execution; Discord
still enforces scopes, application ownership and access. Listing entitlements exposes
user/SKU/guild filters, one before/after cursor, limit 1–100 (default 100), and explicit
exclude-ended/deleted options. Omitted flags retain Discord defaults: ended included,
deleted excluded. SKU filter sets are unique and bounded to 100 entries following
the official specification. Subscription listing defaults to 50, permits 1–100 and
requires a user filter for bot callers. Subscription get permits the official
specification's additive user filter. Typed cursor enums prevent conflicting before
and after parameters.

CreateTestEntitlementRequest binds a typed guild or user owner to the corresponding
owner_type (1 or 2), preventing mismatched IDs. Test creation changes premium access
and requires a Discord client reload to observe it. Delete test removes an active
test entitlement. Consume marks a consumable one-time entitlement as consumed; it
is an explicit mutation, not a purchase or delivery transaction. Empty successful
consume/delete responses require 204. Mutations are never silently merged or
replayed after an uncertain transport outcome. No audit-reason headers, uploads or
generic batching are invented for these routes.

All operations share the existing credential-scoped rate admission, bounded retry,
request/response limits and deadline/cancellation policies. Eligible reads opt into
coalescing/freshness and resource tags; successful entitlement writes invalidate the
credential-scoped entitlement snapshots across applications. A snapshot read may be stale until its explicit
policy expires or invalidates it. Separate credentials never share cached data.

## Finite lazy traversal

EntitlementOperations.pages and SubscriptionOperations.pages expose bounded lazy
sequences with explicit ascending/descending order, page size 1–100 and maximum
pages 1–10,000. The default is descending; ascending traversal without a cursor
starts explicitly after zero. Each demand fetches one page with no prefetch or
completed-response reuse. Filters remain fixed across every page.

Traversal preserves response order and advances by the minimum/maximum snowflake
for its direction; it does not assume Discord sorts returned arrays. A short
nonempty page continues until an empty page or the caller's bound. Oversized,
duplicate, nonadvancing or wrong-resource pages fail locally rather than looping.
Cancellation, deadline and finite page budget retain prior yielded values and
perform no further request. No helper claims a stable snapshot while purchases,
consumption, cancellations or ownership change upstream.

## Compatibility boundaries and evidence

Written references control conflicts with stable/preview specifications. Explicit
compatibility includes partial test-entitlement timestamps, optional example
subscription_id, specification-backed authentication/finite SKU filters and the
subscription-get user filter. The specification's required entitlement user_id conflicts
with documented guild ownership; written optional ownership controls. Nullable
guild_id and country are explicit additive specification compatibility overlays. Spec-only
only_active, current-user entitlement routes, preview-only quest-reward kind 10
and Commerce fulfillment/parent/gifter fields remain unsupported typed contracts; raw preservation does not count as parity.

Tests cover written model fields and variants, exact unknown values, null/absence,
malformed inputs and document bounds; request owner encoding; all eight descriptor
wire shapes, auth/API/rate/transport failures, cancellation, read reuse/invalidation
and finite traversal failure paths. The [dated support record](Parity/changes/2026-10-16-monetization.md)
links chronology and migration; the [execution plan](../.air/plans/phase-5i-execution.plan.md)
records executed checks. Local scripted evidence does not qualify live Discord,
other hosts/devices, distributed storage, sustained capacity or early-access Commerce.
Phase 5J adds [lobbies and identity profiles](SocialGame.md); later catalog/event/platform work remains open.
