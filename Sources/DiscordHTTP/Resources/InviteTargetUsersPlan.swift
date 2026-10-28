// File: Sources/DiscordHTTP/Resources/InviteTargetUsersPlan.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import DiscordModels
import DiscordTransport

/// Explicit operation performed by a bounded invite target-user plan; no generic mutation batching is implied.
public enum InviteTargetUsersBulkAction: Sendable {
    case add
    case remove
}

/// Finite ordered target-user edits using Discord's documented 1,000-user bulk-add/delete operations.
/// Every chunk uses inviter or MANAGE_GUILD authority, ordinary shared admission and conservative mutation replay.
public struct BulkInviteTargetUsersPlan: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// Effective targets in first-occurrence order after the explicitly chosen duplicate policy.
    public let userIDs: [UserID]
    /// Legal upstream groups, each nonempty and at most 1,000 exact IDs.
    public let chunks: [[UserID]]
    public let action: InviteTargetUsersBulkAction
    private let endpoints: [Endpoint<EmptyResponse>]

    /// Validates and materializes a finite bulk plan without fetching users, starting tasks or executing requests.
    /// - Parameters:
    ///   - code: Exact opaque existing invite code; server permissions/existence remain authoritative.
    ///   - userIDs: 1...100,000 input IDs, a local retained-plan cap; every upstream chunk contains at most 1,000.
    ///   - action: Explicit add or remove operation; a plan never mixes different mutation kinds.
    ///   - deduplicate: False rejects repeated input IDs. True explicitly retains only each ID's first occurrence,
    ///     preserving relative order. This local choice makes repeated targets unambiguous without hidden fetches.
    /// - Throws: Safe invalid-value for illegal input count/duplicates or ordinary body/descriptor errors before I/O.
    /// Construction uses bounded linear time/storage and at most 100 immutable request descriptors.
    public init(code: String, userIDs: [UserID], action: InviteTargetUsersBulkAction, deduplicate: Bool = false) throws {
        guard (1...100_000).contains(userIDs.count) else { throw DiscordError.validation(.invalidValue) }
        var seen = Set<UserID>(), effective: [UserID] = []
        for id in userIDs {
            if seen.insert(id).inserted { effective.append(id) }
            else if !deduplicate { throw DiscordError.validation(.invalidValue) }
        }
        self.userIDs = effective
        self.action = action
        chunks = stride(from: 0, to: effective.count, by: 1_000).map { Array(effective[$0..<min($0 + 1_000, effective.count)]) }
        endpoints = try chunks.map { chunk in
            switch action {
            case .add: try InviteEndpoints.bulkAddTargetUsers(code: code, userIDs: chunk)
            case .remove: try InviteEndpoints.bulkDeleteTargetUsers(code: code, userIDs: chunk)
            }
        }
    }

    /// Executes each legal chunk once in input order, retaining acknowledged progress if later work stops.
    /// - Parameters:
    ///   - context: Shared injected clock, cancellation and optional inclusive overall deadline.
    ///   - execute: Sequential cooperative executor, ordinarily the caller's RESTClient; it must validate the
    ///     descriptor's empty HTTP 204 contract. Shared rate/retry policy applies; ambiguous mutations never replay.
    /// - Returns: Acknowledged effective user IDs in original order after all chunks return empty success.
    ///   Empty acknowledgements do not supply per-user classifications or prove current acceptance-list membership.
    /// - Throws: BulkInviteTargetUsersFailure retaining acknowledged IDs, current entered but unacknowledged IDs,
    ///   never-entered IDs and the original error. Acknowledgement racing with cancellation is retained after
    ///   structured child cleanup. Pre-entry cancellation/deadlines record no attempted IDs. A repeated call
    ///   executes the whole plan again; there is no automatic resume, rollback, reconciliation or fallback.
    /// Work retains bounded progress and never overlaps chunks or starts work after failure.
    public func execute<C: Clock>(context: TransportContext<C>,
        execute: @escaping @Sendable (Endpoint<EmptyResponse>) async throws -> EmptyResponse
    ) async throws -> BulkInviteTargetUsersOutcome where C.Duration == Duration {
        var acknowledgedCount = 0
        for (index, endpoint) in endpoints.enumerated() {
            let chunk = chunks[index], progress = InviteBulkProgress()
            do { try context.check() }
            catch {
                throw BulkInviteTargetUsersFailure(acknowledged: Array(userIDs.prefix(acknowledgedCount)), attempted: [],
                    unattempted: Array(userIDs.dropFirst(acknowledgedCount)), underlying: error)
            }
            do {
                _ = try await context.run {
                    await progress.start()
                    let result = try await execute(endpoint)
                    await progress.acknowledge()
                    return result
                }
                acknowledgedCount += chunk.count
            } catch {
                let state = await progress.snapshot()
                if state.acknowledged { acknowledgedCount += chunk.count }
                let attempted = state.started && !state.acknowledged ? chunk : []
                throw BulkInviteTargetUsersFailure(acknowledged: Array(userIDs.prefix(acknowledgedCount)), attempted: attempted,
                    unattempted: Array(userIDs.dropFirst(acknowledgedCount + attempted.count)), underlying: error)
            }
        }
        return BulkInviteTargetUsersOutcome(acknowledged: userIDs)
    }

    /// Conceals identifiers, invite code and retained descriptors from ordinary diagnostics.
    public var description: String { "BulkInviteTargetUsersPlan(redacted)" }
    /// Uses the same safe debug marker.
    public var debugDescription: String { description }
    /// Prevents reflection from traversing targets or request bodies.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}

