//
//  Interaction+CallbackResponse.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/11/25.
//

import NovaMacros

extension Interaction {
    
    @PrettyDescription
    public struct CallbackResponse: Codable, Hashable, Sendable, CustomStringConvertible {
        public let interaction: Callback
        public let resource: Resource?
    }
}
