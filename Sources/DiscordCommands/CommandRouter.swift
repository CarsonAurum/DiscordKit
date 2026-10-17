import DiscordCore
import DiscordInteractions
import DiscordModels

/// An exact, validated route identity. Command types and subcommand paths never collide,
/// and autocomplete, component and modal namespaces are independent.
public struct CommandRouteKey: Sendable, Hashable {
    private let kind: Int
    private let commandType: Int
    private let name: String
    private let path: [String]
    private let focusedOption: String?

    /// Stores a factory-validated route without additional work or resource ownership.
    /// - Parameters:
    ///   - kind: Internal namespace: 2 command, 3 component, 4 autocomplete or 5 modal.
    ///   - commandType: Known command discriminator, or zero for custom-ID routes.
    ///   - name: Validated command name or exact bounded custom ID.
    ///   - path: Zero, one or two validated subcommand path elements.
    ///   - focusedOption: Required validated leaf name only for autocomplete.
    private init(kind: Int, commandType: Int, name: String, path: [String] = [], focusedOption: String? = nil) {
        self.kind = kind; self.commandType = commandType; self.name = name
        self.path = path; self.focusedOption = focusedOption
    }

    /// Defines an exact command/subcommand route; context-menu and entry-point commands cannot have paths.
    /// - Parameters:
    ///   - name: Valid command name, using the selected type's naming rules.
    ///   - type: Known command kind; defaults to chatInput.
    ///   - path: Empty for a root command, one subcommand, or group followed by subcommand; default empty.
    /// - Returns: Validated identity independent of command ID, registration scope and delivery transport.
    /// - Throws: Invalid-value for invalid names, more than two path segments, or paths on non-slash kinds.
    public static func command(name: String, type: ApplicationCommandType = .chatInput, path: [String] = []) throws -> Self {
        _ = try ApplicationCommandCreate(name: name, type: type,
            description: type == .chatInput || type == .primaryEntryPoint ? "route" : nil)
        guard path.count <= 2, type == .chatInput || path.isEmpty else { throw DiscordError.validation(.invalidValue) }
        for name in path { _ = try ApplicationCommandOptionCreate(type: .subcommand, name: name, description: "route") }
        return Self(kind: 2, commandType: type.rawValue, name: name, path: path)
    }

    /// Defines one focused autocomplete leaf, separate from the corresponding command handler.
    /// - Parameters:
    ///   - name: Valid lowercase slash-command name.
    ///   - path: Root, subcommand, or group/subcommand path, at most two segments; default empty.
    ///   - focusedOption: Exact valid name of the focused string/integer/number leaf.
    /// - Returns: Validated autocomplete key; incomplete values and resolved objects remain available in the context.
    /// - Throws: Invalid-value for invalid names or excessive path depth; no registrations or callbacks occur.
    public static func autocomplete(name: String, path: [String] = [], focusedOption: String) throws -> Self {
        _ = try command(name: name, path: path)
        _ = try ApplicationCommandOptionCreate(type: .string, name: focusedOption, description: "route")
        return Self(kind: 4, commandType: ApplicationCommandType.chatInput.rawValue, name: name,
            path: path, focusedOption: focusedOption)
    }

    /// Defines an exact component custom-ID route; no prefix matching, regex work or input capture occurs.
    /// - Parameter customID: Nonempty identifier of at most 100 Unicode scalars, matching Discord's custom_id limit.
    /// - Returns: A component identity that cannot collide with a modal of the same ID.
    /// - Throws: Invalid-value for empty or oversized identifiers; actual component values are not retained in this key.
    public static func component(customID: String) throws -> Self {
        guard (1...100).contains(customID.unicodeScalars.count) else { throw DiscordError.validation(.invalidValue) }
        return Self(kind: 3, commandType: 0, name: customID)
    }

    /// Defines an exact submitted-modal custom-ID route without routing display-only component embeds.
    /// - Parameter customID: Exact identifier of 1...100 Unicode scalars.
    /// - Returns: Validated modal namespace identity; modal inputs stay on the typed context.
    /// - Throws: Invalid-value for empty or oversized custom IDs.
    public static func modal(customID: String) throws -> Self {
        guard (1...100).contains(customID.unicodeScalars.count) else { throw DiscordError.validation(.invalidValue) }
        return Self(kind: 5, commandType: 0, name: customID)
    }

    /// Accounts retained variable-sized route text before router adoption.
    /// - Returns: UTF-8 name, path and focused-leaf bytes; fixed structure overhead is bounded by maximumRoutes.
    fileprivate func retainedTextBytes() -> Int { name.utf8.count + path.reduce(0) { $0 + $1.utf8.count } + (focusedOption?.utf8.count ?? 0) }

