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

extension Channel.DefaultReaction: CustomStringConvertible {
    public var description: String {
        var result = [String]()
        if let emojiID = emojiID { result.append("\(emojiID)") }
        if let emojiName = emojiName { result.append(emojiName) }
        return "[\(result.joined(separator: " || "))]"
    }
}
