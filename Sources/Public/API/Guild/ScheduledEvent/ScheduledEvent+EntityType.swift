//
//  ScheduledEvent+EntityType.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/5/25.
//

extension Guild.ScheduledEvent {
    public enum EntityType: Int, DiscordModel {
        case stageInstance = 1
        case voice = 2
        case external = 3
    }
}

extension Guild.ScheduledEvent.EntityType {
    public var description: String {
        switch self {
        case .stageInstance:    return "Stage Instance"
        case .voice:            return "Voice"
        case .external:         return "External"
        }
    }
}
