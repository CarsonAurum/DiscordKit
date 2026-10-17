import DiscordCore
import Foundation

/// Validated API v10 trigger metadata. Explicit nulls follow the official OpenAPI preview;
/// permitted field associations and limits follow the written Auto Moderation reference.
/// Construction is synchronous and performs no regex compilation, I/O or permission lookup.
public struct AutoModerationTriggerMetadataRequest: GuildRequestPayload {
    /// Validation context; this discriminator is never inserted into the metadata object.
    public let triggerType: AutoModerationTriggerType
    private let fields: [String: JSONValue]

    /// Validates metadata for one known trigger while preserving omitted, null and empty selections.
    /// - Parameters:
    ///   - triggerType: The owning rule's trigger; spam accepts only an empty object.
    ///   - keywordFilter: Keyword/profile-only nullable array, at most 1000 nonempty strings of
    ///     1...60 Unicode scalars. Wildcards remain unchanged and their semantics belong to Discord.
    ///   - regexPatterns: Keyword/profile-only nullable array of at most ten nonempty patterns,
    ///     each at most 260 scalars. Discord validates Rust regex syntax; Swift does not compile it.
    ///   - presets: Preset-only nullable distinct set selection from the three known wordsets.
    ///   - allowList: Keyword/profile/preset-only nullable array of nonempty strings, each at most
    ///     60 scalars; at most 100 entries for keyword/profile and 1000 for preset rules.
    ///   - mentionTotalLimit: Mention-spam-only nullable unique-mention maximum in 0...50.
    ///   - mentionRaidProtectionEnabled: Mention-spam-only nullable detection switch.
    /// - Throws: Sanitized `DiscordError.validation(.invalidValue)` for fields associated with a
    ///   different trigger, duplicate presets, overlong/empty strings or out-of-range numeric values;
    ///   `.limitExceeded` for oversized arrays. Defaults are absent. No input appears in errors.
    public init(triggerType: AutoModerationTriggerType,
                keywordFilter: Field<[String]> = .absent, regexPatterns: Field<[String]> = .absent,
                presets: Field<[AutoModerationKeywordPresetType]> = .absent,
                allowList: Field<[String]> = .absent, mentionTotalLimit: Field<Int> = .absent,
                mentionRaidProtectionEnabled: Field<Bool> = .absent) throws {
        self.triggerType = triggerType
        var result: [String: JSONValue] = [:]
        try guildRequestField(keywordFilter, name: "keyword_filter", nullable: true, into: &result) {
            try autoModerationStrings($0, maximumCount: 1_000, maximumLength: 60)
        }
        try guildRequestField(regexPatterns, name: "regex_patterns", nullable: true, into: &result) {
            try autoModerationStrings($0, maximumCount: 10, maximumLength: 260)
        }
        try guildRequestField(presets, name: "presets", nullable: true, into: &result) {
            guard Set($0).count == $0.count else { throw DiscordError.validation(.invalidValue) }
            return .array(try $0.map { try guildRequestNumber($0.rawValue) })
        }
        try guildRequestField(allowList, name: "allow_list", nullable: true, into: &result) {
            try autoModerationStrings($0, maximumCount: triggerType == .keywordPreset ? 1_000 : 100, maximumLength: 60)
        }
        try guildRequestField(mentionTotalLimit, name: "mention_total_limit", nullable: true, into: &result) {
            try guildRequestRange($0, 0...50)
        }
        try guildRequestField(mentionRaidProtectionEnabled, name: "mention_raid_protection_enabled", nullable: true, into: &result) { .bool($0) }
        let allowed: Set<String>
        switch triggerType {
        case .keyword, .memberProfile: allowed = ["keyword_filter", "regex_patterns", "allow_list"]
        case .keywordPreset: allowed = ["presets", "allow_list"]
        case .mentionSpam: allowed = ["mention_total_limit", "mention_raid_protection_enabled"]
        case .spam: allowed = []
        }
        guard Set(result.keys).isSubset(of: allowed) else { throw DiscordError.validation(.invalidValue) }
        fields = result
    }

    /// Returns validated trigger metadata without adding omitted defaults or a trigger discriminator.
    /// - Returns: Exact immutable object, possibly empty; explicit nulls remain null.
    public func jsonValue() -> JSONValue { .object(fields) }
}

