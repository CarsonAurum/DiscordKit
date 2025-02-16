//
//  CallbackData+Messages.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/11/25.
//

extension Interaction.Response.CallbackData {
    public struct Messages: DiscordModel {
        public let isTTS: Bool?
        public let content: String?
        public let embeds: [Message.Embed]?
        // public let allowedMentions: Message.AllowedMentions?
        public let flags: Message.Flags?
        public let components: [Component]?
        public let attachments: [Message.Attachment]?
        // public let poll: Poll.CreateRequest?
    }
}

extension Interaction.Response.CallbackData.Messages {
    enum CodingKeys: String, CodingKey {
        case isTTS = "tts"
        case content
        case embeds
        // case allowedMentions = "allowed_mentions"
        case flags
        case components
        case attachments
        // case polls
    }
}
