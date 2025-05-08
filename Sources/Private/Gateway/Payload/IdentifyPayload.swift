//
//  IdentifyPayload.swift
//  DiscordKit
//
//  Created by Carson Rau on 1/31/25.
//

import NovaMacros

// MARK: - IdentifyPayload

/// The payload to send with an identify gateway message.
@CodingKeys(.custom(["isCompressed": "compressed"]))
@PrettyDescription
struct IdentifyPayload: Codable, Hashable, Sendable, CustomStringConvertible {
    
    /// The bot token.
    let token: String
    
    /// Client connection information.
    let properties: Properties
    
    /// Flag to determine if the client should receive compressed data.
    /// - Note: This is currently unsupported.
    let isCompressed: Bool?
    
    /// Number between 50 and 250 representing the maximum number of members in a guild before Discord stops sending offline members.
    let largeThreshold: Int?
    
    /// Information about the specific shard being identified.
    /// - Note: This is currently unsupported.
    let shardInfo: [Int]?
    
    /// The presence information to use when identifying.
    let presence: Presence?
    
    /// The intents to use when connecting. 
    let intents: GatewayIntents
}
