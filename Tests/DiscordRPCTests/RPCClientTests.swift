import DiscordCore
import DiscordTransport
import DiscordTestSupport
import Foundation
import Testing
@testable import DiscordRPC

/// Deterministic local RPC peer; barriers synchronize on actual reads/writes, never sleeps.
actor RPCPeer: RPCConnection {
    private var incoming: [RPCFrame] = []
    private var receiveWaiter: CheckedContinuation<RPCFrame?, Never>?
    private var sent: [RPCFrame] = []
    private var sentWaiter: CheckedContinuation<RPCFrame, Never>?
    private var closed = false
    private var readEntered: CheckedContinuation<Void, Never>?
    private var isReading = false
    private(set) var closeCount = 0
    private(set) var handshakes = 0

    /// Creates a fresh peer with a valid v1 READY or supplied startup sequence.
    /// - Parameter startup: Explicit startup sequence; nil uses a synthetic v1 READY.
    init(startup: [RPCFrame]? = nil) {
        incoming = startup ?? [.init(opcode: .frame, payload: Data("{\"cmd\":\"DISPATCH\",\"evt\":\"READY\",\"data\":{\"v\":1}}".utf8))]
    }

    /// Records handshake admission without automatically authorizing the application.
    /// - Parameters:
    ///   - applicationID: Test application identifier, deliberately not a bot token.
    ///   - context: Checked clock/deadline/cancellation.
    /// - Throws: Cancellation/deadline or closed peer.
    func handshake<C: Clock>(applicationID: ApplicationID, context: TransportContext<C>) async throws where C.Duration == Duration {
        try context.check(); guard !closed else { throw RPCFailure.closed }; handshakes += 1
    }

    /// Records one write and wakes an awaiting test observer atomically.
    /// - Parameters:
    ///   - frame: Complete runtime output frame.
    ///   - context: Checked write context.
    /// - Throws: Cancellation/deadline or closed peer.
    func send<C: Clock>(_ frame: RPCFrame, context: TransportContext<C>) async throws where C.Duration == Duration {
        try context.check(); guard !closed else { throw RPCFailure.closed }
        if let waiter = sentWaiter { sentWaiter = nil; waiter.resume(returning: frame) }
        else { sent.append(frame) }
    }

    /// Returns queued input or suspends until explicit test input/cleanup.
    /// - Parameter context: Checked read context with independently cancellable continuation.
    /// - Returns: Input frame or nil on close/cancellation.
    /// - Throws: Cancellation/deadline before admission.
    func receive<C: Clock>(context: TransportContext<C>) async throws -> RPCFrame? where C.Duration == Duration {
        try context.check()
        if !incoming.isEmpty { return incoming.removeFirst() }
        guard !closed else { return nil }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                receiveWaiter = continuation; isReading = true
                readEntered?.resume(); readEntered = nil
            }
        } onCancel: { Task { await self.close() } }
    }

    /// Injects one server frame, resuming the sole reader or retaining it until read.
    /// - Parameter frame: Synthetic remote frame, including malicious variants.
    func push(_ frame: RPCFrame) {
        if let waiter = receiveWaiter { receiveWaiter = nil; isReading = false; waiter.resume(returning: frame) }
        else { incoming.append(frame) }
    }

    /// Injects a JSON object while preserving exact server wire spellings in the fixture string.
    /// - Parameter json: Complete synthetic envelope text.
    func pushJSON(_ json: String) { push(.init(opcode: .frame, payload: Data(json.utf8))) }

    /// Waits until a runtime write is observed, providing deterministic request admission.
    /// - Returns: The next written frame in wire order.
    func nextSent() async -> RPCFrame {
        if !sent.isEmpty { return sent.removeFirst() }
        return await withCheckedContinuation { sentWaiter = $0 }
    }

    /// Waits until the session reader is suspended after consuming all input.
    func waitForRead() async {
        if isReading { return }
        await withCheckedContinuation { readEntered = $0 }
    }

    /// Echoes correlation metadata from a recorded request, allowing custom data/error/event.
    /// - Parameters:
    ///   - request: Recorded FRAME carrying command/nonce.
    ///   - data: Synthetic server data; defaults to explicit null.
    ///   - event: Optional event name such as ERROR.
    ///   - command: Optional malicious command override to test correlation rejection.
    /// - Throws: Malformed local fixture or serialization failure.
    func reply(to request: RPCFrame, data: JSONValue = .null, event: String? = nil, command: String? = nil) throws {
        guard case .object(let object) = try JSONValue.parse(request.payload) else { throw RPCFailure.invalidPayload }
        var response: [String: JSONValue] = ["cmd": command.map(JSONValue.string) ?? object["cmd"]!, "nonce": object["nonce"]!, "data": data]
        if let event { response["evt"] = .string(event) }
        push(.init(opcode: .frame, payload: try JSONValue.object(response).serialized()))
    }

    /// Releases the read continuation exactly once; repeated cleanup has no additional effect.
    func close() async {
        guard !closed else { return }; closed = true; closeCount += 1
        receiveWaiter?.resume(returning: nil); receiveWaiter = nil; isReading = false
    }
}

