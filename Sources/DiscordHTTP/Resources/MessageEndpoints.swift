import DiscordCore
import DiscordModels
import DiscordTransport
import Foundation

/// Typed API v10 message operations, verified against the official reference on 2026-10-16.
///
/// Every descriptor uses bot authentication, the shared credential-global/route admission,
/// bounded retries, cancellation and deadlines in `RESTClient`. Guild channel operations
/// require VIEW_CHANNEL and READ_MESSAGE_HISTORY when reading, plus CONNECT for voice
/// channels. MESSAGE_CONTENT eligibility governs content visibility and search access;
/// no Gateway connection is required. Mutations invalidate local channel reads and search.
/// Permissions are enforced by Discord and cannot be established by cached payloads.
/// See https://docs.discord.com/developers/resources/message.
public enum MessageEndpoints {
    /// Describes newest-first channel history; missing READ_MESSAGE_HISTORY yields an empty list.
    /// - Parameters:
    ///   - channelID: Exact channel major-rate partition.
    ///   - position: Optional single before/after/around cursor; nil starts at the newest messages.
    ///   - limit: Page size, 1...100; default 50. A short page is not a search completion signal.
    ///   - readPolicy: Optional scoped coalescing/freshness; default coalesces without caching.
    /// - Returns: A GET descriptor decoding a bounded array; constructing it sends no request.
    /// - Throws: Safe validation errors for limits or descriptor metadata; malformed arrays fail at decoding.
    public static func history(channelID: ChannelID, position: MessageHistoryPosition? = nil,
                               limit: Int = 50, readPolicy: ReadPolicy? = ReadPolicy()) throws -> Endpoint<[Message]> {
        try messageLimit(limit, maximum: 100)
        var query = [QueryItem(name: "limit", value: String(limit))]
        switch position {
        case .before(let id): query.append(.init(name: "before", value: id.description))
        case .after(let id): query.append(.init(name: "after", value: id.description))
        case .around(let id): query.append(.init(name: "around", value: id.description))
        case nil: break
        }
        return try Endpoint(method: "GET", path: ["channels", channelID.description, "messages"],
            route: "/channels/{channel.id}/messages", query: query, authentication: .bot,
            majorParameter: channelID.description, retrySafety: .safe,
            readPolicy: messageReadPolicy(readPolicy, channelID: channelID), decode: messageArray)
    }

    /// Retrieves one message, subject to channel/history permissions and content redaction.
    /// - Parameters:
    ///   - channelID: Exact channel major-rate partition.
    ///   - messageID: Message within that channel; no existence check occurs locally.
    ///   - readPolicy: Optional coalescing/TTL policy; default has no completed-result cache.
    /// - Returns: A safe GET descriptor; no I/O occurs until execution.
    /// - Throws: Descriptor errors; required/malformed response fields fail during execution.
    public static func get(channelID: ChannelID, messageID: MessageID,
                           readPolicy: ReadPolicy? = ReadPolicy()) throws -> Endpoint<Message> {
        try Endpoint(method: "GET", path: messagePath(channelID, messageID),
            route: "/channels/{channel.id}/messages/{message.id}", authentication: .bot,
            majorParameter: channelID.description, retrySafety: .safe,
            readPolicy: messageReadPolicy(readPolicy, channelID: channelID), decode: { try Message(data: $0) })
    }

