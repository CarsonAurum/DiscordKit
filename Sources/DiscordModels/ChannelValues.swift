import DiscordCore
import Foundation

/// Marker distinguishing forum/media tag identifiers from other Discord snowflakes.
public enum ForumTagTag: Sendable {}
/// Exact unsigned 64-bit forum/media tag identifier, encoded as a decimal string.
public typealias ForumTagID = Snowflake<ForumTagTag>

/// Marker distinguishing custom emoji identifiers from other Discord snowflakes.
public enum ChannelEmojiTag: Sendable {}
/// Exact unsigned 64-bit custom emoji identifier, encoded as a decimal string.
public typealias EmojiID = Snowflake<ChannelEmojiTag>

/// Marker distinguishing role-or-user permission overwrite target identifiers from other Discord snowflakes.
public enum ChannelOverwriteTargetTag: Sendable {}
/// Exact unsigned 64-bit role-or-user permission overwrite target identifier, encoded as a decimal string.
public typealias ChannelOverwriteTargetID = Snowflake<ChannelOverwriteTargetTag>

/// Documented channel variants; wrap response values in RawValue to retain future integral types.
/// API v10; official Channel resource reviewed 2026-10-16.
public enum ChannelType: Int, Sendable {
    /// Guild text channel.
    case guildText = 0
    /// Direct message channel.
    case dm = 1
    /// Guild voice channel.
    case guildVoice = 2
    /// Group direct message channel.
    case groupDM = 3
    /// Guild channel category.
    case guildCategory = 4
    /// Guild announcement channel, formerly news.
    case guildAnnouncement = 5
    /// Thread under an announcement channel; API v9 or later.
    case announcementThread = 10
    /// Public text, forum or media thread; API v9 or later.
    case publicThread = 11
    /// Private text thread; API v9 or later.
    case privateThread = 12
    /// Guild Stage voice channel.
    case guildStageVoice = 13
    /// Guild directory channel for a hub.
    case guildDirectory = 14
    /// Guild forum channel containing threads.
    case guildForum = 15
    /// Guild media channel; only documented behaviors are supported.
    case guildMedia = 16
}

/// Known camera quality modes; RawValue preserves future response variants.
/// API v10; official Channel resource reviewed 2026-10-16.
public enum ChannelVideoQualityMode: Int, Sendable {
    /// Discord selects camera quality.
    case auto = 1
    /// 720p camera quality.
    case full = 2
}

/// Known default forum/media post ordering; null is modeled separately.
/// API v10; official Channel resource reviewed 2026-10-16.
public enum ChannelSortOrder: Int, Sendable {
    /// Order posts by recent activity.
    case latestActivity = 0
    /// Order posts by creation time, newest first.
    case creationDate = 1
}

/// Known default forum layouts; response unknown values remain in RawValue.
/// API v10; official Channel resource reviewed 2026-10-16.
public enum ChannelForumLayout: Int, Sendable {
    /// No administrator default layout.
    case notSet = 0
    /// Display posts as a list.
    case listView = 1
    /// Display posts as a gallery.
    case galleryView = 2
}

/// Known permission overwrite target variants; unknown response integers remain raw.
/// API v10; official Channel resource reviewed 2026-10-16.
public enum ChannelOverwriteType: Int, Sendable {
    /// The overwrite targets a role.
    case role = 0
    /// The overwrite targets a member.
    case member = 1
}

/// Named response channel bits, retaining every unknown unsigned bit without inferring permissions.
/// The response wire field remains UInt64; this wrapper is not an outgoing mutation whitelist.
public struct ChannelFlags: OptionSet, Sendable, Hashable {
    /// Exact unsigned server bitfield, including future combinations.
    public let rawValue: UInt64

    /// Retains the entire response bitfield without clearing or rejecting unknown bits.
    /// - Parameter rawValue: Any unsigned 64-bit combination, including zero and currently unknown flags.
    /// This synchronous value construction has no I/O, permission inference or resource ownership.
    public init(rawValue: UInt64) { self.rawValue = rawValue }

