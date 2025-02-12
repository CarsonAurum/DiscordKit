//
//  Reaction+Count.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/12/25.
//

extension Message.Reaction {
    public struct Count:  DiscordModel {
        public let `super`: Int
        public let normal: Int
    }
}

extension Message.Reaction.Count {
    enum CodingKeys: String, CodingKey {
        case `super` = "burst"
        case normal
    }
}
