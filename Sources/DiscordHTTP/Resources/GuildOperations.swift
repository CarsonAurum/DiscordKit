// File: Sources/DiscordHTTP/Resources/GuildOperations.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import DiscordModels
import DiscordTransport

/// Finite, pull-driven guild workflows using the caller's shared HTTP authority.
/// Executors run sequentially and must cooperate with cancellation. There is no prefetch,
/// automatic profile hydration, mutation retry, or background reconciliation.
public enum GuildOperations {
    /// Enumerates members using exclusive ascending user IDs and the application's GUILD_MEMBERS eligibility.
    /// - Parameters:
    ///   - guildID: Guild whose visible membership is enumerated; server authorization remains authoritative.
    ///   - after: Optional initial exclusive user ID, preserved without floating-point conversion.
    ///   - limit: Requested and accepted page bound, 1...1,000; defaults to 1,000.
    ///   - maximumPages: Finite request budget, 1...10,000; defaults to 10,000.
    ///   - context: Injected clock, cancellation and optional inclusive overall deadline.
    ///   - execute: Sequential cooperative executor called only on demand; reuse is disabled.
    /// - Returns: Lazy pages, including a terminal empty page. Short pages continue; early stopping starts no next request.
    /// - Throws: Invalid configuration before I/O; execution, cancellation, deadline or page-budget failures
    ///   during iteration. Oversized pages, missing user IDs, duplicates and nonascending IDs fail with
    ///   invalid-response, permanently finishing that iterator. Concurrent server changes can affect traversal.
    public static func memberPages<C: Clock>(
        guildID: GuildID, after: UserID? = nil, limit: Int = 1_000, maximumPages: Int = 10_000,
        context: TransportContext<C>, execute: @escaping @Sendable (Endpoint<[GuildMember]>) async throws -> [GuildMember]
    ) throws -> CursorPagination<GuildMember, UserID, C> where C.Duration == Duration {
        try guildPageConfiguration(limit: limit, maximumPages: maximumPages)
        return try CursorPagination(initialCursor: after, maximumPages: maximumPages, context: context) { cursor in
            let members = try await execute(GuildEndpoints.members(guildID: guildID, after: cursor, limit: limit, readPolicy: nil))
            guard members.count <= limit else { throw DiscordError.transport(.invalidResponse) }
            var previous = cursor
            for member in members {
                guard case .value(let user) = member.user, previous.map({ user.id > $0 }) ?? true
                else { throw DiscordError.transport(.invalidResponse) }
                previous = user.id
            }
            return CursorPage(items: members, nextCursor: members.isEmpty ? nil : previous)
        }
    }

    /// Enumerates bans in documented ascending user-ID order using only the after cursor.
    /// - Parameters:
    ///   - guildID: Guild requiring BAN_MEMBERS or VIEW_AUDIT_LOG; Discord checks permission for every request.
    ///   - after: Optional exclusive initial user ID; nil starts at the beginning.
    ///   - limit: Requested/accepted page bound, 1...1,000; defaults to 1,000.
    ///   - maximumPages: Finite page/request budget, 1...10,000; defaults to 10,000.
    ///   - context: Shared monotonic clock, cancellation and optional inclusive deadline.
    ///   - execute: Sequential cooperative executor; descriptors disable read reuse and never prefetch.
    /// - Returns: Lazy ordered ban pages until an empty response; short pages continue. Each iterator owns its progress.
    /// - Throws: Invalid configuration before I/O; original executor/cancellation/deadline/budget errors later,
    ///   or invalid-response for oversized, duplicate, out-of-order or nonadvancing IDs. All failures finish
    ///   the iterator permanently. Ban changes during traversal can affect coverage; no snapshot is promised.
    public static func banPages<C: Clock>(
        guildID: GuildID, after: UserID? = nil, limit: Int = 1_000, maximumPages: Int = 10_000,
        context: TransportContext<C>, execute: @escaping @Sendable (Endpoint<[GuildBan]>) async throws -> [GuildBan]
    ) throws -> CursorPagination<GuildBan, UserID, C> where C.Duration == Duration {
        try guildPageConfiguration(limit: limit, maximumPages: maximumPages)
        return try CursorPagination(initialCursor: after, maximumPages: maximumPages, context: context) { cursor in
            let bans = try await execute(GuildEndpoints.bans(guildID: guildID, after: cursor, limit: limit, readPolicy: nil))
            guard bans.count <= limit else { throw DiscordError.transport(.invalidResponse) }
            var previous = cursor
            for ban in bans {
                guard previous.map({ ban.user.id > $0 }) ?? true else { throw DiscordError.transport(.invalidResponse) }
                previous = ban.user.id
            }
            return CursorPage(items: bans, nextCursor: bans.isEmpty ? nil : previous)
        }
    }

