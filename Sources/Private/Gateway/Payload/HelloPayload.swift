//
//  HelloPayload.swift
//  DiscordKit
//
//  Created by Carson Rau on 1/30/25.
//

import NovaMacros

// MARK: - HelloPayload

/// Data received on opcode HELLO.
@CodingKeys(.custom(["interval": "heartbeat_interval"]))
struct HelloPayload: Codable, Hashable, Sendable {
    
    /// Interval (in milliseconds) an app should heartbeat with
    public let interval: Int
}

// MARK: CustomStringConvertible

extension HelloPayload: CustomStringConvertible {
    public var description: String {
        return "[Interval: \(interval) ms]"
    }
}
