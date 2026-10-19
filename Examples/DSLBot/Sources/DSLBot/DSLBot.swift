import DiscordBotDSL
import DiscordClient
import DiscordCommandDSL
import DiscordCore
import DiscordDSL
import DiscordGateway
import DiscordHTTP
import DiscordInteractions
import DiscordModels
import DiscordTransport
import Foundation

/// Nonsecret local assertions; no service response or credential text is retained in failures.
enum BotDemoFailure: Error, Equatable { case unexpectedRequest, callbackMismatch, incomplete, cleanup }

/// Joined evidence from the independent consumer, using real client/bridge ownership and synthetic peers.
struct BotDemoResult: Sendable {
    let labels: [String]
    let callbackCount: Int
    let registrationCount: Int
    let callbacksBeforeRun: Int
    let ownedResources: Int
}

/// Empty command arguments are rebuilt for every invocation through the public schema extension point.
private struct PingArguments: CommandArguments {
    /// Describes no options and captures a constructor without executing it during compilation.
    /// - Throws: Existing finite schema validation errors.
    static var schema: CommandArgumentSchema<Self> {
        /// Captures the fresh empty-value constructor without invoking it.
        /// - Returns: A validated finite schema with no options.
        /// - Throws: Existing schema admission failures.
        get throws { try .init(options: []) { _ in Self() } }
    }
}

/// Handwritten external command protocol conformance with explicit existing response ownership.
private struct PingCommand: ManualSlashCommandHandler {
    let transcript: BotTranscript
    let command = SlashCommandMetadata(name: "ping", description: "Check the offline supervised bot")

    /// Replies once through the existing responder, then releases the synthetic peer's next dispatch.
    /// - Parameters:
    ///   - context: Trusted Gateway invocation with the existing receipt-relative response owner.
    ///   - arguments: Fresh empty typed invocation value.
    /// - Throws: Existing response validation, cancellation, HTTP admission or delivery failures.
    func execute(_ context: InteractionContext, arguments: PingArguments) async throws {
        let response = try MessageResponse(visibility: .ephemeral) { Text("Pong!") }
        try await context.responder.reply(response.message)
        await transcript.record("ping")
        await transcript.commandCompleted.open()
    }
}

/// Reusable external module owns declarations and initializer-injected services, without runtime work.
private struct PingModule: BotModule {
    let moduleID = "example.commands"
    let ping: SlashCommand<PingCommand>
    /// Contributes one already validated command without registering or executing it.
    @BotBuilder var body: some BotDefinition { ping }
}

/// Typed READY observation demonstrates ordinary event delivery beside private command ingress.
private struct ReadyHandler: GatewayEventHandler {
    let handlerID = "example.ready"
    let selector = GatewayEventSelector<GatewayReady>.ready
    let transcript: BotTranscript
    /// Records the first authenticated dispatch, preserving module order without owning a connection.
    /// - Parameters:
    ///   - event: Existing partial READY value; resource availability is not inferred.
    ///   - context: Original source provenance, unused by this finite observation.
    func handle(_ event: GatewayReady, context: GatewayEventContext) async throws {
        await transcript.record("ready")
        await transcript.readyHandled.open()
    }
}

/// A synthetic future dispatch requests nonjoining stop only after the command's reply completed.
private struct StopHandler: GatewayEventHandler {
    let handlerID = "example.stop"
    let selector = GatewayEventSelector<GatewayUnknownEvent>.unknown
    let transcript: BotTranscript
    let reference: RuntimeReference
    /// Stops its own host without joining the callback currently executing in that host.
    /// - Parameters:
    ///   - event: Existing unknown-event projection of the synthetic completion event.
    ///   - context: Exact shard provenance; not used as authorization evidence.
    func handle(_ event: GatewayUnknownEvent, context: GatewayEventContext) async throws {
        guard event.name == "OFFLINE_STOP" else { return }
        await transcript.record("stop")
        await reference.requestStop()
    }
}

/// A second reusable module shares only explicitly injected application services with the command module.
private struct StatusModule: BotModule {
    let moduleID = "example.events"
    let transcript: BotTranscript
    let reference: RuntimeReference
    /// Preserves READY-before-completion handler ordering through the existing default pipeline.
    @BotBuilder var body: some BotDefinition {
        ReadyHandler(transcript: transcript)
        StopHandler(transcript: transcript, reference: reference)
    }
}

/// `@main`-compatible host composition with no ambient credential or concrete network adapter selection.
@main struct DSLBot: BotApplication {
    /// Builds one inert runtime with explicit protocol modules, authorities and synthetic transport peers.
    /// - Returns: Single-use host; no tasks, HTTP execution, registration or sockets have started.
    /// - Throws: Finite fixture, command/event compilation or host configuration validation failures.
    static func makeRuntime() async throws -> BotRuntime { try await BotExampleFixture().makeRuntime() }

