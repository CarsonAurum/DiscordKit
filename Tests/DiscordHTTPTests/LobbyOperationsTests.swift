// File: Tests/DiscordHTTPTests/LobbyOperationsTests.swift
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

/// Explicit metadata reduction and bounded incremental membership workflows retain exact acknowledged progress.
@Suite(.timeLimit(.minutes(1))) struct LobbyOperationsTests {
    /// Snapshot comparisons preserve absent/null/empty semantics and never replace membership or unrelated fields.
    /// Invalid metadata is rejected before a no-op comparison can suppress validation.
    /// - Throws: Unexpected valid fixture/request errors fail the test; invalid lengths are asserted.
    @Test func metadataSnapshots() throws {
        let lobby = try Lobby(data: Data(#"{"id":"4","application_id":"5","metadata":{"k":"v"},"members":[]}"#.utf8))
        let member = try LobbyMember(data: Data(#"{"id":"6","metadata":{"k":"v"},"flags":1,"additional_name":"P"}"#.utf8))
        #expect(try LobbyOperations.modifyMetadataIfChanged(current: lobby, metadata: .absent) == nil)
        #expect(try LobbyOperations.modifyMetadataIfChanged(current: lobby, metadata: .value(["k": "v"])) == nil)
        #expect(try LobbyOperations.modifyMemberMetadataIfChanged(lobbyID: lobby.id, current: member, metadata: .absent) == nil)
        #expect(try LobbyOperations.modifyMemberMetadataIfChanged(lobbyID: lobby.id, current: member, metadata: .value(["k": "v"])) == nil)
        for metadata: Field<[String: String]> in [.null, .value([:]), .value(["k": "changed"])] {
            let request = try #require(try LobbyOperations.modifyMetadataIfChanged(current: lobby, metadata: metadata))
            let memberRequest = try #require(try LobbyOperations.modifyMemberMetadataIfChanged(lobbyID: lobby.id, current: member, metadata: metadata))
            #expect(request.method == "PATCH" && request.path == ["lobbies", "4"] && request.retrySafety == .unsafe)
            #expect(memberRequest.method == "PUT" && memberRequest.path == ["lobbies", "4", "members", "6"])
            #expect(try JSONValue.parse(#require(request.body?.bytes)) == ModifyLobbyRequest(metadata: metadata).jsonValue())
            #expect(try JSONValue.parse(#require(memberRequest.body?.bytes)) == ModifyLobbyMemberRequest(metadata: metadata).jsonValue())
        }
        let nullLobby = try Lobby(data: Data(#"{"id":"4","application_id":"5","metadata":null,"members":[]}"#.utf8))
        let nullMember = try LobbyMember(data: Data(#"{"id":"6","metadata":null}"#.utf8))
        let absentMember = try LobbyMember(data: Data(#"{"id":"6"}"#.utf8))
        #expect(try LobbyOperations.modifyMetadataIfChanged(current: nullLobby, metadata: .null) == nil)
        #expect(try LobbyOperations.modifyMemberMetadataIfChanged(lobbyID: lobby.id, current: nullMember, metadata: .null) == nil)
        #expect(try LobbyOperations.modifyMemberMetadataIfChanged(lobbyID: lobby.id, current: absentMember, metadata: .null) != nil)
        let emptyLobby = try Lobby(data: Data(#"{"id":"4","application_id":"5","metadata":{},"members":[]}"#.utf8))
        let emptyMember = try LobbyMember(data: Data(#"{"id":"6","metadata":{}}"#.utf8))
        #expect(try LobbyOperations.modifyMetadataIfChanged(current: emptyLobby, metadata: .value([:])) == nil)
        #expect(try LobbyOperations.modifyMemberMetadataIfChanged(lobbyID: lobby.id, current: emptyMember, metadata: .value([:])) == nil)
        let bad: Field<[String: String]> = .value(["k": String(repeating: "x", count: 1_000)])
        #expect(throws: DiscordError.validation(.invalidValue)) { try LobbyOperations.modifyMetadataIfChanged(current: lobby, metadata: bad) }
        #expect(throws: DiscordError.validation(.invalidValue)) {
            try LobbyOperations.modifyMemberMetadataIfChanged(lobbyID: lobby.id, current: member, metadata: bad)
        }
        let oversized = String(repeating: "x", count: 1_000)
        let invalidCurrent = try Lobby(data: Data("{\"id\":\"4\",\"application_id\":\"5\",\"metadata\":{\"k\":\"\(oversized)\"},\"members\":[]}".utf8))
        #expect(throws: DiscordError.validation(.invalidValue)) {
            try LobbyOperations.modifyMetadataIfChanged(current: invalidCurrent, metadata: bad)
        }
    }

    /// Exact legal chunks span single, upstream-boundary and maximum retained-plan sizes without lost/duplicate edits.
    /// Reverse wire-order acknowledgements are restored to input order; silent omissions and removals stay distinct.
    /// - Parameter count: Selected local/remote chunk boundaries, including the 10,000-item local cap.
    /// - Throws: Unexpected setup, body, model or execution failures fail the test.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [1, 25, 26, 51, 10_000]) func legalChunks(count: Int) async throws {
        let members = try Self.members(count)
        let plan = try BulkLobbyMembersPlan(lobbyID: .init(rawValue: 4), members: members)
        #expect(plan.members.map(\.id) == members.map(\.id))
        #expect(plan.chunks.flatMap { $0 }.map(\.id) == members.map(\.id))
        #expect(plan.chunks.count == (count + 24) / 25 && plan.chunks.allSatisfy { (1...25).contains($0.count) })
        let script = LobbyBulkScript()
        let result = try await plan.execute(context: .init(clock: ManualClock())) { try await script.next($0) }
        #expect(result.upserted.map(\.id) == members.filter { $0.removeMember != true && $0.id.rawValue % 3 != 0 }.map(\.id))
        #expect(result.dropped == members.filter { $0.removeMember != true && $0.id.rawValue % 3 == 0 }.map(\.id))
        #expect(result.removed == members.filter { $0.removeMember == true }.map(\.id))
        #expect(await script.calls == plan.chunks.count)
        #expect(await script.ids == members.map(\.id))
        #expect(plan.description == plan.debugDescription && plan.customMirror.children.count == 1)
        #expect(result.description == result.debugDescription && result.customMirror.children.count == 1)
        #expect(!String(reflecting: plan).contains("private-value") && !String(reflecting: result).contains("private-value"))
        #expect(result == result)
    }

    /// Empty/oversized plans and globally repeated IDs are rejected before any descriptor can execute.
    /// Contradictory repeated upsert/removal intents are rejected rather than silently merged.
    /// - Throws: Unexpected valid fixture errors fail the test; illegal plan construction is asserted.
    @Test func invalidPlans() throws {
        let one = try BulkLobbyMemberRequest(id: .init(rawValue: 1))
        for edits in [[], [one, one], Array(repeating: one, count: 10_001),
            try [one, .init(id: one.id, removeMember: true)]] {
            #expect(throws: DiscordError.validation(.invalidValue)) { try BulkLobbyMembersPlan(lobbyID: .init(rawValue: 1), members: edits) }
        }
        let members = try Self.members(26)
        let acrossChunks = members + [members[0]]
        #expect(throws: DiscordError.validation(.invalidValue)) {
            try BulkLobbyMembersPlan(lobbyID: .init(rawValue: 1), members: acrossChunks)
        }
    }

    /// A rejected, malformed or indeterminate second chunk preserves the first and never enters the third.
    /// Missing upserts in acknowledged chunks remain dropped evidence, distinct from attempted unknown outcomes.
    /// - Parameter failure: Exact injected API, transport/schema or uncertain-mutation category.
    /// - Throws: Unexpected fixture failures fail the test; stopped-plan progress and original cause are asserted.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [DiscordError.api(status: 403, code: 50013), .transport(.invalidResponse), .unknownMutationOutcome(.connectionLostAfterSubmission)])
    func partialFailure(failure: DiscordError) async throws {
        let members = try Self.members(51), script = LobbyBulkScript(failure: failure, failOnCall: 2)
        let plan = try BulkLobbyMembersPlan(lobbyID: .init(rawValue: 4), members: members)
        do {
            _ = try await plan.execute(context: .init(clock: ManualClock())) { try await script.next($0) }
            Issue.record("Expected stopped plan")
        } catch let error as BulkLobbyMembersFailure {
            let first = members.prefix(25)
            #expect(error.upserted.map(\.id) == first.filter { $0.removeMember != true && $0.id.rawValue % 3 != 0 }.map(\.id))
            #expect(error.dropped == first.filter { $0.removeMember != true && $0.id.rawValue % 3 == 0 }.map(\.id))
            #expect(error.removed == first.filter { $0.removeMember == true }.map(\.id))
            #expect(error.attempted == members[25..<50].map(\.id) && error.unattempted == [members[50].id])
            #expect(error.underlying as? DiscordError == failure)
            #expect(error.description == error.debugDescription && error.customMirror.children.count == 1)
            #expect(!String(reflecting: error).contains("private-value"))
        }
        #expect(await script.calls == 2)
        #expect(await script.active == 0)
    }

    /// Custom executors cannot bypass identity correlation by returning duplicate, removed or foreign users.
    /// No invalid acknowledgement is committed as successful progress, even when HTTP status is unavailable.
    /// - Parameter ids: One invalid returned identity set for a two-edit chunk.
    /// - Throws: Unexpected fixture errors fail the test; exact unacknowledged progress is asserted.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [[1, 1], [2], [9]]) func corruptCustomAcknowledgement(ids: [Int]) async throws {
        let edits = try [BulkLobbyMemberRequest(id: .init(rawValue: 1)), .init(id: .init(rawValue: 2), removeMember: true)]
        let returned = try ids.map { try LobbyMember(data: Data("{\"id\":\"\($0)\"}".utf8)) }
        let plan = try BulkLobbyMembersPlan(lobbyID: .init(rawValue: 4), members: edits)
        do {
            _ = try await plan.execute(context: .init(clock: ManualClock())) { _ in returned }
            Issue.record("Expected invalid response")
        } catch let error as BulkLobbyMembersFailure {
            #expect(error.upserted.isEmpty && error.dropped.isEmpty && error.removed.isEmpty)
            #expect(error.attempted == edits.map(\.id) && error.unattempted.isEmpty)
            #expect(error.underlying as? DiscordError == .transport(.invalidResponse))
        }
    }

    /// Pre-entry cancellation/deadlines record no attempts, while valid racing acknowledgements survive cleanup.
    /// - Throws: Unexpected fixture errors fail the test; all expected stopped-plan categories are inspected.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func preEntryAndRacingCancellation() async throws {
        let edits = try [BulkLobbyMemberRequest(id: .init(rawValue: 1), removeMember: true)]
        let plan = try BulkLobbyMembersPlan(lobbyID: .init(rawValue: 4), members: edits), clock = ManualClock()
        do {
            _ = try await plan.execute(context: .init(clock: clock, deadline: clock.now)) { _ in Issue.record("Expired execution"); return [] }
            Issue.record("Expected deadline")
        } catch let error as BulkLobbyMembersFailure {
            #expect(error.attempted.isEmpty && error.unattempted == edits.map(\.id) && error.removed.isEmpty)
            #expect(error.underlying as? TransportFailure == .deadlineExceeded)
        }
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await plan.execute(context: .init(clock: clock)) { _ in Issue.record("Cancelled execution"); return [] }
        }
        do { _ = try await cancelled.value; Issue.record("Expected cancellation") }
        catch let error as BulkLobbyMembersFailure {
            #expect(error.attempted.isEmpty && error.unattempted == edits.map(\.id) && error.removed.isEmpty)
            #expect(error.underlying is CancellationError)
        }
        let racing = Task {
            try await plan.execute(context: .init(clock: clock)) { _ in
                withUnsafeCurrentTask { $0?.cancel() }
                return []
            }
        }
        do { _ = try await racing.value; Issue.record("Expected racing cancellation") }
        catch let error as BulkLobbyMembersFailure {
            #expect(error.removed == edits.map(\.id) && error.attempted.isEmpty && error.unattempted.isEmpty)
            #expect(error.underlying is CancellationError)
        }
    }

    /// Suspended cancellation and deadline expiration release executor children before returning progress evidence.
    /// - Parameter expires: True expires first chunk; false cancels second after one acknowledged chunk.
    /// - Throws: Unexpected fixtures/barriers/clock failures fail the test; stopped progress and cleanup are asserted.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [false, true]) func suspendedTermination(expires: Bool) async throws {
        let edits = try Self.members(expires ? 26 : 51), entered = TestBarrier(), timer = TestBarrier()
        let gate = TestBarrier(onWaitScheduled: { entered.open() }), clock = ManualClock(onSleepScheduled: { timer.open() })
        let script = LobbyBulkScript(gate: gate, suspendOnCall: expires ? 1 : 2)
        let plan = try BulkLobbyMembersPlan(lobbyID: .init(rawValue: 4), members: edits)
        let context = TransportContext(clock: clock, deadline: expires ? clock.now.advanced(by: .seconds(1)) : nil)
        let task = Task { try await plan.execute(context: context) { try await script.next($0) } }
        try await entered.wait()
        if expires { try await timer.wait(); try clock.advance(by: .seconds(1)) } else { task.cancel() }
        do { _ = try await task.value; Issue.record("Expected suspension termination") }
        catch let error as BulkLobbyMembersFailure {
            let offset = expires ? 0 : 25
            #expect(error.attempted == edits[offset..<(offset + 25)].map(\.id) && error.unattempted == [edits.last!.id])
            #expect(error.upserted.count + error.dropped.count + error.removed.count == offset)
            if expires { #expect(error.underlying as? TransportFailure == .deadlineExceeded) }
            else { #expect(error.underlying is CancellationError) }
        }
        #expect(await script.active == 0)
        #expect(await script.calls == (expires ? 1 : 2))
        #expect(gate.waitingCount == 0 && clock.pendingSleepCount == 0)
    }

    /// Concurrent independent executions share immutable descriptors while retaining independent progress and outcomes.
    /// A caller who executes twice explicitly submits twice; plans do not hide resumptions or shared mutable state.
    /// - Throws: Unexpected setup or either execution failure fails the test.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func concurrentIndependentExecutions() async throws {
        let edits = try Self.members(26), plan = try BulkLobbyMembersPlan(lobbyID: .init(rawValue: 4), members: edits)
        let first = LobbyBulkScript(), second = LobbyBulkScript()
        async let a = plan.execute(context: .init(clock: ManualClock())) { try await first.next($0) }
        async let b = plan.execute(context: .init(clock: ManualClock())) { try await second.next($0) }
        #expect(try await a == b)
        #expect(await first.calls == 2)
        #expect(await second.calls == 2)
    }

    /// Creates deterministic mixed upsert/removal inputs with optional metadata, preserving exact numeric identities.
    /// - Parameter count: Positive bounded fixture count chosen by a test.
    /// - Returns: Unique increasing IDs; every fifth is a removal and every third remaining upsert is omitted by script.
    /// - Throws: Request validation errors if fixture metadata or identity construction becomes invalid.
    private static func members(_ count: Int) throws -> [BulkLobbyMemberRequest] {
        try (1...count).map { try .init(id: .init(rawValue: UInt64($0)), metadata: .value(["k": "private-value"]), removeMember: $0 % 5 == 0) }
    }
}

/// Deterministic sequential executor verifies legal request groups and injects response omissions/failures/suspension.
@available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
private actor LobbyBulkScript {
    private let failure: DiscordError?
    private let failOnCall: Int?
    private let gate: TestBarrier?
    private let suspendOnCall: Int?
    private(set) var calls = 0
    private(set) var active = 0
    private(set) var ids: [UserID] = []

    /// Configures optional one-call failure and cancellation-cooperative gate without creating tasks.
    /// - Parameters:
    ///   - failure: Exact cause thrown on failOnCall; nil disables thrown injection.
    ///   - failOnCall: One-based index of injected failure, nil never fails.
    ///   - gate: Optional externally owned deterministic suspension barrier.
    ///   - suspendOnCall: One-based gate index, nil never suspends.
    init(failure: DiscordError? = nil, failOnCall: Int? = nil, gate: TestBarrier? = nil, suspendOnCall: Int? = nil) {
        self.failure = failure; self.failOnCall = failOnCall; self.gate = gate; self.suspendOnCall = suspendOnCall
    }

    /// Validates the actual root array, removes scripted omissions/removals and reverses acknowledged wire order.
    /// - Parameter endpoint: One planned bulk endpoint with at most 25 explicit incremental member edits.
    /// - Returns: Production-decoded acknowledged upserts in intentionally reversed wire order.
    /// - Throws: Configured failure, cancellation or malformed fixture/body errors; defer closes active accounting.
    func next(_ endpoint: Endpoint<[LobbyMember]>) async throws -> [LobbyMember] {
        calls += 1; active += 1
        defer { active -= 1 }
        #expect(active == 1 && endpoint.method == "POST" && endpoint.retrySafety == .unsafe && endpoint.bulk?.maximumItems == 25)
        guard case .array(let values) = try JSONValue.parse(#require(endpoint.body?.bytes))
        else { throw DiscordError.transport(.invalidResponse) }
        #expect((1...25).contains(values.count))
        var returned: [JSONValue] = []
        for value in values {
            guard case .object(let fields) = value, case .string(let raw) = fields["id"], let number = UInt64(raw)
            else { throw DiscordError.transport(.invalidResponse) }
            ids.append(.init(rawValue: number))
            if fields["remove_member"] != .bool(true), number % 3 != 0 { returned.append(.object(["id": .string(raw)])) }
        }
        if calls == suspendOnCall { try await gate?.wait() }
        if calls == failOnCall, let failure { throw failure }
        return try endpoint.decode(JSONValue.array(Array(returned.reversed())).serialized())
    }
}
