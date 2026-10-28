// File: Sources/DiscordHTTP/Resources/LobbyEndpoints.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import DiscordModels
import Foundation

/// All written API v10 Lobby operations, verified 2026-10-16 against the official Lobby reference.
/// Descriptors perform no I/O or privilege discovery. Bearer operations require `sdk.social_layer`
/// where documented; Discord verifies application ownership, membership and channel-link eligibility.
/// All writes use conservative unsafe replay semantics, including idempotent removal contracts.
/// Development quotas are application-wide, not per user; ordinary coordinated admission still applies.
public enum LobbyEndpoints {
    /// Creates an application-owned lobby with at most 25 initial members.
    /// Social SDK clients cannot independently join or leave lobbies created through this bot operation.
    /// - Parameter request: Validated optional metadata, members and idle timeout; omission preserves defaults.
    /// - Returns: Bot-only POST requiring HTTP 201 and a Lobby, invalidating scoped lobby snapshots.
    /// - Throws: Body/descriptor errors now; API, schema, cancellation or uncertain submission errors on execution.
    public static func create(request: CreateLobbyRequest) throws -> Endpoint<Lobby> {
        try lobbyMutation("POST", payload: request.jsonValue(), successStatuses: [201], decode: { try Lobby(data: $0) })
    }

    /// Creates or joins the calling user's lobby by its application-scoped secret, updating supplied metadata.
    /// - Parameter request: Validated secret and optional replacement metadata/idle timeout; secret is never logged.
    /// - Returns: Bearer-only PUT requiring `sdk.social_layer` and HTTP 200 with the Lobby.
    /// - Throws: Body/descriptor errors now; auth/scopes/API/schema or uncertain mutation failures on execution.
    /// Existing metadata is overwritten when supplied; no preliminary lookup or ambiguous replay is performed.
    public static func createOrJoin(request: CreateOrJoinLobbyRequest) throws -> Endpoint<Lobby> {
        try lobbyMutation("PUT", authentication: .bearer, payload: request.jsonValue(), decode: { try Lobby(data: $0) })
    }

    /// Fetches one application-owned lobby without fetching related members, channels or user profiles.
    /// - Parameters:
    ///   - lobbyID: Exact lobby snowflake; nonexistence remains an API error.
    ///   - readPolicy: Optional credential-scoped read reuse; default coalesces without completed caching.
    ///     Explicit positive TTL snapshots can be stale after external membership/metadata/link changes.
    /// - Returns: Bot-only safe HTTP 200 GET descriptor preserving the complete Lobby projection.
    /// - Throws: Descriptor/policy errors now; auth/API/transport/schema/cancellation errors during execution.
    public static func get(lobbyID: LobbyID, readPolicy: ReadPolicy? = ReadPolicy()) throws -> Endpoint<Lobby> {
        try Endpoint(method: "GET", path: ["lobbies", lobbyID.description], route: "/lobbies/{lobby.id}",
            authentication: .bot, retrySafety: .safe, readPolicy: lobbyReadPolicy(readPolicy),
            decode: { try Lobby(data: $0) })
    }

    /// Replaces explicitly supplied lobby settings; supplied members replace the entire membership array.
    /// - Parameters:
    ///   - lobbyID: Application-owned lobby to edit; no ownership discovery is performed.
    ///   - request: Validated edits; omitted fields remain unchanged and explicit null metadata clears metadata.
    /// - Returns: Bot-only unsafe PATCH requiring HTTP 200 with the updated Lobby.
    /// - Throws: Body/descriptor errors now; API/schema/cancellation or indeterminate submitted mutation later.
    /// Never chunk a replacement member list: use the explicit bulk membership operation for incremental edits.
    public static func modify(lobbyID: LobbyID, request: ModifyLobbyRequest) throws -> Endpoint<Lobby> {
        try lobbyMutation("PATCH", lobbyID: lobbyID, payload: request.jsonValue(), decode: { try Lobby(data: $0) })
    }

    /// Deletes an application-owned lobby; Discord permits calls after the lobby has already been deleted.
    /// - Parameter lobbyID: Exact lobby to delete, without an existence check.
    /// - Returns: Bot-only unsafe DELETE requiring empty HTTP 204 and conservative scoped invalidation.
    /// - Throws: Descriptor errors now; API/transport/cancellation or uncertain submission errors at execution.
    public static func delete(lobbyID: LobbyID) throws -> Endpoint<EmptyResponse> {
        try lobbyMutation("DELETE", lobbyID: lobbyID, successStatuses: [204], decode: { try EmptyResponse(data: $0) })
    }

