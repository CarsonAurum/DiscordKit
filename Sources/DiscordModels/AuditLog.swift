import DiscordCore
import Foundation

/// One exact audit change, including command-permission snowflake keys, `$add`/`$remove` role arrays,
/// invite `channel_id`, webhook `avatar_hash` and future change shapes. Values intentionally remain JSON:
/// field meaning depends on the action and affected object. Absent newValue with a present oldValue denotes
/// reset/null; absent oldValue denotes a previously null field. Explicit JSON null remains separately visible.
/// The written reference requires a string key, while the official preview permits a required null key;
/// this projection accepts both without inventing a replacement key.
/// API v10; verified 2026-10-16 against https://docs.discord.com/developers/resources/audit-log
/// and https://github.com/discord/discord-api-spec/blob/main/specs/openapi.json.
public struct AuditLogChange: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Required changed-field name or explicit null, accommodating the official preview schema.
    public let key: Nullable<String>
    /// Optional exact new subtree, preserving absence, explicit null, strings, arrays, objects and numeric lexemes.
    public let newValue: Field<JSONValue>
    /// Optional exact previous subtree; an omitted value is not synthesized as JSON null.
    public let oldValue: Field<JSONValue>
    /// Complete original object including future fields and exact numeric lexemes; diagnostics conceal payloads.
    public let rawFields: [String: JSONValue]

    /// Parses one complete API v10 object synchronously with exact unknown-field retention.
    /// - Parameters:
    ///   - data: Complete UTF-8 JSON object. Required nullable keys must exist; optional omissions remain distinct
    ///     from explicit null. Known fields are checked, while unprojected related-family details remain partial.
    ///   - limits: Whole-document bounds covering unknown subtrees: defaults to 1,048,576 UTF-8 bytes,
    ///     container depth 64 and 100,000 JSON values. Byte/node bounds must be positive and depth in 1...128.
    /// - Throws: `JSONValueError` for invalid limits, syntax, Unicode, duplicate keys or exceeded bounds;
    ///   `DiscordError.transport(.invalidResponse)` for missing, forbidden-null, mistyped or out-of-range
    ///   modeled fields. Errors do not disclose payload values; correct the input or limits before retrying.
    /// No I/O, suspension, credential access, cache mutation or ownership changes occur. Decoding is bounded
    /// synchronous work and does not observe cooperative task cancellation during construction.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects one immutable subtree after its complete containing document passed the parser's bounds.
    /// - Parameters:
    ///   - value: Original object subtree; the bounded root is a caller-established invariant.
    ///   - limits: Bounds established at the root, reused for exact scalar decoding.
    /// - Throws: Sanitized invalid-response errors for nonobject roots, missing required values, forbidden null,
    ///   incompatible modeled types or exact integer/identifier overflow. Unknown values are not normalized.
    /// Construction shares immutable JSON storage without reparsing nested objects, suspending, performing I/O
    /// or changing ownership. Parser bounds are enforced at the public data initializer rather than here.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        key = try object.required("key", Nullable<String>.self)
        newValue = try object.nested("new_value", nullable: true) { $0 }
        oldValue = try object.nested("old_value", nullable: true) { $0 }
        rawFields = object.resource.fields
    }
}

