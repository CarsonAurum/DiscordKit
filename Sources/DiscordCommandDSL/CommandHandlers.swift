import DiscordCommands
import DiscordCore
import DiscordDSL
import DiscordInteractions
import DiscordModels

/// Registration metadata for a root API v10 slash command. This inert value is validated
/// with the argument schema when a `SlashCommand` contribution is created. Permissions
/// describe registration defaults; they never authorize application work locally.
public struct SlashCommandMetadata: Sendable {
    public let name: String
    public let description: String
    public let nameLocalizations: Field<[String: String]>
    public let descriptionLocalizations: Field<[String: String]>
    public let defaultMemberPermissions: Field<String>
    public let integrationTypes: [ApplicationIntegrationType]?
    public let contexts: [InteractionContextType]?
    public let nsfw: Bool?

    /// Stores registration settings without validation, registration, tasks or I/O.
    /// - Parameters:
    ///   - name: Lowercase command name, validated as 1...32 Unicode scalars at lowering.
    ///   - description: Command explanation, validated as 1...100 scalars at lowering.
    ///   - nameLocalizations: Omitted, explicitly cleared, or complete translated names.
    ///   - descriptionLocalizations: Omitted, cleared, or complete translated explanations.
    ///   - defaultMemberPermissions: Omitted, unrestricted null, or decimal permission bits.
    ///   - integrationTypes: Explicit global installation contexts, or nil to leave unmanaged.
    ///   - contexts: Explicit global invocation contexts, or nil to leave unmanaged.
    ///   - nsfw: Optional age restriction; nil preserves omission.
    public init(name: String, description: String,
        nameLocalizations: Field<[String: String]> = .absent,
        descriptionLocalizations: Field<[String: String]> = .absent,
        defaultMemberPermissions: Field<String> = .absent,
        integrationTypes: [ApplicationIntegrationType]? = nil,
        contexts: [InteractionContextType]? = nil, nsfw: Bool? = nil) {
        self.name = name
        self.description = description
        self.nameLocalizations = nameLocalizations
        self.descriptionLocalizations = descriptionLocalizations
        self.defaultMemberPermissions = defaultMemberPermissions
        self.integrationTypes = integrationTypes
        self.contexts = contexts
        self.nsfw = nsfw
    }
}

/// A root slash handler that returns one immediate message without access to acknowledgement methods.
/// Invocation decodes complete arguments first, runs in the router caller's task, and submits the returned
/// message through the exact existing responder. Long work must adopt `DeferredSlashCommandHandler`
/// explicitly; no timer, implicit defer, retry, fallback response or detached task is introduced here.
public protocol SlashCommandHandler: Sendable {
    associatedtype Arguments: CommandArguments

    /// Immutable root registration metadata, captured once during contribution construction.
    var command: SlashCommandMetadata {
        /// Returns finite metadata without executing handlers, reading credentials or performing I/O.
        get
    }

    /// Produces the sole initial message after validated invocation admission.
    /// - Parameters:
    ///   - context: Interaction snapshot and receipt mode without an exposed response owner.
    ///   - arguments: Fresh invocation-local typed arguments; no hydration or authorization is inferred.
    /// - Returns: A validated JSON-only immediate message. Deferred, modal, autocomplete and manual callbacks
    ///   are different response families and cannot be returned through this protocol.
    /// - Throws: Application failure or cancellation, propagated unchanged without sending a fallback.
    ///   User work must honor cancellation and complete within the existing three-second acknowledgement deadline.
    func execute(_ context: CommandContext, arguments: Arguments) async throws -> MessageResponse
}

/// A typed slash handler that opens one validated modal as its sole immediate callback.
/// Complete arguments are admitted first; no defer, message or low-level response authority is exposed.
public protocol ModalSlashCommandHandler: Sendable {
    associatedtype Arguments: CommandArguments
    var command: SlashCommandMetadata {
        /// Returns immutable inert root or leaf registration metadata without I/O or user execution.
        get
    }

