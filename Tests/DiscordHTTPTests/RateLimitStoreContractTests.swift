// File: Tests/DiscordHTTPTests/RateLimitStoreContractTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordTestSupport
import DiscordTransport
import Foundation
import Testing
@testable import DiscordHTTP

/// Reusable, adapter-facing checks for the atomic `RateLimitStore` boundary.
///
/// An adapter's test target can construct this harness with a fresh-store factory,
/// translating `ManualClock.Instant` into its backend's test time domain if needed,
/// and call `verify()`. The factory must honor each supplied scheduling policy and
/// isolate successive stores, including their remote keys. No wall-clock advance,
/// credentials, network service or production dependency is needed by these tests.
/// Passing a forwarding fixture demonstrates reuse; it does not certify a durable
/// backend's transactions, crash fencing or cross-host clock translation.
@available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
struct RateLimitStoreContract<Store: RateLimitStore>: Sendable where Store.Instant == ManualClock.Instant {
    typealias Instant = ManualClock.Instant
    private let makeStore: @Sendable (SchedulingPolicy) -> Store
    private let setUnavailable: (@Sendable (Store, Bool) async -> Void)?

    /// Configures the same contract scenarios for an arbitrary authority adapter.
    /// - Parameters:
    ///   - makeStore: Creates independent empty state for the exact finite policy supplied.
    ///     The returned adapter must share one authority across its concurrent callers.
    ///   - setUnavailable: Optional deterministic outage injection. `true` must make every
    ///     mutating boundary fail closed; `false` restores the same state without resetting
    ///     consumed quota or ownership. Nil omits only this fault-injection scenario.
    init(makeStore: @escaping @Sendable (SchedulingPolicy) -> Store,
         setUnavailable: (@Sendable (Store, Bool) async -> Void)? = nil) {
        self.makeStore = makeStore
        self.setUnavailable = setUnavailable
    }

    /// Runs independent atomicity, scope, uncertainty, ownership and validation scenarios.
    ///
    /// All instants are explicit offsets in one scenario-local virtual time domain.
    /// Competing workers are task-group children, joined before assertions or cleanup.
    /// Restrictions may conservatively extend retry times but cannot permit early sends.
    /// - Throws: Unexpected adapter failures or a failed required admission. Swift Testing
    ///   records quota, isolation, cleanup or closed-error contract violations as issues.
    func verify() async throws {
        try await verifyCompetingReservations()
        try await verifyLearnedMajorScopes()
        try await verifyGlobalAndSharedScopes()
        try await verifyUncertainDebits()
        try await verifyValidationAndExpiredOwnership()
        if let setUnavailable { try await verifyOutage(setUnavailable) }
    }

    /// Proves competing workers cannot double-spend a cold or learned route allowance.
    /// Returned remaining counts cannot refund the other worker's possible send.
    /// - Throws: Unexpected factory, reservation or completion failures.
    private func verifyCompetingReservations() async throws {
        let store = makeStore(.init(maximumConcurrentRequestsPerIdentity: 32))
        let now = Instant()
        let request = RateLimitRequest(identity: .init(), route: "GET /contract/atomic")
        let cold = try await compete(store, request: request, now: now)
        #expect(cold.count == 1)
        let first = try #require(cold.first)
        #expect(first.request == request)
        #expect(first.expiresAt > now)
        #expect(await store.snapshot().activeCount == 1)
        try await store.complete(first, status: 200, headers: [
            .init(name: "X-RateLimit-Limit", value: "3"),
            .init(name: "X-RateLimit-Remaining", value: "2"),
            .init(name: "X-RateLimit-Reset-After", value: "0.25")
        ], retryAfter: nil, global: false, now: now)
        let learned = try await compete(store, request: request, now: now)
        #expect(learned.count == 2)
        let completed = try #require(learned.first)
        try await store.complete(completed, status: 200, headers: [
            .init(name: "X-RateLimit-Remaining", value: "2")
        ], retryAfter: nil, global: false, now: now)
        for token in learned.dropFirst() { try await store.release(token, outcome: .uncertain, now: now) }
        try await expectBlocked(store, request: request, now: now, until: now.advanced(by: .milliseconds(250)))
        #expect(await store.snapshot().activeCount == 0)
    }

