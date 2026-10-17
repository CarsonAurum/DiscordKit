import DiscordCore
import Foundation

/// A complete API v10 rule snapshot, verified 2026-10-16 against the official Auto Moderation
/// reference. Reading rules requires MANAGE_GUILD. Values do not establish current permissions,
/// guild rule capacity or action eligibility; response limits are not reapplied as mutation rules.
public struct AutoModerationRule: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Required rule snowflake, preserving every unsigned bit.
    public let id: AutoModerationRuleID
    /// Guild that owns the rule.
    public let guildID: GuildID
    /// Rule name, retained exactly without normalization or logging.
    public let name: String
    /// User who originally created the rule.
    public let creatorID: UserID
    /// Event context, including unknown future discriminators.
    public let eventType: RawValue<AutoModerationEventType>
    /// Trigger kind, including unknown future discriminators.
    public let triggerType: RawValue<AutoModerationTriggerType>
    /// Required trigger metadata object; empty objects and future fields remain exact.
    public let triggerMetadata: AutoModerationTriggerMetadata
    /// Actions in the original server order, including future action kinds.
    public let actions: [AutoModerationAction]
    /// Whether Discord currently enables the rule.
    public let enabled: Bool
    /// Exempt role identifiers, retaining server order.
    public let exemptRoles: [RoleID]
    /// Exempt channel identifiers, retaining server order.
    public let exemptChannels: [ChannelID]
    /// Complete original object and unknown subtrees; ordinary diagnostics redact content.
    public let rawFields: [String: JSONValue]

    /// Parses one immutable bounded rule without I/O, permission lookups or cancellation suspension.
    /// - Parameters:
    ///   - data: Complete UTF-8 JSON object; duplicate keys and trailing documents are invalid.
    ///   - limits: Whole-document byte, depth and node limits, including unknown fields; defaults to
    ///     1,048,576 bytes, depth 64 and 100,000 nodes. Depth must be 1...128 and other limits positive.
    /// - Throws: `JSONValueError` for invalid JSON, limits or exceeded bounds; sanitized
    ///   `DiscordError.transport(.invalidResponse)` for absent, null or mistyped required fields,
    ///   malformed snowflakes or nonintegral/out-of-range integer discriminators. Correct input before retrying.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects a subtree after its entire containing document passed parser limits.
    /// - Parameters:
    ///   - value: Required original object subtree, sharing immutable JSON storage.
    ///   - limits: Root parser bounds reused for exact scalar projection.
    /// - Throws: Sanitized invalid-response errors for missing, null or mistyped fields, invalid IDs,
    ///   invalid nested objects or nonintegral discriminators. This synchronous operation owns no resources.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        id = try object.required("id", AutoModerationRuleID.self)
        guildID = try object.required("guild_id", GuildID.self)
        name = try object.required("name", String.self)
        creatorID = try object.required("creator_id", UserID.self)
        eventType = try object.required("event_type", RawValue<AutoModerationEventType>.self)
        triggerType = try object.required("trigger_type", RawValue<AutoModerationTriggerType>.self)
        triggerMetadata = try object.messageModel("trigger_metadata", AutoModerationTriggerMetadata.self)
        actions = try object.messageModels("actions", AutoModerationAction.self)
        enabled = try object.required("enabled", Bool.self)
        exemptRoles = try object.required("exempt_roles", [RoleID].self)
        exemptChannels = try object.required("exempt_channels", [ChannelID].self)
        rawFields = object.resource.fields
    }
}