    /// Produces one immediate modal after complete argument validation.
    /// - Parameters:
    ///   - context: Immutable normalized interaction without low-level response authority.
    ///   - arguments: Fresh complete typed values; missing/null/malformed input has already failed.
    /// - Returns: Validated modal callback; its later submit handler is a separate exact route.
    /// - Throws: Application failure or cancellation, propagated without fallback or retry.
    ///   User work must complete within the existing initial acknowledgement deadline.
    func execute(_ context: CommandContext, arguments: Arguments) async throws -> ModalResponse
}

/// A root slash handler whose explicit public/ephemeral loading response is acknowledged before user work.
/// Complete argument validation precedes acknowledgement; successful user work edits the deferred original.
/// This policy never creates a follow-up, extends token life, retries an uncertain mutation or hides failure.
public protocol DeferredSlashCommandHandler: Sendable {
    associatedtype Arguments: CommandArguments

    /// Immutable root registration metadata, captured once during contribution construction.
    var command: SlashCommandMetadata {
        /// Returns finite metadata without executing handlers, reading credentials or performing I/O.
        get
    }

    /// Visibility fixed at the initial acknowledgement; the default is public.
    var responseVisibility: CommandResponseVisibility {
        /// Returns an inert policy value, captured once before constructing the compiled route.
        get
    }

    /// Produces an original-message edit after a confirmed deferred-message acknowledgement.
    /// - Parameters:
    ///   - context: Snapshot and receipt mode without acknowledgement, follow-up or low-level response methods.
    ///   - arguments: Invocation-local typed arguments, completely validated before acknowledgement.
    /// - Returns: Validated JSON-only edit used exactly once to complete the deferred original.
    /// - Throws: Application error or cancellation, propagated unchanged while preserving the confirmed defer.
    ///   User work and injected transports must cooperate with cancellation; continuation expiry stays fifteen minutes.
    func execute(_ context: DeferredCommandContext, arguments: Arguments) async throws -> DeferredMessageResponse
}

extension DeferredSlashCommandHandler {
    /// Uses public visibility unless the handler explicitly requests an ephemeral original.
    public var responseVisibility: CommandResponseVisibility { .public }
}

/// Explicit handwritten slash behavior with manual response ownership. A separate immutable
/// argument value is decoded before every invocation. The existing responder owns acknowledgement,
/// deadlines and HTTP/Gateway delivery; this protocol neither defers nor sends a response implicitly.
public protocol ManualSlashCommandHandler: Sendable {
    associatedtype Arguments: CommandArguments

    /// Stable root registration metadata, read once when constructing the contribution.
    var command: SlashCommandMetadata {
        /// Returns finite metadata without executing handlers, reading credentials or performing I/O.
        get
    }

    /// Executes in the router caller's task after complete argument validation and admission.
    /// - Parameters:
    ///   - context: Authenticated interaction with the original unique response owner. The handler
    ///     must explicitly acknowledge/complete using its responder and honor cancellation.
    ///   - arguments: Invocation-local typed values, including defaults and partial resolved references.
    /// - Throws: Application errors or cancellation, propagated unchanged. No automatic retry, reply,
    ///   mutation replay or hydration occurs; suspension permits the existing router's bounded concurrency.
    func execute(_ context: InteractionContext, arguments: Arguments) async throws
}

/// A root slash declaration lowered from exactly one explicit response-family protocol and argument schema.
/// Constructor validation performs synchronous authoring work only; execution starts through its route.
/// A handler adopting multiple response protocols requires an explicit adapter to remove initializer ambiguity.
public struct SlashCommand<Handler: Sendable>: CommandContribution {
    public let declaration: RawDefinitionContribution
    public let definition: CommandDefinition
    public let route: CommandRoute

    /// Captures a manual schema/route without invoking behavior or taking response ownership.
    /// - Parameters:
    ///   - id: Globally unique declaration identity, validated by structural compilation.
    ///   - handler: Inert immutable behavior that receives the existing low-level response owner on invocation.
    ///   - source: Authoring coordinate retained for bounded diagnostics and structural accounting.
    /// - Throws: Contextualized `ArgumentDiagnostic` for invalid schema/defaults, or
    ///   `CommandCompilationDiagnostic.invalidCommand` for invalid metadata. No partial contribution escapes.
    public init(id: String, handler: Handler, source: DefinitionSourceLocation) throws
        where Handler: ManualSlashCommandHandler {
        try self.init(id: id, metadata: handler.command, source: source, schema: { try Handler.Arguments.schema },
            responsePolicy: .string("manual")) { context, arguments in
                try await handler.execute(context, arguments: arguments)
            }
    }

