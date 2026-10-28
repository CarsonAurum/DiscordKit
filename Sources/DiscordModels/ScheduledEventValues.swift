// File: Sources/DiscordModels/ScheduledEventValues.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore

/// Identifies a live Stage instance independently of its channel.
public enum StageInstanceTag: Sendable {}
/// Exact unsigned live-stage identifier.
public typealias StageInstanceID = Snowflake<StageInstanceTag>
/// Identifies an event's hosting entity without assuming a particular resource kind.
public enum ScheduledEventEntityTag: Sendable {}
/// Exact hosting entity ID, whose meaning depends on entity_type.
public typealias ScheduledEventEntityID = Snowflake<ScheduledEventEntityTag>
/// Identifies an individual recurrence exception exposed in the official OpenAPI preview.
public enum ScheduledEventExceptionTag: Sendable {}
/// Exact occurrence exception identifier; exception mutation endpoints remain outside this slice.
public typealias ScheduledEventExceptionID = Snowflake<ScheduledEventExceptionTag>

/// API v10 scheduled-event visibility; unknown response values remain RawValue.
public enum GuildScheduledEventPrivacyLevel: Int, Sendable, CaseIterable {
    /// Wire value 2.
    case guildOnly = 2
}

/// API v10 supported hosting kinds. Preview NONE (0) remains unknown and cannot be written.
public enum GuildScheduledEventEntityType: Int, Sendable, CaseIterable {
    /// Wire value 1.
    case stageInstance = 1
    /// Wire value 2.
    case voice = 2
    /// Wire value 3.
    case external = 3
}

/// API v10 lifecycle states. Completed and canceled are terminal.
public enum GuildScheduledEventStatus: Int, Sendable, CaseIterable {
    /// Wire value 1.
    case scheduled = 1
    /// Wire value 2.
    case active = 2
    /// Wire value 3.
    case completed = 3
    /// Wire value 4.
    case canceled = 4
}

/// API v10 recurrence frequencies, using the authoritative table/examples rather than erroneous prose parentheticals.
public enum ScheduledEventRecurrenceFrequency: Int, Sendable, CaseIterable {
    /// Wire value 0.
    case yearly = 0
    /// Wire value 1.
    case monthly = 1
    /// Wire value 2.
    case weekly = 2
    /// Wire value 3.
    case daily = 3
}

/// API v10 recurrence weekdays, Monday zero through Sunday six.
public enum ScheduledEventWeekday: Int, Sendable, CaseIterable {
    /// Wire value 0.
    case monday = 0
    /// Wire value 1.
    case tuesday = 1
    /// Wire value 2.
    case wednesday = 2
    /// Wire value 3.
    case thursday = 3
    /// Wire value 4.
    case friday = 4
    /// Wire value 5.
    case saturday = 5
    /// Wire value 6.
    case sunday = 6
}

/// API v10 recurrence months, January one through December twelve.
public enum ScheduledEventMonth: Int, Sendable, CaseIterable {
    /// Wire value 1.
    case january = 1
    /// Wire value 2.
    case february = 2
    /// Wire value 3.
    case march = 3
    /// Wire value 4.
    case april = 4
    /// Wire value 5.
    case may = 5
    /// Wire value 6.
    case june = 6
    /// Wire value 7.
    case july = 7
    /// Wire value 8.
    case august = 8
    /// Wire value 9.
    case september = 9
    /// Wire value 10.
    case october = 10
    /// Wire value 11.
    case november = 11
    /// Wire value 12.
    case december = 12
}

/// RSVP states exposed by the official OpenAPI preview; future values survive responses.
public enum ScheduledEventUserResponse: Int, Sendable, CaseIterable {
    /// Wire value 0.
    case uninterested = 0
    /// Wire value 1.
    case interested = 1
}

/// API v10 stage visibility. Public is deprecated and response-only in validated requests.
public enum StageInstancePrivacyLevel: Int, Sendable, CaseIterable {
    /// Wire value 1.
    case `public` = 1
    /// Wire value 2.
    case guildOnly = 2
}
