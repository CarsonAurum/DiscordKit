import Foundation
import Testing
import NIOCore
import NIOPosix
import NIOHTTP1
import NIOWebSocket
import NIOSSL

/// A closed connection before the expected bytes arrive is a failed probe.
private enum ProbeError: Error {
    case prematureClose
}

/// Captures a bounded response on one channel's event loop.
///
/// This fixture deliberately uses raw client bytes so the HTTP/WebSocket server
/// must interoperate with a peer that does not share its protocol encoder.
private final class ByteCollector: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer

    private let promise: EventLoopPromise<[UInt8]>
    private let suffix: [UInt8]
    private var bytes: [UInt8] = []
    private var completed = false
    private var deadline: Scheduled<Void>?

    /// Sets the completion boundary without touching a socket.
    ///
    /// - Parameters:
    ///   - promise: Promise resolved exactly once by this event-loop-confined handler.
    ///   - suffix: Nonempty terminal bytes expected from the local peer.
    init(promise: EventLoopPromise<[UInt8]>, suffix: [UInt8]) {
        self.promise = promise
        self.suffix = suffix
    }

    /// Installs a failure deadline so broken local peers cannot hang the harness.
    ///
    /// The timer only closes the channel; `channelInactive` owns error completion.
    /// It is not used to order successful test behavior.
    /// - Parameter context: Context bound to the channel's sole event loop.
    func handlerAdded(context: ChannelHandlerContext) {
        let channel = context.channel
        deadline = context.eventLoop.scheduleTask(in: .seconds(10)) {
            channel.close(promise: nil)
        }
    }

    /// Accumulates chunks and returns the exact wire response at the terminal bytes.
    ///
    /// Responses larger than 64 KiB are rejected by closing the fixture socket.
    /// - Parameters:
    ///   - context: Event-loop-confined context used to close malformed responses.
    ///   - data: Newly received bytes; arbitrary TCP fragmentation is accepted.
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        guard !completed else { return }
        bytes.append(contentsOf: unwrapInboundIn(data).readableBytesView)
        if bytes.count > 65_536 {
            context.close(promise: nil)
        } else if bytes.suffix(suffix.count).elementsEqual(suffix) {
            completed = true
            deadline?.cancel()
            promise.succeed(bytes)
        }
    }

    /// Resolves unfinished collection with the actual transport or TLS error.
    ///
    /// - Parameters:
    ///   - context: Context whose channel is closed after failure.
    ///   - error: Original error retained for the TLS rejection assertions.
    func errorCaught(context: ChannelHandlerContext, error: any Error) {
        if !completed {
            completed = true
            deadline?.cancel()
            promise.fail(error)
        }
        context.close(promise: nil)
    }

    /// Fails a truncated response and allows channel teardown to continue.
    /// - Parameter context: Event-loop-confined channel context.
    func channelInactive(context: ChannelHandlerContext) {
        if !completed {
            completed = true
            promise.fail(ProbeError.prematureClose)
        }
        deadline?.cancel()
        context.fireChannelInactive()
    }

    /// Cancels the safety timer when the pipeline releases the handler.
    /// - Parameter context: Removed context; no resources escape this callback.
    func handlerRemoved(context: ChannelHandlerContext) {
        deadline?.cancel()
    }
}

/// Returns the request method and URI through a real HTTP/1.1 response.
private final class HTTPResponder: ChannelInboundHandler {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private var response = ""

    /// Responds after the request ends, preserving a chunked request's boundaries.
    ///
    /// The peer is trusted loopback test code; this is not a production HTTP server.
    /// - Parameters:
    ///   - context: Channel context on which response writes are ordered.
    ///   - data: Decoded HTTP request part, including a possibly empty body.
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        switch unwrapInboundIn(data) {
        case .head(let head):
            response = "method=\(head.method.rawValue);uri=\(head.uri)"
        case .body:
            break
        case .end:
            let body = context.channel.allocator.buffer(string: response)
            let headers = HTTPHeaders([("Content-Length", String(body.readableBytes))])
            let head = HTTPResponseHead(version: .http1_1, status: .ok, headers: headers)
            context.write(wrapOutboundOut(.head(head)), promise: nil)
            context.write(wrapOutboundOut(.body(.byteBuffer(body))), promise: nil)
            context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
        }
    }
}

