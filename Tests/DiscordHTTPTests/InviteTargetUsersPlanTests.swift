// File: Tests/DiscordHTTPTests/InviteTargetUsersPlanTests.swift
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

/// Explicit invite bulk planning preserves legal chunks, ordered acknowledgements and indeterminate partial progress.
@Suite(.timeLimit(.minutes(1))) struct InviteTargetUsersPlanTests {
    /// Legal endpoint groups cover 1, 1,000, 1,001 and the full local plan cap with no skipped or repeated IDs.
    /// - Parameter count: Input size across operation and retained-plan boundaries.
    /// - Throws: Unexpected plan, request or execution errors fail the test.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [1, 1_000, 1_001, 100_000]) func legalChunksAndAcknowledgements(count: Int) async throws {
        let ids = (0..<count).map { UserID(rawValue: UInt64.max - UInt64($0)) }
        for action in [InviteTargetUsersBulkAction.add, .remove] {
            let plan = try BulkInviteTargetUsersPlan(code: "private-code", userIDs: ids, action: action)
            #expect(plan.userIDs == ids && plan.chunks.flatMap { $0 } == ids)
            #expect(plan.chunks.count == (count + 999) / 1_000)
            #expect(plan.chunks.allSatisfy { (1...1_000).contains($0.count) })
            let script = InviteBulkScript()
            let outcome = try await plan.execute(context: TransportContext(clock: ManualClock())) { try await script.next($0) }
            #expect(outcome.acknowledged == ids)
            #expect(await script.ids == ids)
            #expect(await script.calls == plan.chunks.count)
            let suffix: String
            switch action { case .add: suffix = "/bulk-add"; case .remove: suffix = "/bulk-delete" }
            #expect(await script.routes.allSatisfy { $0.hasSuffix(suffix) })
            #expect(plan.description == plan.debugDescription && plan.customMirror.children.count == 1)
            #expect(outcome.description == outcome.debugDescription && outcome.customMirror.children.count == 1)
            #expect(!String(reflecting: plan).contains("private-code"))
            #expect(!String(reflecting: outcome).contains("18446744073709551615"))
        }
    }

    /// Duplicate input requires an explicit deduplication choice; first-occurrence order is stable and counts remain bounded.
    /// - Throws: Unexpected valid construction errors fail the test.
    @Test func validationAndExplicitDeduplication() throws {
        let ids = [UserID(rawValue: 3), .init(rawValue: 1), .init(rawValue: 3), .init(rawValue: 2), .init(rawValue: 1)]
        #expect(throws: DiscordError.validation(.invalidValue)) { try BulkInviteTargetUsersPlan(code: "c", userIDs: ids, action: .add) }
        let plan = try BulkInviteTargetUsersPlan(code: "c", userIDs: ids, action: .remove, deduplicate: true)
        #expect(plan.userIDs.map(\.rawValue) == [3, 1, 2] && plan.chunks.count == 1)
        for values: [UserID] in [[], Array(repeating: .init(rawValue: 1), count: 100_001)] {
            #expect(throws: DiscordError.validation(.invalidValue)) { try BulkInviteTargetUsersPlan(code: "c", userIDs: values, action: .add) }
            #expect(throws: DiscordError.validation(.invalidValue)) { try BulkInviteTargetUsersPlan(code: "c", userIDs: values, action: .add, deduplicate: true) }
        }
        for code in ["", "..", "a/b", "a\nb"] {
            #expect(throws: DiscordError.validation(.invalidValue)) { try BulkInviteTargetUsersPlan(code: code, userIDs: [.init(rawValue: 1)], action: .add) }
        }
    }

    /// A rejected or indeterminate second chunk preserves acknowledged first-group IDs and never enters the final group.
    /// - Parameter failure: Distinct API, transport, malformed-acknowledgement and uncertain-mutation evidence is retained exactly.
    /// - Throws: Unexpected setup errors fail the test; progress is asserted on the operation-specific failure.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [DiscordError.api(status: 403, code: 50013), .unknownMutationOutcome(.connectionLostAfterSubmission), .transport(.invalidResponse)])
    func partialFailure(failure: DiscordError) async throws {
        let ids = (1...2_001).map { UserID(rawValue: UInt64($0)) }
        let script = InviteBulkScript(failure: failure, failOnCall: 2)
        let plan = try BulkInviteTargetUsersPlan(code: "c", userIDs: ids, action: .add)
        do {
            _ = try await plan.execute(context: TransportContext(clock: ManualClock())) { try await script.next($0) }
            Issue.record("Expected bulk failure")
        } catch let error as BulkInviteTargetUsersFailure {
            #expect(error.acknowledged == Array(ids.prefix(1_000)))
            #expect(error.attempted == Array(ids[1_000..<2_000]) && error.unattempted == [ids[2_000]])
            #expect(error.underlying as? DiscordError == failure)
            #expect(error.description == error.debugDescription && error.customMirror.children.count == 1)
            #expect(!String(reflecting: error).contains("2001"))
        }
        #expect(await script.calls == 2)
    }

    /// Pre-entry cancellation/deadlines record no attempted IDs; racing acknowledgements survive cancellation cleanup.
    /// - Throws: Unexpected plan/setup errors fail the test; all expected failures are inspected.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func preEntryFailuresAndRacingAcknowledgement() async throws {
        let ids = [UserID(rawValue: UInt64.max)]
        let plan = try BulkInviteTargetUsersPlan(code: "c", userIDs: ids, action: .remove)
        let clock = ManualClock()
        do {
            _ = try await plan.execute(context: TransportContext(clock: clock, deadline: clock.now)) { _ in Issue.record("Expired execution"); return try EmptyResponse(data: Data()) }
            Issue.record("Expected deadline")
        } catch let error as BulkInviteTargetUsersFailure {
            #expect(error.acknowledged.isEmpty && error.attempted.isEmpty && error.unattempted == ids)
            #expect(error.underlying as? TransportFailure == .deadlineExceeded)
        }
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await plan.execute(context: TransportContext(clock: clock)) { _ in Issue.record("Cancelled execution"); return try EmptyResponse(data: Data()) }
        }
        do { _ = try await cancelled.value; Issue.record("Expected cancellation") }
        catch let error as BulkInviteTargetUsersFailure { #expect(error.acknowledged.isEmpty && error.attempted.isEmpty && error.unattempted == ids && error.underlying is CancellationError) }
        let racing = Task {
            try await plan.execute(context: TransportContext(clock: clock)) { _ in
                withUnsafeCurrentTask { $0?.cancel() }
                return try EmptyResponse(data: Data())
            }
        }
        do { _ = try await racing.value; Issue.record("Expected post-acknowledgement cancellation") }
        catch let error as BulkInviteTargetUsersFailure {
            #expect(error.acknowledged == ids && error.attempted.isEmpty && error.unattempted.isEmpty && error.underlying is CancellationError)
        }
    }

    /// Mid-chunk cancellation/deadline expiry releases the suspended executor before progress evidence is returned.
    /// - Parameter expires: True expires the first group; false cancels the second after one acknowledged group.
    /// - Throws: Unexpected fixture, barrier or clock failures fail the test.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [false, true]) func suspendedTermination(expires: Bool) async throws {
        let ids = (1...(expires ? 1_001 : 2_001)).map { UserID(rawValue: UInt64($0)) }
        let entered = TestBarrier(), timer = TestBarrier()
        let gate = TestBarrier(onWaitScheduled: { entered.open() })
        let clock = ManualClock(onSleepScheduled: { timer.open() })
        let script = InviteBulkScript(gate: gate, suspendOnCall: expires ? 1 : 2)
        let plan = try BulkInviteTargetUsersPlan(code: "c", userIDs: ids, action: .add)
        let context = TransportContext(clock: clock, deadline: expires ? clock.now.advanced(by: .seconds(1)) : nil)
        let task = Task { try await plan.execute(context: context) { try await script.next($0) } }
        try await entered.wait()
        if expires { try await timer.wait(); try clock.advance(by: .seconds(1)) } else { task.cancel() }
        do { _ = try await task.value; Issue.record("Expected suspended operation to fail") }
        catch let error as BulkInviteTargetUsersFailure {
            let completed = expires ? 0 : 1_000
            #expect(error.acknowledged == Array(ids.prefix(completed)))
            #expect(error.attempted == Array(ids[completed..<(completed + 1_000)]) && error.unattempted == [ids.last!])
            if expires { #expect(error.underlying as? TransportFailure == .deadlineExceeded) }
            else { #expect(error.underlying is CancellationError) }
        }
        #expect(await script.calls == (expires ? 1 : 2))
        #expect(await script.active == 0)
        #expect(gate.waitingCount == 0 && clock.pendingSleepCount == 0)
    }
}

