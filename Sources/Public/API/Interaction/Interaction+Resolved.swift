//
//  Interaction+Resolved.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/8/25.
//

extension Interaction {
    public struct ResolvedData: DiscordModel {
        public let users: [Snowflake: User]?
        public let members: [Snowflake: Guild.Member]?
        public let roles: [Snowflake: Role]?
        public let channels: [Snowflake: Channel]?
        public let messages: [Snowflake: Message]?
        public let attachments: [Snowflake: Message.Attachment]?
    }
}

extension Interaction.ResolvedData {
    enum CodingKeys: String, CodingKey {
        case users
        case members
        case roles
        case channels
        case messages
        case attachments
    }
    
    // 2. Custom decoder
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.users = try Self.decodeMapIfPresent(User.self, forKey: .users, in: container)
        self.members = try Self.decodeMapIfPresent(Guild.Member.self,forKey: .members, in: container)
        self.roles = try Self.decodeMapIfPresent(Role.self, forKey: .roles, in: container)
        self.channels = try Self.decodeMapIfPresent(Channel.self, forKey: .channels, in: container)
        self.messages = try Self.decodeMapIfPresent(Message.self, forKey: .messages, in: container)
        self.attachments = try Self.decodeMapIfPresent(Message.Attachment.self, forKey: .attachments, in: container)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try Self.encodeMapIfPresent(users, forKey: .users, into: &container)
        try Self.encodeMapIfPresent(members, forKey: .members, into: &container)
        try Self.encodeMapIfPresent(roles, forKey: .roles, into: &container)
        try Self.encodeMapIfPresent(channels, forKey: .channels, into: &container)
        try Self.encodeMapIfPresent(messages, forKey: .messages, into: &container)
        try Self.encodeMapIfPresent(attachments, forKey: .attachments, into: &container)
    }
    
    private static func decodeMapIfPresent<T: Decodable>(
        _ type: T.Type,
        forKey key: CodingKeys,
        in container: KeyedDecodingContainer<CodingKeys>
    ) throws -> [Snowflake: T]? {
        guard let rawMap = try container.decodeIfPresent([String: T].self, forKey: key)
        else { return nil }
        let converted = [Snowflake: T](
            uniqueKeysWithValues: rawMap.compactMap { (k, v) in
                guard let sf = Snowflake(value: k) else { return nil }
                return (sf, v)
            }
        )
        return converted.isEmpty ? nil : converted
    }
    
    private static func encodeMapIfPresent<T: Encodable>(
        _ map: [Snowflake: T]?,
        forKey key: CodingKeys,
        into container: inout KeyedEncodingContainer<CodingKeys>
    ) throws {
        guard let map = map else { return }
        let stringKeyed = [String: T](
            uniqueKeysWithValues: map.map { (k, v) in
                (k.value.description, v)
            }
        )
        try container.encode(stringKeyed, forKey: key)
    }
}
