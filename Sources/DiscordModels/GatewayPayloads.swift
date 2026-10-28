// File: Sources/DiscordModels/GatewayPayloads.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import Foundation


/// Guild deletion or READY availability marker. Omitted unavailable on GUILD_DELETE means removal; true means outage. It never implies an available full Guild snapshot.
/// API v10; verified 2026-10-16 against https://docs.discord.com/developers/events/gateway-events.
public struct GatewayGuildAvailability: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Required nonnull `id` wire value; unknown siblings remain in rawFields.
    public let id: GuildID
    /// Optional nonnull `unavailable` wire value; unknown siblings remain in rawFields.
    public let unavailable: Field<Bool>
    /// Original complete object, including future fields and exact numeric lexemes; ordinary diagnostics redact it.
    public let rawFields: [String: JSONValue]

    /// Parses an immutable dispatch payload synchronously without I/O, tasks or ownership changes.
    /// - Parameters:
    ///   - data: Complete UTF-8 object. Required nullable keys must exist; optional keys retain absence.
    ///   - limits: Whole-document bounds including unknown fields; defaults to 1 MiB, depth 64, and 100,000 nodes.
    /// - Throws: JSON syntax, duplicate-key or bound errors; sanitized invalid-response errors for missing,
    ///   forbidden-null, mistyped or out-of-range known fields. Parsing does not suspend or inspect cancellation.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects a previously bounded subtree while retaining exact unknown values.
    /// - Parameters:
    ///   - value: Original object from a complete containing document that passed its parser bounds.
    ///   - limits: The same document bounds, reused for scalar and subtree projections.
    /// - Throws: Sanitized invalid-response errors for incompatible modeled fields; no payload values are disclosed.
    /// This synchronous operation shares immutable storage and owns no external resources.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        id = try object.required("id", GuildID.self)
        unavailable = try object.field("unavailable", Bool.self)
        rawFields = object.resource.fields
    }
}

/// READY partial application containing application identity and legacy/current flag representations. flags_new preserves omission within the partial object; decimal digits retain arbitrary width.
/// API v10; verified 2026-10-16 against https://docs.discord.com/developers/events/gateway-events.
public struct GatewayReadyApplication: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Required nonnull `id` wire value; unknown siblings remain in rawFields.
    public let id: ApplicationID
    /// Required nonnull `flags` wire value; unknown siblings remain in rawFields.
    public let flags: UInt64
    /// Optional nonnull `flags_new` wire value; unknown siblings remain in rawFields.
    public let flagsNew: Field<String>
    /// Original complete object, including future fields and exact numeric lexemes; ordinary diagnostics redact it.
    public let rawFields: [String: JSONValue]

    /// Parses an immutable dispatch payload synchronously without I/O, tasks or ownership changes.
    /// - Parameters:
    ///   - data: Complete UTF-8 object. Required nullable keys must exist; optional keys retain absence.
    ///   - limits: Whole-document bounds including unknown fields; defaults to 1 MiB, depth 64, and 100,000 nodes.
    /// - Throws: JSON syntax, duplicate-key or bound errors; sanitized invalid-response errors for missing,
    ///   forbidden-null, mistyped or out-of-range known fields. Parsing does not suspend or inspect cancellation.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects a previously bounded subtree while retaining exact unknown values.
    /// - Parameters:
    ///   - value: Original object from a complete containing document that passed its parser bounds.
    ///   - limits: The same document bounds, reused for scalar and subtree projections.
    /// - Throws: Sanitized invalid-response errors for incompatible modeled fields; no payload values are disclosed.
    /// This synchronous operation shares immutable storage and owns no external resources.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        id = try object.required("id", ApplicationID.self)
        flags = try object.required("flags", UInt64.self)
        flagsNew = try object.field("flags_new", String.self)
        if case .value(let digits) = flagsNew {
            guard !digits.isEmpty, digits.utf8.allSatisfy({ (48...57).contains($0) })
            else { throw DiscordError.transport(.invalidResponse) }
        }
        rawFields = object.resource.fields
    }
}

/// Initial Gateway v10 session state. Guilds remain unavailable until GUILD_CREATE; shard-local ordering and server visibility do not establish cache completeness. Session and resume fields are secrets in ordinary diagnostics.
/// API v10; verified 2026-10-16 against https://docs.discord.com/developers/events/gateway-events.
public struct GatewayReady: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Required nonnull `v` wire value; unknown siblings remain in rawFields.
    public let v: Int
    /// Required nonnull `user` wire value; unknown siblings remain in rawFields.
    public let user: User
    /// Required nonnull `guilds` wire value; unknown siblings remain in rawFields.
    public let guilds: [GatewayGuildAvailability]
    /// Required nonnull `session_id` wire value; unknown siblings remain in rawFields.
    public let sessionID: String
    /// Required nonnull `resume_gateway_url` wire value; unknown siblings remain in rawFields.
    public let resumeGatewayURL: String
    /// Optional nonnull `shard` wire value; unknown siblings remain in rawFields.
    public let shard: Field<[Int]>
    /// Required nonnull `application` wire value; unknown siblings remain in rawFields.
    public let application: GatewayReadyApplication
    /// Original complete object, including future fields and exact numeric lexemes; ordinary diagnostics redact it.
    public let rawFields: [String: JSONValue]

    /// Parses an immutable dispatch payload synchronously without I/O, tasks or ownership changes.
    /// - Parameters:
    ///   - data: Complete UTF-8 object. Required nullable keys must exist; optional keys retain absence.
    ///   - limits: Whole-document bounds including unknown fields; defaults to 1 MiB, depth 64, and 100,000 nodes.
    /// - Throws: JSON syntax, duplicate-key or bound errors; sanitized invalid-response errors for missing,
    ///   forbidden-null, mistyped or out-of-range known fields. Parsing does not suspend or inspect cancellation.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects a previously bounded subtree while retaining exact unknown values.
    /// - Parameters:
    ///   - value: Original object from a complete containing document that passed its parser bounds.
    ///   - limits: The same document bounds, reused for scalar and subtree projections.
    /// - Throws: Sanitized invalid-response errors for incompatible modeled fields; no payload values are disclosed.
    /// This synchronous operation shares immutable storage and owns no external resources.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        v = try object.required("v", Int.self)
        user = try object.messageModel("user", User.self)
        guilds = try object.messageModels("guilds", GatewayGuildAvailability.self)
        sessionID = try object.required("session_id", String.self)
        resumeGatewayURL = try object.required("resume_gateway_url", String.self)
        shard = try gatewayIntegerArray(object, name: "shard")
        application = try object.messageModel("application", GatewayReadyApplication.self)
        guard v > 0 else { throw DiscordError.transport(.invalidResponse) }
        if case .value(let pair) = shard {
            guard pair.count == 2, pair[1] > 0, pair[0] >= 0, pair[0] < pair[1]
            else { throw DiscordError.transport(.invalidResponse) }
        }
        rawFields = object.resource.fields
    }
}

/// Resume acknowledgment. Unknown tracing fields survive without a modeled contract; replayed dispatches retain per-shard arrival order.
/// API v10; verified 2026-10-16 against https://docs.discord.com/developers/events/gateway-events.
public struct GatewayResumed: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Original complete object, including future fields and exact numeric lexemes; ordinary diagnostics redact it.
    public let rawFields: [String: JSONValue]

    /// Parses an immutable dispatch payload synchronously without I/O, tasks or ownership changes.
    /// - Parameters:
    ///   - data: Complete UTF-8 object. Required nullable keys must exist; optional keys retain absence.
    ///   - limits: Whole-document bounds including unknown fields; defaults to 1 MiB, depth 64, and 100,000 nodes.
    /// - Throws: JSON syntax, duplicate-key or bound errors; sanitized invalid-response errors for missing,
    ///   forbidden-null, mistyped or out-of-range known fields. Parsing does not suspend or inspect cancellation.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects a previously bounded subtree while retaining exact unknown values.
    /// - Parameters:
    ///   - value: Original object from a complete containing document that passed its parser bounds.
    ///   - limits: The same document bounds, reused for scalar and subtree projections.
    /// - Throws: Sanitized invalid-response errors for incompatible modeled fields; no payload values are disclosed.
    /// This synchronous operation shares immutable storage and owns no external resources.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        rawFields = object.resource.fields
    }
}

/// Executed Auto Moderation action; requires MANAGE_GUILD. Content and matched content can be omitted without MESSAGE_CONTENT; omission must never erase previously observed text.
/// API v10; verified 2026-10-16 against https://docs.discord.com/developers/events/gateway-events.
public struct GatewayAutoModerationActionExecution: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Required nonnull `guild_id` wire value; unknown siblings remain in rawFields.
    public let guildID: GuildID
    /// Required nonnull `action` wire value; unknown siblings remain in rawFields.
    public let action: AutoModerationAction
    /// Required nonnull `rule_id` wire value; unknown siblings remain in rawFields.
    public let ruleID: AutoModerationRuleID
    /// Required nonnull `rule_trigger_type` wire value; unknown siblings remain in rawFields.
    public let ruleTriggerType: RawValue<AutoModerationTriggerType>
    /// Required nonnull `user_id` wire value; unknown siblings remain in rawFields.
    public let userID: UserID
    /// Optional nonnull `channel_id` wire value; unknown siblings remain in rawFields.
    public let channelID: Field<ChannelID>
    /// Optional nonnull `message_id` wire value; unknown siblings remain in rawFields.
    public let messageID: Field<MessageID>
    /// Optional nonnull `alert_system_message_id` wire value; unknown siblings remain in rawFields.
    public let alertSystemMessageID: Field<MessageID>
    /// Optional nonnull `content` wire value; unknown siblings remain in rawFields.
    public let content: Field<String>
    /// Required nullable `matched_keyword` wire value; unknown siblings remain in rawFields.
    public let matchedKeyword: Nullable<String>
    /// Optional nullable `matched_content` wire value; unknown siblings remain in rawFields.
    public let matchedContent: Field<String>
    /// Original complete object, including future fields and exact numeric lexemes; ordinary diagnostics redact it.
    public let rawFields: [String: JSONValue]

    /// Parses an immutable dispatch payload synchronously without I/O, tasks or ownership changes.
    /// - Parameters:
    ///   - data: Complete UTF-8 object. Required nullable keys must exist; optional keys retain absence.
    ///   - limits: Whole-document bounds including unknown fields; defaults to 1 MiB, depth 64, and 100,000 nodes.
    /// - Throws: JSON syntax, duplicate-key or bound errors; sanitized invalid-response errors for missing,
    ///   forbidden-null, mistyped or out-of-range known fields. Parsing does not suspend or inspect cancellation.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects a previously bounded subtree while retaining exact unknown values.
    /// - Parameters:
    ///   - value: Original object from a complete containing document that passed its parser bounds.
    ///   - limits: The same document bounds, reused for scalar and subtree projections.
    /// - Throws: Sanitized invalid-response errors for incompatible modeled fields; no payload values are disclosed.
    /// This synchronous operation shares immutable storage and owns no external resources.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        guildID = try object.required("guild_id", GuildID.self)
        action = try object.messageModel("action", AutoModerationAction.self)
        ruleID = try object.required("rule_id", AutoModerationRuleID.self)
        ruleTriggerType = try object.required("rule_trigger_type", RawValue<AutoModerationTriggerType>.self)
        userID = try object.required("user_id", UserID.self)
        channelID = try object.field("channel_id", ChannelID.self)
        messageID = try object.field("message_id", MessageID.self)
        alertSystemMessageID = try object.field("alert_system_message_id", MessageID.self)
        content = try object.field("content", String.self)
        matchedKeyword = try object.required("matched_keyword", Nullable<String>.self)
        matchedContent = try object.field("matched_content", String.self, nullable: true)
        rawFields = object.resource.fields
    }
}

/// Ephemeral channel information. Voice start times are Unix seconds; omitted and null values retain distinct meanings.
/// API v10; verified 2026-10-16 against https://docs.discord.com/developers/events/gateway-events.
public struct GatewayChannelInfoChannel: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Required nonnull `id` wire value; unknown siblings remain in rawFields.
    public let id: ChannelID
    /// Optional nullable `status` wire value; unknown siblings remain in rawFields.
    public let status: Field<String>
    /// Optional nullable `voice_start_time` wire value; unknown siblings remain in rawFields.
    public let voiceStartTime: Field<Int64>
    /// Original complete object, including future fields and exact numeric lexemes; ordinary diagnostics redact it.
    public let rawFields: [String: JSONValue]

    /// Parses an immutable dispatch payload synchronously without I/O, tasks or ownership changes.
    /// - Parameters:
    ///   - data: Complete UTF-8 object. Required nullable keys must exist; optional keys retain absence.
    ///   - limits: Whole-document bounds including unknown fields; defaults to 1 MiB, depth 64, and 100,000 nodes.
    /// - Throws: JSON syntax, duplicate-key or bound errors; sanitized invalid-response errors for missing,
    ///   forbidden-null, mistyped or out-of-range known fields. Parsing does not suspend or inspect cancellation.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects a previously bounded subtree while retaining exact unknown values.
    /// - Parameters:
    ///   - value: Original object from a complete containing document that passed its parser bounds.
    ///   - limits: The same document bounds, reused for scalar and subtree projections.
    /// - Throws: Sanitized invalid-response errors for incompatible modeled fields; no payload values are disclosed.
    /// This synchronous operation shares immutable storage and owns no external resources.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        id = try object.required("id", ChannelID.self)
        status = try object.field("status", String.self, nullable: true)
        voiceStartTime = try object.field("voice_start_time", Int64.self, nullable: true)
        rawFields = object.resource.fields
    }
}

/// Response to Request Channel Info. There is no documented nonce; correlation uses the guild and requested field scope.
/// API v10; verified 2026-10-16 against https://docs.discord.com/developers/events/gateway-events.
public struct GatewayChannelInfo: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Required nonnull `guild_id` wire value; unknown siblings remain in rawFields.
    public let guildID: GuildID
    /// Required nonnull `channels` wire value; unknown siblings remain in rawFields.
    public let channels: [GatewayChannelInfoChannel]
    /// Original complete object, including future fields and exact numeric lexemes; ordinary diagnostics redact it.
    public let rawFields: [String: JSONValue]

    /// Parses an immutable dispatch payload synchronously without I/O, tasks or ownership changes.
    /// - Parameters:
    ///   - data: Complete UTF-8 object. Required nullable keys must exist; optional keys retain absence.
    ///   - limits: Whole-document bounds including unknown fields; defaults to 1 MiB, depth 64, and 100,000 nodes.
    /// - Throws: JSON syntax, duplicate-key or bound errors; sanitized invalid-response errors for missing,
    ///   forbidden-null, mistyped or out-of-range known fields. Parsing does not suspend or inspect cancellation.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects a previously bounded subtree while retaining exact unknown values.
    /// - Parameters:
    ///   - value: Original object from a complete containing document that passed its parser bounds.
    ///   - limits: The same document bounds, reused for scalar and subtree projections.
    /// - Throws: Sanitized invalid-response errors for incompatible modeled fields; no payload values are disclosed.
    /// This synchronous operation shares immutable storage and owns no external resources.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        guildID = try object.required("guild_id", GuildID.self)
        channels = try object.messageModels("channels", GatewayChannelInfoChannel.self)
        rawFields = object.resource.fields
    }
}

/// Voice channel status replacement. Null clears the status; omission is malformed.
/// API v10; verified 2026-10-16 against https://docs.discord.com/developers/events/gateway-events.
public struct GatewayVoiceChannelStatusUpdate: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Required nonnull `id` wire value; unknown siblings remain in rawFields.
    public let id: ChannelID
    /// Required nonnull `guild_id` wire value; unknown siblings remain in rawFields.
    public let guildID: GuildID
    /// Required nullable `status` wire value; unknown siblings remain in rawFields.
    public let status: Nullable<String>
    /// Original complete object, including future fields and exact numeric lexemes; ordinary diagnostics redact it.
    public let rawFields: [String: JSONValue]

    /// Parses an immutable dispatch payload synchronously without I/O, tasks or ownership changes.
    /// - Parameters:
    ///   - data: Complete UTF-8 object. Required nullable keys must exist; optional keys retain absence.
    ///   - limits: Whole-document bounds including unknown fields; defaults to 1 MiB, depth 64, and 100,000 nodes.
    /// - Throws: JSON syntax, duplicate-key or bound errors; sanitized invalid-response errors for missing,
    ///   forbidden-null, mistyped or out-of-range known fields. Parsing does not suspend or inspect cancellation.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects a previously bounded subtree while retaining exact unknown values.
    /// - Parameters:
    ///   - value: Original object from a complete containing document that passed its parser bounds.
    ///   - limits: The same document bounds, reused for scalar and subtree projections.
    /// - Throws: Sanitized invalid-response errors for incompatible modeled fields; no payload values are disclosed.
    /// This synchronous operation shares immutable storage and owns no external resources.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        id = try object.required("id", ChannelID.self)
        guildID = try object.required("guild_id", GuildID.self)
        status = try object.required("status", Nullable<String>.self)
        rawFields = object.resource.fields
    }
}

/// Voice session start-time update in Unix seconds. Omission is retained separately from explicit null.
/// API v10; verified 2026-10-16 against https://docs.discord.com/developers/events/gateway-events.
public struct GatewayVoiceChannelStartTimeUpdate: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Required nonnull `id` wire value; unknown siblings remain in rawFields.
    public let id: ChannelID
    /// Required nonnull `guild_id` wire value; unknown siblings remain in rawFields.
    public let guildID: GuildID
    /// Optional nullable `voice_start_time` wire value; unknown siblings remain in rawFields.
    public let voiceStartTime: Field<Int64>
    /// Original complete object, including future fields and exact numeric lexemes; ordinary diagnostics redact it.
    public let rawFields: [String: JSONValue]

    /// Parses an immutable dispatch payload synchronously without I/O, tasks or ownership changes.
    /// - Parameters:
    ///   - data: Complete UTF-8 object. Required nullable keys must exist; optional keys retain absence.
    ///   - limits: Whole-document bounds including unknown fields; defaults to 1 MiB, depth 64, and 100,000 nodes.
    /// - Throws: JSON syntax, duplicate-key or bound errors; sanitized invalid-response errors for missing,
    ///   forbidden-null, mistyped or out-of-range known fields. Parsing does not suspend or inspect cancellation.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects a previously bounded subtree while retaining exact unknown values.
    /// - Parameters:
    ///   - value: Original object from a complete containing document that passed its parser bounds.
    ///   - limits: The same document bounds, reused for scalar and subtree projections.
    /// - Throws: Sanitized invalid-response errors for incompatible modeled fields; no payload values are disclosed.
    /// This synchronous operation shares immutable storage and owns no external resources.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        id = try object.required("id", ChannelID.self)
        guildID = try object.required("guild_id", GuildID.self)
        voiceStartTime = try object.field("voice_start_time", Int64.self, nullable: true)
        rawFields = object.resource.fields
    }
}

