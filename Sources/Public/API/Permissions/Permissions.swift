//
//  Permissions.swift
//  DiscordKit
//
//  Created by Carson Rau on 2/4/25.
//

public struct Permissions: OptionSet, DiscordModel {
    /// Allows creation of instant invites
    public static let createInstantInvite = Permissions(rawValue: 1 << 0)
    public static let kickMembers = Permissions(rawValue: 1 << 1)
    public static let banMembers = Permissions(rawValue: 1 << 2)
    public static let administrator = Permissions(rawValue: 1 << 3)
    public static let manageChannels = Permissions(rawValue: 1 << 4)
    public static let manageGuild = Permissions(rawValue: 1 << 5)
    public static let addReactions = Permissions(rawValue: 1 << 6)
    public static let viewAuditLog = Permissions(rawValue: 1 << 7)
    public static let prioritySpeaker = Permissions(rawValue: 1 << 8)
    public static let stream = Permissions(rawValue: 1 << 9)
    public static let viewChannel = Permissions(rawValue: 1 << 10)
    public static let sendMessages = Permissions(rawValue: 1 << 11)
    public static let sendTTSMessages = Permissions(rawValue: 1 << 12)
    public static let manageMessages = Permissions(rawValue: 1 << 13)
    public static let embedLinks = Permissions(rawValue: 1 << 14)
    public static let attachFiles = Permissions(rawValue: 1 << 15)
    public static let readMessageHistory = Permissions(rawValue: 1 << 16)
    public static let mentionEveryone = Permissions(rawValue: 1 << 17)
    public static let useExternalEmojis = Permissions(rawValue: 1 << 18)
    public static let viewGuildInsights = Permissions(rawValue: 1 << 19)
    public static let connect = Permissions(rawValue: 1 << 20)
    public static let speak = Permissions(rawValue: 1 << 21)
    public static let muteMembers = Permissions(rawValue: 1 << 22)
    public static let deafenMembers = Permissions(rawValue: 1 << 23)
    public static let moveMembers = Permissions(rawValue: 1 << 24)
    public static let useVAD = Permissions(rawValue: 1 << 25)
    public static let changeNickname = Permissions(rawValue: 1 << 26)
    public static let manageNickname = Permissions(rawValue: 1 << 27)
    public static let manageRoles = Permissions(rawValue: 1 << 28)
    public static let manageWebhooks = Permissions(rawValue: 1 << 29)
    public static let manageGuildExpressions = Permissions(rawValue: 1 << 30)
    public static let useApplicationCommands = Permissions(rawValue: 1 << 31)
    public static let requestToSpeak = Permissions(rawValue: 1 << 32)
    public static let manageEvents = Permissions(rawValue: 1 << 33)
    public static let manageThreads = Permissions(rawValue: 1 << 34)
    public static let createPublicThreads = Permissions(rawValue: 1 << 35)
    public static let createPrivateThreads = Permissions(rawValue: 1 << 36)
    public static let useExternalStickers = Permissions(rawValue: 1 << 37)
    public static let sendMessagesInThreads = Permissions(rawValue: 1 << 38)
    public static let useEmbeddedActivities = Permissions(rawValue: 1 << 39)
    public static let moderateMembers = Permissions(rawValue: 1 << 40)
    public static let viewCreatorMonetizationAnalytics = Permissions(rawValue: 1 << 41)
    public static let useSoundboard = Permissions(rawValue: 1 << 42)
    public static let createGuildExpressions = Permissions(rawValue: 1 << 43)
    public static let createEvents = Permissions(rawValue: 1 << 44)
    public static let useExternalSounds = Permissions(rawValue: 1 << 45)
    public static let sendVoiceMessages = Permissions(rawValue: 1 << 46)
    public static let sendPolls = Permissions(rawValue: 1 << 49)
    public static let useExternalApps = Permissions(rawValue: 1 << 50)
    
    public let rawValue: UInt64
    public init(rawValue: UInt64) {
        self.rawValue = rawValue
    }
    
    public init(from decoder: Decoder) throws {
         let container = try decoder.singleValueContainer()
         let rawString = try container.decode(String.self)
         guard let value = UInt64(rawString) else {
             throw DecodingError.dataCorruptedError(
                 in: container,
                 debugDescription: "Invalid raw value for Permission: \(rawString)"
             )
         }
         self.init(rawValue: value)
     }
     
