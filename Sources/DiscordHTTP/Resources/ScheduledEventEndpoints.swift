// File: Sources/DiscordHTTP/Resources/ScheduledEventEndpoints.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import DiscordModels
import Foundation

/// Exclusive subscriber cursor; choosing one direction avoids upstream before-over-after precedence.
public enum ScheduledEventUserPosition: Sendable, Equatable {
    /// Users below this ID, still returned in ascending ID order.
    case before(UserID)
    /// Users above this ID, returned in ascending ID order.
    case after(UserID)
}

/// Six API v10 scheduled-event operations verified 2026-10-16 against
/// https://docs.discord.com/developers/resources/guild-scheduled-event and the official OpenAPI preview.
/// Discord checks guild visibility and VIEW_CHANNEL; creation requires CREATE_EVENTS. Editing/deleting
/// own events requires CREATE_EVENTS or MANAGE_EVENTS; other events require MANAGE_EVENTS. Stage events
/// additionally require moderator permissions, voice events VIEW_CHANNEL/CONNECT. Shared REST admission,
/// finite 429 budgets, cancellation and transport ownership are inherited from the executor.
public enum GuildScheduledEventEndpoints {
    /// Lists all visible guild events in one request, without inventing pagination or per-event hydration.
    /// - Parameters:
    ///   - guildID: Owning guild and major rate partition.
    ///   - withUserCount: Optional count inclusion; nil preserves upstream default.
    ///   - readPolicy: Optional credential-scoped reuse; default coalesces without completed caching.
    /// - Returns: Safe HTTP 200 GET descriptor returning complete ordered events, including an empty list.
    /// - Throws: Descriptor/policy errors now; auth/API/transport/schema failures on explicit execution.
    public static func list(guildID: GuildID, withUserCount: Bool? = nil,
                            readPolicy: ReadPolicy? = ReadPolicy()) throws -> Endpoint<[GuildScheduledEvent]> {
        try Endpoint(method: "GET", path: ["guilds", guildID.description, "scheduled-events"],
            route: "/guilds/{guild.id}/scheduled-events", query: scheduledEventCountQuery(withUserCount),
            authentication: .bot, majorParameter: guildID.description, retrySafety: .safe,
            readPolicy: scheduledEventReadPolicy(readPolicy), decode: { try guildArray($0) { try GuildScheduledEvent(data: $0) } })
    }

    /// Gets one event without related-user, channel or recurrence-exception requests.
    /// - Parameters:
    ///   - guildID: Owning guild and major rate partition.
    ///   - eventID: Exact event ID, checked for guild ownership upstream.
    ///   - withUserCount: Optional subscriber-count inclusion; nil omits the query parameter.
    ///   - readPolicy: Optional credential-scoped reuse; default coalesces without completed caching.
    /// - Returns: Safe HTTP 200 GET descriptor; missing resources remain API errors rather than cached absence.
    /// - Throws: Descriptor/policy errors now; auth/API/transport/schema errors at execution.
    public static func get(guildID: GuildID, eventID: GuildScheduledEventID, withUserCount: Bool? = nil,
                           readPolicy: ReadPolicy? = ReadPolicy()) throws -> Endpoint<GuildScheduledEvent> {
        try Endpoint(method: "GET", path: ["guilds", guildID.description, "scheduled-events", eventID.description],
            route: "/guilds/{guild.id}/scheduled-events/{event.id}", query: scheduledEventCountQuery(withUserCount),
            authentication: .bot, majorParameter: guildID.description, retrySafety: .safe,
            readPolicy: scheduledEventReadPolicy(readPolicy), decode: { try GuildScheduledEvent(data: $0) })
    }

    /// Creates a validated event without checking the guild's current 100 scheduled/active-event capacity.
    /// - Parameters:
    ///   - guildID: Owning guild and major rate partition.
    ///   - request: Validated stage, voice or external creation body.
    ///   - auditReason: Optional supported audit reason, at most 512 Unicode scalars before encoding.
    /// - Returns: One unsafe POST descriptor requiring HTTP 200 with the created event.
    /// - Throws: Body/descriptor/audit errors now; API/transport or indeterminate submission errors later.
    ///   Ambiguous mutations are never automatically replayed; rejected 429 attempts share the finite budget.
    public static func create(guildID: GuildID, request: GuildScheduledEventCreate,
                              auditReason: String? = nil) throws -> Endpoint<GuildScheduledEvent> {
        try scheduledEventMutation("POST", guildID: guildID, payload: request.jsonValue(), auditReason: auditReason,
            decode: { try GuildScheduledEvent(data: $0) })
    }