    /// Sends a message, reply, forward, poll or voice attachment. Requires SEND_MESSAGES;
    /// TTS additionally requires SEND_TTS_MESSAGES, replies READ_MESSAGE_HISTORY.
    /// - Parameters:
    ///   - channelID: Destination and major-rate partition.
    ///   - request: Complete typed creation fields; validates V2/voice/forward compatibility.
    ///   - files: Explicit upload bytes/factories, default empty; IDs must be unique and match metadata.
    ///   - limits: Separate per-file and aggregate multipart bounds; default 20 MiB/file, 25 MiB/request.
    /// - Returns: An unsafe POST descriptor; enforce_nonce does not make ambiguous sends replayable.
    /// - Throws: Safe payload/upload/descriptor validation errors before I/O. Execution can report
    ///   an indeterminate mutation; reconcile it rather than blindly resending.
    public static func create(channelID: ChannelID, request: MessageCreate, files: [MessageUploadFile] = [],
                              limits: MessageUploadLimits = .default) throws -> Endpoint<Message> {
        let types = try messageUploadTypes(files)
        let payload = try request.jsonValue(uploadIDs: files.map(\.id), uploadContentTypes: types)
        return try Endpoint(method: "POST", path: ["channels", channelID.description, "messages"],
            route: "/channels/{channel.id}/messages", authentication: .bot, majorParameter: channelID.description,
            body: MessageUpload.body(payload: payload, files: files, limits: limits),
            invalidates: messageTags(channelID), decode: { try Message(data: $0) })
    }

    /// Publishes an announcement message to followers. Requires SEND_MESSAGES and,
    /// for another author's message, MANAGE_MESSAGES. No generic mutation retry is inferred.
    /// - Parameters:
    ///   - channelID: Announcement channel major-rate partition.
    ///   - messageID: Message to publish.
    /// - Returns: An unsafe POST descriptor with typed updated message and scoped invalidation.
    /// - Throws: Descriptor errors; execution preserves API failures or ambiguous outcomes.
    public static func crosspost(channelID: ChannelID, messageID: MessageID) throws -> Endpoint<Message> {
        try Endpoint(method: "POST", path: messagePath(channelID, messageID) + ["crosspost"],
            route: "/channels/{channel.id}/messages/{message.id}/crosspost", authentication: .bot,
            majorParameter: channelID.description, invalidates: messageTags(channelID), decode: { try Message(data: $0) })
    }

    /// Adds the current bot's normal reaction. Requires READ_MESSAGE_HISTORY and ADD_REACTIONS
    /// when this emoji is not yet represented. Emoji text is escaped exactly once.
    /// - Parameters:
    ///   - channelID: Channel major-rate partition.
    ///   - messageID: Target message.
    ///   - emoji: Unicode or named custom emoji; no pre-encoding is required.
    /// - Returns: A PUT descriptor expecting 204 empty bytes; ambiguous sends are not automatically replayed.
    /// - Throws: Safe emoji/descriptor errors before I/O; execution retains API/transport failures.
    public static func createReaction(channelID: ChannelID, messageID: MessageID, emoji: ReactionEmoji) throws -> Endpoint<EmptyResponse> {
        try messageEmpty("PUT", channelID: channelID, path: messagePath(channelID, messageID) + ["reactions", emoji.segment(), "@me"],
            route: "/channels/{channel.id}/messages/{message.id}/reactions/{emoji}/@me")
    }

    /// Removes the current bot's reaction; successful responses are empty 204s.
    /// - Parameters:
    ///   - channelID: Channel major-rate partition.
    ///   - messageID: Target message.
    ///   - emoji: Unescaped Unicode/custom emoji.
    /// - Returns: A DELETE descriptor with channel/search invalidation and conservative replay policy.
    /// - Throws: Safe route/emoji errors; execution preserves API failures and uncertain outcomes.
    public static func deleteOwnReaction(channelID: ChannelID, messageID: MessageID, emoji: ReactionEmoji) throws -> Endpoint<EmptyResponse> {
        try messageEmpty("DELETE", channelID: channelID, path: messagePath(channelID, messageID) + ["reactions", emoji.segment(), "@me"],
            route: "/channels/{channel.id}/messages/{message.id}/reactions/{emoji}/@me")
    }

    /// Removes another user's reaction. Requires MANAGE_MESSAGES.
    /// - Parameters:
    ///   - channelID: Channel major-rate partition.
    ///   - messageID: Target message.
    ///   - emoji: Unescaped Unicode/custom emoji.
    ///   - userID: Reaction owner; permissions remain a server decision.
    /// - Returns: A DELETE descriptor expecting exactly empty 204 success.
    /// - Throws: Safe emoji/descriptor errors; execution failures preserve uncertainty.
    public static func deleteUserReaction(channelID: ChannelID, messageID: MessageID, emoji: ReactionEmoji,
                                          userID: UserID) throws -> Endpoint<EmptyResponse> {
        try messageEmpty("DELETE", channelID: channelID, path: messagePath(channelID, messageID) + ["reactions", emoji.segment(), userID.description],
            route: "/channels/{channel.id}/messages/{message.id}/reactions/{emoji}/{user.id}")
    }

