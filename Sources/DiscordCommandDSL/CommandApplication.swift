import DiscordLogging
import DiscordCommands
import DiscordCore
import DiscordHTTP
import DiscordInteractions
import DiscordModels
import DiscordTransport

/// Closed configuration/dispatch failures without submitted input, credentials or transport details.
public enum CommandApplicationError: Error, Sendable, Equatable {
    /// DSL-managed response ownership cannot share an application-level automatic defer timer.
    case competingAutoDefer
    /// A signed non-PING interaction did not match a compiled exact interaction route.
    case unmatchedCommand
}

/// Independently adopted signed HTTP host over one compiled catalog and one bounded router.
/// Construction owns no listener, timer or registration work. Copies share router/reconciler authorities;
/// distinct instances must explicitly share ingress, acknowledgement and REST authorities as appropriate.
public struct CommandApplication: Sendable {
    private let application: InteractionHTTPApplication
    private let router: CommandRouter
    private let reconciler: CommandReconciler
    private let maximumConcurrentRequests: Int

    /// Validates a complete catalog and response ownership policy without executing handlers or I/O.
    /// - Parameters:
    ///   - applicationID: Expected signed interaction and command-registration owner.
    ///   - commands: Previously compiled finite command-family catalog; declaration order is retained.
    ///   - ingress: Caller-shared signature/replay/body/concurrency authority; no listener is opened.
    ///   - admission: Shared initial-response count/byte authority, independent of ordinary REST quotas.
    ///   - guildID: Explicit registration scope, nil for global. Dispatch still checks the application ID.
    ///   - maximumConcurrentHandlers: Positive aggregate router bound, default 64; overload has no queue.
    ///   - maximumConcurrentRequests: Positive active exchange/child-task bound for `run`, default 64.
    ///     Direct concurrent `handle` calls remain bounded by the injected ingress and router authorities.
    ///   - maximumDefinitionBytes: Positive encoded registration budget, default 1 MiB.
    ///   - autoDefer: Must be nil. A nonnil value is rejected before any work; typed deferred handlers
    ///     acknowledge explicitly and manual handlers retain their existing unique response owner.
    ///   - limits: JSON decoding bounds applied after authentication, default standard model limits.
    /// - Throws: `competingAutoDefer`, invalid positive bounds, router/catalog/scope validation or byte limits.
    ///   Registration caps are the existing API v10 `CommandReconciler` caps; nothing is registered here.
    public init(applicationID: ApplicationID, commands: CompiledCommands, ingress: DiscordSignedIngress,
        admission: InteractionAcknowledgementAdmission, guildID: GuildID? = nil,
        maximumConcurrentHandlers: Int = 64, maximumConcurrentRequests: Int = 64,
        maximumDefinitionBytes: Int = 1_048_576, autoDefer: InteractionAutoDeferPolicy? = nil,
        limits: JSONLimits = .default) throws {
        guard autoDefer == nil else { throw CommandApplicationError.competingAutoDefer }
        guard maximumConcurrentRequests > 0 else { throw DiscordError.validation(.invalidValue) }
        router = try commands.makeRouter(maximumConcurrentHandlers: maximumConcurrentHandlers)
        reconciler = try CommandReconciler(applicationID: applicationID, guildID: guildID,
            definitions: commands.definitions, maximumDefinitionBytes: maximumDefinitionBytes)
        application = InteractionHTTPApplication(applicationID: applicationID, ingress: ingress,
            admission: admission, autoDefer: nil, limits: limits)
        self.maximumConcurrentRequests = maximumConcurrentRequests
    }

