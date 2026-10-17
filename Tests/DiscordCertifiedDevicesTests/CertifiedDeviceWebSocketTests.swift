import DiscordCertifiedDevices
import DiscordCore
import DiscordRPC
import DiscordTestSupport
import DiscordTransport
import Foundation
import Testing

/// Complete deterministic WebSocket peers verify local endpoint policy and RPC publication.
@Suite("Certified Devices WebSocket publication")
struct CertifiedDeviceWebSocketTests {
    /// Preserves the Certified-specific upper port and registered Origin without IPC headers.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func connectorEndpointAndFrameOwnership() async throws {
        let socket = CertifiedSocketPeer(mode: .success)
        let factory = CertifiedSocketFactory(socket: socket)
        let connector = try CertifiedDeviceWebSocketConnector(transport: factory, port: 6473,
            origin: "https://vendor.example.invalid")
        #expect(await factory.requests.isEmpty)
        let context = TransportContext(clock: ManualClock())
        let wire = try await connector.connect(applicationID: .init(rawValue: UInt64.max), context: context)
        let request = try #require(await factory.requests.first)
        #expect(request.method == "GET" && request.body == nil)
        #expect(request.url.absoluteString == "ws://127.0.0.1:6473/?v=1&client_id=18446744073709551615&encoding=json")
        #expect(request.headers.count == 1)
        #expect(request.headers.first?.name == "Origin")
        #expect(request.headers.first?.value == "https://vendor.example.invalid")
        try await wire.handshake(applicationID: .init(rawValue: 1), context: context)
        #expect(await socket.sent.isEmpty)
        let ready = try #require(await wire.receive(context: context))
        #expect(ready.opcode == .frame)
        let command = try JSONValue.object(["cmd": .string("SET_CERTIFIED_DEVICES"),
            "nonce": .string("n"), "args": .object(["devices": .array([])])]).serialized()
        try await wire.send(RPCFrame(opcode: .frame, payload: command), context: context)
        #expect(await socket.sent == [.text(String(decoding: command, as: UTF8.self))])
        let reply = try #require(await wire.receive(context: context))
        #expect(try JSONValue.parse(reply.payload) == .object(["cmd": .string("SET_CERTIFIED_DEVICES"),
            "nonce": .string("n"), "data": .null, "evt": .null]))
        await wire.close()
        await wire.close()
        #expect(await socket.closeCount == 1)
        #expect(try await wire.receive(context: context) == nil)
    }

    /// Exercises actual RPCClient correlation with full arrays, clearing and server access denial.
    /// - Parameter mode: The peer sends a null success, non-null invalid acknowledgement, or RPC error.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [CertifiedSocketMode.success, .invalidAcknowledgement, .accessDenied])
    func rpcPublisher(_ mode: CertifiedSocketMode) async throws {
        let clock = ManualClock()
        let context = TransportContext(clock: clock)
        let socket = CertifiedSocketPeer(mode: mode)
        let connector = try CertifiedDeviceWebSocketConnector(transport: CertifiedSocketFactory(socket: socket),
            port: 6463, origin: "https://vendor.example.invalid")
        let client = try RPCClient(applicationID: .init(rawValue: 1), clock: clock, connector: connector)
        let publisher = try CertifiedDeviceRPCPublisher(client: client)
        #expect(await socket.sent.isEmpty)
        try await client.connect(context: context)
        let first = try certifiedDevice("Preferred")
        let second = try certifiedDevice("Secondary")
        if mode == .success {
            try await publisher.publish([first, second], context: context)
            try await publisher.publish([second], context: context)
            try await publisher.publish([], context: context)
            let values = try await socket.sent.map { message -> JSONValue in
                guard case .text(let text) = message else { throw CertifiedDeviceFailure.invalidResponse }
                return try JSONValue.parse(text)
            }
            #expect(values.count == 3)
            for (value, devices) in zip(values, [[first, second], [second], []]) {
                guard case .object(let fields) = value else { Issue.record("Expected command object"); continue }
                #expect(fields["cmd"] == .string("SET_CERTIFIED_DEVICES"))
                #expect(fields["args"] == .object(["devices": .array(devices.map(\.jsonValue))]))
                guard case .string(let nonce) = fields["nonce"] else { Issue.record("Expected nonce"); continue }
                #expect(!nonce.isEmpty)
            }
        } else if mode == .accessDenied {
            await #expect(throws: RPCFailure.server(code: 4006)) {
                try await publisher.publish([first], context: context)
            }
        } else {
            await #expect(throws: CertifiedDeviceFailure.invalidResponse) {
                try await publisher.publish([first], context: context)
            }
        }
        await client.close()
        #expect(await socket.closeCount == 1)
        #expect(await socket.pendingReceives == 0)
    }

    /// Rejects malformed origins, ports and bounds without invoking a socket factory.
    @Test func connectorValidation() throws {
        let factory = CertifiedSocketFactory(socket: CertifiedSocketPeer(mode: .success))
        for port in [6462, 6474, Int.max] {
            #expect(throws: CertifiedDeviceFailure.invalidPort) {
                try CertifiedDeviceWebSocketConnector(transport: factory, port: port, origin: "https://example.invalid")
            }
        }
        for origin in ["", "file:///tmp/x", "https://example.invalid/", "https://user@example.invalid",
                       "https://example.invalid?q=1", "https://example.invalid#x", "https://example.invalid bad",
                       "https://" + String(repeating: "a", count: 2_049)] {
            #expect(throws: CertifiedDeviceFailure.invalidURL) {
                try CertifiedDeviceWebSocketConnector(transport: factory, port: 6463, origin: origin)
            }
        }
        for value in [Int.min, 0, 1_048_577, Int.max] {
            #expect(throws: CertifiedDeviceFailure.invalidLimits) {
                try CertifiedDeviceWebSocketConnector(transport: factory, port: 6463,
                    origin: "https://example.invalid", maximumPayloadBytes: value)
            }
        }
        _ = try CertifiedDeviceWebSocketConnector(transport: factory, port: 6463,
            origin: "http://localhost:8080", maximumPayloadBytes: 1_048_576)
    }

    /// Rejects invalid identity and expired/cancelled upgrades before a factory executes.
    /// Late deadline completion closes transferred sockets and hides opaque transport text.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func connectorCancellationAndLateCleanup() async throws {
        let clock = ManualClock()
        let socket = CertifiedSocketPeer(mode: .success)
        let factory = CertifiedSocketFactory(socket: socket)
        let connector = try CertifiedDeviceWebSocketConnector(transport: factory, port: 6463,
            origin: "https://example.invalid")
        await #expect(throws: CertifiedDeviceFailure.invalidClientID) {
            _ = try await connector.connect(applicationID: .init(rawValue: 0), context: TransportContext(clock: clock))
        }
        await #expect(throws: TransportFailure.deadlineExceeded) {
            _ = try await connector.connect(applicationID: .init(rawValue: 1),
                context: TransportContext(clock: clock, deadline: clock.now))
        }
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await connector.connect(applicationID: .init(rawValue: 1), context: TransportContext(clock: clock))
        }
        await #expect(throws: CancellationError.self) { _ = try await cancelled.value }
        #expect(await factory.requests.isEmpty)

        let late = try CertifiedDeviceWebSocketConnector(transport: CertifiedLateSocketFactory(socket: socket, clock: clock),
            port: 6463, origin: "https://example.invalid")
        await #expect(throws: TransportFailure.deadlineExceeded) {
            _ = try await late.connect(applicationID: .init(rawValue: 1),
                context: TransportContext(clock: clock, deadline: clock.now.advanced(by: .seconds(1))))
        }
        #expect(await socket.closeCount == 1)
        let failing = try CertifiedDeviceWebSocketConnector(transport: CertifiedFailingSocketFactory(),
            port: 6463, origin: "https://example.invalid")
        await #expect(throws: RPCFailure.connectionLost) {
            _ = try await failing.connect(applicationID: .init(rawValue: 1), context: TransportContext(clock: clock))
        }
    }

    /// Caps outgoing/incoming messages and rejects IPC controls, invalid UTF-8 and binary input.
    /// - Parameter variant: Particular unsupported or oversized complete-message fixture.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: ["binary", "receiveSize", "sendSize", "opcode", "utf8"])
    func frameValidation(_ variant: String) async throws {
        let incoming: WebSocketMessage = variant == "binary" ? .binary(Data([1])) : .text(String(repeating: "x", count: 17))
        let socket = try ScriptedWebSocketConnection(incoming: [incoming])
        let connector = try CertifiedDeviceWebSocketConnector(transport: ScriptedWebSocketTransport(connection: socket),
            port: 6463, origin: "https://example.invalid", maximumPayloadBytes: 16)
        let context = TransportContext(clock: ManualClock())
        let wire = try await connector.connect(applicationID: .init(rawValue: 1), context: context)
        switch variant {
        case "binary":
            await #expect(throws: RPCFailure.invalidPayload) { _ = try await wire.receive(context: context) }
        case "receiveSize":
            await #expect(throws: RPCFailure.frameTooLarge) { _ = try await wire.receive(context: context) }
        case "sendSize":
            await #expect(throws: RPCFailure.frameTooLarge) {
                try await wire.send(.init(opcode: .frame, payload: Data(repeating: 1, count: 17)), context: context)
            }
        case "opcode":
            await #expect(throws: RPCFailure.invalidPayload) {
                try await wire.send(.init(opcode: .ping, payload: Data()), context: context)
            }
        default:
            await #expect(throws: RPCFailure.invalidPayload) {
                try await wire.send(.init(opcode: .frame, payload: Data([0xFF])), context: context)
            }
        }
        #expect(await socket.sent.isEmpty)
        await wire.close()
    }

    /// Validates RPC wrapper budgets and arguments before dispatching onto an unconnected client.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func rpcPublisherValidation() async throws {
        let clock = ManualClock()
        let connector = try CertifiedDeviceWebSocketConnector(transport: CertifiedSocketFactory(socket: CertifiedSocketPeer(mode: .success)),
            port: 6463, origin: "https://example.invalid")
        let client = try RPCClient(applicationID: .init(rawValue: 1), clock: clock, connector: connector)
        for value in [0, 1_025, Int.max] {
            #expect(throws: CertifiedDeviceFailure.invalidLimits) {
                try CertifiedDeviceRPCPublisher(client: client, maximumDevices: value)
            }
        }
        for value in [0, 1_048_577, Int.max] {
            #expect(throws: CertifiedDeviceFailure.invalidLimits) {
                try CertifiedDeviceRPCPublisher(client: client, maximumArgumentBytes: value)
            }
        }
        let publisher = try CertifiedDeviceRPCPublisher(client: client, maximumDevices: 1)
        let device = try certifiedDevice()
        await #expect(throws: CertifiedDeviceFailure.tooManyDevices) {
            try await publisher.publish([device, device], context: TransportContext(clock: clock))
        }
        let duplicate = try CertifiedDeviceRPCPublisher(client: client)
        await #expect(throws: CertifiedDeviceFailure.duplicateDevice) {
            try await duplicate.publish([device, device], context: TransportContext(clock: clock))
        }
        let tiny = try CertifiedDeviceRPCPublisher(client: client, maximumArgumentBytes: 1)
        await #expect(throws: JSONValueError.maximumBytesExceeded) {
            try await tiny.publish([], context: TransportContext(clock: clock))
        }
        await #expect(throws: RPCFailure.notConnected) {
            try await publisher.publish([], context: TransportContext(clock: clock))
        }
        await #expect(throws: TransportFailure.deadlineExceeded) {
            try await publisher.publish([], context: TransportContext(clock: clock, deadline: clock.now))
        }
        await client.close()
    }
}

