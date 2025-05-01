//
//  Component+Button.swift
//  DiscordKit
//
//  Created by Carson Rau on 5/1/25.
//

extension Component {
    public struct Button: DiscordModel {
        public let id: Int?
        public let style: Style
        public let label: String
        public let emoji: Emoji?
        public let customID: String
        public let skuID: String
        public let isDisabled: Bool
    }
}

extension Component.Button {
    enum CodingKeys: String, CodingKey {
        case id
        case style
        case label
        case emoji
        case customID = "custom_id"
        case skuID = "sku_id"
        case isDisabled = "disabled"
    }
}
