import DiscordCore
import DiscordDSL
import DiscordGateway
import DiscordModels

/// One bounded event-compilation failure without event data, credentials or arbitrary diagnostics.
public struct EventCompilationDiagnostic: Error, Sendable, Equatable {
    /// Stable failure categories; structural failures retain the shared `DefinitionDiagnostic` type.
    public enum Code: Sendable, Equatable {
        /// The independent-group bound is negative or exceeds the hard ceiling of 128.
        case invalidConfiguration
        /// An admitted raw leaf does not provide the public event-contribution contract.
        case unsupportedContribution
        /// A registration's complete snapshot disagrees or its selector/group identity is invalid.
        case invalidRegistration
        /// Structural namespaces contain the same runtime handler ID, which must remain globally unique.
        case duplicateHandlerID
        /// Explicitly selected host intents omit one or more declared required bits.
        case missingIntents
        /// Another distinct named independent group would exceed the configured finite bound.
        case independentGroupLimit
    }

    public let code: Code
    /// Bounded stable handler identity; never a payload or credential.
    public let handlerID: String
    public let source: DefinitionSourceLocation
    /// Exact absent bits for `.missingIntents`; empty for every other failure category.
    public let missingIntents: GatewayIntents

    /// Creates bounded display context using the shared diagnostic's UTF-8 limits.
    /// - Parameters:
    ///   - code: Stable validation failure category.
    ///   - handlerID: Author identity, truncated to 128 UTF-8 bytes without splitting Unicode scalars.
    ///   - source: Coordinate whose file label is truncated to 256 UTF-8 bytes.
    ///   - missingIntents: Absent explicit intent bits, default empty for non-intent failures.
    public init(code: Code, handlerID: String = "", source: DefinitionSourceLocation,
        missingIntents: GatewayIntents = []) {
        let bounded = DefinitionDiagnostic(code: .invalidIdentity, source: source, modulePath: [handlerID])
        self.code = code
        self.handlerID = bounded.modulePath.first ?? ""
        self.source = bounded.source
        self.missingIntents = missingIntents
    }
}

/// One named or default pipeline's source-ordered immutable registrations.
internal struct CompiledEventGroup: Sendable {
    let id: String?
    var registrations: [GatewayHandlerRegistration]
}

/// Immutable event declarations compiled without running handlers, subscriptions or network I/O.
/// All modules in the default group share one existing dispatcher and subscription. Named groups
/// are explicit independent subscriptions and provide no ordering guarantee between groups.
public struct CompiledEvents: Sendable {
    public let description: DefinitionDescription
    /// Union of declared selector and handler requirements; these are never enabled automatically.
    public let requiredIntents: GatewayIntents
    /// Stable handler IDs in global declaration order, including independent groups.
    public let handlerIDs: [String]
    /// Subscription groups in first-declaration order. Nil identifies the shared default group.
    /// An empty compiled plan has no groups and needs no subscription.
    public let groupIDs: [String?]
    internal let groups: [CompiledEventGroup]

    /// Stores already validated output without touching runtime authorities.
    /// - Parameters:
    ///   - description: Shared bounded structural description and source metadata.
    ///   - requiredIntents: Union checked against the caller's explicit host intent selection.
    ///   - handlerIDs: Unique stable declarations in source order.
    ///   - groups: Bounded nonempty groups in first-declaration order.
    internal init(description: DefinitionDescription, requiredIntents: GatewayIntents,
        handlerIDs: [String], groups: [CompiledEventGroup]) {
        self.description = description
        self.requiredIntents = requiredIntents
        self.handlerIDs = handlerIDs
        self.groups = groups
        groupIDs = groups.map(\.id)
    }

    /// Acquires every bounded broadcast subscription before returning any runnable work.
    /// - Parameters:
    ///   - hub: Existing application-owned broadcast hub; raw shard ingestion stays with its owner.
    ///   - configuration: Existing finite dispatcher concurrency/count/byte bounds, applied per group.
    ///   - authority: Optional shared aggregate callback authority across groups and other dispatchers.
    ///   - policy: Explicit slow-subscriber action, default resynchronization failure. Lossy policies
    ///     are opt-in and retain the existing hub's visibility and continuity limitations.
    ///   - maximumEvents: Positive queue-count override per subscription; nil uses hub defaults.
    ///   - maximumBytes: Positive envelope-byte override per subscription; nil uses hub defaults.
    /// - Returns: Single-use pipeline owner with all subscriptions ready for publication. No callbacks
    ///   run until its explicit `run()`. Constructing/compiling the plan acquired no subscriptions.
    /// - Throws: Cancellation or existing hub admission/configuration/shutdown errors. Any partially
    ///   admitted subscriptions are explicitly cancelled and awaited before the error escapes.
    ///
    /// No client is started, stopped or retained. A later supervised host can subscribe before its
    /// client starts, then own both lifetimes. Call `cancel()` if abandoning the returned owner.
    public func subscribe(to hub: GatewayEventHub, configuration: GatewayEventHandlerConfiguration,
        authority: GatewayHandlerAuthority? = nil, policy: GatewayEventOverflowPolicy = .resynchronize,
        maximumEvents: Int? = nil, maximumBytes: Int? = nil) async throws -> GatewayEventPipelines {
        var subscriptions: [GatewayEventSubscription] = []
        do {
            try Task.checkCancellation()
            for _ in groups {
                subscriptions.append(try await hub.subscribe(policy: policy,
                    maximumEvents: maximumEvents, maximumBytes: maximumBytes))
            }
            try Task.checkCancellation()
            return GatewayEventPipelines(groups: groups, subscriptions: subscriptions,
                dispatcher: .init(configuration: configuration, authority: authority))
        } catch {
            for subscription in subscriptions { await subscription.cancel() }
            throw error
        }
    }
}