/// Fresh connection sequence for reconnect/correlation fencing tests.
actor RPCPeerConnector: RPCConnector {
    private var peers: [RPCPeer]
    /// Stores finite peers without opening I/O or consuming a script entry.
    /// - Parameter peers: Returned in order for successive explicit connection generations.
    init(_ peers: [RPCPeer]) { self.peers = peers }
    /// Transfers the next peer or reports an absent desktop without retrying.
    /// - Parameters:
    ///   - applicationID: Synthetic registered app ID.
    ///   - context: Checked startup context.
    /// - Returns: Next explicitly supplied owned peer.
    /// - Throws: Cancellation/deadline or script exhaustion as unavailable.
    func connect<C: Clock>(applicationID: ApplicationID, context: TransportContext<C>) async throws -> any RPCConnection where C.Duration == Duration {
        try context.check(); guard !peers.isEmpty else { throw RPCFailure.unavailable }; return peers.removeFirst()
    }
}

/// Runtime regressions use lossless synthetic RPC v1 peers and direct async tasks.
@Suite struct RPCClientTests {
    /// Creates an unconnected client with tiny deterministic request/event budgets.
    /// - Parameters:
    ///   - peers: Explicit fresh connection generations.
    ///   - maximumPending: Pending request cap, default two.
    ///   - maximumEvents: Event count cap, default two.
    /// - Returns: Client with no started tasks or network I/O.
    /// - Throws: Invalid local budget configuration.
    private func client(_ peers: [RPCPeer], maximumPending: Int = 2, maximumEvents: Int = 2) throws -> RPCClient<ContinuousClock> {
        try RPCClient(applicationID: ApplicationID(rawValue: UInt64.max), clock: ContinuousClock(), connector: RPCPeerConnector(peers), maximumPendingRequests: maximumPending, maximumEvents: maximumEvents)
    }

    /// Supplies a real monotonic context with no timing assumptions or real-time sleeps.
    /// - Returns: Nonexpiring test context; synchronization is through explicit peer barriers.
    private func context() -> TransportContext<ContinuousClock> { .init(clock: ContinuousClock()) }

    /// Two reversed replies resolve their exact callers and ERROR retains only numeric code.
    /// - Throws: Unexpected connection or request behavior.
    @Test func correlationAndErrors() async throws {
        let peer = RPCPeer(); let rpc = try client([peer]); try await rpc.connect(context: context())
        #expect(await peer.handshakes == 1)
        let first = Task { try await rpc.request(.getGuilds(), context: context()) }
        let sent1 = await peer.nextSent()
        let second = Task { try await rpc.request(.getVoiceSettings(), context: context()) }
        let sent2 = await peer.nextSent()
        try await peer.reply(to: sent2, data: .string("second"))
        try await peer.reply(to: sent1, data: .string("first"))
        #expect(try await first.value == .string("first")); #expect(try await second.value == .string("second"))
        let rejected = Task { try await rpc.request(.getGuilds(), context: context()) }
        let sent3 = await peer.nextSent()
        try await peer.reply(to: sent3, data: .object(["code": .number(try JSONNumber(rawValue: "4006")), "message": .string("secret")]), event: "ERROR")
        await #expect(throws: RPCFailure.server(code: 4006)) { try await rejected.value }
        #expect(await rpc.resourceCounts().pending == 0)
        await rpc.close(); await rpc.close()
        #expect(await peer.closeCount == 1)
    }

