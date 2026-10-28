// File: Sources/DiscordHTTP/Resources/ChannelEndpoints.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import DiscordModels
import DiscordTransport
import Foundation

/// API v10 channel and thread operations, verified 2026-10-16 against the official
/// Channel reference and Guild active-thread endpoint. No Gateway connection is needed.
///
/// All operations use bot authorization, including application-managed group DMs;
/// adding a recipient additionally requires that user's separate `gdm.join` access token
/// in the body. Server permissions and application eligibility remain authoritative.
/// Every execution shares the client's credential-global/channel rate admission,
/// bounded queues, retry budget, cancellation and deadline. Mutations do not replay
/// ambiguous submissions. Reads coalesce by default; completed caching requires a TTL.
/// See https://docs.discord.com/developers/resources/channel.
public enum ChannelEndpoints {
    /// Gets one visible channel, including current membership when the channel is a thread.
    /// - Parameters:
    ///   - channelID: Exact channel identifier and major rate partition.
    ///   - readPolicy: Optional scoped reuse; default coalesces without completed caching.
    /// - Returns: A safe GET descriptor decoding a presence-aware Channel, including unknown fields.
    /// - Throws: Descriptor errors now; API/transport/schema errors on execution. Missing channels
    ///   and forbidden access are not converted to absent values or authorization evidence.
    public static func get(channelID: ChannelID, readPolicy: ReadPolicy? = ReadPolicy()) throws -> Endpoint<Channel> {
        try Endpoint(method: "GET", path: ["channels", channelID.description], route: "/channels/{channel.id}",
            authentication: .bot, majorParameter: channelID.description, retrySafety: .safe,
            readPolicy: channelReadPolicy(readPolicy), decode: { try Channel(data: $0) })
    }

    /// Changes settings using the request's explicit channel-type context. Guild settings require
    /// MANAGE_CHANNELS; overwrites also MANAGE_ROLES. Thread changes generally require
    /// MANAGE_THREADS; unarchiving an unlocked thread can use SEND_MESSAGES. Discord validates state.
    /// - Parameters:
    ///   - channelID: Target and channel-major partition.
    ///   - request: Validated group-DM, guild-channel or thread settings; omission retains state.
    ///   - auditReason: Optional supported audit reason, at most 512 Unicode scalars.
    /// - Returns: An unsafe PATCH descriptor decoding updated channel data and invalidating channel/message reads.
    /// - Throws: Descriptor/audit errors; execution preserves API failure or uncertain mutation outcome.
    public static func modify(channelID: ChannelID, request: ChannelModify, auditReason: String? = nil) throws -> Endpoint<Channel> {
        try channelMutation("PATCH", channelID: channelID, path: ["channels", channelID.description],
            route: "/channels/{channel.id}", body: channelJSON(request.jsonValue()), auditReason: auditReason)
    }

    /// Deletes a guild channel or closes an application-accessible DM. Requires MANAGE_CHANNELS
    /// for guild channels or MANAGE_THREADS for threads. Category children are retained by Discord.
    /// - Parameters:
    ///   - channelID: Channel to delete; deleting a guild channel is irreversible upstream.
    ///   - auditReason: Optional supported audit reason, at most 512 Unicode scalars.
    /// - Returns: An unsafe DELETE descriptor returning the deleted Channel snapshot.
    /// - Throws: Descriptor/audit errors; API failures or uncertain submission on execution. Community
    ///   rules/updates channels cannot be deleted. No child resource is fetched or deleted locally.
    public static func delete(channelID: ChannelID, auditReason: String? = nil) throws -> Endpoint<Channel> {
        try channelMutation("DELETE", channelID: channelID, path: ["channels", channelID.description],
            route: "/channels/{channel.id}", auditReason: auditReason)
    }

