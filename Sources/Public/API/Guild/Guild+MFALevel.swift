//
//  Guild+MFALevel.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/4/25.
//

import NovaMacros

extension Guild {
    
    @PrettyDescription
    public enum MFALevel: Int, Codable, Hashable, Sendable, CustomStringConvertible {
        case none = 0
        case elevated = 1
    }
}
