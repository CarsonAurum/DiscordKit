//
//  ApplicationCommand+Option.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/6/25.
//

import AnyCodable
import NovaMacros

extension ApplicationCommand {
    
    @CodingKeys(.custom([
        "optionDescription": "description",
        "isRequired": "required",
        "channelType": "channel_types",
        "isAutocompleteAvailable": "autocomplete"
    ]))
    @PrettyDescription
    public struct Option<T>: Codable, Hashable, Sendable, CustomStringConvertible
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
        
        public init(
            type: OptionType,
            name: String,
            nameLocalizations: [Locale: String]? = nil,
            optionDescription: String,
            descriptionLocalizations: [Locale: String]? = nil,
            isRequired: Bool? = nil,
            choices: [Choice]? = nil,
            options: [Option<AnyCodable>]? = nil,
            channelType: [Channel.ChannelType]? = nil,
            minValue: T? = nil,
            maxValue: T? = nil,
            minLength: Int? = nil,
            maxLength: Int? = nil,
            isAutocompleteAvailable: Bool? = nil
        ) {
            self.type = type
            self.name = name
            self.nameLocalizations = nameLocalizations
            self.optionDescription = optionDescription
            self.descriptionLocalizations = descriptionLocalizations
            self.isRequired = isRequired
            self.choices = choices
            self.options = options
            self.channelType = channelType
            self.minValue = minValue
            self.maxValue = maxValue
            self.minLength = minLength
            self.maxLength = maxLength
            self.isAutocompleteAvailable = isAutocompleteAvailable
        }
    }
}
