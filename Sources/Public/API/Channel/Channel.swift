//
//  Channel.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/5/25.
//

import Foundation

/// A model representing a Discord channel, covering text, voice, DM, forum, and other channel types.
/// Conforms to `DiscordModel` for decoding from Discord API responses.
public struct Channel: DiscordModel {
    /// The unique identifier of the channel.
    public let id: Snowflake
    /// The type of the channel (text, voice, DM, etc.).
    public let type: ChannelType
    /// The ID of the guild this channel belongs to, if any.
    public let guildID: Snowflake?
    /// The position of the channel in the guild's channel list.
    public let position: Int?
    /// A list of permission overwrite objects for roles and members.
    public let permissionOverwrites: [Permissions.Overwrite]?
    /// The name of the channel.
    public let name: String?
    /// The channel topic (for forum and text channels).
    public let topic: String?
    /// Whether the channel is marked as NSFW.
    public let isNSFW: Bool?
    /// The ID of the last message sent in this channel.
    public let lastMessageID: Snowflake?
    /// The bitrate (in bits) of the channel (for voice channels).
    public let bitrate: Int?
    /// The maximum number of users allowed in a voice channel.
    public let userLimit: Int?
    /// The time (in seconds) a user must wait between sending messages (slowmode).
    public let rateLimitPerUser: Int?
    /// The recipients of a DM or group DM channel.
    public let recipients: [User]?
    /// The icon hash of the channel (for group DM channels).
    public let icon: Snowflake?
    /// The ID of the user who owns the channel (for group DM channels).
    public let ownerID: Snowflake?
    /// The application ID of the channel creator (for application-owned channels).
    public let applicationID: Snowflake?
    /// Whether the channel is managed by an integration.
    public let isManaged: Bool?
    /// The ID of the parent category for this channel.
    public let parentID: Snowflake?
    /// The timestamp of the last pinned message in the channel.
    public let lastPinTimestamp: Date?
    /// The voice region ID for voice channels.
    public let rtcRegion: String?
    /// The camera video quality mode (for voice channels with video support).
    public let videoQualityMode: VideoQualityMode?
    /// The total number of messages in the channel (for threads).
    public let messageCount: Int?
    /// The number of members in the channel (for threads).
    public let memberCount: Int?
    /// Additional metadata for thread channels.
    public let threadMetadata: ThreadMetadata?
    /// Thread member data for the current user.
    public let member: ThreadMember?
    /// The default auto-archive duration (in minutes) for new threads.
    public let defaultAutoArchiveDuration: Int?
    /// Computed permissions for the current user in this channel.
    public let permissions: Permissions?
    /// Channel-specific flags.
    public let flags: Flags?
    /// Approximate total messages sent in a thread, rounded down.
    public let totalMessageSent: Int?
    /// The forum tags that can be used in a forum channel.
    public let availableTags: [ForumTag]?
    /// The tag IDs that have been applied to the channel in a forum.
    public let appliedTags: [Snowflake]?
    /// The default reaction emoji for the channel.
    public let defaultReactionEmoji: DefaultReaction?
    /// The default per-user rate limit (slowmode) for threads.
    public let defaultThreadRateLimitPerUser: Int?
    /// The default sorting order for posts in forum channels.
    public let defaultSortOrder: SortOrderType?
    /// The default layout view for forum channels.
    public let defaultForumLayout: ForumLayoutType?
    
}

