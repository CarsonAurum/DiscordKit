//
//  RecurrenceRule+Weekday.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/5/25.
//

extension Guild.ScheduledEvent.RecurrenceRule {
    public enum Weekday: Int, DiscordModel {
        case monday = 0
        case tuesday = 1
        case wednesday = 2
        case thursday = 3
        case friday = 4
        case saturday = 5
        case sunday = 6
    }
}

extension Guild.ScheduledEvent.RecurrenceRule.Weekday: CustomStringConvertible {
    public var description: String {
        switch self {
        case .monday:    return "Monday"
        case .tuesday:   return "Tuesday"
        case .wednesday: return "Wednesday"
        case .thursday:  return "Thursday"
        case .friday:    return "Friday"
        case .saturday:  return "Saturday"
        case .sunday:    return "Sunday"
        }
    }
}
