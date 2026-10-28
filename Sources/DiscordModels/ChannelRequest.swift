// File: Sources/DiscordModels/ChannelRequest.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import Foundation

/// A validated partial permission overwrite; arbitrary-width permission decimals never pass through integers.
/// See https://docs.discord.com/developers/resources/channel#overwrite-object (API v10).
public struct ChannelPermissionOverwrite: Sendable {
    public let id: ChannelOverwriteTargetID
    public let type: ChannelOverwriteType
    public let allow: Field<String>
    public let deny: Field<String>
    private let fields: [String: JSONValue]

    /// Validates an overwrite without checking guild membership or the caller's permission ceiling.
    /// - Parameters:
    ///   - id: Role/member ID selected by `type`, including all unsigned snowflake bits.
    ///   - type: Whether the target is a role or member.
    ///   - allow: Omitted/null defaults to zero upstream; values are nonempty ASCII unsigned decimals of any width.
    ///   - deny: Omitted/null defaults to zero upstream; values follow the same decimal rules as `allow`.
    /// - Throws: Safe validation errors for malformed decimal strings; no input is included in diagnostics.
    public init(id: ChannelOverwriteTargetID, type: ChannelOverwriteType,
                allow: Field<String> = .absent, deny: Field<String> = .absent) throws {
        try channelRequestPermission(allow); try channelRequestPermission(deny)
        self.id = id; self.type = type; self.allow = allow; self.deny = deny
        var result = try channelRequestPermissionFields(type: type, allow: allow, deny: deny)
        result["id"] = .string(id.description); fields = result
    }

    /// Produces the partial overwrite object while preserving omission and explicit null.
    /// - Returns: Exact decimal permission strings and the target ID; no permission is granted locally.
    public func jsonValue() -> JSONValue {
        .object(fields)
    }
}

/// API v10 Edit Channel Permissions payload; sending requires MANAGE_ROLES and server-side permission checks.
/// Used by PUT /channels/{channel.id}/permissions/{overwrite.id}; emits Channel Update on success.
public struct ChannelPermissionEdit: Sendable {
    public let type: ChannelOverwriteType
    public let allow: Field<String>
    public let deny: Field<String>
    private let fields: [String: JSONValue]

    /// Validates the overwrite payload without performing I/O or changing permissions.
    /// - Parameters:
    ///   - type: Required target category, role or member.
    ///   - allow: Omitted/null defaults to zero; nonnull values are nonempty unsigned ASCII decimals of any width.
    ///   - deny: Omitted/null defaults to zero; nonnull values use the same arbitrary-width decimal representation.
    /// - Throws: Safe validation errors for signs, whitespace, nondecimal scalars or empty permission strings.
    public init(type: ChannelOverwriteType, allow: Field<String> = .absent, deny: Field<String> = .absent) throws {
        try channelRequestPermission(allow); try channelRequestPermission(deny)
        self.type = type; self.allow = allow; self.deny = deny
        fields = try channelRequestPermissionFields(type: type, allow: allow, deny: deny)
    }

    /// Encodes immutable validated fields for PUT channel permissions.
    /// - Returns: An object retaining explicit nulls and upstream-default omissions.
    public func jsonValue() -> JSONValue { .object(fields) }
}

/// Default forum/media reaction request; exactly one custom or Unicode emoji is selected.
public struct ChannelDefaultReactionRequest: Sendable {
    private let fields: [String: JSONValue]

    /// Selects one custom guild emoji without checking guild availability.
    /// - Parameter emojiID: Custom emoji snowflake, retained as an exact decimal string.
    public init(emojiID: EmojiID) { fields = ["emoji_id": .string(emojiID.description), "emoji_name": .null] }

    /// Selects one Unicode emoji; Discord decides whether the nonempty string is an eligible emoji.
    /// - Parameter emojiName: Nonempty Unicode emoji string, retained without normalization.
    /// - Throws: A safe validation error for an empty name.
    public init(emojiName: String) throws {
        guard !emojiName.isEmpty else { throw DiscordError.validation(.invalidValue) }
        fields = ["emoji_id": .null, "emoji_name": .string(emojiName)]
    }

    /// Produces both nullable emoji fields with exactly one nonnull selector.
    /// - Returns: A default-reaction object without resource lookup or side effects.
    public func jsonValue() -> JSONValue { .object(fields) }
}

