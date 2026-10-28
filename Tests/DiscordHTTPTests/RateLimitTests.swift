// File: Tests/DiscordHTTPTests/RateLimitTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordTransport
import DiscordTestSupport
import Foundation
import Testing
@testable import DiscordHTTP

/// Virtual-time conformance coverage for shared authority and bounded queue ownership.
@Suite struct RateLimitTests {
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    typealias Instant = ManualClock.Instant

    /// Extracts required admission while recording a useful test failure for refusal.
    /// - Parameters:
    ///   - store: Authority under test.
    ///   - request: Explicit identity/resource scopes.
    ///   - now: Virtual admission instant.
    /// - Returns: Granted single-use token.
    /// - Throws: Store failures or a failed admission requirement.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    private func admitted(_ store: any RateLimitStore<Instant>, _ request: RateLimitRequest,
                          at now: Instant) async throws -> RateLimitReservation<Instant> {
        let result = try await store.reserve(request, now: now)
        guard case .admitted(let token) = result else {
            Issue.record("Expected admission")
            throw RateLimitFailure.coordinatorUnavailable
        }
        return token
    }

    /// Asserts exact refusal time instead of merely invoking the authority.
    /// - Parameters:
    ///   - store: Authority under test.
    ///   - request: Attempted request.
    ///   - now: Virtual attempt time.
    ///   - expected: Earliest permitted retry time.
    /// - Throws: Unexpected store errors.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    private func expectRetry(_ store: any RateLimitStore<Instant>, _ request: RateLimitRequest,
                             at now: Instant, until expected: Instant) async throws {
        switch try await store.reserve(request, now: now) {
        case .retry(let date): #expect(date == expected)
        case .admitted: Issue.record("Unexpected admission before budget reset")
        }
    }

    /// Verifies opaque identity reuse, conservative cold discovery and fractional reset headers.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func learnsFractionalBucketAndPreservesOpaqueIdentity() async throws {
        let id = UUID()
        #expect(RateLimitIdentity(id) == RateLimitIdentity(id))
        #expect(RateLimitIdentity() != RateLimitIdentity())
        let store = InProcessRateLimitStore<Instant>()
        let request = RateLimitRequest(identity: .init(id), route: "GET /channels/{channel}/messages", majorResource: "1")
        let now = Instant()
        let first = try await admitted(store, request, at: now)
        try await expectRetry(store, request, at: now, until: now.advanced(by: .seconds(1)))
        try await store.complete(first, status: 200, headers: [
            .init(name: "X-RateLimit-Bucket", value: "messages"),
            .init(name: "x-ratelimit-limit", value: "2"),
            .init(name: "X-RATELIMIT-REMAINING", value: "0"),
            .init(name: "X-RateLimit-Reset-After", value: "0.125")
        ], now: now)
        try await expectRetry(store, request, at: now, until: now.advanced(by: .milliseconds(125)))
        let next = try await admitted(store, request, at: now.advanced(by: .milliseconds(125)))
        try await store.release(next, outcome: .notSent, now: now.advanced(by: .milliseconds(125)))
        #expect(await store.snapshot().activeCount == 0)
    }

    /// Proves bucket hashes retain major-resource isolation and combine sibling routes safely.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func majorResourcesAndProvisionalMerging() async throws {
        let store = InProcessRateLimitStore<Instant>()
        let identity = RateLimitIdentity()
        let a = RateLimitRequest(identity: identity, route: "GET /channels/{id}/a", majorResource: "1")
        let b = RateLimitRequest(identity: identity, route: "POST /channels/{id}/b", majorResource: "1")
        let other = RateLimitRequest(identity: identity, route: a.route, majorResource: "2")
        let now = Instant()
        let first = try await admitted(store, a, at: now)
        let second = try await admitted(store, b, at: now)
        let headers: [HTTPHeader] = [.init(name: "X-RateLimit-Bucket", value: "same"),
                                    .init(name: "X-RateLimit-Limit", value: "2"),
                                    .init(name: "X-RateLimit-Remaining", value: "0"),
                                    .init(name: "X-RateLimit-Reset-After", value: "2")]
        try await store.complete(first, status: 200, headers: headers, now: now)
        try await store.complete(second, status: 200, headers: headers, now: now)
        try await expectRetry(store, a, at: now, until: now.advanced(by: .seconds(2)))
        try await expectRetry(store, b, at: now, until: now.advanced(by: .seconds(2)))
        let independent = try await admitted(store, other, at: now)
        try await store.release(independent, outcome: .uncertain, now: now)
        #expect(await store.snapshot().activeCount == 0)
    }

    /// Shared-resource 429s survive credential rotation and do not consume another resource's budget.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func sharedLimitsCrossCredentialsAndRotation() async throws {
        let store = InProcessRateLimitStore<Instant>()
        let now = Instant()
        let firstRequest = RateLimitRequest(identity: .init(), route: "GET /channels/{id}", majorResource: "1")
        let first = try await admitted(store, firstRequest, at: now)
        try await store.complete(first, status: 429, headers: [
            .init(name: "X-RateLimit-Scope", value: "shared"),
            .init(name: "Retry-After", value: "0.5")
        ], retryAfter: .milliseconds(750), now: now)
        let rotated = RateLimitRequest(identity: .init(), route: firstRequest.route, majorResource: "1")
        try await expectRetry(store, rotated, at: now, until: now.advanced(by: .milliseconds(750)))
        let unrelated = RateLimitRequest(identity: rotated.identity, route: firstRequest.route, majorResource: "2")
        let token = try await admitted(store, unrelated, at: now)
        try await store.release(token, outcome: .notSent, now: now)
    }

    /// Global 429s block other routes for the credential while exempt interaction work proceeds.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func globalLimitsAndInteractionExemption() async throws {
        let store = InProcessRateLimitStore<Instant>()
        let now = Instant()
        let identity = RateLimitIdentity()
        let token = try await admitted(store, .init(identity: identity, route: "GET /users/@me"), at: now)
        try await store.complete(token, status: 429, headers: [], retryAfter: .seconds(2), global: true, now: now)
        try await expectRetry(store, .init(identity: identity, route: "GET /applications/@me"), at: now,
                              until: now.advanced(by: .seconds(2)))
        let exempt = try await admitted(store, .init(identity: identity, route: "POST /interactions/{id}/callback",
                                                     usesGlobalLimit: false), at: now)
        try await store.release(exempt, outcome: .notSent, now: now)
        let independent = try await admitted(store, .init(identity: .init(), route: "GET /users/@me"), at: now)
        try await store.release(independent, outcome: .uncertain, now: now)
    }

    /// In-flight requests are subtracted from returned remaining counts and retained on release.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func outstandingReservationsDoNotGetRefunded() async throws {
        let store = InProcessRateLimitStore<Instant>()
        let now = Instant()
        let request = RateLimitRequest(identity: .init(), route: "GET /test")
        let first = try await admitted(store, request, at: now)
        try await store.complete(first, status: 200, headers: [
            .init(name: "X-RateLimit-Limit", value: "3"),
            .init(name: "X-RateLimit-Remaining", value: "2"),
            .init(name: "X-RateLimit-Reset-After", value: "1")
        ], now: now)
        let a = try await admitted(store, request, at: now)
        let b = try await admitted(store, request, at: now)
        try await store.complete(a, status: 200, headers: [.init(name: "X-RateLimit-Remaining", value: "2")], now: now)
        try await store.release(b, outcome: .notSent, now: now)
        try await expectRetry(store, request, at: now, until: now.advanced(by: .seconds(1)))
        await #expect(throws: RateLimitFailure.unknownReservation) {
            try await store.release(b, outcome: .uncertain, now: now)
        }
        #expect(await store.snapshot().activeCount == 0)
    }

    /// Simultaneous workers sharing an authority cannot both consume the cold-route token.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func concurrentWorkersShareOneAuthority() async throws {
        let store = InProcessRateLimitStore<Instant>()
        let request = RateLimitRequest(identity: .init(), route: "GET /same")
        let tokens = try await withThrowingTaskGroup(of: RateLimitReservation<Instant>?.self) { group in
            for _ in 0..<20 {
                group.addTask {
                    if case .admitted(let token) = try await store.reserve(request, now: Instant()) { return token }
                    return nil
                }
            }
            var tokens: [RateLimitReservation<Instant>] = []
            for try await token in group { if let token { tokens.append(token) } }
            return tokens
        }
        #expect(tokens.count == 1)
        for token in tokens { try await store.release(token, outcome: .uncertain, now: Instant()) }
        #expect(await store.snapshot().activeCount == 0)
    }

    /// Invalid-response protection spans rotated credentials sharing an egress and excludes shared 429s.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func invalidRequestPressureIsEgressScoped() async throws {
        let policy = SchedulingPolicy(invalidRequestThreshold: 2, invalidRequestWindow: .seconds(10))
        let store = InProcessRateLimitStore<Instant>(policy: policy)
        let egress = UUID()
        let now = Instant()
        for status in [401, 403] {
            let token = try await admitted(store, .init(identity: .init(), route: "GET /test", egress: egress), at: now)
            try await store.complete(token, status: status, headers: [], now: now)
        }
        let request = RateLimitRequest(identity: .init(), route: "GET /other", egress: egress)
        try await expectRetry(store, request, at: now, until: now.advanced(by: .seconds(10)))
        let token = try await admitted(store, request, at: now.advanced(by: .seconds(10)))
        try await store.complete(token, status: 429, headers: [.init(name: "X-RateLimit-Scope", value: "shared")],
                                 now: now.advanced(by: .seconds(10)))
        let rotated = try await admitted(store, .init(identity: .init(), route: "GET /other", egress: egress),
                                         at: now.advanced(by: .seconds(10)))
        try await store.release(rotated, outcome: .notSent, now: now.advanced(by: .seconds(10)))
    }

    /// Depleted metadata cannot be evicted to admit a new route; expired provisional state can be reclaimed.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func metadataExhaustionPreservesDepletedBudget() async throws {
        let store = InProcessRateLimitStore<Instant>(policy: .init(maximumMetadata: 2))
        let now = Instant()
        let identity = RateLimitIdentity()
        let request = RateLimitRequest(identity: identity, route: "GET /first")
        let token = try await admitted(store, request, at: now)
        try await store.release(token, outcome: .uncertain, now: now)
        await #expect(throws: RateLimitFailure.metadataFull) {
            _ = try await store.reserve(.init(identity: identity, route: "GET /new"), now: now)
        }
        try await expectRetry(store, request, at: now, until: now.advanced(by: .seconds(1)))
        #expect(await store.snapshot().metadataCount <= 2)
        let next = try await admitted(store, .init(identity: identity, route: "GET /new"), at: now.advanced(by: .seconds(1)))
        try await store.release(next, outcome: .notSent, now: now.advanced(by: .seconds(1)))
        #expect(await store.snapshot().metadataCount <= 2)
    }

    /// Inclusive expiry clears ownership, rejects stale headers, and never refunds a live window.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func expiredOwnershipCannotLearnOrLeakConcurrency() async throws {
        let store = InProcessRateLimitStore<Instant>(policy: .init(reservationLifetime: .milliseconds(100)))
        let now = Instant()
        let request = RateLimitRequest(identity: .init(), route: "GET /test")
        let token = try await admitted(store, request, at: now)
        await #expect(throws: RateLimitFailure.reservationExpired) {
            try await store.complete(token, status: 200, headers: [.init(name: "X-RateLimit-Remaining", value: "100")],
                                     now: now.advanced(by: .milliseconds(100)))
        }
        #expect(await store.snapshot().activeCount == 0)
        try await expectRetry(store, request, at: now.advanced(by: .milliseconds(100)), until: now.advanced(by: .seconds(1)))
        let next = try await admitted(store, request, at: now.advanced(by: .seconds(1)))
        try await store.release(next, outcome: .notSent, now: now.advanced(by: .seconds(1)))
    }

    /// Malformed/nonfinite server values cannot expand quota or overflow Duration conversion.
    /// - Parameter invalid: Invalid count/delay spelling exercised across all parsed headers.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: ["NaN", "inf", "-1", "9999999999999999999999", "not-a-number"])
    func malformedHeadersRemainConservative(_ invalid: String) async throws {
        let store = InProcessRateLimitStore<Instant>()
        let now = Instant()
        let request = RateLimitRequest(identity: .init(), route: "GET /test")
        let token = try await admitted(store, request, at: now)
        try await store.complete(token, status: 429, headers: [
            .init(name: "Retry-After", value: invalid),
            .init(name: "X-RateLimit-Remaining", value: invalid),
            .init(name: "X-RateLimit-Reset-After", value: invalid)
        ], now: now)
        try await expectRetry(store, request, at: now, until: now.advanced(by: .seconds(1)))
    }

    /// Validation prevents negative byte accounting and unbounded route metadata before allocation.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func rejectsInvalidAdmissionScopes() async throws {
        let store = InProcessRateLimitStore<Instant>()
        for request in [RateLimitRequest(identity: .init(), route: ""),
                        .init(identity: .init(), route: "GET /x", queuedBytes: -1),
                        .init(identity: .init(), route: String(repeating: "x", count: 1_025)),
                        .init(identity: .init(), route: "GET /x", majorResource: String(repeating: "x", count: 257))] {
            await #expect(throws: RateLimitFailure.invalidRequest) { _ = try await store.reserve(request, now: Instant()) }
        }
        #expect(await store.snapshot() == .init(queuedCount: 0, queuedBytes: 0, activeCount: 0, metadataCount: 0))
    }

    /// Ten-times offered queue overload never exceeds count/byte budgets, and canceled work disappears promptly.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func queueOverloadAndCancellationAreBounded() async throws {
        let sleeping = TestBarrier()
        let clock = ManualClock(onSleepScheduled: { sleeping.open() })
        let policy = SchedulingPolicy(maximumQueuedRequests: 1, maximumQueuedRequestsPerIdentity: 1,
                                      maximumQueuedBytes: 5, maximumQueuedBytesPerIdentity: 5)
        let coordinator = RateLimitCoordinator(clock: clock, policy: policy)
        let request = RateLimitRequest(identity: .init(), route: "GET /test", queuedBytes: 5)
        let first = try await coordinator.acquire(request)
        let pending = Task { try await coordinator.acquire(request) }
        try await sleeping.wait()
        for _ in 0..<10 {
            await #expect(throws: RateLimitFailure.queueFull) { _ = try await coordinator.acquire(request) }
            #expect(await coordinator.snapshot().queuedCount == 1)
            #expect(await coordinator.snapshot().queuedBytes == 5)
        }
        pending.cancel()
        await #expect(throws: CancellationError.self) { _ = try await pending.value }
        #expect(await coordinator.snapshot().queuedCount == 0)
        #expect(await coordinator.snapshot().queuedBytes == 0)
        #expect(clock.pendingSleepCount == 0)
        try await coordinator.release(first, outcome: .notSent)
        await coordinator.close()
        await #expect(throws: RateLimitFailure.closed) { _ = try await coordinator.acquire(request) }
    }

    /// A hot blocked identity does not prevent an unrelated eligible identity from admission.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func unrelatedIdentityBypassesBlockedQueue() async throws {
        let sleeping = TestBarrier()
        let clock = ManualClock(onSleepScheduled: { sleeping.open() })
        let coordinator = RateLimitCoordinator(clock: clock)
        let hot = RateLimitRequest(identity: .init(), route: "GET /test")
        let first = try await coordinator.acquire(hot)
        let blocked = Task { try await coordinator.acquire(hot) }
        try await sleeping.wait()
        let unrelated = try await coordinator.acquire(.init(identity: .init(), route: hot.route))
        #expect(unrelated.request.identity != hot.identity)
        #expect(await coordinator.snapshot().queuedCount == 1)
        try await coordinator.release(unrelated, outcome: .notSent)
        blocked.cancel()
        await #expect(throws: CancellationError.self) { _ = try await blocked.value }
        try await coordinator.release(first, outcome: .uncertain)
        #expect(await coordinator.snapshot().activeCount == 0)
    }

    /// FIFO queues reject at inclusive deadlines and close wakes pending work without advancing time.
    /// - Parameter close: Whether to close the coordinator or advance to its inclusive deadline.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [false, true])
    func deadlinesAndCloseRemoveOwnedSleepers(_ close: Bool) async throws {
        let sleeping = TestBarrier()
        let clock = ManualClock(onSleepScheduled: { sleeping.open() })
        let coordinator = RateLimitCoordinator(clock: clock)
        let request = RateLimitRequest(identity: .init(), route: "GET /test")
        let token = try await coordinator.acquire(request)
        let pending = Task { try await coordinator.acquire(request, deadline: clock.now.advanced(by: .milliseconds(5))) }
        try await sleeping.wait()
        if close {
            await coordinator.close()
            await #expect(throws: RateLimitFailure.closed) { _ = try await pending.value }
        } else {
            try clock.advance(by: .milliseconds(5))
            await #expect(throws: RateLimitFailure.deadlineExceeded) { _ = try await pending.value }
        }
        #expect(clock.pendingSleepCount == 0)
        #expect(await coordinator.snapshot().queuedCount == 0)
        try await coordinator.release(token, outcome: .notSent)
        await coordinator.close()
    }
    /// A fractional 429 delay is observed exactly in virtual time with no early admission.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func queuedAttemptWaitsForFractionalServerDelay() async throws {
        let sleeping = TestBarrier()
        let clock = ManualClock(onSleepScheduled: { sleeping.open() })
        let coordinator = RateLimitCoordinator(clock: clock)
        let request = RateLimitRequest(identity: .init(), route: "GET /limited")
        let first = try await coordinator.acquire(request)
        try await coordinator.complete(first, status: 429, headers: [], retryAfter: .milliseconds(125))
        let pending = Task { try await coordinator.acquire(request) }
        try await sleeping.wait()
        try clock.advance(by: .milliseconds(124))
        #expect(await coordinator.snapshot().activeCount == 0)
        #expect(await coordinator.snapshot().queuedCount == 1)
        try clock.advance(by: .milliseconds(1))
        let token = try await pending.value
        #expect(clock.now == Instant(offset: .milliseconds(125)))
        try await coordinator.release(token, outcome: .uncertain)
        #expect(clock.pendingSleepCount == 0)
    }

    /// Whole-operation ownership spans retries/backoff and permits unrelated partitions.
    /// - Parameter cancel: Whether the queued same-partition operation is canceled or runs after FIFO release.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [false, true])
    func wholeOperationOrderingAndCancellation(_ cancel: Bool) async throws {
        let entered = TestBarrier()
        let release = TestBarrier()
        let sleeping = TestBarrier()
        let clock = ManualClock(onSleepScheduled: { sleeping.open() })
        let coordinator = RateLimitCoordinator(clock: clock)
        let request = RateLimitRequest(identity: .init(), route: "POST /ordered", queuedBytes: 3)
        let first = Task {
            try await coordinator.withOrdering(request: request) {
                entered.open()
                try await release.wait()
                return 1
            }
        }
        try await entered.wait()
        let second = Task { try await coordinator.withOrdering(request: request) { 2 } }
        try await sleeping.wait()
        #expect(await coordinator.snapshot().orderedOperationsCount == 1)
        #expect(await coordinator.snapshot().queuedBytes == 3)
        let independent = try await coordinator.withOrdering(request: .init(identity: .init(), route: request.route)) { 3 }
        #expect(independent == 3)
        if cancel { second.cancel() }
        release.open()
        #expect(try await first.value == 1)
        if cancel {
            await #expect(throws: CancellationError.self) { _ = try await second.value }
        } else {
            try clock.advance(by: .milliseconds(10))
            #expect(try await second.value == 2)
        }
        #expect(await coordinator.snapshot().orderedOperationsCount == 0)
        #expect(await coordinator.snapshot().queuedCount == 0)
        #expect(clock.pendingSleepCount == 0)
        await #expect(throws: RateLimitFailure.invalidRequest) {
            _ = try await coordinator.withOrdering(request: request) { throw RateLimitFailure.invalidRequest } as Int
        }
        #expect(await coordinator.snapshot().orderedOperationsCount == 0)
    }

    /// Ordering waiters share bounded count/byte admission and shutdown wakes them immediately.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func orderingQueueOverloadCloseAndValidation() async throws {
        let entered = TestBarrier()
        let release = TestBarrier()
        let sleeping = TestBarrier()
        let clock = ManualClock(onSleepScheduled: { sleeping.open() })
        let coordinator = RateLimitCoordinator(clock: clock, policy: .init(maximumQueuedRequests: 1))
        let request = RateLimitRequest(identity: .init(), route: "POST /ordered")
        let first = Task {
            try await coordinator.withOrdering(request: request) {
                entered.open(); try await release.wait(); return 1
            }
        }
        try await entered.wait()
        let pending = Task { try await coordinator.withOrdering(request: request) { 2 } }
        try await sleeping.wait()
        await #expect(throws: RateLimitFailure.queueFull) {
            _ = try await coordinator.withOrdering(request: request) { 3 }
        }
        await coordinator.close()
        await #expect(throws: RateLimitFailure.closed) { _ = try await pending.value }
        release.open()
        #expect(try await first.value == 1)
        #expect(await coordinator.snapshot().orderedOperationsCount == 0)
        #expect(await coordinator.snapshot().queuedCount == 0)
        #expect(clock.pendingSleepCount == 0)
        let other = RateLimitCoordinator(clock: clock)
        await #expect(throws: RateLimitFailure.invalidRequest) {
            _ = try await other.withOrdering(request: .init(identity: .init(), route: "POST /x", queuedBytes: -1)) { 0 }
        }
        await #expect(throws: RateLimitFailure.deadlineExceeded) {
            _ = try await other.withOrdering(request: request, deadline: clock.now) { 0 }
        }
    }

    /// An injected authority outage never admits local work and latches the coordinator closed to admission.
    /// - Parameter untrusted: Whether the failed adapter throws a closed category or an unsafe secret-bearing error.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [false, true])
    func injectedAuthorityFailureNeverFallsBack(_ untrusted: Bool) async throws {
        let store = UnavailableRateStore(untrusted: untrusted)
        let coordinator = RateLimitCoordinator(clock: ManualClock(), store: store)
        let request = RateLimitRequest(identity: .init(), route: "GET /x")
        await #expect(throws: RateLimitFailure.coordinatorUnavailable) { _ = try await coordinator.acquire(request) }
        await #expect(throws: RateLimitFailure.coordinatorUnavailable) { _ = try await coordinator.acquire(request) }
        #expect(await store.attempts == 1)
        #expect(await coordinator.snapshot().activeCount == 0)
        #expect(await coordinator.snapshot().queuedCount == 0)
    }

}

