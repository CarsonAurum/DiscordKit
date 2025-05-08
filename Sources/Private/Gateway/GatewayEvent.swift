//
//  GatewayEvent.swift
//  DiscordKit
//
//  Created by Carson Rau on 1/30/25.
//

import Foundation
import AnyCodable
import NovaMacros

// MARK: - GatewayEvent

/// An event received from/sent to Discord's gateway.
@CodingKeys(.custom([
    "opcode": "op",
    "data": "d",
    "sequence": "s",
    "name": "t"
]))
struct GatewayEvent<EventPayload>: Codable, Hashable, Sendable
where EventPayload: Codable, EventPayload: Hashable, EventPayload: Sendable {
    
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
        try JSONEncoder().encode(data)
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
