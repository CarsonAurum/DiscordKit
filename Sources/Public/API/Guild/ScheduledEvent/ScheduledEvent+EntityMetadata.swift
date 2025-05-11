//
//  ScheduledEvent+EntityMetadata.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/5/25.
//

import NovaMacros

extension Guild.ScheduledEvent {
    
    @PrettyDescription
    public struct EntityMetadata: Codable, Hashable, Sendable, CustomStringConvertible {
        public let location: String?
    }
}
