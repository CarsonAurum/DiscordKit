import DiscordClient
import DiscordCommandDSL
import DiscordCommands
import DiscordCore
import DiscordGateway
import DiscordInteractions
import DiscordModels
import DiscordTransport

/// Closed bridge failures containing no interaction content, tokens or arbitrary dependency text.
public enum GatewayInteractionFailure: Error, Sendable, Equatable {
    case alreadyPrepared
    case notPrepared
    case alreadyRun
    case untrustedEvent
    case wrongApplication
    case unmatchedCommand
}

/// Trusted Gateway-to-command composition owned by a supervised bot runtime. Only the package's
/// client ingestion callback can publish to its private bounded hub; public hubs/replay events cannot
/// become authenticated interactions. Construction starts no tasks, subscriptions, registration or I/O.
/// Callbacks and continuations use HTTP; no Gateway acknowledgement opcode is invented.
public actor GatewayInteractionAdapter<C: Clock> where C.Duration == Duration {
    private let applicationID: ApplicationID
    private let services: BotServiceAdapter<C>
    private let clock: InteractionClock
    private let admission: InteractionAcknowledgementAdmission
    private let limits: JSONLimits
    private let router: CommandRouter
    private let reconciler: CommandReconciler
    private let hub: GatewayEventHub
    private let dispatcher: GatewayEventHandlerDispatcher
    private var subscription: GatewayEventSubscription?
    private var prepared = false
    private var started = false
    private var stopped = false
    private var runTask: Task<Void, any Error>?

    /// Validates a finite command host and stores shared authorities without invoking injected work.
    /// - Parameters:
    ///   - applicationID: Expected interaction and explicit registration application owner.
    ///   - commands: Complete compiled command/interaction catalog, including route-only families.
    ///   - services: Shared bot REST services and separately admitted exact-token HTTP response factories.
    ///   - clock: Monotonic clock shared with the client and HTTP clients; socket receipt age is preserved.
    ///   - admission: Shared initial-only acknowledgement count/byte authority, independent of ordinary REST.
    ///   - guildID: Explicit registration scope, default nil for global; dispatch still checks application ID.
    ///   - configuration: Existing dispatcher task/retained-event bounds, default four tasks and 128 events.
    ///     Complete-shard serialization is preserved; different shards may progress concurrently.
    ///   - authority: Optional aggregate handler authority, shared explicitly with other event pipelines.
    ///   - maximumPendingInteractions: Positive private input queue cap, default 256, in addition to
    ///     the dispatcher's separately bounded retained events. Overflow fails the supervised host closed.
    ///   - maximumPendingBytes: Positive private queue envelope-byte cap, default 8 MiB.
    ///   - maximumConcurrentHandlers: Positive existing command-router aggregate cap, default 64.
    ///   - maximumDefinitionBytes: Positive explicit registration JSON bound, default 1 MiB.
    ///   - limits: Existing interaction JSON decoding bounds, default standard model limits.
    /// - Throws: Existing router/catalog/reconciler or nonpositive queue-bound validation errors.
    /// No application auto-defer timer exists; typed deferred handlers retain their explicit ownership.
    public init(applicationID: ApplicationID, commands: CompiledCommands, services: BotServiceAdapter<C>,
        clock: C, admission: InteractionAcknowledgementAdmission, guildID: GuildID? = nil,
        configuration: GatewayEventHandlerConfiguration = try! .init(), authority: GatewayHandlerAuthority? = nil,
        maximumPendingInteractions: Int = 256, maximumPendingBytes: Int = 8 * 1_024 * 1_024,
        maximumConcurrentHandlers: Int = 64, maximumDefinitionBytes: Int = 1_048_576,
        limits: JSONLimits = .default) throws {
        self.applicationID = applicationID
        self.services = services
        self.clock = InteractionClock(clock)
        self.admission = admission
        self.limits = limits
        router = try commands.makeRouter(maximumConcurrentHandlers: maximumConcurrentHandlers)
        reconciler = try CommandReconciler(applicationID: applicationID, guildID: guildID,
            definitions: commands.definitions, maximumDefinitionBytes: maximumDefinitionBytes)
        hub = GatewayEventHub(configuration: try .init(maximumSubscriptions: 1,
            maximumBufferedEvents: maximumPendingInteractions, maximumBufferedBytes: maximumPendingBytes,
            maximumEventsPerSubscription: maximumPendingInteractions, maximumBytesPerSubscription: maximumPendingBytes))
        dispatcher = GatewayEventHandlerDispatcher(configuration: configuration, authority: authority)
    }

    /// Explicitly reconciles this catalog through the existing bot REST service and managed-name owner.
    /// - Parameter deadline: Optional overall deadline in the shared REST clock domain, default nil.
    /// - Returns: Existing unchanged/upsert report; unmanaged commands are preserved.
    /// - Throws: Existing scope/read/schema failures, overlapping reconciliation or partial mutation outcomes.
    /// Construction, preparation and serving never invoke this method or make registration requests.
    public func synchronize(deadline: C.Instant? = nil) async throws -> CommandSyncReport {
        try await reconciler.synchronize(using: services.services.rest, deadline: deadline)
    }

    /// Readies the sole private bounded subscription before installing the trusted client receiver.
    /// - Parameter client: Exact owned client; it must be idle and may admit only one interaction receiver.
    /// - Throws: Cancellation, repeated preparation, stopped owner or client/hub admission errors.
    /// Partial setup closes the subscription; no client, command handler, HTTP operation or factory runs.
    package func prepare<L: ShardLeaseStore>(client: DiscordClient<C, L>) async throws where L.LeaseClock == C {
        guard !prepared else { throw GatewayInteractionFailure.alreadyPrepared }
        prepared = true
        do {
            try Task.checkCancellation()
            guard !stopped else { throw CancellationError() }
            let subscription = try await hub.subscribe()
            self.subscription = subscription
            try await client.setInteractionHandler { event in try await self.receive(event) }
            try Task.checkCancellation()
            guard !stopped else { throw CancellationError() }
        } catch {
            await cancel()
            throw error
        }
    }

    /// Admits only client-owned socket input, retaining its original monotonic receipt-age observation.
    /// - Parameter event: Actual client ingestion dispatch, before optional user cache projection.
    /// - Throws: Cancellation, missing receipt provenance, closed input or queue-overflow failure.
    /// This operation only enqueues; it never decodes payloads, invokes response factories or executes handlers.
    internal func receive(_ event: GatewayEvent) async throws {
        try Task.checkCancellation()
        guard !stopped else { throw CancellationError() }
        guard event.elapsedSinceReceipt != nil else { throw GatewayInteractionFailure.untrustedEvent }
        guard event.opcode == 0, event.name == "INTERACTION_CREATE" else { return }
        let publication = await hub.publish(event)
        guard publication.delivered == 1, publication.terminated == 0 else {
            throw GatewayEventDeliveryFailure.resynchronizationRequired
        }
    }

    /// Runs the prepared private dispatcher until failure or supervised cancellation, joining all handlers.
    /// - Throws: Repeated/missing preparation, malformed/wrong-application/unmatched input, original command
    ///   failures, queue/admission errors, response uncertainty or cancellation. Completed effects are not replayed.
    /// Cancellation closes the queue and awaits cooperative callbacks; noncooperative injected work cannot
    /// be forcibly terminated. Receipt-relative three-second and fifteen-minute response limits are unchanged.
    package func run() async throws {
        guard !started else { throw GatewayInteractionFailure.alreadyRun }
        started = true
        guard prepared, let subscription else { throw GatewayInteractionFailure.notPrepared }
        do {
            try Task.checkCancellation()
            guard !stopped else { throw CancellationError() }
            let dispatcher = self.dispatcher, applicationID = self.applicationID, services = self.services
            let clock = self.clock, admission = self.admission, router = self.router, limits = self.limits
            let task = Task {
                try await dispatcher.run(subscription: subscription) { event in
                    let responseNow = clock.now
                    guard let age = event.elapsedSinceReceipt, age >= .zero else {
                        throw GatewayInteractionFailure.untrustedEvent
                    }
                    let receivedAt = responseNow - age
                    guard let dispatch = try event.decodeDispatch(limits: limits),
                          case .interactionCreate(let interaction) = dispatch else {
                        throw GatewayInteractionFailure.untrustedEvent
                    }
                    guard interaction.applicationID == applicationID else { throw GatewayInteractionFailure.wrongApplication }
                    let responder = InteractionResponder(interaction: interaction, deliveryMode: .gateway,
                        clock: clock, sink: services.responseSink(for: interaction), admission: admission,
                        receivedAt: receivedAt)
                    let context = try InteractionContext(interaction: interaction, deliveryMode: .gateway, responder: responder)
                    guard try await router.route(context) else { throw GatewayInteractionFailure.unmatchedCommand }
                }
            }
            runTask = task
            try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
            runTask = nil
            try Task.checkCancellation()
            if stopped { throw CancellationError() }
        } catch {
            await cancel()
            runTask = nil
            throw error
        }
        await cancel()
    }

    /// Stops private input and cancels the owning run without joining a callback that may request stop.
    /// Repeated calls release queued payloads. The runtime must still await `run` for handler cleanup;
    /// shared REST transports, rate/admission authorities and unrelated public subscriptions remain caller-owned.
    package func cancel() async {
        stopped = true
        runTask?.cancel()
        await subscription?.cancel()
        await hub.finish()
    }
}
