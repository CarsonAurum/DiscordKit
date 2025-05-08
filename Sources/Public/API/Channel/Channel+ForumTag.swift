//
//  Channel+ForumTag.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/7/25.
//

import NovaMacros

extension Channel {
    
    @CodingKeys(.custom(["isModerated": "moderated"]))
    @PrettyDescription
    public struct ForumTag: Codable, Hashable, Sendable, CustomStringConvertible {
        public let id: Snowflake
        public let name: String
        public let isModerated: Bool
        public let emojiId: Snowflake?
        public let emojiName: String?
    }
}
