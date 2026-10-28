// File: Sources/DiscordCommandDSL/CommandFamilies.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCommands
import DiscordCore
import DiscordDSL
import DiscordInteractions
import DiscordModels

/// Registration-only metadata shared by user and message context-menu commands.
/// The contribution selects the command type; permission defaults never grant local authority.
public struct ContextMenuCommandMetadata: Sendable {
    public let name: String
    public let nameLocalizations: Field<[String: String]>
    public let defaultMemberPermissions: Field<String>
    public let integrationTypes: [ApplicationIntegrationType]?
    public let contexts: [InteractionContextType]?
    public let nsfw: Bool?

    /// Stores finite settings without validation, registration, tasks or I/O.
    /// - Parameters:
    ///   - name: Display name of 1...32 Unicode scalars, allowing spaces and mixed case.
    ///   - nameLocalizations: Omitted, cleared, or complete translated names.
    ///   - defaultMemberPermissions: Omitted, unrestricted null, or decimal permission bits.
    ///   - integrationTypes: Optional global installation contexts; nil leaves settings unmanaged.
    ///   - contexts: Optional global invocation contexts; nil leaves settings unmanaged.
    ///   - nsfw: Optional age restriction; nil omits the field.
    public init(name: String, nameLocalizations: Field<[String: String]> = .absent,
        defaultMemberPermissions: Field<String> = .absent,
        integrationTypes: [ApplicationIntegrationType]? = nil,
        contexts: [InteractionContextType]? = nil, nsfw: Bool? = nil) {
        self.name = name; self.nameLocalizations = nameLocalizations
        self.defaultMemberPermissions = defaultMemberPermissions
        self.integrationTypes = integrationTypes; self.contexts = contexts; self.nsfw = nsfw
    }
}

/// Selected message identity and its same-interaction partial projection. No hydration occurs.
public struct MessageCommandTarget: Sendable, Equatable {
    public let id: MessageID
    public let message: Field<MessageRelatedResource>

    /// Retains an exact selected message and independently supplied partial observation.
    /// - Parameters:
    ///   - id: Full unsigned 64-bit message identifier.
    ///   - message: Absent, null, or partial resolved object; absent by default.
    public init(id: MessageID, message: Field<MessageRelatedResource> = .absent) {
        self.id = id; self.message = message
    }
}

/// Returns one immediate message or modal; no implicit defer occurs. The complete context-menu envelope and selected target are admitted first.
public protocol UserCommandHandler: Sendable {
    associatedtype Response: CommandInitialResponse
    var command: ContextMenuCommandMetadata {
        /// Returns inert registration metadata without tasks, I/O or handler execution.
        get
    }
    /// Executes in the caller's cancellation-cooperative router task after complete input admission.
    /// - Parameters:
    ///   - context: Immutable normalized snapshot without acknowledgement authority.
    ///   - target: Exact selected user ID and partial same-interaction observations; never hydrated.
    /// - Returns: A validated immediate message or modal without retries or fallback.
    /// - Throws: Application failure or cancellation, propagated without replay or invented responses.
    func execute(_ context: CommandContext, target: UserReference) async throws -> Response
}

/// Returns an original edit after a confirmed explicit defer. The complete context-menu envelope and selected target are admitted first.
public protocol DeferredUserCommandHandler: Sendable {
    var command: ContextMenuCommandMetadata {
        /// Returns inert registration metadata without tasks, I/O or handler execution.
        get
    }
    var responseVisibility: CommandResponseVisibility {
        /// Returns fixed deferred visibility, captured once during contribution construction.
        get
    }
    /// Executes in the caller's cancellation-cooperative router task after complete input admission.
    /// - Parameters:
    ///   - context: Immutable normalized snapshot without acknowledgement authority.
    ///   - target: Exact selected user ID and partial same-interaction observations; never hydrated.
    /// - Returns: Validated original edit completing the confirmed defer without retries or fallback.
    /// - Throws: Application failure or cancellation, propagated without replay or invented responses.
    func execute(_ context: DeferredCommandContext, target: UserReference) async throws -> DeferredMessageResponse
}

public extension DeferredUserCommandHandler {
    /// Selects public visibility unless the handler explicitly overrides it.
    var responseVisibility: CommandResponseVisibility { .public }
}

/// Uses the exact existing responder explicitly; no automatic callback occurs. The complete context-menu envelope and selected target are admitted first.
public protocol ManualUserCommandHandler: Sendable {
    var command: ContextMenuCommandMetadata {
        /// Returns inert registration metadata without tasks, I/O or handler execution.
        get
    }
    /// Executes in the caller's cancellation-cooperative router task after complete input admission.
    /// - Parameters:
    ///   - context: Immutable normalized snapshot; manual response authority is explicit.
    ///   - target: Exact selected user ID and partial same-interaction observations; never hydrated.
    /// - Throws: Application failure or cancellation, propagated without replay or invented responses.
    func execute(_ context: InteractionContext, target: UserReference) async throws
}

/// A typed user context-menu contribution with exact command routing and no construction side effects.
public struct UserCommand<Handler: Sendable>: CommandFamilyContribution {
    public let family: CommandFamily
    public let declaration: RawDefinitionContribution

    /// Captures immediate response behavior and registration without invoking the handler.
    /// - Parameters:
    ///   - id: Stable declaration identity validated by structural compilation.
    ///   - handler: Inert handler; metadata and response policy are captured once.
    ///   - source: Bounded authoring coordinate, retained without reading files.
    /// - Throws: Sanitized compilation diagnostics for invalid registration metadata.
    public init(id: String, handler: Handler, source: DefinitionSourceLocation) throws
        where Handler: UserCommandHandler {
        let built = try contextMenuFamily(metadata: handler.command, type: .user, source: source,
            policy: .string("immediate"), execute: { context, data in
                let target = try contextMenuUserTarget(data)
                try Task.checkCancellation()
                let response = try await handler.execute(CommandContext(context), target: target)
                try await sendFamilyResponse(response.interactionResponse, context: context,
                    allowed: [.channelMessageWithSource, .modal])
            })
        family = built
        declaration = family.declaration(id: id, source: source)
    }

