//
//  Channel+ForumTag.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/7/25.
//

extension Channel {
    public struct ForumTag: DiscordModel {
        public let id: Snowflake
        public let name: String
        public let isModerated: Bool
        public let emojiID: Snowflake?
        public let emojiName: String?
    }
}

extension Channel.ForumTag {
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case isModerated = "moderated"
        case emojiID = "emoji_id"
        case emojiName = "emoji_name"
    }
}

extension Channel.ForumTag: CustomStringConvertible {
    public var description: String {
        var result = "[ID: \(id) || Name: \(name) || Is Moderated: \(isModerated)"
        if let emojiID = emojiID {
            result += " || Emoji ID: \(emojiID)"
        }
        if let emojiName = emojiName {
            result += " || Emoji Name: \(emojiName)"
        }
        return result + "]"
    }
}
