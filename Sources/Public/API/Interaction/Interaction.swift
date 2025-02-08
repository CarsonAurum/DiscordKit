//
//  Interaction.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/6/25.
//

public struct Interaction<T>: DiscordModel where T: Codable, T: Hashable, T: Sendable {
    public let id: Snowflake
    public let applicationID: Snowflake
    public let type: InteractionType
    public let data: T?
    public let guild: Guild
    public let guildID: Snowflake?
    public let channel: Channel?
    public let channelID: Snowflake?
    public let member: Guild.Member?
    public let user: User?
    public let token: String
    public let version: Int
    public let message: Message?
    public let appPermissions: Permissions?
    public let locale: Locale?
    public let guildLocale: Locale?
    public let entitlements: [Entitlement]
    public let authorizingIntegrationOwners: [Application.IntegrationType: Snowflake]
    public let context: ContextType?
}

extension Interaction {
    enum CodingKeys: String, CodingKey {
        case id
        case applicationID = "application_id"
        case type
        case data
        case guild
        case guildID = "guild_id"
        case channel
        case channelID = "channel_id"
        case member
        case user
        case token
        case version
        case message
        case appPermissions = "application_permissions"
        case locale
        case guildLocale = "guild_locale"
        case entitlements
        case authorizingIntegrationOwners = "authorizing_integration_owners"
        case context
    }
}
