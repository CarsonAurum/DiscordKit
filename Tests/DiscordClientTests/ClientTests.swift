// File: Tests/DiscordClientTests/ClientTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordClient
import DiscordCore
import DiscordGateway
import DiscordHTTP
import DiscordTransport
import DiscordTestSupport
import Foundation
import Testing

@Suite("Consumer client lifecycle", .timeLimit(.minutes(1)))
struct ClientTests {
    /// Rejects invalid topology/batch/aggregate configuration before any dependency is used.
    @Test func bounds() throws {
        #expect(throws: ClientFailure.invalidConfiguration) { try ClientConfiguration(intents: [], maximumShards: 0) }
        #expect(throws: ClientFailure.invalidConfiguration) { try ClientConfiguration(intents: [], shardIndices: [0, 0]) }
        #expect(throws: ClientFailure.invalidConfiguration) { try ClientConfiguration(intents: [], shardIndices: [-1]) }
        #expect(throws: ClientFailure.invalidConfiguration) { try ClientConfiguration(intents: [], ingestionBatchSize: 0) }
        #expect(throws: ClientFailure.invalidConfiguration) { try ClientResourceBudget(maximumRawBytes: 0) }
        let value = try ClientConfiguration(intents: [.guilds, .guildMessages])
        #expect(value.intents == [.guilds, .guildMessages])
        #expect(value.shardIndices == nil && value.maximumShards == 256 && value.ingestionBatchSize == 64)
    }

    /// Aggregate reservations include raw byte/count ceilings and release idempotently across identities.
    @Test func aggregateReservations() async throws {
        let budget = try ClientResourceBudget(maximumClients: 2, maximumShards: 2,
            maximumRawEvents: 4, maximumRawBytes: 2048)
        let config = try GatewayShardConfiguration(maximumBufferedEvents: 2, maximumBufferedBytes: 1024)
        let first = try await budget.reserve(shards: 1, configuration: config)
        let second = try await budget.reserve(shards: 1, configuration: config)
        await #expect(throws: ClientFailure.capacityExceeded) { try await budget.reserve(shards: 0, configuration: config) }
        #expect(await budget.snapshot().rawBytes == 2048)
        try await budget.resize(first, shards: 0, configuration: config)
        #expect(await budget.snapshot().shards == 1)
        await #expect(throws: ClientFailure.capacityExceeded) { try await budget.resize(second, shards: Int.max, configuration: config) }
        await #expect(throws: ClientFailure.capacityExceeded) { try await budget.resize(second, shards: 3, configuration: config) }
        await #expect(throws: ClientFailure.capacityExceeded) { try await budget.resize(second, shards: -1, configuration: config) }
        await budget.release(first); await budget.release(first); await budget.release(second)
        #expect(await budget.snapshot().clients == 0)
        await #expect(throws: ClientFailure.capacityExceeded) { try await budget.resize(first, shards: 0, configuration: config) }
        await #expect(throws: ClientFailure.capacityExceeded) { try await budget.reserve(shards: Int.max, configuration: config) }
        await #expect(throws: ClientFailure.capacityExceeded) { try await budget.reserve(shards: -1, configuration: config) }
    }

