import DiscordClient
import DiscordCore
import DiscordGateway
import DiscordHTTP
import DiscordTransport
import DiscordTestSupport
import Foundation
import Testing

/// Correlated facade delivery, cancellation-safe shutdown and observable terminal ownership failures.
@Suite("Client shutdown regressions", .timeLimit(.minutes(1)))
struct ClientRegressionTests {
    /// A live typed request receives its correlated chunk while the same event remains independently broadcast.
    /// Invalid shard selection is rejected while running without transmitting or consuming correlation state;
    /// the subsequent valid request succeeds, and ordinary shutdown releases every runtime resource.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func correlatedFacadeRequestAndRunningShardSelection() async throws {
        let fixture = try RegressionClientFixture(respondToMemberRequests: true)
        let subscription = try await fixture.hub.subscribe()
        let run = Task { try await fixture.client.run() }
        var iterator = subscription.makeAsyncIterator()
        #expect(try await iterator.next()?.name == "READY")
        #expect(await fixture.client.snapshot().ready)
        let command = try GatewayCommand.requestGuildMembers(guildID: GuildID(rawValue: 1),
            userIDs: [UserID(rawValue: 42)], nonce: "facade-request")
        await #expect(throws: ClientFailure.notReady) {
            try await fixture.client.send(.updatePresence(try GatewayPresence()), shardIndex: 99)
        }
        await #expect(throws: ClientFailure.notReady) {
            try await fixture.client.request(command, shardIndex: 99)
        }
        #expect(await fixture.socket.memberRequestCount == 0)
        let result = try await fixture.client.request(command, shardIndex: 0)
        #expect(result.events.count == 1)
        let correlated = try #require(result.events.first)
        #expect(correlated.name == "GUILD_MEMBERS_CHUNK")
        #expect(correlated.sequence == 2)
        #expect(correlated.shard.index == 0)
        #expect(correlated.socketGeneration == 1)
        let broadcast = try #require(try await iterator.next())
        #expect(broadcast.name == correlated.name)
        #expect(broadcast.sequence == correlated.sequence)
        #expect(broadcast.data == correlated.data)
        #expect(broadcast.socketGeneration == correlated.socketGeneration)
        #expect(await fixture.socket.memberRequestCount == 1)
        await fixture.client.shutdown()
        try await run.value
        #expect(try await iterator.next() == nil)
        #expect(await fixture.client.snapshot().phase == .stopped)
        #expect(await fixture.budget.snapshot().clients == 0)
        #expect(await fixture.leases.retainedCount() == 0)
        #expect(await fixture.socket.closed)
        #expect(await fixture.hub.snapshot().subscriptions == 0)
        #expect(fixture.clock.pendingSleepCount == 0)
    }

    /// A cancelled shutdown caller and an independent waiter both remain joined until owner cleanup finishes.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func cancelledShutdownWaiterCannotReleaseOtherWaiters() async throws {
        let fixture = try RegressionClientFixture(holdCleanup: true)
        let subscription = try await fixture.hub.subscribe()
        let run = Task { try await fixture.client.run() }
        var iterator = subscription.makeAsyncIterator()
        #expect(try await iterator.next()?.name == "READY")
        let observations = ShutdownObservations()
        let shutdown = Task {
            await fixture.client.shutdown()
            await observations.record(cleanupFinished: await fixture.cleanup.completed)
        }
        try await fixture.cleanup.entered.wait()
        let otherStarted = TestBarrier()
        let other = Task {
            otherStarted.open()
            await fixture.client.shutdown()
            await observations.record(cleanupFinished: await fixture.cleanup.completed)
        }
        try await otherStarted.wait()
        shutdown.cancel()
        // Give the cancelled waiter runnable turns while cleanup remains explicitly blocked.
        // This uses cooperative scheduling only, without a wall-clock timing dependency.
        for _ in 0..<128 { await Task.yield() }
        #expect(await observations.returned == 0)
        #expect(await fixture.cleanup.completed == false)
        await fixture.cleanup.unblock()
        await shutdown.value
        await other.value
        try await run.value
        #expect(await observations.returned == 2)
        #expect(await observations.returnedBeforeCleanup == false)
        #expect(await fixture.cleanup.count == 1)
        #expect(await fixture.budget.snapshot().clients == 0)
        #expect(await fixture.leases.retainedCount() == 0)
        #expect(await fixture.socket.closed)
        #expect(await fixture.hub.snapshot().subscriptions == 0)
    }

    /// Lease-release failure remains observable after ingestion EOF or an earlier explicit shutdown signal.
    /// - Parameter explicitShutdown: Stops the client instead of requesting a fatal peer close.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [false, true])
    func terminalLeaseReleaseFailureIsNotMasked(_ explicitShutdown: Bool) async throws {
        let fixture = try RegressionClientFixture(failRelease: true, holdRelease: true)
        let subscription = try await fixture.hub.subscribe()
        let run = Task { try await fixture.client.run() }
        var iterator = subscription.makeAsyncIterator()
        #expect(try await iterator.next()?.name == "READY")
        let shutdown: Task<Void, Never>?
        if explicitShutdown { shutdown = Task { await fixture.client.shutdown() } }
        else { shutdown = nil; fixture.socket.peerClose.open() }
        // Shard.finish closes ingestion before this deliberately held remote release.
        // Joining only the earlier ingestion/shutdown completion would hide its later error.
        try await fixture.leases.releaseEntered.wait()
        #expect(await fixture.budget.snapshot().clients == 1)
        await fixture.leases.allowRelease()
        await #expect(throws: ShardOwnershipFailure.coordinatorUnavailable) { try await run.value }
        await shutdown?.value
        #expect(await fixture.client.snapshot().phase == .failed)
        #expect(await fixture.cleanup.count == 1)
        #expect(await fixture.budget.snapshot().clients == 0)
        #expect(await fixture.leases.releaseCalls == 1)
        // A failed external release cannot claim handoff: authority is retained until expiry.
        #expect(await fixture.leases.retainedCount() == 1)
        #expect(await fixture.socket.closed)
        #expect(await fixture.hub.snapshot().subscriptions == 0)
        #expect(fixture.clock.pendingSleepCount == 0)
    }
}

