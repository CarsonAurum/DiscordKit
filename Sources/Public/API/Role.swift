//
//  Role.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/4/25.
//

/// Roles represent a set of permissions attached to a group of users.
///
/// Roles have names, colors, and can be "pinned" to the side bar, causing their members to be listed separately.
/// Roles can have separate permission profiles for the global context (guild) and channel context.
///
/// The `@everyone` role has the same ID as the guild it belongs to.
public struct Role: DiscordModel {
    /// Role ID
    public let id: Snowflake
    /// Role name
    public let name: String?
    /// The integer representation of hexadecimal color code
    public let color: Int?
    /// If this role is pinned in the user listing
    public let isPinned: Bool?
    /// The role icon hash
    public let icon: String?
    /// Role unicode emoji
    public let unicodeEmoji: String?
    /// Position of this role
    /// - Note: Roles with the same position are sorted by `id`
    public let position: Int?
    /// Permission bitset
    public let permissions: Permissions?
    /// Whether this role is managed by an integration
    public let isManaged: Bool?
    /// Whether this role is mentionable
    public let isMentionable: Bool?
    /// The tags this role has
    public let tags: Tags?
    /// Role flags combined as a bitfield
    public let flags: Flags?
    
    internal enum CodingKeys: String, CodingKey {
        case id
        case name
        case color
        case isPinned = "hoist"
        case icon
        case unicodeEmoji = "unicode_emoji"
        case position
        case permissions
        case isManaged = "managed"
        case isMentionable = "mentionable"
        case tags
        case flags
    }
}
// MARK: - Nested Types
extension Role {
    /// A collection of tags associated with a role.
    public struct Tags: Codable, Hashable, Sendable {
        /// The ID of the bot this role belongs to
        public let botID: Snowflake?
        /// The ID of the integration this role belongs to
        public let integrationID: Snowflake?
        /// Whether this is the guild's Booster role
        public let premiumSubscriber: Bool
        /// The ID of this role's subscription SKU and listing
        public let subscriptionListingID: Snowflake?
        /// Whether this role is available for purchase
        public let availableForPurchase: Bool
        /// Whether this role is a guild's linked role
        public let guildConnections: Bool
        
        internal enum CodingKeys: String, CodingKey {
            case botID = "bot_id"
            case integrationID = "integration_id"
            case premiumSubscriber = "premium_subscriber"
            case subscriptionListingID = "subscription_listing_id"
            case availableForPurchase = "available_for_purchase"
            case guildConnections = "guild_connections"
        }
        
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            
            botID = try container.decodeIfPresent(Snowflake.self, forKey: .botID)
            integrationID = try container.decodeIfPresent(Snowflake.self, forKey: .integrationID)
            subscriptionListingID = try container.decodeIfPresent(Snowflake.self, forKey: .subscriptionListingID)
            
            premiumSubscriber = container.contains(.premiumSubscriber)
            availableForPurchase = container.contains(.availableForPurchase)
            guildConnections = container.contains(.guildConnections)
        }
        
        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            
            try container.encodeIfPresent(botID, forKey: .botID)
            try container.encodeIfPresent(integrationID, forKey: .integrationID)
            try container.encodeIfPresent(subscriptionListingID, forKey: .subscriptionListingID)
            
            if premiumSubscriber { try container.encodeNil(forKey: .premiumSubscriber) }
            if availableForPurchase { try container.encodeNil(forKey: .availableForPurchase) }
            if guildConnections { try container.encodeNil(forKey: .guildConnections) }
        }
    }
    /// A bitset of flags associated with a role.
    public struct Flags: OptionSet, Codable, Hashable, Sendable {
        /// Role can be selected by members in an onboarding prompt.
        public static let inPrompt = Flags(rawValue: 1 << 0)
        /// The bitset value.
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
    }
}