    /// Runs a joined offline demonstration and prints only bounded verified evidence.
    /// - Throws: Configuration, callback, lifecycle, cancellation or final cleanup assertion errors.
    static func main() async throws {
        let evidence = try await runOffline()
        print("Offline supervised bot: \(evidence.labels.joined(separator: " -> ")); one HTTP callback; zero registration requests; zero owned resources.")
    }

    /// Executes the independent protocol-based modules over actual client ingestion and HTTP response ownership.
    /// - Returns: Joined observations; local synthetic evidence does not qualify live Discord or capacity.
    /// - Throws: Original compile/runtime errors or a final finite evidence/cleanup assertion failure.
    static func runOffline() async throws -> BotDemoResult {
        let fixture = try BotExampleFixture()
        let runtime = try await fixture.makeRuntime()
        let before = await fixture.http.callbackCount
        guard before == 0, await fixture.http.requestCount == 0,
              await fixture.hub.snapshot().subscriptions == 0 else { throw BotDemoFailure.incomplete }
        try await runtime.run()
        try await runtime.shutdown()
        let hub = await fixture.hub.snapshot(), handlers = await fixture.handlerAuthority.snapshot()
        let budget = await fixture.budget.snapshot()
        let owned = hub.subscriptions + hub.bufferedEvents + hub.bufferedBytes + hub.waitingConsumers +
            handlers.activeHandlers + handlers.waitingHandlers + budget.clients + budget.shards + budget.rawEvents + budget.rawBytes +
            (await fixture.leases.retainedLeaseCount())
        guard owned == 0, await fixture.socket.closed else { throw BotDemoFailure.cleanup }
        let labels = await fixture.transcript.snapshot()
        guard labels == ["ready", "ping", "stop"], await fixture.http.callbackCount == 1,
              await fixture.http.registrationCount == 0 else { throw BotDemoFailure.incomplete }
        return BotDemoResult(labels: labels, callbackCount: await fixture.http.callbackCount,
            registrationCount: await fixture.http.registrationCount, callbacksBeforeRun: before, ownedResources: owned)
    }
}

/// Application-owned observation and explicit completion gate, bounded to three labels.
private actor BotTranscript {
    nonisolated let commandCompleted = DemoGate()
    nonisolated let readyHandled = DemoGate()
    private var labels: [String] = []
    /// Records one application-owned label; no wire or token data is stored.
    /// - Parameter label: One of the three fixed example labels.
    func record(_ label: String) { if labels.count < 3 { labels.append(label) } }
    /// Copies the finite record after the owner has joined all callbacks.
    /// - Returns: Recorded labels in arrival order.
    func snapshot() -> [String] { labels }
}

/// Resolves the explicit host/handler dependency cycle before starting work.
private actor RuntimeReference {
    private var runtime: BotRuntime?
    /// Installs exactly the host that will own these event handlers.
    /// - Parameter runtime: Inert application host.
    func install(_ runtime: BotRuntime) { self.runtime = runtime }
    /// Clears the reference and requests stop without joining the current handler.
    func requestStop() async { let host = runtime; runtime = nil; await host?.requestStop() }
}

/// Real production owners over injected in-memory peers; construction performs no transport execution.
private struct BotExampleFixture {
    let clock = ContinuousClock()
    let transcript = BotTranscript()
    let reference = RuntimeReference()
    let http = DemoHTTP()
    let socket: DemoSocket
    let hub: GatewayEventHub
    let budget: ClientResourceBudget
    let handlerAuthority: GatewayHandlerAuthority
    let leases: InProcessShardLeaseStore<ContinuousClock>
    let client: DiscordClient<ContinuousClock, InProcessShardLeaseStore<ContinuousClock>>

    /// Creates shared bot, startup, lease and callback authorities with one credential-free scripted peer.
    /// - Throws: Invalid fixed finite bounds or synthetic sentinel credential format.
    init() throws {
        socket = DemoSocket(completed: transcript.commandCompleted, ready: transcript.readyHandled)
        hub = GatewayEventHub(configuration: try .init())
        budget = try ClientResourceBudget()
        handlerAuthority = try GatewayHandlerAuthority(maximumActiveHandlers: 4, maximumWaitingHandlers: 4)
        leases = try InProcessShardLeaseStore(clock: clock, maximumLeases: 2)
        let rest = RESTClient(credential: .bot(try BotToken("offline-dslbot-sentinel")), identity: RateLimitIdentity(),
            transport: http, coordinator: RateLimitCoordinator(clock: clock), clock: clock)
        let authority = try ClientAuthority(botID: .init(rawValue: 42), clock: clock, budget: budget)
        client = DiscordClient(token: try BotToken("offline-dslbot-sentinel"),
            configuration: try .init(intents: [.guilds]), services: ServiceContext(rest: rest),
            transport: DemoWebSocketTransport(socket: socket), clock: clock, leases: leases,
            authority: authority, events: hub)
    }

