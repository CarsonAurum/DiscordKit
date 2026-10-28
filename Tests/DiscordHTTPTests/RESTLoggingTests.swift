// File: Tests/DiscordHTTPTests/RESTLoggingTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import DiscordLogging
import DiscordTestSupport
import DiscordTransport
import Foundation
import Testing
@testable import DiscordHTTP

/// Captures native SwiftLog execution evidence without global bootstrap, sockets or credentials.
@Suite(.timeLimit(.minutes(1))) struct RESTLoggingTests {
    /// Safe transport retries disclose only fixed events/counts while construction remains inert.
    /// - Throws: Unexpected descriptor, transport-script, admission or execution failure.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func retryRedactsTransportAndRouteData() async throws {
        let recorder = LogRecorder()
        let secret = "private_route_token_body_header_error"
        let clock = ManualClock()
        let coordinator = RateLimitCoordinator(clock: clock)
        let transport = try ScriptedHTTPTransport(steps: [
            { _ in throw TestSupportFailure.scripted(secret) },
            { _ in HTTPResponse(status: 204) }
        ])
        let client = DiscordLog.$loggerFactory.withValue({ recorder.makeLogger($0) }) {
            RESTClient(credential: .none, identity: RateLimitIdentity(), transport: transport,
                coordinator: coordinator, clock: clock,
                retryPolicy: .init(maximumAttempts: 2, initialBackoff: .zero))
        }
        #expect(recorder.entries.isEmpty)
        let endpoint = try Endpoint(method: "GET", path: [secret], authentication: .none,
            successStatuses: [204], retrySafety: .safe, decode: { $0 })
        let result = try await DiscordLog.$loggerFactory.withValue({ recorder.makeLogger($0) }) {
            let task = Task { try await client.execute(endpoint) }
            defer { task.cancel() }
            // The failed first send retains its conservative one-second unknown-route
            // debit. Wait for the observed retry before advancing injected time.
            while !recorder.entries.contains(where: { $0.metadata["dk.event"] == "http.retry.transport" }) {
                try Task.checkCancellation()
                await Task.yield()
            }
            #expect(await transport.executionCount == 1)
            try clock.advance(by: .seconds(1))
            return try await task.value
        }
        #expect(result.isEmpty)
        #expect(clock.pendingSleepCount == 0)
        let entries = recorder.entries
        #expect(await transport.executionCount == 2)
        #expect(await coordinator.snapshot().activeCount == 0)
        #expect(entries.filter { $0.metadata["dk.event"] == "http.retry.transport" }.count == 1)
        #expect(entries.contains { $0.level == .notice && $0.metadata["dk.event"] == "http.retry.transport" })
        #expect(entries.last?.metadata["dk.event"] == "http.operation.completed")
        #expect(entries.allSatisfy { $0.label.hasPrefix("discordkit.http.") && $0.metadata["dk.subsystem"]?.description.hasPrefix("http.") == true })
        #expect(entries.allSatisfy { $0.metadata["dk.event"] != nil })
        #expect(entries.contains { $0.level == .info && $0.metadata["dk.event"] == "http.execute.completed" })
        #expect(Set(entries.compactMap { $0.metadata["dk.trace_id"]?.description }).count == 1)
        #expect(entries.allSatisfy { $0.metadata["dk.span_id"] != nil })
        #expect(!String(describing: entries.map { ($0.message, $0.metadata) }).contains(secret))
    }

    /// A successful exchange exposes each owned phase in order and keeps secret request/body data absent.
    /// - Throws: Unexpected scripted transport, descriptor, admission or response decoding failure.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func successfulExchangeTraceSequence() async throws {
        let recorder = LogRecorder()
        let clock = ManualClock()
        let body = Data("private_response_payload".utf8)
        let source = LoggingResponseBody(data: body)
        let stream = try BodyStream(maximumChunkBytes: body.count, next: { await source.next() }, close: {})
        let transport = try ScriptedHTTPTransport(steps: [{ _ in HTTPResponse(status: 200, body: stream) }])
        let coordinator = RateLimitCoordinator(clock: clock)
        let client = RESTClient(credential: .none, identity: RateLimitIdentity(), transport: transport,
            coordinator: coordinator, clock: clock)
        let endpoint = try Endpoint(method: "GET", path: ["private_path"], authentication: .none,
            successStatuses: [200], retrySafety: .safe, decode: { $0 })
        let result = try await DiscordLog.$loggerFactory.withValue({ recorder.makeLogger($0) }) {
            try await client.execute(endpoint)
        }
        #expect(result == body)
        let events = recorder.entries.compactMap { $0.metadata["dk.event"]?.description }
        let required = ["http.operation.started", "http.execute.validated", "http.attempt.started",
            "http.request.admission", "http.admission.queued", "http.admission.reserve",
            "http.admission.granted", "http.request.encoded", "http.request.submitted",
            "http.response.received", "http.response.body.started", "http.response.body.completed",
            "http.admission.completed", "http.request.completed", "http.attempt.classified",
            "http.decode.started", "http.decode.completed", "http.execute.completed", "http.operation.completed"]
        var remaining = events[...]
        for event in required {
            let index = try #require(remaining.firstIndex(of: event))
            remaining = remaining[remaining.index(after: index)...]
        }
        let received = try #require(recorder.entries.first { $0.metadata["dk.event"] == "http.response.body.completed" })
        #expect(received.level == .trace)
        #expect(received.metadata["dk.bytes"]?.description == String(body.count))
        #expect(received.label == "discordkit.http.execution")
        #expect(recorder.entries.last?.metadata["dk.duration_ns"] != nil)
        #expect(await coordinator.snapshot().activeCount == 0)
        let rendered = String(describing: recorder.entries.map { ($0.message, $0.metadata) })
        #expect(!rendered.contains("private_path") && !rendered.contains("private_response_payload"))
    }

    /// Decoder rejection has its own bounded category and preserves cleanup before the operation fails.
    /// - Throws: Unexpected setup errors; the secret-bearing decoder failure is expected and normalized.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func decoderFailureIsSeparatedAndRedacted() async throws {
        let recorder = LogRecorder()
        let clock = ManualClock()
        let coordinator = RateLimitCoordinator(clock: clock)
        let transport = try ScriptedHTTPTransport(steps: [{ _ in HTTPResponse(status: 200) }])
        let client = RESTClient(credential: .none, identity: RateLimitIdentity(), transport: transport,
            coordinator: coordinator, clock: clock)
        let endpoint = try Endpoint<Data>(method: "GET", path: ["private_decode_route"], authentication: .none,
            successStatuses: [200], retrySafety: .safe, decode: { _ in throw TestSupportFailure.scripted("private_decoder_error") })
        await DiscordLog.$loggerFactory.withValue({ recorder.makeLogger($0) }) {
            await #expect(throws: DiscordError.transport(.invalidResponse)) { try await client.execute(endpoint) }
        }
        #expect(recorder.entries.contains { $0.label == "discordkit.http.codec" && $0.level == .debug && $0.metadata["dk.event"] == "http.decode.rejected" })
        #expect(recorder.entries.last?.metadata["dk.event"] == "http.operation.failed")
        #expect(await coordinator.snapshot().activeCount == 0)
        let rendered = String(describing: recorder.entries.map { ($0.message, $0.metadata) })
        #expect(!rendered.contains("private_decode_route") && !rendered.contains("private_decoder_error"))
    }


    /// Shared reads expose join/release counts, and cache retention/expiry logs never include representation keys.
    /// - Throws: Unexpected coalescer, barrier, cancellation or manual-clock fixture failure.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func readReuseTracePreservesScopedPrivacy() async throws {
        let recorder = LogRecorder()
        let clock = ManualClock()
        let cache = ReadCache(clock: clock)
        let coalescer = RequestCoalescer()
        let identity = RateLimitIdentity()
        let key = HTTPReadKey(identity: identity, representation: "PRIVATE_REPRESENTATION")
        let gate = TestBarrier()
        try await DiscordLog.$loggerFactory.withValue({ recorder.makeLogger($0) }) {
            let first = Task { try await coalescer.run(key: key) { try await gate.wait(); return Data([1, 2]) } }
            defer { first.cancel() }
            while gate.waitingCount == 0 { await Task.yield() }
            let second = Task { try await coalescer.run(key: key) { throw TestSupportFailure.scripted("PRIVATE_UNEXPECTED_REPLAY") } }
            defer { second.cancel() }
            while !recorder.entries.contains(where: { $0.metadata["dk.event"] == "http.coalescing.joined" }) { await Task.yield() }
            gate.open()
            #expect(try await first.value == Data([1, 2]))
            #expect(try await second.value == Data([1, 2]))
            let generation = await cache.generation()
            await cache.insert(Data([1, 2]), for: key, timeToLive: .seconds(1), tags: ["PRIVATE_TAG"], generation: generation)
            #expect(await cache.value(for: key) == Data([1, 2]))
            try clock.advance(by: .seconds(1))
            #expect(await cache.value(for: key) == nil)
            await coalescer.close()
        }
        let entries = recorder.entries
        for event in ["http.coalescing.created", "http.coalescing.joined", "http.coalescing.completed",
            "http.cache.inserted", "http.cache.lookup.hit", "http.cache.removed", "http.cache.expired", "http.cache.lookup.missed"] {
            #expect(entries.contains { $0.metadata["dk.event"]?.description == event && $0.level == .trace })
        }
        let joined = try #require(entries.first { $0.metadata["dk.event"] == "http.coalescing.joined" })
        #expect(joined.metadata["dk.waiters"]?.description == "2")
        let snapshot = await coalescer.snapshot()
        #expect(snapshot.flights == 0 && snapshot.waiters == 0)
        #expect(await cache.snapshot().entries == 0)
        #expect(!String(describing: entries.map { ($0.message, $0.metadata) }).contains("PRIVATE_"))
    }

    /// Cancellation logs a fixed lifecycle event after cleanup and never serializes request/error data.
    /// - Throws: Unexpected setup failures; operation cancellation is expected and observed.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func cancelledExchangeReleasesAdmission() async throws {
        let recorder = LogRecorder()
        let clock = ManualClock()
        let coordinator = RateLimitCoordinator(clock: clock)
        let gate = TestBarrier()
        let transport = try ScriptedHTTPTransport(steps: [{ _ in
            try await gate.wait()
            return HTTPResponse(status: 204)
        }])
        let client = RESTClient(credential: .none, identity: RateLimitIdentity(), transport: transport,
            coordinator: coordinator, clock: clock, retryPolicy: .init(maximumAttempts: 1))
        let endpoint = try Endpoint(method: "GET", path: ["private_cancel_route"], authentication: .none,
            successStatuses: [204], retrySafety: .safe, decode: { $0 })
        await DiscordLog.$loggerFactory.withValue({ recorder.makeLogger($0) }) {
            let task = Task { try await client.execute(endpoint) }
            while gate.waitingCount == 0 { await Task.yield() }
            task.cancel()
            await #expect(throws: CancellationError.self) { try await task.value }
        }
        #expect(await coordinator.snapshot().activeCount == 0)
        #expect(clock.pendingSleepCount == 0)
        #expect(recorder.entries.contains { $0.level == .debug && $0.metadata["dk.event"] == "http.execute.cancelled" })
        #expect(!String(describing: recorder.entries.map { ($0.message, $0.metadata) }).contains("private_cancel_route"))
    }
    /// A permanently latched authority emits one critical transition even when outstanding cleanup fails twice.
    /// - Throws: Unexpected reservation setup failure; injected completion failures are expected.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func unavailableAuthorityLogsCriticalOnce() async throws {
        let recorder = LogRecorder()
        let store = LoggingCompletionFailureStore()
        let coordinator = RateLimitCoordinator(clock: ManualClock(), store: store)
        let firstRequest = RateLimitRequest(identity: .init(), route: "private_first_route")
        let secondRequest = RateLimitRequest(identity: .init(), route: "private_second_route")
        try await DiscordLog.$loggerFactory.withValue({ recorder.makeLogger($0) }) {
            let first = try await coordinator.acquire(firstRequest)
            let second = try await coordinator.acquire(secondRequest)
            for reservation in [first, second] {
                await #expect(throws: RateLimitFailure.coordinatorUnavailable) {
                    try await coordinator.complete(reservation, status: 204, headers: [])
                }
            }
            await #expect(throws: RateLimitFailure.coordinatorUnavailable) {
                try await coordinator.acquire(firstRequest)
            }
        }
        let critical = recorder.entries.filter { $0.level == .critical }
        #expect(critical.count == 1)
        #expect(critical.first?.metadata["dk.event"] == "http.admission.unavailable")
        #expect(critical.first?.metadata.keys.sorted() == ["dk.event", "dk.module", "dk.subsystem"])
        #expect(await store.reserveCount == 2)
        #expect(await store.completionCount == 2)
        #expect(await coordinator.snapshot().activeCount == 0)
        let recorded = String(describing: recorder.entries.map { ($0.message, $0.metadata) })
        #expect(!recorded.contains("private_first_route") && !recorded.contains("private_second_route"))
        #expect(!recorded.contains("private_authority_failure"))
    }

}


