//
//  ScheduledEvent+RecurrenceRule.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/5/25.
//

import Foundation

extension Guild.ScheduledEvent {
    public struct RecurrenceRule: DiscordModel {
        public let start: Date
        public let end: Date?
        public let frequency: Frequency
        public let interval: Int
        public let byWeekday: [Weekday]?
        public let byNWeekday: [NWeekday]?
        public let byMonth: [Month]?
        public let byMonthDay: [Int]?
        public let byYearDay: [Int]?
        public let count: Int?
    }
}

extension Guild.ScheduledEvent.RecurrenceRule {
    enum CodingKeys: String, CodingKey {
        case start
        case end
        case frequency
        case interval
        case byWeekday = "by_weekday"
        case byNWeekday = "by_n_weekday"
        case byMonth = "by_month"
        case byMonthDay = "by_month_day"
        case byYearDay = "by_year_day"
        case count
    }
}