/// One validated API v10 action, configured using fields appropriate to its known type.
/// MANAGE_GUILD is required for all mutations; timeout also needs MODERATE_MEMBERS.
public struct AutoModerationActionRequest: GuildRequestPayload {
    /// Selected known action, used by enclosing requests for timeout trigger validation.
    public let type: AutoModerationActionType
    private let fields: [String: JSONValue]

    /// Validates an action without executing it or looking up destination channels/permissions.
    /// - Parameters:
    ///   - type: Known action discriminator; future action values remain response-only.
    ///   - channelID: Required nonnull destination for sendAlertMessage; absent for other types.
    ///   - durationSeconds: Required nonnull timeout duration, 0...2419200 seconds inclusive;
    ///     absent for other types. The written reference's required duration takes precedence over
    ///     the preview's nullable duration. Zero is allowed by its documented schema minimum.
    ///   - customMessage: Optional nullable blockMessage explanation, at most 150 Unicode scalars.
    ///     The written 150-character cap takes precedence over the preview's conflicting 300 cap.
    ///     Absent omits metadata entirely when no other action field exists; null remains explicit.
    /// - Throws: Sanitized invalid-value errors for missing required metadata, forbidden nulls,
    ///   fields associated with other types or invalid duration/text bounds. No I/O or suspension occurs.
    public init(type: AutoModerationActionType, channelID: Field<ChannelID> = .absent,
                durationSeconds: Field<Int> = .absent, customMessage: Field<String> = .absent) throws {
        self.type = type
        var metadata: [String: JSONValue] = [:]
        try guildRequestField(channelID, name: "channel_id", into: &metadata) { .string($0.description) }
        try guildRequestField(durationSeconds, name: "duration_seconds", into: &metadata) { try guildRequestRange($0, 0...2_419_200) }
        try guildRequestField(customMessage, name: "custom_message", nullable: true, into: &metadata) { try guildRequestText($0, length: 0...150) }
        switch type {
        case .blockMessage:
            guard Set(metadata.keys).isSubset(of: ["custom_message"]) else { throw DiscordError.validation(.invalidValue) }
        case .sendAlertMessage:
            guard Set(metadata.keys) == ["channel_id"] else { throw DiscordError.validation(.invalidValue) }
        case .timeout:
            guard Set(metadata.keys) == ["duration_seconds"] else { throw DiscordError.validation(.invalidValue) }
        case .blockMemberInteraction:
            guard metadata.isEmpty else { throw DiscordError.validation(.invalidValue) }
        }
        var result: [String: JSONValue] = ["type": try guildRequestNumber(type.rawValue)]
        if !metadata.isEmpty { result["metadata"] = .object(metadata) }
        fields = result
    }

    /// Returns one action without checking server state or adding an unnecessary metadata object.
    /// - Returns: Exact type and any explicitly configured metadata, with nullable text preserved.
    public func jsonValue() -> JSONValue { .object(fields) }
}

/// API v10 POST /guilds/{guild.id}/auto-moderation/rules, requiring MANAGE_GUILD and optionally
/// MODERATE_MEMBERS for timeout. Success emits Auto Moderation Rule Create. Upstream rule counts,
/// permissions, channel existence and Rust regex syntax remain server checks.
public struct AutoModerationCreateRequest: GuildRequestPayload {
    private let fields: [String: JSONValue]

