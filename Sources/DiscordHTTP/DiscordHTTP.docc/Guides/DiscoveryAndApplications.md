# Discovery, events, applications and users

Coordinate invitations and configuration without conflating installation, identity or current consent.

## Overview

### Invitations and scheduled discovery

``InviteEndpoints``, ``GuildTemplateEndpoints``, ``GuildScheduledEventEndpoints`` and ``StageInstanceEndpoints`` provide separate resources and workflows. Target-user invite jobs use bounded validated CSV and explicit job polling; they are not a generic bulk-invite API. Templates distinguish create/sync/modify/delete and guild creation rather than making a template into an implicit live guild mirror.

Scheduled events validate entity type, location/channel requirements, status transitions and recurrence metadata. Subscriber traversal is bounded. A Stage instance controls its documented resource; it does not join voice, start media I/O or grant moderation authority. Preserve unknown response statuses and use supported transitions for writes.

### Application and user configuration

``ApplicationEndpoints`` and ``UserEndpoints`` provide current resources and documented configuration/profile operations. Resource fields can be required nullable, optional or response-only. Application installation settings, permission strings and user premium fields do not establish that the caller currently owns those permissions or scopes.

Snapshot helpers can avoid an unchanged scalar update without a hidden fetch. Nonnull image uploads remain explicit writes because a returned hash cannot prove equality with supplied bytes. If your supplied snapshot is stale, another worker's intervening write can race the comparison; assign an owner or reconcile deliberately.

Current guild traversal uses its documented guild-list partition, which is distinct from a Gateway connection shard ID. Enumerate every applicable list partition when complete coverage is needed. Shards do not increase ordinary REST quotas.

``ApplicationRoleConnectionMetadataEndpoints`` owns linked-role schemas and user metadata writes. Localized keys, schema record limits and string-valued metadata are validated. Discord still decides role assignment. OAuth consent acquisition belongs to DiscordOAuth; a decoded connection alone does not prove a live scope grant.

### Register commands explicitly

``ApplicationCommandEndpoints`` contains global/guild reads, CRUD, bulk replacement and command permission operations. Command types, option nesting, required ordering, localization, autocomplete/choices and installation contexts have typed request validation. A command definition performs no registration by itself.

Bulk overwrite replaces the entire selected scope and is intentionally explicit. Do not chunk it into smaller replacements, silently merge an incomplete listing or automatically replay an uncertain write. DiscordCommands supplies bounded diff/apply orchestration over these descriptors when you want one application-owned registration workflow.

Command visibility, bot permissions, user OAuth consent, guild membership and host interaction context are distinct authorities. Read the endpoint's credential requirement rather than selecting an arbitrary token that happens to be available.

### Validate independent adoption

A REST application can configure commands or read application resources without opening Gateway. Test exact routes, nullable list results, localization payloads, unknown flags, destructive replacement plans and zero-send no-ops with supplied snapshots. The [application/user guide](https://github.com/CarsonAurum/DiscordKit/blob/main/Docs/ApplicationsUsers.md) and [discovery guide](https://github.com/CarsonAurum/DiscordKit/blob/main/Docs/DiscoveryEvents.md) describe each operation's detailed contract.
