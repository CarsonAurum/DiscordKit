//
//  RecurrenceRule+NWeekday.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/5/25.
//

extension Guild.ScheduledEvent.RecurrenceRule {
    public struct NWeekday: DiscordModel {
        public let n: Int
        public let day: Weekday
    }
}
