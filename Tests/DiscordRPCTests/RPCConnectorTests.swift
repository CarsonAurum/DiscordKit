// File: Tests/DiscordRPCTests/RPCConnectorTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import DiscordRPC
import DiscordTestSupport
import DiscordTransport
import Foundation
import Testing

/// Deterministic native IPC opening and deprecated fixed-loopback WebSocket adaptation.
@Suite("RPC connectors")
struct RPCConnectorTests {
    /// Uses only the generic RPC ten-port range and sends registered Origin/v1/JSON metadata.
    /// Handshake starts no extra WebSocket message; the connection exclusively owns socket closure.
    /// - Parameter port: Either inclusive boundary of the documented generic RPC range.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [6463, 6472])
    func webSocketEndpointAndText(_ port: Int) async throws {
        let counter = ResourceCounter()
        let lease = await counter.acquire()
        let socket = try ScriptedWebSocketConnection(incoming: [.text("{}")], lease: lease)
        let factory = RPCConnectorSocketFactory(socket: socket)
        let connector = try RPCWebSocketConnector(transport: factory, port: port, origin: "https://vendor.example.invalid")
        #expect(await factory.requests.isEmpty)
        let context = TransportContext(clock: ManualClock())
        let connection = try await connector.connect(applicationID: .init(rawValue: UInt64.max), context: context)
        let request = try #require(await factory.requests.first)
        #expect(request.method == "GET" && request.body == nil)
        #expect(request.url.absoluteString == "ws://127.0.0.1:\(port)/?v=1&client_id=18446744073709551615&encoding=json")
        #expect(request.headers.count == 1)
        #expect(request.headers.first?.name == "Origin")
        #expect(request.headers.first?.value == "https://vendor.example.invalid")
        try await connection.handshake(applicationID: .init(rawValue: 1), context: context)
        #expect(await socket.sent.isEmpty)
        try await connection.send(.init(opcode: .frame, payload: Data("{}".utf8)), context: context)
        #expect(await socket.sent == [.text("{}")])
        #expect(try await connection.receive(context: context) == .init(opcode: .frame, payload: Data("{}".utf8)))
        #expect(try await connection.receive(context: context) == nil)
        await connection.close()
        await connection.close()
        #expect(await counter.snapshot().released == 1)
        #expect(await counter.snapshot().live == 0)
    }

