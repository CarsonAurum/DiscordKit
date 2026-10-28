// File: Tests/DiscordBotDSLTests/BridgeTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordClient
import DiscordCommandDSL
import DiscordCommands
import DiscordCore
import DiscordDSL
import DiscordHTTP
import DiscordInteractions
import DiscordModels
import DiscordTestSupport
import DiscordTransport
import Foundation
import Testing
@testable import DiscordBotDSL
@testable import DiscordGateway

/// Counts conservative write invalidation without exposing private cache state to the host adapter.
private actor BridgeInvalidations {
    private(set) var count = 0

    /// Records one before/after mutation invalidation, including failed operations.
    func record() { count += 1 }
}

/// Distinguishes original callback failures from cancellation introduced during host cleanup.
private enum BridgeTestFailure: Error, Equatable { case handler }

/// Finite task-free composition used for private bridge admission tests. Actual client/socket provenance
/// is separately covered by the independent DSLBot/lifecycle consumer; internal receipt construction here
/// isolates response deadline, routing, queue and cleanup behavior without a network or scheduler race.
@available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
private struct BridgeFixture {
    let clock = ManualClock()
    let botHTTP: ScriptedHTTPTransport
    let initialHTTP: ScriptedHTTPTransport
    let continuationHTTP: ScriptedHTTPTransport
    let hub: GatewayEventHub
    let client: DiscordClient<ManualClock, InProcessShardLeaseStore<ManualClock>>
    let services: BotServiceAdapter<ManualClock>
    let invalidations = BridgeInvalidations()
    let admission: InteractionAcknowledgementAdmission

    /// Stores finite scripts and real shared production owners without starting work.
    /// - Parameters:
    ///   - botSteps: Ordinary authenticated REST operations, default none.
    ///   - initialSteps: Dedicated exact-token callback operations, default none.
    ///   - continuationSteps: Ordinary continuation operations, default none.
    ///   - connection: Optional owned synthetic socket; nil creates an inert immediate-EOF peer.
    ///   - project: Optional bounded state-projection gate, default no work.
    /// - Throws: Invalid finite fixture or production configuration.
    init(botSteps: [ScriptedHTTPTransport.Step] = [], initialSteps: [ScriptedHTTPTransport.Step] = [],
         continuationSteps: [ScriptedHTTPTransport.Step] = [], connection: (any WebSocketConnection)? = nil,
         project: @escaping @Sendable (GatewayEvent) async throws -> Void = { _ in }) throws {
        botHTTP = try ScriptedHTTPTransport(steps: botSteps)
        initialHTTP = try ScriptedHTTPTransport(steps: initialSteps)
        continuationHTTP = try ScriptedHTTPTransport(steps: continuationSteps)
        hub = GatewayEventHub(configuration: try .init())
        admission = try InteractionAcknowledgementAdmission()
        let clock = self.clock
        let bot = RESTClient(credential: .bot(try BotToken("synthetic-bridge-bot")), identity: RateLimitIdentity(),
            transport: botHTTP, coordinator: RateLimitCoordinator(clock: clock), clock: clock)
        let identity = RateLimitIdentity(), token = try InteractionToken("bridge-token")
        let initial = RESTClient(credential: .interaction(token), identity: identity,
            transport: initialHTTP, coordinator: RateLimitCoordinator(clock: clock), clock: clock,
            retryPolicy: .init(maximumAttempts: 1))
        let continuation = RESTClient(credential: .interaction(token), identity: identity,
            transport: continuationHTTP, coordinator: RateLimitCoordinator(clock: clock), clock: clock,
            retryPolicy: .init(maximumAttempts: 1))
        let invalidations = self.invalidations
        services = BotServiceAdapter(services: ServiceContext(rest: bot), clock: clock,
            initialClient: { _ in initial }, continuationServices: { _ in
                ServiceContext(rest: continuation) { await invalidations.record() }
            })
        client = DiscordClient(token: try BotToken("synthetic-bridge-bot"),
            configuration: try ClientConfiguration(intents: []), services: ServiceContext(rest: bot),
            transport: ScriptedWebSocketTransport(connection: try connection ?? ScriptedWebSocketConnection(incoming: [])),
            clock: clock, leases: try InProcessShardLeaseStore(clock: clock, maximumLeases: 1),
            authority: try ClientAuthority(botID: UserID(rawValue: 42), clock: clock, budget: ClientResourceBudget()),
            events: hub, project: project)
    }