/// Finite peer acknowledgement modes used by integration fixtures.
enum CertifiedSocketMode: Sendable, CaseIterable { case success, invalidAcknowledgement, accessDenied }

/// Recording test-only upgrade factory; it never opens a network connection.
actor CertifiedSocketFactory: WebSocketTransport {
    let socket: any WebSocketConnection
    var requests: [HTTPRequest] = []

    /// Borrows the deterministic peer that each test exclusively owns.
    /// - Parameter socket: Fixture socket returned from one explicit connect.
    init(socket: any WebSocketConnection) { self.socket = socket }

    /// Records the exact upgrade request under normal clock/cancellation validation.
    /// - Parameters:
    ///   - request: Fixed-loopback upgrade metadata to assert in the test.
    ///   - context: Injected operation deadline and cancellation.
    /// - Returns: The fixture's exclusively owned socket.
    /// - Throws: Cancellation/deadline or finite test-capacity exhaustion.
    func connectWebSocket<C: Clock>(_ request: HTTPRequest, context: TransportContext<C>) async throws
        -> any WebSocketConnection where C.Duration == Duration {
        try context.check()
        guard requests.count < 2 else { throw TestSupportFailure.capacityExceeded }
        requests.append(request)
        return socket
    }
}

/// Deliberately returns an expired socket to exercise successful-upgrade ownership cleanup.
@available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
struct CertifiedLateSocketFactory: WebSocketTransport {
    let socket: any WebSocketConnection
    let clock: ManualClock

