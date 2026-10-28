// File: Sources/DiscordBotDSL/GatewayInteractionAdapter.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordClient
import DiscordCommandDSL
import DiscordCommands
import DiscordCore
import DiscordGateway
import DiscordInteractions
import DiscordHTTP
import DiscordLogging
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

/// Finite invocation handling choices. Recovery never retries work or sends a replacement response.
/// Security, malformed input, owner/admission continuity and cancellation failures remain terminal.
public enum GatewayInvocationFailurePolicy: Sendable {
    /// Preserves the original supervised fail-fast behavior.
    case failFast
    /// Releases one failed invocation and continues queued work after trusted input admission.
    /// Handler, initial callback, continuation and stale/unmatched command failures are observed only;
    /// no acknowledgement, follow-up, token refresh or compensating mutation is performed.
    case continueInvocations
}

/// Internal aggregate ownership evidence without event, credential or per-interaction labels.
internal struct GatewayInteractionSnapshot: Sendable {
    let activeHandlers: Int
    let bufferedEvents: Int
    let bufferedBytes: Int
    let subscriptions: Int
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
    private let failurePolicy: GatewayInvocationFailurePolicy
    private let failureObserver: BotFailureObserver?
    private var subscription: GatewayEventSubscription?
    private var prepared = false
    private var started = false
    private var stopped = false
    private var runTask: Task<Void, any Error>?

    /// Preserves legacy complete-shard interaction ordering while retaining all existing finite authorities.
    /// - Parameters:
    ///   - applicationID: Expected application and explicit registration owner.
    ///   - commands: Validated inert command catalog.
    ///   - services: Shared bot services and exact-token response factories.
    ///   - clock: Shared monotonic response clock; original socket receipt age is retained.
    ///   - admission: Shared initial-only acknowledgement authority.
    ///   - guildID: Explicit registration scope; does not filter incoming interactions.
    ///   - configuration: Finite dispatcher task, retained event and retained byte bounds.
    ///   - authority: Optional shared aggregate callback authority.
    ///   - maximumPendingInteractions: Positive private input event cap.
    ///   - maximumPendingBytes: Positive private input byte cap.
    ///   - maximumConcurrentHandlers: Positive router invocation cap.
    ///   - maximumDefinitionBytes: Positive explicit registration JSON bound.
    ///   - limits: Existing interaction model decoding bounds.
    ///   - failurePolicy: Explicit fail-fast or isolated invocation handling.
    ///   - failureObserver: Finite synchronous redacted failure observer.
    /// - Throws: Existing catalog, router, queue-bound or registration validation errors.
    public init(applicationID: ApplicationID, commands: CompiledCommands, services: BotServiceAdapter<C>,
        clock: C, admission: InteractionAcknowledgementAdmission, guildID: GuildID? = nil,
        configuration: GatewayEventHandlerConfiguration = try! .init(), authority: GatewayHandlerAuthority? = nil,
        maximumPendingInteractions: Int = 256, maximumPendingBytes: Int = 8 * 1_024 * 1_024,
        maximumConcurrentHandlers: Int = 64, maximumDefinitionBytes: Int = 1_048_576,
        limits: JSONLimits = .default, failurePolicy: GatewayInvocationFailurePolicy = .failFast,
        failureObserver: BotFailureObserver? = nil) throws {
        self.applicationID = applicationID
        self.services = services
        self.clock = InteractionClock(clock)
        self.admission = admission
        self.limits = limits
        self.failurePolicy = failurePolicy
        self.failureObserver = failureObserver
        router = try commands.makeRouter(maximumConcurrentHandlers: maximumConcurrentHandlers)
        reconciler = try CommandReconciler(applicationID: applicationID, guildID: guildID,
            definitions: commands.definitions, maximumDefinitionBytes: maximumDefinitionBytes)
        hub = GatewayEventHub(configuration: try .init(maximumSubscriptions: 1,
            maximumBufferedEvents: maximumPendingInteractions, maximumBufferedBytes: maximumPendingBytes,
            maximumEventsPerSubscription: maximumPendingInteractions, maximumBytesPerSubscription: maximumPendingBytes))
        dispatcher = GatewayEventHandlerDispatcher(configuration: configuration, authority: authority)
    }

