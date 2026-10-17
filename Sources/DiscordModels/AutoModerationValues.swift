import DiscordCore

/// Type marker separating Auto Moderation rule identifiers from other snowflakes.
public enum AutoModerationRuleTag: Sendable {}
/// Exact unsigned 64-bit Auto Moderation rule identifier, encoded as decimal text.
public typealias AutoModerationRuleID = Snowflake<AutoModerationRuleTag>

/// API v10 rule contexts verified 2026-10-16 against the official Auto Moderation reference.
/// Response `RawValue` projections retain future values without inventing their behavior.
public enum AutoModerationEventType: Int, Sendable, CaseIterable {
    /// A member sends or edits a guild message.
    case messageSend = 1
    /// A member edits their profile.
    case memberUpdate = 2
}

/// API v10 Auto Moderation triggers; maximum rule counts are enforced by Discord using guild state.
public enum AutoModerationTriggerType: Int, Sendable, CaseIterable {
    /// User-defined message keywords and Rust-flavored patterns; at most six rules per guild.
    case keyword = 1
    /// Generic spam detection; at most one rule per guild.
    case spam = 3
    /// Discord's predefined keyword sets; at most one rule per guild.
    case keywordPreset = 4
    /// Unique role/user mention limits and mention-raid detection; at most one rule per guild.
    case mentionSpam = 5
    /// User-defined profile keywords and patterns; at most one rule per guild.
    case memberProfile = 6
}

/// API v10 internally maintained keyword sets; response raw values remain forward compatible.
public enum AutoModerationKeywordPresetType: Int, Sendable, CaseIterable {
    /// Words associated with swearing or cursing.
    case profanity = 1
    /// Words associated with sexually explicit activity.
    case sexualContent = 2
    /// Personal insults and words associated with hate speech.
    case slurs = 3
}

/// API v10 actions verified against https://docs.discord.com/developers/resources/auto-moderation.
public enum AutoModerationActionType: Int, Sendable, CaseIterable {
    /// Prevents a member's message from being posted, optionally displaying an explanation.
    case blockMessage = 1
    /// Logs triggering content to the selected channel.
    case sendAlertMessage = 2
    /// Times out the member; requires MODERATE_MEMBERS and a keyword or mention-spam trigger.
    case timeout = 3
    /// Prevents the member from using text, voice and other interactions; available for member-profile rules.
    case blockMemberInteraction = 4
}
