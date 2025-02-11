//
//  CallbackData+Modal.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/11/25.
//

extension Interaction.Response.CallbackData {
    public struct Modal: DiscordModel {
        public let customID: String
        public let title: String
        public let components: [Component]
    }
}

extension Interaction.Response.CallbackData.Modal {
    enum CodingKeys: String, CodingKey {
        case customID = "custom_id"
        case title
        case components
    }
}
