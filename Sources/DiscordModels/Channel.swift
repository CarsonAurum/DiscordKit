// File: Sources/DiscordModels/Channel.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import Foundation

/// A complete documented Channel projection plus the forum-start message envelope. It preserves every wire presence state and future field. Parsing establishes neither resource visibility nor current permissions; recipient/member resource families remain explicitly partial.
/// API v10; verified against https://docs.discord.com/developers/resources/channel on 2026-10-16.
public struct Channel: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Required nonnull `id` wire value; exact original representation remains in rawFields.
    public let id: ChannelID
    /// Required nonnull `type` wire value; exact original representation remains in rawFields.
    public let type: RawValue<ChannelType>
    /// Owning guild ID; may be absent on channel objects received within Gateway guild dispatches.
    public let guildID: Field<GuildID>
    /// Sorting position; equal positions use the channel ID as a tie-breaker.
    public let position: Field<Int>
    /// Optional nonnull `permission_overwrites` projection in server order where applicable; unknown nested fields survive.
    public let permissionOverwrites: Field<[ChannelOverwrite]>
    /// Optional nullable channel name. Obfuscated names do not establish visibility; check isObfuscated.
    public let name: Field<String>
    /// Optional nullable `topic` wire field; omission remains distinct from explicit null.
    public let topic: Field<String>
    /// Whether the channel is age-restricted; omission is not treated as false.
    public let nsfw: Field<Bool>
    /// Last message ID, or last thread ID for forum/media channels. It may reference a deleted or otherwise invalid resource.
    public let lastMessageID: Field<MessageID>
    /// Voice bitrate in bits per second; no host or entitlement support is inferred.
    public let bitrate: Field<Int>
    /// Optional nonnull `user_limit` wire field; omission remains distinct from explicit null.
    public let userLimit: Field<Int>
    /// Slowmode interval in seconds; also applies independently to thread creation. Bots and BYPASS_SLOWMODE users are unaffected.
    public let rateLimitPerUser: Field<Int>
    /// DM recipients as explicitly partial related User projections; unknown user fields remain exact.
    public let recipients: Field<[ChannelRecipient]>
    /// Optional nullable `icon` wire field; omission remains distinct from explicit null.
    public let icon: Field<String>
    /// Optional nonnull `owner_id` wire field; omission remains distinct from explicit null.
    public let ownerID: Field<UserID>
    /// Optional nullable `application_id` wire field; omission remains distinct from explicit null.
    public let applicationID: Field<ApplicationID>
    /// Optional nonnull `managed` wire field; omission remains distinct from explicit null.
    public let managed: Field<Bool>
    /// Optional nullable `parent_id` wire field; omission remains distinct from explicit null.
    public let parentID: Field<ChannelID>
    /// Optional nullable `last_pin_timestamp` wire field; omission remains distinct from explicit null.
    public let lastPinTimestamp: Field<DiscordTimestamp>
    /// Voice region ID; explicit null selects automatic region behavior and remains distinct from omission.
    public let rtcRegion: Field<String>
    /// Camera quality code; absent means Discord uses AUTO, while unknown future integral codes remain raw.
    public let videoQualityMode: Field<RawValue<ChannelVideoQualityMode>>
    /// Thread message count excluding the starter and deleted messages. Counts above 50 are historically inaccurate for pre-2022-07-01 threads.
    public let messageCount: Field<Int>
    /// Approximate thread membership count, which currently stops at 50; not proof of complete membership.
    public let memberCount: Field<Int>
    /// Optional nonnull `thread_metadata` projection in server order where applicable; unknown nested fields survive.
    public let threadMetadata: Field<ThreadMetadata>
    /// Optional nonnull `member` projection in server order where applicable; unknown nested fields survive.
    public let member: Field<ThreadMember>
    /// Default inactivity duration in minutes used by clients, not the API, when creating threads; future response values remain unchanged.
    public let defaultAutoArchiveDuration: Field<Int>
    /// Invoking user permission decimal string from interaction resolved data; implicit permissions are excluded.
    public let permissions: Field<String>
    /// Bot permission decimal string from interaction resolved data; implicit permissions are excluded.
    public let appPermissions: Field<String>
    /// Exact unsigned response bitfield; use ChannelFlags for known membership checks without dropping future bits.
    public let flags: Field<UInt64>
    /// Lifetime thread message count, which is not decremented by deletion.
    public let totalMessageSent: Field<Int>
    /// Optional nonnull `available_tags` projection in server order where applicable; unknown nested fields survive.
    public let availableTags: Field<[ForumTag]>
    /// Optional nonnull `applied_tags` wire field; omission remains distinct from explicit null.
    public let appliedTags: Field<[ForumTagID]>
    /// Optional nullable `default_reaction_emoji` projection in server order where applicable; unknown nested fields survive.
    public let defaultReactionEmoji: Field<DefaultReaction>
    /// Slowmode seconds copied into new threads at creation; later changes do not update existing threads.
    public let defaultThreadRateLimitPerUser: Field<Int>
    /// Optional nullable `default_sort_order` wire field; omission remains distinct from explicit null.
    public let defaultSortOrder: Field<RawValue<ChannelSortOrder>>
    /// Optional nonnull `default_forum_layout` wire field; omission remains distinct from explicit null.
    public let defaultForumLayout: Field<RawValue<ChannelForumLayout>>
    /// Forum/media thread starter message returned by Start Thread in Forum or Media Channel; absent in ordinary Channel objects.
    public let message: Field<Message>
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
        id = try object.required("id", ChannelID.self)
        type = try object.required("type", RawValue<ChannelType>.self)
        guildID = try object.field("guild_id", GuildID.self)
        position = try object.field("position", Int.self)
        permissionOverwrites = try object.messageArray("permission_overwrites", ChannelOverwrite.self)
        name = try object.field("name", String.self, nullable: true)
        topic = try object.field("topic", String.self, nullable: true)
        nsfw = try object.field("nsfw", Bool.self)
        lastMessageID = try object.field("last_message_id", MessageID.self, nullable: true)
        bitrate = try object.field("bitrate", Int.self)
        userLimit = try object.field("user_limit", Int.self)
        rateLimitPerUser = try object.field("rate_limit_per_user", Int.self)
        recipients = try object.messageArray("recipients", ChannelRecipient.self)
        icon = try object.field("icon", String.self, nullable: true)
        ownerID = try object.field("owner_id", UserID.self)
        applicationID = try object.field("application_id", ApplicationID.self, nullable: true)
        managed = try object.field("managed", Bool.self)
        parentID = try object.field("parent_id", ChannelID.self, nullable: true)
        lastPinTimestamp = try object.field("last_pin_timestamp", DiscordTimestamp.self, nullable: true)
        rtcRegion = try object.field("rtc_region", String.self, nullable: true)
        videoQualityMode = try object.field("video_quality_mode", RawValue<ChannelVideoQualityMode>.self)
        messageCount = try object.field("message_count", Int.self)
        memberCount = try object.field("member_count", Int.self)
        threadMetadata = try object.messageField("thread_metadata", ThreadMetadata.self)
        member = try object.messageField("member", ThreadMember.self)
        defaultAutoArchiveDuration = try object.field("default_auto_archive_duration", Int.self)
        permissions = try object.field("permissions", String.self)
        appPermissions = try object.field("app_permissions", String.self)
        flags = try object.field("flags", UInt64.self)
        totalMessageSent = try object.field("total_message_sent", Int.self)
        availableTags = try object.messageArray("available_tags", ForumTag.self)
        appliedTags = try object.field("applied_tags", [ForumTagID].self)
        defaultReactionEmoji = try object.messageField("default_reaction_emoji", DefaultReaction.self, nullable: true)
        defaultThreadRateLimitPerUser = try object.field("default_thread_rate_limit_per_user", Int.self)
        defaultSortOrder = try object.field("default_sort_order", RawValue<ChannelSortOrder>.self, nullable: true)
        defaultForumLayout = try object.field("default_forum_layout", RawValue<ChannelForumLayout>.self)
        message = try object.messageField("message", Message.self)
        if case .value(let bits) = permissions { try validateChannelPermissionBits(bits) }
        if case .value(let bits) = appPermissions { try validateChannelPermissionBits(bits) }
        rawFields = object.resource.fields
    }
}

