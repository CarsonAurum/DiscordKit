//
//  Channel+FollowedChannel.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/7/25.
//

extension Channel {
    public struct FollowedChannel: DiscordModel {
        public let channelID: Snowflake
        public let webhookID: Snowflake
    }
}

extension Channel.FollowedChannel {
    enum CodingKeys: String, CodingKey {
        case channelID = "channel_id"
        case webhookID = "webhook_id"
    }
}