/// Owns a single deterministic credential-free bot session and explicit cleanup/failure gates.
@available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
private struct RegressionClientFixture {
    let clock = ManualClock()
    let hub: GatewayEventHub
    let budget: ClientResourceBudget
    let leases: RegressionLeases
    let socket: RegressionClientSocket
    let cleanup: RegressionCleanup
    let client: DiscordClient<ManualClock, RegressionLeases>

    /// Creates bounded dependencies without running HTTP, Gateway, or user callbacks.
    /// - Parameters:
    ///   - holdCleanup: Keeps owner cleanup parked until `cleanup.unblock`, default false.
    ///   - failRelease: Throws a closed coordinator outage during remote release, default false.
    ///   - holdRelease: Parks release until `leases.allowRelease`, ignoring caller cancellation as cleanup must.
    ///   - respondToMemberRequests: Emits one complete correlated member chunk after an opcode-8 request,
    ///     default false; the targeted-user form requires no privileged member intent.
    /// - Throws: Invalid fixture transport, credential sentinel, or runtime-bound construction errors.
    init(holdCleanup: Bool = false, failRelease: Bool = false, holdRelease: Bool = false,
         respondToMemberRequests: Bool = false) throws {
        hub = GatewayEventHub(configuration: try .init())
        budget = try ClientResourceBudget()
        leases = try RegressionLeases(clock: clock, failRelease: failRelease, holdRelease: holdRelease)
        socket = RegressionClientSocket(respondToMemberRequests: respondToMemberRequests)
        cleanup = RegressionCleanup(hold: holdCleanup)
        let transport = try ScriptedHTTPTransport(steps: [{ _ in
            let json = #"{"url":"wss://gateway.discord.gg","shards":1,"session_start_limit":{"total":100,"remaining":100,"reset_after":3600000,"max_concurrency":1}}"#
            let body = RegressionResponseBody(Data(json.utf8))
            return HTTPResponse(status: 200, body: try BodyStream(maximumChunkBytes: 4_096,
                next: { await body.take() }, close: { await body.clear() }))
        }])
        let rest = RESTClient(credential: .bot(try BotToken("regression-test-sentinel")), identity: RateLimitIdentity(),
            transport: transport, coordinator: RateLimitCoordinator(clock: clock), clock: clock)
        let authority = try ClientAuthority(botID: UserID(rawValue: 42), clock: clock, budget: budget)
        let cleanup = cleanup
        client = DiscordClient(token: try BotToken("regression-test-sentinel"),
            configuration: try ClientConfiguration(intents: [.guilds]), services: ServiceContext(rest: rest),
            transport: ScriptedWebSocketTransport(connection: socket), clock: clock, leases: leases,
            authority: authority, events: hub, cleanup: { await cleanup.perform() })
    }
}