/// Partial forum/media tag used by Modify Channel; omitted IDs create tags and present IDs update tags.
public struct ChannelForumTagRequest: Sendable {
    public let id: ForumTagID?
    public let name: String
    public let moderated: Bool?
    public let emojiID: Field<EmojiID>
    public let emojiName: Field<String>

    /// Validates a tag without resolving emoji availability or MANAGE_THREADS privileges.
    /// - Parameters:
    ///   - id: Existing tag ID, or nil to request a new tag.
    ///   - name: Required name containing 0...20 Unicode scalars; empty names are documented as valid.
    ///   - moderated: Optional restriction to members with MANAGE_THREADS; omitted retains upstream behavior.
    ///   - emojiID: Omitted/null/custom emoji selector; at most one emoji selector may be nonnull.
    ///   - emojiName: Omitted/null/Unicode emoji selector; nonnull strings must be nonempty.
    /// - Throws: Safe validation errors for an overlong name, empty emoji or conflicting selectors.
    public init(id: ForumTagID? = nil, name: String, moderated: Bool? = nil,
                emojiID: Field<EmojiID> = .absent, emojiName: Field<String> = .absent) throws {
        guard name.unicodeScalars.count <= 20 else { throw DiscordError.validation(.limitExceeded) }
        if case .value = emojiID, case .value = emojiName { throw DiscordError.validation(.invalidValue) }
        if case .value(let value) = emojiName, value.isEmpty { throw DiscordError.validation(.invalidValue) }
        self.id = id; self.name = name; self.moderated = moderated; self.emojiID = emojiID; self.emojiName = emojiName
    }

    /// Produces the partial tag without inventing an ID or filling absent emoji fields.
    /// - Returns: Required name and all explicitly selected optional fields.
    public func jsonValue() -> JSONValue {
        var fields: [String: JSONValue] = ["name": .string(name)]
        if let id { fields["id"] = .string(id.description) }
        if let moderated { fields["moderated"] = .bool(moderated) }
        channelRequestOptional(emojiID, name: "emoji_id", into: &fields) { .string($0.description) }
        channelRequestOptional(emojiName, name: "emoji_name", into: &fields) { .string($0) }
        return .object(fields)
    }
}

/// API v10 Modify Channel, validated against an explicit existing channel kind.
/// Used by PATCH /channels/{channel.id}; see https://docs.discord.com/developers/resources/channel#modify-channel.
///
/// Guild edits require MANAGE_CHANNELS, overwrites additionally MANAGE_ROLES, and thread edits
/// normally MANAGE_THREADS. Unarchiving an unlocked thread can use SEND_MESSAGES. Discord alone
/// checks current archived/NSFW state, guild features, boost bitrate ceilings and permissions.
/// This value performs no reads, mutations, retry, pagination or credential access.
public struct ChannelModify: Sendable {
    /// Existing channel type supplied by the caller; the optional outgoing `type` may convert text/announcement.
    public let channelType: ChannelType
    /// Parent evidence used to validate forum/media-only thread settings; never encoded in the body.
    public let parentChannelType: ChannelType?
    private let fields: [String: JSONValue]

