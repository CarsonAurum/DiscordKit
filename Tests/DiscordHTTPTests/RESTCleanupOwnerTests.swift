// File: Tests/DiscordHTTPTests/RESTCleanupOwnerTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import DiscordTestSupport
import DiscordTransport
import Foundation
import Testing
@testable import DiscordHTTP

/// Cleanup authority outages remain observable without replacing primary failures or replaying mutations.
@Suite(.timeLimit(.minutes(1))) struct RESTCleanupOwnerTests {
    /// Every cleanup-suppression path preserves primary evidence and reports the lost owner separately.
    /// - Parameter path: Request construction, post-construction cancellation, transport loss or response-body loss.
    /// - Throws: Unexpected fixture construction or primary error propagation fails the test.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: 0..<4) func observesCleanupFailureWithoutReplacingPrimary(path: Int) async throws {
        let clock = ManualClock(), observed = CleanupOwnerObservations()
        let store = CleanupFailureRateStore(failCompletion: path == 3)
        let coordinator = RateLimitCoordinator(clock: clock, store: store)
        let transport = try ScriptedHTTPTransport(steps: [{ _ in
            if path == 3 {
                return HTTPResponse(status: 200, body: try BodyStream(maximumChunkBytes: 1,
                    next: { throw DiscordError.transport(.disconnected) }, close: { await observed.closedBody() }))
            }
            throw DiscordError.transport(.disconnected)
        }])
        let body: RequestBody?
        if path <= 1 {
            body = try .stream(contentType: "application/octet-stream", maximumBytes: 1) {
                if path == 0 { throw DiscordError.validation(.invalidValue) }
                withUnsafeCurrentTask { $0?.cancel() }
                return try BodyStream(maximumChunkBytes: 1, next: { nil }, close: { await observed.closedBody() })
            }
        } else { body = nil }
        let client = RESTClient(credential: .none, identity: RateLimitIdentity(), transport: transport,
            coordinator: coordinator, clock: clock, retryPolicy: .init(maximumAttempts: 3))
        let endpoint = try Endpoint(method: "POST", path: ["mutation"], authentication: .none,
            body: body, retrySafety: .unsafe, decode: { $0 })
        await InvocationOwnerFailureScope.$observer.withValue({ failure in await observed.record(failure) }) {
            let task = Task { try await client.execute(endpoint) }
            do {
                _ = try await task.value
                Issue.record("Expected primary operation failure")
            } catch {
                switch path {
                case 0: #expect(error as? DiscordError == .validation(.invalidValue))
                case 1: #expect(error is CancellationError)
                default: #expect(error as? DiscordError == .unknownMutationOutcome(.connectionLostAfterSubmission))
                }
            }
        }
        let observations = await observed.failures
        #expect(observations.count == 1)
        if case .some(.rateLimitCoordinatorUnavailable) = observations.first {} else {
            Issue.record("Expected closed safe coordinator-unavailable observation")
        }
        #expect(await transport.executionCount == (path <= 1 ? 0 : 1))
        #expect(await observed.bodyCloseCount == (path == 1 || path == 3 ? 1 : 0))
        #expect(await store.releaseCount == (path == 3 ? 0 : 1))
        #expect(await store.completeCount == (path == 3 ? 1 : 0))
        let final = await coordinator.snapshot()
        #expect(final.activeCount == 0)
        #expect(final.queuedCount == 0)
        #expect(final.orderedOperationsCount == 0)
        #expect(clock.pendingSleepCount == 0)
        await #expect(throws: RateLimitFailure.coordinatorUnavailable) {
            try await coordinator.acquire(RateLimitRequest(identity: .init(), route: "GET /later"))
        }
        #expect(await store.reserveCount == 1)
    }
}

/// Bounded typed observations retain no request, token or arbitrary Error object.
private actor CleanupOwnerObservations {
    var failures: [InvocationOwnerFailure] = []
    var bodyCloseCount = 0

    /// Records the only expected closed owner category from one finite exchange.
    /// - Parameter failure: Safe package-owned category without arbitrary associated text.
    func record(_ failure: InvocationOwnerFailure) { failures.append(failure) }

    /// Counts exactly-once cleanup of the explicitly constructed request or response stream.
    func closedBody() { bodyCloseCount += 1 }
}

/// A deterministic authority that clears backing ownership, then reports unavailable cleanup.
@available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
private actor CleanupFailureRateStore: RateLimitStore {
    typealias Instant = ManualClock.Instant
    private let base = InProcessRateLimitStore<Instant>()
    private let failCompletion: Bool
    var reserveCount = 0
    var releaseCount = 0
    var completeCount = 0

    /// Selects the failing terminal operation without allocating tasks or reservations.
    /// - Parameter failCompletion: True fails body-error completion; false fails request/send-error release.
    init(failCompletion: Bool) { self.failCompletion = failCompletion }

    /// Delegates one normal reservation while counting attempts after an authority becomes unavailable.
    /// - Parameters:
    ///   - request: Synthetic request scope, never retained by diagnostic output.
    ///   - now: Shared virtual monotonic time.
    /// - Returns: Backing store admission decision.
    /// - Throws: Backing store validation or admission errors.
    func reserve(_ request: RateLimitRequest, now: Instant) async throws -> RateLimitAdmission<Instant> {
        reserveCount += 1
        return try await base.reserve(request, now: now)
    }

    /// Clears backing ownership before reporting the configured completion failure.
    /// - Parameters:
    ///   - reservation: Exact issued reservation.
    ///   - status: Synthetic response status.
    ///   - headers: Synthetic response headers.
    ///   - retryAfter: Synthetic relative retry delay.
    ///   - global: Synthetic global-rate observation.
    ///   - now: Shared virtual monotonic time.
    /// - Throws: Coordinator-unavailable for the body-error path, otherwise only backing store errors.
    func complete(_ reservation: RateLimitReservation<Instant>, status: Int, headers: [HTTPHeader],
        retryAfter: Duration?, global: Bool, now: Instant) async throws {
        completeCount += 1
        try await base.complete(reservation, status: status, headers: headers,
            retryAfter: retryAfter, global: global, now: now)
        if failCompletion { throw RateLimitFailure.coordinatorUnavailable }
    }

    /// Clears backing ownership before reporting the configured release failure.
    /// - Parameters:
    ///   - reservation: Exact issued reservation.
    ///   - outcome: Original no-send or uncertain submission evidence.
    ///   - now: Shared virtual monotonic time.
    /// - Throws: Coordinator-unavailable for request/send-error paths, otherwise only backing store errors.
    func release(_ reservation: RateLimitReservation<Instant>, outcome: RateLimitReleaseOutcome, now: Instant) async throws {
        releaseCount += 1
        try await base.release(reservation, outcome: outcome, now: now)
        if !failCompletion { throw RateLimitFailure.coordinatorUnavailable }
    }

    /// Reads backing ownership counts without returning diagnostic identities or credentials.
    /// - Returns: Bounded accounting, including zero active reservations after terminal cleanup.
    func snapshot() async -> SchedulingSnapshot { await base.snapshot() }
}