    /// Selects one exact route from a normalized authenticated context without executing application work.
    /// - Parameter interaction: Already authenticated HTTP or trusted Gateway interaction; unknown types are unhandled.
    /// - Returns: Validated route or nil for unsupported, malformed, ambiguous or incomplete command paths/focus.
    ///   Inspection is bounded to three levels of at most 25 siblings; submitted values never become route keys.
    fileprivate static func incoming(_ interaction: Interaction) -> Self? {
        guard case .value(let data) = interaction.data else { return nil }
        switch (interaction.type.knownValue, data) {
        case (.applicationCommand, .command(let command)), (.applicationCommandAutocomplete, .command(let command)):
            guard let type = command.type.knownValue else { return nil }
            var path: [String] = [], options: [InteractionCommandOption]
            if case .value(let supplied) = command.options { options = supplied } else { options = [] }
            for depth in 0...2 {
                guard options.count <= 25, Set(options.map(\.name)).count == options.count else { return nil }
                let containers = options.filter { $0.type.knownValue == .subcommand || $0.type.knownValue == .subcommandGroup }
                guard !containers.isEmpty else { break }
                guard depth < 2, containers.count == 1, options.count == 1,
                      let container = containers.first, container.focused != .value(true),
                      (depth == 0 || container.type.knownValue == .subcommand),
                      !(depth == 1 && path.count == 1 && options.first?.type.knownValue == .subcommandGroup),
                      case .value(let children) = container.options else { return nil }
                if container.type.knownValue == .subcommandGroup {
                    guard children.count == 1, children.first?.type.knownValue == .subcommand else { return nil }
                } else if children.contains(where: { $0.type.knownValue == .subcommand || $0.type.knownValue == .subcommandGroup }) {
                    return nil
                }
                path.append(container.name); options = children
            }
            if interaction.type.knownValue == .applicationCommandAutocomplete {
                let focused = options.filter { $0.focused == .value(true) }
                guard type == .chatInput, focused.count == 1, let leaf = focused.first,
                      [.string, .integer, .number].contains(leaf.type.knownValue) else { return nil }
                return try? autocomplete(name: command.name, path: path, focusedOption: leaf.name)
            }
            return try? self.command(name: command.name, type: type, path: path)
        case (.messageComponent, .component(let component)): return try? self.component(customID: component.customID)
        case (.modalSubmit, .modal(let modal)): return try? self.modal(customID: modal.customID)
        default: return nil
        }
    }
}

/// One exact route and its caller-owned async handler. The context retains its original delivery mechanics.
public struct CommandRoute: Sendable {
    /// Exact validated key; registration does not imply a matching Discord registration exists.
    public let key: CommandRouteKey
    fileprivate let handler: @Sendable (InteractionContext) async throws -> Void

    /// Adopts a handler without executing it, registering a Discord command, or starting background work.
    /// - Parameters:
    ///   - key: Validated command/autocomplete/component/modal identity.
    ///   - handler: Cancellation-cooperative application work. Respond through context.responder;
    ///     errors propagate unchanged and do not trigger an invented acknowledgment or auto-defer.
    ///     Configure explicit auto-defer through the interaction lifecycle when the selected kind permits it.
    public init(key: CommandRouteKey, handler: @escaping @Sendable (InteractionContext) async throws -> Void) {
        self.key = key; self.handler = handler
    }
}

/// Bounded exact routing, independent of DiscordClient and Gateway. Fixed routes cannot grow at runtime.
/// Admission fails immediately when busy; no hidden handler queue or task is created. Share an instance
/// across consumers requiring one aggregate handler bound, and coordinate broader per-identity limits externally.
public actor CommandRouter {
    private let routes: [CommandRouteKey: CommandRoute]
    private let maximumConcurrentHandlers: Int
    private var activeHandlers = 0

    /// Validates fixed route count/text budgets and concurrency without running handlers or network work.
    /// - Parameters:
    ///   - routes: Finite routes with unique exact keys; default no routes. Different namespaces can reuse names.
    ///   - maximumRoutes: Positive route-count cap, default 1024; fixed closure captures remain caller-owned.
    ///   - maximumRouteTextBytes: Positive aggregate retained UTF-8 key budget, default 256 KiB.
    ///   - maximumConcurrentHandlers: Positive total admitted handler cap, default 64; excess callers fail immediately.
    /// - Throws: Invalid-value for invalid bounds or duplicate keys; limitExceeded for route-count/text excess.
    public init(routes: [CommandRoute] = [], maximumRoutes: Int = 1024,
        maximumRouteTextBytes: Int = 262_144, maximumConcurrentHandlers: Int = 64) throws {
        guard maximumRoutes > 0, maximumRouteTextBytes > 0, maximumConcurrentHandlers > 0,
              Set(routes.map(\.key)).count == routes.count else { throw DiscordError.validation(.invalidValue) }
        guard routes.count <= maximumRoutes else { throw DiscordError.validation(.limitExceeded) }
        var bytes = 0
        for route in routes {
            let size = route.key.retainedTextBytes()
            guard size <= maximumRouteTextBytes - bytes else { throw DiscordError.validation(.limitExceeded) }
            bytes += size
        }
        self.routes = Dictionary(uniqueKeysWithValues: routes.map { ($0.key, $0) })
        self.maximumConcurrentHandlers = maximumConcurrentHandlers
    }

    /// Number of currently admitted handlers, including suspended handlers; inspection performs no work.
    public var activeHandlerCount: Int { activeHandlers }

    /// Invokes one matching handler in the caller's task after bounded actor-isolated admission.
    /// - Parameter context: Shared normalized interaction context, authenticated before routing. HTTP and Gateway
    ///   responses retain their distinct mechanics through its responder; this method does not acknowledge automatically.
    /// - Returns: True after a matched handler completes; false for unknown kinds, unmatched keys or ambiguous input paths.
    /// - Throws: Cancellation before admission, limitExceeded at capacity, or the original handler error/cancellation.
    ///   Every completion releases admission, including thrown errors. Suspension is reentrant and concurrency remains bounded.
    public func route(_ context: InteractionContext) async throws -> Bool {
        try Task.checkCancellation()
        guard let key = CommandRouteKey.incoming(context.interaction), let route = routes[key] else { return false }
        guard activeHandlers < maximumConcurrentHandlers else { throw DiscordError.validation(.limitExceeded) }
        activeHandlers += 1
        defer { activeHandlers -= 1 }
        try await route.handler(context)
        return true
    }
}