    /// A public bot consumer performs no construction I/O, receives its own broadcast copies,
    /// calls a typed service, sends a command and awaits complete idempotent UI-actor shutdown.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @MainActor @Test func runAndStop() async throws {
        let fixture = try ClientFixture()
        #expect(await fixture.http.executionCount == 0)
        #expect(await fixture.client.snapshot().phase == .idle)
        #expect(await fixture.leases.retainedLeaseCount() == 0)
        let first = try await fixture.hub.subscribe(), second = try await fixture.hub.subscribe()
        let task = Task { try await fixture.client.run() }
        var a = first.makeAsyncIterator(), b = second.makeAsyncIterator()
        #expect(try await a.next()?.name == "READY")
        #expect(try await b.next()?.name == "READY")
        #expect(try await a.next()?.name == "FUTURE")
        #expect(try await b.next()?.name == "FUTURE")
        #expect(await fixture.client.snapshot().ready)
        let user = try await fixture.client.services.execute(DiscordEndpoints.currentUser())
        #expect(user.id.rawValue == 42)
        try await fixture.client.send(.updatePresence(try GatewayPresence()), shardIndex: 0)
        #expect(await fixture.socket.sentOpcodes.contains(3))
        await #expect(throws: ClientFailure.alreadyRunning) { try await fixture.client.run() }
        await fixture.client.shutdown()
        try await task.value
        await fixture.client.shutdown()
        #expect(try await a.next() == nil)
        #expect(await fixture.client.snapshot().phase == .stopped)
        #expect(await fixture.budget.snapshot().clients == 0)
        #expect(await fixture.leases.retainedLeaseCount() == 0)
        #expect(await fixture.socket.closed)
        #expect(fixture.clock.pendingSleepCount == 0)
        #expect(await fixture.cleanup.count == 1)
        #expect(await fixture.hub.snapshot().bufferedBytes == 0)
        #expect(String(reflecting: fixture.client).contains("redacted"))
        await #expect(throws: ClientFailure.stopped) { try await fixture.client.run() }
        await #expect(throws: ClientFailure.notReady) {
            try await fixture.client.send(.updatePresence(try GatewayPresence()), shardIndex: 99)
        }
        await #expect(throws: ClientFailure.notReady) {
            try await fixture.client.request(.requestSoundboardSounds(guildIDs: [GuildID(rawValue: 1)]), shardIndex: 0)
        }
    }

    /// Cancelling the owner closes socket/leases and every broadcast waiter before returning.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func cancellation() async throws {
        let fixture = try ClientFixture()
        let subscription = try await fixture.hub.subscribe()
        let task = Task { try await fixture.client.run() }
        var iterator = subscription.makeAsyncIterator()
        _ = try await iterator.next()
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await fixture.budget.snapshot().rawBytes == 0)
        #expect(await fixture.leases.retainedLeaseCount() == 0)
        #expect(await fixture.socket.closed)
        #expect(fixture.clock.pendingSleepCount == 0)
        #expect(await fixture.cleanup.count == 1)
    }

    /// Pre-run shutdown and pre-cancellation never discover or acquire a shard lease.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [true, false]) func neverStarted(_ shutdown: Bool) async throws {
        let fixture = try ClientFixture()
        if shutdown {
            await fixture.client.shutdown()
            await #expect(throws: ClientFailure.stopped) { try await fixture.client.run() }
        } else {
            let gate = TestBarrier()
            let task = Task { try? await gate.wait(); try await fixture.client.run() }
            task.cancel()
            await #expect(throws: CancellationError.self) { try await task.value }
        }
        #expect(await fixture.http.executionCount == 0)
        #expect(await fixture.leases.retainedLeaseCount() == 0)
        #expect(await fixture.cleanup.count == 1)
    }

    /// A malformed discovery fails without opening sockets and still finishes consumers/cleanup.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func discoveryFailure() async throws {
        let fixture = try ClientFixture(discovery: "{}")
        await #expect(throws: (any Error).self) { try await fixture.client.run() }
        #expect(await fixture.client.snapshot().phase == .failed)
        #expect(await fixture.budget.snapshot().clients == 0)
        #expect(await fixture.cleanup.count == 1)
    }

    /// Shutdown interrupts a suspended discovery without requiring the caller to own an HTTP task.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func shutdownDuringDiscovery() async throws {
        let entered = TestBarrier(), blocked = TestBarrier()
        let http = try ScriptedHTTPTransport(steps: [{ _ in entered.open(); try await blocked.wait(); throw CancellationError() }])
        let fixture = try ClientFixture(httpOverride: http)
        let task = Task { try await fixture.client.run() }
        try await entered.wait()
        await fixture.client.shutdown()
        // Explicit shutdown normalizes its own child cancellation to successful owner completion.
        try await task.value
        #expect(await fixture.budget.snapshot().clients == 0)
        #expect(await fixture.cleanup.count == 1)
        #expect(fixture.clock.pendingSleepCount == 0)
    }

    /// Services retain HTTP-only usability and invalidate entity evidence twice for every local
    /// write, including rejected requests, while safe reads never invalidate projections.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func servicesInvalidateMutations() async throws {
        let clock = ManualClock(), counter = CleanupCounter()
        let http = try ScriptedHTTPTransport(steps: [
            { _ in try clientResponse("{}") }, { _ in try clientResponse("{}") },
            { _ in HTTPResponse(status: 400) }
        ])
        let rest = RESTClient(credential: .bot(try BotToken("service-sentinel")), identity: RateLimitIdentity(),
            transport: http, coordinator: RateLimitCoordinator(clock: clock), clock: clock)
        let services = ServiceContext(rest: rest) { await counter.increment() }
        let read = try Endpoint<JSONValue>(method: "GET", path: ["test"], authentication: .bot,
            retrySafety: .safe) { try JSONValue.parse($0) }
        let write = try Endpoint<JSONValue>(method: "POST", path: ["test"], authentication: .bot,
            retrySafety: .unsafe) { try JSONValue.parse($0) }
        let failingWrite = try Endpoint<JSONValue>(method: "POST", path: ["failure"], authentication: .bot,
            retrySafety: .unsafe) { try JSONValue.parse($0) }
        #expect(try await services.execute(read) == .object([:]))
        #expect(await counter.count == 0)
        #expect(try await services.execute(write) == .object([:]))
        #expect(await counter.count == 2)
        await #expect(throws: (any Error).self) { try await services.execute(failingWrite) }
        #expect(await counter.count == 4)
        #expect(await http.executionCount == 3)
    }

    /// Reusing the consumer authority conservatively refreshes discovery without refilling
    /// spent Identify budget or losing per-bot command coordination.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func authorityRetainsStartupBudget() async throws {
        let clock = ManualClock(), budget = try ClientResourceBudget()
        let authority = try ClientAuthority(botID: UserID(rawValue: 42), clock: clock,
            budget: budget, cacheIdentity: "scope")
        let discovery = try GatewayDiscovery(json: JSONValue.parse(clientDiscovery))
        let first = try await authority.startupCoordinator(discovery: discovery)
        let shard = try ShardIdentity(botID: UserID(rawValue: 42), topologyGeneration: 0, index: 0, count: 1)
        #expect(try await first.reserveIdentify(for: shard) == .admitted)
        let refreshed = try await authority.startupCoordinator(discovery: discovery)
        #expect(try await refreshed.reserveIdentify(for: shard) == .wait(.seconds(5)))
        #expect(authority.botID.rawValue == 42 && authority.cacheIdentity == "scope")
        let external = FixedClientStartup()
        let other = try ClientAuthority(botID: UserID(rawValue: 42), clock: clock, budget: budget,
            startup: external, commands: authority.commands)
        let retained = try await other.startupCoordinator(discovery: discovery)
        #expect(try await retained.reserveIdentify(for: shard) == .wait(.seconds(7)))
    }
}