/// Thread creation or private-thread access. The complete Channel contains the optional current thread member; newlyCreated is present for newly created threads.
/// API v10; verified 2026-10-16 against https://docs.discord.com/developers/events/gateway-events.
public struct GatewayThreadCreate: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Typed Channel view of this same event object; this is not a nested `channel` wire field.
    public let channel: Channel
    /// Optional nonnull `newly_created` wire value; unknown siblings remain in rawFields.
    public let newlyCreated: Field<Bool>
    /// Original complete object, including future fields and exact numeric lexemes; ordinary diagnostics redact it.
    public let rawFields: [String: JSONValue]

    /// Parses an immutable dispatch payload synchronously without I/O, tasks or ownership changes.
    /// - Parameters:
    ///   - data: Complete UTF-8 object. Required nullable keys must exist; optional keys retain absence.
    ///   - limits: Whole-document bounds including unknown fields; defaults to 1 MiB, depth 64, and 100,000 nodes.
    /// - Throws: JSON syntax, duplicate-key or bound errors; sanitized invalid-response errors for missing,
    ///   forbidden-null, mistyped or out-of-range known fields. Parsing does not suspend or inspect cancellation.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects a previously bounded subtree while retaining exact unknown values.
    /// - Parameters:
    ///   - value: Original object from a complete containing document that passed its parser bounds.
    ///   - limits: The same document bounds, reused for scalar and subtree projections.
    /// - Throws: Sanitized invalid-response errors for incompatible modeled fields; no payload values are disclosed.
    /// This synchronous operation shares immutable storage and owns no external resources.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        channel = try Channel(value: value, limits: limits)
        newlyCreated = try object.field("newly_created", Bool.self)
        rawFields = object.resource.fields
    }
}

/// Minimal thread deletion shape. It deliberately does not require a complete Channel resource.
/// API v10; verified 2026-10-16 against https://docs.discord.com/developers/events/gateway-events.
public struct GatewayThreadDelete: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Required nonnull `id` wire value; unknown siblings remain in rawFields.
    public let id: ChannelID
    /// Required nonnull `guild_id` wire value; unknown siblings remain in rawFields.
    public let guildID: GuildID
    /// Required nonnull `parent_id` wire value; unknown siblings remain in rawFields.
    public let parentID: ChannelID
    /// Required nonnull `type` wire value; unknown siblings remain in rawFields.
    public let type: RawValue<ChannelType>
    /// Original complete object, including future fields and exact numeric lexemes; ordinary diagnostics redact it.
    public let rawFields: [String: JSONValue]

    /// Parses an immutable dispatch payload synchronously without I/O, tasks or ownership changes.
    /// - Parameters:
    ///   - data: Complete UTF-8 object. Required nullable keys must exist; optional keys retain absence.
    ///   - limits: Whole-document bounds including unknown fields; defaults to 1 MiB, depth 64, and 100,000 nodes.
    /// - Throws: JSON syntax, duplicate-key or bound errors; sanitized invalid-response errors for missing,
    ///   forbidden-null, mistyped or out-of-range known fields. Parsing does not suspend or inspect cancellation.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects a previously bounded subtree while retaining exact unknown values.
    /// - Parameters:
    ///   - value: Original object from a complete containing document that passed its parser bounds.
    ///   - limits: The same document bounds, reused for scalar and subtree projections.
    /// - Throws: Sanitized invalid-response errors for incompatible modeled fields; no payload values are disclosed.
    /// This synchronous operation shares immutable storage and owns no external resources.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        id = try object.required("id", ChannelID.self)
        guildID = try object.required("guild_id", GuildID.self)
        parentID = try object.required("parent_id", ChannelID.self)
        type = try object.required("type", RawValue<ChannelType>.self)
        rawFields = object.resource.fields
    }
}

/// Accessible active threads and current membership. Missing channelIDs means guild-wide synchronization; an empty array does not mean the same scope.
/// API v10; verified 2026-10-16 against https://docs.discord.com/developers/events/gateway-events.
public struct GatewayThreadListSync: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Required nonnull `guild_id` wire value; unknown siblings remain in rawFields.
    public let guildID: GuildID
    /// Optional nonnull `channel_ids` wire value; unknown siblings remain in rawFields.
    public let channelIDs: Field<[ChannelID]>
    /// Required nonnull `threads` wire value; unknown siblings remain in rawFields.
    public let threads: [Channel]
    /// Required nonnull `members` wire value; unknown siblings remain in rawFields.
    public let members: [ThreadMember]
    /// Original complete object, including future fields and exact numeric lexemes; ordinary diagnostics redact it.
    public let rawFields: [String: JSONValue]

    /// Parses an immutable dispatch payload synchronously without I/O, tasks or ownership changes.
    /// - Parameters:
    ///   - data: Complete UTF-8 object. Required nullable keys must exist; optional keys retain absence.
    ///   - limits: Whole-document bounds including unknown fields; defaults to 1 MiB, depth 64, and 100,000 nodes.
    /// - Throws: JSON syntax, duplicate-key or bound errors; sanitized invalid-response errors for missing,
    ///   forbidden-null, mistyped or out-of-range known fields. Parsing does not suspend or inspect cancellation.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects a previously bounded subtree while retaining exact unknown values.
    /// - Parameters:
    ///   - value: Original object from a complete containing document that passed its parser bounds.
    ///   - limits: The same document bounds, reused for scalar and subtree projections.
    /// - Throws: Sanitized invalid-response errors for incompatible modeled fields; no payload values are disclosed.
    /// This synchronous operation shares immutable storage and owns no external resources.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        guildID = try object.required("guild_id", GuildID.self)
        channelIDs = try object.field("channel_ids", [ChannelID].self)
        threads = try object.messageModels("threads", Channel.self)
        members = try object.messageModels("members", ThreadMember.self)
        rawFields = object.resource.fields
    }
}

/// Current-user thread membership update. This generally signals membership; it does not provide a complete guild member inventory.
/// API v10; verified 2026-10-16 against https://docs.discord.com/developers/events/gateway-events.
public struct GatewayThreadMemberUpdate: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Typed ThreadMember view of this same event object; this is not a nested `member` wire field.
    public let member: ThreadMember
    /// Required nonnull `guild_id` wire value; unknown siblings remain in rawFields.
    public let guildID: GuildID
    /// Original complete object, including future fields and exact numeric lexemes; ordinary diagnostics redact it.
    public let rawFields: [String: JSONValue]

    /// Parses an immutable dispatch payload synchronously without I/O, tasks or ownership changes.
    /// - Parameters:
    ///   - data: Complete UTF-8 object. Required nullable keys must exist; optional keys retain absence.
    ///   - limits: Whole-document bounds including unknown fields; defaults to 1 MiB, depth 64, and 100,000 nodes.
    /// - Throws: JSON syntax, duplicate-key or bound errors; sanitized invalid-response errors for missing,
    ///   forbidden-null, mistyped or out-of-range known fields. Parsing does not suspend or inspect cancellation.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects a previously bounded subtree while retaining exact unknown values.
    /// - Parameters:
    ///   - value: Original object from a complete containing document that passed its parser bounds.
    ///   - limits: The same document bounds, reused for scalar and subtree projections.
    /// - Throws: Sanitized invalid-response errors for incompatible modeled fields; no payload values are disclosed.
    /// This synchronous operation shares immutable storage and owns no external resources.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        member = try ThreadMember(value: value, limits: limits)
        guildID = try object.required("guild_id", GuildID.self)
        rawFields = object.resource.fields
    }
}

/// Added thread member including guild-member details exposed by ThreadMember and optional nullable presence. GUILD_MEMBERS controls delivery for other users.
/// API v10; verified 2026-10-16 against https://docs.discord.com/developers/events/gateway-events.
public struct GatewayThreadAddedMember: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Typed ThreadMember view of this same event object; this is not a nested `member` wire field.
    public let member: ThreadMember
    /// Optional nullable `presence` wire value; unknown siblings remain in rawFields.
    public let presence: Field<GatewayPartialPresence>
    /// Original complete object, including future fields and exact numeric lexemes; ordinary diagnostics redact it.
    public let rawFields: [String: JSONValue]

    /// Parses an immutable dispatch payload synchronously without I/O, tasks or ownership changes.
    /// - Parameters:
    ///   - data: Complete UTF-8 object. Required nullable keys must exist; optional keys retain absence.
    ///   - limits: Whole-document bounds including unknown fields; defaults to 1 MiB, depth 64, and 100,000 nodes.
    /// - Throws: JSON syntax, duplicate-key or bound errors; sanitized invalid-response errors for missing,
    ///   forbidden-null, mistyped or out-of-range known fields. Parsing does not suspend or inspect cancellation.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects a previously bounded subtree while retaining exact unknown values.
    /// - Parameters:
    ///   - value: Original object from a complete containing document that passed its parser bounds.
    ///   - limits: The same document bounds, reused for scalar and subtree projections.
    /// - Throws: Sanitized invalid-response errors for incompatible modeled fields; no payload values are disclosed.
    /// This synchronous operation shares immutable storage and owns no external resources.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        member = try ThreadMember(value: value, limits: limits)
        presence = try object.messageField("presence", GatewayPartialPresence.self, nullable: true)
        rawFields = object.resource.fields
    }
}

/// Thread membership delta. memberCount is approximate and capped at 50, never an authoritative full member count.
/// API v10; verified 2026-10-16 against https://docs.discord.com/developers/events/gateway-events.
public struct GatewayThreadMembersUpdate: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Required nonnull `id` wire value; unknown siblings remain in rawFields.
    public let id: ChannelID
    /// Required nonnull `guild_id` wire value; unknown siblings remain in rawFields.
    public let guildID: GuildID
    /// Required nonnull `member_count` wire value; unknown siblings remain in rawFields.
    public let memberCount: Int
    /// Optional nonnull `added_members` wire value; unknown siblings remain in rawFields.
    public let addedMembers: Field<[GatewayThreadAddedMember]>
    /// Optional nonnull `removed_member_ids` wire value; unknown siblings remain in rawFields.
    public let removedMemberIDs: Field<[UserID]>
    /// Original complete object, including future fields and exact numeric lexemes; ordinary diagnostics redact it.
    public let rawFields: [String: JSONValue]

    /// Parses an immutable dispatch payload synchronously without I/O, tasks or ownership changes.
    /// - Parameters:
    ///   - data: Complete UTF-8 object. Required nullable keys must exist; optional keys retain absence.
    ///   - limits: Whole-document bounds including unknown fields; defaults to 1 MiB, depth 64, and 100,000 nodes.
    /// - Throws: JSON syntax, duplicate-key or bound errors; sanitized invalid-response errors for missing,
    ///   forbidden-null, mistyped or out-of-range known fields. Parsing does not suspend or inspect cancellation.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects a previously bounded subtree while retaining exact unknown values.
    /// - Parameters:
    ///   - value: Original object from a complete containing document that passed its parser bounds.
    ///   - limits: The same document bounds, reused for scalar and subtree projections.
    /// - Throws: Sanitized invalid-response errors for incompatible modeled fields; no payload values are disclosed.
    /// This synchronous operation shares immutable storage and owns no external resources.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        id = try object.required("id", ChannelID.self)
        guildID = try object.required("guild_id", GuildID.self)
        memberCount = try object.required("member_count", Int.self)
        addedMembers = try object.messageArray("added_members", GatewayThreadAddedMember.self)
        removedMemberIDs = try object.field("removed_member_ids", [UserID].self)
        guard (0...50).contains(memberCount) else { throw DiscordError.transport(.invalidResponse) }
        rawFields = object.resource.fields
    }
}

/// Pin change notification. Deletion of a pinned message does not produce this dispatch; nullable time and absent time remain distinct.
/// API v10; verified 2026-10-16 against https://docs.discord.com/developers/events/gateway-events.
public struct GatewayChannelPinsUpdate: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Optional nonnull `guild_id` wire value; unknown siblings remain in rawFields.
    public let guildID: Field<GuildID>
    /// Required nonnull `channel_id` wire value; unknown siblings remain in rawFields.
    public let channelID: ChannelID
    /// Optional nullable `last_pin_timestamp` wire value; unknown siblings remain in rawFields.
    public let lastPinTimestamp: Field<DiscordTimestamp>
    /// Original complete object, including future fields and exact numeric lexemes; ordinary diagnostics redact it.
    public let rawFields: [String: JSONValue]

    /// Parses an immutable dispatch payload synchronously without I/O, tasks or ownership changes.
    /// - Parameters:
    ///   - data: Complete UTF-8 object. Required nullable keys must exist; optional keys retain absence.
    ///   - limits: Whole-document bounds including unknown fields; defaults to 1 MiB, depth 64, and 100,000 nodes.
    /// - Throws: JSON syntax, duplicate-key or bound errors; sanitized invalid-response errors for missing,
    ///   forbidden-null, mistyped or out-of-range known fields. Parsing does not suspend or inspect cancellation.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects a previously bounded subtree while retaining exact unknown values.
    /// - Parameters:
    ///   - value: Original object from a complete containing document that passed its parser bounds.
    ///   - limits: The same document bounds, reused for scalar and subtree projections.
    /// - Throws: Sanitized invalid-response errors for incompatible modeled fields; no payload values are disclosed.
    /// This synchronous operation shares immutable storage and owns no external resources.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        guildID = try object.field("guild_id", GuildID.self)
        channelID = try object.required("channel_id", ChannelID.self)
        lastPinTimestamp = try object.field("last_pin_timestamp", DiscordTimestamp.self, nullable: true)
        rawFields = object.resource.fields
    }
}

/// Available GUILD_CREATE with the full Guild plus Gateway-owned state. Members/presences can be restricted by intents, large threshold and guild size, and must not be treated as complete.
/// API v10; verified 2026-10-16 against https://docs.discord.com/developers/events/gateway-events.
public struct GatewayAvailableGuild: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Typed Guild view of this same event object; this is not a nested `guild` wire field.
    public let guild: Guild
    /// Required nonnull `joined_at` wire value; unknown siblings remain in rawFields.
    public let joinedAt: DiscordTimestamp
    /// Required nonnull `large` wire value; unknown siblings remain in rawFields.
    public let large: Bool
    /// Optional nonnull `unavailable` wire value; unknown siblings remain in rawFields.
    public let unavailable: Field<Bool>
    /// Required nonnull `member_count` wire value; unknown siblings remain in rawFields.
    public let memberCount: Int
    /// Required nonnull `voice_states` wire value; unknown siblings remain in rawFields.
    public let voiceStates: [VoiceState]
    /// Required nonnull `members` wire value; unknown siblings remain in rawFields.
    public let members: [GuildMember]
    /// Required nonnull `channels` wire value; unknown siblings remain in rawFields.
    public let channels: [Channel]
    /// Required nonnull `threads` wire value; unknown siblings remain in rawFields.
    public let threads: [Channel]
    /// Required nonnull `presences` wire value; unknown siblings remain in rawFields.
    public let presences: [GatewayPartialPresence]
    /// Required nonnull `stage_instances` wire value; unknown siblings remain in rawFields.
    public let stageInstances: [StageInstance]
    /// Required nonnull `guild_scheduled_events` wire value; unknown siblings remain in rawFields.
    public let guildScheduledEvents: [GuildScheduledEvent]
    /// Required nonnull `soundboard_sounds` wire value; unknown siblings remain in rawFields.
    public let soundboardSounds: [SoundboardSound]
    /// Original complete object, including future fields and exact numeric lexemes; ordinary diagnostics redact it.
    public let rawFields: [String: JSONValue]

    /// Parses an immutable dispatch payload synchronously without I/O, tasks or ownership changes.
    /// - Parameters:
    ///   - data: Complete UTF-8 object. Required nullable keys must exist; optional keys retain absence.
    ///   - limits: Whole-document bounds including unknown fields; defaults to 1 MiB, depth 64, and 100,000 nodes.
    /// - Throws: JSON syntax, duplicate-key or bound errors; sanitized invalid-response errors for missing,
    ///   forbidden-null, mistyped or out-of-range known fields. Parsing does not suspend or inspect cancellation.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects a previously bounded subtree while retaining exact unknown values.
    /// - Parameters:
    ///   - value: Original object from a complete containing document that passed its parser bounds.
    ///   - limits: The same document bounds, reused for scalar and subtree projections.
    /// - Throws: Sanitized invalid-response errors for incompatible modeled fields; no payload values are disclosed.
    /// This synchronous operation shares immutable storage and owns no external resources.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        guild = try Guild(value: value, limits: limits)
        joinedAt = try object.required("joined_at", DiscordTimestamp.self)
        large = try object.required("large", Bool.self)
        unavailable = try object.field("unavailable", Bool.self)
        memberCount = try object.required("member_count", Int.self)
        voiceStates = try object.messageModels("voice_states", VoiceState.self)
        members = try object.messageModels("members", GuildMember.self)
        channels = try object.messageModels("channels", Channel.self)
        threads = try object.messageModels("threads", Channel.self)
        presences = try object.messageModels("presences", GatewayPartialPresence.self)
        stageInstances = try object.messageModels("stage_instances", StageInstance.self)
        guildScheduledEvents = try object.messageModels("guild_scheduled_events", GuildScheduledEvent.self)
        soundboardSounds = try object.messageModels("soundboard_sounds", SoundboardSound.self)
        guard memberCount >= 0 else { throw DiscordError.transport(.invalidResponse) }
        rawFields = object.resource.fields
    }
}

