//
//  ApplicationCommand+CommandType.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/6/25.
//

import NovaMacros

extension ApplicationCommand {
    
    @PrettyDescription
    public enum CommandType: Int, Codable, Hashable, Sendable, CustomStringConvertible {
        case slashCommand = 1
        case user = 2
        case message = 3
        case activityEntry = 4
    }
}
