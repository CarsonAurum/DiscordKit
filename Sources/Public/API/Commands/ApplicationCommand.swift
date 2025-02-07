//
//  ApplicationCommand.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/4/25.
//

import AnyCodable

public struct ApplicationCommand: DiscordModel {
    public let id: Snowflake
    public let type: CommandType
    public let applicationID: Snowflake
    public let guildID: Snowflake?
    public let name: String
    public let nameLocalizations: [Locale: String]?
    public let commandDescription: String
    public let descriptionLocalizations: [Locale: String]?
    public let options: [Option<AnyCodable>]?
    public let defaultPermissions: Permissions?
    public let isNSFW: Bool?
    public let integrationTypes: [Application.IntegrationType]?
    public let contexts: [Interaction.ContextType]?
    public let version: Snowflake
    public let handler: EntryPointHandlerType?
}

extension ApplicationCommand {
    enum CodingKeys: String, CodingKey {
        case id
        case type
        case applicationID = "application_id"
        case guildID = "guild_id"
        case name
        case nameLocalizations = "name_localizations"
        case commandDescription = "description"
        case descriptionLocalizations = "description_localizations"
        case options
        case defaultPermissions = "default_member_permissions"
        case isNSFW = "nsfw"
        case integrationTypes = "integration_types"
        case contexts
        case version
        case handler
    }
}