    /// Avoids a guild PATCH when all explicitly requested fields equal the caller's snapshot.
    /// - Parameters:
    ///   - current: Caller-owned Guild snapshot; no freshness or current authority is inferred.
    ///   - request: Validated settings, with omission distinct from explicit null. Empty settings are a no-op.
    ///   - auditReason: Optional reason validated only when a mutation descriptor is needed.
    /// - Returns: Nil for matching requested fields; otherwise one ordinary unsafe guild PATCH. No I/O occurs here.
    /// - Throws: Invalid-value for an incompatible request root or ordinary descriptor/audit errors.
    ///   A stale snapshot carries the usual reconciliation race and must not be treated as authorization.
    public static func modifyIfChanged(current: Guild, request: GuildModify,
                                       auditReason: String? = nil) throws -> Endpoint<Guild>? {
        guard case .object(let fields) = request.jsonValue() else { throw DiscordError.validation(.invalidValue) }
        guard fields.contains(where: { current.rawFields[$0.key] != $0.value }) else { return nil }
        return try GuildEndpoints.modify(guildID: current.id, request: request, auditReason: auditReason)
    }

    /// Avoids a role PATCH when every explicit field matches a caller-owned role snapshot.
    /// - Parameters:
    ///   - guildID: Owning guild; Discord validates membership, hierarchy and MANAGE_ROLES at execution.
    ///   - current: Snapshot to compare, including exact raw fields; absent and null remain different.
    ///   - request: Validated role edits; omitted fields do not participate in comparison.
    ///   - auditReason: Optional supported reason, checked only when an edit is needed.
    /// - Returns: Nil for a no-op, or one unsafe descriptor. No read, write or related-resource fetch occurs.
    /// - Throws: Invalid-value for an incompatible request root or descriptor/audit validation errors.
    ///   External changes can race this comparison; repeating the method does not guarantee idempotence.
    public static func modifyRoleIfChanged(guildID: GuildID, current: GuildRole, request: GuildRoleModify,
                                           auditReason: String? = nil) throws -> Endpoint<GuildRole>? {
        guard case .object(let fields) = request.jsonValue() else { throw DiscordError.validation(.invalidValue) }
        guard fields.contains(where: { current.rawFields[$0.key] != $0.value }) else { return nil }
        return try GuildEndpoints.modifyRole(guildID: guildID, roleID: current.id, request: request, auditReason: auditReason)
    }
}

/// Bounds cursor history, accepted response size and requests without allocating work per member.
/// - Parameters:
///   - limit: Inclusive page bound in 1...1,000.
///   - maximumPages: Inclusive total page/request bound in 1...10,000.
/// - Throws: Safe invalid-value for either invalid bound; no I/O or state changes occur.
func guildPageConfiguration(limit: Int, maximumPages: Int) throws {
    guard (1...1_000).contains(limit), (1...10_000).contains(maximumPages)
    else { throw DiscordError.validation(.invalidValue) }
}