/// Echoes text frames after NIO has validated the HTTP upgrade and unmasked input.
private final class WebSocketEcho: ChannelInboundHandler {
    typealias InboundIn = WebSocketFrame
    typealias OutboundOut = WebSocketFrame

    /// Sends a text echo with the incoming FIN flag; other opcodes close the probe.
    /// - Parameters:
    ///   - context: Event-loop-confined upgraded WebSocket channel.
    ///   - data: Decoded frame whose unmasked payload becomes the response body.
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let frame = unwrapInboundIn(data)
        guard frame.opcode == .text else {
            context.close(promise: nil)
            return
        }
        let echo = WebSocketFrame(fin: frame.fin, opcode: .text, data: frame.unmaskedData)
        context.writeAndFlush(wrapOutboundOut(echo), promise: nil)
    }
}

/// Echoes each UDP datagram back to its source without merging message boundaries.
private final class DatagramEcho: ChannelInboundHandler {
    typealias InboundIn = AddressedEnvelope<ByteBuffer>
    typealias OutboundOut = AddressedEnvelope<ByteBuffer>

    /// Writes exactly one response envelope for each inbound datagram.
    /// - Parameters:
    ///   - context: Bound loopback UDP channel context.
    ///   - data: Envelope carrying the sender address and original payload bytes.
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        context.writeAndFlush(wrapOutboundOut(unwrapInboundIn(data)), promise: nil)
    }
}

/// Collects one UDP response and validates source-address preservation in the test.
private final class DatagramCollector: ChannelInboundHandler {
    typealias InboundIn = AddressedEnvelope<ByteBuffer>

    private let promise: EventLoopPromise<AddressedEnvelope<ByteBuffer>>
    private var completed = false
    private var deadline: Scheduled<Void>?

    /// Retains a promise resolved once by the next datagram or a channel failure.
    /// - Parameter promise: Completion on the event loop that owns this handler.
    init(promise: EventLoopPromise<AddressedEnvelope<ByteBuffer>>) {
        self.promise = promise
    }

    /// Adds a ten-second failure deadline that never drives a success assertion.
    /// - Parameter context: Bound channel context used only for event-loop scheduling.
    func handlerAdded(context: ChannelHandlerContext) {
        let channel = context.channel
        deadline = context.eventLoop.scheduleTask(in: .seconds(10)) {
            channel.close(promise: nil)
        }
    }

    /// Completes with the first envelope; subsequent datagrams cannot double-complete.
    /// - Parameters:
    ///   - context: Channel context; no extra writes are performed here.
    ///   - data: Original addressed envelope received from the loopback peer.
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        guard !completed else { return }
        completed = true
        deadline?.cancel()
        promise.succeed(unwrapInboundIn(data))
    }

    /// Fails a probe whose channel closes before returning a datagram.
    /// - Parameter context: Channel context forwarded after completing the failure.
    func channelInactive(context: ChannelHandlerContext) {
        if !completed {
            completed = true
            promise.fail(ProbeError.prematureClose)
        }
        deadline?.cancel()
        context.fireChannelInactive()
    }

    /// Releases the deadline task when its pipeline is destroyed.
    /// - Parameter context: Removed channel context, with no further side effects.
    func handlerRemoved(context: ChannelHandlerContext) {
        deadline?.cancel()
    }
}

/// Transport modes distinguish TLS success from trust and hostname failures.
private enum HTTPMode: String, CaseIterable, Sendable {
    case plaintext
    case trustedTLS
    case untrustedTLS
    case wrongHostname
}

/// Executes a probe with an owned event loop and cleans up on success or error.
///
/// Group shutdown closes remaining channels, including failures during setup.
/// No blocking future waits run on Swift's cooperative executor.
/// - Parameter body: Async probe body; must not retain channels beyond its return.
/// - Throws: The original body error, or shutdown failure after a successful body.
private func withEventLoopGroup(
    _ body: (MultiThreadedEventLoopGroup) async throws -> Void
) async throws {
    let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    do {
        try await body(group)
    } catch {
        try? await group.shutdownGracefully()
        throw error
    }
    try await group.shutdownGracefully()
}

