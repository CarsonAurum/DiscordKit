//
//  Guild.swift
//  DiscordKit
//
//  Created by Carson Rau on 1/31/25.
//


import Foundation

public struct Guild: DiscordModel {
    public let id: Snowflake
    public let name: String?
    public let icon: String?
    public let iconHash: String?
    public let splash: String?
    public let discoverySplash: String?
    public let isOwner: Bool?
    public let ownerID: Snowflake?
    public let permissions: Permissions?
    public let afkChannelID: Snowflake?
    public let afkTimeout: Int?
    public let isWidgetEnabled: Bool?
    public let widgetChannelID: Snowflake?
    public let verificationLevel: VerificationLevel?
    public let defaultMessageNotifications: DefaultMessageNotificationLevel?
    public let explicitContentFilter: ExplicitContentFilter?
    public let roles: [Role]?
    public let emojis: [Emoji]?
    public let features: [Feature]?
    public let mfaLevel: MFALevel?
    public let applicationID: Snowflake?
    public let systemChannelID: Snowflake?
    public let systemChannelFlags: SystemChannelFlags?
    public let rulesChannelID: Snowflake?
    public let maxPresences: Int?
    public let maxMembers: Int?
    public let vanityURLCode: String?
    public let serverDescription: String?
    public let banner: String?
    public let boostTier: BoostTier?
    public let boostCount: Int?
    public let preferredLocale: Locale?
    public let publicUpdatesChannelID: Snowflake?
    public let maxVideoChannelUsers: Int?
    public let maxStageVideoChannelUsers: Int?
    public let approximateMemberCount: Int?
    public let approximatePresenceCount: Int?
    public let welcomeScreen: WelcomeScreen?
    public let nsfwLevel: NSFWLevel?
    public let stickers: [Sticker]?
    public let premiumProgressBarEnabled: Bool?
    public let safetyAlertsChannelID: Snowflake?
    
    // MARK: - GuildCreate
    public let joinedAt: Date?
    public let isLarge: Bool?
    public let isUnavailable: Bool?
    public let memberCount: Int?
    public let voiceStates: [VoiceState]?
    public let members: [Member]?
    public let channels: [Channel]?
    public let threads: [Channel]?
    public let presences: [Presence.Update]?
    public let stageInstances: [StageInstance]?
    public let guildScheduledEvents: [ScheduledEvent]?
    public let soundboardSounds: [SoundboardSound]?
}

extension Guild {
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case icon
        case iconHash = "icon_hash"
        case splash
        case discoverySplash = "discovery_splash"
        case isOwner = "owner"
        case ownerID = "owner_id"
        case permissions
        case afkChannelID = "afk_channel_id"
        case afkTimeout = "afk_timeout"
        case isWidgetEnabled = "widget_enabled"
        case widgetChannelID = "widget_channel_id"
        case verificationLevel = "verification_level"
        case defaultMessageNotifications = "default_message_notifications"
        case explicitContentFilter = "explicit_content_filter"
        case roles
        case emojis
        case features
        case mfaLevel = "mfa_level"
        case applicationID = "application_id"
        case systemChannelID = "system_channel_id"
        case systemChannelFlags = "system_channel_flags"
        case rulesChannelID = "rules_channel_id"
        case maxPresences = "max_presences"
        case maxMembers = "max_members"
        case vanityURLCode = "vanity_url_code"
        case serverDescription = "description"
        case banner
        case premiumTier = "premium_tier"
        case premiumSubscriptionCount = "premium_subscription_count"
        case preferredLocale = "preferred_locale"
        case publicUpdatesChannelID = "public_updates_channel_id"
        case maxVideoChannelUsers = "max_video_channel_users"
        case maxStageVideoChannelUsers = "max_stage_video_channel_users"
        case approximateMemberCount = "approximate_member_count"
        case approximatePresenceCount = "approximate_presence_count"
        case welcomeScreen = "welcome_screen"
        case nsfwLevel = "nsfw_level"
        case stickers
        case premiumProgressBarEnabled = "premium_progress_bar_enabled"
        case safetyAlertsChannelID = "safety_alerts_channel_id"
        