/// Audit-log creation; requires VIEW_AUDIT_LOG and applicable intent. Entry fields retain their existing typed resource semantics.
/// API v10; verified 2026-10-16 against https://docs.discord.com/developers/events/gateway-events.
public struct GatewayGuildAuditLogEntryCreate: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Typed AuditLogEntry view of this same event object; this is not a nested `entry` wire field.
    public let entry: AuditLogEntry
    /// Required nonnull `guild_id` wire value; unknown siblings remain in rawFields.
    public let guildID: GuildID
    /// Original complete object, including future fields and exact numeric lexemes; ordinary diagnostics redact it.
    public let rawFields: [String: JSONValue]

    /// Parses an immutable dispatch payload synchronously without I/O, tasks or ownership changes.
    /// - Parameters:
    ///   - data: Complete UTF-8 object. Required nullable keys must exist; optional keys retain absence.
    ///   - limits: Whole-document bounds including unknown fields; defaults to 1 MiB, depth 64, and 100,000 nodes.
    /// - Throws: JSON syntax, duplicate-key or bound errors; sanitized invalid-response errors for missing,
    ///   forbidden-null, mistyped or out-of-range known fields. Parsing does not suspend or inspect cancellation.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects a previously bounded subtree while retaining exact unknown values.
    /// - Parameters:
    ///   - value: Original object from a complete containing document that passed its parser bounds.
    ///   - limits: The same document bounds, reused for scalar and subtree projections.
    /// - Throws: Sanitized invalid-response errors for incompatible modeled fields; no payload values are disclosed.
    /// This synchronous operation shares immutable storage and owns no external resources.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        entry = try AuditLogEntry(value: value, limits: limits)
        guildID = try object.required("guild_id", GuildID.self)
        rawFields = object.resource.fields
    }
}

/// User plus guild for ban add/remove and member removal. BAN_MEMBERS or VIEW_AUDIT_LOG applies to ban events; GUILD_MEMBERS applies to removal.
/// API v10; verified 2026-10-16 against https://docs.discord.com/developers/events/gateway-events.
public struct GatewayGuildUser: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Required nonnull `guild_id` wire value; unknown siblings remain in rawFields.
    public let guildID: GuildID
    /// Required nonnull `user` wire value; unknown siblings remain in rawFields.
    public let user: User
    /// Original complete object, including future fields and exact numeric lexemes; ordinary diagnostics redact it.
    public let rawFields: [String: JSONValue]

    /// Parses an immutable dispatch payload synchronously without I/O, tasks or ownership changes.
    /// - Parameters:
    ///   - data: Complete UTF-8 object. Required nullable keys must exist; optional keys retain absence.
    ///   - limits: Whole-document bounds including unknown fields; defaults to 1 MiB, depth 64, and 100,000 nodes.
    /// - Throws: JSON syntax, duplicate-key or bound errors; sanitized invalid-response errors for missing,
    ///   forbidden-null, mistyped or out-of-range known fields. Parsing does not suspend or inspect cancellation.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects a previously bounded subtree while retaining exact unknown values.
    /// - Parameters:
    ///   - value: Original object from a complete containing document that passed its parser bounds.
    ///   - limits: The same document bounds, reused for scalar and subtree projections.
    /// - Throws: Sanitized invalid-response errors for incompatible modeled fields; no payload values are disclosed.
    /// This synchronous operation shares immutable storage and owns no external resources.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        guildID = try object.required("guild_id", GuildID.self)
        user = try object.messageModel("user", User.self)
        rawFields = object.resource.fields
    }
}

/// Guild emoji replacement snapshot; users and flags retain existing resource projections and unknown values.
/// API v10; verified 2026-10-16 against https://docs.discord.com/developers/events/gateway-events.
public struct GatewayGuildEmojisUpdate: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Required nonnull `guild_id` wire value; unknown siblings remain in rawFields.
    public let guildID: GuildID
    /// Required nonnull `emojis` wire value; unknown siblings remain in rawFields.
    public let emojis: [Emoji]
    /// Original complete object, including future fields and exact numeric lexemes; ordinary diagnostics redact it.
    public let rawFields: [String: JSONValue]

    /// Parses an immutable dispatch payload synchronously without I/O, tasks or ownership changes.
    /// - Parameters:
    ///   - data: Complete UTF-8 object. Required nullable keys must exist; optional keys retain absence.
    ///   - limits: Whole-document bounds including unknown fields; defaults to 1 MiB, depth 64, and 100,000 nodes.
    /// - Throws: JSON syntax, duplicate-key or bound errors; sanitized invalid-response errors for missing,
    ///   forbidden-null, mistyped or out-of-range known fields. Parsing does not suspend or inspect cancellation.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects a previously bounded subtree while retaining exact unknown values.
    /// - Parameters:
    ///   - value: Original object from a complete containing document that passed its parser bounds.
    ///   - limits: The same document bounds, reused for scalar and subtree projections.
    /// - Throws: Sanitized invalid-response errors for incompatible modeled fields; no payload values are disclosed.
    /// This synchronous operation shares immutable storage and owns no external resources.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        guildID = try object.required("guild_id", GuildID.self)
        emojis = try object.messageModels("emojis", Emoji.self)
        rawFields = object.resource.fields
    }
}

/// Guild sticker replacement snapshot, preserving server order and future sticker variants.
/// API v10; verified 2026-10-16 against https://docs.discord.com/developers/events/gateway-events.
public struct GatewayGuildStickersUpdate: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Required nonnull `guild_id` wire value; unknown siblings remain in rawFields.
    public let guildID: GuildID
    /// Required nonnull `stickers` wire value; unknown siblings remain in rawFields.
    public let stickers: [Sticker]
    /// Original complete object, including future fields and exact numeric lexemes; ordinary diagnostics redact it.
    public let rawFields: [String: JSONValue]

    /// Parses an immutable dispatch payload synchronously without I/O, tasks or ownership changes.
    /// - Parameters:
    ///   - data: Complete UTF-8 object. Required nullable keys must exist; optional keys retain absence.
    ///   - limits: Whole-document bounds including unknown fields; defaults to 1 MiB, depth 64, and 100,000 nodes.
    /// - Throws: JSON syntax, duplicate-key or bound errors; sanitized invalid-response errors for missing,
    ///   forbidden-null, mistyped or out-of-range known fields. Parsing does not suspend or inspect cancellation.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects a previously bounded subtree while retaining exact unknown values.
    /// - Parameters:
    ///   - value: Original object from a complete containing document that passed its parser bounds.
    ///   - limits: The same document bounds, reused for scalar and subtree projections.
    /// - Throws: Sanitized invalid-response errors for incompatible modeled fields; no payload values are disclosed.
    /// This synchronous operation shares immutable storage and owns no external resources.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        guildID = try object.required("guild_id", GuildID.self)
        stickers = try object.messageModels("stickers", Sticker.self)
        rawFields = object.resource.fields
    }
}

/// Guild integration invalidation signal; it includes no complete integration snapshot.
/// API v10; verified 2026-10-16 against https://docs.discord.com/developers/events/gateway-events.
public struct GatewayGuildIntegrationsUpdate: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Required nonnull `guild_id` wire value; unknown siblings remain in rawFields.
    public let guildID: GuildID
    /// Original complete object, including future fields and exact numeric lexemes; ordinary diagnostics redact it.
    public let rawFields: [String: JSONValue]

    /// Parses an immutable dispatch payload synchronously without I/O, tasks or ownership changes.
    /// - Parameters:
    ///   - data: Complete UTF-8 object. Required nullable keys must exist; optional keys retain absence.
    ///   - limits: Whole-document bounds including unknown fields; defaults to 1 MiB, depth 64, and 100,000 nodes.
    /// - Throws: JSON syntax, duplicate-key or bound errors; sanitized invalid-response errors for missing,
    ///   forbidden-null, mistyped or out-of-range known fields. Parsing does not suspend or inspect cancellation.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects a previously bounded subtree while retaining exact unknown values.
    /// - Parameters:
    ///   - value: Original object from a complete containing document that passed its parser bounds.
    ///   - limits: The same document bounds, reused for scalar and subtree projections.
    /// - Throws: Sanitized invalid-response errors for incompatible modeled fields; no payload values are disclosed.
    /// This synchronous operation shares immutable storage and owns no external resources.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        guildID = try object.required("guild_id", GuildID.self)
        rawFields = object.resource.fields
    }
}

/// Guild member addition or repeated existing member notification; requires GUILD_MEMBERS. Duplicate delivery is possible and does not imply exactly-once semantics.
/// API v10; verified 2026-10-16 against https://docs.discord.com/developers/events/gateway-events.
public struct GatewayGuildMemberAdd: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Typed GuildMember view of this same event object; this is not a nested `member` wire field.
    public let member: GuildMember
    /// Required nonnull `guild_id` wire value; unknown siblings remain in rawFields.
    public let guildID: GuildID
    /// Original complete object, including future fields and exact numeric lexemes; ordinary diagnostics redact it.
    public let rawFields: [String: JSONValue]

    /// Parses an immutable dispatch payload synchronously without I/O, tasks or ownership changes.
    /// - Parameters:
    ///   - data: Complete UTF-8 object. Required nullable keys must exist; optional keys retain absence.
    ///   - limits: Whole-document bounds including unknown fields; defaults to 1 MiB, depth 64, and 100,000 nodes.
    /// - Throws: JSON syntax, duplicate-key or bound errors; sanitized invalid-response errors for missing,
    ///   forbidden-null, mistyped or out-of-range known fields. Parsing does not suspend or inspect cancellation.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects a previously bounded subtree while retaining exact unknown values.
    /// - Parameters:
    ///   - value: Original object from a complete containing document that passed its parser bounds.
    ///   - limits: The same document bounds, reused for scalar and subtree projections.
    /// - Throws: Sanitized invalid-response errors for incompatible modeled fields; no payload values are disclosed.
    /// This synchronous operation shares immutable storage and owns no external resources.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        member = try GuildMember(value: value, limits: limits)
        guildID = try object.required("guild_id", GuildID.self)
        rawFields = object.resource.fields
    }
}

/// Guild member update; requires GUILD_MEMBERS. Nullable joinedAt supports guest members; omission of optional fields preserves the prior projection.
/// API v10; verified 2026-10-16 against https://docs.discord.com/developers/events/gateway-events.
public struct GatewayGuildMemberUpdate: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Required nonnull `guild_id` wire value; unknown siblings remain in rawFields.
    public let guildID: GuildID
    /// Required nonnull `roles` wire value; unknown siblings remain in rawFields.
    public let roles: [RoleID]
    /// Required nonnull `user` wire value; unknown siblings remain in rawFields.
    public let user: User
    /// Optional nullable `nick` wire value; unknown siblings remain in rawFields.
    public let nick: Field<String>
    /// Required nullable `avatar` wire value; unknown siblings remain in rawFields.
    public let avatar: Nullable<String>
    /// Required nullable `banner` wire value; unknown siblings remain in rawFields.
    public let banner: Nullable<String>
    /// Required nullable `joined_at` wire value; unknown siblings remain in rawFields.
    public let joinedAt: Nullable<DiscordTimestamp>
    /// Optional nullable `premium_since` wire value; unknown siblings remain in rawFields.
    public let premiumSince: Field<DiscordTimestamp>
    /// Optional nonnull `deaf` wire value; unknown siblings remain in rawFields.
    public let deaf: Field<Bool>
    /// Optional nonnull `mute` wire value; unknown siblings remain in rawFields.
    public let mute: Field<Bool>
    /// Optional nonnull `pending` wire value; unknown siblings remain in rawFields.
    public let pending: Field<Bool>
    /// Optional nullable `communication_disabled_until` wire value; unknown siblings remain in rawFields.
    public let communicationDisabledUntil: Field<DiscordTimestamp>
    /// Optional nullable `avatar_decoration_data` wire value; unknown siblings remain in rawFields.
    public let avatarDecorationData: Field<UserAvatarDecoration>
    /// Optional nullable `collectibles` wire value; unknown siblings remain in rawFields.
    public let collectibles: Field<UserCollectibles>
    /// Original complete object, including future fields and exact numeric lexemes; ordinary diagnostics redact it.
    public let rawFields: [String: JSONValue]

    /// Parses an immutable dispatch payload synchronously without I/O, tasks or ownership changes.
    /// - Parameters:
    ///   - data: Complete UTF-8 object. Required nullable keys must exist; optional keys retain absence.
    ///   - limits: Whole-document bounds including unknown fields; defaults to 1 MiB, depth 64, and 100,000 nodes.
    /// - Throws: JSON syntax, duplicate-key or bound errors; sanitized invalid-response errors for missing,
    ///   forbidden-null, mistyped or out-of-range known fields. Parsing does not suspend or inspect cancellation.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects a previously bounded subtree while retaining exact unknown values.
    /// - Parameters:
    ///   - value: Original object from a complete containing document that passed its parser bounds.
    ///   - limits: The same document bounds, reused for scalar and subtree projections.
    /// - Throws: Sanitized invalid-response errors for incompatible modeled fields; no payload values are disclosed.
    /// This synchronous operation shares immutable storage and owns no external resources.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        guildID = try object.required("guild_id", GuildID.self)
        roles = try object.required("roles", [RoleID].self)
        user = try object.messageModel("user", User.self)
        nick = try object.field("nick", String.self, nullable: true)
        avatar = try object.required("avatar", Nullable<String>.self)
        banner = try object.required("banner", Nullable<String>.self)
        joinedAt = try object.required("joined_at", Nullable<DiscordTimestamp>.self)
        premiumSince = try object.field("premium_since", DiscordTimestamp.self, nullable: true)
        deaf = try object.field("deaf", Bool.self)
        mute = try object.field("mute", Bool.self)
        pending = try object.field("pending", Bool.self)
        communicationDisabledUntil = try object.field("communication_disabled_until", DiscordTimestamp.self, nullable: true)
        avatarDecorationData = try object.messageField("avatar_decoration_data", UserAvatarDecoration.self, nullable: true)
        collectibles = try object.messageField("collectibles", UserCollectibles.self, nullable: true)
        rawFields = object.resource.fields
    }
}

/// Response chunk for Request Guild Members. Nonce is echoed only when valid; duplicate and reordered chunks need correlation outside this immutable model.
/// API v10; verified 2026-10-16 against https://docs.discord.com/developers/events/gateway-events.
public struct GatewayGuildMembersChunk: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Required nonnull `guild_id` wire value; unknown siblings remain in rawFields.
    public let guildID: GuildID
    /// Required nonnull `members` wire value; unknown siblings remain in rawFields.
    public let members: [GuildMember]
    /// Required nonnull `chunk_index` wire value; unknown siblings remain in rawFields.
    public let chunkIndex: Int
    /// Required nonnull `chunk_count` wire value; unknown siblings remain in rawFields.
    public let chunkCount: Int
    /// Optional nonnull `not_found` wire value; unknown siblings remain in rawFields.
    public let notFound: Field<[UserID]>
    /// Optional nonnull `presences` wire value; unknown siblings remain in rawFields.
    public let presences: Field<[GatewayPartialPresence]>
    /// Optional nonnull `nonce` wire value; unknown siblings remain in rawFields.
    public let nonce: Field<String>
    /// Original complete object, including future fields and exact numeric lexemes; ordinary diagnostics redact it.
    public let rawFields: [String: JSONValue]

    /// Parses an immutable dispatch payload synchronously without I/O, tasks or ownership changes.
    /// - Parameters:
    ///   - data: Complete UTF-8 object. Required nullable keys must exist; optional keys retain absence.
    ///   - limits: Whole-document bounds including unknown fields; defaults to 1 MiB, depth 64, and 100,000 nodes.
    /// - Throws: JSON syntax, duplicate-key or bound errors; sanitized invalid-response errors for missing,
    ///   forbidden-null, mistyped or out-of-range known fields. Parsing does not suspend or inspect cancellation.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects a previously bounded subtree while retaining exact unknown values.
    /// - Parameters:
    ///   - value: Original object from a complete containing document that passed its parser bounds.
    ///   - limits: The same document bounds, reused for scalar and subtree projections.
    /// - Throws: Sanitized invalid-response errors for incompatible modeled fields; no payload values are disclosed.
    /// This synchronous operation shares immutable storage and owns no external resources.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        guildID = try object.required("guild_id", GuildID.self)
        members = try object.messageModels("members", GuildMember.self)
        chunkIndex = try object.required("chunk_index", Int.self)
        chunkCount = try object.required("chunk_count", Int.self)
        notFound = try object.field("not_found", [UserID].self)
        presences = try object.messageArray("presences", GatewayPartialPresence.self)
        nonce = try object.field("nonce", String.self)
        guard chunkCount > 0, chunkIndex >= 0, chunkIndex < chunkCount else {
            throw DiscordError.transport(.invalidResponse)
        }
        rawFields = object.resource.fields
    }
}

/// Guild role create/update wrapper retaining the complete current typed Role resource.
/// API v10; verified 2026-10-16 against https://docs.discord.com/developers/events/gateway-events.
public struct GatewayGuildRoleUpdate: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Required nonnull `guild_id` wire value; unknown siblings remain in rawFields.
    public let guildID: GuildID
    /// Required nonnull `role` wire value; unknown siblings remain in rawFields.
    public let role: GuildRole
    /// Original complete object, including future fields and exact numeric lexemes; ordinary diagnostics redact it.
    public let rawFields: [String: JSONValue]

    /// Parses an immutable dispatch payload synchronously without I/O, tasks or ownership changes.
    /// - Parameters:
    ///   - data: Complete UTF-8 object. Required nullable keys must exist; optional keys retain absence.
    ///   - limits: Whole-document bounds including unknown fields; defaults to 1 MiB, depth 64, and 100,000 nodes.
    /// - Throws: JSON syntax, duplicate-key or bound errors; sanitized invalid-response errors for missing,
    ///   forbidden-null, mistyped or out-of-range known fields. Parsing does not suspend or inspect cancellation.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects a previously bounded subtree while retaining exact unknown values.
    /// - Parameters:
    ///   - value: Original object from a complete containing document that passed its parser bounds.
    ///   - limits: The same document bounds, reused for scalar and subtree projections.
    /// - Throws: Sanitized invalid-response errors for incompatible modeled fields; no payload values are disclosed.
    /// This synchronous operation shares immutable storage and owns no external resources.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        guildID = try object.required("guild_id", GuildID.self)
        role = try object.messageModel("role", GuildRole.self)
        rawFields = object.resource.fields
    }
}

