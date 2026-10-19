# Modular authoring design

The Phase 15 DSL is an authoring layer over DiscordKit's existing values, command
router, interaction responder and supervised client. A module describes finite
contributions. A compiler validates those contributions. An explicitly started
host invokes them through the existing runtime owners. Selecting syntax does not
select a Discord connection, register commands or grant authorization.

See [adoption](DSLAdoption.md) for independently compiled examples and
[the implementation roadmap](DSLImplementationRoadmap.md) for milestone accounting.

## Choose the layer that owns the requirement

| Layer | Responsibility | Explicit selection |
| --- | --- | --- |
| Shared declarations | Ordered modules, stable IDs, namespaces, dependency validation, structural limits, text and generic policies | `DiscordDSL`, over Core/Models only |
| Commands | Typed invocation preparation, command families, validated messages, route lowering and response adapters | `DiscordCommandDSL`, over existing Commands/Interactions/HTTP/Transport |
| Gateway applications | Intent checks, bounded event pipelines, trusted interaction admission and supervised client composition | `DiscordBotDSL`, over existing Client and command owners |
| Macro authoring | Generate ordinary protocol conformances, schemas and metadata at compile time | Separate `Packages/DiscordDSLMacros` package |
| Extension libraries | Application-domain codecs, modules, policies and service contracts | Separate downstream packages, such as `Packages/DiscordDSLExtensions` |
| Measurement and release | Compiler/runtime budgets, independent consumers, API/graph/docs/evidence checks | Development tools, outside runtime product graphs |

Existing low-level products remain independently adoptable. Runtime products select
no macro plugin, SwiftSyntax or documentation generator. The umbrella does not
silently install a DSL application. Optional Voice, Social and OAuth integration
belongs to the application's composition root and injected interfaces.

## Follow declarations into execution

`BotModule` supplies an explicit `moduleID` and synchronous `body`. `BotBuilder`
collects declarations in source order, including finite loops and conditionals.
`DefinitionPlan` admits module/declaration identities, supported kinds/capabilities,
depth, count and UTF-8 text budgets. Its immutable description supports reproducible
offline review; it does not describe every behavior captured by handler closures.

Typed leaves retain their contribution values for downstream compilation.
`CommandCompilation` captures schemas once and lowers commands to existing
`CommandDefinition`/`CommandRoute` values. `EventCompilation` checks explicit intent
requirements and creates an inert event plan. Both reject unsupported or inconsistent
metadata rather than treating a raw declaration's kind as implementation evidence.

The host starts work explicitly. `CommandApplication` verifies signed HTTP receipt
and invokes the bounded router. `BotRuntime` subscribes before client startup and
supervises the client, events and optional trusted interaction bridge. Neither
construction, compilation nor ordinary serving synchronizes command registrations.
Reconciliation is an explicit operation with managed name/type scope and partial
or indeterminate outcomes.

## Preserve identity, authority and response ownership

`ModuleNamespace` records exact namespace components separately from original IDs
and source metadata. It qualifies structural installation identity, while Discord
command names, component/modal IDs and event handler IDs retain their own uniqueness
rules. Installing the same wire command twice still fails command compilation.

Services and actors enter through ordinary typed Sendable dependencies.
`DependentModule` validates immutable local configuration after module admission
and before creating its body. It creates no service locator, replacement actor or
implicit authority. Share aggregate credential, startup, lease, handler, REST and
resource authorities across every module that uses the same application resources.
One process-local actor does not coordinate multiple workers.

Complete input preparation precedes policies, middleware and deferral. Authorization
is an injected current decision; command defaults, cache snapshots and partial
resolved resources remain observations. Bounded predicates short circuit;
middleware forwards at most once through command adapters. Exceptions, cancellation
and partial side effects never justify automatic mutation replay.

Immediate handlers return one initial response. Deferred handlers confirm the defer
before user work and finish through edit-original. Manual handlers retain the existing
responder and its deadline, uncertainty and token-expiry state. Gateway receipt
changes admission, while callbacks continue through HTTP with independent initial
response admission. Public event-hub publication cannot authenticate an interaction.

## Bound the owned state and report the actual evidence

Count, byte, depth, queue and concurrency limits govern the state each owner admits.
User builders, validators and callbacks remain ordinary Swift: they must terminate,
cooperate with cancellation and keep child work structured. Admission cannot preempt
arbitrary Swift or reclaim allocations made before compilation.

Source audit, compiler fixtures, exact JSON comparisons, cleanup tests and independent
offline consumers establish their named local contracts. Compiler-generated DocC
pages and callable-comment presence require semantic review as well. The
[benchmark guide](DSLBenchmarks.md) separates paired handler measurements, compiler
costs, handler soak and cache/broadcast soak. None qualifies a live fleet. Release
records preserve platform, live Discord, device, independent crypto review and
complete-client interoperability exclusions.
