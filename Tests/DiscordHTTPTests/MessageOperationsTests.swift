import DiscordCore
import DiscordModels
import DiscordTestSupport
import DiscordTransport
import Foundation
import Testing
@testable import DiscordHTTP

/// Deterministic workflow coverage using exact fixtures, bounded scripts and virtual time.
@Suite struct MessageOperationsTests {
    let channel = ChannelID(rawValue: 1)
    let message = MessageID(rawValue: 2)
    let guild = GuildID(rawValue: 3)
    let now: UInt64 = 1_792_108_800_000

    /// History is lazy, preserves its exclusive cursor, continues short pages and includes terminal emptiness.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func historyLazyShortPages() async throws {
        let first = try messages([99, 98])
        let second = try messages([97])
        let script = OperationScript(responses: [first, second, []])
        let pages = try MessageOperations.historyPages(channelID: channel, before: MessageID(rawValue: 100),
            limit: 3, context: TransportContext(clock: ManualClock())) { try await script.next($0) }
        #expect(await script.calls == 0)
        var iterator = pages.makeAsyncIterator()
        #expect(try await iterator.next()?.map(\.id.rawValue) == [99, 98])
        #expect(await script.calls == 1)
        #expect(try await iterator.next()?.map(\.id.rawValue) == [97])
        #expect(try await iterator.next()?.isEmpty == true)
        #expect(try await iterator.next() == nil)
        #expect(await script.cursors("before") == ["100", "98", "97"])
        #expect(await script.readReuseCount == 0)
    }

    /// Separate iterators own independent cursor state and do not retain or share completed page results.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func historyIndependentIterators() async throws {
        let item = try messages([99])
        let script = OperationScript(responses: [item, item])
        let pages = try MessageOperations.historyPages(channelID: channel,
            context: TransportContext(clock: ManualClock())) { try await script.next($0) }
        var first = pages.makeAsyncIterator()
        var second = pages.makeAsyncIterator()
        #expect(try await first.next()?.count == 1)
        #expect(try await second.next()?.count == 1)
        #expect(await script.cursors("before") == [nil, nil])
    }

    /// Invalid page budgets and endpoint limits fail synchronously before an executor can run.
    /// - Parameter budget: Invalid finite-boundary or extreme page count; every workflow rejects it.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [Int.min, -1, 0, 10_001, Int.max]) func invalidPageBudget(budget: Int) throws {
        let context = TransportContext(clock: ManualClock())
        #expect(throws: DiscordError.validation(.invalidValue)) {
            try MessageOperations.historyPages(channelID: channel, maximumPages: budget, context: context) { _ in [] }
        }
        #expect(throws: DiscordError.validation(.invalidValue)) {
            try MessageOperations.pinPages(channelID: channel, maximumPages: budget, context: context) { _ in throw TestSupportFailure.scripted("unused") }
        }
        #expect(throws: DiscordError.validation(.invalidValue)) {
            try MessageOperations.reactionPages(channelID: channel, messageID: message, emoji: .unicode("a"), maximumPages: budget, context: context) { _ in [] }
        }
        #expect(throws: DiscordError.validation(.invalidValue)) {
            try MessageOperations.pollVoterPages(channelID: channel, messageID: message, answerID: 1, maximumPages: budget, context: context) { _ in [] }
        }
        #expect(throws: DiscordError.validation(.invalidValue)) {
            try MessageOperations.searchPages(guildID: guild, query: MessageSearchQuery(), maximumPages: budget, context: context) { _ in throw TestSupportFailure.scripted("unused") }
        }
    }

    /// Every wrapper validates its endpoint-specific bounds and answer/emoji requirements at construction.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func endpointConfigurationErrors() throws {
        let context = TransportContext(clock: ManualClock())
        for limit in [0, 101] {
            #expect(throws: DiscordError.self) { try MessageOperations.historyPages(channelID: channel, limit: limit, context: context) { _ in [] } }
            #expect(throws: DiscordError.self) { try MessageOperations.reactionPages(channelID: channel, messageID: message, emoji: .unicode("a"), limit: limit, context: context) { _ in [] } }
            #expect(throws: DiscordError.self) { try MessageOperations.pollVoterPages(channelID: channel, messageID: message, answerID: 1, limit: limit, context: context) { _ in [] } }
        }
        for limit in [0, 51] {
            #expect(throws: DiscordError.self) { try MessageOperations.pinPages(channelID: channel, limit: limit, context: context) { _ in throw TestSupportFailure.scripted("unused") } }
        }
        #expect(throws: DiscordError.self) { try MessageOperations.reactionPages(channelID: channel, messageID: message, emoji: .unicode(""), context: context) { _ in [] } }
        #expect(throws: DiscordError.self) { try MessageOperations.pollVoterPages(channelID: channel, messageID: message, answerID: 0, context: context) { _ in [] } }
    }

    /// Oversized, repeated or backward history cursors fail and permanently finish that iterator.
    /// - Parameter ids: Oversized or nonadvancing response IDs relative to the initial before cursor.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [[99, 98], [100], [101]]) func malformedHistory(ids: [UInt64]) async throws {
        let script = OperationScript(responses: [try messages(ids)])
        let pages = try MessageOperations.historyPages(channelID: channel, before: MessageID(rawValue: 100),
            limit: 1, context: TransportContext(clock: ManualClock())) { try await script.next($0) }
        var iterator = pages.makeAsyncIterator()
        await #expect(throws: DiscordError.transport(.invalidResponse)) { try await iterator.next() }
        #expect(try await iterator.next() == nil)
        #expect(await script.calls == 1)
    }

    /// Pin completion uses has_more; short intermediate pages preserve exact nanoseconds and offset spelling.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func pinsExactTimestampAndCompletion() async throws {
        let timestamp = "2026-10-15T23:59:59.123456789+00:00"
        let script = OperationScript(responses: [try pins([timestamp], hasMore: true), try pins([], hasMore: false)])
        let pages = try MessageOperations.pinPages(channelID: channel,
            context: TransportContext(clock: ManualClock())) { try await script.next($0) }
        #expect(await script.calls == 0)
        var iterator = pages.makeAsyncIterator()
        #expect(try await iterator.next()?.first?.pinnedAt.rawValue == timestamp)
        #expect(try await iterator.next()?.isEmpty == true)
        #expect(try await iterator.next() == nil)
        #expect(await script.cursors("before") == [nil, timestamp])
        #expect(await script.readReuseCount == 0)
        let done = OperationScript(responses: [try pins([timestamp], hasMore: false)])
        var terminal = try MessageOperations.pinPages(channelID: channel,
            context: TransportContext(clock: ManualClock())) { try await done.next($0) }.makeAsyncIterator()
        #expect(try await terminal.next()?.count == 1)
        #expect(try await terminal.next() == nil)
        #expect(await done.calls == 1)
    }

    /// Empty continuation, oversized pin pages and repeated timestamp cursors are malformed responses.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func malformedPins() async throws {
        let timestamp = "2026-10-16T00:00:00Z"
        for page in [try pins([], hasMore: true), try pins([timestamp, timestamp], hasMore: false),
                     try pins([timestamp], hasMore: true),
                     try pins(["2026-10-16T01:00:00+01:00"], hasMore: true),
                     try pins(["2026-10-16T00:00:00.000000001Z"], hasMore: true),
                     try pins(["2026-10-17T00:00:00Z"], hasMore: true)] {
            let script = OperationScript(responses: [page])
            var iterator = try MessageOperations.pinPages(channelID: channel,
                before: DiscordTimestamp(rawValue: timestamp), limit: 1,
                context: TransportContext(clock: ManualClock())) { try await script.next($0) }.makeAsyncIterator()
            await #expect(throws: DiscordError.transport(.invalidResponse)) { try await iterator.next() }
            #expect(try await iterator.next() == nil)
        }
    }

    /// Reaction and voter reads both advance ascending IDs after short pages and stop only after empty responses.
    /// - Parameter voters: True selects poll voters; false selects burst reaction users.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [false, true]) func userCursorWorkflows(voters: Bool) async throws {
        let script = OperationScript(responses: [try users([11]), try users([12]), []])
        let context = TransportContext(clock: ManualClock())
        let pages = try voters
            ? MessageOperations.pollVoterPages(channelID: channel, messageID: message, answerID: 7,
                after: UserID(rawValue: 10), limit: 3, context: context) { try await script.next($0) }
            : MessageOperations.reactionPages(channelID: channel, messageID: message, emoji: .unicode("🎉"),
                type: .burst, after: UserID(rawValue: 10), limit: 3, context: context) { try await script.next($0) }
        #expect(await script.calls == 0)
        var iterator = pages.makeAsyncIterator()
        #expect(try await iterator.next()?.map(\.id.rawValue) == [11])
        #expect(try await iterator.next()?.map(\.id.rawValue) == [12])
        #expect(try await iterator.next()?.isEmpty == true)
        #expect(try await iterator.next() == nil)
        #expect(await script.cursors("after") == ["10", "11", "12"])
        #expect(await script.readReuseCount == 0)
        if !voters { #expect(await script.cursors("type") == ["1", "1", "1"]) }
    }

    /// User workflows reject oversized pages and cursors that repeat or reverse direction.
    /// - Parameter ids: Server IDs violating the one-item response cap or exclusive ascending cursor.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [[11, 12], [10], [9]]) func malformedUsers(ids: [UInt64]) async throws {
        let script = OperationScript(responses: [try users(ids)])
        var iterator = try MessageOperations.pollVoterPages(channelID: channel, messageID: message,
            answerID: 1, after: UserID(rawValue: 10), limit: 1,
            context: TransportContext(clock: ManualClock())) { try await script.next($0) }.makeAsyncIterator()
        await #expect(throws: DiscordError.transport(.invalidResponse)) { try await iterator.next() }
        #expect(try await iterator.next() == nil)
    }

    /// Requested limits, rather than returned match counts, advance offsets through short and empty pages.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func searchOffsetsAndDeepIndexing() async throws {
        let script = OperationScript(responses: [try search(total: 1, deep: true, ids: [5]),
            try search(total: 8, deep: true), try search(total: 8, ids: [4])])
        let pages = try MessageOperations.searchPages(guildID: guild, query: MessageSearchQuery(limit: 3, offset: 1),
            context: TransportContext(clock: ManualClock())) { try await script.next($0) }
        #expect(await script.calls == 0)
        var iterator = pages.makeAsyncIterator()
        #expect(try await iterator.next()?.first?.first?.id.rawValue == 5)
        #expect(try await iterator.next()?.isEmpty == true)
        #expect(try await iterator.next()?.first?.first?.id.rawValue == 4)
        #expect(try await iterator.next() == nil)
        #expect(await script.cursors("offset") == ["1", "4", "7"])
        #expect(await script.readReuseCount == 0)
    }

    /// The final legal window page is yielded before the next pull reports incomplete search-window exhaustion.
    /// - Parameter deep: True tests incomplete indexing despite zero results; false tests excess total results.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [false, true]) func searchWindowExhaustion(deep: Bool) async throws {
        let script = OperationScript(responses: [try search(total: deep ? 0 : 10_001, deep: deep)])
        var iterator = try MessageOperations.searchPages(guildID: guild,
            query: MessageSearchQuery(offset: 9_975), context: TransportContext(clock: ManualClock())) {
                try await script.next($0)
            }.makeAsyncIterator()
        #expect(try await iterator.next()?.isEmpty == true)
        await #expect(throws: DiscordError.validation(.limitExceeded)) { try await iterator.next() }
        #expect(try await iterator.next() == nil)
        #expect(await script.calls == 1)
        let complete = OperationScript(responses: [try search(total: 10_000)])
        var done = try MessageOperations.searchPages(guildID: guild, query: MessageSearchQuery(offset: 9_975),
            context: TransportContext(clock: ManualClock())) { try await complete.next($0) }.makeAsyncIterator()
        #expect(try await done.next()?.isEmpty == true)
        #expect(try await done.next() == nil)
    }

    /// A zero retry_after is floored to 100 ms; virtual time drives sequential indexing and leaves no sleepers.
    /// - Parameter delay: Server delay, either zero or fractional positive seconds.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [0.0, 2.5]) func indexingDelayAndSuccess(delay: Double) async throws {
        let sleeping = TestBarrier()
        let clock = ManualClock(onSleepScheduled: { sleeping.open() })
        let script = OperationScript(responses: [try indexing(delay), try search(total: 1, ids: [5])])
        let pages = try MessageOperations.searchPages(guildID: guild, query: MessageSearchQuery(),
            context: TransportContext(clock: clock)) { try await script.next($0) }
        let task = Task {
            var iterator = pages.makeAsyncIterator()
            return try await iterator.next()
        }
        try await sleeping.wait()
        #expect(await script.calls == 1)
        #expect(clock.pendingSleepCount == 1)
        try clock.advance(by: .seconds(max(0.1, delay)) - .nanoseconds(1))
        #expect(await script.calls == 1)
        try clock.advance(by: .nanoseconds(1))
        #expect(try await task.value?.first?.first?.id.rawValue == 5)
        #expect(await script.calls == 2)
        #expect(await script.cursors("offset") == ["0", "0"])
        #expect(clock.pendingSleepCount == 0)
    }

    /// Configurations are bounded; final pending attempts do not sleep and excessive delay fails immediately.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func indexingBoundsAndExhaustion() async throws {
        let clock = ManualClock()
        let context = TransportContext(clock: clock)
        for attempts in [0, 1_001] {
            #expect(throws: DiscordError.validation(.invalidValue)) {
                try MessageOperations.searchPages(guildID: guild, query: MessageSearchQuery(), maximumIndexingAttempts: attempts,
                    context: context) { _ in throw TestSupportFailure.scripted("unused") }
            }
        }
        for delay in [-1, 0, 0.09, 3_601, Double.infinity, -Double.infinity, Double.nan] {
            #expect(throws: DiscordError.validation(.invalidValue)) {
                try MessageOperations.searchPages(guildID: guild, query: MessageSearchQuery(), maximumRetryDelaySeconds: delay,
                    context: context) { _ in throw TestSupportFailure.scripted("unused") }
            }
        }
        let pending = OperationScript(responses: [try indexing(60)])
        var exhausted = try MessageOperations.searchPages(guildID: guild, query: MessageSearchQuery(),
            maximumIndexingAttempts: 1, context: context) { try await pending.next($0) }.makeAsyncIterator()
        await #expect(throws: DiscordError.validation(.limitExceeded)) { try await exhausted.next() }
        #expect(await pending.calls == 1)
        #expect(clock.pendingSleepCount == 0)
        let excessive = OperationScript(responses: [try indexing(60.001)])
        var rejected = try MessageOperations.searchPages(guildID: guild, query: MessageSearchQuery(),
            context: context) { try await excessive.next($0) }.makeAsyncIterator()
        await #expect(throws: DiscordError.transport(.invalidResponse)) { try await rejected.next() }
        #expect(clock.pendingSleepCount == 0)
        let large = OperationScript(responses: [try search(total: 3, ids: [1, 2])])
        var oversized = try MessageOperations.searchPages(guildID: guild, query: MessageSearchQuery(limit: 1),
            context: context) { try await large.next($0) }.makeAsyncIterator()
        await #expect(throws: DiscordError.transport(.invalidResponse)) { try await oversized.next() }
    }

    /// Indexing sleeps honor cancellation and deadlines and release all operation-owned virtual timers.
    /// - Parameter deadline: True expires the virtual deadline; false cancels the owning task.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [false, true]) func indexingCancellationAndDeadline(deadline: Bool) async throws {
        let sleeping = TestBarrier()
        let entered = TestBarrier()
        let clock = ManualClock(onSleepScheduled: { sleeping.open() })
        let script = OperationScript(responses: [try indexing(20)])
        let context = TransportContext(clock: clock, deadline: deadline ? clock.now.advanced(by: .seconds(5)) : nil)
        let task = Task {
            var iterator = try MessageOperations.searchPages(guildID: guild, query: MessageSearchQuery(),
                context: context) {
                    let response = try await script.next($0)
                    entered.open()
                    return response
                }.makeAsyncIterator()
            return try await iterator.next()
        }
        try await sleeping.wait()
        try await entered.wait()
        if deadline {
            try clock.advance(by: .seconds(5))
            await #expect(throws: TransportFailure.deadlineExceeded) { try await task.value }
        } else {
            task.cancel()
            await #expect(throws: CancellationError.self) { try await task.value }
        }
        #expect(await script.calls == 1)
        #expect(clock.pendingSleepCount == 0)
    }

    /// Cancellation while an executor owns a resource is awaited; no page or indexing request overlaps it.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func activeReadCancellationCleanup() async throws {
        let entered = TestBarrier()
        let release = TestBarrier()
        let probe = OperationActivity()
        let task = Task {
            var iterator = try MessageOperations.searchPages(guildID: guild, query: MessageSearchQuery(),
                context: TransportContext(clock: ManualClock())) { _ in
                    await probe.begin()
                    do { entered.open(); try await release.wait() }
                    catch { await probe.end(); throw error }
                    await probe.end()
                    return try search(total: 0)
                }.makeAsyncIterator()
            return try await iterator.next()
        }
        try await entered.wait()
        #expect(await probe.active == 1)
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await probe.active == 0)
        #expect(await probe.maximumActive == 1)
        #expect(release.waitingCount == 0)
    }

    /// Page exhaustion, original executor errors and already-expired deadlines never trigger hidden extra reads.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func pageBudgetAndReadFailures() async throws {
        let script = OperationScript(responses: [try messages([99])])
        var limited = try MessageOperations.historyPages(channelID: channel, maximumPages: 1,
            context: TransportContext(clock: ManualClock())) { try await script.next($0) }.makeAsyncIterator()
        #expect(try await limited.next()?.count == 1)
        await #expect(throws: DiscordError.validation(.limitExceeded)) { try await limited.next() }
        #expect(await script.calls == 1)
        var failed = try MessageOperations.reactionPages(channelID: channel, messageID: message, emoji: .unicode("a"),
            context: TransportContext(clock: ManualClock())) { _ in throw DiscordError.api(status: 403, code: 50_001) }.makeAsyncIterator()
        await #expect(throws: DiscordError.api(status: 403, code: 50_001)) { try await failed.next() }
        #expect(try await failed.next() == nil)
        let clock = ManualClock()
        var expired = try MessageOperations.historyPages(channelID: channel,
            context: TransportContext(clock: clock, deadline: clock.now)) { _ in
                Issue.record("Expired history executed"); return []
            }.makeAsyncIterator()
        await #expect(throws: TransportFailure.deadlineExceeded) { try await expired.next() }
    }

    /// Plans preserve every ID exactly once and choose only legal chunks, including singleton-prone remainders.
    /// - Parameter count: Valid input size exercising minimum, chunk boundaries and the 10,000-ID cap.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [2, 99, 100, 101, 102, 199, 200, 201, 10_000]) func bulkChunking(count: Int) throws {
        let ids = try recentIDs(count)
        let plan = try BulkMessageDeletePlan(channelID: channel, messageIDs: ids, nowMilliseconds: now)
        #expect(plan.messageIDs == ids)
        #expect(plan.chunks.flatMap { $0 } == ids)
        #expect(plan.chunks.allSatisfy { (2...100).contains($0.count) })
        if count == 101 { #expect(plan.chunks.map(\.count) == [99, 2]) }
        if count == 201 { #expect(plan.chunks.map(\.count) == [100, 99, 2]) }
        #expect(String(describing: plan) == "BulkMessageDeletePlan(redacted)")
        #expect(String(reflecting: plan) == "BulkMessageDeletePlan(redacted)")
        #expect(Mirror(reflecting: plan).children.count == 1)
    }

    /// Whole-plan validation rejects invalid counts, duplicate or too-old IDs, including one-millisecond age excess.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func bulkPlanValidation() throws {
        let ids = try recentIDs(2)
        let old = try MessageID(timestampMilliseconds: now - 1_209_600_000 - 1)
        for invalid in [[], [ids[0]], [ids[0], ids[0]], [ids[0], old], try recentIDs(10_001)] {
            #expect(throws: DiscordError.self) { try BulkMessageDeletePlan(channelID: channel, messageIDs: invalid, nowMilliseconds: now) }
        }
        let boundary = try MessageID(timestampMilliseconds: now - 1_209_600_000)
        #expect(try BulkMessageDeletePlan(channelID: channel, messageIDs: [ids[0], boundary], nowMilliseconds: now).chunks.count == 1)
        #expect(throws: DiscordError.self) { try BulkMessageDeletePlan(channelID: channel, messageIDs: ids, nowMilliseconds: now, auditReason: String(repeating: "x", count: 513)) }
    }

    /// Bulk execution is explicit and sequential; descriptors never declare ambiguous mutation retry safety.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func bulkSequentialSuccess() async throws {
        let ids = try recentIDs(201)
        let plan = try BulkMessageDeletePlan(channelID: channel, messageIDs: ids, nowMilliseconds: now)
        let entered = TestBarrier()
        let release = TestBarrier()
        let script = OperationScript(responses: [try EmptyResponse(data: Data()), try EmptyResponse(data: Data()), try EmptyResponse(data: Data())])
        #expect(await script.calls == 0)
        let task = Task {
            try await plan.execute(context: TransportContext(clock: ManualClock())) { endpoint in
                let result = try await script.next(endpoint)
                if await script.calls == 1 { entered.open(); try await release.wait() }
                return result
            }
        }
        try await entered.wait()
        #expect(await script.calls == 1)
        release.open()
        #expect(try await task.value == ids)
        #expect(await script.calls == 3)
        #expect(await script.retrySafety == [.unsafe, .unsafe, .unsafe])
    }

    /// Failures preserve exact acknowledged/attempted/unattempted partitions and the original mutation uncertainty.
    /// - Parameter failingChunk: Zero-based chunk that throws after entering execution.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [0, 1, 2]) func bulkPartialFailure(failingChunk: Int) async throws {
        let ids = try recentIDs(201)
        let plan = try BulkMessageDeletePlan(channelID: channel, messageIDs: ids, nowMilliseconds: now)
        let script = OperationScript(responses: Array(repeating: try EmptyResponse(data: Data()), count: 3))
        do {
            _ = try await plan.execute(context: TransportContext(clock: ManualClock())) { endpoint in
                let response = try await script.next(endpoint)
                if await script.calls == failingChunk + 1 {
                    throw DiscordError.unknownMutationOutcome(.connectionLostAfterSubmission)
                }
                return response
            }
            Issue.record("Expected partial failure")
        } catch let error as BulkMessageDeleteFailure {
            #expect(error.completed == plan.chunks.prefix(failingChunk).flatMap { $0 })
            #expect(error.attempted == plan.chunks[failingChunk])
            #expect(error.unattempted == plan.chunks.dropFirst(failingChunk + 1).flatMap { $0 })
            #expect(error.underlying as? DiscordError == .unknownMutationOutcome(.connectionLostAfterSubmission))
            #expect(error.completed + error.attempted + error.unattempted == ids)
            #expect(String(describing: error) == "BulkMessageDeleteFailure(redacted)")
            #expect(String(reflecting: error) == "BulkMessageDeleteFailure(redacted)")
            #expect(Mirror(reflecting: error).children.count == 1)
        }
        #expect(await script.calls == failingChunk + 1)
    }

    /// Pre-cancellation and expired deadlines report entirely unattempted plans without invoking the executor.
    /// - Parameter deadline: True tests inclusive expiration; false tests a pre-cancelled child task.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [false, true]) func bulkPreflightFailure(deadline: Bool) async throws {
        let ids = try recentIDs(2)
        let plan = try BulkMessageDeletePlan(channelID: channel, messageIDs: ids, nowMilliseconds: now)
        let clock = ManualClock()
        let task = Task {
            if !deadline { withUnsafeCurrentTask { $0?.cancel() } }
            return try await plan.execute(context: TransportContext(clock: clock, deadline: deadline ? clock.now : nil)) { _ in
                Issue.record("Preflight failure executed"); return try EmptyResponse(data: Data())
            }
        }
        do { _ = try await task.value; Issue.record("Expected preflight failure") }
        catch let error as BulkMessageDeleteFailure {
            #expect(error.completed.isEmpty)
            #expect(error.attempted.isEmpty)
            #expect(error.unattempted == ids)
            if deadline { #expect(error.underlying as? TransportFailure == .deadlineExceeded) }
            else { #expect(error.underlying is CancellationError) }
        }
    }

    /// In-flight cancellation/deadlines await executor cleanup and retain attempted chunk evidence.
    /// - Parameter deadline: True expires the active deadline; false cancels its owning task.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [false, true]) func bulkActiveFailureCleanup(deadline: Bool) async throws {
        let ids = try recentIDs(101)
        let plan = try BulkMessageDeletePlan(channelID: channel, messageIDs: ids, nowMilliseconds: now)
        let entered = TestBarrier()
        let release = TestBarrier()
        let clock = ManualClock()
        let task = Task {
            try await plan.execute(context: TransportContext(clock: clock, deadline: deadline ? clock.now.advanced(by: .seconds(1)) : nil)) { _ in
                entered.open(); try await release.wait(); return try EmptyResponse(data: Data())
            }
        }
        try await entered.wait()
        if deadline { try clock.advance(by: .seconds(1)) } else { task.cancel() }
        do { _ = try await task.value; Issue.record("Expected active failure") }
        catch let error as BulkMessageDeleteFailure {
            #expect(error.completed.isEmpty)
            #expect(error.attempted == plan.chunks[0])
            #expect(error.unattempted == plan.chunks[1])
            if deadline { #expect(error.underlying as? TransportFailure == .deadlineExceeded) }
            else { #expect(error.underlying is CancellationError) }
        }
        #expect(release.waitingCount == 0)
        #expect(clock.pendingSleepCount == 0)
    }

    /// Cancellation racing after an acknowledgement must preserve the successful chunk in completed progress.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func bulkAcknowledgementCancellationRace() async throws {
        let ids = try recentIDs(101)
        let plan = try BulkMessageDeletePlan(channelID: channel, messageIDs: ids, nowMilliseconds: now)
        let task = Task {
            try await plan.execute(context: TransportContext(clock: ManualClock())) { _ in
                withUnsafeCurrentTask { $0?.cancel() }
                return try EmptyResponse(data: Data())
            }
        }
        do {
            _ = try await task.value
            Issue.record("Expected cancellation after acknowledgement")
        } catch let error as BulkMessageDeleteFailure {
            #expect(error.completed == plan.chunks[0])
            #expect(error.attempted.isEmpty)
            #expect(error.unattempted == plan.chunks[1])
            #expect(error.underlying is CancellationError)
        }
    }

    /// Produces recent distinct snowflakes with deterministic low sequence bits, without consulting wall time.
    /// - Parameter count: Nonnegative desired fixture size; test callers use at most 10,001 IDs.
    /// - Returns: Distinct IDs at the test's trusted wall time, in ascending order.
    /// - Throws: Snowflake timestamp errors if the fixture epoch becomes invalid.
    private func recentIDs(_ count: Int) throws -> [MessageID] {
        let first = try MessageID(timestampMilliseconds: now).rawValue
        return (0..<count).map { MessageID(rawValue: first + UInt64($0)) }
    }

    /// Builds a complete minimal message fixture while preserving each supplied unsigned identifier.
    /// - Parameter id: Exact raw snowflake, including boundary values.
    /// - Returns: JSON object text for nested response fixtures; never sent to Discord.
    private func messageJSON(_ id: UInt64) -> String {
        """
        {"id":"\(id)","channel_id":"1","author":{"id":"1","username":"author","discriminator":"0","global_name":null,"avatar":null},"content":"private-body","timestamp":"2026-10-16T00:00:00Z","edited_timestamp":null,"tts":false,"mention_everyone":false,"mentions":[],"mention_roles":[],"attachments":[],"embeds":[],"pinned":false,"type":0}
        """
    }

    /// Parses ordered complete message fixtures for injectable page responses.
    /// - Parameter ids: Exact IDs in desired server order; empty produces an empty response.
    /// - Returns: Independent immutable message projections.
    /// - Throws: Model validation errors if the fixture no longer matches the supported schema.
    private func messages(_ ids: [UInt64]) throws -> [Message] {
        try ids.map { try Message(data: Data(messageJSON($0).utf8)) }
    }

    /// Parses complete partial-family user fixtures without relying on floating-point ID conversion.
    /// - Parameter ids: Exact raw user snowflakes in desired page order.
    /// - Returns: User projections; empty input produces an empty terminal page.
    /// - Throws: Model validation errors for an invalid fixture.
    private func users(_ ids: [UInt64]) throws -> [User] {
        try ids.map { try User(data: Data("{\"id\":\"\($0)\",\"username\":\"u\",\"discriminator\":\"0\",\"global_name\":null,\"avatar\":null}".utf8)) }
    }

    /// Builds current pin envelopes with caller-controlled exact cursors and independent completion metadata.
    /// - Parameters:
    ///   - timestamps: Valid ISO8601 spellings, retained exactly by the pin projection.
    ///   - hasMore: Explicit upstream continuation signal, independent of array length.
    /// - Returns: Parsed pins response used by endpoint executor scripts.
    /// - Throws: Timestamp/response validation errors if fixture data is invalid.
    private func pins(_ timestamps: [String], hasMore: Bool) throws -> MessagePins {
        let items = timestamps.enumerated().map { "{\"pinned_at\":\"\($0.element)\",\"message\":\(messageJSON(UInt64($0.offset + 1)))}" }
        return try MessagePins(data: Data("{\"items\":[\(items.joined(separator: ","))],\"has_more\":\(hasMore)}".utf8))
    }

    /// Builds search result groups, each containing one match, with independent total/deep-indexing metadata.
    /// - Parameters:
    ///   - total: Nonnegative server-reported total, including results beyond the supported window.
    ///   - deep: Whether deep historical indexing is still in progress; default false.
    ///   - ids: Exact result IDs; default empty to exercise empty intermediate pages.
    /// - Returns: Typed results variant.
    /// - Throws: Schema validation errors if the fixture is invalid.
    private func search(total: Int, deep: Bool = false, ids: [UInt64] = []) throws -> MessageSearchResponse {
        let groups = ids.map { "[\(messageJSON($0))]" }.joined(separator: ",")
        return .results(try MessageSearchResults(data: Data("{\"total_results\":\(total),\"messages\":[\(groups)],\"doing_deep_historical_index\":\(deep)}".utf8)))
    }

    /// Builds a pending search response with an explicit server retry delay, including zero.
    /// - Parameter delay: Finite JSON seconds; tests include accepted and locally excessive values.
    /// - Returns: Typed indexing variant representing HTTP 202 without a real request.
    /// - Throws: Model validation errors if fixture data is invalid.
    private func indexing(_ delay: Double) throws -> MessageSearchResponse {
        .indexing(try MessageSearchIndexing(data: Data("{\"code\":110000,\"message\":\"Index not yet available\",\"retry_after\":\(delay)}".utf8)))
    }
}

