import DiscordCore
import DiscordModels
import DiscordTestSupport
import DiscordTransport
import Foundation
import Testing
@testable import DiscordHTTP

/// Finite monetization traversal using exact fixtures, synthetic ownership and virtual time, without live requests.
@Suite(.timeLimit(.minutes(1))) struct MonetizationOperationsTests {
    /// Both directions retain filters, preserve unsorted wire order, advance by extrema and continue short pages to empty.
    /// - Parameter ascending: Selects after versus before continuation, including extreme unsigned IDs.
    /// - Throws: Unexpected fixture, descriptor or iteration failures fail the test.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [true, false]) func entitlementContinuation(ascending: Bool) async throws {
        let ids: [[UInt64]] = ascending ? [[12, 11], [.max], []] : [[9, 8], [1], []]
        let script = MonetizationPageScript(try ids.map { try Self.entitlements($0) })
        let pages = try EntitlementOperations.pages(applicationID: .init(rawValue: 2), userID: .init(rawValue: 3),
            skuIDs: [.init(rawValue: 4)], direction: ascending ? .ascending : .descending,
            cursor: .init(rawValue: 10), limit: 2, guildID: .init(rawValue: 5), excludeEnded: false, excludeDeleted: true,
            context: TransportContext(clock: ManualClock())) { try await script.next($0) }
        #expect(await script.calls == 0)
        var iterator = pages.makeAsyncIterator()
        for expected in ids { #expect(try await iterator.next()?.map(\.id.rawValue) == expected) }
        #expect(try await iterator.next() == nil)
        #expect(await script.calls == 3)
        #expect(await script.reuseCount == 0)
        let queries = await script.queries
        let key = ascending ? "after" : "before"
        #expect(queries.compactMap { $0.first { $0.name == key }?.value } ==
            (ascending ? ["10", "12", "18446744073709551615"] : ["10", "8", "1"]))
        for query in queries {
            #expect(query.contains(.init(name: "user_id", value: "3")))
            #expect(query.contains(.init(name: "sku_ids", value: "4")))
            #expect(query.contains(.init(name: "guild_id", value: "5")))
            #expect(query.contains(.init(name: "exclude_ended", value: "false")))
            #expect(query.contains(.init(name: "exclude_deleted", value: "true")))
        }
    }

    /// Subscription traversal retains user filtering and authentication while continuing short pages without prefetch.
    /// - Parameters:
    ///   - ascending: Selects increasing versus decreasing exclusive boundaries.
    ///   - filtered: A user filter permits bot/Bearer auth; omission requires Bearer auth.
    /// - Throws: Unexpected fixture or iteration failures fail the test.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [true, false], [true, false])
    func subscriptionContinuation(ascending: Bool, filtered: Bool) async throws {
        let ids: [[UInt64]] = ascending ? [[12, 11], [.max], []] : [[9, 8], [1], []]
        let script = MonetizationPageScript(try ids.map { try Self.subscriptions($0) })
        let pages = try SubscriptionOperations.pages(skuID: .init(rawValue: 4),
            userID: filtered ? .init(rawValue: 3) : nil, direction: ascending ? .ascending : .descending,
            cursor: .init(rawValue: 10), limit: 2, context: TransportContext(clock: ManualClock())) {
                #expect($0.authentication == (filtered ? .botOrBearer : .bearer))
                return try await script.next($0)
            }
        #expect(await script.calls == 0)
        var iterator = pages.makeAsyncIterator()
        for expected in ids { #expect(try await iterator.next()?.map(\.id.rawValue) == expected) }
        #expect(try await iterator.next() == nil)
        #expect(await script.calls == 3)
        #expect(await script.reuseCount == 0)
        let queries = await script.queries
        let key = ascending ? "after" : "before"
        #expect(queries.compactMap { $0.first { $0.name == key }?.value } ==
            (ascending ? ["10", "12", "18446744073709551615"] : ["10", "8", "1"]))
        #expect(queries.allSatisfy { $0.contains(.init(name: "user_id", value: "3")) == filtered })
    }

    /// Omitted ascending cursors explicitly select after zero; omitted descending cursors leave the server boundary absent.
    /// Separate iterators own their initial cursor independently and terminate on one empty page.
    /// - Parameter ascending: Exercises each direction's nil-cursor policy for both resource families.
    /// - Throws: Unexpected descriptor/iteration failures fail the test.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [true, false]) func initialBoundaries(ascending: Bool) async throws {
        let direction: MonetizationTraversal = ascending ? .ascending : .descending
        let entitlements = MonetizationPageScript<Entitlement>([[], []])
        let subscriptions = MonetizationPageScript<Subscription>([[], []])
        let first = try EntitlementOperations.pages(applicationID: .init(rawValue: 2), direction: direction,
            context: TransportContext(clock: ManualClock())) { try await entitlements.next($0) }
        let second = try SubscriptionOperations.pages(skuID: .init(rawValue: 4), direction: direction,
            context: TransportContext(clock: ManualClock())) { try await subscriptions.next($0) }
        var a = first.makeAsyncIterator(), b = first.makeAsyncIterator()
        var c = second.makeAsyncIterator(), d = second.makeAsyncIterator()
        #expect(try await a.next()?.isEmpty == true); #expect(try await b.next()?.isEmpty == true)
        #expect(try await c.next()?.isEmpty == true); #expect(try await d.next()?.isEmpty == true)
        #expect(try await a.next() == nil); #expect(try await c.next() == nil)
        let queries = await entitlements.queries + subscriptions.queries
        #expect(queries.count == 4)
        #expect(queries.allSatisfy { $0.contains(.init(name: "after", value: "0")) == ascending })
        #expect(queries.allSatisfy { !$0.contains { $0.name == "before" } })
    }

    /// Both families reject invalid per-page and total request budgets before fetching, including integer extremes.
    /// - Throws: Unexpected valid setup errors fail the test; exact safe validation errors are asserted.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func invalidConfiguration() throws {
        let context = TransportContext(clock: ManualClock())
        for value in [Int.min, -1, 0, 101, Int.max] {
            #expect(throws: DiscordError.validation(.invalidValue)) {
                try EntitlementOperations.pages(applicationID: .init(rawValue: 2), limit: value,
                    context: context) { _ in Issue.record("Unexpected execution"); return [] }
            }
            #expect(throws: DiscordError.validation(.invalidValue)) {
                try SubscriptionOperations.pages(skuID: .init(rawValue: 4), limit: value,
                    context: context) { _ in Issue.record("Unexpected execution"); return [] }
            }
        }
        for value in [Int.min, -1, 0, 10_001, Int.max] {
            #expect(throws: DiscordError.validation(.invalidValue)) {
                try EntitlementOperations.pages(applicationID: .init(rawValue: 2), maximumPages: value,
                    context: context) { _ in Issue.record("Unexpected execution"); return [] }
            }
            #expect(throws: DiscordError.validation(.invalidValue)) {
                try SubscriptionOperations.pages(skuID: .init(rawValue: 4), maximumPages: value,
                    context: context) { _ in Issue.record("Unexpected execution"); return [] }
            }
        }
        for ids in [[SKUID(rawValue: 1), SKUID(rawValue: 1)], (0...100).map { SKUID(rawValue: UInt64($0)) }] {
            #expect(throws: DiscordError.validation(.invalidValue)) {
                try EntitlementOperations.pages(applicationID: .init(rawValue: 2), skuIDs: ids,
                    context: context) { _ in Issue.record("Invalid filter execution"); return [] }
            }
        }
    }

    /// Oversized, duplicate and out-of-bound pages terminate permanently, preserving the request budget on failure.
    /// - Parameter ascending: Both exclusive directions, including equality and crossing the selected cursor.
    /// - Throws: Unexpected fixture/setup failures fail the test; malformed-page failures are asserted.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [true, false]) func malformedPages(ascending: Bool) async throws {
        let invalid: [[UInt64]] = ascending ? [[11, 11], [10], [9], [11, 12, 13]] : [[9, 9], [10], [11], [7, 8, 9]]
        for ids in invalid {
            let entitlements = MonetizationPageScript([try Self.entitlements(ids)])
            let subscriptions = MonetizationPageScript([try Self.subscriptions(ids)])
            var a = try EntitlementOperations.pages(applicationID: .init(rawValue: 2),
                direction: ascending ? .ascending : .descending, cursor: .init(rawValue: 10), limit: 2,
                context: TransportContext(clock: ManualClock())) { try await entitlements.next($0) }.makeAsyncIterator()
            var b = try SubscriptionOperations.pages(skuID: .init(rawValue: 4),
                direction: ascending ? .ascending : .descending, cursor: .init(rawValue: 10), limit: 2,
                context: TransportContext(clock: ManualClock())) { try await subscriptions.next($0) }.makeAsyncIterator()
            await #expect(throws: DiscordError.transport(.invalidResponse)) { try await a.next() }
            await #expect(throws: DiscordError.transport(.invalidResponse)) { try await b.next() }
            #expect(try await a.next() == nil); #expect(try await b.next() == nil)
            #expect(await entitlements.calls == 1); #expect(await subscriptions.calls == 1)
        }
    }

    /// Wrong owning applications, subscription SKUs and filtered users fail without silently crossing resource scope.
    /// - Throws: Unexpected fixture/setup errors fail the test; invalid-response is asserted.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func mismatchedOwnership() async throws {
        let wrong = try Self.entitlements([1], application: 9)
        var a = try EntitlementOperations.pages(applicationID: .init(rawValue: 2),
            context: TransportContext(clock: ManualClock())) { _ in wrong }.makeAsyncIterator()
        await #expect(throws: DiscordError.transport(.invalidResponse)) { try await a.next() }
        #expect(try await a.next() == nil)
        for values in [try Self.subscriptions([1], sku: 9), try Self.subscriptions([1], user: 9)] {
            var b = try SubscriptionOperations.pages(skuID: .init(rawValue: 4), userID: .init(rawValue: 3),
                context: TransportContext(clock: ManualClock())) { _ in values }.makeAsyncIterator()
            await #expect(throws: DiscordError.transport(.invalidResponse)) { try await b.next() }
            #expect(try await b.next() == nil)
        }
    }

    /// Exhausted budgets, original executor errors and already-expired deadlines permanently finish both iterator types.
    /// - Throws: Unexpected setup errors fail the test; exact failure categories are asserted.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func terminalFailures() async throws {
        let clock = ManualClock(), context = TransportContext(clock: ManualClock())
        let entitlements = MonetizationPageScript([try Self.entitlements([1])])
        let subscriptions = MonetizationPageScript([try Self.subscriptions([1])])
        var a = try EntitlementOperations.pages(applicationID: .init(rawValue: 2), maximumPages: 1,
            context: context) { try await entitlements.next($0) }.makeAsyncIterator()
        var b = try SubscriptionOperations.pages(skuID: .init(rawValue: 4), maximumPages: 1,
            context: context) { try await subscriptions.next($0) }.makeAsyncIterator()
        #expect(try await a.next()?.count == 1); #expect(try await b.next()?.count == 1)
        await #expect(throws: DiscordError.validation(.limitExceeded)) { try await a.next() }
        await #expect(throws: DiscordError.validation(.limitExceeded)) { try await b.next() }
        #expect(try await a.next() == nil); #expect(try await b.next() == nil)
        #expect(await entitlements.calls == 1); #expect(await subscriptions.calls == 1)
        var c = try EntitlementOperations.pages(applicationID: .init(rawValue: 2),
            context: context) { _ in throw TransportFailure.closed }.makeAsyncIterator()
        var d = try SubscriptionOperations.pages(skuID: .init(rawValue: 4),
            context: context) { _ in throw TransportFailure.closed }.makeAsyncIterator()
        await #expect(throws: TransportFailure.closed) { try await c.next() }
        await #expect(throws: TransportFailure.closed) { try await d.next() }
        #expect(try await c.next() == nil); #expect(try await d.next() == nil)
        let expired = TransportContext(clock: clock, deadline: clock.now)
        var e = try EntitlementOperations.pages(applicationID: .init(rawValue: 2),
            context: expired) { _ in Issue.record("Expired execution"); return [] }.makeAsyncIterator()
        var f = try SubscriptionOperations.pages(skuID: .init(rawValue: 4),
            context: expired) { _ in Issue.record("Expired execution"); return [] }.makeAsyncIterator()
        await #expect(throws: TransportFailure.deadlineExceeded) { try await e.next() }
        await #expect(throws: TransportFailure.deadlineExceeded) { try await f.next() }
        #expect(try await e.next() == nil); #expect(try await f.next() == nil)
        #expect(clock.pendingSleepCount == 0)
    }

    /// Cancellation before execution or while a cooperative fetch is suspended releases its waiter and prevents further pulls.
    /// - Parameter inFlight: Selects cancellation before the first pull versus during executor suspension.
    /// - Throws: Unexpected barrier/setup errors fail the test; cancellation and cleanup are asserted.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [true, false]) func cancellation(inFlight: Bool) async throws {
        let entered = TestBarrier(), gate = TestBarrier(), clock = ManualClock()
        let entitlements = try EntitlementOperations.pages(applicationID: .init(rawValue: 2),
            context: TransportContext(clock: clock)) { _ in entered.open(); try await gate.wait(); return [] }
        let task = Task { () async throws -> Void in
            if !inFlight { withUnsafeCurrentTask { $0?.cancel() } }
            var iterator = entitlements.makeAsyncIterator()
            do { _ = try await iterator.next(); Issue.record("Missing cancellation") }
            catch { #expect(error is CancellationError) }
            #expect(try await iterator.next() == nil)
        }
        if inFlight { try await entered.wait(); task.cancel() }
        try await task.value
        #expect(gate.waitingCount == 0)
        let subscriptionEntered = TestBarrier(), subscriptionGate = TestBarrier()
        let subscriptions = try SubscriptionOperations.pages(skuID: .init(rawValue: 4),
            context: TransportContext(clock: clock)) { _ in subscriptionEntered.open(); try await subscriptionGate.wait(); return [] }
        let other = Task { () async throws -> Void in
            if !inFlight { withUnsafeCurrentTask { $0?.cancel() } }
            var iterator = subscriptions.makeAsyncIterator()
            do { _ = try await iterator.next(); Issue.record("Missing cancellation") }
            catch { #expect(error is CancellationError) }
            #expect(try await iterator.next() == nil)
        }
        if inFlight { try await subscriptionEntered.wait(); other.cancel() }
        try await other.value
        #expect(subscriptionGate.waitingCount == 0); #expect(clock.pendingSleepCount == 0)
    }

    /// Expiry during a suspended fetch cancels cooperative executors and releases both timer and fetch waiters.
    /// This exercises the overall deadline at the suspension point rather than only preflight validation.
    /// - Throws: Unexpected setup/barrier failures fail the test; exact deadline termination is asserted.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func suspendedDeadlines() async throws {
        let entered = TestBarrier(), timer = TestBarrier(), gate = TestBarrier()
        let clock = ManualClock(onSleepScheduled: { timer.open() })
        let context = TransportContext(clock: clock, deadline: clock.now.advanced(by: .seconds(1)))
        let pages = try EntitlementOperations.pages(applicationID: .init(rawValue: 2), context: context) { _ in
            entered.open(); try await gate.wait(); return []
        }
        let task = Task { () async throws -> Void in
            var iterator = pages.makeAsyncIterator()
            await #expect(throws: TransportFailure.deadlineExceeded) { try await iterator.next() }
            #expect(try await iterator.next() == nil)
        }
        try await entered.wait(); try await timer.wait(); try clock.advance(by: .seconds(1))
        try await task.value
        #expect(gate.waitingCount == 0); #expect(clock.pendingSleepCount == 0)

        let otherEntered = TestBarrier(), otherTimer = TestBarrier(), otherGate = TestBarrier()
        let otherClock = ManualClock(onSleepScheduled: { otherTimer.open() })
        let otherContext = TransportContext(clock: otherClock, deadline: otherClock.now.advanced(by: .seconds(1)))
        let subscriptions = try SubscriptionOperations.pages(skuID: .init(rawValue: 4), context: otherContext) { _ in
            otherEntered.open(); try await otherGate.wait(); return []
        }
        let other = Task { () async throws -> Void in
            var iterator = subscriptions.makeAsyncIterator()
            await #expect(throws: TransportFailure.deadlineExceeded) { try await iterator.next() }
            #expect(try await iterator.next() == nil)
        }
        try await otherEntered.wait(); try await otherTimer.wait(); try otherClock.advance(by: .seconds(1))
        try await other.value
        #expect(otherGate.waitingCount == 0); #expect(otherClock.pendingSleepCount == 0)
    }

    /// Creates partial perpetual entitlement fixtures, retaining exact IDs without depending on subscription state.
    /// - Parameters:
    ///   - ids: Ordered IDs, including deliberate duplicates and extreme values for malformed-page tests.
    ///   - application: Owning application, default two; overrides exercise scope failures.
    /// - Returns: Independent decoded resource values in the supplied order.
    /// - Throws: Unexpected JSON/model validation errors for the controlled fixture.
    private static func entitlements(_ ids: [UInt64], application: UInt64 = 2) throws -> [Entitlement] {
        try ids.map { id in
            try Entitlement(data: Data("{\"id\":\"\(id)\",\"application_id\":\"\(application)\",\"sku_id\":\"4\",\"type\":1,\"deleted\":false}".utf8))
        }
    }

    /// Creates lifecycle fixtures whose active status is deliberately independent of an empty entitlement list.
    /// - Parameters:
    ///   - ids: Exact ordered subscription IDs, including malformed traversal combinations.
    ///   - sku: Owning SKU, default four; overrides exercise wrong-SKU rejection.
    ///   - user: Subscriber, default three; overrides exercise filtered-user rejection.
    /// - Returns: Decoded subscriptions retaining required nullable renewal/cancellation fields.
    /// - Throws: Unexpected JSON/model errors for the controlled fixture.
    private static func subscriptions(_ ids: [UInt64], sku: UInt64 = 4, user: UInt64 = 3) throws -> [Subscription] {
        try ids.map { id in
            try Subscription(data: Data("{\"id\":\"\(id)\",\"user_id\":\"\(user)\",\"sku_ids\":[\"\(sku)\"],\"entitlement_ids\":[],\"renewal_sku_ids\":null,\"current_period_start\":\"2026-10-01T00:00:00Z\",\"current_period_end\":\"2026-11-01T00:00:00Z\",\"status\":0,\"canceled_at\":null}".utf8))
        }
    }
}

/// Actor-owned finite page script recording descriptor policy without real transport or shared iterator state.
private actor MonetizationPageScript<Item: Sendable> {
    private var pages: [[Item]]
    private(set) var calls = 0
    private(set) var queries: [[QueryItem]] = []
    private(set) var reuseCount = 0

    /// Stores synthetic pages without starting work.
    /// - Parameter pages: Exact pages to consume in order; empty pages explicitly terminate traversal.
    init(_ pages: [[Item]]) { self.pages = pages }

    /// Records one pull and consumes one predefined page, rejecting unexpected extra work.
    /// - Parameter endpoint: Production descriptor whose query and disabled reuse are inspected.
    /// - Returns: Next fixture in wire order without normalization.
    /// - Throws: Invalid-response after script exhaustion; no suspension, sleeps or network activity occurs.
    func next(_ endpoint: Endpoint<[Item]>) throws -> [Item] {
        calls += 1; queries.append(endpoint.query)
        if endpoint.readPolicy != nil { reuseCount += 1 }
        guard !pages.isEmpty else { throw DiscordError.transport(.invalidResponse) }
        return pages.removeFirst()
    }
}
