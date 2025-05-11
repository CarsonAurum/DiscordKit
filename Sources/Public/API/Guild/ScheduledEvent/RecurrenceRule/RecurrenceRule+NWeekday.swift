//
//  RecurrenceRule+NWeekday.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/5/25.
//

import NovaMacros

extension Guild.ScheduledEvent.RecurrenceRule {
    
    @PrettyDescription
    public struct NWeekday: Codable, Hashable, Sendable, CustomStringConvertible {
        public let n: Int
        public let day: Weekday
    }
}