    /// Captures immediate-message behavior without execution, acknowledgement or network work.
    /// - Parameters:
    ///   - id: Globally unique declaration identity admitted during structural compilation.
    ///   - handler: Inert typed immediate behavior; schema/metadata are captured synchronously once.
    ///   - source: Bounded diagnostic coordinate; no file access occurs.
    /// - Throws: The same schema/metadata diagnostics as manual construction. At invocation, user errors
    ///   propagate and the existing responder enforces the single initial slot and original receipt deadline.
    public init(id: String, handler: Handler, source: DefinitionSourceLocation) throws
        where Handler: SlashCommandHandler {
        try self.init(id: id, metadata: handler.command, source: source, schema: { try Handler.Arguments.schema },
            responsePolicy: .string("immediate")) { context, arguments in
                let response = try await handler.execute(CommandContext(context), arguments: arguments)
                try Task.checkCancellation()
                try await context.responder.reply(response.message)
            }
    }

    /// Captures an immediate modal response without executing handlers or opening UI locally.
    /// - Parameters:
    ///   - id: Explicit stable declaration identity, admitted during compilation.
    ///   - handler: Inert modal-only typed behavior; schema and metadata are captured once.
    ///   - source: Diagnostic coordinate retained without source-file access.
    /// - Throws: Schema/metadata diagnostics. Invocation preserves one initial callback and propagates errors.
    public init(id: String, handler: Handler, source: DefinitionSourceLocation) throws
        where Handler: ModalSlashCommandHandler {
        try self.init(id: id, metadata: handler.command, source: source, schema: { try Handler.Arguments.schema },
            responsePolicy: .string("modal")) { context, arguments in
                let response = try await handler.execute(CommandContext(context), arguments: arguments)
                try Task.checkCancellation()
                try await context.responder.respond(.modal(response.modal))
            }
    }

    /// Captures a caller coordinate for typed immediate modal behavior.
    /// - Parameters:
    ///   - id: Stable declaration identity, admitted during structural compilation.
    ///   - handler: Inert modal handler; construction starts no execution or acknowledgement.
    ///   - fileID: Caller identifier retained without filesystem access.
    ///   - line: Caller one-based line; zero means unavailable.
    ///   - column: Caller one-based column; zero means unavailable.
    /// - Throws: The same authoring diagnostics as explicit-source construction.
    public init(id: String, handler: Handler, fileID: String = #fileID, line: UInt = #line,
        column: UInt = #column) throws where Handler: ModalSlashCommandHandler {
        try self.init(id: id, handler: handler, source: .init(fileID: fileID, line: line, column: column))
    }

    /// Captures explicit deferred-original completion without starting a timer or invoking the handler.
    /// - Parameters:
    ///   - id: Globally unique declaration identity admitted during structural compilation.
    ///   - handler: Inert deferred behavior; visibility, schema and metadata are captured once now.
    ///   - source: Diagnostic coordinate retained without reading source files.
    /// - Throws: Schema/metadata diagnostics during construction. At invocation, acknowledgement failures
    ///   prevent user execution; user/edit failures propagate without follow-up, retry or fallback response.
    public init(id: String, handler: Handler, source: DefinitionSourceLocation) throws
        where Handler: DeferredSlashCommandHandler {
        let visibility = handler.responseVisibility
        try self.init(id: id, metadata: handler.command, source: source, schema: { try Handler.Arguments.schema },
            responsePolicy: .object(["deferred": .string(visibility == .ephemeral ? "ephemeral" : "public")])) {
                context, arguments in
                try await context.responder.deferResponse(ephemeral: visibility == .ephemeral)
                try Task.checkCancellation()
                let response = try await handler.execute(DeferredCommandContext(context), arguments: arguments)
                try Task.checkCancellation()
                _ = try await context.responder.editOriginal(response.edit)
            }
    }

