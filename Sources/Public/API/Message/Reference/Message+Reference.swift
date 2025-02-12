//
//  Message+Reference.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/12/25.
//

extension Message {
    public struct Reference: DiscordModel {
        public let type: ReferenceType?
        public let messageID: Snowflake?
        public let channelID: Snowflake?
        public let guildID: Snowflake?
        public let failIfNotExists: Bool?
    }
}

extension Message.Reference {
    enum CodingKeys: String, CodingKey {
        case type
        case messageID = "message_id"
        case channelID = "channel_id"
        case guildID = "guild_id"
        case failIfNotExists = "fail_if_not_exists"
    }
}