    /// Rejects arbitrary ports, invalid origins and unsafe frame limits before I/O.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func webSocketConfiguration() throws {
        let socket = try ScriptedWebSocketConnection(incoming: [])
        let transport = ScriptedWebSocketTransport(connection: socket)
        for port in [Int.min, 6462, 6473, 65536, Int.max] {
            #expect(throws: RPCFailure.invalidConfiguration) {
                try RPCWebSocketConnector(transport: transport, port: port, origin: "https://example.invalid")
            }
        }
        for origin in ["", "file:///tmp/device", "https://example.invalid/", "https://example.invalid/path",
                       "https://name:secret@example.invalid", "https://example.invalid?q=1", "https://example.invalid#fragment",
                       "https://example.invalid\n", "https://example.invalid bad"] {
            #expect(throws: RPCFailure.invalidConfiguration) {
                try RPCWebSocketConnector(transport: transport, port: 6463, origin: origin)
            }
        }
        for limit in [Int.min, 0, Int(UInt32.max), Int.max] {
            #expect(throws: RPCFailure.invalidConfiguration) {
                try RPCWebSocketConnector(transport: transport, port: 6463, origin: "https://example.invalid", maximumPayloadBytes: limit)
            }
        }
        _ = try RPCWebSocketConnector(transport: transport, port: 6463, origin: "http://localhost:8080", maximumPayloadBytes: 1)
    }

    /// Rejects binary/oversize messages, unsupported IPC controls and malformed UTF-8.
    /// Exact-limit text messages remain valid in both directions.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func webSocketMessageBounds() async throws {
        let socket = try ScriptedWebSocketConnection(incoming: [.text("1234"), .binary(Data([1])), .text("12345")])
        let connector = try RPCWebSocketConnector(transport: ScriptedWebSocketTransport(connection: socket), port: 6463,
            origin: "https://example.invalid", maximumPayloadBytes: 4)
        let context = TransportContext(clock: ManualClock())
        let connection = try await connector.connect(applicationID: .init(rawValue: 1), context: context)
        try await connection.send(.init(opcode: .frame, payload: Data("1234".utf8)), context: context)
        #expect(await socket.sent == [.text("1234")])
        #expect(try await connection.receive(context: context)?.payload == Data("1234".utf8))
        await #expect(throws: RPCFailure.invalidPayload) { _ = try await connection.receive(context: context) }
        await #expect(throws: RPCFailure.frameTooLarge) { _ = try await connection.receive(context: context) }
        for frame in [RPCFrame(opcode: .frame, payload: Data("12345".utf8)),
                      RPCFrame(opcode: .ping, payload: Data()), RPCFrame(opcode: .frame, payload: Data([0xff]))] {
            await #expect(throws: RPCFailure.invalidPayload) { try await connection.send(frame, context: context) }
        }
        #expect(await socket.sent.count == 1)
        await connection.close()
    }

    /// Rejects cancellation/deadlines before upgrade and handshake and closes late-upgrade ownership.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func webSocketCancellationAndLateCleanup() async throws {
        let clock = ManualClock()
        let counter = ResourceCounter()
        let lease = await counter.acquire()
        let socket = try ScriptedWebSocketConnection(incoming: [], lease: lease)
        let factory = RPCConnectorSocketFactory(socket: socket)
        let connector = try RPCWebSocketConnector(transport: factory, port: 6463, origin: "https://example.invalid")
        let expired = TransportContext(clock: clock, deadline: clock.now)
        await #expect(throws: RPCFailure.invalidConfiguration) {
            _ = try await connector.connect(applicationID: .init(rawValue: 0), context: TransportContext(clock: clock))
        }
        await #expect(throws: TransportFailure.deadlineExceeded) {
            _ = try await connector.connect(applicationID: .init(rawValue: 1), context: expired)
        }
        let before = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await connector.connect(applicationID: .init(rawValue: 1), context: TransportContext(clock: clock))
        }
        await #expect(throws: CancellationError.self) { _ = try await before.value }
        #expect(await factory.requests.isEmpty)
        let wire = try await connector.connect(applicationID: .init(rawValue: 1), context: TransportContext(clock: clock))
        await #expect(throws: TransportFailure.deadlineExceeded) {
            try await wire.handshake(applicationID: .init(rawValue: 1), context: expired)
        }
        let handshake = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await wire.handshake(applicationID: .init(rawValue: 1), context: TransportContext(clock: clock))
        }
        await #expect(throws: CancellationError.self) { try await handshake.value }
        await wire.close()
        #expect(await counter.snapshot().released == 1)

        let lateCounter = ResourceCounter()
        let lateSocket = try ScriptedWebSocketConnection(incoming: [], lease: await lateCounter.acquire())
        let lateFactory = RPCConnectorSocketFactory(socket: lateSocket, lateClock: clock)
        let late = try RPCWebSocketConnector(transport: lateFactory, port: 6463, origin: "https://example.invalid")
        await #expect(throws: TransportFailure.deadlineExceeded) {
            _ = try await late.connect(applicationID: .init(rawValue: 1),
                context: TransportContext(clock: clock, deadline: clock.now.advanced(by: .seconds(1))))
        }
        #expect(await lateCounter.snapshot().released == 1)
        #expect(await lateCounter.snapshot().live == 0)
    }

    /// Opens candidates sequentially, stops at first success and transfers exclusive cleanup ownership.
    /// Explicit subsequent connects retry fresh candidates rather than retaining a stale winner.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func ipcSequentialOpeningAndFreshAttempts() async throws {
        let counter = ResourceCounter()
        let first = try RPCConnectorOwnedIPC(lease: await counter.acquire())
        let second = try RPCConnectorOwnedIPC(lease: await counter.acquire())
        let opener = RPCConnectorScriptedOpener(steps: [
            { _ in throw TestSupportFailure.scripted("unavailable") }, { _ in first }, { _ in second },
        ])
        let connector = try RPCIPCConnector(platform: .unix, environment: ["XDG_RUNTIME_DIR": "/fixture/runtime"],
            indices: 0..<3, opener: opener)
        #expect(await opener.paths.isEmpty)
        let context = TransportContext(clock: ManualClock())
        let connection = try await connector.connect(applicationID: .init(rawValue: 1), context: context)
        #expect(await opener.paths == ["/fixture/runtime/discord-ipc-0", "/fixture/runtime/discord-ipc-1"])
        #expect(await counter.snapshot().released == 0)
        try await connection.handshake(applicationID: .init(rawValue: 1), context: context)
        var decoder = try RPCFrameDecoder()
        let frames = try decoder.append(await first.written())
        #expect(frames.count == 1 && frames.first?.opcode == .handshake)
        #expect(try JSONValue.parse(#require(frames.first).payload) == .object([
            "v": .number(try JSONNumber(rawValue: "1")), "client_id": .string("1")]))
        await connection.close()
        let fresh = try await connector.connect(applicationID: .init(rawValue: 1), context: context)
        #expect(await opener.paths == ["/fixture/runtime/discord-ipc-0", "/fixture/runtime/discord-ipc-1", "/fixture/runtime/discord-ipc-0"])
        await fresh.close()
        #expect(await counter.snapshot().released == 2)
        #expect(await counter.snapshot().live == 0)
    }

    /// Maps all candidate failures to unavailable without exposing native error messages.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func ipcAllUnavailable() async throws {
        let opener = RPCConnectorScriptedOpener(steps: (0..<3).map { _ in
            { _ in throw TestSupportFailure.scripted("sentinel-native-path-secret") }
        })
        let connector = try RPCIPCConnector(platform: .unix, environment: [:], indices: 0..<3, opener: opener)
        await #expect(throws: RPCFailure.unavailable) {
            _ = try await connector.connect(applicationID: .init(rawValue: 1), context: TransportContext(clock: ManualClock()))
        }
        #expect(await opener.paths == ["/tmp/discord-ipc-0", "/tmp/discord-ipc-1", "/tmp/discord-ipc-2"])
    }

    /// Stops discovery immediately on cancellation or deadline, including late acquired-stream cleanup.
    /// - Parameter variant: Pre-entry cancellation/deadline, opener cancellation/deadline, or late success.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: ["preCancel", "preDeadline", "cancel", "deadline", "late"])
    func ipcCancellationAndLateCleanup(_ variant: String) async throws {
        let clock = ManualClock()
        let counter = ResourceCounter()
        let stream = try RPCConnectorOwnedIPC(lease: await counter.acquire())
        let opener = RPCConnectorScriptedOpener(steps: [{ _ in
            if variant == "cancel" { throw CancellationError() }
            try clock.advance(by: .seconds(2))
            if variant == "late" { return stream }
            throw TestSupportFailure.scripted("expired")
        }])
        let connector = try RPCIPCConnector(platform: .unix, environment: [:], indices: 0..<3, opener: opener)
        let context = TransportContext(clock: clock,
            deadline: clock.now.advanced(by: variant == "preDeadline" ? .zero : .seconds(1)))
        if variant == "preCancel" {
            let task = Task {
                withUnsafeCurrentTask { $0?.cancel() }
                return try await connector.connect(applicationID: .init(rawValue: 1), context: context)
            }
            await #expect(throws: CancellationError.self) { _ = try await task.value }
        } else if variant == "cancel" {
            await #expect(throws: CancellationError.self) {
                _ = try await connector.connect(applicationID: .init(rawValue: 1), context: context)
            }
        } else {
            await #expect(throws: TransportFailure.deadlineExceeded) {
                _ = try await connector.connect(applicationID: .init(rawValue: 1), context: context)
            }
        }
        #expect(await opener.paths.count == (variant.hasPrefix("pre") ? 0 : 1))
        #expect(await counter.snapshot().released == (variant == "late" ? 1 : 0))
        await stream.close()
        #expect(await counter.snapshot().live == 0)
    }
}

