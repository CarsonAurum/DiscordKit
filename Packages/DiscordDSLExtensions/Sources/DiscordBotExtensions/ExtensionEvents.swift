import DiscordBotDSL
import DiscordDSL
import DiscordGateway
import DiscordModels

/// Exact Sendable event services; the caller supplies lifetimes, actors and termination ownership.
public struct ExtensionEventDependencies: ModuleDependencies {
    public let ready: @Sendable () async throws -> Void
    public let stop: @Sendable () async throws -> Void

    /// Captures explicit callbacks without running them, subscribing or creating a client.
    /// - Parameters:
    ///   - ready: Called once for each admitted READY dispatch in the existing event pipeline.
    ///   - stop: Called for the exact synthetic OFFLINE_STOP event; may request nonjoining host stop.
    public init(ready: @escaping @Sendable () async throws -> Void,
        stop: @escaping @Sendable () async throws -> Void) { self.ready = ready; self.stop = stop }

    /// Accepts statically required callbacks without invoking them or inspecting captured actor state.
    /// This contract has no optional services or configuration requiring additional runtime validation.
    public func validate() throws {}
}

/// A separately compiled custom typed selector and handler over the existing decoded READY projection.
public struct ExtensionReadyHandler: GatewayEventHandler {
    public let handlerID = "ready"
    public let dependencies: ExtensionEventDependencies
    /// Retains the existing READY payload while proving public custom-selector extensibility.
    public var selector: GatewayEventSelector<GatewayReady> {
        .init(id: "external.ready") { dispatch in
            guard case .ready(let ready) = dispatch else { return nil }
            return ready
        }
    }

    /// Captures explicitly injected callback services without performing any work.
    /// - Parameter dependencies: The exact immutable contract shared by this module's handlers.
    public init(dependencies: ExtensionEventDependencies) { self.dependencies = dependencies }

    /// Delivers the existing decoded event through caller-owned callback and cancellation semantics.
    /// - Parameters:
    ///   - event: Partial existing READY model; no hydration or additional protocol support is inferred.
    ///   - context: Exact original shard provenance; no service authorization is inferred from it.
    /// - Throws: Cooperative cancellation or the injected callback's original error, without replay.
    public func handle(_ event: GatewayReady, context: GatewayEventContext) async throws {
        try Task.checkCancellation()
        try await dependencies.ready()
    }
}

/// A future-event escape hatch that only recognizes the independent consumer's exact completion fixture.
public struct ExtensionStopHandler: GatewayEventHandler {
    public let handlerID = "stop"
    public let selector = GatewayEventSelector<GatewayUnknownEvent>.unknown
    public let dependencies: ExtensionEventDependencies

    /// Captures the host-owned nonjoining stop callback without selecting or starting a runtime.
    /// - Parameter dependencies: Exact required callback contract; no ambient lookup is performed.
    public init(dependencies: ExtensionEventDependencies) { self.dependencies = dependencies }

    /// Requests stop only for the explicit synthetic event name; unrelated future events are ignored.
    /// - Parameters:
    ///   - event: Lossless unknown dispatch, never used as command authentication evidence.
    ///   - context: Original bounded shard metadata; intentionally unused by this exact-name filter.
    /// - Throws: Cooperative cancellation or the injected stop callback's original failure.
    public func handle(_ event: GatewayUnknownEvent, context: GatewayEventContext) async throws {
        try Task.checkCancellation()
        guard event.name == "OFFLINE_STOP" else { return }
        try await dependencies.stop()
    }
}

/// An imported reusable event module that owns declarations while the existing host owns runtime work.
public struct ExtensionEvents: BotModule {
    public let moduleID: String
    public let dependencies: ExtensionEventDependencies

    /// Captures stable identity and typed callbacks with no execution, registration, subscriptions or I/O.
    /// - Parameters:
    ///   - id: Author-supplied stable module identity within its explicit namespace.
    ///   - dependencies: Required callbacks sharing the caller's exact actor and host authorities.
    public init(id: String, dependencies: ExtensionEventDependencies) { moduleID = id; self.dependencies = dependencies }

    /// Validates dependencies before collecting custom READY and exact unknown-event handlers in order.
    @BotBuilder public var body: some BotDefinition {
        DependentModule(id: "event-dependencies", dependencies: dependencies) { dependencies in
            ExtensionReadyHandler(dependencies: dependencies)
            ExtensionStopHandler(dependencies: dependencies)
        }
    }
}
