# Macro command authoring

Part 15C adds `DiscordDSLMacros` as a separate Swift package under
`Packages/DiscordDSLMacros`. It consumes the existing runtime products; neither the
root package nor a macro-free consumer selects a compiler plugin or SwiftSyntax.
Swift 6.4 and the pinned SwiftSyntax **604.0.0** are the verified local combination.
The package remains unpublished with the **0.15.0 authoring candidate**.

## Adopt the macros

Add both the root DiscordKit package and the separate macro package to your
application's SwiftPM dependencies. Select `DiscordDSLMacros` from the latter and
`DiscordCommandDSL`, `DiscordDSL` and `DiscordInteractions` from the root as needed
by your source imports. The macro package's local root dependency is `../..`;
repository consumers use a local path to this separate package. A standalone remote
macro-package distribution is not established by this milestone.

```swift
import DiscordCommandDSL
import DiscordDSL
import DiscordDSLMacros
import DiscordInteractions
import DiscordModels

@CommandArguments
struct GreetingArguments: Sendable {
    @Option(description: "Name to greet")
    var name: String

    @Option(description: "Optional repetition count")
    var repetitions: Int?
}

@SlashCommand("greet", description: "Show a greeting")
struct Greeting: ManualSlashCommandHandler {
    typealias Arguments = GreetingArguments

    /// Sends one explicit initial response using the existing unique responder.
    /// - Parameters:
    ///   - context: Trusted interaction context; cancellation and reply errors propagate.
    ///   - arguments: Fresh validated input for this invocation.
    /// - Throws: Cancellation, validation or delivery errors from the responder.
    func execute(_ context: InteractionContext, arguments: Arguments) async throws {
        try await context.responder.reply(
            InteractionMessageCreate(content: .value("Hello, " + arguments.name)))
    }
}
```

To obtain an
inert contribution, call `try Greeting().contribution(id: "community.greet", source:
.init(fileID: #fileID, line: #line, column: #column))`. Include it in an existing
`Module` and call `CommandCompilation.compile`. Inspect the definitions, then
explicitly construct/invoke the existing router or reconcile registrations through
application-owned infrastructure. Macro expansion and compilation do not invoke
`execute`, register commands, read credentials or start network work.

## Generated contracts and supported properties

`@CommandArguments` inspects only its own struct. Each `@Option` field declares an
explicit `ArgumentValue` type and a literal description; an optional literal `name`
overrides the property name. Required fields precede optional/defaulted fields in
source. Built-in scalar/reference types, `StringArgumentChoice` enums and external
custom codecs all use the existing protocol. The macro never resolves another
module's source, hydrates resources or implements its own wire decoder.

The expansion supplies a throwing `schema` getter, typed descriptors, a fresh
aggregate constructor and `CommandArguments` conformance. Existing conformance may
be written explicitly. Generated callables include documentation. Runtime schema
validation remains authoritative for custom codecs, required ordering, numeric and
string constraints, defaults and Discord registration metadata. See
[typed command contracts](CommandDSL.md) for missing/null values, diagnostics,
partial resolved references, cancellation and bounded router ownership.

This initial macro supports simple stored instance properties with one binding,
an explicit type and no observers/accessors. Metadata uses simple single-line unescaped
literals and a conservative lowercase letter/number/underscore/hyphen name subset;
advanced Unicode names and escaped descriptions remain available through explicit schemas. Optional fields decode omission as
nil. A supported literal initializer on a `var` is a local fallback for omission;
explicit null still fails. Initialized `let` fields are rejected because Swift
cannot replace them with decoded invocation state. Computed/static/lazy properties,
property wrappers, destructuring, unsupported metadata and arbitrary executable
default expressions are rejected with source diagnostics. An enum-member spelling can
refer to an author-defined computed member; that code must remain finite and inert,
just like a custom codec. Syntactic admission does not sandbox application Swift. Use explicit Part 15B
schemas for unsupported forms or advanced metadata rather than relying on reflection.

`@SlashCommand` generates `SlashCommandMetadata`, handler conformance and
`contribution(id:source:)` plumbing. It references the handler's `Arguments`
protocol instead of inspecting that type. The behavior stays in `execute`; the
Swift compiler checks its signature, Sendable captures and every generated codec
use. In Part 15D, explicitly conform to `SlashCommandHandler` for an immediate
`MessageResponse`, `DeferredSlashCommandHandler` for acknowledged-before-execution
`DeferredMessageResponse`, or `ManualSlashCommandHandler` for raw responder ownership.
Omitting the family preserves the original manual default. The macro factory uses
the same `SlashCommand` runtime adapters as handwritten code; it does not create
another response owner. See [response modes and HTTP applications](CommandResponses.md).
Part 15E composes the same handlers with [message/component builders](MessageBuilders.md)
without changing macro expansion or response ownership. Other command families remain
later milestones.

## Verification and scope

```sh
swift test --package-path Packages/DiscordDSLMacros
python3 Tools/ci/dsl_compile_fixtures.py
python3 -m unittest discover -s Tools/ci -p 'test_dsl_compile_fixtures.py'
```

Expansion tests inspect generated declarations and source diagnostics. Execution
parity tests compile the actual expansions and compare definitions, routes and
argument decoding with handwritten implementations, including malformed input,
defaults, references and invocation isolation. The fixture runner builds genuine
external package targets, including a codec in another module, and requires
negative consumers to fail with the expected semantic diagnostic. It checks compiler
Sendable enforcement rather than accepting a text expansion snapshot as execution
evidence. These checks are offline; no fixture needs Discord credentials.

The [SwiftSyntax release](https://github.com/swiftlang/swift-syntax/releases/tag/604.0.0),
[attached macro proposal](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0389-attached-macros.md)
and affected [Discord command contracts](https://docs.discord.com/developers/interactions/application-commands)
were reviewed on **2026-10-18**. Exact review input hashes are recorded in
[the source record](Release/sources/2026-10-18-phase15c.json). Local Swift 6.4/macOS
build and synthetic parity evidence do not establish other toolchains/platforms,
live Discord interoperability, capacity or complete Phase 15 support.
