//
//  Snowflake.swift
//  DiscordKit
//
//  Created by Carson Rau on 1/30/25.
//

// MARK: - Snowflake

/// A unique identifier.
public struct Snowflake: DiscordModel {
    
    /// A zero snowflake value.
    public static let zero = Snowflake(value: 0)
    
    /// The raw snowflake value.
    public let value: UInt64
}

// MARK: Codable

extension Snowflake {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let stringValue = try container.decode(String.self)
        
        guard let value = UInt64(stringValue) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ID Format.")
        }
        self.value = value
    }
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(String(value))
    }
}