    /// Admission overload and cancellation release only the owned waiter; late replies cannot cross callers.
    /// - Throws: Unexpected valid runtime setup/request behavior.
    @Test func overloadCancellationAndLateReply() async throws {
        let peer = RPCPeer(); let rpc = try client([peer], maximumPending: 1); try await rpc.connect(context: context())
        let first = Task { try await rpc.request(.getGuilds(), context: context()) }
        let old = await peer.nextSent()
        await #expect(throws: RPCFailure.overloaded) { try await rpc.request(.getGuilds(), context: context()) }
        first.cancel(); await #expect(throws: CancellationError.self) { try await first.value }
        #expect(await rpc.resourceCounts().pendingBytes == 0)
        let second = Task { try await rpc.request(.getGuilds(), context: context()) }
        let current = await peer.nextSent()
        try await peer.reply(to: old, data: .string("stale"))
        try await peer.reply(to: current, data: .string("current"))
        #expect(try await second.value == .string("current"))
        await rpc.close()
        let preCanceled = Task { try Task.checkCancellation(); return try await rpc.request(.getGuilds(), context: context()) }
        preCanceled.cancel()
        await #expect(throws: CancellationError.self) { try await preCanceled.value }
    }

    /// Explicit reconnect rejects old pending work and starts independent nonce/auth/subscription ownership.
    /// - Throws: Unexpected reconnect or response error.
    @Test func reconnectAndClose() async throws {
        let firstPeer = RPCPeer(); let secondPeer = RPCPeer(); let rpc = try client([firstPeer, secondPeer])
        await #expect(throws: RPCFailure.notConnected) { try await rpc.request(.getGuilds(), context: context()) }
        try await rpc.connect(context: context())
        await #expect(throws: RPCFailure.alreadyConnected) { try await rpc.connect(context: context()) }
        let old = Task { try await rpc.request(.getGuilds(), context: context()) }
        _ = await firstPeer.nextSent()
        try await rpc.reconnect(context: context())
        await #expect(throws: RPCFailure.closed) { try await old.value }
        #expect(await firstPeer.closeCount == 1)
        let active = Task { try await rpc.request(.getGuilds(), context: context()) }
        let request = await secondPeer.nextSent(); try await secondPeer.reply(to: request)
        #expect(try await active.value == .null)
        let event = Task { try await rpc.nextEvent(context: context()) }
        await rpc.close()
        #expect(try await event.value == nil)
        let counts = await rpc.resourceCounts()
        #expect(counts.pending == 0 && counts.pendingBytes == 0 && counts.events == 0 && counts.eventBytes == 0)
        #expect(await secondPeer.closeCount == 1)
    }

    /// Malformed or wrong-command replies fail the generation and resolve pending continuations.
    /// - Parameter wrongCommand: Whether corruption is a mismatched command or malformed JSON.
    /// - Throws: Unexpected setup error.
    @Test(arguments: [false, true]) func invalidResponses(wrongCommand: Bool) async throws {
        let peer = RPCPeer(); let rpc = try client([peer]); try await rpc.connect(context: context())
        let pending = Task { try await rpc.request(.getGuilds(), context: context()) }
        let sent = await peer.nextSent()
        if wrongCommand { try await peer.reply(to: sent, command: "AUTHENTICATE") }
        else { await peer.pushJSON("{bad-secret") }
        await #expect(throws: RPCFailure.invalidPayload) { try await pending.value }
        await rpc.close()
        #expect(await peer.closeCount == 1)
    }

    /// Pings preserve exact opaque bytes and unknown dispatches retain arbitrary numeric lexemes.
    /// - Throws: Unexpected protocol/setup error.
    @Test func pingAndEvents() async throws {
        let peer = RPCPeer(); let rpc = try client([peer]); try await rpc.connect(context: context())
        await peer.push(.init(opcode: .ping, payload: Data([255, 0, 128])))
        let pong = await peer.nextSent()
        #expect(pong == .init(opcode: .pong, payload: Data([255, 0, 128])))
        await peer.pushJSON("{\"cmd\":\"DISPATCH\",\"evt\":\"FUTURE\",\"nonce\":null,\"data\":{\"n\":1.2300e100}}")
        let event = try #require(try await rpc.nextEvent(context: context()))
        #expect(event.name == "FUTURE")
        #expect(event.data == .object(["n": .number(try JSONNumber(rawValue: "1.2300e100"))]))
        #expect(event.description == event.debugDescription)
        #expect(event.customMirror.children.count == 1)
        await rpc.close()
    }

