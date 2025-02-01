//
//  GatewayEvent+Opcode.swift
//  DiscordKit
//
//  Created by Carson Rau on 1/31/25.
//

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
