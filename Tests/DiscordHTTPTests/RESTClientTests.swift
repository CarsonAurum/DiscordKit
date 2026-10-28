// File: Tests/DiscordHTTPTests/RESTClientTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import DiscordModels
import DiscordTestSupport
import DiscordTransport
import Foundation
import Testing
@testable import DiscordHTTP

/// End-to-end HTTP policy tests use finite scripts and virtual time; no credentials or Discord requests.
@Suite(.timeLimit(.minutes(1)))
struct RESTClientTests {
    /// Verifies MainActor adoption, v10 routing, default library identification, bot auth, decoding and ownership.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @MainActor @Test func typedUserAndApplication() async throws {
        let transport = try ScriptedHTTPTransport(steps: [ { request in
            #expect(request.url.absoluteString == "https://discord.com/api/v10/users/@me")
            #expect(request.headers.filter { $0.name == "User-Agent" }.map(\.value) ==
                ["DiscordBot (https://github.com/CarsonAurum/DiscordKit, 0.19.0)"])
            #expect(request.headers.contains { $0.name == "Authorization" && $0.value == "Bot synthetic_token" })
            return try response("{\"id\":\"18446744073709551615\",\"username\":\"test\",\"discriminator\":\"0\",\"global_name\":null,\"avatar\":null}")
        }, { request in
            #expect(request.url.path == "/api/v10/applications/@me")
            return try response("{\"id\":\"1\",\"name\":\"test\",\"icon\":null,\"description\":\"\",\"bot_public\":true,\"bot_require_code_grant\":false,\"verify_key\":\"test\",\"team\":null}")
        } ])
        let clock = ManualClock()
        let coordinator = RateLimitCoordinator(clock: clock)
        let client = RESTClient(credential: .bot(try BotToken("synthetic_token")), identity: RateLimitIdentity(),
            transport: transport, coordinator: coordinator, clock: clock)
        let user = try await client.execute(DiscordEndpoints.currentUser())
        #expect(user.id.rawValue == UInt64.max)
        #expect(user.username == "test")
        let app = try await client.execute(DiscordEndpoints.currentApplication())
        #expect(app.id.rawValue == 1)
        #expect(await coordinator.snapshot().activeCount == 0)
        #expect(String(reflecting: client) == "RESTClient(redacted)")
        #expect(client.customMirror.children.count == 1)
        await coordinator.close()
    }

    /// Preserves HTTP status, unknown Discord codes and nested error evidence without unsafe diagnostics.
    /// - Parameter status: Scripted 401/403/404/429/500/503 status exercising one nonretrying exchange.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [401, 403, 404, 429, 500, 503])
    func apiFailures(status: Int) async throws {
        let transport = try ScriptedHTTPTransport(steps: [{ _ in
            try response("{\"code\":987654,\"message\":\"synthetic_secret\",\"errors\":{\"token\":{\"_errors\":[{\"code\":\"UNKNOWN\",\"message\":\"synthetic_secret\"}]}}}", status: status)
        }])
        let clock = ManualClock()
        let coordinator = RateLimitCoordinator(clock: clock)
        let client = RESTClient(credential: .none, identity: RateLimitIdentity(), transport: transport,
            coordinator: coordinator, clock: clock, retryPolicy: .init(maximumAttempts: 1))
        do {
            _ = try await client.execute(bytesEndpoint())
            Issue.record("Expected API failure")
        } catch let error as APIResponseError {
            #expect(error.status == status)
            #expect(error.code == 987654)
            #expect(!String(reflecting: error).contains("synthetic_secret"))
            #expect(error.withUnsafePayload { $0 != nil })
        }
        #expect(await transport.executionCount == 1)
        #expect(await coordinator.snapshot().activeCount == 0)
    }

    /// Empty/204 responses decode explicitly, malformed successes fail safely, and byte caps close bodies.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func emptyMalformedAndBoundedBodies() async throws {
        let clock = ManualClock()
        let coordinator = RateLimitCoordinator(clock: clock)
        let transport = try ScriptedHTTPTransport(steps: [ { _ in HTTPResponse(status: 204) },
            { _ in try response("malformed") }, { _ in try response("12345") } ])
        let client = RESTClient(credential: .none, identity: RateLimitIdentity(), transport: transport,
            coordinator: coordinator, clock: clock, retryPolicy: .init(maximumAttempts: 1), maximumResponseBytes: 4)
        let empty = try Endpoint(method: "DELETE", path: ["empty"], authentication: .none,
            successStatuses: [204], decode: { try EmptyResponse(data: $0) })
        #expect(try await client.execute(empty) == EmptyResponse(data: Data()))
        let malformed = try Endpoint(method: "GET", path: ["malformed"], authentication: .none,
            retrySafety: .safe, decode: { data in try User(data: data) })
        // The body cap is enforced before decoding and still releases authority ownership.
        await #expect(throws: DiscordError.transport(.limitExceeded)) { try await client.execute(malformed) }
        let large = try bytesEndpoint(path: "large")
        await #expect(throws: DiscordError.transport(.limitExceeded)) { try await client.execute(large) }
        #expect(await coordinator.snapshot().activeCount == 0)
    }

    /// Ambiguous POST transport failure executes once and reports an indeterminate mutation.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func unsafeMutationNeverBlindlyReplays() async throws {
        let clock = ManualClock()
        let coordinator = RateLimitCoordinator(clock: clock)
        let transport = try ScriptedHTTPTransport(steps: [{ _ in throw TestSupportFailure.scripted("synthetic_secret") }])
        let client = RESTClient(credential: .none, identity: RateLimitIdentity(), transport: transport,
            coordinator: coordinator, clock: clock)
        let endpoint = try Endpoint(method: "POST", path: ["mutation"], authentication: .none, decode: { $0 })
        await #expect(throws: DiscordError.unknownMutationOutcome(.connectionLostAfterSubmission)) {
            try await client.execute(endpoint)
        }
        #expect(await transport.executionCount == 1)
        #expect(await coordinator.snapshot().activeCount == 0)
        #expect(await coordinator.snapshot().orderedOperationsCount == 0)
    }

    /// A safe retry honors fractional 429 admission and preserves the original request representation.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func rateLimitedRetryAndSafeServerRetry() async throws {
        let slept = TestBarrier()
        let clock = ManualClock(onSleepScheduled: { slept.open() })
        let coordinator = RateLimitCoordinator(clock: clock)
        let transport = try ScriptedHTTPTransport(steps: [{ _ in
            try response("{\"retry_after\":0.25,\"global\":true}", status: 429)
        }, { _ in try response("done") }])
        let client = RESTClient(credential: .none, identity: RateLimitIdentity(), transport: transport,
            coordinator: coordinator, clock: clock)
        let task = Task { try await client.execute(bytesEndpoint()) }
        // Exchange lifetime creates a deadline sleeper too; inspect the transport before advancing.
        while await transport.executionCount == 0 { try Task.checkCancellation(); await Task.yield() }
        while await coordinator.snapshot().activeCount > 0 { try Task.checkCancellation(); await Task.yield() }
        try clock.advance(by: .milliseconds(249))
        #expect(await transport.executionCount == 1)
        try clock.advance(by: .seconds(1))
        #expect(try await task.value == Data("done".utf8))
        #expect(await transport.executionCount == 2)
        #expect(clock.pendingSleepCount == 0)
    }

    /// Eligible concurrent callers share one exchange; cache hits, invalidation and scopes preserve isolation.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func integratedCoalescingCacheAndInvalidation() async throws {
        let gate = TestBarrier()
        let clock = ManualClock()
        let coordinator = RateLimitCoordinator(clock: clock)
        let cache = ReadCache(clock: clock)
        let coalescer = RequestCoalescer()
        let identity = RateLimitIdentity()
        let transport = try ScriptedHTTPTransport(steps: [{ _ in try await gate.wait(); return try response("first") },
            { _ in try response("second") }])
        let client = RESTClient(credential: .none, identity: identity, transport: transport,
            coordinator: coordinator, clock: clock, cache: cache, coalescer: coalescer)
        let endpoint = try bytesEndpoint(readPolicy: .init(timeToLive: .seconds(10), tags: ["snapshot"]))
        let tasks = (0..<100).map { _ in Task { try await client.execute(endpoint) } }
        while await coalescer.snapshot().waiters < 100 { try Task.checkCancellation(); await Task.yield() }
        while gate.waitingCount == 0 { try Task.checkCancellation(); await Task.yield() }
        #expect(await transport.executionCount == 1)
        gate.open()
        for task in tasks { #expect(try await task.value == Data("first".utf8)) }
        #expect(try await client.execute(endpoint) == Data("first".utf8))
        #expect(await transport.executionCount == 1)
        await client.invalidate(tags: ["snapshot"])
        try clock.advance(by: .seconds(1))
        #expect(try await client.execute(endpoint) == Data("second".utf8))
        #expect(await transport.executionCount == 2)
        #expect(await coordinator.snapshot().activeCount == 0)
        #expect(await coalescer.snapshot().waiters == 0)
        await coalescer.close()
    }

    /// Pre-cancellation and past deadlines send nothing; in-flight unsafe cancellation remains uncertain.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func cancellationAndDeadlineEvidence() async throws {
        let clock = ManualClock()
        let coordinator = RateLimitCoordinator(clock: clock)
        let gate = TestBarrier()
        let transport = try ScriptedHTTPTransport(steps: [{ _ in try await gate.wait(); return try response("") }])
        let client = RESTClient(credential: .none, identity: RateLimitIdentity(), transport: transport,
            coordinator: coordinator, clock: clock)
        await #expect(throws: TransportFailure.deadlineExceeded) {
            try await client.execute(bytesEndpoint(), deadline: clock.now)
        }
        #expect(await transport.executionCount == 0)
        let endpoint = try Endpoint(method: "POST", path: ["cancel"], authentication: .none, decode: { $0 })
        let task = Task { try await client.execute(endpoint) }
        while gate.waitingCount < 1 { try Task.checkCancellation(); await Task.yield() }
        task.cancel()
        await #expect(throws: DiscordError.unknownMutationOutcome(.cancelledAfterSubmission)) { try await task.value }
        #expect(await coordinator.snapshot().activeCount == 0)
        #expect(clock.pendingSleepCount == 0)
    }

    /// One subscriber deadline expires independently while another subscriber receives the shared result.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func subscriberDeadlinesAreIndependent() async throws {
        let clock = ManualClock()
        let gate = TestBarrier()
        let coordinator = RateLimitCoordinator(clock: clock)
        let coalescer = RequestCoalescer()
        let transport = try ScriptedHTTPTransport(steps: [{ _ in try await gate.wait(); return try response("shared") }])
        let client = RESTClient(credential: .none, identity: RateLimitIdentity(), transport: transport,
            coordinator: coordinator, clock: clock, coalescer: coalescer)
        let endpoint = try bytesEndpoint(readPolicy: .init())
        let short = Task { try await client.execute(endpoint, deadline: clock.now.advanced(by: .milliseconds(100))) }
        while await coalescer.snapshot().waiters < 1 { try Task.checkCancellation(); await Task.yield() }
        let long = Task { try await client.execute(endpoint, deadline: clock.now.advanced(by: .seconds(2))) }
        while await coalescer.snapshot().waiters < 2 { try Task.checkCancellation(); await Task.yield() }
        while gate.waitingCount == 0 { try Task.checkCancellation(); await Task.yield() }
        try clock.advance(by: .milliseconds(100))
        await #expect(throws: TransportFailure.deadlineExceeded) { try await short.value }
        #expect(await coalescer.snapshot().waiters == 1)
        gate.open()
        #expect(try await long.value == Data("shared".utf8))
        #expect(await transport.executionCount == 1)
        #expect(clock.pendingSleepCount == 0)
        await coalescer.close()
    }

    /// Decoder failures are sanitized and never inserted into an opted-in response cache.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func malformedSuccessIsNotCached() async throws {
        let clock = ManualClock()
        let coordinator = RateLimitCoordinator(clock: clock)
        let cache = ReadCache(clock: clock)
        let transport = try ScriptedHTTPTransport(steps: [{ _ in try response("synthetic_private_response") }])
        let client = RESTClient(credential: .none, identity: RateLimitIdentity(), transport: transport,
            coordinator: coordinator, clock: clock, cache: cache)
        let endpoint = try Endpoint(method: "GET", path: ["malformed"], authentication: .none,
            retrySafety: .safe, readPolicy: .init(timeToLive: .seconds(10)), decode: { try User(data: $0) })
        await #expect(throws: DiscordError.transport(.invalidResponse)) { try await client.execute(endpoint) }
        #expect(await cache.snapshot().entries == 0)
        #expect(await coordinator.snapshot().activeCount == 0)
    }

    /// Capped exponential backoff stops at its finite attempt budget and handles invalid attempt indices.
    @Test func finiteRetryPolicy() {
        let policy = RetryPolicy(maximumAttempts: 5, initialBackoff: .milliseconds(100), maximumBackoff: .milliseconds(300))
        #expect(policy.delay(after: 0) == nil)
        #expect(policy.delay(after: 1) == .milliseconds(100))
        #expect(policy.delay(after: 2) == .milliseconds(200))
        #expect(policy.delay(after: 3) == .milliseconds(300))
        #expect(policy.delay(after: 4) == .milliseconds(300))
        #expect(policy.delay(after: 5) == nil)
    }
}

/// Constructs a safe descriptor with no authentication and explicit byte-level semantics.
/// - Parameters:
///   - path: Single route segment, default `bytes`.
///   - readPolicy: Optional opt-in reuse; nil disables read reduction.
/// - Returns: Descriptor returning exact bounded response bytes.
/// - Throws: Descriptor validation failures.
private func bytesEndpoint(path: String = "bytes", readPolicy: ReadPolicy? = nil) throws -> Endpoint<Data> {
    try Endpoint(method: "GET", path: [path], authentication: .none, retrySafety: .safe, readPolicy: readPolicy, decode: { $0 })
}

/// Constructs one replayable test response without sockets or a producer queue.
/// - Parameters:
///   - text: Exact UTF-8 body text.
///   - status: Wire status, default200.
/// - Returns: Response whose consumer owns a fresh single-use body.
/// - Throws: Materialized body validation failures.
private func response(_ text: String, status: Int = 200) throws -> HTTPResponse {
    HTTPResponse(status: status, body: try RequestBody(bytes: Data(text.utf8), contentType: "application/json").makeStream())
}
