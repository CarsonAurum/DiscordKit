#if canImport(Darwin)
import DiscordTransport
import DiscordTestSupport
import Foundation
import Testing
@testable import DiscordFoundationTransport

/// Exercises owned Foundation adapters against deterministic local peers only.
@Suite(.timeLimit(.minutes(1)))
struct FoundationTransportTests {
    /// Invalid zero/negative limits, inconsistent chunk sizes and nonfinite timeouts fail.
    @Test
    func configurationValidation() throws {
        #expect(throws: TransportFailure.invalidLimit) { try FoundationTransportConfiguration(maximumConcurrentOperations: 0) }
        #expect(throws: TransportFailure.invalidLimit) { try FoundationTransportConfiguration(maximumRequestBodyBytes: -1) }
        #expect(throws: TransportFailure.invalidLimit) { try FoundationTransportConfiguration(maximumResponseBodyBytes: 0) }
        #expect(throws: TransportFailure.invalidLimit) { try FoundationTransportConfiguration(responseChunkBytes: 0) }
        #expect(throws: TransportFailure.invalidLimit) { try FoundationTransportConfiguration(maximumResponseBodyBytes: 1, responseChunkBytes: 2) }
        #expect(throws: TransportFailure.invalidLimit) { try FoundationTransportConfiguration(maximumWebSocketMessageBytes: 0) }
        for timeout in [0, -1, Double.infinity, Double.nan] {
            #expect(throws: TransportFailure.invalidLimit) { try FoundationTransportConfiguration(networkTimeout: timeout) }
        }
        let valid = try FoundationTransportConfiguration(maximumConcurrentOperations: 1, maximumRequestBodyBytes: 1,
                                                        maximumResponseBodyBytes: 1, responseChunkBytes: 1,
                                                        maximumWebSocketMessageBytes: 1, networkTimeout: 0.5)
        #expect(valid.maximumConcurrentOperations == 1)
        #expect(valid.maximumRequestBodyBytes == 1)
        #expect(valid.maximumResponseBodyBytes == 1)
        #expect(valid.responseChunkBytes == 1)
        #expect(valid.maximumWebSocketMessageBytes == 1)
        #expect(valid.networkTimeout == 0.5)
    }

    /// Validation rejects injection, URL credentials and normalization-sensitive headers.
    @Test
    func requestValidation() throws {
        let url = URL(string: "http://127.0.0.1/test")!
        for request in [
            HTTPRequest(method: "", url: url), HTTPRequest(method: "G ET", url: url),
            HTTPRequest(method: "GET", url: URL(string: "file:///tmp/test")!),
            HTTPRequest(method: "GET", url: URL(string: "https://user:secret@example.com")!),
            HTTPRequest(method: "GET", url: URL(string: "https://example.com/#fragment")!),
            HTTPRequest(method: "GET", url: url, headers: [HTTPHeader(name: "bad name", value: "x")]),
            HTTPRequest(method: "GET", url: url, headers: [HTTPHeader(name: "x", value: "x\r\ny")]),
            HTTPRequest(method: "GET", url: url, headers: [HTTPHeader(name: "X", value: "a"), HTTPHeader(name: "x", value: "b")]),
            HTTPRequest(method: "GET", url: url, headers: [HTTPHeader(name: "Host", value: "other")]),
            HTTPRequest(method: "GET", url: url, headers: [HTTPHeader(name: "Sec-WebSocket-Key", value: "key")]),
        ] {
            #expect(throws: FoundationTransportFailure.invalidRequest) { try foundationRequest(request, webSocket: false) }
        }
        let valid = try foundationRequest(HTTPRequest(method: "POST", url: url, headers: [HTTPHeader(name: "X-Test", value: "hello\tworld")]), webSocket: false)
        #expect(valid.httpMethod == "POST")
        #expect(valid.value(forHTTPHeaderField: "X-Test") == "hello\tworld")
        #expect(!valid.httpShouldHandleCookies)
        #expect(throws: FoundationTransportFailure.invalidRequest) { try foundationRequest(HTTPRequest(method: "POST", url: URL(string: "ws://localhost/")!), webSocket: true) }
    }

