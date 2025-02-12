//
//  Message+Call.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/12/25.
//

import Foundation

extension Message {
    public struct Call: DiscordModel {
        public let participants: [Snowflake]
        public let endedTimestamp: Date?
    }
}

extension Message.Call {
    enum CodingKeys: String, CodingKey {
        case participants
        case endedTimestamp = "ended_timestamp"
    }
}
