//
//  Component+TextInput.swift
//  DiscordKit
//
//  Created by Carson Rau on 5/1/25.
//

extension Component {
    public struct TextInput: DiscordModel {
        public let id: Int?
        public let customID: String
        public let style: Style
        public let label: StringSelect
        public let minLength: Int?
        public let maxLength: Int?
        public let isRequired: Bool?
        public let value: String?
        public let placeholder: String?
    }
}

extension Component.TextInput {
    enum CodingKeys: String, CodingKey {
        case id
        case customID = "custom_id"
        case style
        case label
        case minLength = "min_length"
        case maxLength = "max_length"
        case isRequired = "required"
        case value
        case placeholder
    }
}
