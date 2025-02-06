//
//  RecurrenceRule+Frequency.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/5/25.
//

extension Guild.ScheduledEvent.RecurrenceRule {
    public enum Frequency: Int, DiscordModel {
        case yearly = 0
        case monthly = 1
        case weekly = 2
        case daily = 3
    }
}

extension Guild.ScheduledEvent.RecurrenceRule.Frequency: CustomStringConvertible {
    public var description: String {
        switch self {
        case .yearly:    return "YEARLY"
        case .monthly:   return "MONTHLY"
        case .weekly:    return "WEEKLY"
        case .daily:     return "DAILY"
        }
    }
}
