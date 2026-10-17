# Lobbies and application identity profiles: Phase 5J

Verified and locally added **2026-10-16**, REST API **v10**. Local release/commit
remain unknown until creation. [Current source fingerprints](../social-game-current-sources.json)
are recorded separately from unchanged historical discovery pins.

## Previous and current behavior

Previously these Lobby and Application Identity Profile REST operations were
unsupported. This slice adds 16 written Lobby operations and five identity/profile
operations, validated typed request/response contracts, bounded correlated member
bulk workflows and snapshot no-op reconciliation. It preserves bot/Bearer categories,
full-replacement statistics, exact unknown fields and shared HTTP policy ownership.
The link/unlink descriptors share one route; operation counts are not unique routes
or discovery-record counts.

## Known upstream chronology

| Behavior | Announced | Effective | Adopted behavior |
| --- | --- | --- | --- |
| Bulk lobby member reference | 2026-04-24 | unknown | At most 25 updates/removals; returned upserts and silently dropped entries remain distinct |
| Create-or-join, send/recent messages and targeted linked-channel invites | 2026-06-03 | unknown | Explicit member Bearer and backend bot operations |
| additional_name in Create/Modify Lobby | 2026-08-12 | unknown | Nullable writes and optional response/send-time snapshots |
| Game Stats Widgets and Application Identity Profile API | 2026-08-26 | unknown | Owning-bot profile reads/writes and replacement stats |

The [official change log](https://docs.discord.com/developers/change-log) establishes
the dated announcements except the Create/Modify additional_name extension, which
is recorded in the [Lobby resource change log](https://docs.discord.com/developers/resources/lobby#change-log).
Other introduction/effective dates remain unknown. Local support dates do not
establish upstream introduction dates.

## Compatibility and migration

All APIs are additive. Use application bots for backend management and identity
operations, authorized user Bearer tokens for written user lobby operations, and
request the documented target-user consent upstream. ApplicationIdentityProfile
updates replace all included data; send the complete desired data object or omit
data to leave it untouched. Do not send arbitrary metadata as an undocumented write.
Provider IDs are external strings, with optional provider_id disambiguation.

Bulk operations can silently omit upserts and return no removed entries. Preserve
correlation, partial progress and uncertain outcomes; do not assume an atomic bulk
transaction. Written references override preview auth/nullability conflicts. Profile
PATCH accepts first-write 201 and update 204 without a mandatory body, decoding
an optional object according to the explicit [ambiguity policy](../ambiguities.json).

The [contract guide](../../SocialGame.md) records limits, authorization, replacement
and cleanup semantics. Native Social SDK, OAuth flows, Gateway dispatch, production
approval, other-host/device, live Discord, distributed and sustained-capacity gates
remain separate. See the [execution record](../../../.air/plans/phase-5j-execution.plan.md)
for validation evidence.
