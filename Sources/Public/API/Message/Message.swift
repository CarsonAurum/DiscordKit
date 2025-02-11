//
//  Message.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/7/25.
//

import Foundation

public struct Message: DiscordModel {
    public let id: Snowflake
    public let channelID: Snowflake
    public let author: User
    public let content: String
    public let timestamp: Date
}
