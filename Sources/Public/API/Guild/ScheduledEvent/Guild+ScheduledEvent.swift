//
//  Guild+ScheduledEvent.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/5/25.
//

extension Guild {
    public struct ScheduledEvent: DiscordModel {
        public let id: Snowflake
        public let guildID: Snowflake
        public let channelID: Snowflake?
        public let creatorID: Snowflake?
        public let name: String
        public let eventDescription: String?
        // TODO: Finish this
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
    }
}