/// Verifies real HTTP bytes over plaintext or certificate-validated loopback TLS.
///
/// A self-signed, public fixture certificate is explicitly trusted only in the
/// positive case. Negative cases independently reject unknown roots and a wrong
/// hostname. Each invocation owns fresh ephemeral ports and its event loop.
/// - Parameter mode: Plaintext success, trusted TLS success, or TLS rejection case.
/// - Throws: Resource setup, connection, decoding, or unexpected transport failures.
@Test(arguments: HTTPMode.allCases)
private func httpAndTLSLoopback(mode: HTTPMode) async throws {
    try await withEventLoopGroup { group in
        let resources = try #require(Bundle.module.url(forResource: "Resources", withExtension: nil))
        let certificates = try NIOSSLCertificate.fromPEMFile(
            resources.appendingPathComponent("localhost-cert.pem").path
        )
        let certificate = try #require(certificates.first)
        let key = try NIOSSLPrivateKey(
            file: resources.appendingPathComponent("localhost-key.pem").path,
            format: .pem
        )
        let serverContext = try NIOSSLContext(configuration: .makeServerConfiguration(
            certificateChain: [.certificate(certificate)], privateKey: .privateKey(key)
        ))
        var clientConfiguration = TLSConfiguration.makeClientConfiguration()
        if mode != .untrustedTLS {
            clientConfiguration.trustRoots = .certificates([certificate])
        }
        let clientContext = try NIOSSLContext(configuration: clientConfiguration)
        let server = try await ServerBootstrap(group: group)
            .childChannelInitializer { channel in
                do {
                    if mode != .plaintext {
                        try channel.pipeline.syncOperations.addHandler(NIOSSLServerHandler(context: serverContext))
                    }
                    return channel.pipeline.configureHTTPServerPipeline().flatMapThrowing {
                        try channel.pipeline.syncOperations.addHandler(HTTPResponder())
                    }
                } catch {
                    return channel.eventLoop.makeFailedFuture(error)
                }
            }
            .bind(host: "127.0.0.1", port: 0).get()
        let address = try #require(server.localAddress)
        let response = group.next().makePromise(of: [UInt8].self)
        let expectedBody = "method=GET;uri=/probe?value=1"
        let client = try await ClientBootstrap(group: group)
            .connectTimeout(.seconds(5))
            .channelInitializer { channel in
                do {
                    if mode != .plaintext {
                        let hostname = mode == .wrongHostname ? "wrong.example" : "localhost"
                        try channel.pipeline.syncOperations.addHandler(
                            NIOSSLClientHandler(context: clientContext, serverHostname: hostname)
                        )
                    }
                    try channel.pipeline.syncOperations.addHandler(
                        ByteCollector(promise: response, suffix: Array(expectedBody.utf8))
                    )
                    return channel.eventLoop.makeSucceededFuture(())
                } catch {
                    return channel.eventLoop.makeFailedFuture(error)
                }
            }
            .connect(to: address).get()
        let request = client.allocator.buffer(string: "GET /probe?value=1 HTTP/1.1\r\nHost: localhost\r\n\r\n")
        // TLS may reject the peer before this write completes. The read promise
        // retains the original handshake error for the negative-case assertion.
        try? await client.writeAndFlush(request).get()
        if mode == .untrustedTLS || mode == .wrongHostname {
            do {
                _ = try await response.futureResult.get()
                Issue.record("TLS unexpectedly accepted an untrusted certificate or wrong hostname")
            } catch {
                if mode == .wrongHostname {
                    #expect(error as? NIOSSLExtraError == .failedToValidateHostname)
                } else if case .handshakeFailed = error as? NIOSSLError {
                    // An ordinary channel close or deadline is insufficient:
                    // the untrusted-root case must fail in the TLS handshake.
                } else {
                    Issue.record("Expected a TLS handshake failure, received \(error)")
                }
            }
        } else {
            let bytes = try await response.futureResult.get()
            let wire = String(decoding: bytes, as: UTF8.self)
            #expect(wire.hasPrefix("HTTP/1.1 200 OK\r\n"))
            #expect(wire.hasSuffix("\r\n\r\n" + expectedBody))
        }
        try? await client.close().get()
        try await server.close().get()
    }
}

