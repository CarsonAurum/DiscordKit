// File: Tests/DiscordHTTPTests/EgressGlobalTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordTestSupport
import DiscordTransport
import Foundation
import Testing
@testable import DiscordHTTP

/// Deterministic outbound-IP global admission, independent of credential-global and invalid-response scopes.
/// Every owned reservation is completed or released without sockets, credentials, wall-clock waits or sleeps.
@Suite struct EgressGlobalTests {
    /// Explicit IP-global admission requires an egress before allocating ownership or metadata.
    /// Defaults retain the existing credential-global behavior and redacted diagnostic contract.
    /// - Throws: Unexpected valid admission failures fail the test; invalid scope errors are asserted.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func requestDefaultsAndRequiredEgress() async throws {
        let identity = RateLimitIdentity(), now = ManualClock.Instant()
        let normal = RateLimitRequest(identity: identity, route: "GET /normal")
        #expect(normal.usesGlobalLimit && !normal.usesEgressGlobalLimit)
        let explicit = RateLimitRequest(identity: identity, route: "GET /private-route", egress: UUID(), usesEgressGlobalLimit: true)
        #expect(explicit.usesEgressGlobalLimit && explicit != normal)
        #expect(!explicit.description.contains("private-route"))
        #expect(!explicit.debugDescription.contains("private-route"))
        #expect(Mirror(reflecting: explicit).children.count == 1)
        let store = InProcessRateLimitStore<ManualClock.Instant>()
        for global in [false, true] {
            await #expect(throws: RateLimitFailure.invalidRequest) {
                try await store.reserve(.init(identity: identity, route: "GET /invalid", usesGlobalLimit: global,
                    usesEgressGlobalLimit: true), now: now)
            }
        }
        #expect(await store.snapshot().activeCount == 0)
        #expect(await store.snapshot().metadataCount == 0)
    }

    /// Different webhook identities sharing one IP consume one startup allowance, with independent IP/bot/exempt scopes.
    /// Completion/release clears all concurrency so the entire next one-second allowance becomes available.
    /// - Throws: Unexpected admission, refusal or cleanup failures fail the test.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func startupBudgetSharesEgressAndSeparatesOtherScopes() async throws {
        let store = InProcessRateLimitStore<ManualClock.Instant>(policy: .init(initialGlobalRequestsPerSecond: 2))
        let now = ManualClock.Instant(), egress = UUID(), identity = RateLimitIdentity()
        let first = try await Self.admit(store, request: .init(identity: identity, route: "POST /first", egress: egress,
            usesEgressGlobalLimit: true), now: now)
        let second = try await Self.admit(store, request: .init(identity: .init(), route: "POST /second", egress: egress,
            usesEgressGlobalLimit: true), now: now)
        try await Self.expectBlocked(store, request: .init(identity: .init(), route: "POST /third", egress: egress,
            usesEgressGlobalLimit: true), now: now, until: now.advanced(by: .seconds(1)))
        let bot = try await Self.admit(store, request: .init(identity: identity, route: "GET /bot", egress: egress), now: now)
        let independent = try await Self.admit(store, request: .init(identity: identity, route: "POST /other-ip", egress: UUID(),
            usesEgressGlobalLimit: true), now: now)
        let exempt = try await Self.admit(store, request: .init(identity: identity, route: "POST /interaction", egress: egress,
            usesGlobalLimit: false, usesEgressGlobalLimit: true), now: now)
        for token in [first, second, bot, independent, exempt] { try await store.release(token, outcome: .uncertain, now: now) }
        #expect(await store.snapshot().activeCount == 0)
        let later = now.advanced(by: .seconds(1))
        let nextA = try await Self.admit(store, request: .init(identity: .init(), route: "POST /next-a", egress: egress,
            usesEgressGlobalLimit: true), now: later)
        let nextB = try await Self.admit(store, request: .init(identity: .init(), route: "POST /next-b", egress: egress,
            usesEgressGlobalLimit: true), now: later)
        for token in [nextA, nextB] { try await store.release(token, outcome: .notSent, now: later) }
        #expect(await store.snapshot().activeCount == 0)
    }

    /// Competing independent credentials cannot double-spend one IP window across actor suspension points.
    /// - Throws: Unexpected contender or cleanup failures fail the test; all task-group children are joined.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func concurrentCredentialIdentitiesShareAtomicIPAllowance() async throws {
        let store = InProcessRateLimitStore<ManualClock.Instant>(policy: .init(initialGlobalRequestsPerSecond: 3))
        let now = ManualClock.Instant(), egress = UUID()
        let admitted = try await withThrowingTaskGroup(of: RateLimitReservation<ManualClock.Instant>?.self) { group in
            for index in 0..<20 {
                group.addTask {
                    let request = RateLimitRequest(identity: .init(), route: "POST /concurrent/\(index)", egress: egress,
                        usesEgressGlobalLimit: true)
                    if case .admitted(let token) = try await store.reserve(request, now: now) { return token }
                    return nil
                }
            }
            var result: [RateLimitReservation<ManualClock.Instant>] = []
            for try await token in group { if let token { result.append(token) } }
            return result
        }
        #expect(admitted.count == 3)
        #expect(await store.snapshot().activeCount == 3)
        #expect(await store.snapshot().metadataCount == 4)
        for token in admitted { try await store.release(token, outcome: .uncertain, now: now) }
        #expect(await store.snapshot().activeCount == 0)
    }

    /// Body/header global 429 evidence blocks every token on the same IP while preserving credential and other-IP limits.
    /// Relative body/header delays compose conservatively and the restriction expires at its inclusive boundary.
    /// - Parameter source: Body flag, X-RateLimit-Global header or global scope header.
    /// - Throws: Unexpected admission, observation or cleanup failures fail the test.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: ["body", "header", "scope"])
    func globalRejectionUsesIPScope(source: String) async throws {
        let store = InProcessRateLimitStore<ManualClock.Instant>()
        let now = ManualClock.Instant(), egress = UUID(), identity = RateLimitIdentity()
        let first = try await Self.admit(store, request: .init(identity: identity, route: "POST /limited", egress: egress,
            usesEgressGlobalLimit: true), now: now)
        var headers: [HTTPHeader] = [.init(name: "Retry-After", value: "3")]
        if source == "header" { headers.append(.init(name: "x-RATELIMIT-global", value: "TRUE")) }
        if source == "scope" { headers.append(.init(name: "X-RateLimit-Scope", value: "global")) }
        try await store.complete(first, status: 429, headers: headers, retryAfter: .seconds(2), global: source == "body", now: now)
        let rotated = RateLimitRequest(identity: .init(), route: "POST /rotated", egress: egress, usesEgressGlobalLimit: true)
        try await Self.expectBlocked(store, request: rotated, now: now, until: now.advanced(by: .seconds(3)))
        let bot = try await Self.admit(store, request: .init(identity: identity, route: "GET /bot", egress: egress), now: now)
        let otherIP = try await Self.admit(store, request: .init(identity: identity, route: "POST /other", egress: UUID(),
            usesEgressGlobalLimit: true), now: now)
        let exempt = try await Self.admit(store, request: .init(identity: identity, route: "POST /callback", egress: egress,
            usesGlobalLimit: false, usesEgressGlobalLimit: true), now: now)
        for token in [bot, otherIP, exempt] { try await store.release(token, outcome: .notSent, now: now) }
        let deadline = now.advanced(by: .seconds(3))
        let resumed = try await Self.admit(store, request: rotated, now: deadline)
        try await store.release(resumed, outcome: .notSent, now: deadline)
        #expect(await store.snapshot().activeCount == 0)
    }

    /// Bot global rejection cannot debit/block the IP window, and exempt interactions cannot create either global block.
    /// Route-specific rejection still applies to the rejected interaction itself.
    /// - Throws: Unexpected admission/observation/cleanup failures fail the test.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func credentialGlobalAndInteractionExemptionRemainIndependent() async throws {
        let store = InProcessRateLimitStore<ManualClock.Instant>(policy: .init(initialGlobalRequestsPerSecond: 1))
        let now = ManualClock.Instant(), egress = UUID(), identity = RateLimitIdentity()
        let bot = try await Self.admit(store, request: .init(identity: identity, route: "GET /bot", egress: egress), now: now)
        try await store.complete(bot, status: 429, headers: [], retryAfter: .seconds(5), global: true, now: now)
        let webhook = try await Self.admit(store, request: .init(identity: identity, route: "POST /token", egress: egress,
            usesEgressGlobalLimit: true), now: now)
        try await store.release(webhook, outcome: .notSent, now: now)
        try await Self.expectBlocked(store, request: .init(identity: identity, route: "GET /other-bot"), now: now,
            until: now.advanced(by: .seconds(5)))

        let exemptStore = InProcessRateLimitStore<ManualClock.Instant>(policy: .init(initialGlobalRequestsPerSecond: 1))
        let request = RateLimitRequest(identity: identity, route: "POST /callback", egress: egress,
            usesGlobalLimit: false, usesEgressGlobalLimit: true)
        let exempt = try await Self.admit(exemptStore, request: request, now: now)
        try await exemptStore.complete(exempt, status: 429, headers: [], retryAfter: .seconds(5), global: true, now: now)
        let normal = try await Self.admit(exemptStore, request: .init(identity: identity, route: "GET /normal", egress: egress), now: now)
        let ip = try await Self.admit(exemptStore, request: .init(identity: identity, route: "POST /ordinary-token", egress: egress,
            usesEgressGlobalLimit: true), now: now)
        for token in [normal, ip] { try await exemptStore.release(token, outcome: .uncertain, now: now) }
        try await Self.expectBlocked(exemptStore, request: request, now: now, until: now.advanced(by: .seconds(5)))
        #expect(await store.snapshot().activeCount == 0)
        #expect(await exemptStore.snapshot().activeCount == 0)
    }

    /// Route refusal retains its earlier IP debit but releases concurrency, allowing the entire next IP window.
    /// - Throws: Unexpected reserve, refusal or cleanup failures fail the test.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func routeRefusalRetainsDebitAndClearsEgressConcurrency() async throws {
        let store = InProcessRateLimitStore<ManualClock.Instant>(policy: .init(initialGlobalRequestsPerSecond: 2))
        let now = ManualClock.Instant(), egress = UUID()
        let request = RateLimitRequest(identity: .init(), route: "POST /same-route", egress: egress, usesEgressGlobalLimit: true)
        let first = try await Self.admit(store, request: request, now: now)
        try await store.release(first, outcome: .notSent, now: now)
        try await Self.expectBlocked(store, request: request, now: now, until: now.advanced(by: .seconds(1)))
        try await Self.expectBlocked(store, request: .init(identity: .init(), route: "POST /fresh", egress: egress,
            usesEgressGlobalLimit: true), now: now, until: now.advanced(by: .seconds(1)))
        #expect(await store.snapshot().activeCount == 0)
        let later = now.advanced(by: .seconds(1))
        var tokens: [RateLimitReservation<ManualClock.Instant>] = []
        for suffix in ["a", "b"] {
            tokens.append(try await Self.admit(store, request: .init(identity: .init(), route: "POST /later-\(suffix)",
                egress: egress, usesEgressGlobalLimit: true), now: later))
        }
        for token in tokens { try await store.release(token, outcome: .uncertain, now: later) }
        #expect(await store.snapshot().activeCount == 0)
    }

    /// Success, both release outcomes and inclusive expired completion/release clear IP concurrency without refunds.
    /// Unknown tokens cannot release a second time, and stale response headers cannot grant fresh allowance.
    /// - Parameter outcome: One normal or expired ownership terminal path.
    /// - Throws: Unexpected reserve/cleanup failures fail the test; expired/unknown failures are asserted.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: ["complete", "not-sent", "uncertain", "expired-complete", "expired-release"])
    func terminalOwnershipPathsDoNotLeakOrRefund(outcome: String) async throws {
        let store = InProcessRateLimitStore<ManualClock.Instant>(policy: .init(reservationLifetime: .milliseconds(100),
            initialGlobalRequestsPerSecond: 1))
        let now = ManualClock.Instant(), egress = UUID()
        let request = RateLimitRequest(identity: .init(), route: "POST /terminal", egress: egress, usesEgressGlobalLimit: true)
        let token = try await Self.admit(store, request: request, now: now)
        switch outcome {
        case "complete":
            // A route's larger learned allowance cannot replenish the independently consumed IP budget.
            try await store.complete(token, status: 200, headers: [
                .init(name: "X-RateLimit-Limit", value: "100"),
                .init(name: "X-RateLimit-Remaining", value: "99"),
                .init(name: "X-RateLimit-Reset-After", value: "0.1")
            ], now: now)
        case "expired-complete":
            await #expect(throws: RateLimitFailure.reservationExpired) {
                try await store.complete(token, status: 429, headers: [], retryAfter: .seconds(100), global: true, now: token.expiresAt)
            }
        case "expired-release":
            await #expect(throws: RateLimitFailure.reservationExpired) {
                try await store.release(token, outcome: .uncertain, now: token.expiresAt)
            }
        default: try await store.release(token, outcome: outcome == "not-sent" ? .notSent : .uncertain, now: now)
        }
        await #expect(throws: RateLimitFailure.unknownReservation) { try await store.release(token, outcome: .uncertain, now: now) }
        #expect(await store.snapshot().activeCount == 0)
        let fresh = RateLimitRequest(identity: .init(), route: "POST /fresh", egress: egress, usesEgressGlobalLimit: true)
        try await Self.expectBlocked(store, request: fresh, now: token.expiresAt, until: now.advanced(by: .seconds(1)))
        let later = now.advanced(by: .seconds(1))
        let next = try await Self.admit(store, request: fresh, now: later)
        try await store.release(next, outcome: .notSent, now: later)
        #expect(await store.snapshot().activeCount == 0)
    }

    /// Missing room for route metadata fails closed after IP debit, while expired unowned IP state remains reclaimable.
    /// Failure to learn a returned route bucket clears all ownership and makes the entire authority unavailable.
    /// - Throws: Unexpected valid reserve/cleanup failures fail the test; bounded metadata failures are asserted.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func metadataFailuresReleaseConcurrencyAndFailClosed() async throws {
        let now = ManualClock.Instant(), egress = UUID()
        let request = RateLimitRequest(identity: .init(), route: "POST /bounded", egress: egress, usesEgressGlobalLimit: true)
        let tiny = InProcessRateLimitStore<ManualClock.Instant>(policy: .init(maximumMetadata: 1))
        await #expect(throws: RateLimitFailure.metadataFull) { try await tiny.reserve(request, now: now) }
        #expect(await tiny.snapshot().activeCount == 0)
        #expect(await tiny.snapshot().metadataCount == 1)
        let later = now.advanced(by: .seconds(1))
        let replacement = try await Self.admit(tiny, request: .init(identity: .init(), route: "POST /exempt", usesGlobalLimit: false), now: later)
        try await tiny.release(replacement, outcome: .notSent, now: later)
        #expect(await tiny.snapshot().metadataCount == 1)

        for site in ["route-bucket", "invalid-response"] {
            let store = InProcessRateLimitStore<ManualClock.Instant>(policy: .init(maximumMetadata: 2))
            let token = try await Self.admit(store, request: request, now: now)
            await #expect(throws: RateLimitFailure.metadataFull) {
                try await store.complete(token, status: site == "route-bucket" ? 200 : 401,
                    headers: site == "route-bucket" ? [.init(name: "X-RateLimit-Bucket", value: "new-bucket")] : [], now: now)
            }
            #expect(await store.snapshot().activeCount == 0)
            #expect(await store.snapshot().metadataCount <= 2)
            await #expect(throws: RateLimitFailure.coordinatorUnavailable) { try await store.reserve(request, now: later) }
        }
    }

    /// Cancellation before reservation allocates nothing; cancellation exactly during IP-window allocation releases both actors.
    /// A test instant triggers cancellation synchronously at the one-second IP reset calculation, without scheduler races.
    /// - Throws: Unexpected admission/cleanup failures fail the test; cooperative cancellation and retained debit are asserted.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func cancellationBeforeAndAfterIPDebitCleansUp() async throws {
        let store = InProcessRateLimitStore<EgressCancellationInstant>(policy: .init(initialGlobalRequestsPerSecond: 1))
        let egress = UUID()
        let request = RateLimitRequest(identity: .init(), route: "POST /cancelled", egress: egress, usesEgressGlobalLimit: true)
        let before = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await store.reserve(request, now: .init())
        }
        await #expect(throws: CancellationError.self) { try await before.value }
        let initial = await store.snapshot()
        #expect(initial.activeCount == 0 && initial.metadataCount == 0)
        let during = Task {
            do {
                _ = try await store.reserve(request, now: .init(cancelAtOneSecondAdvance: true))
                return false
            } catch is CancellationError { return true }
        }
        #expect(try await during.value)
        #expect(await store.snapshot().activeCount == 0)
        switch try await store.reserve(.init(identity: .init(), route: "POST /another", egress: egress,
            usesEgressGlobalLimit: true), now: .init()) {
        case .retry(let instant): #expect(instant.offset >= .seconds(1))
        case .admitted(let token):
            Issue.record("Cancellation must not refund IP debit")
            try await store.release(token, outcome: .uncertain, now: .init())
        }
        guard case .admitted(let next) = try await store.reserve(.init(identity: .init(), route: "POST /after-reset",
            egress: egress, usesEgressGlobalLimit: true), now: .init(offset: .seconds(1))) else {
            Issue.record("Cancellation leaked IP concurrency"); return
        }
        try await store.release(next, outcome: .notSent, now: .init(offset: .seconds(1)))
        #expect(await store.snapshot().activeCount == 0)
    }

    /// Requires an immediately eligible owned token while leaving its terminal cleanup with the test.
    /// - Parameters:
    ///   - store: Independent scenario authority with finite budgets.
    ///   - request: Exact expected eligible identity/route/IP scopes.
    ///   - now: Explicit virtual time shared by all contenders.
    /// - Returns: Single-use reservation requiring completion/release.
    /// - Throws: Store failures or a recorded failed requirement if admission is unexpectedly refused.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    private static func admit(_ store: InProcessRateLimitStore<ManualClock.Instant>, request: RateLimitRequest,
                              now: ManualClock.Instant) async throws -> RateLimitReservation<ManualClock.Instant> {
        guard case .admitted(let token) = try await store.reserve(request, now: now) else {
            Issue.record("Expected eligible reservation")
            throw RateLimitFailure.coordinatorUnavailable
        }
        return token
    }

    /// Asserts a blocked scope and cleans up an unexpected admission to avoid leaking test ownership.
    /// - Parameters:
    ///   - store: Scenario authority with a known consumed or rejected budget.
    ///   - request: Scope that must remain ineligible.
    ///   - now: Virtual attempt time before reset.
    ///   - minimum: Earliest permissible reset; conservative later retry values are accepted.
    /// - Throws: Unexpected store or cleanup failures fail the test.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    private static func expectBlocked(_ store: InProcessRateLimitStore<ManualClock.Instant>, request: RateLimitRequest,
                                      now: ManualClock.Instant, until minimum: ManualClock.Instant) async throws {
        switch try await store.reserve(request, now: now) {
        case .retry(let instant): #expect(instant >= minimum && instant > now)
        case .admitted(let token):
            Issue.record("Expected blocked reservation")
            try await store.release(token, outcome: .uncertain, now: now)
        }
    }
}

