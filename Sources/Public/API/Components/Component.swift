//
//  Component.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/11/25.
//

public enum Component: DiscordModel {
    case actionRow(Component.ActionRow)
    case button(Component.Button)
    case stringSelect(Component.StringSelect)
    case textInput
    case userSelect
    case roleSelect
    case mentionableSelect
    case channelSelect
    case section
    case textDisplay
    case thumbnail
    case mediaGallery
    case file
    case separator
    case container
}

extension Component {
    internal struct RawComponent: DiscordModel {
        public let type: Int
        
        enum CodingKeys: String, CodingKey {
            case type
        }
    }
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: RawComponent.CodingKeys.self)
        let componentType = try container.decode(Int.self, forKey: .type)
        switch componentType {
        case 1:     self = .actionRow(try .init(from: decoder))
        case 2:     self = .button(try .init(from: decoder))
        case 3:     self = .stringSelect(try .init(from: decoder))
        case 4:     self = .textInput
        case 5:     self = .userSelect
        case 6:     self = .roleSelect
        case 7:     self = .mentionableSelect
        case 8:     self = .channelSelect
        case 9:     self = .section
        case 10:    self = .textDisplay
        case 11:    self = .thumbnail
        case 12:    self = .mediaGallery
        case 13:    self = .file
        case 14:    self = .separator
        case 17:    self = .container
        default:    fatalError("Unexpected component type encountered") // TODO: Be more graceful
        }
    }
}