    /// Captures the caller coordinate while constructing immediate user behavior.
    /// - Parameters:
    ///   - id: Stable declaration identity validated during compilation.
    ///   - handler: Inert retained behavior; construction performs no user execution or I/O.
    ///   - fileID: Caller source identifier; no file lookup occurs.
    ///   - line: One-based source line, or explicit zero for unavailable.
    ///   - column: One-based source column, or explicit zero for unavailable.
    /// - Throws: The same sanitized registration diagnostics as explicit-source construction.
    public init(id: String, handler: Handler, fileID: String = #fileID, line: UInt = #line,
        column: UInt = #column) throws where Handler: UserCommandHandler {
        try self.init(id: id, handler: handler, source: .init(fileID: fileID, line: line, column: column))
    }

    /// Captures deferred behavior and registration without invoking the handler.
    /// - Parameters:
    ///   - id: Stable declaration identity validated by structural compilation.
    ///   - handler: Inert handler; metadata and response policy are captured once.
    ///   - source: Bounded authoring coordinate, retained without reading files.
    /// - Throws: Sanitized compilation diagnostics for invalid registration metadata.
    public init(id: String, handler: Handler, source: DefinitionSourceLocation) throws
        where Handler: DeferredUserCommandHandler {
        let visibility = handler.responseVisibility
        let built = try contextMenuFamily(metadata: handler.command, type: .user, source: source,
            policy: .object(["deferred": .string(visibility == .ephemeral ? "ephemeral" : "public")]), execute: { context, data in
                let target = try contextMenuUserTarget(data)
                try await context.responder.deferResponse(ephemeral: visibility == .ephemeral)
                try Task.checkCancellation()
                let response = try await handler.execute(DeferredCommandContext(context), target: target)
                try Task.checkCancellation()
                _ = try await context.responder.editOriginal(response.edit)
            })
        family = built
        declaration = family.declaration(id: id, source: source)
    }

    /// Captures the caller coordinate while constructing deferred user behavior.
    /// - Parameters:
    ///   - id: Stable declaration identity validated during compilation.
    ///   - handler: Inert retained behavior; construction performs no user execution or I/O.
    ///   - fileID: Caller source identifier; no file lookup occurs.
    ///   - line: One-based source line, or explicit zero for unavailable.
    ///   - column: One-based source column, or explicit zero for unavailable.
    /// - Throws: The same sanitized registration diagnostics as explicit-source construction.
    public init(id: String, handler: Handler, fileID: String = #fileID, line: UInt = #line,
        column: UInt = #column) throws where Handler: DeferredUserCommandHandler {
        try self.init(id: id, handler: handler, source: .init(fileID: fileID, line: line, column: column))
    }

    /// Captures manual behavior and registration without invoking the handler.
    /// - Parameters:
    ///   - id: Stable declaration identity validated by structural compilation.
    ///   - handler: Inert handler; metadata and response policy are captured once.
    ///   - source: Bounded authoring coordinate, retained without reading files.
    /// - Throws: Sanitized compilation diagnostics for invalid registration metadata.
    public init(id: String, handler: Handler, source: DefinitionSourceLocation) throws
        where Handler: ManualUserCommandHandler {
        let built = try contextMenuFamily(metadata: handler.command, type: .user, source: source,
            policy: .string("manual"), execute: { context, data in
                let target = try contextMenuUserTarget(data)
                try Task.checkCancellation()
                try await handler.execute(context, target: target)
            })
        family = built
        declaration = family.declaration(id: id, source: source)
    }

    /// Captures the caller coordinate while constructing manual user behavior.
    /// - Parameters:
    ///   - id: Stable declaration identity validated during compilation.
    ///   - handler: Inert retained behavior; construction performs no user execution or I/O.
    ///   - fileID: Caller source identifier; no file lookup occurs.
    ///   - line: One-based source line, or explicit zero for unavailable.
    ///   - column: One-based source column, or explicit zero for unavailable.
    /// - Throws: The same sanitized registration diagnostics as explicit-source construction.
    public init(id: String, handler: Handler, fileID: String = #fileID, line: UInt = #line,
        column: UInt = #column) throws where Handler: ManualUserCommandHandler {
        try self.init(id: id, handler: handler, source: .init(fileID: fileID, line: line, column: column))
    }
}

/// Returns one immediate message or modal; no implicit defer occurs. The complete context-menu envelope and selected target are admitted first.
public protocol MessageCommandHandler: Sendable {
    associatedtype Response: CommandInitialResponse
    var command: ContextMenuCommandMetadata {
        /// Returns inert registration metadata without tasks, I/O or handler execution.
        get
    }
    /// Executes in the caller's cancellation-cooperative router task after complete input admission.
    /// - Parameters:
    ///   - context: Immutable normalized snapshot without acknowledgement authority.
    ///   - target: Exact selected message ID and partial same-interaction observations; never hydrated.
    /// - Returns: A validated immediate message or modal without retries or fallback.
    /// - Throws: Application failure or cancellation, propagated without replay or invented responses.
    func execute(_ context: CommandContext, target: MessageCommandTarget) async throws -> Response
}

