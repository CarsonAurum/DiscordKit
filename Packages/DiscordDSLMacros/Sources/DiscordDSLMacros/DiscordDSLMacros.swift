import DiscordCommandDSL

/// Synthesizes a finite `DiscordCommandDSL.CommandArguments` schema for a nongeneric struct.
/// Each instance property must carry `@Option`, an explicit `ArgumentValue` type, and no accessor.
/// Declaration order is retained: required values must precede optional/defaulted values. A `var`
/// initializer is an explicit fallback and must be a finite literal or enum member expression.
/// Initialized `let` properties cannot be decoded and are rejected; use `var` for fallbacks.
/// Compilation generates inert declarations only. Schema access performs existing synchronous
/// descriptor validation; custom codecs and member expressions remain author-owned Swift code.
/// - Note: No reflection, imported-source inspection, runtime registration or response handling occurs.
@attached(member, names: named(schema), named(init))
@attached(extension, conformances: DiscordCommandDSL.CommandArguments)
public macro CommandArguments() = #externalMacro(module: "DiscordDSLMacrosPlugin", type: "CommandArgumentsMacro")

/// Marks one explicitly typed stored argument property for the enclosing `@CommandArguments` macro.
/// - Parameters:
///   - name: Optional literal Discord option name. Nil uses the Swift property name. Names are
///     validated syntactically and again by the runtime registration model; duplicates are rejected.
///   - description: Literal explanation containing 1...100 Unicode scalars.
/// Defaults use the property's finite literal/member initializer, never this marker's execution.
/// A custom imported `ArgumentValue` or `StringArgumentChoice` is accepted by type spelling; Swift
/// checks its conformance without the macro resolving source files. This marker adds no peers or work.
@attached(peer)
public macro Option(name: String? = nil, description: String) = #externalMacro(module: "DiscordDSLMacrosPlugin", type: "OptionMacro")

/// Synthesizes metadata and a contribution factory for an explicitly manual slash-command handler.
/// The nongeneric struct supplies `typealias Arguments` and `execute(_:arguments:) async throws`.
/// Its existing responder retains acknowledgement, cancellation and completion ownership; the macro
/// never sends or defers a response and starts no tasks, registration, network or device work.
/// - Parameters:
///   - name: Literal root slash-command name; 1...32 lowercase Unicode scalars under runtime rules.
///   - description: Literal registration explanation containing 1...100 Unicode scalars.
@attached(member, names: named(command), named(contribution))
@attached(extension, conformances: DiscordCommandDSL.ManualSlashCommandHandler)
public macro SlashCommand(_ name: String, description: String) = #externalMacro(module: "DiscordDSLMacrosPlugin", type: "SlashCommandMacro")
