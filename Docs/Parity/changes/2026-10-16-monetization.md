<!--
File: Docs/Parity/changes/2026-10-16-monetization.md
Created by Carson Rau.
Copyright (c) 2026 Aurum Studios.
https://aurum-studios.com
-->

# SKUs, entitlements and subscriptions

Verified **2026-10-16**, REST API **v10**. Current [source fingerprints](../monetization-current-sources.json)
are separate from historical discovery pins; no historical revision is rewritten.

## Previous and current behavior

Previously all eight current written operations were unsupported; interaction
entitlements retained partial related-resource data. This batch implements one SKU,
five Entitlement and two Subscription operations with typed, bounded owned models,
validated owner requests and exact unknown-data preservation. Interaction premium
entitlements now use the resource model. Lazy ascending/descending traversal has
finite page budgets, resource/cursor checks, cancellation and caller-owned partial
results. Existing shared HTTP admission/retry/reuse policies remain authoritative.

## Known upstream chronology

The [official change log](https://docs.discord.com/developers/change-log) establishes
the dates below. Effective dates remain unknown unless explicitly stated. Local
support dates never establish upstream introduction dates.

| Behavior | Announced | Effective | Adopted behavior |
| --- | --- | --- | --- |
| Premium Apps SKU/list/test-entitlement operations and interaction entitlements | 2023-09-26 | 2023-09-26 | Current written REST and typed premium interaction fields; regional eligibility was historical announcement scope |
| One-time purchases, consumable types and consume endpoint | 2024-04-24 | 2024-04-24 | Explicit consume mutation and optional consumed state |
| Premium buttons and callback type 10 deprecation | 2024-06-17 | 2024-06-17 | Existing premium components and deprecated callback retained |
| Subscription API announcement | 2024-08-28 | 2024-08-28 | SKU subscription list/get and billing fields |
| Subscription entitlement migration | 2024-08-28 | 2024-10-01 through 2024-11-01 | Ongoing null ends_at; PURCHASE type 1; no billing-period entitlement renewal assumption |
| Migration completion notice | 2024-11-05 | 2024-11-01 | Subscription cancellation uses status/canceled_at; entitlements indicate access |
| Multiple subscription tiers and renewal_sku_ids | 2024-12-12 | 2024-12-12 | Nullable renewal SKU arrays retained |
| Subscription status documentation correction | 2026-06-16 | unknown | INACTIVE=1, ENDING=2; API values were always correct |

Get Entitlement and other unlisted introduction/effective dates remain unknown.
Gateway and webhook event chronology is context, not an event implementation claim.

## Compatibility and migration

Interaction.entitlements changes from Field<[MessageRelatedResource]> to
Field<[Entitlement]>. Callers gain typed SKU/application/ownership/type/deletion,
nullable validity dates and consumed state. Fixtures containing only ID must supply
the current documented core shape; jsonValue preserves raw/unknown fields. Test
creation is explicitly partial and may omit starts_at, ends_at and subscription_id.
Do not infer absence is null or perpetual access without operation context.

Use subscription state for billing lifecycle and entitlements for premium access.
Recognize corrected statuses and null ongoing ends_at; never require legacy type 8
for subscription purchases. Country remains private-scope data. Create test uses
bot authorization, and unfiltered subscription listing requires OAuth. Written
references control preview ownership/nullability conflicts; every adopted overlay
and spec-only gap is recorded in the [contract guide](../../Monetization.md).

This slice does not create a DiscordCommerce product, publish SKUs, initiate purchases,
implement SDK checkout/fulfillment or close Social Commerce early-access/missing-wire
blockers. Typed event dispatch, ingress and other-host/live/distributed/soak gates
remain open. See the [technical guide](../../Monetization.md)
for local validation and [coverage](../coverage.md) for historical qualification limits.
