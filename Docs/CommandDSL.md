# Typed command authoring

Part 15B adds the independently adopted `DiscordCommandDSL` product over
DSL/Core/Models/Commands/Interactions, with HTTP/Transport for application composition.
A handwritten argument schema drives both
validated registration options and strict invocation decoding. Finite module
compilation produces existing `CommandDefinition` and `CommandRoute` values.
Construction and compilation start no tasks, I/O, registration or handler execution.

The implemented family is root slash commands with leaf options. Part 15C adds
optional [macro authoring](MacroDSL.md); Part 15D adds
[immediate/deferred/manual response ownership and signed HTTP applications](CommandResponses.md).
Subcommands/groups, autocomplete, other command families,
message/component builders, policies and Gateway hosts remain later
[implementation milestones](DSLImplementationRoadmap.md). Existing low-level APIs
remain independently usable for their broader implemented surfaces.

## Declare arguments once

A schema captures typed descriptors in registration order and a synchronous
constructor for one fresh argument value. This example declares a required string
and an optional integer, using ordinary Swift and no mutable property wrappers:

```swift
import DiscordCommandDSL

struct GreetingArguments: CommandArguments {
    let name: String
    let repetitions: Int?

    static var schema: CommandArgumentSchema<Self> {
        get throws {
            let name = try ArgumentOption<String>(
                name: "name", description: "Name to greet", minLength: 1, maxLength: 80)
            let repetitions = try ArgumentOption<Int?>(
                name: "repetitions", description: "Optional repetition count")
            return try CommandArgumentSchema(options: [name.erased, repetitions.erased]) { decoder in
                Self(name: try decoder.value(for: name),
                     repetitions: try decoder.value(for: repetitions))
            }
        }
    }
}
```

Each descriptor exposes its erased schema entry without erasing the type used by
`decoder.value(for:)`. The schema validates option identity, supported leaf kinds,
required-before-optional ordering, choices and applicable constraints through the
existing API v10 registration models. At most 25 descriptors are admitted. The
constructor runs only after the complete submitted input has passed validation.
Each present or omitted optional codec runs once; validated defaults reuse their
retained value. Typed lookup reuses the invocation's cached result. A descriptor
from another schema cannot silently select a value by matching its name.

`String`, `Bool`, `Int`, `Int64` and `Double` conform to `ArgumentValue`; `Optional`
forwards the wrapped wire kind and accepts omission. `StringArgumentChoice` supplies
finite string-enum choices in declared case order. `UserReference`, `ChannelReference`,
`RoleReference`, `MentionableReference` and `AttachmentReference` retain exact
snowflake IDs plus any same-interaction partial resolved observations. A constrained
channel requires matching resolved type data; absent or conflicting type evidence
fails closed. Attachment file-type filters remain picker hints and do not inspect
file contents. Missing and null resource categories remain distinct. A reference
does not hydrate data, download an attachment, assert resource existence or
authorize application work.

Integer codecs enforce exact inclusive `-(2^53-1)...(2^53-1)` without floating-point
rounding. `Double` accepts finite values in inclusive `-2^53...2^53`; decimal range
admission occurs before conversion, while ordinary IEEE-754 rounding/underflow
still applies within that range. Custom codecs may impose stronger local rules.

Omission, explicit null and a supplied value remain distinct. A missing required
option fails; an absent optional becomes nil. `ArgumentDefault.value(...)` supplies
an explicit local fallback for omission, including a deliberately nil optional;
`.none` means no default. Defaults are validated against the same codec/constraints
at schema construction and are not transmitted as registration fields. Explicit
null is rejected rather than treated as an omitted option.

The default unknown-option policy rejects undeclared names. An explicit ignore
policy allows an application to tolerate unknown options; malformed structure,
duplicate names, nested options, focused autocomplete inputs and known-option type
or constraint failures still reject. The complete declared input is validated even
when an application constructor does not request every field.

## Lower a manual slash handler

A `ManualSlashCommandHandler` supplies metadata and executes with the existing
`InteractionContext`. It retains the established response owner and must reply,
defer or otherwise complete explicitly with `context.responder`. This milestone
does not choose a response policy or automatically acknowledge a failed decoder.