/// Complete documented optional audit entry information. Every field is optional and nonnull when present;
/// event applicability is descriptive rather than a decoder restriction, allowing future event combinations.
/// Decimal counts, trigger types and overwrite types are strings on the wire, retained without integer coercion.
/// Unknown keys and arbitrary future value shapes remain exact in rawFields.
/// API v10; verified 2026-10-16 against https://docs.discord.com/developers/resources/audit-log
/// and https://github.com/discord/discord-api-spec/blob/main/specs/openapi.json.
public struct AuditLogEntryOptions: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Application whose command permissions were targeted (APPLICATION_COMMAND_PERMISSION_UPDATE).
    public let applicationID: Field<ApplicationID>
    /// Triggered Auto Moderation rule name; may contain private moderation configuration.
    public let autoModerationRuleName: Field<String>
    /// Triggered Auto Moderation rule type as its exact wire string, including unknown future codes.
    public let autoModerationRuleTriggerType: Field<String>
    /// Targeted channel for voice moves, message actions, Stage actions, Auto Moderation or voice statuses.
    public let channelID: Field<ChannelID>
    /// Number of targeted entities as an exact string; no local overflow, rounding or numeric normalization.
    public let count: Field<String>
    /// Prune inactivity threshold in days as the original string.
    public let deleteMemberDays: Field<String>
    /// Overwritten role/member snowflake for channel overwrite actions, distinct from the entry target.
    public let id: Field<ChannelOverwriteTargetID>
    /// Pruned member count as the original string, independent of native integer capacity.
    public let membersRemoved: Field<String>
    /// Message targeted by pin/unpin actions.
    public let messageID: Field<MessageID>
    /// Overwritten role name when overwrite type is "0"; missing on member overwrites.
    public let roleName: Field<String>
    /// Overwritten entity type: role "0", member "1", or an unchanged future wire string.
    public let type: Field<String>
    /// Integration kind performing MEMBER_KICK or MEMBER_ROLE_UPDATE.
    public let integrationType: Field<String>
    /// New voice channel status for VOICE_CHANNEL_STATUS_CREATE; payload diagnostics remain redacted.
    public let status: Field<String>
    /// Complete original object including future fields and exact numeric lexemes; diagnostics conceal payloads.
    public let rawFields: [String: JSONValue]

    /// Parses one complete API v10 object synchronously with exact unknown-field retention.
    /// - Parameters:
    ///   - data: Complete UTF-8 JSON object. Required nullable keys must exist; optional omissions remain distinct
    ///     from explicit null. Known fields are checked, while unprojected related-family details remain partial.
    ///   - limits: Whole-document bounds covering unknown subtrees: defaults to 1,048,576 UTF-8 bytes,
    ///     container depth 64 and 100,000 JSON values. Byte/node bounds must be positive and depth in 1...128.
    /// - Throws: `JSONValueError` for invalid limits, syntax, Unicode, duplicate keys or exceeded bounds;
    ///   `DiscordError.transport(.invalidResponse)` for missing, forbidden-null, mistyped or out-of-range
    ///   modeled fields. Errors do not disclose payload values; correct the input or limits before retrying.
    /// No I/O, suspension, credential access, cache mutation or ownership changes occur. Decoding is bounded
    /// synchronous work and does not observe cooperative task cancellation during construction.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects one immutable subtree after its complete containing document passed the parser's bounds.
    /// - Parameters:
    ///   - value: Original object subtree; the bounded root is a caller-established invariant.
    ///   - limits: Bounds established at the root, reused for exact scalar decoding.
    /// - Throws: Sanitized invalid-response errors for nonobject roots, missing required values, forbidden null,
    ///   incompatible modeled types or exact integer/identifier overflow. Unknown values are not normalized.
    /// Construction shares immutable JSON storage without reparsing nested objects, suspending, performing I/O
    /// or changing ownership. Parser bounds are enforced at the public data initializer rather than here.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        applicationID = try object.field("application_id", ApplicationID.self)
        autoModerationRuleName = try object.field("auto_moderation_rule_name", String.self)
        autoModerationRuleTriggerType = try object.field("auto_moderation_rule_trigger_type", String.self)
        channelID = try object.field("channel_id", ChannelID.self)
        count = try object.field("count", String.self)
        deleteMemberDays = try object.field("delete_member_days", String.self)
        id = try object.field("id", ChannelOverwriteTargetID.self)
        membersRemoved = try object.field("members_removed", String.self)
        messageID = try object.field("message_id", MessageID.self)
        roleName = try object.field("role_name", String.self)
        type = try object.field("type", String.self)
        integrationType = try object.field("integration_type", String.self)
        status = try object.field("status", String.self)
        rawFields = object.resource.fields
    }
}

