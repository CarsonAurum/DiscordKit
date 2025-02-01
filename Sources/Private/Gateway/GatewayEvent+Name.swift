//
//  GatewayEvent+Name.swift
//  DiscordKit
//
//  Created by Carson Rau on 1/31/25.
//

// MARK: - Name

extension GatewayEvent {
    
    /// A type-safe wrapper for the string name of dispatch events.
    enum Name: DiscordModel {
        
        /// The guild create event.
        case guildCreate
        
        /// Not a dispatch event.
        case none
        
        /// Presence update event.
        case presenceUpdate
        
        /// The ready event.
        case ready
        
        /// An unknown event.
        case unknown(String)
    }
}

// MARK: Codable

extension GatewayEvent.Name {
    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .none
            return
        }
        let rawValue = try container.decode(String.self)
        switch rawValue {
        case "GUILD_CREATE":    self = .guildCreate
        case "PRESENCE_UPDATE": self = .presenceUpdate
        case "READY":           self = .ready
        default:                self = .unknown(rawValue)
        }
    }
    
    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .guildCreate:          try container.encode("GUILD_CREATE")
        case .presenceUpdate:       try container.encode("PRESENCE_UPDATE")
        case .ready:                try container.encode("READY")
        case .unknown(let value):   try container.encode(value)
        case .none:                 try container.encodeNil()
        }
        
    }
}

// MARK: CustomStringConvertible

extension GatewayEvent.Name: CustomStringConvertible {
    var description: String {
        switch self {
        case .guildCreate:          return "GUILD_CREATE"
        case .presenceUpdate:       return "PRESENCE_UPDATE"
        case .ready:                return "READY"
        case .unknown(let string):  return string.uppercased()
        case .none:                 return "NO_NAME"
        }
    }
}
