# Phase 15B: typed arguments and command lowering

Recorded, verified and local support date: **2026-10-18**. The additive **0.15.0
candidate** remains unpublished. Local commit is **unknown** until the implementation
commit is created. Upstream announcement/effective dates are **unknown** because
this checkpoint introduces no Discord protocol change. Explicit REST/Gateway v10,
Voice v8, RPC v1, MLS 1.0 and DAVE v1 versions are unchanged.

Previously, Part 15A supplied inert structural declarations while consumers authored
command options, routes and invocation decoding directly. Independently selected
`DiscordCommandDSL` now supplies handwritten `CommandArguments`/`ArgumentValue`,
finite typed descriptors/schemas, optional/default/choice/reference codecs and strict
per-invocation decoding. A `ManualSlashCommandHandler` and `SlashCommand` use one
captured schema to produce existing validated registrations and matching routes.
`ExistingSlashCommand` explicitly adopts a validated low-level root slash pair.
`CommandCompilation` lowers finite modules in source order and rejects duplicate
routes, unsupported contributions and inconsistent external snapshots.

Construction and compilation start no tasks, I/O, registration or handler execution.
`CompiledCommands.makeRouter` explicitly constructs the existing bounded router;
application-owned invocation retains cancellation and the existing unique response
owner. Each typed invocation validates complete input before creating fresh argument
state. Missing/null/value, exact integer/snowflake IDs and same-interaction partial
resolved data remain distinct. Diagnostics retain bounded metadata rather than user
argument contents. User-provided synchronous getters/codecs/builders must terminate
and remain free of side effects; arbitrary Swift is not sandboxed.

The product selects DSL/Core/Models/Commands/Interactions. Existing products and
the Core/Models-only shared DSL acquire no upward dependency. No Gateway, Client,
Cache, concrete adapter, compiler plugin or SwiftSyntax is selected. Existing
low-level consumers require no migration: opt into the new product, compile manual
root slash contributions and explicitly register/reconcile/route using existing
owners. The adapter performs no typed decoding. Existing low-level APIs retain
broader family/autocomplete/nesting coverage until those authoring milestones ship.

The [official application-command reference](https://docs.discord.com/developers/interactions/application-commands),
[interaction reference](https://docs.discord.com/developers/interactions/receiving-and-responding),
[API reference](https://docs.discord.com/developers/reference) and
[change log](https://docs.discord.com/developers/change-log) were reviewed on the
verification date for the affected contract. [Source hashes](../../Release/sources/2026-10-18-phase15b.json)
identify fetched inputs and review scope. Integer and number bounds, leaf option
shape and resolved observations follow existing API v10 models and fresh regression
fixtures; attachment filters remain extension hints rather than content checks.
No upstream endpoint, payload field, permission, intent, event or opcode support is
newly claimed, and discovery/reviewed support classifications are unchanged.

[The guide](../../CommandDSL.md), [implementation status](../../DSLImplementationRoadmap.md)
and scoped release evidence distinguish local authoring/decoding/synthetic route
coverage from macros, typed response builders, policies, other command families,
supervised HTTP/Gateway applications, live Discord, platform and capacity gates.