/// One guild administrative action snapshot. Entries are retained upstream for 45 days and retrieval requires
/// VIEW_AUDIT_LOG. This value performs no permission checks or network requests. Unknown action codes,
/// change structures and option fields remain exact; action recognition does not imply full event catalog parity.
/// API v10; verified 2026-10-16 against https://docs.discord.com/developers/resources/audit-log
/// and https://github.com/discord/discord-api-spec/blob/main/specs/openapi.json.
public struct AuditLogEntry: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Affected entity identifier as a required nullable opaque string. The written reference permits strings; no snowflake coercion is imposed.
    public let targetID: Nullable<String>
    /// Optional ordered change list; omission differs from a present empty list and explicit null is invalid.
    public let changes: Field<[AuditLogChange]>
    /// Required nullable user/app actor snowflake; null does not identify an anonymous or particular actor.
    public let userID: Nullable<UserID>
    /// Required exact entry snowflake; distinct from target identifiers and retained across pagination.
    public let id: AuditLogEntryID
    /// Required integral administrative action code; unknown values survive without guessed interpretation.
    public let actionType: RawValue<AuditLogEvent>
    /// Optional additional event information; absence differs from a present empty options object.
    public let options: Field<AuditLogEntryOptions>
    /// Optional audit reason text, concealed by ordinary diagnostics. Response text is not truncated or locally normalized.
    public let reason: Field<String>
    /// Complete original object including future fields and exact numeric lexemes; diagnostics conceal payloads.
    public let rawFields: [String: JSONValue]

    /// Parses one complete API v10 object synchronously with exact unknown-field retention.
    /// - Parameters:
    ///   - data: Complete UTF-8 JSON object. Required nullable keys must exist; optional omissions remain distinct
    ///     from explicit null. Known fields are checked, while unprojected related-family details remain partial.
    ///   - limits: Whole-document bounds covering unknown subtrees: defaults to 1,048,576 UTF-8 bytes,
    ///     container depth 64 and 100,000 JSON values. Byte/node bounds must be positive and depth in 1...128.
    /// - Throws: `JSONValueError` for invalid limits, syntax, Unicode, duplicate keys or exceeded bounds;
    ///   `DiscordError.transport(.invalidResponse)` for missing, forbidden-null, mistyped or out-of-range
    ///   modeled fields. Errors do not disclose payload values; correct the input or limits before retrying.
    /// No I/O, suspension, credential access, cache mutation or ownership changes occur. Decoding is bounded
    /// synchronous work and does not observe cooperative task cancellation during construction.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects one immutable subtree after its complete containing document passed the parser's bounds.
    /// - Parameters:
    ///   - value: Original object subtree; the bounded root is a caller-established invariant.
    ///   - limits: Bounds established at the root, reused for exact scalar decoding.
    /// - Throws: Sanitized invalid-response errors for nonobject roots, missing required values, forbidden null,
    ///   incompatible modeled types or exact integer/identifier overflow. Unknown values are not normalized.
    /// Construction shares immutable JSON storage without reparsing nested objects, suspending, performing I/O
    /// or changing ownership. Parser bounds are enforced at the public data initializer rather than here.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        targetID = try object.required("target_id", Nullable<String>.self)
        changes = try object.messageArray("changes", AuditLogChange.self)
        userID = try object.required("user_id", Nullable<UserID>.self)
        id = try object.required("id", AuditLogEntryID.self)
        actionType = try object.required("action_type", RawValue<AuditLogEvent>.self)
        options = try object.messageField("options", AuditLogEntryOptions.self)
        reason = try object.field("reason", String.self)
        rawFields = object.resource.fields
    }
}

