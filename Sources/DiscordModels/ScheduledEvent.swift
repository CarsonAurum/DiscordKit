// File: Sources/DiscordModels/ScheduledEvent.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import Foundation

/// Complete written API v10 event and optional OpenAPI RSVP/exception extensions. Related User projections remain explicitly partial. Reading requires guild membership or public-guild visibility plus VIEW_CHANNEL for channel-backed events. Response parsing retains unknown kinds and does not reapply mutation constraints.
/// Verified 2026-10-16 against the official Guild Scheduled Event/Stage Instance references and discord-api-spec.
public struct GuildScheduledEvent: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Exact wire id projection; original unknown fields remain available in rawFields.
    public let id: GuildScheduledEventID
    /// Exact wire guild_id projection; original unknown fields remain available in rawFields.
    public let guildID: GuildID
    /// Exact wire channel_id projection; original unknown fields remain available in rawFields.
    public let channelID: Nullable<ChannelID>
    /// Exact wire creator_id projection; original unknown fields remain available in rawFields.
    public let creatorID: Field<UserID>
    /// Exact wire name projection; original unknown fields remain available in rawFields.
    public let name: String
    /// Exact wire description projection; original unknown fields remain available in rawFields.
    public let eventDescription: Field<String>
    /// Exact wire scheduled_start_time projection; original unknown fields remain available in rawFields.
    public let scheduledStartTime: DiscordTimestamp
    /// Exact wire scheduled_end_time projection; original unknown fields remain available in rawFields.
    public let scheduledEndTime: Nullable<DiscordTimestamp>
    /// Exact wire privacy_level projection; original unknown fields remain available in rawFields.
    public let privacyLevel: RawValue<GuildScheduledEventPrivacyLevel>
    /// Exact wire status projection; original unknown fields remain available in rawFields.
    public let status: RawValue<GuildScheduledEventStatus>
    /// Exact wire entity_type projection; original unknown fields remain available in rawFields.
    public let entityType: RawValue<GuildScheduledEventEntityType>
    /// Exact wire entity_id projection; original unknown fields remain available in rawFields.
    public let entityID: Nullable<ScheduledEventEntityID>
    /// Exact wire entity_metadata projection; original unknown fields remain available in rawFields.
    public let entityMetadata: Nullable<ScheduledEventEntityMetadata>
    /// Exact wire creator projection; original unknown fields remain available in rawFields.
    public let creator: Field<ChannelRecipient>
    /// Exact wire user_count projection; original unknown fields remain available in rawFields.
    public let userCount: Field<Int>
    /// Exact wire image projection; original unknown fields remain available in rawFields.
    public let image: Field<String>
    /// Exact wire recurrence_rule projection; original unknown fields remain available in rawFields.
    public let recurrenceRule: Nullable<ScheduledEventRecurrenceRule>
    /// Exact wire user_rsvp projection; original unknown fields remain available in rawFields.
    public let userRSVP: Field<GuildScheduledEventUser>
    /// Exact wire guild_scheduled_event_exceptions projection; original unknown fields remain available in rawFields.
    public let exceptions: Field<[ScheduledEventException]>
    /// Complete original object, preserving unknown fields and numeric lexemes; diagnostics redact payloads.
    public let rawFields: [String: JSONValue]

    /// Parses one immutable bounded object without I/O, permission checks, suspension or hydration.
    /// - Parameters:
    ///   - data: Complete UTF-8 object; duplicate keys and trailing JSON documents are rejected.
    ///   - limits: Whole-document byte/depth/node bounds, including unknown subtrees; defaults to 1 MiB/64/100,000.
    /// - Throws: JSON syntax/bounds errors or sanitized invalid-response errors for missing, forbidden-null,
    ///   malformed or mistyped fields, invalid IDs/timestamps and nonintegral or overflowing integer values.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects an already bounded subtree without reparsing, mutation, tasks or external resource ownership.
    /// - Parameters:
    ///   - value: Original object from a complete document that already passed parser bounds.
    ///   - limits: Same whole-document limits used for scalar projection and exact integer validation.
    /// - Throws: Sanitized invalid-response errors for incompatible known fields. Response-only values and
    ///   future enum cases remain preserved; parsing does not establish current server authorization or freshness.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        id = try object.required("id", GuildScheduledEventID.self)
        guildID = try object.required("guild_id", GuildID.self)
        channelID = try object.required("channel_id", Nullable<ChannelID>.self)
        creatorID = try object.field("creator_id", UserID.self, nullable: true)
        name = try object.required("name", String.self)
        eventDescription = try object.field("description", String.self, nullable: true)
        scheduledStartTime = try object.required("scheduled_start_time", DiscordTimestamp.self)
        scheduledEndTime = try object.required("scheduled_end_time", Nullable<DiscordTimestamp>.self)
        privacyLevel = try object.required("privacy_level", RawValue<GuildScheduledEventPrivacyLevel>.self)
        status = try object.required("status", RawValue<GuildScheduledEventStatus>.self)
        entityType = try object.required("entity_type", RawValue<GuildScheduledEventEntityType>.self)
        entityID = try object.required("entity_id", Nullable<ScheduledEventEntityID>.self)
        guard let entityMetadataValue = object.resource.fields["entity_metadata"] else { throw DiscordError.transport(.invalidResponse) }
        entityMetadata = entityMetadataValue == .null ? .null : .value(try ScheduledEventEntityMetadata(value: entityMetadataValue, limits: limits))
        creator = try object.messageField("creator", ChannelRecipient.self)
        userCount = try object.field("user_count", Int.self)
        image = try object.field("image", String.self, nullable: true)
        guard let recurrenceRuleValue = object.resource.fields["recurrence_rule"] else { throw DiscordError.transport(.invalidResponse) }
        recurrenceRule = recurrenceRuleValue == .null ? .null : .value(try ScheduledEventRecurrenceRule(value: recurrenceRuleValue, limits: limits))
        userRSVP = try object.messageField("user_rsvp", GuildScheduledEventUser.self, nullable: true)
        exceptions = try object.messageArray("guild_scheduled_event_exceptions", ScheduledEventException.self)
        if case .value(let count) = userCount, count < 0 { throw DiscordError.transport(.invalidResponse) }
        rawFields = object.resource.fields
    }
}

