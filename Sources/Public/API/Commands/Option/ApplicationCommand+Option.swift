//
//  ApplicationCommand+Option.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/6/25.
//

import AnyCodable

extension ApplicationCommand {
    public struct Option<T>: DiscordModel
        where T: Codable, T: Hashable, T: Sendable {
        public let type: OptionType
        public let name: String
        public let nameLocalizations: [Locale: String]?
        public let optionDescription: String
        public let descriptionLocalizations: [Locale: String]?
        public let isRequired: Bool?
        public let choices: [Choice]?
        public let options: [Option<AnyCodable>]?
        public let channelType: [Channel.ChannelType]?
        public let minValue: T?
        public let maxValue: T?
        public let minLength: Int?
        public let maxLength: Int?
        public let isAutocompleteAvailable: Bool?
    }
}

extension ApplicationCommand.Option {
    enum CodingKeys: String, CodingKey {
        case type
        case name
        case nameLocalizations = "name_localizations"
        case optionDescription = "description"
        case descriptionLocalizations = "description_localizations"
        case isRequired = "required"
        case choices
        case options
        case channelType = "channel_types"
        case minValue = "min_value"
        case maxValue = "max_value"
        case minLength = "min_length"
        case maxLength = "max_length"
        case isAutocompleteAvailable = "autocomplete"
    }
}