    /// Adds a user or updates supplied fields of an existing member without replacing other members.
    /// - Parameters:
    ///   - lobbyID: Application-owned target lobby.
    ///   - userID: Exact user to add/update; Discord validates permission and per-application lobby limits.
    ///   - request: Validated metadata/flags/additional name; omission preserves existing values.
    /// - Returns: Bot-only unsafe PUT requiring HTTP 200 with the returned LobbyMember.
    /// - Throws: Body/descriptor errors now; API/schema or uncertain mutation/cancellation failures later.
    public static func addMember(lobbyID: LobbyID, userID: UserID,
                                 request: ModifyLobbyMemberRequest) throws -> Endpoint<LobbyMember> {
        try lobbyMutation("PUT", lobbyID: lobbyID, suffix: ["members", userID.description],
            routeSuffix: "/members/{user.id}", payload: request.jsonValue(), decode: { try LobbyMember(data: $0) })
    }

    /// Applies 1...25 explicit incremental member upserts/removals in one documented bulk request.
    /// - Parameters:
    ///   - lobbyID: Application-owned target lobby.
    ///   - request: Unique validated users; `remove_member` true removes, false/omitted upserts.
    /// - Returns: Bot-only unsafe HTTP 200 POST with only acknowledged upserts, in upstream order.
    ///   Removed users are omitted; permission/lobby-cap failures can silently omit upserts. Empty is valid.
    /// - Throws: Body/descriptor errors now; invalid-response for duplicate, unrequested or removed response IDs,
    ///   or ordinary API/transport/schema/uncertain-mutation/cancellation failures during execution.
    /// Unknown users produce upstream 404. No fallback, individual retry or membership hydration occurs.
    public static func bulkUpdateMembers(lobbyID: LobbyID,
        request: BulkUpdateLobbyMembersRequest) throws -> Endpoint<[LobbyMember]> {
        let allowed = Set(request.members.filter { $0.removeMember != true }.map(\.id))
        return try lobbyMutation("POST", lobbyID: lobbyID, suffix: ["members", "bulk"],
            routeSuffix: "/members/bulk", payload: request.jsonValue(),
            bulk: .init(maximumItems: 25, preservesOrder: false, permitsPartialResults: true,
                documentationURL: URL(string: "https://docs.discord.com/developers/resources/lobby#bulk-update-lobby-members")!),
            decode: { data in
                let members = try guildArray(data) { try LobbyMember(data: $0) }
                let ids = members.map(\.id)
                guard ids.count <= allowed.count, Set(ids).count == ids.count, Set(ids).isSubset(of: allowed)
                else { throw DiscordError.transport(.invalidResponse) }
                return members
            })
    }

    /// Removes a user, including an already absent member, while a missing lobby remains an API error.
    /// - Parameters:
    ///   - lobbyID: Application-owned target lobby.
    ///   - userID: Exact user whose membership is removed, without preliminary lookup.
    /// - Returns: Bot-only unsafe DELETE requiring empty HTTP 204.
    /// - Throws: Descriptor errors now; API/schema/cancellation or uncertain mutation outcome later.
    public static func removeMember(lobbyID: LobbyID, userID: UserID) throws -> Endpoint<EmptyResponse> {
        try lobbyMutation("DELETE", lobbyID: lobbyID, suffix: ["members", userID.description],
            routeSuffix: "/members/{user.id}", successStatuses: [204], decode: { try EmptyResponse(data: $0) })
    }

    /// Removes the bearer-authenticated caller, including an already absent member; missing lobbies still fail.
    /// - Parameter lobbyID: Exact lobby to leave; no caller ID or membership fetch is required.
    /// - Returns: Bearer-only unsafe DELETE requiring empty HTTP 204.
    /// - Throws: Descriptor errors now; auth/API/schema/cancellation or uncertain submitted-mutation errors later.
    public static func leave(lobbyID: LobbyID) throws -> Endpoint<EmptyResponse> {
        try lobbyMutation("DELETE", lobbyID: lobbyID, suffix: ["members", "@me"], routeSuffix: "/members/@me",
            authentication: .bearer, successStatuses: [204], decode: { try EmptyResponse(data: $0) })
    }

    /// Links an existing text channel using a bearer-authenticated member with the CanLinkLobby flag.
    /// - Parameters:
    ///   - lobbyID: Lobby whose link is replaced; Discord checks channel eligibility and permissions.
    ///   - channelID: Existing text channel to link; no channel hydration occurs.
    /// - Returns: Bearer-only unsafe PATCH requiring HTTP 200 with the linked Lobby.
    /// - Throws: Body/descriptor errors now; permission/API/schema or uncertain mutation/cancellation errors later.
    public static func linkChannel(lobbyID: LobbyID, channelID: ChannelID) throws -> Endpoint<Lobby> {
        try lobbyMutation("PATCH", lobbyID: lobbyID, suffix: ["channel-linking"], routeSuffix: "/channel-linking",
            authentication: .bearer, payload: LinkLobbyChannelRequest(channelID: channelID).jsonValue(),
            decode: { try Lobby(data: $0) })
    }

