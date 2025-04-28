//
//  Box.swift
//  DiscordKit
//
//  Created by Carson Rau on 4/28/25.
//

/// Box wrapper to break recursive struct cycles for Codable
public final class Box<T>: DiscordModel where T: Codable, T: Hashable, T: Sendable {
    let value: T
    init(_ value: T) { self.value = value }
    public required init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.value = try container.decode(T.self)
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(self.value)
    }
    public func hash(into hasher: inout Hasher) {
        self.value.hash(into: &hasher)
    }
    public static func == (lhs: Box<T>, rhs: Box<T>) -> Bool {
        return lhs.value == rhs.value
    }
}
