import DiscordCommands
import DiscordCore
import DiscordDSL
import DiscordInteractions
import DiscordModels

/// Finite local admission failures, without submitted input or credential diagnostics.
public enum CommandPolicyError: Error, Sendable, Equatable {
    case denied
    case capacityExceeded
    case invalidCapacity
    case continuationAlreadyInvoked
    case unknownRoute
}

/// Injected aggregate admission authority. Implementations must bound their state and reject excess
/// work without hidden unbounded queues. Distributed coordination, fairness and failure behavior
/// belong to that authority; this contract never changes Discord's HTTP rate limits.
public protocol CommandConcurrencyAuthority: Sendable {
    /// Runs one operation under cancellation-cooperative admission and releases it on every exit.
    /// - Parameter operation: Caller-owned work, invoked at most once after successful admission.
    /// - Returns: Its result after admission cleanup has completed.
    /// - Throws: Capacity/coordinator failure before execution, operation failure, or cancellation.
    ///   Implementations must await cleanup before returning; cleanup failures remain observable.
    func withPermit<Value: Sendable>(operation: @Sendable () async throws -> Value) async throws -> Value
}

/// A fixed-size, fail-fast in-process authority shared across selected commands, catalogs and routers.
/// It retains only an active count, with no identity table, history, waiters, TTL records or tasks.
/// Reuse one instance for an aggregate bound; separate instances create separate authorities.
public actor CommandConcurrencyLimit: CommandConcurrencyAuthority {
    public let maximumConcurrent: Int
    private var active = 0

    /// Configures a finite active-invocation limit without starting work or allocating reservations.
    /// - Parameter maximumConcurrent: Positive simultaneous operation cap, with no waiting queue.
    /// - Throws: `CommandPolicyError.invalidCapacity` for zero or negative values.
    public init(maximumConcurrent: Int) throws {
        guard maximumConcurrent > 0 else { throw CommandPolicyError.invalidCapacity }
        self.maximumConcurrent = maximumConcurrent
    }

    /// Current admitted operations, including suspended work; reading starts no work.
    public var activeCount: Int { active }

    /// Admits immediately and releases actor-isolated count on success, error and cancellation.
    /// - Parameter operation: Cancellation-cooperative caller work, invoked exactly once if admitted.
    /// - Returns: The operation's value after its reservation has been released.
    /// - Throws: Cancellation before admission, `capacityExceeded` when full, or the operation's error.
    ///   Actor suspension is reentrant; a cancelled operation retains its slot until it actually exits.
    public func withPermit<Value: Sendable>(operation: @Sendable () async throws -> Value) async throws -> Value {
        try Task.checkCancellation()
        guard active < maximumConcurrent else { throw CommandPolicyError.capacityExceeded }
        active += 1
        defer { active -= 1 }
        try Task.checkCancellation()
        return try await operation()
    }
}

/// Built-in observations and injected current authorization over an authenticated normalized invocation.
/// Registration defaults and cached permissions never authorize application work through these helpers.
public enum CommandPolicy {
    /// Requires a concrete guild ID, rejecting absent/null IDs without hydration or permission inference.
    /// - Returns: Inert predicate, evaluated only during explicit invocation after complete input admission.
    public static func isGuild() -> InvocationPolicy<CommandContext> {
        InvocationPolicy { context in
            if case .value = context.interaction.guildID { return true }
            return false
        }
    }

    /// Requires an exact known interaction context; missing, null and future raw values fail closed.
    /// - Parameter expected: Guild, bot DM or private channel context from the API v10 interaction envelope.
    /// - Returns: Inert predicate with no fallback from a guild ID or registration context defaults.
    public static func context(_ expected: InteractionContextType) -> InvocationPolicy<CommandContext> {
        InvocationPolicy { context in
            guard case .value(let observed) = context.interaction.context else { return false }
            return observed.knownValue == expected
        }
    }

    /// Injects current application authorization without interpreting permission or entitlement snapshots.
    /// - Parameter check: Application-owned cancellation-cooperative decision. False denies; errors propagate
    ///   without executing a handler. Network/store bounds, freshness and distributed authority stay injected.
    /// - Returns: Inert predicate; constructing or compiling it never invokes the closure.
    public static func authorized(by check: @escaping @Sendable (CommandContext) async throws -> Bool)
        -> InvocationPolicy<CommandContext> {
        InvocationPolicy(check)
    }
}

