import Foundation
import Testing
import DiscordTransport
import DiscordFoundationTransport
import DiscordTestSupport
@testable import DiscordNIOTransport
import NIOCore
import NIOPosix
import NIOHTTP1
import NIOConcurrencyHelpers
import NIOSSL

/// Local HTTP/HTTPS peer with controlled malformed, delayed and bounded responses.
private struct HTTPTestPeer: Sendable {
    let group: MultiThreadedEventLoopGroup
    let channel: any Channel
    let requests: NIOLockedValueBox<Int>
    let arrived: EventLoopPromise<Void>
    let arrivalCompleted: NIOLockedValueBox<Bool>

    /// Opens an ephemeral IPv4 loopback listener, optionally using the public test key.
    /// - Parameter tls: Whether to install TLS with the committed localhost fixture.
    /// - Returns: Owned local peer; caller must await close on every test exit path.
    /// - Throws: Fixture decoding, bind, TLS or pipeline construction failures.
    static func open(tls: Bool = false) async throws -> HTTPTestPeer {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let requests = NIOLockedValueBox(0)
        let arrived = group.next().makePromise(of: Void.self)
        let arrivalCompleted = NIOLockedValueBox(false)
        let ssl: NIOSSLContext?
        if tls {
            let directory = Bundle.module.resourceURL!.appendingPathComponent("Resources")
            let certificate = try NIOSSLCertificate.fromPEMFile(directory.appendingPathComponent("localhost-cert.pem").path)
            let key = try NIOSSLPrivateKey(file: directory.appendingPathComponent("localhost-key.pem").path, format: .pem)
            ssl = try NIOSSLContext(configuration: .makeServerConfiguration(certificateChain: certificate.map { .certificate($0) }, privateKey: .privateKey(key)))
        } else { ssl = nil }
        do {
            let channel = try await ServerBootstrap(group: group).childChannelInitializer { channel in
                channel.eventLoop.makeCompletedFuture {
                    if let ssl { try channel.pipeline.syncOperations.addHandler(NIOSSLServerHandler(context: ssl)) }
                    // Fixtures supply their own framing. Preserve legal 304
                    // representation metadata that NIO's automatic framing strips.
                    var encoder = HTTPResponseEncoder.Configuration()
                    encoder.automaticallySetFramingHeaders = false
                    try channel.pipeline.syncOperations.configureHTTPServerPipeline(withEncoderConfiguration: encoder)
                    try channel.pipeline.syncOperations.addHandler(HTTPTestHandler(requests: requests, arrived: arrived, arrivalCompleted: arrivalCompleted))
                }
            }.bind(host: "127.0.0.1", port: 0).get()
            return HTTPTestPeer(group: group, channel: channel, requests: requests, arrived: arrived, arrivalCompleted: arrivalCompleted)
        } catch { try? await group.shutdownGracefully(); throw error }
    }

    /// Builds a valid loopback origin with a caller-selected request target.
    /// - Parameters:
    ///   - path: Test route including optional query; default /ok.
    ///   - tls: Selects HTTPS with localhost hostname for positive certificate tests.
    /// - Returns: URL to this listener's ephemeral port.
    func url(_ path: String = "/ok", tls: Bool = false) -> URL {
        URL(string: "\(tls ? "https://localhost" : "http://127.0.0.1"):\(channel.localAddress!.port!)\(path)")!
    }

    /// Closes the listener and all child sockets through event-loop group shutdown.
    /// Returning establishes no fixture socket/thread remains owned by this test.
    func close() async {
        if !arrivalCompleted.withLockedValue({ old in let previous = old; old = true; return previous }) { arrived.succeed(()) }
        try? await channel.close().get(); try? await group.shutdownGracefully()
    }
}

/// Deterministic responder that never contacts an external service.
private final class HTTPTestHandler: ChannelInboundHandler {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart
    let requests: NIOLockedValueBox<Int>
    let arrived: EventLoopPromise<Void>
    let arrivalCompleted: NIOLockedValueBox<Bool>
    var path = ""
    var method = HTTPMethod.GET
    var body = Data()

    /// Stores peer-owned observations and the first-request barrier.
    /// - Parameters:
    ///   - requests: Locked count safe for async test assertions.
    ///   - arrived: Completed once when the /hold request reaches the wire.
    ///   - arrivalCompleted: Shared exactly-once reservation including teardown.
    init(requests: NIOLockedValueBox<Int>, arrived: EventLoopPromise<Void>, arrivalCompleted: NIOLockedValueBox<Bool>) {
        self.requests = requests; self.arrived = arrived; self.arrivalCompleted = arrivalCompleted
    }