    /// Thread pinned to its parent forum/media channel.
    public static let pinned = Self(rawValue: 1 << 1)
    /// Forum/media threads require an applied tag.
    public static let requireTag = Self(rawValue: 1 << 4)
    /// Media channel embedded downloads are hidden.
    public static let hideMediaDownloadOptions = Self(rawValue: 1 << 15)
    /// Gateway channel metadata is obfuscated; HTTP never sets this bit.
    public static let channelObfuscated = Self(rawValue: 1 << 17)
    /// Users must opt in before viewing this Spoiler Channel.
    public static let isSpoilerChannel = Self(rawValue: 1 << 21)
}

/// Validates response permission strings without narrowing future permission bits to machine width.
/// - Parameter value: Nonempty ASCII decimal digits; leading zeroes and arbitrary widths are retained unchanged.
/// - Throws: Sanitized invalid-response errors for empty strings, signs, whitespace, Unicode digits or other syntax.
/// Validation is linear in the bounded input bytes, performs no integer conversion and establishes no authorization.
func validateChannelPermissionBits(_ value: String) throws {
    guard !value.isEmpty, value.utf8.allSatisfy({ (48...57).contains($0) })
    else { throw DiscordError.transport(.invalidResponse) }
}

/// A role-or-member permission overwrite; allow/deny are unbounded decimal strings, never computed effective permissions.
/// API v10; verified against https://docs.discord.com/developers/resources/channel on 2026-10-16.
public struct ChannelOverwrite: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Role or user snowflake; type distinguishes the target family and unknown types remain raw.
    public let id: ChannelOverwriteTargetID
    /// Required nonnull `type` wire value; exact original representation remains in rawFields.
    public let type: RawValue<ChannelOverwriteType>
    /// Allowed permission bits as an exact decimal string, including widths beyond UInt64.
    public let allow: String
    /// Denied permission bits as an exact decimal string; interpretation requires guild/role/channel context.
    public let deny: String
    /// Complete original object, including future keys and exact numeric spellings; diagnostics redact payload values.
    public let rawFields: [String: JSONValue]

    /// Parses one complete API v10 response object synchronously under whole-document bounds.
    /// - Parameters:
    ///   - data: Complete UTF-8 JSON object. Required nullable keys must be present; optional keys retain omission.
    ///   - limits: Byte, nesting and node bounds applied to all fields, including unknown values; defaults to 1 MiB/64/100,000.
    /// - Throws: JSON syntax/bounds errors or sanitized invalid-response errors for missing, forbidden-null,
    ///   mistyped or out-of-range modeled fields. Unknown fields retain their exact JSON values.
    /// No I/O, suspension, credential access, URL fetch or resource ownership changes occur.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects an immutable subtree whose complete outer document already passed its parser bounds.
    /// - Parameters:
    ///   - value: Original object subtree, with unknown keys and exact number spellings preserved.
    ///   - limits: Bounds established at the containing root; scalar decoding uses the same limits.
    /// - Throws: Sanitized invalid-response errors for incompatible known fields; no payload text is disclosed.
    /// Construction is synchronous and shares the original immutable JSON tree without reparsing nested objects.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        id = try object.required("id", ChannelOverwriteTargetID.self)
        type = try object.required("type", RawValue<ChannelOverwriteType>.self)
        allow = try object.required("allow", String.self)
        deny = try object.required("deny", String.self)
        try validateChannelPermissionBits(allow)
        try validateChannelPermissionBits(deny)
        rawFields = object.resource.fields
    }
}

