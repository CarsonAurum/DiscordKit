import DiscordBotDSL
import DiscordClient
import DiscordCore
import DiscordDSL
import DiscordGateway
import DiscordHTTP
import DiscordLogging
import DiscordTestSupport
import DiscordTransport
import Foundation
import Testing

/// Real client supervision over finite in-memory HTTP/WebSocket peers; no Discord service is contacted.
@Suite("Supervised bot lifetime", .timeLimit(.minutes(1)))
struct LifecycleTests {
    /// A complete synthetic bot run exposes subscription-before-client ordering and joined cleanup across module labels.
    /// - Throws: Unexpected offline fixture, synchronization, run or shutdown failure.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func detailedLifecycleLogging() async throws {
        let logs = LogRecorder(maximumEntries: 2048)
        let fixture = try BotLifecycleFixture()
        let runtime = try DiscordLog.$loggerFactory.withValue({ logs.makeLogger($0) }) { try fixture.runtime() }
        #expect(logs.entries.isEmpty)
        try await DiscordLog.$loggerFactory.withValue({ logs.makeLogger($0) }) {
            let run = Task { try await runtime.run() }
            try await fixture.delivered.wait()
            try await runtime.shutdown()
            try await run.value
        }
        let entries = logs.entries
        let events = entries.compactMap { $0.metadata["dk.event"]?.description }
        let subscribed = try #require(events.firstIndex(of: "bot_dsl.events.subscribed"))
        let clientStarted = try #require(events.firstIndex(of: "client.run.started"))
        let cleanup = try #require(events.lastIndex(of: "bot_dsl.runtime.cleanup_completed"))
        let stopped = try #require(events.lastIndex(of: "bot_dsl.runtime.stopped"))
        #expect(subscribed < clientStarted)
        #expect(cleanup < stopped)
        for event in ["client.discovery.reserving", "client.discovery.received", "client.discovery.validated",
            "client.discovery.budget_resized", "client.discovery.startup_acquired", "client.ingestion.projected",
            "client.ingestion.published", "bot_dsl.handler.entered", "bot_dsl.handler.exited",
            "bot_dsl.runtime.children_joined", "client.cleanup.dependencies_released"] {
            #expect(events.contains(event))
        }
        #expect(entries.contains { $0.label == "discordkit.bot.lifecycle" && $0.level == .info && $0.metadata["dk.event"] == "bot_dsl.runtime.stopped" })
        #expect(entries.contains { $0.label == "discordkit.client.discovery" && $0.level == .trace })
        let botScope = try #require(entries.first { $0.metadata["dk.event"] == "bot_dsl.runtime.operation.started" })
        let clientScope = try #require(entries.first { $0.metadata["dk.event"] == "client.run.operation.started" })
        let clientDiscovery = try #require(entries.first { $0.metadata["dk.event"] == "client.discovery.started" })
        #expect(botScope.metadata["dk.trace_id"] != nil)
        #expect(clientScope.metadata["dk.trace_id"] == botScope.metadata["dk.trace_id"])
        #expect(clientScope.metadata["dk.parent_span_id"] == botScope.metadata["dk.span_id"])
        #expect(clientDiscovery.metadata["dk.span_id"] == clientScope.metadata["dk.span_id"])
        #expect(entries.contains { $0.metadata["dk.event"] == "bot_dsl.runtime.operation.completed" && $0.metadata["dk.duration_ns"] != nil })
        let rendered = String(describing: entries.map { ($0.message, $0.metadata) })
        for privateValue in ["dsl-lifetime-offline-sentinel", "wss://gateway.discord.gg", "lifetime", "18446744073709551615"] {
            #expect(!rendered.contains(privateValue))
        }
        await fixture.expectEmpty()
    }

    /// Construction and pre-run stop perform no discovery; joining stop closes every owner once.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func inertConstructionAndStopBeforeRun() async throws {
        let fixture = try BotLifecycleFixture()
        let runtime = try fixture.runtime()
        #expect(await fixture.http.executionCount == 0)
        #expect(await fixture.hub.snapshot().subscriptions == 0)
        #expect(await runtime.phase == .idle)
        await runtime.requestStop()
        try await runtime.shutdown()
        try await runtime.shutdown()
        await #expect(throws: BotRuntimeFailure.stopped) { try await runtime.run() }
        #expect(await fixture.http.executionCount == 0)
        #expect(await fixture.cleanup.count == 1)
        await fixture.expectEmpty()
    }

    /// A pre-cancelled owner admits no HTTP work, and cancellation during discovery interrupts its script.
    /// - Parameter duringDiscovery: Whether cancellation occurs after the real HTTP adapter enters discovery.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [false, true]) func cancellationBeforeOrDuringDiscovery(_ duringDiscovery: Bool) async throws {
        let entered = TestBarrier(), blocked = TestBarrier()
        let http = try ScriptedHTTPTransport(steps: [{ _ in
            entered.open()
            try await blocked.wait()
            throw CancellationError()
        }])
        let fixture = try BotLifecycleFixture(http: http)
        let runtime = try fixture.runtime()
        let run = Task {
            if !duringDiscovery { while !Task.isCancelled { await Task.yield() } }
            try await runtime.run()
        }
        if duringDiscovery { try await entered.wait() }
        run.cancel()
        await #expect(throws: CancellationError.self) { try await run.value }
        #expect(await fixture.http.executionCount == (duringDiscovery ? 1 : 0))
        #expect(await fixture.cleanup.count == 1)
        await fixture.expectEmpty()
    }

    /// Stop racing the first scheduled client turn remains successful and never invents a stopped-client failure.
    /// Repetition exercises both child-start orderings while every iteration verifies complete local cleanup.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func immediateStopDuringClientStartup() async throws {
        for _ in 0..<32 {
            let fixture = try BotLifecycleFixture()
            let runtime = try fixture.runtime()
            let run = Task { try await runtime.run() }
            while await runtime.phase != .running { await Task.yield() }
            await runtime.requestStop()
            try await runtime.shutdown()
            try await run.value
            await fixture.expectEmpty()
        }
    }

    /// Event subscriptions precede discovery, live duplicate runs fail, and shutdown is repeatable.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func runningAndRepeatedShutdown() async throws {
        let fixture = try BotLifecycleFixture()
        let runtime = try fixture.runtime()
        let run = Task { try await runtime.run() }
        try await fixture.delivered.wait()
        #expect(await fixture.hub.snapshot().subscriptions == 1)
        await #expect(throws: BotRuntimeFailure.alreadyRunning) { try await runtime.run() }
        async let first: Void = runtime.shutdown()
        async let second: Void = runtime.shutdown()
        _ = try await (first, second)
        try await run.value
        try await runtime.shutdown()
        await #expect(throws: BotRuntimeFailure.stopped) { try await runtime.run() }
        #expect(await fixture.cleanup.count == 1)
        await fixture.expectEmpty()
    }

    /// A stop request made inside the owned handler returns without joining that handler's own task.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func handlerCanRequestStop() async throws {
        let reference = BotRuntimeReference()
        let fixture = try BotLifecycleFixture()
        let runtime = try fixture.runtime(callback: { await reference.requestStop() })
        await reference.install(runtime)
        try await runtime.run()
        try await runtime.shutdown()
        #expect(await fixture.cleanup.count == 1)
        await fixture.expectEmpty()
    }

    /// Failure in one event child stops the client and preserves the original callback error for all joiners.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func callbackFailureCancelsClientAndPersistsForShutdown() async throws {
        let fixture = try BotLifecycleFixture()
        let runtime = try fixture.runtime(callback: { throw BotLifecycleFailure.callback })
        await #expect(throws: BotLifecycleFailure.callback) { try await runtime.run() }
        await #expect(throws: BotLifecycleFailure.callback) { try await runtime.shutdown() }
        await #expect(throws: BotLifecycleFailure.callback) { try await runtime.shutdown() }
        #expect(await fixture.cleanup.count == 1)
        await fixture.expectEmpty()
    }

    /// A failed discovery cancels prepared event pipelines even though no Gateway socket was opened.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func discoveryFailureReleasesPreparedSubscriptions() async throws {
        let fixture = try BotLifecycleFixture(http: ScriptedHTTPTransport(steps: [{ _ in HTTPResponse(status: 400) }]))
        let runtime = try fixture.runtime()
        await #expect(throws: (any Error).self) { try await runtime.run() }
        #expect(await fixture.socket.closed == false)
        #expect(await fixture.cleanup.count == 1)
        await fixture.expectEmpty()
    }

    /// Cancellation of one joining caller cannot complete other callers while mandatory cleanup is held.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func cancelledCleanupWaiterCannotReleaseOtherWaiters() async throws {
        let fixture = try BotLifecycleFixture(holdCleanup: true)
        let runtime = try fixture.runtime()
        let run = Task { try await runtime.run() }
        try await fixture.delivered.wait()
        let observations = BotShutdownObservations()
        let first = Task {
            try await runtime.shutdown()
            await observations.record(await fixture.cleanup.completed)
        }
        try await fixture.cleanup.entered.wait()
        let secondEntered = TestBarrier()
        let second = Task {
            secondEntered.open()
            try await runtime.shutdown()
            await observations.record(await fixture.cleanup.completed)
        }
        try await secondEntered.wait()
        first.cancel()
        for _ in 0..<128 { await Task.yield() }
        #expect(await observations.returned == 0)
        await fixture.cleanup.unblock()
        try await first.value
        try await second.value
        try await run.value
        #expect(await observations.returned == 2)
        #expect(await observations.premature == false)
        await fixture.expectEmpty()
    }

    /// An event-free host still owns a live client and waits for explicit stop instead of treating empty pipelines as EOF.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func emptyEventCatalogKeepsClientRunning() async throws {
        let fixture = try BotLifecycleFixture()
        let events = try EventCompilation.compile(EmptyBotDefinition(), intents: [.guilds])
        let runtime = try BotRuntime(client: fixture.client, events: events,
            handlerConfiguration: .init(), handlerAuthority: fixture.authority)
        let observation = try await fixture.hub.subscribe()
        let run = Task { try await runtime.run() }
        var iterator = observation.makeAsyncIterator()
        #expect(try await iterator.next()?.name == "READY")
        #expect(await runtime.phase == .running)
        #expect(await fixture.hub.snapshot().subscriptions == 1)
        try await runtime.shutdown()
        try await run.value
        await fixture.expectEmpty()
    }

    /// A compiled plan cannot silently enable intent bits absent from its actual client configuration.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func hostRejectsBroaderCompiledIntentsWithoutStartingWork() async throws {
        let fixture = try BotLifecycleFixture()
        let handler = BotLifecycleHandler(requiredIntents: [.guildMembers]) { _ in }
        let events = try EventCompilation.compile(Module(id: "broader") { handler }, intents: [.guildMembers])
        do {
            _ = try BotRuntime(client: fixture.client, events: events, handlerConfiguration: .init())
            Issue.record("Expected missing-intent host admission failure")
        } catch let diagnostic as EventCompilationDiagnostic {
            #expect(diagnostic.code == .missingIntents)
            #expect(diagnostic.missingIntents == [.guildMembers])
        }
        #expect(await fixture.http.executionCount == 0)
        await fixture.client.shutdown()
        await fixture.expectEmpty()
    }

    /// Distinct callback and remote-release failures are both retained after all owned children exit.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func multipleChildFailuresAreBoundedAndRedacted() async throws {
        let fixture = try BotLifecycleFixture(failRelease: true)
        let diagnostics = DiagnosticCapture()
        let runtime = try fixture.runtime(failureObserver: diagnostics.record) { throw BotLifecycleFailure.callback }
        do {
            try await runtime.run()
            Issue.record("Expected aggregated child failures")
        } catch let failures as BotRuntimeFailures {
            #expect(failures.primary as? BotLifecycleFailure == .callback)
            #expect(failures.additional.count == 1)
            #expect(failures.additional.first as? ShardOwnershipFailure == .coordinatorUnavailable)
            #expect(failures.diagnostics.map(\.stage) == [.events, .cleanup])
            #expect(failures.diagnostics.map(\.category) == [.unclassified, .shardOwnershipCoordinatorUnavailable])
            #expect(String(describing: failures) == "BotRuntimeFailures(redacted)")
            #expect(String(reflecting: failures).contains("redacted"))
        }
        await #expect(throws: BotRuntimeFailures.self) { try await runtime.shutdown() }
        await fixture.expectEmpty(expectedLeases: 1)
    }

    /// A late remote-release outage survives explicit stop and remains observable to every shutdown waiter.
    /// The remote lease remains fenced until expiry; all locally owned queues, permits and timers are empty.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func leaseReleaseFailureIsPreserved() async throws {
        let fixture = try BotLifecycleFixture(failRelease: true, holdRelease: true)
        let diagnostics = DiagnosticCapture()
        let runtime = try fixture.runtime(failureObserver: diagnostics.record)
        let run = Task { try await runtime.run() }
        try await fixture.delivered.wait()
        let shutdown = Task { try await runtime.shutdown() }
        try await fixture.leases.releaseEntered.wait()
        #expect(await fixture.budget.snapshot().clients == 1)
        await fixture.leases.allowRelease()
        await #expect(throws: ShardOwnershipFailure.coordinatorUnavailable) { try await run.value }
        await #expect(throws: ShardOwnershipFailure.coordinatorUnavailable) { try await shutdown.value }
        await #expect(throws: ShardOwnershipFailure.coordinatorUnavailable) { try await runtime.shutdown() }
        #expect(await fixture.leases.releaseCalls == 1)
        #expect(diagnostics.diagnostics.map(\.stage) == [.cleanup])
        #expect(diagnostics.diagnostics.map(\.category) == [.shardOwnershipCoordinatorUnavailable])
        #expect(await fixture.leases.retainedCount() == 1)
        #expect(await fixture.socket.closed)
        await fixture.expectEmpty(expectedLeases: 1)
    }
}