    /// Constructs one rule with explicit required actions and no implicit server requests.
    /// - Parameters:
    ///   - name: Exact rule name of at most 100 Unicode scalars per the official preview; no minimum
    ///     length is published and empty text is forwarded for Discord's validation.
    ///   - eventType: Required known event context; no unpublished event/trigger pairing is inferred.
    ///   - triggerType: Required known trigger kind, also used for action/metadata compatibility.
    ///   - triggerMetadata: Absent or null for keyword/spam/mention-spam uses upstream semantics;
    ///     preset/profile creation requires a value. Metadata context must match triggerType.
    ///   - actions: Required ordered array of 1...5 validated actions. Timeout may only accompany
    ///     keyword or mentionSpam triggers; blockMemberInteraction requires memberProfile per the
    ///     official 2024-05-31 change log. Actions are not reordered or deduplicated.
    ///   - enabled: Absent preserves the upstream false default; explicit null follows the preview.
    ///   - exemptRoles: Nullable ordered array of at most 20 distinct roles; absence preserves defaults.
    ///   - exemptChannels: Nullable ordered array of at most 50 distinct channels; absence preserves defaults.
    /// - Throws: Sanitized invalid-value errors for overlong names, missing/mismatched metadata,
    ///   duplicates or action/trigger incompatibility; limit-exceeded errors for action/exemption counts.
    ///   Validation is synchronous with no I/O, suspension, rate admission or resource ownership.
    public init(name: String, eventType: AutoModerationEventType, triggerType: AutoModerationTriggerType,
                triggerMetadata: Field<AutoModerationTriggerMetadataRequest> = .absent,
                actions: [AutoModerationActionRequest], enabled: Field<Bool> = .absent,
                exemptRoles: Field<[RoleID]> = .absent, exemptChannels: Field<[ChannelID]> = .absent) throws {
        var result = try autoModerationRuleFields(triggerType: triggerType, name: .value(name),
            eventType: .value(eventType), triggerMetadata: triggerMetadata, actions: .value(actions),
            enabled: enabled, exemptRoles: exemptRoles, exemptChannels: exemptChannels)
        if [.keywordPreset, .memberProfile].contains(triggerType) {
            guard case .value = triggerMetadata else { throw DiscordError.validation(.invalidValue) }
        }
        result["trigger_type"] = try guildRequestNumber(triggerType.rawValue)
        fields = result
    }

    /// Returns the validated creation body, preserving omitted defaults and action order.
    /// - Returns: Exact required fields and every explicitly selected optional field.
    public func jsonValue() -> JSONValue { .object(fields) }
}

/// API v10 PATCH /guilds/{guild.id}/auto-moderation/rules/{rule.id}, requiring MANAGE_GUILD
/// and emitting Auto Moderation Rule Update. The trigger kind is immutable in the written API;
/// the caller supplies its known current value solely for local validation, with no hidden GET.
public struct AutoModerationModifyRequest: GuildRequestPayload {
    /// Caller-supplied current trigger context for validation; never included in the PATCH body.
    public let triggerType: AutoModerationTriggerType
    private let fields: [String: JSONValue]

    /// Validates selected rule changes without fetching, merging or guessing current rule state.
    /// - Parameters:
    ///   - triggerType: Caller-supplied current trigger kind; validation context only, never encoded.
    ///     Obtain it from a trusted current snapshot. Unknown future kinds cannot be safely mutated here.
    ///   - name: Absent preserves the current name; nonnull values permit 0...100 Unicode scalars.
    ///   - eventType: Absent preserves the current context; null is forbidden. If omitted, existing
    ///     event/action compatibility remains a server decision because current event state is unknown.
    ///   - triggerMetadata: Absent leaves metadata unchanged; matching values replace selected metadata
    ///     according to Discord's PATCH semantics. Null is supported only for keyword/spam/mention-spam.
    ///   - actions: Absent leaves actions unchanged; nullable per the official preview; values require
    ///     1...5 entries. Timeout is accepted only for keyword/mentionSpam triggers, and
    ///     blockMemberInteraction only for memberProfile, as published in the 2024-05-31 change log.
    ///   - enabled: Absent leaves current state unchanged; null retains the preview's server semantics.
    ///   - exemptRoles: Absent leaves exemptions unchanged; null is distinct from an explicit empty array;
    ///     values contain at most 20 distinct roles in caller order.
    ///   - exemptChannels: Absent leaves exemptions unchanged; null is distinct from an explicit empty array;
    ///     values contain at most 50 distinct channels in caller order.
    /// - Throws: Sanitized invalid-value errors for forbidden nulls, overlong names, metadata context
    ///   mismatch, duplicate IDs or action/trigger incompatibility; limit-exceeded for oversized arrays.
    ///   Work is synchronous, side-effect free and owns no I/O, task, lock or network resource.
    public init(triggerType: AutoModerationTriggerType, name: Field<String> = .absent,
                eventType: Field<AutoModerationEventType> = .absent,
                triggerMetadata: Field<AutoModerationTriggerMetadataRequest> = .absent,
                actions: Field<[AutoModerationActionRequest]> = .absent, enabled: Field<Bool> = .absent,
                exemptRoles: Field<[RoleID]> = .absent, exemptChannels: Field<[ChannelID]> = .absent) throws {
        self.triggerType = triggerType
        fields = try autoModerationRuleFields(triggerType: triggerType, name: name, eventType: eventType,
            triggerMetadata: triggerMetadata, actions: actions, enabled: enabled,
            exemptRoles: exemptRoles, exemptChannels: exemptChannels)
    }

