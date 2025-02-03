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

extension Presence.Activity: CustomStringConvertible {
    public var description: String {
        var values = [String]()
        switch type {
        case .playing:
            values.append("\(type) \(name)")
        case .streaming:
            if let details = details {
                values.append("\(type) \(details)")
            } else {
                values.append("\(type)")
            }
        case .listening:
            values.append("\(type) \(name)")
        case .watching:
            values.append("\(type) \(name)")
        case .custom:
            if let emoji = emoji, let state = state {
                values.append("Custom: \(emoji) \(state)")
            } else if let state = state {
                values.append("Custom: \(state)")
            } else if let emoji = emoji {
                values.append("Custom: \(emoji)")
            }
        case .competing:
            values.append("\(type) \(name)")
        }
        if let url = url { values.append(url) }
        values.append("\(createdAt)")
        if let timestamps = timestamps {
            values.append("\(timestamps)")
        }
        if let details = details { values.append("Details: \(details)") }
        if let state = state { values.append("State: \(state)") }
        if let emoji = emoji { values.append("Emoji: \(emoji)") }
        if let party = party { values.append("Party: \(party)") }
        if let assets = assets { values.append("Assets: \(assets)") }
        if let secrets = secrets { values.append("Secrets: \(secrets)") }
        if let instance = instance { values.append("Is Instanced: \(instance)") }
        if let flags = flags { values.append("Flags: \(flags)") }
        if let buttons = buttons {
            var result = "Buttons: ["
            for button in buttons {
                result += "\(button)"
            }
            result += "]"
            values.append(result)
        }
        
        return "[\(values.joined(separator: " || "))]"
    }
}

// MARK: - ActivityType

extension Presence.Activity {
    
    /// The kind of activity being used.
    public enum ActivityType: Int, DiscordModel {
        
        /// Playing a game.
        case playing = 0
        
        /// Streaming a video.
        case streaming = 1
        
        /// Listening to content.
        case listening = 2
        
        /// Watching content.
        case watching = 3
        
        /// Custom status
        case custom = 4
        
        /// Competing in competition.
        case competing = 5
    }
}

// MARK: CustomStringConvertible

extension Presence.Activity.ActivityType: CustomStringConvertible {
    public var description: String {
        switch self {
        case .playing:
            return "Playing"
        case .streaming:
            return "Streaming"
        case .listening:
            return "Listening to"
        case .watching:
            return "Watching"
        case .custom:
            return ""
        case .competing:
            return "Competing in"
        }
    }
}

// MARK: - Timestamps

extension Presence.Activity {
    
    /// Information regarding the start and end of an activity.
    public struct Timestamps: DiscordModel {
        
        /// The start of the current activity.
        public let start: Date?
        
        /// The end of the current activity.
        public let end: Date?
    }
}

// MARK: CustomStringConvertible

extension Presence.Activity.Timestamps: CustomStringConvertible {
    public var description: String {
        var result = "["
        if let start = start {
            result += "Starting: \(start)"
        }
        if let end = end {
            result += " Ending: \(end)"
        }
        result += "]"
        return result
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
    
    /// An emoji used in a custom presence.
    public struct Emoji: DiscordModel {
        
        /// The name of the custom emoji.
        public let name: String
        
        /// The ID of the custom emoji
        public let id: Snowflake?
        
        /// `true` if this is an animated emoji, `false` otherwise.
        public let isAnimated: Bool?
    }
}

extension Presence.Activity.Emoji: CustomStringConvertible {
    public var description: String {
        var result = "[\(name)"
        if let id = id {
            result += " || \(id)"
        }
        if let isAnimated = isAnimated {
            result += " || Animated: \(isAnimated)"
        }
        result += "]"
        return result
    }
}

// MARK: - Party

extension Presence.Activity {
    
    /// Information about the party the activity occurs in.
    public struct Party: DiscordModel {
        
        /// The ID of the party.
        public let id: String?
        
        /// Size information
        public let size: [Int]?
    }
}

// MARK: CustomStringConvertible

extension Presence.Activity.Party: CustomStringConvertible {
    public var description: String {
        var result = "["
        if let id = id {
            result += "\(id)"
        }
        if let size = size {
            result += " || Current Size: \(size[0]) Max Size: \(size[1])"
        }
        result += "]"
        return result
    }
}

// MARK: - Assets

extension Presence.Activity {
    