    /// Checks case-insensitive fractional headers, sibling bucket merging and major isolation.
    /// The same learned hash cannot combine two distinct channel resources.
    /// - Throws: Unexpected reservation or response-observation failures.
    private func verifyLearnedMajorScopes() async throws {
        let store = makeStore(.init())
        let now = Instant(), identity = RateLimitIdentity()
        let firstRoute = RateLimitRequest(identity: identity, route: "GET /channels/{id}/contract", majorResource: "1")
        let siblingRoute = RateLimitRequest(identity: identity, route: "POST /channels/{id}/contract", majorResource: "1")
        let a = try await admit(store, request: firstRoute, now: now)
        let b = try await admit(store, request: siblingRoute, now: now)
        let headers: [HTTPHeader] = [
            .init(name: "x-ratelimit-bucket", value: "contract-bucket"),
            .init(name: "X-RATELIMIT-LIMIT", value: "2"),
            .init(name: "x-ratelimit-remaining", value: "0"),
            .init(name: "X-RateLimit-Reset-After", value: "0.125")
        ]
        for token in [a, b] {
            try await store.complete(token, status: 200, headers: headers, retryAfter: nil, global: false, now: now)
        }
        for request in [firstRoute, siblingRoute] {
            try await expectBlocked(store, request: request, now: now, until: now.advanced(by: .milliseconds(125)))
        }
        let other = try await admit(store, request: .init(identity: identity, route: firstRoute.route, majorResource: "2"), now: now)
        try await store.release(other, outcome: .notSent, now: now)
        #expect(await store.snapshot().activeCount == 0)
        #expect(await store.snapshot().metadataCount <= SchedulingPolicy().maximumMetadata)
    }

    /// Composes global body/header delays, interaction exemption and credential-independent resources.
    /// A resource-scoped 429 must survive an opaque credential rotation.
    /// - Throws: Unexpected admission or response-observation failures.
    private func verifyGlobalAndSharedScopes() async throws {
        let store = makeStore(.init())
        let now = Instant(), identity = RateLimitIdentity()
        let original = RateLimitRequest(identity: identity, route: "GET /contract/global")
        let token = try await admit(store, request: original, now: now)
        try await store.complete(token, status: 429, headers: [.init(name: "Retry-After", value: "1.5")],
                                 retryAfter: .seconds(2), global: true, now: now)
        try await expectBlocked(store, request: .init(identity: identity, route: "GET /contract/other"),
                                now: now, until: now.advanced(by: .seconds(2)))
        let exempt = try await admit(store, request: .init(identity: identity, route: "POST /interactions/{id}/callback",
                                                         usesGlobalLimit: false), now: now)
        try await store.release(exempt, outcome: .notSent, now: now)
        let independent = try await admit(store, request: .init(identity: .init(), route: original.route), now: now)
        try await store.release(independent, outcome: .uncertain, now: now)

        let resourceStore = makeStore(.init())
        let resource = RateLimitRequest(identity: .init(), route: "GET /channels/{id}/contract", majorResource: "1")
        let shared = try await admit(resourceStore, request: resource, now: now)
        try await resourceStore.complete(shared, status: 429, headers: [
            .init(name: "X-RateLimit-Scope", value: "shared"), .init(name: "Retry-After", value: "1")
        ], retryAfter: .milliseconds(1_250), global: false, now: now)
        let rotated = RateLimitRequest(identity: .init(), route: resource.route, majorResource: resource.majorResource)
        try await expectBlocked(resourceStore, request: rotated, now: now, until: now.advanced(by: .milliseconds(1_250)))
        let other = try await admit(resourceStore, request: .init(identity: rotated.identity, route: resource.route,
                                                                majorResource: "2"), now: now)
        try await resourceStore.release(other, outcome: .notSent, now: now)
        #expect(await store.snapshot().activeCount == 0)
        #expect(await resourceStore.snapshot().activeCount == 0)
    }