/// Deterministic event lowering over the shared structural collector. No model parity, client
/// lifecycle, registration, authentication or capacity qualification is added by this authoring layer.
public enum EventCompilation {
    /// Supported shared contribution discriminator; custom leaves must expose the typed contract.
    public static let contributionKind = "discord.gateway-event"

    /// Flattens finite modules, validates exact snapshots/intents, and groups handlers in source order.
    /// - Parameters:
    ///   - definition: Synchronous finite definitions; arbitrary user getters/builders must remain
    ///     deterministic, inert and cooperatively terminating. Execution methods are never called.
    ///   - intents: Host's already selected Identify intent bits. Requirements are checked as a subset;
    ///     no bit is added and privileged-intent approval/delivery cannot be proven here.
    ///   - limits: Shared finite module/depth/declaration/text/structure admission defaults.
    ///   - maximumIndependentGroups: Named subscription cap in `0...128`, default eight, in addition
    ///     to at most one default group. Zero allows only the default group.
    /// - Returns: Immutable declarations and finite groups, with no runtime side effects.
    /// - Throws: Shared structural diagnostics, duplicate runtime handler IDs even across structural
    ///   namespaces, custom expansion
    ///   errors, or event diagnostics for forged snapshots, invalid selector/group names, absent
    ///   intents, unsupported custom leaves or exhausted independent-group admission. No partial
    ///   plan or executable pipeline escapes. Work is proportional to admitted structure and metadata.
    public static func compile<Definition: BotDefinition>(_ definition: Definition,
        intents: GatewayIntents, limits: DefinitionLimits = .init(), maximumIndependentGroups: Int = 8) throws -> CompiledEvents {
        guard (0...128).contains(maximumIndependentGroups) else {
            throw EventCompilationDiagnostic(code: .invalidConfiguration,
                source: .init(fileID: "<configuration>", line: 0, column: 0))
        }
        let plan = try DefinitionPlan.compile(definition, supportedKinds: [contributionKind], limits: limits)
        var groups: [CompiledEventGroup] = []
        var independentGroups = 0
        var requiredIntents: GatewayIntents = []
        var handlerIDs: [String] = []
        var runtimeIDs: Set<String> = []
        for (index, contribution) in plan.contributions.enumerated() {
            let metadata = plan.description.declarations[index].declaration
            guard let contribution = contribution as? any GatewayEventContribution else {
                throw EventCompilationDiagnostic(code: .unsupportedContribution,
                    handlerID: metadata.id, source: metadata.source)
            }
            let registration = contribution.registration
            guard registration.declaration == metadata, validIdentity(registration.selectorID),
                  registration.eventGroup.map(validIdentity) ?? true else {
                throw EventCompilationDiagnostic(code: .invalidRegistration,
                    handlerID: metadata.id, source: metadata.source)
            }
            guard runtimeIDs.insert(registration.id).inserted else {
                throw EventCompilationDiagnostic(code: .duplicateHandlerID,
                    handlerID: metadata.id, source: metadata.source)
            }
            let missing = registration.requiredIntents.subtracting(intents)
            guard missing.isEmpty else {
                throw EventCompilationDiagnostic(code: .missingIntents,
                    handlerID: metadata.id, source: metadata.source, missingIntents: missing)
            }
            requiredIntents.formUnion(registration.requiredIntents)
            handlerIDs.append(registration.id)
            if let index = groups.firstIndex(where: { $0.id == registration.eventGroup }) {
                groups[index].registrations.append(registration)
            } else {
                if registration.eventGroup != nil {
                    guard independentGroups < maximumIndependentGroups else {
                        throw EventCompilationDiagnostic(code: .independentGroupLimit,
                            handlerID: metadata.id, source: metadata.source)
                    }
                    independentGroups += 1
                }
                groups.append(.init(id: registration.eventGroup, registrations: [registration]))
            }
        }
        return .init(description: plan.description, requiredIntents: requiredIntents,
            handlerIDs: handlerIDs, groups: groups)
    }

    /// Validates an extra selector/group identity without accepting normalization or ASCII controls.
    /// - Parameter value: Exact identity already counted in the raw payload's structural byte budget.
    /// - Returns: True for nonempty strings of at most 128 UTF-8 bytes without ASCII controls or DEL.
    private static func validIdentity(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.prefix(129).count <= 128 &&
            !value.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 })
    }
}

/// Terminal owner-state failures, distinct from the existing hub/dispatcher failures.
public enum GatewayEventPipelineFailure: Error, Sendable, Equatable {
    /// The single-use subscription owner has already begun its run, whether successful or failed.
    case alreadyRun
}