/// Bounded sequential response script retaining only query/retry observations needed by assertions.
private actor OperationScript<Response: Sendable> {
    private let responses: [Response]
    private var queries: [[QueryItem]] = []
    private(set) var calls = 0
    private(set) var readReuseCount = 0
    private(set) var retrySafety: [RetrySafety] = []

    /// Stores immutable deterministic responses; no execution begins during construction.
    /// - Parameter responses: One response per expected descriptor execution, in order.
    init(responses: [Response]) { self.responses = responses }

    /// Observes one descriptor then returns the next scripted value without retaining its payload.
    /// - Parameter endpoint: Descriptor under test; query and safe policy metadata are recorded.
    /// - Returns: Next response in configured order.
    /// - Throws: Script exhaustion rather than silently replaying a prior response.
    func next(_ endpoint: Endpoint<Response>) throws -> Response {
        guard calls < responses.count else { throw TransportFailure.scriptExhausted }
        queries.append(endpoint.query)
        if endpoint.readPolicy != nil { readReuseCount += 1 }
        retrySafety.append(endpoint.retrySafety)
        let response = responses[calls]
        calls += 1
        return response
    }

    /// Reads exact per-request cursor strings without parsing them as dates or numbers.
    /// - Parameter name: Query name to inspect; missing fields remain nil.
    /// - Returns: One value or nil per recorded execution, preserving request order.
    func cursors(_ name: String) -> [String?] {
        queries.map { $0.first(where: { $0.name == name })?.value }
    }
}

/// Tracks owned executor activity for deterministic nonoverlap and cleanup assertions.
private actor OperationActivity {
    private(set) var active = 0
    private(set) var maximumActive = 0

    /// Records entry into an executor and its peak simultaneous ownership count.
    func begin() { active += 1; maximumActive = max(maximumActive, active) }

    /// Releases one owned execution before its cancellation propagates to the caller.
    func end() { active -= 1 }
}
