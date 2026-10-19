import DiscordCore
import DiscordGateway
import DiscordHTTP
import DiscordTransport
import Foundation

/// Consumer lifecycle independent of individual shard reconnect phases.
public enum ClientPhase: String, Sendable { case idle, discovering, running, stopping, stopped, failed }

/// Bounded diagnostics excluding tokens, sessions, resource payloads and server text.
public struct ClientSnapshot: Sendable {
    public let phase: ClientPhase
    public let shards: [GatewayShardSnapshot]
    public let ready: Bool
}

/// Supervised single-use bot composition with explicit service and event access.
///
/// Construction performs no I/O and launches no tasks. `run` owns discovery, shard
/// lifetimes and ingestion as structured children; handlers are independently adopted
/// through the event hub. Per-shard order is preserved, with no global order,
/// completeness or exactly-once guarantee. Share credential-scoped authorities and
/// aggregate cache/subscriber/handler budgets across clients as documented.
public actor DiscordClient<C: Clock, Leases: ShardLeaseStore>: CustomStringConvertible,
    CustomReflectable where C.Duration == Duration, Leases.LeaseClock == C {
    public nonisolated let events: GatewayEventHub
    public nonisolated let services: ServiceContext<C>
    public nonisolated let configuration: ClientConfiguration
    private let token: BotToken
    private let clock: C
    private let transport: any WebSocketTransport
    private let leases: Leases
    private let authority: ClientAuthority<C>
    private let project: @Sendable (GatewayEvent) async throws -> Void
    private let cleanup: @Sendable () async -> Void
    private var interactionHandler: (@Sendable (GatewayEvent) async throws -> Void)?
    private var phase: ClientPhase = .idle
    private var shards: [GatewayShard<C, Leases>] = []
    private var reservation: UInt64?
    private var cleaned = false
    private let stopSignal = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
    private let completion = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
    private var completionWait: Task<Void, Never>?

    /// Stores explicit runtime and ownership boundaries without any hidden work.
    /// - Parameters:
    ///   - token: Bot credential matching services and authority; never appears in diagnostics.
    ///   - configuration: Explicit intents and finite topology/ingestion limits.
    ///   - services: Authenticated typed REST access, usable before Gateway is ready.
    ///   - transport: Injected WebSocket connector; active connections become shard-owned.
    ///   - clock: Monotonic clock shared with leases, startup and REST coordination.
    ///   - leases: Shared fail-closed shard ownership; external stores support worker handoff.
    ///   - authority: Shared bot identity/startup/opcode and aggregate session accounting.
    ///   - events: Independent bounded broadcast hub, created by the caller without tasks.
    ///   - project: Optional bounded state reducer called before publication, default no cache.
    ///     It must not call arbitrary user handlers. A slow reducer can exhaust the raw queue
    ///     and explicitly terminate the session; it cannot suspend heartbeat/control work.
    ///   - cleanup: Optional idempotent owner cleanup, default empty for shared dependencies.
    ///     Runs once after all children exit, including pre-run shutdown. Supply closure-owned
    ///     adapter/coordinator cleanup only when this client owns their complete lifetime.
    public init(token: BotToken, configuration: ClientConfiguration, services: ServiceContext<C>,
                transport: any WebSocketTransport, clock: C, leases: Leases,
                authority: ClientAuthority<C>, events: GatewayEventHub,
                project: @escaping @Sendable (GatewayEvent) async throws -> Void = { _ in },
                cleanup: @escaping @Sendable () async -> Void = {}) {
        self.token = token; self.configuration = configuration; self.services = services
        self.transport = transport; self.clock = clock; self.leases = leases
        self.authority = authority; self.events = events; self.project = project; self.cleanup = cleanup
    }

    /// Installs the package-owned interaction queue before this single-use client starts.
    /// Public broadcast publication and replay events never invoke this callback. The callback must
    /// only enqueue bounded input: decoding, HTTP operations and user handlers belong to its separate
    /// supervised dispatcher. Installation neither subscribes nor starts the client.
    /// - Parameter handler: Sole trusted ingestion receiver, called before optional cache projection.
    /// - Throws: `alreadyRunning` if installation was already performed or the client left idle state.
    package func setInteractionHandler(_ handler: @escaping @Sendable (GatewayEvent) async throws -> Void) throws {
        guard phase == .idle, interactionHandler == nil else { throw ClientFailure.alreadyRunning }
        interactionHandler = handler
    }

    /// Discovers v10 topology and supervises all selected sessions until shutdown or failure.
    /// Only one invocation is accepted, including after a completed or failed run.
    /// Cancellation awaits socket/lease/task/queue cleanup and terminates subscriptions.
    /// - Throws: Cancellation; sanitized HTTP/Gateway/ownership errors; invalid topology or
    ///   aggregate resource exhaustion. Projection failures become `invalidPayload` without
    ///   exposing dependency text. No automatic client restart resets shared budgets.
    public func run() async throws {
        guard phase == .idle else {
            if phase == .stopped || phase == .failed { throw ClientFailure.stopped }
            throw ClientFailure.alreadyRunning
        }
        phase = .discovering
        startCompletionWait()
        var failure: (any Error)?
        do {
            try Task.checkCancellation()
            try await withThrowingTaskGroup(of: Bool.self) { group in
                group.addTask { try await self.runWork(); return true }
                group.addTask {
                    for await _ in self.stopSignal.stream { return false }
                    return false
                }
                do {
                    while let workFinished = try await group.next() {
                        if workFinished { break }
                        group.cancelAll()
                        await self.stopShards()
                        // Join work explicitly so a lease-release failure cannot disappear
                        // behind the earlier shutdown signal.
                    }
                } catch {
                    var terminal = error
                    group.cancelAll(); await self.stopShards()
                    while !group.isEmpty {
                        do { _ = try await group.next() }
                        catch { if terminal is CancellationError { terminal = error } }
                    }
                    if !(terminal is CancellationError && phase == .stopping && !Task.isCancelled) { throw terminal }
                }
                group.cancelAll()
                await self.stopShards()
            }
            try Task.checkCancellation()
        } catch { failure = error }
        phase = failure == nil || failure is CancellationError ? .stopped : .failed
        await events.finish()
        if let reservation { self.reservation = nil; await authority.budget.release(reservation) }
        await cleanupOnce()
        stopSignal.continuation.finish()
        completion.continuation.finish()
        await completionWait?.value
        if let failure { throw failure }
    }

    /// Requests stop and awaits the owning run's complete structured cleanup.
    /// Repeated/concurrent calls are harmless, including from an event handler or MainActor.
    /// Callers must not invoke this from the state reducer or owner cleanup callback:
    /// both belong to the same run and would await their own completion.
    /// Before `run`, shutdown permanently closes this client without discovering or leasing.
    public func shutdown() async {
        if phase == .idle {
            startCompletionWait()
            phase = .stopped
            await events.finish(); await cleanupOnce()
            stopSignal.continuation.finish(); completion.continuation.finish()
            await completionWait?.value
            return
        }
        if phase != .stopped && phase != .failed {
            phase = .stopping
            stopSignal.continuation.yield(())
        }
        // Awaiting the shared owned task cannot cancel its stream when this caller is cancelled.
        await completionWait?.value
    }

    /// Reads bounded nonsecret shard/session diagnostics; readiness can change after return.
    /// - Returns: Current client phase, selected shard snapshots and all-shards-ready flag.
    public func snapshot() async -> ClientSnapshot {
        var values: [GatewayShardSnapshot] = []
        for shard in shards { values.append(await shard.snapshot()) }
        return ClientSnapshot(phase: phase, shards: values,
            ready: phase == .running && !values.isEmpty && values.allSatisfy { $0.phase == .ready })
    }

    /// Sends a validated typed command through an explicitly selected local shard.
    /// - Parameters:
    ///   - command: Existing v10 command contract, including intents/rate/resource requirements.
    ///   - shardIndex: Fixed topology index assigned to this client.
    /// - Throws: `notReady` for absent/inactive shards, or Gateway admission/write failures.
    public func send(_ command: GatewayCommand, shardIndex: Int) async throws {
        guard phase == .running, let shard = shards.first(where: { $0.identity.index == shardIndex }) else {
            throw ClientFailure.notReady
        }
        try await shard.send(command)
    }

    /// Issues one bounded correlated request without consuming broadcast events.
    /// - Parameters:
    ///   - command: Validated member, soundboard or channel-info request; never automatically replayed.
    ///   - shardIndex: Explicit assigned topology index.
    ///   - timeout: Finite positive request deadline, default 30 seconds, at most one day.
    /// - Returns: Correlated responses in the command's documented deterministic result order.
    /// - Throws: `notReady`, cancellation or Gateway request failures carrying bounded partials.
    public func request(_ command: GatewayCommand, shardIndex: Int,
                        timeout: Duration = .seconds(30)) async throws -> GatewayRequestResult {
        guard phase == .running, let shard = shards.first(where: { $0.identity.index == shardIndex }) else {
            throw ClientFailure.notReady
        }
        return try await shard.request(command, timeout: timeout)
    }

    /// Conceals credential and dependency payloads from ordinary diagnostics.
    public nonisolated var description: String { "DiscordClient(redacted)" }
    /// Prevents reflection from walking credential-bearing dependencies.
    public nonisolated var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }

    /// Performs cancellable discovery and owns bounded shard ingestion siblings.
    /// - Throws: Existing v10 discovery/topology/admission/shard failures or cancellation.
    private func runWork() async throws {
        reservation = try await authority.budget.reserve(shards: 0, configuration: configuration.shard)
        try Task.checkCancellation()
        let discovery = try await services.execute(GatewayEndpoints.bot())
        try Task.checkCancellation()
        let identities = try discovery.shards(botID: authority.botID,
            topologyGeneration: configuration.topologyGeneration, indices: configuration.shardIndices,
            maximumShards: configuration.maximumShards)
        guard let reservation else { throw ClientFailure.capacityExceeded }
        try await authority.budget.resize(reservation, shards: identities.count, configuration: configuration.shard)
        try Task.checkCancellation()
        let startup = try await authority.startupCoordinator(discovery: discovery)
        try Task.checkCancellation()
        shards = identities.map { identity in
            GatewayShard(identity: identity, token: token, intents: configuration.intents.rawValue,
                discovery: discovery, transport: transport, clock: clock, leases: leases,
                startup: startup, configuration: configuration.shard, commandCoordinator: authority.commands)
        }
        phase = .running
        let bot = try GatewayBot(shards: shards, maximumShards: configuration.maximumShards)
        try await withThrowingTaskGroup(of: Bool.self) { group in
            group.addTask { try await bot.run(); return true }
            for shard in shards { group.addTask { try await self.ingest(shard); return false } }
            do {
                // Ingestion EOF precedes lease release; only bot completion certifies cleanup.
                while let botFinished = try await group.next() { if botFinished { break } }
            }
            catch {
                var terminal = error
                group.cancelAll(); await bot.stop()
                while !group.isEmpty {
                    do { _ = try await group.next() }
                    catch { if terminal is CancellationError { terminal = error } }
                }
                throw terminal
            }
            group.cancelAll(); await bot.stop()
        }
    }

    /// Drains each bounded raw batch in shard order, queues trusted interaction dispatches before
    /// optional state projection, then publishes independent public broadcast copies. The package-only
    /// interaction receiver can enqueue bounded input only; arbitrary handlers and HTTP response work
    /// belong to a separately supervised dispatcher. Public hub publication never calls this receiver.
    /// - Parameter shard: This run's exclusive raw queue consumer; raw ownership is never transferred.
    /// - Throws: Cancellation, raw ingestion/queue failures, or sanitized `invalidPayload` for private
    ///   receiver/projection failure. A failed event is not published or replayed. Actor suspension
    ///   permits other shards to progress; heartbeat/control receive remains owned by the shard.
    private func ingest(_ shard: GatewayShard<C, Leases>) async throws {
        while let batch = try await shard.nextEvents(maximum: configuration.ingestionBatchSize) {
            for event in batch {
                try Task.checkCancellation()
                do {
                    if event.opcode == 0, event.name == "INTERACTION_CREATE" {
                        try await interactionHandler?(event)
                    }
                    try await project(event)
                }
                catch is CancellationError { throw CancellationError() }
                catch { throw GatewayFailure.invalidPayload }
                _ = await events.publish(event)
            }
        }
    }

    /// Requests simultaneous bounded shard drains; group scope awaits connection cleanup.
    private func stopShards() async {
        await withTaskGroup(of: Void.self) { group in
            for shard in shards { group.addTask { await shard.stop() } }
        }
    }

    /// Releases the private interaction receiver and transfers optional dependency cleanup exactly
    /// once before its suspension point. Running clients call this only after ingestion children join;
    /// pre-run shutdown drops the idle receiver without discovering, leasing or retaining its catalog.
    private func cleanupOnce() async {
        guard !cleaned else { return }
        cleaned = true
        interactionHandler = nil
        await cleanup()
    }

    /// Starts one explicitly owned completion waiter when run/shutdown begins, never at construction.
    /// It owns no payload or user work and is awaited by run and every shutdown caller, including
    /// cancelled callers. This avoids allowing one cancelled AsyncStream iterator to release others.
    private func startCompletionWait() {
        guard completionWait == nil else { return }
        let stream = completion.stream
        completionWait = Task { for await _ in stream {} }
    }
}
