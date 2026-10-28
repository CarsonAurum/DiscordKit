// File: Sources/DiscordHTTP/Resources/LobbyOperations.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import DiscordModels
import DiscordTransport

/// Explicit snapshot comparisons avoid redundant metadata writes without fetching or merging current server state.
public enum LobbyOperations {
    /// Avoids replacing metadata when the caller's exact lobby snapshot already contains the requested value.
    /// - Parameters:
    ///   - current: Caller-owned Lobby; its age and current authorization are unknown.
    ///   - metadata: Absent makes no request; null clears metadata; a dictionary replaces it, including empty.
    /// - Returns: Nil for omitted/equal metadata; otherwise one unsafe bot PATCH containing only metadata.
    /// - Throws: Metadata/body/descriptor validation errors, even for invalid values that would compare equal.
    /// No I/O, merge, background refresh or membership replacement occurs; external changes can race the snapshot.
    public static func modifyMetadataIfChanged(current: Lobby,
        metadata: Field<[String: String]>) throws -> Endpoint<Lobby>? {
        let request = try ModifyLobbyRequest(metadata: metadata)
        guard case .object(let fields) = request.jsonValue(), let value = fields["metadata"],
              current.rawFields["metadata"] != value else { return nil }
        return try LobbyEndpoints.modify(lobbyID: current.id, request: request)
    }

    /// Avoids a member upsert when caller-owned metadata already equals the explicitly requested replacement.
    /// - Parameters:
    ///   - lobbyID: Application-owned lobby containing the supplied member snapshot.
    ///   - current: Caller-owned member; this helper does not infer continued membership or freshness.
    ///   - metadata: Absent makes no request; null clears; a dictionary replaces, including empty.
    /// - Returns: Nil for omitted/equal metadata, otherwise one unsafe bot upsert containing only metadata.
    /// - Throws: Metadata/body/descriptor validation errors before I/O; execution errors belong to the descriptor.
    /// Flags, additional name and other members are not sent. Concurrent changes require caller reconciliation.
    public static func modifyMemberMetadataIfChanged(lobbyID: LobbyID, current: LobbyMember,
        metadata: Field<[String: String]>) throws -> Endpoint<LobbyMember>? {
        let request = try ModifyLobbyMemberRequest(metadata: metadata)
        guard case .object(let fields) = request.jsonValue(), let value = fields["metadata"],
              current.rawFields["metadata"] != value else { return nil }
        return try LobbyEndpoints.addMember(lobbyID: lobbyID, userID: current.id, request: request)
    }
}

