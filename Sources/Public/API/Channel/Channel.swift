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
    }
}
