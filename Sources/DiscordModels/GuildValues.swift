import DiscordCore
import Foundation

/// Type marker separating GuildIntegration snowflakes from other identifiers.
public enum GuildIntegrationTag: Sendable {}
/// Exact unsigned 64-bit GuildIntegration identifier, encoded as a decimal string.
public typealias GuildIntegrationID = Snowflake<GuildIntegrationTag>

/// Type marker separating GuildOnboardingPrompt snowflakes from other identifiers.
public enum GuildOnboardingPromptTag: Sendable {}
/// Exact unsigned 64-bit GuildOnboardingPrompt identifier, encoded as a decimal string.
public typealias GuildOnboardingPromptID = Snowflake<GuildOnboardingPromptTag>

/// Type marker separating GuildOnboardingOption snowflakes from other identifiers.
public enum GuildOnboardingOptionTag: Sendable {}
/// Exact unsigned 64-bit GuildOnboardingOption identifier, encoded as a decimal string.
public typealias GuildOnboardingOptionID = Snowflake<GuildOnboardingOptionTag>

/// Marker for a monetization SKU referenced by guild integration metadata.
public enum SKUTag: Sendable {}
/// Exact unsigned SKU snowflake without importing the monetization resource catalog.
public typealias SKUID = Snowflake<SKUTag>

/// API v10 GuildVerificationLevel values verified 2026-10-16 against the official Guild reference.
/// Response RawValue wrappers preserve future variants; unknown variants are never guessed.
public enum GuildVerificationLevel: Int, Sendable {
    /// No verification restriction.
    case `none` = 0
    /// Verified account email required.
    case low = 1
    /// Account must be older than five minutes.
    case medium = 2
    /// Guild membership must be older than ten minutes.
    case high = 3
    /// Verified telephone number required.
    case veryHigh = 4
}

/// API v10 GuildDefaultMessageNotificationLevel values verified 2026-10-16 against the official Guild reference.
/// Response RawValue wrappers preserve future variants; unknown variants are never guessed.
public enum GuildDefaultMessageNotificationLevel: Int, Sendable {
    /// Notify for all messages by default.
    case allMessages = 0
    /// Notify only for mentions by default.
    case onlyMentions = 1
}

/// API v10 GuildExplicitContentFilterLevel values verified 2026-10-16 against the official Guild reference.
/// Response RawValue wrappers preserve future variants; unknown variants are never guessed.
public enum GuildExplicitContentFilterLevel: Int, Sendable {
    /// No media scanning.
    case disabled = 0
    /// Scan media from members without roles.
    case membersWithoutRoles = 1
    /// Scan media from every member.
    case allMembers = 2
}

/// API v10 GuildMFALevel values verified 2026-10-16 against the official Guild reference.
/// Response RawValue wrappers preserve future variants; unknown variants are never guessed.
public enum GuildMFALevel: Int, Sendable {
    /// No moderation MFA requirement.
    case `none` = 0
    /// Moderation actions require MFA.
    case elevated = 1
}

/// API v10 GuildPremiumTier values verified 2026-10-16 against the official Guild reference.
/// Response RawValue wrappers preserve future variants; unknown variants are never guessed.
public enum GuildPremiumTier: Int, Sendable {
    /// No Server Boost tier.
    case `none` = 0
    /// Server Boost tier one.
    case tier1 = 1
    /// Server Boost tier two.
    case tier2 = 2
    /// Server Boost tier three.
    case tier3 = 3
}

/// API v10 GuildNSFWLevel values verified 2026-10-16 against the official Guild reference.
/// Response RawValue wrappers preserve future variants; unknown variants are never guessed.
public enum GuildNSFWLevel: Int, Sendable {
    /// Default age restriction classification.
    case `default` = 0
    /// Explicit guild classification.
    case explicit = 1
    /// Safe guild classification.
    case safe = 2
    /// Age restricted guild classification.
    case ageRestricted = 3
}

