//
//  ScheduledEvent+PrivacyLevel.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/5/25.
//

extension Guild.ScheduledEvent {
    public enum PrivacyLevel: Int, DiscordModel {
        case guildOnly = 2
    }
}

extension Guild.ScheduledEvent.PrivacyLevel: CustomStringConvertible {
    public var description: String {
        switch self {
        case .guildOnly: return "Guild Only"
        }
    }
}