/// Fixed nonsecret callback failure for original-error propagation assertions.
private enum BotLifecycleFailure: Error, Equatable { case callback }

/// A real production client with finite script-backed dependencies and explicit remote-cleanup gates.
@available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
private struct BotLifecycleFixture {
    let clock = ManualClock()
    let delivered = TestBarrier()
    let http: ScriptedHTTPTransport
    let socket = BotLifecycleSocket()
    let hub: GatewayEventHub
    let authority: GatewayHandlerAuthority
    let budget: ClientResourceBudget
    let leases: BotLifecycleLeases
    let cleanup: BotLifecycleCleanup
    let client: DiscordClient<ManualClock, BotLifecycleLeases>

    /// Builds inert real client dependencies with optional HTTP suspension and remote cleanup failures.
    /// - Parameters:
    ///   - http: Optional finite transport script; nil serves one successful discovery response.
    ///   - holdCleanup: Whether final cleanup waits for an explicit test signal, default false.
    ///   - failRelease: Whether the injected remote lease store rejects release, default false.
    ///   - holdRelease: Whether remote release waits for its explicit signal, default false.
    /// - Throws: Invalid finite configuration, sentinel credential or response stream bounds.
    init(http: ScriptedHTTPTransport? = nil, holdCleanup: Bool = false,
        failRelease: Bool = false, holdRelease: Bool = false) throws {
        self.http = try http ?? ScriptedHTTPTransport(steps: [{ _ in
            let json = #"{"url":"wss://gateway.discord.gg","shards":1,"session_start_limit":{"total":100,"remaining":100,"reset_after":3600000,"max_concurrency":1}}"#
            let body = BotLifecycleBody(Data(json.utf8))
            return HTTPResponse(status: 200, body: try BodyStream(maximumChunkBytes: 4096,
                next: { await body.take() }, close: { await body.clear() }))
        }])
        hub = GatewayEventHub(configuration: try .init())
        authority = try GatewayHandlerAuthority(maximumActiveHandlers: 2, maximumWaitingHandlers: 2)
        budget = try ClientResourceBudget()
        leases = try BotLifecycleLeases(clock: clock, failRelease: failRelease, holdRelease: holdRelease)
        cleanup = BotLifecycleCleanup(hold: holdCleanup)
        let rest = RESTClient(credential: .bot(try BotToken("dsl-lifetime-offline-sentinel")),
            identity: RateLimitIdentity(), transport: self.http, coordinator: RateLimitCoordinator(clock: clock), clock: clock)
        let clientAuthority = try ClientAuthority(botID: UserID(rawValue: 42), clock: clock, budget: budget)
        let cleanup = cleanup
        client = DiscordClient(token: try BotToken("dsl-lifetime-offline-sentinel"),
            configuration: try ClientConfiguration(intents: [.guilds]), services: ServiceContext(rest: rest),
            transport: ScriptedWebSocketTransport(connection: socket), clock: clock, leases: leases,
            authority: clientAuthority, events: hub, cleanup: { await cleanup.perform() })
    }