/// A deterministic failed external authority used to verify absence of local fallback.
@available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
private actor UnavailableRateStore: RateLimitStore {
    typealias Instant = ManualClock.Instant
    var attempts = 0
    let untrusted: Bool

    /// Configures a safe-category or deliberately untrusted external-store failure.
    /// - Parameter untrusted: True to throw an error containing a synthetic secret, false for a closed category.
    init(untrusted: Bool) { self.untrusted = untrusted }

    /// Records the attempt and simulates an unavailable shared coordinator.
    /// - Parameters:
    ///   - request: Requested admission scopes; never admitted.
    ///   - now: Virtual attempt instant, ignored because the authority is unavailable.
    /// - Returns: Never returns admission.
    /// - Throws: coordinatorUnavailable or a secret-bearing test error according to fixture configuration.
    func reserve(_ request: RateLimitRequest, now: Instant) throws -> RateLimitAdmission<Instant> {
        attempts += 1
        if untrusted { throw UntrustedAuthorityError.failed("synthetic_secret") }
        throw RateLimitFailure.coordinatorUnavailable
    }

    /// Rejects completion because this fixture never issues a token.
    /// - Parameters:
    ///   - reservation: Unissued token.
    ///   - status: Ignored response status.
    ///   - headers: Ignored wire metadata.
    ///   - retryAfter: Ignored decoded delay.
    ///   - global: Ignored decoded flag.
    ///   - now: Ignored virtual observation instant.
    /// - Throws: coordinatorUnavailable unconditionally.
    func complete(_ reservation: RateLimitReservation<Instant>, status: Int, headers: [HTTPHeader],
                  retryAfter: Duration?, global: Bool, now: Instant) throws {
        throw RateLimitFailure.coordinatorUnavailable
    }

    /// Rejects release because no token can be owned by this failed authority.
    /// - Parameters:
    ///   - reservation: Unissued token.
    ///   - outcome: Ignored send uncertainty.
    ///   - now: Ignored virtual time.
    /// - Throws: coordinatorUnavailable unconditionally.
    func release(_ reservation: RateLimitReservation<Instant>, outcome: RateLimitReleaseOutcome, now: Instant) throws {
        throw RateLimitFailure.coordinatorUnavailable
    }

    /// Reports that an unavailable authority has issued no local ownership.
    /// - Returns: Zero owned resources; no fallback reservations are represented.
    func snapshot() -> SchedulingSnapshot { .init(queuedCount: 0, queuedBytes: 0, activeCount: 0, metadataCount: 0) }
}

/// An intentionally unsafe fixture error that must never escape authority normalization.
private enum UntrustedAuthorityError: Error {
    case failed(String)
}