    /// Sets or clears a voice channel's status. Requires SET_VOICE_CHANNEL_STATUS and,
    /// when the bot is disconnected, MANAGE_CHANNELS. Status is not a Channel response field.
    /// - Parameters:
    ///   - channelID: Voice channel major-rate partition.
    ///   - request: Validated required nullable status, up to 500 characters.
    ///   - auditReason: Optional supported audit reason, at most 512 Unicode scalars.
    /// - Returns: An unsafe PUT descriptor expecting an empty 204 response.
    /// - Throws: Descriptor/audit errors; API/transport or uncertain mutation errors during execution.
    public static func setVoiceStatus(channelID: ChannelID, request: VoiceChannelStatus,
                                      auditReason: String? = nil) throws -> Endpoint<EmptyResponse> {
        try channelEmpty("PUT", channelID: channelID, suffix: ["voice-status"],
            route: "/channels/{channel.id}/voice-status", body: channelJSON(request.jsonValue()), auditReason: auditReason)
    }

    /// Replaces one guild-channel permission overwrite; requires MANAGE_ROLES. Only permissions
    /// the bot may grant/deny can be changed; decimal-string bitsets are never narrowed to UInt64.
    /// - Parameters:
    ///   - channelID: Channel major-rate partition.
    ///   - overwriteID: Exact target role or member identifier; request type disambiguates it.
    ///   - request: Target kind and optional/null permission strings; omitted/null allow/deny default to zero upstream.
    ///   - auditReason: Optional supported audit reason, at most 512 Unicode scalars.
    /// - Returns: An unsafe PUT descriptor expecting empty 204; all local channel projections are invalidated.
    /// - Throws: Descriptor/audit errors; API/transport/uncertain mutation errors on execution.
    public static func editPermissions(channelID: ChannelID, overwriteID: ChannelOverwriteTargetID,
                                       request: ChannelPermissionEdit, auditReason: String? = nil) throws -> Endpoint<EmptyResponse> {
        try channelEmpty("PUT", channelID: channelID, suffix: ["permissions", overwriteID.description],
            route: "/channels/{channel.id}/permissions/{overwrite.id}", body: channelJSON(request.jsonValue()), auditReason: auditReason)
    }

    /// Deletes a guild-channel permission overwrite; requires MANAGE_ROLES.
    /// - Parameters:
    ///   - channelID: Channel major-rate partition.
    ///   - overwriteID: Exact role/member overwrite target.
    ///   - auditReason: Optional supported audit reason, at most 512 Unicode scalars.
    /// - Returns: An unsafe DELETE descriptor expecting empty 204 and invalidating channel visibility snapshots.
    /// - Throws: Descriptor/audit errors; execution can fail or report an uncertain mutation.
    public static func deletePermission(channelID: ChannelID, overwriteID: ChannelOverwriteTargetID,
                                         auditReason: String? = nil) throws -> Endpoint<EmptyResponse> {
        try channelEmpty("DELETE", channelID: channelID, suffix: ["permissions", overwriteID.description],
            route: "/channels/{channel.id}/permissions/{overwrite.id}", auditReason: auditReason)
    }

    /// Lists a guild channel's invites with metadata; requires MANAGE_CHANNELS.
    /// - Parameters:
    ///   - channelID: Channel major-rate partition.
    ///   - readPolicy: Optional scoped reuse; default coalesces without caching invite codes.
    /// - Returns: A safe GET descriptor preserving order, empty arrays and unknown fields.
    /// - Throws: Descriptor errors; incompatible invite/metadata fields and API failures on execution.
    ///   Referenced Guild/Application/Event/Role families remain explicitly partial projections.
    public static func invites(channelID: ChannelID, readPolicy: ReadPolicy? = ReadPolicy()) throws -> Endpoint<[ChannelInvite]> {
        try Endpoint(method: "GET", path: ["channels", channelID.description, "invites"],
            route: "/channels/{channel.id}/invites", authentication: .bot, majorParameter: channelID.description,
            retrySafety: .safe, readPolicy: channelReadPolicy(readPolicy), decode: { data in
                guard case .array(let values) = try JSONValue.parse(data) else { throw DiscordError.transport(.invalidResponse) }
                return try values.map { try ChannelInvite(data: $0.serialized(), requiresMetadata: true) }
            })
    }