/// Guild role deletion identity; no resource fetch or mutation occurs during parsing.
/// API v10; verified 2026-10-16 against https://docs.discord.com/developers/events/gateway-events.
public struct GatewayGuildRoleDelete: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Required nonnull `guild_id` wire value; unknown siblings remain in rawFields.
    public let guildID: GuildID
    /// Required nonnull `role_id` wire value; unknown siblings remain in rawFields.
    public let roleID: RoleID
    /// Original complete object, including future fields and exact numeric lexemes; ordinary diagnostics redact it.
    public let rawFields: [String: JSONValue]

    /// Parses an immutable dispatch payload synchronously without I/O, tasks or ownership changes.
    /// - Parameters:
    ///   - data: Complete UTF-8 object. Required nullable keys must exist; optional keys retain absence.
    ///   - limits: Whole-document bounds including unknown fields; defaults to 1 MiB, depth 64, and 100,000 nodes.
    /// - Throws: JSON syntax, duplicate-key or bound errors; sanitized invalid-response errors for missing,
    ///   forbidden-null, mistyped or out-of-range known fields. Parsing does not suspend or inspect cancellation.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects a previously bounded subtree while retaining exact unknown values.
    /// - Parameters:
    ///   - value: Original object from a complete containing document that passed its parser bounds.
    ///   - limits: The same document bounds, reused for scalar and subtree projections.
    /// - Throws: Sanitized invalid-response errors for incompatible modeled fields; no payload values are disclosed.
    /// This synchronous operation shares immutable storage and owns no external resources.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        guildID = try object.required("guild_id", GuildID.self)
        roleID = try object.required("role_id", RoleID.self)
        rawFields = object.resource.fields
    }
}

/// Scheduled-event subscription addition/removal identity. It is independent of paid app subscriptions.
/// API v10; verified 2026-10-16 against https://docs.discord.com/developers/events/gateway-events.
public struct GatewayScheduledEventUser: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Required nonnull `guild_scheduled_event_id` wire value; unknown siblings remain in rawFields.
    public let guildScheduledEventID: GuildScheduledEventID
    /// Required nonnull `user_id` wire value; unknown siblings remain in rawFields.
    public let userID: UserID
    /// Required nonnull `guild_id` wire value; unknown siblings remain in rawFields.
    public let guildID: GuildID
    /// Original complete object, including future fields and exact numeric lexemes; ordinary diagnostics redact it.
    public let rawFields: [String: JSONValue]

    /// Parses an immutable dispatch payload synchronously without I/O, tasks or ownership changes.
    /// - Parameters:
    ///   - data: Complete UTF-8 object. Required nullable keys must exist; optional keys retain absence.
    ///   - limits: Whole-document bounds including unknown fields; defaults to 1 MiB, depth 64, and 100,000 nodes.
    /// - Throws: JSON syntax, duplicate-key or bound errors; sanitized invalid-response errors for missing,
    ///   forbidden-null, mistyped or out-of-range known fields. Parsing does not suspend or inspect cancellation.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects a previously bounded subtree while retaining exact unknown values.
    /// - Parameters:
    ///   - value: Original object from a complete containing document that passed its parser bounds.
    ///   - limits: The same document bounds, reused for scalar and subtree projections.
    /// - Throws: Sanitized invalid-response errors for incompatible modeled fields; no payload values are disclosed.
    /// This synchronous operation shares immutable storage and owns no external resources.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        guildScheduledEventID = try object.required("guild_scheduled_event_id", GuildScheduledEventID.self)
        userID = try object.required("user_id", UserID.self)
        guildID = try object.required("guild_id", GuildID.self)
        rawFields = object.resource.fields
    }
}

/// Deleted guild soundboard identity; no audio is decoded or played.
/// API v10; verified 2026-10-16 against https://docs.discord.com/developers/events/gateway-events.
public struct GatewayGuildSoundboardSoundDelete: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Required nonnull `sound_id` wire value; unknown siblings remain in rawFields.
    public let soundID: SoundboardSoundID
    /// Required nonnull `guild_id` wire value; unknown siblings remain in rawFields.
    public let guildID: GuildID
    /// Original complete object, including future fields and exact numeric lexemes; ordinary diagnostics redact it.
    public let rawFields: [String: JSONValue]

    /// Parses an immutable dispatch payload synchronously without I/O, tasks or ownership changes.
    /// - Parameters:
    ///   - data: Complete UTF-8 object. Required nullable keys must exist; optional keys retain absence.
    ///   - limits: Whole-document bounds including unknown fields; defaults to 1 MiB, depth 64, and 100,000 nodes.
    /// - Throws: JSON syntax, duplicate-key or bound errors; sanitized invalid-response errors for missing,
    ///   forbidden-null, mistyped or out-of-range known fields. Parsing does not suspend or inspect cancellation.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects a previously bounded subtree while retaining exact unknown values.
    /// - Parameters:
    ///   - value: Original object from a complete containing document that passed its parser bounds.
    ///   - limits: The same document bounds, reused for scalar and subtree projections.
    /// - Throws: Sanitized invalid-response errors for incompatible modeled fields; no payload values are disclosed.
    /// This synchronous operation shares immutable storage and owns no external resources.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        soundID = try object.required("sound_id", SoundboardSoundID.self)
        guildID = try object.required("guild_id", GuildID.self)
        rawFields = object.resource.fields
    }
}

/// Guild soundboard replacement or Request Soundboard Sounds response. No nonce is documented; correlate using guild identity.
/// API v10; verified 2026-10-16 against https://docs.discord.com/developers/events/gateway-events.
public struct GatewaySoundboardSounds: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Required nonnull `soundboard_sounds` wire value; unknown siblings remain in rawFields.
    public let soundboardSounds: [SoundboardSound]
    /// Required nonnull `guild_id` wire value; unknown siblings remain in rawFields.
    public let guildID: GuildID
    /// Original complete object, including future fields and exact numeric lexemes; ordinary diagnostics redact it.
    public let rawFields: [String: JSONValue]

    /// Parses an immutable dispatch payload synchronously without I/O, tasks or ownership changes.
    /// - Parameters:
    ///   - data: Complete UTF-8 object. Required nullable keys must exist; optional keys retain absence.
    ///   - limits: Whole-document bounds including unknown fields; defaults to 1 MiB, depth 64, and 100,000 nodes.
    /// - Throws: JSON syntax, duplicate-key or bound errors; sanitized invalid-response errors for missing,
    ///   forbidden-null, mistyped or out-of-range known fields. Parsing does not suspend or inspect cancellation.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects a previously bounded subtree while retaining exact unknown values.
    /// - Parameters:
    ///   - value: Original object from a complete containing document that passed its parser bounds.
    ///   - limits: The same document bounds, reused for scalar and subtree projections.
    /// - Throws: Sanitized invalid-response errors for incompatible modeled fields; no payload values are disclosed.
    /// This synchronous operation shares immutable storage and owns no external resources.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        soundboardSounds = try object.messageModels("soundboard_sounds", SoundboardSound.self)
        guildID = try object.required("guild_id", GuildID.self)
        rawFields = object.resource.fields
    }
}

/// Integration create/update snapshot. Discord omits the optional User; the underlying resource preserves external opaque integration IDs.
/// API v10; verified 2026-10-16 against https://docs.discord.com/developers/events/gateway-events.
public struct GatewayIntegrationUpdate: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Typed GuildIntegration view of this same event object; this is not a nested `integration` wire field.
    public let integration: GuildIntegration
    /// Required nonnull `guild_id` wire value; unknown siblings remain in rawFields.
    public let guildID: GuildID
    /// Original complete object, including future fields and exact numeric lexemes; ordinary diagnostics redact it.
    public let rawFields: [String: JSONValue]

    /// Parses an immutable dispatch payload synchronously without I/O, tasks or ownership changes.
    /// - Parameters:
    ///   - data: Complete UTF-8 object. Required nullable keys must exist; optional keys retain absence.
    ///   - limits: Whole-document bounds including unknown fields; defaults to 1 MiB, depth 64, and 100,000 nodes.
    /// - Throws: JSON syntax, duplicate-key or bound errors; sanitized invalid-response errors for missing,
    ///   forbidden-null, mistyped or out-of-range known fields. Parsing does not suspend or inspect cancellation.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects a previously bounded subtree while retaining exact unknown values.
    /// - Parameters:
    ///   - value: Original object from a complete containing document that passed its parser bounds.
    ///   - limits: The same document bounds, reused for scalar and subtree projections.
    /// - Throws: Sanitized invalid-response errors for incompatible modeled fields; no payload values are disclosed.
    /// This synchronous operation shares immutable storage and owns no external resources.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        integration = try GuildIntegration(value: value, limits: limits)
        guildID = try object.required("guild_id", GuildID.self)
        rawFields = object.resource.fields
    }
}

/// Deleted integration identity and optional associated application.
/// API v10; verified 2026-10-16 against https://docs.discord.com/developers/events/gateway-events.
public struct GatewayIntegrationDelete: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Required nonnull `id` wire value; unknown siblings remain in rawFields.
    public let id: GuildIntegrationID
    /// Required nonnull `guild_id` wire value; unknown siblings remain in rawFields.
    public let guildID: GuildID
    /// Optional nonnull `application_id` wire value; unknown siblings remain in rawFields.
    public let applicationID: Field<ApplicationID>
    /// Original complete object, including future fields and exact numeric lexemes; ordinary diagnostics redact it.
    public let rawFields: [String: JSONValue]

    /// Parses an immutable dispatch payload synchronously without I/O, tasks or ownership changes.
    /// - Parameters:
    ///   - data: Complete UTF-8 object. Required nullable keys must exist; optional keys retain absence.
    ///   - limits: Whole-document bounds including unknown fields; defaults to 1 MiB, depth 64, and 100,000 nodes.
    /// - Throws: JSON syntax, duplicate-key or bound errors; sanitized invalid-response errors for missing,
    ///   forbidden-null, mistyped or out-of-range known fields. Parsing does not suspend or inspect cancellation.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects a previously bounded subtree while retaining exact unknown values.
    /// - Parameters:
    ///   - value: Original object from a complete containing document that passed its parser bounds.
    ///   - limits: The same document bounds, reused for scalar and subtree projections.
    /// - Throws: Sanitized invalid-response errors for incompatible modeled fields; no payload values are disclosed.
    /// This synchronous operation shares immutable storage and owns no external resources.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        id = try object.required("id", GuildIntegrationID.self)
        guildID = try object.required("guild_id", GuildID.self)
        applicationID = try object.field("application_id", ApplicationID.self)
        rawFields = object.resource.fields
    }
}

/// Explicitly partial application on an invite. Fields outside the documented partial projection remain raw; it is not a complete Application.
/// API v10; verified 2026-10-16 against https://docs.discord.com/developers/events/gateway-events.
public struct GatewayInviteApplication: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Required nonnull `id` wire value; unknown siblings remain in rawFields.
    public let id: ApplicationID
    /// Optional nonnull `name` wire value; unknown siblings remain in rawFields.
    public let name: Field<String>
    /// Optional nullable `icon` wire value; unknown siblings remain in rawFields.
    public let icon: Field<String>
    /// Optional nonnull `description` wire value; unknown siblings remain in rawFields.
    public let applicationDescription: Field<String>
    /// Optional nonnull `cover_image` wire value; unknown siblings remain in rawFields.
    public let coverImage: Field<String>
    /// Optional nonnull `flags` wire value; unknown siblings remain in rawFields.
    public let flags: Field<UInt64>
    /// Original complete object, including future fields and exact numeric lexemes; ordinary diagnostics redact it.
    public let rawFields: [String: JSONValue]

    /// Parses an immutable dispatch payload synchronously without I/O, tasks or ownership changes.
    /// - Parameters:
    ///   - data: Complete UTF-8 object. Required nullable keys must exist; optional keys retain absence.
    ///   - limits: Whole-document bounds including unknown fields; defaults to 1 MiB, depth 64, and 100,000 nodes.
    /// - Throws: JSON syntax, duplicate-key or bound errors; sanitized invalid-response errors for missing,
    ///   forbidden-null, mistyped or out-of-range known fields. Parsing does not suspend or inspect cancellation.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects a previously bounded subtree while retaining exact unknown values.
    /// - Parameters:
    ///   - value: Original object from a complete containing document that passed its parser bounds.
    ///   - limits: The same document bounds, reused for scalar and subtree projections.
    /// - Throws: Sanitized invalid-response errors for incompatible modeled fields; no payload values are disclosed.
    /// This synchronous operation shares immutable storage and owns no external resources.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        id = try object.required("id", ApplicationID.self)
        name = try object.field("name", String.self)
        icon = try object.field("icon", String.self, nullable: true)
        applicationDescription = try object.field("description", String.self)
        coverImage = try object.field("cover_image", String.self)
        flags = try object.field("flags", UInt64.self)
        rawFields = object.resource.fields
    }
}

/// New invite; requires MANAGE_CHANNELS on the channel. Durations are seconds; invite codes and URLs are sensitive and redacted by ordinary diagnostics.
/// API v10; verified 2026-10-16 against https://docs.discord.com/developers/events/gateway-events.
public struct GatewayInviteCreate: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Required nonnull `channel_id` wire value; unknown siblings remain in rawFields.
    public let channelID: ChannelID
    /// Required nonnull `code` wire value; unknown siblings remain in rawFields.
    public let code: String
    /// Required nonnull `created_at` wire value; unknown siblings remain in rawFields.
    public let createdAt: DiscordTimestamp
    /// Optional nonnull `guild_id` wire value; unknown siblings remain in rawFields.
    public let guildID: Field<GuildID>
    /// Optional nonnull `inviter` wire value; unknown siblings remain in rawFields.
    public let inviter: Field<User>
    /// Required nonnull `max_age` wire value; unknown siblings remain in rawFields.
    public let maxAge: Int
    /// Required nonnull `max_uses` wire value; unknown siblings remain in rawFields.
    public let maxUses: Int
    /// Optional nonnull `target_type` wire value; unknown siblings remain in rawFields.
    public let targetType: Field<RawValue<ChannelInviteTargetType>>
    /// Optional nonnull `target_user` wire value; unknown siblings remain in rawFields.
    public let targetUser: Field<User>
    /// Optional nonnull `target_application` wire value; unknown siblings remain in rawFields.
    public let targetApplication: Field<GatewayInviteApplication>
    /// Required nonnull `temporary` wire value; unknown siblings remain in rawFields.
    public let temporary: Bool
    /// Required nonnull `uses` wire value; unknown siblings remain in rawFields.
    public let uses: Int
    /// Required nullable `expires_at` wire value; unknown siblings remain in rawFields.
    public let expiresAt: Nullable<DiscordTimestamp>
    /// Optional nonnull `role_ids` wire value; unknown siblings remain in rawFields.
    public let roleIDs: Field<[RoleID]>
    /// Original complete object, including future fields and exact numeric lexemes; ordinary diagnostics redact it.
    public let rawFields: [String: JSONValue]

    /// Parses an immutable dispatch payload synchronously without I/O, tasks or ownership changes.
    /// - Parameters:
    ///   - data: Complete UTF-8 object. Required nullable keys must exist; optional keys retain absence.
    ///   - limits: Whole-document bounds including unknown fields; defaults to 1 MiB, depth 64, and 100,000 nodes.
    /// - Throws: JSON syntax, duplicate-key or bound errors; sanitized invalid-response errors for missing,
    ///   forbidden-null, mistyped or out-of-range known fields. Parsing does not suspend or inspect cancellation.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects a previously bounded subtree while retaining exact unknown values.
    /// - Parameters:
    ///   - value: Original object from a complete containing document that passed its parser bounds.
    ///   - limits: The same document bounds, reused for scalar and subtree projections.
    /// - Throws: Sanitized invalid-response errors for incompatible modeled fields; no payload values are disclosed.
    /// This synchronous operation shares immutable storage and owns no external resources.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        channelID = try object.required("channel_id", ChannelID.self)
        code = try object.required("code", String.self)
        createdAt = try object.required("created_at", DiscordTimestamp.self)
        guildID = try object.field("guild_id", GuildID.self)
        inviter = try object.messageField("inviter", User.self)
        maxAge = try object.required("max_age", Int.self)
        maxUses = try object.required("max_uses", Int.self)
        targetType = try object.field("target_type", RawValue<ChannelInviteTargetType>.self)
        targetUser = try object.messageField("target_user", User.self)
        targetApplication = try object.messageField("target_application", GatewayInviteApplication.self)
        temporary = try object.required("temporary", Bool.self)
        uses = try object.required("uses", Int.self)
        expiresAt = try object.required("expires_at", Nullable<DiscordTimestamp>.self)
        roleIDs = try object.field("role_ids", [RoleID].self)
        rawFields = object.resource.fields
    }
}

/// Deleted invite; requires MANAGE_CHANNELS. An absent guild is preserved without inferring DM delivery.
/// API v10; verified 2026-10-16 against https://docs.discord.com/developers/events/gateway-events.
public struct GatewayInviteDelete: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Required nonnull `channel_id` wire value; unknown siblings remain in rawFields.
    public let channelID: ChannelID
    /// Optional nonnull `guild_id` wire value; unknown siblings remain in rawFields.
    public let guildID: Field<GuildID>
    /// Required nonnull `code` wire value; unknown siblings remain in rawFields.
    public let code: String
    /// Original complete object, including future fields and exact numeric lexemes; ordinary diagnostics redact it.
    public let rawFields: [String: JSONValue]

    /// Parses an immutable dispatch payload synchronously without I/O, tasks or ownership changes.
    /// - Parameters:
    ///   - data: Complete UTF-8 object. Required nullable keys must exist; optional keys retain absence.
    ///   - limits: Whole-document bounds including unknown fields; defaults to 1 MiB, depth 64, and 100,000 nodes.
    /// - Throws: JSON syntax, duplicate-key or bound errors; sanitized invalid-response errors for missing,
    ///   forbidden-null, mistyped or out-of-range known fields. Parsing does not suspend or inspect cancellation.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects a previously bounded subtree while retaining exact unknown values.
    /// - Parameters:
    ///   - value: Original object from a complete containing document that passed its parser bounds.
    ///   - limits: The same document bounds, reused for scalar and subtree projections.
    /// - Throws: Sanitized invalid-response errors for incompatible modeled fields; no payload values are disclosed.
    /// This synchronous operation shares immutable storage and owns no external resources.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        channelID = try object.required("channel_id", ChannelID.self)
        guildID = try object.field("guild_id", GuildID.self)
        code = try object.required("code", String.self)
        rawFields = object.resource.fields
    }
}

