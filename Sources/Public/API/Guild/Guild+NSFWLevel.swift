//
//  Guild+NSFWLevel.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/4/25.
//

import NovaMacros

extension Guild {
    
    @PrettyDescription
    public enum NSFWLevel: Int, Codable, Hashable, Sendable, CustomStringConvertible {
        case `default` = 0
        case explicit = 1
        case safe = 2
        case ageRestricted = 3
    }
}
