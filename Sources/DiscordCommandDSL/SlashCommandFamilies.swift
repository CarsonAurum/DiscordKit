// File: Sources/DiscordCommandDSL/SlashCommandFamilies.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCommands
import DiscordCore
import DiscordDSL
import DiscordInteractions
import DiscordModels

/// One typed subcommand with an explicit response family. Parent command and group metadata belong
/// to `SlashCommandTree`; leaf handlers retain the same complete argument and response ownership rules.
public struct SlashSubcommand: Sendable {
    internal let option: ApplicationCommandOptionCreate
    internal let metadata: JSONValue
    private let prepare: @Sendable (InteractionContext, [InteractionCommandOption], Field<InteractionResolvedData>, String)
        throws -> @Sendable () async throws -> Void

    /// Captures manual subcommand behavior without decoding, acknowledgement or execution.
    /// - Parameters:
    ///   - handler: Leaf handler; only its name, description and localizations apply to a subcommand.
    ///   - source: Author coordinate; nil captures compiler defaults without file access.
    ///   - fileID: Caller identifier when source is nil.
    ///   - line: One-based caller line when source is nil; zero indicates unknown.
    ///   - column: One-based caller column when source is nil; zero indicates unknown.
    /// - Throws: Schema/metadata diagnostics, including any root-only settings that would otherwise be lost.
    public init<Handler: ManualSlashCommandHandler>(handler: Handler,
        source: DefinitionSourceLocation? = nil, fileID: String = #fileID,
        line: UInt = #line, column: UInt = #column) throws {
        try self.init(command: handler.command, schema: Handler.Arguments.schema, policy: .string("manual"),
            source: source ?? .init(fileID: fileID, line: line, column: column)) { context, arguments in
                try await handler.execute(context, arguments: arguments)
            }
    }

    /// Captures one immediate-message leaf, with complete argument admission before user work.
    /// - Parameters:
    ///   - handler: Inert immediate handler; no low-level responder is exposed to its execute method.
    ///   - source: Explicit diagnostic coordinate, or nil for compiler defaults.
    ///   - fileID: Caller identifier when source is nil; no file is read.
    ///   - line: Caller line when source is nil; zero means unavailable.
    ///   - column: Caller column when source is nil; zero means unavailable.
    /// - Throws: Invalid schema, leaf metadata or root-only settings. Invocation propagates user/response errors.
    public init<Handler: SlashCommandHandler>(handler: Handler,
        source: DefinitionSourceLocation? = nil, fileID: String = #fileID,
        line: UInt = #line, column: UInt = #column) throws {
        try self.init(command: handler.command, schema: Handler.Arguments.schema, policy: .string("immediate"),
            source: source ?? .init(fileID: fileID, line: line, column: column)) { context, arguments in
                let response = try await handler.execute(CommandContext(context), arguments: arguments)
                try Task.checkCancellation()
                try await context.responder.reply(response.message)
            }
    }

    /// Captures a typed immediate modal leaf with complete argument validation before user execution.
    /// - Parameters:
    ///   - handler: Inert modal-only behavior; root-only registration settings must be absent.
    ///   - source: Explicit author coordinate, or nil for compiler defaults.
    ///   - fileID: Caller identifier when source is nil; no source file is opened.
    ///   - line: Caller line when source is nil; zero means unknown.
    ///   - column: Caller column when source is nil; zero means unknown.
    /// - Throws: Schema/metadata diagnostics. Invocation sends one modal and never defers implicitly.
    public init<Handler: ModalSlashCommandHandler>(handler: Handler,
        source: DefinitionSourceLocation? = nil, fileID: String = #fileID,
        line: UInt = #line, column: UInt = #column) throws {
        try self.init(command: handler.command, schema: Handler.Arguments.schema, policy: .string("modal"),
            source: source ?? .init(fileID: fileID, line: line, column: column)) { context, arguments in
                let response = try await handler.execute(CommandContext(context), arguments: arguments)
                try Task.checkCancellation()
                try await context.responder.respond(.modal(response.modal))
            }
    }

    /// Captures explicitly deferred leaf behavior, completing through one edit of the original message.
    /// - Parameters:
    ///   - handler: Inert deferred handler; its fixed visibility is captured synchronously.
    ///   - source: Explicit coordinate, or nil to capture compiler defaults.
    ///   - fileID: Caller identifier when source is nil.
    ///   - line: Caller line when source is nil; zero means unknown.
    ///   - column: Caller column when source is nil; zero means unknown.
    /// - Throws: Schema/metadata diagnostics. Invocation admits complete arguments before deferring,
    ///   and acknowledgement failure prevents execution. Cancellation/errors never synthesize a fallback.
    public init<Handler: DeferredSlashCommandHandler>(handler: Handler,
        source: DefinitionSourceLocation? = nil, fileID: String = #fileID,
        line: UInt = #line, column: UInt = #column) throws {
        let visibility = handler.responseVisibility
        try self.init(command: handler.command, schema: Handler.Arguments.schema,
            policy: .object(["deferred": .string(visibility == .ephemeral ? "ephemeral" : "public")]),
            source: source ?? .init(fileID: fileID, line: line, column: column)) { context, arguments in
                try await context.responder.deferResponse(ephemeral: visibility == .ephemeral)
                try Task.checkCancellation()
                let response = try await handler.execute(DeferredCommandContext(context), arguments: arguments)
                try Task.checkCancellation()
                _ = try await context.responder.editOriginal(response.edit)
            }
    }

