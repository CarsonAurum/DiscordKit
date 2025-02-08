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
    public let appPermissions: Permissions
    public let locale: Locale?
    public let guildLocale: Locale?
    public let entitlements: [Entitlement]
    public let authorizingIntegrationOwners: [Application.IntegrationType: Snowflake]
    public let context: ContextType?
    
}
