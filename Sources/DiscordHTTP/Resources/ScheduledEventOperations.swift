import DiscordCore
import DiscordModels
import DiscordTransport

/// Explicit caller-owned event workflows without hydration, request prefetch or background tasks.
public enum GuildScheduledEventOperations {
    /// Suppresses a PATCH when all requested fields already equal the caller's event snapshot.
    /// - Parameters:
    ///   - current: Caller-owned complete event; freshness, visibility and authorization are not inferred.
    ///   - request: Validated edits whose hosting/status context must match this snapshot, even for no-op edits.
    ///   - auditReason: Optional supported reason, validated only if a mutation is produced.
    /// - Returns: Nil for an empty/matching selection, otherwise one ordinary unsafe PATCH descriptor.
    /// - Throws: Invalid-value for unknown/mismatched context or start/end ordering against retained snapshot
    ///   timestamps, plus ordinary descriptor/audit errors. Stale snapshots retain reconciliation races;
    ///   omitted fields are not compared and no HTTP read, retry or permission lookup occurs.
    public static func modifyIfChanged(current: GuildScheduledEvent, request: GuildScheduledEventModify,
                                       auditReason: String? = nil) throws -> Endpoint<GuildScheduledEvent>? {
        guard current.entityType.knownValue == request.currentEntityType else { throw DiscordError.validation(.invalidValue) }
        if let status = request.currentStatus {
            guard current.status.knownValue == status else { throw DiscordError.validation(.invalidValue) }
        }
        guard case .object(let fields) = request.jsonValue() else { throw DiscordError.validation(.invalidValue) }
        let start: DiscordTimestamp
        if case .string(let text) = fields["scheduled_start_time"] { start = try DiscordTimestamp(rawValue: text) }
        else { start = current.scheduledStartTime }
        let end: DiscordTimestamp?
        switch fields["scheduled_end_time"] {
        case .string(let text): end = try DiscordTimestamp(rawValue: text)
        case .null: end = nil
        default: if case .value(let value) = current.scheduledEndTime { end = value } else { end = nil }
        }
        if fields["scheduled_start_time"] != nil || fields["scheduled_end_time"] != nil, let end {
            guard start.unixSeconds < end.unixSeconds || (start.unixSeconds == end.unixSeconds && start.nanosecond < end.nanosecond)
            else { throw DiscordError.validation(.invalidValue) }
        }
        guard fields.contains(where: { current.rawFields[$0.key] != $0.value }) else { return nil }
        return try GuildScheduledEventEndpoints.modify(guildID: current.guildID, eventID: current.id,
            request: request, auditReason: auditReason)
    }

    /// Produces one permitted status transition or skips an already-equal status.
    /// - Parameters:
    ///   - current: Caller-owned snapshot with known hosting and lifecycle discriminators.
    ///   - status: Desired known lifecycle state; scheduled->active/canceled and active->completed are allowed.
    ///   - auditReason: Optional supported reason, validated only when a PATCH is necessary.
    /// - Returns: Nil for equal states, otherwise one unsafe HTTP 200 PATCH changing only status.
    /// - Throws: Invalid-value for unknown context or disallowed terminal/reverse/skipped transitions;
    ///   descriptor/audit errors propagate. Discord may change status automatically before execution,
    ///   so local acceptance does not guarantee server acceptance and no hidden refresh/retry occurs.
    public static func transition(current: GuildScheduledEvent, to status: GuildScheduledEventStatus,
                                  auditReason: String? = nil) throws -> Endpoint<GuildScheduledEvent>? {
        guard let kind = current.entityType.knownValue, let from = current.status.knownValue
        else { throw DiscordError.validation(.invalidValue) }
        let request = try GuildScheduledEventModify(currentEntityType: kind, currentStatus: from, status: .value(status))
        return try modifyIfChanged(current: current, request: request, auditReason: auditReason)
    }

