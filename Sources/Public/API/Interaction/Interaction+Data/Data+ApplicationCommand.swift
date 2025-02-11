//
//  Data+ApplicationCommand.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/11/25.
//

import AnyCodable

extension Interaction.Data {
    public struct ApplicationCommand: DiscordModel {
        public let id: Snowflake
        public let name: String
        public let type: DiscordKit.ApplicationCommand.CommandType
        public let resolved: Interaction.ResolvedData?
        public let options: [Option<AnyCodable>]?
        public let guildID: Snowflake?
        public let targetID: Snowflake?
    }
}

extension Interaction.Data.ApplicationCommand {
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case type
        case resolved
        case options
        case guildID = "guild_id"
        case targetID = "target_id"
    }
}

extension Interaction.Data.ApplicationCommand {
    public struct Option<T>: DiscordModel where T: Codable, T: Hashable, T: Sendable {
        public let name: String
        public let type: ApplicationCommand.Option<T>.OptionType
        public let value: T?
        public let options: [Option<AnyCodable>]?
        public let isFocused: Bool?
    }
}

extension Interaction.Data.ApplicationCommand.Option {
    enum CodingKeys: String, CodingKey {
        case name
        case type
        case value
        case options
        case isFocused = "focused"
    }
}
