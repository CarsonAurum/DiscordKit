//
//  Channel+ThreadMember.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/7/25.
//

import Foundation

extension Channel {
    public struct ThreadMember: DiscordModel {
        public let id: Snowflake?
        public let userID: Snowflake?
        public let joinTimestamp: Date
        public let flags: Int
        public let member: Guild.Member?
    }
}

extension Channel.ThreadMember {
    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case joinTimestamp = "join_timestamp"
        case flags
        case member
    }
    
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decodeIfPresent(Snowflake.self, forKey: .id)
        userID = try container.decodeIfPresent(Snowflake.self, forKey: .userID)
        
        let joinTimestampString = try container.decode(String.self, forKey: .joinTimestamp)
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.joinTimestamp = fmt.date(from: joinTimestampString)!
        
        flags = try container.decode(Int.self, forKey: .flags)
        member = try container.decodeIfPresent(Guild.Member.self, forKey: .member)
    }
    
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encodeIfPresent(id, forKey: .id)
        try container.encodeIfPresent(userID, forKey: .userID)
        
        let joinTimestampString = ISO8601DateFormatter().string(from: joinTimestamp)
        try container.encode(joinTimestampString, forKey: .joinTimestamp)
        
        try container.encode(flags, forKey: .flags)
        try container.encodeIfPresent(member, forKey: .member)
        
        
    }
}
