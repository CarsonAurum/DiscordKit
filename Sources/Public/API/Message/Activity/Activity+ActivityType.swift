//
//  Activity+ActivityType.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/8/25.
//

extension Message.Activity {
    public enum ActivityType: Int, DiscordModel {
        case join = 1
        case spectate = 2
        case listen = 3
        case joinRequest = 5
    }
}
