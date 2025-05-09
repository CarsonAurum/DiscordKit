//
//  Guild+ExplicitContentFilter.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/4/25.
//

import NovaMacros

extension Guild {
    
    @PrettyDescription
    public enum ExplicitContentFilter: Int, Codable, Hashable, Sendable, CustomStringConvertible {
        case disabled = 0
        case membersWithoutRoles = 1
        case allMembers = 2
    }
}