/// Mentioned user with optional partial guild-member fields supplied only by Gateway delivery.
/// API v10; verified 2026-10-16 against https://docs.discord.com/developers/events/gateway-events.
public struct GatewayMessageMention: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Typed User view of this same event object; this is not a nested `user` wire field.
    public let user: User
    /// Optional nonnull `member` wire value; unknown siblings remain in rawFields.
    public let member: Field<GatewayPartialGuildMember>
    /// Original complete object, including future fields and exact numeric lexemes; ordinary diagnostics redact it.
    public let rawFields: [String: JSONValue]

    /// Parses an immutable dispatch payload synchronously without I/O, tasks or ownership changes.
    /// - Parameters:
    ///   - data: Complete UTF-8 object. Required nullable keys must exist; optional keys retain absence.
    ///   - limits: Whole-document bounds including unknown fields; defaults to 1 MiB, depth 64, and 100,000 nodes.
    /// - Throws: JSON syntax, duplicate-key or bound errors; sanitized invalid-response errors for missing,
    ///   forbidden-null, mistyped or out-of-range known fields. Parsing does not suspend or inspect cancellation.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects a previously bounded subtree while retaining exact unknown values.
    /// - Parameters:
    ///   - value: Original object from a complete containing document that passed its parser bounds.
    ///   - limits: The same document bounds, reused for scalar and subtree projections.
    /// - Throws: Sanitized invalid-response errors for incompatible modeled fields; no payload values are disclosed.
    /// This synchronous operation shares immutable storage and owns no external resources.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        user = try User(value: value, limits: limits)
        member = try object.messageField("member", GatewayPartialGuildMember.self)
        rawFields = object.resource.fields
    }
}

/// Complete message and Gateway-owned context. Ephemeral messages use DIRECT_MESSAGES and omit guild/member; MESSAGE_CONTENT can redact text/media. Existing related-resource projections remain explicitly partial.
/// API v10; verified 2026-10-16 against https://docs.discord.com/developers/events/gateway-events.
public struct GatewayMessageCreate: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Typed Message view of this same event object; this is not a nested `message` wire field.
    public let message: Message
    /// Optional nonnull `guild_id` wire value; unknown siblings remain in rawFields.
    public let guildID: Field<GuildID>
    /// Optional nonnull `member` wire value; unknown siblings remain in rawFields.
    public let member: Field<GatewayPartialGuildMember>
    /// Required nonnull `mentions` wire value; unknown siblings remain in rawFields.
    public let mentions: [GatewayMessageMention]
    /// Optional nonnull `channel_type` wire value; unknown siblings remain in rawFields.
    public let channelType: Field<RawValue<ChannelType>>
    /// Original complete object, including future fields and exact numeric lexemes; ordinary diagnostics redact it.
    public let rawFields: [String: JSONValue]

    /// Parses an immutable dispatch payload synchronously without I/O, tasks or ownership changes.
    /// - Parameters:
    ///   - data: Complete UTF-8 object. Required nullable keys must exist; optional keys retain absence.
    ///   - limits: Whole-document bounds including unknown fields; defaults to 1 MiB, depth 64, and 100,000 nodes.
    /// - Throws: JSON syntax, duplicate-key or bound errors; sanitized invalid-response errors for missing,
    ///   forbidden-null, mistyped or out-of-range known fields. Parsing does not suspend or inspect cancellation.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects a previously bounded subtree while retaining exact unknown values.
    /// - Parameters:
    ///   - value: Original object from a complete containing document that passed its parser bounds.
    ///   - limits: The same document bounds, reused for scalar and subtree projections.
    /// - Throws: Sanitized invalid-response errors for incompatible modeled fields; no payload values are disclosed.
    /// This synchronous operation shares immutable storage and owns no external resources.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        message = try Message(value: value, limits: limits)
        guildID = try object.field("guild_id", GuildID.self)
        member = try object.messageField("member", GatewayPartialGuildMember.self)
        mentions = try object.messageModels("mentions", GatewayMessageMention.self)
        channelType = try object.field("channel_type", RawValue<ChannelType>.self)
        rawFields = object.resource.fields
    }
}

/// Single message deletion identity. Absence of guildID is retained and never treated as a removal from every guild.
/// API v10; verified 2026-10-16 against https://docs.discord.com/developers/events/gateway-events.
public struct GatewayMessageDelete: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Required nonnull `id` wire value; unknown siblings remain in rawFields.
    public let id: MessageID
    /// Required nonnull `channel_id` wire value; unknown siblings remain in rawFields.
    public let channelID: ChannelID
    /// Optional nonnull `guild_id` wire value; unknown siblings remain in rawFields.
    public let guildID: Field<GuildID>
    /// Original complete object, including future fields and exact numeric lexemes; ordinary diagnostics redact it.
    public let rawFields: [String: JSONValue]

    /// Parses an immutable dispatch payload synchronously without I/O, tasks or ownership changes.
    /// - Parameters:
    ///   - data: Complete UTF-8 object. Required nullable keys must exist; optional keys retain absence.
    ///   - limits: Whole-document bounds including unknown fields; defaults to 1 MiB, depth 64, and 100,000 nodes.
    /// - Throws: JSON syntax, duplicate-key or bound errors; sanitized invalid-response errors for missing,
    ///   forbidden-null, mistyped or out-of-range known fields. Parsing does not suspend or inspect cancellation.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects a previously bounded subtree while retaining exact unknown values.
    /// - Parameters:
    ///   - value: Original object from a complete containing document that passed its parser bounds.
    ///   - limits: The same document bounds, reused for scalar and subtree projections.
    /// - Throws: Sanitized invalid-response errors for incompatible modeled fields; no payload values are disclosed.
    /// This synchronous operation shares immutable storage and owns no external resources.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        id = try object.required("id", MessageID.self)
        channelID = try object.required("channel_id", ChannelID.self)
        guildID = try object.field("guild_id", GuildID.self)
        rawFields = object.resource.fields
    }
}

/// Server-ordered bulk deletion identities. This is a notification, not a generic REST batch request.
/// API v10; verified 2026-10-16 against https://docs.discord.com/developers/events/gateway-events.
public struct GatewayMessageDeleteBulk: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Required nonnull `ids` wire value; unknown siblings remain in rawFields.
    public let ids: [MessageID]
    /// Required nonnull `channel_id` wire value; unknown siblings remain in rawFields.
    public let channelID: ChannelID
    /// Optional nonnull `guild_id` wire value; unknown siblings remain in rawFields.
    public let guildID: Field<GuildID>
    /// Original complete object, including future fields and exact numeric lexemes; ordinary diagnostics redact it.
    public let rawFields: [String: JSONValue]

    /// Parses an immutable dispatch payload synchronously without I/O, tasks or ownership changes.
    /// - Parameters:
    ///   - data: Complete UTF-8 object. Required nullable keys must exist; optional keys retain absence.
    ///   - limits: Whole-document bounds including unknown fields; defaults to 1 MiB, depth 64, and 100,000 nodes.
    /// - Throws: JSON syntax, duplicate-key or bound errors; sanitized invalid-response errors for missing,
    ///   forbidden-null, mistyped or out-of-range known fields. Parsing does not suspend or inspect cancellation.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects a previously bounded subtree while retaining exact unknown values.
    /// - Parameters:
    ///   - value: Original object from a complete containing document that passed its parser bounds.
    ///   - limits: The same document bounds, reused for scalar and subtree projections.
    /// - Throws: Sanitized invalid-response errors for incompatible modeled fields; no payload values are disclosed.
    /// This synchronous operation shares immutable storage and owns no external resources.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        ids = try object.required("ids", [MessageID].self)
        channelID = try object.required("channel_id", ChannelID.self)
        guildID = try object.field("guild_id", GuildID.self)
        rawFields = object.resource.fields
    }
}

/// Reaction addition with super-reaction metadata. Unknown integral reaction types survive; member visibility follows guild delivery.
/// API v10; verified 2026-10-16 against https://docs.discord.com/developers/events/gateway-events.
public struct GatewayMessageReactionAdd: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Required nonnull `user_id` wire value; unknown siblings remain in rawFields.
    public let userID: UserID
    /// Required nonnull `channel_id` wire value; unknown siblings remain in rawFields.
    public let channelID: ChannelID
    /// Required nonnull `message_id` wire value; unknown siblings remain in rawFields.
    public let messageID: MessageID
    /// Optional nonnull `guild_id` wire value; unknown siblings remain in rawFields.
    public let guildID: Field<GuildID>
    /// Optional nonnull `member` wire value; unknown siblings remain in rawFields.
    public let member: Field<GuildMember>
    /// Required nonnull `emoji` wire value; unknown siblings remain in rawFields.
    public let emoji: PartialEmoji
    /// Optional nonnull `message_author_id` wire value; unknown siblings remain in rawFields.
    public let messageAuthorID: Field<UserID>
    /// Required nonnull `burst` wire value; unknown siblings remain in rawFields.
    public let burst: Bool
    /// Optional nonnull `burst_colors` wire value; unknown siblings remain in rawFields.
    public let burstColors: Field<[String]>
    /// Required nonnull `type` wire value; unknown siblings remain in rawFields.
    public let type: RawValue<GatewayReactionType>
    /// Original complete object, including future fields and exact numeric lexemes; ordinary diagnostics redact it.
    public let rawFields: [String: JSONValue]

    /// Parses an immutable dispatch payload synchronously without I/O, tasks or ownership changes.
    /// - Parameters:
    ///   - data: Complete UTF-8 object. Required nullable keys must exist; optional keys retain absence.
    ///   - limits: Whole-document bounds including unknown fields; defaults to 1 MiB, depth 64, and 100,000 nodes.
    /// - Throws: JSON syntax, duplicate-key or bound errors; sanitized invalid-response errors for missing,
    ///   forbidden-null, mistyped or out-of-range known fields. Parsing does not suspend or inspect cancellation.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects a previously bounded subtree while retaining exact unknown values.
    /// - Parameters:
    ///   - value: Original object from a complete containing document that passed its parser bounds.
    ///   - limits: The same document bounds, reused for scalar and subtree projections.
    /// - Throws: Sanitized invalid-response errors for incompatible modeled fields; no payload values are disclosed.
    /// This synchronous operation shares immutable storage and owns no external resources.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        userID = try object.required("user_id", UserID.self)
        channelID = try object.required("channel_id", ChannelID.self)
        messageID = try object.required("message_id", MessageID.self)
        guildID = try object.field("guild_id", GuildID.self)
        member = try object.messageField("member", GuildMember.self)
        emoji = try gatewayRequiredEmoji(object, name: "emoji")
        messageAuthorID = try object.field("message_author_id", UserID.self)
        burst = try object.required("burst", Bool.self)
        burstColors = try object.field("burst_colors", [String].self)
        type = try object.required("type", RawValue<GatewayReactionType>.self)
        rawFields = object.resource.fields
    }
}

/// Reaction removal including normal versus super-reaction identity. Unknown integral types remain supported as raw values.
/// API v10; verified 2026-10-16 against https://docs.discord.com/developers/events/gateway-events.
public struct GatewayMessageReactionRemove: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Required nonnull `user_id` wire value; unknown siblings remain in rawFields.
    public let userID: UserID
    /// Required nonnull `channel_id` wire value; unknown siblings remain in rawFields.
    public let channelID: ChannelID
    /// Required nonnull `message_id` wire value; unknown siblings remain in rawFields.
    public let messageID: MessageID
    /// Optional nonnull `guild_id` wire value; unknown siblings remain in rawFields.
    public let guildID: Field<GuildID>
    /// Required nonnull `emoji` wire value; unknown siblings remain in rawFields.
    public let emoji: PartialEmoji
    /// Required nonnull `burst` wire value; unknown siblings remain in rawFields.
    public let burst: Bool
    /// Required nonnull `type` wire value; unknown siblings remain in rawFields.
    public let type: RawValue<GatewayReactionType>
    /// Original complete object, including future fields and exact numeric lexemes; ordinary diagnostics redact it.
    public let rawFields: [String: JSONValue]

    /// Parses an immutable dispatch payload synchronously without I/O, tasks or ownership changes.
    /// - Parameters:
    ///   - data: Complete UTF-8 object. Required nullable keys must exist; optional keys retain absence.
    ///   - limits: Whole-document bounds including unknown fields; defaults to 1 MiB, depth 64, and 100,000 nodes.
    /// - Throws: JSON syntax, duplicate-key or bound errors; sanitized invalid-response errors for missing,
    ///   forbidden-null, mistyped or out-of-range known fields. Parsing does not suspend or inspect cancellation.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects a previously bounded subtree while retaining exact unknown values.
    /// - Parameters:
    ///   - value: Original object from a complete containing document that passed its parser bounds.
    ///   - limits: The same document bounds, reused for scalar and subtree projections.
    /// - Throws: Sanitized invalid-response errors for incompatible modeled fields; no payload values are disclosed.
    /// This synchronous operation shares immutable storage and owns no external resources.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        userID = try object.required("user_id", UserID.self)
        channelID = try object.required("channel_id", ChannelID.self)
        messageID = try object.required("message_id", MessageID.self)
        guildID = try object.field("guild_id", GuildID.self)
        emoji = try gatewayRequiredEmoji(object, name: "emoji")
        burst = try object.required("burst", Bool.self)
        type = try object.required("type", RawValue<GatewayReactionType>.self)
        rawFields = object.resource.fields
    }
}

/// Explicit removal of all reactions from a message, without user or emoji fields.
/// API v10; verified 2026-10-16 against https://docs.discord.com/developers/events/gateway-events.
public struct GatewayMessageReactionRemoveAll: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Required nonnull `channel_id` wire value; unknown siblings remain in rawFields.
    public let channelID: ChannelID
    /// Required nonnull `message_id` wire value; unknown siblings remain in rawFields.
    public let messageID: MessageID
    /// Optional nonnull `guild_id` wire value; unknown siblings remain in rawFields.
    public let guildID: Field<GuildID>
    /// Original complete object, including future fields and exact numeric lexemes; ordinary diagnostics redact it.
    public let rawFields: [String: JSONValue]

    /// Parses an immutable dispatch payload synchronously without I/O, tasks or ownership changes.
    /// - Parameters:
    ///   - data: Complete UTF-8 object. Required nullable keys must exist; optional keys retain absence.
    ///   - limits: Whole-document bounds including unknown fields; defaults to 1 MiB, depth 64, and 100,000 nodes.
    /// - Throws: JSON syntax, duplicate-key or bound errors; sanitized invalid-response errors for missing,
    ///   forbidden-null, mistyped or out-of-range known fields. Parsing does not suspend or inspect cancellation.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects a previously bounded subtree while retaining exact unknown values.
    /// - Parameters:
    ///   - value: Original object from a complete containing document that passed its parser bounds.
    ///   - limits: The same document bounds, reused for scalar and subtree projections.
    /// - Throws: Sanitized invalid-response errors for incompatible modeled fields; no payload values are disclosed.
    /// This synchronous operation shares immutable storage and owns no external resources.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        channelID = try object.required("channel_id", ChannelID.self)
        messageID = try object.required("message_id", MessageID.self)
        guildID = try object.field("guild_id", GuildID.self)
        rawFields = object.resource.fields
    }
}

/// Explicit removal of every reaction for an emoji; Unicode and deleted emoji retain null/absence semantics.
/// API v10; verified 2026-10-16 against https://docs.discord.com/developers/events/gateway-events.
public struct GatewayMessageReactionRemoveEmoji: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Required nonnull `channel_id` wire value; unknown siblings remain in rawFields.
    public let channelID: ChannelID
    /// Optional nonnull `guild_id` wire value; unknown siblings remain in rawFields.
    public let guildID: Field<GuildID>
    /// Required nonnull `message_id` wire value; unknown siblings remain in rawFields.
    public let messageID: MessageID
    /// Required nonnull `emoji` wire value; unknown siblings remain in rawFields.
    public let emoji: PartialEmoji
    /// Original complete object, including future fields and exact numeric lexemes; ordinary diagnostics redact it.
    public let rawFields: [String: JSONValue]

    /// Parses an immutable dispatch payload synchronously without I/O, tasks or ownership changes.
    /// - Parameters:
    ///   - data: Complete UTF-8 object. Required nullable keys must exist; optional keys retain absence.
    ///   - limits: Whole-document bounds including unknown fields; defaults to 1 MiB, depth 64, and 100,000 nodes.
    /// - Throws: JSON syntax, duplicate-key or bound errors; sanitized invalid-response errors for missing,
    ///   forbidden-null, mistyped or out-of-range known fields. Parsing does not suspend or inspect cancellation.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects a previously bounded subtree while retaining exact unknown values.
    /// - Parameters:
    ///   - value: Original object from a complete containing document that passed its parser bounds.
    ///   - limits: The same document bounds, reused for scalar and subtree projections.
    /// - Throws: Sanitized invalid-response errors for incompatible modeled fields; no payload values are disclosed.
    /// This synchronous operation shares immutable storage and owns no external resources.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        channelID = try object.required("channel_id", ChannelID.self)
        guildID = try object.field("guild_id", GuildID.self)
        messageID = try object.required("message_id", MessageID.self)
        emoji = try gatewayRequiredEmoji(object, name: "emoji")
        rawFields = object.resource.fields
    }
}

/// Presence-only User projection. Discord guarantees only id and explicitly permits arbitrary types for every other user field; rawFields deliberately retains those values without schema rejection.
/// API v10; verified 2026-10-16 against https://docs.discord.com/developers/events/gateway-events.
public struct GatewayPresenceUser: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Required nonnull `id` wire value; unknown siblings remain in rawFields.
    public let id: UserID
    /// Original complete object, including future fields and exact numeric lexemes; ordinary diagnostics redact it.
    public let rawFields: [String: JSONValue]

    /// Parses an immutable dispatch payload synchronously without I/O, tasks or ownership changes.
    /// - Parameters:
    ///   - data: Complete UTF-8 object. Required nullable keys must exist; optional keys retain absence.
    ///   - limits: Whole-document bounds including unknown fields; defaults to 1 MiB, depth 64, and 100,000 nodes.
    /// - Throws: JSON syntax, duplicate-key or bound errors; sanitized invalid-response errors for missing,
    ///   forbidden-null, mistyped or out-of-range known fields. Parsing does not suspend or inspect cancellation.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects a previously bounded subtree while retaining exact unknown values.
    /// - Parameters:
    ///   - value: Original object from a complete containing document that passed its parser bounds.
    ///   - limits: The same document bounds, reused for scalar and subtree projections.
    /// - Throws: Sanitized invalid-response errors for incompatible modeled fields; no payload values are disclosed.
    /// This synchronous operation shares immutable storage and owns no external resources.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        id = try object.required("id", UserID.self)
        rawFields = object.resource.fields
    }
}