    /// Returns selected changes without transmitting the validation-only trigger kind.
    /// - Returns: Exact immutable PATCH object, including an empty object when all fields are absent.
    public func jsonValue() -> JSONValue { .object(fields) }
}

/// Validates bounded keyword/pattern arrays without compiling or normalizing their contents.
/// - Parameters:
///   - values: Caller-ordered strings; empty arrays explicitly select none, repeated strings remain exact.
///   - maximumCount: Inclusive array bound from the associated trigger's published constraints.
///   - maximumLength: Inclusive nonempty-string bound measured in Unicode scalars.
/// - Returns: Original ordered strings as JSON.
/// - Throws: Limit-exceeded for oversized arrays; invalid-value for empty or overlong strings.
private func autoModerationStrings(_ values: [String], maximumCount: Int, maximumLength: Int) throws -> JSONValue {
    guard values.count <= maximumCount else { throw DiscordError.validation(.limitExceeded) }
    return .array(try values.map { try guildRequestText($0, length: 1...maximumLength) })
}

/// Builds shared create/modify fields without inferring any current server-side state.
/// - Parameters:
///   - triggerType: Validation-only current/selected trigger context.
///   - name: Omitted or nonnull name of at most 100 scalars.
///   - eventType: Omitted or nonnull known event context.
///   - triggerMetadata: Omitted, allowed null or metadata with matching trigger context.
///   - actions: Omitted, null or ordered array of 1...5 known actions; timeout requires a keyword or
///     mention-spam trigger and member-interaction blocking requires a member-profile trigger.
///   - enabled: Omitted, null or explicit enabled state.
///   - exemptRoles: Omitted, null or at most 20 distinct role IDs.
///   - exemptChannels: Omitted, null or at most 50 distinct channel IDs.
/// - Returns: Complete validated immutable body fields, without trigger_type.
/// - Throws: Sanitized invalid-value errors for null/type/context/range/duplicate violations;
///   limit-exceeded for count violations. This pure synchronous helper performs no I/O or suspension.
private func autoModerationRuleFields(triggerType: AutoModerationTriggerType, name: Field<String>,
    eventType: Field<AutoModerationEventType>, triggerMetadata: Field<AutoModerationTriggerMetadataRequest>,
    actions: Field<[AutoModerationActionRequest]>, enabled: Field<Bool>,
    exemptRoles: Field<[RoleID]>, exemptChannels: Field<[ChannelID]>) throws -> [String: JSONValue] {
    var result: [String: JSONValue] = [:]
    try guildRequestField(name, name: "name", into: &result) { try guildRequestText($0, length: 0...100) }
    try guildRequestField(eventType, name: "event_type", into: &result) { try guildRequestNumber($0.rawValue) }
    let nullableMetadata = ![.keywordPreset, .memberProfile].contains(triggerType)
    try guildRequestField(triggerMetadata, name: "trigger_metadata", nullable: nullableMetadata, into: &result) {
        guard $0.triggerType == triggerType else { throw DiscordError.validation(.invalidValue) }
        return $0.jsonValue()
    }
    try guildRequestField(actions, name: "actions", nullable: true, into: &result) {
        guard (1...5).contains($0.count) else { throw DiscordError.validation(.limitExceeded) }
        if $0.contains(where: { $0.type == .timeout }), ![.keyword, .mentionSpam].contains(triggerType) {
            throw DiscordError.validation(.invalidValue)
        }
        if $0.contains(where: { $0.type == .blockMemberInteraction }), triggerType != .memberProfile {
            throw DiscordError.validation(.invalidValue)
        }
        return .array($0.map { $0.jsonValue() })
    }
    try guildRequestField(enabled, name: "enabled", nullable: true, into: &result) { .bool($0) }
    try guildRequestField(exemptRoles, name: "exempt_roles", nullable: true, into: &result) {
        guard $0.count <= 20 else { throw DiscordError.validation(.limitExceeded) }
        return try guildRequestIDs($0)
    }
    try guildRequestField(exemptChannels, name: "exempt_channels", nullable: true, into: &result) {
        guard $0.count <= 50 else { throw DiscordError.validation(.limitExceeded) }
        return try guildRequestIDs($0)
    }
    return result
}