/// Thread lifecycle metadata. Response auto-archive durations remain integers so future values are not silently normalized.
/// API v10; verified against https://docs.discord.com/developers/resources/channel on 2026-10-16.
public struct ThreadMetadata: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Required nonnull `archived` wire value; exact original representation remains in rawFields.
    public let archived: Bool
    /// Inactivity duration in minutes. Documented values are 60, 1440, 4320 and 10080; future response values survive.
    public let autoArchiveDuration: Int
    /// Last archive-state change timestamp; archive endpoints sort by this value descending.
    public let archiveTimestamp: DiscordTimestamp
    /// Whether only MANAGE_THREADS holders can unarchive the thread.
    public let locked: Bool
    /// Private-thread setting allowing non-moderators to invite others; absence remains distinct from false.
    public let invitable: Field<Bool>
    /// Optional nullable creation time, populated for threads created after 2022-01-09.
    public let createTimestamp: Field<DiscordTimestamp>
    /// Complete original object, including future keys and exact numeric spellings; diagnostics redact payload values.
    public let rawFields: [String: JSONValue]

    /// Parses one complete API v10 response object synchronously under whole-document bounds.
    /// - Parameters:
    ///   - data: Complete UTF-8 JSON object. Required nullable keys must be present; optional keys retain omission.
    ///   - limits: Byte, nesting and node bounds applied to all fields, including unknown values; defaults to 1 MiB/64/100,000.
    /// - Throws: JSON syntax/bounds errors or sanitized invalid-response errors for missing, forbidden-null,
    ///   mistyped or out-of-range modeled fields. Unknown fields retain their exact JSON values.
    /// No I/O, suspension, credential access, URL fetch or resource ownership changes occur.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects an immutable subtree whose complete outer document already passed its parser bounds.
    /// - Parameters:
    ///   - value: Original object subtree, with unknown keys and exact number spellings preserved.
    ///   - limits: Bounds established at the containing root; scalar decoding uses the same limits.
    /// - Throws: Sanitized invalid-response errors for incompatible known fields; no payload text is disclosed.
    /// Construction is synchronous and shares the original immutable JSON tree without reparsing nested objects.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        archived = try object.required("archived", Bool.self)
        autoArchiveDuration = try object.required("auto_archive_duration", Int.self)
        archiveTimestamp = try object.required("archive_timestamp", DiscordTimestamp.self)
        locked = try object.required("locked", Bool.self)
        invitable = try object.field("invitable", Bool.self)
        createTimestamp = try object.field("create_timestamp", DiscordTimestamp.self, nullable: true)
        rawFields = object.resource.fields
    }
}

/// An explicitly partial related User projection for DM recipients; this is not complete User catalog parity. All other user fields remain exact in rawFields.
/// API v10; verified against https://docs.discord.com/developers/resources/channel on 2026-10-16.
public struct ChannelRecipient: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Required nonnull `id` wire value; exact original representation remains in rawFields.
    public let id: UserID
    /// Optional nonnull `username` wire field; omission remains distinct from explicit null.
    public let username: Field<String>
    /// Optional nonnull `discriminator` wire field; omission remains distinct from explicit null.
    public let discriminator: Field<String>
    /// Optional nullable `global_name` wire field; omission remains distinct from explicit null.
    public let globalName: Field<String>
    /// Optional nullable `avatar` wire field; omission remains distinct from explicit null.
    public let avatar: Field<String>
    /// Optional nonnull `bot` wire field; omission remains distinct from explicit null.
    public let bot: Field<Bool>
    /// Complete original object, including future keys and exact numeric spellings; diagnostics redact payload values.
    public let rawFields: [String: JSONValue]

    /// Parses one complete API v10 response object synchronously under whole-document bounds.
    /// - Parameters:
    ///   - data: Complete UTF-8 JSON object. Required nullable keys must be present; optional keys retain omission.
    ///   - limits: Byte, nesting and node bounds applied to all fields, including unknown values; defaults to 1 MiB/64/100,000.
    /// - Throws: JSON syntax/bounds errors or sanitized invalid-response errors for missing, forbidden-null,
    ///   mistyped or out-of-range modeled fields. Unknown fields retain their exact JSON values.
    /// No I/O, suspension, credential access, URL fetch or resource ownership changes occur.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects an immutable subtree whose complete outer document already passed its parser bounds.
    /// - Parameters:
    ///   - value: Original object subtree, with unknown keys and exact number spellings preserved.
    ///   - limits: Bounds established at the containing root; scalar decoding uses the same limits.
    /// - Throws: Sanitized invalid-response errors for incompatible known fields; no payload text is disclosed.
    /// Construction is synchronous and shares the original immutable JSON tree without reparsing nested objects.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        id = try object.required("id", UserID.self)
        username = try object.field("username", String.self)
        discriminator = try object.field("discriminator", String.self)
        globalName = try object.field("global_name", String.self, nullable: true)
        avatar = try object.field("avatar", String.self, nullable: true)
        bot = try object.field("bot", Bool.self)
        rawFields = object.resource.fields
    }
}

