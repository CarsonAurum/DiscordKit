//
//  Channel+DefaultReaction.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/7/25.
//

extension Channel {
    public struct DefaultReaction: DiscordModel {
        public let emojiID: Snowflake?
        public let emojiName: String?
    }
}

extension Channel.DefaultReaction {
    enum CodingKeys: String, CodingKey {
        case emojiID = "emoji_id"
        case emojiName = "emoji_name"
    }
}
