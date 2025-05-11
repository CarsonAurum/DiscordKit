//
//  ScheduledEvent+PrivacyLevel.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/5/25.
//

import NovaMacros

extension Guild.ScheduledEvent {
    @PrettyDescription
    public enum PrivacyLevel: Int, Codable, Hashable, Sendable, CustomStringConvertible {
        case guildOnly = 2
    }
}