    /// Unlinks any channel using a bearer-authenticated lobby member with CanLinkLobby.
    /// - Parameter lobbyID: Lobby to unlink; no current-link lookup is performed.
    /// - Returns: Bearer-only unsafe PATCH with an empty JSON object, requiring HTTP 200 with the unlinked Lobby.
    /// - Throws: Body/descriptor errors now; auth/permission/API/schema or uncertain submission/cancellation later.
    public static func unlinkChannel(lobbyID: LobbyID) throws -> Endpoint<Lobby> {
        try lobbyMutation("PATCH", lobbyID: lobbyID, suffix: ["channel-linking"], routeSuffix: "/channel-linking",
            authentication: .bearer, payload: .object([:]), decode: { try Lobby(data: $0) })
    }

    /// Sends one message as the bearer-authenticated lobby member, requiring `sdk.social_layer`.
    /// - Parameters:
    ///   - lobbyID: Lobby the caller currently belongs to.
    ///   - request: Nonempty content, optional dispatch metadata and server-validated SDK-creatable flags.
    /// - Returns: Unsafe POST requiring HTTP 201 with the created LobbyMessage.
    /// - Throws: Body/descriptor errors now; membership/scopes/API/schema or uncertain mutation/cancellation later.
    /// Linked-channel forwarding can fail independently (for example AutoMod) while lobby delivery succeeds;
    /// the returned lobby message does not prove linked-channel delivery. Dispatch metadata is not persisted there.
    public static func sendMessage(lobbyID: LobbyID, request: SendLobbyMessageRequest) throws -> Endpoint<LobbyMessage> {
        try lobbyMutation("POST", lobbyID: lobbyID, suffix: ["messages"], routeSuffix: "/messages",
            authentication: .bearer, payload: request.jsonValue(), successStatuses: [201],
            decode: { try LobbyMessage(data: $0) })
    }

    /// Fetches one finite recent-message snapshot for a bearer-authenticated lobby member with `sdk.social_layer`.
    /// - Parameters:
    ///   - lobbyID: Exact lobby; membership remains authoritative upstream.
    ///   - limit: Optional inclusive 1...200 result cap; nil preserves upstream default 50.
    ///   - readPolicy: Credential-scoped reuse, coalescing only by default; nil disables reuse.
    /// - Returns: Safe HTTP 200 GET preserving wire order and empty snapshots; there is no documented cursor.
    /// - Throws: Invalid limit/policy/descriptor now; oversized arrays, schema/API/cancellation failures later.
    /// No invented before/after pagination, hidden traversal, or message/user hydration is performed.
    public static func messages(lobbyID: LobbyID, limit: Int? = nil,
                                readPolicy: ReadPolicy? = ReadPolicy()) throws -> Endpoint<[LobbyMessage]> {
        guard limit.map({ (1...200).contains($0) }) ?? true else { throw DiscordError.validation(.invalidValue) }
        return try Endpoint(method: "GET", path: ["lobbies", lobbyID.description, "messages"],
            route: "/lobbies/{lobby.id}/messages", query: limit.map { [.init(name: "limit", value: String($0))] } ?? [],
            authentication: .bearer, retrySafety: .safe, readPolicy: lobbyReadPolicy(readPolicy), decode: { data in
                let messages = try guildArray(data) { try LobbyMessage(data: $0) }
                guard messages.count <= (limit ?? 50) else { throw DiscordError.transport(.invalidResponse) }
                return messages
            })
    }

    /// Replaces app-scoped moderation metadata, delivered to active Social SDK clients as a realtime update.
    /// - Parameters:
    ///   - lobbyID: Application-owned lobby containing the message.
    ///   - messageID: Exact lobby message to moderate; no message fetch occurs.
    ///   - request: Validated free-form root dictionary, at most five keys of 1,024 and values of 2,000 characters.
    /// - Returns: Bot-only unsafe PUT requiring empty HTTP 204; no message-content edit is implied.
    /// - Throws: Body/descriptor errors now; auth/API/schema/cancellation or uncertain mutation outcome later.
    public static func updateMessageModeration(lobbyID: LobbyID, messageID: MessageID,
        request: LobbyMessageModerationRequest) throws -> Endpoint<EmptyResponse> {
        try lobbyMutation("PUT", lobbyID: lobbyID, suffix: ["messages", messageID.description, "moderation-metadata"],
            routeSuffix: "/messages/{message.id}/moderation-metadata", payload: request.jsonValue(),
            successStatuses: [204], decode: { try EmptyResponse(data: $0) })
    }