/// Returns an original edit after a confirmed explicit defer. The complete context-menu envelope and selected target are admitted first.
public protocol DeferredMessageCommandHandler: Sendable {
    var command: ContextMenuCommandMetadata {
        /// Returns inert registration metadata without tasks, I/O or handler execution.
        get
    }
    var responseVisibility: CommandResponseVisibility {
        /// Returns fixed deferred visibility, captured once during contribution construction.
        get
    }
    /// Executes in the caller's cancellation-cooperative router task after complete input admission.
    /// - Parameters:
    ///   - context: Immutable normalized snapshot without acknowledgement authority.
    ///   - target: Exact selected message ID and partial same-interaction observations; never hydrated.
    /// - Returns: Validated original edit completing the confirmed defer without retries or fallback.
    /// - Throws: Application failure or cancellation, propagated without replay or invented responses.
    func execute(_ context: DeferredCommandContext, target: MessageCommandTarget) async throws -> DeferredMessageResponse
}

public extension DeferredMessageCommandHandler {
    /// Selects public visibility unless the handler explicitly overrides it.
    var responseVisibility: CommandResponseVisibility { .public }
}

/// Uses the exact existing responder explicitly; no automatic callback occurs. The complete context-menu envelope and selected target are admitted first.
public protocol ManualMessageCommandHandler: Sendable {
    var command: ContextMenuCommandMetadata {
        /// Returns inert registration metadata without tasks, I/O or handler execution.
        get
    }
    /// Executes in the caller's cancellation-cooperative router task after complete input admission.
    /// - Parameters:
    ///   - context: Immutable normalized snapshot; manual response authority is explicit.
    ///   - target: Exact selected message ID and partial same-interaction observations; never hydrated.
    /// - Throws: Application failure or cancellation, propagated without replay or invented responses.
    func execute(_ context: InteractionContext, target: MessageCommandTarget) async throws
}

/// A typed message context-menu contribution with exact command routing and no construction side effects.
public struct MessageCommand<Handler: Sendable>: CommandFamilyContribution {
    public let family: CommandFamily
    public let declaration: RawDefinitionContribution

    /// Captures immediate response behavior and registration without invoking the handler.
    /// - Parameters:
    ///   - id: Stable declaration identity validated by structural compilation.
    ///   - handler: Inert handler; metadata and response policy are captured once.
    ///   - source: Bounded authoring coordinate, retained without reading files.
    /// - Throws: Sanitized compilation diagnostics for invalid registration metadata.
    public init(id: String, handler: Handler, source: DefinitionSourceLocation) throws
        where Handler: MessageCommandHandler {
        let built = try contextMenuFamily(metadata: handler.command, type: .message, source: source,
            policy: .string("immediate"), execute: { context, data in
                let target = try contextMenuMessageTarget(data)
                try Task.checkCancellation()
                let response = try await handler.execute(CommandContext(context), target: target)
                try await sendFamilyResponse(response.interactionResponse, context: context,
                    allowed: [.channelMessageWithSource, .modal])
            })
        family = built
        declaration = family.declaration(id: id, source: source)
    }

    /// Captures the caller coordinate while constructing immediate message behavior.
    /// - Parameters:
    ///   - id: Stable declaration identity validated during compilation.
    ///   - handler: Inert retained behavior; construction performs no user execution or I/O.
    ///   - fileID: Caller source identifier; no file lookup occurs.
    ///   - line: One-based source line, or explicit zero for unavailable.
    ///   - column: One-based source column, or explicit zero for unavailable.
    /// - Throws: The same sanitized registration diagnostics as explicit-source construction.
    public init(id: String, handler: Handler, fileID: String = #fileID, line: UInt = #line,
        column: UInt = #column) throws where Handler: MessageCommandHandler {
        try self.init(id: id, handler: handler, source: .init(fileID: fileID, line: line, column: column))
    }

    /// Captures deferred behavior and registration without invoking the handler.
    /// - Parameters:
    ///   - id: Stable declaration identity validated by structural compilation.
    ///   - handler: Inert handler; metadata and response policy are captured once.
    ///   - source: Bounded authoring coordinate, retained without reading files.
    /// - Throws: Sanitized compilation diagnostics for invalid registration metadata.
    public init(id: String, handler: Handler, source: DefinitionSourceLocation) throws
        where Handler: DeferredMessageCommandHandler {
        let visibility = handler.responseVisibility
        let built = try contextMenuFamily(metadata: handler.command, type: .message, source: source,
            policy: .object(["deferred": .string(visibility == .ephemeral ? "ephemeral" : "public")]), execute: { context, data in
                let target = try contextMenuMessageTarget(data)
                try await context.responder.deferResponse(ephemeral: visibility == .ephemeral)
                try Task.checkCancellation()
                let response = try await handler.execute(DeferredCommandContext(context), target: target)
                try Task.checkCancellation()
                _ = try await context.responder.editOriginal(response.edit)
            })
        family = built
        declaration = family.declaration(id: id, source: source)
    }

    /// Captures the caller coordinate while constructing deferred message behavior.
    /// - Parameters:
    ///   - id: Stable declaration identity validated during compilation.
    ///   - handler: Inert retained behavior; construction performs no user execution or I/O.
    ///   - fileID: Caller source identifier; no file lookup occurs.
    ///   - line: One-based source line, or explicit zero for unavailable.
    ///   - column: One-based source column, or explicit zero for unavailable.
    /// - Throws: The same sanitized registration diagnostics as explicit-source construction.
    public init(id: String, handler: Handler, fileID: String = #fileID, line: UInt = #line,
        column: UInt = #column) throws where Handler: DeferredMessageCommandHandler {
        try self.init(id: id, handler: handler, source: .init(fileID: fileID, line: line, column: column))
    }

    /// Captures manual behavior and registration without invoking the handler.
    /// - Parameters:
    ///   - id: Stable declaration identity validated by structural compilation.
    ///   - handler: Inert handler; metadata and response policy are captured once.
    ///   - source: Bounded authoring coordinate, retained without reading files.
    /// - Throws: Sanitized compilation diagnostics for invalid registration metadata.
    public init(id: String, handler: Handler, source: DefinitionSourceLocation) throws
        where Handler: ManualMessageCommandHandler {
        let built = try contextMenuFamily(metadata: handler.command, type: .message, source: source,
            policy: .string("manual"), execute: { context, data in
                let target = try contextMenuMessageTarget(data)
                try Task.checkCancellation()
                try await handler.execute(context, target: target)
            })
        family = built
        declaration = family.declaration(id: id, source: source)
    }

