//
//  Guild+NSFWLevel.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/4/25.
//

extension Guild {
    public enum NSFWLevel: Int, DiscordModel {
        case `default` = 0
        case explicit = 1
        case safe = 2
        case ageRestricted = 3
    }
}