/// Presence status per platform. Omission indicates no active visible session; future strings are preserved without assuming online status.
/// API v10; verified 2026-10-16 against https://docs.discord.com/developers/events/gateway-events.
public struct GatewayClientStatus: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Optional nonnull `desktop` wire value; unknown siblings remain in rawFields.
    public let desktop: Field<String>
    /// Optional nonnull `mobile` wire value; unknown siblings remain in rawFields.
    public let mobile: Field<String>
    /// Optional nonnull `web` wire value; unknown siblings remain in rawFields.
    public let web: Field<String>
    /// Optional nonnull `vr` wire value; unknown siblings remain in rawFields.
    public let vr: Field<String>
    /// Original complete object, including future fields and exact numeric lexemes; ordinary diagnostics redact it.
    public let rawFields: [String: JSONValue]

    /// Parses an immutable dispatch payload synchronously without I/O, tasks or ownership changes.
    /// - Parameters:
    ///   - data: Complete UTF-8 object. Required nullable keys must exist; optional keys retain absence.
    ///   - limits: Whole-document bounds including unknown fields; defaults to 1 MiB, depth 64, and 100,000 nodes.
    /// - Throws: JSON syntax, duplicate-key or bound errors; sanitized invalid-response errors for missing,
    ///   forbidden-null, mistyped or out-of-range known fields. Parsing does not suspend or inspect cancellation.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects a previously bounded subtree while retaining exact unknown values.
    /// - Parameters:
    ///   - value: Original object from a complete containing document that passed its parser bounds.
    ///   - limits: The same document bounds, reused for scalar and subtree projections.
    /// - Throws: Sanitized invalid-response errors for incompatible modeled fields; no payload values are disclosed.
    /// This synchronous operation shares immutable storage and owns no external resources.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        desktop = try object.field("desktop", String.self)
        mobile = try object.field("mobile", String.self)
        web = try object.field("web", String.self)
        vr = try object.field("vr", String.self)
        rawFields = object.resource.fields
    }
}

/// Presence update; requires privileged GUILD_PRESENCES. Custom statuses may be suppressed by profile privacy; visible activities never prove complete user activity.
/// API v10; verified 2026-10-16 against https://docs.discord.com/developers/events/gateway-events.
public struct GatewayPresenceUpdate: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Required nonnull `user` wire value; unknown siblings remain in rawFields.
    public let user: GatewayPresenceUser
    /// Required nonnull `guild_id` wire value; unknown siblings remain in rawFields.
    public let guildID: GuildID
    /// Required nonnull `status` wire value; unknown siblings remain in rawFields.
    public let status: String
    /// Required nonnull `activities` wire value; unknown siblings remain in rawFields.
    public let activities: [GatewayReceivedActivity]
    /// Required nonnull `client_status` wire value; unknown siblings remain in rawFields.
    public let clientStatus: GatewayClientStatus
    /// Original complete object, including future fields and exact numeric lexemes; ordinary diagnostics redact it.
    public let rawFields: [String: JSONValue]

    /// Parses an immutable dispatch payload synchronously without I/O, tasks or ownership changes.
    /// - Parameters:
    ///   - data: Complete UTF-8 object. Required nullable keys must exist; optional keys retain absence.
    ///   - limits: Whole-document bounds including unknown fields; defaults to 1 MiB, depth 64, and 100,000 nodes.
    /// - Throws: JSON syntax, duplicate-key or bound errors; sanitized invalid-response errors for missing,
    ///   forbidden-null, mistyped or out-of-range known fields. Parsing does not suspend or inspect cancellation.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects a previously bounded subtree while retaining exact unknown values.
    /// - Parameters:
    ///   - value: Original object from a complete containing document that passed its parser bounds.
    ///   - limits: The same document bounds, reused for scalar and subtree projections.
    /// - Throws: Sanitized invalid-response errors for incompatible modeled fields; no payload values are disclosed.
    /// This synchronous operation shares immutable storage and owns no external resources.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        user = try object.messageModel("user", GatewayPresenceUser.self)
        guildID = try object.required("guild_id", GuildID.self)
        status = try object.required("status", String.self)
        activities = try object.messageModels("activities", GatewayReceivedActivity.self)
        clientStatus = try object.messageModel("client_status", GatewayClientStatus.self)
        rawFields = object.resource.fields
    }
}

/// Partial presence embedded in guild creation, chunks and thread membership. Guild scope and optional presence fields are never synthesized.
/// API v10; verified 2026-10-16 against https://docs.discord.com/developers/events/gateway-events.
public struct GatewayPartialPresence: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Required nonnull `user` wire value; unknown siblings remain in rawFields.
    public let user: GatewayPresenceUser
    /// Optional nonnull `guild_id` wire value; unknown siblings remain in rawFields.
    public let guildID: Field<GuildID>
    /// Optional nonnull `status` wire value; unknown siblings remain in rawFields.
    public let status: Field<String>
    /// Optional nonnull `activities` wire value; unknown siblings remain in rawFields.
    public let activities: Field<[GatewayReceivedActivity]>
    /// Optional nonnull `client_status` wire value; unknown siblings remain in rawFields.
    public let clientStatus: Field<GatewayClientStatus>
    /// Original complete object, including future fields and exact numeric lexemes; ordinary diagnostics redact it.
    public let rawFields: [String: JSONValue]

    /// Parses an immutable dispatch payload synchronously without I/O, tasks or ownership changes.
    /// - Parameters:
    ///   - data: Complete UTF-8 object. Required nullable keys must exist; optional keys retain absence.
    ///   - limits: Whole-document bounds including unknown fields; defaults to 1 MiB, depth 64, and 100,000 nodes.
    /// - Throws: JSON syntax, duplicate-key or bound errors; sanitized invalid-response errors for missing,
    ///   forbidden-null, mistyped or out-of-range known fields. Parsing does not suspend or inspect cancellation.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects a previously bounded subtree while retaining exact unknown values.
    /// - Parameters:
    ///   - value: Original object from a complete containing document that passed its parser bounds.
    ///   - limits: The same document bounds, reused for scalar and subtree projections.
    /// - Throws: Sanitized invalid-response errors for incompatible modeled fields; no payload values are disclosed.
    /// This synchronous operation shares immutable storage and owns no external resources.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        user = try object.messageModel("user", GatewayPresenceUser.self)
        guildID = try object.field("guild_id", GuildID.self)
        status = try object.field("status", String.self)
        activities = try object.messageArray("activities", GatewayReceivedActivity.self)
        clientStatus = try object.messageField("client_status", GatewayClientStatus.self)
        rawFields = object.resource.fields
    }
}

/// Activity start/end Unix timestamps in milliseconds; response values are not interpreted against a local clock.
/// API v10; verified 2026-10-16 against https://docs.discord.com/developers/events/gateway-events.
public struct GatewayActivityTimestamps: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Optional nonnull `start` wire value; unknown siblings remain in rawFields.
    public let start: Field<Int64>
    /// Optional nonnull `end` wire value; unknown siblings remain in rawFields.
    public let end: Field<Int64>
    /// Original complete object, including future fields and exact numeric lexemes; ordinary diagnostics redact it.
    public let rawFields: [String: JSONValue]

    /// Parses an immutable dispatch payload synchronously without I/O, tasks or ownership changes.
    /// - Parameters:
    ///   - data: Complete UTF-8 object. Required nullable keys must exist; optional keys retain absence.
    ///   - limits: Whole-document bounds including unknown fields; defaults to 1 MiB, depth 64, and 100,000 nodes.
    /// - Throws: JSON syntax, duplicate-key or bound errors; sanitized invalid-response errors for missing,
    ///   forbidden-null, mistyped or out-of-range known fields. Parsing does not suspend or inspect cancellation.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects a previously bounded subtree while retaining exact unknown values.
    /// - Parameters:
    ///   - value: Original object from a complete containing document that passed its parser bounds.
    ///   - limits: The same document bounds, reused for scalar and subtree projections.
    /// - Throws: Sanitized invalid-response errors for incompatible modeled fields; no payload values are disclosed.
    /// This synchronous operation shares immutable storage and owns no external resources.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        start = try object.field("start", Int64.self)
        end = try object.field("end", Int64.self)
        rawFields = object.resource.fields
    }
}

/// Emoji within an activity. ID omission denotes non-custom data without inventing a snowflake.
/// API v10; verified 2026-10-16 against https://docs.discord.com/developers/events/gateway-events.
public struct GatewayActivityEmoji: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Required nonnull `name` wire value; unknown siblings remain in rawFields.
    public let name: String
    /// Optional nonnull `id` wire value; unknown siblings remain in rawFields.
    public let id: Field<EmojiID>
    /// Optional nonnull `animated` wire value; unknown siblings remain in rawFields.
    public let animated: Field<Bool>
    /// Original complete object, including future fields and exact numeric lexemes; ordinary diagnostics redact it.
    public let rawFields: [String: JSONValue]

    /// Parses an immutable dispatch payload synchronously without I/O, tasks or ownership changes.
    /// - Parameters:
    ///   - data: Complete UTF-8 object. Required nullable keys must exist; optional keys retain absence.
    ///   - limits: Whole-document bounds including unknown fields; defaults to 1 MiB, depth 64, and 100,000 nodes.
    /// - Throws: JSON syntax, duplicate-key or bound errors; sanitized invalid-response errors for missing,
    ///   forbidden-null, mistyped or out-of-range known fields. Parsing does not suspend or inspect cancellation.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects a previously bounded subtree while retaining exact unknown values.
    /// - Parameters:
    ///   - value: Original object from a complete containing document that passed its parser bounds.
    ///   - limits: The same document bounds, reused for scalar and subtree projections.
    /// - Throws: Sanitized invalid-response errors for incompatible modeled fields; no payload values are disclosed.
    /// This synchronous operation shares immutable storage and owns no external resources.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        name = try object.required("name", String.self)
        id = try object.field("id", EmojiID.self)
        animated = try object.field("animated", Bool.self)
        rawFields = object.resource.fields
    }
}

/// Activity party identity and current/maximum size pair.
/// API v10; verified 2026-10-16 against https://docs.discord.com/developers/events/gateway-events.
public struct GatewayActivityParty: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Optional nonnull `id` wire value; unknown siblings remain in rawFields.
    public let id: Field<String>
    /// Optional nonnull `size` wire value; unknown siblings remain in rawFields.
    public let size: Field<[Int]>
    /// Original complete object, including future fields and exact numeric lexemes; ordinary diagnostics redact it.
    public let rawFields: [String: JSONValue]

    /// Parses an immutable dispatch payload synchronously without I/O, tasks or ownership changes.
    /// - Parameters:
    ///   - data: Complete UTF-8 object. Required nullable keys must exist; optional keys retain absence.
    ///   - limits: Whole-document bounds including unknown fields; defaults to 1 MiB, depth 64, and 100,000 nodes.
    /// - Throws: JSON syntax, duplicate-key or bound errors; sanitized invalid-response errors for missing,
    ///   forbidden-null, mistyped or out-of-range known fields. Parsing does not suspend or inspect cancellation.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects a previously bounded subtree while retaining exact unknown values.
    /// - Parameters:
    ///   - value: Original object from a complete containing document that passed its parser bounds.
    ///   - limits: The same document bounds, reused for scalar and subtree projections.
    /// - Throws: Sanitized invalid-response errors for incompatible modeled fields; no payload values are disclosed.
    /// This synchronous operation shares immutable storage and owns no external resources.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        id = try object.field("id", String.self)
        size = try gatewayIntegerArray(object, name: "size")
        if case .value(let values) = size {
            guard values.count == 2 else { throw DiscordError.transport(.invalidResponse) }
        }
        rawFields = object.resource.fields
    }
}

/// Activity image data including arbitrary media-proxy strings. These user-controlled strings are never fetched or treated as trusted URLs.
/// API v10; verified 2026-10-16 against https://docs.discord.com/developers/events/gateway-events.
public struct GatewayActivityAssets: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Optional nonnull `large_image` wire value; unknown siblings remain in rawFields.
    public let largeImage: Field<String>
    /// Optional nonnull `large_text` wire value; unknown siblings remain in rawFields.
    public let largeText: Field<String>
    /// Optional nonnull `large_url` wire value; unknown siblings remain in rawFields.
    public let largeURL: Field<String>
    /// Optional nonnull `small_image` wire value; unknown siblings remain in rawFields.
    public let smallImage: Field<String>
    /// Optional nonnull `small_text` wire value; unknown siblings remain in rawFields.
    public let smallText: Field<String>
    /// Optional nonnull `small_url` wire value; unknown siblings remain in rawFields.
    public let smallURL: Field<String>
    /// Optional nonnull `invite_cover_image` wire value; unknown siblings remain in rawFields.
    public let inviteCoverImage: Field<String>
    /// Original complete object, including future fields and exact numeric lexemes; ordinary diagnostics redact it.
    public let rawFields: [String: JSONValue]

    /// Parses an immutable dispatch payload synchronously without I/O, tasks or ownership changes.
    /// - Parameters:
    ///   - data: Complete UTF-8 object. Required nullable keys must exist; optional keys retain absence.
    ///   - limits: Whole-document bounds including unknown fields; defaults to 1 MiB, depth 64, and 100,000 nodes.
    /// - Throws: JSON syntax, duplicate-key or bound errors; sanitized invalid-response errors for missing,
    ///   forbidden-null, mistyped or out-of-range known fields. Parsing does not suspend or inspect cancellation.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects a previously bounded subtree while retaining exact unknown values.
    /// - Parameters:
    ///   - value: Original object from a complete containing document that passed its parser bounds.
    ///   - limits: The same document bounds, reused for scalar and subtree projections.
    /// - Throws: Sanitized invalid-response errors for incompatible modeled fields; no payload values are disclosed.
    /// This synchronous operation shares immutable storage and owns no external resources.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        largeImage = try object.field("large_image", String.self)
        largeText = try object.field("large_text", String.self)
        largeURL = try object.field("large_url", String.self)
        smallImage = try object.field("small_image", String.self)
        smallText = try object.field("small_text", String.self)
        smallURL = try object.field("small_url", String.self)
        inviteCoverImage = try object.field("invite_cover_image", String.self)
        rawFields = object.resource.fields
    }
}

/// Sensitive Rich Presence join/spectate/match secrets. Normal formatting and reflection conceal every field.
/// API v10; verified 2026-10-16 against https://docs.discord.com/developers/events/gateway-events.
public struct GatewayActivitySecrets: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Optional nonnull `join` wire value; unknown siblings remain in rawFields.
    public let join: Field<String>
    /// Optional nonnull `spectate` wire value; unknown siblings remain in rawFields.
    public let spectate: Field<String>
    /// Optional nonnull `match` wire value; unknown siblings remain in rawFields.
    public let match: Field<String>
    /// Original complete object, including future fields and exact numeric lexemes; ordinary diagnostics redact it.
    public let rawFields: [String: JSONValue]

    /// Parses an immutable dispatch payload synchronously without I/O, tasks or ownership changes.
    /// - Parameters:
    ///   - data: Complete UTF-8 object. Required nullable keys must exist; optional keys retain absence.
    ///   - limits: Whole-document bounds including unknown fields; defaults to 1 MiB, depth 64, and 100,000 nodes.
    /// - Throws: JSON syntax, duplicate-key or bound errors; sanitized invalid-response errors for missing,
    ///   forbidden-null, mistyped or out-of-range known fields. Parsing does not suspend or inspect cancellation.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects a previously bounded subtree while retaining exact unknown values.
    /// - Parameters:
    ///   - value: Original object from a complete containing document that passed its parser bounds.
    ///   - limits: The same document bounds, reused for scalar and subtree projections.
    /// - Throws: Sanitized invalid-response errors for incompatible modeled fields; no payload values are disclosed.
    /// This synchronous operation shares immutable storage and owns no external resources.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        join = try object.field("join", String.self)
        spectate = try object.field("spectate", String.self)
        match = try object.field("match", String.self)
        rawFields = object.resource.fields
    }
}