    /// Compiles one explicit low-level command module, retaining original normalized response ownership.
    /// - Parameter handler: Cooperative test callback; only explicit bridge execution invokes it.
    /// - Returns: Immutable command catalog with one exact root route and matching registration.
    /// - Throws: Invalid command or compile-time catalog validation.
    func commands(_ handler: @escaping @Sendable (InteractionContext) async throws -> Void) throws -> CompiledCommands {
        try CommandCompilation.compile(ExistingCommandFamily(id: "bridge", definitions: [
            CommandDefinition.slash(name: "bridge", description: "Synthetic bridge command")
        ], routes: [CommandRoute(key: .command(name: "bridge"), handler: handler)]))
    }

    /// Creates the task-free private host with a finite input queue and optional command behavior.
    /// - Parameters:
    ///   - maximumPending: Positive private queue count, default two.
    ///   - maximumBytes: Positive private queue byte bound, default 1 MiB.
    ///   - serializesPerShard: True retains legacy ordering; false allows independent same-shard handlers.
    ///   - handler: Cooperative callback, default an original distinguishable failure.
    /// - Returns: Unprepared owner that has not invoked factories, handlers, REST or client startup.
    /// - Throws: Invalid queue, router or registration bounds.
    func adapter(maximumPending: Int = 2, maximumBytes: Int = 1_048_576, serializesPerShard: Bool = true,
                 handler: @escaping @Sendable (InteractionContext) async throws -> Void = { _ in throw BridgeTestFailure.handler })
        throws -> GatewayInteractionAdapter<ManualClock> {
        try GatewayInteractionAdapter(applicationID: .init(rawValue: 9), commands: commands(handler),
            services: services, clock: clock, admission: admission,
            maximumPendingInteractions: maximumPending, maximumPendingBytes: maximumBytes,
            serializesPerShard: serializesPerShard)
    }

    /// Creates an internal socket-equivalent receipt observation for isolated private queue tests.
    /// Public constructors intentionally cannot attach this provenance or reach the private receiver.
    /// - Parameters:
    ///   - application: Expected application snowflake string, default nine.
    ///   - name: Command name, default bridge; other names exercise unmatched-route behavior.
    ///   - payload: Optional replacement complete interaction JSON, including malformed input.
    ///   - age: Initial receipt age, default zero; future/negative observations fail closed.
    /// - Returns: Internal timestamped raw dispatch retaining age as the manual clock advances.
    /// - Throws: Fixture JSON/envelope or shard validation.
    func event(application: String = "9", name: String = "bridge", payload: String? = nil,
               age: Duration = .zero) throws -> GatewayEvent {
        let json = payload ?? Self.interactionJSON(application: application, name: name)
        let envelope = try GatewayEnvelope(.text("{\"op\":0,\"s\":1,\"t\":\"INTERACTION_CREATE\",\"d\":\(json)}"),
            maximumBytes: 1_048_576)
        let clock = self.clock
        let receivedAt = clock.now.advanced(by: .zero - age)
        return GatewayEvent(shard: try .init(botID: .init(rawValue: 42), topologyGeneration: 0, index: 0, count: 1),
            envelope: envelope, receiptAge: { receivedAt.duration(to: clock.now) })
    }

