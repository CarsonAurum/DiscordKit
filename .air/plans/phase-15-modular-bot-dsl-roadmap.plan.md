# Phase 15: Modular Swift bot authoring DSL

## 1. Goal

Add a protocol-led, macro-assisted Swift DSL that turns reusable bot modules into the existing validated command, interaction and Gateway execution APIs, with independently adoptable HTTP and Gateway products.

## 2. Approach

Use protocols for executable behavior and extension points, result builders for composition, and macros for repetitive schema, routing and decoding declarations. Compile declarations into an immutable, bounded plan before starting work; lower that plan into the existing command router, interaction responder, event dispatcher and client rather than introducing another network runtime. The standard authoring experience includes macros from an early milestone, while every generated conformance also has a supported explicit Swift implementation.

This is one coordinated roadmap with independently usable milestones. It follows your preference for protocols, builders and macros: command and event behavior normally lives in protocol methods; trailing closures remain for builder bodies, and callback closures remain implementation details at existing adapter boundaries.

### Existing foundations and design consequences

- Command definitions already have an option result builder and validated registration models. Reuse those models rather than create parallel wire validation. [CommandDefinition.swift][definitions]
- Exact routes already distinguish command type, subcommand path, autocomplete focus, components and modals, with bounded handler admission. DSL compilation produces these existing definitions and routes from one declaration. [CommandRouter.swift][router]
- Incoming arguments preserve exact JSON values and field presence, but do not yet provide a command-specific typed argument model. This is the principal new command abstraction. [Interaction.swift][arguments]
- Initial reply and deferred completion are different operations. The first release uses immediate, explicitly deferred and manual handler modes, with one response owner. [InteractionResponder.swift][responses]
- The client already owns raw Gateway ingestion and shutdown. The DSL consumes its broadcast hub and existing bounded dispatcher. [DiscordClient.swift][ingestion], [EventHandlers.swift][dispatcher]
- Root products use Swift 6.4, ApproachableConcurrency and nonisolated default isolation. Preserve those settings. SwiftSyntax currently exists only in the separate development package. [Package.swift][settings], [Package.swift][syntax]

### Package architecture

| Product/package | Responsibility | Dependency boundary |
| --- | --- | --- |
| DiscordDSL | Shared module/body protocols, structural builders, source diagnostics, finite plan contributions, typed message content and policy composition | Core and Models only; no execution, transports or compiler plugins |
| DiscordCommandDSL | Argument/schema protocols, command handler families, response/component builders, lowering, HTTP composition and explicit registration | DSL plus existing Commands, Interactions, HTTP and their directly imported foundations; no Gateway, Client or Cache |
| DiscordBotDSL | Typed event handlers, Gateway interaction adapter, shared service adapter, BotApplication and supervised lifetime | DSL, CommandDSL, Client, Gateway and explicitly imported foundation products; no voice, Social, OAuth or concrete adapter requirement |
| DiscordDSLMacros, separate Swift package | Public authoring macro declarations plus a host compiler-plugin target | Authoring library references runtime products; plugin uses compatible SwiftSyntax. Runtime packages never depend back on this package |

The shared product earns its place by serving both command and event modules: structural composition, diagnostics, policy expressions and message content have no interaction-runtime dependency. Existing independently adopted products receive no upward dependency on the DSL. Concrete transports stay in application composition roots, following [Package.swift][dependencies] and [Architecture.md][architecture].

The macro package is a separate consumer of the runtime package, avoiding a dependency cycle. Quickstarts explicitly import its public authoring module and the relevant runtime DSL product. Pin and verify a SwiftSyntax release compatible with the implementation toolchain; the existing 604.0.0 development pin is a starting point, not an automatic upgrade decision. [Package.swift][syntax]

### Proposed authoring experience

Illustrative API target, to be compiler-tested in 15B–15E:

~~~swift
import DiscordCommandDSL
import DiscordDSLMacros

@CommandArguments
struct GreetArguments: Sendable {
    @Option(description: "Person to greet")
    var user: UserReference

    @Option(description: "Optional greeting")
    var greeting: String?
}

@SlashCommand("greet", description: "Greet someone")
struct Greet: SlashCommandHandler {
    typealias Arguments = GreetArguments

    func execute(
        _ context: CommandContext,
        arguments: Arguments
    ) async throws -> MessageResponse {
        MessageResponse {
            Text("\(arguments.greeting ?? "Hello"), \(mention: arguments.user.id)!")
        }
        .ephemeral()
    }
}

struct CommunityCommands: BotModule {
    @BotBuilder
    var body: some BotDefinition {
        Greet()
        Help()
    }
}
~~~

Policy composition is similarly declarative, with named equivalents for each operator:

~~~swift
Greet()
    .requiring(IsGuild() && Authorized(by: accessPolicy))
    .middleware(AuditInteractions(log: audit) >>> RecordMetrics(metrics))
~~~

Here Option is macro field metadata, not mutable invocation state. CommandArguments generates schema and a decoder from its own declaration. SlashCommand generates command metadata and contribution plumbing; it refers to Arguments through its protocol and does not try to inspect another type's source. Handler instances are immutable definitions; each invocation receives a separate argument value.

A Gateway module uses the same structural builder to include types conforming to GatewayEventHandler. Their handle methods receive an associated typed event and context. Actor services are ordinary initializer dependencies. A BotApplication supplies modules and an explicitly constructed host; its default main delegates to the supervised runner. Environment reading, credential creation and concrete adapter selection remain in the application host.

### Swift feature choices

