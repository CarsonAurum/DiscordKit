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
    public let attachments: [Attachment]
    public let embeds: [Embed]
    public let reactions: [Reaction]?
    public let nonce: Nonce?
    public let isPinned: Bool
    public let webhookID: Snowflake?
    public let type: MessageType
    public let activity: Activity?
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
        case attachments
        case embeds
        case reactions
        case nonce
        case isPinned = "pinned"
        case webhookID = "webhook_id"
        case type
        case activity
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
        attachments = try container.decode([Attachment].self, forKey: .attachments)
        embeds = try container.decode([Embed].self, forKey: .embeds)
        reactions = try container.decodeIfPresent([Reaction].self, forKey: .reactions)
        
        if let stringNonce = try? container.decodeIfPresent(String.self, forKey: .nonce) {
            self.nonce = .string(stringNonce)
        } else if let intNonce = try? container.decodeIfPresent(Int.self, forKey: .nonce) {
            self.nonce = .int(intNonce)
        } else {
            self.nonce = nil
        }
        
        self.isPinned = try container.decode(Bool.self, forKey: .isPinned)
        self.webhookID = try container.decodeIfPresent(Snowflake.self, forKey: .webhookID)
        self.type = try container.decode(MessageType.self, forKey: .type)
        self.activity = try container.decodeIfPresent(Activity.self, forKey: .activity)
    }
    
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(channelID, forKey: .channelID)
        try container.encode(author, forKey: .author)
        try container.encode(content, forKey: .content)
        
        let dateString = ISO8601DateFormatter().string(from: timestamp)
        try container.encode(dateString, forKey: .timestamp)
        
        if let editedTimestamp = editedTimestamp {
            let dateString = ISO8601DateFormatter().string(from: editedTimestamp)
            try container.encode(dateString, forKey: .editedTimestamp)
        } else {
            try container.encodeNil(forKey: .editedTimestamp)
        }
        
        try container.encode(isTTS, forKey: .isTTS)
        try container.encode(isMentionEveryone, forKey: .isMentionEveryone)
        try container.encode(mentions, forKey: .mentions)
        try container.encode(mentionRoles, forKey: .mentionRoles)
        try container.encodeIfPresent(mentionChannels, forKey: .mentionChannels)
        try container.encode(attachments, forKey: .attachments)
        try container.encode(embeds, forKey: .embeds)
        try container.encodeIfPresent(reactions, forKey: .reactions)
        
        if let nonce = nonce {
            switch nonce {
            case .int(let intNonce):
                try container.encode(intNonce, forKey: .nonce)
            case .string(let stringNonce):
                try container.encode(stringNonce, forKey: .nonce)
            }
        }
        try container.encode(isPinned, forKey: .isPinned)
        try container.encodeIfPresent(webhookID, forKey: .webhookID)
        try container.encode(type, forKey: .type)
        try container.encode(activity, forKey: .activity)
    }
}