/// Verifies an RFC 6455 upgrade and masked client text frame over real TCP.
///
/// The raw client uses the published RFC handshake key and a four-byte mask;
/// NIO must return the standard accept digest and an unmasked `ping` echo.
/// - Throws: Port binding, upgrade, collection, or channel cleanup errors.
@Test
private func webSocketLoopback() async throws {
    try await withEventLoopGroup { group in
        let server = try await ServerBootstrap(group: group)
            .childChannelInitializer { channel in
                let upgrader = NIOWebSocketServerUpgrader(
                    shouldUpgrade: { channel, _ in channel.eventLoop.makeSucceededFuture(HTTPHeaders()) },
                    upgradePipelineHandler: { channel, _ in
                        channel.eventLoop.makeCompletedFuture {
                            try channel.pipeline.syncOperations.addHandler(WebSocketEcho())
                        }
                    }
                )
                return channel.pipeline.configureHTTPServerPipeline(
                    withServerUpgrade: (upgraders: [upgrader], completionHandler: { _ in })
                )
            }
            .bind(host: "127.0.0.1", port: 0).get()
        let address = try #require(server.localAddress)
        let response = group.next().makePromise(of: [UInt8].self)
        let expectedFrame: [UInt8] = [0x81, 0x04, 0x70, 0x69, 0x6E, 0x67]
        let client = try await ClientBootstrap(group: group)
            .connectTimeout(.seconds(5))
            .channelInitializer { channel in
                channel.eventLoop.makeCompletedFuture {
                    try channel.pipeline.syncOperations.addHandler(ByteCollector(promise: response, suffix: expectedFrame))
                }
            }
            .connect(to: address).get()
        var request = client.allocator.buffer(string:
            "GET /probe HTTP/1.1\r\nHost: localhost\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
            + "Sec-WebSocket-Version: 13\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n\r\n"
        )
        request.writeBytes([0x81, 0x84, 1, 2, 3, 4, 0x70 ^ 1, 0x69 ^ 2, 0x6E ^ 3, 0x67 ^ 4])
        try await client.writeAndFlush(request).get()
        let bytes = try await response.futureResult.get()
        let headers = String(decoding: bytes.dropLast(expectedFrame.count), as: UTF8.self)
        #expect(headers.hasPrefix("HTTP/1.1 101 Switching Protocols\r\n"))
        #expect(headers.lowercased().contains("sec-websocket-accept: s3pplmbitxaq9kygzzhzrbk+xoo="))
        #expect(bytes.suffix(expectedFrame.count).elementsEqual(expectedFrame))
        try await client.close().get()
        try await server.close().get()
    }
}

/// Verifies IPv4 UDP message bytes and source addresses on ephemeral loopback ports.
///
/// Empty and binary payloads cover legal zero-length datagrams and byte values that
/// cannot be interpreted as UTF-8. No Discord request or external socket is used.
/// - Parameter payload: Exact UDP bytes expected to survive the echoed round trip.
/// - Throws: Socket setup, send, collection, or channel cleanup errors.
@Test(arguments: [[UInt8](), [0, 1, 127, 128, 255]])
private func datagramLoopback(payload: [UInt8]) async throws {
    try await withEventLoopGroup { group in
        let server = try await DatagramBootstrap(group: group)
            .channelInitializer { channel in
                channel.eventLoop.makeCompletedFuture {
                    try channel.pipeline.syncOperations.addHandler(DatagramEcho())
                }
            }
            .bind(host: "127.0.0.1", port: 0).get()
        let address = try #require(server.localAddress)
        let response = group.next().makePromise(of: AddressedEnvelope<ByteBuffer>.self)
        let client = try await DatagramBootstrap(group: group)
            .channelInitializer { channel in
                channel.eventLoop.makeCompletedFuture {
                    try channel.pipeline.syncOperations.addHandler(DatagramCollector(promise: response))
                }
            }
            .bind(host: "127.0.0.1", port: 0).get()
        let bytes = client.allocator.buffer(bytes: payload)
        try await client.writeAndFlush(AddressedEnvelope(remoteAddress: address, data: bytes)).get()
        let envelope = try await response.futureResult.get()
        #expect(envelope.remoteAddress == address)
        #expect(Array(envelope.data.readableBytesView) == payload)
        try await client.close().get()
        try await server.close().get()
    }
}
