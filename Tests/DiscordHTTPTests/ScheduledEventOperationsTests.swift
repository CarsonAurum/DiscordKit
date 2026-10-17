import DiscordCore
import DiscordModels
import DiscordTestSupport
import DiscordTransport
import Foundation
import Testing
@testable import DiscordHTTP

/// Snapshot-only request suppression and bounded nonprefetching subscriber traversal.
@Suite(.timeLimit(.minutes(1))) struct ScheduledEventOperationsTests {
    /// Empty/matching requests suppress writes; changed values retain exact context, target and audit handling.
    /// - Throws: Unexpected fixture/request/descriptor failures fail the test.
    @Test func noOpSnapshots() throws {
        let event = try GuildScheduledEvent(data: Data(ScheduledEventEndpointTests.eventJSON.utf8))
        #expect(try GuildScheduledEventOperations.modifyIfChanged(current: event, request: GuildScheduledEventModify(currentEntityType: .voice)) == nil)
        #expect(try GuildScheduledEventOperations.modifyIfChanged(current: event,
            request: GuildScheduledEventModify(currentEntityType: .voice, name: .value("private-event"), description: .null), auditReason: "\n") == nil)
        let change = try GuildScheduledEventModify(currentEntityType: .voice, name: .value("new"))
        let descriptor = try #require(try GuildScheduledEventOperations.modifyIfChanged(current: event, request: change, auditReason: "why"))
        #expect(descriptor.path == ["guilds", "18446744073709551615", "scheduled-events", "18446744073709551615"])
        #expect(descriptor.auditReason == "why")
        #expect(try JSONValue.parse(#require(descriptor.body?.storedBodyBytes)) == change.jsonValue())
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildScheduledEventOperations.modifyIfChanged(current: event, request: change, auditReason: "\n") }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildScheduledEventOperations.modifyIfChanged(current: event, request: GuildScheduledEventModify(currentEntityType: .external)) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildScheduledEventOperations.modifyIfChanged(current: event, request: GuildScheduledEventModify(currentEntityType: .voice, currentStatus: .active)) }
        let tooLate = try DiscordTimestamp(rawValue: "2030-01-02T00:00:00Z")
        #expect(throws: DiscordError.validation(.invalidValue)) {
            try GuildScheduledEventOperations.modifyIfChanged(current: event, request: GuildScheduledEventModify(currentEntityType: .voice, scheduledStartTime: .value(tooLate)))
        }
        let tooEarly = try DiscordTimestamp(rawValue: "2029-01-02T00:00:00Z")
        #expect(throws: DiscordError.validation(.invalidValue)) {
            try GuildScheduledEventOperations.modifyIfChanged(current: event, request: GuildScheduledEventModify(currentEntityType: .voice, scheduledEndTime: .value(tooEarly)))
        }
        let stage = try StageInstance(data: Data(ScheduledEventEndpointTests.stageJSON.utf8))
        #expect(try StageInstanceOperations.modifyIfChanged(current: stage, request: StageInstanceModify()) == nil)
        #expect(try StageInstanceOperations.modifyIfChanged(current: stage, request: StageInstanceModify(topic: .value("private-topic"), privacyLevel: .value(.guildOnly)), auditReason: "\n") == nil)
        let stageChange = try #require(try StageInstanceOperations.modifyIfChanged(current: stage, request: StageInstanceModify(topic: .value("new")), auditReason: "why"))
        #expect(stageChange.path == ["stage-instances", "18446744073709551615"])
        #expect(stageChange.auditReason == "why")
    }

    /// Every lifecycle edge is checked, equal states skip writes, and future context cannot be guessed.
    /// - Throws: Unexpected fixture/request failures fail the test; unsupported transitions are asserted.
    @Test func statusTransitions() throws {
        let base = try GuildScheduledEvent(data: Data(ScheduledEventEndpointTests.eventJSON.utf8))
        for from in GuildScheduledEventStatus.allCases {
            var fields = base.rawFields
            fields["status"] = .number(try JSONNumber(rawValue: String(from.rawValue)))
            let current = try GuildScheduledEvent(data: JSONValue.object(fields).serialized())
            for to in GuildScheduledEventStatus.allCases {
                if from == to { #expect(try GuildScheduledEventOperations.transition(current: current, to: to, auditReason: "\n") == nil) }
                else if (from == .scheduled && [.active,.canceled].contains(to)) || (from == .active && to == .completed) {
                    let endpoint = try #require(try GuildScheduledEventOperations.transition(current: current, to: to))
                    #expect(try JSONValue.parse(#require(endpoint.body?.storedBodyBytes)) == .object(["status": .number(try JSONNumber(rawValue: String(to.rawValue)))]))
                } else { #expect(throws: DiscordError.validation(.invalidValue)) { try GuildScheduledEventOperations.transition(current: current, to: to) } }
            }
        }
        for key in ["status", "entity_type"] {
            var fields = base.rawFields; fields[key] = .number(try JSONNumber(rawValue: "999"))
            let current = try GuildScheduledEvent(data: JSONValue.object(fields).serialized())
            #expect(throws: DiscordError.validation(.invalidValue)) { try GuildScheduledEventOperations.transition(current: current, to: .active) }
        }
    }

    /// Short nonempty pages continue; before retreats to the first ID while after advances to the last.
    /// - Parameter before: True exercises ascending pages within descending exclusive page windows.
    /// - Throws: Unexpected fixture, descriptor or iteration failures fail the test.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [false, true]) func continuation(before: Bool) async throws {
        let pages: [[UInt64]] = before ? [[100, 101], [10], []] : [[10, 11], [100], []]
        let script = ScheduledUserPageScript(try pages.map { try Self.users($0) })
        let sequence = try GuildScheduledEventOperations.userPages(guildID: .init(rawValue: 1), eventID: .init(rawValue: .max),
            position: before ? .before(.init(rawValue: .max)) : .after(.init(rawValue: 0)), limit: 2, withMember: true,
            context: TransportContext(clock: ManualClock())) { try await script.next($0) }
        #expect(await script.calls == 0)
        var iterator = sequence.makeAsyncIterator()
        #expect(try await iterator.next()?.count == 2)
        #expect(await script.calls == 1)
        #expect(try await iterator.next()?.count == 1)
        #expect(try await iterator.next()?.isEmpty == true)
        #expect(try await iterator.next() == nil)
        #expect(await script.calls == 3)
        let name = before ? "before" : "after"
        let expected = before ? ["18446744073709551615", "100", "10"] : ["0", "11", "100"]
        #expect(await script.queries == expected.map { [.init(name: "limit", value: "2"), .init(name: "with_member", value: "true"), .init(name: name, value: $0)] })
        #expect(await script.reused == false)
    }

    /// Duplicate/reversed/oversized/out-of-bound results and foreign event IDs permanently finish each iterator.
    /// - Parameter before: Both cursor directions enforce ascending page-local ordering and exclusive bounds.
    /// - Throws: Unexpected fixture errors fail the test; malformed page errors are explicitly asserted.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [false, true]) func malformedPages(before: Bool) async throws {
        let invalid: [[UInt64]] = before ? [[9,9], [9,8], [10], [11], [1,2,3]] : [[11,11], [12,11], [10], [9], [11,12,13]]
        for ids in invalid {
            let script = ScheduledUserPageScript([try Self.users(ids)])
            var iterator = try GuildScheduledEventOperations.userPages(guildID: .init(rawValue: 1), eventID: .init(rawValue: .max),
                position: before ? .before(.init(rawValue: 10)) : .after(.init(rawValue: 10)), limit: 2,
                context: TransportContext(clock: ManualClock())) { try await script.next($0) }.makeAsyncIterator()
            await #expect(throws: DiscordError.transport(.invalidResponse)) { try await iterator.next() }
            #expect(try await iterator.next() == nil)
            #expect(await script.calls == 1)
        }
        for page in [try Self.users([1], eventID: 2), [try GuildScheduledEventUser(data: Data(#"{"guild_scheduled_event_id":"18446744073709551615","user_id":"1","response":1}"#.utf8))]] {
            var iterator = try GuildScheduledEventOperations.userPages(guildID: .init(rawValue: 1), eventID: .init(rawValue: .max),
                context: TransportContext(clock: ManualClock())) { _ in page }.makeAsyncIterator()
            await #expect(throws: DiscordError.transport(.invalidResponse)) { try await iterator.next() }
            #expect(try await iterator.next() == nil)
        }
    }

    /// Bounds, page budget, deadline, executor errors and cancellation terminate without requests after failure.
    /// - Throws: Unexpected fixture/configuration errors fail the test; every failure category is asserted.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func terminalFailures() async throws {
        let clock = ManualClock(), script = ScheduledUserPageScript([try Self.users([1])])
        for bound in [Int.min, 0, 101, Int.max] {
            #expect(throws: DiscordError.validation(.invalidValue)) {
                try GuildScheduledEventOperations.userPages(guildID: .init(rawValue: 1), eventID: .init(rawValue: 1),
                    limit: bound, context: TransportContext(clock: clock)) { _ in Issue.record("Unexpected executor"); return [] }
            }
        }
        for bound in [Int.min, 0, 10_001, Int.max] {
            #expect(throws: DiscordError.validation(.invalidValue)) {
                try GuildScheduledEventOperations.userPages(guildID: .init(rawValue: 1), eventID: .init(rawValue: 1),
                    maximumPages: bound, context: TransportContext(clock: clock)) { _ in Issue.record("Unexpected executor"); return [] }
            }
        }
        var limited = try GuildScheduledEventOperations.userPages(guildID: .init(rawValue: 1), eventID: .init(rawValue: .max),
            maximumPages: 1, context: TransportContext(clock: clock)) { try await script.next($0) }.makeAsyncIterator()
        #expect(try await limited.next()?.count == 1)
        await #expect(throws: DiscordError.validation(.limitExceeded)) { try await limited.next() }
        #expect(try await limited.next() == nil)
        #expect(await script.calls == 1)
        var failed = try GuildScheduledEventOperations.userPages(guildID: .init(rawValue: 1), eventID: .init(rawValue: 1),
            context: TransportContext(clock: clock)) { _ in throw TransportFailure.closed }.makeAsyncIterator()
        await #expect(throws: TransportFailure.closed) { try await failed.next() }
        #expect(try await failed.next() == nil)
        var expired = try GuildScheduledEventOperations.userPages(guildID: .init(rawValue: 1), eventID: .init(rawValue: 1),
            context: TransportContext(clock: clock, deadline: clock.now)) { _ in Issue.record("Unexpected executor"); return [] }.makeAsyncIterator()
        await #expect(throws: TransportFailure.deadlineExceeded) { try await expired.next() }
        #expect(try await expired.next() == nil)
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            var iterator = try GuildScheduledEventOperations.userPages(guildID: .init(rawValue: 1), eventID: .init(rawValue: 1),
                context: TransportContext(clock: clock)) { _ in Issue.record("Unexpected executor"); return [] }.makeAsyncIterator()
            return try await iterator.next()
        }
        await #expect(throws: CancellationError.self) { try await cancelled.value }
        #expect(clock.pendingSleepCount == 0)
    }

    /// In-flight cancellation releases the suspended executor, and separate iterators retain independent boundaries.
    /// - Throws: Unexpected setup/iteration failures fail the test; cancellation is explicitly asserted.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func cancellationAndIndependentIterators() async throws {
        let entered = TestBarrier(), gate = TestBarrier(), clock = ManualClock()
        let sequence = try GuildScheduledEventOperations.userPages(guildID: .init(rawValue: 1), eventID: .init(rawValue: 1),
            context: TransportContext(clock: clock)) { _ in entered.open(); try await gate.wait(); return [] }
        let task = Task { var iterator = sequence.makeAsyncIterator(); return try await iterator.next() }
        try await entered.wait(); task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(gate.waitingCount == 0)
        let script = ScheduledUserPageScript([try Self.users([1]), try Self.users([1]), [], []])
        let independent = try GuildScheduledEventOperations.userPages(guildID: .init(rawValue: 1), eventID: .init(rawValue: .max),
            context: TransportContext(clock: clock)) { try await script.next($0) }
        var first = independent.makeAsyncIterator(), second = independent.makeAsyncIterator()
        #expect(try await first.next()?.count == 1)
        #expect(try await second.next()?.count == 1)
        #expect(try await first.next()?.isEmpty == true)
        #expect(try await second.next()?.isEmpty == true)
        #expect(try await first.next() == nil)
        #expect(try await second.next() == nil)
        #expect(await script.calls == 4)
    }

    /// Builds generic subscriber projections without applying endpoint pagination validation.
    /// - Parameters:
    ///   - ids: Exact IDs including deliberately malformed page-local order and duplicates.
    ///   - eventID: Owning event, default maximum; other values exercise scope rejection.
    /// - Returns: Ordered projections suitable for injected page executors.
    /// - Throws: Unexpected JSON/model fixture errors fail fixture users.
    static func users(_ ids: [UInt64], eventID: UInt64 = .max) throws -> [GuildScheduledEventUser] {
        guard case .array(let values) = try JSONValue.parse(ScheduledEventEndpointTests.usersData(ids, eventID: eventID)) else { throw DiscordError.transport(.invalidResponse) }
        return try values.map { try GuildScheduledEventUser(data: $0.serialized()) }
    }
}

/// Finite sequential executor records page queries and reuse metadata without sockets or hidden tasks.
private actor ScheduledUserPageScript {
    private var pages: [[GuildScheduledEventUser]]
    private(set) var calls = 0
    private(set) var queries: [[QueryItem]] = []
    private(set) var reused = false

    /// Stores the bounded response script without starting work.
    /// - Parameter pages: Complete per-call subscriber snapshots, including explicit empty completion pages.
    init(_ pages: [[GuildScheduledEventUser]]) { self.pages = pages }

    /// Records one descriptor and consumes one scripted result in executor order.
    /// - Parameter endpoint: Ordinary bot GET generated by the subscriber workflow, with reuse disabled.
    /// - Returns: Next scripted page exactly as supplied; no response decoding masks malformed-order fixtures.
    /// - Throws: Closed transport once the finite script is exhausted; calls and queries still record entry.
    func next(_ endpoint: Endpoint<[GuildScheduledEventUser]>) throws -> [GuildScheduledEventUser] {
        calls += 1; queries.append(endpoint.query); reused = reused || endpoint.readPolicy != nil
        guard !pages.isEmpty else { throw TransportFailure.closed }
        return pages.removeFirst()
    }
}