    /// Produces a complete credential-free command snapshot with stable context metadata.
    /// - Parameters:
    ///   - application: Application snowflake, default nine.
    ///   - name: Exact command name, default bridge.
    /// - Returns: Valid interaction JSON containing only a synthetic token.
    static func interactionJSON(application: String = "9", name: String = "bridge") -> String {
        "{\"id\":\"1\",\"application_id\":\"\(application)\",\"type\":2,\"token\":\"bridge-token\",\"version\":1," +
        "\"data\":{\"id\":\"3\",\"name\":\"\(name)\",\"type\":1},\"app_permissions\":\"0\",\"entitlements\":[]," +
        "\"authorizing_integration_owners\":{},\"attachment_size_limit\":1048576}"
    }

    /// Provides a complete immutable message for continuation endpoint decoding.
    static let messageJSON = #"{"id":"7","channel_id":"4","author":{"id":"5","username":"user","discriminator":"0","avatar":null},"content":"response","timestamp":"2026-10-18T12:00:00Z","edited_timestamp":null,"tts":false,"mention_everyone":false,"mentions":[],"mention_roles":[],"attachments":[],"embeds":[],"pinned":false,"type":20}"#

    /// Creates a bounded owned successful JSON response with explicit nonblocking rate metadata.
    /// - Parameters:
    ///   - json: Complete small JSON response fixture.
    ///   - status: HTTP response status, default 200.
    /// - Returns: Single-use response body owned by the real REST pipeline.
    /// - Throws: Invalid bounded request-body fixture.
    static func response(_ json: String, status: Int = 200) throws -> HTTPResponse {
        HTTPResponse(status: status, headers: [.init(name: "X-RateLimit-Limit", value: "100"),
            .init(name: "X-RateLimit-Remaining", value: "99"), .init(name: "X-RateLimit-Reset-After", value: "1")],
            body: try RequestBody(bytes: Data(json.utf8), contentType: "application/json").makeStream())
    }
}

