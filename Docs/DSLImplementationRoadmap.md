# Modular bot authoring implementation

Phase 15 is delivered as independently usable milestones. **15A** implements the
shared structural foundation in `DiscordDSL`; **15B** adds typed argument decoding
and explicit slash-command lowering in `DiscordCommandDSL`. **15C** adds the separate
`DiscordDSLMacros` authoring package with compiled parity and external fixtures.
**15D** adds typed immediate/deferred responses, manual ownership and a signed HTTP
command application. **15E** adds validated message/component builders and safe typed
interpolation over existing Models. **15F** adds command trees, typed context menus,
partial autocomplete, exact component/modal handlers and explicit catalog reconciliation.
**15G** adds bounded short-circuit policies, ordered middleware, injected authorization and
concurrency admission with explicit rejection/error mapping. **15H** adds typed Gateway
event modules over existing bounded subscriptions and per-shard dispatch. **15I** adds
an explicit bot application host, shared REST services and a trusted Gateway interaction
bridge under the existing supervised client lifetime. **15J** adds explicit namespace
installation, typed dependency validation and independent external extension consumers.
**15K** adds an independent offline benchmark package, paired direct/DSL handler workloads,
compiler-cost measurements, finite regression budgets and separate handler/cache soak evidence.
These statuses do not
imply that the complete bot authoring experience is available. See
[shared declarations](DSL.md), [typed commands](CommandDSL.md), [macros](MacroDSL.md),
[response ownership and HTTP applications](CommandResponses.md),
[message/component builders](MessageBuilders.md), [command families](CommandFamilies.md),
[policies and middleware](CommandPolicies.md), [Gateway event modules](GatewayEventModules.md),
[supervised bot applications](BotApplications.md), [external modules and typed dependencies](ModuleExtensions.md),
[offline measurements](DSLBenchmarks.md) and [architecture](Architecture.md) for the implemented APIs and product boundaries.

| Milestone | Status | Scope |
| --- | --- | --- |
| 15A | Implemented | Protocol/module composition, result builders, stable explicit identities, source diagnostics and bounded deterministic descriptions. |
| 15B | Implemented | Typed argument schemas/decoding, manual slash handlers, exact existing-command adapters and lowering to existing command definitions/routes. |
| 15C | Implemented | Separate authoring macro package, source diagnostics, compiled expansion parity and external positive/negative compile fixtures. |
| 15D | Implemented | Typed immediate/deferred and manual response ownership, signed HTTP command application, explicit reconciliation and independent offline/listener consumer. |
| 15E | Implemented | Validated text/embed/component builders, safe typed interpolation and explicit mention allowlists, with direct-payload parity and immediate/deferred response adapters. |
| 15F | Implemented | Slash trees, typed context menus, partial autocomplete, exact component/modal handlers, legal response families and explicit change-only catalog reconciliation. |
| 15G | Implemented | Bounded named/operator policies and middleware, guild/context checks, injected authorization/concurrency and explicit rejection/error mapping. |
| 15H | Implemented | Typed selectors/handlers, explicit intent validation, one default subscription and bounded independent groups over existing per-shard dispatch. |
| 15I | Implemented | Explicit BotApplication host construction, shared typed services, trusted Gateway interaction callbacks over HTTP and supervised client/pipeline lifetime. |
| 15J | Implemented | Explicit namespaces, validated lazy typed dependencies and independently compiled public extension libraries reused by HTTP/Gateway consumers. |
| 15K | Implemented locally | Reproducible direct/DSL handler and manual/macro compiler measurements, finite budgets and separate fixed-working-set handler/cache soak evidence. |
| 15L | Planned | Complete DSL adoption/migration guides and full Phase 15 release certification. |

15A's immutable descriptions can be inspected and compared offline. The description
contains only metadata; the plan also retains typed contributions without executing
them or owning a runtime. 15B compiles retained command contributions to existing
`CommandDefinition` and `CommandRoute` values, with an explicit `makeRouter` factory.
Compilation starts no tasks or handler execution; invoking that router uses existing
interaction response ownership. Bot products will reuse the existing client
implementation, while existing products keep their independent adoption graphs.
15D composes the existing signed HTTP application and bounded router. Explicit
`synchronize` owns registration; construction and ordinary `run` never
register commands. Typed handlers cannot access the raw responder; manual handlers
retain that explicit escape hatch. The macro package remains a separate consumer of runtime products, with no compiler
plugin or SwiftSyntax dependency in the shared product. Part 15E adds shared pure
content values and CommandDSL message/component builders with explicit validated
lowering. Ordinary text is escaped and typed mentions synthesize narrow allowlists.
Response builder overloads reuse the same immediate/deferred owners. Raw Models and
field-presence semantics remain available. Part 15F extends the compiled catalog to
all currently supported command families and route-only interaction contributions.
Initial-response constraints and complete-versus-partial decoding remain distinct;
existing command reconciliation preserves unmanaged names and partial outcomes.

Part 15I broadens the explicitly selected `DiscordBotDSL` graph to compose Client,
CommandDSL and the existing Commands/Interactions/HTTP/Transport owners. Existing
products acquire no dependency on BotDSL; shared and command-only adoption remain
independent. `BotRuntime` subscribes before client startup and joins client, event
and interaction work on terminal exit. Construction and ordinary execution register
nothing. Trusted interaction admission comes from the client's ingestion boundary;
publishing a synthetic envelope to an ordinary event hub grants no authenticity.

Part 15J keeps the existing shared, command and bot runtime graphs unchanged.
`ModuleNamespace` scopes only structural module/declaration identities and records
its exact component path separately from original metadata. Wire route names and
event handler identities keep their existing downstream uniqueness rules.
`DependentModule` admits its installation, validates an injected Sendable
`ModuleDependencies` value, then creates its body. Invalid dependencies produce a
bounded diagnostic before body evaluation. The separate `DiscordDSLExtensions`
package is consumed explicitly by the independent HTTP and Gateway examples;
runtime targets do not depend on it or discover it automatically. Application-owned
Voice, Social and OAuth interfaces can be injected without changing those graphs.

Structural admission limits describe finite compilation resources. They do not
establish network throughput, bot population, live Discord interoperability or
production capacity. Later milestones require their own implementation, tests,
independent consumers and evidence before those behaviors are claimed.
