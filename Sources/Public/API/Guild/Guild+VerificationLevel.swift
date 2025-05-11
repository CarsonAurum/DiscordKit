//
//  Guild+VerificationLevel.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/4/25.
//

import NovaMacros

extension Guild {
    
    @PrettyDescription
    public enum VerificationLevel: Int, Codable, Hashable, Sendable, CustomStringConvertible {
        case none = 0
        case low = 1
        case medium = 2
        case high = 3
        case veryHigh = 4
    }
}
