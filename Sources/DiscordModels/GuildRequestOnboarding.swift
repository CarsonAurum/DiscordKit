import DiscordCore
import Foundation

/// API v10 welcome channel request; custom emoji IDs may be accompanied by their custom names.
/// Bounds follow Discord's official OpenAPI preview, reconciled with the Guild resource reference.
public struct GuildWelcomeChannelRequest: GuildRequestPayload {
    public let channelID: ChannelID
    private let fields: [String: JSONValue]

    /// Validates one welcome-channel entry without checking channel visibility or emoji availability.
    /// All `Field` parameters default to `.absent`, preserving server defaults or current values unless stated otherwise.
    /// - Parameters:
    ///   - channelID: Required target channel snowflake, retained exactly as a decimal string.
    ///   - description: Required description with 1...50 Unicode scalars.
    ///   - emojiID: Absent/null/custom emoji ID; custom names may also be sent in emojiName.
    ///   - emojiName: Absent/null/custom name or Unicode emoji; the reference leaves emoji eligibility to Discord.
    /// - Throws: Safe validation errors for description bounds; no credential/content is included in errors.
    public init(channelID: ChannelID, description: String, emojiID: Field<EmojiID> = .absent,
                emojiName: Field<String> = .absent) throws {
        self.channelID = channelID
        var result: [String: JSONValue] = ["channel_id": .string(channelID.description),
            "description": try guildRequestText(description, length: 1...50)]
        try guildRequestField(emojiID, name: "emoji_id", nullable: true, into: &result) { .string($0.description) }
        try guildRequestField(emojiName, name: "emoji_name", nullable: true, into: &result) { .string($0) }
        fields = result
    }

    /// Produces the welcome-channel object without converting a custom name into a Unicode selector.
    /// - Returns: Required channel and description plus exactly selected nullable emoji fields.
    public func jsonValue() -> JSONValue { .object(fields) }
}

/// API v10 PATCH /guilds/{guild.id}/welcome-screen; requires MANAGE_GUILD and may emit Guild Update.
public struct GuildWelcomeScreenModify: GuildRequestPayload {
    private let fields: [String: JSONValue]

    /// Validates the nullable welcome-screen settings without requiring a local guild snapshot.
    /// All `Field` parameters default to `.absent`, preserving server defaults or current values unless stated otherwise.
    /// - Parameters:
    ///   - enabled: Omitted or nullable enable switch; all fields are nullable in the Guild reference.
    ///   - welcomeChannels: Nullable list of at most five distinct channel entries; empty explicitly selects none.
    ///   - description: Nullable welcome description, at most 140 Unicode scalars in the official schema.
    /// - Throws: Safe validation errors for duplicate/overlong channel lists or an overlong description.
    public init(enabled: Field<Bool> = .absent, welcomeChannels: Field<[GuildWelcomeChannelRequest]> = .absent,
                description: Field<String> = .absent) throws {
        var result: [String: JSONValue] = [:]
        try guildRequestField(enabled, name: "enabled", nullable: true, into: &result) { .bool($0) }
        try guildRequestField(welcomeChannels, name: "welcome_channels", nullable: true, into: &result) {
            let ids = $0.map(\.channelID)
            guard $0.count <= 5, Set(ids).count == ids.count else { throw DiscordError.validation(.invalidValue) }
            return .array($0.map { $0.jsonValue() })
        }
        try guildRequestField(description, name: "description", nullable: true, into: &result) { try guildRequestText($0, length: 0...140) }
        fields = result
    }

    /// Produces exact welcome-screen changes without enabling it implicitly.
    /// - Returns: Immutable nullable PATCH object with omitted defaults preserved.
    public func jsonValue() -> JSONValue { .object(fields) }
}

/// API v10 onboarding option request, using flattened emoji fields rather than a response emoji object.
/// See https://docs.discord.com/developers/resources/guild#guild-onboarding-object and Discord's OpenAPI preview.
public struct GuildOnboardingOptionRequest: GuildRequestPayload {
    public let id: Field<GuildOnboardingOptionID>
    private let fields: [String: JSONValue]

