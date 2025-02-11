//
//  CallbackResponse+Callback.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/11/25.
//

extension Interaction.CallbackResponse {
    public struct Callback: DiscordModel {
        public let id: Snowflake
        public let type: Interaction.InteractionType
        public let activityInstanceID: String?
        public let responseMessageID: Snowflake?
        public let isResponseMessageLoading: Bool?
        public let isResponseMessageEphemeral: Bool?
    }
}

extension Interaction.CallbackResponse.Callback {
    enum CodingKeys: String, CodingKey {
        case id
        case type
        case activityInstanceID = "activity_instance_id"
        case responseMessageID = "response_message_id"
        case isResponseMessageLoading = "response_message_loading"
        case isResponseMessageEphemeral = "response_message_ephemeral"
    }
}
