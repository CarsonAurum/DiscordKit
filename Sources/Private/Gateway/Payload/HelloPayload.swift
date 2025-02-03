//
//  HelloPayload.swift
//  DiscordKit
//
//  Created by Carson Rau on 1/30/25.
//

// MARK: - HelloPayload

/// Data received on opcode HELLO.
struct HelloPayload: DiscordModel {
    
    /// Interval (in milliseconds) an app should heartbeat with
    public let interval: Int
}

// MARK: Codable

extension HelloPayload {
    enum CodingKeys: String, CodingKey {
        case interval = "heartbeat_interval"
    }
}

// MARK: CustomStringConvertible

extension HelloPayload: CustomStringConvertible {
    public var description: String {
        return "[Interval: \(interval) ms]"
    }
}
