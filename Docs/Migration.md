# Compatibility and migration

The current runtime candidate is **0.18.0**. The separate authoring checkpoint is
**0.15.0**, covering Parts 15A-15L. The
historical Phase 14 checkpoint is **0.14.0**. Neither candidate implies a tag or
package publication. Preserve the
explicit protocol versions REST/Gateway **v10**, Voice **v8**, RPC **v1**, MLS **1.0**
with ciphersuite **2**, and DAVE **v1** independently of the package version.

## Semantic logging migration

Logging now uses dotted component labels, for example `discordkit.http.execution`
and `discordkit.gateway.session`. Update exact-label filters from the earlier flat
labels; `dk.module` groups logical modules and `dk.subsystem` identifies the full
component. Existing event identities remain where their meaning is unchanged.

Info and notice now record significant library lifecycle outcomes and milestones,
so default SwiftLog configuration exposes those events. Trace records fine execution
steps; debug records diagnostic summaries. Use `DiscordLogConfiguration` to select
thresholds by longest dotted-prefix match, and `DiscordLog.context` or correlated
operation scopes to follow work through child components.

Changing a native multiplex logger's threshold also changes child thresholds.
Wrap outputs with `DiscordLevelFilterLogHandler` to preserve a console's minimum
severity while enabling trace to a file. Bootstrap and output lifetime remain owned
by the executable. See [logging adoption](Logging.md) for setup and privacy details.

## Local Swift API changes

Compare the current emitted public symbol graphs with the committed API baseline
before publishing. The baseline records its compiler/platform scope; compare using
the same toolchain and host. Treat removed declarations, signature changes,
default-argument changes, enum evolution, concurrency/isolation changes, behavior
and error contracts as compatibility review inputs. Symbol graph comparison cannot
establish binary ABI, source compatibility on every platform or unchanged behavior.

Use semantic versioning: after 1.0, incompatible public changes require a major
version; backward-compatible additions require a minor version; compatible fixes
require a patch. During 0.x, use a minor increment for breaking API design changes
and document each affected symbol and migration. Do not silently reset a baseline
to make a check pass. Retain the previous baseline/report for release comparison,
review the difference, explain required edits, then adopt the new baseline as part
of the approved release change. Phase 14 establishes the initial recorded baseline;
it introduces tooling/docs/example composition and no intended runtime API removal.

Independent adoption remains the preferred migration path: replace umbrella imports
with the products your consumer needs, inject the shared authorities it owns,
start work explicitly, and await closure. Values with `Field.absent`, `.null` and
`.value` retain different update meanings. Unknown enum values and raw fields do
not prove implemented support for the corresponding upstream feature.

## Adopt typed command authoring

Follow [the adoption guide](DSLAdoption.md) for a source-backed route from minimal
protocol/macro commands to actor dependencies, policies and HTTP/Gateway hosts.
The [design guide](DSLDesign.md) explains each layer's dependency and lifetime
ownership. Existing direct consumers can adopt one route or module at a time.

Existing `DiscordCommands` consumers require no migration. Select `DiscordDSL`
for structural modules and `DiscordCommandDSL` for typed argument decoding and
manual root slash handlers. A `SlashCommand` contribution captures one schema and
lowers it to existing `CommandDefinition`/`CommandRoute` values; inspect the
compiled definitions before explicit reconciliation or registration.

To adopt an existing root slash definition and exact matching route incrementally,
wrap them in `ExistingSlashCommand`. This adapter performs no typed decoding and
rejects unsupported families, nesting and autocomplete. Use `ExistingCommandFamily`
for complete low-level catalogs or the typed family adapters introduced in Part 15F.
Use `ManualSlashCommandHandler` with the existing `InteractionContext.responder`
for explicit response ownership. Part 15C optionally replaces schema/metadata
boilerplate with the separate [macro package](MacroDSL.md), retaining the same
protocols and decoders. Part 15D adds opt-in `SlashCommandHandler` and
`DeferredSlashCommandHandler` contracts; change `execute` to accept the restricted
typed context and return `MessageResponse` or `DeferredMessageResponse`. The adapter
owns acknowledgement and edit-original completion. Manual handlers need no changes.
Use `CommandApplication` for signed HTTP composition and call `synchronize` separately
when registration is intended. Do not configure application auto-defer alongside it.
Part 15E optionally replaces direct message construction with `Text`, `Embed` and
`Components` inside a response builder. `MessageContent` escapes ordinary strings
and admits mentions through typed interpolation; explicit raw segments retain
caller-owned formatting and never enable broad parsing by themselves. Existing raw
Models remain available. See [message builders](MessageBuilders.md) for field
presence, validation and intentional mention policies. Part 15F adds optional
[command-family adapters](CommandFamilies.md) without changing existing handlers.
Use a command tree for nested slash paths and keep partial autocomplete distinct from
complete invocation arguments. Context menus use typed partial targets; component and
modal routes use separate exact-ID namespaces. Synchronization still manages only
compiled name/type pairs and never deletes unmanaged commands. Part 15G adds
optional [policies and middleware](CommandPolicies.md) with explicit authorization,
shared concurrency admission and rejection/error mapping. See
[response ownership](CommandResponses.md) and [the guide](CommandDSL.md)
for argument presence, limits, diagnostics and the custom-code contract.

