//
//  Option+OptionType.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/6/25.
//

import NovaMacros

extension ApplicationCommand.Option {
    
    @PrettyDescription
    public enum OptionType: Int, Codable, Hashable, Sendable, CustomStringConvertible {
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