    /// Compiles a raw event handler without running it and stores the real client in its supervised host.
    /// - Parameters:
    ///   - failureObserver: Optional finite synchronous safe diagnostic observation.
    ///   - callback: Optional finite callback behavior, default empty; called only after publication.
    /// - Returns: Inert single-use host with one compiled event group and shared aggregate admission.
    /// - Throws: Structural compilation or finite dispatcher validation errors.
    func runtime(failureObserver: BotFailureObserver? = nil,
        callback: @escaping @Sendable () async throws -> Void = {}) throws -> BotRuntime {
        let delivered = delivered
        let handler = BotLifecycleHandler { event in
            if event.name == "READY" { delivered.open(); try await callback() }
        }
        let events = try EventCompilation.compile(Module(id: "lifetime") { handler }, intents: [.guilds])
        return try BotRuntime(client: client, events: events, handlerConfiguration: try .init(), handlerAuthority: authority,
            failureObserver: failureObserver)
    }

    /// Checks final owned accounting after the runtime's joining API has completed.
    /// - Parameter expectedLeases: Zero normally; one when the injected remote release fails closed.
    func expectEmpty(expectedLeases: Int = 0) async {
        let hubState = await hub.snapshot(), handlers = await authority.snapshot()
        let resources = await budget.snapshot()
        #expect(hubState.subscriptions == 0)
        #expect(hubState.bufferedEvents == 0)
        #expect(hubState.bufferedBytes == 0)
        #expect(hubState.waitingConsumers == 0)
        #expect(handlers.activeHandlers == 0)
        #expect(handlers.waitingHandlers == 0)
        #expect(resources.clients == 0)
        #expect(resources.shards == 0)
        #expect(resources.rawEvents == 0)
        #expect(resources.rawBytes == 0)
        #expect(await leases.retainedCount() == expectedLeases)
        #expect(clock.pendingSleepCount == 0)
    }
}

