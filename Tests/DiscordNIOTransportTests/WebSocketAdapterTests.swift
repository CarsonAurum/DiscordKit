// File: Tests/DiscordNIOTransportTests/WebSocketAdapterTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import Foundation
import Testing
import DiscordTransport
import DiscordFoundationTransport
import DiscordTestSupport
@testable import DiscordNIOTransport
import NIOCore
import NIOPosix
import NIOHTTP1
import NIOWebSocket
import NIOConcurrencyHelpers

/// Server behaviors isolate frame assembly, control handling and protocol rejection.
private enum WebSocketPeerMode: Sendable, Equatable {
    case echo, fragment, invalidUTF8, masked, excessive, reject, halfClose, flood, unsolicitedExtension, unsolicitedProtocol, bufferedClose
    case unexpectedContinuation, interleavedFragment, reservedBit, fragmentedPing, holdUpgrade
    case closePayload(Data)
}

/// Legal empty, standard and application close-code boundaries, with a UTF-8 reason.
private let validWebSocketClosePayloads: [[UInt8]] = [
    [], [3, 232], [3, 244], [11, 184, 111, 107], [19, 135]
]

/// Invalid close lengths, forbidden/unassigned code ranges and malformed UTF-8.
private let invalidWebSocketClosePayloads: [[UInt8]] = [
    [0], [3, 231], [3, 236], [3, 237], [3, 238], [3, 247],
    [7, 208], [11, 183], [19, 136], [255, 255], [3, 232, 255]
]

/// Local RFC 6455 peer, independent of Discord protocol semantics.
private struct WebSocketTestPeer: Sendable {
    let group: MultiThreadedEventLoopGroup
    let channel: any Channel
    let controlObserved: EventLoopPromise<Void>
    let controlCompleted: NIOLockedValueBox<Bool>

    /// Binds an ephemeral local peer and installs the chosen handshake/frame behavior.
    /// A five-second failure guard resolves the optional pong observation, so a
    /// broken control path fails instead of leaving the test awaiting a promise.
    /// - Parameter mode: Deterministic peer behavior for one test instance.
    /// - Returns: Owned listener requiring close after the client connection closes.
    /// - Throws: Bind or pipeline construction error.
    static func open(_ mode: WebSocketPeerMode = .echo) async throws -> WebSocketTestPeer {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let controlObserved = group.next().makePromise(of: Void.self)
        let controlCompleted = NIOLockedValueBox(false)
        let guardTimer = group.next().scheduleTask(in: .seconds(5)) {
            if !controlCompleted.withLockedValue({ value in let old = value; value = true; return old }) {
                controlObserved.fail(TransportFailure.deadlineExceeded)
            }
        }
        controlObserved.futureResult.whenComplete { _ in guardTimer.cancel() }
        do {
            let channel = try await ServerBootstrap(group: group).childChannelInitializer { channel in
                if mode == .holdUpgrade {
                    return channel.eventLoop.makeCompletedFuture {
                        try channel.pipeline.syncOperations.configureHTTPServerPipeline()
                        try channel.pipeline.syncOperations.addHandler(WebSocketHeldHandshakeHandler(
                            observed: controlObserved, completed: controlCompleted))
                    }
                }
                let upgrader = NIOWebSocketServerUpgrader(maxFrameSize: 4096,
                    shouldUpgrade: { channel, _ in
                        var headers = HTTPHeaders()
                        if mode == .unsolicitedExtension { headers.add(name: "Sec-WebSocket-Extensions", value: "permessage-deflate") }
                        if mode == .unsolicitedProtocol { headers.add(name: "Sec-WebSocket-Protocol", value: "unexpected") }
                        return channel.eventLoop.makeSucceededFuture(mode == .reject ? nil : headers)
                    },
                    upgradePipelineHandler: { channel, _ in
                        channel.pipeline.removeHandler(name: "http-fallback").flatMap {
                            channel.eventLoop.makeCompletedFuture {
                                try channel.pipeline.syncOperations.addHandler(WebSocketTestHandler(mode: mode, controlObserved: controlObserved, controlCompleted: controlCompleted))
                            }
                        }
                    })
                return channel.pipeline.configureHTTPServerPipeline(withServerUpgrade: ([upgrader], { _ in })).flatMap {
                    channel.eventLoop.makeCompletedFuture {
                        try channel.pipeline.syncOperations.addHandler(WebSocketRejectHandler(), name: "http-fallback")
                    }
                }
            }.bind(host: "127.0.0.1", port: 0).get()
            return WebSocketTestPeer(group: group, channel: channel, controlObserved: controlObserved, controlCompleted: controlCompleted)
        } catch {
            if !controlCompleted.withLockedValue({ value in let old = value; value = true; return old }) { controlObserved.succeed(()) }
            try? await group.shutdownGracefully(); throw error
        }
    }

