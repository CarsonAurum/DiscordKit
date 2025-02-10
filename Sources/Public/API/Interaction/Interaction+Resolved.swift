//
//  Interaction+Resolved.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/8/25.
//

extension Interaction {
    public struct ResolvedData: DiscordModel {
        public let user: [Snowflake: User]?
        public let members: [Snowflake: Guild.Member]?
        public let roles: [Snowflake: Role]?
        public let channels: [Snowflake: Channel]?
        public let messages: [Snowflake: Message]?
        public let attachments: [Snowflake: Message.Attachment]?
    }
}
