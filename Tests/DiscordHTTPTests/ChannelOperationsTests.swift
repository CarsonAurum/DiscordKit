// File: Tests/DiscordHTTPTests/ChannelOperationsTests.swift
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

/// Exercises channel continuations with finite scripts, exact cursors and injected virtual time.
@Suite struct ChannelOperationsTests {
    let channel = ChannelID(rawValue: 1)

    /// Archive traversal is lazy, preserves member correlation, follows short pages and stops only on hasMore false.
    /// - Parameter visibility: Both timestamp-based archive routes must use identical continuation rules.
    /// - Throws: Unexpected fixture/pagination construction, executor or required-value assertion errors fail the test; expected workflow failures are asserted locally.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [ArchivedThreadVisibility.public, .private])
    func archivesPreserveEnvelope(visibility: ArchivedThreadVisibility) async throws {
        let exact = "2026-10-15T12:00:00.123456789+00:00"
        let script = ChannelPageScript([try archive([99], timestamp: exact, hasMore: true), try archive([], hasMore: false)])
        let pages = try ChannelOperations.archivedThreadPages(channelID: channel, visibility: visibility,
            context: TransportContext(clock: ManualClock())) { try await script.next($0) }
        #expect(await script.calls == 0)
        var iterator = pages.makeAsyncIterator()
        let first = try #require(try await iterator.next()?.first)
        #expect(first.threads.map(\.id.rawValue) == [99])
        #expect(first.members.count == 1)
        #expect(await script.calls == 1)
        #expect(try await iterator.next()?.first?.threads.isEmpty == true)
        #expect(try await iterator.next() == nil)
        #expect(await script.cursors == [nil, exact])
        #expect(await script.reuseCount == 0)
        #expect(await script.routes.allSatisfy { $0.hasSuffix(visibility == .public ? "/public" : "/private") })
    }

