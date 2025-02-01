//
//  Presence+Update.swift
//  DiscordKit
//
//  Created by Carson Rau on 1/31/25.
//

extension Presence {
    
    /// An event sent when a presence update occurs.
    public struct Update: DiscordModel {
        
        /// The user associated with this presence update.
        public let user: User
        
        /// The guild in which this event was detected.
        public let guildID: Snowflake
        
        /// The new status.
        public let status: Status
        
        /// The new activities.
        public let activities: [Activity]
        
        /// The client status -- specifying which client was used.
        public let clientStatus: ClientStatus
    }
}

// MARK: ClientStatus

extension Presence.Update {
    
    /// The client status -- indicating which client is in use.
    public enum ClientStatus: DiscordModel {
        
        /// If the client is connected through a desktop connection, this will be filled.
        case desktop(String)
        
        /// If the client is connected through a moblie connection, this will be filled.
        case mobile(String)
        
        /// If the client is connected through a web connection, this will be filled.
        case web(String)
    }
}

extension Presence.Update.ClientStatus {
    enum CodingKeys: String, CodingKey {
        case desktop
        case mobile
        case web
    }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let status = try container.decodeIfPresent(String.self, forKey: .desktop) {
            self = .desktop(status)
        } else if let status = try container.decodeIfPresent(String.self, forKey: .mobile) {
            self = .mobile(status)
        } else if let status = try container.decodeIfPresent(String.self, forKey: .web) {
            self = .web(status)
        } else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "No valid session status found")
            )
        }
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .desktop(let status):
            try container.encode(status, forKey: .desktop)
        case .mobile(let status):
            try container.encode(status, forKey: .mobile)
        case .web(let status):
            try container.encode(status, forKey: .web)
        }
    }
}