    /// Invalid/unsupported READY and EOF terminate startup and close the peer exactly once.
    /// - Parameter json: Malformed, unsupported-version or ERROR startup response.
    /// - Throws: Unexpected constructor error.
    @Test(arguments: ["{}", "[]", "{\"cmd\":\"DISPATCH\",\"evt\":\"READY\",\"data\":{\"v\":2}}", "{\"evt\":\"ERROR\",\"data\":{\"code\":4006}}"])
    func startupFailure(json: String) async throws {
        let peer = RPCPeer(startup: [.init(opcode: .frame, payload: Data(json.utf8))]); let rpc = try client([peer])
        await #expect(throws: (any Error).self) { try await rpc.connect(context: context()) }
        #expect(await peer.closeCount == 1)
        #expect(await rpc.resourceCounts().pending == 0)
        await rpc.close()
    }

    /// Event count/byte overflow closes the session and rejects an unrelated pending request.
    /// - Parameter byteOverflow: Selects byte or count exhaustion without dropping a dispatch silently.
    /// - Throws: Unexpected setup or request construction failure.
    @Test(arguments: [false, true]) func eventOverload(byteOverflow: Bool) async throws {
        let peer = RPCPeer()
        let rpc = try RPCClient(applicationID: ApplicationID(rawValue: 1), clock: ContinuousClock(), connector: RPCPeerConnector([peer]), maximumEvents: 1, maximumEventBytes: byteOverflow ? 1 : 1024)
        try await rpc.connect(context: context())
        let pending = Task { try await rpc.request(.getGuilds(), context: context()) }
        _ = await peer.nextSent()
        await peer.pushJSON("{\"cmd\":\"DISPATCH\",\"evt\":\"FUTURE\",\"data\":null}")
        if !byteOverflow { await peer.pushJSON("{\"cmd\":\"DISPATCH\",\"evt\":\"NEXT\",\"data\":null}") }
        await #expect(throws: RPCFailure.overloaded) { try await pending.value }
        await #expect(throws: RPCFailure.overloaded) { try await rpc.nextEvent(context: context()) }
        let counts = await rpc.resourceCounts()
        #expect(counts.pending == 0 && counts.pendingBytes == 0 && counts.events == 0 && counts.eventBytes == 0)
        await rpc.close()
    }

    /// Subscription replies must echo their exact event; ordinary replies cannot impersonate events.
    /// - Parameter subscription: Whether the request requires a named subscription echo.
    /// - Throws: Unexpected setup/fixture errors.
    @Test(arguments: [false, true]) func replyEventCorrelation(subscription: Bool) async throws {
        let peer = RPCPeer(); let rpc = try client([peer]); try await rpc.connect(context: context())
        let request = Task { try await rpc.request(subscription ? .subscribe(.guildCreate) : .getGuilds(), context: context()) }
        let frame = await peer.nextSent()
        try await peer.reply(to: frame, event: "WRONG_EVENT")
        await #expect(throws: RPCFailure.invalidPayload) { try await request.value }
        await rpc.close()
    }

    /// Accepts the documented data.evt acknowledgement and reconnects directly after malformed-session failure.
    /// - Throws: Unexpected valid subscription, reconnect or response failure.
    @Test func documentedSubscriptionAndConnectAfterFailure() async throws {
        let first = RPCPeer(); let second = RPCPeer(); let rpc = try client([first, second])
        try await rpc.connect(context: context())
        for command in [RPCCommand.subscribe, .unsubscribe] {
            let result = Task { try await rpc.request(RPCRequest(command: command, event: .guildCreate), context: context()) }
            let frame = await first.nextSent()
            try await first.reply(to: frame, data: .object(["evt": .string("GUILD_CREATE")]))
            #expect(try await result.value == .object(["evt": .string("GUILD_CREATE")]))
        }
        let failure = Task { try await rpc.request(.getGuilds(), context: context()) }
        _ = await first.nextSent(); await first.pushJSON("{invalid}")
        await #expect(throws: RPCFailure.invalidPayload) { try await failure.value }
        try await rpc.connect(context: context())
        let fresh = Task { try await rpc.request(.getGuilds(), context: context()) }
        let frame = await second.nextSent(); try await second.reply(to: frame)
        #expect(try await fresh.value == .null)
        await rpc.close()
        #expect(await first.closeCount == 1)
        #expect(await second.closeCount == 1)
    }