    /// Validates one prompt option without fetching its target channels, roles or emoji.
    /// All `Field` parameters default to `.absent`, preserving server defaults or current values unless stated otherwise.
    /// - Parameters:
    ///   - title: Required 1...50 scalar display title.
    ///   - id: Optional existing option snowflake; absent/null requests server allocation for a new option.
    ///   - description: Optional nullable description with at most 100 scalars.
    ///   - channelIDs: Optional nullable array of at most 50 distinct channels assigned on selection.
    ///   - roleIDs: Optional nullable array of at most 50 distinct roles assigned on selection.
    ///   - emojiID: Optional nullable custom emoji snowflake; availability remains a server check.
    ///   - emojiName: Optional nullable emoji name/Unicode string with at most 100 scalars.
    ///   - emojiAnimated: Optional nullable animation marker, transmitted without inferring emoji type.
    /// - Throws: Safe validation errors for string/list bounds or duplicate target IDs.
    ///   Current role hierarchy, permission eligibility and emoji consistency are server checks.
    public init(title: String, id: Field<GuildOnboardingOptionID> = .absent,
                description: Field<String> = .absent, channelIDs: Field<[ChannelID]> = .absent,
                roleIDs: Field<[RoleID]> = .absent, emojiID: Field<EmojiID> = .absent,
                emojiName: Field<String> = .absent, emojiAnimated: Field<Bool> = .absent) throws {
        self.id = id
        var result: [String: JSONValue] = ["title": try guildRequestText(title, length: 1...50)]
        try guildRequestField(id, name: "id", nullable: true, into: &result) { .string($0.description) }
        try guildRequestField(description, name: "description", nullable: true, into: &result) { try guildRequestText($0, length: 0...100) }
        try guildRequestField(channelIDs, name: "channel_ids", nullable: true, into: &result) {
            guard $0.count <= 50 else { throw DiscordError.validation(.invalidValue) }; return try guildRequestIDs($0)
        }
        try guildRequestField(roleIDs, name: "role_ids", nullable: true, into: &result) {
            guard $0.count <= 50 else { throw DiscordError.validation(.invalidValue) }; return try guildRequestIDs($0)
        }
        try guildRequestField(emojiID, name: "emoji_id", nullable: true, into: &result) { .string($0.description) }
        try guildRequestField(emojiName, name: "emoji_name", nullable: true, into: &result) { try guildRequestText($0, length: 0...100) }
        try guildRequestField(emojiAnimated, name: "emoji_animated", nullable: true, into: &result) { .bool($0) }
        fields = result
    }

    /// Produces the flattened option representation accepted by the onboarding update endpoint.
    /// - Returns: Required title and explicitly supplied nullable option fields; never a nested emoji object.
    public func jsonValue() -> JSONValue { .object(fields) }
}

/// API v10 onboarding prompt request; the official update schema requires id, title and options.
/// IDs identify existing prompts or caller-selected new prompt identifiers; Discord resolves their validity.
public struct GuildOnboardingPromptRequest: GuildRequestPayload {
    public let id: GuildOnboardingPromptID
    private let fields: [String: JSONValue]

    /// Validates one prompt and its option IDs while leaving permission/visibility checks to Discord.
    /// All `Field` parameters default to `.absent`, preserving server defaults or current values unless stated otherwise.
    /// - Parameters:
    ///   - id: Required prompt snowflake, preserved as an exact decimal string.
    ///   - title: Required 1...100 scalar prompt title.
    ///   - options: One through 50 validated options; nonnull supplied option IDs must be distinct.
    ///   - type: Optional nullable multiple-choice/dropdown kind; unknown values are rejected.
    ///   - singleSelect: Optional nullable restriction to selecting one option.
    ///   - required: Optional nullable completion requirement.
    ///   - inOnboarding: Optional nullable presence in initial onboarding; false limits it to Channels & Roles.
    /// - Throws: Safe validation errors for title/option bounds, duplicate option IDs or unknown prompt types.
    public init(id: GuildOnboardingPromptID, title: String, options: [GuildOnboardingOptionRequest],
                type: Field<GuildOnboardingPromptType> = .absent, singleSelect: Field<Bool> = .absent,
                required: Field<Bool> = .absent, inOnboarding: Field<Bool> = .absent) throws {
        let ids = options.compactMap { option -> GuildOnboardingOptionID? in
            if case .value(let id) = option.id { return id }; return nil
        }
        guard (1...50).contains(options.count), Set(ids).count == ids.count else { throw DiscordError.validation(.invalidValue) }
        self.id = id
        var result: [String: JSONValue] = ["id": .string(id.description),
            "title": try guildRequestText(title, length: 1...100), "options": .array(options.map { $0.jsonValue() })]
        try guildRequestField(type, name: "type", nullable: true, into: &result) { try guildRequestRange($0.rawValue, 0...1) }
        try guildRequestField(singleSelect, name: "single_select", nullable: true, into: &result) { .bool($0) }
        try guildRequestField(required, name: "required", nullable: true, into: &result) { .bool($0) }
        try guildRequestField(inOnboarding, name: "in_onboarding", nullable: true, into: &result) { .bool($0) }
        fields = result
    }