    /// Authenticates and routes one transferred HTTP exchange, awaiting all handler/response work.
    /// PING is answered by the existing application without user execution. Invalid signatures, bodies
    /// and applications keep its 401/400/403 behavior. Unmatched routes fail with 500 before acknowledgement;
    /// handler failures propagate, and a reserved/uncertain initial response is never replayed.
    /// - Parameters:
    ///   - exchange: Accepted single-response exchange; input/response ownership transfers on every path.
    ///   - context: Monotonic receipt clock and optional outer deadline. The responder independently
    ///     enforces receipt-relative three-second acknowledgement and fifteen-minute continuation limits.
    ///   - continuations: Optional application-owned REST sink factory for original edits/followups/deletion.
    ///     Nil supports immediate/manual initial responses only; deferred edits require an edit sink.
    /// - Throws: Unmatched route, argument/handler/lifecycle errors, cancellation or transport uncertainty.
    ///   No registration, fallback acknowledgement, automatic mutation retry or detached work occurs.
    public func handle<C: Clock>(_ exchange: HTTPExchange, context: TransportContext<C>,
        continuations: (@Sendable (Interaction) -> InteractionResponseSink)? = nil) async throws
        where C.Duration == Duration {
        DiscordLog.makeLogger("command_dsl.http").debug("Command HTTP exchange started", metadata: ["dk.event": "command_dsl.exchange.started"])
        do {
            try await application.handle(exchange, context: context, continuations: continuations) { input in
                DiscordLog.makeLogger("command_dsl.http").trace("Authenticated command exchange reached routing", metadata: ["dk.event": "command_dsl.exchange.routing"])
                guard try await router.route(input) else { throw CommandApplicationError.unmatchedCommand }
            }
            DiscordLog.makeLogger("command_dsl.http").debug("Command HTTP exchange completed", metadata: ["dk.event": "command_dsl.exchange.completed"])
        } catch {
            DiscordLog.makeLogger("command_dsl.http").debug("Command HTTP exchange stopped", metadata: ["dk.event": "command_dsl.exchange.stopped", "dk.cancelled": .stringConvertible(error is CancellationError)])
            throw error
        }
    }

    /// Explicitly serves a caller-created ingress with bounded structured child tasks and owned shutdown.
    /// One acceptance operation runs at a time alongside at most the configured number of handlers.
    /// Handler failures interrupt pending acceptance. EOF drains admitted handlers;
    /// cancellation/failure closes acceptance, cancels children, awaits their cooperative cleanup and rethrows.
    /// The listener must not be served concurrently elsewhere and must unblock acceptance when closed.
    /// - Parameters:
    ///   - listener: Ownership transfers on entry, including cancellation; always closed before return.
    ///   - context: Host acceptance clock/optional overall deadline, reused for accepted exchanges.
    ///   - continuations: Shared optional continuation factory, with the same contract as `handle`.
    /// - Throws: Acceptance, handler, cancellation, deadline or response errors. Injected noncooperative
    ///   work cannot be forcibly terminated. Close is nonthrowing by the transport contract.
    /// Running never synchronizes registrations, reads environment variables or creates a concrete adapter.
    public func run<C: Clock>(listener: any HTTPIngress, context: TransportContext<C>,
        continuations: (@Sendable (Interaction) -> InteractionResponseSink)? = nil) async throws
        where C.Duration == Duration {
        DiscordLog.makeLogger("command_dsl.http").info("Command HTTP listener started", metadata: ["dk.event": "command_dsl.listener.started"])
        let accepted = AcceptedCommandExchange()
        do {
            try await withThrowingTaskGroup(of: CommandApplicationEvent.self) { group in
                do {
                    var active = 0
                    var accepting = false
                    var ended = false
                    while !ended || active > 0 {
                        try context.check()
                        if !ended && !accepting && active < maximumConcurrentRequests {
                            accepting = true
                            DiscordLog.makeLogger("command_dsl.http").trace("Waiting for command HTTP exchange", metadata: ["dk.event": "command_dsl.listener.accepting", "dk.active": .stringConvertible(active)])
                            group.addTask {
                                guard let exchange = try await listener.accept(context: context) else { return .end }
                                await accepted.store(exchange)
                                return .accepted
                            }
                        }
                        guard let event = try await group.next() else { break }
                        switch event {
                        case .accepted:
                            accepting = false
                            guard let exchange = await accepted.take() else { throw TransportFailure.closed }
                            active += 1
                            DiscordLog.makeLogger("command_dsl.http").trace("Accepted command HTTP exchange admitted", metadata: ["dk.event": "command_dsl.listener.admitted", "dk.active": .stringConvertible(active)])
                            group.addTask {
                                try await handle(exchange, context: context, continuations: continuations)
                                return .handled
                            }
                        case .end:
                            accepting = false
                            ended = true
                            DiscordLog.makeLogger("command_dsl.http").trace("Command listener reached end of input", metadata: ["dk.event": "command_dsl.listener.eof", "dk.active": .stringConvertible(active)])
                        case .handled:
                            active -= 1
                            DiscordLog.makeLogger("command_dsl.http").trace("Command HTTP exchange child joined", metadata: ["dk.event": "command_dsl.listener.released", "dk.active": .stringConvertible(active)])
                        }
                    }
                } catch {
                    DiscordLog.makeLogger("command_dsl.http").trace("Cancelling listener children and closing acceptance", metadata: ["dk.event": "command_dsl.listener.children_cancelling"])
                    group.cancelAll()
                    await listener.close()
                    await accepted.close()
                    throw error
                }
            }
            await accepted.close()
            await listener.close()
            DiscordLog.makeLogger("command_dsl.http").info("Command HTTP listener stopped", metadata: ["dk.event": "command_dsl.listener.stopped"])
        } catch {
            if error is CancellationError {
                DiscordLog.makeLogger("command_dsl.http").debug("Command HTTP listener cancelled", metadata: ["dk.event": "command_dsl.listener.cancelled"])
            } else {
                DiscordLog.makeLogger("command_dsl.http").error("Command HTTP listener failed", metadata: ["dk.event": "command_dsl.listener.failed"])
            }
            await accepted.close()
            await listener.close()
            DiscordLog.makeLogger("command_dsl.http").trace("Command listener acceptance and pending exchange closed", metadata: ["dk.event": "command_dsl.listener.cleanup_completed"])
            throw error
        }
    }