    /// Modifies one event from explicit caller context; Discord rechecks permissions and current lifecycle.
    /// - Parameters:
    ///   - guildID: Owning guild and major rate partition.
    ///   - eventID: Exact target event.
    ///   - request: Validated presence-aware edits; no hidden context fetch occurs.
    ///   - auditReason: Optional supported audit reason of at most 512 Unicode scalars before encoding.
    /// - Returns: Unsafe PATCH descriptor requiring HTTP 200 with the updated event.
    /// - Throws: Body/descriptor/audit errors now; auth/state/API/transport or uncertain mutation outcomes later.
    public static func modify(guildID: GuildID, eventID: GuildScheduledEventID, request: GuildScheduledEventModify,
                              auditReason: String? = nil) throws -> Endpoint<GuildScheduledEvent> {
        try scheduledEventMutation("PATCH", guildID: guildID, eventID: eventID, payload: request.jsonValue(),
            auditReason: auditReason, decode: { try GuildScheduledEvent(data: $0) })
    }

    /// Deletes one event with strict empty HTTP 204 success semantics.
    /// - Parameters:
    ///   - guildID: Owning guild and major rate partition.
    ///   - eventID: Event to remove; missing resources remain server errors.
    /// - Returns: Unsafe DELETE descriptor invalidating scoped event/stage/invite and audit snapshots.
    /// - Throws: Descriptor errors now; auth/API/transport or indeterminate outcomes on execution.
    ///   The written endpoint does not advertise an audit-reason header, so none is exposed here.
    public static func delete(guildID: GuildID, eventID: GuildScheduledEventID) throws -> Endpoint<EmptyResponse> {
        try scheduledEventMutation("DELETE", guildID: guildID, eventID: eventID,
            successStatuses: [204], decode: { try EmptyResponse(data: $0) })
    }

    /// Gets one subscriber page; before/after always return users in ascending user-ID order.
    /// - Parameters:
    ///   - guildID: Owning guild and major rate partition.
    ///   - eventID: Target event; subscriber event IDs are checked when decoding.
    ///   - limit: Optional 1...100 subscriber limit; nil preserves server default 100.
    ///   - withMember: Optional member inclusion; nil preserves upstream default false.
    ///   - position: Optional exclusive before/after user boundary; only one direction can be selected.
    ///   - readPolicy: Optional credential-scoped reuse; default coalesces with no completed caching.
    /// - Returns: Safe HTTP 200 GET descriptor returning a complete ordered subscriber page.
    /// - Throws: Invalid-value for bad limit or descriptor/policy errors now; API/transport or invalid-response
    ///   for missing user objects, mismatched event/IDs, excessive counts or nonascending IDs at execution.
    public static func users(guildID: GuildID, eventID: GuildScheduledEventID, limit: Int? = nil,
        withMember: Bool? = nil, position: ScheduledEventUserPosition? = nil,
        readPolicy: ReadPolicy? = ReadPolicy()) throws -> Endpoint<[GuildScheduledEventUser]> {
        var query: [QueryItem] = []
        if let limit {
            guard (1...100).contains(limit) else { throw DiscordError.validation(.invalidValue) }
            query.append(.init(name: "limit", value: String(limit)))
        }
        if let withMember { query.append(.init(name: "with_member", value: String(withMember))) }
        switch position {
        case .before(let id): query.append(.init(name: "before", value: id.description))
        case .after(let id): query.append(.init(name: "after", value: id.description))
        case nil: break
        }
        return try Endpoint(method: "GET", path: ["guilds", guildID.description, "scheduled-events", eventID.description, "users"],
            route: "/guilds/{guild.id}/scheduled-events/{event.id}/users", query: query,
            authentication: .bot, majorParameter: guildID.description, retrySafety: .safe,
            readPolicy: scheduledEventReadPolicy(readPolicy), decode: { data in
                let users = try guildArray(data) { try GuildScheduledEventUser(data: $0) }
                guard users.count <= (limit ?? 100) else { throw DiscordError.transport(.invalidResponse) }
                var previous: UserID?
                for entry in users {
                    guard entry.guildScheduledEventID == eventID, case .value(let user) = entry.user else { throw DiscordError.transport(.invalidResponse) }
                    if let previous { guard user.id > previous else { throw DiscordError.transport(.invalidResponse) } }
                    switch position {
                    case .before(let id): guard user.id < id else { throw DiscordError.transport(.invalidResponse) }
                    case .after(let id): guard user.id > id else { throw DiscordError.transport(.invalidResponse) }
                    case nil: break
                    }
                    previous = user.id
                }
                return users
            })
    }
}

