//
//  ScheduledEvent+RecurrenceRule.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/5/25.
//

import Foundation
import NovaMacros

extension Guild.ScheduledEvent {
    
    @CodingKeys(.all)
    @PrettyDescription
    public struct RecurrenceRule: Codable, Hashable, Sendable, CustomStringConvertible {
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

// TODO: Date encoding
