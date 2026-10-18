import DiscordCommands
import DiscordCore
import DiscordDSL

/// A bounded lowering failure. Submitted values and underlying codec errors are never retained.
public struct CommandCompilationDiagnostic: Error, Sendable, Equatable {
    public enum Code: Sendable, Equatable {
        case invalidCommand
        case duplicateRoute
        case unsupportedContribution
        case invalidInvocation
    }
    public let code: Code
    /// At most 128 Unicode scalars of command metadata, never invocation argument content.
    public let commandName: String
    /// At most 256 Unicode scalars of an untrusted source label; no filesystem lookup occurs.
    public let source: DefinitionSourceLocation

    /// Retains bounded context for a single failure without logging or reading source files.
    /// - Parameters:
    ///   - code: Stable failure category.
    ///   - commandName: Author metadata, truncated to 128 Unicode scalars.
    ///   - source: Coordinate whose label is truncated to 256 Unicode scalars.
    public init(code: Code, commandName: String, source: DefinitionSourceLocation) {
        self.code = code
        self.commandName = String(commandName.unicodeScalars.prefix(128))
        self.source = .init(fileID: String(source.fileID.unicodeScalars.prefix(256)),
            line: source.line, column: source.column)
    }
}

/// A public extension point for existing root slash definitions/routes. Custom implementations
/// must expose deterministic, inert snapshots agreeing with their raw declaration. Compilation
/// checks the pair through `ExistingSlashCommand`; arbitrary user accessors must terminate cooperatively.
public protocol CommandContribution: DefinitionContribution {
    var definition: CommandDefinition {
        /// Returns the validated immutable root registration without registering or executing it.
        get
    }
    var route: CommandRoute {
        /// Returns its exact manual route without invoking the retained handler.
        get
    }
}

/// Finite ordered command output, independent of any transport, application host or registration.
/// Reuse the router created from this plan across workers that need one aggregate handler bound.
public struct CompiledCommands: Sendable {
    public let description: DefinitionDescription
    public let definitions: [CommandDefinition]
    public let routes: [CommandRoute]

    /// Assembles validated lowering output after all contributions have passed admission.
    /// - Parameters:
    ///   - description: Bounded structural metadata in deterministic source order.
    ///   - definitions: Matching validated registrations in declaration order.
    ///   - routes: Unique exact routes aligned with the definitions.
    fileprivate init(description: DefinitionDescription, definitions: [CommandDefinition], routes: [CommandRoute]) {
        self.description = description
        self.definitions = definitions
        self.routes = routes
    }

    /// Creates an existing bounded router without starting tasks, registering or invoking handlers.
    /// - Parameter maximumConcurrentHandlers: Positive aggregate active-handler bound, default 64;
    ///   excess invocations fail immediately with no implicit queue.
    /// - Returns: Independently owned router. Construction is inert; call its route method explicitly.
    /// - Throws: Existing router validation for nonpositive concurrency. Structural admission already
    ///   bounds route count/text; the router adopts those exact counts without imposing a smaller default.
    public func makeRouter(maximumConcurrentHandlers: Int = 64) throws -> CommandRouter {
        try CommandRouter(routes: routes, maximumRoutes: max(1, routes.count),
            maximumRouteTextBytes: max(1, description.textBytes),
            maximumConcurrentHandlers: maximumConcurrentHandlers)
    }
}

/// Synchronous command lowering over the shared structural collector. No reflection, macro,
/// network work, handler invocation, registration or response policy is introduced here.
public enum CommandCompilation {
    public static let contributionKind = "discord.slash-command"

    /// Collects finite modules and lowers admitted root slash contributions in source order.
    /// - Parameters:
    ///   - definition: Finite synchronous builder/module/contribution structure; injected Swift code
    ///     must terminate and remain free of side effects. Constructors have already validated schemas.
    ///   - limits: Shared module/depth/declaration/text/node bounds, including full registration JSON.
    /// - Returns: Immutable registration/route output with one source of typed command metadata.
    /// - Throws: Structural diagnostics, duplicate-route/unsupported-contribution diagnostics, invalid
    ///   third-party snapshot pairs, or custom collector failures. No partially lowered plan escapes.
    public static func compile<Definition: BotDefinition>(_ definition: Definition,
        limits: DefinitionLimits = .init()) throws -> CompiledCommands {
        let plan = try DefinitionPlan.compile(definition, supportedKinds: [contributionKind], limits: limits)
        var definitions: [CommandDefinition] = []
        var routes: [CommandRoute] = []
        var keys: Set<CommandRouteKey> = []
        for (index, contribution) in plan.contributions.enumerated() {
            let metadata = plan.description.declarations[index].declaration
            guard let command = contribution as? any CommandContribution else {
                throw CommandCompilationDiagnostic(code: .unsupportedContribution,
                    commandName: "", source: metadata.source)
            }
            // Capture each public accessor once and verify the stored collector snapshot agrees.
            let definition = command.definition
            let route = command.route
            let registration: JSONValue
            if case .object(let fields) = metadata.payload, let nested = fields["registration"] {
                registration = nested
            } else { registration = metadata.payload }
            guard definition.request.jsonValue() == registration else {
                throw CommandCompilationDiagnostic(code: .invalidCommand,
                    commandName: definition.request.name, source: metadata.source)
            }
            _ = try ExistingSlashCommand(id: metadata.id, definition: definition, route: route, source: metadata.source)
            guard keys.insert(route.key).inserted else {
                throw CommandCompilationDiagnostic(code: .duplicateRoute,
                    commandName: definition.request.name, source: metadata.source)
            }
            definitions.append(definition)
            routes.append(route)
        }
        return CompiledCommands(description: plan.description, definitions: definitions, routes: routes)
    }
}
