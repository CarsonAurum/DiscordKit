//
//  IdentifyPayload.swift
//  DiscordKit
//
//  Created by Carson Rau on 1/31/25.
//

// MARK: - IdentifyPayload

struct IdentifyPayload: DiscordModel {
    let token: String
    let properties: Properties
    let isCompressed: Bool?
    let largeThreshold: Int?
    let shardInfo: [Int]?
    let presence: Presence?
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
        var result = "[Token: \(token) Intents: \(intents)"
        if let isCompressed = isCompressed {
            result += " Compressed: \(isCompressed)"
        }
        if let largeThreshold = largeThreshold {
            result += " Large Threshold: \(largeThreshold)"
        }
        if let shardInfo = shardInfo {
            result += " Shard Info: ID-\(shardInfo[0]) COUNT-\(shardInfo[1])"
        }
        if let presence = presence {
            result += " Presence: \(presence)"
        }
        result += "]"
        return result
    }
}

// MARK: - Properties

extension IdentifyPayload {
    struct Properties: Codable, Hashable, Sendable {
        public let os: String
        public let browser: String
        public let device: String
    }
}