    /// Creates an invite with CREATE_INSTANT_INVITE; role grants additionally require MANAGE_ROLES
    /// and cannot exceed the sender's roles. Empty parameters still send the required `{}` body.
    /// - Parameters:
    ///   - channelID: Guild channel major-rate partition.
    ///   - request: Validated expiration, use, target and role fields; defaults to an empty object.
    ///   - targetUsersCSV: Optional UTF-8 single-column snowflake CSV. Mutually exclusive with
    ///     targetUserIDs; duplicates are preserved for Discord to ignore. No file is opened locally.
    ///   - auditReason: Optional supported audit reason, at most 512 Unicode scalars.
    ///   - maximumBytes: Local complete request cap including multipart framing, 1...8 MiB; default 1 MiB.
    ///     This local policy does not claim an unpublished upstream CSV maximum.
    /// - Returns: An unsafe POST descriptor; CSV uses the exact `target_users_file` multipart field.
    /// - Throws: Invalid CSV/target conflicts, byte bounds or descriptor errors before I/O;
    ///   API validation and uncertain outcomes remain visible during execution.
    public static func createInvite(channelID: ChannelID, request: ChannelInviteCreate = ChannelInviteCreate(),
                                     targetUsersCSV: Data? = nil, auditReason: String? = nil,
                                     maximumBytes: Int = 1_048_576) throws -> Endpoint<ChannelInvite> {
        let body = try channelInviteBody(request, csv: targetUsersCSV, maximumBytes: maximumBytes)
        return try Endpoint(method: "POST", path: ["channels", channelID.description, "invites"],
            route: "/channels/{channel.id}/invites", authentication: .bot, majorParameter: channelID.description,
            auditReason: auditReason, body: body, invalidates: channelTags(channelID), decode: { try ChannelInvite(data: $0) })
    }

    /// Follows an announcement source into a target channel; requires MANAGE_WEBHOOKS in the target.
    /// - Parameters:
    ///   - channelID: Announcement source and major-rate partition.
    ///   - targetChannelID: Destination where Discord creates the following webhook.
    ///   - auditReason: Optional supported audit reason, at most 512 Unicode scalars.
    /// - Returns: An unsafe POST descriptor returning source channel and created webhook IDs.
    /// - Throws: Descriptor/audit errors; API/transport/uncertain mutation failures on execution.
    public static func follow(channelID: ChannelID, targetChannelID: ChannelID,
                               auditReason: String? = nil) throws -> Endpoint<FollowedChannel> {
        try Endpoint(method: "POST", path: ["channels", channelID.description, "followers"],
            route: "/channels/{channel.id}/followers", authentication: .bot, majorParameter: channelID.description,
            auditReason: auditReason, body: channelJSON(.object(["webhook_channel_id": .string(targetChannelID.description)])),
            invalidates: channelTags(channelID).union(channelTags(targetChannelID)), decode: { try FollowedChannel(data: $0) })
    }

    /// Posts one typing indicator lasting ten seconds upstream. Intended for bounded command work;
    /// this descriptor creates no timer or refresh task and Discord still enforces channel visibility.
    /// - Parameter channelID: Destination and channel-major partition.
    /// - Returns: An unsafe POST descriptor expecting empty 204 success.
    /// - Throws: Descriptor errors; API/transport/uncertain mutation errors on execution.
    public static func typing(channelID: ChannelID) throws -> Endpoint<EmptyResponse> {
        try channelEmpty("POST", channelID: channelID, suffix: ["typing"], route: "/channels/{channel.id}/typing")
    }

    /// Adds a user to an application-managed group DM using their `gdm.join` OAuth grant.
    /// The outer request uses the application's bot token; the recipient token belongs in the body.
    /// - Parameters:
    ///   - channelID: Group DM channel major-rate partition; eligibility is enforced by Discord.
    ///   - userID: Recipient whose access token was granted to this application.
    ///   - request: Recipient token and nickname; diagnostics conceal both.
    /// - Returns: An unsafe PUT descriptor accepting HTTP 201 with a Channel snapshot or empty HTTP 204,
    ///   represented by nil. No user token is put into the URL or authorization header. The shared descriptor
    ///   decoder receives body bytes only, so it validates either permitted shape without pairing it to a status.
    /// - Throws: Descriptor errors; malformed nonempty channel data, API/transport errors or an uncertain
    ///   mutation outcome during execution. An empty result does not imply that membership already existed.
    public static func addRecipient(channelID: ChannelID, userID: UserID,
                                    request: GroupDMRecipientAdd) throws -> Endpoint<Channel?> {
        try Endpoint(method: "PUT", path: ["channels", channelID.description, "recipients", userID.description],
            route: "/channels/{channel.id}/recipients/{user.id}", authentication: .bot, successStatuses: [201, 204],
            majorParameter: channelID.description, body: channelJSON(request.jsonValue()),
            invalidates: channelTags(channelID), decode: { $0.isEmpty ? nil : try Channel(data: $0) })
    }

