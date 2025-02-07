//
//  ApplicationCommand+EntryPointHandlerType.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/6/25.
//

extension ApplicationCommand {
    public enum EntryPointHandlerType: Int, DiscordModel {
        case appHandler = 1
        case discordLaunchActivity = 2
    }
}

extension ApplicationCommand.EntryPointHandlerType: CustomStringConvertible {
    public var description: String {
        switch self {
        case .appHandler:                   return "App Handler"
        case .discordLaunchActivity:        return "Discord Launch Activity"
        }
    }
}
