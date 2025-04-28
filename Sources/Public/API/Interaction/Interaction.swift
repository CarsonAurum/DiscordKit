//
//  Interaction.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/6/25.
//

/// A message received when a user uses an application command or a message component.
public struct Interaction: DiscordModel {
    /// The ID of the interaction.
    public let id: Snowflake
    /// The ID of the application this interaction is for.
    public let applicationID: Snowflake
    /// The type of interaction.
    public let type: InteractionType
    /// Interaction data payload.
    public let data: Data?
    /// Guild that the interaction was sent from.
    public let guild: Guild?
    /// Guild that the interaction was sent from.
    public let guildID: Snowflake?
    /// Channel that the interaction was sent from.
    public let channel: Channel?
    /// Channel that the interaction was sent from.
    public let channelID: Snowflake?
    /// Guild member data for the invoking user, including permissions.
    public let member: Guild.Member?
    /// User object for the invoking user, if involved in a DM.
    public let user: User?
    /// Continuation token for responding to the interaction.
    public let token: String
    /// Read-only property, always 1.
    public let version: Int
    /// For components, the message they were attached to.
    public let message: Message?
    /// Bitwise set of permissions the app has in the source location of the interaction.
    public let appPermissions: Permissions?
    /// Selected language of the invoking user.
    public let locale: Locale?
    /// Guild's preferred locale, if invoked in a guild.
    public let guildLocale: Locale?
    /// For monetized apps, any entitlements for the invoking user, representing access to premium SKUs.
    public let entitlements: [Entitlement]
    /// Mapping of installation contexts that the interaction was authorized for to related user or guild IDs.
    public let authorizingIntegrationOwners: [Application.IntegrationType: String]
    /// Context where the interaction was triggered from.
    public let context: ContextType?
    /// Attachment size limit in bytes.
    public let attachmentSizeLimit: Int
}

// MARK: - Codable

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
        case attachmentSizeLimit = "attachment_size_limit"
    }
    
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        self.id = try container.decode(Snowflake.self, forKey: .id)
        self.applicationID = try container.decode(Snowflake.self, forKey: .applicationID)
        self.type = try container.decode(InteractionType.self, forKey: .type)
        if container.contains(.data) {
            switch self.type {
            case .applicationCommand, .applicationCommandAutocomplete:
                self.data = .applicationCommand(try container.decode(Data.ApplicationCommand.self, forKey: .data))
            case .messageComponent:
                self.data = .messageComponent(try container.decode(Data.MessageComponent.self, forKey: .data))
            case .modalSubmit:
                self.data = .modalSubmit(try container.decode(Data.ModalSubmit.self, forKey: .data))
            default:
                fatalError("Unexpected Interaction data detected.")
            }
        } else {
            self.data = nil
        }
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
        self.attachmentSizeLimit = try container.decode(Int.self, forKey: .attachmentSizeLimit)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(id, forKey: .id)
        try container.encode(applicationID, forKey: .applicationID)
        try container.encode(type, forKey: .type)
        if let data = self.data {
            switch data {
            case .applicationCommand(let command):
                try container.encode(command, forKey: .data)
            case .messageComponent(let component):
                try container.encode(component, forKey: .data)
            case .modalSubmit(let modal):
                try container.encode(modal, forKey: .data)
            }
        }
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
        try container.encode(attachmentSizeLimit, forKey: .attachmentSizeLimit)
    }
}