    /// Lists normal or burst reaction users in ascending user-ID order with an explicit after cursor.
    /// - Parameters:
    ///   - channelID: Channel major-rate partition.
    ///   - messageID: Reacted message.
    ///   - emoji: Unescaped Unicode/custom emoji.
    ///   - type: Normal (default) or burst reactions; this does not create a super reaction.
    ///   - after: Optional exclusive user cursor.
    ///   - limit: Users per page, 1...100; default 25.
    ///   - readPolicy: Optional scoped read reuse; default coalesces without caching.
    /// - Returns: A safe GET descriptor. User projections retain their documented partial coverage.
    /// - Throws: Safe cursor/limit/emoji errors; incompatible response users fail decoding.
    public static func reactions(channelID: ChannelID, messageID: MessageID, emoji: ReactionEmoji,
                                 type: MessageReactionType = .normal, after: UserID? = nil, limit: Int = 25,
                                 readPolicy: ReadPolicy? = ReadPolicy()) throws -> Endpoint<[User]> {
        try messageLimit(limit, maximum: 100)
        var query = [QueryItem(name: "type", value: String(type.rawValue)), QueryItem(name: "limit", value: String(limit))]
        if let after { query.append(.init(name: "after", value: after.description)) }
        return try Endpoint(method: "GET", path: messagePath(channelID, messageID) + ["reactions", emoji.segment()],
            route: "/channels/{channel.id}/messages/{message.id}/reactions/{emoji}", query: query, authentication: .bot,
            majorParameter: channelID.description, retrySafety: .safe,
            readPolicy: messageReadPolicy(readPolicy, channelID: channelID), decode: messageUsers)
    }

    /// Removes every reaction on a message. Requires MANAGE_MESSAGES.
    /// - Parameters:
    ///   - channelID: Channel major-rate partition.
    ///   - messageID: Target message.
    /// - Returns: A DELETE descriptor expecting empty 204; no automatic ambiguous replay.
    /// - Throws: Descriptor errors and, during execution, safe API/transport/uncertainty errors.
    public static func deleteAllReactions(channelID: ChannelID, messageID: MessageID) throws -> Endpoint<EmptyResponse> {
        try messageEmpty("DELETE", channelID: channelID, path: messagePath(channelID, messageID) + ["reactions"],
            route: "/channels/{channel.id}/messages/{message.id}/reactions")
    }

    /// Removes every reaction matching one emoji. Requires MANAGE_MESSAGES.
    /// - Parameters:
    ///   - channelID: Channel major-rate partition.
    ///   - messageID: Target message.
    ///   - emoji: Unescaped Unicode/custom emoji.
    /// - Returns: A DELETE descriptor expecting empty 204 and invalidating scoped reads.
    /// - Throws: Emoji/descriptor errors; API/transport failures surface during execution.
    public static func deleteEmojiReactions(channelID: ChannelID, messageID: MessageID, emoji: ReactionEmoji) throws -> Endpoint<EmptyResponse> {
        try messageEmpty("DELETE", channelID: channelID, path: messagePath(channelID, messageID) + ["reactions", emoji.segment()],
            route: "/channels/{channel.id}/messages/{message.id}/reactions/{emoji}")
    }