    /// Creates a single-use, one-hour guild invite to the linked channel for the calling lobby member.
    /// - Parameter lobbyID: Lobby with an existing linked channel; caller needs bearer `sdk.social_layer` scope.
    /// - Returns: Unsafe HTTP 200 POST with a LobbyInvite code, without accepting or using that invite.
    /// - Throws: Descriptor errors now; missing-link/membership/scopes/API/schema or uncertain mutation later.
    public static func createChannelInviteForSelf(lobbyID: LobbyID) throws -> Endpoint<LobbyInvite> {
        try lobbyMutation("POST", lobbyID: lobbyID, suffix: ["members", "@me", "invites"],
            routeSuffix: "/members/@me/invites", authentication: .bearer, decode: { try LobbyInvite(data: $0) })
    }

    /// Creates an application-issued single-use, one-hour linked-channel guild invite targeted at one user.
    /// - Parameters:
    ///   - lobbyID: Application-owned lobby with an existing linked channel.
    ///   - userID: Exact invite target; Discord verifies eligibility without local user hydration.
    /// - Returns: Bot-only unsafe HTTP 200 POST with the LobbyInvite code; no invite acceptance occurs.
    /// - Throws: Descriptor errors now; auth/link/eligibility/API/schema or uncertain mutation/cancellation later.
    public static func createChannelInviteForUser(lobbyID: LobbyID, userID: UserID) throws -> Endpoint<LobbyInvite> {
        try lobbyMutation("POST", lobbyID: lobbyID, suffix: ["members", userID.description, "invites"],
            routeSuffix: "/members/{user.id}/invites", decode: { try LobbyInvite(data: $0) })
    }
}

/// Conservative family invalidation also covers related guild/channel/invite and forwarded-message projections.
/// Credential identity scopes these finite tags; external writes remain stale until caller-selected TTL expiry.
let lobbyTags: Set<String> = ["lobby-catalog", "channel-catalog", "guild-catalog", "invite-catalog", "message-catalog"]

/// Adds lobby dependencies while retaining the caller's explicit coalescing and freshness choices.
/// - Parameter policy: Optional reuse choices; nil disables completed and in-flight sharing.
/// - Returns: Equivalent scoped policy including conservative dependency tags, without I/O or cache creation.
func lobbyReadPolicy(_ policy: ReadPolicy?) -> ReadPolicy? {
    policy.map { .init(coalescing: $0.coalescing, timeToLive: $0.timeToLive, tags: $0.tags.union(lobbyTags)) }
}

/// Constructs a bounded, explicitly unsafe Lobby mutation without synthetic major rate partitions.
/// - Parameters:
///   - method: Exact uppercase documented mutation method.
///   - lobbyID: Optional target; nil addresses the lobby collection.
///   - suffix: Fixed action segments and exact typed IDs, default empty.
///   - routeSuffix: Matching stable route template, default empty.
///   - authentication: Required credential category, default bot; written user operations select bearer.
///   - payload: Validated JSON body, or nil for bodyless operations.
///   - successStatuses: Exact accepted success set, default HTTP 200.
///   - bulk: Optional operation-specific upstream bulk metadata; never triggers combining requests.
///   - decode: Original synchronous typed decoder; strict empty validation remains active for HTTP 204.
/// - Returns: Descriptor invalidating scoped dependencies on observed success; no I/O occurs.
/// - Throws: Body/metadata/descriptor validation errors synchronously; submission uncertainty belongs to execution.
func lobbyMutation<T: Sendable>(_ method: String, lobbyID: LobbyID? = nil, suffix: [String] = [],
    routeSuffix: String = "", authentication: AuthenticationPolicy = .bot, payload: JSONValue? = nil,
    successStatuses: Set<Int> = [200], bulk: BulkOperationMetadata? = nil,
    decode: @escaping @Sendable (Data) throws -> T) throws -> Endpoint<T> {
    try Endpoint(method: method, path: ["lobbies"] + (lobbyID.map { [$0.description] } ?? []) + suffix,
        route: "/lobbies" + (lobbyID == nil ? "" : "/{lobby.id}") + routeSuffix,
        authentication: authentication, successStatuses: successStatuses,
        body: payload.map { try guildJSON($0) }, retrySafety: .unsafe,
        invalidates: lobbyTags, bulk: bulk, decode: decode)
}
