import DiscordCore
import DiscordModels
import DiscordTransport

/// Explicit exclusive snowflake traversal shared by the two monetization list operations.
/// Wire order is preserved; cursor advancement does not require an undocumented sorting guarantee.
public enum MonetizationTraversal: Sendable, Equatable {
    /// Advances an after boundary through increasing IDs; an omitted initial cursor starts after zero.
    case ascending
    /// Advances a before boundary through decreasing IDs; an omitted initial cursor uses the server's first page.
    case descending
}

/// Opt-in finite entitlement reads without implicit consumption, per-user fan-out or access decisions.
public enum EntitlementOperations {
    /// Lazily traverses application entitlements while retaining every selected server filter.
    /// Each pull runs one API v10 list descriptor through caller-owned shared rate authority.
    /// - Parameters:
    ///   - applicationID: Owning application, validated against every returned entitlement.
    ///   - userID: Optional user filter; no user/member lookup occurs.
    ///   - skuIDs: Optional SKU filter set, validated by the endpoint before iteration.
    ///   - direction: Fixed exclusive cursor direction, default descending. Ascending starts after zero when cursor is nil.
    ///   - cursor: Optional initial exclusive entitlement boundary, retaining all 64 bits.
    ///   - limit: Requested and accepted page item cap, 1...100, default 100.
    ///   - guildID: Optional guild owner filter; no guild lookup occurs.
    ///   - excludeEnded: Optional ended-entitlement exclusion; nil preserves Discord's default false.
    ///   - excludeDeleted: Optional deleted-entitlement exclusion; nil preserves Discord's default true.
    ///   - maximumPages: Finite request/history cap, 1...10,000, default 10,000; pages are not accumulated.
    ///   - context: Shared monotonic clock, cooperative cancellation and optional inclusive overall deadline.
    ///   - execute: Sequential cooperative HTTP executor. Traversal disables coalescing and completed caching.
    /// - Returns: Independent lazy iterators with one page per pull, no prefetch, and wire-order preservation.
    ///   Empty pages terminate; short nonempty pages continue. Concurrent server changes can affect coverage.
    /// - Throws: Invalid bounds/filter/descriptor configuration before I/O; execution, cancellation, deadline or
    ///   page-budget errors on iteration. Oversized pages, duplicate/nonadvancing IDs or wrong applications
    ///   fail with invalid-response and permanently finish that iterator. Snapshots do not prove current access.
    public static func pages<C: Clock>(
        applicationID: ApplicationID, userID: UserID? = nil, skuIDs: [SKUID]? = nil,
        direction: MonetizationTraversal = .descending, cursor: EntitlementID? = nil, limit: Int = 100,
        guildID: GuildID? = nil, excludeEnded: Bool? = nil, excludeDeleted: Bool? = nil,
        maximumPages: Int = 10_000, context: TransportContext<C>,
        execute: @escaping @Sendable (Endpoint<[Entitlement]>) async throws -> [Entitlement]
    ) throws -> CursorPagination<Entitlement, EntitlementID, C> where C.Duration == Duration {
        guard (1...100).contains(limit), (1...10_000).contains(maximumPages)
        else { throw DiscordError.validation(.invalidValue) }
        _ = try EntitlementEndpoints.list(applicationID: applicationID, userID: userID, skuIDs: skuIDs,
            limit: limit, guildID: guildID, excludeEnded: excludeEnded, excludeDeleted: excludeDeleted, readPolicy: nil)
        let initial = cursor ?? (direction == .ascending ? EntitlementID(rawValue: 0) : nil)
        return try CursorPagination(initialCursor: initial, maximumPages: maximumPages, context: context) { boundary in
            let position: EntitlementPosition? = boundary.map { direction == .ascending ? .after($0) : .before($0) }
            let items = try await execute(EntitlementEndpoints.list(applicationID: applicationID,
                userID: userID, skuIDs: skuIDs, position: position, limit: limit, guildID: guildID,
                excludeEnded: excludeEnded, excludeDeleted: excludeDeleted, readPolicy: nil))
            guard items.allSatisfy({ $0.applicationID == applicationID })
            else { throw DiscordError.transport(.invalidResponse) }
            return try monetizationPage(items, boundary: boundary, direction: direction, limit: limit) { $0.id }
        }
    }
}