    /// Validates every documented group-DM, guild and thread modification field without upstream I/O.
    /// - Parameters:
    ///   - channelType: Existing kind; direct DMs have no supported edit payload here.
    ///   - parentChannelType: Thread parent kind; a public thread with forum/media evidence is required for applied tags or PINNED.
    ///   - name: Omitted or 1...100 Unicode scalars; null is forbidden.
    ///   - icon: Group-DM-only canonical base64 icon, optionally an image data URI; null is forbidden.
    ///   - type: Omitted or text/announcement conversion; the guild NEWS feature remains a server check.
    ///   - position: Guild-channel listing position; null and exact signed integer positions are transmitted without imposing an undocumented range.
    ///   - topic: Nullable text/announcement topic up to 1,024 scalars, forum/media up to 4,096.
    ///   - nsfw: Nullable age restriction on supported guild channel kinds; incompatible with a sent spoiler flag.
    ///   - rateLimitPerUser: Nullable 0...21,600 second slowmode; unsupported on announcements/categories/group DMs.
    ///   - bitrate: Nullable voice/stage bits per second, at least 8,000; stage maximum 64,000, voice 384,000.
    ///   - userLimit: Nullable voice limit 0...99 or stage limit 0...10,000; zero means unlimited.
    ///   - permissionOverwrites: Nullable complete guild overwrite list; duplicate target/category pairs are rejected.
    ///   - parentID: Nullable guild category ID; categories, DMs and threads cannot set this field.
    ///   - rtcRegion: Nullable voice/stage region ID; null selects automatic routing, nonnull must be nonempty.
    ///   - videoQualityMode: Nullable voice/stage AUTO/FULL camera mode.
    ///   - defaultAutoArchiveDuration: Nullable text/announcement/forum/media archive duration in minutes: 60, 1440, 4320 or 10080.
    ///   - flags: Omitted or known writable type-compatible bits; read-only obfuscation and unknown bits are rejected.
    ///   - availableTags: Forum/media-only array of at most 20 tags with distinct supplied IDs; null is forbidden.
    ///   - defaultReactionEmoji: Nullable forum/media default reaction; null clears the selection.
    ///   - defaultThreadRateLimitPerUser: Text/forum/media initial thread slowmode, 0...21,600 seconds; null is forbidden.
    ///   - defaultSortOrder: Nullable forum/media activity/creation sort order.
    ///   - defaultForumLayout: Forum-only default layout; null is forbidden.
    ///   - archived: Thread-only archive state; null is forbidden and existing state is not fetched.
    ///   - autoArchiveDuration: Thread-only archive duration in the four documented minute choices; null is forbidden.
    ///   - locked: Thread-only lock state; null is forbidden.
    ///   - invitable: Private-thread-only nonmoderator invitations; null is forbidden.
    ///   - appliedTags: Forum/media-child thread tag IDs, at most five distinct IDs; null is forbidden.
    /// - Throws: Safe validation errors for bounds, forbidden nulls, type-incompatible fields or combinations.
    ///   Boost-dependent voice limits below the absolute ceiling and omitted prior NSFW state remain server checks.
    public init(channelType: ChannelType, parentChannelType: ChannelType? = nil,
                name: Field<String> = .absent, icon: Field<String> = .absent, type: Field<ChannelType> = .absent,
                position: Field<Int> = .absent, topic: Field<String> = .absent, nsfw: Field<Bool> = .absent,
                rateLimitPerUser: Field<Int> = .absent, bitrate: Field<Int> = .absent, userLimit: Field<Int> = .absent,
                permissionOverwrites: Field<[ChannelPermissionOverwrite]> = .absent, parentID: Field<ChannelID> = .absent,
                rtcRegion: Field<String> = .absent, videoQualityMode: Field<ChannelVideoQualityMode> = .absent,
                defaultAutoArchiveDuration: Field<Int> = .absent, flags: Field<ChannelFlags> = .absent,
                availableTags: Field<[ChannelForumTagRequest]> = .absent,
                defaultReactionEmoji: Field<ChannelDefaultReactionRequest> = .absent,
                defaultThreadRateLimitPerUser: Field<Int> = .absent,
                defaultSortOrder: Field<ChannelSortOrder> = .absent, defaultForumLayout: Field<ChannelForumLayout> = .absent,
                archived: Field<Bool> = .absent, autoArchiveDuration: Field<Int> = .absent,
                locked: Field<Bool> = .absent, invitable: Field<Bool> = .absent, appliedTags: Field<[ForumTagID]> = .absent) throws {
        var result: [String: JSONValue] = [:]
        try channelRequestField(name, name: "name", into: &result) { try channelRequestName($0) }
        try channelRequestField(icon, name: "icon", into: &result) { try channelRequestIcon($0) }
        try channelRequestField(type, name: "type", into: &result) { try channelRequestNumber($0.rawValue) }
        try channelRequestField(position, name: "position", nullable: true, into: &result) { try channelRequestNumber($0) }
        try channelRequestField(topic, name: "topic", nullable: true, into: &result) {
            guard $0.unicodeScalars.count <= ([15, 16].contains(channelType.rawValue) ? 4_096 : 1_024)
            else { throw DiscordError.validation(.limitExceeded) }; return .string($0)
        }
        try channelRequestField(nsfw, name: "nsfw", nullable: true, into: &result) { .bool($0) }
        try channelRequestField(rateLimitPerUser, name: "rate_limit_per_user", nullable: true, into: &result) { try channelRequestRange($0, 0...21_600) }
        try channelRequestField(bitrate, name: "bitrate", nullable: true, into: &result) { try channelRequestRange($0, 8_000...(channelType.rawValue == 13 ? 64_000 : 384_000)) }
        try channelRequestField(userLimit, name: "user_limit", nullable: true, into: &result) { try channelRequestRange($0, 0...(channelType.rawValue == 13 ? 10_000 : 99)) }
        try channelRequestField(permissionOverwrites, name: "permission_overwrites", nullable: true, into: &result) {
            let keys = $0.map { "\($0.type.rawValue):\($0.id.description)" }
            guard Set(keys).count == keys.count else { throw DiscordError.validation(.invalidValue) }
            return .array($0.map { $0.jsonValue() })
        }
        try channelRequestField(parentID, name: "parent_id", nullable: true, into: &result) { .string($0.description) }
        try channelRequestField(rtcRegion, name: "rtc_region", nullable: true, into: &result) {
            guard !$0.isEmpty else { throw DiscordError.validation(.invalidValue) }; return .string($0)
        }
        try channelRequestField(videoQualityMode, name: "video_quality_mode", nullable: true, into: &result) { try channelRequestNumber($0.rawValue) }
        try channelRequestField(defaultAutoArchiveDuration, name: "default_auto_archive_duration", nullable: true, into: &result) { try channelRequestArchive($0) }
        try channelRequestField(flags, name: "flags", into: &result) { try channelRequestNumber($0.rawValue) }
        try channelRequestField(availableTags, name: "available_tags", into: &result) {
            let ids = $0.compactMap(\.id)
            guard $0.count <= 20, Set(ids).count == ids.count else { throw DiscordError.validation(.invalidValue) }
            return .array($0.map { $0.jsonValue() })
        }
        try channelRequestField(defaultReactionEmoji, name: "default_reaction_emoji", nullable: true, into: &result) { $0.jsonValue() }
        try channelRequestField(defaultThreadRateLimitPerUser, name: "default_thread_rate_limit_per_user", into: &result) { try channelRequestRange($0, 0...21_600) }
        try channelRequestField(defaultSortOrder, name: "default_sort_order", nullable: true, into: &result) { try channelRequestNumber($0.rawValue) }
        try channelRequestField(defaultForumLayout, name: "default_forum_layout", into: &result) { try channelRequestNumber($0.rawValue) }
        try channelRequestField(archived, name: "archived", into: &result) { .bool($0) }
        try channelRequestField(autoArchiveDuration, name: "auto_archive_duration", into: &result) { try channelRequestArchive($0) }
        try channelRequestField(locked, name: "locked", into: &result) { .bool($0) }
        try channelRequestField(invitable, name: "invitable", into: &result) { .bool($0) }
        try channelRequestField(appliedTags, name: "applied_tags", into: &result) { try channelRequestTags($0) }
        let kind = channelType.rawValue
        let guild = [0, 2, 4, 5, 13, 14, 15, 16].contains(kind)
        let thread = [10, 11, 12].contains(kind)
        guard guild || thread || kind == 3 else { throw DiscordError.validation(.invalidValue) }
        var allowed: Set<String> = ["name"]
        if kind == 3 { allowed.insert("icon") }
        if guild { allowed.formUnion(["position", "permission_overwrites"]) }
        if [0, 5].contains(kind) { allowed.insert("type") }
        if [0, 5, 15, 16].contains(kind) { allowed.formUnion(["topic", "default_auto_archive_duration"]) }
        if [0, 2, 5, 13, 15, 16].contains(kind) { allowed.formUnion(["nsfw", "parent_id"]) }
        if [0, 2, 13, 15, 16].contains(kind) || thread { allowed.insert("rate_limit_per_user") }
        if [2, 13].contains(kind) { allowed.formUnion(["bitrate", "user_limit", "rtc_region", "video_quality_mode"]) }
        if [0, 2, 5, 15, 16].contains(kind) || thread { allowed.insert("flags") }
        if [15, 16].contains(kind) { allowed.formUnion(["available_tags", "default_reaction_emoji", "default_sort_order"]) }
        if [0, 15, 16].contains(kind) { allowed.insert("default_thread_rate_limit_per_user") }
        if kind == 15 { allowed.insert("default_forum_layout") }
        if thread { allowed.formUnion(["archived", "auto_archive_duration", "locked"]) }
        if kind == 12 { allowed.insert("invitable") }
        let forumThread = kind == 11 && [15, 16].contains(parentChannelType?.rawValue ?? -1)
        if forumThread { allowed.insert("applied_tags") }
        guard Set(result.keys).isSubset(of: allowed) else { throw DiscordError.validation(.invalidValue) }
        if case .value(let value) = type, ![0, 5].contains(value.rawValue) { throw DiscordError.validation(.invalidValue) }
        if case .value(let value) = flags {
            var mask: UInt64 = [0, 2, 5, 15, 16, 10, 11, 12].contains(kind) ? 1 << 21 : 0
            if [15, 16].contains(kind) { mask |= 1 << 4 }
            if kind == 16 { mask |= 1 << 15 }
            if forumThread { mask |= 1 << 1 }
            guard value.rawValue & ~mask == 0 else { throw DiscordError.validation(.invalidValue) }
            if value.rawValue & (1 << 21) != 0, case .value(true) = nsfw { throw DiscordError.validation(.invalidValue) }
        }
        self.channelType = channelType; self.parentChannelType = parentChannelType; fields = result
    }