    /// Removes a recipient from an application-managed group DM; bot/application ownership is server-checked.
    /// - Parameters:
    ///   - channelID: Group DM major-rate partition.
    ///   - userID: Recipient to remove, without fetching their profile.
    /// - Returns: An unsafe DELETE descriptor expecting empty 204 and invalidating channel reads.
    /// - Throws: Descriptor errors; API/transport/uncertain mutation errors during execution.
    public static func removeRecipient(channelID: ChannelID, userID: UserID) throws -> Endpoint<EmptyResponse> {
        try channelEmpty("DELETE", channelID: channelID, suffix: ["recipients", userID.description],
            route: "/channels/{channel.id}/recipients/{user.id}")
    }

    /// Starts a public or announcement thread from an existing message; requires CREATE_PUBLIC_THREADS.
    /// The source must be a text/announcement channel. Forum/media channels use `startForumThread`.
    /// - Parameters:
    ///   - channelID: Parent channel and major-rate partition.
    ///   - messageID: Source message; Discord uses its ID for the thread and permits one thread per message.
    ///   - request: Validated name, optional archive duration and slowmode seconds.
    ///   - auditReason: Optional supported audit reason, at most 512 Unicode scalars.
    /// - Returns: An unsafe POST descriptor decoding the created Channel from HTTP 201 Created.
    /// - Throws: Descriptor/audit errors; API/transport/uncertain mutation errors on execution.
    public static func startThreadFromMessage(channelID: ChannelID, messageID: MessageID,
                                               request: ThreadStartFromMessage, auditReason: String? = nil) throws -> Endpoint<Channel> {
        try channelMutation("POST", channelID: channelID,
            path: ["channels", channelID.description, "messages", messageID.description, "threads"],
            route: "/channels/{channel.id}/messages/{message.id}/threads", body: channelJSON(request.jsonValue()),
            auditReason: auditReason, successStatuses: [201])
    }

    /// Starts a thread without a source message; requires CREATE_PUBLIC_THREADS or CREATE_PRIVATE_THREADS
    /// according to the requested type. API v10 defaults an omitted type to PRIVATE_THREAD.
    /// - Parameters:
    ///   - channelID: Text parent channel and major-rate partition.
    ///   - request: Validated name/type/archive/slowmode/invitability; invitable is private-thread-only.
    ///   - auditReason: Optional supported audit reason, at most 512 Unicode scalars.
    /// - Returns: An unsafe POST descriptor returning the created Channel from HTTP 201 Created.
    /// - Throws: Descriptor/audit errors; execution preserves API failure and uncertain submission.
    public static func startThread(channelID: ChannelID, request: ThreadStartWithoutMessage,
                                    auditReason: String? = nil) throws -> Endpoint<Channel> {
        try channelMutation("POST", channelID: channelID, path: ["channels", channelID.description, "threads"],
            route: "/channels/{channel.id}/threads", body: channelJSON(request.jsonValue()),
            auditReason: auditReason, successStatuses: [201])
    }

