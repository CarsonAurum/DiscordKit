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
        #expect(entries.contains { $0.level == .debug && $0.metadata["dk.event"] == "http.retry.transport" })
        #expect(entries.last?.metadata["dk.event"] == "http.execute.completed")
        #expect(entries.allSatisfy { $0.label == "discordkit.http" && $0.metadata["dk.subsystem"] == "http" })
        #expect(entries.allSatisfy { $0.metadata["dk.event"] != nil && $0.level != .info && $0.level != .notice })
        #expect(!String(describing: entries.map { ($0.message, $0.metadata) }).contains(secret))
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
        #expect(critical.first?.metadata.keys.sorted() == ["dk.event", "dk.subsystem"])
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
