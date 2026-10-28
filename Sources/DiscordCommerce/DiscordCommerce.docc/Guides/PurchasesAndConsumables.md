[//]: # "File: Sources/DiscordCommerce/DiscordCommerce.docc/Guides/PurchasesAndConsumables.md | Created by Carson Rau. | Copyright (c) 2026 Aurum Studios. | https://aurum-studios.com"

# Purchases, consumables and durable delivery

Treat host acknowledgements as hints and preserve uncertain consumption outcomes for reconciliation.

## Overview

### Verify before consuming

``EntitlementVerification`` exposes an explicit consume operation. The requirement must select `consumable: true`; otherwise it fails before I/O. It fetches uncached authoritative data, validates the exact grant and submits one typed consume mutation. The returned snapshot describes the verified pre-consumption state after an acknowledged consume.

The helper does not deliver a game item, issue refunds, retry uncertain consumption or guarantee exactly once across workers. Assign a durable backend receipt owner and design item delivery idempotently. If cancellation or transport loss follows submission, consumption may already have succeeded; fetch authoritative current state and reconcile the durable receipt before another action.

Verification and consumption are two operations and can race another worker or a revocation. A local actor alone cannot serialize multiple backend processes. Use application-owned transactional/lease boundaries as appropriate for actual delivery semantics, and preserve acknowledged progress when later work fails.

### Keep purchase UI in the host

``ActivityPurchasing`` accepts an injected Activity `startPurchase` bridge and an authoritative backend executor. The bridge returns entitlement ID hints or no synchronous acknowledgement; it never embeds backend credentials. The orchestration independently verifies every returned hint against the server-owned requirement.

Nil means no synchronous acknowledgement and differs from an explicit empty successful list. Later entitlement events should trigger a separate server check. Duplicate, excessive or foreign acknowledgements fail closed; more than 100 IDs are rejected before reads. Activity purchase orchestration requires a user owner and does not silently select a guild grant or consume a returned entitlement.

A successful host purchase call does not mean the backend has granted an item. UI confirmation, server verification, durable admission, consumption and delivery remain distinct owned steps. The portable Swift product does not bundle JavaScript hosting or native store/payment UI.

### Scope claims to implemented contracts

These APIs implement ordinary premium entitlement verification and explicit consumption over the typed catalog. They do not establish unpublished Social Commerce catalog/pricing/gifting/fulfillment contracts. An ordinary consume endpoint is not a fulfillment acknowledgement for another commerce protocol.

### Test end-to-end ownership without purchases

Inject a host closure returning nil, empty, duplicate, excessive and valid synthetic IDs. Assert invalid acknowledgements perform no server reads; valid IDs are verified in host order, and a failed verification stops the result. Assert no hidden consume occurs.

For consumables, record exact fetch/consume counts, cancellation before submission, uncertain writes, acknowledged progress and durable duplicate delivery. Make a late response race deterministic with a barrier. A local synthetic round trip verifies the library's boundaries, not live purchasing, production payment qualification or a durable store implementation.