    /// Starts a forum/media PUBLIC_THREAD with its initial message. Requires SEND_MESSAGES;
    /// CREATE_PUBLIC_THREADS is ignored. Uploads share the bounded message multipart implementation.
    /// - Parameters:
    ///   - channelID: Forum/media parent and channel-major partition.
    ///   - request: Validated thread fields and the endpoint's restricted initial-message schema.
    ///   - files: Explicit new upload bytes or fresh producer factories; default empty.
    ///   - limits: Separate per-file and total request bounds, default 20 MiB/file and 25 MiB/request.
    ///   - auditReason: Optional supported audit reason, at most 512 Unicode scalars.
    /// - Returns: An unsafe POST descriptor returning HTTP 201 Created Channel with a nested initial Message.
    /// - Throws: Payload/upload/count/byte/descriptor errors before I/O. Execution closes producers on
    ///   completion/failure/cancellation and preserves API or uncertain mutation outcomes.
    public static func startForumThread(channelID: ChannelID, request: ForumThreadStart,
                                         files: [MessageUploadFile] = [], limits: MessageUploadLimits = .default,
                                         auditReason: String? = nil) throws -> Endpoint<Channel> {
        let types = try messageUploadTypes(files)
        let payload = try request.jsonValue(uploadIDs: files.map(\.id), uploadContentTypes: types)
        return try channelMutation("POST", channelID: channelID, path: ["channels", channelID.description, "threads"],
            route: "/channels/{channel.id}/threads", body: MessageUpload.body(payload: payload, files: files, limits: limits),
            auditReason: auditReason, successStatuses: [201])
    }

    /// Joins the current bot to an unarchived thread. Discord checks access and membership limits.
    /// - Parameter channelID: Thread and channel-major partition.
    /// - Returns: An unsafe PUT descriptor expecting empty 204.
    /// - Throws: Descriptor errors; execution preserves API errors and uncertain outcomes.
    public static func joinThread(channelID: ChannelID) throws -> Endpoint<EmptyResponse> {
        try channelEmpty("PUT", channelID: channelID, suffix: ["thread-members", "@me"], route: "/channels/{channel.id}/thread-members/@me")
    }

    /// Leaves an unarchived thread as the current bot; this does not delete the thread.
    /// - Parameter channelID: Thread and channel-major partition.
    /// - Returns: An unsafe DELETE descriptor expecting empty 204.
    /// - Throws: Descriptor errors; API/transport/uncertain outcomes during execution.
    public static func leaveThread(channelID: ChannelID) throws -> Endpoint<EmptyResponse> {
        try channelEmpty("DELETE", channelID: channelID, suffix: ["thread-members", "@me"], route: "/channels/{channel.id}/thread-members/@me")
    }

    /// Adds a member to an unarchived thread; requires the ability to send messages there.
    /// Already-present membership also succeeds upstream with 204.
    /// - Parameters:
    ///   - channelID: Thread and channel-major partition.
    ///   - userID: Exact member to add; no profile hydration occurs.
    /// - Returns: An unsafe PUT descriptor expecting empty 204; ambiguous sends are not replayed.
    /// - Throws: Descriptor errors; API/transport/uncertain outcomes during execution.
    public static func addThreadMember(channelID: ChannelID, userID: UserID) throws -> Endpoint<EmptyResponse> {
        try channelEmpty("PUT", channelID: channelID, suffix: ["thread-members", userID.description], route: "/channels/{channel.id}/thread-members/{user.id}")
    }

    /// Removes another member from an unarchived thread; requires MANAGE_THREADS or private-thread creatorship.
    /// - Parameters:
    ///   - channelID: Thread and channel-major partition.
    ///   - userID: Member to remove without automatic related-resource requests.
    /// - Returns: An unsafe DELETE descriptor expecting empty 204.
    /// - Throws: Descriptor errors; API/transport/uncertain outcomes during execution.
    public static func removeThreadMember(channelID: ChannelID, userID: UserID) throws -> Endpoint<EmptyResponse> {
        try channelEmpty("DELETE", channelID: channelID, suffix: ["thread-members", userID.description], route: "/channels/{channel.id}/thread-members/{user.id}")
    }

