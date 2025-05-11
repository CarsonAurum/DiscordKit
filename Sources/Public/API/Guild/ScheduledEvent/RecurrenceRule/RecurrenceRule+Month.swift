//
//  RecurrenceRule+Month.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/5/25.
//

import NovaMacros

extension Guild.ScheduledEvent.RecurrenceRule {
    
    @PrettyDescription
    public enum Month: Int, Codable, Hashable, Sendable, CustomStringConvertible {
        case january = 1
        case february = 2
        case march = 3
        case april = 4
        case may = 5
        case june = 6
        case july = 7
        case august = 8
        case september = 9
        case october = 10
        case november = 11
        case december = 12
    }
}