| Feature | Planned use and semantics |
| --- | --- |
| Protocols, associated types and opaque results | BotModule/Body, BotDefinition, CommandArguments, ArgumentValue, command response families, GatewayEventHandler, policies and host interfaces. Third-party types compose without adding cases to a central closed enum. |
| Result builders | BotBuilder, MessageBuilder, ComponentBuilder and command-group composition. Support empty blocks, expressions, if/else, optional branches, arrays and finite loops. Use partial-block construction where it simplifies inference; erase structural collections before runtime. |
| Compiler literal protocols | MessageContent conforms to ExpressibleByStringLiteral and ExpressibleByStringInterpolation, with a custom StringInterpolationProtocol. Preserve literal/text/typed-mention segments until validated rendering. |
| Custom operators | A single new >>> operator composes middleware; named then has identical behavior. Overloaded &&, || and ! compose policy values with documented evaluation order and short circuit behavior. Operators construct values and perform no I/O. |
| Macros | CommandArguments, Option and SlashCommand first; additional command-family macros after their explicit protocols work. Emit ordinary schema/decoder/conformance code and useful source diagnostics. |
| Sendable and actors | Immutable definitions and compiler-checked captures; actor dependencies own mutable state. No unchecked concurrency escape hatch for convenience. |
| AsyncSequence | Reuse existing bounded Gateway subscriptions. It provides iteration syntax; queue bounds and broadcast ownership continue to come from the existing hub. |
| callAsFunction | Optional invocation syntax for compiled pure policies/decoders, with named evaluate/decode equivalents. Resource startup remains named run. |

Result builders and macros are compiler features rather than protocols. The literal/interpolation interfaces are actual compiler-integrated protocols. Their language contracts support the separation above. [Result builders](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0289-result-builders.md), [partial blocks](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0348-buildpartialblock.md), [string interpolation](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0228-fix-expressiblebystringinterpolation.md), [attached macros](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0389-attached-macros.md)

Parameter packs are a later convenience experiment for heterogeneous argument constructors, subject to compile-time measurements; named argument structs remain the primary API. String-based dynamic member lookup, dynamic callable routing, reflection-driven property discovery and global service locators are outside the initial design. Key-path-based access can be added where it demonstrably removes boilerplate without weakening checking.

### Compilation and execution contract

1. Construct modules synchronously. No tasks, subscriptions, sockets, environment reads or registration occur.
2. Collect public typed plan contributions, retaining module identity and source locations. Third-party composite modules expand through their body; custom leaves implement the documented contribution protocol.
3. Validate duplicate identities/routes, schema/decoder agreement, available host capabilities, module depth, declaration count, total text bytes and policy count. Unsupported contribution kinds fail with a source diagnostic.
4. Lower commands to CommandDefinition and CommandRoute; assemble one existing bounded CommandRouter. Keep explicit adapters for already-written low-level definitions/routes. [CommandDefinition.swift][definitions], [CommandRouter.swift][router]
5. Expose explicit synchronize through CommandReconciler. Construction and run never synchronize automatically, delete unmanaged registrations or introduce automatic mutation replay. [CommandReconciler.swift][reconciler]
6. For Gateway hosts, subscribe before client startup and supervise the client and handler dispatcher in one task group. Module count does not imply subscriber count. [DiscordClient.swift][construction], [EventHandlers.swift][dispatcher]
7. On failure or cancellation, cancel subscriptions, request client shutdown, await every child and propagate terminal cleanup errors. Preserve the underlying single-use lifecycle. [DiscordClient.swift][shutdown]

Proposed initial structural defaults: 256 module instances, depth 32, 4,096 declarations, 1 MiB declaration text and 32 policies per route. These are configurable admission defaults, not deployment capacity claims. Builders enforce count/byte bounds incrementally where possible; expansion halts at depth/count limits. Arbitrary user code inside a builder must terminate cooperatively.

### Invocation and response contract