    /// Joined archives use decreasing exact IDs even when archive timestamps increase.
    /// - Throws: Unexpected fixture/pagination construction, executor or required-value assertion errors fail the test; expected workflow failures are asserted locally.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func joinedArchivesUseIDs() async throws {
        let script = ChannelPageScript([try archive([UInt64.max - 1], hasMore: true),
                                       try archive([9_007_199_254_740_993], hasMore: false)])
        var iterator = try ChannelOperations.joinedPrivateArchivedThreadPages(channelID: channel,
            before: ChannelID(rawValue: UInt64.max), context: TransportContext(clock: ManualClock())) {
                try await script.next($0)
            }.makeAsyncIterator()
        #expect(try await iterator.next()?.first?.threads.first?.id.rawValue == UInt64.max - 1)
        #expect(try await iterator.next()?.first?.threads.first?.id.rawValue == 9_007_199_254_740_993)
        #expect(try await iterator.next() == nil)
        #expect(await script.cursors == ["18446744073709551615", "18446744073709551614"])
    }

    /// The API v10 member workflow always enables pagination and continues after short responses.
    /// - Throws: Unexpected fixture/pagination construction, executor or required-value assertion errors fail the test; expected workflow failures are asserted locally.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func memberPages() async throws {
        let script = ChannelPageScript([try members([11]), try members([12]), []])
        let pages = try ChannelOperations.threadMemberPages(channelID: channel, after: UserID(rawValue: 10),
            limit: 2, context: TransportContext(clock: ManualClock())) { try await script.next($0) }
        #expect(await script.calls == 0)
        var first = pages.makeAsyncIterator()
        #expect(try await first.next()?.count == 1)
        #expect(try await first.next()?.count == 1)
        #expect(try await first.next()?.isEmpty == true)
        #expect(try await first.next() == nil)
        #expect(await script.cursors == ["10", "11", "12"])
        #expect(await script.memberOptions == ["true", "true", "true"])
        #expect(await script.reuseCount == 0)
    }

    /// Invalid local budgets and endpoint limits fail synchronously without invoking an executor.
    /// - Parameter budget: Invalid count including lower/upper extreme integers.
    /// - Throws: Unexpected fixture/pagination construction, executor or required-value assertion errors fail the test; expected workflow failures are asserted locally.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [Int.min, -1, 0, 10_001, Int.max])
    func invalidBudgets(budget: Int) throws {
        let context = TransportContext(clock: ManualClock())
        #expect(throws: DiscordError.validation(.invalidValue)) {
            try ChannelOperations.archivedThreadPages(channelID: channel, visibility: .public, maximumPages: budget, context: context) { _ in throw CancellationError() }
        }
        #expect(throws: DiscordError.validation(.invalidValue)) {
            try ChannelOperations.joinedPrivateArchivedThreadPages(channelID: channel, maximumPages: budget, context: context) { _ in throw CancellationError() }
        }
        #expect(throws: DiscordError.validation(.invalidValue)) {
            try ChannelOperations.threadMemberPages(channelID: channel, maximumPages: budget, context: context) { _ in [] }
        }
        for limit in [0, 101] {
            #expect(throws: DiscordError.self) { try ChannelOperations.archivedThreadPages(channelID: channel, visibility: .private, limit: limit, context: context) { _ in throw CancellationError() } }
            #expect(throws: DiscordError.self) { try ChannelOperations.joinedPrivateArchivedThreadPages(channelID: channel, limit: limit, context: context) { _ in throw CancellationError() } }
            #expect(throws: DiscordError.self) { try ChannelOperations.threadMemberPages(channelID: channel, limit: limit, context: context) { _ in [] } }
        }
    }

    /// Empty-continuing, oversized, missing-metadata and nonprogressing timestamps cannot produce endless traversal.
    /// - Throws: Unexpected fixture/pagination construction, executor or required-value assertion errors fail the test; expected workflow failures are asserted locally.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func malformedArchives() async throws {
        let initial = try DiscordTimestamp(rawValue: "2026-10-16T00:00:00Z")
        let missing = try ArchivedThreads(data: Data("{\"threads\":[{\"id\":\"1\",\"type\":11}],\"members\":[],\"has_more\":true}".utf8))
        for page in [try archive([], hasMore: true), try archive([1, 2], hasMore: false), missing,
                     try archive([1], timestamp: initial.rawValue, hasMore: true),
                     try archive([1], timestamp: "2026-10-16T01:00:00+01:00", hasMore: true),
                     try archive([1], timestamp: "2026-10-16T00:00:00.000000001Z", hasMore: true)] {
            let script = ChannelPageScript([page])
            var iterator = try ChannelOperations.archivedThreadPages(channelID: channel, visibility: .public,
                before: initial, limit: 1, context: TransportContext(clock: ManualClock())) { try await script.next($0) }.makeAsyncIterator()
            await #expect(throws: DiscordError.transport(.invalidResponse)) { try await iterator.next() }
            #expect(try await iterator.next() == nil)
            #expect(await script.calls == 1)
        }
        for page in [try archive([], hasMore: true), try archive([10], hasMore: true), try archive([11], hasMore: true),
                     try archive([8, 7], hasMore: false)] {
            let script = ChannelPageScript([page])
            var iterator = try ChannelOperations.joinedPrivateArchivedThreadPages(channelID: channel,
                before: .init(rawValue: 10), limit: 1, context: TransportContext(clock: ManualClock())) { try await script.next($0) }.makeAsyncIterator()
            await #expect(throws: DiscordError.transport(.invalidResponse)) { try await iterator.next() }
            #expect(try await iterator.next() == nil)
        }
    }

    /// Validates every timestamp and ID, including nonfinal rows and pages whose has_more is false.
    /// Equal instants are legal within a page, but every item must precede the exclusive requested cursor.
    /// - Parameter hasMore: Both terminal and continuing pages enforce the same response invariants.
    /// - Throws: Unexpected fixture/pagination construction, executor or required-value assertion errors fail the test; expected workflow failures are asserted locally.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [false, true])
    func archivesValidateAllRows(hasMore: Bool) async throws {
        let cursor = try DiscordTimestamp(rawValue: "2026-10-16T00:00:00Z")
        let older = "2026-10-15T00:00:00Z"
        let later = "2026-10-15T12:00:00Z"
        let rows: [[(UInt64, String?)]] = [
            [(9, cursor.rawValue), (8, older)],
            [(9, "2026-10-17T00:00:00Z"), (8, older)],
            [(9, older), (8, later)],
            [(9, older), (9, older)],
            [(9, nil), (8, older)],
            [(9, older), (8, nil)],
            [(9, older), (8, "2026-10-16T01:00:00+01:00")],
        ]
        for visibility in [ArchivedThreadVisibility.public, .private] {
            for values in rows {
                let script = ChannelPageScript([try archiveRows(values, hasMore: hasMore)])
                var iterator = try ChannelOperations.archivedThreadPages(channelID: channel, visibility: visibility,
                    before: cursor, limit: 3, context: TransportContext(clock: ManualClock())) {
                        try await script.next($0)
                    }.makeAsyncIterator()
                await #expect(throws: DiscordError.transport(.invalidResponse)) { try await iterator.next() }
                #expect(try await iterator.next() == nil)
                #expect(await script.calls == 1)
            }
        }
    }

    /// Descending timestamp ordering permits ties and preserves the final exact offset spelling for continuation.
    /// The next page advances by one nanosecond, exercising exact instant comparison without Date rounding.
    /// - Throws: Unexpected fixture/pagination construction, executor or required-value assertion errors fail the test; expected workflow failures are asserted locally.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func archiveTimestampTiesPreserveExactCursor() async throws {
        let exact = "2026-10-15T13:00:00.123456789+01:00"
        let first = try archiveRows([(9, "2026-10-15T12:00:00.123456789Z"), (8, exact)], hasMore: true)
        let last = try archiveRows([(7, "2026-10-15T12:00:00.123456788Z")], hasMore: false)
        let script = ChannelPageScript([first, last])
        var iterator = try ChannelOperations.archivedThreadPages(channelID: channel, visibility: .public,
            limit: 3, context: TransportContext(clock: ManualClock())) {
                try await script.next($0)
            }.makeAsyncIterator()
        #expect(try await iterator.next()?.first?.threads.map(\.id.rawValue) == [9, 8])
        #expect(try await iterator.next()?.first?.threads.map(\.id.rawValue) == [7])
        #expect(try await iterator.next() == nil)
        #expect(await script.cursors == [nil, exact])
    }

    /// Joined-private archives enforce strict descending IDs on every row, including terminal pages.
    /// - Parameter hasMore: Whether a next cursor would be derived after successful validation.
    /// - Throws: Unexpected fixture/pagination construction, executor or required-value assertion errors fail the test; expected workflow failures are asserted locally.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [false, true])
    func joinedArchivesValidateAllRows(hasMore: Bool) async throws {
        let cases: [[UInt64]] = [[10, 9], [11, 9], [9, 8, 9], [9, 9], [8, 9, 7], [9, 10]]
        for ids in cases {
            let script = ChannelPageScript([try archive(ids, hasMore: hasMore)])
            var iterator = try ChannelOperations.joinedPrivateArchivedThreadPages(channelID: channel,
                before: ChannelID(rawValue: 10), limit: 3, context: TransportContext(clock: ManualClock())) {
                    try await script.next($0)
                }.makeAsyncIterator()
            await #expect(throws: DiscordError.transport(.invalidResponse)) { try await iterator.next() }
            #expect(try await iterator.next() == nil)
            #expect(await script.calls == 1)
        }
        let duplicate = ChannelPageScript([try archive([9, 9], hasMore: hasMore)])
        var initial = try ChannelOperations.joinedPrivateArchivedThreadPages(channelID: channel,
            limit: 3, context: TransportContext(clock: ManualClock())) {
                try await duplicate.next($0)
            }.makeAsyncIterator()
        await #expect(throws: DiscordError.transport(.invalidResponse)) { try await initial.next() }
        #expect(await duplicate.calls == 1)
    }

    /// A subsequent page cannot repeat the exact timestamp cursor even if it incorrectly advertises completion.
    /// - Parameter hasMore: Repeated-cursor responses are rejected whether continuing or terminal.
    /// - Throws: Unexpected fixture/pagination construction, executor or required-value assertion errors fail the test; expected workflow failures are asserted locally.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [false, true])
    func repeatedArchiveContinuationFails(hasMore: Bool) async throws {
        let timestamp = "2026-10-15T00:00:00.000000001Z"
        let script = ChannelPageScript([try archive([9], timestamp: timestamp, hasMore: true),
                                       try archive([8], timestamp: timestamp, hasMore: hasMore)])
        var iterator = try ChannelOperations.archivedThreadPages(channelID: channel, visibility: .public,
            context: TransportContext(clock: ManualClock())) {
                try await script.next($0)
            }.makeAsyncIterator()
        #expect(try await iterator.next()?.first?.threads.first?.id.rawValue == 9)
        await #expect(throws: DiscordError.transport(.invalidResponse)) { try await iterator.next() }
        #expect(try await iterator.next() == nil)
        #expect(await script.calls == 2)
    }

    /// Membership continuation rejects IDs missing from legacy-shaped responses, duplicates, reverse order and oversized pages.
    /// - Throws: Unexpected fixture/pagination construction, executor or required-value assertion errors fail the test; expected workflow failures are asserted locally.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func malformedMembers() async throws {
        let noID = try ThreadMember(data: Data("{\"join_timestamp\":\"2026-10-16T00:00:00Z\",\"flags\":0}".utf8))
        for page in [[noID], try members([10]), try members([9]), try members([11, 11]), try members([12, 11]), try members([11, 12, 13])] {
            let script = ChannelPageScript([page])
            var iterator = try ChannelOperations.threadMemberPages(channelID: channel, after: .init(rawValue: 10),
                limit: 2, context: TransportContext(clock: ManualClock())) { try await script.next($0) }.makeAsyncIterator()
            await #expect(throws: DiscordError.transport(.invalidResponse)) { try await iterator.next() }
            #expect(try await iterator.next() == nil)
        }
    }

    /// Cancellation, executor failures, page budgets and already-expired deadlines finish the iterator without retry.
    /// - Throws: Unexpected fixture/pagination construction, executor or required-value assertion errors fail the test; expected workflow failures are asserted locally.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func lifecycleAndIndependentIterators() async throws {
        let page = try archive([1], hasMore: false)
        let script = ChannelPageScript([page, page])
        let pages = try ChannelOperations.archivedThreadPages(channelID: channel, visibility: .public,
            context: TransportContext(clock: ManualClock())) { try await script.next($0) }
        var a = pages.makeAsyncIterator(), b = pages.makeAsyncIterator()
        #expect(try await a.next()?.count == 1)
        #expect(try await b.next()?.count == 1)
        #expect(await script.cursors == [nil, nil])
        var failed = try ChannelOperations.threadMemberPages(channelID: channel,
            context: TransportContext(clock: ManualClock())) { _ in throw TestSupportFailure.scripted("expected") }.makeAsyncIterator()
        await #expect(throws: TestSupportFailure.self) { try await failed.next() }
        #expect(try await failed.next() == nil)
        let capped = ChannelPageScript([try members([1]), try members([2])])
        var cap = try ChannelOperations.threadMemberPages(channelID: channel, maximumPages: 1,
            context: TransportContext(clock: ManualClock())) { try await capped.next($0) }.makeAsyncIterator()
        #expect(try await cap.next()?.count == 1)
        await #expect(throws: DiscordError.validation(.limitExceeded)) { try await cap.next() }
        #expect(await capped.calls == 1)
        let clock = ManualClock()
        let expired = ChannelPageScript([page])
        var late = try ChannelOperations.joinedPrivateArchivedThreadPages(channelID: channel,
            context: TransportContext(clock: clock, deadline: clock.now)) { try await expired.next($0) }.makeAsyncIterator()
        await #expect(throws: (any Error).self) { try await late.next() }
        #expect(await expired.calls == 0)
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            var iterator = pages.makeAsyncIterator()
            return try await iterator.next()
        }
        await #expect(throws: CancellationError.self) { try await cancelled.value }
        #expect(await script.calls == 2)
        #expect(clock.pendingSleepCount == 0)
    }

    /// An active pull cooperatively cancels its sole executor and deadline sleeper without leaving a barrier waiter.
    /// - Parameters:
    ///   - kind: Timestamp archive, joined-ID archive or member traversal; all own the same structured lifecycle.
    ///   - deadline: True advances virtual time to the inclusive deadline; false cancels the task directly.
    /// - Throws: Unexpected fixture/pagination construction, executor or required-value assertion errors fail the test; expected workflow failures are asserted locally.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: 0..<3, [false, true])
    func activeCancellationAndDeadline(kind: Int, deadline: Bool) async throws {
        let entered = TestBarrier(), release = TestBarrier()
        let clock = ManualClock()
        let context = TransportContext(clock: clock, deadline: deadline ? clock.now.advanced(by: .seconds(1)) : nil)
        let task = Task {
            switch kind {
            case 0:
                var iterator = try ChannelOperations.archivedThreadPages(channelID: channel, visibility: .private, context: context) { _ in
                    entered.open(); try await release.wait(); throw TestSupportFailure.scripted("unexpected release")
                }.makeAsyncIterator()
                _ = try await iterator.next()
            case 1:
                var iterator = try ChannelOperations.joinedPrivateArchivedThreadPages(channelID: channel, context: context) { _ in
                    entered.open(); try await release.wait(); throw TestSupportFailure.scripted("unexpected release")
                }.makeAsyncIterator()
                _ = try await iterator.next()
            default:
                var iterator = try ChannelOperations.threadMemberPages(channelID: channel, context: context) { _ in
                    entered.open(); try await release.wait(); return []
                }.makeAsyncIterator()
                _ = try await iterator.next()
            }
        }
        try await entered.wait()
        if deadline { try clock.advance(by: .seconds(1)) } else { task.cancel() }
        if deadline { await #expect(throws: TransportFailure.deadlineExceeded) { try await task.value } }
        else { await #expect(throws: CancellationError.self) { try await task.value } }
        #expect(release.waitingCount == 0 && clock.pendingSleepCount == 0)
    }

    /// Timestamp comparison preserves nanoseconds and offset equivalence across strict cursor boundaries.
    /// - Throws: Unexpected fixture/pagination construction, executor or required-value assertion errors fail the test; expected workflow failures are asserted locally.
    @Test func exactTimestampOrdering() throws {
        let cursor = try DiscordTimestamp(rawValue: "2026-10-16T00:00:00.000000002Z")
        #expect(try channelTimestampPrecedes(DiscordTimestamp(rawValue: "2026-10-15T23:59:59Z"), cursor))
        #expect(try channelTimestampPrecedes(DiscordTimestamp(rawValue: "2026-10-16T00:00:00.000000001Z"), cursor))
        #expect(try !channelTimestampPrecedes(DiscordTimestamp(rawValue: "2026-10-16T01:00:00.000000002+01:00"), cursor))
        #expect(try !channelTimestampPrecedes(DiscordTimestamp(rawValue: "2026-10-17T00:00:00Z"), cursor))
    }

    /// Snapshot reconciliation sends zero requests for no-op settings, rejects obfuscated/type-mismatched
    /// snapshots and produces one ordinary descriptor for changed or explicitly cleared values.
    /// - Throws: Unexpected fixture/pagination construction, executor or required-value assertion errors fail the test; expected workflow failures are asserted locally.
    @Test func noOpReconciliation() throws {
        let current = try Channel(data: Data("{\"id\":\"1\",\"type\":0,\"name\":\"same\",\"topic\":null}".utf8))
        #expect(try ChannelOperations.modifyIfChanged(current: current, request: ChannelModify(channelType: .guildText)) == nil)
        #expect(try ChannelOperations.modifyIfChanged(current: current, request: ChannelModify(channelType: .guildText, name: .value("same"), topic: .null)) == nil)
        let changed = try #require(try ChannelOperations.modifyIfChanged(current: current,
            request: ChannelModify(channelType: .guildText, name: .value("changed"))))
        #expect(changed.method == "PATCH" && changed.path == ["channels", "1"])
        #expect(try JSONValue.parse(#require(changed.body?.storedBodyBytes)) == .object(["name": .string("changed")]))
        let obfuscated = try Channel(data: Data("{\"id\":\"1\",\"type\":0,\"flags\":131072}".utf8))
        #expect(throws: DiscordError.validation(.invalidValue)) { try ChannelOperations.modifyIfChanged(current: obfuscated, request: ChannelModify(channelType: .guildText)) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try ChannelOperations.modifyIfChanged(current: current, request: ChannelModify(channelType: .guildVoice)) }
        #expect(try ChannelOperations.modifyIfChanged(current: current, request: ChannelModify(channelType: .guildText, parentID: .null)) != nil)
    }

    /// Constructs a complete exact archive fixture with one correlated membership per returned thread.
    /// - Parameters:
    ///   - ids: Ordered thread snowflakes, including empty arrays for terminal/invalid-continuing pages.
    ///   - timestamp: Exact metadata cursor timestamp; defaults to one stable instant.
    ///   - hasMore: Explicit upstream continuation indicator, independent of page length.
    /// - Returns: A typed archive envelope suitable for a finite script.
    /// - Throws: Parser/schema errors indicate invalid fixture setup.
    private func archive(_ ids: [UInt64], timestamp: String = "2026-10-15T00:00:00Z", hasMore: Bool) throws -> ArchivedThreads {
        let threads = ids.map { "{\"id\":\"\($0)\",\"type\":11,\"thread_metadata\":{\"archived\":true,\"auto_archive_duration\":60,\"archive_timestamp\":\"\(timestamp)\",\"locked\":false}}" }.joined(separator: ",")
        let members = ids.map { "{\"id\":\"\($0)\",\"user_id\":\"10\",\"join_timestamp\":\"2026-10-16T00:00:00Z\",\"flags\":0}" }.joined(separator: ",")
        return try ArchivedThreads(data: Data("{\"threads\":[\(threads)],\"members\":[\(members)],\"has_more\":\(hasMore)}".utf8))
    }

    /// Constructs archive rows with distinct or omitted metadata for ordering and all-item validation tests.
    /// - Parameters:
    ///   - rows: Thread IDs and exact optional timestamps; nil omits metadata to exercise malformed responses.
    ///   - hasMore: Explicit response continuation signal, independent of row count.
    /// - Returns: A complete archive envelope with no joined-member records.
    /// - Throws: Parsing errors when a trusted fixture fragment is invalid.
    private func archiveRows(_ rows: [(UInt64, String?)], hasMore: Bool) throws -> ArchivedThreads {
        let threads = rows.map { id, timestamp in
            let metadata = timestamp.map { ",\"thread_metadata\":{\"archived\":true,\"auto_archive_duration\":60,\"archive_timestamp\":\"\($0)\",\"locked\":false}" } ?? ""
            return "{\"id\":\"\(id)\",\"type\":11\(metadata)}"
        }.joined(separator: ",")
        return try ArchivedThreads(data: Data("{\"threads\":[\(threads)],\"members\":[],\"has_more\":\(hasMore)}".utf8))
    }

    /// Constructs ordered thread membership without related guild-member hydration.
    /// - Parameter ids: Exact user snowflakes, including duplicates or reverse order for negative tests.
    /// - Returns: Parsed members in supplied order.
    /// - Throws: Parser/schema errors indicate invalid fixture setup.
    private func members(_ ids: [UInt64]) throws -> [ThreadMember] {
        try ids.map { try ThreadMember(data: Data("{\"id\":\"1\",\"user_id\":\"\($0)\",\"join_timestamp\":\"2026-10-16T00:00:00Z\",\"flags\":0}".utf8)) }
    }
}

