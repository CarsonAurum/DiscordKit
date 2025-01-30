//
//  GatewayEvent.swift
//  DiscordKit
//
//  Created by Carson Rau on 1/30/25.
//

import Foundation
import AnyCodable

struct GatewayEvent<EventPayload>: DiscordModel
where EventPayload: DiscordModel {
    let opcode: Opcode
    let data: EventPayload
    let sequence: Int?
    let name: String?
    
    enum CodingKeys: String, CodingKey {
        case opcode = "op"
        case data = "d"
        case sequence = "s"
        case name = "t"
    }
}

extension GatewayEvent: CustomStringConvertible {
    var description: String {
        var result = "EVENT: \(opcode)"
        if opcode == .dispatch {
            result += " - \(name ?? "NO NAME")"
            if let sequence = sequence {
                result += " - \(sequence)"
            }
        }
        return result
    }
}


// MARK: - Opcode

extension GatewayEvent {
    enum Opcode: Int, DiscordModel {
        case dispatch = 0
        case heartbeat = 1
        case identify = 2
        case presenceUpdate = 3
        case voiceStateUpdate = 4
        case resume = 6
        case reconnect = 7
        case requestGuildMembers = 8
        case invalidSession = 9
        case hello = 10
        case heartbeatACK = 11
        case requestSoundboardSounds = 31
    }
}

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