/// Handshakes with the real shard and confirms its interaction was timestamped/queued before
/// waiting for shutdown. No socket read is fabricated through the public event hub.
@available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
private actor BridgeSocket: WebSocketConnection {
    private let identified = TestBarrier()
    private let idle = TestBarrier()
    nonisolated let interactionQueued = TestBarrier()
    private var nextIndex = 0
    private var closed = false

    /// Accepts control writes and opens the READY authentication gate only after Identify.
    /// - Parameters:
    ///   - message: Complete bounded outgoing JSON; no credential bytes are retained.
    ///   - context: Existing cancellation/deadline owner for the write.
    /// - Throws: Cancellation, malformed fixture JSON or an invalid transport context.
    func send<C: Clock>(_ message: WebSocketMessage, context: TransportContext<C>) async throws where C.Duration == Duration {
        try context.check()
        if case .text(let text) = message, case .object(let value) = try JSONValue.parse(text),
           value["op"] == .number(try JSONNumber(rawValue: "2")) { identified.open() }
    }

    /// Supplies Hello, authenticated READY and one interaction, then confirms the caller returned
    /// to its read loop after stamping and enqueueing the interaction before waiting cooperatively.
    /// - Parameter context: Caller-owned clock and cancellation context.
    /// - Returns: Next finite frame, or nil after explicit close.
    /// - Throws: Cancellation, fixture gate or context failures.
    func receive<C: Clock>(context: TransportContext<C>) async throws -> WebSocketMessage? where C.Duration == Duration {
        try context.check()
        guard !closed else { return nil }
        let index = nextIndex; nextIndex += 1
        switch index {
        case 0: return .text(#"{"op":10,"d":{"heartbeat_interval":10000}}"#)
        case 1:
            try await identified.wait()
            return .text(#"{"op":0,"s":1,"t":"READY","d":{"session_id":"synthetic","resume_gateway_url":"wss://gateway.discord.gg"}}"#)
        case 2:
            return .text("{\"op\":0,\"s\":2,\"t\":\"INTERACTION_CREATE\",\"d\":\(BridgeFixture.interactionJSON())}")
        default:
            interactionQueued.open()
            try await idle.wait()
            return nil
        }
    }

    /// Unblocks all owned fixture reads and authentication gates, idempotently.
    func close() { closed = true; identified.open(); idle.open() }
}

/// Proves trusted admission, existing HTTP response ownership and bounded cancellation with offline scripts.
@Suite("Gateway interaction bridge", .timeLimit(.minutes(1)))
struct BridgeTests {
    /// Independent dispatch acknowledges a second same-shard interaction while the first already deferred handler waits.
    /// Advancing the clock afterward does not recreate either initial response; cancellation joins both owners.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func independentInteractionsDoNotWaitForPriorDeferredWork() async throws {
        let fixture = try BridgeFixture(initialSteps: [
            { _ in try BridgeFixture.response("", status: 204) },
            { _ in try BridgeFixture.response("", status: 204) }
        ])
        let first = TestBarrier(), second = TestBarrier(), blocked = TestBarrier()
        let commands = try fixture.commands { context in
            try await context.responder.deferResponse()
            if context.interaction.id.rawValue == 1 { first.open() }
            else { second.open() }
            try await blocked.wait()
        }
        let adapter = try GatewayInteractionAdapter(applicationID: .init(rawValue: 9), commands: commands,
            services: fixture.services, clock: fixture.clock, admission: fixture.admission,
            configuration: try .init(maximumConcurrentHandlers: 2), serializesPerShard: false)
        try await adapter.prepare(client: fixture.client)
        let task = Task { try await adapter.run() }
        try await adapter.receive(fixture.event())
        try await first.wait()
        let secondJSON = BridgeFixture.interactionJSON().replacingOccurrences(of: "\"id\":\"1\"", with: "\"id\":\"2\"")
        try await adapter.receive(fixture.event(payload: secondJSON))
        try await second.wait()
        #expect(await fixture.initialHTTP.executionCount == 2)
        #expect(await adapter.snapshot().activeHandlers == 2)
        try fixture.clock.advance(by: .seconds(4))
        #expect(await fixture.initialHTTP.executionCount == 2)
        await adapter.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(blocked.waitingCount == 0)
        #expect(await adapter.snapshot().activeHandlers == 0)
        #expect(await adapter.snapshot().bufferedEvents == 0)
        #expect(await adapter.snapshot().bufferedBytes == 0)
        #expect(await adapter.snapshot().subscriptions == 0)
        #expect(await fixture.admission.snapshot().activeCount == 0)
        #expect(fixture.clock.pendingSleepCount == 0)
    }

    /// Construction/preparation starts no I/O, replay events cannot gain receipt provenance and
    /// publication to the client's ordinary public hub cannot dispatch a command.
    /// - Throws: Unexpected valid configuration/preparation or cancellation cleanup errors.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func inertConstructionAndPublicReplayIsolation() async throws {
        let fixture = try BridgeFixture(), adapter = try fixture.adapter()
        #expect(await fixture.botHTTP.executionCount == 0)
        #expect(await fixture.initialHTTP.executionCount == 0)
        try await adapter.prepare(client: fixture.client)
        #expect(await fixture.hub.snapshot().subscriptions == 0)
        let internalEvent = try fixture.event()
        let replay = try GatewayEvent(shard: internalEvent.shard, name: internalEvent.name,
            sequence: 1, data: internalEvent.data)
        #expect(replay.elapsedSinceReceipt == nil)
        await #expect(throws: GatewayInteractionFailure.untrustedEvent) { try await adapter.receive(replay) }
        _ = await fixture.hub.publish(replay)
        let owner = Task { try await adapter.run() }
        await adapter.cancel()
        await #expect(throws: CancellationError.self) { try await owner.value }
        #expect(await fixture.initialHTTP.executionCount == 0)
        #expect(await fixture.botHTTP.executionCount == 0)
        #expect(await fixture.client.snapshot().phase == .idle)
        #expect(fixture.clock.pendingSleepCount == 0)
    }

    /// Invalid queue/concurrency limits fail before work; single-use preparation/run and stopped
    /// clients reject installation, while cancellation is idempotent before preparation or execution.
    /// - Throws: Unexpected valid configuration or closed-state transition errors.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func configurationAndSingleUseOwnership() async throws {
        let fixture = try BridgeFixture()
        #expect(throws: GatewayEventDeliveryFailure.invalidConfiguration) { try fixture.adapter(maximumPending: 0) }
        #expect(throws: GatewayEventDeliveryFailure.invalidConfiguration) { try fixture.adapter(maximumBytes: -1) }
        let missing = try fixture.adapter()
        await #expect(throws: GatewayInteractionFailure.notPrepared) { try await missing.run() }
        await #expect(throws: GatewayInteractionFailure.alreadyRun) { try await missing.run() }
        await missing.cancel(); await missing.cancel()
        await #expect(throws: CancellationError.self) { try await missing.prepare(client: fixture.client) }
        let first = try fixture.adapter()
        try await first.prepare(client: fixture.client)
        await #expect(throws: GatewayInteractionFailure.alreadyPrepared) { try await first.prepare(client: fixture.client) }
        let competing = try fixture.adapter()
        await #expect(throws: ClientFailure.alreadyRunning) { try await competing.prepare(client: fixture.client) }
        await first.cancel()
        let stoppedFixture = try BridgeFixture(), stopped = try stoppedFixture.adapter()
        await stoppedFixture.client.shutdown()
        await #expect(throws: ClientFailure.alreadyRunning) { try await stopped.prepare(client: stoppedFixture.client) }
        #expect(await fixture.initialHTTP.executionCount == 0)
    }

    /// Exact application checks, unmatched routes, malformed models and negative receipt ages fail
    /// before callback transmission; the bridge retains original user callback errors through cleanup.
    /// - Parameter mode: One independently exercised invalid input or callback failure branch.
    /// - Throws: Unexpected preparation, queue admission or propagated failure category.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: ["application", "unmatched", "malformed", "age", "handler"])
    func invalidInputAndOriginalHandlerFailure(_ mode: String) async throws {
        let fixture = try BridgeFixture(), adapter = try fixture.adapter()
        try await adapter.prepare(client: fixture.client)
        let event: GatewayEvent = switch mode {
        case "application": try fixture.event(application: "8")
        case "unmatched": try fixture.event(name: "other")
        case "malformed": try fixture.event(payload: "{}")
        case "age": try fixture.event(age: .seconds(-1))
        default: try fixture.event()
        }
        try await adapter.receive(event)
        switch mode {
        case "application": await #expect(throws: GatewayInteractionFailure.wrongApplication) { try await adapter.run() }
        case "unmatched": await #expect(throws: GatewayInteractionFailure.unmatchedCommand) { try await adapter.run() }
        case "age": await #expect(throws: GatewayInteractionFailure.untrustedEvent) { try await adapter.run() }
        case "handler": await #expect(throws: BridgeTestFailure.handler) { try await adapter.run() }
        default: await #expect(throws: (any Error).self) { try await adapter.run() }
        }
        #expect(await fixture.initialHTTP.executionCount == 0)
        #expect(await fixture.admission.snapshot().activeCount == 0)
        #expect(fixture.clock.pendingSleepCount == 0)
    }

    /// Age includes private/raw queue delay; reaching exactly three seconds never refreshes
    /// the acknowledgement budget or submits an HTTP callback after late dispatch admission.
    /// - Parameter serializesPerShard: Verifies receipt-relative expiry under both scheduling modes.
    /// - Throws: Unexpected fixture/admission errors or a different response expiry category.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [true, false]) func receiptDeadlineSurvivesQueueDelay(serializesPerShard: Bool) async throws {
        let fixture = try BridgeFixture()
        let adapter = try fixture.adapter(serializesPerShard: serializesPerShard) { context in
            #expect(context.deliveryMode == .gateway)
            try await context.responder.reply(InteractionMessageCreate(content: .value("late")))
        }
        try await adapter.prepare(client: fixture.client)
        let event = try fixture.event()
        try await adapter.receive(event)
        try fixture.clock.advance(by: .seconds(3))
        #expect(event.elapsedSinceReceipt == .seconds(3))
        await #expect(throws: InteractionLifecycleError.deadlineExceeded) { try await adapter.run() }
        #expect(await fixture.initialHTTP.executionCount == 0)
        #expect(await fixture.admission.snapshot().activeCount == 0)
    }

    /// The real shard stamps socket receipt before raw queue/projection delays; a slow READY
    /// projection cannot reset the following interaction's acknowledgement deadline at bridge admission.
    /// - Throws: Unexpected handshake, projection, command expiry or structured shutdown failures.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func ownedSocketReceiptSurvivesSlowProjection() async throws {
        let socket = BridgeSocket(), projection = TestBarrier()
        let fixture = try BridgeFixture(botSteps: [{ request in
            #expect(request.url.path == "/api/v10/gateway/bot")
            return try BridgeFixture.response(#"{"url":"wss://gateway.discord.gg","shards":1,"session_start_limit":{"total":100,"remaining":100,"reset_after":3600000,"max_concurrency":1}}"#)
        }], connection: socket, project: { event in
            if event.name == "READY" { try await projection.wait() }
        })
        let adapter = try fixture.adapter { context in
            try await context.responder.reply(InteractionMessageCreate(content: .value("late")))
        }
        try await adapter.prepare(client: fixture.client)
        let client = Task { try await fixture.client.run() }
        let commands = Task { try await adapter.run() }
        try await socket.interactionQueued.wait()
        try fixture.clock.advance(by: .seconds(3))
        projection.open()
        await #expect(throws: InteractionLifecycleError.deadlineExceeded) { try await commands.value }
        await fixture.client.shutdown()
        try await client.value
        #expect(await fixture.client.snapshot().phase == .stopped)
        #expect(await fixture.initialHTTP.executionCount == 0)
        #expect(await fixture.admission.snapshot().activeCount == 0)
        #expect(await fixture.hub.snapshot().bufferedBytes == 0)
        #expect(fixture.clock.pendingSleepCount == 0)
    }

    /// Private input count and byte overload terminate continuity explicitly without unbounded tasks,
    /// and cancellation while a callback is active awaits the callback's cooperative cleanup.
    /// - Parameter bytes: Selects envelope-byte exhaustion instead of queue-count exhaustion.
    /// - Throws: Unexpected preparation or overflow error categories.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [false, true]) func privateQueueBounds(bytes: Bool) async throws {
        let fixture = try BridgeFixture(), adapter = try fixture.adapter(maximumPending: 1, maximumBytes: bytes ? 1 : 1_048_576)
        try await adapter.prepare(client: fixture.client)
        if !bytes { try await adapter.receive(fixture.event()) }
        await #expect(throws: GatewayEventDeliveryFailure.resynchronizationRequired) {
            try await adapter.receive(fixture.event())
        }
        await #expect(throws: GatewayEventDeliveryFailure.resynchronizationRequired) { try await adapter.run() }
        await adapter.cancel()
        #expect(await fixture.initialHTTP.executionCount == 0)
    }

    /// Handler cancellation releases all shared admission and clock records before the run returns.
    /// - Throws: Unexpected setup, gate or cancellation propagation failures.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func activeHandlerCancellation() async throws {
        let entered = TestBarrier(), blocked = TestBarrier(), fixture = try BridgeFixture()
        let adapter = try fixture.adapter { _ in entered.open(); try await blocked.wait() }
        try await adapter.prepare(client: fixture.client)
        try await adapter.receive(fixture.event())
        let owner = Task { try await adapter.run() }
        try await entered.wait()
        owner.cancel()
        await #expect(throws: CancellationError.self) { try await owner.value }
        #expect(blocked.waitingCount == 0)
        #expect(await fixture.admission.snapshot().activeCount == 0)
        #expect(fixture.clock.pendingSleepCount == 0)
        await adapter.cancel()
    }

    /// Gateway initial callbacks and deferred completion use the existing exact-token HTTP routes,
    /// separate transport admission and conservative continuation mutation invalidation.
    /// - Throws: Unexpected typed REST, responder or continuation decoding failures.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func serviceHTTPCallbacksAndContinuations() async throws {
        let fixture = try BridgeFixture(initialSteps: [{ request in
            #expect(request.method == "POST")
            #expect(request.url.path == "/api/v10/interactions/1/bridge-token/callback")
            #expect(!request.headers.contains { $0.name.lowercased() == "authorization" })
            return HTTPResponse(status: 204)
        }], continuationSteps: [
            { request in
                #expect(request.method == "PATCH")
                #expect(request.url.path == "/api/v10/webhooks/9/bridge-token/messages/@original")
                return try BridgeFixture.response(BridgeFixture.messageJSON)
            },
            { request in
                #expect(request.method == "POST")
                #expect(request.url.path == "/api/v10/webhooks/9/bridge-token")
                return try BridgeFixture.response(BridgeFixture.messageJSON)
            },
            { request in
                #expect(request.method == "DELETE")
                return HTTPResponse(status: 204)
            }
        ])
        let interaction = try Interaction(data: Data(BridgeFixture.interactionJSON().utf8))
        let responder = InteractionResponder(interaction: interaction, deliveryMode: .gateway,
            clock: InteractionClock(fixture.clock), sink: fixture.services.responseSink(for: interaction),
            admission: fixture.admission)
        try await responder.deferResponse(ephemeral: true)
        #expect(await fixture.initialHTTP.executionCount == 1)
        #expect(await fixture.continuationHTTP.executionCount == 0)
        #expect(try await responder.editOriginal(InteractionMessageEdit(content: .value("done"))).id.rawValue == 7)
        #expect(try await responder.followup(InteractionMessageCreate(content: .value("next"))).id.rawValue == 7)
        try await responder.deleteOriginal()
        #expect(await fixture.invalidations.count == 6)
        #expect(await fixture.initialHTTP.executionCount == 1)
        #expect(await fixture.continuationHTTP.executionCount == 3)
        #expect(await fixture.botHTTP.executionCount == 0)
        #expect(await fixture.admission.snapshot().activeCount == 0)
        #expect(fixture.clock.pendingSleepCount == 0)
    }

    /// Clock-independent generic service injection preserves ordinary bot authentication; invalid
    /// relative timeout values fail before any request and explicit catalog synchronization alone reads commands.
    /// - Throws: Unexpected REST decoding or explicit reconciliation failures.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func genericServiceAndExplicitSynchronization() async throws {
        let read: ScriptedHTTPTransport.Step = { request in
            #expect(request.method == "GET")
            #expect(request.url.path == "/api/v10/users/@me")
            return try BridgeFixture.response(#"{"id":"42","username":"bot","discriminator":"0","global_name":null,"avatar":null}"#)
        }
        let fixture = try BridgeFixture(botSteps: [read, read])
        let services: any BotServiceProviding = fixture.services
        for invalid: Duration in [.zero, .seconds(-1), .seconds(86_401), .seconds(Int64.max)] {
            await #expect(throws: DiscordError.validation(.invalidValue)) {
                _ = try await services.execute(DiscordEndpoints.currentUser(), timeout: invalid)
            }
        }
        #expect(await fixture.botHTTP.executionCount == 0)
        #expect(try await services.execute(DiscordEndpoints.currentUser(), timeout: .seconds(1)).id.rawValue == 42)
        #expect(try await fixture.services.execute(DiscordEndpoints.currentUser()).id.rawValue == 42)
        let registration = try BridgeFixture(botSteps: [{ request in
            #expect(request.method == "GET")
            #expect(request.url.path == "/api/v10/applications/9/commands")
            return try BridgeFixture.response("[]")
        }])
        let commands = try CommandCompilation.compile(EmptyBotDefinition())
        let adapter = try GatewayInteractionAdapter(applicationID: .init(rawValue: 9), commands: commands,
            services: registration.services, clock: registration.clock, admission: registration.admission)
        #expect(await registration.botHTTP.executionCount == 0)
        _ = try await adapter.synchronize()
        #expect(await registration.botHTTP.executionCount == 1)
        #expect(fixture.clock.pendingSleepCount == 0)
    }

    /// Ambiguous initial delivery retains uncertainty without replay; failed continuation mutations
    /// still invalidate twice, and exact fifteen-minute expiry prevents further HTTP transmission.
    /// - Parameter initialFailure: Selects initial callback loss instead of continuation connection loss.
    /// - Throws: Unexpected fixture/admission errors or failure classification.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [true, false]) func serviceFailureUncertaintyAndExpiry(initialFailure: Bool) async throws {
        let fixture = try BridgeFixture(initialSteps: [{ _ in
            if initialFailure { throw DiscordError.transport(.disconnected) }
            return HTTPResponse(status: 204)
        }], continuationSteps: [{ _ in throw DiscordError.transport(.disconnected) }])
        let interaction = try Interaction(data: Data(BridgeFixture.interactionJSON().utf8))
        let responder = InteractionResponder(interaction: interaction, deliveryMode: .gateway,
            clock: InteractionClock(fixture.clock), sink: fixture.services.responseSink(for: interaction),
            admission: fixture.admission)
        if initialFailure {
            await #expect(throws: DiscordError.unknownMutationOutcome(.connectionLostAfterSubmission)) {
                try await responder.deferResponse()
            }
            #expect(await responder.snapshot() == .indeterminate)
            await #expect(throws: InteractionLifecycleError.indeterminateAcknowledgement) {
                try await responder.deferResponse()
            }
            #expect(await fixture.continuationHTTP.executionCount == 0)
        } else {
            try await responder.deferResponse()
            await #expect(throws: DiscordError.unknownMutationOutcome(.connectionLostAfterSubmission)) {
                _ = try await responder.editOriginal(InteractionMessageEdit(content: .value("uncertain")))
            }
            #expect(await fixture.invalidations.count == 2)
            try fixture.clock.advance(by: .seconds(900))
            await #expect(throws: InteractionLifecycleError.tokenExpired) { try await responder.deleteOriginal() }
            #expect(await fixture.continuationHTTP.executionCount == 1)
        }
        #expect(await fixture.initialHTTP.executionCount == 1)
        #expect(await fixture.admission.snapshot().activeCount == 0)
        #expect(fixture.clock.pendingSleepCount == 0)
    }

    /// Cancellation during HTTP response-body consumption closes that transferred body and releases
    /// response admission before returning, while preserving possible remote callback submission.
    /// - Throws: Unexpected gate, fixture or uncertainty classification failures.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func serviceCancellationClosesTransferredResponseBody() async throws {
        let entered = TestBarrier(), blocked = TestBarrier(), closed = BridgeInvalidations()
        let fixture = try BridgeFixture(initialSteps: [{ _ in
            HTTPResponse(status: 204, body: try BodyStream(maximumChunkBytes: 64,
                next: { entered.open(); try await blocked.wait(); return nil },
                close: { await closed.record() }))
        }])
        let interaction = try Interaction(data: Data(BridgeFixture.interactionJSON().utf8))
        let responder = InteractionResponder(interaction: interaction, deliveryMode: .gateway,
            clock: InteractionClock(fixture.clock), sink: fixture.services.responseSink(for: interaction),
            admission: fixture.admission)
        let owner = Task { try await responder.deferResponse() }
        try await entered.wait()
        owner.cancel()
        do {
            try await owner.value
            Issue.record("Cancelled callback must report cancellation or submission uncertainty")
        } catch {
            #expect(error is CancellationError ||
                (error as? DiscordError) == .unknownMutationOutcome(.cancelledAfterSubmission))
        }
        #expect(await responder.snapshot() == .indeterminate)
        await #expect(throws: InteractionLifecycleError.indeterminateAcknowledgement) { try await responder.deferResponse() }
        #expect(await closed.count == 1)
        #expect(blocked.waitingCount == 0)
        #expect(await fixture.initialHTTP.executionCount == 1)
        #expect(await fixture.admission.snapshot().activeCount == 0)
        #expect(fixture.clock.pendingSleepCount == 0)
    }
}