/// An explicit denial callback selected before any middleware, deferral or handler work.
/// Autocomplete can only suppress suggestions; message callbacks remain unavailable for that family.
public enum CommandRejectionResponse: Sendable {
    case message(MessageResponse)
    case emptyAutocomplete
}

/// Validated immutable execution configuration. Construction performs no authorization, handler work,
/// admission or I/O. Execution order is input validation, predicate, concurrency admission, middleware,
/// existing response adapter, reverse middleware exit, admission release, then optional error translation.
/// There are no retries or automatic deferrals. Middleware owns its own cleanup and partial side effects.
public struct CommandPolicies: Sendable {
    public let limits: PolicyLimits
    internal let predicate: InvocationPolicy<CommandContext>?
    internal let middleware: InvocationMiddleware<CommandContext, Void>?
    private let concurrency: (any CommandConcurrencyAuthority)?
    private let rejection: (@Sendable (CommandContext) throws -> CommandRejectionResponse)?
    private let errorMapping: (@Sendable (any Error, CommandContext) -> any Error)?
    internal let nodeCount: Int

    /// Validates finite expression bounds and retains injected behavior without executing it.
    /// - Parameters:
    ///   - limits: Explicit finite node/depth bounds, also applied across repeated catalog applications.
    ///   - requiring: Optional short-circuit predicate. False throws `denied` unless rejection is supplied.
    ///   - middleware: Optional outer-left/inner-right composition, around the original response adapter.
    ///     Its terminal continuation can execute the original invocation at most once, even concurrently;
    ///     replacement input passed to next never replaces the authenticated invocation or response owner.
    ///     The terminal continuation closes on middleware exit; an already started terminal is joined before
    ///     admission releases. Authors must await next and must not retain it or launch detached work.
    ///   - concurrency: Optional shared local/distributed authority; nil adds no additional admission.
    ///   - onRejection: Optional explicit callback for a false predicate only. Default nil propagates denial
    ///     with no acknowledgement. Message denial is legal for commands/components/modals; autocomplete
    ///     requires `emptyAutocomplete`. Invalid family choices fail before submission. Capacity, authority
    ///     failures, predicate errors and handler errors never send an implicit callback.
    ///   - mapError: Optional error-to-error translation after cleanup. It cannot send a response or replay
    ///     work. Cancellation bypasses this closure; original partial side effects and responder state remain.
    /// - Throws: `PolicyCompositionError` for excessive combined expression count or individual tree depth.
    public init(limits: PolicyLimits, requiring: InvocationPolicy<CommandContext>? = nil,
        middleware: InvocationMiddleware<CommandContext, Void>? = nil,
        concurrency: (any CommandConcurrencyAuthority)? = nil,
        onRejection: (@Sendable (CommandContext) throws -> CommandRejectionResponse)? = nil,
        mapError: (@Sendable (any Error, CommandContext) -> any Error)? = nil) throws {
        try requiring?.validate(limits: limits)
        try middleware?.validate(limits: limits)
        let predicateNodes = requiring?.nodeCount ?? 0
        let middlewareNodes = middleware?.nodeCount ?? 0
        guard predicateNodes < limits.maximumNodes,
              middlewareNodes <= limits.maximumNodes - predicateNodes - 1 else {
            throw PolicyCompositionError.nodeLimit
        }
        let nodes = 1 + predicateNodes + middlewareNodes
        self.limits = limits
        predicate = requiring
        self.middleware = middleware
        self.concurrency = concurrency
        rejection = onRejection
        errorMapping = mapError
        nodeCount = nodes
    }