/// Received activity. createdAt and timestamps use Unix milliseconds; Gateway buttons expose labels only. Unknown activity/display types and flag bits remain representable; bots can set only the documented restricted subset.
/// API v10; verified 2026-10-16 against https://docs.discord.com/developers/events/gateway-events.
public struct GatewayReceivedActivity: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Required nonnull `name` wire value; unknown siblings remain in rawFields.
    public let name: String
    /// Required nonnull `type` wire value; unknown siblings remain in rawFields.
    public let type: RawValue<GatewayReceivedActivityType>
    /// Optional nullable `url` wire value; unknown siblings remain in rawFields.
    public let url: Field<String>
    /// Required nonnull `created_at` wire value; unknown siblings remain in rawFields.
    public let createdAt: Int64
    /// Optional nonnull `timestamps` wire value; unknown siblings remain in rawFields.
    public let timestamps: Field<GatewayActivityTimestamps>
    /// Optional nonnull `application_id` wire value; unknown siblings remain in rawFields.
    public let applicationID: Field<ApplicationID>
    /// Optional nullable `status_display_type` wire value; unknown siblings remain in rawFields.
    public let statusDisplayType: Field<RawValue<GatewayActivityStatusDisplayType>>
    /// Optional nullable `details` wire value; unknown siblings remain in rawFields.
    public let details: Field<String>
    /// Optional nullable `details_url` wire value; unknown siblings remain in rawFields.
    public let detailsURL: Field<String>
    /// Optional nullable `state` wire value; unknown siblings remain in rawFields.
    public let state: Field<String>
    /// Optional nullable `state_url` wire value; unknown siblings remain in rawFields.
    public let stateURL: Field<String>
    /// Optional nullable `emoji` wire value; unknown siblings remain in rawFields.
    public let emoji: Field<GatewayActivityEmoji>
    /// Optional nonnull `party` wire value; unknown siblings remain in rawFields.
    public let party: Field<GatewayActivityParty>
    /// Optional nonnull `assets` wire value; unknown siblings remain in rawFields.
    public let assets: Field<GatewayActivityAssets>
    /// Optional nonnull `secrets` wire value; unknown siblings remain in rawFields.
    public let secrets: Field<GatewayActivitySecrets>
    /// Optional nonnull `instance` wire value; unknown siblings remain in rawFields.
    public let instance: Field<Bool>
    /// Optional nonnull `flags` wire value; unknown siblings remain in rawFields.
    public let flags: Field<UInt64>
    /// Optional nonnull `buttons` wire value; unknown siblings remain in rawFields.
    public let buttons: Field<[String]>
    /// Original complete object, including future fields and exact numeric lexemes; ordinary diagnostics redact it.
    public let rawFields: [String: JSONValue]

    /// Parses an immutable dispatch payload synchronously without I/O, tasks or ownership changes.
    /// - Parameters:
    ///   - data: Complete UTF-8 object. Required nullable keys must exist; optional keys retain absence.
    ///   - limits: Whole-document bounds including unknown fields; defaults to 1 MiB, depth 64, and 100,000 nodes.
    /// - Throws: JSON syntax, duplicate-key or bound errors; sanitized invalid-response errors for missing,
    ///   forbidden-null, mistyped or out-of-range known fields. Parsing does not suspend or inspect cancellation.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects a previously bounded subtree while retaining exact unknown values.
    /// - Parameters:
    ///   - value: Original object from a complete containing document that passed its parser bounds.
    ///   - limits: The same document bounds, reused for scalar and subtree projections.
    /// - Throws: Sanitized invalid-response errors for incompatible modeled fields; no payload values are disclosed.
    /// This synchronous operation shares immutable storage and owns no external resources.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        name = try object.required("name", String.self)
        type = try object.required("type", RawValue<GatewayReceivedActivityType>.self)
        url = try object.field("url", String.self, nullable: true)
        createdAt = try object.required("created_at", Int64.self)
        timestamps = try object.messageField("timestamps", GatewayActivityTimestamps.self)
        applicationID = try object.field("application_id", ApplicationID.self)
        statusDisplayType = try object.field("status_display_type", RawValue<GatewayActivityStatusDisplayType>.self, nullable: true)
        details = try object.field("details", String.self, nullable: true)
        detailsURL = try object.field("details_url", String.self, nullable: true)
        state = try object.field("state", String.self, nullable: true)
        stateURL = try object.field("state_url", String.self, nullable: true)
        emoji = try object.messageField("emoji", GatewayActivityEmoji.self, nullable: true)
        party = try object.messageField("party", GatewayActivityParty.self)
        assets = try object.messageField("assets", GatewayActivityAssets.self)
        secrets = try object.messageField("secrets", GatewayActivitySecrets.self)
        instance = try object.field("instance", Bool.self)
        flags = try object.field("flags", UInt64.self)
        buttons = try object.field("buttons", [String].self)
        rawFields = object.resource.fields
    }
}

/// Typing start with Unix-seconds timestamp. Presence of a member depends on guild context and does not establish current permission.
/// API v10; verified 2026-10-16 against https://docs.discord.com/developers/events/gateway-events.
public struct GatewayTypingStart: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Required nonnull `channel_id` wire value; unknown siblings remain in rawFields.
    public let channelID: ChannelID
    /// Optional nonnull `guild_id` wire value; unknown siblings remain in rawFields.
    public let guildID: Field<GuildID>
    /// Required nonnull `user_id` wire value; unknown siblings remain in rawFields.
    public let userID: UserID
    /// Required nonnull `timestamp` wire value; unknown siblings remain in rawFields.
    public let timestamp: Int64
    /// Optional nonnull `member` wire value; unknown siblings remain in rawFields.
    public let member: Field<GuildMember>
    /// Original complete object, including future fields and exact numeric lexemes; ordinary diagnostics redact it.
    public let rawFields: [String: JSONValue]

    /// Parses an immutable dispatch payload synchronously without I/O, tasks or ownership changes.
    /// - Parameters:
    ///   - data: Complete UTF-8 object. Required nullable keys must exist; optional keys retain absence.
    ///   - limits: Whole-document bounds including unknown fields; defaults to 1 MiB, depth 64, and 100,000 nodes.
    /// - Throws: JSON syntax, duplicate-key or bound errors; sanitized invalid-response errors for missing,
    ///   forbidden-null, mistyped or out-of-range known fields. Parsing does not suspend or inspect cancellation.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects a previously bounded subtree while retaining exact unknown values.
    /// - Parameters:
    ///   - value: Original object from a complete containing document that passed its parser bounds.
    ///   - limits: The same document bounds, reused for scalar and subtree projections.
    /// - Throws: Sanitized invalid-response errors for incompatible modeled fields; no payload values are disclosed.
    /// This synchronous operation shares immutable storage and owns no external resources.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        channelID = try object.required("channel_id", ChannelID.self)
        guildID = try object.field("guild_id", GuildID.self)
        userID = try object.required("user_id", UserID.self)
        timestamp = try object.required("timestamp", Int64.self)
        member = try object.messageField("member", GuildMember.self)
        rawFields = object.resource.fields
    }
}

/// Voice channel effect for the channel the bot is connected to. Default sounds accept exact integral IDs and custom sounds accept snowflake strings; soundVolume is finite in 0...1.
/// API v10; verified 2026-10-16 against https://docs.discord.com/developers/events/gateway-events.
public struct GatewayVoiceChannelEffect: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Required nonnull `channel_id` wire value; unknown siblings remain in rawFields.
    public let channelID: ChannelID
    /// Required nonnull `guild_id` wire value; unknown siblings remain in rawFields.
    public let guildID: GuildID
    /// Required nonnull `user_id` wire value; unknown siblings remain in rawFields.
    public let userID: UserID
    /// Optional nullable `emoji` wire value; unknown siblings remain in rawFields.
    public let emoji: Field<PartialEmoji>
    /// Optional nullable `animation_type` wire value; unknown siblings remain in rawFields.
    public let animationType: Field<RawValue<GatewayVoiceEffectAnimationType>>
    /// Optional nonnull `animation_id` wire value; unknown siblings remain in rawFields.
    public let animationID: Field<Int>
    /// Optional nonnull `sound_id` wire value; unknown siblings remain in rawFields.
    public let soundID: Field<SoundboardSoundID>
    /// Optional nonnull `sound_volume` wire value; unknown siblings remain in rawFields.
    public let soundVolume: Field<Double>
    /// Original complete object, including future fields and exact numeric lexemes; ordinary diagnostics redact it.
    public let rawFields: [String: JSONValue]

    /// Parses an immutable dispatch payload synchronously without I/O, tasks or ownership changes.
    /// - Parameters:
    ///   - data: Complete UTF-8 object. Required nullable keys must exist; optional keys retain absence.
    ///   - limits: Whole-document bounds including unknown fields; defaults to 1 MiB, depth 64, and 100,000 nodes.
    /// - Throws: JSON syntax, duplicate-key or bound errors; sanitized invalid-response errors for missing,
    ///   forbidden-null, mistyped or out-of-range known fields. Parsing does not suspend or inspect cancellation.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects a previously bounded subtree while retaining exact unknown values.
    /// - Parameters:
    ///   - value: Original object from a complete containing document that passed its parser bounds.
    ///   - limits: The same document bounds, reused for scalar and subtree projections.
    /// - Throws: Sanitized invalid-response errors for incompatible modeled fields; no payload values are disclosed.
    /// This synchronous operation shares immutable storage and owns no external resources.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        channelID = try object.required("channel_id", ChannelID.self)
        guildID = try object.required("guild_id", GuildID.self)
        userID = try object.required("user_id", UserID.self)
        emoji = try object.nested("emoji", nullable: true) { try PartialEmoji(value: $0, limits: limits) }
        animationType = try object.field("animation_type", RawValue<GatewayVoiceEffectAnimationType>.self, nullable: true)
        animationID = try object.field("animation_id", Int.self)
        soundID = try object.nested("sound_id") { try gatewaySoundID($0, limits: limits) }
        soundVolume = try object.messageNumber("sound_volume")
        if case .value(let volume) = soundVolume {
            guard (0...1).contains(volume) else { throw DiscordError.transport(.invalidResponse) }
        }
        rawFields = object.resource.fields
    }
}

/// Voice server allocation update. Null endpoint instructs the consumer to disconnect and wait for a replacement allocation; parsing never starts a voice connection. Token is redacted.
/// API v10; verified 2026-10-16 against https://docs.discord.com/developers/events/gateway-events.
public struct GatewayVoiceServerUpdate: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Required nonnull `token` wire value; unknown siblings remain in rawFields.
    public let token: String
    /// Required nonnull `guild_id` wire value; unknown siblings remain in rawFields.
    public let guildID: GuildID
    /// Required nullable `endpoint` wire value; unknown siblings remain in rawFields.
    public let endpoint: Nullable<String>
    /// Original complete object, including future fields and exact numeric lexemes; ordinary diagnostics redact it.
    public let rawFields: [String: JSONValue]

    /// Parses an immutable dispatch payload synchronously without I/O, tasks or ownership changes.
    /// - Parameters:
    ///   - data: Complete UTF-8 object. Required nullable keys must exist; optional keys retain absence.
    ///   - limits: Whole-document bounds including unknown fields; defaults to 1 MiB, depth 64, and 100,000 nodes.
    /// - Throws: JSON syntax, duplicate-key or bound errors; sanitized invalid-response errors for missing,
    ///   forbidden-null, mistyped or out-of-range known fields. Parsing does not suspend or inspect cancellation.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects a previously bounded subtree while retaining exact unknown values.
    /// - Parameters:
    ///   - value: Original object from a complete containing document that passed its parser bounds.
    ///   - limits: The same document bounds, reused for scalar and subtree projections.
    /// - Throws: Sanitized invalid-response errors for incompatible modeled fields; no payload values are disclosed.
    /// This synchronous operation shares immutable storage and owns no external resources.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        token = try object.required("token", String.self)
        guildID = try object.required("guild_id", GuildID.self)
        endpoint = try object.required("endpoint", Nullable<String>.self)
        rawFields = object.resource.fields
    }
}

/// Webhook invalidation for a guild channel, without exposing a complete webhook resource.
/// API v10; verified 2026-10-16 against https://docs.discord.com/developers/events/gateway-events.
public struct GatewayWebhooksUpdate: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Required nonnull `guild_id` wire value; unknown siblings remain in rawFields.
    public let guildID: GuildID
    /// Required nonnull `channel_id` wire value; unknown siblings remain in rawFields.
    public let channelID: ChannelID
    /// Original complete object, including future fields and exact numeric lexemes; ordinary diagnostics redact it.
    public let rawFields: [String: JSONValue]

    /// Parses an immutable dispatch payload synchronously without I/O, tasks or ownership changes.
    /// - Parameters:
    ///   - data: Complete UTF-8 object. Required nullable keys must exist; optional keys retain absence.
    ///   - limits: Whole-document bounds including unknown fields; defaults to 1 MiB, depth 64, and 100,000 nodes.
    /// - Throws: JSON syntax, duplicate-key or bound errors; sanitized invalid-response errors for missing,
    ///   forbidden-null, mistyped or out-of-range known fields. Parsing does not suspend or inspect cancellation.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects a previously bounded subtree while retaining exact unknown values.
    /// - Parameters:
    ///   - value: Original object from a complete containing document that passed its parser bounds.
    ///   - limits: The same document bounds, reused for scalar and subtree projections.
    /// - Throws: Sanitized invalid-response errors for incompatible modeled fields; no payload values are disclosed.
    /// This synchronous operation shares immutable storage and owns no external resources.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        guildID = try object.required("guild_id", GuildID.self)
        channelID = try object.required("channel_id", ChannelID.self)
        rawFields = object.resource.fields
    }
}

/// Poll vote addition/removal; multiple selections generate one event per answer. It does not prove the complete vote tally.
/// API v10; verified 2026-10-16 against https://docs.discord.com/developers/events/gateway-events.
public struct GatewayMessagePollVote: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Required nonnull `user_id` wire value; unknown siblings remain in rawFields.
    public let userID: UserID
    /// Required nonnull `channel_id` wire value; unknown siblings remain in rawFields.
    public let channelID: ChannelID
    /// Required nonnull `message_id` wire value; unknown siblings remain in rawFields.
    public let messageID: MessageID
    /// Optional nonnull `guild_id` wire value; unknown siblings remain in rawFields.
    public let guildID: Field<GuildID>
    /// Required nonnull `answer_id` wire value; unknown siblings remain in rawFields.
    public let answerID: Int
    /// Original complete object, including future fields and exact numeric lexemes; ordinary diagnostics redact it.
    public let rawFields: [String: JSONValue]

    /// Parses an immutable dispatch payload synchronously without I/O, tasks or ownership changes.
    /// - Parameters:
    ///   - data: Complete UTF-8 object. Required nullable keys must exist; optional keys retain absence.
    ///   - limits: Whole-document bounds including unknown fields; defaults to 1 MiB, depth 64, and 100,000 nodes.
    /// - Throws: JSON syntax, duplicate-key or bound errors; sanitized invalid-response errors for missing,
    ///   forbidden-null, mistyped or out-of-range known fields. Parsing does not suspend or inspect cancellation.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects a previously bounded subtree while retaining exact unknown values.
    /// - Parameters:
    ///   - value: Original object from a complete containing document that passed its parser bounds.
    ///   - limits: The same document bounds, reused for scalar and subtree projections.
    /// - Throws: Sanitized invalid-response errors for incompatible modeled fields; no payload values are disclosed.
    /// This synchronous operation shares immutable storage and owns no external resources.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        userID = try object.required("user_id", UserID.self)
        channelID = try object.required("channel_id", ChannelID.self)
        messageID = try object.required("message_id", MessageID.self)
        guildID = try object.field("guild_id", GuildID.self)
        answerID = try object.required("answer_id", Int.self)
        rawFields = object.resource.fields
    }
}

/// Documented opcode 8 rate-limit metadata. Nonce may be absent when omitted or invalid in the original request.
/// API v10; verified 2026-10-16 against https://docs.discord.com/developers/events/gateway-events.
public struct GatewayMemberRateLimitMetadata: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Required nonnull `guild_id` wire value; unknown siblings remain in rawFields.
    public let guildID: GuildID
    /// Optional nonnull `nonce` wire value; unknown siblings remain in rawFields.
    public let nonce: Field<String>
    /// Original complete object, including future fields and exact numeric lexemes; ordinary diagnostics redact it.
    public let rawFields: [String: JSONValue]

    /// Parses an immutable dispatch payload synchronously without I/O, tasks or ownership changes.
    /// - Parameters:
    ///   - data: Complete UTF-8 object. Required nullable keys must exist; optional keys retain absence.
    ///   - limits: Whole-document bounds including unknown fields; defaults to 1 MiB, depth 64, and 100,000 nodes.
    /// - Throws: JSON syntax, duplicate-key or bound errors; sanitized invalid-response errors for missing,
    ///   forbidden-null, mistyped or out-of-range known fields. Parsing does not suspend or inspect cancellation.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects a previously bounded subtree while retaining exact unknown values.
    /// - Parameters:
    ///   - value: Original object from a complete containing document that passed its parser bounds.
    ///   - limits: The same document bounds, reused for scalar and subtree projections.
    /// - Throws: Sanitized invalid-response errors for incompatible modeled fields; no payload values are disclosed.
    /// This synchronous operation shares immutable storage and owns no external resources.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        guildID = try object.required("guild_id", GuildID.self)
        nonce = try object.field("nonce", String.self)
        rawFields = object.resource.fields
    }
}

/// Gateway opcode-specific rate limit. retryAfter is finite nonnegative seconds and is independent of REST admission; unknown opcode metadata remains lossless.
/// API v10; verified 2026-10-16 against https://docs.discord.com/developers/events/gateway-events.
public struct GatewayRateLimited: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Required nonnull `opcode` wire value; unknown siblings remain in rawFields.
    public let opcode: Int
    /// Required nonnull `retry_after` wire value; unknown siblings remain in rawFields.
    public let retryAfter: Double
    /// Exact metadata, including future opcode-specific structures.
    public let metadata: JSONValue
    /// Typed opcode 8 metadata; nil for an unrecognized opcode.
    public let memberMetadata: GatewayMemberRateLimitMetadata?
    /// Original complete object, including future fields and exact numeric lexemes; ordinary diagnostics redact it.
    public let rawFields: [String: JSONValue]

    /// Parses an immutable dispatch payload synchronously without I/O, tasks or ownership changes.
    /// - Parameters:
    ///   - data: Complete UTF-8 object. Required nullable keys must exist; optional keys retain absence.
    ///   - limits: Whole-document bounds including unknown fields; defaults to 1 MiB, depth 64, and 100,000 nodes.
    /// - Throws: JSON syntax, duplicate-key or bound errors; sanitized invalid-response errors for missing,
    ///   forbidden-null, mistyped or out-of-range known fields. Parsing does not suspend or inspect cancellation.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects a previously bounded subtree while retaining exact unknown values.
    /// - Parameters:
    ///   - value: Original object from a complete containing document that passed its parser bounds.
    ///   - limits: The same document bounds, reused for scalar and subtree projections.
    /// - Throws: Sanitized invalid-response errors for incompatible modeled fields; no payload values are disclosed.
    /// This synchronous operation shares immutable storage and owns no external resources.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        opcode = try object.required("opcode", Int.self)
        retryAfter = try gatewayRequiredNumber(object, name: "retry_after")
        guard let meta = object.resource.fields["meta"] else { throw DiscordError.transport(.invalidResponse) }
        metadata = meta
        memberMetadata = opcode == 8 ? try GatewayMemberRateLimitMetadata(value: meta, limits: limits) : nil
        guard retryAfter >= 0 else { throw DiscordError.transport(.invalidResponse) }
        rawFields = object.resource.fields
    }
}

