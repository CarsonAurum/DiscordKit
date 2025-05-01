//
//  Component+StringSelect.swift
//  DiscordKit
//
//  Created by Carson Rau on 5/1/25.
//

extension Component {
    public struct StringSelect: DiscordModel {
        public let id: Int?
        public let customID: String
        public let options: [Option]
        public let placeholder: String?
        public let minValues: Int?
        public let maxValues: Int?
        public let isDisabled: Bool?
    }
}

extension Component.StringSelect {
    enum CodingKeys: String, CodingKey {
        case id
        case customID = "custom_id"
        case options
        case placeholder
        case minValues = "min_values"
        case maxValues = "max_values"
        case isDisabled = "disabled"
    }
}