    /// Gets a thread member; nonmembership returns 404 upstream rather than a null model.
    /// - Parameters:
    ///   - channelID: Thread and major-rate partition.
    ///   - userID: Exact member identifier.
    ///   - withMember: Whether Discord includes additional guild-member data; default false.
    ///   - readPolicy: Optional scoped reuse, default coalescing without caching.
    /// - Returns: A safe GET descriptor. Guild-member fields retain their named partial projection.
    /// - Throws: Descriptor errors; API/transport/schema errors during execution.
    public static func threadMember(channelID: ChannelID, userID: UserID, withMember: Bool = false,
                                     readPolicy: ReadPolicy? = ReadPolicy()) throws -> Endpoint<ThreadMember> {
        try Endpoint(method: "GET", path: ["channels", channelID.description, "thread-members", userID.description],
            route: "/channels/{channel.id}/thread-members/{user.id}", query: [.init(name: "with_member", value: String(withMember))],
            authentication: .bot, majorParameter: channelID.description, retrySafety: .safe,
            readPolicy: channelReadPolicy(readPolicy), decode: { try ThreadMember(data: $0) })
    }

    /// Lists thread membership, subject to the application's GUILD_MEMBERS privileged-intent eligibility.
    /// In API v10 only `withMember: true` enables pagination; the legacy false variant is one response.
    /// - Parameters:
    ///   - channelID: Thread and channel-major partition.
    ///   - withMember: Include guild-member data and enable pagination; default false preserves v10 legacy behavior.
    ///   - after: Optional exclusive ascending user cursor, only with withMember true.
    ///   - limit: Optional 1...100 page size, only with withMember true; nil leaves Discord's default 100.
    ///   - readPolicy: Optional scoped reuse, default coalescing without completed caching.
    /// - Returns: A safe GET descriptor decoding ordered ThreadMembers. No follow-up hydration occurs.
    /// - Throws: Invalid limit or legacy-pagination combination before I/O; API/transport/schema errors on execution.
    public static func threadMembers(channelID: ChannelID, withMember: Bool = false, after: UserID? = nil,
                                      limit: Int? = nil, readPolicy: ReadPolicy? = ReadPolicy()) throws -> Endpoint<[ThreadMember]> {
        guard withMember || (after == nil && limit == nil) else { throw DiscordError.validation(.invalidValue) }
        var query = [QueryItem(name: "with_member", value: String(withMember))]
        if let after { query.append(.init(name: "after", value: after.description)) }
        if let limit { try messageLimit(limit, maximum: 100); query.append(.init(name: "limit", value: String(limit))) }
        return try Endpoint(method: "GET", path: ["channels", channelID.description, "thread-members"],
            route: "/channels/{channel.id}/thread-members", query: query, authentication: .bot,
            majorParameter: channelID.description, retrySafety: .safe, readPolicy: channelReadPolicy(readPolicy), decode: { data in
                guard case .array(let values) = try JSONValue.parse(data) else { throw DiscordError.transport(.invalidResponse) }
                return try values.map { try ThreadMember(data: $0.serialized()) }
            })
    }

    /// Lists public archived threads in descending archive_timestamp order; requires READ_MESSAGE_HISTORY.
    /// - Parameters:
    ///   - channelID: Parent channel major-rate partition.
    ///   - before: Optional exclusive archive timestamp preserving its original precision/offset.
    ///   - limit: Optional positive local page bound, at most 100; nil uses the server default.
    ///     The written reference publishes no numeric maximum; 100 is this library's bounded policy.
    ///   - readPolicy: Optional scoped reuse, default coalescing without caching.
    /// - Returns: A safe GET descriptor retaining threads, joined-members and explicit hasMore.
    /// - Throws: Local limit/descriptor errors; API/transport/schema errors during execution.
    public static func publicArchivedThreads(channelID: ChannelID, before: DiscordTimestamp? = nil,
                                              limit: Int? = nil, readPolicy: ReadPolicy? = ReadPolicy()) throws -> Endpoint<ArchivedThreads> {
        try channelArchived(channelID: channelID, suffix: ["threads", "archived", "public"],
            route: "/channels/{channel.id}/threads/archived/public", before: before?.rawValue, limit: limit, readPolicy: readPolicy)
    }

