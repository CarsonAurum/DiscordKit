//
//  Component+Separator.swift
//  DiscordKit
//
//  Created by Carson Rau on 5/6/25.
//

import NovaMacros

extension Component {
    
    @CodingKeys(.custom([
        "isDivider": "divider"
    ]))
    @PrettyDescription
    public struct Separator: Codable, Hashable, Sendable, CustomStringConvertible {
        public let id: Int?
        public let isDivider: Bool?
        public let spacing: Spacing?
    }
}
