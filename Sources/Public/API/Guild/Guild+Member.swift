//
//  Guild+Member.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/5/25.
//

import NovaMacros

extension Guild {
    @CodingKeys(.all)
    @PrettyDescription
    public struct Member: Codable, Hashable, Sendable, CustomStringConvertible {
        public let user: User?
        public let nick: String?
        public let avatar: String?
        public let banner: String?
        public let roles: [Snowflake]
        // TODO: Finish this
    }
}