    /// Echoes body/query, returns redirects, emits bodyless HEAD/304 metadata and
    /// holds selected headers or bodies until cancellation. All routes remain local fixtures.
    /// - Parameters:
    ///   - context: Sole event-loop owner of parser and outbound write ordering.
    ///   - data: Decoded request part, including chunked upload data.
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        switch unwrapInboundIn(data) {
        case .head(let head): path = head.uri; method = head.method; body = Data(); requests.withLockedValue { $0 += 1 }
        case .body(let bytes): body.append(contentsOf: bytes.readableBytesView)
        case .end:
            if path == "/hold" {
                if !arrivalCompleted.withLockedValue({ old in let previous = old; old = true; return previous }) { arrived.succeed(()) }; return
            }
            let payload = path.hasPrefix("/echo") ? body : Data("hello\0world".utf8)
            if path == "/info" {
                context.write(wrapOutboundOut(.head(HTTPResponseHead(version: .http1_1, status: .continue))), promise: nil)
            }
            let status: HTTPResponseStatus = path == "/not-modified" ? .notModified : path == "/redirect" ? .temporaryRedirect : .ok
            let length = path == "/metadata" || path == "/not-modified" ? 1_000_000_000 : path == "/large" ? 100_000 : payload.count
            var headers = HTTPHeaders([("Content-Length", String(length)),
                                       ("X-Duplicate", "one"), ("X-Duplicate", "two")])
            if path == "/redirect" { headers.add(name: "Location", value: "/ok") }
            context.write(wrapOutboundOut(.head(HTTPResponseHead(version: .http1_1, status: status, headers: headers))), promise: nil)
            if path == "/hold-body" { context.flush(); return }
            if method != .HEAD, status != .notModified {
                var bytes = context.channel.allocator.buffer(capacity: payload.count); bytes.writeBytes(payload)
                context.write(wrapOutboundOut(.body(.byteBuffer(bytes))), promise: nil)
            }
            context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
        }
    }
}