/// API v10 event metadata; external event writes require a nonnull location, while response fields preserve their exact presence.
/// Verified 2026-10-16 against the official Guild Scheduled Event/Stage Instance references and discord-api-spec.
public struct ScheduledEventEntityMetadata: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Exact wire location projection; original unknown fields remain available in rawFields.
    public let location: Field<String>
    /// Complete original object, preserving unknown fields and numeric lexemes; diagnostics redact payloads.
    public let rawFields: [String: JSONValue]

    /// Parses one immutable bounded object without I/O, permission checks, suspension or hydration.
    /// - Parameters:
    ///   - data: Complete UTF-8 object; duplicate keys and trailing JSON documents are rejected.
    ///   - limits: Whole-document byte/depth/node bounds, including unknown subtrees; defaults to 1 MiB/64/100,000.
    /// - Throws: JSON syntax/bounds errors or sanitized invalid-response errors for missing, forbidden-null,
    ///   malformed or mistyped fields, invalid IDs/timestamps and nonintegral or overflowing integer values.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects an already bounded subtree without reparsing, mutation, tasks or external resource ownership.
    /// - Parameters:
    ///   - value: Original object from a complete document that already passed parser bounds.
    ///   - limits: Same whole-document limits used for scalar projection and exact integer validation.
    /// - Throws: Sanitized invalid-response errors for incompatible known fields. Response-only values and
    ///   future enum cases remain preserved; parsing does not establish current server authorization or freshness.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        location = try object.field("location", String.self)
        rawFields = object.resource.fields
    }
}

