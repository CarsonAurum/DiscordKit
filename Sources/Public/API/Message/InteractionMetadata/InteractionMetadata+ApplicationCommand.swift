//
//  InteractionMetadata+ApplicationCommand.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/11/25.
//

extension Message.InteractionMetadata {
    public struct ApplicationCommand: DiscordModel {
        public let id: Snowflake
        public let type: Interaction.InteractionType
        public let user: User
        public let authorizingIntegrationOwners: [Application.IntegrationType: String]
        public let originalResponseMessageID: Snowflake?
        public let targetUser: User?
        public let targetMessageID: Snowflake?
    }
}

extension Message.InteractionMetadata.ApplicationCommand {
    enum CodingKeys: String, CodingKey {
        case id
        case type
        case user
        case authorizingIntegrationOwners = "authorizing_integration_owners"
        case originalResponseMessageID = "original_response_message_id"
        case targetUser = "target_user"
        case targetMessageID = "target_message_id"
    }
}
