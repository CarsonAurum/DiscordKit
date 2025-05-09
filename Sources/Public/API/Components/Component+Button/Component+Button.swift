//
//  Component+Button.swift
//  DiscordKit
//
//  Created by Carson Rau on 5/1/25.
//

import NovaMacros

extension Component {
    
    @CodingKeys(.custom(
        [
            "isDisabled": "disabled"
        ]
    ))
    @PrettyDescription
    public struct Button: Codable, Hashable, Sendable, CustomStringConvertible {
        public let id: Int?
        public let style: Style
        public let label: String
        public let emoji: Emoji?
        public let customId: String
        public let skuId: String
        public let isDisabled: Bool
    }
}