/// Complete API v10 recurrence snapshot. End, by_year_day and count preserve absence for compatibility with the official preview. Unknown discriminators and response combinations survive; client mutation limitations apply only to request values.
/// Verified 2026-10-16 against the official Guild Scheduled Event/Stage Instance references and discord-api-spec.
public struct ScheduledEventRecurrenceRule: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Exact wire start projection; original unknown fields remain available in rawFields.
    public let start: DiscordTimestamp
    /// Exact wire end projection; original unknown fields remain available in rawFields.
    public let end: Field<DiscordTimestamp>
    /// Exact wire frequency projection; original unknown fields remain available in rawFields.
    public let frequency: RawValue<ScheduledEventRecurrenceFrequency>
    /// Exact wire interval projection; original unknown fields remain available in rawFields.
    public let interval: Int
    /// Exact wire by_weekday projection; original unknown fields remain available in rawFields.
    public let byWeekday: Nullable<[RawValue<ScheduledEventWeekday>]>
    /// Exact wire by_n_weekday projection; original unknown fields remain available in rawFields.
    public let byNWeekday: Nullable<[ScheduledEventNWeekday]>
    /// Exact wire by_month projection; original unknown fields remain available in rawFields.
    public let byMonth: Nullable<[RawValue<ScheduledEventMonth>]>
    /// Exact wire by_month_day projection; original unknown fields remain available in rawFields.
    public let byMonthDay: Nullable<[Int]>
    /// Exact wire by_year_day projection; original unknown fields remain available in rawFields.
    public let byYearDay: Field<[Int]>
    /// Exact wire count projection; original unknown fields remain available in rawFields.
    public let count: Field<Int>
    /// Complete original object, preserving unknown fields and numeric lexemes; diagnostics redact payloads.
    public let rawFields: [String: JSONValue]

    /// Parses one immutable bounded object without I/O, permission checks, suspension or hydration.
    /// - Parameters:
    ///   - data: Complete UTF-8 object; duplicate keys and trailing JSON documents are rejected.
    ///   - limits: Whole-document byte/depth/node bounds, including unknown subtrees; defaults to 1 MiB/64/100,000.
    /// - Throws: JSON syntax/bounds errors or sanitized invalid-response errors for missing, forbidden-null,
    ///   malformed or mistyped fields, invalid IDs/timestamps and nonintegral or overflowing integer values.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects an already bounded subtree without reparsing, mutation, tasks or external resource ownership.
    /// - Parameters:
    ///   - value: Original object from a complete document that already passed parser bounds.
    ///   - limits: Same whole-document limits used for scalar projection and exact integer validation.
    /// - Throws: Sanitized invalid-response errors for incompatible known fields. Response-only values and
    ///   future enum cases remain preserved; parsing does not establish current server authorization or freshness.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        start = try object.required("start", DiscordTimestamp.self)
        end = try object.field("end", DiscordTimestamp.self, nullable: true)
        frequency = try object.required("frequency", RawValue<ScheduledEventRecurrenceFrequency>.self)
        interval = try object.required("interval", Int.self)
        byWeekday = try scheduledEventEnumArray(object, key: "by_weekday", type: ScheduledEventWeekday.self)
        guard let byNWeekdayValue = object.resource.fields["by_n_weekday"] else { throw DiscordError.transport(.invalidResponse) }
        byNWeekday = byNWeekdayValue == .null ? .null : .value(try object.messageModels("by_n_weekday", ScheduledEventNWeekday.self))
        byMonth = try scheduledEventEnumArray(object, key: "by_month", type: ScheduledEventMonth.self)
        guard let byMonthDayValue = object.resource.fields["by_month_day"] else { throw DiscordError.transport(.invalidResponse) }
        byMonthDay = byMonthDayValue == .null ? .null : .value(try scheduledEventIntegerValues(byMonthDayValue))
        byYearDay = try object.nested("by_year_day", nullable: true) { try scheduledEventIntegerValues($0) }
        count = try object.field("count", Int.self, nullable: true)
        rawFields = object.resource.fields
    }
}