    /// Information regarding the image assets attached to this activity.
    public struct Assets: DiscordModel {
        
        /// The large image ID.
        public let largeImage: String?
        
        /// The large image hover text.
        public let largeText: String?
        
        /// The small image ID.
        public let smallImage: String?
        
        /// The small image hover text
        public let smallText: String?
    }
}

// MARK: Codable

extension Presence.Activity.Assets {
    enum CodingKeys: String, CodingKey {
        case largeImage = "large_image"
        case largeText = "large_text"
        case smallImage = "small_image"
        case smallText = "small_text"
    }
}

// MARK: CustomStringConvertible

extension Presence.Activity.Assets: CustomStringConvertible {
    public var description: String {
        var result = "["
        if let largeImage = largeImage {
            result += "Large Image: \(largeImage)"
        }
        if let largeText = largeText {
            result += ", Large Text: \(largeText)"
        }
        if let smallImage = smallImage {
            if largeImage.isSome { result += " || " }
            result += "Small Image: \(smallImage)"
        }
        if let smallText = smallText {
            result += ", Small Text: \(smallText)"
        }
        result += "]"
        return result
    }
}

// MARK: - Secrets

extension Presence.Activity {
    
    /// Secrets for joining a rich activity.
    public struct Secrets: DiscordModel {
        
        /// Secret for joining a party.
        public let join: String?
        
        /// Secret for spectating a game.
        public let spectate: String?
        
        /// Secret for a specific instanced game match.
        public let match: String?
    }
}

extension Presence.Activity.Secrets: CustomStringConvertible {
    public var description: String {
        var values = [String]()
        if let join = join { values.append("Join: \(join)") }
        if let spectate = spectate { values.append("Spectate: \(spectate)") }
        if let match = match { values.append("Match: \(match)") }
        return "[\(values.joined(separator: " || "))]"
    }
}

// MARK: - Flags
 
extension Presence.Activity {
    
    /// Flags indicating what values are within the payload.
    public struct Flags: OptionSet, DiscordModel {
        
        /// An instanced activity.
        public static let instance = Flags(rawValue: 1 << 0)
        
        /// A joinable activity.
        public static let join = Flags(rawValue: 1 << 1)
        
        /// A spectatable activity.
        public static let spectate = Flags(rawValue: 1 << 2)
        
        /// A request to join another activity.
        public static let joinRequest = Flags(rawValue: 1 << 3)
        
        /// A sync update between activities.
        public static let sync = Flags(rawValue: 1 << 4)
        
        /// A game activity.
        public static let play = Flags(rawValue: 1 << 5)
        
        /// A party with the friends privacy setting.
        public static let partyPrivacyFriends = Flags(rawValue: 1 << 6)
        
        /// A party with the voice channel privacy setting.
        public static let partyPrivacyVoiceChannel = Flags(rawValue: 1 << 7)
        
        /// An embedded activity
        public static let embedded = Flags(rawValue: 1 << 8)
        
        public let rawValue: Int
        public init(rawValue: Int) {
            self.rawValue = rawValue
        }
    }
}

extension Presence.Activity.Flags: CustomStringConvertible {
    public var description: String {
        var cases = [String]()
        if contains(.instance) { cases.append("Instance") }
        if contains (.join) { cases.append("Join") }
        if contains (.spectate) { cases.append("Spectate") }
        if contains (.joinRequest) { cases.append("JoinRequest") }
        if contains (.sync) { cases.append("Sync") }
        if contains (.play) { cases.append("Play") }
        if contains (.partyPrivacyFriends) { cases.append("PartyPrivacyFriends") }
        if contains (.partyPrivacyVoiceChannel) { cases.append("PartyPrivacyVoiceChannel") }
        if contains (.embedded) { cases.append("Embedded") }
        return "[\(cases.joined(separator: ", "))]"
    }
}

// MARK: - Button

extension Presence.Activity {
    
    /// A button within a rich presence activity.
    public struct Button: DiscordModel {
        
        /// The label associated with the button.
        public let label: String
        
        /// The url to be routed when the button is clicked.
        public let url: String
    }
}

extension Presence.Activity.Button: CustomStringConvertible {
    public var description: String {
        "[Label: \(url) || URL: \(url)]"
    }
}
