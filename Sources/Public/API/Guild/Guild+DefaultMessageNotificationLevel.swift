//
//  Guild+DefaultMessageNotificationLevel.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/4/25.
//

extension Guild {
    public enum DefaultMessageNotificationLevel: Int, DiscordModel {
        case allMessages = 0
        case onlyMentions = 1
    }
}

extension Guild.DefaultMessageNotificationLevel: CustomStringConvertible {
    public var description: String {
        switch self {
        case .allMessages:      return "All Messages"
        case .onlyMentions:     return "Only Mentions"
        }
    }
}