/// API v10 ordinal weekday snapshot. Response values are retained without applying current request bounds.
/// Verified 2026-10-16 against the official Guild Scheduled Event/Stage Instance references and discord-api-spec.
public struct ScheduledEventNWeekday: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Exact wire n projection; original unknown fields remain available in rawFields.
    public let n: Int
    /// Exact wire day projection; original unknown fields remain available in rawFields.
    public let day: RawValue<ScheduledEventWeekday>
    /// Complete original object, preserving unknown fields and numeric lexemes; diagnostics redact payloads.
    public let rawFields: [String: JSONValue]

    /// Parses one immutable bounded object without I/O, permission checks, suspension or hydration.
    /// - Parameters:
    ///   - data: Complete UTF-8 object; duplicate keys and trailing JSON documents are rejected.
    ///   - limits: Whole-document byte/depth/node bounds, including unknown subtrees; defaults to 1 MiB/64/100,000.
    /// - Throws: JSON syntax/bounds errors or sanitized invalid-response errors for missing, forbidden-null,
    ///   malformed or mistyped fields, invalid IDs/timestamps and nonintegral or overflowing integer values.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects an already bounded subtree without reparsing, mutation, tasks or external resource ownership.
    /// - Parameters:
    ///   - value: Original object from a complete document that already passed parser bounds.
    ///   - limits: Same whole-document limits used for scalar projection and exact integer validation.
    /// - Throws: Sanitized invalid-response errors for incompatible known fields. Response-only values and
    ///   future enum cases remain preserved; parsing does not establish current server authorization or freshness.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        n = try object.required("n", Int.self)
        day = try object.required("day", RawValue<ScheduledEventWeekday>.self)
        rawFields = object.resource.fields
    }
}

/// Complete recurrence exception snapshot from the official OpenAPI preview. This value does not claim support for exception mutation endpoints.
/// Verified 2026-10-16 against the official Guild Scheduled Event/Stage Instance references and discord-api-spec.
public struct ScheduledEventException: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Exact wire event_id projection; original unknown fields remain available in rawFields.
    public let eventID: GuildScheduledEventID
    /// Exact wire event_exception_id projection; original unknown fields remain available in rawFields.
    public let id: ScheduledEventExceptionID
    /// Exact wire scheduled_start_time projection; original unknown fields remain available in rawFields.
    public let scheduledStartTime: Nullable<DiscordTimestamp>
    /// Exact wire scheduled_end_time projection; original unknown fields remain available in rawFields.
    public let scheduledEndTime: Nullable<DiscordTimestamp>
    /// Exact wire is_canceled projection; original unknown fields remain available in rawFields.
    public let isCanceled: Bool
    /// Complete original object, preserving unknown fields and numeric lexemes; diagnostics redact payloads.
    public let rawFields: [String: JSONValue]

    /// Parses one immutable bounded object without I/O, permission checks, suspension or hydration.
    /// - Parameters:
    ///   - data: Complete UTF-8 object; duplicate keys and trailing JSON documents are rejected.
    ///   - limits: Whole-document byte/depth/node bounds, including unknown subtrees; defaults to 1 MiB/64/100,000.
    /// - Throws: JSON syntax/bounds errors or sanitized invalid-response errors for missing, forbidden-null,
    ///   malformed or mistyped fields, invalid IDs/timestamps and nonintegral or overflowing integer values.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects an already bounded subtree without reparsing, mutation, tasks or external resource ownership.
    /// - Parameters:
    ///   - value: Original object from a complete document that already passed parser bounds.
    ///   - limits: Same whole-document limits used for scalar projection and exact integer validation.
    /// - Throws: Sanitized invalid-response errors for incompatible known fields. Response-only values and
    ///   future enum cases remain preserved; parsing does not establish current server authorization or freshness.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        eventID = try object.required("event_id", GuildScheduledEventID.self)
        id = try object.required("event_exception_id", ScheduledEventExceptionID.self)
        scheduledStartTime = try object.required("scheduled_start_time", Nullable<DiscordTimestamp>.self)
        scheduledEndTime = try object.required("scheduled_end_time", Nullable<DiscordTimestamp>.self)
        isCanceled = try object.required("is_canceled", Bool.self)
        rawFields = object.resource.fields
    }
}

