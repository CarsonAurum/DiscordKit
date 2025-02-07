//
//  Option+Choice.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/6/25.
//

extension ApplicationCommand.Option {
    public struct Choice: DiscordModel {
        public let name: String
        public let nameLocalizations: [Locale: String]?
        public let value: T
    }
}

extension ApplicationCommand.Option.Choice {
    enum CodingKeys: String, CodingKey {
        case name
        case nameLocalizations = "name_localizations"
        case value
    }
}

extension ApplicationCommand.Option.Choice: CustomStringConvertible {
    public var description: String {
        var result = "[Name: \(name)"
        if let nameLocalizations = nameLocalizations {
            result += " || \(nameLocalizations)"
        }
        result += " || Value: \(value)]"
        return result
    }
}
