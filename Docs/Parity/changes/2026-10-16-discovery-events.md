<!--
File: Docs/Parity/changes/2026-10-16-discovery-events.md
Created by Carson Rau.
Copyright (c) 2026 Aurum Studios.
https://aurum-studios.com
-->

# Invites, templates, scheduled events and stages

Local implementation and verification: **2026-10-16**. REST API version: **10**.
No dependency changes.

Previously channel invite creation/listing and guild invite listing were available
with explicitly partial related projections. The remaining Invite family and the
Guild Template, Guild Scheduled Event and Stage Instance families were unsupported.
This change exposes all **25 current written-reference operations**: nine Invite,
six Guild Template, six Guild Scheduled Event and four Stage Instance operations.
Existing channel/guild invite descriptors are reused. Corresponding Gateway dispatch
catalogs and related User/Application family completion remain separate.

Upstream chronology, distinct from local support:

- **2021-11-15:** Initial Guild Scheduled Event documentation recorded in the
  **2021-11-23** change-log entry. This is documentation history, not an inferred
  introduction date for every current endpoint or recurrence field.
- **2021-11-18:** That entry records the users response-shape change, before/after
  cursors, creator responses and the single-event user-count query option.
- **2025-11-20** and **2025-11-24:** Event permission changes announced; the
  CREATE_EVENTS requirement for bot event creation takes effect **2026-02-23**.
- **2026-01-13:** Target-user CSV export/replacement/job-status operations and
  channel invite role grants/CSV restrictions announced.
- **2026-02-05:** Export CSV header standardized to `user_id`; channel invite role
  responses changed to the documented partial role shape.
- **2026-09-18:** Single/bulk target-user addition/removal and the channel invite
  `target_user_ids` creation option announced.
- Other endpoint, template, stage, recurrence and field introduction/effective dates
  are unknown. Local commits do not establish upstream chronology.

The official [Invite](https://docs.discord.com/developers/resources/invite),
[Guild Template](https://docs.discord.com/developers/resources/guild-template),
[Guild Scheduled Event](https://docs.discord.com/developers/resources/guild-scheduled-event),
[Stage Instance](https://docs.discord.com/developers/resources/stage-instance),
[Permissions](https://docs.discord.com/developers/topics/permissions),
[API reference](https://docs.discord.com/developers/reference),
[change log](https://docs.discord.com/developers/change-log) and
[official OpenAPI](https://github.com/discord/discord-api-spec/tree/ed014089afa986f2b532ae081c456a85de074d0c)
were verified **2026-10-16**. GitHub's API confirmed that specification revision as
current main. Current hashes in the discovery/event source record are separate
from original discovery pins; upstream source contents are not vendored.

Compatibility decisions remain explicit in the ambiguity register. Template
snapshots preserve signed integer placeholders and exact permission digits from the written
example, while accepting explicitly supported preview reference forms. Partial
snapshot fields remain optional rather than requiring preview-only fields absent
from the written example. Deprecated public-stage response values remain readable;
validated outgoing requests use the supported guild-only privacy level. Recurrence
frequency codes follow the consistent frequency table and examples, retaining the
prose inconsistency as a documented ambiguity. Preview RSVP/recurrence-exception
response supplements do not implement preview-only mutation operations.

Migration: ChannelInvite guild/roles/event properties now use typed projections;
replace explicit old MessageRelatedResource type annotations. Exact rawFields remain
available. Import Models/HTTP and opt into the family endpoint and bounded workflow
helpers. Share authentication-scoped rate/reuse authorities; retain exact opaque
invite/template codes and the standardized CSV header. Template placeholders are
not live resource IDs. CSV jobs and user traversal have finite caller-selected
budgets, cancellation and independent cursor ownership. Mutations preserve ordering
and indeterminate outcomes rather than silently replaying unsafe submissions.
Bulk target-user plans split explicit finite inputs into legal 1000-ID chunks and
retain acknowledged, entered-but-unacknowledged and unattempted IDs on failure. An
empty 204 response acknowledges a chunk without reporting individual membership.
Cover images have a local 1 MiB decoded-byte cap and event JSON a local 2 MiB
encoded-byte cap. Snapshot no-op comparisons do not establish current server state
or permission.

No removed guild-creation route is recreated. Tests use deterministic local fixtures,
without Discord credentials or live Discord traffic. Live API conformance, other
platforms/devices, durable distributed coordination and long-soak qualification
remain separate gates. See the discovery/event contracts for
exact permissions, compatibility boundaries and validation evidence.