    /// Executes one prevalidated invocation in the caller's task without replacing response authority.
    /// - Parameters:
    ///   - context: Original normalized invocation, whose input preparation has already succeeded.
    ///   - next: Original prepared adapter, invoked zero or one times by middleware.
    /// - Throws: Admission/authorization/application/delivery failures or cancellation. Error translation
    ///   runs after admission release and never fabricates a reply after acknowledgement or uncertainty.
    internal func execute(_ context: InteractionContext,
        next: @escaping @Sendable () async throws -> Void) async throws {
        let snapshot = CommandContext(context)
        do {
            try Task.checkCancellation()
            if let predicate, try await !predicate.evaluate(snapshot, limits: limits) {
                try Task.checkCancellation()
                guard let rejection else { throw CommandPolicyError.denied }
                let response = try rejection(snapshot)
                try Task.checkCancellation()
                switch response {
                case .message(let message): try await context.responder.reply(message.message)
                case .emptyAutocomplete: try await context.responder.respond(.autocomplete([]))
                }
                return
            }
            try Task.checkCancellation()
            let operation: @Sendable () async throws -> Void = {
                let continuation = CommandPolicyContinuation()
                let terminal: @Sendable (CommandContext) async throws -> Void = { _ in
                    try await continuation.claim()
                    do {
                        try Task.checkCancellation()
                        try await next()
                        await continuation.complete()
                    } catch {
                        await continuation.complete()
                        throw error
                    }
                }
                do {
                    if let middleware {
                        try await middleware.run(snapshot, limits: limits, next: terminal)
                    } else { try await terminal(snapshot) }
                    await continuation.close()
                    try Task.checkCancellation()
                } catch {
                    await continuation.close()
                    throw error
                }
            }
            if let concurrency { try await concurrency.withPermit(operation: operation) }
            else { try await operation() }
            try Task.checkCancellation()
        } catch {
            if let cancellation = error as? DiscordError, cancellation == .cancelled { throw cancellation }
            if error is CancellationError || Task.isCancelled { throw CancellationError() }
            throw errorMapping?(error, snapshot) ?? error
        }
    }
}

extension CompiledCommands {
    /// Applies one finite execution layer to all or an exact subset of already compiled routes.
    /// - Parameters:
    ///   - policies: Validated inert predicate/middleware/admission/error configuration. A later application
    ///     becomes the outer layer, while each middleware expression retains left-outer ordering.
    ///   - keys: Exact route subset, default nil for every family. Empty applies to no routes; unknown keys
    ///     reject construction. Definitions and structural registration metadata remain byte-for-byte identical.
    /// - Returns: An inert catalog sharing captured authorities. Reuse those authorities across catalogs
    ///   when one aggregate concurrency bound is required. Low-level routes own their own input preparation.
    /// - Throws: `unknownRoute` for missing keys or composition limits for cumulative count/wrapper depth.
    ///   No policy, middleware, handler, mapper, registration request or admission executes here.
    public func applying(_ policies: CommandPolicies, to keys: Set<CommandRouteKey>? = nil) throws -> CompiledCommands {
        if let keys, !keys.isSubset(of: Set(routes.map(\.key))) { throw CommandPolicyError.unknownRoute }
        guard policyNodeCount <= policies.limits.maximumNodes - policies.nodeCount else {
            throw PolicyCompositionError.nodeLimit
        }
        guard policyDepth < policies.limits.maximumDepth else { throw PolicyCompositionError.depthLimit }
        let wrapped = routes.map { route in
            guard keys?.contains(route.key) ?? true else { return route }
            return route.wrappingExecution { context, next in try await policies.execute(context, next: next) }
        }
        return CompiledCommands(description: description, definitions: definitions, routes: wrapped,
            policyNodeCount: policyNodeCount + policies.nodeCount, policyDepth: policyDepth + 1)
    }
}

/// One invocation-local flag serializing middleware continuation claims, with no history or tasks.
private actor CommandPolicyContinuation {
    private var invoked = false
    private var running = false
    private var closed = false
    private var completion: CheckedContinuation<Void, Never>?

    /// Claims the original adapter once; failed or completed attempts can never be replayed.
    /// - Throws: `continuationAlreadyInvoked` on every later claim, including concurrent claims.
    func claim() throws {
        guard !invoked, !closed else { throw CommandPolicyError.continuationAlreadyInvoked }
        invoked = true
        running = true
    }

    /// Marks terminal cleanup complete and resumes the sole structured closing caller, if present.
    func complete() {
        running = false
        completion?.resume()
        completion = nil
    }

    /// Rejects future claims and joins a terminal already started by middleware before releasing admission.
    /// Suspension is cancellation independent so cleanup completes even if the parent task is cancelled.
    func close() async {
        closed = true
        if running { await withCheckedContinuation { completion = $0 } }
    }
}