/// The documented partial integration shape embedded in audit logs, including provider account information.
/// This is intentionally separate from GuildIntegration: audit snapshots omit enabled/subscriber configuration.
/// The preview permits nullable names and requires application_id for Discord integration variants;
/// the written example also includes application_id on a Twitch integration. This projection accepts optional
/// application_id for every variant, preserving that ambiguity without inferring an application.
/// API v10; verified 2026-10-16 against https://docs.discord.com/developers/resources/audit-log
/// and https://github.com/discord/discord-api-spec/blob/main/specs/openapi.json.
public struct AuditLogIntegration: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Required integration snowflake from the audit-specific partial integration schema.
    public let id: GuildIntegrationID
    /// Required nullable integration name, following the official preview variant schemas.
    public let name: Nullable<String>
    /// Required integration type string, retaining future provider variants.
    public let type: RawValue<GuildIntegrationType>
    /// Required provider account; its external identifier remains an opaque string.
    public let account: GuildIntegrationAccount
    /// Optional application snowflake; not inferred from integration type or provider account.
    public let applicationID: Field<ApplicationID>
    /// Complete original object including future fields and exact numeric lexemes; diagnostics conceal payloads.
    public let rawFields: [String: JSONValue]

    /// Parses one complete API v10 object synchronously with exact unknown-field retention.
    /// - Parameters:
    ///   - data: Complete UTF-8 JSON object. Required nullable keys must exist; optional omissions remain distinct
    ///     from explicit null. Known fields are checked, while unprojected related-family details remain partial.
    ///   - limits: Whole-document bounds covering unknown subtrees: defaults to 1,048,576 UTF-8 bytes,
    ///     container depth 64 and 100,000 JSON values. Byte/node bounds must be positive and depth in 1...128.
    /// - Throws: `JSONValueError` for invalid limits, syntax, Unicode, duplicate keys or exceeded bounds;
    ///   `DiscordError.transport(.invalidResponse)` for missing, forbidden-null, mistyped or out-of-range
    ///   modeled fields. Errors do not disclose payload values; correct the input or limits before retrying.
    /// No I/O, suspension, credential access, cache mutation or ownership changes occur. Decoding is bounded
    /// synchronous work and does not observe cooperative task cancellation during construction.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects one immutable subtree after its complete containing document passed the parser's bounds.
    /// - Parameters:
    ///   - value: Original object subtree; the bounded root is a caller-established invariant.
    ///   - limits: Bounds established at the root, reused for exact scalar decoding.
    /// - Throws: Sanitized invalid-response errors for nonobject roots, missing required values, forbidden null,
    ///   incompatible modeled types or exact integer/identifier overflow. Unknown values are not normalized.
    /// Construction shares immutable JSON storage without reparsing nested objects, suspending, performing I/O
    /// or changing ownership. Parser bounds are enforced at the public data initializer rather than here.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        id = try object.required("id", GuildIntegrationID.self)
        name = try object.required("name", Nullable<String>.self)
        type = try object.required("type", RawValue<GuildIntegrationType>.self)
        account = try object.messageModel("account", GuildIntegrationAccount.self)
        applicationID = try object.field("application_id", ApplicationID.self)
        rawFields = object.resource.fields
    }
}

/// An explicitly partial application command referenced by an audit response. Only its identifier and common
/// display/context fields are projected; permissions, options, localizations and versions remain exact in rawFields.
/// This wrapper does not claim command registration, interaction execution or complete Application Command parity.
/// API v10; verified 2026-10-16 against https://docs.discord.com/developers/resources/audit-log
/// and https://github.com/discord/discord-api-spec/blob/main/specs/openapi.json.
public struct AuditLogApplicationCommand: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Required exact command snowflake.
    public let id: ApplicationCommandID
    /// Optional owning application identifier within this partial projection.
    public let applicationID: Field<ApplicationID>
    /// Optional guild context; absence is retained rather than treated as a global-registration guarantee.
    public let guildID: Field<GuildID>
    /// Optional command display name, including future naming conventions.
    public let name: Field<String>
    /// Optional exact integral command kind, including future values without guessed enum support.
    public let type: Field<Int>
    /// Optional command description; options and localized descriptions remain unprojected.
    public let commandDescription: Field<String>
    /// Complete original object including future fields and exact numeric lexemes; diagnostics conceal payloads.
    public let rawFields: [String: JSONValue]

    /// Parses one complete API v10 object synchronously with exact unknown-field retention.
    /// - Parameters:
    ///   - data: Complete UTF-8 JSON object. Required nullable keys must exist; optional omissions remain distinct
    ///     from explicit null. Known fields are checked, while unprojected related-family details remain partial.
    ///   - limits: Whole-document bounds covering unknown subtrees: defaults to 1,048,576 UTF-8 bytes,
    ///     container depth 64 and 100,000 JSON values. Byte/node bounds must be positive and depth in 1...128.
    /// - Throws: `JSONValueError` for invalid limits, syntax, Unicode, duplicate keys or exceeded bounds;
    ///   `DiscordError.transport(.invalidResponse)` for missing, forbidden-null, mistyped or out-of-range
    ///   modeled fields. Errors do not disclose payload values; correct the input or limits before retrying.
    /// No I/O, suspension, credential access, cache mutation or ownership changes occur. Decoding is bounded
    /// synchronous work and does not observe cooperative task cancellation during construction.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects one immutable subtree after its complete containing document passed the parser's bounds.
    /// - Parameters:
    ///   - value: Original object subtree; the bounded root is a caller-established invariant.
    ///   - limits: Bounds established at the root, reused for exact scalar decoding.
    /// - Throws: Sanitized invalid-response errors for nonobject roots, missing required values, forbidden null,
    ///   incompatible modeled types or exact integer/identifier overflow. Unknown values are not normalized.
    /// Construction shares immutable JSON storage without reparsing nested objects, suspending, performing I/O
    /// or changing ownership. Parser bounds are enforced at the public data initializer rather than here.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        id = try object.required("id", ApplicationCommandID.self)
        applicationID = try object.field("application_id", ApplicationID.self)
        guildID = try object.field("guild_id", GuildID.self)
        name = try object.field("name", String.self)
        type = try object.field("type", Int.self)
        commandDescription = try object.field("description", String.self)
        rawFields = object.resource.fields
    }
}