/// Captures exact upgrade metadata and optionally models a late ownership transfer.
@available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
private actor RPCConnectorSocketFactory: WebSocketTransport {
    let socket: any WebSocketConnection
    let lateClock: ManualClock?
    var requests: [HTTPRequest] = []

    /// Stores a finite test peer without opening a desktop socket.
    /// - Parameters:
    ///   - socket: Exclusively owned fixture socket returned by a valid upgrade.
    ///   - lateClock: Optional fixture clock advanced after pre-admission validation.
    init(socket: any WebSocketConnection, lateClock: ManualClock? = nil) {
        self.socket = socket; self.lateClock = lateClock
    }

    /// Records at most four upgrades and optionally returns a deliberately expired socket.
    /// - Parameters:
    ///   - request: Exact request supplied by production endpoint construction.
    ///   - context: Cooperative cancellation/deadline checked before recording.
    /// - Returns: Fixture socket; a deliberately late transfer must be cleaned up by the connector.
    /// - Throws: Cancellation, deadline, capacity or clock-advance errors.
    func connectWebSocket<C: Clock>(_ request: HTTPRequest, context: TransportContext<C>) async throws
        -> any WebSocketConnection where C.Duration == Duration {
        try context.check()
        guard requests.count < 4 else { throw TestSupportFailure.capacityExceeded }
        requests.append(request)
        try lateClock?.advance(by: .seconds(2))
        return socket
    }
}

