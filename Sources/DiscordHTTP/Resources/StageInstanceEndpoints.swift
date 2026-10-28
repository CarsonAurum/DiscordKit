// File: Sources/DiscordHTTP/Resources/StageInstanceEndpoints.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import DiscordModels
import Foundation

/// Four API v10 stage operations verified 2026-10-16 against
/// https://docs.discord.com/developers/resources/stage-instance and the official OpenAPI preview.
/// Mutations require stage moderator permissions MANAGE_CHANNELS, MUTE_MEMBERS and MOVE_MEMBERS;
/// start notifications additionally require MENTION_EVERYONE. No voice connection is started here.
public enum StageInstanceEndpoints {
    /// Creates a live stage in the requested Stage channel, without a voice or Gateway owner.
    /// - Parameters:
    ///   - request: Validated creation body containing the target channel and optional event association.
    ///   - auditReason: Optional supported reason of at most 512 Unicode scalars before encoding.
    /// - Returns: Unsafe POST descriptor requiring HTTP 200 with a complete stage snapshot.
    /// - Throws: Body/descriptor/audit errors now; authorization/state/API/transport or uncertain submission
    ///   errors on execution. Ambiguous writes are not replayed; rejected 429s share the bounded retry budget.
    public static func create(request: StageInstanceCreate, auditReason: String? = nil) throws -> Endpoint<StageInstance> {
        try stageInstanceMutation("POST", channelID: request.channelID, collection: true,
            payload: request.jsonValue(), auditReason: auditReason, decode: { try StageInstance(data: $0) })
    }

    /// Gets the live stage associated with one channel; missing stages remain server API errors.
    /// - Parameters:
    ///   - channelID: Stage channel and major channel rate partition.
    ///   - readPolicy: Optional credential-scoped reuse; default coalesces without completed caching.
    /// - Returns: Safe HTTP 200 GET descriptor with complete stage and unknown-field preservation.
    /// - Throws: Descriptor/policy errors now; auth/API/transport/schema failures on execution.
    public static func get(channelID: ChannelID, readPolicy: ReadPolicy? = ReadPolicy()) throws -> Endpoint<StageInstance> {
        try Endpoint(method: "GET", path: ["stage-instances", channelID.description],
            route: "/stage-instances/{channel.id}", authentication: .bot,
            majorParameter: channelID.description, retrySafety: .safe, readPolicy: scheduledEventReadPolicy(readPolicy),
            decode: { try StageInstance(data: $0) })
    }

    /// Updates explicitly selected topic/visibility fields without reading the current stage.
    /// - Parameters:
    ///   - channelID: Stage channel and major channel rate partition.
    ///   - request: Validated presence-aware edits; empty objects remain explicit PATCH bodies.
    ///   - auditReason: Optional supported audit reason, at most 512 Unicode scalars before encoding.
    /// - Returns: Unsafe HTTP 200 PATCH descriptor returning the updated stage.
    /// - Throws: Body/descriptor/audit errors now; permissions/state/API/transport or indeterminate outcomes later.
    public static func modify(channelID: ChannelID, request: StageInstanceModify,
                              auditReason: String? = nil) throws -> Endpoint<StageInstance> {
        try stageInstanceMutation("PATCH", channelID: channelID, payload: request.jsonValue(),
            auditReason: auditReason, decode: { try StageInstance(data: $0) })
    }

    /// Removes the channel's live stage with strict empty HTTP 204 success semantics.
    /// - Parameters:
    ///   - channelID: Target Stage channel and major channel rate partition.
    ///   - auditReason: Optional supported reason of at most 512 Unicode scalars before encoding.
    /// - Returns: Unsafe DELETE descriptor with stage/event/invite/audit invalidation.
    /// - Throws: Descriptor/audit errors now; auth/API/transport or uncertain deletion outcomes at execution.
    public static func delete(channelID: ChannelID, auditReason: String? = nil) throws -> Endpoint<EmptyResponse> {
        try stageInstanceMutation("DELETE", channelID: channelID, auditReason: auditReason,
            successStatuses: [204], decode: { try EmptyResponse(data: $0) })
    }
}

/// Builds one stage mutation without starting voice ownership, hidden reads or background work.
/// - Parameters:
///   - method: Explicit mutation verb, retaining unsafe replay policy.
///   - channelID: Stage channel partition and invalidation scope.
///   - collection: True only for POST creation, whose body carries channel_id; defaults to false.
///   - payload: Optional validated JSON object; nil sends no body.
///   - auditReason: Optional supported audit header, validated before I/O.
///   - successStatuses: Exact accepted statuses, default 200 or 204 for deletion.
///   - decode: Bounded complete model or empty-response projection.
/// - Returns: Immutable descriptor with conservative stage/event/invite/guild/audit invalidation.
/// - Throws: Body/descriptor/audit validation errors; server state and submission outcomes remain execution concerns.
func stageInstanceMutation<T: Sendable>(_ method: String, channelID: ChannelID, collection: Bool = false,
    payload: JSONValue? = nil, auditReason: String? = nil, successStatuses: Set<Int> = [200],
    decode: @escaping @Sendable (Data) throws -> T) throws -> Endpoint<T> {
    try Endpoint(method: method, path: ["stage-instances"] + (collection ? [] : [channelID.description]),
        route: "/stage-instances" + (collection ? "" : "/{channel.id}"), authentication: .bot,
        successStatuses: successStatuses, majorParameter: channelID.description, auditReason: auditReason,
        body: payload.map { try guildJSON($0) },
        invalidates: channelTags(channelID).union(["scheduled-event-catalog", "stage-instance-catalog", "invite-catalog", "guild-catalog", "audit-log-catalog"]), decode: decode)
}