    /// Shares finite leaf registration and per-invocation typed decoding among response adapters.
    /// - Parameters:
    ///   - command: Captured leaf metadata; root-only settings must be absent.
    ///   - schema: Captured complete argument schema; its constructor is retained without execution.
    ///   - policy: Deterministic inert response-family description.
    ///   - source: Diagnostic coordinate used for authoring errors.
    ///   - execute: Caller-task response adapter, invoked only after successful complete synchronous
    ///     decoding and execution interception. Preparation captures fresh arguments without responding.
    /// - Throws: Invalid-command diagnostics for root-only settings or invalid leaf registration.
    private init<Arguments: CommandArguments>(command: SlashCommandMetadata,
        schema: CommandArgumentSchema<Arguments>, policy: JSONValue, source: DefinitionSourceLocation,
        execute: @escaping @Sendable (InteractionContext, Arguments) async throws -> Void) throws {
        guard command.defaultMemberPermissions == .absent, command.integrationTypes == nil,
              command.contexts == nil, command.nsfw == nil else {
            throw CommandCompilationDiagnostic(code: .invalidCommand, commandName: command.name, source: source)
        }
        do {
            option = try ApplicationCommandOptionCreate(type: .subcommand, name: command.name,
                description: command.description, nameLocalizations: command.nameLocalizations,
                descriptionLocalizations: command.descriptionLocalizations, options: schema.options)
        } catch {
            throw CommandCompilationDiagnostic(code: .invalidCommand, commandName: command.name, source: source)
        }
        metadata = .object(["arguments": schema.metadata, "response": policy])
        prepare = { context, options, resolved, rootName in
            try Task.checkCancellation()
            let arguments = try schema.decode(options: options, resolved: resolved, commandName: rootName)
            try Task.checkCancellation()
            return { try await execute(context, arguments) }
        }
    }

    /// Creates one exact leaf route that validates its full command path before typed decoding.
    /// - Parameters:
    ///   - name: Validated root slash name.
    ///   - path: One subcommand, or group followed by subcommand.
    ///   - source: Author coordinate for invalid invocation diagnostics.
    /// - Returns: Inert existing router value. Its synchronous preparation validates the full path
    ///   and typed arguments before execution wrappers can run; no handler work runs during construction.
    /// - Throws: Existing route factory validation for invalid path metadata.
    internal func route(name: String, path: [String], source: DefinitionSourceLocation) throws -> CommandRoute {
        let prepare = self.prepare
        return CommandRoute(key: try .command(name: name, path: path), prepare: { context in
            let input = try commandLeafInput(context, name: name, path: path, autocomplete: false, source: source)
            return try prepare(context, input.options, input.resolved, name)
        })
    }
}

/// One finite group of one through 25 typed subcommands; nested groups are not representable.
public struct SlashSubcommandGroup: Sendable {
    internal let option: ApplicationCommandOptionCreate
    internal let subcommands: [SlashSubcommand]

    /// Validates one group synchronously using the existing command model.
    /// - Parameters:
    ///   - name: Valid lowercase group name, 1...32 Unicode scalars.
    ///   - description: Explanation, 1...100 scalars.
    ///   - subcommands: One through 25 unique named subcommands in author order.
    ///   - nameLocalizations: Omitted, cleared or complete validated localized names.
    ///   - descriptionLocalizations: Omitted, cleared or complete localized explanations.
    /// - Throws: Existing model errors for empty/excessive/duplicate children, names, localizations or text limits.
    public init(name: String, description: String, subcommands: [SlashSubcommand],
        nameLocalizations: Field<[String: String]> = .absent,
        descriptionLocalizations: Field<[String: String]> = .absent) throws {
        guard !subcommands.isEmpty else { throw DiscordError.validation(.invalidValue) }
        option = try ApplicationCommandOptionCreate(type: .subcommandGroup, name: name,
            description: description, nameLocalizations: nameLocalizations,
            descriptionLocalizations: descriptionLocalizations, options: subcommands.map(\.option))
        self.subcommands = subcommands
    }
}

