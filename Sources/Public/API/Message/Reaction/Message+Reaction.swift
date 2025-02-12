//
//  Message+Reaction.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/12/25.
//

extension Message {
    public struct Reaction: DiscordModel {
        public let count: Int
        public let countDetails: Count
        public let isMe: Bool
        public let isMeSuper: Bool
        public let emoji: Emoji
        public let superColors: [Int]?
    }
}

extension Message.Reaction {
    enum CodingKeys: String, CodingKey {
        case count
        case countDetails = "count_details"
        case isMe = "me"
        case isMeSuper = "me_burst"
        case emoji
        case superColors = "burst_colors"
    }
}
