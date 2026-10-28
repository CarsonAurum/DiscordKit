// File: Sources/DiscordHTTP/Resources/UserOperations.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import DiscordModels
import DiscordTransport

/// REST storage-shard selection for the current-user guild list. This is deliberately distinct from
/// Gateway shard IDs: valid values are zero through the session-start limit's max_concurrency minus one.
/// The requirement for large-bot apps took effect in Discord's 2026-09-15 announcement.
public struct UserGuildListShard: Sendable, Equatable, Hashable {
    /// Zero-based REST storage-shard index; deliberately separate from a Gateway connection shard.
    public let index: Int
    /// Caller-supplied positive session-start max_concurrency used to validate the selected index.
    public let maxConcurrency: Int

    /// Validates one REST storage-shard selection against caller-supplied Get Gateway Bot metadata.
    /// - Parameters:
    ///   - index: Zero-based REST storage-shard index, in 0..<maxConcurrency; never a Gateway connection shard ID.
    ///   - maxConcurrency: Positive current session-start max_concurrency from Get Gateway Bot, explicitly supplied
    ///     without the helper fetching Gateway data or opening a connection. Staleness remains caller-owned.
    /// - Throws: Safe invalid-value errors for nonpositive maxConcurrency or negative/out-of-range indices.
    ///   Construction is synchronous, starts no I/O and does not raise REST rate limits.
    public init(index: Int, maxConcurrency: Int) throws {
        guard maxConcurrency > 0, (0..<maxConcurrency).contains(index) else { throw DiscordError.validation(.invalidValue) }
        self.index = index; self.maxConcurrency = maxConcurrency
    }
}

/// Validated one-page query for GET /users/@me/guilds. No request starts during construction.
public struct UserGuildsQuery: Sendable, Equatable {
    /// Optional exclusive upper guild-ID bound, transmitted without numeric conversion.
    public let before: GuildID?
    /// Optional exclusive lower guild-ID bound, transmitted without numeric conversion.
    public let after: GuildID?
    /// Optional validated per-page item cap; nil preserves Discord's default of 200.
    public let limit: Int?
    /// Optional validated REST storage-shard selection.
    public let shard: UserGuildListShard?
    /// Optional approximate member/presence-count selection; nil preserves the upstream default false.
    public let withCounts: Bool?
    /// Explicit caller knowledge requiring a shard locally, rather than inferred deployment size.
    public let largeBotSharding: Bool

    /// Validates user-guild pagination and optional explicit large-bot shard requirements.
    /// - Parameters:
    ///   - before: Optional exclusive upper guild-ID bound. It may combine with after for one explicit bounded read;
    ///     the lazy helper uses only one directional cursor and does not guess a traversal from two bounds.
    ///   - after: Optional exclusive lower guild-ID bound, preserving exact unsigned bits.
    ///   - limit: Optional 1...200 result cap; nil preserves Discord's default 200.
    ///   - shard: Optional validated REST storage shard; supplying it does not infer large-bot app eligibility.
    ///   - withCounts: Optional include-approximate-counts switch; nil preserves the server default false.
    ///   - largeBotSharding: Explicit caller knowledge, default false; true rejects missing shard locally because
    ///     Discord now returns 400 for large-bot requests without the required storage-shard selection.
    /// - Throws: Safe invalid-value errors for invalid limits or an explicitly required missing shard.
    ///   Server checks metadata freshness and app eligibility on execution.
    public init(before: GuildID? = nil, after: GuildID? = nil, limit: Int? = nil,
                shard: UserGuildListShard? = nil, withCounts: Bool? = nil, largeBotSharding: Bool = false) throws {
        guard limit.map({ (1...200).contains($0) }) ?? true,
              !largeBotSharding || shard != nil
        else { throw DiscordError.validation(.invalidValue) }
        self.before = before; self.after = after; self.limit = limit; self.shard = shard
        self.withCounts = withCounts; self.largeBotSharding = largeBotSharding
    }

    /// Emits only caller-selected query fields in stable documented order, with no default hydration.
    /// - Returns: before, after, limit, shard and with_counts when present; exact IDs remain decimal strings.
    /// This synchronous method performs no I/O, permission checks, caching or state changes.
    func queryItems() -> [QueryItem] {
        var fields: [QueryItem] = []
        if let before { fields.append(.init(name: "before", value: before.description)) }
        if let after { fields.append(.init(name: "after", value: after.description)) }
        if let limit { fields.append(.init(name: "limit", value: String(limit))) }
        if let shard { fields.append(.init(name: "shard", value: String(shard.index))) }
        if let withCounts { fields.append(.init(name: "with_counts", value: withCounts ? "true" : "false")) }
        return fields
    }
}

/// Explicit forward/backward guild-list traversal. The API exposes before/after snowflake cursors;
/// each selected direction remains fixed for the lifetime of one lazy sequence.
public enum UserGuildTraversal: Sendable, Equatable {
    /// Requests after the current cursor and advances its bound through increasing guild IDs.
    case ascending
    /// Requests before the current cursor and advances its bound through decreasing guild IDs.
    case descending
}

