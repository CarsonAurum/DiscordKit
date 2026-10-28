[//]: # "File: Sources/DiscordHTTP/DiscordHTTP.docc/Guides/GuildsModerationAndExpressions.md | Created by Carson Rau. | Copyright (c) 2026 Aurum Studios. | https://aurum-studios.com"

# Guild administration, moderation and expressions

Build narrow administrative workflows with current authorization and explicit partial progress.

## Overview

### Guild-owned resources

``GuildEndpoints`` and ``GuildOperations`` cover guild configuration, members, bans, roles, widgets, integrations, onboarding, welcome screens and incident actions. Every operation retains its descriptor-specific credential, audit-reason, major-resource and response contract. A member list, role array or integration projection does not hydrate the rest of a guild.

Creation, modification and removal can require different permissions and role-hierarchy facts. A cached permission calculation is advisory; Discord remains authoritative. Large member enumeration uses bounded lazy continuation, and ban/prune or role-position plans preserve their documented partial outcomes instead of promising a transaction.

Optional request fields preserve omission, null and empty values. Role reordering and onboarding arrays can have replacement semantics. Check complete requested state before construction; do not chunk a replacement merely because an incremental helper exists for another operation.

### Audit logs and Auto Moderation

``AuditLogEndpoints`` supplies typed audit traversal and keeps unknown action codes and nested change values. Correlate related resources using the response's explicit objects rather than assuming every changed ID is a user. Pagination is bounded and preserves the selected before/after direction. Audit reasons are encoded by descriptor policy; do not pre-escape them or insert them into a route string.

``AutoModerationEndpoints`` and its request values validate trigger metadata, actions and legal create/edit combinations. Trigger type, event type, exemptions, enabled state and action metadata must describe a supported combination. Validation prevents malformed local payloads; rule effectiveness, permissions and remote limits can still fail at execution.

Test unknown action/trigger values on reads and rejected unsupported writes separately. Keep attacker-supplied message content and rule metadata out of generic logs.

### Emoji, stickers and soundboard

``EmojiEndpoints``, ``StickerEndpoints`` and ``SoundboardEndpoints`` expose distinct guild/application/default resource operations. Permissions, media formats, image/audio limits, sticker packs and available authentication differ by operation. A response image hash or URL does not prove it equals outgoing bytes, so snapshot reconciliation cannot silently suppress a new media upload.

Validated media payloads and upload helpers bound per-file and full-request bytes. Use credential-free AssetClient for an approved external asset fetch rather than forwarding a bot or bearer token to a CDN. Preserve nullable creator/user projections and unknown expression fields during decoding.

Soundboard data and control requests are separate from a running Voice session. Listing a sound or describing a send does not select an audio device or own a UDP lifetime.

### Design reviewable administrative jobs

Resolve the requested target set before beginning, cap items/pages/bytes, retain input correlation and report completed, rejected, dropped and unattempted work. Stop after an unsafe uncertain submission and reconcile. A successful earlier mutation remains applied if a later request fails.

Use synthetic guilds and deterministic peers to test authorization errors, age/count bounds, invalid combinations, unknown response fields, fractional 429 delays, deadlines and cancellation cleanup. See the [guild](https://github.com/CarsonAurum/DiscordKit/blob/main/Docs/Guilds.md), [moderation](https://github.com/CarsonAurum/DiscordKit/blob/main/Docs/Moderation.md) and [expression](https://github.com/CarsonAurum/DiscordKit/blob/main/Docs/Expressions.md) contracts for exact operations.