    /// Checks that both release outcomes clear ownership without refunding a possible quota debit.
    /// Reusing a consumed token is rejected, while the configured window eventually permits work.
    /// - Throws: Unexpected reservation/release failures.
    private func verifyUncertainDebits() async throws {
        for outcome in [RateLimitReleaseOutcome.notSent, .uncertain] {
            let policy = SchedulingPolicy()
            let store = makeStore(policy), now = Instant()
            let request = RateLimitRequest(identity: .init(), route: "POST /contract/uncertain")
            let token = try await admit(store, request: request, now: now)
            try await store.release(token, outcome: outcome, now: now)
            await #expect(throws: RateLimitFailure.unknownReservation) {
                try await store.release(token, outcome: outcome, now: now)
            }
            try await expectBlocked(store, request: request, now: now, until: now.advanced(by: policy.provisionalWindow))
            #expect(await store.snapshot().activeCount == 0)
            let later = now.advanced(by: policy.provisionalWindow)
            let next = try await admit(store, request: request, now: later)
            try await store.release(next, outcome: .uncertain, now: later)
        }
    }

    /// Checks closed validation/ownership errors and rejects stale response learning at inclusive expiry.
    /// Expired completion still clears retained concurrency and cannot manufacture new allowance.
    /// - Throws: Unexpected adapter failures outside the explicitly asserted closed error categories.
    private func verifyValidationAndExpiredOwnership() async throws {
        let store = makeStore(.init(reservationLifetime: .milliseconds(100)))
        let now = Instant(), identity = RateLimitIdentity()
        for request in [RateLimitRequest(identity: identity, route: ""),
                        .init(identity: identity, route: "GET /contract/invalid", queuedBytes: -1)] {
            await #expect(throws: RateLimitFailure.invalidRequest) { _ = try await store.reserve(request, now: now) }
        }
        #expect(await store.snapshot().activeCount == 0)
        let request = RateLimitRequest(identity: identity, route: "GET /contract/expiry")
        let token = try await admit(store, request: request, now: now)
        await #expect(throws: RateLimitFailure.reservationExpired) {
            try await store.complete(token, status: 200, headers: [.init(name: "X-RateLimit-Remaining", value: "100")],
                                     retryAfter: nil, global: false, now: token.expiresAt)
        }
        await #expect(throws: RateLimitFailure.unknownReservation) {
            try await store.release(token, outcome: .uncertain, now: token.expiresAt)
        }
        #expect(await store.snapshot().activeCount == 0)
        try await expectBlocked(store, request: request, now: token.expiresAt, until: now.advanced(by: .seconds(1)))
    }

    /// Injects a temporary outage while ownership exists and proves recovery retains its original debit.
    /// - Parameter changeAvailability: Fixture hook preserving the same authority across outage/recovery.
    /// - Throws: Unexpected failures outside the expected coordinator-unavailability category.
    private func verifyOutage(_ changeAvailability: @Sendable (Store, Bool) async -> Void) async throws {
        let store = makeStore(.init()), now = Instant()
        let request = RateLimitRequest(identity: .init(), route: "POST /contract/outage")
        let token = try await admit(store, request: request, now: now)
        await changeAvailability(store, true)
        await #expect(throws: RateLimitFailure.coordinatorUnavailable) { _ = try await store.reserve(request, now: now) }
        await #expect(throws: RateLimitFailure.coordinatorUnavailable) {
            try await store.complete(token, status: 200, headers: [], retryAfter: nil, global: false, now: now)
        }
        await #expect(throws: RateLimitFailure.coordinatorUnavailable) {
            try await store.release(token, outcome: .uncertain, now: now)
        }
        #expect(await store.snapshot().activeCount == 1)
        await changeAvailability(store, false)
        try await store.release(token, outcome: .uncertain, now: now)
        try await expectBlocked(store, request: request, now: now, until: now.advanced(by: .seconds(1)))
        #expect(await store.snapshot().activeCount == 0)
    }

    /// Offers twenty concurrent requests at exactly one virtual instant and joins every worker.
    /// - Parameters:
    ///   - store: One shared authority, rather than independently created per-worker stores.
    ///   - request: Identical credential/route/major scope for all contenders.
    ///   - now: Explicit common attempt instant; no real time or scheduler order affects quota.
    /// - Returns: Every admitted token, retained by the caller for completion or uncertain release.
    /// - Throws: Any contender's unexpected adapter error after sibling cancellation and join.
    private func compete(_ store: Store, request: RateLimitRequest, now: Instant) async throws -> [RateLimitReservation<Instant>] {
        try await withThrowingTaskGroup(of: RateLimitReservation<Instant>?.self) { group in
            for _ in 0..<20 {
                group.addTask {
                    if case .admitted(let token) = try await store.reserve(request, now: now) { return token }
                    return nil
                }
            }
            var tokens: [RateLimitReservation<Instant>] = []
            for try await token in group { if let token { tokens.append(token) } }
            return tokens
        }
    }

    /// Requires one immediately eligible reservation and preserves its cleanup responsibility.
    /// - Parameters:
    ///   - store: Configured scenario authority.
    ///   - request: Expected eligible scope.
    ///   - now: Explicit virtual admission time.
    /// - Returns: Owned single-use permission to complete or release in this scenario.
    /// - Throws: Adapter errors or a failed requirement when admission is unexpectedly refused.
    private func admit(_ store: Store, request: RateLimitRequest, now: Instant) async throws -> RateLimitReservation<Instant> {
        let result = try await store.reserve(request, now: now)
        guard case .admitted(let token) = result else {
            Issue.record("Contract expected an eligible admission")
            throw RateLimitFailure.coordinatorUnavailable
        }
        return token
    }

    /// Asserts no permission is issued before a known reset; conservative later retries are accepted.
    /// Unexpected admissions are released uncertain so an assertion failure cannot leak ownership.
    /// - Parameters:
    ///   - store: Authority containing the known restriction.
    ///   - request: Scope that must remain blocked.
    ///   - now: Explicit attempt before its permitted time.
    ///   - minimum: Earliest safe retry instant derived from the scenario's policy/server evidence.
    /// - Throws: Unexpected authority or cleanup failures.
    private func expectBlocked(_ store: Store, request: RateLimitRequest, now: Instant, until minimum: Instant) async throws {
        switch try await store.reserve(request, now: now) {
        case .retry(let retry): #expect(retry >= minimum && retry > now)
        case .admitted(let token):
            Issue.record("Contract admitted before the known reset")
            try await store.release(token, outcome: .uncertain, now: now)
        }
    }
}

