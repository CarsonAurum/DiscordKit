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
    
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Snowflake.self, forKey: .id)
        type = try container.decode(Interaction.InteractionType.self, forKey: .type)
        user = try container.decode(User.self, forKey: .user)
        let rawDict = try container.decode([String: String].self, forKey: .authorizingIntegrationOwners)
        var convertedDict = [Application.IntegrationType: String]()
        for (key, value) in rawDict {
            guard let intKey = Int(key),
                  let enumKey = Application.IntegrationType(rawValue: intKey) else {
                continue
            }
            convertedDict[enumKey] = value
        }
        self.authorizingIntegrationOwners = convertedDict
        originalResponseMessageID = try container.decodeIfPresent(Snowflake.self, forKey: .originalResponseMessageID)
        targetUser = try container.decodeIfPresent(User.self, forKey: .targetUser)
        targetMessageID = try container.decodeIfPresent(Snowflake.self, forKey: .targetMessageID)
    }
}