/// Single remote-release gate is intentionally uncancellable to model mandatory cleanup after owner cancellation.
@available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
private actor RegressionLeases: ShardLeaseStore {
    typealias LeaseClock = ManualClock
    nonisolated let releaseEntered = TestBarrier()
    private let base: InProcessShardLeaseStore<ManualClock>
    private let failRelease: Bool
    private var releaseAllowed: Bool
    private var releaseWaiter: CheckedContinuation<Void, Never>?
    private(set) var releaseCalls = 0

    /// Retains finite ownership state with an optional release outage and explicit noncancellable hold.
    /// - Parameters:
    ///   - clock: Injected monotonic clock shared with client and startup.
    ///   - failRelease: Whether release throws while retaining the original authority.
    ///   - holdRelease: Whether release awaits an explicit test signal.
    /// - Throws: Invalid base ownership capacity, fixed at two for this fixture.
    init(clock: ManualClock, failRelease: Bool, holdRelease: Bool) throws {
        base = try InProcessShardLeaseStore(clock: clock, maximumLeases: 2)
        self.failRelease = failRelease
        releaseAllowed = !holdRelease
    }

    /// Delegates atomic acquisition to the real in-process lease ledger.
    /// - Parameters:
    ///   - shard: Requested fixed-topology session.
    ///   - owner: Nonsecret worker identity.
    ///   - lifetime: Positive requested lease duration.
    /// - Returns: The real validated ownership ticket.
    /// - Throws: Base cancellation, capacity, topology, or existing-owner failures.
    func acquire(_ shard: ShardIdentity, owner: UUID, lifetime: Duration) async throws -> ShardLease<ManualClock> {
        try await base.acquire(shard, owner: owner, lifetime: lifetime)
    }

    /// Delegates fenced authority validation without changing stored ownership.
    /// - Parameter lease: Current ticket to verify.
    /// - Throws: Cancellation or stale/expired ownership.
    func validate(_ lease: ShardLease<ManualClock>) async throws { try await base.validate(lease) }

    /// Delegates replacement fencing and monotonic expiry to the real ledger.
    /// - Parameters:
    ///   - lease: Current ticket to renew.
    ///   - lifetime: Positive replacement duration from the injected instant.
    /// - Returns: A fresh ticket superseding the prior expiry/generation.
    /// - Throws: Base cancellation, invalid lifetime, or stale ownership.
    func renew(_ lease: ShardLease<ManualClock>, lifetime: Duration) async throws -> ShardLease<ManualClock> {
        try await base.renew(lease, lifetime: lifetime)
    }

    /// Records release before its explicit hold, then preserves or relinquishes authority as configured.
    /// - Parameter lease: Current ticket; cleanup remains callable from cancelled client children.
    /// - Throws: `coordinatorUnavailable` after the hold for configured outage; no arbitrary payload text escapes.
    func release(_ lease: ShardLease<ManualClock>) async throws {
        releaseCalls += 1
        releaseEntered.open()
        if !releaseAllowed { await withCheckedContinuation { releaseWaiter = $0 } }
        if failRelease { throw ShardOwnershipFailure.coordinatorUnavailable }
        await base.release(lease)
    }

    /// Allows the single held cleanup call to continue; repeated signals are harmless.
    func allowRelease() {
        releaseAllowed = true
        releaseWaiter?.resume()
        releaseWaiter = nil
    }

    /// Reads the actual retained ownership count after successful or failed release.
    /// - Returns: Zero after successful cleanup, one while an injected outage retains its ticket.
    func retainedCount() async -> Int { await base.retainedLeaseCount() }
}

/// Single callback cleanup gate makes premature shutdown completion observable without wall-clock delays.
@available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
private actor RegressionCleanup {
    nonisolated let entered = TestBarrier()
    private var hold: Bool
    private var waiter: CheckedContinuation<Void, Never>?
    private(set) var count = 0
    private(set) var completed = false

    /// Configures an optional owner-cleanup hold without starting any task.
    /// - Parameter hold: Whether the cleanup operation waits for the test's unblock signal.
    init(hold: Bool) { self.hold = hold }

    /// Records invocation and completes only after the explicit cleanup hold is released.
    /// The continuation deliberately ignores cancellation, modelling required owner cleanup.
    func perform() async {
        count += 1
        entered.open()
        if hold { await withCheckedContinuation { waiter = $0 } }
        completed = true
    }

    /// Releases held cleanup exactly once; early or repeated calls are harmless.
    func unblock() {
        hold = false
        waiter?.resume()
        waiter = nil
    }
}

/// Records whether any shutdown caller returned before the owner finished cleanup.
private actor ShutdownObservations {
    private(set) var returned = 0
    private(set) var returnedBeforeCleanup = false

    /// Adds one completed caller and retains any observed premature-return evidence.
    /// - Parameter cleanupFinished: Cleanup completion observed immediately after shutdown returns.
    func record(cleanupFinished: Bool) {
        returned += 1
        returnedBeforeCleanup = returnedBeforeCleanup || !cleanupFinished
    }
}