/// API v10 subscriber/RSVP snapshot combining the written user object with the optional official-preview ID/response form. The written form requires user; the preview ID form requires user_id and response. When both user forms exist their IDs must agree. The users endpoint additionally requires user.
/// Verified 2026-10-16 against the official Guild Scheduled Event/Stage Instance references and discord-api-spec.
public struct GuildScheduledEventUser: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Exact wire guild_scheduled_event_id projection; original unknown fields remain available in rawFields.
    public let guildScheduledEventID: GuildScheduledEventID
    /// Exact wire user projection; original unknown fields remain available in rawFields.
    public let user: Field<ChannelRecipient>
    /// Exact wire member projection; original unknown fields remain available in rawFields.
    public let member: Field<GuildMember>
    /// Exact wire user_id projection; original unknown fields remain available in rawFields.
    public let userID: Field<UserID>
    /// Exact wire guild_scheduled_event_exception_id projection; original unknown fields remain available in rawFields.
    public let exceptionID: Field<ScheduledEventExceptionID>
    /// Exact wire response projection; original unknown fields remain available in rawFields.
    public let response: Field<RawValue<ScheduledEventUserResponse>>
    /// Complete original object, preserving unknown fields and numeric lexemes; diagnostics redact payloads.
    public let rawFields: [String: JSONValue]

    /// Parses one immutable bounded object without I/O, permission checks, suspension or hydration.
    /// - Parameters:
    ///   - data: Complete UTF-8 object; duplicate keys and trailing JSON documents are rejected.
    ///   - limits: Whole-document byte/depth/node bounds, including unknown subtrees; defaults to 1 MiB/64/100,000.
    /// - Throws: JSON syntax/bounds errors or sanitized invalid-response errors for missing, forbidden-null,
    ///   malformed or mistyped fields, invalid IDs/timestamps and nonintegral or overflowing integer values.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects an already bounded subtree without reparsing, mutation, tasks or external resource ownership.
    /// - Parameters:
    ///   - value: Original object from a complete document that already passed parser bounds.
    ///   - limits: Same whole-document limits used for scalar projection and exact integer validation.
    /// - Throws: Sanitized invalid-response errors for incompatible known fields. Response-only values and
    ///   future enum cases remain preserved; parsing does not establish current server authorization or freshness.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        guildScheduledEventID = try object.required("guild_scheduled_event_id", GuildScheduledEventID.self)
        user = try object.messageField("user", ChannelRecipient.self)
        member = try object.messageField("member", GuildMember.self)
        userID = try object.field("user_id", UserID.self)
        exceptionID = try object.field("guild_scheduled_event_exception_id", ScheduledEventExceptionID.self, nullable: true)
        response = try object.field("response", RawValue<ScheduledEventUserResponse>.self)
        switch (user, userID) {
        case (.value(let user), .value(let id)):
            guard user.id == id else { throw DiscordError.transport(.invalidResponse) }
        case (.value, .absent): break
        case (.absent, .value):
            guard case .value = response else { throw DiscordError.transport(.invalidResponse) }
        default: throw DiscordError.transport(.invalidResponse)
        }
        rawFields = object.resource.fields
    }
}