/// An explicitly partial scheduled event referenced by an audit response. Recurrence, entity metadata, timing,
/// subscriber counts and other event fields remain exact in rawFields; this wrapper does not claim scheduling
/// operations, event subscription support or complete Scheduled Event schema parity.
/// API v10; verified 2026-10-16 against https://docs.discord.com/developers/resources/audit-log
/// and https://github.com/discord/discord-api-spec/blob/main/specs/openapi.json.
public struct AuditLogScheduledEvent: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Required exact scheduled event identifier.
    public let id: GuildScheduledEventID
    /// Optional owning guild identifier within this partial projection.
    public let guildID: Field<GuildID>
    /// Optional nullable hosting channel; explicit null is valid for an external scheduled event.
    public let channelID: Field<ChannelID>
    /// Optional event display name.
    public let name: Field<String>
    /// Optional exact integral entity kind, including future kinds without guessed semantics.
    public let entityType: Field<Int>
    /// Optional exact integral event status, without inferring a current legal transition.
    public let status: Field<Int>
    /// Complete original object including future fields and exact numeric lexemes; diagnostics conceal payloads.
    public let rawFields: [String: JSONValue]

    /// Parses one complete API v10 object synchronously with exact unknown-field retention.
    /// - Parameters:
    ///   - data: Complete UTF-8 JSON object. Required nullable keys must exist; optional omissions remain distinct
    ///     from explicit null. Known fields are checked, while unprojected related-family details remain partial.
    ///   - limits: Whole-document bounds covering unknown subtrees: defaults to 1,048,576 UTF-8 bytes,
    ///     container depth 64 and 100,000 JSON values. Byte/node bounds must be positive and depth in 1...128.
    /// - Throws: `JSONValueError` for invalid limits, syntax, Unicode, duplicate keys or exceeded bounds;
    ///   `DiscordError.transport(.invalidResponse)` for missing, forbidden-null, mistyped or out-of-range
    ///   modeled fields. Errors do not disclose payload values; correct the input or limits before retrying.
    /// No I/O, suspension, credential access, cache mutation or ownership changes occur. Decoding is bounded
    /// synchronous work and does not observe cooperative task cancellation during construction.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects one immutable subtree after its complete containing document passed the parser's bounds.
    /// - Parameters:
    ///   - value: Original object subtree; the bounded root is a caller-established invariant.
    ///   - limits: Bounds established at the root, reused for exact scalar decoding.
    /// - Throws: Sanitized invalid-response errors for nonobject roots, missing required values, forbidden null,
    ///   incompatible modeled types or exact integer/identifier overflow. Unknown values are not normalized.
    /// Construction shares immutable JSON storage without reparsing nested objects, suspending, performing I/O
    /// or changing ownership. Parser bounds are enforced at the public data initializer rather than here.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        id = try object.required("id", GuildScheduledEventID.self)
        guildID = try object.field("guild_id", GuildID.self)
        channelID = try object.field("channel_id", ChannelID.self, nullable: true)
        name = try object.field("name", String.self)
        entityType = try object.field("entity_type", Int.self)
        status = try object.field("status", Int.self)
        rawFields = object.resource.fields
    }
}

