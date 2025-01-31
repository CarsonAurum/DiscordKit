//
//  HelloPayload.swift
//  DiscordKit
//
//  Created by Carson Rau on 1/30/25.
//

struct HelloPayload: DiscordModel {
    public let interval: Int
}

extension HelloPayload {
    enum CodingKeys: String, CodingKey {
        case interval = "heartbeat_interval"
    }
}
