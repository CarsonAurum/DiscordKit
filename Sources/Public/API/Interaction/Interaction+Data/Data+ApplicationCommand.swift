//
//  Data+ApplicationCommand.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/11/25.
//

import AnyCodable
import NovaMacros

extension Interaction.Data {
    
    @CodingKeys(.all)
    @PrettyDescription
    public struct ApplicationCommand: Codable, Hashable, Sendable, CustomStringConvertible {
        public let id: Snowflake
        public let name: String
        public let type: DiscordKit.ApplicationCommand.CommandType
        public let resolved: Interaction.ResolvedData?
        public let options: [Option<AnyCodable>]?
        public let guildId: Snowflake?
        public let targetId: Snowflake?
    }
}

extension Interaction.Data.ApplicationCommand {
    
    @CodingKeys(.custom([
        "_value": "value",
        "isFocused": "focused"
    ]))
    @PrettyDescription
    public struct Option<T>: Codable, Hashable, Sendable, CustomStringConvertible where T: Codable, T: Hashable, T: Sendable {
        public let name: String
        public let type: ApplicationCommand.Option<T>.OptionType
        public let _value: T?
        public let options: [Option<AnyCodable>]?
        public let isFocused: Bool?
    }
}

extension Interaction.Data.ApplicationCommand.Option where T == AnyCodable {
    public var value: Any? {
        _value?.value
    }
}
