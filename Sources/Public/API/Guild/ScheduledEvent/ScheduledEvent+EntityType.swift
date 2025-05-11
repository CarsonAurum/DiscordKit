//
//  ScheduledEvent+EntityType.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/5/25.
//

import NovaMacros

extension Guild.ScheduledEvent {
    
    @PrettyDescription
    public enum EntityType: Int, Codable, Hashable, Sendable, CustomStringConvertible {
        case stageInstance = 1
        case voice = 2
        case external = 3
    }
}
