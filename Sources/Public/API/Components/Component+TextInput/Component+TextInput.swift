//
//  Component+TextInput.swift
//  DiscordKit
//
//  Created by Carson Rau on 5/1/25.
//

import NovaMacros

extension Component {
    
    @CodingKeys(.custom([
        "isRequired": "required"
    ]))
    @PrettyDescription
    public struct TextInput: Codable, Hashable, Sendable, CustomStringConvertible {
        public let id: Int?
        public let customId: String
        public let style: Style
        public let label: StringSelect
        public let minLength: Int?
        public let maxLength: Int?
        public let isRequired: Bool?
        public let value: String?
        public let placeholder: String?
    }
}
