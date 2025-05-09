//
//  Separator+Spacing.swift
//  DiscordKit
//
//  Created by Carson Rau on 5/6/25.
//

import NovaMacros

extension Component.Separator {
    
    @PrettyDescription
    public enum Spacing: Int, Codable, Hashable, Sendable, CustomStringConvertible {
        case small = 1
        case large = 2
    }
}