/// An explicitly partial webhook snapshot referenced by an audit response. Token, source guild/channel and
/// webhook User fields remain exact in rawFields and concealed from ordinary diagnostics. Parsing never fetches
/// URLs, executes webhooks, grants token access or claims complete Webhook model/endpoint parity.
/// API v10; verified 2026-10-16 against https://docs.discord.com/developers/resources/audit-log
/// and https://github.com/discord/discord-api-spec/blob/main/specs/openapi.json.
public struct AuditLogWebhook: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Required exact webhook snowflake.
    public let id: WebhookID
    /// Optional exact integral webhook kind, including future variants.
    public let type: Field<Int>
    /// Optional guild identifier, retained independently of channel and webhook type.
    public let guildID: Field<GuildID>
    /// Optional nullable webhook channel identifier.
    public let channelID: Field<ChannelID>
    /// Optional nullable default webhook name; omission and explicit null remain separate.
    public let name: Field<String>
    /// Optional nullable avatar hash, retained without constructing or fetching an asset URL.
    public let avatar: Field<String>
    /// Optional nullable application owning the webhook.
    public let applicationID: Field<ApplicationID>
    /// Complete original object including future fields and exact numeric lexemes; diagnostics conceal payloads.
    public let rawFields: [String: JSONValue]

    /// Parses one complete API v10 object synchronously with exact unknown-field retention.
    /// - Parameters:
    ///   - data: Complete UTF-8 JSON object. Required nullable keys must exist; optional omissions remain distinct
    ///     from explicit null. Known fields are checked, while unprojected related-family details remain partial.
    ///   - limits: Whole-document bounds covering unknown subtrees: defaults to 1,048,576 UTF-8 bytes,
    ///     container depth 64 and 100,000 JSON values. Byte/node bounds must be positive and depth in 1...128.
    /// - Throws: `JSONValueError` for invalid limits, syntax, Unicode, duplicate keys or exceeded bounds;
    ///   `DiscordError.transport(.invalidResponse)` for missing, forbidden-null, mistyped or out-of-range
    ///   modeled fields. Errors do not disclose payload values; correct the input or limits before retrying.
    /// No I/O, suspension, credential access, cache mutation or ownership changes occur. Decoding is bounded
    /// synchronous work and does not observe cooperative task cancellation during construction.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects one immutable subtree after its complete containing document passed the parser's bounds.
    /// - Parameters:
    ///   - value: Original object subtree; the bounded root is a caller-established invariant.
    ///   - limits: Bounds established at the root, reused for exact scalar decoding.
    /// - Throws: Sanitized invalid-response errors for nonobject roots, missing required values, forbidden null,
    ///   incompatible modeled types or exact integer/identifier overflow. Unknown values are not normalized.
    /// Construction shares immutable JSON storage without reparsing nested objects, suspending, performing I/O
    /// or changing ownership. Parser bounds are enforced at the public data initializer rather than here.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        id = try object.required("id", WebhookID.self)
        type = try object.field("type", Int.self)
        guildID = try object.field("guild_id", GuildID.self)
        channelID = try object.field("channel_id", ChannelID.self, nullable: true)
        name = try object.field("name", String.self, nullable: true)
        avatar = try object.field("avatar", String.self, nullable: true)
        applicationID = try object.field("application_id", ApplicationID.self, nullable: true)
        rawFields = object.resource.fields
    }
}

