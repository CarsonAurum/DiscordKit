<!--
File: Docs/ModuleExtensions.md
Created by Carson Rau.
Copyright (c) 2026 Aurum Studios.
https://aurum-studios.com
-->

# External modules and typed dependencies

DiscordKit provides explicit namespace installation and validated typed dependencies to
the independently selected `DiscordDSL` product. External packages can implement
ordinary Swift modules, contributions, command handlers, event selectors, policies
and builders through the existing public extension points. Applications select
those packages and pass their dependencies explicitly; root runtime products gain
no dependency on an extension package.

## Install reusable declarations with explicit identities

`ModuleNamespace` scopes authoring identities without changing declaration metadata.
Install a reusable module in separate namespaces when its local module/declaration
IDs are the same:

```swift
import DiscordDSL

let source = DefinitionSourceLocation(fileID: "Guide/Extensions.swift", line: 1, column: 1)
let notes = Module(id: "notes", source: source) {
    RawDefinitionContribution(id: "help", kind: "guide.note", text: "Help", source: source)
}
let installation = Module(id: "application", source: source) {
    ModuleNamespace(id: "community", source: source) { notes }
    ModuleNamespace(id: "staff", source: source) { notes }
}
let plan = try DefinitionPlan.compile(installation, supportedKinds: ["guide.note"])
assert(plan.description.declarations.map(\.identity) == [
    DefinitionIdentity(namespacePath: ["community"], id: "help"),
    DefinitionIdentity(namespacePath: ["staff"], id: "help")
])
```

`DefinitionIdentity` compares ordered namespace components plus the original local
ID using ordinary Swift `String` equality, retaining their original spelling.
Canonically equivalent Unicode strings retain the existing identity-equality
behavior. It does not concatenate strings: the single component `a.b`
and the two components `a`, `b` remain different identities. `PlannedModule` and
`PlannedDeclaration` retain their original IDs, module ancestry, source coordinates
and raw payloads, with separate `namespacePath` and `identity` observations.
`DefinitionDescription.namespaces` records installations in preorder, including
empty namespaces. Ordinary definitions use an empty namespace path and retain
their existing duplicate checks.

Each full namespace path can be installed once throughout a plan. Different
enclosing modules do not create separate namespaces automatically. Within a
namespace, module IDs and declaration IDs each remain unique. Namespace components
use the same nonempty, 128 UTF-8-byte, no-ASCII-control identity rules. The shared
`DefinitionLimits.maxNamespaces` defaults to 256; every namespace also consumes
structural/depth admission and charges its ID/source label to the shared text
budget. All namespaces share the plan's existing module/declaration/text budgets.

Namespaces never rename application commands, autocomplete paths, component/modal
custom IDs, selector IDs or event groups. Two namespaced commands with the same
wire route still fail the downstream command compiler's duplicate-route checks.
Choose different explicit command metadata when two installed modules need
different Discord registrations. Event handlers likewise retain the existing
global handler-ID requirement across event groups; namespace installation grants
no new intent or independent subscription.

`ModuleNamespace`, like `Module`, constructs its synchronous builder once during
initialization. Namespace admission later bounds collection; it cannot undo memory
or side effects already produced by a caller's builder. Use `DependentModule` when
body creation must wait for dependency validation.

## Validate dependencies before creating a module body

`ModuleDependencies` is a Sendable protocol with a synchronous throwing
`validate()` requirement. A conforming value holds the module's finite local
configuration and injected service/actor references. It checks configuration;
it does not resolve services, read environment variables or probe a remote host.

```swift
struct NotesDependencies: ModuleDependencies {
    let title: String

    enum InvalidConfiguration: Error { case title }

    /// Requires a finite nonempty local label without invoking any service.
    /// - Throws: InvalidConfiguration.title when the label cannot be admitted.
    func validate() throws {
        guard !title.isEmpty, title.utf8.count <= 80 else {
            throw InvalidConfiguration.title
        }
    }
}

let configured = DependentModule(
    id: "notes", dependencies: NotesDependencies(title: "Community help"), source: source
) { dependencies in
    RawDefinitionContribution(
        id: "help", kind: "guide.note", text: dependencies.title, source: source)
}
let configuredPlan = try DefinitionPlan.compile(configured, supportedKinds: ["guide.note"])
```