    /// Constructs this peer's upgrade request with no application-level credentials.
    /// - Returns: GET ws URL selecting the ephemeral listener.
    func request() -> HTTPRequest {
        HTTPRequest(method: "GET", url: URL(string: "ws://127.0.0.1:\(channel.localAddress!.port!)/gateway")!)
    }

    /// Resolves any unused pong observation, cancels its guard and releases the
    /// listener, accepted sockets and event-loop resources after the test.
    func close() async {
        if !controlCompleted.withLockedValue({ value in let old = value; value = true; return old }) { controlObserved.succeed(()) }
        try? await channel.close().get(); try? await group.shutdownGracefully()
    }
}

/// Receives an upgrade request without sending headers or retaining native promises.
private final class WebSocketHeldHandshakeHandler: ChannelInboundHandler {
    typealias InboundIn = HTTPServerRequestPart
    let observed: EventLoopPromise<Void>
    let completed: NIOLockedValueBox<Bool>

    /// Stores the peer-owned request observation shared with failure guard/teardown.
    /// - Parameters:
    ///   - observed: Completed when the full HTTP upgrade request reaches this peer.
    ///   - completed: Exactly-once completion reservation, including teardown races.
    init(observed: EventLoopPromise<Void>, completed: NIOLockedValueBox<Bool>) {
        self.observed = observed; self.completed = completed
    }

    /// Opens the request barrier and deliberately withholds the upgrade response.
    /// - Parameters:
    ///   - context: Sole event-loop owner; channel closure releases parser state.
    ///   - data: Decoded HTTP request, with only its terminal part opening the gate.
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        if case .end = unwrapInboundIn(data),
           !completed.withLockedValue({ value in let old = value; value = true; return old }) {
            observed.succeed(())
        }
    }
}

/// Handles nonupgraded HTTP only; successful upgrade removes the HTTP server handlers.
private final class WebSocketRejectHandler: ChannelInboundHandler, RemovableChannelHandler {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    /// Returns an empty 400 response when a peer deliberately declines an upgrade.
    /// - Parameters:
    ///   - context: HTTP channel still owned by the fixture.
    ///   - data: Original HTTP request; only its end triggers the response.
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        if case .end = unwrapInboundIn(data) {
            context.write(wrapOutboundOut(.head(HTTPResponseHead(version: .http1_1, status: .badRequest, headers: HTTPHeaders([("Content-Length", "0")])))), promise: nil)
            context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
        }
    }
}

/// Responds to client frames; client masking is verified before any echo is sent.
private final class WebSocketTestHandler: ChannelInboundHandler {
    typealias InboundIn = WebSocketFrame
    typealias OutboundOut = WebSocketFrame
    let mode: WebSocketPeerMode
    let controlObserved: EventLoopPromise<Void>
    let controlCompleted: NIOLockedValueBox<Bool>

    /// Stores one deterministic frame behavior; no tasks or timers are created.
    /// - Parameters:
    ///   - mode: Scenario exercised when the first application frame arrives.
    ///   - controlObserved: Completes when a matching masked pong reaches this peer.
    ///   - controlCompleted: Exactly-once result reservation shared with teardown/guard.
    init(mode: WebSocketPeerMode, controlObserved: EventLoopPromise<Void>, controlCompleted: NIOLockedValueBox<Bool>) {
        self.mode = mode; self.controlObserved = controlObserved; self.controlCompleted = controlCompleted
    }