/// Single-response body ownership for authenticated discovery fixtures.
private actor RegressionResponseBody {
    private var data: Data?
    /// Stores the bounded discovery JSON until its first pull.
    /// - Parameter data: Small credential-free complete response, less than 4,096 bytes.
    init(_ data: Data) { self.data = data }
    /// Transfers the response once and returns EOF on every later pull.
    /// - Returns: Original bytes, or nil after transfer/close.
    func take() -> Data? { defer { data = nil }; return data }
    /// Discards unread bytes; repeated close is harmless.
    func clear() { data = nil }
}

/// One optional correlated reply and controlled EOF exercise live requests and owner-stop cleanup.
@available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
private actor RegressionClientSocket: WebSocketSessionConnection {
    nonisolated let peerClose = TestBarrier()
    private let identified = TestBarrier()
    private let requestAvailable = TestBarrier()
    private let respondToMemberRequests: Bool
    private var response: WebSocketMessage?
    private var index = 0
    private(set) var memberRequestCount = 0
    private(set) var closed = false

    /// Configures a task-free scripted peer with at most one bounded correlated response.
    /// - Parameter respondToMemberRequests: Whether the first opcode-8 command unlocks a complete chunk.
    init(respondToMemberRequests: Bool = false) {
        self.respondToMemberRequests = respondToMemberRequests
    }

    /// Observes Identify without retaining credentials and optionally constructs one correlated member chunk.
    /// - Parameters:
    ///   - message: Complete bounded JSON Gateway command.
    ///   - context: Caller cancellation/deadline context.
    /// - Throws: Context, malformed JSON, invalid test request fields, or serialization errors.
    func send<C: Clock>(_ message: WebSocketMessage, context: TransportContext<C>) async throws where C.Duration == Duration {
        try context.check()
        guard case .text(let text) = message, case .object(let value) = try JSONValue.parse(text),
              case .number(let opcode) = value["op"] else { throw GatewayFailure.invalidPayload }
        if opcode.rawValue == "2" { identified.open() }
        if opcode.rawValue == "8" {
            memberRequestCount += 1
            guard respondToMemberRequests, memberRequestCount == 1,
                  case .object(let data) = value["d"], case .string(let guild) = data["guild_id"],
                  case .string(let nonce) = data["nonce"] else { throw GatewayFailure.invalidPayload }
            let envelope: JSONValue = .object([
                "op": .number(try JSONNumber(rawValue: "0")), "t": .string("GUILD_MEMBERS_CHUNK"),
                "s": .number(try JSONNumber(rawValue: "2")), "d": .object([
                    "guild_id": .string(guild), "nonce": .string(nonce), "members": .array([]),
                    "chunk_index": .number(try JSONNumber(rawValue: "0")),
                    "chunk_count": .number(try JSONNumber(rawValue: "1"))])])
            response = .text(String(decoding: try envelope.serialized(), as: UTF8.self))
            requestAvailable.open()
        }
    }

    /// Emits Hello, authenticated READY and an optional request-gated chunk before controlled peer EOF.
    /// - Parameter context: Caller cancellation/deadline context.
    /// - Returns: Next complete protocol frame or nil after the peer/owner closes.
    /// - Throws: Cancellation or context failures; every suspension cooperates with sibling cleanup.
    func receive<C: Clock>(context: TransportContext<C>) async throws -> WebSocketMessage? where C.Duration == Duration {
        try context.check()
        guard !closed else { return nil }
        let slot = index
        index += 1
        switch slot {
        case 0: return .text(#"{"op":10,"d":{"heartbeat_interval":10000}}"#)
        case 1:
            try await identified.wait()
            return .text(#"{"op":0,"s":1,"t":"READY","d":{"session_id":"regression","resume_gateway_url":"wss://gateway.discord.gg"}}"#)
        case 2 where respondToMemberRequests:
            try await requestAvailable.wait()
            guard !closed else { return nil }
            defer { response = nil }
            return response
        default: try await peerClose.wait(); return nil
        }
    }

    /// Closes cooperatively and unblocks pending receive work without any retained socket resources.
    func close() { closed = true; response = nil; peerClose.open(); identified.open(); requestAvailable.open() }
    /// Implements the session adapter's resumable close through the same idempotent test disposal.
    func closeForReconnect() { close() }
    /// Supplies fatal authentication close code 4004 so natural EOF cannot reconnect.
    /// - Returns: The public numeric test close status, without untrusted reason text.
    func peerCloseCode() -> Int? { 4004 }
}
