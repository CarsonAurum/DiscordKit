import DiscordCore
import DiscordModels
import DiscordTransport

/// Which archived-thread timestamp route to traverse. Joined-private traversal has a different ID cursor.
public enum ArchivedThreadVisibility: Sendable {
    /// Accessible public/announcement threads; requires READ_MESSAGE_HISTORY.
    case `public`
    /// Accessible private threads; additionally requires MANAGE_THREADS.
    case `private`
}

/// Finite, lazy channel workflows. Executors are sequential, cancellation-cooperative closures such
/// as `{ try await client.execute($0) }`; every request still uses shared credential rate admission.
/// No workflow prefetches, automatically hydrates members, packs mutations, or adds retries.
/// Independent iterators have independent progress; one iterator has a single consumer.
public enum ChannelOperations {
    /// Traverses public/private archives using exclusive archive timestamps and explicit hasMore.
    /// Each yielded item is the complete envelope, so member-to-thread correlation is preserved.
    /// - Parameters:
    ///   - channelID: Parent channel; visibility and history permissions are server-enforced.
    ///   - visibility: Public or private archive; private requires MANAGE_THREADS.
    ///   - before: Optional initial exact timestamp, including offset and fractional precision.
    ///   - limit: Local requested/accepted page bound, 1...100; default 100. This is a conservative
    ///     local policy because the written archive reference does not publish a numeric maximum.
    ///   - maximumPages: Finite page/request budget, 1...10,000; default 10,000.
    ///   - context: Injected monotonic clock, cancellation and optional inclusive deadline.
    ///   - execute: Bounded sequential archive executor; called only on a pull. Read reuse is disabled.
    /// - Returns: Lazy singleton arrays of complete archive envelopes; hasMore false completes after that page.
    /// - Throws: Configuration errors now; executor/cancellation/deadline/budget errors during iteration,
    ///   or invalid-response for oversized pages, duplicate thread IDs, missing metadata, out-of-order
    ///   timestamps or items outside the requested exclusive cursor, including on terminal pages.
    /// Short pages do not imply exhaustion. Equal archive timestamps within a page are allowed;
    /// continuation must advance to a strictly earlier instant. Cursor precision is never replaced
    /// by thread creation time. Validation retains at most one page's bounded set of thread IDs.
    /// Discord publishes no timestamp tie-breaker or snapshot guarantee; ties split across server
    /// page boundaries and concurrent archive-state changes can affect complete traversal coverage.
    public static func archivedThreadPages<C: Clock>(
        channelID: ChannelID, visibility: ArchivedThreadVisibility, before: DiscordTimestamp? = nil,
        limit: Int = 100, maximumPages: Int = 10_000, context: TransportContext<C>,
        execute: @escaping @Sendable (Endpoint<ArchivedThreads>) async throws -> ArchivedThreads
    ) throws -> CursorPagination<ArchivedThreads, DiscordTimestamp, C> where C.Duration == Duration {
        try channelPageBudget(maximumPages)
        try messageLimit(limit, maximum: 100)
        return try CursorPagination(initialCursor: before, maximumPages: maximumPages, context: context) { cursor in
            let endpoint = try visibility == .public
                ? ChannelEndpoints.publicArchivedThreads(channelID: channelID, before: cursor, limit: limit, readPolicy: nil)
                : ChannelEndpoints.privateArchivedThreads(channelID: channelID, before: cursor, limit: limit, readPolicy: nil)
            let page = try await execute(endpoint)
            guard page.threads.count <= limit, !page.hasMore || !page.threads.isEmpty
            else { throw DiscordError.transport(.invalidResponse) }
            var previous: DiscordTimestamp?
            var threadIDs: Set<ChannelID> = []
            for thread in page.threads {
                guard threadIDs.insert(thread.id).inserted,
                      case .value(let metadata) = thread.threadMetadata,
                      cursor.map({ channelTimestampPrecedes(metadata.archiveTimestamp, $0) }) ?? true,
                      previous.map({ !channelTimestampPrecedes($0, metadata.archiveTimestamp) }) ?? true
                else { throw DiscordError.transport(.invalidResponse) }
                previous = metadata.archiveTimestamp
            }
            return CursorPage(items: [page], nextCursor: page.hasMore ? previous : nil)
        }
    }

    /// Traverses joined-private archives in descending thread-ID order, preserving complete envelopes.
    /// - Parameters:
    ///   - channelID: Parent channel requiring READ_MESSAGE_HISTORY.
    ///   - before: Optional initial exclusive thread ID; nil starts with the newest joined archive.
    ///   - limit: Local requested/accepted page bound, 1...100; default 100.
    ///   - maximumPages: Finite request/page budget, 1...10,000; default 10,000.
    ///   - context: Injected monotonic clock, cancellation and optional inclusive deadline.
    ///   - execute: Sequential cancellation-cooperative executor; descriptors disable read reuse.
    /// - Returns: Lazy singleton arrays of complete envelopes, completing only when hasMore is false.
    /// - Throws: Configuration errors now; executor/cancellation/deadline/budget errors later;
    ///   invalid-response for oversized or empty-continuing pages, duplicate/out-of-order IDs, or any item
    ///   outside the exclusive requested cursor, including on terminal pages. No timestamp cursor is used.
    public static func joinedPrivateArchivedThreadPages<C: Clock>(
        channelID: ChannelID, before: ChannelID? = nil, limit: Int = 100, maximumPages: Int = 10_000,
        context: TransportContext<C>, execute: @escaping @Sendable (Endpoint<ArchivedThreads>) async throws -> ArchivedThreads
    ) throws -> CursorPagination<ArchivedThreads, ChannelID, C> where C.Duration == Duration {
        try channelPageBudget(maximumPages)
        try messageLimit(limit, maximum: 100)
        return try CursorPagination(initialCursor: before, maximumPages: maximumPages, context: context) { cursor in
            let page = try await execute(ChannelEndpoints.joinedPrivateArchivedThreads(channelID: channelID,
                before: cursor, limit: limit, readPolicy: nil))
            guard page.threads.count <= limit, !page.hasMore || !page.threads.isEmpty
            else { throw DiscordError.transport(.invalidResponse) }
            var previous = cursor
            for thread in page.threads {
                guard previous.map({ thread.id < $0 }) ?? true
                else { throw DiscordError.transport(.invalidResponse) }
                previous = thread.id
            }
            return CursorPage(items: [page], nextCursor: page.hasMore ? previous : nil)
        }
    }