/// An explicitly partial related Guild Member projection returned by with_member. All unmodeled guild-member fields remain exact; this does not claim Guild catalog parity.
/// API v10; verified against https://docs.discord.com/developers/resources/channel on 2026-10-16.
public struct ThreadGuildMember: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Optional nonnull `user` projection in server order where applicable; unknown nested fields survive.
    public let user: Field<ChannelRecipient>
    /// Optional nullable `nick` wire field; omission remains distinct from explicit null.
    public let nick: Field<String>
    /// Optional nullable `avatar` wire field; omission remains distinct from explicit null.
    public let avatar: Field<String>
    /// Optional nonnull `roles` wire field; omission remains distinct from explicit null.
    public let roles: Field<[RoleID]>
    /// Optional nonnull `joined_at` wire field; omission remains distinct from explicit null.
    public let joinedAt: Field<DiscordTimestamp>
    /// Optional nullable `premium_since` wire field; omission remains distinct from explicit null.
    public let premiumSince: Field<DiscordTimestamp>
    /// Optional nonnull `deaf` wire field; omission remains distinct from explicit null.
    public let deaf: Field<Bool>
    /// Optional nonnull `mute` wire field; omission remains distinct from explicit null.
    public let mute: Field<Bool>
    /// Optional nonnull `flags` wire field; omission remains distinct from explicit null.
    public let flags: Field<UInt64>
    /// Optional nonnull `pending` wire field; omission remains distinct from explicit null.
    public let pending: Field<Bool>
    /// Optional nonnull `permissions` wire field; omission remains distinct from explicit null.
    public let permissions: Field<String>
    /// Optional nullable `communication_disabled_until` wire field; omission remains distinct from explicit null.
    public let communicationDisabledUntil: Field<DiscordTimestamp>
    /// Complete original object, including future keys and exact numeric spellings; diagnostics redact payload values.
    public let rawFields: [String: JSONValue]

    /// Parses one complete API v10 response object synchronously under whole-document bounds.
    /// - Parameters:
    ///   - data: Complete UTF-8 JSON object. Required nullable keys must be present; optional keys retain omission.
    ///   - limits: Byte, nesting and node bounds applied to all fields, including unknown values; defaults to 1 MiB/64/100,000.
    /// - Throws: JSON syntax/bounds errors or sanitized invalid-response errors for missing, forbidden-null,
    ///   mistyped or out-of-range modeled fields. Unknown fields retain their exact JSON values.
    /// No I/O, suspension, credential access, URL fetch or resource ownership changes occur.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects an immutable subtree whose complete outer document already passed its parser bounds.
    /// - Parameters:
    ///   - value: Original object subtree, with unknown keys and exact number spellings preserved.
    ///   - limits: Bounds established at the containing root; scalar decoding uses the same limits.
    /// - Throws: Sanitized invalid-response errors for incompatible known fields; no payload text is disclosed.
    /// Construction is synchronous and shares the original immutable JSON tree without reparsing nested objects.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        user = try object.messageField("user", ChannelRecipient.self)
        nick = try object.field("nick", String.self, nullable: true)
        avatar = try object.field("avatar", String.self, nullable: true)
        roles = try object.field("roles", [RoleID].self)
        joinedAt = try object.field("joined_at", DiscordTimestamp.self)
        premiumSince = try object.field("premium_since", DiscordTimestamp.self, nullable: true)
        deaf = try object.field("deaf", Bool.self)
        mute = try object.field("mute", Bool.self)
        flags = try object.field("flags", UInt64.self)
        pending = try object.field("pending", Bool.self)
        permissions = try object.field("permissions", String.self)
        communicationDisabledUntil = try object.field("communication_disabled_until", DiscordTimestamp.self, nullable: true)
        if case .value(let bits) = permissions { try validateChannelPermissionBits(bits) }
        rawFields = object.resource.fields
    }
}

