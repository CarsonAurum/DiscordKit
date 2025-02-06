//
//  ScheduledEvent+Status.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/5/25.
//

extension Guild.ScheduledEvent {
    public enum Status: Int, DiscordModel {
        case scheduled = 1
        case active = 2
        case completed = 3
        case cancelled = 4
    }
}

extension Guild.ScheduledEvent.Status: CustomStringConvertible {
    public var description: String {
        switch self {
        case .scheduled:    return "Scheduled"
        case .active:       return "Active"
        case .completed:    return "Completed"
        case .cancelled:    return "Cancelled"
        }
    }
}
