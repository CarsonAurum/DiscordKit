# Guild administration REST catalog

Phase 5C implements all **45 operations** in the current official
[Guild reference](https://docs.discord.com/developers/resources/guild), including
active threads through the existing Channel implementation. Contracts were verified
**2026-10-16** against REST **v10**, the [Permissions reference](https://docs.discord.com/developers/topics/permissions),
[Voice reference](https://docs.discord.com/developers/resources/voice),
[API reference](https://docs.discord.com/developers/reference), official
[OpenAPI specification](https://github.com/discord/discord-api-spec) and
[change log](https://docs.discord.com/developers/change-log). Current source hashes
are separate from original discovery pins. No dependencies or products were added;
Part 5D adds [audit logs and Auto Moderation](Moderation.md), and Part 5E adds
[emoji, stickers and soundboard](Expressions.md), and Part 5F adds
[invites, templates, scheduled events and stages](DiscoveryEvents.md); 5J remain pending.
Phase 5G adds [applications, users, linked roles and commands](ApplicationsUsers.md).

Import `DiscordModels` and `DiscordHTTP`, inject a transport and the credential-sharing
rate/reuse authority, then execute `GuildEndpoints` descriptors. REST adoption
requires no Gateway. All requests use the existing bounded [HTTP pipeline](HTTP.md),
explicit v10 paths and guild-major rate admission. Shards do not raise REST quotas.
Mutations reject ambiguous replay, and explicit rejected-429 retries remain within
the common finite budget. Permissions, hierarchy, current feature entitlements,
OAuth consent and intents are server facts, never established by decoded snapshots.

```swift
let guild = try await client.execute(GuildEndpoints.get(guildID: guildID, withCounts: true))
let request = try GuildModify(name: .value("Project community"))
if let edit = try GuildOperations.modifyIfChanged(current: guild, request: request) {
    _ = try await client.execute(edit)
}
```

## Operations and authorization

| Descriptors | Contract and additional requirements |
| --- | --- |
| `get`, `preview` | Guild snapshot or discoverable/joined preview; counts are explicitly requested; unknown fields survive |
| `modify` | MANAGE_GUILD, with ADMINISTRATOR for COMMUNITY changes and feature eligibility on individual fields; JSON presence and nullable image/channel settings remain distinct |
| `channels`, `createChannel`, `modifyChannelPositions` | Lists exclude threads; create/order require MANAGE_CHANNELS, overwrite grants require eligible permissions; GET accepts bot/bearer contexts; one parent move per ordering request |
| `activeThreads` | Existing accessible active-thread envelope; no pagination or member fan-out |
| `member`, `members`, `searchMembers` | User-specific or bounded member results; list requires privileged GUILD_MEMBERS eligibility; search prefix is explicit and no continuation is invented |
| `addMember` | Bot token of the same application plus separately body-carried user `guilds.join` grant; bot must be in guild with CREATE_INSTANT_INVITE; 201 new member or empty 204 existing member |
| `modifyMember` | Per-field MANAGE_NICKNAMES, MANAGE_ROLES, MUTE/DEAFEN/MOVE_MEMBERS, MODERATE_MEMBERS or documented flags eligibility; hierarchy/state checked upstream |
| `modifyCurrentMember`, `modifyCurrentUserNick` | Current nickname/profile settings; CHANGE_NICKNAME for nick; deprecated nick route remains available with migration guidance |
| `addMemberRole`, `removeMemberRole`, `removeMember` | MANAGE_ROLES/hierarchy or KICK_MEMBERS; no implicit related-user fetch |
| `bans`, `ban` | BAN_MEMBERS or VIEW_AUDIT_LOG; ascending exact user-ID pagination, before wins if both before/after supplied |
| `createBan`, `removeBan`, `bulkBan` | BAN_MEMBERS; bulk also MANAGE_GUILD, at most 200 IDs, explicit successful/failed users; failed can mean already banned |
| `roles`, `role`, `roleMemberCounts` | Role metadata, single role and ID-to-count map excluding everyone; no per-member enumeration required |
| `createRole`, `modifyRolePositions`, `modifyRole`, `deleteRole` | MANAGE_ROLES plus hierarchy/grant/feature restrictions; preserve decimal permissions and gradient/holographic colors |
| `pruneCount`, `beginPrune` | MANAGE_GUILD and KICK_MEMBERS, or ADMINISTRATOR when PRUNE_REQUIRES_ADMIN; 1–30 days, explicit role filters; disable count computation for large guilds |
| `voiceRegions`, `invites` | Guild-specific regions; invites require MANAGE_GUILD or VIEW_AUDIT_LOG, with metadata included only for MANAGE_GUILD |
| `integrations`, `deleteIntegration` | MANAGE_GUILD; list capped by Discord to 50, with no documented pagination; deletion can remove associated webhooks/bot |
| `widgetSettings`, `modifyWidget` | MANAGE_GUILD; nullable invite channel and explicit enabled state |
| `widget`, `widgetImage` | Public credential-free access; JSON widget may cause an invite to be created upstream; image returns bounded PNG bytes without attaching credentials |
| `vanityURL` | MANAGE_GUILD and appropriate guild feature; nullable code plus usage count |
| `welcomeScreen`, `modifyWelcomeScreen` | Disabled-screen reads require MANAGE_GUILD; edits require MANAGE_GUILD; nullable fields preserve clearing semantics |
| `onboarding`, `modifyOnboarding` | Read current configuration; edits require MANAGE_GUILD and MANAGE_ROLES; enabled constraints depend on mode and server channel permissions |
| `modifyIncidentActions` | MANAGE_GUILD; optional nullable invites/DM expiration within 24 hours; null disables action |

Audit reasons are exposed only where the written reference permits them. Creation
of a channel expects 201. Member addition accepts 201 Member or empty 204; its
body-only decoder cannot independently bind a permitted body to its status. Ordinary
resource responses require 200; empty operations require exactly 204 and empty
bytes. Member PATCH deliberately requires the written 200/member contract even
though the preview also lists 204. No removed guild-creation/deletion endpoint,
undocumented integration modification, or screening-form operation is introduced.

## Models and validation

Guild, unavailable/preview, member, role/colors/tags/counts, ban/bulk result, prune,
regions, integration/account/application, widget/settings/channel/member/activity,
vanity/error, welcome/onboarding/prompt/option and incidents have typed immutable
projections. Optional absent/null/value states remain distinct; required nullable
keys still reject omission. Exact snowflakes, arbitrary-width permission strings,
future integral/string variants, flag bits and unknown nested numeric spellings
survive. Related User/Application/Emoji/Sticker projections retain explicit partial
classification; decoding does not silently fetch full resources. No Guild Gateway
dispatch completeness or complete resource-family parity is claimed.

The official preview supplements the written table with optional home-header,
legacy age-restriction and progress-bar timestamps, integration application
metadata, widget activity and vanity error details. External integration IDs may
be arbitrary provider strings, while deletion accepts a snowflake only; a returned
string is not fabricated into a deletable ID. Nullable integration names/role IDs
follow explicit response compatibility. The [ambiguity register](Parity/ambiguities.json)
records these decisions and the written/spec member-status discrepancy.

Typed requests cover every written field and explicit preview supplements such as
home-header images and the channel default tag setting. They validate presence,
nullability, names/text, channel-type applicability, archive/slowmode/voice limits,
image data, overwrite/role IDs, writable flags, permission decimal strings,
role-color relationships, welcome/onboarding bounds and user-token syntax. Prose
controls known conflicts: media creation remains available and permissions remain
strings. Optional onboarding request nulls explicitly follow the official preview;
this does not broaden all other request nullability. Server-owned channel visibility,
role hierarchy, boost entitlements and onboarding send-permission counts remain
server checks. No unbounded member hydration, task-per-user fan-out or mutation
packing is hidden in request construction.

Member timeouts use an injectable wall-time snapshot and allow at most 28 days;
incident controls allow at most 24 hours. Construct close to execution because
Discord rechecks these deadlines. The transport's monotonic execution deadline is
independent of those payload wall times. Local request bodies use existing bounded
JSON framing. Position lists have a finite local cap; prune role filters follow
the published 100-role cap. User credentials, names, invitations and raw payloads
are concealed by ordinary descriptions/debug output/reflection; deliberate property
or raw JSON access remains caller-owned.

## Screening and upstream chronology

`GuildMember.pending` preserves the documented screening lifecycle: joins can be
pending, and later member updates clear pending. `BYPASSES_VERIFICATION` is the
only writable member flag. The official reference removed getting/editing the
Membership Screening object and publishes no current form schema. No form model
or route is invented; the member screening state is the available typed contract.

Guild creation deprecation was announced **2025-04-15**, with removal effective
**2025-07-15**. Gradient role colors were documented **2025-07-02**; legacy `color`
remains available for compatibility while `colors` is preferred. Role member counts
were announced **2025-12-09**. Existing channel obfuscation history still applies:
mandatory Gateway redaction/HTTP guild-channel omission is scheduled for
**2026-11-16**, and is not claimed already enforced on this verification date.
Other introduction/effective dates remain unknown. Local support dates and upstream
chronology are distinct in the [change record](Parity/changes/2026-10-16-guilds.md).

## Request reduction and explicit bulk work

Eligible reads coalesce within the injected authentication identity; completed
caching requires an explicit positive TTL. Guild mutations invalidate guild,
channel and message visibility/search snapshots within that identity. These
conservative tags cover membership/role effects on channels whose IDs are not
locally available, with stale-completion fencing in the common pipeline. Foreign
identities remain separate. Unobserved external changes can remain stale until TTL
expiry. Public widgets omit credentials even when called by an authenticated client.

`GuildOperations.memberPages` and `banPages` use lazy exclusive ascending IDs, at
most 1,000 items per page and 10,000 requests. They continue after short pages and
stop on an empty page, without prefetch. Every returned ID must advance, including
nonfinal rows; oversized, duplicate, absent-user or out-of-order results fail safely.
Early stop starts no next request. Cancellation, deadline, executor and page-budget
failures permanently finish an iterator. Concurrent membership/ban changes can
affect coverage; the API provides no traversal snapshot. Member search, integration
listing and active threads gain no invented pagination.

`modifyIfChanged` and `modifyRoleIfChanged` compare only explicitly requested raw
fields against caller snapshots and return nil for a no-op. They perform no read or
write; stale snapshots retain the normal reconciliation race.

`BulkGuildBanPlan` is explicit opt-in, with 1–10,000 distinct users in input order,
sequential legal chunks of at most 200 and at most 50 requests. Complete input
validation happens before I/O. Returned successful and failed IDs must classify
each chunk exactly once, with no duplicate, overlapping, missing or foreign ID.
The outcome restores input order and never silently retries failed users. On error,
`BulkGuildBanFailure` retains acknowledged banned/failed users, entered but
unacknowledged attempted users, wholly unattempted users and the original cause.
A racing valid acknowledgement survives cancellation; an uncertain submission
remains uncertain. There is no rollback, auto-resume or single-ban fallback.
Discord can return API code 500000 when no user can be banned.

## Validation scope

Swift Testing covers all descriptors through the real local scripted HTTP pipeline,
request/response field and enum boundaries, optional/null/malformed/future values,
large IDs, authentication and grant isolation, HTTP/API/transport failures,
cancellation and cleanup, partial bulk outcomes, exact cursors, no-op reconciliation,
request counts, scoped invalidation and coalescing. Tests inject finite scripts and
clocks, with no Discord credentials or live requests. The independent REST example,
tooling/generation/parity and local HTTP load scenarios are validated separately.
Cross-platform/device, live API, durable coordination and long-soak gates remain
separate in [platform support](PlatformSupport.md).

Phase 5H adds [webhooks, interaction responses and voice control](WebhooksInteractionsVoice.md).