/// Acknowledged target-user chunks, in effective input order; no per-user success schema is invented.
public struct BulkInviteTargetUsersOutcome: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let acknowledged: [UserID]

    /// Retains exact IDs whose request group received a valid empty success acknowledgement.
    /// - Parameter acknowledged: Effective plan targets in original first-occurrence order.
    /// Construction performs no I/O or inference about current server membership.
    fileprivate init(acknowledged: [UserID]) { self.acknowledged = acknowledged }
    /// Conceals target identifiers in ordinary interpolation.
    public var description: String { "BulkInviteTargetUsersOutcome(redacted)" }
    /// Uses the same safe debug marker.
    public var debugDescription: String { description }
    /// Prevents reflective traversal of acceptance targets.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}

/// Evidence retained after a plan stops; deliberately inspect properties to reconcile ambiguous submissions.
public struct BulkInviteTargetUsersFailure: Error, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let acknowledged: [UserID]
    public let attempted: [UserID]
    public let unattempted: [UserID]
    public let underlying: any Error

    /// Records exact bounded progress after all owned structured work has ended.
    /// - Parameters:
    ///   - acknowledged: Targets from completed or racing-acknowledged chunks, in plan order.
    ///   - attempted: Entered current chunk without valid acknowledgement; submission/outcome may be indeterminate.
    ///   - unattempted: Effective remaining targets never entered in this invocation.
    ///   - underlying: Original failure, including cancellation/deadline/API or explicit mutation uncertainty.
    /// Construction performs no I/O, string interpolation, retry-safety inference or automatic recovery.
    fileprivate init(acknowledged: [UserID], attempted: [UserID], unattempted: [UserID], underlying: any Error) {
        self.acknowledged = acknowledged; self.attempted = attempted
        self.unattempted = unattempted; self.underlying = underlying
    }
    /// Conceals identifiers and potentially private error messages from ordinary formatting.
    public var description: String { "BulkInviteTargetUsersFailure(redacted)" }
    /// Uses the same safe debug marker.
    public var debugDescription: String { description }
    /// Prevents reflection from exposing targets or underlying error payloads.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}

/// Serializes one chunk's entry/acknowledgement evidence across cancellation/deadline child cleanup.
private actor InviteBulkProgress {
    private var started = false
    private var acknowledged = false

    /// Records executor entry; this alone establishes neither actual submission nor completion.
    func start() { started = true }
    /// Records a complete valid acknowledgement before crossing the structured cancellation boundary.
    func acknowledge() { acknowledged = true }
    /// Reads final evidence after executor and deadline children have terminated.
    /// - Returns: Whether caller execution began and whether it returned a valid acknowledgement.
    func snapshot() -> (started: Bool, acknowledged: Bool) { (started, acknowledged) }
}