/// Complete API v10 live-stage snapshot, including deprecated discovery and public visibility fields. No voice connection, speaker state, permission inference or automatic lifecycle owner is created.
/// Verified 2026-10-16 against the official Guild Scheduled Event/Stage Instance references and discord-api-spec.
public struct StageInstance: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Exact wire id projection; original unknown fields remain available in rawFields.
    public let id: StageInstanceID
    /// Exact wire guild_id projection; original unknown fields remain available in rawFields.
    public let guildID: GuildID
    /// Exact wire channel_id projection; original unknown fields remain available in rawFields.
    public let channelID: ChannelID
    /// Exact wire topic projection; original unknown fields remain available in rawFields.
    public let topic: String
    /// Exact wire privacy_level projection; original unknown fields remain available in rawFields.
    public let privacyLevel: RawValue<StageInstancePrivacyLevel>
    /// Exact wire discoverable_disabled projection; original unknown fields remain available in rawFields.
    public let discoverableDisabled: Bool
    /// Exact wire guild_scheduled_event_id projection; original unknown fields remain available in rawFields.
    public let guildScheduledEventID: Nullable<GuildScheduledEventID>
    /// Complete original object, preserving unknown fields and numeric lexemes; diagnostics redact payloads.
    public let rawFields: [String: JSONValue]

    /// Parses one immutable bounded object without I/O, permission checks, suspension or hydration.
    /// - Parameters:
    ///   - data: Complete UTF-8 object; duplicate keys and trailing JSON documents are rejected.
    ///   - limits: Whole-document byte/depth/node bounds, including unknown subtrees; defaults to 1 MiB/64/100,000.
    /// - Throws: JSON syntax/bounds errors or sanitized invalid-response errors for missing, forbidden-null,
    ///   malformed or mistyped fields, invalid IDs/timestamps and nonintegral or overflowing integer values.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects an already bounded subtree without reparsing, mutation, tasks or external resource ownership.
    /// - Parameters:
    ///   - value: Original object from a complete document that already passed parser bounds.
    ///   - limits: Same whole-document limits used for scalar projection and exact integer validation.
    /// - Throws: Sanitized invalid-response errors for incompatible known fields. Response-only values and
    ///   future enum cases remain preserved; parsing does not establish current server authorization or freshness.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        id = try object.required("id", StageInstanceID.self)
        guildID = try object.required("guild_id", GuildID.self)
        channelID = try object.required("channel_id", ChannelID.self)
        topic = try object.required("topic", String.self)
        privacyLevel = try object.required("privacy_level", RawValue<StageInstancePrivacyLevel>.self)
        discoverableDisabled = try object.required("discoverable_disabled", Bool.self)
        guildScheduledEventID = try object.required("guild_scheduled_event_id", Nullable<GuildScheduledEventID>.self)
        rawFields = object.resource.fields
    }
}

/// Projects a required nullable enum array using exact number tokens rather than lossy Codable rounding.
/// - Parameters:
///   - object: Already bounded containing recurrence object.
///   - key: Required nullable array key.
///   - type: Known integer enum whose future raw values must remain intact.
/// - Returns: Null or ordered exact raw values, including unknown discriminators and an empty array.
/// - Throws: Sanitized invalid-response for omission, wrong roots, noninteger tokens or native overflow.
func scheduledEventEnumArray<E: RawRepresentable & Sendable>(_ object: PayloadObject, key: String,
    type: E.Type) throws -> Nullable<[RawValue<E>]> where E.RawValue == Int {
    guard let value = object.resource.fields[key] else { throw DiscordError.transport(.invalidResponse) }
    if value == .null { return .null }
    guard case .array(let values) = value else { throw DiscordError.transport(.invalidResponse) }
    return .value(try values.map {
        guard case .number(let number) = $0, let raw = Int(number.rawValue)
        else { throw DiscordError.transport(.invalidResponse) }
        return RawValue<E>(rawValue: raw)
    })
}

/// Reads exact integral recurrence members, avoiding JSONDecoder rounding of nested number tokens.
/// - Parameter value: Already bounded array subtree, including empty arrays and future integral values.
/// - Returns: Ordered native integers without normalization or mutation-only bounds.
/// - Throws: Sanitized invalid-response for nonarrays, noninteger members or native integer overflow.
func scheduledEventIntegerValues(_ value: JSONValue) throws -> [Int] {
    guard case .array(let values) = value else { throw DiscordError.transport(.invalidResponse) }
    return try values.map {
        guard case .number(let number) = $0, let result = Int(number.rawValue)
        else { throw DiscordError.transport(.invalidResponse) }
        return result
    }
}