    /// Echoes bytes, emits fragmented/control frames or intentionally malformed input.
    /// Matching pong payloads/masking are asserted before opening the control barrier.
    /// - Parameters:
    ///   - context: Upgraded socket's event loop, defining response ordering.
    ///   - data: Complete decoded client frame; client messages must be masked.
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let frame = unwrapInboundIn(data)
        if frame.opcode == .pong {
            #expect(frame.maskKey != nil)
            #expect(frame.unmaskedData.getString(at: frame.unmaskedData.readerIndex, length: frame.unmaskedData.readableBytes) == (mode == .bufferedClose ? "ownership" : "ping"))
            if !controlCompleted.withLockedValue({ value in let old = value; value = true; return old }) { controlObserved.succeed(()) }
            return
        }
        guard frame.opcode == .text || frame.opcode == .binary else { return }
        #expect(frame.maskKey != nil)
        switch mode {
        case .echo:
            context.writeAndFlush(wrapOutboundOut(WebSocketFrame(fin: true, opcode: frame.opcode, data: frame.unmaskedData)), promise: nil)
        case .fragment:
            context.write(wrapOutboundOut(WebSocketFrame(fin: false, opcode: .text, data: context.channel.allocator.buffer(bytes: [0xF0, 0x9F]))), promise: nil)
            context.write(wrapOutboundOut(WebSocketFrame(fin: true, opcode: .ping, data: context.channel.allocator.buffer(string: "ping"))), promise: nil)
            context.write(wrapOutboundOut(WebSocketFrame(fin: true, opcode: .continuation, data: context.channel.allocator.buffer(bytes: [0x90, 0x95]))), promise: nil)
            context.writeAndFlush(wrapOutboundOut(WebSocketFrame(fin: true, opcode: .text, data: context.channel.allocator.buffer(string: "second"))), promise: nil)
        case .invalidUTF8:
            context.writeAndFlush(wrapOutboundOut(WebSocketFrame(fin: true, opcode: .text, data: context.channel.allocator.buffer(bytes: [255]))), promise: nil)
        case .masked:
            context.writeAndFlush(wrapOutboundOut(WebSocketFrame(fin: true, opcode: .text, maskKey: .random(), data: context.channel.allocator.buffer(string: "masked"))), promise: nil)
        case .excessive:
            context.writeAndFlush(wrapOutboundOut(WebSocketFrame(fin: true, opcode: .binary, data: context.channel.allocator.buffer(repeating: 0, count: 1024))), promise: nil)
        case .halfClose: context.close(promise: nil)
        case .flood:
            for _ in 0..<16 { context.write(wrapOutboundOut(WebSocketFrame(fin: true, opcode: .text, data: context.channel.allocator.buffer(string: "flood"))), promise: nil) }
            context.flush()
        case .closePayload(let bytes):
            context.writeAndFlush(wrapOutboundOut(WebSocketFrame(fin: true, opcode: .connectionClose, data: context.channel.allocator.buffer(bytes: bytes))), promise: nil)
        case .unexpectedContinuation:
            context.writeAndFlush(wrapOutboundOut(WebSocketFrame(fin: true, opcode: .continuation, data: context.channel.allocator.buffer(string: "unexpected"))), promise: nil)
        case .interleavedFragment:
            context.write(wrapOutboundOut(WebSocketFrame(fin: false, opcode: .text, data: context.channel.allocator.buffer(string: "unfinished"))), promise: nil)
            context.writeAndFlush(wrapOutboundOut(WebSocketFrame(fin: true, opcode: .binary, data: context.channel.allocator.buffer(string: "interleaved"))), promise: nil)
        case .reservedBit:
            context.writeAndFlush(wrapOutboundOut(WebSocketFrame(fin: true, rsv1: true, opcode: .text, data: context.channel.allocator.buffer(string: "reserved"))), promise: nil)
        case .fragmentedPing:
            context.writeAndFlush(wrapOutboundOut(WebSocketFrame(fin: false, opcode: .ping, data: context.channel.allocator.buffer(string: "invalid"))), promise: nil)
        case .bufferedClose:
            context.write(wrapOutboundOut(WebSocketFrame(fin: true, opcode: .text, data: context.channel.allocator.buffer(string: "queued"))), promise: nil)
            context.write(wrapOutboundOut(WebSocketFrame(fin: false, opcode: .binary, data: context.channel.allocator.buffer(bytes: [1, 2, 3]))), promise: nil)
            context.write(wrapOutboundOut(WebSocketFrame(fin: true, opcode: .ping, data: context.channel.allocator.buffer(string: "ownership"))), promise: nil)
            context.writeAndFlush(wrapOutboundOut(WebSocketFrame(fin: true, opcode: .connectionClose, data: context.channel.allocator.buffer(bytes: [3, 232]))), promise: nil)
        case .reject, .unsolicitedExtension, .unsolicitedProtocol, .holdUpgrade: break
        }
    }
}

