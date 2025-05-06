//
//  Component+SelectDefaultValue.swift
//  DiscordKit
//
//  Created by Carson Rau on 5/5/25.
//

extension Component {
    public enum SelectDefaultValue: DiscordModel {
        case user(Snowflake)
        case role(Snowflake)
        case channel(Snowflake)
    }
}

extension Component.SelectDefaultValue {
    enum CodingKeys: String, CodingKey {
        case id
        case type
    }
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .type) {
        case "user":
            self = .user(try container.decode(Snowflake.self, forKey: .id))
        case "role":
            self = .role(try container.decode(Snowflake.self, forKey: .id))
        case "channel":
            self = .channel(try container.decode(Snowflake.self, forKey: .id))
        default:
            fatalError() // TODO: Be more graceful
        }
    }
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .user(let id):
            try container.encode(id, forKey: .id)
            try container.encode("user", forKey: .type)
        case .role(let id):
            try container.encode(id, forKey: .id)
            try container.encode("role", forKey: .type)
        case .channel(let id):
            try container.encode(id, forKey: .id)
            try container.encode("channel", forKey: .type)
        }
    }
}