/// Finite ordered opener script; it never probes a real path or native socket.
private actor RPCConnectorScriptedOpener: RPCIPCOpening {
    typealias Step = @Sendable (String) async throws -> any IPCTransport
    let steps: [Step]
    var paths: [String] = []

    /// Stores a test-owned finite sequence of opening decisions.
    /// - Parameter steps: One operation per attempted candidate, consumed in order.
    init(steps: [Step]) { self.steps = steps }

    /// Records one attempted path before executing its opening decision.
    /// - Parameters:
    ///   - path: Deterministically constructed candidate supplied by the connector.
    ///   - context: Clock/cancellation/deadline validated before consuming a fixture step.
    /// - Returns: An owned test stream when the selected step succeeds.
    /// - Throws: Cancellation, deadline, script exhaustion or the scripted opening error.
    func open<C: Clock>(path: String, context: TransportContext<C>) async throws -> any IPCTransport where C.Duration == Duration {
        try context.check()
        guard paths.count < steps.count else { throw TransportFailure.scriptExhausted }
        let step = steps[paths.count]
        paths.append(path)
        return try await step(path)
    }
}

/// IPC stream fixture with exactly-once resource accounting and bounded scripted output.
private struct RPCConnectorOwnedIPC: IPCTransport {
    let stream: ScriptedIPCTransport
    let lease: ResourceLease

    /// Creates a finite empty-input stream and retains its test resource lease.
    /// - Parameter lease: Lease released by close; repeated closure remains idempotent.
    /// - Throws: Fixture output-bound validation errors.
    init(lease: ResourceLease) throws {
        stream = try ScriptedIPCTransport(incoming: Data())
        self.lease = lease
    }

    /// Writes bounded fixture bytes while preserving cancellation and ordering.
    /// - Parameters:
    ///   - bytes: IPC handshake or frame bytes.
    ///   - context: Per-write injected clock/cancellation/deadline.
    /// - Throws: Fixture capacity, cancellation, deadline or closed-stream errors.
    func write<C: Clock>(_ bytes: Data, context: TransportContext<C>) async throws where C.Duration == Duration {
        try await stream.write(bytes, context: context)
    }

    /// Delegates a bounded empty-input read to the fixture stream.
    /// - Parameters:
    ///   - maximumBytes: Positive maximum returned bytes.
    ///   - context: Per-read clock/deadline/cancellation.
    /// - Returns: Nil for EOF, since this fixture has no incoming data.
    /// - Throws: Invalid limit, cancellation or deadline.
    func read<C: Clock>(maximumBytes: Int, context: TransportContext<C>) async throws -> Data? where C.Duration == Duration {
        try await stream.read(maximumBytes: maximumBytes, context: context)
    }

    /// Returns raw written fixture bytes for explicit handshake assertions.
    /// - Returns: Finite stream output; tests alone inspect these wire values.
    func written() async -> Data { await stream.written }

    /// Closes the fixture stream and releases its exactly-once resource lease.
    func close() async { await stream.close(); await lease.release() }
}