/// Scenario-local virtual instant whose optional synchronous cancellation targets the IP-window calculation.
/// The flag affects test execution only; equality/ordering use offset so all instants share one virtual domain.
private struct EgressCancellationInstant: InstantProtocol {
    let offset: Duration
    let cancelAtOneSecondAdvance: Bool

    /// Constructs an explicit virtual time and optional one-second-advance cancellation hook.
    /// - Parameters:
    ///   - offset: Duration from this scenario's origin, zero by default.
    ///   - cancelAtOneSecondAdvance: True cancels only the current task during a one-second advance; default false.
    init(offset: Duration = .zero, cancelAtOneSecondAdvance: Bool = false) {
        self.offset = offset; self.cancelAtOneSecondAdvance = cancelAtOneSecondAdvance
    }

    /// Computes a new virtual instant and optionally cancels the current logical reservation task.
    /// - Parameter duration: Exact relative advance; one second identifies IP-global startup reset construction.
    /// - Returns: New offset in the same domain, retaining the deterministic hook.
    func advanced(by duration: Duration) -> Self {
        if cancelAtOneSecondAdvance && duration == .seconds(1) { withUnsafeCurrentTask { $0?.cancel() } }
        return .init(offset: offset + duration, cancelAtOneSecondAdvance: cancelAtOneSecondAdvance)
    }

    /// Computes the exact signed relative distance in the virtual domain.
    /// - Parameter other: Destination instant; the execution-only cancellation flag does not affect time.
    /// - Returns: Destination offset minus this offset.
    func duration(to other: Self) -> Duration { other.offset - offset }

    /// Compares virtual positions independently of test execution hooks.
    /// - Parameters:
    ///   - lhs: First instant.
    ///   - rhs: Second instant in the same scenario domain.
    /// - Returns: True exactly when both offsets are equal.
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.offset == rhs.offset }

    /// Orders virtual positions independently of test execution hooks.
    /// - Parameters:
    ///   - lhs: Candidate earlier instant.
    ///   - rhs: Candidate later instant.
    /// - Returns: True exactly when the first offset precedes the second.
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.offset < rhs.offset }
}