/// Encodes optional count inclusion without inventing server defaults.
/// - Parameter value: Nil omits the parameter; true and false are both explicit selections.
/// - Returns: Empty query or one stable with_user_count item; performs no I/O.
func scheduledEventCountQuery(_ value: Bool?) -> [QueryItem] {
    value.map { [.init(name: "with_user_count", value: String($0))] } ?? []
}

/// Preserves caller reuse choices while adding catalog dependencies invalidated by local writes.
/// - Parameter policy: Optional scoped policy; nil disables caching and coalescing entirely.
/// - Returns: Equivalent freshness/coalescing plus event, stage, invite and guild tags; no cache is populated.
func scheduledEventReadPolicy(_ policy: ReadPolicy?) -> ReadPolicy? {
    policy.map { ReadPolicy(coalescing: $0.coalescing, timeToLive: $0.timeToLive,
        tags: $0.tags.union(["scheduled-event-catalog", "stage-instance-catalog", "invite-catalog", "guild-catalog", "channel-catalog"])) }
}

/// Builds an ordinary conservative event mutation using the common guild admission partition.
/// - Parameters:
///   - method: POST, PATCH or DELETE; all mutations retain unsafe replay policy.
///   - guildID: Owning guild and major rate partition.
///   - eventID: Optional target; nil addresses the event collection.
///   - payload: Optional previously validated body; nil sends none.
///   - auditReason: Optional supported audit reason, validated by Endpoint.
///   - successStatuses: Exact success status set; defaults to 200, deletion uses 204.
///   - decode: Operation-specific bounded response projection.
/// - Returns: Immutable descriptor with scoped event/stage/invite/audit invalidation and no tasks.
/// - Throws: Body/descriptor/audit validation errors before I/O; server state remains execution-validated.
func scheduledEventMutation<T: Sendable>(_ method: String, guildID: GuildID, eventID: GuildScheduledEventID? = nil,
    payload: JSONValue? = nil, auditReason: String? = nil, successStatuses: Set<Int> = [200],
    decode: @escaping @Sendable (Data) throws -> T) throws -> Endpoint<T> {
    try Endpoint(method: method, path: ["guilds", guildID.description, "scheduled-events"] + (eventID.map { [$0.description] } ?? []),
        route: "/guilds/{guild.id}/scheduled-events" + (eventID == nil ? "" : "/{event.id}"),
        authentication: .bot, successStatuses: successStatuses, majorParameter: guildID.description,
        auditReason: auditReason, body: payload.map { try scheduledEventJSON($0) },
        invalidates: guildTags(guildID).union(["scheduled-event-catalog", "stage-instance-catalog", "invite-catalog", "audit-log-catalog"]), decode: decode)
}

/// Serializes event-cover payloads within an explicit encoded-body cap that includes base64 expansion.
/// - Parameter value: Previously validated event body, whose image has at most 1 MiB decoded bytes.
/// - Returns: Replayable application/json bytes bounded at 2 MiB, covering image expansion and field overhead.
/// - Throws: JSON syntax/depth/node/encoded-byte errors or RequestBody validation errors before any I/O.
func scheduledEventJSON(_ value: JSONValue) throws -> RequestBody {
    try RequestBody(bytes: value.serialized(limits: .init(maximumBytes: 2_097_152)),
        contentType: "application/json", maximumBytes: 2_097_152)
}