    /// Captures the caller coordinate while validating a manual root slash contribution.
    /// - Parameters:
    ///   - id: Stable declaration identity admitted during structural compilation.
    ///   - handler: Inert manual behavior whose schema and metadata are captured once now.
    ///   - fileID: Caller file identifier, retained without filesystem access.
    ///   - line: One-based caller line; explicit zero marks unavailable.
    ///   - column: One-based caller column; explicit zero marks unavailable.
    /// - Throws: The same contextualized schema/metadata diagnostics as explicit-source construction.
    public init(id: String, handler: Handler, fileID: String = #fileID, line: UInt = #line,
        column: UInt = #column) throws where Handler: ManualSlashCommandHandler {
        try self.init(id: id, handler: handler, source: .init(fileID: fileID, line: line, column: column))
    }

    /// Captures the caller coordinate while validating an immediate-message root slash contribution.
    /// - Parameters:
    ///   - id: Stable declaration identity admitted during structural compilation.
    ///   - handler: Inert immediate behavior; it is retained without running user work or acknowledging.
    ///   - fileID: Caller compiler identifier; no file is read.
    ///   - line: One-based caller line, or explicit zero when unavailable.
    ///   - column: One-based caller column, or explicit zero when unavailable.
    /// - Throws: The same schema/metadata diagnostics as explicit-source construction.
    public init(id: String, handler: Handler, fileID: String = #fileID, line: UInt = #line,
        column: UInt = #column) throws where Handler: SlashCommandHandler {
        try self.init(id: id, handler: handler, source: .init(fileID: fileID, line: line, column: column))
    }

    /// Captures the caller coordinate while validating a deferred-original root slash contribution.
    /// - Parameters:
    ///   - id: Stable declaration identity admitted during structural compilation.
    ///   - handler: Inert deferred behavior; fixed visibility is captured without acknowledgement.
    ///   - fileID: Caller compiler identifier; no filesystem access occurs.
    ///   - line: One-based caller line; zero explicitly indicates unavailable.
    ///   - column: One-based caller column; zero explicitly indicates unavailable.
    /// - Throws: The same schema/metadata diagnostics as explicit-source construction.
    public init(id: String, handler: Handler, fileID: String = #fileID, line: UInt = #line,
        column: UInt = #column) throws where Handler: DeferredSlashCommandHandler {
        try self.init(id: id, handler: handler, source: .init(fileID: fileID, line: line, column: column))
    }

    /// Builds one shared validated registration and exact root route for a concrete response adapter.
    /// - Parameters:
    ///   - id: Stable declaration identity, validated by structural admission.
    ///   - metadata: Captured registration fields; defaults never imply local authorization.
    ///   - source: Coordinate used to contextualize finite compilation/invocation diagnostics.
    ///   - schema: Finite synchronous schema factory invoked once now, never during routing.
    ///   - responsePolicy: Inert deterministic policy metadata, including fixed deferred visibility.
    ///   - execute: Response-family adapter called only after complete validation and cancellation checks.
    /// - Throws: Sanitized contextual schema or command metadata diagnostics; route creation performs no I/O.
    private init<Arguments: CommandArguments>(id: String, metadata: SlashCommandMetadata,
        source: DefinitionSourceLocation, schema makeSchema: () throws -> CommandArgumentSchema<Arguments>,
        responsePolicy: JSONValue,
        execute: @escaping @Sendable (InteractionContext, Arguments) async throws -> Void) throws {
        let schema: CommandArgumentSchema<Arguments>
        do {
            schema = try makeSchema()
            definition = try CommandDefinition.slash(name: metadata.name, description: metadata.description,
                nameLocalizations: metadata.nameLocalizations,
                descriptionLocalizations: metadata.descriptionLocalizations,
                defaultMemberPermissions: metadata.defaultMemberPermissions,
                integrationTypes: metadata.integrationTypes, contexts: metadata.contexts, nsfw: metadata.nsfw) {
                    schema.options
                }
        } catch let diagnostic as ArgumentDiagnostic {
            throw diagnostic.contextualized(commandName: metadata.name)
        } catch {
            throw CommandCompilationDiagnostic(code: .invalidCommand, commandName: metadata.name, source: source)
        }
        let name = metadata.name
        route = CommandRoute(key: try .command(name: name)) { context in
            try Task.checkCancellation()
            guard context.interaction.type.knownValue == .applicationCommand,
                  case .value(.command(let data)) = context.interaction.data,
                  data.name == name, data.type.knownValue == .chatInput else {
                throw CommandCompilationDiagnostic(code: .invalidInvocation, commandName: name, source: source)
            }
            let options: [InteractionCommandOption]
            switch data.options {
            case .absent: options = []
            case .value(let values): options = values
            case .null:
                throw CommandCompilationDiagnostic(code: .invalidInvocation, commandName: name, source: source)
            }
            let arguments = try schema.decode(options: options, resolved: data.resolved, commandName: name)
            try Task.checkCancellation()
            try await execute(context, arguments)
        }
        declaration = RawDefinitionContribution(id: id, kind: CommandCompilation.contributionKind,
            payload: .object(["registration": definition.request.jsonValue(), "arguments": schema.metadata,
                "response": responsePolicy]), source: source)
    }
}