/// API v10 GuildOnboardingMode values verified 2026-10-16 against the official Guild reference.
/// Response RawValue wrappers preserve future variants; unknown variants are never guessed.
public enum GuildOnboardingMode: Int, Sendable {
    /// Count default channels toward onboarding constraints.
    case `default` = 0
    /// Count default channels and questions toward constraints.
    case advanced = 1
}

/// API v10 GuildOnboardingPromptType values verified 2026-10-16 against the official Guild reference.
/// Response RawValue wrappers preserve future variants; unknown variants are never guessed.
public enum GuildOnboardingPromptType: Int, Sendable {
    /// Multiple choice prompt.
    case multipleChoice = 0
    /// Dropdown selection prompt.
    case dropdown = 1
}

/// API v10 GuildIntegrationExpireBehavior values verified 2026-10-16 against the official Guild reference.
/// Response RawValue wrappers preserve future variants; unknown variants are never guessed.
public enum GuildIntegrationExpireBehavior: Int, Sendable {
    /// Remove the subscriber role when membership expires.
    case removeRole = 0
    /// Remove expired subscribers from the guild.
    case kick = 1
}

/// API v10 GuildIntegrationType values verified 2026-10-16 against the official Guild reference.
/// Response RawValue wrappers preserve future variants; unknown variants are never guessed.
public enum GuildIntegrationType: String, Sendable {
    /// Twitch account integration.
    case twitch = "twitch"
    /// YouTube account integration.
    case youtube = "youtube"
    /// Discord application integration.
    case discord = "discord"
    /// Guild subscription integration.
    case guildSubscription = "guild_subscription"
}

/// API v10 GuildWidgetImageStyle values verified 2026-10-16 against the official Guild reference.
/// Response RawValue wrappers preserve future variants; unknown variants are never guessed.
public enum GuildWidgetImageStyle: String, Sendable, CaseIterable {
    /// Compact shield with online count.
    case shield = "shield"
    /// Large guild image with powered by Discord footer.
    case banner1 = "banner1"
    /// Small guild image with Discord logo to the right.
    case banner2 = "banner2"
    /// Large guild image with Chat Now footer.
    case banner3 = "banner3"
    /// Large Discord logo, guild summary and join button.
    case banner4 = "banner4"
}

/// API v10 GuildIntegrationApplicationType values verified 2026-10-16 against the official OpenAPI integration schema.
/// Response RawValue wrappers preserve future variants; unknown variants are never guessed.
public enum GuildIntegrationApplicationType: Int, Sendable {
    /// Guild role subscription application type documented in the official OpenAPI integration schema.
    case guildRoleSubscriptions = 4
}

