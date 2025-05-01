//
//  Button+Style.swift
//  DiscordKit
//
//  Created by Carson Rau on 5/1/25.
//

extension Component.Button {
    public enum Style: Int, DiscordModel {
        case primary = 1
        case secondary = 2
        case success = 3
        case danger = 4
        case link = 5
        case premium = 6
    }
}