    /// Produces the exact validated PATCH body; no context-only fields or defaults are added.
    /// - Returns: An object including explicit nulls; an empty object is a valid no-change request.
    public func jsonValue() -> JSONValue { .object(fields) }
}

/// API v10 voice status update; SET_VOICE_CHANNEL_STATUS is required, plus MANAGE_CHANNELS when disconnected.
/// Used by PUT /channels/{channel.id}/voice-status; emits Voice Channel Status Update on success.
public struct VoiceChannelStatus: Sendable {
    public let status: String?

    /// Validates a voice status without connecting to voice or checking permissions.
    /// - Parameter status: Nil clears the status; otherwise up to 500 Unicode scalars, including empty text.
    /// - Throws: A safe limit-exceeded error when text exceeds 500 scalars.
    public init(status: String?) throws {
        guard (status?.unicodeScalars.count ?? 0) <= 500 else { throw DiscordError.validation(.limitExceeded) }
        self.status = status
    }

    /// Encodes the required nullable status key for PUT voice-status.
    /// - Returns: A single-field object; nil is explicit JSON null, never omission.
    public func jsonValue() -> JSONValue { .object(["status": status.map(JSONValue.string) ?? .null]) }
}

/// API v10 Group DM recipient addition using the recipient's OAuth2 gdm.join access token.
/// Used by PUT /channels/{channel.id}/recipients/{user.id}; the token belongs in the body, not a path.
/// Ordinary descriptions and reflection conceal both the token and nickname; explicit encoding exposes them.
public struct GroupDMRecipientAdd: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    private let accessToken: BearerToken
    private let nick: String

    /// Stores an already validated OAuth2 secret and nickname without inspecting scopes or expiry.
    /// - Parameters:
    ///   - accessToken: Recipient's access token; caller must obtain gdm.join consent before execution.
    ///   - nick: Exact required nickname; the reference specifies no local length range, so Discord validates it.
    public init(accessToken: BearerToken, nick: String) { self.accessToken = accessToken; self.nick = nick }

    /// Validates credential syntax before storing a redacted recipient request.
    /// - Parameters:
    ///   - accessToken: Nonempty token without whitespace/control characters or an authorization prefix.
    ///   - nick: Exact required nickname; no undocumented size constraint is imposed.
    /// - Throws: Safe credential-validation errors; token and nickname are excluded from diagnostics.
    public init(accessToken: String, nick: String) throws { self.init(accessToken: try BearerToken(accessToken), nick: nick) }

    /// Explicitly exposes the token only in the outgoing body; callers must keep the returned object out of logs.
    /// - Returns: Required access_token and nick fields, without checking upstream OAuth consent.
    public func jsonValue() -> JSONValue { accessToken.withUnsafeValue { .object(["access_token": .string($0), "nick": .string(nick)]) } }
    /// Fixed diagnostic marker independent of credential and nickname content or length.
    public var description: String { "GroupDMRecipientAdd(redacted)" }
    /// Safe debug marker with no credential data.
    public var debugDescription: String { description }
    /// Redacted reflection that never recursively exposes stored secrets or personal nicknames.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}