/// Single-owner finite workflow script recording observable request counts, cursor units and reuse metadata.
private actor ChannelPageScript<Response: Sendable> {
    var responses: [Response]
    var calls = 0
    var cursors: [String?] = []
    var routes: [String] = []
    var memberOptions: [String?] = []
    var reuseCount = 0

    /// Stores a finite ordered response sequence without starting work.
    /// - Parameter responses: Complete return values; consuming beyond the array fails explicitly.
    init(_ responses: [Response]) { self.responses = responses }

    /// Records one descriptor and returns exactly one response with no timing-dependent waits.
    /// - Parameter endpoint: Operation under test, whose before/after cursor and pagination flags are recorded.
    /// - Returns: The next typed scripted value.
    /// - Throws: Script exhaustion; malformed production descriptors are asserted in caller tests.
    func next(_ endpoint: Endpoint<Response>) throws -> Response {
        calls += 1
        cursors.append(endpoint.query.first { $0.name == "before" || $0.name == "after" }?.value)
        memberOptions.append(endpoint.query.first { $0.name == "with_member" }?.value)
        routes.append(endpoint.route)
        if endpoint.readPolicy != nil { reuseCount += 1 }
        guard !responses.isEmpty else { throw TestSupportFailure.scripted("script exhausted") }
        return responses.removeFirst()
    }
}