/// API v10 GuildFeature values verified 2026-10-16 against the official Guild reference and OpenAPI schema.
/// Response RawValue wrappers preserve future variants; unknown variants are never guessed.
public enum GuildFeature: String, Sendable {
    /// Documented OFFICIAL_GAME_GUILD capability; no authorization or entitlement inference follows.
    case officialGameGuild = "OFFICIAL_GAME_GUILD"
    /// Documented ANIMATED_BANNER capability; no authorization or entitlement inference follows.
    case animatedBanner = "ANIMATED_BANNER"
    /// Documented ANIMATED_ICON capability; no authorization or entitlement inference follows.
    case animatedIcon = "ANIMATED_ICON"
    /// Documented APPLICATION_COMMAND_PERMISSIONS_V2 capability; no authorization or entitlement inference follows.
    case applicationCommandPermissionsV2 = "APPLICATION_COMMAND_PERMISSIONS_V2"
    /// Documented AUTO_MODERATION capability; no authorization or entitlement inference follows.
    case autoModeration = "AUTO_MODERATION"
    /// Documented BANNER capability; no authorization or entitlement inference follows.
    case banner = "BANNER"
    /// Documented COMMUNITY capability; no authorization or entitlement inference follows.
    case community = "COMMUNITY"
    /// Documented CREATOR_MONETIZABLE_PROVISIONAL capability; no authorization or entitlement inference follows.
    case creatorMonetizableProvisional = "CREATOR_MONETIZABLE_PROVISIONAL"
    /// Documented CREATOR_STORE_PAGE capability; no authorization or entitlement inference follows.
    case creatorStorePage = "CREATOR_STORE_PAGE"
    /// Documented DEVELOPER_SUPPORT_SERVER capability; no authorization or entitlement inference follows.
    case developerSupportServer = "DEVELOPER_SUPPORT_SERVER"
    /// Documented DISCOVERABLE capability; no authorization or entitlement inference follows.
    case discoverable = "DISCOVERABLE"
    /// Documented ENHANCED_ROLE_COLORS capability; no authorization or entitlement inference follows.
    case enhancedRoleColors = "ENHANCED_ROLE_COLORS"
    /// Documented FEATURABLE capability; no authorization or entitlement inference follows.
    case featurable = "FEATURABLE"
    /// Documented GUILD_TAGS capability; no authorization or entitlement inference follows.
    case guildTags = "GUILD_TAGS"
    /// Documented GUESTS_ENABLED capability; no authorization or entitlement inference follows.
    case guestsEnabled = "GUESTS_ENABLED"
    /// Documented INVITES_DISABLED capability; no authorization or entitlement inference follows.
    case invitesDisabled = "INVITES_DISABLED"
    /// Documented INVITE_SPLASH capability; no authorization or entitlement inference follows.
    case inviteSplash = "INVITE_SPLASH"
    /// Documented MEMBER_VERIFICATION_GATE_ENABLED capability; no authorization or entitlement inference follows.
    case memberVerificationGateEnabled = "MEMBER_VERIFICATION_GATE_ENABLED"
    /// Documented MORE_SOUNDBOARD capability; no authorization or entitlement inference follows.
    case moreSoundboard = "MORE_SOUNDBOARD"
    /// Documented MORE_STICKERS capability; no authorization or entitlement inference follows.
    case moreStickers = "MORE_STICKERS"
    /// Documented NEWS capability; no authorization or entitlement inference follows.
    case news = "NEWS"
    /// Documented PARTNERED capability; no authorization or entitlement inference follows.
    case partnered = "PARTNERED"
    /// Documented PREVIEW_ENABLED capability; no authorization or entitlement inference follows.
    case previewEnabled = "PREVIEW_ENABLED"
    /// Documented PRUNE_REQUIRES_ADMIN capability; no authorization or entitlement inference follows.
    case pruneRequiresAdmin = "PRUNE_REQUIRES_ADMIN"
    /// Documented RAID_ALERTS_DISABLED capability; no authorization or entitlement inference follows.
    case raidAlertsDisabled = "RAID_ALERTS_DISABLED"
    /// Documented ROLE_ICONS capability; no authorization or entitlement inference follows.
    case roleIcons = "ROLE_ICONS"
    /// Documented ROLE_SUBSCRIPTIONS_AVAILABLE_FOR_PURCHASE capability; no authorization or entitlement inference follows.
    case roleSubscriptionsAvailableForPurchase = "ROLE_SUBSCRIPTIONS_AVAILABLE_FOR_PURCHASE"
    /// Documented ROLE_SUBSCRIPTIONS_ENABLED capability; no authorization or entitlement inference follows.
    case roleSubscriptionsEnabled = "ROLE_SUBSCRIPTIONS_ENABLED"
    /// Documented SOUNDBOARD capability; no authorization or entitlement inference follows.
    case soundboard = "SOUNDBOARD"
    /// Documented TICKETED_EVENTS_ENABLED capability; no authorization or entitlement inference follows.
    case ticketedEventsEnabled = "TICKETED_EVENTS_ENABLED"
    /// Documented VANITY_URL capability; no authorization or entitlement inference follows.
    case vanityUrl = "VANITY_URL"
    /// Documented VERIFIED capability; no authorization or entitlement inference follows.
    case verified = "VERIFIED"
    /// Documented VIP_REGIONS capability; no authorization or entitlement inference follows.
    case vipRegions = "VIP_REGIONS"
    /// Documented WELCOME_SCREEN_ENABLED capability; no authorization or entitlement inference follows.
    case welcomeScreenEnabled = "WELCOME_SCREEN_ENABLED"
}

