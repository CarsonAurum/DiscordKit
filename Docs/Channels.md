<!--
File: Docs/Channels.md
Created by Carson Rau.
Copyright (c) 2026 Aurum Studios.
https://aurum-studios.com
-->

# Channel and thread REST catalog

DiscordKit provides all 24 operations in the official [Channel reference](https://docs.discord.com/developers/resources/channel)
and [active guild threads](https://docs.discord.com/developers/resources/guild#list-active-guild-threads).
Contracts were verified **2026-10-16** against API **v10**, the
[API reference](https://docs.discord.com/developers/reference), official specification
and [change log](https://docs.discord.com/developers/change-log).
The two thread-start variants sharing a route remain separate typed operations.
See [guild administration](Guilds.md) for related operations.
Related catalogs cover [audit logs and Auto Moderation](Moderation.md),
[emoji, stickers and soundboard](Expressions.md),
[invites, templates, scheduled events and stages](DiscoveryEvents.md), and
[lobbies and identity profiles](SocialGame.md).
DiscordKit provides [applications, users, linked roles and commands](ApplicationsUsers.md).

Import `DiscordHTTP` and `DiscordModels`, inject a transport and credential-sharing
rate/reuse authority, then execute `ChannelEndpoints` descriptors. REST adoption
does not require Gateway. All descriptors use the existing bounded
[HTTP pipeline](HTTP.md), explicit v10 origin and bot authorization. Mutations
conservatively reject ambiguous replay; rejected 429s use the common finite retry
budget. Shards do not raise REST quotas. Permissions remain server-enforced;
snapshots never prove current visibility, membership or authority.

```swift
let channel = try await client.execute(ChannelEndpoints.get(channelID: channelID))
let settings = try ChannelModify(channelType: .guildText, topic: .value("Project updates"))
if let update = try ChannelOperations.modifyIfChanged(current: channel, request: settings) {
    _ = try await client.execute(update)
}
```

## Operations and authorization

| Descriptor | Behavior and additional requirements |
| --- | --- |
| `get` | GET visible channel; thread result can include current membership |
| `modify` | PATCH group DM, guild channel or thread; guild MANAGE_CHANNELS, overwrites MANAGE_ROLES; thread MANAGE_THREADS except eligible unlocked unarchive |
| `delete` | DELETE/close; guild MANAGE_CHANNELS or thread MANAGE_THREADS; returns Channel, retains category children |
| `setVoiceStatus` | PUT nullable status, at most 500 characters; SET_VOICE_CHANNEL_STATUS plus MANAGE_CHANNELS if disconnected; empty 204 |
| `editPermissions`, `deletePermission` | PUT/DELETE guild overwrite, MANAGE_ROLES and grant/hierarchy eligibility; empty 204 |
| `invites` | GET invites plus metadata, MANAGE_CHANNELS; empty lists remain empty |
| `createInvite` | POST required JSON object or CSV multipart, CREATE_INSTANT_INVITE; role grants also MANAGE_ROLES/hierarchy checks |
| `follow` | POST announcement follow, MANAGE_WEBHOOKS in target; returns source channel/webhook IDs |
| `typing` | POST one ten-second indicator; empty 204, no automatic timer/refresh |
| `addRecipient`, `removeRecipient` | PUT/DELETE application-managed group DM membership; outer bot token, add body contains user's separate `gdm.join` token; add returns a Channel on 201 or no snapshot on 204 |
| `startThreadFromMessage` | POST text/announcement source, CREATE_PUBLIC_THREADS; source message ID becomes thread ID |
| `startThread` | POST without message; CREATE_PUBLIC_THREADS/CREATE_PRIVATE_THREADS; omitted v10 type defaults to private |
| `startForumThread` | POST forum/media thread plus first message, SEND_MESSAGES; CREATE_PUBLIC_THREADS ignored; bounded multipart |
| `joinThread`, `leaveThread` | PUT/DELETE current membership; thread must be unarchived; empty 204 |
| `addThreadMember`, `removeThreadMember` | PUT requires ability to send; DELETE requires MANAGE_THREADS or private-thread creatorship; unarchived, empty 204 |
| `threadMember` | GET one membership; 404 is an API error, not an empty member; optional guild-member details |
| `threadMembers` | GET membership; application GUILD_MEMBERS eligibility; v10 pagination only when `withMember` is true |
| `publicArchivedThreads` | GET history-visible public archives, descending archive timestamp |
| `privateArchivedThreads` | GET private archives, READ_MESSAGE_HISTORY and MANAGE_THREADS, descending archive timestamp |
| `joinedPrivateArchivedThreads` | GET joined private archives, READ_MESSAGE_HISTORY, descending thread ID |
| `activeGuildThreads` | GET accessible active public/private guild threads, descending ID; no pagination; guild ID is the rate major parameter |

Audit reasons are supported only where the official reference permits them and
are encoded once by the common pipeline. All empty-result operations require
exactly HTTP 204 and empty bytes. All three thread-creation operations require
HTTP 201; ordinary channel-returning mutations require HTTP 200. Recipient addition
accepts 201 Channel JSON or empty 204; its body decoder accepts either shape after
the common status check and cannot independently bind a shape to one status.
Descriptors preserve exact large snowflakes and never attach credentials to response
asset URLs.

## Models, requests and privacy

`Channel` projects every documented field: guild/text/voice/category/DM/thread/
forum/media settings, overwrite permissions, recipients, managed ownership,
thread metadata/membership, tags, reactions, computed permissions and flags.
`application_id` is optional **and nullable**. Unknown integral variants, flag
bits, field names and nested numeric spellings survive. Unknown response variants
are not accepted as supported outgoing choices. Permission strings retain their
arbitrary width. Forum creation additionally projects the returned initial message.

`ChannelModify` requires channel type and, when needed, parent type context.
Requests validate field applicability, nullability, archive durations, slowmode,
voice limits, tag counts, emoji exclusivity and writable flags. Guild boost level,
existing state and current permissions are server facts; local validation does
not invent them. `ForumThreadStart` permits the documented initial-message fields
and flags, rejects unrelated message features, and reuses validated embeds,
components, attachment metadata and bounded upload factories. Per-file and full
request caps remain separate: defaults are 20 MiB/file and 25 MiB/request.

`ChannelInviteCreate` covers all non-file channel invite fields, validates target
relationships and preserves empty JSON. Optional acceptance CSV uses the exact
`target_users_file` multipart name, validates single-column UTF-8 snowflakes and
bounds the complete materialized body (default local 1 MiB, configurable through
8 MiB). The server ignores duplicate CSV IDs; the library preserves them. An ID
array and CSV cannot coexist. This local byte cap is not a claimed upstream row
limit. The invite response projects every invite/metadata field; nested Guild,
Application, Event and Role families and user/member-family extensions remain
explicit partial projections with exact raw fields until their own batches. The
invite application projection accepts absent/null/future raw types. Approximate
invite counts and roles also retain explicit null, following the official schema
where it differs from the written table; status/schema discrepancies and adopted
policies are recorded in [ambiguities](Parity/ambiguities.json).

Response-model descriptions, debug output and reflection conceal channel names,
invite codes and raw payloads. Recipient token request diagnostics also redact the
token and nickname. Deliberate property/raw-JSON access remains caller-owned.

## Obfuscated channels and chronology

Check `Channel.isObfuscated`, which reads `CHANNEL_OBFUSCATED` (`1 << 17`), rather
than comparing a name to a placeholder. A false result does not prove visibility.
Preserve supplied redacted/null fields and never hydrate them automatically.
For flagged Gateway channels, only id/type/position/parent_id remain reliable;
overwrites contain only an everyone-role VIEW_CHANNEL denial. The model preserves
these snapshots without treating them as authoritative permission calculations.

The **2026-08-12** announcement sets mandatory Gateway obfuscation and HTTP guild
channel omission for **2026-11-16**. On the verification date, Gateway testing
can opt in through a capability or portal toggle; HTTP omission has no early
opt-in. This distinguishes the future transition from already-enforced behavior.
Nullable application IDs were announced **2026-08-05**. Voice status was documented
**2026-04-20**, with its original introduction date unknown; ephemeral status/start
time are not Channel fields. Thread-member detail/pagination was announced
**2023-01-09**; v11's future always-paginated behavior is not assumed in v10.
See the [chronological change record](Parity/changes/2026-10-16-channels.md).

## Request reduction and continuation

Eligible reads coalesce within the injected authentication identity by default.
Completed caching requires an explicit positive TTL. Channel mutations invalidate
the authentication-scoped channel catalog because parent/guild/permission effects
can reach resources whose IDs are not locally available. Direct channel message
tags and search are invalidated too. External changes can remain stale until TTL
expiry. No automatic member/profile hydration or per-item task fan-out is added.

`ChannelOperations` offers finite lazy sequences (at most 10,000 pages) with no
prefetch. Timestamp archives follow `has_more` and the last metadata archive time;
joined private archives follow `has_more` and the last exact thread ID. Complete
envelopes are yielded as singleton pages so thread/member correlation survives.
Every returned cursor is checked against the requested exclusive boundary, even
on terminal pages. Archive timestamps may tie within a page; duplicate thread IDs
and reversed order fail safely. Missing/nonadvancing cursors and empty-continuing
responses also fail; short pages continue. The timestamp API offers no secondary
ID cursor, so ties spanning server page boundaries or concurrent archive changes
can prevent exhaustive traversal; the helper cannot recover omitted records. Archive
page size uses a local 1–100 bound because the written reference does not publish a
numeric maximum. Member pagination explicitly enables
`with_member=true`, advances after-user IDs and continues until an empty page.
Early stop starts no next request. Cancellation, deadline, executor failure and
page exhaustion finish that iterator permanently.

`modifyIfChanged` compares only explicitly requested fields with a caller-owned
snapshot, yielding no descriptor for a no-op. It rejects obfuscated/type-mismatched
snapshots. It performs no read or write itself; stale snapshots still carry the
usual reconciliation race. There is no upstream channel bulk endpoint to invent
or silently emulate with unbounded per-resource mutations.

## Validation scope

Swift Testing fixtures cover typed fields/variants, presence/null rules, type and
count boundaries, exact IDs/permissions, request wire metadata, authorization,
API/transport failure, uncertain mutations, cancellation, upload cleanup, scoped
invalidation, pagination request counts and no-op reconciliation. Tests use finite
local scripts and injected clocks, with no credentials or live Discord traffic.
Full resource-family parity, cross-platform/device qualification, live API and
long-soak gates remain separate in [platform support](PlatformSupport.md).

DiscordKit provides [webhooks, interaction responses and voice control](WebhooksInteractionsVoice.md).