    /// Edits an authored message, or its allowed flags with MANAGE_MESSAGES. Voice messages cannot
    /// be edited. Attachments supplied in API v10 must enumerate both retained and new files.
    /// - Parameters:
    ///   - channelID: Channel major-rate partition.
    ///   - messageID: Existing message.
    ///   - request: Presence-aware edits, previous flags and attachment-retention intent.
    ///   - files: New upload bytes/factories, default empty; unmentioned IDs are rejected.
    ///   - limits: Separate per-file and aggregate multipart limits.
    /// - Returns: An unsafe PATCH descriptor; mutations never share or cache results.
    /// - Throws: Payload/upload/descriptor validation failures; execution can report an indeterminate outcome.
    public static func edit(channelID: ChannelID, messageID: MessageID, request: MessageEdit,
                            files: [MessageUploadFile] = [], limits: MessageUploadLimits = .default) throws -> Endpoint<Message> {
        let types = try messageUploadTypes(files)
        let payload = try request.jsonValue(uploadIDs: files.map(\.id), uploadContentTypes: types)
        return try Endpoint(method: "PATCH", path: messagePath(channelID, messageID),
            route: "/channels/{channel.id}/messages/{message.id}", authentication: .bot,
            majorParameter: channelID.description, body: MessageUpload.body(payload: payload, files: files, limits: limits),
            invalidates: messageTags(channelID), decode: { try Message(data: $0) })
    }

    /// Deletes a message. Deleting another author's guild message requires MANAGE_MESSAGES.
    /// - Parameters:
    ///   - channelID: Channel major-rate partition.
    ///   - messageID: Target message.
    ///   - auditReason: Optional audit reason, at most 512 Unicode scalars, encoded once.
    /// - Returns: An unsafe DELETE descriptor expecting empty 204.
    /// - Throws: Descriptor/audit validation errors; execution preserves API and ambiguous outcomes.
    public static func delete(channelID: ChannelID, messageID: MessageID, auditReason: String? = nil) throws -> Endpoint<EmptyResponse> {
        try messageEmpty("DELETE", channelID: channelID, path: messagePath(channelID, messageID),
            route: "/channels/{channel.id}/messages/{message.id}", auditReason: auditReason)
    }

    /// Deletes one legal bulk chunk in a guild channel. Requires MANAGE_MESSAGES.
    /// - Parameters:
    ///   - channelID: Guild channel major-rate partition.
    ///   - messageIDs: 2...100 distinct IDs, none older than two weeks at the supplied wall time.
    ///   - nowMilliseconds: Explicit Unix milliseconds used only for local snowflake-age validation.
    ///     Callers must supply a current trusted wall time; Discord independently enforces the age limit.
    ///   - auditReason: Optional audit reason, at most 512 Unicode scalars.
    /// - Returns: An unsafe POST descriptor; no chunking or request merging occurs implicitly.
    /// - Throws: Safe count/duplicate/age errors before I/O; execution can return indeterminate completion.
    public static func bulkDelete(channelID: ChannelID, messageIDs: [MessageID], nowMilliseconds: UInt64,
                                  auditReason: String? = nil) throws -> Endpoint<EmptyResponse> {
        try validateBulkMessageIDs(messageIDs, maximum: 100, nowMilliseconds: nowMilliseconds)
        let payload = JSONValue.object(["messages": .array(messageIDs.map { .string($0.description) })])
        return try Endpoint(method: "POST", path: ["channels", channelID.description, "messages", "bulk-delete"],
            route: "/channels/{channel.id}/messages/bulk-delete", authentication: .bot, successStatuses: [204],
            majorParameter: channelID.description, auditReason: auditReason,
            body: RequestBody(bytes: payload.serialized(), contentType: "application/json"),
            invalidates: messageTags(channelID),
            bulk: .init(maximumItems: 100, preservesOrder: false, permitsPartialResults: false,
                        documentationURL: URL(string: "https://docs.discord.com/developers/resources/message#bulk-delete-messages")!),
            decode: { try EmptyResponse(data: $0) })
    }