    /// Traverses v10 thread-member pages with with_member=true, using exclusive ascending user IDs.
    /// Requires the application's GUILD_MEMBERS eligibility; it performs no independent member hydration.
    /// - Parameters:
    ///   - channelID: Thread whose visible membership is read.
    ///   - after: Optional initial exclusive user ID, preserved exactly.
    ///   - limit: Requested/accepted page bound, 1...100; default 100.
    ///   - maximumPages: Finite request/page budget, 1...10,000; default 10,000.
    ///   - context: Injected cancellation, monotonic clock and optional inclusive deadline.
    ///   - execute: Sequential cooperative executor; called once per pull and disables read reuse.
    /// - Returns: Lazy member arrays including a terminal empty page. A short page continues.
    /// - Throws: Configuration errors now; executor/cancellation/deadline/budget errors on iteration,
    ///   or invalid-response for oversized pages, missing IDs, duplicates or nonascending user IDs.
    public static func threadMemberPages<C: Clock>(
        channelID: ChannelID, after: UserID? = nil, limit: Int = 100, maximumPages: Int = 10_000,
        context: TransportContext<C>, execute: @escaping @Sendable (Endpoint<[ThreadMember]>) async throws -> [ThreadMember]
    ) throws -> CursorPagination<ThreadMember, UserID, C> where C.Duration == Duration {
        try channelPageBudget(maximumPages)
        try messageLimit(limit, maximum: 100)
        return try CursorPagination(initialCursor: after, maximumPages: maximumPages, context: context) { cursor in
            let members = try await execute(ChannelEndpoints.threadMembers(channelID: channelID,
                withMember: true, after: cursor, limit: limit, readPolicy: nil))
            guard members.count <= limit else { throw DiscordError.transport(.invalidResponse) }
            var previous = cursor
            for member in members {
                guard case .value(let id) = member.userID, previous.map({ id > $0 }) ?? true
                else { throw DiscordError.transport(.invalidResponse) }
                previous = id
            }
            return CursorPage(items: members, nextCursor: members.isEmpty ? nil : previous)
        }
    }

    /// Avoids an unnecessary settings mutation when every explicitly requested wire field already
    /// matches a caller-supplied Channel snapshot. No automatic read or write is performed.
    /// - Parameters:
    ///   - current: Caller-owned snapshot with exact raw fields. Obfuscated snapshots are rejected;
    ///     a stale unobfuscated snapshot can still miss intervening server changes.
    ///   - request: Validated settings for the snapshot's actual channel type; all-absent is a no-op.
    ///   - auditReason: Optional supported audit reason, validated only when a descriptor is needed.
    /// - Returns: Nil when every requested field is present and equal; otherwise one normal unsafe PATCH descriptor.
    ///   Unknown omitted fields do not count as equal to explicit null. No generic mutation batching occurs.
    /// - Throws: Invalid-value for obfuscated/type-incompatible snapshots or malformed request root;
    ///   ordinary descriptor/audit errors when constructing a required change.
    public static func modifyIfChanged(current: Channel, request: ChannelModify,
                                        auditReason: String? = nil) throws -> Endpoint<Channel>? {
        guard !current.isObfuscated, case .object(let fields) = request.jsonValue()
        else { throw DiscordError.validation(.invalidValue) }
        // Request validation uses explicit caller context; the public type context must match this snapshot.
        guard current.type.knownValue == request.channelType else { throw DiscordError.validation(.invalidValue) }
        guard fields.contains(where: { current.rawFields[$0.key] != $0.value }) else { return nil }
        return try ChannelEndpoints.modify(channelID: current.id, request: request, auditReason: auditReason)
    }
}

/// Bounds retained cursor history and requests consistently across channel workflows.
/// - Parameter maximumPages: Inclusive finite budget in 1...10,000.
/// - Throws: Safe invalid-value for a nonpositive or oversized page budget; no I/O occurs.
func channelPageBudget(_ maximumPages: Int) throws {
    guard (1...10_000).contains(maximumPages) else { throw DiscordError.validation(.invalidValue) }
}

/// Compares exact parsed instants without losing subsecond precision or treating offsets as ordering.
/// - Parameters:
///   - lhs: Proposed next exclusive archive cursor.
///   - rhs: Previously requested cursor.
/// - Returns: True only for a strictly earlier instant; equivalent offset spellings return false.
func channelTimestampPrecedes(_ lhs: DiscordTimestamp, _ rhs: DiscordTimestamp) -> Bool {
    lhs.unixSeconds < rhs.unixSeconds || (lhs.unixSeconds == rhs.unixSeconds && lhs.nanosecond < rhs.nanosecond)
}
