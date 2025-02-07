//
//  Interaction+ContextType.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/6/25.
//

extension Interaction {
    public enum ContextType: Int, DiscordModel {
        case guild = 0
        case botDM = 1
        case privateChannel = 2
    }
}

extension Interaction.ContextType: CustomStringConvertible {
    public var description: String {
        switch self {
        case .guild:            return "Guild"
        case .botDM:            return "Bot DM"
        case .privateChannel:   return "Private Channel"
        }
    }
}
