//
//  Guild+VerificationLevel.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/4/25.
//

extension Guild {
    public enum VerificationLevel: Int, DiscordModel {
        case none = 0
        case low = 1
        case medium = 2
        case high = 3
        case veryHigh = 4
    }
}


extension Guild.VerificationLevel: CustomStringConvertible {
    public var description: String {
        switch self {
        case .none:     return "None"
        case .low:      return "Low"
        case .medium:   return "Medium"
        case .high:     return "High"
        case .veryHigh: return "Very High"
        }
    }
}