/// WebSocket wire conformance over owned loopback peers, with bounded failure deadlines.
/// Cases serialize their native event-loop fixtures to respect host descriptor/thread
/// limits; each scenario explicitly controls its own concurrent operations.
@Suite(.serialized) private struct WebSocketAdapterTests {
    /// Provides real-time safety bounds without sleeping to drive successful tests.
    /// - Returns: Five-second per-operation monotonic context.
    private func context() -> TransportContext<ContinuousClock> {
        TransportContext(clock: ContinuousClock(), deadline: ContinuousClock().now.advanced(by: .seconds(5)))
    }

    /// Confirms text, binary, empty messages and repeated operation/close transitions.
    /// - Parameter message: Complete application payload, including empty values.
    /// - Throws: Local peer setup/upgrade, send or receive errors.
    @Test(arguments: [WebSocketMessage.text(""), .text("snowflake:18446744073709551615 🐕"), .binary(Data()), .binary(Data([0, 128, 255]))])
    func roundTrip(_ message: WebSocketMessage) async throws {
        let peer = try await WebSocketTestPeer.open()
        let transport: NIOWebSocketTransport
        do { transport = try NIOWebSocketTransport(configuration: NIOWebSocketConfiguration()) }
        catch { await peer.close(); Issue.record("WebSocket transport initialization failed"); throw error }
        var phase = "upgrade"
        do {
            let connection = try await transport.connectWebSocket(peer.request(), context: context())
            phase = "send"
            try await connection.send(message, context: context())
            phase = "receive"
            #expect(try await connection.receive(context: context()) == message)
            await connection.close(); await connection.close()
            #expect(await transport.connectionCount() == 0)
            #expect(try await connection.receive(context: context()) == nil)
            await #expect(throws: TransportFailure.closed) { try await connection.send(.text("closed"), context: context()) }
        } catch { await transport.close(); await peer.close(); Issue.record("WebSocket round-trip failed during \(phase)"); throw error }
        await transport.close(); await transport.close(); await peer.close()
    }

    /// A fast bodyless GET peer can begin its 101 response as soon as it parses the request head.
    /// Repeated real upgrades verify that the client's end is queued before flushing the head,
    /// preventing NIO's writing-during-upgrade race and returning the sole admission slot each time.
    /// - Throws: Any setup, upgrade or round-trip failure; transient connect failures are not retried.
    @Test func fastPeerUpgradeAndAdmissionReuse() async throws {
        let peer = try await WebSocketTestPeer.open()
        let transport = try NIOWebSocketTransport(configuration: NIOWebSocketConfiguration(maximumConnections: 1))
        do {
            for ordinal in 0..<64 {
                let connection = try await transport.connectWebSocket(peer.request(), context: context())
                let message = WebSocketMessage.text("upgrade-\(ordinal)")
                try await connection.send(message, context: context())
                #expect(try await connection.receive(context: context()) == message)
                await connection.close()
                #expect(await transport.connectionCount() == 0)
            }
        } catch { await transport.close(); await peer.close(); throw error }
        await transport.close(); await peer.close()
    }