Construction stores the typed value and Sendable body factory. It performs no
validation and does not invoke the factory. For each module installation in a
compilation, the collector first admits its identity, count, depth and metadata
bytes, then calls `validate()`, then creates and collects the body once. Installing
the same value in two distinct namespaces validates and expands each installation.
Failed module admission skips both validation
and body creation. Failed dependencies skip body creation and return the bounded
`DefinitionDiagnostic.Code.invalidDependencies` category at the module's source and
module/namespace ancestry. The original error and dependency contents are omitted.
A failed collector remains terminal even if a custom enclosing composite catches
the error; no successful partial plan escapes.

The factory receives the same injected dependency value on every compilation.
Reference values retain their original identity; the DSL creates no replacement
authority, client, cache or service. Validation repeats for each admitted
installation, so it must be deterministic, finite and free of side effects.
Successful validation is local authoring evidence. It cannot prove credentials,
current permissions, host availability or future operation success. Arbitrary
application validators and builders remain ordinary Swift and must terminate
cooperatively; compilation cannot sandbox them.

## Keep extension behavior with its existing owner

| Extension point | Explicit adoption and ownership |
| --- | --- |
| `BotModule`, `BotDefinition`, `DefinitionContribution` | Shared finite collection over Core/Models. Custom composites use collector admission and propagate failures. |
| `CommandContribution`, `CommandFamilyContribution` | CommandDSL checks exact raw metadata against retained registrations/routes. Existing Commands/Interactions own invocation and responses. |
| Command argument codecs and typed handlers | Existing finite schemas, strict input preparation, response families and router admission remain authoritative. |
| `GatewayEventSelector`, `GatewayEventHandler`, `GatewayEventContribution` | BotDSL checks intents and metadata, then explicitly owned pipelines invoke selection/handlers over existing broadcast dispatch. |
| `InvocationPolicy`, `InvocationMiddleware` | Typed closure composition retains bounded admission, cancellation, single terminal execution and explicit error mapping. |
| Message/component builder helpers | Helpers return existing typed content/model builders; ordinary dynamic strings retain escaping and mention policy. |

Metadata that merely claims a supported contribution kind is insufficient. Command
and event lowering require their public typed contribution protocols and compare
the captured metadata. A custom extension cannot bypass validators by wrapping an
invalid raw declaration. Use existing low-level adapters when adopting an already
validated command family or route.

The independent [extension package](../Packages/DiscordDSLExtensions/README.md) provides reusable public
`DiscordCommandExtensions` and `DiscordBotExtensions` libraries. DSLCommands selects
the command-only library; DSLBot also selects the event library. These are downstream
libraries built through public APIs, with no
`@testable` access to runtime targets. Their tests and consumer offline runs prove
that the selected package graph and extension behavior compile and execute outside
the root package. `UppercaseCode` supplies a custom typed argument codec;
`ExtensionCommands` retains a shared `ExtensionCounter` actor, typed dependencies,
an `ExtensionAuthorizationPolicy` adapter and a raw command beside a typed command.
`ExtensionEvents` supplies custom event selection and handlers with injected
callbacks. The same command module is invoked through the synthetic signed HTTP
consumer and the trusted-ingestion Gateway consumer, with no runtime source change
needed to add it. See the package and [HTTP](../Examples/DSLCommands/README.md) /
[Gateway](../Examples/DSLBot/README.md) consumer READMEs for exact example behavior.

An application may hold its own narrow Voice, Social or OAuth interfaces in a typed
dependency value, and select those separate products at its composition root when
needed. Those references do not add imports or upward dependencies to shared DSL,
CommandDSL or BotDSL. Consent, credentials, lifetime, media/device qualification and
service-specific validation remain with their existing owners. Extensions must
reuse the application's aggregate credential, startup, lease, handler, REST and
resource authorities across modules; module installation does not create quotas
or authorize duplicate owners.

## Evidence and qualification boundaries

Run root build/tests, callable documentation, graph/import isolation, scoped public
API and DocC checks, the independent extension package tests, and the affected
command/event consumers. Verify namespace collisions and limits, dependency failure
before body creation, zero execution during construction/compilation, exact
direct-versus-extension payloads/routes and cooperative runtime cancellation.
Keep command-only extension adoption independent of Gateway/Client/Cache and
concrete adapters; adding an event extension is an explicit broader selection.

Local and offline checks introduce no new Discord wire contract and establish
no authorized live service, other-platform, hardware or production-capacity claim.
See [local compile/runtime measurements](DSLBenchmarks.md) for finite budgets and
separate handler/cache soaks, and the [adoption guide](DSLAdoption.md) for integration.