    /// Advances fixture time past the caller's deadline before transferring the socket.
    /// - Parameters:
    ///   - request: Ignored fixed-loopback fixture upgrade request.
    ///   - context: Checked before time is deliberately advanced.
    /// - Returns: Late socket; production connector must close it before throwing.
    /// - Throws: Cancellation, initial expiration or clock advance validation failures.
    func connectWebSocket<C: Clock>(_ request: HTTPRequest, context: TransportContext<C>) async throws
        -> any WebSocketConnection where C.Duration == Duration {
        try context.check()
        try clock.advance(by: .seconds(2))
        return socket
    }
}

/// Opaque native failure fixture proves error diagnostics discard upstream text.
struct CertifiedFailingSocketFactory: WebSocketTransport {
    /// Fails before ownership transfer with deliberately sensitive diagnostic text.
    /// - Parameters:
    ///   - request: Ignored fixed-loopback fixture request.
    ///   - context: Ignored because this factory models an immediate native error.
    /// - Returns: Never returns a connection.
    /// - Throws: A scripted opaque transport error that production must sanitize.
    func connectWebSocket<C: Clock>(_ request: HTTPRequest, context: TransportContext<C>) async throws
        -> any WebSocketConnection where C.Duration == Duration {
        throw TestSupportFailure.scripted("sentinel-secret")
    }
}

