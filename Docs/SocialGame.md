# Lobbies and application identity profiles

Phase 5J implements **21 current written REST operations** in API **v10**:
16 Lobby operations, including the separate link/unlink descriptors sharing one
route, and five Application Identity/Profile operations. The current
[Lobby reference](https://docs.discord.com/developers/resources/lobby),
[Application Identity Profile reference](https://docs.discord.com/developers/resources/application-identity-profile),
[API reference](https://docs.discord.com/developers/reference) and
[change log](https://docs.discord.com/developers/change-log) were verified
**2026-10-16**. [Current fingerprints](Parity/social-game-current-sources.json)
remain separate from historical discovery pins. No dependencies or runtime products
are added. Native Social SDK, OAuth consent acquisition and Gateway event dispatch
remain independent roadmap work.

## Owned models and authorization

Lobby snapshots include application ownership, nullable string metadata, members
and optional linked channels. Members preserve metadata absence/null, open flags
and optional additional names. Messages project their own ID/type/content, lobby
and compatibility channel IDs, typed User author, send-time additional-name snapshot,
dispatch/moderation metadata, flags and application ID. Exact unknown JSON and
numeric lexemes remain available under whole-document byte/depth/node bounds.
Linked Channel and author User reuse the existing independently owned projections;
a snapshot does not establish current membership, permission or freshness.

| Operations | Credential contract |
| --- | --- |
| Create/get/modify/delete lobby; add/bulk/remove member | Application bot |
| Create or join; send/recent messages; self invite | Bearer with sdk.social_layer |
| Leave; link/unlink channel | Bearer; linking also requires CanLinkLobby |
| Moderation metadata; invite a specified user | Application bot |
| All identity/profile operations | Owning application bot; target user consent with application_identities.write |

Credential categories are checked locally. Discord enforces scopes, application
ownership, consent and current membership. Applications without increased production
limits have application-wide development limits, including 100 operations per two
hours for listed lobby writes and 20 channel-linking writes per two hours. These
are not per-user allowances. Descriptors retain shared rate admission, bounded
retry, request/response budgets, deadline and cancellation ownership; they do not
override upstream quotas. Reads use explicit credential-scoped reuse policies and
successful writes invalidate affected snapshots conservatively within that credential
scope. A bot write cannot invalidate an independently scoped Bearer snapshot; use
explicit caller invalidation or bounded TTL for changes observed through another
credential. Mutations are never
silently combined or replayed after uncertain transport outcomes.

## Lobby writes and bounded workflows

Metadata updates replace the supplied map; omission preserves it and explicit null
clears it where documented. Lobby/member metadata has a 1,000-character combined
key/value limit. Member additional_name accepts 1–80 characters, with omission
preserving and null clearing it on writes. Idle timeout is 5–604,800 seconds.
Create/modify member arrays have at most 25 entries. Bulk update takes 1–25 entries;
remove_member marks removals and the response contains only successful upserts.
Unknown users cause a 404; permission/membership-limit failures may silently drop
upserts. An absent response member never proves removal or successful admission.

Explicit bounded member workflows split legal requests sequentially, retain input
correlation and completed progress, and expose silent omissions separately from
removals. Failures stop subsequent requests; no helper promises a transaction or
rolls back already accepted writes. Snapshot reconciliation can avoid unchanged
metadata writes without fetching current state; callers decide whether their
snapshot is fresh enough. A modify-lobby member array is not automatically chunked
because that could change replacement semantics.

Recent-message retrieval accepts limit 1–200 (default 50). The written API has no
cursor, so this slice exposes no invented history pagination. Sending requires
nonempty content; dispatch metadata is not persisted on forwarded channel messages.
If linked-channel forwarding fails, Discord can still deliver the lobby message.
Moderation accepts up to five string pairs, keys up to 1,024 characters and values
up to 2,000. Linked-channel invites are single-use, targeted and expire in one hour;
the caller must establish the documented linked-channel and membership prerequisites.

## Identity keys and complete statistics replacement

ApplicationIdentity keeps provider_type, optional provider_id, external
provider_issued_user_id and the lookup examples' optional Discord user_id.
Provider types remain open strings and external identifiers are encoded as path
segments rather than interpreted as snowflakes. Wrapped identity lookups preserve
empty matches. provider_id disambiguates external lookup and deletion.

Profile snapshots include required nullable username, arbitrary metadata and data;
data contains optional primary statistics and dynamic fields. All 18 primary fields,
the string/number/media dynamic variants and media URLs are typed. Unknown variants
and fields retain exact raw values. Numeric statistics preserve decimal spelling
instead of passing through binary floating point. Media URLs must be publicly
reachable for Discord to fetch them; local validation does not prove reachability.

An update can change username and/or data. **Including data replaces the entire
existing data object**, including omitted primary/dynamic fields; omitting data
leaves existing statistics untouched. The API does not document a metadata write.
The written data-object cap is 10 KB. The request builder conservatively requires
fewer than 10,000 serialized UTF-8 bytes, rather than assuming a 10,240-byte
interpretation. It accepts at most 30 dynamic fields,
100-character stat strings/names and a 1,024-character username. Widget-config
custom strings are a separate portal surface. No helper fetches and merges stats
or assumes that a sparse patch preserves omitted fields.

A first profile write can create a NONE-provider identity. Subsequent writes must
match an existing external ID. Deletion removes an identity and its profile data, but Discord blocks deletion
of the last account-linking identity. Profile-only NONE identities can be deleted. Callers own external
account conflict recovery and consent. A read snapshot grants no deletion authority.

## Compatibility and qualification

Written references control credential conflicts with the preview specification,
including Bearer-only user operations and nonnull bulk arrays. Link and unlink use
the same channel-linking route with different payloads. The profile-update prose
mentions an object while its response section specifies first-write 201 and
subsequent 204. The descriptor accepts those statuses without requiring a body;
when a body is supplied it validates the typed profile. This is an explicit
compatibility policy, not a claim that Discord always supplies an object.

The [dated support record](Parity/changes/2026-10-16-social-game.md) preserves
upstream/local chronology and the [execution record](../.air/plans/phase-5j-execution.plan.md)
records validation. Scripted tests and finite offline HTTP measurements do not
qualify live Discord, native Social SDK interoperability, production approval,
other-host/device behavior, distributed coordination or sustained capacity.