    /// Lists current pin objects. VIEW_CHANNEL is required; missing history permission yields no pins.
    /// - Parameters:
    ///   - channelID: Channel major-rate partition.
    ///   - before: Exact exclusive pinned-at timestamp, or nil for the first page.
    ///   - limit: Pin page size, 1...50; default 50.
    ///   - readPolicy: Optional scoped coalescing/freshness; default has no completed cache.
    /// - Returns: A safe GET descriptor preserving `has_more`; page length alone never ends iteration.
    /// - Throws: Safe limit/descriptor errors; malformed pin envelopes fail decoding.
    public static func pins(channelID: ChannelID, before: DiscordTimestamp? = nil, limit: Int = 50,
                            readPolicy: ReadPolicy? = ReadPolicy()) throws -> Endpoint<MessagePins> {
        try messageLimit(limit, maximum: 50)
        var query = [QueryItem(name: "limit", value: String(limit))]
        if let before { query.append(.init(name: "before", value: before.rawValue)) }
        return try Endpoint(method: "GET", path: ["channels", channelID.description, "messages", "pins"],
            route: "/channels/{channel.id}/messages/pins", query: query, authentication: .bot,
            majorParameter: channelID.description, retrySafety: .safe,
            readPolicy: messageReadPolicy(readPolicy, channelID: channelID), decode: { try MessagePins(data: $0) })
    }

    /// Pins a message using the current route and PIN_MESSAGES permission.
    /// - Parameters:
    ///   - channelID: Channel major-rate partition.
    ///   - messageID: Message to pin.
    ///   - auditReason: Optional control-free reason, at most 512 Unicode scalars.
    /// - Returns: A PUT descriptor expecting empty 204; no I/O starts at construction.
    /// - Throws: Descriptor errors; permission/limit/API/transport failures arise during execution.
    public static func pin(channelID: ChannelID, messageID: MessageID, auditReason: String? = nil) throws -> Endpoint<EmptyResponse> {
        try messageEmpty("PUT", channelID: channelID, path: ["channels", channelID.description, "messages", "pins", messageID.description],
            route: "/channels/{channel.id}/messages/pins/{message.id}", auditReason: auditReason)
    }

    /// Unpins a message using the current route and PIN_MESSAGES permission.
    /// - Parameters:
    ///   - channelID: Channel major-rate partition.
    ///   - messageID: Message to unpin.
    ///   - auditReason: Optional audit reason, at most 512 Unicode scalars.
    /// - Returns: A DELETE descriptor expecting empty 204 and invalidating channel/search snapshots.
    /// - Throws: Descriptor/audit errors and execution-time API/transport/uncertainty errors.
    public static func unpin(channelID: ChannelID, messageID: MessageID, auditReason: String? = nil) throws -> Endpoint<EmptyResponse> {
        try messageEmpty("DELETE", channelID: channelID, path: ["channels", channelID.description, "messages", "pins", messageID.description],
            route: "/channels/{channel.id}/messages/pins/{message.id}", auditReason: auditReason)
    }

    /// Reads the first 50 pins using Discord's deprecated nonpaginated route.
    /// - Parameters:
    ///   - channelID: Channel major-rate partition.
    ///   - readPolicy: Optional scoped read reuse, default coalescing without caching.
    /// - Returns: A safe GET descriptor decoding the legacy message array.
    /// - Throws: Descriptor errors or execution-time malformed-response/API failures.
    /// - SeeAlso: `pins(channelID:before:limit:readPolicy:)` for the current paginated API.
    @available(*, deprecated, message: "Use pins(channelID:before:limit:readPolicy:).")
    public static func legacyPins(channelID: ChannelID, readPolicy: ReadPolicy? = ReadPolicy()) throws -> Endpoint<[Message]> {
        try Endpoint(method: "GET", path: ["channels", channelID.description, "pins"], route: "/channels/{channel.id}/pins",
            authentication: .bot, majorParameter: channelID.description, retrySafety: .safe,
            readPolicy: messageReadPolicy(readPolicy, channelID: channelID), decode: messageArray)
    }

    /// Pins using the deprecated route; new code should use the current PIN_MESSAGES API.
    /// - Parameters:
    ///   - channelID: Channel major-rate partition.
    ///   - messageID: Target message.
    ///   - auditReason: Optional audit reason, at most 512 scalars.
    /// - Returns: A legacy PUT descriptor expecting empty 204.
    /// - Throws: Descriptor/audit errors; execution can fail or be indeterminate.
    @available(*, deprecated, message: "Use pin(channelID:messageID:auditReason:).")
    public static func legacyPin(channelID: ChannelID, messageID: MessageID, auditReason: String? = nil) throws -> Endpoint<EmptyResponse> {
        try messageEmpty("PUT", channelID: channelID, path: ["channels", channelID.description, "pins", messageID.description],
            route: "/channels/{channel.id}/pins/{message.id}", auditReason: auditReason)
    }