/// A complete audit log response envelope with all eight required arrays. Entries retain server wire order:
/// before/default queries normally descend by entry ID and after queries ascend. Empty arrays are valid;
/// no sorting, pagination completion inference, related-resource fetching or cross-page cache is performed.
/// Threads use the implemented Channel projection. Users and command/event/webhook families
/// remain explicitly partial. Auto Moderation rules use the complete implemented projection; the official
/// preview permits null rule elements, preserved by Nullable.
/// API v10; verified 2026-10-16 against https://docs.discord.com/developers/resources/audit-log
/// and https://github.com/discord/discord-api-spec/blob/main/specs/openapi.json.
public struct AuditLog: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Required ordered referenced commands, projected explicitly partially.
    public let applicationCommands: [AuditLogApplicationCommand]
    /// Required ordered administrative entries exactly as returned; no implicit sorting or deduplication.
    public let auditLogEntries: [AuditLogEntry]
    /// Required ordered referenced rules; explicit null slots survive per the official preview schema.
    public let autoModerationRules: [Nullable<AutoModerationRule>]
    /// Required ordered referenced scheduled events, projected explicitly partially.
    public let guildScheduledEvents: [AuditLogScheduledEvent]
    /// Required ordered audit-specific partial integrations; ordinary full Integration fields are not required.
    public let integrations: [AuditLogIntegration]
    /// Required ordered referenced thread channels, including archived threads from create/update actions.
    public let threads: [Channel]
    /// Required ordered users using an explicitly partial existing User projection; no full User parity claim.
    public let users: [ChannelRecipient]
    /// Required ordered referenced webhook snapshots, projected explicitly partially.
    public let webhooks: [AuditLogWebhook]
    /// Complete original object including future fields and exact numeric lexemes; diagnostics conceal payloads.
    public let rawFields: [String: JSONValue]

    /// Parses one complete API v10 object synchronously with exact unknown-field retention.
    /// - Parameters:
    ///   - data: Complete UTF-8 JSON object. Required nullable keys must exist; optional omissions remain distinct
    ///     from explicit null. Known fields are checked, while unprojected related-family details remain partial.
    ///   - limits: Whole-document bounds covering unknown subtrees: defaults to 1,048,576 UTF-8 bytes,
    ///     container depth 64 and 100,000 JSON values. Byte/node bounds must be positive and depth in 1...128.
    /// - Throws: `JSONValueError` for invalid limits, syntax, Unicode, duplicate keys or exceeded bounds;
    ///   `DiscordError.transport(.invalidResponse)` for missing, forbidden-null, mistyped or out-of-range
    ///   modeled fields. Errors do not disclose payload values; correct the input or limits before retrying.
    /// No I/O, suspension, credential access, cache mutation or ownership changes occur. Decoding is bounded
    /// synchronous work and does not observe cooperative task cancellation during construction.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects one immutable subtree after its complete containing document passed the parser's bounds.
    /// - Parameters:
    ///   - value: Original object subtree; the bounded root is a caller-established invariant.
    ///   - limits: Bounds established at the root, reused for exact scalar decoding.
    /// - Throws: Sanitized invalid-response errors for nonobject roots, missing required values, forbidden null,
    ///   incompatible modeled types or exact integer/identifier overflow. Unknown values are not normalized.
    /// Construction shares immutable JSON storage without reparsing nested objects, suspending, performing I/O
    /// or changing ownership. Parser bounds are enforced at the public data initializer rather than here.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        applicationCommands = try object.messageModels("application_commands", AuditLogApplicationCommand.self)
        auditLogEntries = try object.messageModels("audit_log_entries", AuditLogEntry.self)
        guard case .array(let rules) = object.resource.fields["auto_moderation_rules"] else {
            throw DiscordError.transport(.invalidResponse)
        }
        autoModerationRules = try rules.map { $0 == .null ? .null : .value(try AutoModerationRule(value: $0, limits: limits)) }
        guildScheduledEvents = try object.messageModels("guild_scheduled_events", AuditLogScheduledEvent.self)
        integrations = try object.messageModels("integrations", AuditLogIntegration.self)
        threads = try object.messageModels("threads", Channel.self)
        users = try object.messageModels("users", ChannelRecipient.self)
        webhooks = try object.messageModels("webhooks", AuditLogWebhook.self)
        rawFields = object.resource.fields
    }
}