    /// Validates a finite command host and stores shared authorities without invoking injected work.
    /// - Parameters:
    ///   - applicationID: Expected interaction and explicit registration application owner.
    ///   - commands: Complete compiled command/interaction catalog, including route-only families.
    ///   - services: Shared bot REST services and separately admitted exact-token HTTP response factories.
    ///   - clock: Monotonic clock shared with the client and HTTP clients; socket receipt age is preserved.
    ///   - admission: Shared initial-only acknowledgement count/byte authority, independent of ordinary REST.
    ///   - guildID: Explicit registration scope, default nil for global; dispatch still checks application ID.
    ///   - configuration: Existing dispatcher task/retained-event bounds, default four tasks and 128 events.
    ///     Complete-shard serialization is preserved by default; explicit concurrent interaction
    ///     dispatch retains these same task and event bounds.
    ///   - authority: Optional aggregate handler authority, shared explicitly with other event pipelines.
    ///   - maximumPendingInteractions: Positive private input queue cap, default 256, in addition to
    ///     the dispatcher's separately bounded retained events. Overflow fails the supervised host closed.
    ///   - maximumPendingBytes: Positive private queue envelope-byte cap, default 8 MiB.
    ///   - maximumConcurrentHandlers: Positive existing command-router aggregate cap, default 64.
    ///   - maximumDefinitionBytes: Positive explicit registration JSON bound, default 1 MiB.
    ///   - limits: Existing interaction JSON decoding bounds, default standard model limits.
    ///   - serializesPerShard: True preserves legacy complete-shard ordering. False allows independent
    ///     interaction callbacks on one shard to overlap, preventing an already acknowledged slow command
    ///     from consuming a later command's initial-response window. Handlers must support concurrency;
    ///     response ownership, receipt deadlines, shared admission and joined cleanup remain unchanged.
    ///   - failurePolicy: Fail-fast by default; explicit continuation isolates ordinary invocation failures.
    ///     Preparation, untrusted/malformed input, wrong identity, cancellation and host failures stay terminal.
    ///   - failureObserver: Optional synchronous nonthrowing safe diagnostic callback. It runs inline once
    ///     per failed invocation, may run concurrently across shards, and must return promptly. No original
    ///     error or interaction is passed, and the adapter retains no diagnostic history or observer tasks.
    /// - Throws: Existing router/catalog/reconciler or nonpositive queue-bound validation errors.
    /// No application auto-defer timer exists; typed deferred handlers retain their explicit ownership.
    public init(applicationID: ApplicationID, commands: CompiledCommands, services: BotServiceAdapter<C>,
        clock: C, admission: InteractionAcknowledgementAdmission, guildID: GuildID? = nil,
        configuration: GatewayEventHandlerConfiguration = try! .init(), authority: GatewayHandlerAuthority? = nil,
        maximumPendingInteractions: Int = 256, maximumPendingBytes: Int = 8 * 1_024 * 1_024,
        maximumConcurrentHandlers: Int = 64, maximumDefinitionBytes: Int = 1_048_576,
        limits: JSONLimits = .default, serializesPerShard: Bool, failurePolicy: GatewayInvocationFailurePolicy = .failFast,
        failureObserver: BotFailureObserver? = nil) throws {
        self.applicationID = applicationID
        self.services = services
        self.clock = InteractionClock(clock)
        self.admission = admission
        self.limits = limits
        self.failurePolicy = failurePolicy
        self.failureObserver = failureObserver
        router = try commands.makeRouter(maximumConcurrentHandlers: maximumConcurrentHandlers)
        reconciler = try CommandReconciler(applicationID: applicationID, guildID: guildID,
            definitions: commands.definitions, maximumDefinitionBytes: maximumDefinitionBytes)
        hub = GatewayEventHub(configuration: try .init(maximumSubscriptions: 1,
            maximumBufferedEvents: maximumPendingInteractions, maximumBufferedBytes: maximumPendingBytes,
            maximumEventsPerSubscription: maximumPendingInteractions, maximumBytesPerSubscription: maximumPendingBytes))
        dispatcher = GatewayEventHandlerDispatcher(configuration: configuration, authority: authority,
            serializesPerShard: serializesPerShard)
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
        DiscordLog.makeLogger("bot.interactions").debug("Trusted Gateway interaction bridge preparation started", metadata: ["dk.event": "bot_dsl.interactions.preparing"])
        do {
            try Task.checkCancellation()
            guard !stopped else { throw CancellationError() }
            let subscription = try await hub.subscribe()
            self.subscription = subscription
            DiscordLog.makeLogger("bot.interactions").trace("Private Gateway interaction subscription acquired", metadata: ["dk.event": "bot_dsl.interactions.subscription_acquired"])
            try await client.setInteractionHandler { event in try await self.receive(event) }
            DiscordLog.makeLogger("bot.interactions").trace("Private trusted client interaction receiver installed", metadata: ["dk.event": "bot_dsl.interactions.receiver_installed"])
            try Task.checkCancellation()
            guard !stopped else { throw CancellationError() }
            DiscordLog.makeLogger("bot.interactions").debug("Trusted Gateway interaction bridge prepared", metadata: ["dk.event": "bot_dsl.interactions.prepared"])
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
        DiscordLog.makeLogger("bot.interactions").trace("Gateway interaction input admission started", metadata: ["dk.event": "bot_dsl.interactions.receiving"])
        try Task.checkCancellation()
        guard !stopped else { throw CancellationError() }
        guard event.elapsedSinceReceipt != nil else { throw GatewayInteractionFailure.untrustedEvent }
        guard event.opcode == 0, event.name == "INTERACTION_CREATE" else { return }
        let publication = await hub.publish(event)
        guard publication.delivered == 1, publication.terminated == 0 else {
            DiscordLog.makeLogger("bot.interactions").warning("Trusted interaction queue cannot preserve continuity", metadata: ["dk.event": "bot_dsl.interactions.delivery_failed"])
            throw GatewayEventDeliveryFailure.resynchronizationRequired
        }
        DiscordLog.makeLogger("bot.interactions").trace("Trusted Gateway interaction queued", metadata: ["dk.event": "bot_dsl.interactions.queued"])
    }

    /// Runs the prepared private dispatcher until failure or supervised cancellation, joining all handlers.
    /// - Parameter reportingStage: Internal supervised composition option, default false. True preserves
    ///   an operation-stage envelope for the runtime, which unwraps the original error before public rethrow.
    /// - Throws: Repeated/missing preparation, malformed/wrong-application input, owner/continuity errors
    ///   or cancellation. Fail-fast also propagates invocation failures unchanged. Explicit continuation
    ///   observes handler/response and unmatched-command failures after releasing all invocation ownership.
    /// Cancellation closes the queue and awaits cooperative callbacks; noncooperative injected work cannot
    /// be forcibly terminated. Receipt-relative three-second and fifteen-minute response limits are unchanged.
    package func run(reportingStage: Bool = false) async throws {
        guard !started else { throw GatewayInteractionFailure.alreadyRun }
        started = true
        guard prepared, let subscription else { throw GatewayInteractionFailure.notPrepared }
        DiscordLog.makeLogger("bot.interactions").info("Trusted Gateway interaction dispatcher started", metadata: ["dk.event": "bot_dsl.interactions.started"])
        do {
            try Task.checkCancellation()
            guard !stopped else { throw CancellationError() }
            let dispatcher = self.dispatcher, applicationID = self.applicationID, services = self.services
            let clock = self.clock, admission = self.admission, router = self.router, limits = self.limits
            let policy = failurePolicy, observer = failureObserver
            let task = Task {
                try await dispatcher.run(subscription: subscription) { event in
                    do {
                        DiscordLog.makeLogger("bot.interactions").trace("Decoding trusted Gateway interaction envelope", metadata: ["dk.event": "bot_dsl.interactions.decoding"])
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
                        guard CommandRouteKey.incoming(interaction) != nil else {
                            throw DiscordError.validation(.invalidValue)
                        }
                        DiscordLog.makeLogger("bot.interactions").trace("Trusted interaction provenance and application validated", metadata: ["dk.event": "bot_dsl.interactions.validated"])
                        let responder = InteractionResponder(interaction: interaction, deliveryMode: .gateway,
                            clock: clock, sink: services.responseSink(for: interaction), admission: admission,
                            receivedAt: receivedAt)
                        let context = try InteractionContext(interaction: interaction, deliveryMode: .gateway, responder: responder)
                        DiscordLog.makeLogger("bot.interactions").trace("Gateway response ownership normalized for routing", metadata: ["dk.event": "bot_dsl.interactions.normalized"])
                        do {
                            try await InteractionFailureScope.$captureOperationFailures.withValue(true) {
                                guard try await router.route(context) else { throw GatewayInteractionFailure.unmatchedCommand }
                            }
                            DiscordLog.makeLogger("bot.interactions").debug("Trusted Gateway interaction completed", metadata: ["dk.event": "bot_dsl.interactions.completed"])
                        } catch {
                            let operation = error as? InteractionOperationFailure
                            let original = operation?.underlying ?? error
                            if original is CancellationError { throw original }
                            let stage: BotFailureStage = switch operation?.stage {
                            case .preparation, .none: .interactions
                            case .handler: .handler
                            case .acknowledgement: .acknowledgement
                            case .continuation: .continuation
                            }
                            let diagnosticSource: any Error = switch operation?.ownerFailure {
                            case .rateLimit(let failure): failure
                            case .transport(let failure): failure
                            case .none: original
                            }
                            let diagnostic = BotFailureDiagnostic(classifying: diagnosticSource, stage: stage)
                            observer?(diagnostic)
                            if policy == .continueInvocations,
                               operation?.ownerFailure == nil,
                               Self.canContinue(original, stage: operation?.stage), !Task.isCancelled {
                                Self.logInvocation(diagnostic)
                                return
                            }
                            throw BotFailureObservationError(original: original, diagnostic: diagnostic)
                        }
                    } catch {
                        if error is CancellationError { throw error }
                        if error is BotFailureObservationError { throw error }
                        throw BotFailureObservationError(original: error,
                            diagnostic: BotFailureDiagnostic(classifying: error, stage: .interactions))
                    }
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
            if !reportingStage, let failure = error as? BotFailureObservationError { throw failure.original }
            throw error
        }
        await cancel()
        DiscordLog.makeLogger("bot.interactions").info("Trusted Gateway interaction dispatcher stopped", metadata: ["dk.event": "bot_dsl.interactions.stopped"])
    }

    /// Determines whether a failed, already authenticated invocation may release the dispatcher callback.
    /// - Parameters:
    ///   - error: Original error, inspected only by closed typed cases; no text or reflection is used.
    ///   - stage: Exact route/response stage, or nil only for an unmatched command.
    /// - Returns: False for preparation, cancellation and owner/control failures. Other matched handler
    ///   and response failures may end only their invocation; uncertainty never authorizes replay.
    private nonisolated static func canContinue(_ error: any Error, stage: InteractionOperationStage?) -> Bool {
        if error is CancellationError { return false }
        if let failure = error as? DiscordError, failure == .cancelled { return false }
        if stage == .preparation { return false }
        if let failure = error as? GatewayInteractionFailure { return failure == .unmatchedCommand }
        if error is GatewayFailure || error is GatewayEventDeliveryFailure || error is ClientFailure ||
            error is BotRuntimeFailure || error is BotRuntimeFailures || error is ShardOwnershipFailure ||
            error is RuntimeCleanupFailure { return false }
        if let failure = error as? RateLimitFailure {
            switch failure {
            case .closed, .invalidRequest, .unknownReservation, .coordinatorUnavailable: return false
            case .queueFull, .metadataFull, .deadlineExceeded, .reservationExpired: break
            }
        }
        if let failure = error as? TransportFailure {
            switch failure {
            case .closed, .concurrentRead, .invalidLimit, .scriptExhausted: return false
            case .deadlineExceeded, .chunkTooLarge: break
            }
        }
        if let failure = error as? InteractionLifecycleError {
            switch failure {
            case .invalidConfiguration, .contextMismatch: return false
            default: break
            }
        }
        return stage != nil
    }

    /// Emits one finite fixed diagnostic for an explicitly recovered invocation without retaining input.
    /// - Parameter diagnostic: Closed category/stage and optional numeric protocol evidence only.
    private nonisolated static func logInvocation(_ diagnostic: BotFailureDiagnostic) {
        var metadata = diagnostic.logMetadata
        metadata["dk.event"] = "bot_dsl.invocation.failed"
        DiscordLog.makeLogger("bot.interactions").notice("Gateway invocation failed; dispatcher continues by explicit policy", metadata: metadata)
    }

    /// Reads aggregate router and private queue ownership for package regression evidence.
    /// - Returns: Current bounded counts; values are separate actor observations, not a transactional snapshot.
    internal func snapshot() async -> GatewayInteractionSnapshot {
        let queue = await hub.snapshot()
        return GatewayInteractionSnapshot(activeHandlers: await router.activeHandlerCount,
            bufferedEvents: queue.bufferedEvents, bufferedBytes: queue.bufferedBytes, subscriptions: queue.subscriptions)
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
