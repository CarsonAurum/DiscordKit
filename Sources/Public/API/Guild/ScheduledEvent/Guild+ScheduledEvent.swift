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
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Snowflake.self, forKey: .id)
        guildID = try container.decode(Snowflake.self, forKey: .guildID)
        channelID = try container.decodeIfPresent(Snowflake.self, forKey: .channelID)
        creatorID = try container.decodeIfPresent(Snowflake.self, forKey: .creatorID)
        name = try container.decode(String.self, forKey: .name)
        eventDescription = try container.decodeIfPresent(String.self, forKey: .eventDescription)
        
        let startTimeString = try container.decode(String.self, forKey: .startTime)
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.startTime = fmt.date(from: startTimeString)!
        
        if let endTimeString = try container.decodeIfPresent(String.self, forKey: .endTime) {
            let fmt = ISO8601DateFormatter()
            fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            self.endTime = fmt.date(from: endTimeString)
        } else {
            self.endTime = nil
        }
        
        privacyLevel = try container.decode(PrivacyLevel.self, forKey: .privacyLevel)
        status = try container.decode(Status.self, forKey: .status)
        entityType = try container.decode(EntityType.self, forKey: .entityType)
        entityID = try container.decode(Snowflake.self, forKey: .entityID)
        entityMetadata = try container.decodeIfPresent(EntityMetadata.self, forKey: .entityMetadata)
        creator = try container.decodeIfPresent(User.self, forKey: .creator)
        userCount = try container.decodeIfPresent(Int.self, forKey: .userCount)
        image = try container.decodeIfPresent(String.self, forKey: .image)
        recurrenceRule = try container.decodeIfPresent(RecurrenceRule.self, forKey: .recurrenceRule)
    }
    
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(guildID, forKey: .guildID)
        try container.encodeIfPresent(channelID, forKey: .channelID)
        try container.encodeIfPresent(creatorID, forKey: .creatorID)
        try container.encode(name, forKey: .name)
        try container.encode(eventDescription, forKey: .eventDescription)
        
        let startDateString = ISO8601DateFormatter().string(from: startTime)
        try container.encode(startDateString, forKey: .startTime)
        
        if let endTime = endTime {
            let dateString = ISO8601DateFormatter().string(from: endTime)
            try container.encode(dateString, forKey: .endTime)
        } else {
            try container.encodeNil(forKey: .endTime)
        }
        
        try container.encode(privacyLevel, forKey: .privacyLevel)
        try container.encode(status, forKey: .status)
        try container.encode(entityType, forKey: .entityType)
        try container.encode(entityID, forKey: .entityID)
        try container.encodeIfPresent(entityMetadata, forKey: .entityMetadata)
        try container.encodeIfPresent(creator, forKey: .creator)
        try container.encodeIfPresent(userCount, forKey: .userCount)
        try container.encodeIfPresent(image, forKey: .image)
        try container.encodeIfPresent(recurrenceRule, forKey: .recurrenceRule)
    }
}
