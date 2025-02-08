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
    public let guild: Guild?
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
    public let authorizingIntegrationOwners: [Application.IntegrationType: String]
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
    
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        self.id = try container.decode(Snowflake.self, forKey: .id)
        self.applicationID = try container.decode(Snowflake.self, forKey: .applicationID)
        self.type = try container.decode(InteractionType.self, forKey: .type)
        self.data = try container.decodeIfPresent(T.self, forKey: .data)
        self.guild = try container.decodeIfPresent(Guild.self, forKey: .guild)
        self.guildID = try container.decodeIfPresent(Snowflake.self, forKey: .guildID)
        self.channel = try container.decodeIfPresent(Channel.self, forKey: .channel)
        self.channelID = try container.decodeIfPresent(Snowflake.self, forKey: .channelID)
        self.member = try container.decodeIfPresent(Guild.Member.self, forKey: .member)
        self.user = try container.decodeIfPresent(User.self, forKey: .user)
        self.token = try container.decode(String.self, forKey: .token)
        self.version = try container.decode(Int.self, forKey: .version)
        self.message = try container.decodeIfPresent(Message.self, forKey: .message)
        self.appPermissions = try container.decodeIfPresent(Permissions.self, forKey: .appPermissions)
        self.locale = try container.decodeIfPresent(Locale.self, forKey: .locale)
        self.guildLocale = try container.decodeIfPresent(Locale.self, forKey: .guildLocale)
        self.entitlements = try container.decode([Entitlement].self, forKey: .entitlements)
        self.context = try container.decodeIfPresent(ContextType.self, forKey: .context)
        
        let rawDict = try container.decode([String: String].self, forKey: .authorizingIntegrationOwners)
        var convertedDict = [Application.IntegrationType: String]()
        for (key, value) in rawDict {
            guard let intKey = Int(key),
                  let enumKey = Application.IntegrationType(rawValue: intKey) else {
                continue
            }
            convertedDict[enumKey] = value
        }
        self.authorizingIntegrationOwners = convertedDict
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(id, forKey: .id)
        try container.encode(applicationID, forKey: .applicationID)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(data, forKey: .data)
        try container.encodeIfPresent(guild, forKey: .guild)
        try container.encodeIfPresent(guildID, forKey: .guildID)
        try container.encodeIfPresent(channel, forKey: .channel)
        try container.encodeIfPresent(channelID, forKey: .channelID)
        try container.encodeIfPresent(member, forKey: .member)
        try container.encodeIfPresent(user, forKey: .user)
        try container.encode(token, forKey: .token)
        try container.encode(version, forKey: .version)
        try container.encodeIfPresent(message, forKey: .message)
        try container.encodeIfPresent(appPermissions, forKey: .appPermissions)
        try container.encodeIfPresent(locale, forKey: .locale)
        try container.encodeIfPresent(guildLocale, forKey: .guildLocale)
        try container.encode(entitlements, forKey: .entitlements)
        try container.encodeIfPresent(context, forKey: .context)
        
        var rawDict = [String: String]()
        for (key, value) in authorizingIntegrationOwners {
            rawDict["\(key.rawValue)"] = value
        }
        try container.encode(rawDict, forKey: .authorizingIntegrationOwners)
    }
}