    /// Produces the prompt's complete required fields plus selected nullable settings.
    /// - Returns: Immutable prompt object preserving option order and exact snowflake IDs.
    public func jsonValue() -> JSONValue { .object(fields) }
}

/// API v10 PUT /guilds/{guild.id}/onboarding; requires MANAGE_GUILD and MANAGE_ROLES.
/// Enabling requires at least seven eligible channels, with at least five allowing @everyone to send.
/// Mode changes which default/question channels count. These state-dependent constraints are checked
/// by Discord because omitted prior settings, channel permissions and advanced-mode eligibility are unknown locally.
public struct GuildOnboardingModify: GuildRequestPayload {
    private let fields: [String: JSONValue]

    /// Validates the published structural bounds while preserving nullable official-schema settings.
    /// All `Field` parameters default to `.absent`, preserving server defaults or current values unless stated otherwise.
    /// - Parameters:
    ///   - prompts: Optional nullable list of at most 15 prompts with distinct prompt IDs.
    ///   - defaultChannelIDs: Optional nullable list of at most 500 distinct default channel IDs.
    ///   - enabled: Optional nullable onboarding switch; does not imply local validation of current permissions.
    ///   - mode: Optional nullable default/advanced constraint mode; unknown future values are rejected on requests.
    /// - Throws: Safe validation errors for duplicate/overlong collections or unknown modes.
    ///   The server can still reject feature, hierarchy and permission-dependent enablement constraints.
    public init(prompts: Field<[GuildOnboardingPromptRequest]> = .absent,
                defaultChannelIDs: Field<[ChannelID]> = .absent, enabled: Field<Bool> = .absent,
                mode: Field<GuildOnboardingMode> = .absent) throws {
        var result: [String: JSONValue] = [:]
        try guildRequestField(prompts, name: "prompts", nullable: true, into: &result) {
            let ids = $0.map(\.id)
            guard $0.count <= 15, Set(ids).count == ids.count else { throw DiscordError.validation(.invalidValue) }
            return .array($0.map { $0.jsonValue() })
        }
        try guildRequestField(defaultChannelIDs, name: "default_channel_ids", nullable: true, into: &result) {
            guard $0.count <= 500 else { throw DiscordError.validation(.invalidValue) }; return try guildRequestIDs($0)
        }
        try guildRequestField(enabled, name: "enabled", nullable: true, into: &result) { .bool($0) }
        try guildRequestField(mode, name: "mode", nullable: true, into: &result) { try guildRequestRange($0.rawValue, 0...1) }
        fields = result
    }

    /// Produces explicit onboarding configuration changes without reading server permissions or state.
    /// - Returns: Exact nullable PUT body; absent fields are never filled with inferred prior settings.
    public func jsonValue() -> JSONValue { .object(fields) }
}

/// API v10 PUT /guilds/{guild.id}/incident-actions; requires MANAGE_GUILD.
/// Each incident action may extend at most 24 hours into the future; null disables an action.
public struct GuildIncidentActionsModify: GuildRequestPayload {
    private let fields: [String: JSONValue]

    /// Validates nullable incident-action deadlines against an injectable wall-clock snapshot.
    /// All `Field` parameters default to `.absent`, preserving server defaults or current values unless stated otherwise.
    /// - Parameters:
    ///   - invitesDisabledUntil: Absent leaves invite state unchanged; null disables the action;
    ///     a value must fall within the inclusive reference-time through 24-hour future window.
    ///   - dmsDisabledUntil: Equivalent selection for direct messages.
    ///   - referenceTime: Finite validation snapshot, defaulting to construction time; never transmitted.
    ///     Construct near execution because Discord rechecks the deadline on receipt.
    /// - Throws: Safe validation errors for past/overlong deadlines or nonfinite reference times.
    public init(invitesDisabledUntil: Field<DiscordTimestamp> = .absent,
                dmsDisabledUntil: Field<DiscordTimestamp> = .absent, referenceTime: Date = Date()) throws {
        var result: [String: JSONValue] = [:]
        try guildRequestField(invitesDisabledUntil, name: "invites_disabled_until", nullable: true, into: &result) {
            try guildRequestDeadline($0, referenceTime: referenceTime, maximumSeconds: 86_400)
        }
        try guildRequestField(dmsDisabledUntil, name: "dms_disabled_until", nullable: true, into: &result) {
            try guildRequestDeadline($0, referenceTime: referenceTime, maximumSeconds: 86_400)
        }
        fields = result
    }

    /// Produces exact incident-action updates while retaining timestamp offset/fraction spellings.
    /// - Returns: Immutable object with explicit action removals and no clock metadata.
    public func jsonValue() -> JSONValue { .object(fields) }
}