/// API v10 thread creation from an existing text/announcement message; IDs remain endpoint path arguments.
/// Used by POST /channels/{channel.id}/messages/{message.id}/threads; one source message can own one thread.
public struct ThreadStartFromMessage: Sendable {
    private let fields: [String: JSONValue]

    /// Validates thread settings without fetching the source message or inferring create permissions.
    /// - Parameters:
    ///   - name: Required 1...100 scalar name; Discord may normalize it.
    ///   - autoArchiveDuration: Optional inactivity duration in minutes, one of 60, 1440, 4320, 10080.
    ///   - rateLimitPerUser: Omitted/null or 0...21,600 second slowmode; null is preserved exactly.
    /// - Throws: Safe validation errors for invalid names or numeric limits.
    public init(name: String, autoArchiveDuration: Int? = nil, rateLimitPerUser: Field<Int> = .absent) throws {
        fields = try channelRequestThreadFields(name: name, autoArchiveDuration: autoArchiveDuration, rateLimitPerUser: rateLimitPerUser)
    }

    /// Encodes immutable settings; the source message determines public versus announcement thread kind.
    /// - Returns: Validated JSON object with omitted defaults and explicit nullable slowmode.
    public func jsonValue() -> JSONValue { .object(fields) }
}

/// API v10 thread creation without a message; omission retains v10's PRIVATE_THREAD default.
/// Used by POST /channels/{channel.id}/threads; emits Thread Create on success.
public struct ThreadStartWithoutMessage: Sendable {
    private let fields: [String: JSONValue]