/// Explicit adoption of a previously authored root slash definition and its exact manual route.
/// This adapter performs no typed decoding. Existing low-level validation/response ownership applies.
public struct ExistingSlashCommand: CommandContribution {
    public let declaration: RawDefinitionContribution
    public let definition: CommandDefinition
    public let route: CommandRoute

    /// Validates root slash identity and retains the supplied low-level pair without running work.
    /// - Parameters:
    ///   - id: Stable declaration ID, admitted by the structural compiler.
    ///   - definition: Validated chat-input registration with leaf options only and no autocomplete.
    ///   - route: Exact root command route with the same name/type as the registration.
    ///   - source: Diagnostic coordinate for invalid adapters and duplicate routes.
    /// - Throws: `CommandCompilationDiagnostic.invalidCommand` for another command kind, subcommand,
    ///   autocomplete registration, or mismatched route. Structured command families require their own adapters.
    public init(id: String, definition: CommandDefinition, route: CommandRoute,
        source: DefinitionSourceLocation) throws {
        let name = definition.request.name
        guard definition.request.type == .chatInput,
              route.key == (try .command(name: name)),
              case .object(let fields) = definition.request.jsonValue() else {
            throw CommandCompilationDiagnostic(code: .invalidCommand, commandName: name, source: source)
        }
        if case .array(let options) = fields["options"] {
            for option in options {
                guard case .object(let fields) = option,
                      case .number(let type) = fields["type"],
                      let value = Int(type.rawValue), value >= 3,
                      fields["autocomplete"] != .bool(true) else {
                    throw CommandCompilationDiagnostic(code: .invalidCommand, commandName: name, source: source)
                }
            }
        }
        self.definition = definition
        self.route = route
        declaration = RawDefinitionContribution(id: id, kind: CommandCompilation.contributionKind,
            payload: definition.request.jsonValue(), source: source)
    }

    /// Captures the caller coordinate while adopting a validated existing root slash pair.
    /// - Parameters:
    ///   - id: Stable declaration identity, admitted during compilation.
    ///   - definition: Root chat-input registration with leaf options and no autocomplete.
    ///   - route: Exact root manual route matching the registration name and kind.
    ///   - fileID: Compiler caller identifier, retained without reading a file.
    ///   - line: One-based caller line; explicit zero marks unavailable.
    ///   - column: One-based caller column; explicit zero marks unavailable.
    /// - Throws: Invalid-command diagnostics from the explicit-source initializer.
    public init(id: String, definition: CommandDefinition, route: CommandRoute,
        fileID: String = #fileID, line: UInt = #line, column: UInt = #column) throws {
        try self.init(id: id, definition: definition, route: route,
            source: .init(fileID: fileID, line: line, column: column))
    }
}
