//
//  Presence+Activity.swift
//  DiscordKit
//
//  Created by Carson Rau on 1/31/25.
//

import Foundation

// MARK: - Presence.Activity

extension Presence {
    
    /// An object describing an activity within a rich presence.
    public struct Activity: DiscordModel {
        
        /// Activity's name
        public let name: String
        
        /// Activity type
        public let type: ActivityType
        
        /// Stream URL -- validated when ``ActivityType/streaming``
        public let url: String?
        
        /// When the activity was added to the user's session.
        public let createdAt: Date
        
        /// Timestamps for the start and end of a game.
        public let timestamps: Timestamps?
        
        /// Application ID for a game.
        public let applicationID: Snowflake?
        
        /// What the player is currently doing.
        public let details: String?
        
        /// User's current party status -- or text used for a custom status.
        public let state: String?
        
        /// Emoji used for a custom status.
        public let emoji: Emoji?
        
        /// Information for the party of the current player.
        public let party: Party?
        
        /// Images for the presence and their hover text.
        public let assets: Assets?
        
        /// Secrets for rich presence joining/spectating.
        public let secrets: Secrets?
        
        /// Whether or not the activity is an instanced game session.
        public let instance: Bool?
        
        /// Describes what the payload includes.
        public let flags: Flags?
        
        /// Custom buttons shown in the rich presence (max 2).
        public let buttons: [Button]?
    }
}

// MARK: Codable

extension Presence.Activity {
    enum CodingKeys: String, CodingKey {
        case name
        case type
        case url
        case createdAt = "created_at"
        case timestamps
        case applicationID = "application_id"
        case details
        case state
        case emoji
        case party
        case assets
        case secrets
        case instance
        case flags
        case buttons
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        self.name = try container.decode(String.self, forKey: .name)
        self.type = try container.decode(ActivityType.self, forKey: .type)
        self.url = try container.decodeIfPresent(String.self, forKey: .url)
        
        let createdAtTimestamp = try container.decode(Int.self, forKey: .createdAt)
        self.createdAt = Date(timeIntervalSince1970: Double(createdAtTimestamp) / 1000.0)
        
        self.timestamps = try container.decodeIfPresent(Presence.Activity.Timestamps.self, forKey: .timestamps)
        self.applicationID = try container.decodeIfPresent(Snowflake.self, forKey: .applicationID)
        self.details = try container.decodeIfPresent(String.self, forKey: .details)
        self.state = try container.decodeIfPresent(String.self, forKey: .state)
        self.emoji = try container.decodeIfPresent(Presence.Activity.Emoji.self, forKey: .emoji)
        self.party = try container.decodeIfPresent(Presence.Activity.Party.self, forKey: .party)
        self.assets = try container.decodeIfPresent(Presence.Activity.Assets.self, forKey: .assets)
        self.secrets = try container.decodeIfPresent(Presence.Activity.Secrets.self, forKey: .secrets)
        self.instance = try container.decodeIfPresent(Bool.self, forKey: .instance)
        self.flags = try container.decodeIfPresent(Presence.Activity.Flags.self, forKey: .flags)
        self.buttons = try container.decodeIfPresent([Presence.Activity.Button].self, forKey: .buttons)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(name, forKey: .name)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(url, forKey: .url)
        
        let createdAtTimestamp = Int(createdAt.timeIntervalSince1970 * 1000)
        try container.encode(createdAtTimestamp, forKey: .createdAt)
        
        try container.encodeIfPresent(timestamps, forKey: .timestamps)
        try container.encodeIfPresent(applicationID, forKey: .applicationID)
        try container.encodeIfPresent(details, forKey: .details)
        try container.encodeIfPresent(state, forKey: .state)
        try container.encodeIfPresent(emoji, forKey: .emoji)
        try container.encodeIfPresent(party, forKey: .party)
        try container.encodeIfPresent(assets, forKey: .assets)
        try container.encodeIfPresent(secrets, forKey: .secrets)
        try container.encodeIfPresent(instance, forKey: .instance)
        try container.encodeIfPresent(flags, forKey: .flags)
        try container.encodeIfPresent(buttons, forKey: .buttons)
    }
}

// MARK: - ActivityType

extension Presence.Activity {
    public enum ActivityType: Int, DiscordModel {
        case playing = 0
        case streaming = 1
        case listening = 2
        case watching = 3
        case custom = 4
        case competing = 5
    }
}

// MARK: - Timestamps

extension Presence.Activity {
    public struct Timestamps: DiscordModel {
        public let start: Date?
        public let end: Date?
    }
}

// MARK: Codable

extension Presence.Activity.Timestamps {
    
    enum CodingKeys: String, CodingKey {
        case start
        case end
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let startTimestamp = try container.decodeIfPresent(Int.self, forKey: .start) {
            self.start = Date(timeIntervalSince1970: Double(startTimestamp) / 1000.0)
        } else {
            self.start = nil
        }

        if let endTimestamp = try container.decodeIfPresent(Int.self, forKey: .end) {
            self.end = Date(timeIntervalSince1970: Double(endTimestamp) / 1000.0)
        } else {
            self.end = nil
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        if let start = start {
            try container.encode(Int(start.timeIntervalSince1970 * 1000), forKey: .start)
        }

        if let end = end {
            try container.encode(Int(end.timeIntervalSince1970 * 1000), forKey: .end)
        }
    }
}

// MARK: - Emoji

extension Presence.Activity {
    public struct Emoji: DiscordModel {
        public let name: String
        public let id: Snowflake?
        public let isAnimated: Bool?
    }
    
    public struct Party: DiscordModel {
        public let id: String
        public let size: [Int]?
    }
    
    public struct Assets: DiscordModel {
        public let largeImage: String?
        public let largeText: String?
        public let smallImage: String?
        public let smallText: String?
    }
    
    public struct Secrets: DiscordModel {
        public let join: String?
        public let spectate: String?
        public let match: String?
    }
    
    public struct Flags: OptionSet, DiscordModel {
        
        public static let instance = Flags(rawValue: 1 << 0)
        public static let join = Flags(rawValue: 1 << 1)
        public static let spectate = Flags(rawValue: 1 << 2)
        public static let joinRequest = Flags(rawValue: 1 << 3)
        public static let sync = Flags(rawValue: 1 << 4)
        public static let play = Flags(rawValue: 1 << 5)
        public static let partyPrivacyFriends = Flags(rawValue: 1 << 6)
        public static let partyPrivacyVoiceChannel = Flags(rawValue: 1 << 7)
        public static let embedded = Flags(rawValue: 1 << 8)
        
        public let rawValue: Int
        public init(rawValue: Int) {
            self.rawValue = rawValue
        }
    }
    
    public struct Button: DiscordModel {
        public let label: String
        public let url: String
    }
}