    /// Validates thread creation with optional explicit type, without checking parent-channel eligibility.
    /// - Parameters:
    ///   - name: Required 1...100 scalar thread name.
    ///   - type: Announcement/public/private thread, or nil for API v10's private-thread default; parent eligibility is checked by Discord.
    ///   - autoArchiveDuration: Optional 60, 1440, 4320 or 10080 minute inactivity duration.
    ///   - invitable: Optional nonmoderator invite setting; legal only for explicit/default private threads.
    ///   - rateLimitPerUser: Omitted/null or 0...21,600 second slowmode.
    /// - Throws: Safe validation errors for incompatible type/invitable settings or invalid shared fields.
    public init(name: String, type: ChannelType? = nil, autoArchiveDuration: Int? = nil,
                invitable: Bool? = nil, rateLimitPerUser: Field<Int> = .absent) throws {
        guard type.map({ [10, 11, 12].contains($0.rawValue) }) ?? true,
              invitable == nil || (type?.rawValue ?? 12) == 12 else { throw DiscordError.validation(.invalidValue) }
        var result = try channelRequestThreadFields(name: name, autoArchiveDuration: autoArchiveDuration, rateLimitPerUser: rateLimitPerUser)
        if let type { result["type"] = try channelRequestNumber(type.rawValue) }
        if let invitable { result["invitable"] = .bool(invitable) }
        fields = result
    }

    /// Encodes settings without adding an explicit type when the caller selected the v10 default.
    /// - Returns: Validated JSON object; sending can fail for parent state, permissions or archive limits.
    public func jsonValue() -> JSONValue { .object(fields) }
}

/// API v10 forum/media thread creation, restricted to its documented first-message field subset.
/// Used by POST /channels/{channel.id}/threads; emits Thread Create and Message Create on success.
/// SEND_MESSAGES is required; the resulting thread is PUBLIC_THREAD. Binary parts belong to the HTTP layer.
public struct ForumThreadStart: Sendable {
    private let fields: [String: JSONValue]
    public let message: MessageCreate

    /// Validates thread metadata and context-independent message restrictions without opening uploads.
    /// - Parameters:
    ///   - name: Required 1...100 scalar thread name.
    ///   - message: Initial message; only content, embeds, allowed mentions, components, stickers, attachments and
    ///     SUPPRESS_EMBEDS/SUPPRESS_NOTIFICATIONS flags are accepted. TTS, nonce, references, polls, themes,
    ///     voice messages and Components V2 are excluded by the forum/media endpoint's current schema.
    ///   - autoArchiveDuration: Optional 60, 1440, 4320 or 10080 minute inactivity duration.
    ///   - rateLimitPerUser: Omitted/null or 0...21,600 second slowmode.
    ///   - appliedTags: Optional up to five distinct forum tag IDs; an empty array explicitly selects no tags.
    /// - Throws: Safe validation errors for unsupported message fields/flags, invalid thread metadata or tags.
    ///   The required nonempty message and upload metadata match are checked by `jsonValue` with actual files.
    public init(name: String, message: MessageCreate, autoArchiveDuration: Int? = nil,
                rateLimitPerUser: Field<Int> = .absent, appliedTags: [ForumTagID]? = nil) throws {
        var result = try channelRequestThreadFields(name: name, autoArchiveDuration: autoArchiveDuration, rateLimitPerUser: rateLimitPerUser)
        guard case .absent = message.nonce, case .absent = message.tts,
              case .absent = message.messageReference, case .absent = message.enforceNonce,
              case .absent = message.poll, case .absent = message.sharedClientTheme
        else { throw DiscordError.validation(.invalidValue) }
        if case .value(let flags) = message.flags, flags.rawValue & ~UInt64((1 << 2) | (1 << 12)) != 0 {
            throw DiscordError.validation(.invalidValue)
        }
        if let appliedTags { result["applied_tags"] = try channelRequestTags(appliedTags) }
        fields = result; self.message = message
    }

