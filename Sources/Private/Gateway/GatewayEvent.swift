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
