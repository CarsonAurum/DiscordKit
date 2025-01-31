//
//  IdentifyPayload.swift
//  DiscordKit
//
//  Created by Carson Rau on 1/31/25.
//

// MARK: - IdentifyPayload

/// The payload to send with an identify gateway message.
struct IdentifyPayload: DiscordModel {
    
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

// MARK: Codable

extension IdentifyPayload {
    enum CodingKeys: String, CodingKey {
        case token
        case properties
        case isCompressed = "compressed"
        case largeThreshold = "large_threshold"
        case shardInfo = "shard_info"
        case presence
        case intents
    }
}

extension IdentifyPayload: CustomStringConvertible {
    var description: String {
        var result = "[Token: \(token) || Intents: \(intents)"
        if let isCompressed = isCompressed {
            result += " || Compressed: \(isCompressed)"
        }
        if let largeThreshold = largeThreshold {
            result += " || Large Threshold: \(largeThreshold)"
        }
        if let shardInfo = shardInfo {
            result += " || Shard Info: ID-\(shardInfo[0]) COUNT-\(shardInfo[1])"
        }
        if let presence = presence {
            result += " || Presence: \(presence)"
        }
        result += "]"
        return result
    }
}

// MARK: - Properties

extension IdentifyPayload {
    
    /// Information about the connecting client.
    struct Properties: Codable, Hashable, Sendable {
        
        /// The operating system of the client.
        public let os: String
        
        /// The browser of the client.
        public let browser: String
        
        /// The device of the client.
        public let device: String
    }
}

extension IdentifyPayload.Properties: CustomStringConvertible {
    var description: String {
        "[\(browser)@\(device)-\(os)]"
    }
}
