//
//  Channel.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/5/25.
//

import Foundation

public struct Channel: DiscordModel {
    public let id: Snowflake
    public let type: ChannelType
    public let guildID: Snowflake?
    public let position: Int?
    public let permissionOverwrites: [Permissions.Overwrite]?
    public let name: String?
    public let topic: String?
    public let isNSFW: Bool?
    public let lastMessageID: Snowflake?
    public let bitrate: Int?
    public let userLimit: Int?
    public let rateLimitPerUser: Int?
    public let recipients: [User]?
    public let icon: Snowflake?
    public let ownerID: Snowflake?
    public let applicationID: Snowflake?
    public let isManaged: Bool?
    public let parentID: Snowflake?
    public let lastPinTimestamp: Date?
    public let rtcRegion: String?
    public let videoQualityMode: VideoQualityMode?
    public let messageCount: Int?
    public let memberCount: Int?
    public let threadMetadata: ThreadMetadata?
    public let member: ThreadMember?
    public let defaultAutoArchiveDuration: Int?
    public let permissions: Permissions?
    public let flags: Flags?
    public let totalMessageSent: Int?
    public let availableTags: [ForumTag]?
    public let appliedTags: [Snowflake]?
    public let defaultReactionEmoji: DefaultReaction?
    public let defaultThreadRateLimitPerUser: Int?
    public let defaultSortOrder: SortOrderType?
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

