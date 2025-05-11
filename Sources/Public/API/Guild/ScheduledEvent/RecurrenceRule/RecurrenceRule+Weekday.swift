//
//  RecurrenceRule+Weekday.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/5/25.
//

import NovaMacros

extension Guild.ScheduledEvent.RecurrenceRule {
    
    @PrettyDescription
    public enum Weekday: Int, Codable, Hashable, Sendable, CustomStringConvertible {
        case monday = 0
        case tuesday = 1
        case wednesday = 2
        case thursday = 3
        case friday = 4
        case saturday = 5
        case sunday = 6
    }
}