- Decode arguments before calling user execution. Required absence fails; optional absence becomes nil; explicit null follows the selected codec and is not silently treated as absence. Reject duplicate/unknown argument names for the chosen schema, wrong kinds and invalid ranges with a structured error.
- Decode integers from exact number lexemes and snowflakes from typed identifiers. Respect Discord option ranges independently of Swift numeric capacity. Resolved references retain their partial/unavailable state; decoding performs no hydration. [Interaction.swift][arguments], [official command schema](https://docs.discord.com/developers/interactions/application-commands)
- Immediate typed handlers return a response sent through the existing initial-response owner. Deferred typed handlers explicitly acknowledge before invoking user work, then complete through editOriginal. Manual handlers use a distinct protocol and return Void.
- Typed-return contexts do not expose the raw responder. Manual contexts do. This prevents the ordinary API from both acknowledging imperatively and returning another initial response. [InteractionResponder.swift][responses]
- The DSL host owns defer policy and disables any competing application-level auto-defer configuration. Do not implement snapshot-then-reply/edit logic. Delayed automatic defer is a separately gated future enhancement. [InteractionHTTPApplication.swift][httpdefer]
- Autocomplete, modal-opening, component-update and message-response handlers have separate response constraints. Do not defer a response kind that Discord requires immediately. Initial acknowledgement and token expiry remain receipt-relative and bounded by the existing responder. [InteractionResponder.swift][responses], [official response rules](https://docs.discord.com/developers/interactions/receiving-and-responding)
- Message interpolation escapes ordinary text, emits typed mentions explicitly and builds matching allowed-mentions data. Default mention parsing is empty; raw text/mention policy overrides are explicit. Ordinary literal initializers cannot throw, so length/layout validation occurs at response compilation, before transmission.
- Gateway convenience services delegate through ServiceContext.execute, including cache invalidation and indeterminate-mutation behavior. A narrow generic service-provider protocol can hide the concrete clock from common handler signatures; its adapter retains the real clock and accepts relative timeouts rather than mixing Instant types. [ServiceContext.swift][services]

## 3. File Changes

No production edits or deletions are part of this planning request. The following is the proposed implementation inventory.

### Modify existing files

- [Package.swift][manifest]: add runtime products and matching test targets only when each has a real implementation; preserve concurrency settings and existing independent graphs.
- [release-policy.json][policy]: register exact new target dependencies and independent consumers.
- [ci.yml][ci]: test runtime/macro packages and compile fixtures, build new consumers, collect scoped API and performance artifacts.
- [platform-qualification.yml][platformci]: add new offline consumers only to applicable platform jobs; report skipped gates accurately.
- [ToolCommand.swift][toolcommand] and [DocumentationAudit.swift][docaudit]: include the separate macro package in explicit callable documentation auditing without adding tooling to products.
- [curate_docc.py][curatedocs], [build_docc.py][builddocs], [documentation_examples.py][docexamples]: include new public modules, macro authoring docs and independently compiled examples.
- [test_curate_docc.py][docctests]: cover new catalog/tutorial discovery behavior.
- [Architecture.md][architecture], [Setup.md][setup], [Migration.md][migration], [ReleaseTooling.md][releasetools], [CI.md][cidocs], [README.md][readme] and [AGENTS.md][agents]: document adoption, dependencies, command migration and validation.
- [README.md][releasereadme] and [maintenance.json][maintenance]: point current validation to the new candidate and record current source review without rewriting historical release claims.
- [history.json][history]: append an authoring-layer entry; do not relabel unchanged endpoint/event parity as newly implemented.
- [discordkit-full-platform-roadmap.plan.md][roadmap]: append Phase 15 and milestone dependencies after approval.
- No existing networking, responder, codec, cryptographic or cache implementation is expected to change. A discovered required behavioral fix receives its own regression test and explicit scope amendment.

### Create planned files

All entries below are new files, with exact future locations relative to the verified [DiscordKit][root]. They are intentionally not links to files that already exist. Supporting source is grouped by responsibility; generated reference pages are added in 15L from the actual symbol graph.

~~~text
Sources/DiscordDSL/BotDefinition.swift
Sources/DiscordDSL/BotBuilder.swift
Sources/DiscordDSL/DefinitionPlan.swift
Sources/DiscordDSL/MessageContent.swift
Sources/DiscordDSL/PolicyComposition.swift
Sources/DiscordDSL/DiscordDSL.docc/DiscordDSL.md

Sources/DiscordCommandDSL/CommandArguments.swift
Sources/DiscordCommandDSL/ArgumentValues.swift
Sources/DiscordCommandDSL/CommandHandlers.swift
Sources/DiscordCommandDSL/CommandCompilation.swift
Sources/DiscordCommandDSL/CommandContext.swift
Sources/DiscordCommandDSL/CommandResponses.swift
Sources/DiscordCommandDSL/MessageBuilder.swift
Sources/DiscordCommandDSL/ComponentBuilder.swift
Sources/DiscordCommandDSL/CommandFamilies.swift
Sources/DiscordCommandDSL/CommandPolicies.swift
Sources/DiscordCommandDSL/CommandApplication.swift
Sources/DiscordCommandDSL/DiscordCommandDSL.docc/DiscordCommandDSL.md

Sources/DiscordBotDSL/GatewayEventHandler.swift
Sources/DiscordBotDSL/EventCompilation.swift
Sources/DiscordBotDSL/GatewayInteractionAdapter.swift
Sources/DiscordBotDSL/BotApplication.swift
Sources/DiscordBotDSL/BotRuntime.swift
Sources/DiscordBotDSL/BotServiceAdapter.swift
Sources/DiscordBotDSL/DiscordBotDSL.docc/DiscordBotDSL.md

Tests/DiscordDSLTests/DefinitionTests.swift
Tests/DiscordDSLTests/ContentPolicyTests.swift
Tests/DiscordCommandDSLTests/ArgumentTests.swift
Tests/DiscordCommandDSLTests/CompilationTests.swift
Tests/DiscordCommandDSLTests/ResponseTests.swift
Tests/DiscordCommandDSLTests/FamilyPolicyTests.swift
Tests/DiscordBotDSLTests/EventTests.swift
Tests/DiscordBotDSLTests/LifecycleTests.swift
Tests/DiscordBotDSLTests/ExtensionTests.swift
Tests/Fixtures/DSLCompile/fixtures.json
Tests/Fixtures/DSLCompile/Positive.swift
Tests/Fixtures/DSLCompile/Negative.swift

Packages/DiscordDSLMacros/Package.swift
Packages/DiscordDSLMacros/Sources/DiscordDSLMacros/Declarations.swift
Packages/DiscordDSLMacros/Sources/DiscordDSLMacros/DiscordDSLMacros.docc/DiscordDSLMacros.md
Packages/DiscordDSLMacros/Sources/DiscordDSLMacroPlugin/Plugin.swift
Packages/DiscordDSLMacros/Sources/DiscordDSLMacroPlugin/ArgumentMacros.swift
Packages/DiscordDSLMacros/Sources/DiscordDSLMacroPlugin/CommandMacros.swift
Packages/DiscordDSLMacros/Tests/DiscordDSLMacrosTests/ExpansionTests.swift
Packages/DiscordDSLMacros/Tests/DiscordDSLMacrosTests/ExecutionParityTests.swift

Examples/DSLCommands/Package.swift
Examples/DSLCommands/Sources/DSLCommands/DSLCommands.swift
Examples/DSLCommands/Tests/DSLCommandsTests/DSLCommandsTests.swift
Examples/DSLCommands/README.md
Examples/DSLBot/Package.swift
Examples/DSLBot/Sources/DSLBot/DSLBot.swift
Examples/DSLBot/Tests/DSLBotTests/DSLBotTests.swift
Examples/DSLBot/README.md

Tools/ci/dsl_compile_fixtures.py
Tools/ci/test_dsl_compile_fixtures.py
Tools/DiscordDSLBenchmarks/Package.swift
Tools/DiscordDSLBenchmarks/Sources/DiscordDSLBenchmarks/main.swift
Tools/DiscordDSLBenchmarks/README.md

Docs/DSL.md
Docs/DSLArchitecture.md
Docs/DSLImplementationRoadmap.md
Docs/Release/phase15-report.json
Docs/Release/api-baseline-0.15.0.json
Docs/Parity/changes/phase15-dsl.md
~~~

Responsibilities map directly to the steps below. Any package resolution lockfiles are generated and reviewed with their owning package, according to existing repository conventions. No deletions are planned.

## 4. Implementation Steps

### Task 15A — Shared declarations and deterministic compilation

**Depends on:** existing Phase 14 foundations.

Create BotDefinition.swift, BotBuilder.swift and DefinitionPlan.swift at the locations above. Define BotModule with associated Body, public extension/contribution protocols, source locations, stable explicit module IDs, bounded structural diagnostics and deterministic declaration order. Provide primitive and composite implementations, conditional/array/empty builder support and one public raw contribution escape hatch.

Add the shared target/tests to [Package.swift][manifest] and the reviewed graph to [release-policy.json][policy]. DefinitionTests.swift must verify count/depth/text limits, duplicate IDs, unsupported capabilities, builder order and zero invocation of injected work counters. Contributions must be useful and testable before another public target is introduced.

**Exit:** an explicit Swift module compiles to a reproducible validated description with no runtime side effects.

### Task 15B — Typed arguments and command lowering

**Depends on:** 15A.

Create CommandArguments.swift, ArgumentValues.swift, CommandHandlers.swift and CommandCompilation.swift. An argument schema and decoder are one protocol contract; built-in codecs cover String, Bool, supported exact integers/numbers, typed entity references, optional values and explicit choice enums. User-defined ArgumentValue types map to an existing Discord option kind.

Compile a handwritten slash handler into one registration definition and exact route using the existing [CommandDefinition.swift][definitions] and [CommandRouter.swift][router]. Add explicit typed defaults, validation errors with command/option/source locations, unknown-name policy and incomplete autocomplete decoding reserved for its later handler family.

ArgumentTests.swift and CompilationTests.swift compare serialized registration and invocation behavior against direct low-level construction. Include missing/null/duplicate/wrong-kind values, numeric boundaries, maximum snowflakes, unresolved entities and failing custom codecs.

**Exit:** one handwritten command has a typed invocation and one source of registration/route metadata, with no reflection.

### Task 15C — First-class macro authoring

**Depends on:** 15B.

Create the separate macro package and declarations/plugin/argument/command implementations listed above. CommandArguments generates schema, decoding and useful generated callable comments from its own annotated properties. SlashCommand generates metadata and declaration plumbing through the Arguments protocol. Keep handler behavior in execute methods.

ExpansionTests.swift checks generated declarations and diagnostics for unsupported property forms, invalid literal metadata, duplicate options and incompatible defaults. ExecutionParityTests.swift compiles real generated code and compares it with 15B's explicit implementation. Cross-module argument codecs must work without the macro resolving their implementation.

Add positive/negative compile fixtures and the runner. Start with required string, optional integer, enum choice and external custom codec; a successful text expansion snapshot alone does not pass the milestone.

**Exit:** the preferred macro/protocol syntax compiles and produces the same definitions and decoded values as explicit Swift.

### Task 15D — Response ownership and HTTP command application

**Depends on:** 15C.

Create CommandContext.swift, CommandResponses.swift and CommandApplication.swift. Implement separate typed immediate, typed deferred and manual handler contracts. Decode and preflight cheap policies before user work; immediate handlers send their returned response once, deferred handlers acknowledge before user execution and complete with editOriginal, and manual handlers own raw responder access.

Compose the existing signed [InteractionHTTPApplication.swift][httpdefer] and [CommandRouter.swift][router], preserving independent initial-response admission. Validate that application-level auto-defer is not also configured for DSL-managed dispatch. Add explicit synchronization through [CommandReconciler.swift][reconciler].

Create DSLCommands as an independent consumer, with an offline test mode and opt-in listener ownership. ResponseTests.swift exercises HTTP and trusted Gateway-normalized contexts using deterministic sinks/clocks, including expiry, cancellation, transport uncertainty, handler failure, forbidden response kinds and exactly one acknowledgement.

**Exit:** macro-authored /ping works against a synthetic signed HTTP exchange; construction and ordinary run perform zero command-registration requests.

### Task 15E — Message/component builders and compiler literal protocols

**Depends on:** 15D.

Create MessageContent.swift, MessageBuilder.swift and ComponentBuilder.swift. Add typed text, embeds and the component layouts already supported by Models. Preserve explicit field omission/null and lower to existing validated payloads; layout builders reject illegal combinations before transmission.

Implement literal/interpolation conformance with typed user/channel/role mentions, escaped plain text, explicit raw segments and allowed-mentions synthesis. Keep content length, mentions, component rows, embeds and aggregate payload limits in existing validation paths. Manual raw model adoption remains available.

ContentPolicyTests.swift and ResponseTests.swift verify escaping, mention opt-in, Unicode boundaries, empty output, invalid layout combinations and exact lowered payload parity.

**Exit:** a builder-authored response serializes identically to its direct model equivalent, and interpolated untrusted text cannot enable unintended mention parsing.

### Task 15F — Complete command-family authoring and registration

**Depends on:** 15E.

Create CommandFamilies.swift and extend CommandMacros.swift. Implement protocol families for slash subcommands/groups, user/message context menus, autocomplete providers, exact-ID component handlers and modal submissions. Keep typed targets, partial autocomplete arguments and legal response kinds separate.

Registration uses the compiled catalog with explicit application/scope/managed-name policy. Preserve unmanaged commands and partial synchronization outcomes through [CommandReconciler.swift][reconciler]. Expose existing localization, contexts, permissions and advanced fields without automatically claiming previously missing upstream fields.

FamilyPolicyTests.swift covers namespace collisions, group-depth boundaries, focused autocomplete options, response incompatibility, component/modal ID separation, malformed submissions and sync no-op/change/partial-failure behavior.

**Exit:** each currently supported command family has an executable protocol-based example; illegal family/response combinations fail at compile time where representable and otherwise before user execution.

### Task 15G — Policies, middleware and custom operators

**Depends on:** 15F.

Create PolicyComposition.swift and CommandPolicies.swift. Implement named policy composition and >>> middleware composition with explicit precedence/associativity. Document execution as outer-left entry, inner-right entry, handler, inner-right exit, outer-left exit. Short-circuit predicates evaluate left-to-right and never execute the skipped branch.

Provide guild/context checks, injected application authorization, bounded concurrency and explicit error mapping. Registration default permissions, cached permission observations and current authorization remain different concepts. Rate coordination continues through existing HTTP authorities; no DSL-local replacement quotas or blind retry middleware are added. [ServiceContext.swift][services]

Tests use observable counters and deterministic barriers for operator order, short circuiting, rejection, cancellation, cleanup and partial side effects. Stateful policy stores require injected finite count/TTL bounds; distributed authority remains injected.

**Exit:** named and operator-composed policies have identical observable behavior, with bounded state and documented rejection responses.

### Task 15H — Typed Gateway event modules

**Depends on:** 15A and 15G.

Create GatewayEventHandler.swift and EventCompilation.swift in the separate bot product. Protocol handlers declare their associated event selector and required intents. Selectors use existing decodeDispatch, including unknown/raw fallback, and do not add model-parity claims. [GatewayProtocol.swift][dispatchdecode]

Flatten modules into one default subscription and dispatcher. Execute matching handlers in declaration order for each event, preserving existing per-complete-shard serialization. Independent event groups are explicit, bounded subscriptions with no cross-group ordering guarantee. [EventHandlers.swift][dispatcher]

EventTests.swift covers same-shard order, cross-shard progress, missing intents, duplicate registrations, unknown events, malformed known events, overflow, callback failure and finite independent-group admission. Privileged intents are never enabled implicitly.

**Exit:** two modules receive typed synthetic events through one default subscription while Gateway control work remains independent.

### Task 15I — BotApplication, interaction bridge and supervised lifetime

**Depends on:** 15H.

Create BotApplication.swift, BotRuntime.swift, BotServiceAdapter.swift and GatewayInteractionAdapter.swift. Provide the @main-compatible application protocol and explicit host/dependency construction. Reuse shared credential, startup, lease, event, handler, REST and aggregate resource authorities rather than creating one set per module.

The trusted Gateway interaction adapter builds the same normalized context/response owner used by command execution; callbacks still use HTTP. It does not bypass provenance or permit arbitrary public calls to mark untrusted input authenticated.

Subscribe before client.run; supervise one client and the declared pipelines; on all exits cancel subscriptions, shut down the client, join children and preserve cleanup failures. Keep raw shard consumption exclusive to the existing client. [DiscordClient.swift][ingestion], [DiscordClient.swift][shutdown]

Create DSLBot, build it without credentials and exercise it offline. LifecycleTests.swift covers cancellation before/during startup, stop-before-run, repeated shutdown, canceled cleanup waiters, handler-triggered stop, child failure, failed lease release and zero final owned counters.

**Exit:** an application composes commands and events through protocol modules and uses the existing single-use client lifetime without leaked work.

### Task 15J — External extensibility and modular adoption

**Depends on:** 15I.

Use ExtensionTests.swift and the separate DSLBot/DSLCommands consumer packages to prove external modules, custom argument codecs, actor dependencies, custom policy types and raw low-level definitions can be supplied without editing a central switch or widening private access. Add nested module namespaces and typed dependency validation using explicit initializer injection.

A command-only module must compile without Gateway/Client/Cache; a macro-free consumer must compile without the macro package. Unsupported capabilities fail during plan validation before I/O. Duplicate module installation is an explicit error unless the caller provides distinct stable instances.

Document how optional voice, Social or OAuth services can be injected into user modules through their existing independent products. Do not add automatic voice joining, scheduler runtimes, plugin discovery, persistence or new protocol implementations to complete this milestone.

**Exit:** an independently compiled extension supplies reusable behavior and custom decoding with no changes to DSL implementation source.

### Task 15K — Compile-time and runtime qualification

**Depends on:** 15J; fixture validation begins in 15C.

Create the independent DiscordDSLBenchmarks package. Compare direct and DSL implementations using identical offline workloads: 10/100/1,000 declared handlers, finite payloads, bounded offered concurrency and 1,000,000 fixed-working-set invocations. Measure plan compilation, invocation p50/p95/p99, throughput, allocation/accounted state and actual RSS. Measure clean and incremental consumer builds with and without macros on the same toolchain.

Record the first measured results before setting numerical regression tolerances. Hard functional gates apply immediately: no per-invocation schema reconstruction, no implicit REST hydration/registration, all configured bounds respected and all owned counters zero after cleanup. Benchmark artifacts state hardware, compiler, workload and measurement limitations.

Run the existing consumer/cache/event validation required by [AGENTS.md][agents], including the documented fixed-working-set 30-minute local soak. Add a DSL handler workload so the existing cache/broadcast soak is not misrepresented as handler execution evidence. [README.md][loadreadme]

**Exit:** reproducible direct-versus-DSL measurements and finite compile/runtime regression budgets exist; local evidence makes no fleet-capacity claim.

### Task 15L — Documentation, migration and release candidate

**Depends on:** 15K.

Create the DSL design/roadmap/adoption documents and public DocC catalogs. Explain the conceptual model, minimal protocol/macro command, module reuse, async actor dependencies, policies/operators, HTTP/Gateway hosts, response modes, testing, deployment ownership and escape hatches. All examples must compile independently.

Extend the separate documentation audit to macro package sources and test generated callable documentation in expansion fixtures. Curate generated type reference pages and tutorial listings from compiler output through the existing [curate_docc.py][curatedocs], [documentation_examples.py][docexamples] and [build_docc.py][builddocs].

Compare the current 0.14.0 API baseline with the proposed 0.15.0 candidate, then capture the separately named 0.15.0 baseline after review. Append authoring-layer history and a new release evidence report; preserve old parity history and historical certification records. Update current CI/report selection rather than treating old hash-bound evidence as evidence for new source. [ReleaseTooling.md][releasetools]

**Exit:** current API, graph, documentation, parity, examples and evidence validators pass, with unrun platform/live gates explicitly excluded. No publication or tag is required by this roadmap.

## 5. Acceptance Criteria

1. A macro-authored slash command defines name, description, options and handler once; its compiled definition and route agree, verified against direct construction. [CommandDefinition.swift][definitions], [CommandRouter.swift][router]
2. Protocol/module bodies support nested modules, conditionals, arrays and loops with deterministic order, and reject each configured structural bound at its first exceeded value.
3. External argument codecs and modules compile in an independent consumer. Macro-free equivalents select no SwiftSyntax package.
4. Every new/modified explicit callable, including tests and generated callable templates, has comprehensive documentation; the source audit reports zero missing comments for the new scope. [DocumentationAudit.swift][docaudit]
5. Generated and handwritten argument models agree for normal, absent, null, wrong-kind, duplicate, unresolved and numeric-boundary fixtures. Invalid arguments never invoke the user handler. [Interaction.swift][arguments]
6. Immediate handlers issue exactly one initial response; explicitly deferred handlers issue one defer followed by one original edit; manual mode permits the existing explicit lifecycle. Expired/uncertain states do not trigger fallback replay. [InteractionResponder.swift][responses]
7. Text/mention interpolation produces the asserted allowed-mentions payload; ordinary untrusted text cannot opt into mention parsing.
8. Command-only consumers exclude Gateway, Client and Cache, and existing REST/voice/Activity independent graphs remain unchanged. [release-policy.json][policy]
9. Command registration is explicit, preserves unmanaged registrations and reports partial/indeterminate outcomes. Constructing, compiling and running a bot causes zero registration calls. [CommandReconciler.swift][reconciler]
10. Default event delivery uses one subscription regardless of module count, preserves same-shard order and propagates overflow/callback failures. [EventHandlers.swift][dispatcher]
11. Missing required intents or host capabilities fail before client discovery or socket creation. Privileged intents are never silently enabled.
12. Cancellation, stop and failure paths finish with zero DSL-owned subscriptions, admitted handlers, waiters and child tasks; underlying cleanup failures remain observable. [DiscordClient.swift][shutdown]
13. >>> and its named equivalent have identical entry/exit behavior; &&/|| short circuit tests prove the skipped branch executes zero times.
14. Positive compile fixtures pass and negative fixtures fail with stable expected diagnostic identifiers or semantic substrings, not brittle whole compiler messages.
15. Repeated invocations reuse compiled schemas/routes; fixed-working-set load never exceeds configured accounting limits and records actual RSS separately.
16. All required checks below pass or have a specific unavailable-infrastructure record; hosted workflow configuration alone is never recorded as a passed platform run. [CI.md][cidocs]

## 6. Verification Steps

These are implementation-time checks; none are claimed to have run during planning. Commands below are executed from the repository root.

### Each source/manifest milestone

~~~sh
swift build
swift test
~~~

Run focused suites while developing, then the full root suite before accepting each source milestone. Tests use Swift Testing, injected clocks, deterministic transports and synchronization barriers, following [AGENTS.md][agents].

### Macros, independent consumers and compiler diagnostics

~~~sh
swift test --package-path Packages/DiscordDSLMacros
python3 Tools/ci/dsl_compile_fixtures.py
python3 -m unittest discover -s Tools/ci -p 'test_dsl_compile_fixtures.py'
swift build --package-path Examples/DSLCommands --explicit-target-dependency-import-check error
swift test --package-path Examples/DSLCommands
swift build --package-path Examples/DSLBot --explicit-target-dependency-import-check error
swift test --package-path Examples/DSLBot
~~~

The fixture runner must compile genuine external consumers, including macro expansion and strict Sendable checking. Credential-bearing modes are never started in ordinary validation.

### Existing consumers and release/tooling regression checks

~~~sh
swift build --package-path Examples/HTTPApp
swift build --package-path Examples/CommandsApp
swift build --package-path Examples/GatewayBot
swift test --package-path Tools/DiscordKitTools
swift run --package-path Tools/DiscordKitTools DiscordKitTools documentation audit --repository .
swift run --package-path Tools/DiscordKitTools DiscordKitTools inventory validate --repository .
swift run --package-path Tools/DiscordKitTools DiscordKitTools generate --check --repository .
swift run --package-path Tools/DiscordKitTools DiscordKitTools parity check --repository .
python3 -m unittest discover -s Tools/DiscordKitTools/scripts -p 'test_*.py'
python3 Tools/DiscordKitTools/scripts/release_check.py graph --repository .
python3 Tools/DiscordKitTools/scripts/release_check.py report --repository . --report Docs/Release/phase15-report.json
python3 Tools/DiscordKitTools/scripts/release_check.py maintenance --repository . --record Docs/Release/maintenance.json
~~~

Update the documentation-audit command to include the separate macro package and test that coverage. Keep the reviewed generator nonwriting: this DSL does not change reviewed wire definitions. Existing nine consumer builds and their relevant offline tests remain in CI. [ci.yml][ci]

### Documentation and API review

~~~sh
swift package dump-symbol-graph --minimum-access-level public
python3 Tools/ci/curate_docc.py --check
python3 Tools/ci/documentation_examples.py
python3 Tools/ci/build_docc.py
python3 Tools/DiscordKitTools/scripts/api_baseline.py snapshot --repository . --symbolgraphs .build/out/symbolgraph --version 0.15.0 --output /tmp/discordkit-dsl-api.json
python3 Tools/DiscordKitTools/scripts/api_baseline.py check --baseline Docs/Release/api-baseline.json --candidate /tmp/discordkit-dsl-api.json --version 0.15.0
~~~

Use the actual emitted symbolgraph directory. Extend separate-package macro documentation/API collection as necessary and record its scope explicitly. Review additive public APIs and any inferred compatibility changes before capturing the new baseline. [ReleaseTooling.md][releasetools]

### Runtime/load checks

~~~sh
swift test --package-path Tools/DiscordKitLoadTests
python3 -m unittest discover -s Tools/DiscordKitLoadTests/scripts -p 'test_*.py'
swift run -c release --package-path Tools/DiscordKitLoadTests DiscordKitLoadTests --scenario soak --profile accounts-1000000 --burst --duration-seconds 1800
swift run -c release --package-path Tools/DiscordDSLBenchmarks
~~~

The new benchmark's default run is a fixed, documented offline matrix and must include direct/DSL comparisons; its command is implemented in 15K. Existing soak evidence and the new handler evidence remain separate. Run the meaningful existing local Gateway profiles when runtime composition changes. [README.md][loadreadme]

Manually review generated macro diagnostics, a tiny command example, a multi-module bot, explicit sync output and lifecycle documentation. Final review includes the complete diff and whitespace/status audit. All live Discord registration/messages, device behavior and cross-platform qualification remain separately authorized/run gates.

## 7. Risks & Mitigations

- **Macros accidentally become a second schema implementation.** Generate calls to the same public argument/schema protocols and existing model validators; compare generated and explicit implementations in execution tests. [CommandDefinition.swift][definitions], [Interaction.swift][arguments]
- **Compiler cost and poor diagnostics from deeply nested generic builders.** Flatten structural collections at compilation, bound definition depth, avoid unnecessary overload families and measure clean/incremental representative consumers in 15K.
- **Duplicate response ownership or defer races.** Separate typed/manual contexts, require explicit early defer for deferred handlers, and reject competing application-level auto-defer. [InteractionResponder.swift][responses], [InteractionHTTPApplication.swift][httpdefer]
- **Macro package cycles/toolchain coupling.** Keep the plugin downstream of runtime products, require explicit authoring imports, pin a compatible SwiftSyntax release and compile-test supported toolchains. [Package.swift][syntax]
- **Module composition multiplies queues, tasks or quotas.** One default event pipeline; explicit finite independent groups; caller-shared existing authorities and no module-created network coordinators. [EventHandlers.swift][dispatcher], [DiscordClient.swift][construction]
- **Gateway wrappers lose cleanup or cache semantics.** Delegate lifetime to DiscordClient, service operations to ServiceContext and raw dispatch decoding to the existing model path. [DiscordClient.swift][shutdown], [ServiceContext.swift][services], [GatewayProtocol.swift][dispatchdecode]
- **DSL convenience obscures incomplete models or authorization.** Preserve raw/partial values, expose unresolved references, never hydrate implicitly and require application authorization where needed. Existing parity and qualification exclusions remain visible. [Interaction.swift][arguments], [Architecture.md][architecture]
- **New source invalidates historical release evidence.** Create new candidate evidence, preserve historical baselines/history and select the current report in CI. Do not rewrite old evidence into new qualification. [ReleaseTooling.md][releasetools]

The first useful delivery is 15A–15D: reusable protocol modules and macro-authored typed commands running through independent HTTP composition. 15E–15G complete command authoring; 15H–15J add the full supervised bot experience; 15K–15L establish measured limits and release readiness.

[root]: air-folder://l5n6o8gm5adj032jrr52/Users/carsonrau/Developer/DiscordKit?type=folder&root=%252F
[manifest]: air-file://l5n6o8gm5adj032jrr52/Users/carsonrau/Developer/DiscordKit/Package.swift?type=file&root=%252F
[settings]: air-file://l5n6o8gm5adj032jrr52/Users/carsonrau/Developer/DiscordKit/Package.swift?type=file&linesData=%7B%22range%22%3A%7B%22first%22%3A0%2C%22second%22%3A185%7D%2C%22lines%22%3A%7B%22first%22%3A0%2C%22second%22%3A7%7D%7D&root=%252F
[dependencies]: air-file://l5n6o8gm5adj032jrr52/Users/carsonrau/Developer/DiscordKit/Package.swift?type=file&linesData=%7B%22range%22%3A%7B%22first%22%3A3106%2C%22second%22%3A5398%7D%2C%22lines%22%3A%7B%22first%22%3A59%2C%22second%22%3A73%7D%7D&root=%252F
[definitions]: air-file://l5n6o8gm5adj032jrr52/Users/carsonrau/Developer/DiscordKit/Sources/DiscordCommands/CommandDefinition.swift?type=file&linesData=%7B%22range%22%3A%7B%22first%22%3A2205%2C%22second%22%3A3052%7D%2C%22lines%22%3A%7B%22first%22%3A28%2C%22second%22%3A38%7D%7D&root=%252F
[router]: air-file://l5n6o8gm5adj032jrr52/Users/carsonrau/Developer/DiscordKit/Sources/DiscordCommands/CommandRouter.swift?type=file&linesData=%7B%22range%22%3A%7B%22first%22%3A9120%2C%22second%22%3A12522%7D%2C%22lines%22%3A%7B%22first%22%3A134%2C%22second%22%3A180%7D%7D&root=%252F
[reconciler]: air-file://l5n6o8gm5adj032jrr52/Users/carsonrau/Developer/DiscordKit/Sources/DiscordCommands/CommandReconciler.swift?type=file&linesData=%7B%22range%22%3A%7B%22first%22%3A3004%2C%22second%22%3A4272%7D%2C%22lines%22%3A%7B%22first%22%3A48%2C%22second%22%3A64%7D%7D&root=%252F
[arguments]: air-file://l5n6o8gm5adj032jrr52/Users/carsonrau/Developer/DiscordKit/Sources/DiscordModels/Interaction.swift?type=file&linesData=%7B%22range%22%3A%7B%22first%22%3A4323%2C%22second%22%3A5141%7D%2C%22lines%22%3A%7B%22first%22%3A71%2C%22second%22%3A84%7D%7D&root=%252F
[responses]: air-file://l5n6o8gm5adj032jrr52/Users/carsonrau/Developer/DiscordKit/Sources/DiscordInteractions/InteractionResponder.swift?type=file&linesData=%7B%22range%22%3A%7B%22first%22%3A8538%2C%22second%22%3A10994%7D%2C%22lines%22%3A%7B%22first%22%3A149%2C%22second%22%3A179%7D%7D&root=%252F
[httpdefer]: air-file://l5n6o8gm5adj032jrr52/Users/carsonrau/Developer/DiscordKit/Sources/DiscordInteractions/InteractionHTTPApplication.swift?type=file&linesData=%7B%22range%22%3A%7B%22first%22%3A4885%2C%22second%22%3A5857%7D%2C%22lines%22%3A%7B%22first%22%3A68%2C%22second%22%3A80%7D%7D&root=%252F
[construction]: air-file://l5n6o8gm5adj032jrr52/Users/carsonrau/Developer/DiscordKit/Sources/DiscordClient/DiscordClient.swift?type=file&linesData=%7B%22range%22%3A%7B%22first%22%3A520%2C%22second%22%3A1105%7D%2C%22lines%22%3A%7B%22first%22%3A16%2C%22second%22%3A23%7D%7D&root=%252F
[shutdown]: air-file://l5n6o8gm5adj032jrr52/Users/carsonrau/Developer/DiscordKit/Sources/DiscordClient/DiscordClient.swift?type=file&linesData=%7B%22range%22%3A%7B%22first%22%3A6812%2C%22second%22%3A7846%7D%2C%22lines%22%3A%7B%22first%22%3A123%2C%22second%22%3A143%7D%7D&root=%252F
[ingestion]: air-file://l5n6o8gm5adj032jrr52/Users/carsonrau/Developer/DiscordKit/Sources/DiscordClient/DiscordClient.swift?type=file&linesData=%7B%22range%22%3A%7B%22first%22%3A12684%2C%22second%22%3A13423%7D%2C%22lines%22%3A%7B%22first%22%3A228%2C%22second%22%3A239%7D%7D&root=%252F
[dispatcher]: air-file://l5n6o8gm5adj032jrr52/Users/carsonrau/Developer/DiscordKit/Sources/DiscordGateway/EventHandlers.swift?type=file&linesData=%7B%22range%22%3A%7B%22first%22%3A4862%2C%22second%22%3A5781%7D%2C%22lines%22%3A%7B%22first%22%3A97%2C%22second%22%3A109%7D%7D&root=%252F
[services]: air-file://l5n6o8gm5adj032jrr52/Users/carsonrau/Developer/DiscordKit/Sources/DiscordClient/ServiceContext.swift?type=file&linesData=%7B%22range%22%3A%7B%22first%22%3A851%2C%22second%22%3A2230%7D%2C%22lines%22%3A%7B%22first%22%3A17%2C%22second%22%3A36%7D%7D&root=%252F
[dispatchdecode]: air-file://l5n6o8gm5adj032jrr52/Users/carsonrau/Developer/DiscordKit/Sources/DiscordGateway/GatewayProtocol.swift?type=file&linesData=%7B%22range%22%3A%7B%22first%22%3A7388%2C%22second%22%3A8152%7D%2C%22lines%22%3A%7B%22first%22%3A146%2C%22second%22%3A154%7D%7D&root=%252F
[syntax]: air-file://l5n6o8gm5adj032jrr52/Users/carsonrau/Developer/DiscordKit/Tools/DiscordKitTools/Package.swift?type=file&linesData=%7B%22range%22%3A%7B%22first%22%3A223%2C%22second%22%3A421%7D%2C%22lines%22%3A%7B%22first%22%3A8%2C%22second%22%3A11%7D%7D&root=%252F
[architecture]: air-file://l5n6o8gm5adj032jrr52/Users/carsonrau/Developer/DiscordKit/Docs/Architecture.md?type=file&root=%252F
[policy]: air-file://l5n6o8gm5adj032jrr52/Users/carsonrau/Developer/DiscordKit/Tools/DiscordKitTools/release-policy.json?type=file&root=%252F
[ci]: air-file://l5n6o8gm5adj032jrr52/Users/carsonrau/Developer/DiscordKit/.github/workflows/ci.yml?type=file&root=%252F
[platformci]: air-file://l5n6o8gm5adj032jrr52/Users/carsonrau/Developer/DiscordKit/.github/workflows/platform-qualification.yml?type=file&root=%252F
[toolcommand]: air-file://l5n6o8gm5adj032jrr52/Users/carsonrau/Developer/DiscordKit/Tools/DiscordKitTools/Sources/DiscordKitTools/ToolCommand.swift?type=file&root=%252F
[docaudit]: air-file://l5n6o8gm5adj032jrr52/Users/carsonrau/Developer/DiscordKit/Tools/DiscordKitTools/Sources/DiscordKitTools/DocumentationAudit.swift?type=file&root=%252F
[curatedocs]: air-file://l5n6o8gm5adj032jrr52/Users/carsonrau/Developer/DiscordKit/Tools/ci/curate_docc.py?type=file&root=%252F
[builddocs]: air-file://l5n6o8gm5adj032jrr52/Users/carsonrau/Developer/DiscordKit/Tools/ci/build_docc.py?type=file&root=%252F
[docexamples]: air-file://l5n6o8gm5adj032jrr52/Users/carsonrau/Developer/DiscordKit/Tools/ci/documentation_examples.py?type=file&root=%252F
[docctests]: air-file://l5n6o8gm5adj032jrr52/Users/carsonrau/Developer/DiscordKit/Tools/ci/test_curate_docc.py?type=file&root=%252F
[setup]: air-file://l5n6o8gm5adj032jrr52/Users/carsonrau/Developer/DiscordKit/Docs/Setup.md?type=file&root=%252F
[migration]: air-file://l5n6o8gm5adj032jrr52/Users/carsonrau/Developer/DiscordKit/Docs/Migration.md?type=file&root=%252F
[releasetools]: air-file://l5n6o8gm5adj032jrr52/Users/carsonrau/Developer/DiscordKit/Docs/ReleaseTooling.md?type=file&root=%252F
[cidocs]: air-file://l5n6o8gm5adj032jrr52/Users/carsonrau/Developer/DiscordKit/Docs/CI.md?type=file&root=%252F
[readme]: air-file://l5n6o8gm5adj032jrr52/Users/carsonrau/Developer/DiscordKit/README.md?type=file&root=%252F
[agents]: air-file://l5n6o8gm5adj032jrr52/Users/carsonrau/Developer/DiscordKit/AGENTS.md?type=file&root=%252F
[releasereadme]: air-file://l5n6o8gm5adj032jrr52/Users/carsonrau/Developer/DiscordKit/Docs/Release/README.md?type=file&root=%252F
[maintenance]: air-file://l5n6o8gm5adj032jrr52/Users/carsonrau/Developer/DiscordKit/Docs/Release/maintenance.json?type=file&root=%252F
[history]: air-file://l5n6o8gm5adj032jrr52/Users/carsonrau/Developer/DiscordKit/Docs/Parity/history.json?type=file&root=%252F
[roadmap]: air-file://l5n6o8gm5adj032jrr52/Users/carsonrau/Developer/DiscordKit/.air/plans/discordkit-full-platform-roadmap.plan.md?type=file&root=%252F
[loadreadme]: air-file://l5n6o8gm5adj032jrr52/Users/carsonrau/Developer/DiscordKit/Tools/DiscordKitLoadTests/README.md?type=file&root=%252F