```swift
import DiscordCommandDSL
import DiscordDSL
import DiscordInteractions
import DiscordModels

struct Greeting: ManualSlashCommandHandler {
    typealias Arguments = GreetingArguments

    var command: SlashCommandMetadata {
        .init(name: "greet", description: "Show a greeting")
    }

    func execute(_ context: InteractionContext, arguments: Arguments) async throws {
        try await context.responder.reply(
            InteractionMessageCreate(content: .value("Hello from DiscordKit!")))
    }
}

let greeting = try SlashCommand(id: "community.greet", handler: Greeting())
let module = Module(id: "community") { greeting }
let compiled = try CommandCompilation.compile(module)
let router = try compiled.makeRouter(maximumConcurrentHandlers: 32)
// Pass trusted interaction contexts to router.route(_:) from an explicitly owned host.
```

`SlashCommand` captures metadata and the schema once, producing the exact validated
registration snapshot and matching root route. `SlashCommandMetadata` preserves
localizations, omitted/null permission defaults, installation/invocation contexts
and age restriction through existing models. Those values configure registration;
they do not replace current Discord authorization. Share the created router when
workers need one aggregate active-handler bound. Admission overflow fails without
an implicit queue; cancellation and handler errors propagate through the existing
router, and no mutation is retried or replayed.

`ExistingSlashCommand(id:definition:route:source:)` is an explicit incremental
adapter for a validated low-level root slash definition and its exact matching
route. It performs no typed decoding. Other command kinds, nested subcommands,
autocomplete and mismatched route identity fail authoring validation. External
extensions can conform to `CommandContribution`; their deterministic raw payload,
validated definition and route must agree. Compilation validates those snapshots
and rejects a raw metadata leaf that merely claims the slash-command kind.

Compilation preserves module/declaration source order and applies all shared
`DefinitionLimits`. Typed declarations account for complete registration JSON and
`CommandArgumentSchema.metadata`: ordered option registrations, explicit default
presence/value fingerprints, the unknown-option policy and schema/option source
coordinates. Author defaults are intentionally visible in these immutable
descriptions; submitted interaction values and executable closures are excluded.
Use explicit source coordinates when cross-file snapshots require reproducible
locations. Duplicate declaration/module IDs fail structurally; different IDs with the same route still fail as duplicate
routes. The result exposes immutable `description`, `definitions` and `routes`.
Registration/reconciliation remain explicit existing `DiscordCommands` operations.

## Diagnostics and evidence boundary

`ArgumentDiagnostic` and `CommandCompilationDiagnostic` carry bounded source/command/
option context and stable failure categories. They do not retain submitted values,
resolved resources, user text or underlying custom errors. Structural collection
uses the existing `DefinitionDiagnostic`. Correct declarations or input before
retrying; compilation returns no successful partial plan.

Application-provided schema getters, codec implementations, constructors, metadata
accessors and module bodies remain ordinary Swift. They must terminate and remain
free of side effects; the library cannot preempt arbitrary synchronous user code
or bound memory already allocated by it. Descriptor count and admitted metadata
bytes bound the owned compilation state; they do not measure or bound the memory
captured by a custom codec/constructor/handler closure or injected service.
Invocation constructors are application code and execute only after full decoding. Handler dependencies must obey Sendable
and cooperative cancellation; application actors can own mutable services.

The affected contracts were reviewed on **2026-10-18** against the official
[application-command reference](https://docs.discord.com/developers/interactions/application-commands),
[interaction reference](https://docs.discord.com/developers/interactions/receiving-and-responding),
[API versions](https://docs.discord.com/developers/reference#api-versioning) and
[change log](https://docs.discord.com/developers/change-log). Exact fetched-source
hashes and scope are in [the review record](Release/sources/2026-10-18-phase15b.json).
This additive authoring layer does not introduce new endpoints/events or upgrade
unchanged discovery support classifications. See [the dated history](Parity/changes/phase15b-command-dsl.md).

Deterministic local tests cover definitions/routes, argument edge cases and synthetic
router invocations. They do not establish authorized live Discord behavior, platform
qualification, full Phase 15 completion or capacity. Part 15C adds optional
[macro authoring](MacroDSL.md) in a separate package, with its own compiled
expansion/diagnostic evidence; this runtime product remains macro free.
