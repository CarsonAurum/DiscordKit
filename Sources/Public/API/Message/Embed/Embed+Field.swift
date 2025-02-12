//
//  Embed+Field.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/12/25.
//

extension Message.Embed {
    public struct Field: DiscordModel {
        public let name: String
        public let value: String
        public let isInline: Bool?
    }
}

extension Message.Embed.Field {
    enum CodingKeys: String, CodingKey {
        case name
        case value
        case isInline = "inline"
    }
}
