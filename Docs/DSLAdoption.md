# Adopt modular commands and bots

Start from one independently compiled example, keep its existing response and
service owners, then move reusable declarations into explicit modules. Swift 6.4
or newer is required. The [design](DSLDesign.md) explains the layers; the
[roadmap](DSLImplementationRoadmap.md) records delivery and qualification boundaries.

## Select a working starting point

| Goal | Starting package | What its offline run exercises |
| --- | --- | --- |
| Macro-authored signed HTTP commands | [DSLCommands](../Examples/DSLCommands/README.md) | `/ping`, command families, safe messages, policies and external command modules |
| Handwritten protocol commands and actor dependencies | [DiscordDSLExtensions](../Packages/DiscordDSLExtensions/README.md), consumed by DSLCommands and DSLBot | Public codecs, typed schemas, shared actor authorization and manual response ownership |
| Typed Gateway handlers without starting a client | [DSLEvents](../Examples/DSLEvents/README.md) | Two modules, ordered synthetic `RESUMED` delivery and one bounded subscription |
| Supervised Gateway application | [DSLBot](../Examples/DSLBot/README.md) | Real client ingestion over injected local peers, an HTTP interaction callback and joined shutdown |

The source packages include manifests, imports, entry points and tests. The DocC
tutorials display synchronized copies of those files. Build the packages in their
committed directories: their manifests resolve the local repository by relative
path. Documentation does not create another implementation to keep synchronized.

## Write the first command with a protocol or macro

For the smallest macro example, open
[DSLCommands.swift](../Examples/DSLCommands/Sources/DSLCommands/DSLCommands.swift).
`PingArguments` is an empty `@CommandArguments` value. `Ping` conforms directly to
`SlashCommandHandler`; `@SlashCommand` supplies its name/description and contribution
factory. Its `execute` receives an immutable `CommandContext` and fresh arguments,
then returns one ephemeral `MessageResponse` containing `Text("Pong!")`.
The generated contribution is installed in `Module(id: "example")` and compiled
once. No handler runs during those steps.

For handwritten authoring, read `ExtensionArguments`, `ExtensionCommand` and
`ExtensionCommands` in
[ExtensionCommands.swift](../Packages/DiscordDSLExtensions/Sources/DiscordCommandExtensions/ExtensionCommands.swift).
`CommandArguments.schema` supplies ordered typed options and constructs a fresh
value from each admitted decoder. `SlashCommandMetadata` provides wire metadata;
`SlashCommand(id:handler:)` contributes the handler. `ManualSlashCommandHandler`
explicitly replies through its authenticated context's responder. This library
selects no compiler plugin or SwiftSyntax. The runtime protocols used by the macro
and handwritten paths are the same.

Choose response ownership deliberately:

| Handler contract | Execution contract |
| --- | --- |
| `SlashCommandHandler` | Return `MessageResponse`; the adapter submits the single initial reply. |
| `DeferredSlashCommandHandler` | The adapter confirms the defer before user work; return `DeferredMessageResponse` for edit-original completion. |
| `ManualSlashCommandHandler` | Use the existing responder explicitly, including defer/continuation decisions and their deadlines. |
| Other command families | Use their typed immediate/deferred/manual contracts; autocomplete, modal opening, updates and message replies have separate legal response kinds. |

Complete arguments, targets or family input are prepared before policies and
deferral. Malformed input runs no handler. Typed contexts deliberately omit the
raw responder; use a manual family when explicit lifecycle control is required.
An expired or uncertain response does not gain another initial slot. See
[responses](CommandResponses.md) and [families](CommandFamilies.md).

## Reuse modules and inject asynchronous actors

A `BotModule` has an explicit stable ID and ordered body. Ordinary initializers
capture Sendable dependencies. `ExtensionDependencies` retains one
`ExtensionCounter` actor, immutable configuration and an asynchronous completion
hook. Its synchronous `validate()` checks local configuration without consulting
the actor. `DependentModule` runs this validation before creating its lazy body;
invalid dependencies return a bounded diagnostic without the original error text.

Compilation makes zero authorization or actor service calls. Invocation awaits the
same injected actor from both policy and handler; actor isolation remains normal
Swift isolation. An asynchronous readiness or authorization check belongs in the
explicit startup/invocation owner. Do not block a synchronous body waiting for it.
Captured child work must remain structured and cancellation cooperative.

Install reusable modules through `ModuleNamespace`. Namespace components qualify
structural identities while preserving original metadata. They do not rename
Discord commands or runtime handler IDs. Choose distinct wire routes before
installing two copies that would collide downstream. The
[extension guide](ModuleExtensions.md) describes count/depth/text bounds and public
extension protocols. Select extension packages explicitly and share existing
aggregate authorities across their modules.

## Add policy and middleware around prepared input

