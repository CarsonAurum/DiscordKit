//
//  Component+MentionableSelect.swift
//  DiscordKit
//
//  Created by Carson Rau on 5/5/25.
//

extension Component {
    public struct MentionableSelect: DiscordModel {
        public let id: Int?
        public let customID: String
        public let placeholder: String?
        public let defaultValues: [SelectDefaultValue]?
        public let minValues: Int?
        public let maxValues: Int?
        public let isDisabled: Bool?
    }
}

extension Component.MentionableSelect {
    enum CodingKeys: String, CodingKey {
        case id
        case customID = "custom_id"
        case placeholder
        case defaultValues = "default_values"
        case minValues = "min_values"
        case maxValues = "max_values"
        case isDisabled = "disabled"
    }
}