/// Opt-in bounded user workflows. Every request executes sequentially through caller-owned HTTP authority,
/// with no prefetch, implicit shard enumeration, permission hydration or automatic account mutation retries.
public enum UserOperations {
    /// Lazily enumerates the current account's guilds for one explicitly selected REST storage shard or ordinary list.
    /// - Parameters:
    ///   - direction: Ascending after-cursor by default, or descending before-cursor. Wire order is preserved;
    ///     the next cursor uses the page maximum/minimum respectively without inventing a result-order guarantee.
    ///   - cursor: Optional initial exclusive guild ID; nil starts at that direction's first page.
    ///   - limit: Per-page requested/accepted item cap, 1...200, default 200.
    ///   - shard: Optional validated REST storage shard. Large-bot callers must enumerate every index separately
    ///     using current max_concurrency; this helper does not fetch that metadata or create parallel requests.
    ///   - largeBotSharding: Explicitly requires shard when true, default false; does not infer app eligibility.
    ///   - withCounts: Include approximate member/presence counts, default false.
    ///   - maximumPages: Finite request/cursor-history budget, 1...10,000, default 10,000; results are not accumulated.
    ///   - context: Shared clock, cancellation and optional inclusive overall deadline, checked before each pull.
    ///   - execute: Cooperative executor through shared rate admission, called exactly once per requested page;
    ///     coalescing/caching are disabled to avoid silently reusing traversal snapshots.
    /// - Returns: Lazy pages preserving each response's wire order until empty/null. Short nonempty pages continue,
    ///   because size alone does not establish completion. Null is a preview-supported terminal absent collection.
    /// - Throws: Configuration errors before I/O; executor/cancellation/deadline/budget errors during iteration.
    ///   Oversized, duplicate or nonadvancing IDs fail with invalid-response and permanently finish
    ///   that iterator. Concurrent server changes can affect coverage; this is not a transaction or stable snapshot.
    public static func guildPages<C: Clock>(
        direction: UserGuildTraversal = .ascending, cursor: GuildID? = nil, limit: Int = 200,
        shard: UserGuildListShard? = nil, largeBotSharding: Bool = false, withCounts: Bool = false,
        maximumPages: Int = 10_000, context: TransportContext<C>,
        execute: @escaping @Sendable (Endpoint<Nullable<[UserGuild]>>) async throws -> Nullable<[UserGuild]>
    ) throws -> CursorPagination<UserGuild, GuildID, C> where C.Duration == Duration {
        guard (1...200).contains(limit), (1...10_000).contains(maximumPages), !largeBotSharding || shard != nil
        else { throw DiscordError.validation(.invalidValue) }
        return try CursorPagination(initialCursor: cursor, maximumPages: maximumPages, context: context) { cursor in
            let query = try UserGuildsQuery(before: direction == .descending ? cursor : nil,
                after: direction == .ascending ? cursor : nil, limit: limit, shard: shard,
                withCounts: withCounts, largeBotSharding: largeBotSharding)
            let result = try await execute(UserEndpoints.guilds(query: query, readPolicy: nil))
            guard case .value(let guilds) = result else { return CursorPage(items: [], nextCursor: nil) }
            guard guilds.count <= limit else { throw DiscordError.transport(.invalidResponse) }
            var seen: Set<GuildID> = []
            var next = cursor
            for guild in guilds {
                guard seen.insert(guild.id).inserted else { throw DiscordError.transport(.invalidResponse) }
                if let cursor {
                    guard direction == .ascending ? guild.id > cursor : guild.id < cursor
                    else { throw DiscordError.transport(.invalidResponse) }
                }
                if let previous = next {
                    next = direction == .ascending ? max(previous, guild.id) : min(previous, guild.id)
                } else { next = guild.id }
            }
            return CursorPage(items: guilds, nextCursor: guilds.isEmpty ? nil : next)
        }
    }

    /// Skips an exact account no-op using an explicitly supplied snapshot without claiming freshness or current authority.
    /// - Parameters:
    ///   - current: Caller-owned current-user snapshot. Passing another user's snapshot does not authorize mutation;
    ///     PATCH always addresses the executing bot and caller is responsible for matching credential ownership.
    ///   - request: Validated optional changes; omission is ignored and null differs from a missing raw field.
    ///     Nonnull avatar/banner uploads always require a write: response asset hashes cannot prove image-byte equality.
    /// - Returns: Nil for empty/matching edits, or one unsafe PATCH descriptor with ordinary invalidation policy.
    /// - Throws: JSON-root/descriptor/body errors for a changed request. No preliminary GET, request merging,
    ///   cache access or resource ownership occurs; stale snapshots retain a reconciliation race.
    public static func modifyIfChanged(current: User, request: UserModify) throws -> Endpoint<User>? {
        guard case .object(let selected) = request.jsonValue() else { throw DiscordError.validation(.invalidValue) }
        if selected.allSatisfy({ field in
            if ["avatar", "banner"].contains(field.key), field.value != .null { return false }
            return current.rawFields[field.key] == field.value
        }) { return nil }
        return try UserEndpoints.modifyCurrent(request: request)
    }
}
