//
//  CallbackResponse+ActivityInstance.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/11/25.
//

import NovaMacros

extension Interaction.CallbackResponse {
    
    @PrettyDescription
    public struct ActivityInstance: Codable, Hashable, Sendable, CustomStringConvertible {
        public let id: String
    }
}
