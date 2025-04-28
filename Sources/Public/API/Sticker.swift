//
//  Sticker.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/5/25.
//

public struct Sticker: DiscordModel {
    
}

extension Sticker {
    public struct Item: DiscordModel {
        public let id: Snowflake
        public let name: String
        public let formatType: Int
    }
}

extension Sticker.Item {
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case formatType = "format_type"
    }
}
