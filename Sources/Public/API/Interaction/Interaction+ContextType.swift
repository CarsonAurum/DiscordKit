//
//  Interaction+ContextType.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/6/25.
//

extension Interaction {
    /// The context in Discord where an interaction can be used, or where it was triggered from.
    public enum ContextType: Int, DiscordModel {
        /// Interaction can be used within servers.
        case guild = 0
        /// Interaction can be used within DMs with the app's bot user.
        case botDM = 1
        /// Interaction can be used within Group DMs and DMs other than the app's bot user.
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
