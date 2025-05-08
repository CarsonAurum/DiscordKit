//
//  Channel+FollowedChannel.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/7/25.
//

import NovaMacros

extension Channel {
    @CodingKeys(.all)
    @PrettyDescription
    public struct FollowedChannel: Codable, Hashable, Sendable, CustomStringConvertible {
        public let channelId: Snowflake
        public let webhookId: Snowflake
    }
}