    /// HTTP preserves upload bytes, status and headers and yields bounded response chunks.
    @Test
    func httpRoundTripAndBodyOwnership() async throws {
        let peer = try FoundationLoopbackPeer(behavior: .response(Data("HTTP/1.1 201 Created\r\nContent-Length: 7\r\nX-Test: yes\r\nConnection: close\r\n\r\nabcdefg".utf8)))
        let url = try await peer.start()
        let adapter = FoundationHTTPTransport(configuration: try FoundationTransportConfiguration(responseChunkBytes: 3))
        let upload = FoundationTestBody(chunks: [Data("up".utf8), Data("load".utf8)])
        let stream = try await upload.stream()
        do {
            let response = try await adapter.execute(HTTPRequest(method: "POST", url: url, body: stream), context: TransportContext(clock: ContinuousClock()))
            #expect(response.status == 201)
            #expect(response.headers.contains { $0.name.lowercased() == "x-test" && $0.value == "yes" })
            var chunks: [Data] = []
            for try await chunk in try #require(response.body) { chunks.append(chunk) }
            #expect(chunks.map(\.count) == [3, 3, 1])
            #expect(chunks.reduce(into: Data()) { $0.append($1) } == Data("abcdefg".utf8))
            let request = await peer.waitForRequest()
            #expect(String(decoding: request, as: UTF8.self).hasSuffix("upload"))
            #expect(await upload.closeCount == 1)
            await response.body?.close()
        } catch { await adapter.close(); await peer.close(); throw error }
        await adapter.close()
        await adapter.close()
        await peer.close()
    }

