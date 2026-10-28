// File: Tests/DiscordHTTPTests/UserOperationsTests.swift
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

/// REST storage-shard selection and finite nonprefetching guild-list traversal with injected clocks/executors.
@Suite(.timeLimit(.minutes(1))) struct UserOperationsTests {
    /// REST shards use max_concurrency rather than Gateway shard count, and only selected query fields are transmitted.
    /// - Throws: Unexpected valid descriptor/query errors fail this test; invalid local ranges are asserted.
    @Test func guildQueryAndShardSelection() throws {
        let shard = try UserGuildListShard(index: 3, maxConcurrency: 4)
        #expect(shard.index == 3); #expect(shard.maxConcurrency == 4)
        #expect(try UserGuildListShard(index: 3, maxConcurrency: 4) == shard)
        #expect(Set([shard, try UserGuildListShard(index: 3, maxConcurrency: 4)]).count == 1)
        #expect(try UserGuildsQuery().queryItems().isEmpty)
        let query = try UserGuildsQuery(before: .init(rawValue: UInt64.max), after: .init(rawValue: 1), limit: 1,
            shard: shard, withCounts: false, largeBotSharding: true)
        #expect(query.before?.rawValue == UInt64.max); #expect(query.after?.rawValue == 1)
        #expect(query.limit == 1); #expect(query.shard == shard); #expect(query.withCounts == false); #expect(query.largeBotSharding)
        #expect(query.queryItems() == [.init(name: "before", value: "18446744073709551615"), .init(name: "after", value: "1"),
            .init(name: "limit", value: "1"), .init(name: "shard", value: "3"), .init(name: "with_counts", value: "false")])
        #expect(try UserEndpoints.guilds(query: query).query == query.queryItems())
        #expect(try UserGuildsQuery(before: .init(rawValue: 1), after: .init(rawValue: 2)).queryItems().count == 2)
        #expect(try UserGuildsQuery(limit: 200, shard: .init(index: 0, maxConcurrency: 1), withCounts: true).queryItems().count == 3)
        for (index, maximum) in [(0, 0), (0, -1), (-1, 4), (4, 4), (Int.max, 4), (Int.min, Int.max)] {
            #expect(throws: DiscordError.validation(.invalidValue)) { try UserGuildListShard(index: index, maxConcurrency: maximum) }
        }
        #expect(try UserGuildListShard(index: Int.max - 1, maxConcurrency: Int.max).index == Int.max - 1)
        #expect(throws: DiscordError.validation(.invalidValue)) { try UserGuildsQuery(largeBotSharding: true) }
        for limit in [Int.min, -1, 0, 201, Int.max] {
            #expect(throws: DiscordError.validation(.invalidValue)) { try UserGuildsQuery(limit: limit) }
        }
    }

    /// Ascending traversal preserves wire order and exact extreme IDs, advances by maximum and follows short pages to empty.
    /// No executor call occurs before next(), and creating independent iterators never shares cursor state.
    /// - Throws: Unexpected fixture/descriptor/iteration errors fail this test.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func ascendingContinuationAndIndependentIterators() async throws {
        let script = UserGuildPageScript([.value(try Self.guilds([12, 11])), .value(try Self.guilds([UInt64.max])), .value([])])
        let pages = try UserOperations.guildPages(cursor: .init(rawValue: 10), limit: 2,
            shard: .init(index: 3, maxConcurrency: 4), largeBotSharding: true, withCounts: true,
            context: TransportContext(clock: ManualClock())) { try await script.next($0) }
        #expect(await script.calls == 0)
        var iterator = pages.makeAsyncIterator()
        #expect(try await iterator.next()?.map(\.id.rawValue) == [12, 11]); #expect(await script.calls == 1)
        #expect(try await iterator.next()?.map(\.id.rawValue) == [UInt64.max])
        #expect(try await iterator.next()?.isEmpty == true); #expect(try await iterator.next() == nil)
        #expect(await script.calls == 3); #expect(await script.reuseCount == 0)
        let queries = await script.queries
        #expect(queries.compactMap { $0.first { $0.name == "after" }?.value } == ["10", "12", "18446744073709551615"])
        #expect(queries.allSatisfy { $0.contains(.init(name: "shard", value: "3")) && $0.contains(.init(name: "with_counts", value: "true")) })
        var independent = pages.makeAsyncIterator()
        await #expect(throws: DiscordError.transport(.invalidResponse)) { try await independent.next() }
        #expect(try await independent.next() == nil)
        #expect(await script.queries.last?.first(where: { $0.name == "after" })?.value == "10")
    }

    /// Descending traversal chooses minimum without imposing an undocumented response order; preview null explicitly terminates.
    /// Initial nil cursors and independent shard selection do not fetch Gateway metadata or enumerate other shards implicitly.
    /// - Throws: Unexpected valid fixture/iteration errors fail the test.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func descendingNullAndSelectedShards() async throws {
        let script = UserGuildPageScript([.value(try Self.guilds([10, 11])), .value(try Self.guilds([1])), .null])
        var iterator = try UserOperations.guildPages(direction: .descending, cursor: .init(rawValue: UInt64.max), limit: 2,
            context: TransportContext(clock: ManualClock())) { try await script.next($0) }.makeAsyncIterator()
        #expect(try await iterator.next()?.map(\.id.rawValue) == [10, 11])
        #expect(try await iterator.next()?.map(\.id.rawValue) == [1])
        #expect(try await iterator.next()?.isEmpty == true); #expect(try await iterator.next() == nil)
        #expect(await script.queries.compactMap { $0.first { $0.name == "before" }?.value } == ["18446744073709551615", "10", "1"])
        for index in 0..<3 {
            let partition = UserGuildPageScript([.value(try Self.guilds([2, 1])), .null])
            let pages = try UserOperations.guildPages(shard: .init(index: index, maxConcurrency: 3), largeBotSharding: true,
                context: TransportContext(clock: ManualClock())) { try await partition.next($0) }
            #expect(await partition.calls == 0)
            var iterator = pages.makeAsyncIterator()
            #expect(try await iterator.next()?.count == 2)
            #expect(try await iterator.next()?.isEmpty == true); #expect(try await iterator.next() == nil)
            #expect(await partition.calls == 2)
            #expect(await partition.queries.first?.contains(.init(name: "shard", value: String(index))) == true)
            #expect(await partition.queries.first?.contains(where: { $0.name == "after" || $0.name == "before" }) == false)
            #expect(await partition.queries.last?.first(where: { $0.name == "after" })?.value == "2")
        }
    }

    /// Per-page, total-page and explicit-shard requirements reject before any fetch starts, including integer extremes.
    /// - Throws: Unexpected setup errors fail the test; sanitized configuration errors are asserted.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func invalidPaginationConfiguration() throws {
        let context = TransportContext(clock: ManualClock())
        for limit in [Int.min, -1, 0, 201, Int.max] {
            #expect(throws: DiscordError.validation(.invalidValue)) {
                try UserOperations.guildPages(limit: limit, context: context) { _ in Issue.record("Invalid fetch"); return .null }
            }
        }
        for count in [Int.min, -1, 0, 10_001, Int.max] {
            #expect(throws: DiscordError.validation(.invalidValue)) {
                try UserOperations.guildPages(maximumPages: count, context: context) { _ in Issue.record("Invalid fetch"); return .null }
            }
        }
        #expect(throws: DiscordError.validation(.invalidValue)) {
            try UserOperations.guildPages(largeBotSharding: true, context: context) { _ in Issue.record("Missing shard fetch"); return .null }
        }
    }

    /// Oversized, repeated and out-of-bound IDs fail permanently without an extra request or a changed cursor.
    /// - Parameter direction: Both before and after traversal under the same finite page ownership rules.
    /// - Throws: Unexpected fixture construction errors fail the test; every invalid page is asserted.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [UserGuildTraversal.ascending, .descending])
    func malformedPages(direction: UserGuildTraversal) async throws {
        let pages = direction == .ascending ? [[11, 12, 13], [11, 11], [10], [9]] : [[9, 8, 7], [9, 9], [10], [11]]
        for ids in pages {
            let script = UserGuildPageScript([.value(try Self.guilds(ids.map(UInt64.init)))])
            var iterator = try UserOperations.guildPages(direction: direction, cursor: .init(rawValue: 10), limit: 2,
                context: TransportContext(clock: ManualClock())) { try await script.next($0) }.makeAsyncIterator()
            await #expect(throws: DiscordError.transport(.invalidResponse)) { try await iterator.next() }
            #expect(try await iterator.next() == nil); #expect(await script.calls == 1)
        }
    }

    /// Budget, executor errors, precancellation and inclusive deadline fail before subsequent work and finish the iterator.
    /// - Throws: Unexpected setup/fixture errors fail this test; failure categories and request counts are asserted.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func pageFailureTermination() async throws {
        let script = UserGuildPageScript([.value(try Self.guilds([1])), .value(try Self.guilds([2]))])
        var bounded = try UserOperations.guildPages(maximumPages: 1, context: TransportContext(clock: ManualClock())) { try await script.next($0) }.makeAsyncIterator()
        #expect(try await bounded.next()?.count == 1)
        await #expect(throws: DiscordError.validation(.limitExceeded)) { try await bounded.next() }
        #expect(try await bounded.next() == nil); #expect(await script.calls == 1)
        var failed = try UserOperations.guildPages(context: TransportContext(clock: ManualClock())) { _ in throw TransportFailure.closed }.makeAsyncIterator()
        await #expect(throws: TransportFailure.closed) { try await failed.next() }
        #expect(try await failed.next() == nil)
        let clock = ManualClock()
        var expired = try UserOperations.guildPages(context: TransportContext(clock: clock, deadline: clock.now)) { _ in Issue.record("Expired fetch"); return .null }.makeAsyncIterator()
        await #expect(throws: TransportFailure.deadlineExceeded) { try await expired.next() }
        #expect(try await expired.next() == nil)
        let task = Task { () throws -> [UserGuild]? in
            withUnsafeCurrentTask { $0?.cancel() }
            var cancelled = try UserOperations.guildPages(context: TransportContext(clock: ManualClock())) { _ in Issue.record("Cancelled fetch"); return .null }.makeAsyncIterator()
            return try await cancelled.next()
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    /// Cancellation/deadline during a suspended page releases both operation/timer children and ends iteration permanently.
    /// - Parameter expires: True advances the injected clock exactly to deadline; false cancels the awaiting task.
    /// - Throws: Unexpected setup/barrier failures fail this test; expected termination and cleanup are asserted.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [false, true]) func suspendedPageCleanup(expires: Bool) async throws {
        let entered = TestBarrier(), timerReady = TestBarrier(), blocked = TestBarrier()
        let clock = ManualClock(onSleepScheduled: { timerReady.open() })
        let context = TransportContext(clock: clock, deadline: clock.now.advanced(by: .seconds(1)))
        let pages = try UserOperations.guildPages(context: context) { _ in
            entered.open(); try await blocked.wait(); return .null
        }
        let task = Task {
            var iterator = pages.makeAsyncIterator()
            do { _ = try await iterator.next(); Issue.record("Expected termination") }
            catch is CancellationError { #expect(!expires) }
            catch let error as TransportFailure { #expect(expires); #expect(error == .deadlineExceeded) }
            #expect(try await iterator.next() == nil)
        }
        try await entered.wait(); try await timerReady.wait()
        if expires { try clock.advance(by: .seconds(1)) } else { task.cancel() }
        try await task.value
        #expect(blocked.waitingCount == 0); #expect(clock.pendingSleepCount == 0)
    }

    /// Builds one independent minimal guild-list fixture for each exact ID, preserving caller order.
    /// - Parameter ids: Exact unsigned guild IDs, including zero and UInt64.max, deliberately allowing duplicates for rejection tests.
    /// - Returns: Typed user-guild snapshots with nullable icon and ordinary required permission/features fields.
    /// - Throws: Unexpected fixture JSON/schema failures; no I/O or resource ownership is involved.
    static func guilds(_ ids: [UInt64]) throws -> [UserGuild] {
        try ids.map { id in
            try UserGuild(data: Data("{\"id\":\"\(id)\",\"name\":\"guild\",\"icon\":null,\"owner\":false,\"permissions\":\"0\",\"features\":[]}".utf8))
        }
    }
}

/// Sequential finite page script retaining only request evidence needed by deterministic continuation tests.
private actor UserGuildPageScript {
    private var pages: [Nullable<[UserGuild]>]
    private(set) var calls = 0
    private(set) var queries: [[QueryItem]] = []
    private(set) var reuseCount = 0

    /// Owns a finite set of predefined nullable pages without beginning a fetch or sharing iterator cursor state.
    /// - Parameter pages: Responses consumed in order, including empty/null terminal pages or deliberately malformed pages.
    init(_ pages: [Nullable<[UserGuild]>]) { self.pages = pages }

    /// Records one pull and returns its next fixture, failing safely when the finite script has been exhausted.
    /// - Parameter endpoint: Actual production descriptor, inspected for selected cursors/shard/query and disabled reuse.
    /// - Returns: The next exact nullable page; no automatic response normalization occurs in the script.
    /// - Throws: Invalid-response when exhausted. State advances once per call and performs no I/O or suspension.
    func next(_ endpoint: Endpoint<Nullable<[UserGuild]>>) throws -> Nullable<[UserGuild]> {
        calls += 1; queries.append(endpoint.query)
        if endpoint.readPolicy != nil { reuseCount += 1 }
        guard !pages.isEmpty else { throw DiscordError.transport(.invalidResponse) }
        return pages.removeFirst()
    }
}