/// HTTP/1.1 adapter conformance with real loopback sockets and injected deadlines.
@Suite struct HTTPAdapterTests {
    /// Consumes a caller-owned body and verifies every emitted chunk fits its budget.
    /// - Parameters:
    ///   - response: Response whose body ownership transfers into this helper.
    ///   - bound: Positive expected output chunk ceiling.
    /// - Returns: Concatenated body, empty when absent.
    /// - Throws: Body producer errors; cleanup runs on both success and failure.
    private func collect(_ response: HTTPResponse, bound: Int = 16_384) async throws -> Data {
        guard let body = response.body else { return Data() }
        do {
            var output = Data()
            for try await chunk in body { #expect(chunk.count <= bound); output.append(chunk) }
            await body.close(); return output
        } catch { await body.close(); throw error }
    }

    /// Confirms exact body bytes, duplicate headers, informational response handling
    /// and pool reuse over repeated exchanges without leaked active reservations.
    /// - Parameter route: Valid path selecting ordinary or informational response.
    /// - Throws: Bind, execute or body-read failure.
    @Test(arguments: ["/ok", "/info"])
    func roundTripAndReuse(_ route: String) async throws {
        let peer = try await HTTPTestPeer.open()
        let transport = try NIOHTTPTransport(configuration: NIOHTTPConfiguration(chunkBytes: 4))
        do {
            for _ in 0..<3 {
                let response = try await transport.execute(HTTPRequest(method: "GET", url: peer.url(route)), context: TransportContext(clock: ContinuousClock(), deadline: ContinuousClock().now.advanced(by: .seconds(5))))
                #expect(response.status == 200)
                #expect(response.headers.filter { $0.name.lowercased() == "x-duplicate" }.map(\.value) == ["one", "two"])
                #expect(try await collect(response, bound: 4) == Data("hello\0world".utf8))
                let counts = await transport.connectionCounts()
                #expect(counts.active == 0); #expect(counts.idle == 1)
            }
            #expect(peer.requests.withLockedValue { $0 } == 3)
        } catch { await transport.close(); await peer.close(); throw error }
        await transport.close(); await transport.close(); await peer.close()
        let counts = await transport.connectionCounts(); #expect(counts.active == 0 && counts.idle == 0)
    }

    /// Verifies send-once uploads, zero-length chunks and no automatic redirect replay.
    /// - Throws: Local transport/fixture failure or an unexpected byte mismatch.
    @Test func uploadAndRedirect() async throws {
        let peer = try await HTTPTestPeer.open()
        let transport = try NIOHTTPTransport(configuration: NIOHTTPConfiguration())
        let source = HTTPUploadSource()
        let body = try BodyStream(maximumChunkBytes: 3, next: { await source.next() }, close: { await source.close() })
        do {
            let response = try await transport.execute(HTTPRequest(method: "POST", url: peer.url("/echo?q=secret"), body: body), context: TransportContext(clock: ContinuousClock(), deadline: ContinuousClock().now.advanced(by: .seconds(5))))
            #expect(try await collect(response) == Data([0, 128, 255]))
            #expect(await source.closeCount == 1)
            let redirect = try await transport.execute(HTTPRequest(method: "GET", url: peer.url("/redirect"), headers: [HTTPHeader(name: "Authorization", value: "sensitive")]), context: TransportContext(clock: ContinuousClock(), deadline: ContinuousClock().now.advanced(by: .seconds(5))))
            #expect(redirect.status == 307); await redirect.body?.close()
            #expect(peer.requests.withLockedValue { $0 } == 2)
        } catch { await transport.close(); await peer.close(); throw error }
        await transport.close(); await peer.close()
    }

    /// Exercises total/per-origin overload and response ownership; closing an unread
    /// body releases admission so a subsequent request succeeds.
    /// - Throws: Fixture/transport failures.
    @Test func boundedAdmission() async throws {
        let peer = try await HTTPTestPeer.open()
        let transport = try NIOHTTPTransport(configuration: NIOHTTPConfiguration(maximumConnections: 1, maximumConnectionsPerOrigin: 1))
        do {
            let first = try await transport.execute(HTTPRequest(method: "GET", url: peer.url()), context: TransportContext(clock: ContinuousClock(), deadline: ContinuousClock().now.advanced(by: .seconds(5))))
            await #expect(throws: NIOAdapterFailure.capacityExceeded) {
                try await transport.execute(HTTPRequest(method: "GET", url: peer.url()), context: TransportContext(clock: ContinuousClock(), deadline: ContinuousClock().now.advanced(by: .seconds(5))))
            }
            await first.body?.close()
            let second = try await transport.execute(HTTPRequest(method: "GET", url: peer.url()), context: TransportContext(clock: ContinuousClock(), deadline: ContinuousClock().now.advanced(by: .seconds(5))))
            #expect(try await collect(second) == Data("hello\0world".utf8))
        } catch { await transport.close(); await peer.close(); throw error }
        await transport.close(); await peer.close()
    }

    /// Parent shutdown closes a retained unread stream before stopping its event
    /// loop, including concurrent body/parent close callers. Later reads return EOF
    /// and repeated closes finish without registering callbacks on a stopped loop.
    /// - Parameter concurrentBodyClose: Whether body closure races the first parent close.
    /// - Throws: Local setup, execution or unexpected retained-body read failures.
    @Test(arguments: [false, true])
    func retainedResponseAfterParentClose(_ concurrentBodyClose: Bool) async throws {
        let peer = try await HTTPTestPeer.open()
        let transport = try NIOHTTPTransport(configuration: NIOHTTPConfiguration())
        do {
            let response = try await transport.execute(HTTPRequest(method: "GET", url: peer.url()),
                context: TransportContext(clock: ContinuousClock(), deadline: ContinuousClock().now.advanced(by: .seconds(5))))
            let body = try #require(response.body)
            if concurrentBodyClose {
                async let first: Void = transport.close()
                async let second: Void = body.close()
                async let third: Void = transport.close()
                async let fourth: Void = body.close()
                _ = await (first, second, third, fourth)
            } else { await transport.close() }
            var iterator = body.makeAsyncIterator()
            #expect(try await iterator.next() == nil)
            #expect(try await iterator.next() == nil)
            async let parentAgain: Void = transport.close()
            async let bodyAgain: Void = body.close()
            _ = await (parentAgain, bodyAgain)
            let counts = await transport.connectionCounts()
            #expect(counts.active == 0 && counts.idle == 0)
            #expect(peer.requests.withLockedValue { $0 } == 1)
        } catch { await transport.close(); await peer.close(); throw error }
        await transport.close(); await peer.close()
    }