/// Explicit ordered bulk-ban planning with legal 200-user chunks and bounded retained progress.
/// Requires BAN_MEMBERS and MANAGE_GUILD. HTTP 200 may contain failed users; already banned users
/// can appear among failures. This workflow never retries failed users or silently falls back to single bans.
public struct BulkGuildBanPlan: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let userIDs: [UserID]
    public let chunks: [[UserID]]
    private let endpoints: [Endpoint<GuildBulkBanResult>]

    /// Validates all input before constructing sequential bulk-ban requests without executing any.
    /// - Parameters:
    ///   - guildID: Exact guild major-rate partition; server permissions/hierarchy remain authoritative.
    ///   - userIDs: 1...10,000 distinct users in caller order. The 10,000 limit is a local plan bound;
    ///     each upstream request contains at most 200 users. No input is silently dropped.
    ///   - deleteMessageSeconds: Optional message deletion age, 0...604,800 seconds; nil preserves default zero.
    ///   - auditReason: Optional reason, at most 512 Unicode scalars, validated by descriptors.
    /// - Throws: Safe count/duplicate/deletion-window or descriptor validation errors before I/O.
    ///   Construction time and storage are linear in the bounded input count, with at most 50 descriptors.
    public init(guildID: GuildID, userIDs: [UserID], deleteMessageSeconds: Int? = nil, auditReason: String? = nil) throws {
        guard (1...10_000).contains(userIDs.count), Set(userIDs).count == userIDs.count
        else { throw DiscordError.validation(.invalidValue) }
        let chunks = stride(from: 0, to: userIDs.count, by: 200).map { Array(userIDs[$0..<min($0 + 200, userIDs.count)]) }
        self.userIDs = userIDs
        self.chunks = chunks
        self.endpoints = try chunks.map { try GuildEndpoints.bulkBan(guildID: guildID,
            request: GuildBulkBan(userIDs: $0, deleteMessageSeconds: deleteMessageSeconds.map { .value($0) } ?? .absent),
            auditReason: auditReason) }
    }

    /// Executes each planned chunk once, preserving successes and explicit failures independently.
    /// - Parameters:
    ///   - context: Shared clock, cancellation and optional inclusive overall deadline.
    ///   - execute: Cooperative sequential executor sharing ordinary rate admission and conservative replay policy.
    /// - Returns: Banned and failed users in original input order after every chunk is acknowledged.
    /// - Throws: `BulkGuildBanFailure` retaining acknowledged successes/failures, current attempted users,
    ///   never-attempted users and the original error. A response must classify every requested user exactly
    ///   once and contain no other ID; malformed correlation fails safely with the entire current chunk
    ///   attempted. Cancellation before entry records no attempted users. Cancellation racing with a valid
    ///   acknowledgement preserves that result after structured child cleanup. A repeated invocation starts
    ///   the whole plan again; no resume, rollback, task fan-out or generic mutation packing is implied.
    public func execute<C: Clock>(context: TransportContext<C>,
        execute: @escaping @Sendable (Endpoint<GuildBulkBanResult>) async throws -> GuildBulkBanResult
    ) async throws -> BulkGuildBanOutcome where C.Duration == Duration {
        var banned: [UserID] = [], failed: [UserID] = []
        var completedCount = 0
        for (index, endpoint) in endpoints.enumerated() {
            let progress = GuildBanProgress()
            let chunk = chunks[index]
            do { try context.check() }
            catch {
                throw BulkGuildBanFailure(banned: banned, failed: failed, attempted: [],
                    unattempted: Array(userIDs.dropFirst(completedCount)), underlying: error)
            }
            do {
                let result = try await context.run {
                    await progress.start()
                    let result = try await execute(endpoint)
                    let success = Set(result.bannedUsers), failure = Set(result.failedUsers)
                    guard success.count == result.bannedUsers.count, failure.count == result.failedUsers.count,
                          success.isDisjoint(with: failure), success.union(failure) == Set(chunk)
                    else { throw DiscordError.transport(.invalidResponse) }
                    let outcome = BulkGuildBanOutcome(banned: chunk.filter { success.contains($0) },
                        failed: chunk.filter { failure.contains($0) })
                    await progress.acknowledge(outcome)
                    return outcome
                }
                banned += result.banned; failed += result.failed; completedCount += chunk.count
            } catch {
                let state = await progress.snapshot()
                if let result = state.result {
                    banned += result.banned; failed += result.failed; completedCount += chunk.count
                }
                let attempted = state.started && state.result == nil ? chunk : []
                throw BulkGuildBanFailure(banned: banned, failed: failed, attempted: attempted,
                    unattempted: Array(userIDs.dropFirst(completedCount + attempted.count)), underlying: error)
            }
        }
        return BulkGuildBanOutcome(banned: banned, failed: failed)
    }

    /// Conceals identifiers and retained request bodies from ordinary interpolation.
    public var description: String { "BulkGuildBanPlan(redacted)" }
    /// Returns the same safe diagnostic marker for debug formatting.
    public var debugDescription: String { description }
    /// Prevents recursive reflection from exposing users, audit text or descriptors.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}