/// Injects uncertain completion failures after issuing two ordinary owned reservations.
@available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
private actor LoggingCompletionFailureStore: RateLimitStore {
    typealias Instant = ManualClock.Instant
    private let base = InProcessRateLimitStore<Instant>()
    var reserveCount = 0
    var completionCount = 0

    /// Forwards normal initial admission while recording whether a latched coordinator calls again.
    /// - Parameters:
    ///   - request: Synthetic request scope, never logged.
    ///   - now: Shared manual clock instant.
    /// - Returns: The backing store's reservation or retry.
    /// - Throws: Backing store admission failure.
    func reserve(_ request: RateLimitRequest, now: Instant) async throws -> RateLimitAdmission<Instant> {
        reserveCount += 1
        return try await base.reserve(request, now: now)
    }

    /// Releases fixture ownership, then reports uncertain external authority failure.
    /// - Parameters:
    ///   - reservation: Previously admitted fixture reservation.
    ///   - status: Ignored synthetic status.
    ///   - headers: Ignored synthetic headers.
    ///   - retryAfter: Ignored synthetic delay.
    ///   - global: Ignored synthetic global flag.
    ///   - now: Shared manual clock instant.
    /// - Throws: A secret-bearing test error that diagnostics must never render.
    func complete(_ reservation: RateLimitReservation<Instant>, status: Int, headers: [HTTPHeader],
        retryAfter: Duration?, global: Bool, now: Instant) async throws {
        completionCount += 1
        try await base.release(reservation, outcome: .uncertain, now: now)
        throw TestSupportFailure.scripted("private_authority_failure")
    }

    /// Forwards explicit release for fixture cleanup.
    /// - Parameters:
    ///   - reservation: Previously admitted fixture reservation.
    ///   - outcome: Caller submission evidence.
    ///   - now: Shared manual clock instant.
    /// - Throws: Backing store release failure.
    func release(_ reservation: RateLimitReservation<Instant>, outcome: RateLimitReleaseOutcome, now: Instant) async throws {
        try await base.release(reservation, outcome: outcome, now: now)
    }

    /// Reads backing accounting without creating any diagnostic text.
    /// - Returns: Bounded aggregate counts.
    func snapshot() async -> SchedulingSnapshot { await base.snapshot() }
}


/// A finite single-chunk source used to verify byte-count diagnostics without retained payload output.
private actor LoggingResponseBody {
    private var data: Data?

    /// Stores one synthetic response chunk; construction performs no work.
    /// - Parameter data: Private fixture bytes transferred on the first pull only.
    init(data: Data) { self.data = data }

    /// Transfers the chunk once, then reports terminal EOF on all subsequent pulls.
    /// - Returns: The stored fixture bytes, or nil after the first read.
    func next() -> Data? {
        defer { data = nil }
        return data
    }
}
