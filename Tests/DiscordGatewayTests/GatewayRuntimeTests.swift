import DiscordCore
import DiscordTransport
import DiscordTestSupport
import Foundation
import Testing
import Synchronization
@testable import DiscordGateway

@Suite("Supervised Gateway runtime", .timeLimit(.minutes(1)))
struct GatewayRuntimeTests {
    /// Confirms Identify, READY, ordered raw delivery, duplicate suppression and complete explicit-stop cleanup.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func identifyAndStop() async throws {
        let identified = TestBarrier(), ingested = TestBarrier(), idle = TestBarrier(onWaitScheduled: { ingested.open() })
        let socket = GatewayTestSocket(steps: [
            { .text(#"{"op":10,"d":{"heartbeat_interval":10000}}"#) },
            { try await identified.wait(); return .text(readyPayload) },
            { .text(#"{"op":0,"s":2,"t":"FUTURE","d":{"value":18446744073709551615}}"#) },
            { .text(#"{"op":0,"s":2,"t":"DUPLICATE","d":null}"#) },
            { .text(#"{"op":99,"d":{"unknown":true}}"#) },
            { try await idle.wait(); return nil }
        ], onSend: { envelope in if envelope.opcode == 2 { identified.open() } })
        let fixture = try makeRuntime(sockets: [socket])
        let task = Task { try await fixture.shard.run() }
        try await ingested.wait()
        let snapshot = await fixture.shard.snapshot()
        #expect(snapshot.phase == .ready && snapshot.sequence == 2 && snapshot.hasResumableSession)
        #expect(snapshot.bufferedEvents == 3 && snapshot.bufferedBytes > 0)
        #expect(await fixture.shard.drainEvents(maximum: 0).isEmpty)
        let events = await fixture.shard.drainEvents()
        #expect(events.map(\.name) == ["READY", "FUTURE", nil])
        #expect(events.map(\.opcode) == [0,0,99])
        #expect(String(describing: events[0]) == "GatewayEvent(redacted)")
        #expect(await fixture.shard.snapshot().bufferedBytes == 0)
        let identify = try #require(await socket.sent.first { $0.opcode == 2 })
        guard case .object(let body) = identify.data else { Issue.record("Identify object required"); return }
        #expect(body["shard"] == .array([gatewayNumber(0), gatewayNumber(2)]))
        #expect(body["intents"] == gatewayNumber(1))
        await #expect(throws: GatewayFailure.alreadyRunning) { try await fixture.shard.run() }
        await fixture.shard.stop()
        try await task.value
        await fixture.shard.stop()
        #expect(await fixture.leases.retainedLeaseCount() == 0)
        #expect(fixture.clock.pendingSleepCount == 0)
        #expect(await socket.closed)
        #expect(await fixture.shard.snapshot().phase == .stopped)
    }

    /// Verifies a reconnect resumes from the last dispatch, uses its URL, and never spends a second Identify.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func resumeAndRequestedHeartbeat() async throws {
        let identified = TestBarrier(), resumed = TestBarrier(), ingested = TestBarrier()
        let idle = TestBarrier(onWaitScheduled: { ingested.open() })
        let first = GatewayTestSocket(steps: [
            { .text(helloPayload) }, { try await identified.wait(); return .text(readyPayload) },
            { .text(#"{"op":7,"d":null}"#) }
        ], onSend: { envelope in if envelope.opcode == 2 { identified.open() } })
        let second = GatewayTestSocket(steps: [
            { .text(helloPayload) },
            { try await resumed.wait(); return .text(#"{"op":0,"s":2,"t":"RESUMED","d":{}}"#) },
            { .text(#"{"op":1,"d":null}"#) }, { .text(#"{"op":11,"d":null}"#) },
            { try await idle.wait(); return nil }
        ], onSend: { envelope in if envelope.opcode == 6 { resumed.open() } })
        let retrySleeping = TestBarrier()
        let fixture = try makeRuntime(sockets: [first,second], onSleep: { retrySleeping.open() }, jitter: 0)
        let task = Task { try await fixture.shard.run() }
        // Zero injected retry jitter reconnects immediately; no virtual advance is needed.
        try await ingested.wait()
        #expect(await first.reconnectCloseCount == 1)
        let resume = try #require(await second.sent.first { $0.opcode == 6 })
        guard case .object(let data) = resume.data else { Issue.record("Resume object required"); return }
        #expect(data["session_id"] == .string("session"))
        #expect(data["seq"] == gatewayNumber(1))
        #expect(await fixture.startup.remainingStarts() == 99)
        #expect(await fixture.transport.urls.last?.host == "resume.discord.gg")
        #expect(await second.sent.contains { $0.opcode == 1 && $0.data == gatewayNumber(2) })
        #expect(await fixture.shard.drainEvents().map(\.name) == ["READY", "RESUMED"])
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await fixture.leases.retainedLeaseCount() == 0)
        #expect(fixture.clock.pendingSleepCount == 0)
    }

    /// Drives a missed ACK with an injected clock; only one supervised reconnect is permitted.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func missedACK() async throws {
        let heartbeatSent = TestBarrier(), idle = TestBarrier()
        let socket = GatewayTestSocket(steps: [
            { .text(#"{"op":10,"d":{"heartbeat_interval":1000}}"#) },
            { try await idle.wait(); return nil }
        ], onSend: { envelope in if envelope.opcode == 1 { heartbeatSent.open() } })
        let sleepScheduled = TestBarrier()
        let fixture = try makeRuntime(sockets: [socket], retries: 0, onSleep: { sleepScheduled.open() }, jitter: 0)
        let task = Task { try await fixture.shard.run() }
        try await heartbeatSent.wait()
        // Wait for actor state after the send, then schedule the next beat from the same virtual now.
        while fixture.clock.pendingSleepCount < 2 { await Task.yield() }
        try fixture.clock.advance(by: .seconds(1))
        await #expect(throws: GatewayFailure.retryLimitExceeded) { try await task.value }
        #expect(await socket.sent.filter { $0.opcode == 1 }.count == 1)
        #expect(await socket.reconnectCloseCount == 1)
        #expect(await fixture.leases.retainedLeaseCount() == 0)
        #expect(fixture.clock.pendingSleepCount == 0)
    }

    /// A server-requested heartbeat just before the periodic timer receives a full scheduled ACK window.
    /// The unacknowledged requested beat must not create an immediate false zombie detection.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func requestedHeartbeatNearTimer() async throws {
        let enterRead = TestBarrier(), request = TestBarrier(), requestedSent = TestBarrier(), periodicSent = TestBarrier()
        let idle = TestBarrier()
        let beats = Mutex(0)
        let socket = GatewayTestSocket(steps: [
            { .text(#"{"op":10,"d":{"heartbeat_interval":1000}}"#) },
            { enterRead.open(); try await request.wait(); return .text(#"{"op":1,"d":null}"#) },
            { try await idle.wait(); return nil }
        ], onSend: { envelope in
            if envelope.opcode == 1 {
                let count = beats.withLock { $0 += 1; return $0 }
                if count == 1 { requestedSent.open() } else { periodicSent.open() }
            }
        })
        let fixture = try makeRuntime(sockets: [socket], jitter: 1)
        let task = Task { try await fixture.shard.run() }
        try await enterRead.wait()
        while fixture.clock.pendingSleepCount < 2 { await Task.yield() }
        try fixture.clock.advance(by: .milliseconds(999))
        request.open()
        try await requestedSent.wait()
        try fixture.clock.advance(by: .milliseconds(1))
        try await periodicSent.wait()
        #expect(await fixture.transport.connectionCount == 1)
        #expect(await socket.sent.filter { $0.opcode == 1 }.count == 2)
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(fixture.clock.pendingSleepCount == 0)
    }

    /// Invalid-session true preserves Resume; false obtains another atomic Identify after the bucket window.
    /// - Parameter resumable: Exact boolean in Discord's opcode-nine invalid-session payload.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [true,false])
    func invalidSession(_ resumable: Bool) async throws {
        let identified = TestBarrier(), secondAuthenticated = TestBarrier(), secondRead = TestBarrier(), finished = TestBarrier()
        let idle = TestBarrier(onWaitScheduled: { finished.open() })
        let first = GatewayTestSocket(steps: [
            { .text(helloPayload) }, { try await identified.wait(); return .text(readyPayload) },
            { .text("{\"op\":9,\"d\":\(resumable)}") }
        ], onSend: { event in if event.opcode == 2 { identified.open() } })
        let second = GatewayTestSocket(steps: [
            { .text(helloPayload) },
            { secondRead.open(); try await secondAuthenticated.wait()
                return .text(resumable ? #"{"op":0,"s":2,"t":"RESUMED","d":{}}"# : readyPayload) },
            { try await idle.wait(); return nil }
        ], onSend: { event in if event.opcode == 2 || event.opcode == 6 { secondAuthenticated.open() } })
        let fixture = try makeRuntime(sockets: [first,second], jitter: 0)
        let task = Task { try await fixture.shard.run() }
        try await secondRead.wait()
        if !resumable {
            // The original shard's bucket was consumed at virtual zero, so a new Identify waits five seconds.
            while fixture.clock.pendingSleepCount < 3 { await Task.yield() }
            try fixture.clock.advance(by: .seconds(5))
        }
        try await finished.wait()
        #expect(await second.sent.contains { $0.opcode == (resumable ? 6 : 2) })
        #expect(await fixture.startup.remainingStarts() == (resumable ? 99 : 98))
        #expect(await fixture.transport.urls.last?.host == (resumable ? "resume.discord.gg" : "gateway.discord.gg"))
        await fixture.shard.stop()
        try await task.value
        #expect(await fixture.leases.retainedLeaseCount() == 0)
    }

    /// A socket finishing its upgrade after explicit stop is immediately closed before authentication.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func lateConnectAfterStop() async throws {
        let gate = TestBarrier(), entered = TestBarrier()
        let socket = GatewayTestSocket(steps: [])
        let fixture = try makeRuntime(sockets: [socket], connectGate: gate, connectEntered: entered)
        let task = Task { try await fixture.shard.run() }
        try await entered.wait()
        await fixture.shard.stop()
        gate.open()
        try await task.value
        #expect(await socket.closed)
        #expect(await socket.sent.isEmpty)
        #expect(await fixture.leases.retainedLeaseCount() == 0)
        #expect(await fixture.shard.snapshot().phase == .stopped)
    }

    /// Fatal peer codes bypass retry and close all owned resources.
    /// - Parameter code: Official terminal authentication/configuration code.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [4004,4010,4011,4012,4013,4014])
    func fatalPeerCode(_ code: Int) async throws {
        let socket = GatewayTestSocket(steps: [{ .text(helloPayload) }, { nil }], peerCode: code)
        let fixture = try makeRuntime(sockets: [socket])
        await #expect(throws: GatewayFailure.fatalClose(code)) { try await fixture.shard.run() }
        #expect(await fixture.transport.connectionCount == 1)
        #expect(await fixture.leases.retainedLeaseCount() == 0)
        #expect(fixture.clock.pendingSleepCount == 0)
    }

    /// Queue count and bytes are hard bounds; overflow terminates without silently losing a live stream.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func overflow() async throws {
        let socket = GatewayTestSocket(steps: [
            { .text(helloPayload) }, { .text(#"{"op":99,"d":null}"#) }, { .text(#"{"op":99,"d":null}"#) }
        ])
        let fixture = try makeRuntime(sockets: [socket], maximumEvents: 1)
        await #expect(throws: GatewayFailure.eventCapacityExceeded) { try await fixture.shard.run() }
        #expect(await fixture.shard.snapshot().bufferedEvents == 0)
        #expect(await socket.closed)
        #expect(await fixture.leases.retainedLeaseCount() == 0)
    }

    /// Ownership expiry fences the next socket completion before it can append events or issue new writes.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func leaseLoss() async throws {
        let waiting = TestBarrier(), continueRead = TestBarrier()
        let socket = GatewayTestSocket(steps: [
            { .text(helloPayload) },
            { waiting.open(); try await continueRead.wait(); return .text(#"{"op":99,"d":null}"#) }
        ])
        let fixture = try makeRuntime(sockets: [socket])
        let task = Task { try await fixture.shard.run() }
        try await waiting.wait()
        try fixture.clock.advance(by: .seconds(60))
        continueRead.open()
        await #expect(throws: ShardOwnershipFailure.staleLease) { try await task.value }
        #expect(await fixture.shard.snapshot().bufferedEvents == 0)
        #expect(await socket.closed)
        #expect(await fixture.leases.retainedLeaseCount() == 0)
    }

    /// A failing shard cancels an indefinitely receiving sibling and awaits both lease/socket cleanups.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func botFailureCancelsSiblings() async throws {
        let receiving = TestBarrier(), idle = TestBarrier()
        let first = GatewayTestSocket(steps: [
            { .text(helloPayload) }, { receiving.open(); try await idle.wait(); return nil }
        ])
        let second = GatewayTestSocket(steps: [
            { .text(helloPayload) }, { try await receiving.wait(); return nil }
        ], peerCode: 4004)
        let fixture = try makeRuntime(sockets: [first])
        let other = GatewayShard(identity: try ShardIdentity(botID: UserID(rawValue: 1), topologyGeneration: 0, index: 1, count: 2),
            token: try BotToken("test-token"), intents: 1, discovery: try makeDiscovery(),
            transport: GatewayTestTransport(sockets: [second]), clock: fixture.clock, leases: fixture.leases,
            startup: fixture.startup, configuration: try GatewayShardConfiguration(), random: { 1 })
        let bot = try GatewayBot(shards: [fixture.shard,other])
        await #expect(throws: GatewayFailure.fatalClose(4004)) { try await bot.run() }
        #expect(await first.closed)
        #expect(await second.closed)
        #expect(await fixture.leases.retainedLeaseCount() == 0)
        #expect(fixture.clock.pendingSleepCount == 0)
    }

    /// Coordinator outages fail closed before opening sockets; release outages remain visible to handoff owners.
    /// - Parameter failRelease: Whether to fail cleanup instead of initial ownership validation.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [false,true])
    func coordinatorOutage(_ failRelease: Bool) async throws {
        let clock = ManualClock()
        let backing = try InProcessShardLeaseStore(clock: clock, maximumLeases: 2)
        let leases = GatewayOutageLeases(backing: backing, failValidation: !failRelease, failRelease: failRelease)
        let socket = GatewayTestSocket(steps: [{ .text(helloPayload) }, { nil }])
        let transport = GatewayTestTransport(sockets: [socket])
        let discovery = try makeDiscovery()
        let startup = InProcessGatewayStartupCoordinator(botID: UserID(rawValue: 1), limit: discovery.sessionStartLimit, clock: clock)
        let shard = GatewayShard(identity: try ShardIdentity(botID: UserID(rawValue: 1), topologyGeneration: 0, index: 0, count: 2),
            token: try BotToken("test-token"), intents: 1, discovery: discovery, transport: transport,
            clock: clock, leases: leases, startup: startup,
            configuration: try GatewayShardConfiguration(maximumReconnectAttempts: 0), random: { 1 })
        await #expect(throws: ShardOwnershipFailure.coordinatorUnavailable) { try await shard.run() }
        #expect(await transport.connectionCount == (failRelease ? 1 : 0))
        #expect(await backing.retainedLeaseCount() == (failRelease ? 1 : 0))
        #expect(await shard.snapshot().phase == .stopped)
        #expect(clock.pendingSleepCount == 0)
        if failRelease { #expect(await socket.closed) }
    }

    /// Credential-bearing custom errors at acquisition, validation, renewal, release and startup
    /// become one fixed category; cleanup still releases local timers, sockets and valid tickets.
    /// - Parameter boundary: Zero-based injected failure boundary in the order listed above.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: 0..<5)
    func unknownCoordinatorErrorsAreSanitized(_ boundary: Int) async throws {
        let clock = ManualClock(), receiving = TestBarrier(), idle = TestBarrier()
        let backing = try InProcessShardLeaseStore(clock: clock, maximumLeases: 2)
        let leases = GatewayOutageLeases(backing: backing, failValidation: false, failRelease: false,
            untrustedBoundary: boundary)
        let socket = GatewayTestSocket(steps: [{ .text(helloPayload) }, {
            if boundary == 2 || boundary == 4 { receiving.open(); try await idle.wait() }
            return nil
        }])
        let transport = GatewayTestTransport(sockets: [socket]), discovery = try makeDiscovery()
        let startup: any GatewayStartupCoordinator = boundary == 4 ? GatewaySecretStartup() :
            InProcessGatewayStartupCoordinator(botID: UserID(rawValue: 1), limit: discovery.sessionStartLimit, clock: clock)
        let shard = GatewayShard(identity: try ShardIdentity(botID: UserID(rawValue: 1), topologyGeneration: 0, index: 0, count: 2),
            token: try BotToken("test-token"), intents: 1, discovery: discovery, transport: transport,
            clock: clock, leases: leases, startup: startup,
            configuration: try GatewayShardConfiguration(maximumReconnectAttempts: 0), random: { 1 })
        let task = Task { try await shard.run() }
        if boundary == 2 {
            try await receiving.wait()
            while clock.pendingSleepCount < 2 { await Task.yield() }
            try clock.advance(by: .seconds(30))
        }
        await #expect(throws: GatewayFailure.coordinatorUnavailable) { try await task.value }
        #expect(await backing.retainedLeaseCount() == (boundary == 3 ? 1 : 0))
        #expect(await shard.snapshot().phase == .stopped)
        #expect(clock.pendingSleepCount == 0)
        #expect(!String(describing: GatewayFailure.coordinatorUnavailable).contains("test-token"))
        if boundary >= 2 { #expect(await socket.closed) }
    }

    /// Validates aggregate task ownership, consistent topology and immediate cancellation/empty subsets.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func botLifecycle() async throws {
        let fixture = try makeRuntime(sockets: [])
        #expect(throws: GatewayFailure.invalidConfiguration) { try GatewayBot(shards: [fixture.shard,fixture.shard]) }
        let bot = try GatewayBot<ManualClock, InProcessShardLeaseStore<ManualClock>>(shards: [])
        try await bot.run()
        await bot.stop()
        let cancelled = Task { withUnsafeCurrentTask { $0?.cancel() }; try await fixture.shard.run() }
        await #expect(throws: CancellationError.self) { try await cancelled.value }
        #expect(await fixture.leases.retainedLeaseCount() == 0)
        await fixture.shard.stop()
        await fixture.shard.stop()
        #expect(await fixture.shard.snapshot().phase == .stopped)
        await #expect(throws: GatewayFailure.alreadyRunning) { try await fixture.shard.run() }
        #expect(await fixture.transport.connectionCount == 0)
        #expect(await fixture.leases.retainedLeaseCount() == 0)
    }
}

private let helloPayload = #"{"op":10,"d":{"heartbeat_interval":10000}}"#
private let readyPayload = #"{"op":0,"s":1,"t":"READY","d":{"session_id":"session","resume_gateway_url":"wss://resume.discord.gg/"}}"#

@available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
private typealias RuntimeShard = GatewayShard<ManualClock, InProcessShardLeaseStore<ManualClock>>

/// All injected dependencies for one runtime test, with no live network or real credential.
@available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
private struct RuntimeFixture {
    let shard: RuntimeShard
    let clock: ManualClock
    let leases: InProcessShardLeaseStore<ManualClock>
    let startup: InProcessGatewayStartupCoordinator<ManualClock>
    let transport: GatewayTestTransport
}

/// Creates isolated bounded ownership/startup/transport state for a single shard.
/// - Parameters:
///   - sockets: Finite connections returned on successive upgrades.
///   - retries: Total reconnect budget, default two.
///   - maximumEvents: Retained raw event bound, default eight.
///   - onSleep: Synchronous clock registration signal, default no-op.
///   - jitter: Deterministic heartbeat/retry fraction, default one.
///   - connectGate: Optional cooperative upgrade gate for stale-completion tests.
///   - connectEntered: Optional observation gate opened before waiting on upgrade.
/// - Returns: Runtime and dependencies for observable assertions.
/// - Throws: Invalid test configuration or fixture construction errors.
@available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
private func makeRuntime(sockets: [GatewayTestSocket], retries: Int = 2, maximumEvents: Int = 8,
                         onSleep: @escaping @Sendable () -> Void = {}, jitter: Double = 1,
                         connectGate: TestBarrier? = nil, connectEntered: TestBarrier? = nil) throws -> RuntimeFixture {
    let clock = ManualClock(onSleepScheduled: onSleep)
    let leases = try InProcessShardLeaseStore(clock: clock, maximumLeases: 4)
    let discovery = try makeDiscovery()
    let startup = InProcessGatewayStartupCoordinator(botID: UserID(rawValue: 1), limit: discovery.sessionStartLimit, clock: clock)
    let transport = GatewayTestTransport(sockets: sockets, connectGate: connectGate, connectEntered: connectEntered)
    let shard = GatewayShard(identity: try ShardIdentity(botID: UserID(rawValue: 1), topologyGeneration: 0, index: 0, count: 2),
        token: try BotToken("test-token"), intents: 1, discovery: discovery, transport: transport,
        clock: clock, leases: leases, startup: startup,
        configuration: try GatewayShardConfiguration(maximumBufferedEvents: maximumEvents, maximumReconnectAttempts: retries),
        random: { jitter })
    return RuntimeFixture(shard: shard, clock: clock, leases: leases, startup: startup, transport: transport)
}

/// Finite test-only transport recording reconnect URL choice without opening sockets.
@available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
private actor GatewayTestTransport: WebSocketTransport {
    let sockets: [GatewayTestSocket]
    let connectGate: TestBarrier?
    let connectEntered: TestBarrier?
    private(set) var urls: [URL] = []
    /// Reports consumed upgrades without retaining request payloads.
    var connectionCount: Int { urls.count }

    /// Stores finite distinct sockets for sequential generations.
    /// - Parameters:
    ///   - sockets: Scripted connections; exhaustion is a transport error.
    ///   - connectGate: Optional cancellation-aware hold before completing upgrade.
    ///   - connectEntered: Optional signal marking entry into held upgrade.
    init(sockets: [GatewayTestSocket], connectGate: TestBarrier? = nil, connectEntered: TestBarrier? = nil) {
        self.sockets = sockets; self.connectGate = connectGate; self.connectEntered = connectEntered
    }

    /// Records an upgrade after cancellation/deadline validation.
    /// - Parameters:
    ///   - request: Explicit v10/JSON trusted Gateway URL.
    ///   - context: Injected clock/deadline.
    /// - Returns: Next finite socket.
    /// - Throws: Cancellation, deadline or script exhaustion.
    func connectWebSocket<C: Clock>(_ request: HTTPRequest, context: TransportContext<C>) async throws -> any WebSocketConnection where C.Duration == Duration {
        try context.check()
        guard urls.count < sockets.count else { throw TransportFailure.scriptExhausted }
        let socket = sockets[urls.count]; urls.append(request.url)
        connectEntered?.open()
        try await connectGate?.wait()
        return socket
    }
}

/// Session-capable deterministic socket with cancellation-aware receive/close races.
@available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
private actor GatewayTestSocket: WebSocketSessionConnection {
    typealias Step = @Sendable () async throws -> WebSocketMessage?
    let steps: [Step]
    let onSend: @Sendable (GatewayEnvelope) -> Void
    let peerCode: Int?
    let closedGate = TestBarrier()
    var readIndex = 0
    private(set) var sent: [GatewayEnvelope] = []
    private(set) var closed = false
    private(set) var reconnectCloseCount = 0

    /// Stores finite input and a synchronous send-observation hook.
    /// - Parameters:
    ///   - steps: Ordered cooperative receive steps.
    ///   - peerCode: Optional numeric peer disconnect cause.
    ///   - onSend: Fast nonblocking test synchronization hook, default no-op.
    init(steps: [Step], peerCode: Int? = nil, onSend: @escaping @Sendable (GatewayEnvelope) -> Void = { _ in }) {
        self.steps = steps; self.peerCode = peerCode; self.onSend = onSend
    }

    /// Records bounded parsed output and signals test gates without changing virtual time.
    /// - Parameters:
    ///   - message: One complete control frame.
    ///   - context: Cancellation/deadline context.
    /// - Throws: Closed socket, malformed output or context failures.
    func send<C: Clock>(_ message: WebSocketMessage, context: TransportContext<C>) async throws where C.Duration == Duration {
        try context.check()
        guard !closed else { throw TransportFailure.closed }
        let envelope = try GatewayEnvelope(message, maximumBytes: 4096)
        sent.append(envelope); onSend(envelope)
    }

    /// Races one cooperative input against explicit close, awaiting cancelled sibling cleanup.
    /// - Parameter context: Clock/deadline governing this read.
    /// - Returns: Next message or EOF; explicit close unblocks every pending read.
    /// - Throws: Cancellation, deadline or a scripted read failure.
    func receive<C: Clock>(context: TransportContext<C>) async throws -> WebSocketMessage? where C.Duration == Duration {
        try context.check()
        guard !closed, readIndex < steps.count else { return nil }
        let step = steps[readIndex]; readIndex += 1
        let gate = closedGate
        return try await context.run {
            try await withThrowingTaskGroup(of: WebSocketMessage?.self) { group in
                group.addTask { try await step() }
                group.addTask { try await gate.wait(); return nil }
                defer { group.cancelAll() }
                return try await group.next() ?? nil
            }
        }
    }

    /// Closes idempotently and unblocks pending receive work without advancing clocks.
    func close() async { closed = true; closedGate.open() }

    /// Records resumable abort once and completes ordinary resource cleanup.
    func closeForReconnect() async { if !closed { reconnectCloseCount += 1 }; await close() }

    /// Returns the injected peer code without blocking or exposing a close reason.
    /// - Returns: Numeric scripted peer code, possibly absent.
    func peerCloseCode() async -> Int? { peerCode }
}

/// Injected durable-coordinator outage model; failed release deliberately retains authority until expiry.
@available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
private actor GatewayOutageLeases: ShardLeaseStore {
    typealias LeaseClock = ManualClock
    let backing: InProcessShardLeaseStore<ManualClock>
    let failValidation: Bool
    let failRelease: Bool
    let untrustedBoundary: Int?

    /// Selects an outage boundary while retaining a real, observable atomic backing store.
    /// - Parameters:
    ///   - backing: Test-owned fencing/expiry implementation.
    ///   - failValidation: Whether authority checks fail closed.
    ///   - failRelease: Whether cleanup reports uncertainty and leaves the record retained.
    ///   - untrustedBoundary: Optional acquire/validate/renew/release failure index; nil by default.
    init(backing: InProcessShardLeaseStore<ManualClock>, failValidation: Bool, failRelease: Bool, untrustedBoundary: Int? = nil) {
        self.backing = backing; self.failValidation = failValidation; self.failRelease = failRelease
        self.untrustedBoundary = untrustedBoundary
    }

    /// Reserves real ownership before the injected later operation can fail.
    /// - Parameters:
    ///   - shard: Fixed topology key.
    ///   - owner: Fresh nonsecret test worker identifier.
    ///   - lifetime: Positive clock-local ticket lifetime.
    /// - Returns: Backing store's fresh fencing ticket.
    /// - Throws: Backing ownership/admission failures.
    func acquire(_ shard: ShardIdentity, owner: UUID, lifetime: Duration) async throws -> ShardLease<ManualClock> {
        if untrustedBoundary == 0 { throw GatewaySecretFailure() }
        return try await backing.acquire(shard, owner: owner, lifetime: lifetime)
    }

    /// Reports injected coordinator unavailability before granting send authority.
    /// - Parameter lease: Current candidate ticket.
    /// - Throws: Injected outage or backing expiry/stale-generation errors.
    func validate(_ lease: ShardLease<ManualClock>) async throws {
        if untrustedBoundary == 1 { throw GatewaySecretFailure() }
        if failValidation { throw ShardOwnershipFailure.coordinatorUnavailable }
        try await backing.validate(lease)
    }

    /// Forwards atomic renewal unchanged; this fixture does not invent a renewal outage.
    /// - Parameters:
    ///   - lease: Current unexpired ownership ticket.
    ///   - lifetime: Replacement monotonic duration.
    /// - Returns: Backing store's replacement ticket.
    /// - Throws: Backing cancellation, expiry, limit or fencing errors.
    func renew(_ lease: ShardLease<ManualClock>, lifetime: Duration) async throws -> ShardLease<ManualClock> {
        if untrustedBoundary == 2 { throw GatewaySecretFailure() }
        return try await backing.renew(lease, lifetime: lifetime)
    }

    /// Either releases real authority or reports failed cleanup without claiming success.
    /// - Parameter lease: Latest ticket owned by the run.
    /// - Throws: Injected coordinator outage, leaving the backing record untouched.
    func release(_ lease: ShardLease<ManualClock>) async throws {
        if untrustedBoundary == 3 { throw GatewaySecretFailure() }
        if failRelease { throw ShardOwnershipFailure.coordinatorUnavailable }
        await backing.release(lease)
    }
}

/// Simulates an untrusted dependency whose textual diagnostics contain a credential.
private struct GatewaySecretFailure: Error, CustomStringConvertible {
    /// Returns intentionally sensitive text that must never leave a public Gateway boundary.
    var description: String { "dependency failure containing test-token" }
}

/// Fails before Identify allowance with the same deliberately unsafe custom dependency error.
private struct GatewaySecretStartup: GatewayStartupCoordinator {
    /// Rejects admission using an untrusted error rather than consuming startup allowance.
    /// - Parameter shard: Ignored fixed topology; no state or credential is retained.
    /// - Returns: Never returns an admission.
    /// - Throws: Test-only credential-bearing custom failure.
    func reserveIdentify(for shard: ShardIdentity) async throws -> GatewayStartAdmission { throw GatewaySecretFailure() }
}
