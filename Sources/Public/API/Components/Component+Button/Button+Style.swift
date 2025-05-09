//
//  Button+Style.swift
//  DiscordKit
//
//  Created by Carson Rau on 5/1/25.
//

import NovaMacros

extension Component.Button {
    @PrettyDescription
    public enum Style: Int, Codable, Hashable, Sendable, CustomStringConvertible {
        case primary = 1
        case secondary = 2
        case success = 3
        case danger = 4
        case link = 5
        case premium = 6
    }
}