    /// Reassembles UTF-8 split across fragments while ping/pong bypasses user reads,
    /// then preserves the next complete message's wire ordering.
    /// - Throws: Local peer, upgrade or receive errors.
    @Test func fragmentationAndControl() async throws {
        let peer = try await WebSocketTestPeer.open(.fragment)
        let transport = try NIOWebSocketTransport(configuration: NIOWebSocketConfiguration())
        do {
            let connection = try await transport.connectWebSocket(peer.request(), context: context())
            try await connection.send(.text("start"), context: context())
            #expect(try await connection.receive(context: context()) == .text("🐕"))
            #expect(try await connection.receive(context: context()) == .text("second"))
            try await peer.controlObserved.futureResult.get()
            await connection.close()
        } catch { await transport.close(); await peer.close(); throw error }
        await transport.close(); await peer.close()
    }

    /// Rejects malformed UTF-8, server masking, oversized frames, abrupt EOF,
    /// unexpected/interleaved fragmentation, reserved bits and fragmented controls.
    /// Every failure terminates the socket and returns its connection reservation.
    /// - Parameter mode: Specific malformed or truncated peer response.
    /// - Throws: Local peer setup/upgrade failure.
    @Test(arguments: [WebSocketPeerMode.invalidUTF8, .masked, .excessive, .halfClose,
                      .unexpectedContinuation, .interleavedFragment, .reservedBit, .fragmentedPing])
    func invalidPeer(_ mode: WebSocketPeerMode) async throws {
        let peer = try await WebSocketTestPeer.open(mode)
        let transport = try NIOWebSocketTransport(configuration: NIOWebSocketConfiguration(maximumMessageBytes: 32))
        do {
            let connection = try await transport.connectWebSocket(peer.request(), context: context())
            do {
                try await connection.send(.text("start"), context: context())
                _ = try await connection.receive(context: context())
                Issue.record("Malformed peer unexpectedly succeeded")
            } catch { #expect(error is NIOAdapterFailure) }
            await connection.close()
            #expect(await transport.connectionCount() == 0)
        } catch { await transport.close(); await peer.close(); throw error }
        await transport.close(); await peer.close()
    }

    /// Verifies failed upgrades do not consume a connection slot or become retries.
    /// - Parameter mode: Rejected upgrade or unsolicited extension/subprotocol negotiation.
    /// - Throws: Local peer setup or transport configuration error.
    @Test(arguments: [WebSocketPeerMode.reject, .unsolicitedExtension, .unsolicitedProtocol])
    func failedUpgrade(_ mode: WebSocketPeerMode) async throws {
        let peer = try await WebSocketTestPeer.open(mode)
        let transport = try NIOWebSocketTransport(configuration: NIOWebSocketConfiguration())
        await #expect(throws: NIOAdapterFailure.upgradeRejected) {
            try await transport.connectWebSocket(peer.request(), context: context())
        }
        #expect(await transport.connectionCount() == 0)
        await transport.close(); await peer.close()
    }