    /// Captures the caller coordinate while constructing manual message behavior.
    /// - Parameters:
    ///   - id: Stable declaration identity validated during compilation.
    ///   - handler: Inert retained behavior; construction performs no user execution or I/O.
    ///   - fileID: Caller source identifier; no file lookup occurs.
    ///   - line: One-based source line, or explicit zero for unavailable.
    ///   - column: One-based source column, or explicit zero for unavailable.
    /// - Throws: The same sanitized registration diagnostics as explicit-source construction.
    public init(id: String, handler: Handler, fileID: String = #fileID, line: UInt = #line,
        column: UInt = #column) throws where Handler: ManualMessageCommandHandler {
        try self.init(id: id, handler: handler, source: .init(fileID: fileID, line: line, column: column))
    }
}

/// Constructs one context-menu definition/route while preserving existing registration validation.
/// - Parameters:
///   - metadata: Captured immutable context-menu settings.
///   - type: Exactly the user or message family selected by the contribution.
///   - source: Bounded diagnostic coordinate.
///   - policy: Inert response policy recorded in structural metadata.
///   - execute: Adapter called only after synchronous envelope/selected-target validation,
///     execution interception and cancellation checks. Its pure target projection preserves typed output.
/// - Returns: A finite family; registration and handler work remain explicitly invoked later.
///   Route preparation admits all selected-target consistency before any execution wrapper can run.
/// - Throws: Sanitized invalid-command diagnostics for malformed metadata. Invocation preparation
///   propagates malformed envelope/target errors without running wrappers or acknowledging.
private func contextMenuFamily(metadata: ContextMenuCommandMetadata, type: ApplicationCommandType,
    source: DefinitionSourceLocation, policy: JSONValue,
    execute: @escaping @Sendable (InteractionContext, InteractionCommandData) async throws -> Void) throws -> CommandFamily {
    let definition: CommandDefinition
    do {
        definition = try .contextMenu(name: metadata.name, type: type,
            nameLocalizations: metadata.nameLocalizations, defaultMemberPermissions: metadata.defaultMemberPermissions,
            integrationTypes: metadata.integrationTypes, contexts: metadata.contexts, nsfw: metadata.nsfw)
    } catch {
        throw CommandCompilationDiagnostic(code: .invalidCommand, commandName: metadata.name, source: source)
    }
    let name = metadata.name
    let route = CommandRoute(key: try .command(name: name, type: type), prepare: { context in
        try Task.checkCancellation()
        guard context.interaction.type.knownValue == .applicationCommand,
              case .value(.command(let data)) = context.interaction.data,
              data.name == name, data.type.knownValue == type,
              case .value = data.targetID else {
            throw CommandCompilationDiagnostic(code: .invalidInvocation, commandName: name, source: source)
        }
        switch data.options {
        case .absent: break
        case .value(let values) where values.isEmpty: break
        default: throw CommandCompilationDiagnostic(code: .invalidInvocation, commandName: name, source: source)
        }
        // Target consistency belongs to complete admission, before any policy or middleware work.
        // The response adapter retains its concrete target type and repeats this pure projection.
        switch type {
        case .user: _ = try contextMenuUserTarget(data)
        case .message: _ = try contextMenuMessageTarget(data)
        default: throw CommandCompilationDiagnostic(code: .invalidInvocation, commandName: name, source: source)
        }
        try Task.checkCancellation()
        return { try await execute(context, data) }
    })
    return CommandFamily(definitions: [definition], routes: [route], metadata: .object(["response": policy]))
}

/// Decodes one selected user without fetching absent resources or assuming complete guild membership.
/// - Parameter data: Completely admitted user command envelope with a required target ID.
/// - Returns: Exact user identity and supplied partial observations, preserving absence/null.
/// - Throws: Sanitized invalid-value for missing IDs or contradictory resolved user/member identities.
private func contextMenuUserTarget(_ data: InteractionCommandData) throws -> UserReference {
    guard case .value(let id) = data.targetID else { throw DiscordError.validation(.invalidValue) }
    let target = try UserReference.decodeArgument(.value(.string(id.description)), resolved: data.resolved)
    if case .value(let member) = target.member, case .value(let supplied) = member.id {
        guard UserID(supplied) == target.id else { throw DiscordError.validation(.invalidValue) }
    }
    return target
}

/// Decodes one partial message target without requiring unrelated complete-message fields.
/// - Parameter data: Completely admitted message command envelope with a required target ID.
/// - Returns: Exact message identity and retained partial resolved projection.
/// - Throws: Sanitized invalid-value for missing target or contradictory partial message identity.
private func contextMenuMessageTarget(_ data: InteractionCommandData) throws -> MessageCommandTarget {
    guard case .value(let id) = data.targetID else { throw DiscordError.validation(.invalidValue) }
    let message: Field<MessageRelatedResource>
    switch data.resolved {
    case .absent: message = .absent
    case .null: message = .null
    case .value(let resolved):
        switch resolved.messages {
        case .absent: message = .absent
        case .null: message = .null
        case .value(let messages): message = messages[id.description].map(Field.value) ?? .absent
        }
    }
    if case .value(let object) = message, case .value(let supplied) = object.id {
        guard MessageID(supplied)?.rawValue == id.rawValue else { throw DiscordError.validation(.invalidValue) }
    }
    return MessageCommandTarget(id: MessageID(rawValue: id.rawValue), message: message)
}

