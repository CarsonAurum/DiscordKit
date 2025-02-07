//
//  Option+OptionType.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/6/25.
//

extension ApplicationCommand.Option {
    public enum OptionType: Int, DiscordModel {
        case subCommand = 1
        case subCommandGroup = 2
        case string = 3
        case integer = 4
        case boolean = 5
        case user = 6
        case channel = 7
        case role = 8
        case mentionable = 9
        case number = 10
        case attachment = 11
    }
}

extension ApplicationCommand.Option.OptionType: CustomStringConvertible {
    public var description: String {
        switch self {
        case .subCommand:           return "Sub Command"
        case .subCommandGroup:      return "Sub Command Group"
        case .string:               return "String"
        case .integer:              return "Integer"
        case .boolean:              return "Boolean"
        case .user:                 return "User"
        case .channel:              return "Channel"
        case .role:                 return "Role"
        case .mentionable:          return "Mentionable"
        case .number:               return "Number"
        case .attachment:           return "Attachment"
        }
    }
}