/// Exercises the exact same reusable contract against direct and injected forwarding adapters.
@Suite struct RateLimitStoreContractTests {
    /// Verifies the common harness is independent of the concrete in-process store type.
    /// - Parameter wrapped: False checks the direct authority; true wraps it behind another
    ///   `RateLimitStore` implementation and also injects a temporary authority outage.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [false, true])
    func adapterContract(_ wrapped: Bool) async throws {
        if wrapped {
            try await RateLimitStoreContract(makeStore: { policy in
                ForwardingRateLimitContractAdapter(base: InProcessRateLimitStore<ManualClock.Instant>(policy: policy))
            }, setUnavailable: { store, unavailable in await store.setUnavailable(unavailable) }).verify()
        } else {
            try await RateLimitStoreContract(makeStore: { policy in
                InProcessRateLimitStore<ManualClock.Instant>(policy: policy)
            }).verify()
        }
    }
}

/// Fault-injectable adapter fixture forwarding every operation into the same atomic authority.
/// Its reentrant actor boundary models an injected backend adapter without introducing fallback state.
@available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
private actor ForwardingRateLimitContractAdapter<Base: RateLimitStore>: RateLimitStore where Base.Instant == ManualClock.Instant {
    typealias Instant = ManualClock.Instant
    private let base: Base
    private var unavailable = false

    /// Retains one shared backing authority without creating separate budgets or background work.
    /// - Parameter base: Fresh scenario store, shared by all forwarded workers and recovery paths.
    init(base: Base) { self.base = base }

    /// Changes only availability, preserving reservations and consumed quota through recovery.
    /// - Parameter value: True rejects all mutations; false restores access to the same backing state.
    func setUnavailable(_ value: Bool) { unavailable = value }

    /// Forwards atomic reservation when authority is available and never substitutes a local budget.
    /// - Parameters:
    ///   - request: Unmodified non-secret request scopes and resource accounting.
    ///   - now: Unmodified common virtual instant.
    /// - Returns: Backing admission or retry decision.
    /// - Throws: coordinatorUnavailable during injection, otherwise the backing closed failure.
    func reserve(_ request: RateLimitRequest, now: Instant) async throws -> RateLimitAdmission<Instant> {
        guard !unavailable else { throw RateLimitFailure.coordinatorUnavailable }
        return try await base.reserve(request, now: now)
    }

    /// Forwards response learning and exact single-use ownership without changing server evidence.
    /// - Parameters:
    ///   - reservation: Unmodified backing token.
    ///   - status: Observed HTTP status.
    ///   - headers: Ordered rate headers, including original case and fractional text.
    ///   - retryAfter: Decoded body delay, or nil if absent.
    ///   - global: Decoded body-wide restriction flag.
    ///   - now: Unmodified virtual observation instant.
    /// - Throws: coordinatorUnavailable during injection, otherwise the backing closed failure.
    func complete(_ reservation: RateLimitReservation<Instant>, status: Int, headers: [HTTPHeader],
                  retryAfter: Duration?, global: Bool, now: Instant) async throws {
        guard !unavailable else { throw RateLimitFailure.coordinatorUnavailable }
        try await base.complete(reservation, status: status, headers: headers, retryAfter: retryAfter, global: global, now: now)
    }

    /// Forwards uncertain cleanup without refunding the backing authority's original debit.
    /// - Parameters:
    ///   - reservation: Exact owned single-use token.
    ///   - outcome: Known-unsent or uncertain result; both retain consumed quota.
    ///   - now: Unmodified virtual cleanup instant.
    /// - Throws: coordinatorUnavailable during injection, otherwise the backing closed failure.
    func release(_ reservation: RateLimitReservation<Instant>, outcome: RateLimitReleaseOutcome, now: Instant) async throws {
        guard !unavailable else { throw RateLimitFailure.coordinatorUnavailable }
        try await base.release(reservation, outcome: outcome, now: now)
    }

    /// Observes retained local fixture ownership even while mutating access is unavailable.
    /// - Returns: Backing aggregate counters without credential/resource labels or fallback state.
    func snapshot() async -> SchedulingSnapshot { await base.snapshot() }
}