/// Applies family-level response admission before delegating to the exact existing unique responder.
/// - Parameters:
///   - response: Validated response wrapper output; public protocol conformers are checked as well.
///   - context: Exact invocation owner, retaining its deadlines and HTTP/Gateway mechanics.
///   - allowed: Finite callback kinds permitted by the selected handler family.
/// - Throws: Cancellation, invalid-value for an illegal family response, or existing lifecycle/sink failures.
///   No retry, implicit defer, follow-up, timer or detached work is created.
private func sendFamilyResponse(_ response: InteractionResponse, context: InteractionContext,
    allowed: [InteractionCallbackType]) async throws {
    try Task.checkCancellation()
    guard allowed.contains(response.type) else { throw DiscordError.validation(.invalidValue) }
    try await context.responder.respond(response)
}

/// Fully admitted component input, independent of outgoing message component construction.
/// Button input has no selected values; selects retain exact wire order and partial resolved resources.
public struct ComponentInput: Sendable {
    public let componentType: ComponentType
    public let values: [String]
    public let resolved: Field<InteractionResolvedData>

    /// Validates complete button/select input against the handler's explicit expected kind.
    /// - Parameters:
    ///   - data: Exact same-interaction component data, parser-bounded before routing.
    ///   - componentType: One of button, string/user/role/mentionable/channel select.
    /// - Throws: Invalid-value for an empty/oversized custom ID, mismatched/unknown kind, forbidden button values, null values,
    ///   duplicate/excessive/oversized selections, or malformed resource snowflakes. No hydration occurs.
    public init(_ data: InteractionComponentData, componentType: ComponentType) throws {
        guard (1...100).contains(data.customID.unicodeScalars.count),
              data.componentType.knownValue == componentType,
              [2, 3, 5, 6, 7, 8].contains(componentType.rawValue)
        else { throw DiscordError.validation(.invalidValue) }
        let values: [String]
        switch (componentType, data.values) {
        case (.button, .absent): values = []
        case (.button, _): throw DiscordError.validation(.invalidValue)
        case (_, .value(let supplied)): values = supplied
        default: throw DiscordError.validation(.invalidValue)
        }
        guard values.count <= 25, Set(values).count == values.count,
              values.allSatisfy({ $0.unicodeScalars.count <= 100 })
        else { throw DiscordError.validation(.invalidValue) }
        if componentType != .button && componentType != .stringSelect {
            guard values.allSatisfy({ UserID($0) != nil }) else { throw DiscordError.validation(.invalidValue) }
        }
        self.componentType = componentType; self.values = values; resolved = data.resolved
    }
}

/// Explicit acknowledgement policy for deferred component/modal handlers. Message visibility is fixed
/// by the initial callback; update requires an attached source message and never creates a loading message.
public enum DeferredInteractionResponseMode: Sendable, Equatable {
    case message(CommandResponseVisibility)
    case update
}

/// Exact-ID component handler returning one immediate legal component response.
public protocol ComponentHandler: Sendable {
    associatedtype Response: ComponentInitialResponse
    var customID: String {
        /// Returns an exact 1...100-scalar route ID without runtime input interpolation.
        get
    }
    var componentType: ComponentType {
        /// Returns the expected button/select family, captured during contribution construction.
        get
    }
    /// Executes after complete component and source-message admission in the caller's task.
    /// - Parameters:
    ///   - context: Immutable invocation without acknowledgement authority.
    ///   - input: Typed button/select values and retained resolved resources; never hydrated.
    /// - Returns: A validated new message, source-message update, or modal.
    /// - Throws: Application failure/cancellation without fallback, retry or implicit defer.
    func execute(_ context: CommandContext, input: ComponentInput) async throws -> Response
}

/// Exact-ID component handler whose explicit defer succeeds before user work starts.
public protocol DeferredComponentHandler: Sendable {
    var customID: String {
        /// Returns the exact bounded route identifier without work.
        get
    }
    var componentType: ComponentType {
        /// Returns the explicit expected button/select kind without I/O.
        get
    }
    var responseMode: DeferredInteractionResponseMode {
        /// Returns the fixed message/update defer policy captured during contribution construction.
        get
    }
    /// Completes the confirmed explicit defer with one original-message edit.
    /// - Parameters:
    ///   - context: Immutable snapshot without response authority after a confirmed defer.
    ///   - input: Completely validated component input, never hydrated.
    /// - Returns: A JSON-only original edit; update-mode edits must use deferredResponse false.
    /// - Throws: Application failure or cancellation while preserving the confirmed initial response.
    func execute(_ context: DeferredCommandContext, input: ComponentInput) async throws -> DeferredMessageResponse
}

public extension DeferredComponentHandler {
    /// Uses a public loading message unless the author explicitly selects another defer policy.
    var responseMode: DeferredInteractionResponseMode { .message(.public) }
}

/// Exact-ID component handler retaining explicit low-level response ownership.
public protocol ManualComponentHandler: Sendable {
    var customID: String {
        /// Returns the exact bounded route identifier without starting work.
        get
    }
    var componentType: ComponentType {
        /// Returns the expected known button/select kind, captured once.
        get
    }
    /// Runs manual behavior only after complete input and source-message admission.
    /// - Parameters:
    ///   - context: Existing normalized owner; acknowledgement is entirely explicit.
    ///   - input: Completely validated component input and partial observations.
    /// - Throws: Application failure/cancellation without automatic response or retry.
    func execute(_ context: InteractionContext, input: ComponentInput) async throws
}

/// Exact-ID modal submission handler with finite typed fields and a restricted response family.
public protocol ModalHandler: Sendable {
    associatedtype Values: ModalValues
    associatedtype Response: ModalInitialResponse
    var customID: String {
        /// Returns the exact bounded modal namespace identifier without work.
        get
    }
    /// Executes after full tree/schema admission and required source-message validation.
    /// - Parameters:
    ///   - context: Immutable normalized snapshot without acknowledgement authority.
    ///   - values: Fresh typed field aggregate; malformed or undeclared input never reaches this method.
    /// - Returns: A new message or legal source-message update; opening another modal is excluded.
    /// - Throws: Application error or cancellation without implicit defer, fallback or retry.
    func execute(_ context: CommandContext, values: Values) async throws -> Response
}