/// One explicit reference resolves the application-owned runtime/handler composition cycle.
private actor BotRuntimeReference {
    private var runtime: BotRuntime?
    /// Installs the inert host before its run starts.
    /// - Parameter runtime: Single host selected by this test.
    func install(_ runtime: BotRuntime) { self.runtime = runtime }
    /// Requests nonjoining stop from inside an owned callback; no callback joins itself.
    func requestStop() async { await runtime?.requestStop() }
}

/// Two shutdown callers record only after mandatory cleanup has returned.
private actor BotShutdownObservations {
    private(set) var returned = 0
    private(set) var premature = false
    /// Records whether this caller returned after mandatory cleanup.
    /// - Parameter completed: Atomic cleanup completion observed immediately after shutdown.
    func record(_ completed: Bool) { returned += 1; premature = premature || !completed }
}

/// Finite body storage used by the scripted discovery transport.
private actor BotLifecycleBody {
    private var data: Data?
    /// Retains one small complete JSON response until transfer or close.
    /// - Parameter data: The finite credential-free body, smaller than 4096 bytes.
    init(_ data: Data) { self.data = data }
    /// Transfers the bytes once, then returns EOF.
    /// - Returns: Original bytes, or nil after transfer/close.
    func take() -> Data? { defer { data = nil }; return data }
    /// Idempotently discards unread fixture bytes.
    func clear() { data = nil }
}

