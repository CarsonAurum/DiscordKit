// File: Tests/DiscordNIOTransportTests/IngressAdapterTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordTransport
import DiscordTestSupport
import Foundation
import NIOCore
import NIOPosix
import Testing
@testable import DiscordNIOTransport

/// A raw TCP client keeps ingress verification independent of the HTTP client codec.
private struct IngressRawPeer: Sendable {
    let group: MultiThreadedEventLoopGroup
    let channel: any Channel
    let response: EventLoopFuture<Data>

    /// Connects to a loopback listener and sends caller-supplied HTTP bytes once.
    /// - Parameters:
    ///   - address: Listener's assigned numeric address and port.
    ///   - request: Complete or deliberately malformed HTTP request bytes.
    ///   - expectWriteRejection: Allows native write failure when the server is
    ///     deliberately enforcing its connection cap before request transmission.
    /// - Returns: An owned client whose response completes when the server closes.
    /// - Throws: Local connection, write, or pipeline initialization failure.
    static func open(address: DatagramAddress, request: String,
                     expectWriteRejection: Bool = false) async throws -> IngressRawPeer {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let promise = group.next().makePromise(of: Data.self)
        do {
            let channel = try await ClientBootstrap(group: group).channelInitializer { channel in
                channel.eventLoop.makeCompletedFuture {
                    try channel.pipeline.syncOperations.addHandler(IngressRawCollector(promise: promise))
                }
            }.connect(host: address.host, port: Int(address.port)).get()
            do { try await channel.writeAndFlush(channel.allocator.buffer(string: request)).get() }
            catch {
                guard expectWriteRejection else { throw error }
                channel.close(promise: nil)
            }
            return IngressRawPeer(group: group, channel: channel, response: promise.futureResult)
        } catch { try? await group.shutdownGracefully(); throw error }
    }

    /// Closes the client socket and awaits event-loop cleanup on every test exit path.
    func close() async {
        channel.close(promise: nil)
        try? await channel.closeFuture.get()
        try? await group.shutdownGracefully()
    }
}

/// Collects at most 2 MiB until EOF, with a failure-only safety deadline.
private final class IngressRawCollector: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer
    let promise: EventLoopPromise<Data>
    var bytes = Data()
    var completed = false
    var timer: Scheduled<Void>?

    /// Retains exactly one completion owned by this channel's event loop.
    /// - Parameter promise: Raw HTTP wire bytes returned at server EOF.
    init(promise: EventLoopPromise<Data>) { self.promise = promise }

    /// Installs a ten-second failure guard; successful tests synchronize by I/O.
    /// - Parameter context: Channel event loop used to schedule guard cleanup.
    func handlerAdded(context: ChannelHandlerContext) {
        let channel = context.channel
        let bound = NIOLoopBound(self, eventLoop: context.eventLoop)
        timer = context.eventLoop.scheduleTask(in: .seconds(10)) {
            let handler = bound.value
            if !handler.completed {
                handler.completed = true
                handler.promise.fail(TransportFailure.deadlineExceeded)
            }
            channel.close(promise: nil)
        }
    }

    /// Accumulates bounded raw bytes without interpreting HTTP framing.
    /// - Parameters:
    ///   - context: Context used to close an oversized fixture response.
    ///   - data: One TCP fragment whose boundaries have no HTTP meaning.
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let value = unwrapInboundIn(data)
        guard value.readableBytes <= 2_097_152 - bytes.count else {
            context.close(promise: nil)
            return
        }
        bytes.append(contentsOf: value.readableBytesView)
    }

    /// Publishes collected bytes once and cancels the failure guard.
    /// - Parameter context: Closed socket context forwarded after completion.
    func channelInactive(context: ChannelHandlerContext) {
        timer?.cancel()
        if !completed { completed = true; promise.succeed(bytes) }
        context.fireChannelInactive()
    }

    /// Treats an intentional ingress rejection/reset as terminal empty/raw input.
    /// - Parameters:
    ///   - context: Fixture socket context used for close.
    ///   - error: Native failure ignored because assertions inspect actual response bytes.
    func errorCaught(context: ChannelHandlerContext, error: any Error) { context.close(promise: nil) }

    /// Releases the guard after pipeline teardown.
    /// - Parameter context: Removed context with no surviving fixture resources.
    func handlerRemoved(context: ChannelHandlerContext) { timer?.cancel() }
}