/// Exact-ID modal submission with an explicitly confirmed defer before user execution.
public protocol DeferredModalHandler: Sendable {
    associatedtype Values: ModalValues
    var customID: String {
        /// Returns the exact bounded modal namespace identifier without I/O.
        get
    }
    var responseMode: DeferredInteractionResponseMode {
        /// Returns fixed loading-message or source-update acknowledgement semantics.
        get
    }
    /// Returns the original-message edit after full admission and a confirmed explicit defer.
    /// - Parameters:
    ///   - context: Immutable snapshot without response authority after acknowledgement succeeds.
    ///   - values: Invocation-local typed values decoded before any acknowledgement.
    /// - Returns: Validated original edit; update mode uses deferredResponse false.
    /// - Throws: Application failure/cancellation, preserving confirmed acknowledgement ownership.
    func execute(_ context: DeferredCommandContext, values: Values) async throws -> DeferredMessageResponse
}

public extension DeferredModalHandler {
    /// Uses a public loading message unless the handler explicitly requests another policy.
    var responseMode: DeferredInteractionResponseMode { .message(.public) }
}

/// Exact-ID modal behavior retaining explicit low-level acknowledgement ownership.
public protocol ManualModalHandler: Sendable {
    associatedtype Values: ModalValues
    var customID: String {
        /// Returns the exact bounded modal identifier without runtime capture.
        get
    }
    /// Executes manual behavior after complete modal tree and typed-field admission.
    /// - Parameters:
    ///   - context: Existing exact invocation response owner; no automatic defer occurs.
    ///   - values: Fresh invocation-local values, completely validated before entry.
    /// - Throws: Application failure/cancellation without automatic responses or retries.
    func execute(_ context: InteractionContext, values: Values) async throws
}

/// A finite exact-ID component contribution. Construction captures schema/policy but performs no handler work.
public struct ComponentCommand<Handler: Sendable>: CommandFamilyContribution {
    public let family: CommandFamily
    public let declaration: RawDefinitionContribution

    /// Captures immediate component behavior without starting tasks or acknowledging input.
    /// - Parameters:
    ///   - id: Stable declaration identity validated by structural compilation.
    ///   - handler: Inert behavior; exact ID, schema/kind and response policy are captured synchronously.
    ///   - source: Diagnostic source coordinate retained without file access.
    /// - Throws: Invalid-value for invalid IDs/kinds/schema or sanitized compilation errors.
    public init(id: String, handler: Handler, source: DefinitionSourceLocation) throws
        where Handler: ComponentHandler {
        family = try componentFamily(customID: handler.customID, componentType: handler.componentType,
            source: source, policy: .string("immediate")) { context, input in
                try Task.checkCancellation()
                let response = try await handler.execute(CommandContext(context), input: input)
                try await sendFamilyResponse(response.interactionResponse, context: context,
                    allowed: [.channelMessageWithSource, .updateMessage, .modal])
            }
        declaration = family.declaration(id: id, source: source)
    }

    /// Captures the caller coordinate for immediate component construction.
    /// - Parameters:
    ///   - id: Stable declaration identity, validated during compilation.
    ///   - handler: Inert retained behavior; construction never executes it.
    ///   - fileID: Caller compiler source identifier, retained without file lookup.
    ///   - line: One-based source line; zero marks unavailable.
    ///   - column: One-based source column; zero marks unavailable.
    /// - Throws: The same metadata/schema diagnostics as explicit-source construction.
    public init(id: String, handler: Handler, fileID: String = #fileID, line: UInt = #line,
        column: UInt = #column) throws where Handler: ComponentHandler {
        try self.init(id: id, handler: handler, source: .init(fileID: fileID, line: line, column: column))
    }

    /// Captures deferred component behavior without starting tasks or acknowledging input.
    /// - Parameters:
    ///   - id: Stable declaration identity validated by structural compilation.
    ///   - handler: Inert behavior; exact ID, schema/kind and response policy are captured synchronously.
    ///   - source: Diagnostic source coordinate retained without file access.
    /// - Throws: Invalid-value for invalid IDs/kinds/schema or sanitized compilation errors.
    public init(id: String, handler: Handler, source: DefinitionSourceLocation) throws
        where Handler: DeferredComponentHandler {
        let mode = handler.responseMode
        family = try componentFamily(customID: handler.customID, componentType: handler.componentType,
            source: source, policy: deferredFamilyMetadata(mode)) { context, input in
                try await acknowledgeFamilyDefer(mode, context: context)
                try Task.checkCancellation()
                let response = try await handler.execute(DeferredCommandContext(context), input: input)
                try Task.checkCancellation()
                _ = try await context.responder.editOriginal(response.edit)
            }
        declaration = family.declaration(id: id, source: source)
    }

    /// Captures the caller coordinate for deferred component construction.
    /// - Parameters:
    ///   - id: Stable declaration identity, validated during compilation.
    ///   - handler: Inert retained behavior; construction never executes it.
    ///   - fileID: Caller compiler source identifier, retained without file lookup.
    ///   - line: One-based source line; zero marks unavailable.
    ///   - column: One-based source column; zero marks unavailable.
    /// - Throws: The same metadata/schema diagnostics as explicit-source construction.
    public init(id: String, handler: Handler, fileID: String = #fileID, line: UInt = #line,
        column: UInt = #column) throws where Handler: DeferredComponentHandler {
        try self.init(id: id, handler: handler, source: .init(fileID: fileID, line: line, column: column))
    }