/// Thread membership. Optional IDs may be omitted in a GUILD_CREATE thread member; flags are opaque notification settings, not permission bits.
/// API v10; verified against https://docs.discord.com/developers/resources/channel on 2026-10-16.
public struct ThreadMember: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Thread ID; omitted for the current member embedded in GUILD_CREATE.
    public let id: Field<ChannelID>
    /// User ID; omitted for the current member embedded in GUILD_CREATE.
    public let userID: Field<UserID>
    /// Required nonnull `join_timestamp` wire value; exact original representation remains in rawFields.
    public let joinTimestamp: DiscordTimestamp
    /// Required nonnull `flags` wire value; exact original representation remains in rawFields.
    public let flags: UInt64
    /// Optional explicitly partial guild-member details, returned only when the endpoint is called with with_member=true.
    public let member: Field<ThreadGuildMember>
    /// Complete original object, including future keys and exact numeric spellings; diagnostics redact payload values.
    public let rawFields: [String: JSONValue]

    /// Parses one complete API v10 response object synchronously under whole-document bounds.
    /// - Parameters:
    ///   - data: Complete UTF-8 JSON object. Required nullable keys must be present; optional keys retain omission.
    ///   - limits: Byte, nesting and node bounds applied to all fields, including unknown values; defaults to 1 MiB/64/100,000.
    /// - Throws: JSON syntax/bounds errors or sanitized invalid-response errors for missing, forbidden-null,
    ///   mistyped or out-of-range modeled fields. Unknown fields retain their exact JSON values.
    /// No I/O, suspension, credential access, URL fetch or resource ownership changes occur.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects an immutable subtree whose complete outer document already passed its parser bounds.
    /// - Parameters:
    ///   - value: Original object subtree, with unknown keys and exact number spellings preserved.
    ///   - limits: Bounds established at the containing root; scalar decoding uses the same limits.
    /// - Throws: Sanitized invalid-response errors for incompatible known fields; no payload text is disclosed.
    /// Construction is synchronous and shares the original immutable JSON tree without reparsing nested objects.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        id = try object.field("id", ChannelID.self)
        userID = try object.field("user_id", UserID.self)
        joinTimestamp = try object.required("join_timestamp", DiscordTimestamp.self)
        flags = try object.required("flags", UInt64.self)
        member = try object.messageField("member", ThreadGuildMember.self)
        rawFields = object.resource.fields
    }
}

/// Forum/media default emoji. Exactly one of emoji_id and emoji_name must be nonnull in a documented response.
/// API v10; verified against https://docs.discord.com/developers/resources/channel on 2026-10-16.
public struct DefaultReaction: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Required nullable `emoji_id` wire value; exact original representation remains in rawFields.
    public let emojiID: Nullable<EmojiID>
    /// Required nullable `emoji_name` wire value; exact original representation remains in rawFields.
    public let emojiName: Nullable<String>
    /// Complete original object, including future keys and exact numeric spellings; diagnostics redact payload values.
    public let rawFields: [String: JSONValue]

    /// Parses one complete API v10 response object synchronously under whole-document bounds.
    /// - Parameters:
    ///   - data: Complete UTF-8 JSON object. Required nullable keys must be present; optional keys retain omission.
    ///   - limits: Byte, nesting and node bounds applied to all fields, including unknown values; defaults to 1 MiB/64/100,000.
    /// - Throws: JSON syntax/bounds errors or sanitized invalid-response errors for missing, forbidden-null,
    ///   mistyped or out-of-range modeled fields. Unknown fields retain their exact JSON values.
    /// No I/O, suspension, credential access, URL fetch or resource ownership changes occur.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects an immutable subtree whose complete outer document already passed its parser bounds.
    /// - Parameters:
    ///   - value: Original object subtree, with unknown keys and exact number spellings preserved.
    ///   - limits: Bounds established at the containing root; scalar decoding uses the same limits.
    /// - Throws: Sanitized invalid-response errors for incompatible known fields; no payload text is disclosed.
    /// Construction is synchronous and shares the original immutable JSON tree without reparsing nested objects.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        emojiID = try object.required("emoji_id", Nullable<EmojiID>.self)
        emojiName = try object.required("emoji_name", Nullable<String>.self)
        switch (emojiID, emojiName) {
        case (.value, .null), (.null, .value): break
        default: throw DiscordError.transport(.invalidResponse)
        }
        rawFields = object.resource.fields
    }
}