    /// Oversized known-length responses fail before body ownership escapes to the caller.
    @Test
    func responseLengthLimit() async throws {
        let peer = try FoundationLoopbackPeer(behavior: .response(Data("HTTP/1.1 200 OK\r\nContent-Length: 9\r\nConnection: close\r\n\r\n123456789".utf8)))
        let url = try await peer.start()
        let adapter = FoundationHTTPTransport(configuration: try FoundationTransportConfiguration(maximumResponseBodyBytes: 8, responseChunkBytes: 4))
        await #expect(throws: FoundationTransportFailure.bodyLimitExceeded(limit: 8)) {
            try await adapter.execute(HTTPRequest(method: "GET", url: url), context: TransportContext(clock: ContinuousClock()))
        }
        await adapter.close()
        await peer.close()
    }

    /// HEAD and 304 metadata may advertise representations larger than the body cap.
    /// Both responses yield empty bodies, preserve Content-Length and release the
    /// sole admission slot at EOF so a subsequent request on the adapter succeeds.
    /// - Parameter scenario: Request method and returned status for a bodyless response.
    @Test(arguments: [("HEAD", 200), ("GET", 304)])
    func representationMetadataLength(scenario: (String, Int)) async throws {
        let (method, status) = scenario
        let representationLength = "9999999999"
        let responseBytes = Data("HTTP/1.1 \(status) Fixture\r\nContent-Length: \(representationLength)\r\nConnection: close\r\n\r\n".utf8)
        let peer = try FoundationLoopbackPeer(behavior: .response(responseBytes))
        let url = try await peer.start()
        let adapter = FoundationHTTPTransport(configuration: try FoundationTransportConfiguration(
            maximumConcurrentOperations: 1, maximumResponseBodyBytes: 8, responseChunkBytes: 4))
        do {
            for _ in 0..<2 {
                let response = try await adapter.execute(HTTPRequest(method: method, url: url),
                                                         context: TransportContext(clock: ContinuousClock()))
                #expect(response.status == status)
                #expect(response.headers.contains {
                    $0.name.lowercased() == "content-length" && $0.value == representationLength
                })
                var iterator = try #require(response.body).makeAsyncIterator()
                #expect(try await iterator.next() == nil)
                #expect(try await iterator.next() == nil)
            }
            #expect(await peer.requestCount == 2)
        } catch { await adapter.close(); await peer.close(); throw error }
        await adapter.close()
        await peer.close()
    }

    /// Unknown-length chunked data cannot bypass the consumed-byte limit on later pulls.
    @Test
    func chunkedResponseLimit() async throws {
        let peer = try FoundationLoopbackPeer(behavior: .response(Data("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n9\r\n123456789\r\n0\r\n\r\n".utf8)))
        let url = try await peer.start()
        let adapter = FoundationHTTPTransport(configuration: try FoundationTransportConfiguration(maximumResponseBodyBytes: 8, responseChunkBytes: 4))
        do {
            let response = try await adapter.execute(HTTPRequest(method: "GET", url: url), context: TransportContext(clock: ContinuousClock()))
            var iterator = try #require(response.body).makeAsyncIterator()
            #expect(try await iterator.next() == Data("1234".utf8))
            #expect(try await iterator.next() == Data("5678".utf8))
            await #expect(throws: FoundationTransportFailure.bodyLimitExceeded(limit: 8)) { try await iterator.next() }
        } catch { await adapter.close(); await peer.close(); throw error }
        await adapter.close()
        await peer.close()
    }

    /// Upload collection rejects the first excess byte and closes the single-use source.
    @Test
    func requestLimitAndValidationCleanup() async throws {
        let adapter = FoundationHTTPTransport(configuration: try FoundationTransportConfiguration(maximumRequestBodyBytes: 3))
        let upload = FoundationTestBody(chunks: [Data("abcd".utf8)])
        let stream = try await upload.stream()
        await #expect(throws: FoundationTransportFailure.bodyLimitExceeded(limit: 3)) {
            try await adapter.execute(HTTPRequest(method: "POST", url: URL(string: "http://127.0.0.1:1/")!, body: stream), context: TransportContext(clock: ContinuousClock()))
        }
        #expect(await upload.closeCount == 1)
        let invalidUpload = FoundationTestBody(chunks: [])
        let invalidStream = try await invalidUpload.stream()
        await #expect(throws: FoundationTransportFailure.invalidRequest) {
            try await adapter.execute(HTTPRequest(method: "bad method", url: URL(string: "http://localhost/")!, body: invalidStream), context: TransportContext(clock: ContinuousClock()))
        }
        #expect(await invalidUpload.closeCount == 1)
        await adapter.close()
    }

    /// A held body consumes aggregate admission until explicit close returns its slot.
    @Test
    func admissionAndExplicitBodyClose() async throws {
        let peer = try FoundationLoopbackPeer(behavior: .response(Data("HTTP/1.1 200 OK\r\nContent-Length: 3\r\nConnection: close\r\n\r\nabc".utf8)))
        let url = try await peer.start()
        let adapter = FoundationHTTPTransport(configuration: try FoundationTransportConfiguration(maximumConcurrentOperations: 1))
        let context = TransportContext(clock: ContinuousClock())
        do {
            let response = try await adapter.execute(HTTPRequest(method: "GET", url: url), context: context)
            await #expect(throws: FoundationTransportFailure.admissionRejected) { try await adapter.execute(HTTPRequest(method: "GET", url: url), context: context) }
            await response.body?.close()
            let next = try await adapter.execute(HTTPRequest(method: "GET", url: url), context: context)
            await next.body?.close()
            await adapter.close()
            await #expect(throws: TransportFailure.closed) { try await adapter.execute(HTTPRequest(method: "GET", url: url), context: context) }
        } catch { await adapter.close(); await peer.close(); throw error }
        await peer.close()
    }

    /// HTTP redirects are returned without following a sensitive Location destination.
    @Test
    func redirectsAreNotFollowed() async throws {
        let peer = try FoundationLoopbackPeer(behavior: .response(Data("HTTP/1.1 302 Found\r\nContent-Length: 0\r\nLocation: http://127.0.0.1:1/secret\r\nConnection: close\r\n\r\n".utf8)))
        let url = try await peer.start()
        let adapter = FoundationHTTPTransport(configuration: try FoundationTransportConfiguration())
        do {
            let response = try await adapter.execute(HTTPRequest(method: "GET", url: url), context: TransportContext(clock: ContinuousClock()))
            #expect(response.status == 302)
            await response.body?.close()
            #expect(await peer.requestCount == 1)
        } catch { await adapter.close(); await peer.close(); throw error }
        await adapter.close()
        await peer.close()
    }

    /// Cacheable responses and Set-Cookie fields never create cache hits or cookie replay.
    @Test
    func cookiesAndCachingAreDisabled() async throws {
        let peer = try FoundationLoopbackPeer(behavior: .response(Data("HTTP/1.1 200 OK\r\nContent-Length: 1\r\nSet-Cookie: fixture=value; Path=/\r\nCache-Control: max-age=86400\r\nConnection: close\r\n\r\nx".utf8)))
        let url = try await peer.start()
        let adapter = FoundationHTTPTransport(configuration: try FoundationTransportConfiguration())
        do {
            for _ in 0..<2 {
                let response = try await adapter.execute(HTTPRequest(method: "GET", url: url), context: TransportContext(clock: ContinuousClock()))
                var bytes = Data()
                for try await chunk in try #require(response.body) { bytes.append(chunk) }
                #expect(bytes == Data("x".utf8))
            }
            #expect(await peer.requestCount == 2)
            let request = try #require(await peer.lastRequest)
            #expect(!String(decoding: request, as: UTF8.self).lowercased().contains("\r\ncookie:"))
        } catch { await adapter.close(); await peer.close(); throw error }
        await adapter.close()
        await peer.close()
    }

    /// Cancelling after a peer receives the request interrupts native pending metadata I/O.
    @Test
    func cancellationDuringHTTPAndShutdown() async throws {
        let peer = try FoundationLoopbackPeer(behavior: .stalledHTTP)
        let url = try await peer.start()
        let adapter = FoundationHTTPTransport(configuration: try FoundationTransportConfiguration())
        let operation = Task { try await adapter.execute(HTTPRequest(method: "GET", url: url), context: TransportContext(clock: ContinuousClock())) }
        _ = await peer.waitForRequest()
        operation.cancel()
        await #expect(throws: CancellationError.self) { try await operation.value }
        async let first: Void = adapter.close()
        async let second: Void = adapter.close()
        _ = await (first, second)
        await peer.close()
    }

    /// Pre-cancelled/expired contexts fail before network work and still close uploads.
    @Test
    func cancellationAndDeadlineBeforeStart() async throws {
        let adapter = FoundationHTTPTransport(configuration: try FoundationTransportConfiguration())
        let context = TransportContext(clock: ContinuousClock(), deadline: ContinuousClock().now)
        let upload = FoundationTestBody(chunks: [Data("unused".utf8)])
        let stream = try await upload.stream()
        await #expect(throws: TransportFailure.deadlineExceeded) {
            try await adapter.execute(HTTPRequest(method: "GET", url: URL(string: "http://127.0.0.1:1/")!, body: stream), context: context)
        }
        #expect(await upload.closeCount == 1)
        let operation = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await adapter.execute(HTTPRequest(method: "GET", url: URL(string: "http://127.0.0.1:1/")!), context: TransportContext(clock: ContinuousClock()))
        }
        await #expect(throws: CancellationError.self) { try await operation.value }
        await adapter.close()
    }

    /// Advancing the injected clock interrupts an already transmitted stalled request.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test
    func injectedDeadlineDuringHTTP() async throws {
        let peer = try FoundationLoopbackPeer(behavior: .stalledHTTP)
        let url = try await peer.start()
        let adapter = FoundationHTTPTransport(configuration: try FoundationTransportConfiguration())
        let timerStarted = TestBarrier()
        let clock = ManualClock(onSleepScheduled: { timerStarted.open() })
        let operation = Task { try await adapter.execute(HTTPRequest(method: "GET", url: url), context: TransportContext(clock: clock, deadline: clock.now.advanced(by: .seconds(1)))) }
        _ = await peer.waitForRequest()
        try await timerStarted.wait()
        try clock.advance(by: .seconds(1))
        await #expect(throws: TransportFailure.deadlineExceeded) { try await operation.value }
        #expect(clock.pendingSleepCount == 0)
        await adapter.close()
        await peer.close()
    }

    /// A response body retains its original clock/deadline after metadata is transferred.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test
    func responseBodyRetainsDeadline() async throws {
        let peer = try FoundationLoopbackPeer(behavior: .response(Data("HTTP/1.1 200 OK\r\nContent-Length: 3\r\nConnection: close\r\n\r\nabc".utf8)))
        let url = try await peer.start()
        let adapter = FoundationHTTPTransport(configuration: try FoundationTransportConfiguration())
        let clock = ManualClock()
        do {
            let response = try await adapter.execute(HTTPRequest(method: "GET", url: url), context: TransportContext(clock: clock, deadline: clock.now.advanced(by: .seconds(1))))
            try clock.advance(by: .seconds(1))
            var iterator = try #require(response.body).makeAsyncIterator()
            await #expect(throws: TransportFailure.deadlineExceeded) { try await iterator.next() }
            #expect(try await iterator.next() == nil)
        } catch { await adapter.close(); await peer.close(); throw error }
        await adapter.close()
        await peer.close()
    }

    /// Native failures discard URL/userInfo secrets while retaining safe numeric codes.
    @Test
    func failuresAreRedacted() async throws {
        let failure = foundationFailure(NSError(domain: "secret-domain", code: 17, userInfo: [NSLocalizedDescriptionKey: "secret-token", NSURLErrorFailingURLErrorKey: URL(string: "https://secret.invalid/token")!]))
        #expect(failure as? FoundationTransportFailure == .network(code: 17))
        #expect(!String(reflecting: failure).contains("secret"))
        #expect(foundationFailure(TransportFailure.closed) as? TransportFailure == .closed)
        #expect(foundationFailure(CancellationError()) is CancellationError)
        #expect(foundationFailure(FoundationTransportFailure.invalidRequest) as? FoundationTransportFailure == .invalidRequest)
    }

    /// Abandoning a partially delivered body cancels its producer and awaits invalidation.
    /// This covers a peer that leaves the declared body unfinished, with no timing sleeps.
    @Test
    func abandonIncompleteResponse() async throws {
        var partialResponse = Data("HTTP/1.1 200 OK\r\nContent-Length: 131072\r\n\r\n".utf8)
        partialResponse.append(Data(repeating: 97, count: 65_536))
        let peer = try FoundationLoopbackPeer(behavior: .response(partialResponse))
        let url = try await peer.start()
        let adapter = FoundationHTTPTransport(configuration: try FoundationTransportConfiguration())
        do {
            let response = try await adapter.execute(HTTPRequest(method: "GET", url: url), context: TransportContext(clock: ContinuousClock()))
            #expect(response.status == 200)
            await response.body?.close()
        } catch { await adapter.close(); await peer.close(); throw error }
        await adapter.close()
        await peer.close()
    }

    #if !os(watchOS)
    /// Native WebSocket text/binary exchange preserves complete messages and size limits.
    @Test
    func webSocketRoundTripAndLimits() async throws {
        let peer = try FoundationLoopbackPeer(behavior: .webSocketEcho)
        let url = try await peer.start()
        let adapter = FoundationWebSocketTransport(configuration: try FoundationTransportConfiguration(maximumConcurrentOperations: 1, maximumWebSocketMessageBytes: 8))
        let context = TransportContext(clock: ContinuousClock())
        do {
            let connection = try await adapter.connectWebSocket(HTTPRequest(method: "GET", url: url), context: context)
            try await connection.send(.text("écho"), context: context)
            #expect(try await connection.receive(context: context) == .text("écho"))
            try await connection.send(.binary(Data([0, 1, 255])), context: context)
            #expect(try await connection.receive(context: context) == .binary(Data([0, 1, 255])))
            try await connection.send(.text("12345678"), context: context)
            #expect(try await connection.receive(context: context) == .text("12345678"))
            await #expect(throws: FoundationTransportFailure.messageLimitExceeded(limit: 8)) { try await connection.send(.text("ééééé"), context: context) }
            await #expect(throws: FoundationTransportFailure.admissionRejected) { try await adapter.connectWebSocket(HTTPRequest(method: "GET", url: url), context: context) }
            await connection.close()
            await connection.close()
            #expect(try await connection.receive(context: context) == nil)
        } catch { await adapter.close(); await peer.close(); throw error }
        await adapter.close()
        await peer.close()
    }

    /// Numeric Gateway peer codes survive Foundation receive failure and local cleanup.
    /// Reopening within the single-slot budget proves terminal input returned admission.
    /// - Parameter code: A private close status requiring distinct higher-level reconnect policy.
    /// - Throws: Loopback startup, upgrade, peer close transmission or unexpected receive errors.
    @Test(arguments: [UInt16(4004),4007,4009,4014])
    func webSocketSessionPeerCode(_ code: UInt16) async throws {
        let peer = try FoundationLoopbackPeer(behavior: .webSocketEcho)
        let url = try await peer.start()
        let adapter = FoundationWebSocketTransport(configuration: try FoundationTransportConfiguration(maximumConcurrentOperations: 1))
        let context = TransportContext(clock: ContinuousClock(), deadline: ContinuousClock().now.advanced(by: .seconds(5)))
        do {
            let connection = try await adapter.connectWebSocket(HTTPRequest(method: "GET", url: url), context: context)
            let session = try #require(connection as? any WebSocketSessionConnection)
            #expect(await session.peerCloseCode() == nil)
            try await peer.sendWebSocketClose(code)
            do { _ = try await session.receive(context: context) }
            catch { #expect(error is FoundationTransportFailure) }
            #expect(await session.peerCloseCode() == Int(code))
            await session.closeForReconnect()
            await session.close()
            let replacement = try await adapter.connectWebSocket(HTTPRequest(method: "GET", url: url), context: context)
            await replacement.close()
            await adapter.close()
            #expect(await session.peerCloseCode() == Int(code))
        } catch { await adapter.close(); await peer.close(); throw error }
        await adapter.close(); await peer.close()
    }

    /// Session-preserving closure is idempotent, rejects writes and releases the connection slot.
    /// A virtual timer gate establishes that a receive is active before aborting its native task.
    /// - Throws: Loopback setup or unexpected post-abort resource/admission errors.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func webSocketSessionReconnectAbort() async throws {
        let peer = try FoundationLoopbackPeer(behavior: .webSocketEcho)
        let url = try await peer.start()
        let adapter = FoundationWebSocketTransport(configuration: try FoundationTransportConfiguration(maximumConcurrentOperations: 1))
        do {
            let context = TransportContext(clock: ContinuousClock())
            let connection = try await adapter.connectWebSocket(HTTPRequest(method: "GET", url: url), context: context)
            let session = try #require(connection as? any WebSocketSessionConnection)
            let entered = TestBarrier()
            let clock = ManualClock(onSleepScheduled: { entered.open() })
            let pending = Task { try await session.receive(context: TransportContext(clock: clock, deadline: clock.now.advanced(by: .seconds(10)))) }
            try await entered.wait()
            await session.closeForReconnect()
            do { #expect(try await pending.value == nil) }
            catch { #expect(error is FoundationTransportFailure) }
            await session.closeForReconnect()
            await #expect(throws: TransportFailure.closed) { try await session.send(.text("late"), context: context) }
            let replacement = try await adapter.connectWebSocket(HTTPRequest(method: "GET", url: url), context: context)
            await replacement.close()
            #expect(clock.pendingSleepCount == 0)
        } catch { await adapter.close(); await peer.close(); throw error }
        await adapter.close(); await peer.close()
    }

    /// A second reader fails while cancellation interrupts an already admitted receive.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test
    func webSocketReceiveCancellation() async throws {
        let peer = try FoundationLoopbackPeer(behavior: .webSocketEcho)
        let url = try await peer.start()
        let adapter = FoundationWebSocketTransport(configuration: try FoundationTransportConfiguration())
        do {
            let connection = try await adapter.connectWebSocket(HTTPRequest(method: "GET", url: url), context: TransportContext(clock: ContinuousClock()))
            let started = TestBarrier()
            let clock = ManualClock(onSleepScheduled: { started.open() })
            let pending = Task { try await connection.receive(context: TransportContext(clock: clock, deadline: clock.now.advanced(by: .seconds(10)))) }
            try await started.wait()
            await #expect(throws: TransportFailure.concurrentRead) { try await connection.receive(context: TransportContext(clock: ContinuousClock())) }
            pending.cancel()
            await #expect(throws: CancellationError.self) { try await pending.value }
            #expect(clock.pendingSleepCount == 0)
            await connection.close()
        } catch { await adapter.close(); await peer.close(); throw error }
        await adapter.close()
        await peer.close()
    }

    /// A stalled upgrade is bounded by the injected deadline and releases admission.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test
    func webSocketUpgradeDeadline() async throws {
        let peer = try FoundationLoopbackPeer(behavior: .stalledHTTP)
        let httpURL = try await peer.start()
        let url = URL(string: httpURL.absoluteString.replacingOccurrences(of: "http://", with: "ws://"))!
        let adapter = FoundationWebSocketTransport(configuration: try FoundationTransportConfiguration(maximumConcurrentOperations: 1))
        let timerStarted = TestBarrier()
        let clock = ManualClock(onSleepScheduled: { timerStarted.open() })
        let operation = Task { try await adapter.connectWebSocket(HTTPRequest(method: "GET", url: url), context: TransportContext(clock: clock, deadline: clock.now.advanced(by: .seconds(1)))) }
        _ = await peer.waitForRequest()
        try await timerStarted.wait()
        try clock.advance(by: .seconds(1))
        await #expect(throws: TransportFailure.deadlineExceeded) { try await operation.value }
        #expect(clock.pendingSleepCount == 0)
        await adapter.close()
        await peer.close()
    }

    /// Foundation's native incoming-message ceiling rejects an oversized server push.
    @Test
    func webSocketIncomingLimit() async throws {
        let peer = try FoundationLoopbackPeer(behavior: .webSocketEcho)
        let url = try await peer.start()
        let adapter = FoundationWebSocketTransport(configuration: try FoundationTransportConfiguration(maximumWebSocketMessageBytes: 8))
        do {
            let connection = try await adapter.connectWebSocket(HTTPRequest(method: "GET", url: url), context: TransportContext(clock: ContinuousClock()))
            try await peer.sendWebSocket(Data(repeating: 42, count: 9))
            await #expect(throws: FoundationTransportFailure.messageLimitExceeded(limit: 8)) {
                try await connection.receive(context: TransportContext(clock: ContinuousClock()))
            }
            await connection.close()
        } catch { await adapter.close(); await peer.close(); throw error }
        await adapter.close()
        await peer.close()
    }

    /// Concurrent callers serialize complete writes and every unique echo remains intact.
    @Test
    func webSocketConcurrentWriters() async throws {
        let peer = try FoundationLoopbackPeer(behavior: .webSocketEcho)
        let url = try await peer.start()
        let adapter = FoundationWebSocketTransport(configuration: try FoundationTransportConfiguration(maximumConcurrentOperations: 16))
        let context = TransportContext(clock: ContinuousClock())
        do {
            let connection = try await adapter.connectWebSocket(HTTPRequest(method: "GET", url: url), context: context)
            try await withThrowingTaskGroup(of: Void.self) { group in
                for index in 0..<16 {
                    group.addTask { try await connection.send(.text("message-\(index)"), context: context) }
                }
                try await group.waitForAll()
            }
            var received: Set<String> = []
            for _ in 0..<16 {
                guard case .text(let text) = try await connection.receive(context: context) else {
                    Issue.record("Expected one complete text echo for each concurrent writer")
                    break
                }
                received.insert(text)
            }
            #expect(received == Set((0..<16).map { "message-\($0)" }))
            await connection.close()
        } catch { await adapter.close(); await peer.close(); throw error }
        await adapter.close()
        await peer.close()
    }

    /// Upgrade redirects fail rather than forwarding sensitive headers to another URL.
    @Test
    func webSocketRedirectIsRejected() async throws {
        let peer = try FoundationLoopbackPeer(behavior: .response(Data("HTTP/1.1 302 Found\r\nContent-Length: 0\r\nLocation: ws://127.0.0.1:1/secret\r\nConnection: close\r\n\r\n".utf8)))
        let httpURL = try await peer.start()
        let url = URL(string: httpURL.absoluteString.replacingOccurrences(of: "http://", with: "ws://"))!
        let adapter = FoundationWebSocketTransport(configuration: try FoundationTransportConfiguration())
        await #expect(throws: FoundationTransportFailure.self) {
            try await adapter.connectWebSocket(HTTPRequest(method: "GET", url: url, headers: [HTTPHeader(name: "Authorization", value: "fixture-only")]), context: TransportContext(clock: ContinuousClock()))
        }
        #expect(await peer.requestCount == 1)
        await adapter.close()
        await peer.close()
    }
    #endif
}

/// Small actor-owned upload source records exactly-once cleanup through observable callers.
private actor FoundationTestBody {
    private var chunks: [Data]
    private(set) var closeCount = 0

    /// Stores finite upload fixture chunks without beginning reads.
    /// - Parameter chunks: Ordered bytes returned on successive pulls; empty means EOF.
    init(chunks: [Data]) { self.chunks = chunks }

    /// Creates a single-use stream around this test's actor-owned state.
    /// - Returns: Stream with a 64 KiB per-chunk limit and observable cleanup.
    /// - Throws: BodyStream configuration validation, impossible for the fixed positive cap.
    func stream() throws -> BodyStream {
        try BodyStream(maximumChunkBytes: 65_536, next: { await self.next() }, close: { await self.close() })
    }

    /// Returns the next fixture chunk or EOF without performing external I/O.
    /// - Returns: First queued chunk, or `nil` once all fixture data has been read.
    private func next() -> Data? { chunks.isEmpty ? nil : chunks.removeFirst() }

    /// Records source cleanup; BodyStream guarantees this is called exactly once.
    private func close() { closeCount += 1; chunks.removeAll() }
}
#endif