/// Acknowledged bulk-ban classifications; explicit failure includes users already banned upstream.
public struct BulkGuildBanOutcome: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let banned: [UserID]
    public let failed: [UserID]

    /// Retains bounded correlated results from the plan in original input order.
    /// - Parameters:
    ///   - banned: Users acknowledged as successfully banned; empty is retained.
    ///   - failed: Users explicitly classified as unsuccessful; empty is retained.
    /// No network action or retry is performed, and these snapshots do not prove current ban state.
    fileprivate init(banned: [UserID], failed: [UserID]) { self.banned = banned; self.failed = failed }
    /// Conceals user IDs during ordinary formatting.
    public var description: String { "BulkGuildBanOutcome(redacted)" }
    /// Conceals user IDs during debug formatting.
    public var debugDescription: String { description }
    /// Conceals user IDs during recursive reflection.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}

/// Safe progress retained when a bulk-ban plan stops; inspect properties deliberately to reconcile.
public struct BulkGuildBanFailure: Error, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let banned: [UserID]
    public let failed: [UserID]
    public let attempted: [UserID]
    public let unattempted: [UserID]
    public let underlying: any Error

    /// Records immutable progress after the cooperative executor and any deadline child finish.
    /// - Parameters:
    ///   - banned: Successfully acknowledged users from prior or racing-completed chunks.
    ///   - failed: Explicitly failed users from acknowledged chunks; never automatically retried.
    ///   - attempted: Current entered chunk without a validated acknowledgement; submission may be unknown.
    ///   - unattempted: Remaining input never entered into execution in this invocation.
    ///   - underlying: Original cause, including unknown mutation outcome; retained without diagnostic interpolation.
    /// Construction performs no I/O and makes no retry-safety inference.
    fileprivate init(banned: [UserID], failed: [UserID], attempted: [UserID], unattempted: [UserID], underlying: any Error) {
        self.banned = banned; self.failed = failed; self.attempted = attempted
        self.unattempted = unattempted; self.underlying = underlying
    }
    /// Conceals identifiers and potentially sensitive underlying error descriptions.
    public var description: String { "BulkGuildBanFailure(redacted)" }
    /// Uses the same safe marker for debug output.
    public var debugDescription: String { description }
    /// Prevents reflection from expanding progress or its underlying error.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}

/// Records a chunk across structured cancellation without losing an acknowledged partial result.
private actor GuildBanProgress {
    private var started = false
    private var result: BulkGuildBanOutcome?
    /// Marks entry into caller code; this alone establishes no network submission.
    func start() { started = true }
    /// Records a correlated acknowledgement before returning across the cancellation boundary.
    /// - Parameter result: Bounded, validated classifications for the current chunk.
    func acknowledge(_ result: BulkGuildBanOutcome) { self.result = result }
    /// Reads final evidence after structured child cleanup.
    /// - Returns: Whether execution began and any validated acknowledgement received.
    func snapshot() -> (started: Bool, result: BulkGuildBanOutcome?) { (started, result) }
}