    /// Captures manual component behavior without starting tasks or acknowledging input.
    /// - Parameters:
    ///   - id: Stable declaration identity validated by structural compilation.
    ///   - handler: Inert behavior; exact ID, schema/kind and response policy are captured synchronously.
    ///   - source: Diagnostic source coordinate retained without file access.
    /// - Throws: Invalid-value for invalid IDs/kinds/schema or sanitized compilation errors.
    public init(id: String, handler: Handler, source: DefinitionSourceLocation) throws
        where Handler: ManualComponentHandler {
        family = try componentFamily(customID: handler.customID, componentType: handler.componentType,
            source: source, policy: .string("manual")) { context, input in
                try Task.checkCancellation()
                try await handler.execute(context, input: input)
            }
        declaration = family.declaration(id: id, source: source)
    }

    /// Captures the caller coordinate for manual component construction.
    /// - Parameters:
    ///   - id: Stable declaration identity, validated during compilation.
    ///   - handler: Inert retained behavior; construction never executes it.
    ///   - fileID: Caller compiler source identifier, retained without file lookup.
    ///   - line: One-based source line; zero marks unavailable.
    ///   - column: One-based source column; zero marks unavailable.
    /// - Throws: The same metadata/schema diagnostics as explicit-source construction.
    public init(id: String, handler: Handler, fileID: String = #fileID, line: UInt = #line,
        column: UInt = #column) throws where Handler: ManualComponentHandler {
        try self.init(id: id, handler: handler, source: .init(fileID: fileID, line: line, column: column))
    }
}

/// A finite exact-ID modal contribution. Construction captures schema/policy but performs no handler work.
public struct ModalCommand<Handler: Sendable>: CommandFamilyContribution {
    public let family: CommandFamily
    public let declaration: RawDefinitionContribution

    /// Captures immediate modal behavior without starting tasks or acknowledging input.
    /// - Parameters:
    ///   - id: Stable declaration identity validated by structural compilation.
    ///   - handler: Inert behavior; exact ID, schema/kind and response policy are captured synchronously.
    ///   - source: Diagnostic source coordinate retained without file access.
    /// - Throws: Invalid-value for invalid IDs/kinds/schema or sanitized compilation errors.
    public init(id: String, handler: Handler, source: DefinitionSourceLocation) throws
        where Handler: ModalHandler {
        let schema = try Handler.Values.schema
        family = try modalFamily(customID: handler.customID, schema: schema,
            source: source, requiresMessage: Handler.Response.requiresSourceMessage, policy: .string("immediate")) { context, values in
                try Task.checkCancellation()
                let response = try await handler.execute(CommandContext(context), values: values)
                try await sendFamilyResponse(response.interactionResponse, context: context,
                    allowed: [.channelMessageWithSource, .updateMessage])
            }
        declaration = family.declaration(id: id, source: source)
    }

    /// Captures the caller coordinate for immediate modal construction.
    /// - Parameters:
    ///   - id: Stable declaration identity, validated during compilation.
    ///   - handler: Inert retained behavior; construction never executes it.
    ///   - fileID: Caller compiler source identifier, retained without file lookup.
    ///   - line: One-based source line; zero marks unavailable.
    ///   - column: One-based source column; zero marks unavailable.
    /// - Throws: The same metadata/schema diagnostics as explicit-source construction.
    public init(id: String, handler: Handler, fileID: String = #fileID, line: UInt = #line,
        column: UInt = #column) throws where Handler: ModalHandler {
        try self.init(id: id, handler: handler, source: .init(fileID: fileID, line: line, column: column))
    }

    /// Captures deferred modal behavior without starting tasks or acknowledging input.
    /// - Parameters:
    ///   - id: Stable declaration identity validated by structural compilation.
    ///   - handler: Inert behavior; exact ID, schema/kind and response policy are captured synchronously.
    ///   - source: Diagnostic source coordinate retained without file access.
    /// - Throws: Invalid-value for invalid IDs/kinds/schema or sanitized compilation errors.
    public init(id: String, handler: Handler, source: DefinitionSourceLocation) throws
        where Handler: DeferredModalHandler {
        let mode = handler.responseMode
        let schema = try Handler.Values.schema
        family = try modalFamily(customID: handler.customID, schema: schema,
            source: source, requiresMessage: mode == .update, policy: deferredFamilyMetadata(mode)) { context, values in
                try await acknowledgeFamilyDefer(mode, context: context)
                try Task.checkCancellation()
                let response = try await handler.execute(DeferredCommandContext(context), values: values)
                try Task.checkCancellation()
                _ = try await context.responder.editOriginal(response.edit)
            }
        declaration = family.declaration(id: id, source: source)
    }

    /// Captures the caller coordinate for deferred modal construction.
    /// - Parameters:
    ///   - id: Stable declaration identity, validated during compilation.
    ///   - handler: Inert retained behavior; construction never executes it.
    ///   - fileID: Caller compiler source identifier, retained without file lookup.
    ///   - line: One-based source line; zero marks unavailable.
    ///   - column: One-based source column; zero marks unavailable.
    /// - Throws: The same metadata/schema diagnostics as explicit-source construction.
    public init(id: String, handler: Handler, fileID: String = #fileID, line: UInt = #line,
        column: UInt = #column) throws where Handler: DeferredModalHandler {
        try self.init(id: id, handler: handler, source: .init(fileID: fileID, line: line, column: column))
    }

    /// Captures manual modal behavior without starting tasks or acknowledging input.
    /// - Parameters:
    ///   - id: Stable declaration identity validated by structural compilation.
    ///   - handler: Inert behavior; exact ID, schema/kind and response policy are captured synchronously.
    ///   - source: Diagnostic source coordinate retained without file access.
    /// - Throws: Invalid-value for invalid IDs/kinds/schema or sanitized compilation errors.
    public init(id: String, handler: Handler, source: DefinitionSourceLocation) throws
        where Handler: ManualModalHandler {
        let schema = try Handler.Values.schema
        family = try modalFamily(customID: handler.customID, schema: schema,
            source: source, requiresMessage: false, policy: .string("manual")) { context, values in
                try Task.checkCancellation()
                try await handler.execute(context, values: values)
            }
        declaration = family.declaration(id: id, source: source)
    }