     public func encode(to encoder: Encoder) throws {
         var container = encoder.singleValueContainer()
         try container.encode(String(rawValue))
     }
}

extension Permissions: CustomStringConvertible {
    public var description: String {
        var activePermissions = [String]()
        if contains(.createInstantInvite) { activePermissions.append("Create Instant Invite") }
        if contains(.kickMembers) { activePermissions.append("Kick Members") }
        if contains(.banMembers) { activePermissions.append("Ban Members") }
        if contains(.administrator) { activePermissions.append("Administrator") }
        if contains(.manageChannels) { activePermissions.append("Manage Channels") }
        if contains(.manageGuild) { activePermissions.append("Manage Guild") }
        if contains(.addReactions) { activePermissions.append("Add Reactions") }
        if contains(.viewAuditLog) { activePermissions.append("View Audit Log") }
        if contains(.prioritySpeaker) { activePermissions.append("Priority Speaker") }
        if contains(.stream) { activePermissions.append("Stream") }
        if contains(.viewChannel) { activePermissions.append("View Channel") }
        if contains(.sendMessages) { activePermissions.append("Send Messages") }
        if contains(.sendTTSMessages) { activePermissions.append("Send TTS Messages") }
        if contains(.manageMessages) { activePermissions.append("Manage Messages") }
        if contains(.embedLinks) { activePermissions.append("Embed Links") }
        if contains(.attachFiles) { activePermissions.append("Attach Files") }
        if contains(.readMessageHistory) { activePermissions.append("Read Message History") }
        if contains(.mentionEveryone) { activePermissions.append("Mention Everyone") }
        if contains(.useExternalEmojis) { activePermissions.append("Use External Emojis") }
        if contains(.viewGuildInsights) { activePermissions.append("View Guild Insights") }
        if contains(.connect) { activePermissions.append("Connect") }
        if contains(.speak) { activePermissions.append("Speak") }
        if contains(.muteMembers) { activePermissions.append("Mute Members") }
        if contains(.deafenMembers) { activePermissions.append("Deafen Members") }
        if contains(.moveMembers) { activePermissions.append("Move Members") }
        if contains(.useVAD) { activePermissions.append("Use VAD") }
        if contains(.changeNickname) { activePermissions.append("Change Nickname") }
        if contains(.manageNickname) { activePermissions.append("Manage Nicknmae") }
        if contains(.manageRoles) { activePermissions.append("Manage Roles") }
        if contains(.manageWebhooks) { activePermissions.append("Manage Webhooks") }
        if contains(.manageGuildExpressions) { activePermissions.append("Manage Guild Expressions") }
        if contains(.useApplicationCommands) { activePermissions.append("Use Application Commands") }
        if contains(.requestToSpeak) { activePermissions.append("Request to Speak") }
        if contains(.manageEvents) { activePermissions.append("Manage Events") }
        if contains(.manageThreads) { activePermissions.append("Manage Threads") }
        if contains(.createPublicThreads) { activePermissions.append("Create Public Threads") }
        if contains(.createPrivateThreads) { activePermissions.append("Create Private Threads") }
        if contains(.useExternalStickers) { activePermissions.append("Use External Stickers") }
        if contains(.sendMessagesInThreads) { activePermissions.append("Send Messages in Threads") }
        if contains(.useEmbeddedActivities) { activePermissions.append("Use Embedded Activities") }
        if contains(.moderateMembers) { activePermissions.append("Moderate Members") }
        if contains(.viewCreatorMonetizationAnalytics) {
            activePermissions.append("View Creator Monetization Analytics")
        }
        if contains(.useSoundboard) { activePermissions.append("Use Soundboard") }
        if contains(.createGuildExpressions) { activePermissions.append("Create Guild Expressions") }
        if contains(.createEvents) { activePermissions.append("Create Events") }
        if contains(.useExternalSounds) { activePermissions.append("Use External Sounds") }
        if contains(.sendVoiceMessages) { activePermissions.append("Send Voice Messages") }
        if contains(.sendPolls) { activePermissions.append("Send Polls") }
        if contains(.useExternalApps) { activePermissions.append("Use External Apps") }

        return "\(activePermissions.joined(separator: ", "))"
    }
}

extension Permissions {
    public struct Overwrite: DiscordModel {
        public let id: Snowflake
        public let type: OverwriteType
        public let allow: Permissions
        public let deny: Permissions
        
        public enum OverwriteType: Int, DiscordModel {
            case role = 0
            case member = 1
        }
    }
}