## Adopt the supervised module host

Existing direct Gateway/client consumers require no migration. Part 15H's
[event modules](GatewayEventModules.md) still compile and run through explicit
subscription owners. Part 15I expands the selected `DiscordBotDSL` graph to include
Client and CommandDSL for [supervised bot applications](BotApplications.md); the
shared and command-only graphs remain independent. A consumer that audits an
event-only product closure must accept these host dependencies or retain direct
Gateway dispatcher adoption. Selecting BotDSL starts no client or command work.

Supply the existing client, compiled event plan, handler configuration and optional
trusted interaction adapter to `BotRuntime`; place explicit dependency construction
in a `BotApplication.makeRuntime` factory when an application entry point is useful.
Use `requestStop` inside handlers and await `run` or external `shutdown` to join
cleanup. Keep authorities shared across modules and client replacements. The bridge
receives trusted input only from client ingestion, while responses remain HTTP
callbacks. Continue to synchronize commands explicitly. The [DSLBot example](../Examples/DSLBot/README.md)
exercises synthetic host composition without credentials or external sockets.

Part 15J optionally installs reusable modules under `ModuleNamespace` and validates
explicit typed `ModuleDependencies` through `DependentModule` before creating its
body. Existing unnamespaced IDs retain their duplicate checks; namespaces preserve
raw IDs and never rewrite command routes or runtime handler IDs. Duplicate event
handler IDs now fail event compilation before a subscription is created. Select
external libraries explicitly and pass the same application-owned services to each
module. See [external modules and typed dependencies](ModuleExtensions.md) for bounds,
diagnostics and the independent HTTP/Gateway consumers.

## Upstream protocol changes

An upstream addition, deprecation, effective-date change or removal is separate
from a local Swift API break. Append parity history with previous/current wire
behavior, affected symbols/payloads, official sources, announcement/effective dates
or `unknown`, the verification day, local release/commit and migration advice.
Review affected inventory rows and regression fixtures together. Keep future
effective transitions distinct from the current contract; do not infer introduction
dates from local commits or automatically apply changed documentation to code.

In particular, the announced channel-obfuscation HTTP transition is effective
**2026-11-16**. The dated transition fixtures and release report identify the
pre-effective and future-effective expectations. A fixture is regression evidence,
not a live preproduction or post-effective Discord result. Reverify the official
[change log](https://docs.discord.com/developers/change-log) and applicable
[HTTP guidance](HTTP.md) at release time; policy or error handling changes must be
reviewed before that effective date.

## Evidence carried with releases

The reviewed Phase 15 API uses separately named `0.15.0` root, macro and extension
baselines. Preserve the `0.14.0` baseline and historical checkpoint reports;
compare fresh compiler graphs to the old baseline for migration review and the
new baseline for same-version stability. Candidate certification adds guides,
tutorials, audits and scoped evidence; it does not require an existing runtime
consumer to adopt DSL products or macros. See [release tooling](ReleaseTooling.md)
for the exact comparisons and current report selection.

Each release includes a machine-readable report and a readable companion identifying
toolchain, protocols, source verification day, platform matrix, public API baseline,
isolation/build/test/generation results, capacity evidence and excluded gates.
The current [release directory](Release/README.md) explains the initial records.
Run the report validator and current-source/maintenance checks before publishing.
Changing a date does not refresh upstream evidence.

Retain workload, hardware and revision alongside performance results. Investigate a
greater-than-10% baseline regression reproduced in three runs on matching hardware.
A local 30-minute fixed-working-set soak measures its named cohort and resources;
it does not count logical accounts as real sockets or qualify a live fleet.
Unverified infrastructure, hardware, live Discord and independent cryptographic
review remain excluded from the associated claims even when all local tests pass.