    /// Captures the caller coordinate for manual modal construction.
    /// - Parameters:
    ///   - id: Stable declaration identity, validated during compilation.
    ///   - handler: Inert retained behavior; construction never executes it.
    ///   - fileID: Caller compiler source identifier, retained without file lookup.
    ///   - line: One-based source line; zero marks unavailable.
    ///   - column: One-based source column; zero marks unavailable.
    /// - Throws: The same metadata/schema diagnostics as explicit-source construction.
    public init(id: String, handler: Handler, fileID: String = #fileID, line: UInt = #line,
        column: UInt = #column) throws where Handler: ManualModalHandler {
        try self.init(id: id, handler: handler, source: .init(fileID: fileID, line: line, column: column))
    }
}

/// Lowers an exact component ID/kind into one inert route with no registration definition.
/// - Parameters:
///   - customID: Exact 1...100-scalar route identifier; prefix matching is never used.
///   - componentType: Supported button/select kind expected by the typed handler.
///   - source: Bounded diagnostic coordinate retained without file access.
///   - policy: Deterministic response policy metadata.
///   - execute: Caller-task adapter invoked after full synchronous component/source-message admission
///     and execution interception. Preparation never runs the handler or sends an acknowledgement.
/// - Returns: Finite route-only family independent of modal IDs with the same text.
/// - Throws: Invalid-value for invalid IDs or unsupported component kinds.
private func componentFamily(customID: String, componentType: ComponentType, source: DefinitionSourceLocation,
    policy: JSONValue, execute: @escaping @Sendable (InteractionContext, ComponentInput) async throws -> Void) throws -> CommandFamily {
    guard [2, 3, 5, 6, 7, 8].contains(componentType.rawValue) else { throw DiscordError.validation(.invalidValue) }
    let route = CommandRoute(key: try .component(customID: customID), prepare: { context in
        try Task.checkCancellation()
        guard context.interaction.type.knownValue == .messageComponent,
              case .value(.component(let data)) = context.interaction.data, data.customID == customID,
              case .value = context.interaction.message else {
            throw CommandCompilationDiagnostic(code: .invalidInvocation, commandName: "component", source: source)
        }
        let input = try ComponentInput(data, componentType: componentType)
        try Task.checkCancellation()
        return { try await execute(context, input) }
    })
    return CommandFamily(routes: [route], metadata: .object(["custom_id": .string(customID),
        "component_type": .number(try JSONNumber(rawValue: String(componentType.rawValue))), "response": policy]))
}

/// Lowers one exact modal ID/schema into a route-only family without opening a modal or registering commands.
/// - Parameters:
///   - customID: Exact bounded modal identifier, separate from the component namespace.
///   - schema: Finite typed field schema captured once at construction.
///   - source: Bounded diagnostic coordinate.
///   - requiresMessage: Whether this response policy requires a source message before user work.
///   - policy: Deterministic explicit response-family metadata.
///   - execute: Adapter invoked only after complete synchronous tree/schema/source-message admission
///     and execution interception. Preparation never acknowledges or executes user behavior.
/// - Returns: An inert exact route and deterministic field description.
/// - Throws: Invalid-value for invalid custom IDs; invocation decoding errors occur only during routing.
private func modalFamily<Values: Sendable>(customID: String, schema: ModalSchema<Values>,
    source: DefinitionSourceLocation, requiresMessage: Bool, policy: JSONValue,
    execute: @escaping @Sendable (InteractionContext, Values) async throws -> Void) throws -> CommandFamily {
    let route = CommandRoute(key: try .modal(customID: customID), prepare: { context in
        try Task.checkCancellation()
        guard context.interaction.type.knownValue == .modalSubmit,
              case .value(.modal(let data)) = context.interaction.data, data.customID == customID else {
            throw CommandCompilationDiagnostic(code: .invalidInvocation, commandName: "modal", source: source)
        }
        if requiresMessage {
            guard case .value = context.interaction.message else { throw InteractionLifecycleError.originalResponseUnavailable }
        }
        let values = try schema.decode(data)
        try Task.checkCancellation()
        return { try await execute(context, values) }
    })
    return CommandFamily(routes: [route], metadata: .object(["custom_id": .string(customID),
        "fields": schema.metadata, "requires_message": .bool(requiresMessage), "response": policy]))
}

/// Describes explicit deferred policy without acknowledging or running behavior.
/// - Parameter mode: Fixed loading-message visibility or source-update acknowledgement.
/// - Returns: Deterministic bounded JSON policy metadata.
private func deferredFamilyMetadata(_ mode: DeferredInteractionResponseMode) -> JSONValue {
    switch mode {
    case .message(let visibility): .object(["deferred_message": .string(visibility == .ephemeral ? "ephemeral" : "public")])
    case .update: .string("deferred_update")
    }
}

/// Confirms an explicit defer through the existing unique responder before user work starts.
/// - Parameters:
///   - mode: Captured message/update acknowledgement policy.
///   - context: Exact normalized response owner, retaining deadlines, admission and receipt mode.
/// - Throws: Existing cancellation, compatibility, admission or delivery failures; no retry or fallback occurs.
private func acknowledgeFamilyDefer(_ mode: DeferredInteractionResponseMode, context: InteractionContext) async throws {
    switch mode {
    case .message(let visibility): try await context.responder.deferResponse(ephemeral: visibility == .ephemeral)
    case .update: try await context.responder.deferUpdate()
    }
}