/// Sequential bulk executor with finite decoded-body accounting and deterministic failure/suspension injection.
@available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
private actor InviteBulkScript {
    private let failure: DiscordError?
    private let failOnCall: Int?
    private let gate: TestBarrier?
    private let suspendOnCall: Int?
    private(set) var ids: [UserID] = []
    private(set) var routes: [String] = []
    private(set) var calls = 0
    private(set) var active = 0

    /// Configures one optional error and one optional cancellation-cooperative suspension without starting tasks.
    /// - Parameters:
    ///   - failure: Optional exact injected cause; nil acknowledges ordinary calls.
    ///   - failOnCall: One-based call index that throws the supplied cause; nil disables failure injection.
    ///   - gate: Optional externally owned suspension gate.
    ///   - suspendOnCall: One-based call index that waits on gate; nil never suspends.
    init(failure: DiscordError? = nil, failOnCall: Int? = nil, gate: TestBarrier? = nil, suspendOnCall: Int? = nil) {
        self.failure = failure; self.failOnCall = failOnCall; self.gate = gate; self.suspendOnCall = suspendOnCall
    }

    /// Captures actual chunk IDs, validates legal wire metadata and applies one configured deterministic outcome.
    /// - Parameter endpoint: One planned documented target-users bulk-add/delete descriptor.
    /// - Returns: Validated empty acknowledgement when no configured failure or cancellation occurs.
    /// - Throws: Injected failure, cancellation, local fixture/body validation or bounded parser failures.
    /// Actor accounting detects unintended overlap; defer records cleanup before caller progress inspection.
    func next(_ endpoint: Endpoint<EmptyResponse>) async throws -> EmptyResponse {
        calls += 1; active += 1
        defer { active -= 1 }
        #expect(active == 1 && endpoint.retrySafety == .unsafe && endpoint.bulk?.maximumItems == 1_000)
        routes.append(endpoint.route)
        guard case .object(let fields) = try JSONValue.parse(#require(endpoint.body?.bytes)),
              case .array(let values) = fields["user_ids"] else { throw DiscordError.transport(.invalidResponse) }
        #expect((1...1_000).contains(values.count))
        for value in values {
            guard case .string(let raw) = value, let integer = UInt64(raw) else { throw DiscordError.transport(.invalidResponse) }
            ids.append(UserID(rawValue: integer))
        }
        if calls == suspendOnCall { try await gate?.wait() }
        if calls == failOnCall, let failure { throw failure }
        return try endpoint.decode(Data())
    }
}
