//
//  ApplicationCommand+CommandType.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/6/25.
//

extension ApplicationCommand {
    public enum CommandType: Int, DiscordModel {
        case slashCommand = 1
        case user = 2
        case message = 3
        case activityEntry = 4
    }
}
