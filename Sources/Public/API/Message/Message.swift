//
//  Message.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/7/25.
//

import Foundation

public struct Message: DiscordModel {
    public let id: Snowflake
    public let channelID: Snowflake
    public let author: User
    public let content: String
    public let timestamp: Date
    public let editedTimestamp: Date?
    public let isTTS: Bool
    public let isMentionEveryone: Bool
    public let mentions: [User]
    public let mentionRoles: [Role]
    public let mentionChannels: [Channel]?
    
}

extension Message {
    enum CodingKeys: String, CodingKey {
        case id
        case channelID = "channel_id"
        case author
        case content
        case timestamp
        case editedTimestamp = "edited_timestamp"
        case isTTS = "tts"
        case isMentionEveryone = "mention_everyone"
        case mentions
        case mentionRoles = "mention_roles"
        case mentionChannels = "mention_channels"
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Snowflake.self, forKey: .id)
        channelID = try container.decode(Snowflake.self, forKey: .channelID)
        author = try container.decode(User.self, forKey: .author)
        content = try container.decode(String.self, forKey: .content)
        
        let timestampString = try container.decode(String.self, forKey: .timestamp)
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.timestamp = fmt.date(from: timestampString)!
        
        if let editedTimestampString = try container.decodeIfPresent(String.self, forKey: .editedTimestamp) {
            let fmt = ISO8601DateFormatter()
            fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            self.editedTimestamp = fmt.date(from: editedTimestampString)
        } else {
            self.editedTimestamp = nil
        }
        
        isTTS = try container.decode(Bool.self, forKey: .isTTS)
        isMentionEveryone = try container.decode(Bool.self, forKey: .isMentionEveryone)
        mentions = try container.decode([User].self, forKey: .mentions)
        mentionRoles = try container.decode([Role].self, forKey: .mentionRoles)
        mentionChannels = try container.decodeIfPresent([Channel].self, forKey: .mentionChannels)
    }
}
