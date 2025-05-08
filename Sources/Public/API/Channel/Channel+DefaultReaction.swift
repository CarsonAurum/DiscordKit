//
//  Channel+DefaultReaction.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/7/25.
//

import NovaMacros

extension Channel {
    @CodingKeys(.all)
    @PrettyDescription
    public struct DefaultReaction: Codable, Hashable, Sendable, CustomStringConvertible {
        public let emojiId: Snowflake?
        public let emojiName: String?
    }
}