extension Channel {
    /// Whether the Gateway explicitly marks this snapshot's metadata as obfuscated.
    /// Only the CHANNEL_OBFUSCATED response flag is inspected; placeholder names, missing names and overwrite patterns
    /// are never used as heuristics. False includes omitted flags and is not proof of current VIEW_CHANNEL permission.
    /// For an obfuscated snapshot only id, type, position and parentID are guaranteed unobfuscated by Discord.
    /// This synchronous query has no I/O, cache effects or permission computation. HTTP never sets this flag.
    public var isObfuscated: Bool {
        guard case .value(let bits) = flags else { return false }
        return ChannelFlags(rawValue: bits).contains(.channelObfuscated)
    }
}

/// An archived-thread page in server order. hasMore is authoritative advisory continuation metadata; short pages and missing member records do not establish exhaustion.
/// API v10; verified against https://docs.discord.com/developers/resources/channel on 2026-10-16.
public struct ArchivedThreads: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Required nonnull `threads` projection in server order where applicable; unknown nested fields survive.
    public let threads: [Channel]
    /// Required nonnull `members` projection in server order where applicable; unknown nested fields survive.
    public let members: [ThreadMember]
    /// Required nonnull `has_more` wire value; exact original representation remains in rawFields.
    public let hasMore: Bool
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
        threads = try object.messageModels("threads", Channel.self)
        members = try object.messageModels("members", ThreadMember.self)
        hasMore = try object.required("has_more", Bool.self)
        rawFields = object.resource.fields
    }
}

/// A guild active-thread snapshot ordered by descending thread ID. Members cover joined threads only; the documented REST response has no pagination signal, and a future has_more field remains optional.
/// API v10; verified against https://docs.discord.com/developers/resources/guild#list-active-guild-threads on 2026-10-16.
public struct ActiveThreads: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Required nonnull `threads` projection in server order where applicable; unknown nested fields survive.
    public let threads: [Channel]
    /// Required nonnull `members` projection in server order where applicable; unknown nested fields survive.
    public let members: [ThreadMember]
    /// Optional nonnull `has_more` wire field; omission remains distinct from explicit null.
    public let hasMore: Field<Bool>
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
        threads = try object.messageModels("threads", Channel.self)
        members = try object.messageModels("members", ThreadMember.self)
        hasMore = try object.field("has_more", Bool.self)
        rawFields = object.resource.fields
    }
}
