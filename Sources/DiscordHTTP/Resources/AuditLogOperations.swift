import DiscordCore
import DiscordModels
import DiscordTransport

/// Explicit bounded audit workflows that never fetch related entities or prefetch another page.
public enum AuditLogOperations {
    /// Enumerates complete audit envelopes with exclusive cursors in either documented direction.
    /// - Parameters:
    ///   - guildID: Guild requiring VIEW_AUDIT_LOG on every request.
    ///   - userID: Optional actor filter, preserved unchanged across requests.
    ///   - actionType: Optional known/future action filter, preserved unchanged across requests.
    ///   - position: Initial exclusive boundary; nil starts newest first, after zero starts oldest first.
    ///   - limit: Requested and accepted entry bound, 1...100; default 100.
    ///   - maximumPages: Local finite request budget, 1...10,000; default 10,000.
    ///   - context: Shared monotonic clock, optional deadline and cooperative cancellation domain.
    ///   - execute: Sequential cooperative executor using ordinary HTTP admission. Descriptors disable reuse.
    /// - Returns: A lazy sequence yielding the full envelope, including related resources, on each pull.
    ///   Short nonempty pages continue; an empty entry list terminates after yielding its envelope once.
    /// - Throws: Invalid bounds before I/O; executor/cancellation/deadline/budget errors on iteration;
    ///   invalid-response for oversized, duplicate, out-of-order or nonadvancing entry IDs. Failures finish
    ///   the iterator permanently. Retention expiry and concurrent actions can affect coverage; this is no snapshot.
    public static func pages<C: Clock>(guildID: GuildID, userID: UserID? = nil,
        actionType: RawValue<AuditLogEvent>? = nil, position: AuditLogPosition? = nil,
        limit: Int = 100, maximumPages: Int = 10_000, context: TransportContext<C>,
        execute: @escaping @Sendable (Endpoint<AuditLog>) async throws -> AuditLog
    ) throws -> AuditLogPages<C> where C.Duration == Duration {
        guard (1...100).contains(limit), (1...10_000).contains(maximumPages)
        else { throw DiscordError.validation(.invalidValue) }
        let ascending: Bool
        let initial: AuditLogEntryID?
        switch position {
        case .after(let id): ascending = true; initial = id
        case .before(let id): ascending = false; initial = id
        case nil: ascending = false; initial = nil
        }
        let pages = try CursorPagination<AuditLog, AuditLogEntryID, C>(
            initialCursor: initial, maximumPages: maximumPages, context: context
        ) { cursor in
            let boundary: AuditLogPosition? = cursor.map { ascending ? .after($0) : .before($0) }
            let log = try await execute(AuditLogEndpoints.get(guildID: guildID, userID: userID,
                actionType: actionType, position: boundary, limit: limit, readPolicy: nil))
            guard log.auditLogEntries.count <= limit else { throw DiscordError.transport(.invalidResponse) }
            var previous = cursor
            for entry in log.auditLogEntries {
                if let previous {
                    guard ascending ? entry.id > previous : entry.id < previous
                    else { throw DiscordError.transport(.invalidResponse) }
                }
                previous = entry.id
            }
            return CursorPage(items: [log], nextCursor: log.auditLogEntries.isEmpty ? nil : previous)
        }
        return AuditLogPages(pages: pages)
    }
}

/// A bounded full-envelope audit sequence. Each iterator independently owns cursor history and page budgets;
/// no network operation occurs until next(). Related resources remain available for local correlation.
public struct AuditLogPages<C: Clock>: AsyncSequence, Sendable where C.Duration == Duration {
    public typealias Element = AuditLog
    private let pages: CursorPagination<AuditLog, AuditLogEntryID, C>

    /// Stores the already configured one-envelope-per-page pagination engine without starting work.
    /// - Parameter pages: Internal engine whose fetch always returns exactly one complete audit envelope.
    init(pages: CursorPagination<AuditLog, AuditLogEntryID, C>) { self.pages = pages }

    /// Creates an independent single-consumer cursor without fetching or prefetching.
    /// - Returns: Iterator retaining bounded cursor history without storing previously yielded envelopes.
    public func makeAsyncIterator() -> AsyncIterator { AsyncIterator(base: pages.makeAsyncIterator()) }

    /// Sequential full-envelope iterator; cancellation, deadlines and failures permanently finish its base.
    public struct AsyncIterator: AsyncIteratorProtocol {
        private var base: CursorPagination<AuditLog, AuditLogEntryID, C>.AsyncIterator

        /// Stores an independent iterator over the internal one-envelope pages.
        /// - Parameter base: Fresh bounded iterator; construction initiates no I/O.
        fileprivate init(base: CursorPagination<AuditLog, AuditLogEntryID, C>.AsyncIterator) { self.base = base }

        /// Fetches exactly one complete envelope and advances its exclusive entry cursor.
        /// - Returns: Full audit data, or nil once the empty-entry envelope has already been yielded.
        /// - Throws: Original execution/cancellation/deadline errors or bounded cursor/budget failures.
        ///   No following request begins until the next invocation. The iterator is single-consumer.
        public mutating func next() async throws -> AuditLog? { try await base.next()?.first }
    }
}
