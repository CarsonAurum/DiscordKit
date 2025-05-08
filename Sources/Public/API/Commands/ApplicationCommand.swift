//
//  ApplicationCommand.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/4/25.
//

import AnyCodable
import NovaMacros

@CodingKeys(.custom([
    "commandDescription": "description",
    "defaultPermissions": "default_member_permissions",
    "isNsfw": "nsfw"
]))
@PrettyDescription
public struct ApplicationCommand: Codable, Hashable, Sendable, CustomStringConvertible {
    public let id: Snowflake
    public let type: CommandType
    public let applicationId: Snowflake
    public let guildId: Snowflake?
    public let name: String
    public let nameLocalizations: [Locale: String]?
    public let commandDescription: String
    public let descriptionLocalizations: [Locale: String]?
    public let options: [Option<AnyCodable>]?
    public let defaultPermissions: Permissions?
    public let isNsfw: Bool?
    public let integrationTypes: [Application.IntegrationType]?
    public let contexts: [Interaction.ContextType]?
    public let version: Snowflake
    public let handler: EntryPointHandlerType?
}
