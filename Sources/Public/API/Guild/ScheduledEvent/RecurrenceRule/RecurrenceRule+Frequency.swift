//
//  RecurrenceRule+Frequency.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/5/25.
//

import NovaMacros

extension Guild.ScheduledEvent.RecurrenceRule {
    
    @PrettyDescription
    public enum Frequency: Int, Codable, Hashable, Sendable, CustomStringConvertible {
        case yearly = 0
        case monthly = 1
        case weekly = 2
        case daily = 3
    }
}
