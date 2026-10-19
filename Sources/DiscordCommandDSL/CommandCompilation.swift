import DiscordCommands
import DiscordCore
import DiscordDSL
import DiscordModels

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
/// checks the exact root registration/route pair; arbitrary user accessors must terminate cooperatively.
public protocol CommandContribution: DefinitionContribution {
    var definition: CommandDefinition {
        /// Returns the validated immutable root registration without registering or executing it.
        get
    }
    var route: CommandRoute {
        /// Returns its exact response-family route without invoking the retained handler.
        get
    }
}

/// Extension point for finite registration and route families. Snapshots must remain deterministic
/// and inert; compilation checks their exact metadata before adopting any retained behavior.
public protocol CommandFamilyContribution: DefinitionContribution {
    var family: CommandFamily {
        /// Returns immutable registrations and routes without running handlers or performing I/O.
        get
    }
}

/// An inert finite family, including route-only component/modal/autocomplete handlers. Registration
/// definitions and exact route identities share structural text admission and deterministic ordering.
public struct CommandFamily: Sendable {
    public let definitions: [CommandDefinition]
    public let routes: [CommandRoute]
    private let authorMetadata: JSONValue
    internal let autocompleteReferences: [AutocompleteRegistrationReference]

    /// Captures validated values without registration, handler execution, tasks or I/O.
    /// - Parameters:
    ///   - definitions: Root registrations in source order; empty for route-only families.
    ///   - routes: Exact handlers in source order; empty for Discord-owned entry-point registration.
    ///   - metadata: Finite additional author metadata, counted in structural byte/node admission.
    ///   - autocompleteReferences: Captured partial schemas verified against registered leaf options.
    internal init(definitions: [CommandDefinition] = [], routes: [CommandRoute],
        metadata: JSONValue = .object([:]), autocompleteReferences: [AutocompleteRegistrationReference] = []) {
        self.definitions = definitions
        self.routes = routes
        authorMetadata = metadata
        self.autocompleteReferences = autocompleteReferences
    }

    /// Complete deterministic author snapshot; it contains no closure or submitted interaction values.
    internal var snapshot: JSONValue {
        .object(["registrations": .array(definitions.map { $0.request.jsonValue() }),
            "routes": .array(routes.map { $0.key.metadata }), "metadata": authorMetadata,
            "autocomplete_references": .array(autocompleteReferences.map { reference in
                .object(["key": reference.key.metadata, "options": .array(reference.options.map { $0.jsonValue() })])
            })])
    }

    /// Describes every retained registration and route for shared structural admission.
    /// - Parameters:
    ///   - id: Explicit declaration identity, validated by compilation.
    ///   - source: Diagnostic author coordinate; no file is opened.
    /// - Returns: Complete immutable family snapshot with a supported contribution discriminator.
    internal func declaration(id: String, source: DefinitionSourceLocation) -> RawDefinitionContribution {
        .init(id: id, kind: CommandCompilation.familyContributionKind, payload: snapshot, source: source)
    }
}

/// Explicit low-level adoption of existing validated registrations and exact routes. This escape
/// hatch retains existing manual response ownership. Global compilation validates complete registration
/// coverage, duplicate identities, exact routes and autocomplete references across all contributions.
public struct ExistingCommandFamily: CommandFamilyContribution {
    public let declaration: RawDefinitionContribution
    public let family: CommandFamily

    /// Retains an inert finite snapshot without invoking handlers or checking remote registrations.
    /// - Parameters:
    ///   - id: Stable declaration identity, admitted by structural compilation.
    ///   - definitions: Root registrations, default empty for route-only component/modal handlers.
    ///   - routes: Exact existing manual routes, default empty for Discord-owned launch entry points.
    ///   - source: Explicit author coordinate, or nil to capture compiler defaults.
    ///   - fileID: Caller identifier when source is nil; no file access occurs.
    ///   - line: One-based caller line when source is nil; zero means unknown.
    ///   - column: One-based caller column when source is nil; zero means unknown.
    public init(id: String, definitions: [CommandDefinition] = [], routes: [CommandRoute] = [],
        source: DefinitionSourceLocation? = nil, fileID: String = #fileID,
        line: UInt = #line, column: UInt = #column) {
        family = CommandFamily(definitions: definitions, routes: routes)
        declaration = family.declaration(id: id, source: source ?? .init(fileID: fileID, line: line, column: column))
    }
}

/// Finite ordered command output, independent of any transport, application host or registration.
/// Reuse the router created from this plan across workers that need one aggregate handler bound.
public struct CompiledCommands: Sendable {
    public let description: DefinitionDescription
    public let definitions: [CommandDefinition]
    public let routes: [CommandRoute]
    /// Aggregate composition nodes adopted by explicit policy applications; declarations remain unchanged.
    public let policyNodeCount: Int
    /// Number of nested execution wrappers, bounded separately from each expression's depth.
    public let policyDepth: Int

