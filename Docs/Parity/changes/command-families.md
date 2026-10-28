<!--
File: Docs/Parity/changes/command-families.md
Created by Carson Rau.
Copyright (c) 2026 Aurum Studios.
https://aurum-studios.com
-->

# Command families and explicit registration

Recorded, verified and local support date: **2026-10-18**. The **0.15.0 candidate**
is unpublished. Upstream
announcement/effective dates are **unknown** for this additive authoring change.
REST/Gateway v10, Voice v8, RPC v1, MLS 1.0 and DAVE v1 remain unchanged.

Previously the command DSL compiled typed root slash commands and required direct
low-level authoring for other families. The command-family APIs add slash subcommands/groups,
typed user/message context-menu targets, partial autocomplete, exact-ID component
handlers and typed modal submissions. Response protocols and validated wrappers
preserve immediate/deferred/manual ownership and prevent ordinary illegal family
combinations. Current text/select/upload/radio/checkbox modal fields remain bounded
and complete input is admitted before user execution. The router also accepts
omitted options on zero-argument subcommands; null/malformed nested paths fail.

Complete catalogs include exact route metadata under shared structural limits.
Registration identity remains `(application, scope, type, name)` and synchronization
remains explicit, change-only and sequential through the existing reconciler.
Unmanaged registrations survive, no-op catalogs fetch once without mutations, and
partial failures retain acknowledged progress. Constructors and ordinary serving
perform no registration. The optional macro package adds context-menu authoring and
slash-leaf adapters without selecting compiler plugins in runtime products.

No existing API is removed. Adopt [family contributions](../../CommandFamilies.md)
in existing modules as needed; raw Models/Commands remain independently usable.
Existing model gaps and authorization distinctions remain explicit. No new endpoint,
field, event, permission, intent or wire-parity classification is claimed. Policies, Gateway hosts and runtime measurements have separate contracts and evidence.

The official [command reference](https://docs.discord.com/developers/interactions/application-commands),
[interaction reference](https://docs.discord.com/developers/interactions/receiving-and-responding),
[component reference](https://docs.discord.com/developers/components/reference),
[API reference](https://docs.discord.com/developers/reference) and
[change log](https://docs.discord.com/developers/change-log) were reviewed with
[exact source hashes](../../Release/sources/2026-10-18-command-families.json).
Local synthetic signed HTTP, compiled fixtures and JSON parity do not qualify live
Discord registration/rendering, other platforms, hardware or production capacity.
