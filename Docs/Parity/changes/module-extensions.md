<!--
File: Docs/Parity/changes/module-extensions.md
Created by Carson Rau.
Copyright (c) 2026 Aurum Studios.
https://aurum-studios.com
-->

# External modules and typed dependencies

The unpublished 0.15.0 candidate adds authoring extensions on
2026-10-18. Upstream announcement/effective dates are unknown: this work introduces
no new Discord endpoint, event, intent, permission, model projection or wire schema.
Existing official-source review records continue to govern the composed contracts.

Previously external modules used public contribution protocols and ordinary
initializer dependencies, with globally unique structural IDs and application-owned
configuration validation. `ModuleNamespace` now installs reusable local module and
declaration IDs under exact ordered namespace components. Original IDs, source
coordinates, module ancestry and raw metadata remain unchanged; descriptions expose
separate namespace installations/paths and collision-safe `DefinitionIdentity` values.
Every namespace, including an empty one, participates in duplicate, count, depth,
structure and aggregate text admission. Namespace installation never rewrites wire
routes or relaxes downstream command/event identity checks.

`ModuleDependencies` provides synchronous throwing local validation.
`DependentModule` retains the explicitly injected Sendable value and lazy body
factory. Compilation first admits the module, validates dependencies, then creates
and collects the body once per admitted installation. Rejected admission skips validation; rejected dependencies
skip body creation. A bounded `invalidDependencies` diagnostic retains source and
ancestry while discarding dependency contents and the original error. Collector
failure remains terminal even if custom expansion catches it.

The separate `DiscordDSLExtensions` package supplies reusable public extension
libraries. Independent HTTP and Gateway consumers select them through ordinary
package dependencies and retain existing command, response, dispatch and supervised
lifetime owners. The examples exercise custom typed argument decoding, command
contributions, policy composition and shared injected state, including low-level
command adoption beside typed handlers. Compile fixtures cover correct and rejected
dependency types. Root products never select the extension package; shared DSL
remains Core/Models-only and command-only adoption remains independent of
Gateway/Client/Cache. No compiler plugin, reflection-based registration, ambient
service lookup or new runtime is introduced.

Application-owned Voice, Social and OAuth interfaces may be injected into typed
dependency values without adding those imports to shared/command/bot runtime
products. Existing service-specific authority, consent, lifetime, qualification and
failure contracts remain unchanged. Reuse the same aggregate authorities across
modules; a namespace or module creates no additional quota or resource owner.

Adopt the [extension guide](../../ModuleExtensions.md), independent
[extension package](../../../Packages/DiscordDSLExtensions/README.md) and affected
[DSLCommands](../../../Examples/DSLCommands/README.md) /
[DSLBot](../../../Examples/DSLBot/README.md) consumers. Current scoped validation
belongs in [the authoring release report](../../Release/release-report-0.15.0.json).
Local/offline compilation and execution do not establish live Discord,
cross-platform/hardware behavior, optional service qualification or DSL capacity.
Compile/runtime measurements, sustained-handler evidence and release validation
retain their own source-bound reports.