    /// Lists private archived threads in descending archive_timestamp order; requires READ_MESSAGE_HISTORY
    /// and MANAGE_THREADS. This includes accessible threads the current bot has not joined.
    /// - Parameters:
    ///   - channelID: Parent channel major-rate partition.
    ///   - before: Optional exclusive archive timestamp, never substituted with a thread ID.
    ///   - limit: Optional local positive page bound, at most 100; nil leaves server default.
    ///   - readPolicy: Optional scoped reuse, default coalescing without completed caching.
    /// - Returns: A safe GET descriptor preserving joined-member correlation and hasMore.
    /// - Throws: Local limit/descriptor errors; API/transport/schema errors during execution.
    public static func privateArchivedThreads(channelID: ChannelID, before: DiscordTimestamp? = nil,
                                               limit: Int? = nil, readPolicy: ReadPolicy? = ReadPolicy()) throws -> Endpoint<ArchivedThreads> {
        try channelArchived(channelID: channelID, suffix: ["threads", "archived", "private"],
            route: "/channels/{channel.id}/threads/archived/private", before: before?.rawValue, limit: limit, readPolicy: readPolicy)
    }

    /// Lists joined private archived threads in descending ID order; requires READ_MESSAGE_HISTORY.
    /// This route uses a snowflake cursor, unlike other archived-thread routes.
    /// - Parameters:
    ///   - channelID: Parent channel major-rate partition.
    ///   - before: Optional exclusive thread ID; exact unsigned decimal-string spelling is retained.
    ///   - limit: Optional local positive page bound, at most 100; nil leaves server default.
    ///   - readPolicy: Optional scoped reuse, default coalescing without caching.
    /// - Returns: A safe GET descriptor retaining threads, members and hasMore.
    /// - Throws: Local limit/descriptor errors; API/transport/schema errors during execution.
    public static func joinedPrivateArchivedThreads(channelID: ChannelID, before: ChannelID? = nil,
                                                     limit: Int? = nil, readPolicy: ReadPolicy? = ReadPolicy()) throws -> Endpoint<ArchivedThreads> {
        try channelArchived(channelID: channelID, suffix: ["users", "@me", "threads", "archived", "private"],
            route: "/channels/{channel.id}/users/@me/threads/archived/private", before: before?.description, limit: limit, readPolicy: readPolicy)
    }

    /// Lists accessible active public/private guild threads in descending ID order. This documented
    /// guild endpoint has no pagination and is included here to complete channel/thread adoption.
    /// - Parameters:
    ///   - guildID: Guild to enumerate and exact guild-major rate partition.
    ///   - readPolicy: Optional scoped reuse, default coalescing without caching.
    /// - Returns: A safe GET descriptor with thread/member correlation. Visibility is server-filtered.
    /// - Throws: Descriptor errors; API/transport/schema or configured response-byte limits on execution.
    /// See https://docs.discord.com/developers/resources/guild#list-active-guild-threads.
    public static func activeGuildThreads(guildID: GuildID, readPolicy: ReadPolicy? = ReadPolicy()) throws -> Endpoint<ActiveThreads> {
        try Endpoint(method: "GET", path: ["guilds", guildID.description, "threads", "active"],
            route: "/guilds/{guild.id}/threads/active", authentication: .bot, majorParameter: guildID.description, retrySafety: .safe,
            readPolicy: channelReadPolicy(readPolicy), decode: { try ActiveThreads(data: $0) })
    }
}

/// Serializes validated channel request JSON directly, retaining exact decimal permission strings.
/// - Parameter value: Validated semantic request tree; no generic response-to-request conversion occurs.
/// - Returns: A bounded materialized application/json body; no stream is opened here.
/// - Throws: JSON bounds or body validation errors; default parser/body limits apply.
func channelJSON(_ value: JSONValue) throws -> RequestBody {
    try RequestBody(bytes: value.serialized(), contentType: "application/json")
}

/// Invalidates channel snapshots across parent/guild relationships whose IDs may be unavailable locally.
/// - Parameter channelID: Directly mutated channel, also used for message invalidation.
/// - Returns: One authentication-scoped catalog tag plus the existing channel/message-search tags.
/// Global catalog invalidation deliberately trades hit rate for correct visibility/membership changes.
func channelTags(_ channelID: ChannelID) -> Set<String> { messageTags(channelID).union(["channel-catalog"]) }