    /// Compiles command/event protocol modules separately and binds exact-token response services to one host.
    /// - Returns: Inert host with an authenticated-client-only command ingress and one event subscription.
    /// - Throws: Existing declaration, response admission, bridge configuration or intent validation failures.
    func makeRuntime() async throws -> BotRuntime {
        let declaration = try SlashCommand(id: "example.ping", handler: PingCommand(transcript: transcript))
        let commands = try CommandCompilation.compile(PingModule(ping: declaration))
        let events = try EventCompilation.compile(StatusModule(transcript: transcript, reference: reference), intents: [.guilds])
        let clock = clock, http = http
        let initialCoordinator = RateLimitCoordinator(clock: clock)
        let continuationCoordinator = RateLimitCoordinator(clock: clock)
        let identity = RateLimitIdentity()
        let services = BotServiceAdapter(services: client.services, clock: clock, initialClient: { interaction in
            RESTClient(credential: .interaction(interaction.token), identity: identity, transport: http,
                coordinator: initialCoordinator, clock: clock)
        }, continuationServices: { interaction in
            ServiceContext(rest: RESTClient(credential: .interaction(interaction.token), identity: identity,
                transport: http, coordinator: continuationCoordinator, clock: clock))
        })
        let interactions = try GatewayInteractionAdapter(applicationID: .init(rawValue: 2), commands: commands,
            services: services, clock: clock, admission: InteractionAcknowledgementAdmission(),
            authority: handlerAuthority)
        let runtime = try BotRuntime(client: client, events: events, handlerConfiguration: .init(),
            handlerAuthority: handlerAuthority, interactions: interactions)
        await reference.install(runtime)
        return runtime
    }
}

/// Cancellable finite gate; cancellation removes precisely the pending waiter and never opens the gate.
private actor DemoGate {
    private var opened = false
    private var waiters: [UUID: CheckedContinuation<Void, any Error>] = [:]
    /// Waits for explicit completion with race-safe cancellation and no clock or network work.
    /// - Throws: Cancellation before admission or while suspended.
    func wait() async throws {
        try Task.checkCancellation()
        if opened { return }
        let identifier = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                if Task.isCancelled { continuation.resume(throwing: CancellationError()) }
                else if opened { continuation.resume() }
                else { waiters[identifier] = continuation }
            }
        } onCancel: { Task { await self.cancel(identifier) } }
    }
    /// Opens permanently and releases every currently retained waiter exactly once.
    func open() { opened = true; let pending = waiters.values; waiters.removeAll(); for waiter in pending { waiter.resume() } }
    /// Removes one cancelled waiter without affecting other consumers.
    /// - Parameter identifier: Exact admitted waiter identity; missing identities are harmless.
    private func cancel(_ identifier: UUID) { waiters.removeValue(forKey: identifier)?.resume(throwing: CancellationError()) }
}

/// Single finite response body owned by one successful discovery exchange.
private actor DemoBody {
    private var bytes: Data?
    /// Retains one bounded JSON fixture body.
    /// - Parameter bytes: Small complete discovery JSON.
    init(_ bytes: Data) { self.bytes = bytes }
    /// Transfers the body once, then returns EOF.
    /// - Returns: Original bytes or nil after transfer/closure.
    func take() -> Data? { defer { bytes = nil }; return bytes }
    /// Idempotently discards unread bytes.
    func clear() { bytes = nil }
}

