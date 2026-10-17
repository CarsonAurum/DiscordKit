# Discovery and event REST catalog

Phase 5F implements all **25 current operations** in the official
[Invite](https://docs.discord.com/developers/resources/invite),
[Guild Template](https://docs.discord.com/developers/resources/guild-template),
[Guild Scheduled Event](https://docs.discord.com/developers/resources/guild-scheduled-event)
and [Stage Instance](https://docs.discord.com/developers/resources/stage-instance)
references: nine invite, six template, six event and four stage operations.
Contracts were verified **2026-10-16** against explicit REST **v10**, the
[API reference](https://docs.discord.com/developers/reference),
[Permissions](https://docs.discord.com/developers/topics/permissions), official
[OpenAPI preview](https://github.com/discord/discord-api-spec) and
[change log](https://docs.discord.com/developers/change-log). Existing channel/guild
invite listing and channel invite creation remain available through their original
descriptors. Removed guild creation from a template is not recreated.

Import `DiscordModels` and `DiscordHTTP`, inject a transport and shared credential
rate/reuse authorities, then execute resource descriptors. This slice adds no
products or dependencies and requires no Gateway connection. Related User and
Application projections remain partial; event dispatch catalogs, voice connections,
5H–5J and platform/live/soak qualification remain separate.
Phase 5G adds [applications, users, linked roles and commands](ApplicationsUsers.md).

## Operations and authority

| Resource | Operations | Authentication and behavior |
| --- | --- | --- |
| Invites | get/delete; export/add/remove/update target users; bulk add/delete targets; job status | Public get defaults to anonymous and supports explicit bot authorization. Other operations require bot authorization. Revocation requires MANAGE_CHANNELS or MANAGE_GUILD; target writes require inviter or MANAGE_GUILD; export/job reads also permit VIEW_AUDIT_LOG. |
| Templates | get/list/create/sync/modify/delete | Public get defaults to anonymous with explicit bot opt-in. Guild operations require bot authorization and MANAGE_GUILD. All successes, including create and delete, return HTTP 200 with template data. |
| Scheduled events | list/create/get/modify/delete/users | Bot authorization. CREATE_EVENTS permits creation and own-event administration; MANAGE_EVENTS permits other-event administration. Stage/voice events also require the documented channel permissions. Get/list require applicable visibility; permissions remain server decisions. |
| Stages | create/get/modify/delete | Bot authorization. Create/modify/delete require Stage moderator permissions; get does not establish moderator authority. Creating a stage does not connect a voice client. |

Invite revocation returns HTTP 200 with the deleted invite. Single/bulk target
mutations and CSV update require empty HTTP 204. CSV update acknowledges upload;
the job status determines processing success. Event creation and ordinary reads/
edits return HTTP 200; event deletion is empty HTTP 204. Stage creation returns
HTTP 200 and deletion empty HTTP 204. Audit reasons are exposed only where the
written contract supports them. Unsafe mutations retain indeterminate outcomes
after ambiguous sends and never silently replay; explicit rejected-429 retries
remain within the common finite budget. Guild/channel major partitions are
preserved; opaque invite/template codes never become invented major parameters.

## Invite targets and asynchronous jobs

`ChannelInvite` now projects its partial guild, assigned roles and embedded
scheduled event with typed fields. Required nullable channel/expiration, approximate
counts, unknown invite variants/flags and exact UInt64 snowflakes retain their
existing presence semantics. Assigned roles are partial snapshots, not full live
`GuildRole` objects; guild/application/user data does not establish acceptance
eligibility or permissions. These guild/role/event properties replace the previous
generic `MessageRelatedResource` types; callers with explicit type annotations
must adopt the new projections. Existing invite creation supports role grants, inline
target IDs and direct multipart CSV, without inventing an acceptance endpoint.

Exports require the documented `user_id` header and retain empty lists, row order,
duplicates and original CSV bytes. Headerless uploads require a nonempty single
column of decimal IDs. LF/CRLF and a trailing newline are accepted; malformed rows,
extra columns, invalid IDs and overflow fail before submission. Parsing is linear
in bounded input bytes and never performs per-user hydration. Local export caps
default to 1 MiB and 100,000 rows, with explicit maxima of 8 MiB/1,000,000 rows;
client response caps also apply. CSV update's local complete multipart cap defaults
to 1 MiB, including framing, with an explicit maximum of 8 MiB. These local caps
are not claims about undocumented upstream upload limits. Nondefault export decode
bounds disable shared read reuse so incompatible decoders cannot share a result.

`InviteTargetUsersJob` retains all six status fields, nullable timestamps/error
text, full UInt32 counters and future status values. `InviteOperations` provides
finite, lazy, paced polling using an injected monotonic clock and deadline. It
yields completed or failed terminal snapshots once; failed processing remains
inspectable failure state. Unspecified/future values remain pending. Abandoned
iteration starts no future poll; polling never submits or retries a CSV mutation.
Explicit bulk target plans split add/remove inputs into legal 1,000-ID groups,
preserve sequential mutation ordering and stop at failure with acknowledged,
attempted and unattempted targets. An empty 204 provides no per-user result.

## Template snapshots and compatibility

`GuildTemplate` includes every written own field, required nonnull creator,
nullable description/is_dirty and exact timestamps. `GuildTemplateSnapshot`
models the serialized partial guild separately from a live Guild: role/channel/
tag IDs are integer placeholders, including negative values and zero. References retain numeric
placeholders and preview decimal-string forms. Roles, overwrites, channels, forum
tags and settings are typed; newly documented preview fields remain optional
because the written snapshot example omits them. Arbitrary-width permission
digits accept the written integer and preview string forms without rounding,
while original JSON preserves their representation. Unknown fields survive the
same whole-document bounds.

Create/modify validate 1–100 Unicode scalar names and omitted/null/0–120 scalar
descriptions. Metadata edits do not synchronize the source guild. Explicit sync
always sends a request; a stale `is_dirty` flag cannot establish that no source
changes exist. `GuildTemplateOperations.modifyIfChanged` validates source-guild
identity and skips only exact requested metadata no-ops against a supplied snapshot.

The [ambiguity register](Parity/ambiguities.json) records the written/preview
creator nullability, numeric snapshot identities/permissions and partial-snapshot
presence differences. Written resource contracts control where they disagree;
compatibility supplements are explicit rather than silently tightening old snapshots.

## Scheduled events, recurrence and stages

`GuildScheduledEvent` includes every written own field, nullable hosting and time
values, recurrence, creator/count/image data and optional preview RSVP/exception
projections. User enumeration preserves typed user/member snapshots, plus preview
RSVP metadata. Required written User data is enforced by the endpoint decoder;
the standalone projection can retain an explicitly identified preview-only RSVP.
Unknown integral status, hosting, privacy and recurrence values remain readable.

Create/modify requests validate stage/voice channel versus external-location
requirements, timestamp ordering, metadata presence, text bounds and the current
writable recurrence subset. External events require a location and end time and
clear channel IDs. Modifying hosting to external requires the explicit documented
fields. Images use a bounded canonical data URI with a local 1 MiB decoded cap;
the complete encoded JSON body is bounded at 2 MiB to account for base64 expansion.
Media content, dimensions, future scheduling and channel eligibility remain server
checks. A guild's 100 scheduled/active event limit is a server constraint.

Recurrence frequency follows the authoritative table/examples/preview: yearly 0,
monthly 1, weekly 2, daily 3. Contrary numeric parentheticals in the limitations
prose are recorded as an ambiguity. Writable rules enforce published intervals
and compatible weekday, ordinal-weekday and annual month/day selectors. End,
count and by_year_day remain response fields because they cannot currently be set
externally. The library does not expand calendars or invent occurrence mutation
routes from preview response schemas.

Snapshot helpers skip exact metadata no-ops and validate requested status context.
Scheduled → active/canceled and active → completed are the permitted transitions;
terminal/reverse transitions fail locally. Discord also automatically begins/ends/
cancels applicable events, so a valid snapshot transition can race server changes.
Subscriber traversal is lazy and finite, validates cursor progress, event identity,
ordering and page size, and performs no member hydration or speculative prefetch.
Pages remain ascending in both cursor directions; before advances toward smaller
IDs using the smallest returned ID. Short nonempty pages continue; empty pages terminate.

`StageInstance` includes its channel/guild IDs, topic, privacy, deprecated
discoverability and nullable scheduled-event association. Writes allow current
guild-only privacy; deprecated public privacy remains readable. Create includes
optional start notification and scheduled-event association. Topic changes have
1–120 scalar bounds. Stage no-op reconciliation uses the caller's exact snapshot
and never assumes liveness, creates a voice connection or fetches current state.

## Request reduction and validation

Eligible reads coalesce within the supplied authentication identity; positive TTLs
explicitly enable completed caching. Successful writes invalidate matching scoped
catalogs and fence stale in-flight completions through the existing pipeline.
Consumers must share rate/reuse authorities across clients/workers using a credential.
Use a shared egress identity for anonymous traffic. Bot writes do not invalidate a
separately scoped anonymous cache; unobserved external actions remain subject to TTL.
Shards do not raise REST quotas, and these operations introduce no unbounded queues,
automatic per-resource tasks or generic mutation packing.

Deterministic Swift Testing fixtures cover all descriptors, model presence and
unknown variants, request limits, CSV framing/jobs, recurrence and transitions,
multiple-page continuation, errors, finite retries, cancellation, scoped reuse/
invalidation and actual no-op request counts. No test requires Discord credentials
or live Discord traffic. Validation results are recorded in the
[Phase 5F execution plan](../.air/plans/phase-5f-execution.plan.md); upstream dates
and local support dates remain distinct in the
[change record](Parity/changes/2026-10-16-discovery-events.md).