    /// A registered response-body operation remains owned until its native read
    /// ends. A virtual-clock registration barrier starts shutdown, cancellation or
    /// expiration without sleeps; every path releases its slot and later reads yield EOF.
    /// - Parameter termination: Parent close, caller cancellation or clock expiration.
    /// - Throws: Fixture setup, deterministic barrier or unexpected read failures.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: ["close", "cancel", "deadline"])
    func pendingBodyReadTermination(_ termination: String) async throws {
        let peer = try await HTTPTestPeer.open()
        let transport = try NIOHTTPTransport(configuration: NIOHTTPConfiguration())
        let reading = TestBarrier()
        let registrations = NIOLockedValueBox(0)
        let clock = ManualClock(onSleepScheduled: {
            if registrations.withLockedValue({ count in count += 1; return count }) == 2 { reading.open() }
        })
        do {
            let response = try await transport.execute(HTTPRequest(method: "GET", url: peer.url("/hold-body")),
                context: TransportContext(clock: clock, deadline: clock.now.advanced(by: .seconds(60))))
            let body = try #require(response.body)
            let operation = Task {
                var iterator = body.makeAsyncIterator()
                return try await iterator.next()
            }
            try await reading.wait()
            if termination == "close" {
                async let first: Void = transport.close()
                async let second: Void = transport.close()
                _ = await (first, second)
            } else if termination == "cancel" { operation.cancel() }
            else { try clock.advance(by: .seconds(60)) }
            do {
                let value = try await operation.value
                #expect(termination == "close")
                #expect(value == nil)
            } catch {
                if termination == "cancel" { #expect(error is CancellationError) }
                else if termination == "deadline" { #expect(error as? TransportFailure == .deadlineExceeded) }
                else { throw error }
            }
            #expect(clock.pendingSleepCount == 0)
            var iterator = body.makeAsyncIterator()
            #expect(try await iterator.next() == nil)
            await body.close()
            let counts = await transport.connectionCounts()
            #expect(counts.active == 0 && counts.idle == 0)
        } catch { await transport.close(); await peer.close(); throw error }
        await transport.close(); await peer.close()
    }

    /// Parent shutdown joins a pending header exchange before releasing its native
    /// event loop. The uncancelled caller observes closure and retains no pool slot.
    /// - Throws: Fixture setup or unexpected exchange completion failures.
    @Test func closePendingHeaderRead() async throws {
        let peer = try await HTTPTestPeer.open()
        let transport = try NIOHTTPTransport(configuration: NIOHTTPConfiguration())
        let operation = Task {
            try await transport.execute(HTTPRequest(method: "GET", url: peer.url("/hold")),
                context: TransportContext(clock: ContinuousClock()))
        }
        try await peer.arrived.futureResult.get()
        async let first: Void = transport.close()
        async let second: Void = transport.close()
        _ = await (first, second)
        await #expect(throws: TransportFailure.closed) { try await operation.value }
        let counts = await transport.connectionCounts()
        #expect(counts.active == 0 && counts.idle == 0)
        await transport.close(); await peer.close()
    }

    /// Uses a virtual clock/barrier to terminate a real pending header read without
    /// sleeps, and proves failed exchanges return all active resource slots.
    /// - Parameter deadline: Whether virtual expiration or task cancellation wins.
    /// - Throws: Fixture setup or cancellation assertion failure.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [false, true])
    func cancelPendingRead(_ deadline: Bool) async throws {
        let peer = try await HTTPTestPeer.open()
        let transport = try NIOHTTPTransport(configuration: NIOHTTPConfiguration())
        let clock = ManualClock()
        let task = Task {
            try await transport.execute(HTTPRequest(method: "GET", url: peer.url("/hold")), context: TransportContext(clock: clock, deadline: deadline ? clock.now.advanced(by: .seconds(1)) : nil))
        }
        try await peer.arrived.futureResult.get()
        if deadline { try clock.advance(by: .seconds(1)) } else { task.cancel() }
        do { _ = try await task.value; Issue.record("Pending read unexpectedly succeeded") }
        catch {
            if deadline { #expect(error as? TransportFailure == .deadlineExceeded) }
            else { #expect(error is CancellationError) }
        }
        let counts = await transport.connectionCounts(); #expect(counts.active == 0)
        await transport.close(); await peer.close()
    }

    /// Ensures known oversized bodies fail before ownership transfer and oversized
    /// uploads close their single-use source while sending no bytes.
    /// - Throws: Local setup/transport failures.
    @Test func byteLimits() async throws {
        let peer = try await HTTPTestPeer.open()
        let transport = try NIOHTTPTransport(configuration: NIOHTTPConfiguration(maximumRequestBytes: 2, maximumResponseBytes: 16))
        do {
            await #expect(throws: NIOAdapterFailure.responseTooLarge) {
                try await transport.execute(HTTPRequest(method: "GET", url: peer.url("/large")), context: TransportContext(clock: ContinuousClock(), deadline: ContinuousClock().now.advanced(by: .seconds(5))))
            }
            let source = HTTPUploadSource()
            let body = try BodyStream(maximumChunkBytes: 3, next: { await source.next() }, close: { await source.close() })
            await #expect(throws: NIOAdapterFailure.requestTooLarge) {
                try await transport.execute(HTTPRequest(method: "POST", url: peer.url("/echo"), body: body), context: TransportContext(clock: ContinuousClock(), deadline: ContinuousClock().now.advanced(by: .seconds(5))))
            }
            #expect(await source.closeCount == 1)
            #expect(peer.requests.withLockedValue { $0 } == 1)
        }
        await transport.close(); await peer.close()
    }

    /// Accepts HEAD/304 representation length metadata beyond the body byte cap,
    /// preserves that header, emits an empty body and safely reuses the connection.
    /// The following ordinary GET still enforces the same finite response budget.
    /// - Parameters:
    ///   - method: HEAD or GET, selecting bodyless method/status semantics.
    ///   - route: Matching fixture path advertising a one-billion-byte representation.
    ///   - status: Expected final HTTP status, 200 for HEAD or 304 for GET.
    /// - Throws: Fixture, response parsing or unexpected body failures.
    @Test(arguments: [("HEAD", "/metadata", 200), ("GET", "/not-modified", 304)])
    func bodylessLengthMetadata(_ method: String, _ route: String, _ status: Int) async throws {
        let peer = try await HTTPTestPeer.open()
        let transport = try NIOHTTPTransport(configuration: NIOHTTPConfiguration(maximumResponseBytes: 16))
        do {
            let clock = ContinuousClock()
            let context = TransportContext(clock: clock, deadline: clock.now.advanced(by: .seconds(5)))
            let response = try await transport.execute(HTTPRequest(method: method, url: peer.url(route)), context: context)
            #expect(response.status == status)
            #expect(response.headers.contains { $0.name.lowercased() == "content-length" && $0.value == "1000000000" })
            #expect(try await collect(response).isEmpty)
            let counts = await transport.connectionCounts()
            #expect(counts.active == 0 && counts.idle == 1)
            let ordinary = try await transport.execute(HTTPRequest(method: "GET", url: peer.url()), context: context)
            #expect(try await collect(ordinary) == Data("hello\0world".utf8))
            await #expect(throws: NIOAdapterFailure.responseTooLarge) {
                try await transport.execute(HTTPRequest(method: "GET", url: peer.url("/large")), context: context)
            }
            #expect(peer.requests.withLockedValue { $0 } == 3)
        } catch { await transport.close(); await peer.close(); throw error }
        await transport.close(); await peer.close()
    }

    /// Suspends a producer before any HTTP bytes are sent, then terminates its
    /// exchange by pool close, cancellation or a virtual deadline. Producer cleanup
    /// must unblock the pull exactly once, with zero retained slots or wire requests.
    /// - Parameter termination: `close`, `cancel` or `deadline`, each using barriers
    ///   rather than timing-dependent sleeps. Older hosts skip unavailable test clocks.
    /// - Throws: Fixture setup, barrier or unexpected operation completion failure.
    @Test(arguments: ["close", "cancel", "deadline"])
    func pendingUploadTermination(_ termination: String) async throws {
        guard #available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *) else { return }
        let peer = try await HTTPTestPeer.open()
        let transport = try NIOHTTPTransport(configuration: NIOHTTPConfiguration())
        let pulling = TestBarrier()
        let unblock = TestBarrier(onWaitScheduled: { pulling.open() })
        let closeCount = NIOLockedValueBox(0)
        let body = try BodyStream(maximumChunkBytes: 1, next: {
            try await unblock.wait()
            return nil
        }, close: {
            closeCount.withLockedValue { $0 += 1 }
            unblock.open()
        })
        let clock = ManualClock()
        let operation = Task {
            try await transport.execute(HTTPRequest(method: "POST", url: peer.url("/echo"), body: body),
                                        context: TransportContext(clock: clock, deadline: termination == "deadline" ? clock.now.advanced(by: .seconds(1)) : nil))
        }
        try await pulling.wait()
        if termination == "close" { await transport.close() }
        else if termination == "cancel" { operation.cancel() }
        else { try clock.advance(by: .seconds(1)) }
        do {
            let response = try await operation.value
            await response.body?.close()
            Issue.record("Terminated upload unexpectedly returned a response")
        } catch {
            if termination == "close" { #expect(error as? TransportFailure == .closed) }
            else if termination == "cancel" { #expect(error is CancellationError) }
            else { #expect(error as? TransportFailure == .deadlineExceeded) }
        }
        #expect(closeCount.withLockedValue { $0 } == 1)
        #expect(clock.pendingSleepCount == 0)
        var iterator = body.makeAsyncIterator()
        #expect(try await iterator.next() == nil)
        #expect(peer.requests.withLockedValue { $0 } == 0)
        let counts = await transport.connectionCounts()
        #expect(counts.active == 0 && counts.idle == 0)
        await transport.close(); await transport.close(); await peer.close()
    }

    /// Qualifies full trust-chain/hostname validation using a local public test cert.
    /// - Parameters:
    ///   - trusted: Whether the explicit test root is installed.
    ///   - hostname: Whether the requested host matches the localhost certificate.
    /// - Throws: Fixture or positive TLS exchange failure.
    @Test(arguments: [(true, true), (false, true), (true, false)])
    func tlsVerification(_ trusted: Bool, _ hostname: Bool) async throws {
        let peer = try await HTTPTestPeer.open(tls: true)
        let bytes = try Data(contentsOf: Bundle.module.resourceURL!.appendingPathComponent("Resources/localhost-cert.pem"))
        let policy = try TLSPolicy(additionalTrustRootsPEM: trusted ? Array(bytes) : nil)
        let transport = try NIOHTTPTransport(configuration: NIOHTTPConfiguration(), tls: policy)
        let url = hostname ? peer.url(tls: true) : URL(string: "https://127.0.0.1:\(peer.channel.localAddress!.port!)/ok")!
        do {
            let response = try await transport.execute(HTTPRequest(method: "GET", url: url), context: TransportContext(clock: ContinuousClock(), deadline: ContinuousClock().now.advanced(by: .seconds(5))))
            #expect(trusted && hostname)
            #expect(try await collect(response) == Data("hello\0world".utf8))
        } catch {
            if trusted && hostname { await transport.close(); await peer.close(); throw error }
            #expect(error as? NIOAdapterFailure == .connectionFailed)
        }
        await transport.close(); await peer.close()
    }

    /// Rejects request injection, unsupported schemes, embedded credentials and
    /// framing overrides before network activity, preserving redacted failures.
    /// - Parameter input: Malformed request shape.
    /// - Throws: Adapter setup errors.
    @Test(arguments: ["scheme", "userinfo", "fragment", "method", "name", "value", "framing", "hostCRLF", "hostNUL"])
    func requestValidation(_ input: String) async throws {
        let transport = try NIOHTTPTransport(configuration: NIOHTTPConfiguration())
        let url = URL(string: input == "scheme" ? "file:///tmp/a" : input == "userinfo" ? "https://user:secret@example.com" : input == "fragment" ? "https://example.com/#secret" : input == "hostCRLF" ? "http://foo%0d%0abar/" : input == "hostNUL" ? "http://foo%00bar/" : "http://127.0.0.1:1/")!
        let headers: [HTTPHeader] = input == "name" ? [HTTPHeader(name: "Bad Name", value: "x")] : input == "value" ? [HTTPHeader(name: "X-Key", value: "secret\r\nInjected: true")] : input == "framing" ? [HTTPHeader(name: "Content-Length", value: "0")] : []
        await #expect(throws: NIOAdapterFailure.invalidRequest) {
            try await transport.execute(HTTPRequest(method: input == "method" ? "BAD METHOD" : "GET", url: url, headers: headers), context: TransportContext(clock: ContinuousClock(), deadline: ContinuousClock().now.advanced(by: .seconds(5))))
        }
        let counts = await transport.connectionCounts(); #expect(counts.active == 0 && counts.idle == 0)
        await transport.close()
    }

    /// Rejects invalid numeric configurations and malformed custom trust roots.
    /// No invalid configuration allocates an event loop or opens a network socket.
    @Test func configurationValidation() {
        #expect(throws: TransportFailure.invalidLimit) { try NIOHTTPConfiguration(maximumConnections: 0) }
        #expect(throws: TransportFailure.invalidLimit) { try NIOHTTPConfiguration(maximumConnectionsPerOrigin: 33) }
        #expect(throws: TransportFailure.invalidLimit) { try NIOHTTPConfiguration(maximumRequestBytes: -1) }
        #expect(throws: TransportFailure.invalidLimit) { try NIOHTTPConfiguration(maximumResponseBytes: -1) }
        #expect(throws: TransportFailure.invalidLimit) { try NIOHTTPConfiguration(maximumHeaderBytes: 0) }
        #expect(throws: TransportFailure.invalidLimit) { try NIOHTTPConfiguration(chunkBytes: 0) }
        #expect(throws: NIOAdapterFailure.connectionFailed) { try TLSPolicy(additionalTrustRootsPEM: [1, 2, 3]) }
    }
}

/// A finite producer with empty and binary chunks plus observable exactly-once close.
private actor HTTPUploadSource {
    var chunks = [Data(), Data([0, 128, 255])]
    var closeCount = 0

    /// Returns one chunk per demand without timers or external I/O.
    /// - Returns: Next chunk, including empty first chunk, or nil at EOF.
    func next() -> Data? { chunks.isEmpty ? nil : chunks.removeFirst() }

    /// Records source release so producer errors and successful EOF can be asserted.
    func close() { closeCount += 1 }
}

/// Reuses the same observable HTTP contract against every published client backend.
private enum HTTPBackend: CaseIterable, Sendable {
    case nio
    #if canImport(Darwin)
    case foundation
    #endif

    /// Creates a backend with identical caller-visible 16 KiB chunk limits.
    /// - Returns: Owned send-once transport, requiring explicit close after the test.
    /// - Throws: Invalid configuration or TLS initialization errors.
    func make() throws -> any HTTPTransport & TransportResource {
        switch self {
        case .nio: try NIOHTTPTransport(configuration: NIOHTTPConfiguration())
        #if canImport(Darwin)
        case .foundation: FoundationHTTPTransport(configuration: try FoundationTransportConfiguration())
        #endif
        }
    }
}

/// Shared success, redirect and resource-close contract, independent of wire details.
@Suite private struct SharedHTTPConformanceTests {
    /// Sends ordinary and redirect exchanges through the identical local peer and
    /// verifies EOF/explicit close ownership and absence of hidden redirect replay.
    /// - Parameter backend: Published concrete adapter selected by parameterization.
    /// - Throws: Local setup, execution or body iteration failure.
    @Test(arguments: HTTPBackend.allCases)
    func conformance(_ backend: HTTPBackend) async throws {
        let peer = try await HTTPTestPeer.open()
        let transport = try backend.make()
        do {
            let response = try await transport.execute(HTTPRequest(method: "GET", url: peer.url("/ok?token=private")), context: TransportContext(clock: ContinuousClock(), deadline: ContinuousClock().now.advanced(by: .seconds(10))))
            #expect(response.status == 200)
            var output = Data()
            if let body = response.body {
                for try await chunk in body { #expect(chunk.count <= 16_384); output.append(chunk) }
                await body.close()
            }
            #expect(output == Data("hello\0world".utf8))
            let redirect = try await transport.execute(HTTPRequest(method: "GET", url: peer.url("/redirect")), context: TransportContext(clock: ContinuousClock(), deadline: ContinuousClock().now.advanced(by: .seconds(5))))
            #expect(redirect.status == 307); await redirect.body?.close()
            #expect(peer.requests.withLockedValue { $0 } == 2)
            await transport.close(); await transport.close()
            await #expect(throws: TransportFailure.closed) {
                try await transport.execute(HTTPRequest(method: "GET", url: peer.url()), context: TransportContext(clock: ContinuousClock(), deadline: ContinuousClock().now.advanced(by: .seconds(5))))
            }
        } catch { await transport.close(); await peer.close(); throw error }
        await peer.close()
    }
}
