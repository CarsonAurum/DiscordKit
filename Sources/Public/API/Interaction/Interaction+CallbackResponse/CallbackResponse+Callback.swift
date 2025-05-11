//
//  CallbackResponse+Callback.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/11/25.
//

import NovaMacros

extension Interaction.CallbackResponse {
    
    @CodingKeys(.custom([
        "isResponseMessageLoading": "response_message_loading",
        "isResponseMessageEphemeral": "response_message_ephemeral"
    ]))
    @PrettyDescription
    public struct Callback: Codable, Hashable, Sendable, CustomStringConvertible {
        public let id: Snowflake
        public let type: Interaction.InteractionType
        public let activityInstanceId: String?
        public let responseMessageId: Snowflake?
        public let isResponseMessageLoading: Bool?
        public let isResponseMessageEphemeral: Bool?
    }
}