/// Adds catalog invalidation while preserving explicit caller coalescing and freshness choices.
/// - Parameter policy: Optional read policy; nil disables all reuse.
/// - Returns: Policy with an authentication-scoped channel-catalog tag, or nil; no caching is enabled implicitly.
func channelReadPolicy(_ policy: ReadPolicy?) -> ReadPolicy? {
    policy.map { ReadPolicy(coalescing: $0.coalescing, timeToLive: $0.timeToLive, tags: $0.tags.union(["channel-catalog"])) }
}

/// Builds a channel-returning mutation with shared conservative replay and invalidation policy.
/// - Parameters:
///   - method: POST, PATCH or DELETE HTTP operation.
///   - channelID: Channel major-rate partition and invalidation owner.
///   - path: Complete raw relative path segments.
///   - route: Stable normalized rate-limit route.
///   - body: Optional bounded request body; nil sends none.
///   - auditReason: Optional supported reason, at most 512 Unicode scalars.
///   - successStatuses: Exact successful statuses; defaults to 200 for settings/deletion and is 201 for thread creation.
///     Discord's current official API v10 specification supplies 201 where the written reference omits numeric status.
/// - Returns: An unsafe mutation expecting Channel JSON only for the explicitly accepted success statuses.
/// - Throws: Descriptor/audit validation errors. No resource is opened or I/O performed at construction.
func channelMutation(_ method: String, channelID: ChannelID, path: [String], route: String,
                     body: RequestBody? = nil, auditReason: String? = nil,
                     successStatuses: Set<Int> = [200]) throws -> Endpoint<Channel> {
    try Endpoint(method: method, path: path, route: route, authentication: .bot, successStatuses: successStatuses,
        majorParameter: channelID.description,
        auditReason: auditReason, body: body, invalidates: channelTags(channelID), decode: { try Channel(data: $0) })
}

/// Constructs an empty-result channel mutation without inferring safety from PUT/DELETE semantics.
/// - Parameters:
///   - method: POST, PUT or DELETE HTTP operation.
///   - channelID: Target channel and major-rate partition.
///   - suffix: Raw relative segments following channels/channelID.
///   - route: Stable normalized rate-limit route.
///   - body: Optional bounded body; default nil sends none.
///   - auditReason: Optional supported audit reason, at most 512 Unicode scalars.
/// - Returns: An unsafe descriptor requiring exactly empty HTTP 204 success.
/// - Throws: Descriptor/audit errors now; nonempty successful bytes fail the decoder on execution.
func channelEmpty(_ method: String, channelID: ChannelID, suffix: [String], route: String,
                  body: RequestBody? = nil, auditReason: String? = nil) throws -> Endpoint<EmptyResponse> {
    try Endpoint(method: method, path: ["channels", channelID.description] + suffix, route: route,
        authentication: .bot, successStatuses: [204], majorParameter: channelID.description,
        auditReason: auditReason, body: body, invalidates: channelTags(channelID), decode: { try EmptyResponse(data: $0) })
}

/// Constructs the common archived-thread response contract while leaving cursor units operation-specific.
/// - Parameters:
///   - channelID: Parent major-rate partition.
///   - suffix: Public/private/joined route segments after the channel.
///   - route: Stable normalized route.
///   - before: Exact timestamp or decimal thread ID already selected by the public typed operation.
///   - limit: Optional local 1...100 page bound; nil sends no limit.
///   - readPolicy: Optional scoped coalescing/TTL configuration.
/// - Returns: A safe GET descriptor retaining the complete archive envelope.
/// - Throws: Local limit/descriptor errors; performs no I/O and starts no follow-up request.
func channelArchived(channelID: ChannelID, suffix: [String], route: String, before: String?, limit: Int?,
                     readPolicy: ReadPolicy?) throws -> Endpoint<ArchivedThreads> {
    var query: [QueryItem] = []
    if let before { query.append(.init(name: "before", value: before)) }
    if let limit { try messageLimit(limit, maximum: 100); query.append(.init(name: "limit", value: String(limit))) }
    return try Endpoint(method: "GET", path: ["channels", channelID.description] + suffix, route: route,
        query: query, authentication: .bot, majorParameter: channelID.description, retrySafety: .safe,
        readPolicy: channelReadPolicy(readPolicy), decode: { try ArchivedThreads(data: $0) })
}
