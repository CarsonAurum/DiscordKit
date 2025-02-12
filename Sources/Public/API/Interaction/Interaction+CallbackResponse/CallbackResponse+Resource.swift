//
//  CallbackResponse+Resource.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/11/25.
//

extension Interaction.CallbackResponse {
    public struct Resource: DiscordModel {
        public let type: Interaction.Response.CallbackType
        public let activityInstance: ActivityInstance?
        public let message: Message?
    }
}

extension Interaction.CallbackResponse.Resource {
    enum CodingKeys: String, CodingKey {
        case type
        case activityInstance = "activity_instance"
        case message
    }
}