/// Opt-in finite subscription lifecycle reads; subscription state never grants premium access.
public enum SubscriptionOperations {
    /// Lazily traverses one SKU's subscriptions using explicit bot-user or OAuth scope semantics.
    /// - Parameters:
    ///   - skuID: SKU required in every returned subscription's sku_ids; no SKU lookup occurs.
    ///   - userID: Optional exact user filter. Nil requires a bearer credential; bots must select a user.
    ///   - direction: Fixed exclusive direction, default descending; ascending with nil cursor starts after zero.
    ///   - cursor: Optional exact exclusive subscription boundary.
    ///   - limit: Requested and accepted page cap, 1...100, default 50 matching the server default.
    ///   - maximumPages: Finite request/history cap, 1...10,000, default 10,000; results are not accumulated.
    ///   - context: Shared monotonic deadline/cancellation domain checked around every suspension.
    ///   - execute: Cooperative sequential executor using shared credential-scoped admission. Reuse is disabled.
    /// - Returns: Independent nonprefetching iterators, preserving wire order and continuing short pages to empty.
    ///   Reads describe recurring payment lifecycle, not entitlement validity or authorization.
    /// - Throws: Invalid configuration before I/O; execution/cancellation/deadline/budget errors on iteration.
    ///   Oversized, duplicate/nonadvancing or wrong SKU/user results fail with invalid-response permanently.
    ///   Server changes can affect traversal; this is not a transaction or stable snapshot.
    public static func pages<C: Clock>(
        skuID: SKUID, userID: UserID? = nil, direction: MonetizationTraversal = .descending,
        cursor: SubscriptionID? = nil, limit: Int = 50, maximumPages: Int = 10_000,
        context: TransportContext<C>,
        execute: @escaping @Sendable (Endpoint<[Subscription]>) async throws -> [Subscription]
    ) throws -> CursorPagination<Subscription, SubscriptionID, C> where C.Duration == Duration {
        guard (1...100).contains(limit), (1...10_000).contains(maximumPages)
        else { throw DiscordError.validation(.invalidValue) }
        let initial = cursor ?? (direction == .ascending ? SubscriptionID(rawValue: 0) : nil)
        return try CursorPagination(initialCursor: initial, maximumPages: maximumPages, context: context) { boundary in
            let position: SubscriptionPosition? = boundary.map { direction == .ascending ? .after($0) : .before($0) }
            let items = try await execute(SubscriptionEndpoints.list(skuID: skuID, userID: userID,
                position: position, limit: limit, readPolicy: nil))
            guard items.allSatisfy({ $0.skuIDs.contains(skuID) && (userID == nil || $0.userID == userID) })
            else { throw DiscordError.transport(.invalidResponse) }
            return try monetizationPage(items, boundary: boundary, direction: direction, limit: limit) { $0.id }
        }
    }
}

/// Validates one finite exclusive snowflake page without assuming response sorting or retaining earlier items.
/// - Parameters:
///   - items: Current page in wire order, including empty terminal pages.
///   - boundary: Optional exclusive request bound; nil is the server's first descending page.
///   - direction: Fixed direction selecting the page maximum or minimum as the next boundary.
///   - limit: Already validated positive requested/accepted item cap.
///   - identifier: Pure typed resource identifier projection, with no I/O or mutation.
/// - Returns: Original items with an advancing cursor, or nil cursor for an empty terminal page.
/// - Throws: Invalid-response for excessive item count, duplicate IDs or IDs outside the exclusive bound.
/// Memory is O(limit); no task, cache or shared mutable state is created.
private func monetizationPage<Item: Sendable, Tag>(
    _ items: [Item], boundary: Snowflake<Tag>?, direction: MonetizationTraversal, limit: Int,
    identifier: (Item) -> Snowflake<Tag>
) throws -> CursorPage<Item, Snowflake<Tag>> {
    guard items.count <= limit else { throw DiscordError.transport(.invalidResponse) }
    var seen: Set<Snowflake<Tag>> = []
    var next = boundary
    for item in items {
        let id = identifier(item)
        guard seen.insert(id).inserted else { throw DiscordError.transport(.invalidResponse) }
        if let boundary {
            guard direction == .ascending ? id > boundary : id < boundary
            else { throw DiscordError.transport(.invalidResponse) }
        }
        if let previous = next { next = direction == .ascending ? max(previous, id) : min(previous, id) }
        else { next = id }
    }
    return CursorPage(items: items, nextCursor: items.isEmpty ? nil : next)
}
