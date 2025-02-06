//
//  Guild+ScheduledEvent.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/5/25.
//

import Foundation

extension Guild {
    public struct ScheduledEvent: DiscordModel {
        public let id: Snowflake
        public let guildID: Snowflake
        public let channelID: Snowflake?
        public let creatorID: Snowflake?
        public let name: String
        public let eventDescription: String?
        public let startTime: Date
        public let endTime: Date?
        public let privacyLevel: PrivacyLevel
        public let status: Status
        public let entityType: EntityType
        public let entityID: Snowflake?
        public let entityMetadata: EntityMetadata?
        public let creator: User?
        public let userCount: Int?
        public let image: String?
        public let recurrenceRule: RecurrenceRule?
    }
}

extension Guild.ScheduledEvent {
    enum CodingKeys: String, CodingKey {
        case id
        case guildID = "guild_id"
        case channelID = "channel_id"
        case creatorID = "creator_id"
        case name
        case eventDescription = "description"
        case startTime = "scheduled_start_time"
        case endTime = "scheduled_end_time"
        case privacyLevel = "privacy_level"
        case status
        case entityType = "entity_type"
        case entityID = "entity_id"
        case entityMetadata = "entity_metadata"
        case creator
        case userCount = "user_count"
        case image
        case recurrenceRule = "recurrence_rule"
    }
}