/// Fixed injected authority proves external admission remains selected after discovery.
private struct FixedClientStartup: GatewayStartupCoordinator {
    /// Rejects immediate admission without silently creating a new local budget.
    /// - Parameter shard: Validated source; unused by this deterministic fixed-delay fixture.
    /// - Returns: Seven-second delay, allowing assertions to distinguish injected ownership.
    func reserveIdentify(for shard: ShardIdentity) async throws -> GatewayStartAdmission { .wait(.seconds(7)) }
}

/// Isolated fixture wiring real production actors to finite credential-free scripts.
@available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
private struct ClientFixture {
    let clock = ManualClock()
    let http: ScriptedHTTPTransport
    let hub: GatewayEventHub
    let budget: ClientResourceBudget
    let leases: InProcessShardLeaseStore<ManualClock>
    let socket = ClientSocket()
    let cleanup = CleanupCounter()
    let client: DiscordClient<ManualClock, InProcessShardLeaseStore<ManualClock>>

    /// Builds task-free dependencies; scripts hold no real credentials or network connections.
    /// - Parameters:
    ///   - discovery: Bounded JSON discovery fixture; default selects one shard.
    ///   - httpOverride: Optional suspended/error script for lifecycle failure scenarios.
    /// - Throws: Fixture/script/configuration validation errors.
    init(discovery: String = clientDiscovery, httpOverride: ScriptedHTTPTransport? = nil) throws {
        http = try httpOverride ?? ScriptedHTTPTransport(steps: [
            { _ in try clientResponse(discovery) },
            { _ in try clientResponse(#"{"id":"42","username":"bot","discriminator":"0","global_name":null,"avatar":null}"#) }
        ])
        hub = GatewayEventHub(configuration: try .init())
        budget = try ClientResourceBudget()
        leases = try InProcessShardLeaseStore(clock: clock, maximumLeases: 4)
        let authority = try ClientAuthority(botID: UserID(rawValue: 42), clock: clock, budget: budget)
        let rest = RESTClient(credential: .bot(try BotToken("client-test-sentinel")), identity: RateLimitIdentity(),
            transport: http, coordinator: RateLimitCoordinator(clock: clock), clock: clock)
        let cleanup = cleanup
        client = DiscordClient(token: try BotToken("client-test-sentinel"),
            configuration: try ClientConfiguration(intents: [.guilds]), services: ServiceContext(rest: rest),
            transport: ScriptedWebSocketTransport(connection: socket), clock: clock, leases: leases,
            authority: authority, events: hub, cleanup: { await cleanup.increment() })
    }
}

/// Nonsecret current discovery snapshot with sufficient startup allowance for one connection.
private let clientDiscovery = #"{"url":"wss://gateway.discord.gg","shards":1,"session_start_limit":{"total":100,"remaining":100,"reset_after":3600000,"max_concurrency":1}}"#

/// Creates a single-use bounded response stream for one fixture JSON object.
/// - Parameter json: Exact small credential-free fixture payload.
/// - Returns: Successful HTTP response whose caller owns and closes its body.
/// - Throws: Invalid body-stream bounds, which fixture sizes cannot trigger.
private func clientResponse(_ json: String) throws -> HTTPResponse {
    let body = ClientBody(data: Data(json.utf8))
    return HTTPResponse(status: 200, body: try BodyStream(maximumChunkBytes: 4096,
        next: { await body.take() }, close: { await body.clear() }))
}

/// Single-use fixture byte ownership for deterministic response cleanup.
private actor ClientBody {
    var data: Data?
    /// Retains a finite fixture response until the first body pull.
    /// - Parameter data: Small complete response, at most 4096 bytes.
    init(data: Data) { self.data = data }
    /// Transfers response bytes once; later pulls return EOF.
    /// - Returns: Original bytes or nil after transfer/close.
    func take() -> Data? { defer { data = nil }; return data }
    /// Discards any unread fixture body, idempotently.
    func clear() { data = nil }
}

/// Exactly-once owner cleanup accounting, safe across reentrant shutdown callers.
private actor CleanupCounter {
    var count = 0
    /// Records one observed cleanup invocation for assertions.
    func increment() { count += 1 }
}

/// Deterministic socket gates READY on Identify and retains no unbounded outbound payloads.
@available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
private actor ClientSocket: WebSocketConnection {
    let identified = TestBarrier(), idle = TestBarrier()
    var index = 0
    var closed = false
    var sentOpcodes: [Int] = []

    /// Accepts bounded protocol writes and releases authentication-dependent receive data.
    /// - Parameters:
    ///   - message: Complete outgoing control/application JSON.
    ///   - context: Cancellation/deadline for the write.
    /// - Throws: Context or invalid fixture JSON failures.
    func send<C: Clock>(_ message: WebSocketMessage, context: TransportContext<C>) async throws where C.Duration == Duration {
        try context.check()
        guard case .text(let text) = message, case .object(let value) = try JSONValue.parse(text),
              case .number(let op) = value["op"], let number = Int(op.rawValue) else { throw GatewayFailure.invalidPayload }
        sentOpcodes.append(number)
        if number == 2 { identified.open() }
    }

    /// Emits Hello/READY/future data and then cooperatively waits for explicit close or cancellation.
    /// - Parameter context: Cancellation/deadline for this read.
    /// - Returns: Next complete text frame or nil after close.
    /// - Throws: Cancellation or context failures.
    func receive<C: Clock>(context: TransportContext<C>) async throws -> WebSocketMessage? where C.Duration == Duration {
        try context.check()
        guard !closed else { return nil }
        let slot = index; index += 1
        switch slot {
        case 0: return .text(#"{"op":10,"d":{"heartbeat_interval":10000}}"#)
        case 1:
            try await identified.wait()
            return .text(#"{"op":0,"s":1,"t":"READY","d":{"session_id":"test","resume_gateway_url":"wss://gateway.discord.gg"}}"#)
        case 2: return .text(#"{"op":0,"s":2,"t":"FUTURE","d":{"id":"18446744073709551615"}}"#)
        default: try await idle.wait(); return nil
        }
    }

    /// Releases pending receive and marks disposal; repeated closure remains harmless.
    func close() { closed = true; idle.open(); identified.open() }
}
