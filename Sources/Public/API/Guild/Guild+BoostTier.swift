//
//  Guild+BoostTier.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/5/25.
//

extension Guild {
    public enum BoostTier: Int, DiscordModel {
        case none = 0
        case tier1 = 1
        case tier2 = 2
        case tier3 = 3
    }
}

extension Guild.BoostTier: CustomStringConvertible {
    public var description: String {
        switch self {
        case .none:     return "None"
        case .tier1:    return "Tier 1"
        case .tier2:    return "Tier 2"
        case .tier3:    return "Tier 3"
        }
    }
}