    /// Assembles validated lowering output after all contributions have passed admission.
    /// - Parameters:
    ///   - description: Bounded structural metadata in deterministic source order.
    ///   - definitions: Validated root registrations in declaration order.
    ///   - routes: Unique exact routes in declaration order, including route-only response families.
    ///   - policyNodeCount: Finite aggregate execution-policy nodes; default zero before explicit adoption.
    ///   - policyDepth: Nested execution wrapper depth; default zero for an unmodified catalog.
    internal init(description: DefinitionDescription, definitions: [CommandDefinition], routes: [CommandRoute],
        policyNodeCount: Int = 0, policyDepth: Int = 0) {
        self.description = description
        self.definitions = definitions
        self.routes = routes
        self.policyNodeCount = policyNodeCount
        self.policyDepth = policyDepth
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
/// network work, handler invocation, registration or response-policy execution is introduced here.
public enum CommandCompilation {
    public static let contributionKind = "discord.slash-command"
    public static let familyContributionKind = "discord.command-family"

    /// Collects finite modules and lowers all admitted command/response families in source order.
    /// - Parameters:
    ///   - definition: Finite synchronous builder/module/contribution structure; injected Swift code
    ///     must terminate and remain free of side effects. Constructors have already validated schemas.
    ///   - limits: Shared module/depth/declaration/text/node bounds, including every complete registration
    ///     and exact route snapshot. Definitions and routes are each capped by maxDeclarations as well.
    /// - Returns: Immutable registration/route output with one source of typed command metadata.
    /// - Throws: Structural diagnostics, duplicate-route/unsupported-contribution diagnostics, invalid
    ///   third-party snapshots, missing execution/autocomplete coverage, mismatched partial schemas,
    ///   or custom collector failures. Registration identity includes command type; components/modals
    ///   occupy separate namespaces and never enter registration reconciliation. No partial plan escapes.
    public static func compile<Definition: BotDefinition>(_ definition: Definition,
        limits: DefinitionLimits = .init()) throws -> CompiledCommands {
        let plan = try DefinitionPlan.compile(definition,
            supportedKinds: [contributionKind, familyContributionKind], limits: limits)
        var definitions: [CommandDefinition] = []
        var routes: [CommandRoute] = []
        var keys: Set<CommandRouteKey> = []
        var registrationKeys: Set<CommandRouteKey> = []
        var requiredKeys: Set<CommandRouteKey> = []
        var allowedKeys: Set<CommandRouteKey> = []
        var autocompleteReferences: [AutocompleteRegistrationReference] = []
        for (index, contribution) in plan.contributions.enumerated() {
            let metadata = plan.description.declarations[index].declaration
            let admittedDefinitions: [CommandDefinition]
            let admittedRoutes: [CommandRoute]
            if let command = contribution as? any CommandContribution,
               metadata.kind == contributionKind {
                // Public accessors are captured exactly once after structural snapshot admission.
                let definition = command.definition
                let route = command.route
                let registration: JSONValue
                if case .object(let fields) = metadata.payload, let nested = fields["registration"] {
                    registration = nested
                } else { registration = metadata.payload }
                guard definition.request.jsonValue() == registration,
                      definition.request.type == .chatInput,
                      route.key == (try .command(name: definition.request.name)),
                      !Self.hasContainers(definition.request.jsonValue()) else {
                    throw CommandCompilationDiagnostic(code: .invalidCommand,
                        commandName: definition.request.name, source: metadata.source)
                }
                admittedDefinitions = [definition]
                admittedRoutes = [route]
            } else if let contribution = contribution as? any CommandFamilyContribution,
                      metadata.kind == familyContributionKind {
                let family = contribution.family
                guard family.snapshot == metadata.payload else {
                    throw CommandCompilationDiagnostic(code: .invalidCommand, commandName: "", source: metadata.source)
                }
                admittedDefinitions = family.definitions
                admittedRoutes = family.routes
                autocompleteReferences.append(contentsOf: family.autocompleteReferences)
            } else {
                throw CommandCompilationDiagnostic(code: .unsupportedContribution,
                    commandName: "", source: metadata.source)
            }
            guard admittedRoutes.count <= limits.maxDeclarations - routes.count,
                  admittedDefinitions.count <= limits.maxDeclarations - definitions.count else {
                throw DefinitionDiagnostic(code: .declarationLimit, source: metadata.source,
                    modulePath: plan.description.declarations[index].modulePath)
            }
            for definition in admittedDefinitions {
                let key = try CommandRouteKey.command(name: definition.request.name, type: definition.request.type)
                guard registrationKeys.insert(key).inserted else {
                    throw CommandCompilationDiagnostic(code: .duplicateRoute,
                        commandName: definition.request.name, source: metadata.source)
                }
                let expected = try Self.expectedRoutes(definition)
                requiredKeys.formUnion(expected)
                allowedKeys.formUnion(expected)
                definitions.append(definition)
            }
            for route in admittedRoutes {
                guard keys.insert(route.key).inserted else {
                    throw CommandCompilationDiagnostic(code: .duplicateRoute, commandName: "", source: metadata.source)
                }
                routes.append(route)
            }
        }
        guard requiredKeys.isSubset(of: keys), routes.allSatisfy({ route in
            guard case .object(let fields) = route.key.metadata else { return false }
            return fields["kind"] == .string("3") || fields["kind"] == .string("5") || allowedKeys.contains(route.key)
        }) else {
            throw CommandCompilationDiagnostic(code: .invalidCommand, commandName: "",
                source: plan.description.declarations.first?.declaration.source ?? .init(fileID: "", line: 0, column: 0))
        }
        for reference in autocompleteReferences {
            guard case .object(let key) = reference.key.metadata,
                  case .string(let name) = key["name"], case .array(let path) = key["path"],
                  let definition = definitions.first(where: { $0.request.type == .chatInput && $0.request.name == name }),
                  case .object(let root) = definition.request.jsonValue() else {
                throw CommandCompilationDiagnostic(code: .invalidCommand, commandName: "", source: reference.source)
            }
            var fields = root
            for segment in path {
                guard case .string(let name) = segment, case .array(let children) = fields["options"],
                      let child = children.first(where: { child in
                          guard case .object(let fields) = child else { return false }
                          return fields["name"] == .string(name)
                      }), case .object(let childFields) = child else {
                    throw CommandCompilationDiagnostic(code: .invalidCommand, commandName: name, source: reference.source)
                }
                fields = childFields
            }
            let options = fields["options"] ?? .array([])
            guard options == .array(reference.options.map { $0.jsonValue() }) else {
                throw CommandCompilationDiagnostic(code: .invalidCommand, commandName: name, source: reference.source)
            }
        }
        return CompiledCommands(description: plan.description, definitions: definitions, routes: routes)
    }

    /// Detects structural root options so legacy single-route contributions cannot hide unhandled paths.
    /// - Parameter registration: Validated registration JSON.
    /// - Returns: Whether any root option is a subcommand or group.
    private static func hasContainers(_ registration: JSONValue) -> Bool {
        guard case .object(let fields) = registration, case .array(let options) = fields["options"] else { return false }
        return options.contains { option in
            guard case .object(let fields) = option else { return true }
            return Self.number(fields["type"], equals: "1") ||
                Self.number(fields["type"], equals: "2")
        }
    }

    /// Compares one validated numeric field with an exact small protocol discriminator.
    /// - Parameters:
    ///   - value: Optional retained JSON field; missing or nonnumeric fields do not match.
    ///   - expected: Canonical decimal discriminator from the current protocol.
    /// - Returns: Whether the exact numeric spelling matches the expected discriminator.
    private static func number(_ value: JSONValue?, equals expected: String) -> Bool {
        guard case .number(let number) = value else { return false }
        return number.rawValue == expected
    }

    /// Derives every legal execution and autocomplete key from one existing validated registration.
    /// - Parameter definition: Immutable root request; its model has already bounded depth and siblings.
    /// - Returns: Complete route set; Discord-owned launch entry points intentionally return empty.
    /// - Throws: Existing route-key validation if an impossible inconsistent registration is supplied.
    private static func expectedRoutes(_ definition: CommandDefinition) throws -> Set<CommandRouteKey> {
        let request = definition.request
        if request.type != .chatInput {
            if request.type == .primaryEntryPoint, case .object(let fields) = request.jsonValue(),
               Self.number(fields["handler"], equals: "2") { return [] }
            return [try .command(name: request.name, type: request.type)]
        }
        guard case .object(let fields) = request.jsonValue() else { return [] }
        let options: [JSONValue]
        if case .array(let values) = fields["options"] { options = values } else { options = [] }
        return try leafRoutes(name: request.name, path: [], options: options)
    }

    /// Visits the model-bounded group/subcommand tree and accounts exact leaf execution/focus routes.
    /// - Parameters:
    ///   - name: Validated root slash name.
    ///   - path: Zero through two already validated segments.
    ///   - options: Validated siblings, at most 25, containing either containers or ordinary leaves.
    /// - Returns: Complete exact route identities, including each enabled autocomplete leaf.
    /// - Throws: Route factory validation for inconsistent metadata; no behavior is invoked.
    private static func leafRoutes(name: String, path: [String], options: [JSONValue]) throws -> Set<CommandRouteKey> {
        var result: Set<CommandRouteKey> = []
        var hasChildren = false
        for option in options {
            guard case .object(let fields) = option, case .string(let childName) = fields["name"] else { continue }
            if Self.number(fields["type"], equals: "1") || Self.number(fields["type"], equals: "2") {
                hasChildren = true
                let children: [JSONValue]
                if case .array(let values) = fields["options"] { children = values } else { children = [] }
                result.formUnion(try leafRoutes(name: name, path: path + [childName], options: children))
            } else if fields["autocomplete"] == .bool(true) {
                result.insert(try .autocomplete(name: name, path: path, focusedOption: childName))
            }
        }
        if !hasChildren { result.insert(try .command(name: name, path: path)) }
        return result
    }
}
