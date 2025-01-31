//
//  GatewayEvent.swift
//  DiscordKit
//
//  Created by Carson Rau on 1/30/25.
//

import Foundation
import AnyCodable

// MARK: - GatewayEvent

/// An event received from/sent to Discord's gateway.
struct GatewayEvent<EventPayload>: DiscordModel
where EventPayload: DiscordModel {
    
    /// The opcode of the event.
    let opcode: Opcode
    
    /// Event payload.
    let data: EventPayload
    
    /// A sequence number used when ordering dispatch events.
    let sequence: Int?
    
    /// A title used to identify dispatch event types.
    let name: Name
    
    /// Construct a new gateway event.
    /// - Parameters:
    ///   - opcode: The opcode of the event.
    ///   - data: Event payload.
    init(opcode: Opcode, data: EventPayload) {
        self.opcode = opcode
        self.data = data
        self.sequence = nil
        self.name = .none
    }
}

// MARK: GatewayEvent+getData()

extension GatewayEvent where EventPayload == AnyCodable {
    
    /// Access the raw data from a gateway event that has codable JSON data.
    /// - Returns: The parsed JSON data.
    func getData() throws -> Data {
        try JSONSerialization.data(withJSONObject: data.value)
    }
}

// MARK: Codable

extension GatewayEvent {
    enum CodingKeys: String, CodingKey {
        case opcode = "op"
        case data = "d"
        case sequence = "s"
        case name = "t"
    }
}

// MARK: CustomStringConvertible

extension GatewayEvent: CustomStringConvertible {
    var description: String {
        var result = "EVENT: \(opcode)"
        if opcode == .dispatch {
            result += " - \(name)"
            if let sequence = sequence {
                result += " - \(sequence)"
            }
        }
        return result
    }
}

// MARK: - Opcode

extension GatewayEvent {
    
    /// A numeric identifier to determine event type.
    enum Opcode: Int, DiscordModel {
        
        /// An event was dispatched.
        case dispatch = 0
        
        /// Fired periodically by the client to keep the connection alive.
        case heartbeat = 1
        
        /// Starts a new session during the initial handshake.
        case identify = 2
        
        /// Update the client's presence.
        case presenceUpdate = 3
        
        /// Used to join/leave or move between voice channels.
        case voiceStateUpdate = 4
        
        /// Resume a previous session that was disconnected.
        case resume = 6
        
        /// You should attempt to reconnect and resume immediately.
        case reconnect = 7
        
        /// Request information about offline guild members in a large guild.
        case requestGuildMembers = 8
        
        /// The session has been invalidated. You should reconnect and identify/resume accordingly.
        case invalidSession = 9
        
        /// Sent immediately after connecting, contains the heartbeat interval to use.
        case hello = 10
        
        /// Sent in response to receiving a heartbeat to acknowledge that it has been received.
        case heartbeatACK = 11
        
        /// Request information about soundboard sounds in a set of guilds.
        case requestSoundboardSounds = 31
    }
}

// MARK: CustomStringConvertible

extension GatewayEvent.Opcode: CustomStringConvertible {
    var description: String {
        switch self {
        case .dispatch:                 return "Dispatch"
        case .heartbeat:                return "Heartbeat"
        case .identify:                 return "Identify"
        case .presenceUpdate:           return "Presence Update"
        case .voiceStateUpdate:         return "Voice State Update"
        case .resume:                   return "Resume"
        case .reconnect:                return "Reconnect"
        case .requestGuildMembers:      return "Request Guild Members"
        case .invalidSession:           return "Invalid Session"
        case .hello:                    return "Hello"
        case .heartbeatACK:             return "Heartbeat ACK"
        case .requestSoundboardSounds:  return "Request Soundboard Sounds"
        }
    }
}

// MARK: - Name

extension GatewayEvent {
    
    /// A type-safe wrapper for the string name of dispatch events.
    enum Name: DiscordModel {
        
        /// The hello event.
        case hello
        
        /// The ready event.
        case ready
        
        /// The guild create event.
        case guildCreate
        
        /// An unknown event.
        case unknown(String)
        
        /// Not a dispatch event.
        case none
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
        case "hello":           self = .hello
        case "ready":           self = .ready
        case "guild_create":    self = .guildCreate
        default:                self = .unknown(rawValue)
        }
    }
    
    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .hello:                try container.encode("hello")
        case .ready:                try container.encode("ready")
        case .guildCreate:          try container.encode("guild_create")
        case .unknown(let value):   try container.encode(value)
        case .none:                 try container.encodeNil()
        }
        
    }
}

// MARK: CustomStringConvertible

extension GatewayEvent.Name: CustomStringConvertible {
    var description: String {
        switch self {
        case .hello:                return "HELLO"
        case .ready:                return "READY"
        case .guildCreate:          return "GUILD_CREATE"
        case .unknown(let string):  return string.uppercased()
        case .none:                 return "NO_NAME"
        }
    }
}