/// Explicit owner for ready subscriptions and one structured handler run. Construction is internal
/// to `CompiledEvents.subscribe`; it does not start tasks or callbacks. Always call `run` or `cancel`
/// after subscription. The actor serializes owner-state transitions while existing dispatchers own
/// callback scheduling and shared aggregate admission. No client, sockets or services are owned here.
public actor GatewayEventPipelines {
    /// Fixed subscription count established before this owner is returned; module count is irrelevant.
    public nonisolated let subscriptionCount: Int
    private let groups: [CompiledEventGroup]
    private let subscriptions: [GatewayEventSubscription]
    private let dispatcher: GatewayEventHandlerDispatcher
    private var runStarted = false
    private var stopped = false
    private var runTask: Task<Void, any Error>?

    /// Stores ready finite subscriptions without starting tasks or consuming events.
    /// - Parameters:
    ///   - groups: Bounded registrations aligned one-to-one with ready subscriptions.
    ///   - subscriptions: Owned single-consumer queues, cancelled on every terminal path.
    ///   - dispatcher: Existing immutable bounded scheduling policy and optional shared authority.
    internal init(groups: [CompiledEventGroup], subscriptions: [GatewayEventSubscription],
        dispatcher: GatewayEventHandlerDispatcher) {
        self.groups = groups
        self.subscriptions = subscriptions
        self.dispatcher = dispatcher
        subscriptionCount = subscriptions.count
    }

    /// Runs every explicit group and awaits every child before returning or propagating failure.
    /// Matching handlers complete sequentially for each event in declaration order. Existing complete
    /// shard identity serialization, cross-shard progress and bounded retained input remain authoritative.
    /// Each group decodes a dispatch once when any selector needs it; known malformed payloads fail
    /// before any handler in that group, including raw handlers. Entirely raw groups skip decoding.
    /// - Throws: `alreadyRun` on a second invocation; cancellation after explicit stop or task
    ///   cancellation; otherwise original decoder, selector, callback, overflow or admission errors.
    ///   A failure cancels all sibling tasks and subscriptions; completed effects are never replayed.
    ///
    /// Hub finish completes normally after admitted callbacks. Cancellation/failure waits for callback
    /// cooperation. This method neither starts nor shuts down the application's existing client.
    public func run() async throws {
        guard !runStarted else { throw GatewayEventPipelineFailure.alreadyRun }
        runStarted = true
        do {
            try Task.checkCancellation()
            if stopped { throw CancellationError() }
            let groups = self.groups
            let subscriptions = self.subscriptions
            let dispatcher = self.dispatcher
            // This explicitly owned task supplies a cancellation handle for stop requests from a
            // callback. It captures only immutable snapshots and is joined on every run exit.
            let task = Task { try await Self.consume(groups: groups, subscriptions: subscriptions, dispatcher: dispatcher) }
            runTask = task
            try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
            runTask = nil
            if stopped { throw CancellationError() }
            try Task.checkCancellation()
        } catch {
            await cancel()
            runTask = nil
            throw error
        }
        await cancel()
    }

    /// Idempotently stops every owned queue and releases all buffered events before returning.
    /// A run already executing callbacks awaits them through its own structured task group; this
    /// method cancels that run's children and closes input without independently joining it or
    /// cancelling application services. The `run` caller remains responsible for awaiting completion.
    /// A run attempted after stopping throws cancellation. Calling this from a handler never waits
    /// for that same handler, avoiding a self-join; handler code must still honor its task cancellation.
    public func cancel() async {
        stopped = true
        runTask?.cancel()
        for subscription in subscriptions { await subscription.cancel() }
    }

    /// Supervises existing dispatchers without inheriting actor-isolated mutable owner state.
    /// - Parameters:
    ///   - groups: Immutable finite source-ordered handler groups, one per subscription.
    ///   - subscriptions: Dedicated already admitted queues, consumed only by their dispatcher.
    ///   - dispatcher: Existing finite scheduling configuration and optional aggregate authority.
    /// - Throws: The first observed original child error or cancellation, after cancelling and
    ///   awaiting every sibling. `next` observes errors immediately rather than waiting for other
    ///   subscriptions to finish normally before initiating cancellation.
    private nonisolated static func consume(groups: [CompiledEventGroup],
        subscriptions: [GatewayEventSubscription], dispatcher: GatewayEventHandlerDispatcher) async throws {
        try await withThrowingTaskGroup(of: Void.self) { tasks in
            defer { tasks.cancelAll() }
            for (index, group) in groups.enumerated() {
                let subscription = subscriptions[index]
                tasks.addTask {
                    let needsDispatch = group.registrations.contains(where: \.decodesDispatch)
                    try await dispatcher.run(subscription: subscription) { raw in
                        let dispatch = needsDispatch ? try raw.decodeDispatch() : nil
                        for registration in group.registrations {
                            try Task.checkCancellation()
                            try await registration.invoke(raw, dispatch)
                        }
                    }
                }
            }
            while try await tasks.next() != nil { }
        }
    }
}