[PolicyExamples.swift](../Examples/DSLCommands/Sources/DSLCommands/PolicyExamples.swift)
is an independently compiled allow/deny example. Its authorization predicate,
`audit >>> metrics` middleware and shared `CommandConcurrencyLimit` are captured
without execution, then applied to the compiled catalog. An authorized invocation
records authorization, audit entry, metrics entry, handler, metrics exit and audit
exit. A denial runs only authorization and returns its explicit ephemeral reply.
Both finish with zero active admission permits.

`and`, `or` and `negated` match `&&`, `||` and `!`; Boolean composition evaluates
left-to-right and skips unused branches. `then` matches `>>>`: the left wrapper
enters first and exits last on success. Use `defer` or explicit error handling for
cleanup on thrown errors. Every evaluation has finite `PolicyLimits`, including
branches that would be skipped. Reuse the same concurrency authority across catalogs
for an aggregate bound. An invocation policy does not replace HTTP rate coordination.
See [policies](CommandPolicies.md) for terminal single-use, cancellation, explicit
rejection compatibility and error translation without retries.

## Choose the host and keep registration explicit

For HTTP, `CommandApplication` composes the compiled router with signed ingress and
the shared initial-response admission authority. The DSLCommands default/`--offline`
mode performs genuine Ed25519 verification over synthetic bytes and asserts exact
callback JSON without sockets. Its explicit `--listen` mode binds loopback using an
application ID/public key; deployment supplies HTTPS termination and preserves the
original signed body and headers. Select concrete adapters in the application.

For Gateway events, `EventCompilation` checks the chosen intents before a pipeline
starts. DSLEvents explicitly subscribes/runs/cancels a bounded pipeline without
starting a client. All default modules share one subscription; same-shard delivery
is serialized and declaration ordered. Independent groups deliberately permit
cross-group progress and have finite separate admission.

For a whole bot, `BotApplication.makeRuntime` builds the existing client, services,
compiled declarations and optional trusted interaction adapter. `BotRuntime.run`
subscribes before client startup and joins child cleanup on stop, failure or
cancellation. Handlers call nonjoining `requestStop`; external owners await `run`
or `shutdown`. A handler must not join itself. The trusted bridge receives only
client-ingested interactions; publishing a normal event envelope cannot authenticate
a command. Its callbacks still use HTTP with separate initial-response admission.
See [event modules](GatewayEventModules.md) and [bot applications](BotApplications.md).

Constructing, compiling and serving any of these compositions registers zero
commands. Review `CompiledCommands.definitions` and the explicit managed
application/scope/name/type set, then call synchronization when registration is
intended. Preserve unmanaged commands, partial results and indeterminate outcomes.
Do not combine typed deferred response ownership with a competing application
auto-defer owner.

## Test the composition before deployment

Run the examples offline and keep their tests as executable reference material:

```sh
swift test --package-path Packages/DiscordDSLExtensions
swift test --package-path Examples/DSLCommands
swift run --package-path Examples/DSLCommands DSLCommands --offline
swift test --package-path Examples/DSLEvents
swift run --package-path Examples/DSLEvents
swift test --package-path Examples/DSLBot
swift run --package-path Examples/DSLBot DSLBot
```

Test exact definitions/routes and JSON, absent/null/wrong-kind input, source
diagnostics and bounds, safe untrusted interpolation, zero compilation effects,
policy short circuiting, response uncertainty and cancellation cleanup. Compile
macro positive/negative fixtures separately. Reuse compiled schemas/routes across
invocations; use injected clocks and finite public-protocol peers for application
tests. Repository development-only test support is not a runtime product.

Before deployment, load credentials at the composition root, choose explicit intents
and required portal approval, configure signed HTTPS receipt or the Gateway host,
share rate/startup/lease/resource authorities, and await terminal cleanup during
worker handoff. Observe queue overflow and freshness signals; recover through
bounded explicit refresh rather than replaying effects. Multiple workers require
externally coordinated authorities. See [setup](Setup.md), [migration](Migration.md)
and [local measurement limits](DSLBenchmarks.md).

## Keep the direct APIs available

Use `ExistingSlashCommand` for an exact supported root slash definition/route or
`ExistingCommandFamily` for a validated low-level family. Use manual response
families when the existing responder is needed. Raw Models and explicit field
presence remain available beside message builders; trusted raw text remains an
explicit formatting choice. Custom codecs, contributions, selectors and modules
use public protocols in downstream packages without a central switch edit.

Adopt one module or route at a time. Existing direct Commands, Interactions and
Client consumers require no conversion. Local examples and release checks establish
their stated macOS/offline scope; live Discord, other platforms, devices, external
crypto review, complete-client interoperability and production/fleet capacity
remain separate evidence gates. The candidate has no publication or tag implied.