/// Bounded echoing peer with READY, nonce-correlated replies and one cancellable reader.
actor CertifiedSocketPeer: WebSocketConnection {
    let mode: CertifiedSocketMode
    var sent: [WebSocketMessage] = []
    private var initialReady = true
    private var incoming: [WebSocketMessage] = []
    private var waiter: (UUID, CheckedContinuation<WebSocketMessage?, any Error>)?
    private var closed = false
    var closeCount = 0

    /// Selects a deterministic response mode without creating tasks.
    /// - Parameter mode: Success, invalid acknowledgement or access-error behavior.
    init(mode: CertifiedSocketMode) { self.mode = mode }

    /// Records one bounded text command and synthesizes its correlated reply.
    /// - Parameters:
    ///   - message: Outgoing text JSON command generated by the production runtime.
    ///   - context: Injected operation clock/deadline/cancellation.
    /// - Throws: Fixture capacity, malformed command, cancellation, deadline or closed-peer errors.
    func send<C: Clock>(_ message: WebSocketMessage, context: TransportContext<C>) async throws where C.Duration == Duration {
        try context.check()
        guard !closed else { throw TransportFailure.closed }
        guard sent.count < 16, incoming.count < 16 else { throw TestSupportFailure.capacityExceeded }
        sent.append(message)
        guard case .text(let text) = message, case .object(let object) = try JSONValue.parse(text),
              let nonce = object["nonce"], let command = object["cmd"] else { throw CertifiedDeviceFailure.invalidResponse }
        let data: JSONValue
        let event: JSONValue
        switch mode {
        case .success: data = .null; event = .null
        case .invalidAcknowledgement: data = .object([:]); event = .null
        case .accessDenied:
            data = .object(["code": .number(try JSONNumber(rawValue: "4006")), "message": .string("sentinel-secret")])
            event = .string("ERROR")
        }
        let bytes = try JSONValue.object(["cmd": command, "nonce": nonce, "data": data, "evt": event]).serialized()
        let reply = WebSocketMessage.text(String(decoding: bytes, as: UTF8.self))
        if let (_, continuation) = waiter {
            waiter = nil
            continuation.resume(returning: reply)
        } else { incoming.append(reply) }
    }

    /// Supplies initial READY, queued replies or a single cancellable receive suspension.
    /// - Parameter context: Injected operation clock/deadline/cancellation.
    /// - Returns: Next fixture message, or nil after closure.
    /// - Throws: Cancellation, deadline, concurrent reader or serialization failures.
    func receive<C: Clock>(context: TransportContext<C>) async throws -> WebSocketMessage? where C.Duration == Duration {
        try context.check()
        guard !closed else { return nil }
        if initialReady {
            initialReady = false
            let bytes = try JSONValue.object(["cmd": .string("DISPATCH"), "evt": .string("READY"),
                "data": .object(["v": .number(try JSONNumber(rawValue: "1"))])]).serialized()
            return .text(String(decoding: bytes, as: UTF8.self))
        }
        if !incoming.isEmpty { return incoming.removeFirst() }
        guard waiter == nil else { throw TransportFailure.concurrentRead }
        let id = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                waiter = (id, continuation)
                if Task.isCancelled { cancelReceive(id) }
            }
        } onCancel: {
            Task { await self.cancelReceive(id) }
        }
    }

    /// Reports the finite receive continuation count for cleanup assertions.
    var pendingReceives: Int { waiter == nil ? 0 : 1 }

    /// Cancels only the matching suspended read, avoiding stale cancellation races.
    /// - Parameter id: Identity captured before the reader suspended.
    private func cancelReceive(_ id: UUID) {
        guard let (current, continuation) = waiter, current == id else { return }
        waiter = nil
        continuation.resume(throwing: CancellationError())
    }

    /// Closes once, drops queued messages and completes a pending read with EOF.
    func close() async {
        guard !closed else { return }
        closed = true
        closeCount += 1
        incoming.removeAll()
        let pending = waiter
        waiter = nil
        pending?.1.resume(returning: nil)
    }
}
