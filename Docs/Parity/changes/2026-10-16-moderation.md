# Audit logs and Auto Moderation: Phase 5D

Local implementation and verification: **2026-10-16**. REST API version: **10**.
Local release/commit: unknown until committed/released. No dependency changes.

Previously Audit Log and Auto Moderation resource operations were unsupported.
This change exposes all **six** current written-reference operations: one audit-log
GET and five Auto Moderation list/get/create/modify/delete operations. Audit-owned
entries, changes, options and action identifiers have typed contracts; the envelope
retains explicitly partial User, application-command, scheduled-event and webhook
projections. Auto Moderation has complete rule/action/trigger contracts and validated
outgoing payloads. These resource APIs do not implement the corresponding Gateway
catalog or complete referenced resource families; batches 5E–5J remain separate.

Upstream chronology, distinct from local support:

- **2017-07-24:** Audit Log documentation announced; prior upstream introduction
  and effective dates are unknown.
- **2022-02-14:** API v10 announcement requires `X-Audit-Log-Reason` rather than a
  `reason` request parameter for administrative actions.
- **2022-06-16:** Auto Moderation announced, including create/modify/delete rules,
  configuration/execution Gateway events and initial Auto Moderation audit actions.
  This announcement does not establish separate list/get introduction dates.
- **2022-09-21:** `SPAM` and `MENTION_SPAM` triggers and mention-count metadata
  announced; **2022-11-04:** Rust-flavored regex patterns announced.
- **2022-11-22:** Keyword allow lists, five keyword rules and 260-character regex
  limits announced. **2023-02-08:** Limits changed to six keyword rules per guild
  and 60 characters per keyword. Current reference limits control outgoing validation.
- **2023-02-24:** Custom block-message explanation metadata announced.
- **2023-05-05:** Mention-raid-protection trigger metadata announced.
- **2024-05-31:** `MEMBER_PROFILE` trigger and `BLOCK_MEMBER_INTERACTION` action
  announced; the latter is available for member-profile rules, which create/modify
  payload validation enforces.
- **2026-04-20:** Voice-channel status audit actions documented. The changelog calls
  code 192 `VOICE_CHANNEL_STATUS_UPDATE`, while the current reference/spec call it
  `VOICE_CHANNEL_STATUS_CREATE`; recognition follows the numeric code and reference name.
- Separate effective dates and other field/endpoint introduction dates are unknown.

Official [Audit Log](https://docs.discord.com/developers/resources/audit-log),
[Auto Moderation](https://docs.discord.com/developers/resources/auto-moderation),
[Permissions](https://docs.discord.com/developers/topics/permissions),
[API reference](https://docs.discord.com/developers/reference),
[change log](https://docs.discord.com/developers/change-log) and
[official OpenAPI](https://github.com/discord/discord-api-spec/tree/ed014089afa986f2b532ae081c456a85de074d0c)
were verified 2026-10-16. GitHub's API confirmed that revision as current main.
Hashes in the moderation current-source record remain separate from original
source discovery membership pins. Source content is not vendored.

Compatibility is explicit in the ambiguity register. Audit change keys accept
preview nulls; heterogeneous new/old values retain exact absent/null/value states.
Audit targets retain the broader written nullable string contract. Preview null
Auto Moderation rule elements and nullable integration names are accepted; partial
integration application IDs remain optional across providers. The 69 written action
codes and seven preview-only codes are recognized without claiming the corresponding
resource endpoints or Gateway events. Unknown integer variants and JSON subtrees
remain intact, while malformed known fields fail with sanitized diagnostics. Preset
array elements validate original exact integer spelling before typed projection,
including fractions that Foundation would otherwise round to integral values.

Migration: import Models/HTTP and opt into AuditLogEndpoints/AuditLogOperations or
AutoModerationEndpoints/AutoModerationOperations. Retain credential-scoped shared
rate/reuse authorities. Audit pagination uses explicit before/newest-first or
after/oldest-first boundaries and preserves the response's referenced objects.
Auto Moderation writes require MANAGE_GUILD, and timeout actions additionally
require MODERATE_MEMBERS. Snapshot reconciliation is opt-in and cannot prove
current server state or authorization; it rejects mismatched or unknown snapshot
trigger context before even an empty edit can become a no-op. Audit reasons use the existing bounded,
percent-encoded header. No existing public API is removed or renamed. Validation
uses deterministic local fixtures; live Discord, other platforms and soak
qualification remain open.