/// Named API v10 GuildSystemChannelFlags bits; every unknown unsigned bit remains exact.
/// This response wrapper does not establish current permissions or whitelist outgoing edits.
public struct GuildSystemChannelFlags: OptionSet, Sendable, Hashable {
    /// Complete unsigned 64-bit bitfield, including future combinations.
    public let rawValue: UInt64

    /// Retains all supplied bits synchronously without validation, normalization, I/O or ownership changes.
    /// - Parameter rawValue: Any unsigned 64-bit combination, including zero and unknown flags.
    public init(rawValue: UInt64) { self.rawValue = rawValue }
    /// Suppress member join notices.
    public static let suppressJoinNotifications = Self(rawValue: 1 << 0)
    /// Suppress Server Boost notices.
    public static let suppressPremiumSubscriptions = Self(rawValue: 1 << 1)
    /// Suppress guild setup tips.
    public static let suppressGuildReminderNotifications = Self(rawValue: 1 << 2)
    /// Hide join sticker reply buttons.
    public static let suppressJoinNotificationReplies = Self(rawValue: 1 << 3)
    /// Suppress role subscription purchase and renewal notices.
    public static let suppressRoleSubscriptionPurchaseNotifications = Self(rawValue: 1 << 4)
    /// Hide role subscription sticker reply buttons.
    public static let suppressRoleSubscriptionPurchaseNotificationReplies = Self(rawValue: 1 << 5)
}

/// Named API v10 GuildMemberFlags bits; every unknown unsigned bit remains exact.
/// This response wrapper does not establish current permissions or whitelist outgoing edits.
public struct GuildMemberFlags: OptionSet, Sendable, Hashable {
    /// Complete unsigned 64-bit bitfield, including future combinations.
    public let rawValue: UInt64

    /// Retains all supplied bits synchronously without validation, normalization, I/O or ownership changes.
    /// - Parameter rawValue: Any unsigned 64-bit combination, including zero and unknown flags.
    public init(rawValue: UInt64) { self.rawValue = rawValue }
    /// Member left and rejoined the guild.
    public static let didRejoin = Self(rawValue: 1 << 0)
    /// Member completed onboarding.
    public static let completedOnboarding = Self(rawValue: 1 << 1)
    /// Member bypasses verification requirements; currently the sole editable member flag.
    public static let bypassesVerification = Self(rawValue: 1 << 2)
    /// Member started onboarding.
    public static let startedOnboarding = Self(rawValue: 1 << 3)
    /// Guest member can access the invited voice channel only.
    public static let isGuest = Self(rawValue: 1 << 4)
    /// Member started Server Guide actions.
    public static let startedHomeActions = Self(rawValue: 1 << 5)
    /// Member completed Server Guide actions.
    public static let completedHomeActions = Self(rawValue: 1 << 6)
    /// AutoMod blocked the member name.
    public static let automodQuarantinedUsername = Self(rawValue: 1 << 7)
    /// Member dismissed the DM settings upsell.
    public static let dmSettingsUpsellAcknowledged = Self(rawValue: 1 << 9)
    /// AutoMod blocked the member guild tag.
    public static let automodQuarantinedGuildTag = Self(rawValue: 1 << 10)
}

/// Named API v10 GuildRoleFlags bits; every unknown unsigned bit remains exact.
/// This response wrapper does not establish current permissions or whitelist outgoing edits.
public struct GuildRoleFlags: OptionSet, Sendable, Hashable {
    /// Complete unsigned 64-bit bitfield, including future combinations.
    public let rawValue: UInt64

    /// Retains all supplied bits synchronously without validation, normalization, I/O or ownership changes.
    /// - Parameter rawValue: Any unsigned 64-bit combination, including zero and unknown flags.
    public init(rawValue: UInt64) { self.rawValue = rawValue }
    /// Role can be selected in an onboarding prompt.
    public static let inPrompt = Self(rawValue: 1 << 0)
}
