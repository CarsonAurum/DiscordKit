// File: Tests/DiscordHTTPTests/InviteOperationsTests.swift
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

/// Deterministic finite Invite CSV-job observations cover pacing, termination, errors and cancellation without live requests.
@Suite(.timeLimit(.minutes(1))) struct InviteOperationsTests {
    /// Pulls start no requests before demand; every pending/future status sleeps once before a terminal completed/failed result.
    /// - Parameters:
    ///   - pending: Unspecified, processing and future statuses remain pending.
    ///   - terminal: Completed and failed snapshots both yield once and terminate without another poll.
    /// - Throws: Unexpected descriptor, fixture, iteration or clock errors fail the test.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [0, 1, 999], [2, 3]) func lazyPacingAndTerminalStates(pending: Int, terminal: Int) async throws {
        let timer = TestBarrier()
        let clock = ManualClock(onSleepScheduled: { timer.open() })
        let script = InviteJobScript([try Self.job(pending), try Self.job(terminal)])
        let pages = try InviteOperations.targetUsersJobStatuses(code: "private-code", interval: .seconds(1),
            context: TransportContext(clock: clock)) { try await script.next($0) }
        #expect(await script.calls == 0 && clock.pendingSleepCount == 0)
        let task = Task { () throws -> Void in
            var iterator = pages.makeAsyncIterator()
            #expect(try await iterator.next()?.first?.status.rawValue == pending)
            #expect(try await iterator.next()?.first?.status.rawValue == terminal)
            #expect(try await iterator.next() == nil)
        }
        try await timer.wait()
        #expect(await script.calls == 1 && clock.pendingSleepCount == 1)
        try clock.advance(by: .milliseconds(999))
        #expect(await script.calls == 1)
        try clock.advance(by: .milliseconds(1))
        try await task.value
        #expect(await script.calls == 2 && clock.pendingSleepCount == 0)
    }

    /// Terminal first responses need no interval timer, and independent iterators start separate budgets without prefetch.
    /// - Parameter terminal: Both successful and failed upstream job states are inspectable terminal results.
    /// - Throws: Unexpected fixture or iteration errors fail the test.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [2, 3]) func immediateTerminalAndIndependentIterators(terminal: Int) async throws {
        let clock = ManualClock(), script = InviteJobScript([try Self.job(terminal), try Self.job(terminal)])
        let sequence = try InviteOperations.targetUsersJobStatuses(code: "c", context: TransportContext(clock: clock)) { try await script.next($0) }
        var first = sequence.makeAsyncIterator()
        #expect(try await first.next()?.first?.status.rawValue == terminal)
        #expect(try await first.next() == nil)
        var second = sequence.makeAsyncIterator()
        #expect(try await second.next()?.first?.status.rawValue == terminal)
        #expect(try await second.next() == nil)
        #expect(await script.calls == 2 && clock.pendingSleepCount == 0)
    }

    /// Invalid count/duration/code configurations fail synchronously before work; legal extremes construct lazily.
    /// - Throws: Unexpected construction errors fail the test.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func invalidConfiguration() throws {
        let context = TransportContext(clock: ManualClock())
        for count in [Int.min, -1, 0, 10_001, Int.max] {
            #expect(throws: DiscordError.validation(.invalidValue)) {
                try InviteOperations.targetUsersJobStatuses(code: "c", maximumPolls: count, context: context) { _ in try Self.job(2) }
            }
        }
        for interval in [Duration.zero, .seconds(-1), .seconds(86_401)] {
            #expect(throws: DiscordError.validation(.invalidValue)) {
                try InviteOperations.targetUsersJobStatuses(code: "c", interval: interval, context: context) { _ in try Self.job(2) }
            }
        }
        for code in ["", "../c", ".", "a\nb"] {
            #expect(throws: DiscordError.validation(.invalidValue)) {
                try InviteOperations.targetUsersJobStatuses(code: code, context: context) { _ in try Self.job(2) }
            }
        }
        _ = try InviteOperations.targetUsersJobStatuses(code: "c", maximumPolls: 1, interval: .nanoseconds(1), context: context) { _ in try Self.job(2) }
        _ = try InviteOperations.targetUsersJobStatuses(code: "c", maximumPolls: 10_000, interval: .seconds(86_400), context: context) { _ in try Self.job(2) }
    }

    /// Exhaustion yields the last pending evidence then fails before sleeping or submitting another request.
    /// API/executor errors permanently finish one iterator without automatic recovery/retry.
    /// - Throws: Unexpected fixture or sequence errors fail the test.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func budgetAndExecutorFailures() async throws {
        let clock = ManualClock(), script = InviteJobScript([try Self.job(1)])
        var iterator = try InviteOperations.targetUsersJobStatuses(code: "c", maximumPolls: 1,
            context: TransportContext(clock: clock)) { try await script.next($0) }.makeAsyncIterator()
        #expect(try await iterator.next()?.first?.status.knownValue == .processing)
        await #expect(throws: DiscordError.validation(.limitExceeded)) { try await iterator.next() }
        #expect(try await iterator.next() == nil)
        #expect(await script.calls == 1 && clock.pendingSleepCount == 0)
        for failure in [DiscordError.api(status: 403, code: 50013), .transport(.disconnected), .cancelled] {
            var failed = try InviteOperations.targetUsersJobStatuses(code: "c", context: TransportContext(clock: clock)) { _ in throw failure }.makeAsyncIterator()
            await #expect(throws: failure) { try await failed.next() }
            #expect(try await failed.next() == nil)
        }
    }

    /// Pre-cancellation and inclusive deadline expiry enter no executor, leave no timers, and finish the iterator.
    /// - Throws: Unexpected fixture or setup errors fail the test.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func cancelledBeforePullAndExpiredDeadline() async throws {
        let clock = ManualClock()
        var expired = try InviteOperations.targetUsersJobStatuses(code: "c", context: TransportContext(clock: clock, deadline: clock.now)) { _ in
            Issue.record("Expired executor called"); return try Self.job(2)
        }.makeAsyncIterator()
        await #expect(throws: TransportFailure.deadlineExceeded) { try await expired.next() }
        #expect(try await expired.next() == nil)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            var iterator = try InviteOperations.targetUsersJobStatuses(code: "c", context: TransportContext(clock: clock)) { _ in
                Issue.record("Cancelled executor called"); return try Self.job(2)
            }.makeAsyncIterator()
            return try await iterator.next()
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(clock.pendingSleepCount == 0)
    }

    /// Cancellation while waiting for the next poll removes its clock sleeper and submits no extra read.
    /// - Throws: Unexpected barrier/fixture errors fail the test.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func cancellationDuringPollDelay() async throws {
        let scheduled = TestBarrier(), clock = ManualClock(onSleepScheduled: { scheduled.open() })
        let script = InviteJobScript([try Self.job(1), try Self.job(2)])
        let sequence = try InviteOperations.targetUsersJobStatuses(code: "c", context: TransportContext(clock: clock)) { try await script.next($0) }
        let task = Task { () throws -> Void in
            var iterator = sequence.makeAsyncIterator()
            #expect(try await iterator.next()?.first?.status.knownValue == .processing)
            do { _ = try await iterator.next(); Issue.record("Expected cancellation") }
            catch is CancellationError { }
            #expect(try await iterator.next() == nil)
        }
        try await scheduled.wait()
        task.cancel()
        try await task.value
        #expect(await script.calls == 1 && clock.pendingSleepCount == 0)
    }

    /// Cancellation and inclusive deadline expiration interrupt a suspended executor and clean up structured children.
    /// - Parameter expires: True reaches the deadline; false cancels the waiting task after actual executor entry.
    /// - Throws: Unexpected fixture, clock or barrier errors fail the test.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [false, true]) func suspendedExecutorTermination(expires: Bool) async throws {
        let entered = TestBarrier(), timer = TestBarrier(), gate = TestBarrier()
        let clock = ManualClock(onSleepScheduled: { timer.open() })
        let sequence = try InviteOperations.targetUsersJobStatuses(code: "c", context: TransportContext(clock: clock, deadline: clock.now.advanced(by: .seconds(1)))) { _ in
            entered.open(); try await gate.wait(); return try Self.job(2)
        }
        let task = Task { () throws -> Void in
            var iterator = sequence.makeAsyncIterator()
            do { _ = try await iterator.next(); Issue.record("Expected interrupted executor") }
            catch is CancellationError { #expect(!expires) }
            catch let error as TransportFailure { #expect(expires && error == .deadlineExceeded) }
            #expect(try await iterator.next() == nil)
        }
        try await entered.wait()
        if expires { try await timer.wait(); try clock.advance(by: .seconds(1)) } else { task.cancel() }
        try await task.value
        #expect(gate.waitingCount == 0 && clock.pendingSleepCount == 0)
    }

    /// Produces independent complete job fixtures, retaining failed messages for deliberate caller inspection.
    /// - Parameter status: Exact known or future job status integer.
    /// - Returns: Complete immutable job with nullable timestamps and error text.
    /// - Throws: Bounded production parser/schema errors if the local fixture is invalid.
    private static func job(_ status: Int) throws -> InviteTargetUsersJob {
        try InviteTargetUsersJob(data: Data("{\"status\":\(status),\"total_users\":2,\"processed_users\":1,\"created_at\":null,\"completed_at\":null,\"error_message\":null}".utf8))
    }
}

/// Finite sequential job-status executor retaining only request-count evidence.
private actor InviteJobScript {
    private var values: [InviteTargetUsersJob]
    private(set) var calls = 0

    /// Stores finite independently constructed status snapshots without starting tasks.
    /// - Parameter values: Responses consumed once in exact supplied order.
    init(_ values: [InviteTargetUsersJob]) { self.values = values }

    /// Checks safe uncached polling metadata before returning the next supplied snapshot.
    /// - Parameter endpoint: One ordinary authenticated job-status GET descriptor.
    /// - Returns: Next exact snapshot, without synthesizing progress or running network I/O.
    /// - Throws: Safe invalid-response if the script is exhausted, exposing accidental extra polling.
    func next(_ endpoint: Endpoint<InviteTargetUsersJob>) throws -> InviteTargetUsersJob {
        #expect(endpoint.readPolicy == nil && endpoint.retrySafety == .safe && endpoint.authentication == .bot)
        #expect(endpoint.route == "/invites/{code}/target-users/job-status")
        calls += 1
        guard !values.isEmpty else { throw DiscordError.transport(.invalidResponse) }
        return values.removeFirst()
    }
}
