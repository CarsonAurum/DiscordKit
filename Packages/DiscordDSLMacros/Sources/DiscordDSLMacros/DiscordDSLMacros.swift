// File: Packages/DiscordDSLMacros/Sources/DiscordDSLMacros/DiscordDSLMacros.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

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

/// Synthesizes metadata and a contribution factory for one explicit slash-command response family.
/// A nongeneric struct supplies `typealias Arguments` and `execute(_:arguments:) async throws`.
/// Explicit `SlashCommandHandler` inheritance selects the typed immediate contract; explicit
/// `ModalSlashCommandHandler` inheritance selects an immediate typed modal. Explicit
/// `DeferredSlashCommandHandler` inheritance selects typed defer-before-work and original-edit
/// completion. Explicit `ManualSlashCommandHandler`, or omission of all supported family names,
/// preserves manual responder ownership. Spell exactly one supported family directly; imported
/// protocol refinements are not resolved by the macro. Swift checks the selected execute signature.
/// The generated `slashSubcommand()` factory adapts the same handler as a leaf in an explicit
/// `SlashCommandTree`; grouping never changes response ownership or invokes work. The macro itself
/// never responds, defers or starts tasks, registration, network or device work.
/// - Parameters:
///   - name: Literal root slash-command name; 1...32 lowercase Unicode scalars under runtime rules.
///   - description: Literal registration explanation containing 1...100 Unicode scalars.
@attached(member, names: named(command), named(contribution), named(slashSubcommand))
@attached(extension, conformances: DiscordCommandDSL.ManualSlashCommandHandler)
public macro SlashCommand(_ name: String, description: String) = #externalMacro(module: "DiscordDSLMacrosPlugin", type: "SlashCommandMacro")

/// Synthesizes user context-menu metadata and an explicit contribution factory for a nongeneric struct.
/// Direct `UserCommandHandler`, `DeferredUserCommandHandler` or `ManualUserCommandHandler`
/// inheritance selects one response contract. With no directly spelled family, manual ownership is
/// generated for compatibility with slash authoring. Imported protocol refinements are not resolved.
/// The author supplies `execute(_:target:)` with the family's context and a `UserReference` target;
/// Swift checks response legality. Expansion and construction start no work or target hydration.
/// - Parameter name: Simple literal context-menu name containing 1...32 Unicode scalars; case and spaces
///   are retained. Existing registration validation remains authoritative.
@attached(member, names: named(command), named(contribution))
@attached(extension, conformances: DiscordCommandDSL.ManualUserCommandHandler)
public macro UserCommand(_ name: String) = #externalMacro(module: "DiscordDSLMacrosPlugin", type: "UserCommandMacro")

/// Synthesizes message context-menu metadata and an explicit contribution factory for a nongeneric struct.
/// Direct `MessageCommandHandler`, `DeferredMessageCommandHandler` or `ManualMessageCommandHandler`
/// inheritance selects one response contract; omitting all three generates manual ownership.
/// `execute(_:target:)` receives the family's context and a `MessageCommandTarget` from that same
/// interaction. Swift checks target/response types; no imported-source lookup, target hydration,
/// handler execution, registration, tasks or I/O occurs during expansion or construction.
/// - Parameter name: Simple literal context-menu name containing 1...32 Unicode scalars, retaining
///   case and spaces; runtime registration validation remains authoritative.
@attached(member, names: named(command), named(contribution))
@attached(extension, conformances: DiscordCommandDSL.ManualMessageCommandHandler)
public macro MessageCommand(_ name: String) = #externalMacro(module: "DiscordDSLMacrosPlugin", type: "MessageCommandMacro")
