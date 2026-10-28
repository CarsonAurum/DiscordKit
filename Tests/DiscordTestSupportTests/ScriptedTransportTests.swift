// File: Tests/DiscordTestSupportTests/ScriptedTransportTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordTestSupport
import DiscordTransport
import Foundation
import Testing

/// Scripts exercise the portable contracts without credentials, DNS or sockets.
@Suite("Scripted transports")
struct ScriptedTransportTests {
    /// Verifies request cleanup and response-body ownership transfer on successful execution.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func httpSuccessAndExhaustion() async throws {
        let counter = ResourceCounter()
        let requestBody = try await trackedBody(counter)
        let responseBody = try await trackedBody(counter)
        let transport = try ScriptedHTTPTransport(steps: [{ request in
            #expect(request.method == "GET")
            #expect(request.headers == [HTTPHeader(name: "X", value: "value")])
            return HTTPResponse(status: 200, body: responseBody)
        }])
        let response = try await transport.execute(request(body: requestBody), context: TransportContext(clock: ManualClock()))
        #expect(response.status == 200)
        #expect(await transport.executionCount == 1)
        #expect(await counter.snapshot().released == 1)
        await response.body?.close()
        #expect(await counter.snapshot().released == 2)
        let exhaustedBody = try await trackedBody(counter)
        await #expect(throws: TransportFailure.scriptExhausted) {
            try await transport.execute(request(body: exhaustedBody), context: TransportContext(clock: ManualClock()))
        }
        #expect(await counter.snapshot().live == 0)
        #expect(await transport.executionCount == 1)
    }

    /// Script errors retain their typed identity while owned request resources close.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func httpFailureAndCapacity() async throws {
        #expect(throws: TestSupportFailure.capacityExceeded) { try ScriptedHTTPTransport(steps: [], maximumSteps: 0) }
        #expect(throws: TestSupportFailure.capacityExceeded) {
            try ScriptedHTTPTransport(steps: [{ _ in HTTPResponse(status: 200) }, { _ in HTTPResponse(status: 201) }], maximumSteps: 1)
        }
        let counter = ResourceCounter()
        let body = try await trackedBody(counter)
        let transport = try ScriptedHTTPTransport(steps: [{ _ in throw TestSupportFailure.scripted("offline") }])
        await #expect(throws: TestSupportFailure.scripted("offline")) {
            try await transport.execute(request(body: body), context: TransportContext(clock: ManualClock()))
        }
        #expect(await counter.snapshot().live == 0)
    }

    /// Cancellation during request cleanup must close the untransferred response body.
    /// Cleanup runs in stream-owned work so the release gate survives caller cancellation.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func httpCancellationDuringCleanup() async throws {
        let counter = ResourceCounter()
        let lease = await counter.acquire()
        let entered = TestBarrier()
        let release = TestBarrier()
        let body = try BodyStream(maximumChunkBytes: 1, next: { nil }, close: {
            entered.open()
            try? await release.wait()
            await lease.release()
        })
        let responseBody = try await trackedBody(counter)
        let transport = try ScriptedHTTPTransport(steps: [{ _ in HTTPResponse(status: 200, body: responseBody) }])
        let task = Task { try await transport.execute(request(body: body), context: TransportContext(clock: ManualClock())) }
        try await entered.wait()
        task.cancel()
        release.open()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await counter.snapshot().released == 2)
        #expect(await counter.snapshot().live == 0)
    }

    /// Rejects a response when cancellation or expiration follows the last pre-transfer snapshot.
    /// The clock hook changes state after that snapshot, so only a check after
    /// taking response ownership can reclaim both bodies instead of returning success.
    /// - Parameter cancel: True cancels the executing task; false reaches the inclusive deadline.
    /// - Throws: Unexpected fixture construction or URL assertion failures.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [false, true])
    func httpRechecksContextAfterTakingResponse(cancel: Bool) async throws {
        let manual = ManualClock()
        let clock = CompletionBoundaryClock(clock: manual, afterSnapshot: { count in
            guard count == 3 else { return }
            if cancel { withUnsafeCurrentTask { $0?.cancel() } }
            else { try? manual.advance(by: .seconds(1)) }
        })
        let context = TransportContext(clock: clock, deadline: manual.now.advanced(by: .seconds(1)))
        let counter = ResourceCounter()
        let requestBody = try await trackedBody(counter)
        let responseBody = try await trackedBody(counter)
        let transport = try ScriptedHTTPTransport(steps: [{ _ in HTTPResponse(status: 200, body: responseBody) }])
        let task = Task { try await transport.execute(request(body: requestBody), context: context) }
        if cancel {
            await #expect(throws: CancellationError.self) { try await task.value }
        } else {
            await #expect(throws: TransportFailure.deadlineExceeded) { try await task.value }
        }
        #expect(await transport.executionCount == 1)
        #expect(await counter.snapshot().released == 2)
        #expect(await counter.snapshot().live == 0)
        #expect(manual.pendingSleepCount == 0)
        await responseBody.close()
    }

    /// A deadline cancels a suspended script; even a late produced response is reclaimed.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func httpDeadlineReclaimsLateResponse() async throws {
        let scheduled = TestBarrier()
        let clock = ManualClock(onSleepScheduled: { scheduled.open() })
        let counter = ResourceCounter()
        let requestBody = try await trackedBody(counter)
        let responseBody = try await trackedBody(counter)
        let gate = TestBarrier()
        let transport = try ScriptedHTTPTransport(steps: [{ _ in
            do { try await gate.wait() } catch { /* Deliberately return a stale completion. */ }
            return HTTPResponse(status: 200, body: responseBody)
        }])
        let context = TransportContext(clock: clock, deadline: clock.now.advanced(by: .seconds(1)))
        let task = Task { try await transport.execute(request(body: requestBody), context: context) }
        try await scheduled.wait()
        try clock.advance(by: .seconds(1))
        await #expect(throws: TransportFailure.deadlineExceeded) { try await task.value }
        #expect(await counter.snapshot().released == 2)
        #expect(clock.pendingSleepCount == 0)
        #expect(gate.waitingCount == 0)
    }

    /// A suspended first request cannot cause the second caller to reuse its reserved script step.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func concurrentHTTPReservations() async throws {
        let entered = TestBarrier()
        let release = TestBarrier()
        let transport = try ScriptedHTTPTransport(steps: [
            { _ in entered.open(); try await release.wait(); return HTTPResponse(status: 201) },
            { _ in HTTPResponse(status: 202) },
        ])
        let context = TransportContext(clock: ManualClock())
        let first = Task { try await transport.execute(request(), context: context) }
        try await entered.wait()
        let second = try await transport.execute(request(), context: context)
        #expect(second.status == 202)
        #expect(await transport.executionCount == 2)
        release.open()
        #expect(try await first.value.status == 201)
    }

    /// Pre-cancellation closes request input without consuming an HTTP script reservation.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func httpPreCancellation() async throws {
        let counter = ResourceCounter()
        let body = try await trackedBody(counter)
        let transport = try ScriptedHTTPTransport(steps: [{ _ in HTTPResponse(status: 204) }])
        let context = TransportContext(clock: ManualClock())
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await transport.execute(request(body: body), context: context)
        }
        await #expect(throws: CancellationError.self) { try await cancelled.value }
        #expect(await counter.snapshot().live == 0)
        #expect(await transport.executionCount == 0)
        #expect(try await transport.execute(request(), context: context).status == 204)
    }

    /// WebSocket scripts preserve message variants/order, bound output and close once at EOF.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func webSocketOrderingAndClosure() async throws {
        let counter = ResourceCounter()
        let lease = await counter.acquire()
        let messages: [WebSocketMessage] = [.text("one"), .binary(Data([2]))]
        let connection = try ScriptedWebSocketConnection(incoming: messages, maximumMessages: 2, lease: lease)
        let factory = ScriptedWebSocketTransport(connection: connection)
        let context = TransportContext(clock: ManualClock())
        let socket = try await factory.connectWebSocket(request(), context: context)
        for message in messages { try await socket.send(message, context: context) }
        #expect(await connection.sent == messages)
        await #expect(throws: TestSupportFailure.capacityExceeded) { try await socket.send(.text("overflow"), context: context) }
        #expect(try await socket.receive(context: context) == messages[0])
        #expect(try await socket.receive(context: context) == messages[1])
        #expect(try await socket.receive(context: context) == nil)
        #expect(try await socket.receive(context: context) == nil)
        await socket.close(); await socket.close()
        #expect(await counter.snapshot().released == 1)
        await #expect(throws: TransportFailure.closed) { try await socket.send(.text("closed"), context: context) }
    }

    /// Invalid WebSocket capacities and upgrade bodies fail without leaking request sources.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func webSocketValidationAndDeadline() async throws {
        #expect(throws: TestSupportFailure.capacityExceeded) { try ScriptedWebSocketConnection(incoming: [], maximumMessages: 0) }
        #expect(throws: TestSupportFailure.capacityExceeded) {
            try ScriptedWebSocketConnection(incoming: [.text("a"), .text("b")], maximumMessages: 1)
        }
        let counter = ResourceCounter()
        let body = try await trackedBody(counter)
        let connection = try ScriptedWebSocketConnection(incoming: [.text("retained")])
        let transport = ScriptedWebSocketTransport(connection: connection)
        let clock = ManualClock()
        await #expect(throws: TestSupportFailure.scripted("WebSocket upgrade body")) {
            try await transport.connectWebSocket(request(body: body), context: TransportContext(clock: clock))
        }
        #expect(await counter.snapshot().live == 0)
        let expired = TransportContext(clock: clock, deadline: clock.now)
        await #expect(throws: TransportFailure.deadlineExceeded) { try await transport.connectWebSocket(request(), context: expired) }
        await #expect(throws: TransportFailure.deadlineExceeded) { try await connection.send(.text("blocked"), context: expired) }
        await #expect(throws: TransportFailure.deadlineExceeded) { try await connection.receive(context: expired) }
        #expect(await connection.sent.isEmpty)
        #expect(try await connection.receive(context: TransportContext(clock: clock)) == .text("retained"))
        await connection.close()
    }

    /// Datagram scripts keep empty packets distinct from EOF and enforce output capacity.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func datagramBoundariesAndCapacity() async throws {
        let peer = DatagramAddress(host: "localhost", port: UInt16.max)
        #expect(peer.host == "localhost")
        #expect(peer.port == UInt16.max)
        #expect(DatagramAddress(host: "0.0.0.0", port: 0).port == 0)
        let datagram = Datagram(bytes: Data(), peer: peer)
        #expect(datagram.bytes.isEmpty)
        #expect(datagram.peer == peer)
        let transport = try ScriptedDatagramTransport(incoming: [datagram], maximumDatagrams: 1)
        let context = TransportContext(clock: ManualClock())
        try await transport.sendDatagram(datagram, context: context)
        #expect(await transport.sent == [datagram])
        await #expect(throws: TestSupportFailure.capacityExceeded) { try await transport.sendDatagram(datagram, context: context) }
        #expect(try await transport.receiveDatagram(context: context) == datagram)
        #expect(try await transport.receiveDatagram(context: context) == nil)
        await transport.close(); await transport.close()
        #expect(try await transport.receiveDatagram(context: context) == nil)
        await #expect(throws: TransportFailure.closed) { try await transport.sendDatagram(datagram, context: context) }
        #expect(throws: TestSupportFailure.capacityExceeded) { try ScriptedDatagramTransport(incoming: [], maximumDatagrams: 0) }
        #expect(throws: TestSupportFailure.capacityExceeded) { try ScriptedDatagramTransport(incoming: [datagram, datagram], maximumDatagrams: 1) }
    }

    /// Local stream reads split byte boundaries and invalid/overflow operations do not mutate data.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func ipcReadWriteBounds() async throws {
        let transport = try ScriptedIPCTransport(incoming: Data([1, 2, 3]), maximumWrittenBytes: 2)
        let context = TransportContext(clock: ManualClock())
        await #expect(throws: TransportFailure.invalidLimit) { try await transport.read(maximumBytes: 0, context: context) }
        await #expect(throws: TransportFailure.invalidLimit) { try await transport.read(maximumBytes: -1, context: context) }
        #expect(try await transport.read(maximumBytes: 2, context: context) == Data([1, 2]))
        #expect(try await transport.read(maximumBytes: Int.max, context: context) == Data([3]))
        #expect(try await transport.read(maximumBytes: 1, context: context) == nil)
        try await transport.write(Data(), context: context)
        try await transport.write(Data([9, 8]), context: context)
        await #expect(throws: TestSupportFailure.capacityExceeded) { try await transport.write(Data([7]), context: context) }
        #expect(await transport.written == Data([9, 8]))
        await transport.close(); await transport.close()
        #expect(try await transport.read(maximumBytes: 1, context: context) == nil)
        await #expect(throws: TransportFailure.closed) { try await transport.write(Data(), context: context) }
        #expect(throws: TestSupportFailure.capacityExceeded) { try ScriptedIPCTransport(incoming: Data(), maximumWrittenBytes: -1) }
    }

    /// Datagrams and IPC reject expired operations before consuming or appending bytes.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func localTransportDeadlines() async throws {
        let clock = ManualClock()
        let expired = TransportContext(clock: clock, deadline: clock.now)
        let valid = TransportContext(clock: clock)
        let datagram = Datagram(bytes: Data([1]), peer: DatagramAddress(host: "local", port: 1))
        let udp = try ScriptedDatagramTransport(incoming: [datagram])
        await #expect(throws: TransportFailure.deadlineExceeded) { try await udp.sendDatagram(datagram, context: expired) }
        await #expect(throws: TransportFailure.deadlineExceeded) { try await udp.receiveDatagram(context: expired) }
        #expect(try await udp.receiveDatagram(context: valid) == datagram)
        #expect(await udp.sent.isEmpty)
        let ipc = try ScriptedIPCTransport(incoming: Data([1]))
        await #expect(throws: TransportFailure.deadlineExceeded) { try await ipc.write(Data([2]), context: expired) }
        await #expect(throws: TransportFailure.deadlineExceeded) { try await ipc.read(maximumBytes: 1, context: expired) }
        #expect(try await ipc.read(maximumBytes: 1, context: valid) == Data([1]))
        #expect(await ipc.written.isEmpty)
        await ipc.close(); await udp.close()
    }

    /// Pre-cancellation leaves WebSocket, datagram and IPC queues intact for later callers.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func scriptedOperationCancellation() async throws {
        let context = TransportContext(clock: ManualClock())
        let packet = Datagram(bytes: Data([1]), peer: DatagramAddress(host: "local", port: 1))
        let udp = try ScriptedDatagramTransport(incoming: [packet])
        let ipc = try ScriptedIPCTransport(incoming: Data([2]))
        let socket = try ScriptedWebSocketConnection(incoming: [.text("value")])
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            await #expect(throws: CancellationError.self) { try await socket.send(.text("blocked"), context: context) }
            await #expect(throws: CancellationError.self) { try await socket.receive(context: context) }
            await #expect(throws: CancellationError.self) { try await udp.sendDatagram(packet, context: context) }
            await #expect(throws: CancellationError.self) { try await udp.receiveDatagram(context: context) }
            await #expect(throws: CancellationError.self) { try await ipc.write(Data([9]), context: context) }
            await #expect(throws: CancellationError.self) { try await ipc.read(maximumBytes: 1, context: context) }
        }
        await cancelled.value
        #expect(await socket.sent.isEmpty)
        #expect(await udp.sent.isEmpty)
        #expect(await ipc.written.isEmpty)
        #expect(try await socket.receive(context: context) == .text("value"))
        #expect(try await udp.receiveDatagram(context: context) == packet)
        #expect(try await ipc.read(maximumBytes: 1, context: context) == Data([2]))
        await socket.close(); await udp.close(); await ipc.close()
    }

    /// Produces a safe isolated request without opening a network connection.
    /// - Parameter body: Optional source whose cleanup transfers to the executing adapter.
    /// - Returns: A GET request with one ordered test header and an invalid test-only host.
    /// - Throws: Test assertion failure if Foundation rejects the constant URL.
    private func request(body: BodyStream? = nil) throws -> HTTPRequest {
        HTTPRequest(method: "GET", url: try #require(URL(string: "https://example.invalid")),
                    headers: [HTTPHeader(name: "X", value: "value")], body: body)
    }

    /// Creates an EOF body with an observable exactly-once cleanup token.
    /// - Parameter counter: Per-test owner of acquisition/release accounting.
    /// - Returns: A bounded stream that releases its token when consumed or closed.
    /// - Throws: Stream initialization errors; the fixed positive bound is valid.
    private func trackedBody(_ counter: ResourceCounter) async throws -> BodyStream {
        let lease = await counter.acquire()
        return try BodyStream(maximumChunkBytes: 1, next: { nil }, close: { await lease.release() })
    }
}
