//
//  BotCommand.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/9/25.
//

import AnyCodable

public struct BotCommand: DiscordModel {
    public let name: String
    public let nameLocalizations: [Locale: String]?
    public let commandDescription: String?
    public let descriptionLocalizations: [Locale: String]?
    public let options: [ApplicationCommand.Option<AnyCodable>]
    public let defaultMemberPermissions: Permissions?
    public let type: ApplicationCommand.CommandType?
    public let isNSFW: Bool?
    
    public let onInteraction: (@Sendable (InteractionContext) async -> Void)
    
    public init(
        name: String,
        nameLocalizations: [Locale: String]? = nil,
        commandDescription: String? = nil,
        descriptionLocalizations: [Locale: String]? = nil,
        options: [ApplicationCommand.Option<AnyCodable>],
        defaultMemberPermissions: Permissions? = nil,
        type: ApplicationCommand.CommandType? = nil,
        isNSFW: Bool? = nil,
        onInteraction: @escaping @Sendable (InteractionContext) async -> Void
    ) {
        self.name = name
        self.nameLocalizations = nameLocalizations
        self.commandDescription = commandDescription
        self.descriptionLocalizations = descriptionLocalizations
        self.options = options
        self.defaultMemberPermissions = defaultMemberPermissions
        self.type = type
        self.isNSFW = isNSFW
        self.onInteraction = onInteraction
    }
}

extension BotCommand {
    // Define coding keys for all properties EXCEPT the closure.
    enum CodingKeys: String, CodingKey {
        case name
        case nameLocalizations = "name_localizations"
        case commandDescription = "description"
        case descriptionLocalizations = "description_localizations"
        case options
        case defaultMemberPermissions = "default_member_permissions"
        case type
        case isNSFW = "nsfw"
    }
    
    public func encode(to encoder: Encoder) throws {
        // Create a container using the defined CodingKeys.
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(nameLocalizations, forKey: .nameLocalizations)
        try container.encode(commandDescription, forKey: .commandDescription)
        try container.encode(descriptionLocalizations, forKey: .descriptionLocalizations)
        try container.encode(options, forKey: .options)
        try container.encode(defaultMemberPermissions, forKey: .defaultMemberPermissions)
        try container.encode(type, forKey: .type)
        try container.encode(isNSFW, forKey: .isNSFW)
        // Note: onInteraction is not encoded.
    }
    
    public init(from decoder: Decoder) throws {
        // Decode using the same keys.
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        nameLocalizations = try container.decodeIfPresent([Locale: String].self, forKey: .nameLocalizations)
        commandDescription = try container.decodeIfPresent(String.self, forKey: .commandDescription)
        descriptionLocalizations = try container.decodeIfPresent([Locale: String].self, forKey: .descriptionLocalizations)
        options = try container.decode([ApplicationCommand.Option<AnyCodable>].self, forKey: .options)
        defaultMemberPermissions = try container.decodeIfPresent(Permissions.self, forKey: .defaultMemberPermissions)
        type = try container.decodeIfPresent(ApplicationCommand.CommandType.self, forKey: .type)
        isNSFW = try container.decodeIfPresent(Bool.self, forKey: .isNSFW)
        
        // Since the closure was not encoded, we must provide a default (usually a dummy)
        // implementation. This can be adjusted based on your use-case.
        onInteraction = { _ in
            fatalError("BotCommand.onInteraction was not decoded. You must provide a closure when initializing.")
        }
    }
}

// MARK: - Hashable Conformance

extension BotCommand {
    public func hash(into hasher: inout Hasher) {
        // Combine only the codable properties.
        hasher.combine(name)
        hasher.combine(nameLocalizations)
        hasher.combine(commandDescription)
        hasher.combine(descriptionLocalizations)
        hasher.combine(options)
        hasher.combine(defaultMemberPermissions)
        hasher.combine(type)
        hasher.combine(isNSFW)
    }
    
    public static func == (lhs: BotCommand, rhs: BotCommand) -> Bool {
        // Compare only the properties that are encoded.
        return lhs.name == rhs.name &&
            lhs.nameLocalizations == rhs.nameLocalizations &&
            lhs.commandDescription == rhs.commandDescription &&
            lhs.descriptionLocalizations == rhs.descriptionLocalizations &&
            lhs.options == rhs.options &&
            lhs.defaultMemberPermissions == rhs.defaultMemberPermissions &&
            lhs.type == rhs.type &&
            lhs.isNSFW == rhs.isNSFW
    }
}

// MARK: - Sendable Conformance

extension BotCommand { }
