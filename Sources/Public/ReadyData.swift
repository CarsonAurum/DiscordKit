//
//  ReadyData.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/3/25.
//

public struct ReadyData: DiscordModel {
    public let guilds: [Guild]
    public let user: User
    public let application: Application
}
