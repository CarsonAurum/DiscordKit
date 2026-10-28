// File: Tests/DiscordHTTPTests/GuildOperationsTests.swift
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

/// Exercises bounded guild continuation and explicit bulk-ban progress without live traffic or credentials.
@Suite(.timeLimit(.minutes(1))) struct GuildOperationsTests {
    /// Member pages advance exact ascending IDs, follow short pages, stop at empty and never prefetch.
    /// - Throws: Unexpected fixture, descriptor or iteration failures fail the test.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func memberContinuation() async throws {
        let script = GuildPageScript([try members([9_007_199_254_740_993]), try members([UInt64.max]), []])
        let pages = try GuildOperations.memberPages(guildID: .init(rawValue: 1), after: .init(rawValue: 10), limit: 2,
            context: TransportContext(clock: ManualClock())) { try await script.next($0) }
        #expect(await script.calls == 0)
        var iterator = pages.makeAsyncIterator()
        #expect(try await iterator.next()?.count == 1)
        #expect(await script.calls == 1)
        #expect(try await iterator.next()?.count == 1)
        #expect(try await iterator.next()?.isEmpty == true)
        #expect(try await iterator.next() == nil)
        #expect(await script.cursors == ["10", "9007199254740993", "18446744073709551615"])
        #expect(await script.reuseCount == 0)
        var independent = pages.makeAsyncIterator()
        await #expect(throws: DiscordError.transport(.invalidResponse)) { try await independent.next() }
        #expect(try await independent.next() == nil)
    }

    /// Bans advance after IDs in ascending order and do not confuse before precedence with reverse pagination.
    /// - Throws: Unexpected fixture or workflow errors fail the test.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func banContinuation() async throws {
        let script = GuildPageScript([try bans([2]), try bans([3]), []])
        let pages = try GuildOperations.banPages(guildID: .init(rawValue: 1), limit: 2,
            context: TransportContext(clock: ManualClock())) { try await script.next($0) }
        #expect(await script.calls == 0)
        var iterator = pages.makeAsyncIterator()
        #expect(try await iterator.next()?.first?.user.id.rawValue == 2)
        #expect(try await iterator.next()?.first?.user.id.rawValue == 3)
        #expect(try await iterator.next()?.isEmpty == true)
        #expect(try await iterator.next() == nil)
        #expect(await script.cursors == [nil, "2", "3"])
        #expect(await script.reuseCount == 0)
    }

    /// Invalid local bounds fail before an executor can run or allocate request ownership.
    /// - Parameter value: Invalid inclusive-bound value, including machine integer extremes.
    /// - Throws: Only unexpected fixture errors; validation rejections are asserted locally.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [Int.min, -1, 0, 10_001, Int.max]) func invalidBounds(value: Int) throws {
        let context = TransportContext(clock: ManualClock())
        #expect(throws: DiscordError.validation(.invalidValue)) {
            try GuildOperations.memberPages(guildID: .init(rawValue: 1), maximumPages: value, context: context) { _ in [] }
        }
        #expect(throws: DiscordError.validation(.invalidValue)) {
            try GuildOperations.banPages(guildID: .init(rawValue: 1), maximumPages: value, context: context) { _ in [] }
        }
        for limit in [0, 1_001, Int.min, Int.max] {
            #expect(throws: DiscordError.validation(.invalidValue)) {
                try GuildOperations.memberPages(guildID: .init(rawValue: 1), limit: limit, context: context) { _ in [] }
            }
            #expect(throws: DiscordError.validation(.invalidValue)) {
                try GuildOperations.banPages(guildID: .init(rawValue: 1), limit: limit, context: context) { _ in [] }
            }
        }
    }

    /// Missing users, oversized, repeated, reversed and out-of-bound IDs terminate iteration safely.
    /// - Throws: Unexpected fixture construction errors fail the test; schema failures are asserted.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func malformedPages() async throws {
        let missing = try GuildMember(data: Data(#"{"roles":[],"joined_at":null,"deaf":false,"mute":false,"flags":0}"#.utf8))
        for page in [try members([11, 12, 13]), try members([11, 11]), try members([12, 11]), try members([10]), [missing]] {
            let script = GuildPageScript([page])
            var iterator = try GuildOperations.memberPages(guildID: .init(rawValue: 1), after: .init(rawValue: 10), limit: 2,
                context: TransportContext(clock: ManualClock())) { try await script.next($0) }.makeAsyncIterator()
            await #expect(throws: DiscordError.transport(.invalidResponse)) { try await iterator.next() }
            #expect(try await iterator.next() == nil)
            #expect(await script.calls == 1)
        }
        for page in [try bans([11, 12, 13]), try bans([11, 11]), try bans([12, 11]), try bans([10])] {
            let script = GuildPageScript([page])
            var iterator = try GuildOperations.banPages(guildID: .init(rawValue: 1), after: .init(rawValue: 10), limit: 2,
                context: TransportContext(clock: ManualClock())) { try await script.next($0) }.makeAsyncIterator()
            await #expect(throws: DiscordError.transport(.invalidResponse)) { try await iterator.next() }
            #expect(try await iterator.next() == nil)
        }
    }

    /// Cancellation, inclusive deadline, executor error and page exhaustion finish both sequences permanently.
    /// - Parameter bans: Selects ban or member pagination under identical termination invariants.
    /// - Throws: Unexpected setup errors fail the test; all expected failures are asserted.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [false, true]) func pageFailures(bans: Bool) async throws {
        let clock = ManualClock(), context = TransportContext(clock: ManualClock())
        if bans {
            let script = GuildPageScript([try self.bans([1]), try self.bans([2])])
            var iterator = try GuildOperations.banPages(guildID: .init(rawValue: 1), maximumPages: 1, context: context) { try await script.next($0) }.makeAsyncIterator()
            #expect(try await iterator.next()?.count == 1)
            await #expect(throws: DiscordError.validation(.limitExceeded)) { try await iterator.next() }
            #expect(try await iterator.next() == nil)
            #expect(await script.calls == 1)
            var expired = try GuildOperations.banPages(guildID: .init(rawValue: 1), context: TransportContext(clock: clock, deadline: clock.now)) { _ in [] }.makeAsyncIterator()
            await #expect(throws: TransportFailure.deadlineExceeded) { try await expired.next() }
            #expect(try await expired.next() == nil)
            var failed = try GuildOperations.banPages(guildID: .init(rawValue: 1), context: context) { _ in throw TransportFailure.closed }.makeAsyncIterator()
            await #expect(throws: TransportFailure.closed) { try await failed.next() }
            #expect(try await failed.next() == nil)
            let task = Task { () throws -> [GuildBan]? in
                withUnsafeCurrentTask { $0?.cancel() }
                var cancelled = try GuildOperations.banPages(guildID: .init(rawValue: 1), context: context) { _ in Issue.record("Cancelled fetch"); return [] }.makeAsyncIterator()
                return try await cancelled.next()
            }
            await #expect(throws: CancellationError.self) { try await task.value }
        } else {
            let script = GuildPageScript([try members([1]), try members([2])])
            var iterator = try GuildOperations.memberPages(guildID: .init(rawValue: 1), maximumPages: 1, context: context) { try await script.next($0) }.makeAsyncIterator()
            #expect(try await iterator.next()?.count == 1)
            await #expect(throws: DiscordError.validation(.limitExceeded)) { try await iterator.next() }
            #expect(try await iterator.next() == nil)
            var expired = try GuildOperations.memberPages(guildID: .init(rawValue: 1), context: TransportContext(clock: clock, deadline: clock.now)) { _ in [] }.makeAsyncIterator()
            await #expect(throws: TransportFailure.deadlineExceeded) { try await expired.next() }
            #expect(try await expired.next() == nil)
            var failed = try GuildOperations.memberPages(guildID: .init(rawValue: 1), context: context) { _ in throw TransportFailure.closed }.makeAsyncIterator()
            await #expect(throws: TransportFailure.closed) { try await failed.next() }
            #expect(try await failed.next() == nil)
            let task = Task { () throws -> [GuildMember]? in
                withUnsafeCurrentTask { $0?.cancel() }
                var cancelled = try GuildOperations.memberPages(guildID: .init(rawValue: 1), context: context) { _ in Issue.record("Cancelled fetch"); return [] }.makeAsyncIterator()
                return try await cancelled.next()
            }
            await #expect(throws: CancellationError.self) { try await task.value }
        }
    }

    /// Cancellation and inclusive deadline expiry interrupt suspended member/ban reads and release both owned children.
    /// - Parameters:
    ///   - bans: True exercises ban pagination; false exercises member pagination.
    ///   - expires: True advances the injected clock exactly to the deadline; false cancels the awaiting task.
    /// - Throws: Unexpected fixture, descriptor, barrier or task failures fail the test.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [false, true], [false, true]) func suspendedPageTermination(bans: Bool, expires: Bool) async throws {
        let entered = TestBarrier(), timerReady = TestBarrier()
        let blocked = TestBarrier(onWaitScheduled: { entered.open() })
        let clock = ManualClock(onSleepScheduled: { timerReady.open() })
        let context = TransportContext(clock: clock, deadline: clock.now.advanced(by: .seconds(1)))
        if bans {
            let script = GuildSuspendedPageScript<GuildBan>(blocked: blocked)
            let pages = try GuildOperations.banPages(guildID: .init(rawValue: 1), context: context) { try await script.next($0) }
            try await verifySuspendedPage(pages, script: script, entered: entered, timerReady: timerReady,
                blocked: blocked, clock: clock, expires: expires)
        } else {
            let script = GuildSuspendedPageScript<GuildMember>(blocked: blocked)
            let pages = try GuildOperations.memberPages(guildID: .init(rawValue: 1), context: context) { try await script.next($0) }
            try await verifySuspendedPage(pages, script: script, entered: entered, timerReady: timerReady,
                blocked: blocked, clock: clock, expires: expires)
        }
    }

    /// Explicit comparisons avoid writes for matching/null/empty edits and retain descriptor errors for real changes.
    /// - Throws: Unexpected snapshot or valid descriptor construction errors fail the test.
    @Test func noOpReconciliation() throws {
        let guild = try Guild(data: Data(GuildEndpointTests.guildJSON.utf8))
        #expect(try GuildOperations.modifyIfChanged(current: guild, request: GuildModify()) == nil)
        #expect(try GuildOperations.modifyIfChanged(current: guild, request: GuildModify(name: .value("fixture"), icon: .null)) == nil)
        #expect(try GuildOperations.modifyIfChanged(current: guild, request: GuildModify(name: .value("new")))?.method == "PATCH")
        #expect(throws: DiscordError.validation(.invalidValue)) {
            try GuildOperations.modifyIfChanged(current: guild, request: GuildModify(name: .value("new")), auditReason: "\n")
        }
        let role = try GuildRole(data: Data(GuildEndpointTests.roleJSON.utf8))
        #expect(try GuildOperations.modifyRoleIfChanged(guildID: guild.id, current: role, request: GuildRoleModify()) == nil)
        #expect(try GuildOperations.modifyRoleIfChanged(guildID: guild.id, current: role, request: GuildRoleModify(name: .value("role"))) == nil)
        #expect(try GuildOperations.modifyRoleIfChanged(guildID: guild.id, current: role, request: GuildRoleModify(icon: .null)) != nil)
        #expect(throws: DiscordError.validation(.invalidValue)) {
            try GuildOperations.modifyRoleIfChanged(guildID: guild.id, current: role, request: GuildRoleModify(name: .value("new")), auditReason: "\n")
        }
    }

    /// Explicit plans use maximal legal chunks, bounded IDs, exact original order and safe diagnostics.
    /// - Throws: Unexpected valid plan errors fail the test; invalid inputs are asserted locally.
    @Test func bulkPlanning() throws {
        for count in [1, 199, 200, 201, 400, 401, 10_000] {
            let ids = (1...count).map { UserID(rawValue: UInt64($0)) }
            let plan = try BulkGuildBanPlan(guildID: .init(rawValue: 1), userIDs: ids, deleteMessageSeconds: 604_800)
            #expect(plan.userIDs == ids)
            #expect(plan.chunks.flatMap { $0 } == ids)
            #expect(plan.chunks.allSatisfy { (1...200).contains($0.count) })
            #expect(plan.chunks.count == (count + 199) / 200)
            #expect(!String(reflecting: plan).contains("guilds"))
            #expect(plan.description == plan.debugDescription)
            #expect(plan.customMirror.children.count == 1)
        }
        for ids in [[], [.init(rawValue: 1), .init(rawValue: 1)], (0...10_000).map { UserID(rawValue: UInt64($0)) }] {
            #expect(throws: DiscordError.validation(.invalidValue)) { try BulkGuildBanPlan(guildID: .init(rawValue: 1), userIDs: ids) }
        }
        for seconds in [-1, 604_801, Int.min, Int.max] {
            #expect(throws: DiscordError.validation(.invalidValue)) { try BulkGuildBanPlan(guildID: .init(rawValue: 1), userIDs: [.init(rawValue: 1)], deleteMessageSeconds: seconds) }
        }
    }

    /// Partial classifications from all chunks remain correlated to input order, with no retry of failed users.
    /// - Throws: Unexpected plan, response or execution errors fail the test.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func bulkPartialSuccess() async throws {
        let ids = (1...401).map { UserID(rawValue: UInt64($0)) }
        let plan = try BulkGuildBanPlan(guildID: .init(rawValue: 1), userIDs: ids)
        let script = GuildBulkScript(mode: 0)
        let result = try await plan.execute(context: TransportContext(clock: ManualClock())) { try await script.next($0) }
        #expect(result.banned == ids.filter { $0.rawValue % 2 == 1 })
        #expect(result.failed == ids.filter { $0.rawValue % 2 == 0 })
        #expect(await script.calls == 3)
        #expect(result.description == result.debugDescription)
        #expect(result.customMirror.children.count == 1)
    }

    /// Thrown or malformed second chunks preserve acknowledged partial results and uncertain attempted IDs.
    /// - Parameter mode: One throws an uncertain transport error; other modes corrupt response correlation.
    /// - Throws: Unexpected plan construction errors fail the test; expected workflow failures are inspected.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: 1...5) func bulkFailureProgress(mode: Int) async throws {
        let ids = (1...401).map { UserID(rawValue: UInt64($0)) }
        let plan = try BulkGuildBanPlan(guildID: .init(rawValue: 1), userIDs: ids)
        let script = GuildBulkScript(mode: mode)
        do {
            _ = try await plan.execute(context: TransportContext(clock: ManualClock())) { try await script.next($0) }
            Issue.record("Expected failure")
        } catch let error as BulkGuildBanFailure {
            #expect(error.banned == ids.prefix(200).filter { $0.rawValue % 2 == 1 })
            #expect(error.failed == ids.prefix(200).filter { $0.rawValue % 2 == 0 })
            #expect(error.attempted == Array(ids[200..<400]))
            #expect(error.unattempted == [ids[400]])
            #expect(error.underlying as? DiscordError == (mode == 1 ? .unknownMutationOutcome(.connectionLostAfterSubmission) : .transport(.invalidResponse)))
            #expect(error.description == error.debugDescription)
            #expect(error.customMirror.children.count == 1)
            #expect(!String(reflecting: error).contains("401"))
        }
        #expect(await script.calls == 2)
    }

    /// Pre-entry cancellation/deadline records no attempt, while cancellation after acknowledgement retains all results.
    /// - Throws: Unexpected plan or timestamp construction errors fail the test; expected errors retain progress.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func bulkCancellationAndDeadline() async throws {
        let ids = [UserID(rawValue: UInt64.max)]
        let plan = try BulkGuildBanPlan(guildID: .init(rawValue: 1), userIDs: ids)
        let clock = ManualClock()
        do {
            _ = try await plan.execute(context: TransportContext(clock: clock, deadline: clock.now)) { _ in Issue.record("Expired execution"); throw CancellationError() }
            Issue.record("Expected deadline")
        } catch let error as BulkGuildBanFailure {
            #expect(error.unattempted == ids && error.attempted.isEmpty && error.banned.isEmpty && error.failed.isEmpty)
            #expect(error.underlying as? TransportFailure == .deadlineExceeded)
        }
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await plan.execute(context: TransportContext(clock: clock)) { _ in Issue.record("Cancelled execution"); throw CancellationError() }
        }
        do { _ = try await cancelled.value; Issue.record("Expected cancellation") }
        catch let error as BulkGuildBanFailure { #expect(error.attempted.isEmpty && error.unattempted == ids && error.underlying is CancellationError) }
        do {
            _ = try await plan.execute(context: TransportContext(clock: clock)) { _ in
                withUnsafeCurrentTask { $0?.cancel() }
                return try GuildBulkBanResult(data: Data(#"{"banned_users":["18446744073709551615"],"failed_users":[]}"#.utf8))
            }
            Issue.record("Expected cancellation after acknowledgement")
        } catch let error as BulkGuildBanFailure {
            #expect(error.banned == ids && error.failed.isEmpty && error.attempted.isEmpty && error.unattempted.isEmpty)
            #expect(error.underlying is CancellationError)
        }
    }

    /// Mid-chunk cancellation preserves acknowledged earlier progress; an in-flight deadline records the uncertain chunk.
    /// - Parameter expires: True expires a suspended first chunk; false cancels a suspended second chunk after partial results.
    /// - Throws: Unexpected plan, barrier, clock or response setup failures fail the test.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [false, true]) func suspendedBulkTermination(expires: Bool) async throws {
        let ids = (1...(expires ? 201 : 401)).map { UserID(rawValue: UInt64($0)) }
        let entered = TestBarrier(), timerReady = TestBarrier()
        let blocked = TestBarrier(onWaitScheduled: { entered.open() })
        let clock = ManualClock(onSleepScheduled: { timerReady.open() })
        let script = GuildSuspendedBulkScript(blocked: blocked, suspendedCall: expires ? 1 : 2)
        let plan = try BulkGuildBanPlan(guildID: .init(rawValue: 1), userIDs: ids)
        let context = TransportContext(clock: clock, deadline: expires ? clock.now.advanced(by: .seconds(1)) : nil)
        let task = Task { try await plan.execute(context: context) { try await script.next($0) } }
        try await entered.wait()
        #expect(blocked.waitingCount == 1)
        #expect(await script.active == 1)
        if expires {
            try await timerReady.wait()
            #expect(clock.pendingSleepCount == 1)
            try clock.advance(by: .seconds(1))
        } else { task.cancel() }
        do {
            _ = try await task.value
            Issue.record("Expected suspended bulk execution to stop")
        } catch let failure as BulkGuildBanFailure {
            let completed = expires ? 0 : 200
            #expect(failure.banned == ids.prefix(completed).filter { $0.rawValue % 2 == 1 })
            #expect(failure.failed == ids.prefix(completed).filter { $0.rawValue % 2 == 0 })
            #expect(failure.attempted == Array(ids[completed..<(completed + 200)]))
            #expect(failure.unattempted == [ids.last!])
            if expires { #expect(failure.underlying as? TransportFailure == .deadlineExceeded) }
            else { #expect(failure.underlying is CancellationError) }
        }
        #expect(await script.calls == (expires ? 1 : 2))
        #expect(await script.active == 0)
        #expect(await script.cleanedUp == (expires ? 1 : 2))
        #expect(blocked.waitingCount == 0)
        #expect(clock.pendingSleepCount == 0)
    }

    /// Coordinates one suspended read so cancellation/deadline order is controlled without timing sleeps.
    /// - Parameters:
    ///   - pages: Typed lazy member/ban sequence whose executor suspends on blocked.
    ///   - script: Actor accounting for executor entry, completion and current resource ownership.
    ///   - entered: Opened only after the executor's cancellable barrier waiter is registered.
    ///   - timerReady: Opened only after the structured deadline child registers its clock sleep.
    ///   - blocked: Executor-owned gate; this helper never opens it, so only cancellation can release execution.
    ///   - clock: Test-local monotonic clock advanced exactly to its one-second deadline when expires is true.
    ///   - expires: Selects deadline expiry instead of cancellation of the iterator's task.
    /// - Throws: Unexpected iterator, barrier or clock errors; expected termination errors are asserted inside the child task.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    private func verifySuspendedPage<Item: Sendable>(_ pages: CursorPagination<Item, UserID, ManualClock>,
        script: GuildSuspendedPageScript<Item>, entered: TestBarrier, timerReady: TestBarrier,
        blocked: TestBarrier, clock: ManualClock, expires: Bool) async throws {
        let task = Task { () async throws -> Void in
            var iterator = pages.makeAsyncIterator()
            do {
                _ = try await iterator.next()
                Issue.record("Expected suspended page to stop")
            } catch {
                if expires { #expect(error as? TransportFailure == .deadlineExceeded) }
                else { #expect(error is CancellationError) }
            }
            #expect(try await iterator.next() == nil)
        }
        try await entered.wait()
        try await timerReady.wait()
        #expect(await script.calls == 1)
        #expect(await script.active == 1)
        #expect(blocked.waitingCount == 1)
        #expect(clock.pendingSleepCount == 1)
        if expires { try clock.advance(by: .seconds(1)) } else { task.cancel() }
        try await task.value
        #expect(await script.calls == 1)
        #expect(await script.active == 0)
        #expect(await script.cleanedUp == 1)
        #expect(blocked.waitingCount == 0)
        #expect(clock.pendingSleepCount == 0)
    }

    /// Builds exact minimal members while preserving absent-user fixtures for separate validation tests.
    /// - Parameter ids: Ordered user IDs, including duplicates when testing malformed pagination.
    /// - Returns: Complete member projections in caller order.
    /// - Throws: Unexpected fixture schema errors.
    private func members(_ ids: [UInt64]) throws -> [GuildMember] {
        try ids.map { try GuildMember(data: Data("{\"user\":{\"id\":\"\($0)\"},\"roles\":[],\"joined_at\":null,\"deaf\":false,\"mute\":false,\"flags\":0}".utf8)) }
    }

    /// Builds ordered ban fixtures without fetching any user profiles.
    /// - Parameter ids: Ordered exact user IDs, including invalid ordering for regression coverage.
    /// - Returns: One minimal ban per supplied ID.
    /// - Throws: Unexpected fixture schema errors.
    private func bans(_ ids: [UInt64]) throws -> [GuildBan] {
        try ids.map { try GuildBan(data: Data("{\"reason\":null,\"user\":{\"id\":\"\($0)\"}}".utf8)) }
    }
}

/// Actor-owned finite page script, permitting deterministic request-count and exact-cursor assertions.
private actor GuildPageScript<Item: Sendable> {
    private var pages: [[Item]]
    private(set) var calls = 0
    private(set) var cursors: [String?] = []
    private(set) var reuseCount = 0
    /// Stores already bounded fixture pages; construction starts no asynchronous work.
    /// - Parameter pages: Ordered responses; exhausting the script throws invalid-response.
    init(_ pages: [[Item]]) { self.pages = pages }
    /// Records one requested page then returns the next scripted result without suspension.
    /// - Parameter endpoint: Typed member/ban descriptor; only after cursors are legal in these workflows.
    /// - Returns: The next bounded fixture array.
    /// - Throws: Invalid-response when the finite script is exhausted.
    func next(_ endpoint: Endpoint<[Item]>) throws -> [Item] {
        calls += 1
        cursors.append(endpoint.query.first { $0.name == "after" }?.value)
        #expect(!endpoint.query.contains { $0.name == "before" })
        if endpoint.readPolicy != nil { reuseCount += 1 }
        guard !pages.isEmpty else { throw DiscordError.transport(.invalidResponse) }
        return pages.removeFirst()
    }
}

/// Scripted bulk executor returning explicit partial results or a corrupted second acknowledgement.
private actor GuildBulkScript {
    private let mode: Int
    private(set) var calls = 0
    /// Selects deterministic acknowledgement behavior without retaining external resources.
    /// - Parameter mode: Zero valid; one throws; two duplicates; three overlaps; four omits; five invents an ID.
    init(mode: Int) { self.mode = mode }
    /// Extracts the submitted IDs and deliberately reverses result order to exercise input correlation.
    /// - Parameter endpoint: Already validated bulk descriptor; all payloads remain within 200 users.
    /// - Returns: A partial-result projection, possibly corrupted on the second call as configured.
    /// - Throws: Unexpected fixture errors, or the selected uncertain connection failure on call two.
    func next(_ endpoint: Endpoint<GuildBulkBanResult>) throws -> GuildBulkBanResult {
        calls += 1
        guard case .object(let body) = try JSONValue.parse(#require(endpoint.body?.storedBodyBytes)),
              case .array(let values) = body["user_ids"] else { throw DiscordError.transport(.invalidResponse) }
        var banned = values.filter { if case .string(let id) = $0, let n = UInt64(id) { n % 2 == 1 } else { false } }.reversed().map { $0 }
        var failed = values.filter { if case .string(let id) = $0, let n = UInt64(id) { n % 2 == 0 } else { false } }.reversed().map { $0 }
        if calls == 2 {
            switch mode {
            case 1: throw DiscordError.unknownMutationOutcome(.connectionLostAfterSubmission)
            case 2: banned.append(banned[0])
            case 3: failed.append(banned[0])
            case 4: banned.removeLast()
            case 5: banned.append(.string("18446744073709551615"))
            default: break
            }
        }
        return try GuildBulkBanResult(data: JSONValue.object(["banned_users": .array(banned), "failed_users": .array(failed)]).serialized())
    }
}


/// A cancellation-cooperative suspended read with actor-owned executor/resource accounting.
@available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
private actor GuildSuspendedPageScript<Item: Sendable> {
    private let blocked: TestBarrier
    private(set) var calls = 0
    private(set) var active = 0
    private(set) var cleanedUp = 0

    /// Stores a test-owned closed barrier without allocating an active operation.
    /// - Parameter blocked: Gate whose registration callback signals deterministic suspension readiness.
    init(blocked: TestBarrier) { self.blocked = blocked }

    /// Holds one requested read until cancellation, keeping cleanup observable even during deadline races.
    /// - Parameter endpoint: Typed descriptor; no real transport or credentials are used.
    /// - Returns: An empty page only if the test explicitly opens the gate, which termination tests never do.
    /// - Throws: The barrier's CancellationError or test-support capacity failure, after recording resource cleanup.
    func next(_ endpoint: Endpoint<[Item]>) async throws -> [Item] {
        calls += 1; active += 1
        defer { active -= 1; cleanedUp += 1 }
        try await blocked.wait()
        return []
    }
}

/// Holds a chosen bulk chunk while earlier chunks return valid partial classifications.
@available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
private actor GuildSuspendedBulkScript {
    private let blocked: TestBarrier
    private let suspendedCall: Int
    private let responses = GuildBulkScript(mode: 0)
    private(set) var calls = 0
    private(set) var active = 0
    private(set) var cleanedUp = 0

    /// Selects the entered chunk that remains suspended until cancellation.
    /// - Parameters:
    ///   - blocked: Cancellation-aware gate whose registration signals the test.
    ///   - suspendedCall: Positive one-based chunk ordinal to block; preceding calls return real fixture results.
    init(blocked: TestBarrier, suspendedCall: Int) { self.blocked = blocked; self.suspendedCall = suspendedCall }

    /// Records one chunk execution and guarantees actor-observable cleanup before its result/error returns.
    /// - Parameter endpoint: Validated bulk descriptor whose body drives the fixture response correlation.
    /// - Returns: Odd-user successes/even-user explicit failures for a nonblocked chunk.
    /// - Throws: Cancellation from the blocked gate or unexpected descriptor/fixture validation errors.
    func next(_ endpoint: Endpoint<GuildBulkBanResult>) async throws -> GuildBulkBanResult {
        calls += 1; active += 1
        defer { active -= 1; cleanedUp += 1 }
        if calls == suspendedCall { try await blocked.wait() }
        return try await responses.next(endpoint)
    }
}