/// A complete forum/media tag response. This differs from update request tags, which may omit the ID and other response keys.
/// API v10; verified against https://docs.discord.com/developers/resources/channel on 2026-10-16.
public struct ForumTag: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Required nonnull `id` wire value; exact original representation remains in rawFields.
    public let id: ForumTagID
    /// Required nonnull `name` wire value; exact original representation remains in rawFields.
    public let name: String
    /// Required nonnull `moderated` wire value; exact original representation remains in rawFields.
    public let moderated: Bool
    /// Required nullable `emoji_id` wire value; exact original representation remains in rawFields.
    public let emojiID: Nullable<EmojiID>
    /// Required nullable `emoji_name` wire value; exact original representation remains in rawFields.
    public let emojiName: Nullable<String>
    /// Complete original object, including future keys and exact numeric spellings; diagnostics redact payload values.
    public let rawFields: [String: JSONValue]

    /// Parses one complete API v10 response object synchronously under whole-document bounds.
    /// - Parameters:
    ///   - data: Complete UTF-8 JSON object. Required nullable keys must be present; optional keys retain omission.
    ///   - limits: Byte, nesting and node bounds applied to all fields, including unknown values; defaults to 1 MiB/64/100,000.
    /// - Throws: JSON syntax/bounds errors or sanitized invalid-response errors for missing, forbidden-null,
    ///   mistyped or out-of-range modeled fields. Unknown fields retain their exact JSON values.
    /// No I/O, suspension, credential access, URL fetch or resource ownership changes occur.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects an immutable subtree whose complete outer document already passed its parser bounds.
    /// - Parameters:
    ///   - value: Original object subtree, with unknown keys and exact number spellings preserved.
    ///   - limits: Bounds established at the containing root; scalar decoding uses the same limits.
    /// - Throws: Sanitized invalid-response errors for incompatible known fields; no payload text is disclosed.
    /// Construction is synchronous and shares the original immutable JSON tree without reparsing nested objects.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        id = try object.required("id", ForumTagID.self)
        name = try object.required("name", String.self)
        moderated = try object.required("moderated", Bool.self)
        emojiID = try object.required("emoji_id", Nullable<EmojiID>.self)
        emojiName = try object.required("emoji_name", Nullable<String>.self)
        if case .value = emojiID, case .value = emojiName { throw DiscordError.transport(.invalidResponse) }
        rawFields = object.resource.fields
    }
}

/// The source announcement channel and newly created target webhook returned by Follow Announcement Channel.
/// API v10; verified against https://docs.discord.com/developers/resources/channel on 2026-10-16.
public struct FollowedChannel: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Required nonnull `channel_id` wire value; exact original representation remains in rawFields.
    public let channelID: ChannelID
    /// Required nonnull `webhook_id` wire value; exact original representation remains in rawFields.
    public let webhookID: WebhookID
    /// Complete original object, including future keys and exact numeric spellings; diagnostics redact payload values.
    public let rawFields: [String: JSONValue]

    /// Parses one complete API v10 response object synchronously under whole-document bounds.
    /// - Parameters:
    ///   - data: Complete UTF-8 JSON object. Required nullable keys must be present; optional keys retain omission.
    ///   - limits: Byte, nesting and node bounds applied to all fields, including unknown values; defaults to 1 MiB/64/100,000.
    /// - Throws: JSON syntax/bounds errors or sanitized invalid-response errors for missing, forbidden-null,
    ///   mistyped or out-of-range modeled fields. Unknown fields retain their exact JSON values.
    /// No I/O, suspension, credential access, URL fetch or resource ownership changes occur.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects an immutable subtree whose complete outer document already passed its parser bounds.
    /// - Parameters:
    ///   - value: Original object subtree, with unknown keys and exact number spellings preserved.
    ///   - limits: Bounds established at the containing root; scalar decoding uses the same limits.
    /// - Throws: Sanitized invalid-response errors for incompatible known fields; no payload text is disclosed.
    /// Construction is synchronous and shares the original immutable JSON tree without reparsing nested objects.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        channelID = try object.required("channel_id", ChannelID.self)
        webhookID = try object.required("webhook_id", WebhookID.self)
        rawFields = object.resource.fields
    }
}
