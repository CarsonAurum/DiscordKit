//
//  Component.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/11/25.
//

import NovaMacros

public indirect enum Component: DiscordModel {
    case actionRow(Component.ActionRow)
    case button(Component.Button)
    case stringSelect(Component.StringSelect)
    case textInput(Component.TextInput)
    case userSelect(Component.UserSelect)
    case roleSelect(Component.RoleSelect)
    case mentionableSelect(Component.MentionableSelect)
    case channelSelect(Component.ChannelSelect)
    case section(Component.Section)
    case textDisplay(Component.TextDisplay)
    case thumbnail(Component.Thumbnail)
    case mediaGallery(Component.MediaGallery)
    case file(Component.File)
    case separator(Component.Separator)
    case container
}

extension Component {
    
    @CodingKeys(.all)
    internal struct RawComponent: Codable, Hashable, Sendable {
        public let type: Int
    }
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: RawComponent.CodingKeys.self)
        let componentType = try container.decode(Int.self, forKey: .type)
        switch componentType {
        case 1:     self = .actionRow(try .init(from: decoder))
        case 2:     self = .button(try .init(from: decoder))
        case 3:     self = .stringSelect(try .init(from: decoder))
        case 4:     self = .textInput(try .init(from: decoder))
        case 5:     self = .userSelect(try .init(from: decoder))
        case 6:     self = .roleSelect(try .init(from: decoder))
        case 7:     self = .mentionableSelect(try .init(from: decoder))
        case 8:     self = .channelSelect(try .init(from: decoder))
        case 9:     self = .section(try .init(from: decoder))
        case 10:    self = .textDisplay(try .init(from: decoder))
        case 11:    self = .thumbnail(try .init(from: decoder))
        case 12:    self = .mediaGallery(try .init(from: decoder))
        case 13:    self = .file(try .init(from: decoder))
        case 14:    self = .separator(try .init(from: decoder))
        case 17:    self = .container
        default:    fatalError("Unexpected component type encountered") // TODO: Be more graceful
        }
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: RawComponent.CodingKeys.self)
        switch self {
        case .actionRow(let value):
            try container.encode(1, forKey: .type)
            try value.encode(to: encoder)
        case .button(let value):
            try container.encode(2, forKey: .type)
            try value.encode(to: encoder)
        case .stringSelect(let value):
            try container.encode(3, forKey: .type)
            try value.encode(to: encoder)
        case .textInput(let value):
            try container.encode(4, forKey: .type)
            try value.encode(to: encoder)
        case .userSelect(let value):
            try container.encode(5, forKey: .type)
            try value.encode(to: encoder)
        case .roleSelect(let value):
            try container.encode(6, forKey: .type)
            try value.encode(to: encoder)
        case .mentionableSelect(let value):
            try container.encode(7, forKey: .type)
            try value.encode(to: encoder)
        case .channelSelect(let value):
            try container.encode(8, forKey: .type)
            try value.encode(to: encoder)
        case .section(let value):
            try container.encode(9, forKey: .type)
            try value.encode(to: encoder)
        case .textDisplay(let value):
            try container.encode(10, forKey: .type)
            try value.encode(to: encoder)
        case .thumbnail(let value):
            try container.encode(11, forKey: .type)
            try value.encode(to: encoder)
        case .mediaGallery(let value):
            try container.encode(12, forKey: .type)
            try value.encode(to: encoder)
        case .file(let value):
            try container.encode(13, forKey: .type)
            try value.encode(to: encoder)
        case .separator(let value):
            try container.encode(14, forKey: .type)
            try value.encode(to: encoder)
        case .container:
            try container.encode(17, forKey: .type)
        }
    }
}
