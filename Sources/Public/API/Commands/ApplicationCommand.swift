//
//  ApplicationCommand.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/4/25.
//

public struct ApplicationCommand: DiscordModel {
    public let id: Snowflake
    public let type: CommandType
    public let applicationID: Snowflake
    public let guildID: Snowflake?
    public let name: String
    public let nameLocalizations: [Locale: String]?
    public let commandDescription: String
    public let descriptionLocalizations: [Locale: String]?
}