    /// Unpins using the deprecated route; new code should use the current PIN_MESSAGES API.
    /// - Parameters:
    ///   - channelID: Channel major-rate partition.
    ///   - messageID: Target message.
    ///   - auditReason: Optional audit reason, at most 512 scalars.
    /// - Returns: A legacy DELETE descriptor expecting empty 204.
    /// - Throws: Descriptor/audit errors; execution preserves API failures and uncertainty.
    @available(*, deprecated, message: "Use unpin(channelID:messageID:auditReason:).")
    public static func legacyUnpin(channelID: ChannelID, messageID: MessageID, auditReason: String? = nil) throws -> Endpoint<EmptyResponse> {
        try messageEmpty("DELETE", channelID: channelID, path: ["channels", channelID.description, "pins", messageID.description],
            route: "/channels/{channel.id}/pins/{message.id}", auditReason: auditReason)
    }

    /// Searches one guild. Requires READ_MESSAGE_HISTORY and MESSAGE_CONTENT eligibility.
    /// Search may return HTTP 202/indexing; a short or empty result page does not prove exhaustion.
    /// - Parameters:
    ///   - guildID: Guild whose authorized messages are searched; guild IDs are not rate-limit major keys.
    ///   - query: Complete typed query including initial offset and filters.
    ///   - offset: Optional paging override, 0...9975; nil uses the query's initial offset.
    /// - Returns: A safe GET descriptor accepting 200/results and 202/indexing. Search is not cached
    ///   or coalesced, so an indexing response never becomes a retained completed-result snapshot.
    /// - Throws: Query/descriptor errors; malformed envelopes fail safely during execution.
    public static func search(guildID: GuildID, query: MessageSearchQuery, offset: Int? = nil) throws -> Endpoint<MessageSearchResponse> {
        try Endpoint(method: "GET", path: ["guilds", guildID.description, "messages", "search"],
            route: "/guilds/{guild.id}/messages/search", query: query.queryItems(offset: offset), authentication: .bot,
            successStatuses: [200, 202], retrySafety: .safe,
            maximumQueryItems: 2_048, maximumMetadataBytes: 1_048_576, decode: { try MessageSearchResponse(data: $0) })
    }
}

/// Requires a positive operation-specific list-page count before descriptor construction.
/// - Parameters:
///   - limit: Requested item count.
///   - maximum: Inclusive published upper bound.
/// - Throws: A safe validation error outside `1...maximum`; performs no I/O.
func messageLimit(_ limit: Int, maximum: Int) throws {
    guard limit > 0, limit <= maximum else { throw DiscordError.validation(.invalidValue) }
}

/// Builds an exact channel/message path without escaping twice or dropping ID bits.
/// - Parameters:
///   - channelID: Channel segment.
///   - messageID: Message segment.
/// - Returns: Raw path segments; the endpoint alone owns percent encoding.
func messagePath(_ channelID: ChannelID, _ messageID: MessageID) -> [String] {
    ["channels", channelID.description, "messages", messageID.description]
}

/// Returns bounded authentication-scoped invalidation tags used by all 5A writes.
/// - Parameter channelID: Channel being modified.
/// - Returns: One channel tag plus a cross-channel search tag, never a credential.
func messageTags(_ channelID: ChannelID) -> Set<String> { ["messages:" + channelID.description, "message-search"] }

