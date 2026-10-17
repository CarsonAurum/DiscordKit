# Applications, users, linked roles and commands: Phase 5G

Verified and locally added **2026-10-16**, REST API **v10**. Local release and commit
are unknown until release/commit creation. The clean 5F baseline is 9542e90.
Current source fingerprints are recorded separately in
[application/user sources](../application-user-current-sources.json); historical
discovery revision/hash membership remains unchanged.

## Previous and current behavior

Previously, User/Application exposed generated partial scalar projections and two
current-profile reads. This batch implements **32 current written operations**:
three Application, twelve User, two Application Role Connection Metadata and
fifteen Application Command operations. Shared global/guild command methods retain
distinct upstream operation mappings. The disabled batch command-permission write
is explicitly classified removed and has no runtime descriptor.

The models cover current owned fields, typed nested values, open response variants,
localizations and unknown exact JSON. Requests validate configuration/install data,
profile edits, consented DMs, role definitions and all command kinds/options/choices.
Finite lazy guild traversal supports explicit large-bot storage shards. Snapshot
helpers skip proven no-ops without fetching; command bulk registration remains an
explicit destructive replacement. Every request uses shared bounded HTTP policy.

Current User/Application codecs and compatibility descriptors are handwritten.
The original 128 scalar fixture cases still execute, and a frozen separate tooling
seed retains positive generator coverage. Generated Swift now retains PremiumType;
all five owned output files are regenerated explicitly and checked without writing.

## Known upstream chronology

The [official change log](https://docs.discord.com/developers/change-log) supplies
these announcement/effective dates. Other upstream introduction/effective dates
remain **unknown**; the local support date cannot establish them.

| Behavior | Announced | Effective | DiscordKit behavior |
| --- | --- | --- | --- |
| Permissions v2 disables batch command-permission editing | 2022-04-27 | unknown | No descriptor; explicit per-command bearer writes |
| Application activity-instance retrieval | 2024-09-26 | unknown | Typed read and location/instance projections |
| User premium type requires approved identify.premium scope | 2026-05-05 | 2026-05-05 | Scope documented; zero is not proof of no Nitro |
| Application response flags_new | 2026-05-07 | 2026-05-07 | Exact decimal string; writes retain legacy flags |
| Riot Games/League connections removed | 2026-07-07 | 2026-07-10 | No new recognized service case; unknown/legacy raw values survive |
| Command attachment file-type filtering | 2026-08-05 | 2026-08-05 | Validated attachment-option file_types |
| Battle.net connections removed | 2026-08-14 | 2026-09-22 | No replacement invented; raw response values remain open |
| Large-bot guild-list shard required | 2026-09-15 | 2026-09-15 | Explicit 0..<max_concurrency selection, distinct from Gateway shard ID |

## Compatibility decisions and migration

Written contracts control conflicts. Application description writes use strings;
localizedDescription is a separate explicit preview form. Permission bitsets use
written decimal strings despite preview integer request schemas. Additional preview
nullable list/nested states remain explicit rather than collapsed into empty values.
Command permission writes require bearer authorization despite preview BotToken
security, and global command counts include the written primary-entry-point slot.
Guild bulk-only settings follow its explicit request table. These decisions appear
in the [ambiguity register](../ambiguities.json) and regression tests.

Existing scalar User/Application APIs and current-profile descriptors remain.
Application.team retains exact raw JSON and adds typed teamDetails; a present
team now requires its documented known shape. Fixtures containing incomplete
arbitrary team objects must supply the required fields. flagsNew now rejects
malformed nondecimal strings. Related partial-resource projections are labeled,
and original raw fields remain available for deliberate inspection.

No dependencies or targets were added. Command routers, interaction handlers,
OAuth2 token acquisition, full referenced/event catalogs and batches 5H–5J remain
separate. Validation is deterministic/local on macOS and uses no live Discord
credentials. Device/other-host, distributed coordination and sustained-capacity
qualification remain open; see [contracts](../../ApplicationsUsers.md) and the
[execution evidence](../../../.air/plans/phase-5g-execution.plan.md).