    /// Enumerates subscriber pages lazily, with strict ascending IDs inside each page in both directions.
    /// - Parameters:
    ///   - guildID: Owning guild, reauthorized by Discord on every request.
    ///   - eventID: Target event; foreign subscriber event IDs are invalid responses.
    ///   - position: Optional initial exclusive boundary; nil starts ascending after the oldest user.
    ///   - limit: Requested and accepted page size in 1...100, default 100.
    ///   - withMember: Whether to include member snapshots, default false; no member hydration occurs.
    ///   - maximumPages: Finite local request budget in 1...10,000, default 10,000.
    ///   - context: Shared cooperative cancellation, monotonic clock and optional deadline domain.
    ///   - execute: Sequential cancellation-cooperative executor using ordinary shared HTTP admission.
    /// - Returns: Lazy nonprefetching pages. Empty pages terminate after yielding once; short nonempty pages
    ///   continue. After advances to the largest user ID; before retreats to the smallest. Reuse is disabled.
    /// - Throws: Invalid-value for bad bounds before I/O; executor/cancellation/deadline/budget errors on pull;
    ///   invalid-response for oversized, foreign-event, missing-user, duplicate, unsorted or nonadvancing IDs.
    ///   Failures permanently finish the iterator. Concurrent subscriptions can affect traversal coverage.
    public static func userPages<C: Clock>(guildID: GuildID, eventID: GuildScheduledEventID,
        position: ScheduledEventUserPosition? = nil, limit: Int = 100, withMember: Bool = false,
        maximumPages: Int = 10_000, context: TransportContext<C>,
        execute: @escaping @Sendable (Endpoint<[GuildScheduledEventUser]>) async throws -> [GuildScheduledEventUser]
    ) throws -> CursorPagination<GuildScheduledEventUser, UserID, C> where C.Duration == Duration {
        guard (1...100).contains(limit), (1...10_000).contains(maximumPages) else { throw DiscordError.validation(.invalidValue) }
        let before: Bool
        let initial: UserID?
        switch position {
        case .before(let id): before = true; initial = id
        case .after(let id): before = false; initial = id
        case nil: before = false; initial = nil
        }
        return try CursorPagination(initialCursor: initial, maximumPages: maximumPages, context: context) { cursor in
            let boundary: ScheduledEventUserPosition? = cursor.map { before ? .before($0) : .after($0) }
            let page = try await execute(GuildScheduledEventEndpoints.users(guildID: guildID, eventID: eventID,
                limit: limit, withMember: withMember, position: boundary, readPolicy: nil))
            guard page.count <= limit else { throw DiscordError.transport(.invalidResponse) }
            var ids: [UserID] = []
            for entry in page {
                guard entry.guildScheduledEventID == eventID, case .value(let user) = entry.user
                else { throw DiscordError.transport(.invalidResponse) }
                if let previous = ids.last { guard user.id > previous else { throw DiscordError.transport(.invalidResponse) } }
                if let cursor { guard before ? user.id < cursor : user.id > cursor else { throw DiscordError.transport(.invalidResponse) } }
                ids.append(user.id)
            }
            return CursorPage(items: page, nextCursor: before ? ids.first : ids.last)
        }
    }
}

/// Explicit snapshot-only stage request reduction. It does not infer stage liveness or connect voice.
public enum StageInstanceOperations {
    /// Suppresses a stage PATCH if every explicit selected value equals the snapshot's exact wire value.
    /// - Parameters:
    ///   - current: Caller-owned complete stage whose channel identifies the mutation target.
    ///   - request: Validated optional edits; absent values do not participate.
    ///   - auditReason: Optional supported reason, validated only when a mutation is needed.
    /// - Returns: Nil for empty/matching edits; otherwise one ordinary unsafe PATCH without any read.
    /// - Throws: Invalid-value for a malformed request root, or normal descriptor/audit validation errors.
    ///   Array/numeric representation comparisons remain exact and stale snapshots retain reconciliation races.
    public static func modifyIfChanged(current: StageInstance, request: StageInstanceModify,
                                       auditReason: String? = nil) throws -> Endpoint<StageInstance>? {
        guard try expressionFieldsChanged(current.rawFields, request: request.jsonValue()) else { return nil }
        return try StageInstanceEndpoints.modify(channelID: current.channelID, request: request, auditReason: auditReason)
    }
}