/// Adds resource invalidation to caller-selected read reuse without enabling caching implicitly.
/// - Parameters:
///   - policy: Optional caller policy; nil keeps reuse disabled.
///   - channelID: Read channel.
/// - Returns: The same eligibility/TTL with channel tags and a shared message-catalog visibility
///   tag added, or nil. Guild membership/role/permission mutations invalidate that shared tag within
///   the authentication identity. Unobserved external changes can remain stale until TTL expiry;
///   snapshots never establish current permission. No caching is enabled by adding tags.
func messageReadPolicy(_ policy: ReadPolicy?, channelID: ChannelID) -> ReadPolicy? {
    policy.map { ReadPolicy(coalescing: $0.coalescing, timeToLive: $0.timeToLive,
        tags: $0.tags.union(messageTags(channelID)).union(["message-catalog"])) }
}

/// Constructs conservative empty-result channel mutations through the common HTTP pipeline.
/// - Parameters:
///   - method: PUT or DELETE operation.
///   - channelID: Major-rate partition and invalidation owner.
///   - path: Complete unescaped relative segments.
///   - route: Stable normalized rate route.
///   - auditReason: Optional supported audit reason.
/// - Returns: An unsafe descriptor expecting exactly empty 204 success.
/// - Throws: Safe route/audit/metadata errors; construction owns no stream or network resource.
func messageEmpty(_ method: String, channelID: ChannelID, path: [String], route: String,
                  auditReason: String? = nil) throws -> Endpoint<EmptyResponse> {
    try Endpoint(method: method, path: path, route: route, authentication: .bot, successStatuses: [204],
        majorParameter: channelID.description, auditReason: auditReason, invalidates: messageTags(channelID),
        decode: { try EmptyResponse(data: $0) })
}

/// Decodes a bounded exact JSON array of messages; no Foundation JSON number bridge is used.
/// - Parameter data: Complete UTF-8 array, bounded by the client's response cap and JSONLimits.default.
/// - Returns: Typed messages in server order, including an empty array.
/// - Throws: Safe parser/schema errors for invalid roots or message fields.
func messageArray(_ data: Data) throws -> [Message] {
    guard case .array(let values) = try JSONValue.parse(data) else { throw DiscordError.transport(.invalidResponse) }
    return try values.map { try Message(data: $0.serialized()) }
}

/// Decodes the existing partial User projection from an API list response.
/// - Parameter data: Complete UTF-8 JSON array; precise snowflakes remain strings.
/// - Returns: Ordered users, including empty lists. User-family unmodeled fields remain in rawFields.
/// - Throws: Safe parser/schema errors; no malformed element is silently skipped.
func messageUsers(_ data: Data) throws -> [User] {
    guard case .array(let values) = try JSONValue.parse(data) else { throw DiscordError.transport(.invalidResponse) }
    return try values.map { try User(data: $0.serialized()) }
}

/// Validates unique upload identifiers before constructing a dictionary or opening any factory.
/// - Parameter files: Explicit finite upload list supplied by the caller.
/// - Returns: ID-to-media-type metadata; no byte producer is opened.
/// - Throws: Safe validation errors for duplicate IDs. Other file invariants are checked at file construction.
func messageUploadTypes(_ files: [MessageUploadFile]) throws -> [Int: String] {
    guard Set(files.map(\.id)).count == files.count else { throw DiscordError.validation(.invalidValue) }
    return Dictionary(uniqueKeysWithValues: files.map { ($0.id, $0.contentType) })
}

/// Validates one complete explicit bulk-delete input before any chunk is sent.
/// - Parameters:
///   - ids: Ordered IDs, at least two and no more than the caller's finite maximum.
///   - maximum: Allowed item count, at most the operation helper's finite plan size.
///   - nowMilliseconds: Trusted current Unix milliseconds; age is inferred from snowflakes only.
/// - Throws: A safe validation error for counts, duplicates or messages older than fourteen days.
///   Discord independently validates availability, permission and age at actual execution time.
func validateBulkMessageIDs(_ ids: [MessageID], maximum: Int, nowMilliseconds: UInt64) throws {
    let age: UInt64 = 14 * 24 * 60 * 60 * 1_000
    let oldest = nowMilliseconds > age ? nowMilliseconds - age : 0
    guard (2...maximum).contains(ids.count), Set(ids).count == ids.count,
          ids.allSatisfy({ $0.timestampMilliseconds >= oldest }) else { throw DiscordError.validation(.invalidValue) }
}