/// Explicit root tree alternatives. Ordinary root arguments cannot be mixed with subcommands/groups.
public enum SlashCommandBranch: Sendable {
    case subcommand(SlashSubcommand)
    case group(SlashSubcommandGroup)

    /// Existing-model registration for this finite branch, preserving localization and omission.
    internal var option: ApplicationCommandOptionCreate {
        switch self { case .subcommand(let value): value.option; case .group(let value): value.option }
    }
}

/// One registered slash root with exact typed subcommand/group routes. Constructors and compilation
/// are synchronous and inert; handlers run only through the explicitly invoked existing router.
public struct SlashCommandTree: CommandFamilyContribution {
    public let declaration: RawDefinitionContribution
    public let family: CommandFamily

    /// Validates a complete group tree and captures every leaf route without invoking user behavior.
    /// - Parameters:
    ///   - id: Stable explicit declaration identity, admitted by structural compilation.
    ///   - command: Complete root metadata, including root-only permission/install/context fields.
    ///   - children: One through 25 unique root subcommands/groups in source order.
    ///   - source: Diagnostic coordinate, or nil to capture compiler defaults.
    ///   - fileID: Caller identifier when source is nil; no filesystem lookup occurs.
    ///   - line: Caller line when source is nil; zero means unknown.
    ///   - column: Caller column when source is nil; zero means unknown.
    /// - Throws: Existing command-model validation or route-key diagnostics. Compile separately enforces
    ///   aggregate route/declaration/text limits and requires enabled autocomplete handlers.
    public init(id: String, command: SlashCommandMetadata, children: [SlashCommandBranch],
        source: DefinitionSourceLocation? = nil, fileID: String = #fileID,
        line: UInt = #line, column: UInt = #column) throws {
        let source = source ?? .init(fileID: fileID, line: line, column: column)
        guard !children.isEmpty else { throw DiscordError.validation(.invalidValue) }
        let definition = try CommandDefinition.slash(name: command.name, description: command.description,
            nameLocalizations: command.nameLocalizations, descriptionLocalizations: command.descriptionLocalizations,
            defaultMemberPermissions: command.defaultMemberPermissions, integrationTypes: command.integrationTypes,
            contexts: command.contexts, nsfw: command.nsfw) { children.map(\.option) }
        var routes: [CommandRoute] = []
        var metadata: [JSONValue] = []
        for child in children {
            switch child {
            case .subcommand(let leaf):
                routes.append(try leaf.route(name: command.name, path: [leaf.option.name], source: source))
                metadata.append(leaf.metadata)
            case .group(let group):
                for leaf in group.subcommands {
                    routes.append(try leaf.route(name: command.name, path: [group.option.name, leaf.option.name], source: source))
                    metadata.append(leaf.metadata)
                }
            }
        }
        family = CommandFamily(definitions: [definition], routes: routes, metadata: .array(metadata))
        declaration = family.declaration(id: id, source: source)
    }
}

/// Selects complete leaves from an exact authenticated command path before any typed codec runs.
/// - Parameters:
///   - context: Existing response-owner context, authenticated by its selected host.
///   - name: Exact declared root name.
///   - path: Zero through two exact declared path segments.
///   - autocomplete: Whether the interaction must belong to the autocomplete response family.
///   - source: Bounded diagnostic source coordinate.
/// - Returns: Retained leaf options and same-interaction resolution data; no hydration occurs.
/// - Throws: Invalid-invocation diagnostics for wrong kind/name/path or malformed container envelopes.
internal func commandLeafInput(_ context: InteractionContext, name: String, path: [String],
    autocomplete: Bool, source: DefinitionSourceLocation) throws
    -> (options: [InteractionCommandOption], resolved: Field<InteractionResolvedData>) {
    guard context.interaction.type.knownValue == (autocomplete ? .applicationCommandAutocomplete : .applicationCommand),
          case .value(.command(let data)) = context.interaction.data,
          data.type.knownValue == .chatInput, data.name == name else {
        throw CommandCompilationDiagnostic(code: .invalidInvocation, commandName: name, source: source)
    }
    var options: [InteractionCommandOption]
    switch data.options {
    case .absent: options = []
    case .value(let values): options = values
    case .null: throw CommandCompilationDiagnostic(code: .invalidInvocation, commandName: name, source: source)
    }
    for (index, segment) in path.enumerated() {
        guard options.count == 1, let container = options.first, container.name == segment,
              container.type.knownValue == (index == 0 && path.count == 2 ? .subcommandGroup : .subcommand),
              container.value == .absent, container.focused == .absent else {
            throw CommandCompilationDiagnostic(code: .invalidInvocation, commandName: name, source: source)
        }
        switch container.options {
        case .absent: options = []
        case .value(let values): options = values
        case .null: throw CommandCompilationDiagnostic(code: .invalidInvocation, commandName: name, source: source)
        }
    }
    return (options, data.resolved)
}