extension Channel {
    enum CodingKeys: String, CodingKey {
        case id
        case type
        case guildID = "guild_id"
        case position
        case permissionOverwrites = "permission_overwrites"
        case name
        case topic
        case isNSFW = "nsfw"
        case lastMessageID = "last_message_id"
        case bitrate
        case userLimit = "user_limit"
        case rateLimitPerUser = "rate_limit_per_user"
        case recipients
        case icon
        case ownerID = "owner_id"
        case applicationID = "application_id"
        case isManaged = "managed"
        case parentID = "parent_id"
        case lastPinTimestamp = "last_pin_timestamp"
        case rtcRegion = "rtc_region"
        case videoQualityMode = "video_quality_mode"
        case messageCount = "message_count"
        case memberCount = "member_count"
        case threadMetadata = "thread_metadata"
        case member
        case defaultAutoArchiveDuration = "default_auto_archive_duration"
        case permissions
        case flags
        case totalMessageSent = "total_message_sent"
        case availableTags = "available_tags"
        case appliedTags = "applied_tags"
        case defaultReactionEmoji = "default_reaction_emoji"
        case defaultThreadRateLimitPerUser = "default_thread_rate_limit_per_user"
        case defaultSortOrder = "default_sort_order"
        case defaultForumLayout = "default_forum_layout"
    }
    
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(Snowflake.self, forKey: .id)
        self.type = try container.decode(ChannelType.self, forKey: .type)
        self.guildID = try container.decodeIfPresent(Snowflake.self, forKey: .guildID)
        self.position = try container.decodeIfPresent(Int.self, forKey: .position)
        self.permissionOverwrites = try container.decodeIfPresent(
            [Permissions.Overwrite].self,
            forKey: .permissionOverwrites
        )
        self.name = try container.decodeIfPresent(String.self, forKey: .name)
        self.topic = try container.decodeIfPresent(String.self, forKey: .topic)
        self.isNSFW = try container.decodeIfPresent(Bool.self, forKey: .isNSFW)
        self.lastMessageID = try container.decodeIfPresent(Snowflake.self, forKey: .lastMessageID)
        self.bitrate = try container.decodeIfPresent(Int.self, forKey: .bitrate)
        self.userLimit = try container.decodeIfPresent(Int.self, forKey: .userLimit)
        self.rateLimitPerUser = try container.decodeIfPresent(Int.self, forKey: .rateLimitPerUser)
        self.recipients = try container.decodeIfPresent([User].self, forKey: .recipients)
        self.icon = try container.decodeIfPresent(Snowflake.self, forKey: .icon)
        self.ownerID = try container.decodeIfPresent(Snowflake.self, forKey: .ownerID)
        self.applicationID = try container.decodeIfPresent(Snowflake.self, forKey: .applicationID)
        self.isManaged = try container.decodeIfPresent(Bool.self, forKey: .isManaged)
        self.parentID = try container.decodeIfPresent(Snowflake.self, forKey: .parentID)
        
        if let lastPinTimestampString = try container.decodeIfPresent(String.self, forKey: .lastPinTimestamp) {
            let fmt = ISO8601DateFormatter()
            fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            self.lastPinTimestamp = fmt.date(from: lastPinTimestampString)
        } else {
            self.lastPinTimestamp = nil
        }
        self.rtcRegion = try container.decodeIfPresent(String.self, forKey: .rtcRegion)
        self.videoQualityMode = try container.decodeIfPresent(VideoQualityMode.self, forKey: .videoQualityMode)
        self.messageCount = try container.decodeIfPresent(Int.self, forKey: .messageCount)
        self.memberCount = try container.decodeIfPresent(Int.self, forKey: .memberCount)
        self.threadMetadata = try container.decodeIfPresent(ThreadMetadata.self, forKey: .threadMetadata)
        self.member = try container.decodeIfPresent(ThreadMember.self, forKey: .member)
        self.defaultAutoArchiveDuration = try container.decodeIfPresent(Int.self, forKey: .defaultAutoArchiveDuration)
        self.permissions = try container.decodeIfPresent(Permissions.self, forKey: .permissions)
        self.flags = try container.decodeIfPresent(Flags.self, forKey: .flags)
        self.totalMessageSent = try container.decodeIfPresent(Int.self, forKey: .totalMessageSent)
        self.availableTags = try container.decodeIfPresent([ForumTag].self, forKey: .availableTags)
        self.appliedTags = try container.decodeIfPresent([Snowflake].self, forKey: .appliedTags)
        self.defaultReactionEmoji = try container.decodeIfPresent(DefaultReaction.self, forKey: .defaultReactionEmoji)
        self.defaultThreadRateLimitPerUser = try container.decodeIfPresent(Int.self, forKey: .defaultThreadRateLimitPerUser)
        self.defaultSortOrder = try container.decodeIfPresent(SortOrderType.self, forKey: .defaultSortOrder)
        self.defaultForumLayout = try container.decodeIfPresent(ForumLayoutType.self, forKey: .defaultForumLayout)
    }
}