/// The only accepted requests are owned Gateway discovery and one exact interaction callback.
private actor DemoHTTP: HTTPTransport {
    private(set) var requestCount = 0
    private(set) var callbackCount = 0
    private(set) var registrationCount = 0
    /// Serves local discovery or validates the callback against the existing direct-model JSON payload.
    /// - Parameters:
    ///   - request: Complete owned request; its body is consumed or closed on every path.
    ///   - context: The existing REST cancellation/deadline context.
    /// - Returns: A bounded discovery response or successful empty callback response.
    /// - Throws: Cancellation, oversized callback body or unexpected URL/method/payload errors.
    func execute<C: Clock>(_ request: HTTPRequest, context: TransportContext<C>) async throws -> HTTPResponse where C.Duration == Duration {
        do {
            try context.check()
            requestCount += 1
            if request.method == "GET", request.url.path == "/api/v10/gateway/bot" {
                let bytes = Data(#"{"url":"wss://gateway.discord.gg","shards":1,"session_start_limit":{"total":100,"remaining":100,"reset_after":3600000,"max_concurrency":1}}"#.utf8)
                let body = DemoBody(bytes)
                await request.body?.close()
                return HTTPResponse(status: 200, body: try BodyStream(maximumChunkBytes: 4096,
                    next: { await body.take() }, close: { await body.clear() }))
            }
            if request.url.path.contains("/commands") { registrationCount += 1 }
            guard request.method == "POST", request.url.path == "/api/v10/interactions/1/synthetic-offline/callback",
                  callbackCount == 0 else { throw BotDemoFailure.unexpectedRequest }
            let bytes = try await ResponseBody.collect(request.body, maximumBytes: 4096)
            let expected = try JSONValue.parse(#"{"type":4,"data":{"content":"Pong!","flags":64,"allowed_mentions":{"parse":[],"replied_user":false}}}"#)
            guard try JSONValue.parse(bytes) == expected else { throw BotDemoFailure.callbackMismatch }
            callbackCount += 1
            return HTTPResponse(status: 204)
        } catch { await request.body?.close(); throw error }
    }
}

/// Injected connector transfers one synthetic connection to the real Gateway shard.
private struct DemoWebSocketTransport: WebSocketTransport {
    let socket: DemoSocket
    /// Returns the local protocol peer only after checking ordinary transport cancellation and deadline.
    /// - Parameters:
    ///   - request: Gateway upgrade request, ignored without reading or retaining credentials.
    ///   - context: Existing connection cancellation/deadline context.
    /// - Returns: The one application-owned synthetic connection.
    /// - Throws: Context cancellation or deadline failures.
    func connectWebSocket<C: Clock>(_ request: HTTPRequest, context: TransportContext<C>) async throws -> any WebSocketConnection where C.Duration == Duration {
        try context.check(); return socket
    }
}

/// Protocol frames enter through the real shard; no public hub publication is treated as trusted ingress.
private actor DemoSocket: WebSocketConnection {
    private let identified = DemoGate(), idle = DemoGate()
    private let completed: DemoGate
    private let ready: DemoGate
    private var index = 0
    private(set) var closed = false
    /// Stores the explicit command completion gate without starting protocol work.
    /// - Parameters:
    ///   - completed: Opened only after the manual command's responder reply has returned.
    ///   - ready: Explicit synthetic peer gate; cross-pipeline scheduling supplies no global order.
    init(completed: DemoGate, ready: DemoGate) { self.completed = completed; self.ready = ready }
    /// Recognizes Identify by opcode without storing token-bearing outbound JSON.
    /// - Parameters:
    ///   - message: Existing complete control frame.
    ///   - context: Production cancellation/deadline context.
    /// - Throws: Context errors or malformed synthetic control JSON.
    func send<C: Clock>(_ message: WebSocketMessage, context: TransportContext<C>) async throws where C.Duration == Duration {
        try context.check()
        guard case .text(let text) = message, case .object(let data) = try JSONValue.parse(text),
            case .number(let opcode) = data["op"] else { throw BotDemoFailure.unexpectedRequest }
        if opcode.rawValue == "2" { await identified.open() }
    }
    /// Emits Hello, Identify-gated READY, an actual command dispatch and completion-gated future dispatch.
    /// - Parameter context: Production receive cancellation/deadline context.
    /// - Returns: The next finite frame, or EOF after local closure.
    /// - Throws: Context or cooperative cancellation failures.
    func receive<C: Clock>(context: TransportContext<C>) async throws -> WebSocketMessage? where C.Duration == Duration {
        try context.check()
        if closed { return nil }
        let slot = index; index += 1
        switch slot {
        case 0: return .text(#"{"op":10,"d":{"heartbeat_interval":10000}}"#)
        case 1:
            try await identified.wait()
            return .text(#"{"op":0,"s":1,"t":"READY","d":{"v":10,"user":{"id":"42","username":"offline","discriminator":"0","global_name":null,"avatar":null},"guilds":[],"session_id":"offline","resume_gateway_url":"wss://gateway.discord.gg","application":{"id":"2","flags":0}}}"#)
        case 2:
            try await ready.wait()
            return .text(#"{"op":0,"s":2,"t":"INTERACTION_CREATE","d":{"id":"1","application_id":"2","type":2,"token":"synthetic-offline","version":1,"data":{"id":"3","name":"ping","type":1},"app_permissions":"0","entitlements":[],"authorizing_integration_owners":{},"attachment_size_limit":1000}}"#)
        case 3:
            try await completed.wait()
            return .text(#"{"op":0,"s":3,"t":"OFFLINE_STOP","d":{}}"#)
        default: try await idle.wait(); return nil
        }
    }
    /// Closes every retained receive gate once; no transport resources exist outside this synthetic peer.
    func close() async { closed = true; await identified.open(); await completed.open(); await ready.open(); await idle.open() }
}
