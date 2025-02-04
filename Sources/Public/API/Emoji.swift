//
//  Emoji.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/4/25.
//

public struct Emoji: DiscordModel {
    public let id: Snowflake?
    public let name: String?
    public let roles: [Snowflake]?
    public let user: User?
    public let requiresColons: Bool?
    public let isManaged: Bool?
    public let isAnimated: Bool?
    public let isAvailable: Bool?
}

extension Emoji {
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case roles
        case user
        case requiresColons = "require_colons"
        case isManaged = "managed"
        case isAnimated = "animated"
        case isAvailable = "available"
    }
}
