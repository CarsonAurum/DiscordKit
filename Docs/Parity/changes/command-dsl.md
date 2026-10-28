<!--
File: Docs/Parity/changes/command-dsl.md
Created by Carson Rau.
Copyright (c) 2026 Aurum Studios.
https://aurum-studios.com
-->

# Typed arguments and command lowering

Recorded, verified and local support date: **2026-10-18**. The additive **0.15.0
candidate** remains unpublished. Upstream announcement/effective dates are **unknown** because
this release record introduces no Discord protocol change. Explicit REST/Gateway v10,
Voice v8, RPC v1, MLS 1.0 and DAVE v1 versions are unchanged.

Previously, the shared DSL supplied inert structural declarations while consumers authored
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
owners. The adapter performs no typed decoding. Broader family, autocomplete and nesting APIs compose through separately
selected contributions.

The [official application-command reference](https://docs.discord.com/developers/interactions/application-commands),
[interaction reference](https://docs.discord.com/developers/interactions/receiving-and-responding),
[API reference](https://docs.discord.com/developers/reference) and
[change log](https://docs.discord.com/developers/change-log) were reviewed on the
verification date for the affected contract. [Source hashes](../../Release/sources/2026-10-18-command-dsl.json)
identify fetched inputs and review scope. Integer and number bounds, leaf option
shape and resolved observations follow existing API v10 models and fresh regression
fixtures; attachment filters remain extension hints rather than content checks.
No upstream endpoint, payload field, permission, intent, event or opcode support is
newly claimed, and discovery/reviewed support classifications are unchanged.

[The command guide](../../CommandDSL.md), [authoring guide](../../DSLAdoption.md)
and scoped release evidence describe each product's adoption and validation limits.
Local decoding and synthetic routes do not establish live Discord, platform or
production-capacity qualification.