    /// Handshake cancellation and explicit close both await the owned startup reader's cleanup.
    /// - Parameter cancel: Whether caller cancellation or explicit close terminates startup.
    /// - Throws: Unexpected constructor failure.
    @Test(arguments: [false, true]) func startupCleanup(cancel: Bool) async throws {
        let peer = RPCPeer(startup: []); let rpc = try client([peer])
        let startup = Task { try await rpc.connect(context: context()) }
        await peer.waitForRead()
        if cancel { startup.cancel() } else { await rpc.close() }
        await #expect(throws: (any Error).self) { try await startup.value }
        #expect(await peer.closeCount == 1)
        await rpc.close()
    }

    /// Local request byte budgets and malformed budgets reject work before any command write.
    /// - Throws: Unexpected valid-budget setup failure.
    @Test func budgetValidation() async throws {
        let clock = ContinuousClock(); let connector = RPCPeerConnector([])
        #expect(throws: RPCFailure.invalidConfiguration) { try RPCClient(applicationID: ApplicationID(rawValue: 0), clock: clock, connector: connector) }
        for cap in [0, -1, 65_537] {
            #expect(throws: RPCFailure.invalidConfiguration) { try RPCClient(applicationID: ApplicationID(rawValue: 1), clock: clock, connector: connector, maximumPendingRequests: cap) }
            #expect(throws: RPCFailure.invalidConfiguration) { try RPCClient(applicationID: ApplicationID(rawValue: 1), clock: clock, connector: connector, maximumEvents: cap) }
        }
        #expect(throws: RPCFailure.invalidConfiguration) { try RPCClient(applicationID: ApplicationID(rawValue: 1), clock: clock, connector: connector, maximumPendingBytes: 0) }
        #expect(throws: RPCFailure.invalidConfiguration) { try RPCClient(applicationID: ApplicationID(rawValue: 1), clock: clock, connector: connector, maximumEventBytes: 0) }
        let peer = RPCPeer()
        let rpc = try RPCClient(applicationID: ApplicationID(rawValue: 1), clock: clock, connector: RPCPeerConnector([peer]), maximumPendingBytes: 1)
        try await rpc.connect(context: context())
        await #expect(throws: RPCFailure.overloaded) { try await rpc.request(.getGuilds(), context: context()) }
        #expect(await rpc.resourceCounts().pending == 0)
        await rpc.close()
    }

    /// Virtual deadlines cancel sent requests while preserving independent session ownership.
    /// - Throws: Unexpected virtual-clock setup or runtime error.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func deadlineAndEventCancellation() async throws {
        let clock = ManualClock()
        let peer = RPCPeer()
        let rpc = try RPCClient(applicationID: ApplicationID(rawValue: 1), clock: clock, connector: RPCPeerConnector([peer]))
        let context = TransportContext(clock: clock)
        try await rpc.connect(context: context)
        let request = Task { try await rpc.request(.getGuilds(), context: .init(clock: clock, deadline: clock.now.advanced(by: .seconds(1)))) }
        _ = await peer.nextSent()
        try clock.advance(by: .seconds(1))
        await #expect(throws: TransportFailure.deadlineExceeded) { try await request.value }
        #expect(await rpc.resourceCounts().pending == 0)
        let event = Task { try await rpc.nextEvent(context: context) }
        event.cancel(); await #expect(throws: CancellationError.self) { try await event.value }
        await peer.pushJSON("{\"cmd\":\"DISPATCH\",\"evt\":\"NEXT\",\"data\":null}")
        #expect(try await rpc.nextEvent(context: context)?.name == "NEXT")
        await rpc.close()
    }
}
