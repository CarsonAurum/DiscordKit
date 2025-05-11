//
//  ScheduledEvent+Status.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/5/25.
//

import NovaMacros

extension Guild.ScheduledEvent {
    
    @PrettyDescription
    public enum Status: Int, Codable, Hashable, Sendable, CustomStringConvertible {
        case scheduled = 1
        case active = 2
        case completed = 3
        case cancelled = 4
    }
}