        case joinedAt = "joined_at"
        case isLarge = "large"
        case isUnavailable = "unavailable"
        case memberCount = "member_count"
        case voiceStates = "voice_states"
        case members
        case channels
        case threads
        case presences
        case stageInstances = "stage_instances"
        case guildScheduledEvents = "guild_scheduled_events"
        case soundboardSounds = "soundboard_sounds"
    }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        self.id = try container.decode(Snowflake.self, forKey: .id)
        self.name = try container.decodeIfPresent(String.self, forKey: .name)
        self.icon = try container.decodeIfPresent(String.self, forKey: .icon)
        self.iconHash = try container.decodeIfPresent(String.self, forKey: .iconHash)
        self.splash = try container.decodeIfPresent(String.self, forKey: .splash)
        self.discoverySplash = try container.decodeIfPresent(String.self, forKey: .discoverySplash)
        self.isOwner = try container.decodeIfPresent(Bool.self, forKey: .isOwner)
        self.ownerID = try container.decodeIfPresent(Snowflake.self, forKey: .ownerID)
        self.permissions = try container.decodeIfPresent(Permissions.self, forKey: .permissions)
        self.afkChannelID = try container.decodeIfPresent(Snowflake.self, forKey: .afkChannelID)
        self.afkTimeout = try container.decodeIfPresent(Int.self, forKey: .afkTimeout)
        self.isWidgetEnabled = try container.decodeIfPresent(Bool.self, forKey: .isWidgetEnabled)
        self.widgetChannelID = try container.decodeIfPresent(Snowflake.self, forKey: .widgetChannelID)
        self.verificationLevel = try container.decodeIfPresent(VerificationLevel.self, forKey: .verificationLevel)
        self.defaultMessageNotifications = try container.decodeIfPresent(DefaultMessageNotificationLevel.self, forKey: .defaultMessageNotifications)
        self.explicitContentFilter = try container.decodeIfPresent(ExplicitContentFilter.self, forKey: .explicitContentFilter)
        self.roles = try container.decodeIfPresent([Role].self, forKey: .roles)
        self.emojis = try container.decodeIfPresent([Emoji].self, forKey: .emojis)
        self.features = try container.decodeIfPresent([Feature].self, forKey: .features)
        self.mfaLevel = try container.decodeIfPresent(MFALevel.self, forKey: .mfaLevel)
        self.applicationID = try container.decodeIfPresent(Snowflake.self, forKey: .applicationID)
        self.systemChannelID = try container.decodeIfPresent(Snowflake.self, forKey: .systemChannelID)
        self.systemChannelFlags = try container.decodeIfPresent(SystemChannelFlags.self, forKey: .systemChannelFlags)
        self.rulesChannelID = try container.decodeIfPresent(Snowflake.self, forKey: .rulesChannelID)
        self.maxPresences = try container.decodeIfPresent(Int.self, forKey: .maxPresences)
        self.maxMembers = try container.decodeIfPresent(Int.self, forKey: .maxMembers)
        self.vanityURLCode = try container.decodeIfPresent(String.self, forKey: .vanityURLCode)
        self.serverDescription = try container.decodeIfPresent(String.self, forKey: .serverDescription)
        self.banner = try container.decodeIfPresent(String.self, forKey: .banner)
        self.boostTier = try container.decodeIfPresent(BoostTier.self, forKey: .premiumTier)
        self.boostCount = try container.decodeIfPresent(Int.self, forKey: .premiumSubscriptionCount)
        self.preferredLocale = try container.decodeIfPresent(Locale.self, forKey: .preferredLocale)
        self.publicUpdatesChannelID = try container.decodeIfPresent(Snowflake.self, forKey: .publicUpdatesChannelID)
        self.maxVideoChannelUsers = try container.decodeIfPresent(Int.self, forKey: .maxVideoChannelUsers)
        self.maxStageVideoChannelUsers = try container.decodeIfPresent(Int.self, forKey: .maxStageVideoChannelUsers)
        self.approximateMemberCount = try container.decodeIfPresent(Int.self, forKey: .approximateMemberCount)
        self.approximatePresenceCount = try container.decodeIfPresent(Int.self, forKey: .approximatePresenceCount)
        self.welcomeScreen = try container.decodeIfPresent(WelcomeScreen.self, forKey: .welcomeScreen)
        self.nsfwLevel = try container.decodeIfPresent(NSFWLevel.self, forKey: .nsfwLevel)
        self.stickers = try container.decodeIfPresent([Sticker].self, forKey: .stickers)
        self.premiumProgressBarEnabled = try container.decodeIfPresent(Bool.self, forKey: .premiumProgressBarEnabled)
        self.safetyAlertsChannelID = try container.decodeIfPresent(Snowflake.self, forKey: .safetyAlertsChannelID)
        
        // Decode joinedAt using ISO8601
        if let joinedAtString = try container.decodeIfPresent(String.self, forKey: .joinedAt) {
            let fmt = ISO8601DateFormatter()
            fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            self.joinedAt = fmt.date(from: joinedAtString)
        } else {
            self.joinedAt = nil
        }
        
        self.isLarge = try container.decodeIfPresent(Bool.self, forKey: .isLarge)
        self.isUnavailable = try container.decodeIfPresent(Bool.self, forKey: .isUnavailable)
        self.memberCount = try container.decodeIfPresent(Int.self, forKey: .memberCount)
        self.voiceStates = try container.decodeIfPresent([VoiceState].self, forKey: .voiceStates)
        self.members = try container.decodeIfPresent([Member].self, forKey: .members)
        self.channels = try container.decodeIfPresent([Channel].self, forKey: .channels)
        self.threads = try container.decodeIfPresent([Channel].self, forKey: .threads)
        self.presences = try container.decodeIfPresent([Presence.Update].self, forKey: .presences)
        self.stageInstances = try container.decodeIfPresent([StageInstance].self, forKey: .stageInstances)
        self.guildScheduledEvents = try container.decodeIfPresent([ScheduledEvent].self, forKey: .guildScheduledEvents)
        self.soundboardSounds = try container.decodeIfPresent([SoundboardSound].self, forKey: .soundboardSounds)
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(icon, forKey: .icon)
        try container.encodeIfPresent(iconHash, forKey: .iconHash)
        try container.encodeIfPresent(splash, forKey: .splash)
        try container.encodeIfPresent(discoverySplash, forKey: .discoverySplash)
        try container.encodeIfPresent(isOwner, forKey: .isOwner)
        try container.encodeIfPresent(ownerID, forKey: .ownerID)
        try container.encodeIfPresent(permissions, forKey: .permissions)
        try container.encodeIfPresent(afkChannelID, forKey: .afkChannelID)
        try container.encodeIfPresent(afkTimeout, forKey: .afkTimeout)
        try container.encodeIfPresent(isWidgetEnabled, forKey: .isWidgetEnabled)
        try container.encodeIfPresent(widgetChannelID, forKey: .widgetChannelID)
        try container.encodeIfPresent(verificationLevel, forKey: .verificationLevel)
        try container.encodeIfPresent(defaultMessageNotifications, forKey: .defaultMessageNotifications)
        try container.encodeIfPresent(explicitContentFilter, forKey: .explicitContentFilter)
        try container.encodeIfPresent(roles, forKey: .roles)
        try container.encodeIfPresent(emojis, forKey: .emojis)
        try container.encodeIfPresent(features, forKey: .features)
        try container.encodeIfPresent(mfaLevel, forKey: .mfaLevel)
        try container.encodeIfPresent(applicationID, forKey: .applicationID)
        try container.encodeIfPresent(systemChannelID, forKey: .systemChannelID)
        try container.encodeIfPresent(systemChannelFlags, forKey: .systemChannelFlags)
        try container.encodeIfPresent(rulesChannelID, forKey: .rulesChannelID)
        try container.encodeIfPresent(maxPresences, forKey: .maxPresences)
        try container.encodeIfPresent(maxMembers, forKey: .maxMembers)
        try container.encodeIfPresent(vanityURLCode, forKey: .vanityURLCode)
        try container.encodeIfPresent(serverDescription, forKey: .serverDescription)
        try container.encodeIfPresent(banner, forKey: .banner)
        try container.encodeIfPresent(boostTier, forKey: .premiumTier)
        try container.encodeIfPresent(boostCount, forKey: .premiumSubscriptionCount)
        try container.encodeIfPresent(preferredLocale, forKey: .preferredLocale)
        try container.encodeIfPresent(publicUpdatesChannelID, forKey: .publicUpdatesChannelID)
        try container.encodeIfPresent(maxVideoChannelUsers, forKey: .maxVideoChannelUsers)
        try container.encodeIfPresent(maxStageVideoChannelUsers, forKey: .maxStageVideoChannelUsers)
        try container.encodeIfPresent(approximateMemberCount, forKey: .approximateMemberCount)
        try container.encodeIfPresent(approximatePresenceCount, forKey: .approximatePresenceCount)
        try container.encodeIfPresent(welcomeScreen, forKey: .welcomeScreen)
        try container.encodeIfPresent(nsfwLevel, forKey: .nsfwLevel)
        try container.encodeIfPresent(stickers, forKey: .stickers)
        try container.encodeIfPresent(premiumProgressBarEnabled, forKey: .premiumProgressBarEnabled)
        try container.encodeIfPresent(safetyAlertsChannelID, forKey: .safetyAlertsChannelID)
        
        // Encode joinedAt as ISO8601 if present
        if let joinedAt = joinedAt {
            let dateString = ISO8601DateFormatter().string(from: joinedAt)
            try container.encode(dateString, forKey: .joinedAt)
        } else {
            try container.encodeNil(forKey: .joinedAt)
        }
        
        try container.encodeIfPresent(isLarge, forKey: .isLarge)
        try container.encodeIfPresent(isUnavailable, forKey: .isUnavailable)
        try container.encodeIfPresent(memberCount, forKey: .memberCount)
        try container.encodeIfPresent(voiceStates, forKey: .voiceStates)
        try container.encodeIfPresent(members, forKey: .members)
        try container.encodeIfPresent(channels, forKey: .channels)
        try container.encodeIfPresent(threads, forKey: .threads)
        try container.encodeIfPresent(presences, forKey: .presences)
        try container.encodeIfPresent(stageInstances, forKey: .stageInstances)
        try container.encodeIfPresent(guildScheduledEvents, forKey: .guildScheduledEvents)
        try container.encodeIfPresent(soundboardSounds, forKey: .soundboardSounds)
    }
}