    /// Validates the complete first message against actual multipart uploads before serialization/execution.
    /// - Parameters:
    ///   - uploadIDs: Actual distinct nonnegative files[n] IDs; empty for a JSON-only request.
    ///   - uploadContentTypes: Actual upload media types; passed to the shared message validator.
    /// - Returns: Thread settings with one nested message object, excluding binary file bytes.
    /// - Throws: Safe validation errors for empty messages, duplicate/negative/unmatched files or attachment metadata.
    public func jsonValue(uploadIDs: [Int] = [], uploadContentTypes: [Int: String] = [:]) throws -> JSONValue {
        var result = fields
        result["message"] = try message.jsonValue(uploadIDs: uploadIDs, uploadContentTypes: uploadContentTypes)
        return .object(result)
    }
}

/// Inserts one presence-aware field and validates its nonnull value synchronously.
/// - Parameters:
///   - field: Omitted, null or typed request value.
///   - name: Exact Discord wire key.
///   - nullable: Whether explicit null is supported, default false.
///   - fields: Object under construction; no partial object escapes when validation fails.
///   - encode: Validation and encoding closure invoked only for nonnull values.
/// - Throws: Safe validation errors for forbidden nulls or errors from the supplied encoder.
private func channelRequestField<Value>(_ field: Field<Value>, name: String, nullable: Bool = false,
                                        into fields: inout [String: JSONValue], encode: (Value) throws -> JSONValue) throws {
    switch field {
    case .absent: break
    case .null:
        guard nullable else { throw DiscordError.validation(.invalidValue) }; fields[name] = .null
    case .value(let value): fields[name] = try encode(value)
    }
}

/// Inserts an already validated optional field whose null state is always supported.
/// - Parameters:
///   - field: Omitted/null/value selection whose nonnull representation has already passed validation.
///   - name: Exact wire key.
///   - fields: Destination object, mutated only by the selected field.
///   - encode: Nonthrowing encoder of the validated typed value.
private func channelRequestOptional<Value>(_ field: Field<Value>, name: String,
                                           into fields: inout [String: JSONValue], encode: (Value) -> JSONValue) {
    switch field {
    case .absent: break
    case .null: fields[name] = .null
    case .value(let value): fields[name] = encode(value)
    }
}

/// Formats an integral value without losing precision through Double or platform JSON bridges.
/// - Parameter value: Any integral value including UInt64.max.
/// - Returns: Exact canonical decimal JSON number.
/// - Throws: JSON numeric validation errors only if Swift integer formatting violates JSON grammar.
private func channelRequestNumber<Value: BinaryInteger>(_ value: Value) throws -> JSONValue {
    .number(try JSONNumber(rawValue: String(value)))
}

/// Validates a numeric setting against the endpoint's inclusive documented range.
/// - Parameters:
///   - value: Requested integer setting, before encoding.
///   - range: Inclusive allowed units/range selected by the caller's endpoint context.
/// - Returns: Exact JSON integer.
/// - Throws: Safe invalid-value errors outside the range, or numeric formatting errors.
private func channelRequestRange(_ value: Int, _ range: ClosedRange<Int>) throws -> JSONValue {
    guard range.contains(value) else { throw DiscordError.validation(.invalidValue) }
    return try channelRequestNumber(value)
}

/// Validates nonempty channel/thread names using scalar bounds consistent with other request models.
/// - Parameter value: Unnormalized name; Discord can normalize eligible characters.
/// - Returns: The original name as a JSON string.
/// - Throws: A safe invalid-value error outside 1...100 Unicode scalars.
private func channelRequestName(_ value: String) throws -> JSONValue {
    guard (1...100).contains(value.unicodeScalars.count) else { throw DiscordError.validation(.invalidValue) }
    return .string(value)
}

