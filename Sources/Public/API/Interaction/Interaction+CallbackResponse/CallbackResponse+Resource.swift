//
//  CallbackResponse+Resource.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/11/25.
//

import NovaMacros

extension Interaction.CallbackResponse {
    
    @CodingKeys(.all)
    @PrettyDescription
    public struct Resource: Codable, Hashable, Sendable, CustomStringConvertible {
        public let type: Interaction.Response.CallbackType
        public let activityInstance: ActivityInstance?
        public let message: Message?
    }
}
