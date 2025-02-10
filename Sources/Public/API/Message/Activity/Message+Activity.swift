//
//  Message+Activity.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/7/25.
//

extension Message {
    public struct Activity: DiscordModel {
        public let type: ActivityType
        public let partyID: String?
    }
}

extension Message.Activity {
    enum CodingKeys: String, CodingKey {
        case type
        case partyID = "party_id"
    }
}