/// Sparse guild member attached to messages and mentions. Every field preserves omission, explicit permitted null and value; nullable joinedAt supports voice guests. No omitted state is defaulted.
/// API v10; verified 2026-10-16 against https://docs.discord.com/developers/events/gateway-events.
public struct GatewayPartialGuildMember: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Optional nonnull `user` wire value; unknown siblings remain in rawFields.
    public let user: Field<ChannelRecipient>
    /// Optional nullable `nick` wire value; unknown siblings remain in rawFields.
    public let nick: Field<String>
    /// Optional nullable `avatar` wire value; unknown siblings remain in rawFields.
    public let avatar: Field<String>
    /// Optional nullable `banner` wire value; unknown siblings remain in rawFields.
    public let banner: Field<String>
    /// Optional nonnull `roles` wire value; unknown siblings remain in rawFields.
    public let roles: Field<[RoleID]>
    /// Optional nullable `joined_at` wire value; unknown siblings remain in rawFields.
    public let joinedAt: Field<DiscordTimestamp>
    /// Optional nullable `premium_since` wire value; unknown siblings remain in rawFields.
    public let premiumSince: Field<DiscordTimestamp>
    /// Optional nonnull `deaf` wire value; unknown siblings remain in rawFields.
    public let deaf: Field<Bool>
    /// Optional nonnull `mute` wire value; unknown siblings remain in rawFields.
    public let mute: Field<Bool>
    /// Optional nonnull `flags` wire value; unknown siblings remain in rawFields.
    public let flags: Field<UInt64>
    /// Optional nonnull `pending` wire value; unknown siblings remain in rawFields.
    public let pending: Field<Bool>
    /// Optional nonnull `permissions` wire value; unknown siblings remain in rawFields.
    public let permissions: Field<String>
    /// Optional nullable `communication_disabled_until` wire value; unknown siblings remain in rawFields.
    public let communicationDisabledUntil: Field<DiscordTimestamp>
    /// Optional nullable `avatar_decoration_data` wire value; unknown siblings remain in rawFields.
    public let avatarDecorationData: Field<UserAvatarDecoration>
    /// Optional nullable `collectibles` wire value; unknown siblings remain in rawFields.
    public let collectibles: Field<UserCollectibles>
    /// Original complete object, including future fields and exact numeric lexemes; ordinary diagnostics redact it.
    public let rawFields: [String: JSONValue]

    /// Parses an immutable dispatch payload synchronously without I/O, tasks or ownership changes.
    /// - Parameters:
    ///   - data: Complete UTF-8 object. Required nullable keys must exist; optional keys retain absence.
    ///   - limits: Whole-document bounds including unknown fields; defaults to 1 MiB, depth 64, and 100,000 nodes.
    /// - Throws: JSON syntax, duplicate-key or bound errors; sanitized invalid-response errors for missing,
    ///   forbidden-null, mistyped or out-of-range known fields. Parsing does not suspend or inspect cancellation.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects a previously bounded subtree while retaining exact unknown values.
    /// - Parameters:
    ///   - value: Original object from a complete containing document that passed its parser bounds.
    ///   - limits: The same document bounds, reused for scalar and subtree projections.
    /// - Throws: Sanitized invalid-response errors for incompatible modeled fields; no payload values are disclosed.
    /// This synchronous operation shares immutable storage and owns no external resources.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        user = try object.messageField("user", ChannelRecipient.self)
        nick = try object.field("nick", String.self, nullable: true)
        avatar = try object.field("avatar", String.self, nullable: true)
        banner = try object.field("banner", String.self, nullable: true)
        roles = try object.field("roles", [RoleID].self)
        joinedAt = try object.field("joined_at", DiscordTimestamp.self, nullable: true)
        premiumSince = try object.field("premium_since", DiscordTimestamp.self, nullable: true)
        deaf = try object.field("deaf", Bool.self)
        mute = try object.field("mute", Bool.self)
        flags = try object.field("flags", UInt64.self)
        pending = try object.field("pending", Bool.self)
        permissions = try object.field("permissions", String.self)
        communicationDisabledUntil = try object.field("communication_disabled_until", DiscordTimestamp.self, nullable: true)
        avatarDecorationData = try object.messageField("avatar_decoration_data", UserAvatarDecoration.self, nullable: true)
        collectibles = try object.messageField("collectibles", UserCollectibles.self, nullable: true)
        rawFields = object.resource.fields
    }
}

/// Sparse MESSAGE_UPDATE. Only identity and channel are required; missing fields preserve prior state, while permitted explicit null clears it. tts from Discord is always false. The model never turns a patch into a full Message or invents omitted content.
/// API v10; verified 2026-10-16 against https://docs.discord.com/developers/events/gateway-events.
public struct GatewayMessageUpdate: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Required nonnull `id` wire value; unknown siblings remain in rawFields.
    public let id: MessageID
    /// Required nonnull `channel_id` wire value; unknown siblings remain in rawFields.
    public let channelID: ChannelID
    /// Optional nonnull `author` wire value; unknown siblings remain in rawFields.
    public let author: Field<MessageAuthor>
    /// Optional nonnull `content` wire value; unknown siblings remain in rawFields.
    public let content: Field<String>
    /// Optional nonnull `timestamp` wire value; unknown siblings remain in rawFields.
    public let timestamp: Field<DiscordTimestamp>
    /// Optional nullable `edited_timestamp` wire value; unknown siblings remain in rawFields.
    public let editedTimestamp: Field<DiscordTimestamp>
    /// Optional nonnull `tts` wire value; unknown siblings remain in rawFields.
    public let tts: Field<Bool>
    /// Optional nonnull `mention_everyone` wire value; unknown siblings remain in rawFields.
    public let mentionEveryone: Field<Bool>
    /// Optional nonnull `mentions` wire value; unknown siblings remain in rawFields.
    public let mentions: Field<[GatewayMessageMention]>
    /// Optional nonnull `mention_roles` wire value; unknown siblings remain in rawFields.
    public let mentionRoles: Field<[RoleID]>
    /// Optional nonnull `mention_channels` wire value; unknown siblings remain in rawFields.
    public let mentionChannels: Field<[MessageChannelMention]>
    /// Optional nonnull `attachments` wire value; unknown siblings remain in rawFields.
    public let attachments: Field<[MessageAttachment]>
    /// Optional nonnull `embeds` wire value; unknown siblings remain in rawFields.
    public let embeds: Field<[MessageEmbed]>
    /// Optional nonnull `reactions` wire value; unknown siblings remain in rawFields.
    public let reactions: Field<[MessageReaction]>
    /// Optional nonnull `pinned` wire value; unknown siblings remain in rawFields.
    public let pinned: Field<Bool>
    /// Optional nonnull `webhook_id` wire value; unknown siblings remain in rawFields.
    public let webhookID: Field<WebhookID>
    /// Optional nonnull `type` wire value; unknown siblings remain in rawFields.
    public let type: Field<RawValue<MessageType>>
    /// Optional nonnull `activity` wire value; unknown siblings remain in rawFields.
    public let activity: Field<MessageActivity>
    /// Optional nonnull `application` wire value; unknown siblings remain in rawFields.
    public let application: Field<MessageRelatedResource>
    /// Optional nonnull `application_id` wire value; unknown siblings remain in rawFields.
    public let applicationID: Field<ApplicationID>
    /// Optional nonnull `flags` wire value; unknown siblings remain in rawFields.
    public let flags: Field<UInt64>
    /// Optional nonnull `message_reference` wire value; unknown siblings remain in rawFields.
    public let messageReference: Field<MessageReference>
    /// Optional nonnull `message_snapshots` wire value; unknown siblings remain in rawFields.
    public let messageSnapshots: Field<[MessageSnapshot]>
    /// Optional nonnull `interaction_metadata` wire value; unknown siblings remain in rawFields.
    public let interactionMetadata: Field<MessageInteractionMetadata>
    /// Optional nonnull `interaction` wire value; unknown siblings remain in rawFields.
    public let interaction: Field<MessageLegacyInteraction>
    /// Optional nonnull `thread` wire value; unknown siblings remain in rawFields.
    public let thread: Field<MessageRelatedResource>
    /// Optional nonnull `components` wire value; unknown siblings remain in rawFields.
    public let components: Field<[MessageComponent]>
    /// Optional nonnull `sticker_items` wire value; unknown siblings remain in rawFields.
    public let stickerItems: Field<[MessageStickerItem]>
    /// Optional nonnull `stickers` wire value; unknown siblings remain in rawFields.
    public let stickers: Field<[MessageRelatedResource]>
    /// Optional nonnull `position` wire value; unknown siblings remain in rawFields.
    public let position: Field<Int>
    /// Optional nonnull `role_subscription_data` wire value; unknown siblings remain in rawFields.
    public let roleSubscriptionData: Field<MessageRoleSubscriptionData>
    /// Optional nonnull `resolved` wire value; unknown siblings remain in rawFields.
    public let resolved: Field<MessageResolvedData>
    /// Optional nonnull `poll` wire value; unknown siblings remain in rawFields.
    public let poll: Field<Poll>
    /// Optional nonnull `call` wire value; unknown siblings remain in rawFields.
    public let call: Field<MessageCall>
    /// Optional nonnull `shared_client_theme` wire value; unknown siblings remain in rawFields.
    public let sharedClientTheme: Field<MessageSharedClientTheme>
    /// Optional nonnull `nonce` wire value; unknown siblings remain in rawFields.
    public let nonce: Field<MessageNonceValue>
    /// Optional nullable `referenced_message` wire value; unknown siblings remain in rawFields.
    public let referencedMessage: Field<Message>
    /// Optional nonnull `guild_id` wire value; unknown siblings remain in rawFields.
    public let guildID: Field<GuildID>
    /// Optional nonnull `member` wire value; unknown siblings remain in rawFields.
    public let member: Field<GatewayPartialGuildMember>
    /// Optional nonnull `channel_type` wire value; unknown siblings remain in rawFields.
    public let channelType: Field<RawValue<ChannelType>>
    /// Original complete object, including future fields and exact numeric lexemes; ordinary diagnostics redact it.
    public let rawFields: [String: JSONValue]

    /// Parses an immutable dispatch payload synchronously without I/O, tasks or ownership changes.
    /// - Parameters:
    ///   - data: Complete UTF-8 object. Required nullable keys must exist; optional keys retain absence.
    ///   - limits: Whole-document bounds including unknown fields; defaults to 1 MiB, depth 64, and 100,000 nodes.
    /// - Throws: JSON syntax, duplicate-key or bound errors; sanitized invalid-response errors for missing,
    ///   forbidden-null, mistyped or out-of-range known fields. Parsing does not suspend or inspect cancellation.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects a previously bounded subtree while retaining exact unknown values.
    /// - Parameters:
    ///   - value: Original object from a complete containing document that passed its parser bounds.
    ///   - limits: The same document bounds, reused for scalar and subtree projections.
    /// - Throws: Sanitized invalid-response errors for incompatible modeled fields; no payload values are disclosed.
    /// This synchronous operation shares immutable storage and owns no external resources.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        id = try object.required("id", MessageID.self)
        channelID = try object.required("channel_id", ChannelID.self)
        author = try object.messageField("author", MessageAuthor.self)
        content = try object.field("content", String.self)
        timestamp = try object.field("timestamp", DiscordTimestamp.self)
        editedTimestamp = try object.field("edited_timestamp", DiscordTimestamp.self, nullable: true)
        tts = try object.field("tts", Bool.self)
        mentionEveryone = try object.field("mention_everyone", Bool.self)
        mentions = try object.messageArray("mentions", GatewayMessageMention.self)
        mentionRoles = try object.field("mention_roles", [RoleID].self)
        mentionChannels = try object.messageArray("mention_channels", MessageChannelMention.self)
        attachments = try object.messageArray("attachments", MessageAttachment.self)
        embeds = try object.messageArray("embeds", MessageEmbed.self)
        reactions = try object.messageArray("reactions", MessageReaction.self)
        pinned = try object.field("pinned", Bool.self)
        webhookID = try object.field("webhook_id", WebhookID.self)
        type = try object.field("type", RawValue<MessageType>.self)
        activity = try object.messageField("activity", MessageActivity.self)
        application = try object.messageField("application", MessageRelatedResource.self)
        applicationID = try object.field("application_id", ApplicationID.self)
        flags = try object.field("flags", UInt64.self)
        messageReference = try object.messageField("message_reference", MessageReference.self)
        messageSnapshots = try object.messageArray("message_snapshots", MessageSnapshot.self)
        interactionMetadata = try object.messageField("interaction_metadata", MessageInteractionMetadata.self)
        interaction = try object.messageField("interaction", MessageLegacyInteraction.self)
        thread = try object.messageField("thread", MessageRelatedResource.self)
        components = try object.messageArray("components", MessageComponent.self)
        stickerItems = try object.messageArray("sticker_items", MessageStickerItem.self)
        stickers = try object.messageArray("stickers", MessageRelatedResource.self)
        position = try object.field("position", Int.self)
        roleSubscriptionData = try object.messageField("role_subscription_data", MessageRoleSubscriptionData.self)
        resolved = try object.messageField("resolved", MessageResolvedData.self)
        poll = try object.messageField("poll", Poll.self)
        call = try object.messageField("call", MessageCall.self)
        sharedClientTheme = try object.messageField("shared_client_theme", MessageSharedClientTheme.self)
        nonce = try object.nested("nonce") { try MessageNonceValue(value: $0) }
        referencedMessage = try object.messageField("referenced_message", Message.self, nullable: true)
        guildID = try object.field("guild_id", GuildID.self)
        member = try object.messageField("member", GatewayPartialGuildMember.self)
        channelType = try object.field("channel_type", RawValue<ChannelType>.self)
        rawFields = object.resource.fields
    }
}

/// Checks exact integer tokens before decoding an optional integer array.
/// - Parameters:
///   - object: Bounded containing object.
///   - name: Nonnullable optional integer-array key.
/// - Returns: Absent or the ordered exact integral values; pair size is checked by the containing model.
/// - Throws: Sanitized invalid-response errors for nonarrays, nonintegers, exponent/fraction tokens or range errors.
private func gatewayIntegerArray(_ object: PayloadObject, name: String) throws -> Field<[Int]> {
    try object.nested(name) { value in
        guard case .array(let values) = value else { throw DiscordError.transport(.invalidResponse) }
        return try values.map { element in
            guard case .number(let number) = element,
                  !number.rawValue.contains("."), !number.rawValue.contains("e"), !number.rawValue.contains("E"),
                  let result = Int(number.rawValue) else { throw DiscordError.transport(.invalidResponse) }
            return result
        }
    }
}

/// Projects a required emoji whose existing resource type does not adopt the internal tree marker.
/// - Parameters:
///   - object: Already bounded containing object.
///   - name: Required nonnull emoji wire key.
/// - Returns: The validated partial emoji, retaining Unicode and deleted-name semantics.
/// - Throws: Sanitized invalid-response errors for missing keys or invalid emoji fields.
private func gatewayRequiredEmoji(_ object: PayloadObject, name: String) throws -> PartialEmoji {
    guard let value = object.resource.fields[name] else { throw DiscordError.transport(.invalidResponse) }
    return try PartialEmoji(value: value, limits: object.limits)
}

/// Projects a required finite JSON number without the integer-only scalar bridge.
/// - Parameters:
///   - object: Already bounded containing object.
///   - name: Required numeric wire key, whose units are documented by the containing model.
/// - Returns: A finite Double; its exact original lexeme remains in rawFields.
/// - Throws: Sanitized invalid-response errors for missing, null, nonnumeric or nonfinite values.
private func gatewayRequiredNumber(_ object: PayloadObject, name: String) throws -> Double {
    guard case .value(let number) = try object.messageNumber(name) else {
        throw DiscordError.transport(.invalidResponse)
    }
    return number
}

/// Accepts Discord's string snowflakes and integer IDs for voice-effect default sounds.
/// - Parameters:
///   - value: Already bounded scalar; integer spelling is required for JSON numbers.
///   - limits: Whole-document bounds reused for exact scalar conversion.
/// - Returns: The exact unsigned sound identity without floating-point conversion.
/// - Throws: Sanitized invalid-response errors for fractions, exponents, negatives, overflow or incompatible roots.
private func gatewaySoundID(_ value: JSONValue, limits: JSONLimits) throws -> SoundboardSoundID {
    switch value {
    case .string(let text):
        guard let result = SoundboardSoundID(text) else { throw DiscordError.transport(.invalidResponse) }
        return result
    case .number(let number):
        guard !number.rawValue.contains("."), !number.rawValue.contains("e"), !number.rawValue.contains("E"),
              let result = SoundboardSoundID(number.rawValue) else { throw DiscordError.transport(.invalidResponse) }
        return result
    default: throw DiscordError.transport(.invalidResponse)
    }
}

/// Available/unavailable GUILD_CREATE union. Outage markers never require full Guild fields.
/// Both variants preserve raw data and redact ordinary diagnostics; no cache or authorization changes occur.
public indirect enum GatewayGuildCreate: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// A full Guild plus Gateway-owned state, potentially restricted by intents and thresholds.
    case available(GatewayAvailableGuild)
    /// An outage marker containing an identity and unavailable flag.
    case unavailable(GatewayGuildAvailability)

    /// Parses one complete GUILD_CREATE while choosing the outage variant before requiring Guild fields.
    /// - Parameters:
    ///   - data: Complete UTF-8 object, with unavailable true for the outage variant.
    ///   - limits: Whole-document byte/depth/node bounds, including unknown fields; defaults to standard bounds.
    /// - Throws: JSON syntax/bound errors or sanitized invalid-response errors for malformed known fields.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects a previously bounded guild subtree without interpreting an outage marker as a full snapshot.
    /// - Parameters:
    ///   - value: Original object subtree from a containing document that passed parser bounds.
    ///   - limits: Bounds established by the root parse.
    /// - Throws: Sanitized invalid-response errors for malformed availability or selected variant fields.
    init(value: JSONValue, limits: JSONLimits) throws {
        let marker = try GatewayGuildAvailability(value: value, limits: limits)
        if marker.unavailable == .value(true) { self = .unavailable(marker) }
        else { self = .available(try GatewayAvailableGuild(value: value, limits: limits)) }
    }

    /// Returns the complete original variant payload, preserving exact unknown numeric spellings.
    /// - Returns: The immutable object; callers control deliberate inspection and logging.
    public func jsonValue() -> JSONValue {
        switch self {
        case .available(let guild): guild.jsonValue()
        case .unavailable(let guild): guild.jsonValue()
        }
    }

    /// Conceals identifiers, member data and tokens from ordinary formatting.
    public var description: String { "GatewayGuildCreate(redacted)" }
    /// Uses the same redacted debug marker.
    public var debugDescription: String { description }
    /// Prevents reflection from traversing payloads.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}
