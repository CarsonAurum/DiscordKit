//
//  StringSelect+Option.swift
//  DiscordKit
//
//  Created by Carson Rau on 5/1/25.
//

import NovaMacros

extension Component.StringSelect {
    
    @CodingKeys(.custom([
        "optionDescription": "description",
        "isDefault": "default"
    ]))
    @PrettyDescription
    public struct Option: Codable, Hashable, Sendable, CustomStringConvertible {
        public let label: String
        public let value: String
        public let optionDescription: String?
        public let emoji: Emoji?
        public let isDefault: Bool?
    }
}
