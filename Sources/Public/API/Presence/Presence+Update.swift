//
//  Presence+Update.swift
//  DiscordKit
//
//  Created by Carson Rau on 1/31/25.
//

// MARK: - Update

extension Presence {
    
    /// An event sent when a presence update occurs.
    public struct Update: DiscordModel {
        
        /// The user associated with this presence update.
        public let user: User
        
        /// The guild in which this event was detected.
        public let guildID: Snowflake?
        
        /// The new status.
        public let status: Status
        
        /// The new activities.
        public let activities: [Activity]
        
        /// The client status -- specifying which client was used.
        public let clientStatus: ClientStatus
    }
}

// MARK: Codable

extension Presence.Update {
    enum CodingKeys: String, CodingKey {
        case user
        case guildID = "guild_id"
        case status
        case activities
        case clientStatus = "client_status"
    }
}

// MARK: CustomStringConvertible

extension Presence.Update: CustomStringConvertible {
    public var description: String {
        var result = "[\(clientStatus) || "
        if activities.count > 0 {
            for activity in activities {
                result += "\(activity) "
            }
        } else {
            result += "No Activities "
        }
        result += "|| User: \(user) || Guild ID: \(guildID)]"
        return result
    }
}

// MARK: - ClientStatus

extension Presence.Update {
    
    /// The client status -- indicating which client is in use.
    public enum ClientStatus: DiscordModel {
        
        /// If the client is connected through a desktop connection, this will be filled.
        case desktop(Presence.Status)
        
        /// If the client is connected through a moblie connection, this will be filled.
        case mobile(Presence.Status)
        
        /// If the client is connected through a web connection, this will be filled.
        case web(Presence.Status)
        
        /// If no client is connected.
        case offline
    }
}

// MARK: Codable

extension Presence.Update.ClientStatus {
    enum CodingKeys: String, CodingKey {
        case desktop
        case mobile
        case web
    }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let status = try container.decodeIfPresent(Presence.Status.self, forKey: .desktop) {
            self = .desktop(status)
        } else if let status = try container.decodeIfPresent(Presence.Status.self, forKey: .mobile) {
            self = .mobile(status)
        } else if let status = try container.decodeIfPresent(Presence.Status.self, forKey: .web) {
            self = .web(status)
        } else {
            self = .offline
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
        case .offline:
            return
        }
    }
}

// MARK: CustomStringConvertible

extension Presence.Update.ClientStatus: CustomStringConvertible {
    public var description: String {
        switch self {
        case .desktop(let status):
            return "Desktop (\(status))"
        case .mobile(let status):
            return "Mobile (\(status))"
        case .web(let status):
            return "Web (\(status))"
        case .offline:
            return "Offline"
        }
    }
}