/// Finite incremental membership edits using only Discord's documented 25-member bulk operation.
/// Chunks run sequentially, preserving input order and explicit upsert/removal intent without replacement lists.
public struct BulkLobbyMembersPlan: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// Exact unique incremental edits in caller order, retained without normalization or deduplication.
    public let members: [BulkLobbyMemberRequest]
    /// Legal sequential request groups, each containing 1...25 edits in caller order.
    public let chunks: [[BulkLobbyMemberRequest]]
    private let endpoints: [Endpoint<[LobbyMember]>]

    /// Validates and materializes bounded legal chunks without executing requests or creating tasks.
    /// - Parameters:
    ///   - lobbyID: Application-owned lobby; Discord verifies ownership, user eligibility and limits upstream.
    ///   - members: 1...10,000 unique users with explicit incremental edits. Duplicate IDs are rejected globally
    ///     because repeated upserts/removals make silent-drop and partial-progress correlation ambiguous.
    /// - Throws: Invalid-value for empty/oversized/duplicate input, or body/descriptor validation errors before I/O.
    /// Time/storage are linear in bounded input; at most 400 descriptors are retained. No write executes here.
    public init(lobbyID: LobbyID, members: [BulkLobbyMemberRequest]) throws {
        guard (1...10_000).contains(members.count), Set(members.map(\.id)).count == members.count
        else { throw DiscordError.validation(.invalidValue) }
        self.members = members
        chunks = stride(from: 0, to: members.count, by: 25).map { Array(members[$0..<min($0 + 25, members.count)]) }
        endpoints = try chunks.map { try LobbyEndpoints.bulkUpdateMembers(lobbyID: lobbyID, request: .init(members: $0)) }
    }

    /// Executes legal chunks once in order, retaining correlated acknowledgements if later work stops.
    /// - Parameters:
    ///   - context: Shared injected clock, cooperative cancellation and optional inclusive overall deadline.
    ///   - execute: Sequential cooperative executor, ordinarily the shared RESTClient. Each returned array is
    ///     revalidated against its submitted chunk, including when a custom executor bypasses descriptor decoding.
    /// - Returns: Upserted members, silently dropped upsert IDs and acknowledged removals, each in input order.
    ///   Removal acknowledgements have no per-user result; they do not prove a current membership snapshot.
    /// - Throws: BulkLobbyMembersFailure with acknowledged progress, entered/unacknowledged IDs, never-entered
    ///   IDs and the original cause. Malformed acknowledgements leave the current chunk unacknowledged.
    /// Racing valid acknowledgements survive cancellation/deadline cleanup. No retries of dropped users,
    /// rollback, fallback, hidden fetch, automatic resume or ambiguous mutation replay occurs. Repeating this
    /// method explicitly executes the complete plan again. No chunk overlaps another or starts after failure.
    public func execute<C: Clock>(context: TransportContext<C>,
        execute: @escaping @Sendable (Endpoint<[LobbyMember]>) async throws -> [LobbyMember]
    ) async throws -> BulkLobbyMembersOutcome where C.Duration == Duration {
        var upserted: [LobbyMember] = [], dropped: [UserID] = [], removed: [UserID] = []
        var acknowledgedCount = 0
        for (index, endpoint) in endpoints.enumerated() {
            let chunk = chunks[index], progress = LobbyBulkProgress()
            do {
                try context.check()
                let result = try await context.run {
                    await progress.start()
                    let returned = try await execute(endpoint)
                    let result = try correlateLobbyMembers(chunk, returned: returned)
                    await progress.acknowledge(result)
                    return result
                }
                upserted += result.upserted; dropped += result.dropped; removed += result.removed
                acknowledgedCount += chunk.count
            } catch {
                let state = await progress.snapshot()
                if let result = state.result {
                    upserted += result.upserted; dropped += result.dropped; removed += result.removed
                    acknowledgedCount += chunk.count
                }
                let attempted = state.started && state.result == nil ? chunk.map(\.id) : []
                throw BulkLobbyMembersFailure(upserted: upserted, dropped: dropped, removed: removed,
                    attempted: attempted, unattempted: members.dropFirst(acknowledgedCount + attempted.count).map(\.id),
                    underlying: error)
            }
        }
        return BulkLobbyMembersOutcome(upserted: upserted, dropped: dropped, removed: removed)
    }

    /// Conceals user identifiers, metadata and retained bodies from ordinary diagnostics.
    public var description: String { "BulkLobbyMembersPlan(redacted)" }
    /// Returns the same safe marker for debug formatting.
    public var debugDescription: String { description }
    /// Prevents recursive reflection from exposing requests or members.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}

/// Correlated acknowledged bulk results in original input order, without assumptions about wire result ordering.
public struct BulkLobbyMembersOutcome: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// Members actually returned by acknowledged chunks, correlated into caller order.
    public let upserted: [LobbyMember]
    /// Acknowledged upsert targets omitted upstream; no individual rejection reason is available.
    public let dropped: [UserID]
    /// Removal targets whose chunks were acknowledged, without individual current-membership evidence.
    public let removed: [UserID]

    /// Records one immutable bounded acknowledgement without inferring present membership or retry eligibility.
    /// - Parameters:
    ///   - upserted: Members actually returned for submitted upserts, correlated into input order.
    ///   - dropped: Submitted upsert IDs missing from a valid response; the server supplies no individual reason.
    ///   - removed: Submitted removal IDs from acknowledged chunks; removals are intentionally absent on the wire.
    fileprivate init(upserted: [LobbyMember], dropped: [UserID], removed: [UserID]) {
        self.upserted = upserted; self.dropped = dropped; self.removed = removed
    }
    /// Conceals identifiers and metadata from ordinary interpolation.
    public var description: String { "BulkLobbyMembersOutcome(redacted)" }
    /// Returns the same safe debug marker.
    public var debugDescription: String { description }
    /// Prevents recursive reflective traversal of returned member metadata.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}