/// Validates one of Discord's four current auto-archive durations.
/// - Parameter value: Inactivity duration in minutes, not seconds.
/// - Returns: Exact JSON integer for 60, 1440, 4320 or 10080.
/// - Throws: A safe invalid-value error for any other duration.
private func channelRequestArchive(_ value: Int) throws -> JSONValue {
    guard [60, 1_440, 4_320, 10_080].contains(value) else { throw DiscordError.validation(.invalidValue) }
    return try channelRequestNumber(value)
}

/// Checks arbitrary-width unsigned permission strings without allocating a big integer or losing bits.
/// - Parameter field: Omitted/null default or nonempty ASCII decimal permission bitset, preserving leading zeroes.
/// - Throws: Safe invalid-value errors for malformed strings; magnitude is intentionally unbounded here.
private func channelRequestPermission(_ field: Field<String>) throws {
    if case .value(let value) = field {
        guard !value.isEmpty, value.utf8.allSatisfy({ (48...57).contains($0) })
        else { throw DiscordError.validation(.invalidValue) }
    }
}

/// Builds a validated permission payload without converting its arbitrary-width decimals.
/// - Parameters:
///   - type: Role/member selector previously checked by the enum.
///   - allow: Validated optional permission string.
///   - deny: Validated optional permission string.
/// - Returns: Required integral type plus explicitly selected allow/deny keys.
/// - Throws: A JSON numeric error only if integral enum formatting violates JSON grammar.
private func channelRequestPermissionFields(type: ChannelOverwriteType, allow: Field<String>, deny: Field<String>) throws -> [String: JSONValue] {
    var fields: [String: JSONValue] = ["type": try channelRequestNumber(type.rawValue)]
    channelRequestOptional(allow, name: "allow", into: &fields) { .string($0) }
    channelRequestOptional(deny, name: "deny", into: &fields) { .string($0) }
    return fields
}

/// Validates forum/media applied tags with the documented five-tag thread limit.
/// - Parameter values: Caller-ordered tag IDs; empty explicitly removes/selects no tags.
/// - Returns: Exact decimal-string ID array without sorting.
/// - Throws: Safe invalid-value errors for duplicates or more than five tags.
private func channelRequestTags(_ values: [ForumTagID]) throws -> JSONValue {
    guard values.count <= 5, Set(values).count == values.count else { throw DiscordError.validation(.invalidValue) }
    return .array(values.map { .string($0.description) })
}

/// Validates shared thread metadata, preserving omitted defaults and nullable slowmode.
/// - Parameters:
///   - name: Required thread name.
///   - autoArchiveDuration: Optional inactivity duration in documented minute choices.
///   - rateLimitPerUser: Omitted/null or bounded second-based slowmode.
/// - Returns: Complete validated shared thread fields.
/// - Throws: Safe validation errors for invalid names, durations or slowmode.
private func channelRequestThreadFields(name: String, autoArchiveDuration: Int?, rateLimitPerUser: Field<Int>) throws -> [String: JSONValue] {
    var fields: [String: JSONValue] = ["name": try channelRequestName(name)]
    if let autoArchiveDuration { fields["auto_archive_duration"] = try channelRequestArchive(autoArchiveDuration) }
    try channelRequestField(rateLimitPerUser, name: "rate_limit_per_user", nullable: true, into: &fields) { try channelRequestRange($0, 0...21_600) }
    return fields
}

/// Checks base64 transport syntax without decoding image dimensions, format compatibility or server limits.
/// - Parameter value: Canonical nonempty base64 or an image data URI containing canonical nonempty base64.
/// - Returns: Original unchanged icon text.
/// - Throws: Safe invalid-value errors for malformed data URIs, empty bytes or noncanonical base64.
private func channelRequestIcon(_ value: String) throws -> JSONValue {
    let encoded: String
    if value.hasPrefix("data:") {
        guard let separator = value.range(of: ";base64,"), value.hasPrefix("data:image/"),
              value[..<separator.lowerBound].count > "data:image/".count
        else { throw DiscordError.validation(.invalidValue) }
        encoded = String(value[separator.upperBound...])
    } else { encoded = value }
    guard let data = Data(base64Encoded: encoded), !data.isEmpty, data.base64EncodedString() == encoded
    else { throw DiscordError.validation(.invalidValue) }
    return .string(value)
}
