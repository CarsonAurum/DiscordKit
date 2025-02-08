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
        
        /// Lazy-load for an unavailable guild, guild becomes available, or user joined a new guild.
        case guildCreate
        
        /// Guild scheduled event was created.
        case guildScheduledEventCreate
        
        /// Guild scheduled event was deleted.
        case guildScheduledEventDelete
        
        /// Guild scheduled event was updated.
        case guildScheduledEventUpdate
        
        /// Not a dispatch event.
        case none
        
        /// Presence update event.
        case presenceUpdate
        
        /// The ready event.
        case ready
        
        case resumed
        
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
        case "GUILD_CREATE":                    self = .guildCreate
        case "GUILD_SCHEDULED_EVENT_CREATE":    self = .guildScheduledEventCreate
        case "GUILD_SCHEDULED_EVENT_DELETE":    self = .guildScheduledEventDelete
        case "GUILD_SCHEDULED_EVENT_UPDATE":    self = .guildScheduledEventUpdate
        case "PRESENCE_UPDATE":                 self = .presenceUpdate
        case "READY":                           self = .ready
        case "RESUMED":                         self = .resumed
        default:                                self = .unknown(rawValue)
        }
    }
    
    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .guildCreate:                  try container.encode("GUILD_CREATE")
        case .guildScheduledEventCreate:    try container.encode("GUILD_SCHEDULED_EVENT_CREATE")
        case .guildScheduledEventDelete:    try container.encode("GUILD_SCHEDULED_EVENT_DELETE")
        case .guildScheduledEventUpdate:    try container.encode("GUILD_SCHEDULED_EVENT_UPDATE")
        case .presenceUpdate:               try container.encode("PRESENCE_UPDATE")
        case .ready:                        try container.encode("READY")
        case .resumed:                      try container.encode("RESUMED")
        case .unknown(let value):           try container.encode(value)
        case .none:                         try container.encodeNil()
        }
        
    }
}

// MARK: CustomStringConvertible

extension GatewayEvent.Name: CustomStringConvertible {
    var description: String {
        switch self {
        case .guildCreate:                  return "GUILD_CREATE"
        case .guildScheduledEventCreate:    return "GUILD_SCHEDULED_EVENT_CREATE"
        case .guildScheduledEventDelete:    return "GUILD_SCHEDULED_EVENT_DELETE"
        case .guildScheduledEventUpdate:    return "GUILD_SCHEDULED_EVENT_UPDATE"
        case .presenceUpdate:               return "PRESENCE_UPDATE"
        case .ready:                        return "READY"
        case .resumed:                      return "RESUMED"
        case .unknown(let string):          return string.uppercased()
        case .none:                         return "NO_NAME"
        }
    }
}
