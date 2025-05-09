//
//  TextInput+Style.swift
//  DiscordKit
//
//  Created by Carson Rau on 5/1/25.
//

import NovaMacros

extension Component.TextInput {
    
    @PrettyDescription
    public enum Style: Int, Codable, Hashable, Sendable, CustomStringConvertible {
        case short = 1
        case paragraph = 2
    }
}
