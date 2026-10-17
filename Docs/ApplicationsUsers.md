# Applications, users, linked roles and commands

Phase 5G completes the written API v10 application/user and command REST slice
within the independently adopted DiscordModels and DiscordHTTP products: **32
available written operations** (3 Application, 12 User, 2 linked-role metadata and
15 Application Command operations). Current
official references and the change log were verified **2026-10-16**; source hashes
are separate from historical discovery membership pins. No new dependencies,
runtime products or consumer generation steps are introduced.

The [Application reference](https://docs.discord.com/developers/resources/application),
[Team reference](https://docs.discord.com/developers/topics/teams),
[User reference](https://docs.discord.com/developers/resources/user),
[linked-role metadata reference](https://docs.discord.com/developers/resources/application-role-connection-metadata)
and [Application Commands reference](https://docs.discord.com/developers/interactions/application-commands)
define this batch. Written references control conflicts with the official preview;
explicit compatibility overlays preserve additional response data without turning
preview-only routes into available operations.

## Application configuration and profiles

Application includes current configuration, installation contexts, counts, team,
owner/bot/guild projections and activity instances. Exact original JSON survives
within whole-document byte/depth/node bounds. Optional, required and explicitly
nullable fields keep their distinct states; future enum codes and unknown fields
remain readable. Response decoding performs no related-resource fetches.

The response-only flags_new field preserves a decimal bitset wider than UInt64.
Configuration writes use the original flags field and its documented mutable mask.
Neither installation settings nor decoded permission strings establish that a
caller has permission to perform an operation. URLs are configuration values;
decoding never opens them or grants destination authority.

Application.team retains the original exact nullable JSON shape; teamDetails
validates the complete typed Team. Existing fixtures with nonnull incomplete teams
must provide their known required fields. flagsNew now rejects nondecimal strings.
Application description writes use the written string form; a separate mutually
exclusive localizedDescription exposes the explicit preview form. Outgoing install
permission digits follow the written string contract despite preview integers.

ApplicationOperations.modifyIfChanged uses caller-supplied snapshots for zero/one
request reconciliation. Nonnull icon/cover uploads always remain mutations: a
response hash cannot prove equality with image data. User profile reconciliation
uses the same rule for avatar/banner uploads.

The original DiscordEndpoints.currentApplication and currentUser entry points
remain available and use the same tagged cache policy as their resource namespaces.
Existing scalar regression cases remain tested after moving both partial generated
models to handwritten bounded codecs. See [generation](Generation.md).

## User authorization and linked roles

User-owned avatar decoration, collectibles/nameplate and primary-guild structures,
connections, current guild summaries and role-connection metadata have typed
projections. Referenced partial resources are explicitly identified; no automatic
full-member or profile hydration occurs. Unknown connection service names survive.
Riot Games/League connections are no longer returned after **2026-07-10**, and
Battle.net connections after **2026-09-22**; historical names are never treated as a new supported service.

Bot and OAuth2 bearer policies follow each operation. Current-user identify/email/
identify.premium, guilds, guilds.members.read, connections, gdm.join and
role_connections.write scopes remain server authorization requirements. Payloads
never imply a scope grant. Group DMs use explicitly supplied authorized user tokens;
this is not a general user-session or Social SDK implementation. Application
provisioning and OAuth2 token acquisition remain separate work.

Guild lists use finite lazy continuation and the documented 1–200 item page limit.
Large bots must supply a guild-list shard in **0..<max_concurrency**, taken from
Gateway discovery. This parameter is distinct from a Gateway connection shard ID.
Complete enumeration requires each applicable guild-list shard; stopping traversal
starts no prefetch. Ordinary bot/guild quotas do not increase with shard count.

List results explicitly preserve preview-permitted top-level null separately
from empty arrays. UserConnectionAccount preserves a required nullable provider
name without widening the older Guild integration-account contract. Linked-role
localization keys include the explicitly documented preview locale overlay.

Linked-role schemas enforce at most five records, unique valid keys and bounded
localized metadata. Explicit user metadata updates preserve strings, empty maps,
omission and permitted null values; role assignment remains Discord's decision.

## Command registration and permissions

Chat-input, user, message and primary-entry-point command types, all eleven option
types, choices, localizations, installation contexts, interaction contexts and both
entry-point handlers have typed request/response contracts. Current attachment
file-type filtering is modeled. Response parsing accepts unknown variants; outgoing
builders validate known types and compatibility rather than sending guessed values.

Validation covers names, localized values, description and option limits, nested
subcommand structure, required-option ordering, choices versus autocomplete, numeric
and string bounds, scope-specific contexts and the complete registration payload.
Bulk overwrite is an explicit destructive replacement with per-type count limits.
The snapshot reconciliation helper uses only caller-supplied complete snapshots;
it issues zero or one replacement request and never silently fetches, merges,
chunks a destructive replacement or replays an ambiguous mutation.

Global and guild CRUD/list/bulk endpoints share implementation while preserving
exact routes, statuses, authentication and guild-major partitioning. Permission
reads are distinct from bearer-only permission replacement, which requires
applications.commands.permissions.update and the necessary guild/role authority.
The **disabled Batch Edit Application Command Permissions** operation has no
descriptor. Use explicit per-command permission writes within shared admission.
Deleting or renaming commands can permanently remove their existing permissions.

## Shared execution and verification boundaries

All operations use [the shared HTTP pipeline](HTTP.md): explicit v10 routes,
credential-scoped rate authority, finite retry budgets, cancellation and deadlines,
ordered mutations, bounded replayable JSON bodies and sanitized API errors.
Eligible read reuse remains opt-in for completed-result caching; successful
mutations invalidate the relevant family tags. Unknown mutation outcomes retain
their uncertainty and are never silently retried as safe requests.

Deterministic tests exercise field presence, malformed inputs, unknown variants,
large IDs, request construction, authorization, exact statuses, API/transport
failures, retries, cancellation, cleanup, request reduction and bounded workflows.
The [execution plan](../.air/plans/phase-5g-execution.plan.md) records final commands
and results. Local tests use synthetic credentials and injected peers, never
authenticated Discord requests. Platform/device, live API, distributed coordination
and sustained-capacity qualification remain open; interaction handlers, command
routers and batches 5H–5J remain later work.

The [chronological change record](Parity/changes/2026-10-16-applications-users.md)
separates known upstream announcements/effective dates from local support dates.
