//
//  Component+Separator.swift
//  DiscordKit
//
//  Created by Carson Rau on 5/6/25.
//

extension Component {
    public struct Separator: DiscordModel {
        public let id: Int?
        public let isDivider: Bool?
        public let spacing: Spacing?
    }
}

extension Component.Separator {
    enum CodingKeys: String, CodingKey {
        case id
        case isDivider = "divider"
        case spacing
    }
}
