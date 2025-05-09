//
//  Guild+BoostTier.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/5/25.
//

import NovaMacros

extension Guild {
    
    @PrettyDescription
    public enum BoostTier: Int, Codable, Hashable, Sendable, CustomStringConvertible {
        case none = 0
        case tier1 = 1
        case tier2 = 2
        case tier3 = 3
    }
}