    /// Oversized outbound values fail before network transmission while preserving
    /// the usable connection; aggregate connection overload fails without waiters.
    /// - Throws: Unexpected setup or valid round-trip failures.
    @Test func sendLimitsAndAdmission() async throws {
        let peer = try await WebSocketTestPeer.open()
        let transport = try NIOWebSocketTransport(configuration: NIOWebSocketConfiguration(maximumConnections: 1, maximumMessageBytes: 4))
        do {
            let connection = try await transport.connectWebSocket(peer.request(), context: context())
            await #expect(throws: NIOAdapterFailure.capacityExceeded) {
                try await transport.connectWebSocket(peer.request(), context: context())
            }
            for message in [WebSocketMessage.text("🐕a"), .binary(Data(repeating: 1, count: 5))] {
                await #expect(throws: NIOAdapterFailure.messageTooLarge) { try await connection.send(message, context: context()) }
            }
            try await connection.send(.text("ok"), context: context())
            #expect(try await connection.receive(context: context()) == .text("ok"))
            await connection.close()
        } catch { await transport.close(); await peer.close(); throw error }
        await transport.close(); await peer.close()
    }

    /// A slow reader cannot create an unbounded message queue; overflow terminates
    /// the connection rather than discarding messages or indefinitely queuing work.
    /// - Throws: Unexpected local setup errors.
    @Test func receiveOverflow() async throws {
        let peer = try await WebSocketTestPeer.open(.flood)
        let transport = try NIOWebSocketTransport(configuration: NIOWebSocketConfiguration(maximumBufferedMessages: 1))
        do {
            let connection = try await transport.connectWebSocket(peer.request(), context: context())
            try await connection.send(.text("start"), context: context())
            do {
                for _ in 0..<17 { _ = try await connection.receive(context: context()) }
                Issue.record("Expected bounded queue overflow")
            } catch { #expect(error as? NIOAdapterFailure == .capacityExceeded) }
            await connection.close()
            #expect(await transport.connectionCount() == 0)
        } catch { await transport.close(); await peer.close(); throw error }
        await transport.close(); await peer.close()
    }

    /// Cancelling an admitted receive race closes the connection and returns its
    /// slot. A virtual timer-registration barrier proves the deadline child entered;
    /// it does not assume which child first reserves the native read promise.
    /// - Throws: Unexpected peer or barrier failure.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func receiveCancellation() async throws {
        let peer = try await WebSocketTestPeer.open()
        let transport = try NIOWebSocketTransport(configuration: NIOWebSocketConfiguration())
        do {
            let connection = try await transport.connectWebSocket(peer.request(), context: context())
            let entered = TestBarrier()
            let clock = ManualClock(onSleepScheduled: { entered.open() })
            let receiving = Task {
                try await connection.receive(context: TransportContext(clock: clock, deadline: clock.now.advanced(by: .seconds(1))))
            }
            try await entered.wait()
            receiving.cancel()
            await #expect(throws: CancellationError.self) { try await receiving.value }
            #expect(clock.pendingSleepCount == 0)
            #expect(await transport.connectionCount() == 0)
        } catch { await transport.close(); await peer.close(); throw error }
        await transport.close(); await peer.close()
    }

    /// Valid empty/status close frames yield orderly EOF and release ownership.
    /// Standard code 1000, permitted 1012, both application-code boundaries and a
    /// valid UTF-8 reason exercise the parser without requiring a prior message.
    /// - Parameter payload: Empty or legal network-order close code plus optional reason.
    /// - Throws: Unexpected peer/connection failure.
    @Test(arguments: validWebSocketClosePayloads)
    func orderlyClose(_ payload: [UInt8]) async throws {
        let peer = try await WebSocketTestPeer.open(.closePayload(Data(payload)))
        let transport = try NIOWebSocketTransport(configuration: NIOWebSocketConfiguration())
        do {
            let connection = try await transport.connectWebSocket(peer.request(), context: context())
            try await connection.send(.text("start"), context: context())
            #expect(try await connection.receive(context: context()) == nil)
            await connection.close()
            #expect(await transport.connectionCount() == 0)
        } catch { await transport.close(); await peer.close(); throw error }
        await transport.close(); await peer.close()
    }

    /// Session-aware status survives receive cleanup and parent event-loop shutdown.
    /// - Parameter code: Current Gateway fatal/new-session/resumable codes, transported without policy.
    /// - Throws: Loopback setup, upgrade or unexpected I/O failure.
    @Test(arguments: [4000,4001,4002,4003,4004,4005,4007,4008,4009,4010,4011,4012,4013,4014])
    func sessionPeerCloseCode(_ code: Int) async throws {
        let bytes = Data([UInt8(code >> 8), UInt8(code & 255)])
        let peer = try await WebSocketTestPeer.open(.closePayload(bytes))
        let transport = try NIOWebSocketTransport(configuration: NIOWebSocketConfiguration())
        do {
            let connection = try await transport.connectWebSocket(peer.request(), context: context())
            let session = try #require(connection as? any WebSocketSessionConnection)
            #expect(await session.peerCloseCode() == nil)
            try await session.send(.text("start"), context: context())
            #expect(try await session.receive(context: context()) == nil)
            #expect(await session.peerCloseCode() == code)
            await session.closeForReconnect()
            #expect(await transport.connectionCount() == 0)
            await transport.close()
            #expect(await session.peerCloseCode() == code)
            await session.closeForReconnect()
        } catch { await transport.close(); await peer.close(); throw error }
        await transport.close(); await peer.close()
    }

    /// Reconnect abort unblocks a pending receive and releases admission without inventing a peer status.
    /// Duplicate-reader rejection is the synchronization barrier proving a native read is pending.
    /// - Throws: Loopback setup, unexpected native receive failure or protocol error.
    @Test func sessionReconnectAbort() async throws {
        let peer = try await WebSocketTestPeer.open()
        let transport = try NIOWebSocketTransport(configuration: NIOWebSocketConfiguration())
        do {
            let connection = try await transport.connectWebSocket(peer.request(), context: context())
            let session = try #require(connection as? any WebSocketSessionConnection)
            try await withThrowingTaskGroup(of: Int.self) { group throws in
                for _ in 0..<2 {
                    group.addTask {
                        do { return try await session.receive(context: TransportContext(clock: ContinuousClock())) == nil ? 0 : 2 }
                        catch TransportFailure.concurrentRead { return 1 }
                    }
                }
                #expect(try await group.next() == 1)
                await session.closeForReconnect()
                #expect(try await group.next() == 0)
            }
            await session.closeForReconnect()
            #expect(await session.peerCloseCode() == nil)
            #expect(await transport.connectionCount() == 0)
            await #expect(throws: TransportFailure.closed) { try await session.send(.text("late"), context: context()) }
        } catch { await transport.close(); await peer.close(); throw error }
        await transport.close(); await peer.close()
    }

    /// Invalid close payloads terminate the connection with a redacted frame error.
    /// Cases cover a one-byte payload, reserved/forbidden 1004/1005/1006/1015,
    /// status values below 1000 or in unassigned ranges, application upper overflow,
    /// and a malformed UTF-8 reason following otherwise legal code 1000.
    /// - Parameter payload: Deliberately invalid close payload in network byte order.
    /// - Throws: Fixture/upgrade failure or an unexpected send failure.
    @Test(arguments: invalidWebSocketClosePayloads)
    func invalidClosePayload(_ payload: [UInt8]) async throws {
        let peer = try await WebSocketTestPeer.open(.closePayload(Data(payload)))
        let transport = try NIOWebSocketTransport(configuration: NIOWebSocketConfiguration())
        do {
            let connection = try await transport.connectWebSocket(peer.request(), context: context())
            try await connection.send(.text("start"), context: context())
            await #expect(throws: NIOAdapterFailure.invalidFrame) {
                try await connection.receive(context: context())
            }
            #expect(await transport.connectionCount() == 0)
            await connection.close()
        } catch { await transport.close(); await peer.close(); throw error }
        await transport.close(); await peer.close()
    }

    /// A matching pong proves queued messages and a partial fragment were processed
    /// before disposal. Natural remote EOF preserves earlier complete messages;
    /// parent close discards all input while the caller still retains its connection,
    /// and later reads return terminal EOF without entering a stopped event loop.
    /// - Parameter parentClose: Whether to explicitly close the parent before reading.
    /// - Throws: Peer setup, upgrade, barrier or unexpected receive failures.
    @Test(arguments: [false, true])
    func retainedConnectionAndQueuedClose(_ parentClose: Bool) async throws {
        let peer = try await WebSocketTestPeer.open(.bufferedClose)
        let transport = try NIOWebSocketTransport(configuration: NIOWebSocketConfiguration())
        do {
            let connection = try await transport.connectWebSocket(peer.request(), context: context())
            try await connection.send(.text("start"), context: context())
            try await peer.controlObserved.futureResult.get()
            if parentClose {
                await transport.close()
                #expect(await transport.connectionCount() == 0)
            } else {
                #expect(try await connection.receive(context: context()) == .text("queued"))
            }
            #expect(try await connection.receive(context: context()) == nil)
            await connection.close(); await connection.close()
            #expect(await transport.connectionCount() == 0)
        } catch { await transport.close(); await peer.close(); throw error }
        await transport.close(); await peer.close()
    }

    /// Duplicate-reader rejection establishes that the first native receive is
    /// genuinely pending. Concurrent explicit close unblocks it with terminal EOF,
    /// drops its reservation once and leaves subsequent reads terminal as well.
    /// - Throws: Local setup, duplicate-reader classification or unexpected I/O errors.
    @Test func explicitCloseDuringPendingReceive() async throws {
        let peer = try await WebSocketTestPeer.open()
        let transport = try NIOWebSocketTransport(configuration: NIOWebSocketConfiguration())
        do {
            let connection = try await transport.connectWebSocket(peer.request(), context: context())
            try await withThrowingTaskGroup(of: Int.self) { group throws in
                for _ in 0..<2 {
                    group.addTask {
                        do { return try await connection.receive(context: TransportContext(clock: ContinuousClock())) == nil ? 0 : 2 }
                        catch TransportFailure.concurrentRead { return 1 }
                    }
                }
                #expect(try await group.next() == 1)
                await withTaskGroup(of: Void.self) { closers in
                    for _ in 0..<4 { closers.addTask { await connection.close() } }
                }
                #expect(try await group.next() == 0)
                #expect(try await group.next() == nil)
            }
            #expect(await transport.connectionCount() == 0)
            #expect(try await connection.receive(context: context()) == nil)
        } catch { await transport.close(); await peer.close(); throw error }
        await transport.close(); await peer.close()
    }

    /// The peer observes a complete upgrade request but withholds all response
    /// headers. Parent shutdown must cancel and await that owned connect task before
    /// stopping its loop, release admission and leave repeated shutdown terminal.
    /// This qualifies held loopback handshakes, not stalled DNS or TCP establishment.
    /// - Throws: Fixture setup or request-observation failure.
    @Test func parentCloseDuringUpgrade() async throws {
        let peer = try await WebSocketTestPeer.open(.holdUpgrade)
        let transport = try NIOWebSocketTransport(configuration: NIOWebSocketConfiguration())
        let operation = Task { try await transport.connectWebSocket(peer.request(), context: context()) }
        do {
            try await peer.controlObserved.futureResult.get()
            #expect(await transport.connectionCount() == 1)
            await transport.close()
            #expect(await transport.connectionCount() == 0)
            do {
                let connection = try await operation.value
                await connection.close()
                Issue.record("Closed parent unexpectedly transferred an upgrade")
            } catch {
                #expect(error is CancellationError || error as? NIOAdapterFailure == .upgradeRejected || error as? TransportFailure == .closed)
            }
            await transport.close()
        } catch { await transport.close(); await peer.close(); throw error }
        await peer.close()
    }

    /// Rejects configuration overflow and invalid limits without allocating sockets.
    @Test func configurations() {
        #expect(throws: TransportFailure.invalidLimit) { try NIOWebSocketConfiguration(maximumConnections: 0) }
        #expect(throws: TransportFailure.invalidLimit) { try NIOWebSocketConfiguration(maximumMessageBytes: 0) }
        #expect(throws: TransportFailure.invalidLimit) { try NIOWebSocketConfiguration(maximumMessageBytes: Int.max) }
        #expect(throws: TransportFailure.invalidLimit) { try NIOWebSocketConfiguration(maximumBufferedMessages: 0) }
        #expect(throws: TransportFailure.invalidLimit) { try NIOWebSocketConfiguration(maximumPendingWrites: 0) }
        #expect(throws: TransportFailure.invalidLimit) { try NIOWebSocketConfiguration(maximumHeaderBytes: 0) }
    }
}
