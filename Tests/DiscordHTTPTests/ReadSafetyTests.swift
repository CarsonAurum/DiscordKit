import DiscordCore
import DiscordTestSupport
import DiscordTransport
import Foundation
import Testing
@testable import DiscordHTTP

/// Regressions for cache freshness, cancellation publication and mutation uncertainty.
@Suite(.timeLimit(.minutes(1))) struct ReadSafetyTests {
    /// Builds an explicitly eligible byte read and sends exactly one scripted response.
    /// - Parameters:
    ///   - headers: Server cache directives whose retention effect is under test.
    ///   - clock: Caller-owned virtual time shared by response and cache.
    ///   - advanceDuringResponse: Elapsed exchange time, default zero.
    /// - Returns: Populated or intentionally empty cache after successful decoding.
    /// - Throws: Descriptor, body or execution failures.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    private func fetch(headers: [HTTPHeader], clock: ManualClock,
                       advanceDuringResponse: Duration = .zero) async throws -> ReadCache<ManualClock> {
        let cache = ReadCache(clock: clock)
        let transport = try ScriptedHTTPTransport(steps: [{ _ in
            try clock.advance(by: advanceDuringResponse)
            return HTTPResponse(status: 200, headers: headers,
                                body: try RequestBody(bytes: Data("value".utf8), contentType: "text/plain").makeStream())
        }])
        let coordinator = RateLimitCoordinator(clock: clock)
        let client = RESTClient(credential: .none, identity: .init(), transport: transport,
                                coordinator: coordinator, clock: clock, cache: cache)
        let endpoint = try Endpoint(method: "GET", path: ["cache"], authentication: .none,
                                    retrySafety: .safe, readPolicy: .init(timeToLive: .seconds(10)), decode: { $0 })
        #expect(try await client.execute(endpoint) == Data("value".utf8))
        #expect(await transport.executionCount == 1)
        #expect(await coordinator.snapshot().activeCount == 0)
        return cache
    }

    /// Explicit forbidden, stale or malformed cache instructions override endpoint opt-in.
    /// - Parameter headers: A response whose representation cannot be retained safely.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [
        [HTTPHeader(name: "Cache-Control", value: "no-store")],
        [.init(name: "Cache-Control", value: "private, no-cache=\"authorization\"")],
        [.init(name: "VARY", value: "Accept, *")],
        [.init(name: "Cache-Control", value: "max-age=0")],
        [.init(name: "Cache-Control", value: "max-age = 0")],
        [.init(name: "Cache-Control", value: "max-age=bad")],
        [.init(name: "Age", value: "NaN")],
        [.init(name: "Expires", value: "Thu, 01 Jan 1970 00:00:00 GMT"),
         .init(name: "Date", value: "Thu, 01 Jan 1970 00:00:00 GMT")],
        [.init(name: "Expires", value: "Thu, 01 Jan 1970 00:00:10 GMT")],
        [.init(name: "Cache-Control", value: "max-age=3"), .init(name: "Age", value: "3")]
    ])
    func serverDirectivesCanDeclineCache(_ headers: [HTTPHeader]) async throws {
        let cache = try await fetch(headers: headers, clock: ManualClock())
        #expect(await cache.snapshot().entries == 0)
        #expect(await cache.snapshot().bytes == 0)
    }

    /// max-age, Age and injected exchange time shorten endpoint freshness and expiry is inclusive.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func serverFreshnessCapsEndpointLifetime() async throws {
        let clock = ManualClock()
        let cache = try await fetch(headers: [.init(name: "Cache-Control", value: "private, max-age=\"3\""),
                                               .init(name: "Age", value: "1")],
                                    clock: clock, advanceDuringResponse: .seconds(1))
        #expect(await cache.snapshot().entries == 1)
        try clock.advance(by: .milliseconds(999))
        #expect(await cache.snapshot().entries == 1)
        try clock.advance(by: .milliseconds(1))
        #expect(await cache.snapshot().entries == 0)
        let expiresClock = ManualClock()
        let expires = try await fetch(headers: [
            .init(name: "Date", value: "Thu, 01 Jan 1970 00:00:00 GMT"),
            .init(name: "Expires", value: "Thu, 01 Jan 1970 00:00:02 GMT")
        ], clock: expiresClock)
        #expect(await expires.snapshot().entries == 1)
        try expiresClock.advance(by: .seconds(2))
        #expect(await expires.snapshot().entries == 0)
    }

    /// Close cannot publish successful bytes from an operation that returns after cancellation.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func canceledCoalescedOperationCannotPublishSuccess() async throws {
        let entered = TestBarrier()
        let canceled = TestBarrier()
        let release = UncancellableReadGate()
        let coalescer = RequestCoalescer()
        let key = HTTPReadKey(identity: .init(), representation: "read")
        let subscriber = Task {
            try await coalescer.run(key: key) {
                entered.open()
                return await withTaskCancellationHandler {
                    await release.wait()
                    return Data("stale".utf8)
                } onCancel: { canceled.open() }
            }
        }
        try await entered.wait()
        let closing = Task { await coalescer.close() }
        try await canceled.wait()
        await release.open()
        await closing.value
        await #expect(throws: CancellationError.self) { _ = try await subscriber.value }
        #expect(await coalescer.snapshot().flights == 0)
        #expect(await coalescer.snapshot().waiters == 0)
    }

    /// A complete 5xx cannot establish that an unsafe mutation had no effect and is never replayed.
    /// - Parameter status: Representative server errors with potentially ambiguous side effects.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [500, 502, 503])
    func unsafeServerErrorsAreIndeterminate(_ status: Int) async throws {
        let clock = ManualClock()
        let coordinator = RateLimitCoordinator(clock: clock)
        let transport = try ScriptedHTTPTransport(steps: [{ _ in HTTPResponse(status: status) }])
        let client = RESTClient(credential: .none, identity: .init(), transport: transport,
                                coordinator: coordinator, clock: clock)
        let endpoint = try Endpoint(method: "POST", path: ["mutation"], authentication: .none, decode: { $0 })
        await #expect(throws: DiscordError.unknownMutationOutcome(.serverErrorAfterSubmission)) {
            _ = try await client.execute(endpoint)
        }
        #expect(await transport.executionCount == 1)
        #expect(await coordinator.snapshot().activeCount == 0)
        #expect(await coordinator.snapshot().orderedOperationsCount == 0)
    }

    /// Deadline expiry during synchronous body creation closes that owned stream before any send.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func factoryDeadlineFailureClosesUnsubmittedBody() async throws {
        let clock = ManualClock()
        let counter = ResourceCounter()
        let lease = await counter.acquire()
        let body = try RequestBody.stream(contentType: "application/octet-stream", maximumBytes: 1) {
            let stream = try BodyStream(maximumChunkBytes: 1, next: { nil }, close: { await lease.release() })
            try clock.advance(by: .seconds(2))
            return stream
        }
        let transport = try ScriptedHTTPTransport(steps: [])
        let coordinator = RateLimitCoordinator(clock: clock)
        let client = RESTClient(credential: .none, identity: .init(), transport: transport,
                                coordinator: coordinator, clock: clock)
        let endpoint = try Endpoint(method: "POST", path: ["body"], authentication: .none, body: body, decode: { $0 })
        await #expect(throws: TransportFailure.deadlineExceeded) {
            _ = try await client.execute(endpoint, deadline: clock.now.advanced(by: .seconds(1)))
        }
        #expect(await transport.executionCount == 0)
        #expect(await counter.snapshot().live == 0)
        #expect(await counter.snapshot().released == 1)
        #expect(await coordinator.snapshot().activeCount == 0)
        #expect(await coordinator.snapshot().orderedOperationsCount == 0)
        #expect(clock.pendingSleepCount == 0)
    }

    /// A complete rejected mutation carries no remaining send uncertainty while its retry is queued.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func cancellationAfterExplicitRejectionIsOrdinaryCancellation() async throws {
        let clock = ManualClock()
        let coordinator = RateLimitCoordinator(clock: clock)
        let transport = try ScriptedHTTPTransport(steps: [{ _ in
            HTTPResponse(status: 429, headers: [.init(name: "Retry-After", value: "2")])
        }])
        let client = RESTClient(credential: .none, identity: .init(), transport: transport,
                                coordinator: coordinator, clock: clock)
        let endpoint = try Endpoint(method: "POST", path: ["rejected"], authentication: .none, decode: { $0 })
        let task = Task { try await client.execute(endpoint) }
        defer { task.cancel() }
        var queued = false
        for _ in 0..<10_000 {
            if await coordinator.snapshot().queuedCount == 1 { queued = true; break }
            await Task.yield()
        }
        try #require(queued)
        task.cancel()
        await #expect(throws: CancellationError.self) { _ = try await task.value }
        #expect(await transport.executionCount == 1)
        #expect(await coordinator.snapshot().activeCount == 0)
        #expect(await coordinator.snapshot().orderedOperationsCount == 0)
        #expect(clock.pendingSleepCount == 0)
    }

    /// A stricter endpoint TTL cannot consume a longer-lived snapshot of the same wire representation.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func endpointFreshnessPoliciesPartitionReuse() async throws {
        let clock = ManualClock()
        let cache = ReadCache(clock: clock)
        let coordinator = RateLimitCoordinator(clock: clock)
        let transport = try ScriptedHTTPTransport(steps: [
            { _ in HTTPResponse(status: 200, body: try RequestBody(bytes: Data("old".utf8), contentType: "text/plain").makeStream()) },
            { _ in HTTPResponse(status: 200, body: try RequestBody(bytes: Data("new".utf8), contentType: "text/plain").makeStream()) }
        ])
        let client = RESTClient(credential: .none, identity: .init(), transport: transport,
                                coordinator: coordinator, clock: clock, cache: cache)
        let long = try Endpoint(method: "GET", path: ["policy"], authentication: .none, retrySafety: .safe,
                                readPolicy: .init(timeToLive: .seconds(60)), decode: { $0 })
        let short = try Endpoint(method: "GET", path: ["policy"], authentication: .none, retrySafety: .safe,
                                 readPolicy: .init(timeToLive: .seconds(1)), decode: { $0 })
        #expect(try await client.execute(long) == Data("old".utf8))
        try clock.advance(by: .seconds(2))
        #expect(try await client.execute(short) == Data("new".utf8))
        #expect(await transport.executionCount == 2)
        #expect(await cache.snapshot().entries == 2)
    }

    /// Shared reuse owners preserve each client's representation, byte, lifetime and retry contracts.
    /// The first client populates one cache entry; an otherwise identical same-scope client whose
    /// selected policy differs must send independently and subsequently reuse its own bytes.
    /// Explicit bucket headroom permits both exchanges without advancing the injected clock.
    /// - Parameter changedPolicy: The single varied client setting; all scripted bodies fit both caps.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: ["userAgent", "responseBytes", "exchangeDuration", "attempts", "backoff", "maximumBackoff"])
    func clientPoliciesPartitionReuse(_ changedPolicy: String) async throws {
        let clock = ManualClock()
        let cache = ReadCache(clock: clock)
        let coalescer = RequestCoalescer()
        let coordinator = RateLimitCoordinator(clock: clock)
        let identity = RateLimitIdentity()
        let allowance = [HTTPHeader(name: "X-RateLimit-Bucket", value: "client-policy"),
                         .init(name: "X-RateLimit-Limit", value: "20"),
                         .init(name: "X-RateLimit-Remaining", value: "19"),
                         .init(name: "X-RateLimit-Reset-After", value: "10")]
        let transport = try ScriptedHTTPTransport(steps: [
            { request in
                #expect(request.headers.contains(.init(name: "User-Agent", value: "DiscordKit-test-a")))
                return HTTPResponse(status: 200, headers: allowance,
                                    body: try RequestBody(bytes: Data("old".utf8), contentType: "text/plain").makeStream())
            },
            { request in
                let expected = changedPolicy == "userAgent" ? "DiscordKit-test-b" : "DiscordKit-test-a"
                #expect(request.headers.contains(.init(name: "User-Agent", value: expected)))
                return HTTPResponse(status: 200, headers: allowance,
                                    body: try RequestBody(bytes: Data("new".utf8), contentType: "text/plain").makeStream())
            }
        ])
        let first = RESTClient(credential: .none, identity: identity, transport: transport,
                               coordinator: coordinator, clock: clock, cache: cache, coalescer: coalescer,
                               maximumResponseBytes: 64, userAgent: "DiscordKit-test-a")
        let retry = RetryPolicy(maximumAttempts: changedPolicy == "attempts" ? 2 : 3,
                                initialBackoff: changedPolicy == "backoff" ? .milliseconds(500) : .milliseconds(250),
                                maximumBackoff: changedPolicy == "maximumBackoff" ? .seconds(1) : .seconds(5))
        let second = RESTClient(credential: .none, identity: identity, transport: transport,
                                coordinator: coordinator, clock: clock, cache: cache, coalescer: coalescer,
                                retryPolicy: retry, maximumResponseBytes: changedPolicy == "responseBytes" ? 8 : 64,
                                maximumExchangeDuration: changedPolicy == "exchangeDuration" ? .seconds(15) : .seconds(30),
                                userAgent: changedPolicy == "userAgent" ? "DiscordKit-test-b" : "DiscordKit-test-a")
        let endpoint = try Endpoint(method: "GET", path: ["client-policy"], authentication: .none, retrySafety: .safe,
                                    readPolicy: .init(timeToLive: .seconds(60)), decode: { $0 })
        #expect(try await first.execute(endpoint) == Data("old".utf8))
        #expect(try await first.execute(endpoint) == Data("old".utf8))
        #expect(await transport.executionCount == 1)
        #expect(try await second.execute(endpoint) == Data("new".utf8))
        #expect(try await second.execute(endpoint) == Data("new".utf8))
        #expect(await transport.executionCount == 2)
        #expect(await cache.snapshot().entries == 2)
        #expect(await coalescer.snapshot().flights == 0)
        #expect(await coordinator.snapshot().activeCount == 0)
    }

    /// Different invalidation tags remain separate even when their HTTP representation is identical.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func endpointInvalidationPoliciesPartitionReuse() async throws {
        let clock = ManualClock()
        let cache = ReadCache(clock: clock)
        let coordinator = RateLimitCoordinator(clock: clock)
        let transport = try ScriptedHTTPTransport(steps: [
            { _ in HTTPResponse(status: 200, body: try RequestBody(bytes: Data("a".utf8), contentType: "text/plain").makeStream()) },
            { _ in HTTPResponse(status: 200, body: try RequestBody(bytes: Data("b".utf8), contentType: "text/plain").makeStream()) }
        ])
        let client = RESTClient(credential: .none, identity: .init(), transport: transport,
                                coordinator: coordinator, clock: clock, cache: cache)
        let a = try Endpoint(method: "GET", path: ["tags"], authentication: .none, retrySafety: .safe,
                             readPolicy: .init(timeToLive: .seconds(60), tags: ["a"]), decode: { $0 })
        let b = try Endpoint(method: "GET", path: ["tags"], authentication: .none, retrySafety: .safe,
                             readPolicy: .init(timeToLive: .seconds(60), tags: ["b"]), decode: { $0 })
        #expect(try await client.execute(a) == Data("a".utf8))
        try clock.advance(by: .seconds(1))
        #expect(try await client.execute(b) == Data("b".utf8))
        await client.invalidate(tags: ["a"])
        #expect(try await client.execute(b) == Data("b".utf8))
        #expect(await transport.executionCount == 2)
        #expect(await cache.snapshot().entries == 1)
    }

    /// Explicit request no-store policy also prevents retention of an otherwise eligible successful response.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func requestCacheDirectivesPreventRetention() async throws {
        let clock = ManualClock()
        let cache = ReadCache(clock: clock)
        let coordinator = RateLimitCoordinator(clock: clock)
        let transport = try ScriptedHTTPTransport(steps: [{ _ in HTTPResponse(status: 200) }])
        let client = RESTClient(credential: .none, identity: .init(), transport: transport,
                                coordinator: coordinator, clock: clock, cache: cache)
        let endpoint = try Endpoint(method: "GET", path: ["request-cache"], authentication: .none,
                                    headers: [.init(name: "Cache-Control", value: "no-store")], retrySafety: .safe,
                                    readPolicy: .init(timeToLive: .seconds(10)), decode: { $0 })
        #expect(try await client.execute(endpoint).isEmpty)
        #expect(await cache.snapshot().entries == 0)
        #expect(await transport.executionCount == 1)
    }

    /// Raw rate metadata and reservation ownership never expand into default diagnostics.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func rateMetadataDiagnosticsAreRedacted() {
        let secret = "synthetic_path_token"
        let request = RateLimitRequest(identity: .init(), route: "POST /webhooks/1/" + secret, majorResource: secret)
        let token = RateLimitReservation(id: UUID(), request: request, expiresAt: ManualClock.Instant())
        #expect(!String(describing: request).contains(secret))
        #expect(!String(reflecting: request).contains(secret))
        #expect(!String(describing: token).contains(secret))
        #expect(!String(reflecting: token).contains(secret))
        #expect(request.customMirror.children.count == 1)
        #expect(token.customMirror.children.count == 1)
        #expect(!String(reflecting: Array(request.customMirror.children)).contains(secret))
        #expect(!String(reflecting: Array(token.customMirror.children)).contains(secret))
    }
}

/// A controlled operation that deliberately ignores cancellation until explicitly released.
private actor UncancellableReadGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var opened = false

    /// Suspends once for a test-controlled release, including while the caller is canceled.
    func wait() async {
        if opened { return }
        await withCheckedContinuation { continuation = $0 }
    }

    /// Releases a suspended test operation exactly once; an early release is remembered.
    func open() {
        opened = true
        continuation?.resume()
        continuation = nil
    }
}
