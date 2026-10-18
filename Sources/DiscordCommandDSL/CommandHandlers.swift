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

/// Explicit handwritten slash behavior with manual response ownership. A separate immutable
/// argument value is decoded before every invocation. The existing responder owns acknowledgement,
/// deadlines and HTTP/Gateway delivery; this protocol neither defers nor sends a response implicitly.
/// Typed response families, autocomplete, subcommands and application hosting are later milestones.
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

/// A root slash declaration lowered once from a single typed schema and handler. Constructor
/// validation performs synchronous authoring work only; execution starts solely through a router.
public struct SlashCommand<Handler: ManualSlashCommandHandler>: CommandContribution {
    public let declaration: RawDefinitionContribution
    public let definition: CommandDefinition
    public let route: CommandRoute

    /// Captures a schema and builds matching registration/route snapshots without invoking the handler.
    /// - Parameters:
    ///   - id: Globally unique declaration identity, validated by structural compilation.
    ///   - handler: Immutable, Sendable behavior; metadata/schema access must remain finite and inert.
    ///   - source: Authoring coordinate retained for bounded diagnostics and structural accounting.
    /// - Throws: `ArgumentDiagnostic` for invalid schemas/defaults, contextualized with this command;
    ///   `CommandCompilationDiagnostic` for invalid command metadata. No partial contribution escapes.
    public init(id: String, handler: Handler, source: DefinitionSourceLocation) throws {
        let metadata = handler.command
        let schema: CommandArgumentSchema<Handler.Arguments>
        do {
            schema = try Handler.Arguments.schema
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
            try await handler.execute(context, arguments: arguments)
        }
        declaration = RawDefinitionContribution(id: id, kind: CommandCompilation.contributionKind,
            payload: .object(["registration": definition.request.jsonValue(), "arguments": schema.metadata]), source: source)
    }

    /// Captures the caller coordinate while validating one handwritten root slash contribution.
    /// - Parameters:
    ///   - id: Stable declaration identity, admitted during structural compilation.
    ///   - handler: Inert Sendable behavior whose schema and metadata are captured once now.
    ///   - fileID: Caller file identifier; no filesystem access occurs.
    ///   - line: One-based caller line, or explicit zero for unknown.
    ///   - column: One-based caller column, or explicit zero for unknown.
    /// - Throws: The same schema/command diagnostics as the explicit-source initializer.
    public init(id: String, handler: Handler, fileID: String = #fileID, line: UInt = #line,
        column: UInt = #column) throws {
        try self.init(id: id, handler: handler, source: .init(fileID: fileID, line: line, column: column))
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
    ///   autocomplete registration, or mismatched route. Later command families require their own adapters.
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