/// Native ingress ownership, framing, admission and failure regression coverage.
@Suite struct IngressAdapterTests {
    /// Supplies a failure deadline independent of the successful test ordering.
    /// - Returns: Monotonic operation context with a ten-second failure bound.
    private func context() -> TransportContext<ContinuousClock> {
        let clock = ContinuousClock()
        return .init(clock: clock, deadline: clock.now.advanced(by: .seconds(10)))
    }

    /// Creates a single-use in-memory body without an unbounded producer queue.
    /// - Parameter bytes: Complete fixture body, including empty bytes.
    /// - Returns: A one-chunk body whose producer memory is released at EOF/close.
    /// - Throws: BodyStream validation failures.
    private func body(_ bytes: Data) throws -> BodyStream {
        let queue = NIOServiceQueue<Data>(maximumCount: 1, maximumBytes: max(1, bytes.count))
        _ = queue.offer(bytes, bytes: bytes.count)
        let consumed = NIOIngressFixtureFlag()
        return try BodyStream(maximumChunkBytes: max(1, bytes.count), next: {
            guard await consumed.take() else { return nil }
            return try await queue.next()
        }, close: { queue.finish() })
    }

    /// Confirms raw chunked input, duplicate headers, request URL and response framing.
    /// - Throws: Unexpected local socket or body failures.
    @Test func requestAndResponseRoundTrip() async throws {
        let listener = try await NIOHTTPIngress.bind(context: context())
        let peer = try await IngressRawPeer.open(address: listener.localAddress, request:
            "POST /interactions?q=secret HTTP/1.1\r\nHost: localhost\r\nX-Duplicate: one\r\nX-Duplicate: two\r\nTransfer-Encoding: chunked\r\n\r\n2\r\nab\r\n1\r\nc\r\n0\r\n\r\n")
        do {
            let exchange = try #require(try await listener.accept(context: context()))
            #expect(exchange.request.method == "POST")
            #expect(exchange.request.url.path == "/interactions")
            #expect(exchange.request.url.query == "q=secret")
            #expect(exchange.request.headers.filter { $0.name.lowercased() == "x-duplicate" }.map(\.value) == ["one", "two"])
            let requestBody = try #require(exchange.request.body)
            var collected = Data()
            for try await chunk in requestBody { collected.append(chunk) }
            #expect(collected == Data("abc".utf8))
            let response = HTTPResponse(status: 201,
                                        headers: [.init(name: "X-Duplicate", value: "a"), .init(name: "X-Duplicate", value: "b"),
                                                  .init(name: "Content-Length", value: "999")],
                                        body: try body(Data([0, 128, 255])))
            try await exchange.responder.respond(response, context: context())
            let wire = try await peer.response.get()
            #expect(wire.starts(with: Data("HTTP/1.1 201 Created\r\n".utf8)))
            #expect(wire.range(of: Data("X-Duplicate: a\r\nX-Duplicate: b\r\n".utf8)) != nil)
            #expect(wire.range(of: Data("Content-Length: 3\r\n".utf8)) != nil)
            #expect(wire.suffix(3) == Data([0, 128, 255]))
            await #expect(throws: NIOServiceFailure.duplicateResponse) {
                try await exchange.responder.respond(.init(status: 200), context: context())
            }
            await exchange.responder.close()
        } catch { await peer.close(); await listener.close(); throw error }
        await peer.close()
        await listener.close()
    }

    /// Proves caller-owned exchanges survive listener close and count toward socket budgets.
    /// - Throws: Unexpected local connection or response failures.
    @Test func acceptedOwnershipAndConnectionBound() async throws {
        let listener = try await NIOHTTPIngress.bind(maximumConnections: 1, context: context())
        let peer = try await IngressRawPeer.open(address: listener.localAddress,
                                                request: "GET /first HTTP/1.1\r\nHost: localhost\r\n\r\n")
        do {
            let exchange = try #require(try await listener.accept(context: context()))
            let rejected = try await IngressRawPeer.open(address: listener.localAddress,
                                                        request: "GET /second HTTP/1.1\r\nHost: localhost\r\n\r\n",
                                                        expectWriteRejection: true)
            #expect(try await rejected.response.get().isEmpty)
            await rejected.close()
            async let first: Void = listener.close()
            async let second: Void = listener.close()
            _ = await (first, second)
            #expect(try await listener.accept(context: context()) == nil)
            try await exchange.responder.respond(.init(status: 204), context: context())
            let wire = try await peer.response.get()
            #expect(wire.starts(with: Data("HTTP/1.1 204 No Content\r\n".utf8)))
            #expect(wire.range(of: Data("Content-Length:".utf8)) == nil)
            await exchange.responder.close()
        } catch { await peer.close(); await listener.close(); throw error }
        await peer.close()
        await listener.close()
    }

    /// Rejects malformed, excessive and unsupported request forms before handoff.
    /// - Parameter request: Request triggering HTTP version, size, URI, Expect or trailer rejection.
    /// - Throws: Unexpected fixture setup failures.
    @Test(arguments: [
        "POST / HTTP/1.1\r\nHost: localhost\r\nContent-Length: 4\r\n\r\nabcd",
        "GET / HTTP/1.0\r\n\r\n",
        "GET http://example.com/ HTTP/1.1\r\nHost: localhost\r\n\r\n",
        "POST / HTTP/1.1\r\nHost: localhost\r\nExpect: 100-continue\r\n\r\n",
        "POST / HTTP/1.1\r\nHost: localhost\r\nTransfer-Encoding: chunked\r\n\r\n0\r\nX-Trailer: value\r\n\r\n",
        "GET / HTTP/1.1\r\nX-Large: " + String(repeating: "a", count: 100) + "\r\n\r\n"
    ])
    func rejectedRequests(request: String) async throws {
        let listener = try await NIOHTTPIngress.bind(maximumBodyBytes: 3, maximumHeaderBytes: 64, context: context())
        let peer = try await IngressRawPeer.open(address: listener.localAddress, request: request)
        #expect(try await peer.response.get().isEmpty)
        await peer.close()
        await listener.close()
        #expect(try await listener.accept(context: context()) == nil)
    }

    /// Invalid status/header/body failures permanently reserve the response slot.
    /// - Parameter mode: Status, field-name, field-value or body-size violation.
    /// - Throws: Unexpected setup or peer I/O failures.
    @Test(arguments: [0, 1, 2, 3])
    func rejectedResponses(mode: Int) async throws {
        let listener = try await NIOHTTPIngress.bind(maximumBodyBytes: 3, context: context())
        let peer = try await IngressRawPeer.open(address: listener.localAddress,
                                                request: "GET / HTTP/1.1\r\nHost: localhost\r\n\r\n")
        do {
            let exchange = try #require(try await listener.accept(context: context()))
            let response: HTTPResponse
            switch mode {
            case 0: response = .init(status: 101)
            case 1: response = .init(status: 200, headers: [.init(name: "bad name", value: "value")])
            case 2: response = .init(status: 200, headers: [.init(name: "X-Test", value: "bad\r\nInjected: yes")])
            default: response = .init(status: 200, body: try body(Data([1, 2, 3, 4])))
            }
            do { try await exchange.responder.respond(response, context: context()); Issue.record("Expected invalid response failure") }
            catch { #expect(error is NIOServiceFailure || error is TransportFailure) }
            #expect(try await peer.response.get().isEmpty)
            await #expect(throws: NIOServiceFailure.duplicateResponse) {
                try await exchange.responder.respond(.init(status: 200), context: context())
            }
        } catch { await peer.close(); await listener.close(); throw error }
        await peer.close()
        await listener.close()
    }

    /// HEAD and body-forbidden status codes never transmit supplied payload bytes.
    /// - Parameter status: Ordinary HEAD response or status forbidding response content.
    /// - Throws: Unexpected socket or body setup failures.
    @Test(arguments: [200, 204, 205, 304])
    func bodySuppression(status: Int) async throws {
        let listener = try await NIOHTTPIngress.bind(context: context())
        let method = status == 200 ? "HEAD" : "GET"
        let peer = try await IngressRawPeer.open(address: listener.localAddress,
                                                request: "\(method) / HTTP/1.1\r\nHost: localhost\r\n\r\n")
        do {
            let exchange = try #require(try await listener.accept(context: context()))
            try await exchange.responder.respond(.init(status: status, body: try body(Data("hidden-body".utf8))),
                                                   context: context())
            let wire = try await peer.response.get()
            #expect(wire.suffix(4) == Data("\r\n\r\n".utf8))
            #expect(wire.range(of: Data("hidden-body".utf8)) == nil)
            if status == 204 || status == 304 {
                #expect(wire.range(of: Data("Content-Length:".utf8)) == nil)
            }
        } catch { await peer.close(); await listener.close(); throw error }
        await peer.close()
        await listener.close()
    }

    /// Rejects invalid budgets/address and inclusive pre-expired bind contexts.
    @Test func invalidConfigurationAndDeadline() async {
        await #expect(throws: NIOServiceFailure.invalidConfiguration) {
            try await NIOHTTPIngress.bind(maximumConnections: 0, context: context())
        }
        await #expect(throws: NIOServiceFailure.invalidConfiguration) {
            try await NIOHTTPIngress.bind(maximumPendingRequests: 0, context: context())
        }
        await #expect(throws: NIOServiceFailure.invalidConfiguration) {
            try await NIOHTTPIngress.bind(maximumBodyBytes: 0, context: context())
        }
        await #expect(throws: NIOServiceFailure.invalidConfiguration) {
            try await NIOHTTPIngress.bind(maximumHeaderBytes: 0, context: context())
        }
        await #expect(throws: NIOServiceFailure.invalidAddress) {
            try await NIOHTTPIngress.bind(localAddress: .init(host: "localhost", port: 0), context: context())
        }
        let clock = ContinuousClock()
        await #expect(throws: TransportFailure.deadlineExceeded) {
            try await NIOHTTPIngress.bind(context: .init(clock: clock, deadline: clock.now))
        }
    }

    /// Rejects duplicate accepts and proves cancellation interrupts the pending accept.
    /// - Throws: Listener setup failures.
    @Test func concurrentAcceptAndCancellation() async throws {
        let listener = try await NIOHTTPIngress.bind(context: context())
        await withTaskGroup(of: Int.self) { group in
            for _ in 0..<2 {
                group.addTask {
                    do { _ = try await listener.accept(context: .init(clock: ContinuousClock())); return 0 }
                    catch TransportFailure.concurrentRead { return 1 }
                    catch is CancellationError { return 2 }
                    catch { return 3 }
                }
            }
            #expect(await group.next() == 1)
            group.cancelAll()
            #expect(await group.next() == 2)
        }
        await listener.close()
        #expect(try await listener.accept(context: context()) == nil)
    }

    /// Advances an injected deadline during acceptance, with no wall-clock sleep.
    /// - Throws: Listener setup, barrier registration or manual-clock failures.
    @Test func deadlineDuringAccept() async throws {
        guard #available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *) else { return }
        let listener = try await NIOHTTPIngress.bind(context: context())
        let registered = TestBarrier()
        let clock = ManualClock(onSleepScheduled: { registered.open() })
        let operation = Task {
            try await listener.accept(context: .init(clock: clock, deadline: clock.now.advanced(by: .seconds(1))))
        }
        try await registered.wait()
        try clock.advance(by: .seconds(1))
        do { _ = try await operation.value; Issue.record("Expected acceptance deadline") }
        catch { #expect(error as? TransportFailure == .deadlineExceeded) }
        #expect(clock.pendingSleepCount == 0)
        await listener.close()
    }

    /// Explicit responder closure releases an in-flight body and never reopens its slot.
    /// - Throws: Unexpected socket, barrier or body construction failures.
    @Test func responderCloseInterruptsBody() async throws {
        guard #available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *) else { return }
        let listener = try await NIOHTTPIngress.bind(context: context())
        let peer = try await IngressRawPeer.open(address: listener.localAddress,
                                                request: "GET / HTTP/1.1\r\nHost: localhost\r\n\r\n")
        do {
            let exchange = try #require(try await listener.accept(context: context()))
            let entered = TestBarrier()
            let release = TestBarrier(onWaitScheduled: { entered.open() })
            let source = try BodyStream(maximumChunkBytes: 1, next: {
                try await release.wait()
                return nil
            }, close: { release.open() })
            let operation = Task {
                try await exchange.responder.respond(.init(status: 200, body: source),
                                                       context: .init(clock: ContinuousClock()))
            }
            try await entered.wait()
            let duplicateBody = try body(Data([9]))
            await #expect(throws: NIOServiceFailure.duplicateResponse) {
                try await exchange.responder.respond(.init(status: 200, body: duplicateBody), context: context())
            }
            var duplicateIterator = duplicateBody.makeAsyncIterator()
            #expect(try await duplicateIterator.next() == nil)
            await exchange.responder.close()
            do { try await operation.value; Issue.record("Expected closed response failure") }
            catch { #expect(error is NIOServiceFailure || error is TransportFailure) }
            #expect(try await peer.response.get().isEmpty)
            await #expect(throws: NIOServiceFailure.duplicateResponse) {
                try await exchange.responder.respond(.init(status: 200), context: context())
            }
        } catch { await peer.close(); await listener.close(); throw error }
        await peer.close()
        await listener.close()
    }

    /// Cancellation or virtual deadline expiry interrupts response body production,
    /// closes the supplied body/socket and permanently consumes the response slot.
    /// - Parameter deadline: Whether to advance the injected clock or cancel the task.
    /// - Throws: Unexpected socket, barrier or manual-clock failures.
    @Test(arguments: [false, true])
    func responderCancellationAndDeadline(deadline: Bool) async throws {
        guard #available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *) else { return }
        let listener = try await NIOHTTPIngress.bind(context: context())
        let peer = try await IngressRawPeer.open(address: listener.localAddress,
                                                request: "GET / HTTP/1.1\r\nHost: localhost\r\n\r\n")
        do {
            let exchange = try #require(try await listener.accept(context: context()))
            let entered = TestBarrier()
            let registered = TestBarrier()
            let release = TestBarrier(onWaitScheduled: { entered.open() })
            let clock = ManualClock(onSleepScheduled: { registered.open() })
            let source = try BodyStream(maximumChunkBytes: 1, next: {
                try await release.wait()
                return nil
            }, close: { release.open() })
            let operation = Task {
                try await exchange.responder.respond(.init(status: 200, body: source),
                    context: .init(clock: clock, deadline: deadline ? clock.now.advanced(by: .seconds(1)) : nil))
            }
            try await entered.wait()
            if deadline { try await registered.wait(); try clock.advance(by: .seconds(1)) }
            else { operation.cancel() }
            do { try await operation.value; Issue.record("Expected response termination") }
            catch {
                if deadline { #expect(error as? TransportFailure == .deadlineExceeded) }
                else { #expect(error is CancellationError) }
            }
            #expect(clock.pendingSleepCount == 0)
            var iterator = source.makeAsyncIterator()
            #expect(try await iterator.next() == nil)
            #expect(try await peer.response.get().isEmpty)
            await #expect(throws: NIOServiceFailure.duplicateResponse) {
                try await exchange.responder.respond(.init(status: 200), context: context())
            }
        } catch { await peer.close(); await listener.close(); throw error }
        await peer.close()
        await listener.close()
    }
}

/// Coordinates the fixture body's single emitted chunk without duplicating payloads.
private actor NIOIngressFixtureFlag {
    var available = true

    /// Reserves the first producer invocation before suspension.
    /// - Returns: `true` once; subsequent calls indicate EOF.
    func take() -> Bool { defer { available = false }; return available }
}
