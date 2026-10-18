# Webhooks, interaction responses, monetization and lobbies

Keep token scopes, server entitlement authority and full-replacement game state explicit.

## Overview

### Webhooks and interaction REST

``WebhookEndpoints`` distinguishes bot-authorized management and exact webhook-path-token execution. ``InteractionEndpoints`` handles initial callbacks and original/follow-up operations using the exact interaction credential. Tokens in path segments are secrets even when they are not Authorization headers. Use a stable opaque identity for each token scope and preserve applicable shared egress/rate authority.

Initial acknowledgement needs a dedicated bounded admission path so ordinary REST work cannot consume its time window. DiscordInteractions supplies response ownership and expiry policy; a bare REST descriptor does not reserve an initial-response slot. Follow-ups and edits have different timing and payload semantics from the initial reply. An uncertain callback must not be replayed automatically.

Compatibility webhook formats retain their own validation. Ordinary diagnostics redact path secrets; direct endpoint/URL evidence can reveal them and must be handled deliberately.

### Voice control is separate from media ownership

``VoiceEndpoints`` provides documented voice region and voice-state REST operations. It does not negotiate Voice WebSocket sessions, discover UDP peers, select audio devices or own a media pipeline. A voice-state edit remains subject to current application/channel permissions and cannot substitute for a supervised Voice session.

### Monetization data and authorization

``SKUEndpoints``, ``EntitlementEndpoints`` and ``SubscriptionEndpoints`` expose catalog, grant and subscription resources. Traversal has endpoint-specific cursor and filter rules; test-mode operations require explicit development policy. A subscription lifecycle snapshot or client purchase acknowledgement does not authorize a feature.

Use DiscordCommerce to fetch authoritative entitlement data and validate exact application, SKU, user/guild owner, time, deletion, origin and consumption state. Durable consumable delivery needs a backend receipt owner and reconciliation after uncertain consumption. Neither REST nor an Activity bridge supplies exactly-once game delivery automatically.

### Lobbies and application identity profiles

``LobbyEndpoints`` separates application-bot administration from bearer-consented joining, messaging, linking and leaving. The caller establishes ownership, sdk.social_layer consent, membership and channel-link capability as required. A successful lobby message does not guarantee linked-channel forwarding succeeded.

Member bulk workflows use documented incremental groups and report silently omitted upserts separately from removals. Supplying a modify-lobby array can have replacement semantics; do not convert it into incremental chunks. Recent messages have a finite limit and no invented history cursor.

``ApplicationIdentityProfileEndpoints`` treats provider-issued user IDs as opaque strings and validates profile statistics. Including `data` replaces the complete statistics object, removing omitted fields; omitting it preserves existing data. Bot ownership and application_identities.write consent remain required independently.

Snapshot conveniences in DiscordGameServices may avoid an unchanged write, but do not establish freshness or permissions. Explicitly invalidate other credential scopes when one scope's mutation changes what another can observe; one cache identity cannot automatically invalidate another account's reads.

See the [webhook/interaction/voice](https://github.com/CarsonAurum/DiscordKit/blob/main/Docs/WebhooksInteractionsVoice.md), [monetization](https://github.com/CarsonAurum/DiscordKit/blob/main/Docs/Monetization.md) and [lobby/profile](https://github.com/CarsonAurum/DiscordKit/blob/main/Docs/SocialGame.md) contracts for operation-level details.