extension Guild: CustomStringConvertible {
    public var description: String {
        var result = [String]()
        result.append("ID: \(id)")
        if let name = name { result.append("Name: \(name)") }
        if let icon = icon { result.append("Icon: \(icon)") }
        if let iconHash = iconHash { result.append("Icon (Template): \(iconHash)") }
        if let splash = splash { result.append("Splash: \(splash)") }
        if let discoverySplash = discoverySplash { result.append("Discovery Splash: \(discoverySplash)") }
        if let isOwner = isOwner { result.append("Is Owner: \(isOwner)") }
        if let ownerID = ownerID { result.append("Owner ID: \(ownerID)") }
        if let permissions = permissions { result.append("Permissions: \(permissions)") }
        if let afkChannelID = afkChannelID { result.append("AFK Channel ID: \(afkChannelID)") }
        if let afkTimeout = afkTimeout { result.append("AFK Timeout: \(afkTimeout)") }
        if let isWidgetEnabled = isWidgetEnabled { result.append("Is Widget Enabled: \(isWidgetEnabled)") }
        if let widgetChannelID = widgetChannelID { result.append("Widget Channel ID: \(widgetChannelID)") }
        if let verificationLevel = verificationLevel { result.append("Verification Level: \(verificationLevel)") }
        if let defaultMessageNotifications = defaultMessageNotifications {
            result.append("Default Message Notifications: \(defaultMessageNotifications)")
        }
        if let explicitContentFilter = explicitContentFilter {
            result.append("Explicit Content Filter: \(explicitContentFilter)")
        }
        if let roles = roles {
            if roles.count > 0 {
                var result2 = [String]()
                for role in roles { result2.append("\(role)") }
                result.append("\(roles.count) Roles: [\(result2.joined(separator: ", "))]")
            } else {
                result.append("0 Roles.")
            }
        }
        if let emojis = emojis {
            if emojis.count > 0 {
                var result2 = [String]()
                for emoji in emojis { result2.append("\(emoji)") }
                result.append("\(emojis.count) Emojis: [\(result2.joined(separator: ", "))]")
            } else {
                result.append("0 Emojis.")
            }
        }
        if let features = features {
            if features.count > 0 {
                var result2 = [String]()
                for feature in features { result2.append("\(feature)") }
                result.append("\(features.count) Features: [\(result2.joined(separator: ", "))]")
            } else {
                result.append("0 Features.")
            }
        }
        if let mfaLevel = mfaLevel { result.append("MFA Level: \(mfaLevel)") }
        if let applicationID = applicationID { result.append("Application ID: \(applicationID)") }
        if let systemChannelID = systemChannelID { result.append("System Channel ID: \(systemChannelID)") }
        if let systemChannelFlags = systemChannelFlags { result.append("System Channel Flags: \(systemChannelFlags)") }
        if let rulesChannelID = rulesChannelID { result.append("Rules Channel ID: \(rulesChannelID)") }
        if let maxPresences = maxPresences { result.append("Max Presences: \(maxPresences)") }
        if let maxMembers = maxMembers { result.append("Max Members: \(maxMembers)") }
        if let vanityURLCode = vanityURLCode { result.append("Vanity URL Code: \(vanityURLCode)") }
        if let serverDescription = serverDescription { result.append("Description: \(serverDescription)") }
        if let banner = banner { result.append("Banner: \(banner)") }
        if let boostTier = boostTier { result.append("Boost Tier: \(boostTier)") }
        if let boostCount = boostCount { result.append("Boost Count: \(boostCount)") }
        if let preferredLocale = preferredLocale { result.append("Preferred Locale: \(preferredLocale)") }
        if let publicUpdatesChannelID = publicUpdatesChannelID {
            result.append("Public Updates Channel ID: \(publicUpdatesChannelID)")
        }
        if let publicUpdatesChannelID = publicUpdatesChannelID {
            result.append("Public Updates Channel ID: \(publicUpdatesChannelID)")
        }
        if let maxVideoChannelUsers = maxVideoChannelUsers {
            result.append("Max Video Channel Users: \(maxVideoChannelUsers)")
        }
        if let maxStageVideoChannelUsers = maxStageVideoChannelUsers {
            result.append("Max Stage Video Channel Users: \(maxStageVideoChannelUsers)")
        }
        if let approximateMemberCount = approximateMemberCount {
            result.append("Approximate Member Count: \(approximateMemberCount)")
        }
        if let approximatePresenceCount = approximatePresenceCount {
            result.append("Approximate Presence Count: \(approximatePresenceCount)")
        }
        return "[\(result.joined(separator: " || "))]"
    }
}
