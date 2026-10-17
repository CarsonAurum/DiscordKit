import DiscordCore
import DiscordModels
import DiscordTestSupport
import DiscordTransport
import Foundation
import Testing
@testable import DiscordHTTP

/// Audit continuation preserves complete envelopes, exclusive exact cursors and finite resource ownership.
@Suite(.timeLimit(.minutes(1))) struct AuditLogOperationsTests {
    /// Short pages continue in both directions; an empty envelope is yielded once and nothing is prefetched.
    /// - Parameter ascending: True starts after zero; false uses the default newest-first direction.
    /// - Throws: Unexpected fixtures, descriptor or iteration errors fail this test.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [false, true]) func continuation(ascending: Bool) async throws {
        let ids: [UInt64] = ascending ? [9_007_199_254_740_993, UInt64.max] : [UInt64.max, 9_007_199_254_740_993]
        let script = AuditPageScript(try [ids.prefix(1).map { $0 }, ids.suffix(1).map { $0 }, []].map {
            try AuditLog(data: ModerationEndpointTests.auditData($0))
        })
        let sequence = try AuditLogOperations.pages(guildID: .init(rawValue: 1), userID: .init(rawValue: 7),
            actionType: .init(rawValue: 999), position: ascending ? .after(.init(rawValue: 0)) : nil,
            limit: 2, context: TransportContext(clock: ManualClock())) { try await script.next($0) }
        #expect(await script.calls == 0)
        var iterator = sequence.makeAsyncIterator()
        #expect(try await iterator.next()?.auditLogEntries.first?.id.rawValue == ids[0])
        #expect(await script.calls == 1)
        #expect(try await iterator.next()?.auditLogEntries.first?.id.rawValue == ids[1])
        let final = try #require(await iterator.next())
        #expect(final.auditLogEntries.isEmpty)
        #expect(final.users.first?.id.rawValue == 7)
        #expect(try await iterator.next() == nil)
        #expect(await script.calls == 3)
        let cursor = ascending ? "after" : "before"
        #expect(await script.queries == [
            [.init(name: "user_id", value: "7"), .init(name: "action_type", value: "999")] +
                (ascending ? [.init(name: "after", value: "0")] : []) + [.init(name: "limit", value: "2")],
            [.init(name: "user_id", value: "7"), .init(name: "action_type", value: "999"), .init(name: cursor, value: String(ids[0])), .init(name: "limit", value: "2")],
            [.init(name: "user_id", value: "7"), .init(name: "action_type", value: "999"), .init(name: cursor, value: String(ids[1])), .init(name: "limit", value: "2")]
        ])
        #expect(await script.reused == false)
        var independent = sequence.makeAsyncIterator()
        await #expect(throws: TransportFailure.closed) { try await independent.next() }
        #expect(try await independent.next() == nil)
    }

    /// Two iterators each begin from their configured boundary and independently finish at the maximum legal page size.
    /// Stopping after one pull cannot advance either cursor or start a hidden request for another page.
    /// - Parameter ascending: Exercises explicit before and after boundaries with 100-entry pages.
    /// - Throws: Unexpected fixture, configuration or iteration failures fail this test.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [false, true]) func independentBoundaryIterators(ascending: Bool) async throws {
        let ids = ascending ? Array(UInt64(101)...200) : Array((UInt64(1)...100).reversed())
        let page = try AuditLog(data: ModerationEndpointTests.auditData(ids))
        let empty = try AuditLog(data: ModerationEndpointTests.auditData())
        let script = AuditPageScript([page, page, empty, empty])
        let position: AuditLogPosition = ascending ? .after(.init(rawValue: 100)) : .before(.init(rawValue: 101))
        let pages = try AuditLogOperations.pages(guildID: .init(rawValue: 1), position: position,
            limit: 100, maximumPages: 10_000, context: TransportContext(clock: ManualClock())) {
                try await script.next($0)
            }
        var first = pages.makeAsyncIterator(), second = pages.makeAsyncIterator()
        #expect(await script.calls == 0)
        #expect(try await first.next() == page)
        #expect(await script.calls == 1)
        #expect(try await second.next() == page)
        #expect(await script.calls == 2)
        #expect(try await first.next() == empty)
        #expect(try await first.next() == nil)
        #expect(await script.calls == 3)
        #expect(try await second.next() == empty)
        #expect(try await second.next() == nil)
        #expect(await script.calls == 4)
        let name = ascending ? "after" : "before"
        let initial = [QueryItem(name: name, value: ascending ? "100" : "101"), .init(name: "limit", value: "100")]
        let final = [QueryItem(name: name, value: ascending ? "200" : "1"), .init(name: "limit", value: "100")]
        #expect(await script.queries == [initial, initial, final, final])
        #expect(await script.reused == false)
    }

    /// Invalid local limits and request budgets are rejected synchronously before any executor call.
    /// - Parameter value: Invalid count, including integer extremes and both adjacent limits.
    /// - Throws: Expected validation rejections are asserted explicitly.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [Int.min, -1, 0, 101, 10_001, Int.max]) func invalidBounds(value: Int) throws {
        let context = TransportContext(clock: ManualClock())
        #expect(throws: DiscordError.validation(.invalidValue)) {
            try AuditLogOperations.pages(guildID: .init(rawValue: 1), limit: value, context: context) { _ in
                Issue.record("Invalid limit entered executor"); return try AuditLog(data: ModerationEndpointTests.auditData())
            }
        }
        if value != 101 {
            #expect(throws: DiscordError.validation(.invalidValue)) {
                try AuditLogOperations.pages(guildID: .init(rawValue: 1), maximumPages: value, context: context) { _ in
                    Issue.record("Invalid budget entered executor"); return try AuditLog(data: ModerationEndpointTests.auditData())
                }
            }
        }
    }

    /// Every row must advance: duplicate, reversed, boundary and oversized results permanently finish iteration.
    /// - Parameter ascending: Both documented sort directions and explicit initial cursor paths are checked.
    /// - Throws: Unexpected fixture errors fail this test; malformed response failures are asserted.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [false, true]) func malformedPages(ascending: Bool) async throws {
        let invalid: [[UInt64]] = ascending ? [[11, 11], [12, 11], [10], [9], [11, 12, 13]] :
            [[9, 9], [8, 9], [10], [11], [9, 8, 7]]
        for ids in invalid {
            let script = AuditPageScript([try AuditLog(data: ModerationEndpointTests.auditData(ids))])
            var iterator = try AuditLogOperations.pages(guildID: .init(rawValue: 1),
                position: ascending ? .after(.init(rawValue: 10)) : .before(.init(rawValue: 10)), limit: 2,
                context: TransportContext(clock: ManualClock())) { try await script.next($0) }.makeAsyncIterator()
            await #expect(throws: DiscordError.transport(.invalidResponse)) { try await iterator.next() }
            #expect(try await iterator.next() == nil)
            #expect(await script.calls == 1)
        }
    }

    /// Maximum pages, executor failures and expired deadlines terminate without a later request.
    /// - Throws: Unexpected fixture/setup errors fail this test.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func terminalFailures() async throws {
        let clock = ManualClock(), script = AuditPageScript([try AuditLog(data: ModerationEndpointTests.auditData([3]))])
        var limited = try AuditLogOperations.pages(guildID: .init(rawValue: 1), maximumPages: 1,
            context: TransportContext(clock: clock)) { try await script.next($0) }.makeAsyncIterator()
        #expect(try await limited.next()?.auditLogEntries.count == 1)
        await #expect(throws: DiscordError.validation(.limitExceeded)) { try await limited.next() }
        #expect(try await limited.next() == nil)
        #expect(await script.calls == 1)
        var failed = try AuditLogOperations.pages(guildID: .init(rawValue: 1), context: TransportContext(clock: clock)) {
            _ in throw TransportFailure.closed
        }.makeAsyncIterator()
        await #expect(throws: TransportFailure.closed) { try await failed.next() }
        #expect(try await failed.next() == nil)
        var expired = try AuditLogOperations.pages(guildID: .init(rawValue: 1),
            context: TransportContext(clock: clock, deadline: clock.now)) { _ in
                Issue.record("Expired executor"); return try AuditLog(data: ModerationEndpointTests.auditData())
            }.makeAsyncIterator()
        await #expect(throws: TransportFailure.deadlineExceeded) { try await expired.next() }
        #expect(try await expired.next() == nil)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            var iterator = try AuditLogOperations.pages(guildID: .init(rawValue: 1), context: TransportContext(clock: clock)) { _ in
                Issue.record("Cancelled executor"); return try AuditLog(data: ModerationEndpointTests.auditData())
            }.makeAsyncIterator()
            return try await iterator.next()
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(clock.pendingSleepCount == 0)
    }

    /// Cancelling or expiring a suspended fetch releases both executor and deadline ownership before returning.
    /// - Parameter expires: True advances the virtual deadline; false cancels the waiting task.
    /// - Throws: Unexpected setup/barrier errors fail this test.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [false, true]) func suspendedTermination(expires: Bool) async throws {
        let entered = TestBarrier(), timer = TestBarrier(), exited = TestBarrier()
        let blocked = TestBarrier(onWaitScheduled: { entered.open() })
        let clock = ManualClock(onSleepScheduled: { timer.open() })
        let pages = try AuditLogOperations.pages(guildID: .init(rawValue: 1),
            context: TransportContext(clock: clock, deadline: clock.now.advanced(by: .seconds(1)))) { _ in
                defer { exited.open() }
                try await blocked.wait()
                return try AuditLog(data: ModerationEndpointTests.auditData())
            }
        let task = Task {
            var iterator = pages.makeAsyncIterator()
            do { _ = try await iterator.next(); Issue.record("Expected termination") }
            catch is CancellationError { #expect(!expires) }
            catch let error as TransportFailure { #expect(expires && error == .deadlineExceeded) }
            #expect(try await iterator.next() == nil)
        }
        try await entered.wait()
        try await timer.wait()
        if expires { try clock.advance(by: .seconds(1)) } else { task.cancel() }
        try await task.value
        try await exited.wait()
        #expect(clock.pendingSleepCount == 0)
    }
}

/// Finite actor-owned audit envelopes and observed requests; no clock, network or timing assumptions.
private actor AuditPageScript {
    private var values: [AuditLog]
    private(set) var calls = 0
    private(set) var queries: [[QueryItem]] = []
    private(set) var reused = false

    /// Stores bounded responses in their exact scripted order.
    /// - Parameter values: Complete envelopes; exhaustion throws closed instead of fabricating completion.
    init(_ values: [AuditLog]) { self.values = values }

    /// Records one entered request and returns the next envelope without suspension inside actor state changes.
    /// - Parameter endpoint: Real audit descriptor; query order and disabled reuse are observed.
    /// - Returns: Next complete scripted response.
    /// - Throws: TransportFailure.closed when the finite script is exhausted.
    func next(_ endpoint: Endpoint<AuditLog>) throws -> AuditLog {
        calls += 1; queries.append(endpoint.query); reused = reused || endpoint.readPolicy != nil
        guard !values.isEmpty else { throw TransportFailure.closed }
        return values.removeFirst()
    }
}
