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
    public let application: Application?
    public let applicationID: Snowflake?
    public let flags: Flags?
    public let messageReference: Reference?
    public let messageSnapshots: [Snapshot]?
    public let referencedMessage: Box<Message>?
    public let interactionMetadata: InteractionMetadata?
    public let thread: Channel?
    public let components: [Component]?
    public let stickerItems: [Sticker.Item]?
    public let position: Int?
    public let roleSubscriptionData: RoleSubscriptionData?
    public let resolved: Interaction.ResolvedData?
    public let poll: Poll?
    public let call: Call?
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
        
        case application
        case applicationID = "application_id"
        case flags
        case messageReference = "message_reference"
        case messageSnapshots = "message_snapshots"
        case referencedMessage = "referenced_message"
        case interactionMetadata = "interaction_metadata"
        case thread
        case components
        case stickerItems = "sticker_items"
        case position
        case roleSubscriptionData = "role_subscription_data"
        case resolved
        case poll
        case call
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
        application = try container.decodeIfPresent(Application.self, forKey: .application)
        applicationID = try container.decodeIfPresent(Snowflake.self, forKey: .applicationID)
        flags = try container.decodeIfPresent(Flags.self, forKey: .flags)
        messageReference = try container.decodeIfPresent(Reference.self, forKey: .messageReference)
        messageSnapshots = try container.decodeIfPresent([Snapshot].self, forKey: .messageSnapshots)
        referencedMessage = try container.decodeIfPresent(Box<Message>.self, forKey: .referencedMessage)
        if container.contains(.interactionMetadata) {
            if let metadata = try? container.decode(InteractionMetadata.ApplicationCommand.self, forKey: .interactionMetadata) {
                self.interactionMetadata = .applicationCommand(metadata)
            } else if let metadata = try? container.decode(InteractionMetadata.MessageComponent.self, forKey: .interactionMetadata) {
                self.interactionMetadata = .messageComponent(metadata)
            } else if let metadata = try? container.decode(InteractionMetadata.ModalSubmit.self, forKey: .interactionMetadata) {
                self.interactionMetadata = .modalSubmit(metadata)
            } else {
                fatalError()
                // TODO: Be more graceful
            }
        } else {
            self.interactionMetadata = nil
        }
        thread = try container.decodeIfPresent(Channel.self, forKey: .thread)
        components = try container.decodeIfPresent([Component].self, forKey: .components)
        stickerItems = try container.decodeIfPresent([Sticker.Item].self, forKey: .stickerItems)
        position = try container.decodeIfPresent(Int.self, forKey: .position)
        roleSubscriptionData = try container.decodeIfPresent(RoleSubscriptionData.self, forKey: .roleSubscriptionData)
        resolved = try container.decodeIfPresent(Interaction.ResolvedData.self, forKey: .resolved)
        poll = try container.decodeIfPresent(Poll.self, forKey: .poll)
        call = try container.decodeIfPresent(Call.self, forKey: .call)
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
        try container.encodeIfPresent(application, forKey: .application)
        try container.encodeIfPresent(applicationID, forKey: .applicationID)
        try container.encodeIfPresent(flags, forKey: .flags)
        try container.encodeIfPresent(messageReference, forKey: .messageReference)
        try container.encodeIfPresent(messageSnapshots, forKey: .messageSnapshots)
        try container.encodeIfPresent(referencedMessage, forKey: .referencedMessage)
        try container.encodeIfPresent(interactionMetadata, forKey: .interactionMetadata)
        try container.encodeIfPresent(thread, forKey: .thread)
        try container.encodeIfPresent(components, forKey: .components)
        try container.encodeIfPresent(stickerItems, forKey: .stickerItems)
        try container.encodeIfPresent(position, forKey: .position)
        try container.encodeIfPresent(roleSubscriptionData, forKey: .roleSubscriptionData)
        try container.encodeIfPresent(resolved, forKey: .resolved)
        try container.encodeIfPresent(poll, forKey: .poll)
        try container.encodeIfPresent(call, forKey: .call)
    }
}