    /// Explicitly reconciles this catalog using the existing change-only registration owner.
    /// - Parameters:
    ///   - client: Caller-owned REST client with shared credential/rate authorities and API v10 permissions.
    ///   - deadline: Optional overall deadline in that client's clock domain; default nil.
    /// - Returns: Unchanged count and acknowledged upserts. Unmanaged commands are preserved.
    /// - Throws: Read/schema/scope errors or `CommandSyncFailure` with partial progress. Overlapping calls
    ///   on this application's shared reconciler reject; ambiguous mutations are never blindly replayed.
    /// One fresh GET is required even for a no-op catalog. Constructors, `handle` and `run` never call this.
    public func synchronize<C: Clock>(using client: RESTClient<C>, deadline: C.Instant? = nil) async throws -> CommandSyncReport
        where C.Duration == Duration {
        try await reconciler.synchronize(using: client, deadline: deadline)
    }
}

/// Finite completion markers; accepted bodies remain in the explicit transfer slot until adopted.
private enum CommandApplicationEvent: Sendable { case accepted, end, handled }

/// Owns the one exchange between listener acceptance and handler admission, including cancellation races.
private actor AcceptedCommandExchange {
    private var exchange: HTTPExchange?
    private var closed = false

    /// Takes ownership after acceptance, disposing late transfers when shutdown has already won.
    /// - Parameter exchange: Newly accepted request and response slot; only one acceptance is active.
    func store(_ exchange: HTTPExchange) async {
        if closed {
            await exchange.request.body?.close()
            await exchange.responder.close()
        } else { self.exchange = exchange }
    }

    /// Transfers the pending exchange exactly once to a structured handler task.
    /// - Returns: Accepted exchange, or nil after shutdown/previous transfer.
    func take() -> HTTPExchange? { defer { exchange = nil }; return exchange }

    /// Prevents late transfers and closes any accepted exchange not yet adopted by a handler.
    /// Repeated closure is safe, and active handlers keep their independent exchange ownership.
    func close() async {
        closed = true
        let pending = exchange
        exchange = nil
        await pending?.request.body?.close()
        await pending?.responder.close()
    }
}