/// Cleanup can be held to prove that cancelled joining waiters cannot escape the shared completion.
@available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
private actor BotLifecycleCleanup {
    nonisolated let entered = TestBarrier()
    private var hold: Bool
    private var waiter: CheckedContinuation<Void, Never>?
    private(set) var count = 0
    private(set) var completed = false
    /// Stores an optional mandatory-cleanup hold without starting work.
    /// - Parameter hold: Whether final cleanup must wait for `unblock`.
    init(hold: Bool) { self.hold = hold }
    /// Records exactly one client-owned cleanup and cooperatively completes only after its explicit hold.
    /// The continuation intentionally remains valid after cancellation of a shutdown caller.
    func perform() async {
        count += 1; entered.open()
        if hold { await withCheckedContinuation { waiter = $0 } }
        completed = true
    }
    /// Releases mandatory cleanup once; early or repeated releases are harmless.
    func unblock() { hold = false; waiter?.resume(); waiter = nil }
}

/// The real fenced ledger owns leases; only its remote-release operation can be delayed or rejected.
@available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
private actor BotLifecycleLeases: ShardLeaseStore {
    typealias LeaseClock = ManualClock
    nonisolated let releaseEntered = TestBarrier()
    private let base: InProcessShardLeaseStore<ManualClock>
    private let failRelease: Bool
    private var releaseAllowed: Bool
    private var waiter: CheckedContinuation<Void, Never>?
    private(set) var releaseCalls = 0
    /// Stores finite ownership and explicit outage behavior, without acquiring a lease.
    /// - Parameters:
    ///   - clock: Shared monotonic clock for expiry and production shard scheduling.
    ///   - failRelease: Whether release preserves remote authority and throws an outage.
    ///   - holdRelease: Whether release waits for `allowRelease`, ignoring owner cancellation.
    /// - Throws: Invalid production ledger capacity, fixed at two.
    init(clock: ManualClock, failRelease: Bool, holdRelease: Bool) throws {
        base = try InProcessShardLeaseStore(clock: clock, maximumLeases: 2)
        self.failRelease = failRelease; releaseAllowed = !holdRelease
    }
    /// Acquires through the real ledger with unchanged fencing and expiry semantics.
    /// - Parameters:
    ///   - shard: Validated fixed-topology shard identity.
    ///   - owner: Nonsecret worker identifier.
    ///   - lifetime: Positive monotonic lease duration.
    /// - Returns: Production validated lease ticket.
    /// - Throws: Original ledger admission, cancellation or ownership failures.
    func acquire(_ shard: ShardIdentity, owner: UUID, lifetime: Duration) async throws -> ShardLease<ManualClock> {
        try await base.acquire(shard, owner: owner, lifetime: lifetime)
    }
    /// Validates the original fenced ticket without changing it.
    /// - Parameter lease: Current production ticket.
    /// - Throws: Cancellation, expiry or stale fencing errors.
    func validate(_ lease: ShardLease<ManualClock>) async throws { try await base.validate(lease) }
    /// Renews through the production ledger without changing ownership scope.
    /// - Parameters:
    ///   - lease: Current fenced ticket.
    ///   - lifetime: Positive requested replacement expiry duration.
    /// - Returns: Fresh production ticket.
    /// - Throws: Original ledger cancellation, expiry or ownership failures.
    func renew(_ lease: ShardLease<ManualClock>, lifetime: Duration) async throws -> ShardLease<ManualClock> {
        try await base.renew(lease, lifetime: lifetime)
    }
    /// Performs mandatory release after its optional hold and reports the configured remote outage.
    /// - Parameter lease: Current ticket, retained remotely when release rejects.
    /// - Throws: `coordinatorUnavailable` for an injected outage, otherwise delegates successful release.
    func release(_ lease: ShardLease<ManualClock>) async throws {
        releaseCalls += 1; releaseEntered.open()
        if !releaseAllowed { await withCheckedContinuation { waiter = $0 } }
        if failRelease { throw ShardOwnershipFailure.coordinatorUnavailable }
        await base.release(lease)
    }
    /// Allows the held release to complete once; repeated signals are harmless.
    func allowRelease() { releaseAllowed = true; waiter?.resume(); waiter = nil }
    /// Reads the real ledger's current ownership count.
    /// - Returns: Zero after success, one after failed remote release until lease expiry.
    func retainedCount() async -> Int { await base.retainedLeaseCount() }
}

