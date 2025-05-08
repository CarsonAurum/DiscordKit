//
//  ApplicationCommand+EntryPointHandlerType.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/6/25.
//

import NovaMacros

extension ApplicationCommand {
    
    @PrettyDescription
    public enum EntryPointHandlerType: Int, Codable, Hashable, Sendable, CustomStringConvertible {
        case appHandler = 1
        case discordLaunchActivity = 2
    }
}