/// Explicit progress after a stopped bulk plan; inspect properties deliberately to reconcile uncertain submissions.
public struct BulkLobbyMembersFailure: Error, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// Valid returned upserts from prior or racing-acknowledged chunks, in caller order.
    public let upserted: [LobbyMember]
    /// Silent upsert omissions from valid acknowledged chunks; these are never automatically retried.
    public let dropped: [UserID]
    /// Explicit removal targets from acknowledged chunks, without an invented per-user response.
    public let removed: [UserID]
    /// Entered current-chunk targets lacking a valid acknowledgement; submission/outcome may be unknown.
    public let attempted: [UserID]
    /// Remaining targets never entered during this execution, in caller order.
    public let unattempted: [UserID]
    /// Original execution cause retained for deliberate inspection; ordinary diagnostics redact it.
    public let underlying: any Error

    /// Retains bounded exact progress after all owned structured children finish cleanup.
    /// - Parameters:
    ///   - upserted: Returned members from prior or racing-acknowledged chunks, in input order.
    ///   - dropped: Silently omitted upserts from those valid acknowledgements, with no invented failure reason.
    ///   - removed: Explicit removal targets from acknowledged chunks, without per-user response evidence.
    ///   - attempted: Current entered chunk without a valid acknowledgement; submission/outcome may be unknown.
    ///   - unattempted: Remaining targets never entered during this execution.
    ///   - underlying: Exact API/transport/uncertainty/cancellation/deadline cause, never interpolated in diagnostics.
    fileprivate init(upserted: [LobbyMember], dropped: [UserID], removed: [UserID], attempted: [UserID],
                     unattempted: [UserID], underlying: any Error) {
        self.upserted = upserted; self.dropped = dropped; self.removed = removed
        self.attempted = attempted; self.unattempted = unattempted; self.underlying = underlying
    }
    /// Conceals identifiers and potentially private underlying error messages.
    public var description: String { "BulkLobbyMembersFailure(redacted)" }
    /// Returns the same safe debug marker.
    public var debugDescription: String { description }
    /// Prevents reflection from exposing progress or raw errors.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}

/// Validates a bulk acknowledgement and restores input correlation without inventing ordering guarantees.
/// - Parameters:
///   - submitted: Unique legal request chunk, at most 25 edits.
///   - returned: Upstream upserts, potentially empty or silently incomplete, in arbitrary wire order.
/// - Returns: Disjoint returned/dropped/removed classifications, preserving each class's input order.
/// - Throws: Invalid-response for duplicate, foreign or explicitly removed returned user IDs.
private func correlateLobbyMembers(_ submitted: [BulkLobbyMemberRequest], returned: [LobbyMember]) throws -> BulkLobbyMembersOutcome {
    let permitted = Set(submitted.filter { $0.removeMember != true }.map(\.id))
    var byID: [UserID: LobbyMember] = [:]
    for member in returned {
        guard permitted.contains(member.id), byID.updateValue(member, forKey: member.id) == nil
        else { throw DiscordError.transport(.invalidResponse) }
    }
    return BulkLobbyMembersOutcome(upserted: submitted.compactMap { byID[$0.id] },
        dropped: submitted.filter { $0.removeMember != true && byID[$0.id] == nil }.map(\.id),
        removed: submitted.filter { $0.removeMember == true }.map(\.id))
}

/// Serializes one chunk's entry and correlated acknowledgement across structured cancellation cleanup.
private actor LobbyBulkProgress {
    private var started = false
    private var result: BulkLobbyMembersOutcome?
    /// Records entry into caller execution; no submission or completion guarantee is inferred.
    func start() { started = true }
    /// Records valid correlated progress before crossing the structured cancellation boundary.
    /// - Parameter result: Acknowledged classifications for this chunk, including silent drops.
    func acknowledge(_ result: BulkLobbyMembersOutcome) { self.result = result }
    /// Reads final evidence after the operation/deadline children terminate.
    /// - Returns: Whether caller execution started and any validated acknowledgement received.
    func snapshot() -> (started: Bool, result: BulkLobbyMembersOutcome?) { (started, result) }
}