/// Presence-aware metadata covering all five API v10 trigger kinds. Fields associated with other
/// kinds are retained if returned, so future responses are not rejected by request-only constraints.
public struct AutoModerationTriggerMetadata: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Optional nonnull keyword array; wildcard syntax and exact spelling are preserved.
    public let keywordFilter: Field<[String]>
    /// Optional nonnull Rust-flavored pattern array; no incompatible Swift regex evaluation occurs.
    public let regexPatterns: Field<[String]>
    /// Optional nonnull keyword-set values, including future set discriminators.
    public let presets: Field<[RawValue<AutoModerationKeywordPresetType>]>
    /// Optional nonnull exception keywords, retaining array order and exact spelling.
    public let allowList: Field<[String]>
    /// Optional nonnull unique role/user mention limit; response integers are not mutation-validated.
    public let mentionTotalLimit: Field<Int>
    /// Optional nonnull mention-raid detection switch.
    public let mentionRaidProtectionEnabled: Field<Bool>
    /// Complete metadata, including unknown subtrees and exact numeric lexemes.
    public let rawFields: [String: JSONValue]

    /// Parses a bounded metadata object without compiling patterns, performing I/O or suspending.
    /// - Parameters:
    ///   - data: Complete UTF-8 JSON object; an empty object is valid.
    ///   - limits: Bounds for the entire JSON tree, including unmodeled trigger data.
    /// - Throws: Parser/bounds errors or sanitized invalid-response errors for null or mistyped modeled
    ///   fields, malformed array members or nonintegral/out-of-range integers. Omission is retained.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects one already bounded trigger metadata subtree with exact optional presence.
    /// - Parameters:
    ///   - value: Required object subtree from a completely bounded document.
    ///   - limits: Root parse limits for scalar decoding; this method does not reparse the tree.
    /// - Throws: Sanitized invalid-response errors for a nonobject root, forbidden nulls or mistyped
    ///   known fields. Work is synchronous, has no side effects and does not observe task cancellation.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        keywordFilter = try object.field("keyword_filter", [String].self)
        regexPatterns = try object.field("regex_patterns", [String].self)
        presets = try object.array("presets") { value in
            // Foundation may round fractional array members when decoding an integer raw value.
            // Inspect each original number token so nested discriminators have scalar-level guarantees.
            guard case .number(let number) = value, let rawValue = Int(number.rawValue) else {
                throw DiscordError.transport(.invalidResponse)
            }
            return RawValue<AutoModerationKeywordPresetType>(rawValue: rawValue)
        }
        allowList = try object.field("allow_list", [String].self)
        mentionTotalLimit = try object.field("mention_total_limit", Int.self)
        mentionRaidProtectionEnabled = try object.field("mention_raid_protection_enabled", Bool.self)
        rawFields = object.resource.fields
    }
}

/// One API v10 rule action. Unknown types and complete metadata survive decoding; response parsing
/// does not infer permissions or apply current action/trigger compatibility to future values.
public struct AutoModerationAction: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Required exact integer discriminator, including future action kinds.
    public let type: RawValue<AutoModerationActionType>
    /// Optional nonnull metadata object; omission remains distinct from an empty object.
    public let metadata: Field<AutoModerationActionMetadata>
    /// Complete original action object with unknown fields preserved.
    public let rawFields: [String: JSONValue]

    /// Parses a bounded immutable action, without I/O or execution of the described action.
    /// - Parameters:
    ///   - data: Complete UTF-8 action object with required integral type.
    ///   - limits: Whole-document bounds, applied to unknown metadata too.
    /// - Throws: Parser/bounds errors or sanitized invalid-response errors for invalid roots,
    ///   discriminators or metadata; no payload value is included in diagnostics.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects a bounded action subtree without reparsing or narrowing unknown kinds.
    /// - Parameters:
    ///   - value: Action object from a root that already passed parser limits.
    ///   - limits: Root parse bounds used for scalar validation.
    /// - Throws: Sanitized invalid-response errors for missing/malformed type or null/mistyped
    ///   metadata. Construction is synchronous, side-effect free and owns no task or external resource.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        type = try object.required("type", RawValue<AutoModerationActionType>.self)
        metadata = try object.messageField("metadata", AutoModerationActionMetadata.self)
        rawFields = object.resource.fields
    }
}

/// API v10 action metadata with exact omission/null semantics for the nullable custom explanation.
public struct AutoModerationActionMetadata: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Optional nonnull destination for alert messages; channel existence is checked upstream.
    public let channelID: Field<ChannelID>
    /// Optional nonnull timeout seconds; response values are retained without mutation bounds.
    public let durationSeconds: Field<Int>
    /// Optional nullable block explanation; null and omission remain distinct per the written reference.
    public let customMessage: Field<String>
    /// Complete original metadata with exact unknown values and redacted default diagnostics.
    public let rawFields: [String: JSONValue]

    /// Parses one bounded metadata object without permission checks, logging or suspension.
    /// - Parameters:
    ///   - data: Complete UTF-8 object, including a permitted empty object.
    ///   - limits: Bounds covering all known and unknown subtrees.
    /// - Throws: Parser/bounds errors or sanitized invalid-response errors for wrong field types,
    ///   null channel/duration, malformed identifiers or nonintegral/out-of-range duration integers.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects an already bounded action metadata object with nullable explanation support.
    /// - Parameters:
    ///   - value: Required original object subtree from a parsed document.
    ///   - limits: Root parse limits reused for scalar decoding.
    /// - Throws: Sanitized invalid-response errors for a nonobject root or incompatible known field.
    ///   Work is synchronous and has no I/O, mutation, cancellation checks or resource ownership.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        channelID = try object.field("channel_id", ChannelID.self)
        durationSeconds = try object.field("duration_seconds", Int.self)
        customMessage = try object.field("custom_message", String.self, nullable: true)
        rawFields = object.resource.fields
    }
}
