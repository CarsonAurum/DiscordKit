//
//  Component+TextDisplay.swift
//  DiscordKit
//
//  Created by Carson Rau on 5/5/25.
//

import NovaMacros

extension Component {
    
    @PrettyDescription
    public struct TextDisplay: Codable, Hashable, Sendable, CustomStringConvertible {
        public let id: Int?
        public let content: String
    }
}