/// One authenticated READY dispatch followed by a cooperative receive wait drives the real shard.
@available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
private actor BotLifecycleSocket: WebSocketConnection {
    private let identified = TestBarrier(), idle = TestBarrier()
    private var index = 0
    private(set) var closed = false
    /// Parses only the opcode, never retaining Identify credentials or arbitrary wire content.
    /// - Parameters:
    ///   - message: Bounded complete outgoing JSON control frame.
    ///   - context: Production cancellation/deadline context.
    /// - Throws: Context or malformed fixture JSON errors.
    func send<C: Clock>(_ message: WebSocketMessage, context: TransportContext<C>) async throws where C.Duration == Duration {
        try context.check()
        guard case .text(let text) = message, case .object(let object) = try JSONValue.parse(text),
            case .number(let opcode) = object["op"] else { throw GatewayFailure.invalidPayload }
        if opcode.rawValue == "2" { identified.open() }
    }
    /// Emits Hello and Identify-gated READY, then waits without wall-clock sleeps.
    /// - Parameter context: Production cancellation/deadline context.
    /// - Returns: One finite protocol frame, or EOF after close.
    /// - Throws: Context failures or cancellation while waiting.
    func receive<C: Clock>(context: TransportContext<C>) async throws -> WebSocketMessage? where C.Duration == Duration {
        try context.check()
        if closed { return nil }
        let slot = index; index += 1
        switch slot {
        case 0: return .text(#"{"op":10,"d":{"heartbeat_interval":10000}}"#)
        case 1:
            try await identified.wait()
            return .text(#"{"op":0,"s":1,"t":"READY","d":{"session_id":"offline","resume_gateway_url":"wss://gateway.discord.gg"}}"#)
        default: try await idle.wait(); return nil
        }
    }
    /// Idempotently closes pending receives without external I/O.
    func close() { closed = true; identified.open(); idle.open() }
}

/// External-style handler conforms to the public protocol without adding production closure adapters.
private struct BotLifecycleHandler: GatewayEventHandler {
    let handlerID = "lifetime.ready"
    let selector = GatewayEventSelector<GatewayEvent>.raw
    var requiredIntents: GatewayIntents = []
    let work: @Sendable (GatewayEvent) async throws -> Void
    /// Executes the injected finite work only after explicit Gateway pipeline admission.
    /// - Parameters:
    ///   - event: Exact original bounded raw envelope.
    ///   - context: Original provenance, intentionally unused by this lifecycle fixture.
    /// - Throws: Original fixture callback failure or cancellation.
    func handle(_ event: GatewayEvent, context: GatewayEventContext) async throws { try await work(event) }
}
