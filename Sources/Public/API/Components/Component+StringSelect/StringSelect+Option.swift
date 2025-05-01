//
//  StringSelect+Option.swift
//  DiscordKit
//
//  Created by Carson Rau on 5/1/25.
//

extension Component.StringSelect {
    public struct Option: DiscordModel {
        public let label: String
        public let value: String
        public let description: String?
        public let emoji: Emoji?
        public let isDefault: Bool?
    }
}

extension Component.StringSelect.Option {
    enum CodingKeys: String, CodingKey {
        case label
        case value
        case description
        case emoji
        case isDefault = "default"
    }
}
