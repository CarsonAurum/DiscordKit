import DiscordCore
import Foundation

/// A validated monthly recurrence selector. Current Discord rules permit one selector per rule.
public struct ScheduledEventNWeekdayRequest: GuildRequestPayload {
    private let fields: [String: JSONValue]

    /// Creates one ordinal weekday without evaluating a calendar or expanding occurrences.
    /// - Parameters:
    ///   - n: Week ordinal in 1...5.
    ///   - day: Known Monday-zero weekday; unknown raw values are response-only.
    /// - Throws: Safe invalid-value for an ordinal outside 1...5. No I/O or suspension occurs.
    public init(n: Int, day: ScheduledEventWeekday) throws {
        fields = ["n": try guildRequestRange(n, 1...5), "day": try guildRequestNumber(day.rawValue)]
    }

    /// Returns the exact validated selector without expanding or normalizing recurrence dates.
    /// - Returns: Object containing n and day; serialization deliberately exposes selected values.
    public func jsonValue() -> JSONValue { .object(fields) }
}

/// Validated writable recurrence subset of the API v10 Guild Scheduled Event reference.
/// End, count and by_year_day cannot currently be set externally and have no request parameters.
/// Frequency uses the authoritative table/examples: yearly 0, monthly 1, weekly 2, daily 3.
public struct ScheduledEventRecurrenceRequest: GuildRequestPayload {
    private let fields: [String: JSONValue]

    /// Validates current client recurrence limitations without expanding future occurrences.
    /// - Parameters:
    ///   - start: Exact recurrence start; server scheduling and time-zone behavior remain upstream checks.
    ///   - frequency: Known yearly/monthly/weekly/daily recurrence kind.
    ///   - interval: 1 by default; 2 is additionally allowed only for weekly events.
    ///   - byWeekday: Optional distinct weekdays. Weekly permits exactly one; daily permits only the
    ///     documented sets Mon-Fri, Tue-Sat, Sun-Thu, Fri-Sat, Sat-Sun or Sun-Mon. Order is retained.
    ///   - byNWeekday: Optional single monthly ordinal selector; mutually exclusive with other selectors.
    ///   - byMonth: Optional single annual month, required together with byMonthDay.
    ///   - byMonthDay: Optional single annual day 1...31 or -1 for last day per official preview;
    ///     impossible dates for the chosen month are rejected, while February 29 remains valid for leap years.
    /// - Throws: Safe invalid-value errors for incompatible selectors, duplicate/empty arrays, invalid
    ///   intervals or impossible dates. Construction is synchronous and owns no task, clock or resource.
    public init(start: DiscordTimestamp, frequency: ScheduledEventRecurrenceFrequency, interval: Int = 1,
                byWeekday: [ScheduledEventWeekday]? = nil, byNWeekday: [ScheduledEventNWeekdayRequest]? = nil,
                byMonth: [ScheduledEventMonth]? = nil, byMonthDay: [Int]? = nil) throws {
        guard interval == 1 || (frequency == .weekly && interval == 2) else { throw DiscordError.validation(.invalidValue) }
        let choices = (byWeekday == nil ? 0 : 1) + (byNWeekday == nil ? 0 : 1) + (byMonth == nil && byMonthDay == nil ? 0 : 1)
        guard choices <= 1 else { throw DiscordError.validation(.invalidValue) }
        var result: [String: JSONValue] = ["start": .string(start.rawValue),
            "frequency": try guildRequestNumber(frequency.rawValue), "interval": try guildRequestNumber(interval)]
        if let byWeekday {
            let days = byWeekday.map(\.rawValue)
            guard Set(days).count == days.count else { throw DiscordError.validation(.invalidValue) }
            if frequency == .weekly {
                guard days.count == 1 else { throw DiscordError.validation(.invalidValue) }
            } else if frequency == .daily {
                let allowed = [[0, 1, 2, 3, 4], [1, 2, 3, 4, 5], [6, 0, 1, 2, 3], [4, 5], [5, 6], [6, 0]].map { Set($0) }
                guard allowed.contains(Set(days)) else { throw DiscordError.validation(.invalidValue) }
            } else { throw DiscordError.validation(.invalidValue) }
            result["by_weekday"] = .array(try days.map { try guildRequestNumber($0) })
        }
        if let byNWeekday {
            guard frequency == .monthly, byNWeekday.count == 1 else { throw DiscordError.validation(.invalidValue) }
            result["by_n_weekday"] = .array(byNWeekday.map { $0.jsonValue() })
        }
        if byMonth != nil || byMonthDay != nil {
            guard frequency == .yearly, let months = byMonth, months.count == 1,
                  let days = byMonthDay, days.count == 1 else { throw DiscordError.validation(.invalidValue) }
            let maximum = [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][months[0].rawValue - 1]
            guard days[0] == -1 || (1...maximum).contains(days[0]) else { throw DiscordError.validation(.invalidValue) }
            result["by_month"] = .array([try guildRequestNumber(months[0].rawValue)])
            result["by_month_day"] = .array([try guildRequestNumber(days[0])])
        }
        fields = result
    }

    /// Returns the writable rule without adding unsupported end/count/by_year_day values.
    /// - Returns: Exact start/frequency/interval and caller-selected recurrence selectors.
    public func jsonValue() -> JSONValue { .object(fields) }
}

/// Validated API v10 event creation. CREATE_EVENTS and entity-specific channel permissions are
/// checked by Discord; a guild may have at most 100 scheduled/active events. No permission lookup occurs.
public struct GuildScheduledEventCreate: GuildRequestPayload {
    private let fields: [String: JSONValue]

    /// Validates one event with explicit hosting constraints and exact timestamp ordering.
    /// - Parameters:
    ///   - name: Exact event name of 1...100 Unicode scalars.
    ///   - entityType: Known stage, voice or external hosting kind; channel type/existence remains server-checked.
    ///   - scheduledStartTime: Exact intended start. Discord rechecks whether it can schedule this instant.
    ///   - privacyLevel: Guild-only visibility, the only currently supported write value; defaults to guildOnly.
    ///   - channelID: Required for stage/voice and nil for external; external encodes explicit null.
    ///   - location: Required external location of 1...100 scalars; forbidden for stage/voice.
    ///   - scheduledEndTime: Required external end, optional channel-backed end; must be strictly after start.
    ///   - description: Absent by default or nullable per official preview; nonnull text is 1...1000 scalars.
    ///   - image: Absent or nullable per official preview; nonnull canonical JPEG/PNG/GIF/WebP/AVIF data URI
    ///     has a local maximum of 1 MiB decoded bytes. Discord checks media content and dimensions.
    ///   - recurrenceRule: Absent or nullable per preview; nonnull rules use the validated writable subset.
    /// - Throws: Safe invalid-value for incompatible hosting fields, text or time ordering; image syntax
    ///   errors or limit-exceeded beyond the local image cap. No network request, task or suspension occurs.
    public init(name: String, entityType: GuildScheduledEventEntityType, scheduledStartTime: DiscordTimestamp,
                privacyLevel: GuildScheduledEventPrivacyLevel = .guildOnly, channelID: ChannelID? = nil,
                location: String? = nil, scheduledEndTime: DiscordTimestamp? = nil,
                description: Field<String> = .absent, image: Field<String> = .absent,
                recurrenceRule: Field<ScheduledEventRecurrenceRequest> = .absent) throws {
        var result: [String: JSONValue] = ["name": try guildRequestText(name, length: 1...100),
            "entity_type": try guildRequestNumber(entityType.rawValue),
            "privacy_level": try guildRequestNumber(privacyLevel.rawValue),
            "scheduled_start_time": .string(scheduledStartTime.rawValue)]
        if entityType == .external {
            guard channelID == nil, let location, scheduledEndTime != nil else { throw DiscordError.validation(.invalidValue) }
            result["channel_id"] = .null
            result["entity_metadata"] = .object(["location": try guildRequestText(location, length: 1...100)])
        } else {
            guard let channelID, location == nil else { throw DiscordError.validation(.invalidValue) }
            result["channel_id"] = .string(channelID.description)
        }
        if let scheduledEndTime {
            guard scheduledEventTimePrecedes(scheduledStartTime, scheduledEndTime) else { throw DiscordError.validation(.invalidValue) }
            result["scheduled_end_time"] = .string(scheduledEndTime.rawValue)
        }
        try guildRequestField(description, name: "description", nullable: true, into: &result) { try guildRequestText($0, length: 1...1000) }
        try guildRequestField(image, name: "image", nullable: true, into: &result) { try scheduledEventImage($0) }
        try guildRequestField(recurrenceRule, name: "recurrence_rule", nullable: true, into: &result) { $0.jsonValue() }
        fields = result
    }

    /// Returns exact validated creation fields without inferring capacity or current authorization.
    /// - Returns: Immutable JSON object including explicit null channel for external events.
    public func jsonValue() -> JSONValue { .object(fields) }
}

/// Validated API v10 event PATCH. Caller-owned context prevents locally contradictory hosting or
/// lifecycle edits without implicit reads. CREATE_EVENTS/MANAGE_EVENTS and channel permissions remain server checks.
public struct GuildScheduledEventModify: GuildRequestPayload {
    /// Caller-supplied current hosting context; snapshot operations verify it against their event.
    public let currentEntityType: GuildScheduledEventEntityType
    /// Caller-supplied current status; required only when selecting a status edit.
    public let currentStatus: GuildScheduledEventStatus?
    private let fields: [String: JSONValue]

    /// Validates selected edits, retaining absence/null/value distinctions and rejecting discarded metadata.
    /// - Parameters:
    ///   - currentEntityType: Required current hosting kind; no freshness or server state is inferred.
    ///   - currentStatus: Optional current status, required for a status edit; defaults to nil.
    ///   - name: Absent or nonnull 1...100 scalar name.
    ///   - privacyLevel: Absent or nonnull guildOnly visibility.
    ///   - channelID: Absent or nullable channel ID. Switching to external requires explicit null;
    ///     switching from external to stage/voice requires a nonnull channel.
    ///   - location: Absent or nullable entity metadata location; nonnull is 1...100 scalars and external-only.
    ///     Null encodes null entity_metadata and is allowed only for stage/voice metadata clearing.
    ///   - scheduledStartTime: Absent or nonnull exact start; ordering is checked when both endpoints are edited.
    ///   - scheduledEndTime: Absent or nullable per preview; external events forbid null. Switching to
    ///     external requires an explicit end, which Discord compares with any retained start.
    ///   - description: Absent or nullable text of 1...1000 scalars.
    ///   - entityType: Absent or nonnull new hosting kind; context remains separately retained.
    ///   - status: Absent or nonnull lifecycle target. Only scheduled->active/canceled and active->completed
    ///     are writable; equal states are accepted for explicit no-op reconciliation. Terminal changes fail.
    ///   - image: Absent or nullable canonical image data URI, at most 1 MiB decoded locally.
    ///   - recurrenceRule: Absent or nullable validated writable recurrence; null removes recurrence.
    /// - Throws: Safe invalid-value for forbidden nulls, invalid text, incompatible hosting, missing
    ///   conversion companions, unsupported lifecycle transitions or time ordering; image cap errors propagate.
    ///   This synchronous operation performs no I/O, implicit hydration, logging or task creation.
    public init(currentEntityType: GuildScheduledEventEntityType, currentStatus: GuildScheduledEventStatus? = nil,
                name: Field<String> = .absent, privacyLevel: Field<GuildScheduledEventPrivacyLevel> = .absent,
                channelID: Field<ChannelID> = .absent, location: Field<String> = .absent,
                scheduledStartTime: Field<DiscordTimestamp> = .absent, scheduledEndTime: Field<DiscordTimestamp> = .absent,
                description: Field<String> = .absent, entityType: Field<GuildScheduledEventEntityType> = .absent,
                status: Field<GuildScheduledEventStatus> = .absent, image: Field<String> = .absent,
                recurrenceRule: Field<ScheduledEventRecurrenceRequest> = .absent) throws {
        self.currentEntityType = currentEntityType
        self.currentStatus = currentStatus
        let target: GuildScheduledEventEntityType
        switch entityType { case .value(let value): target = value; case .absent: target = currentEntityType; case .null: throw DiscordError.validation(.invalidValue) }
        if target == .external {
            if case .value = channelID { throw DiscordError.validation(.invalidValue) }
            if location == .null || scheduledEndTime == .null { throw DiscordError.validation(.invalidValue) }
            if case .value(.external) = entityType {
                guard channelID == .null, case .value = location, case .value = scheduledEndTime else { throw DiscordError.validation(.invalidValue) }
            }
        } else {
            if channelID == .null { throw DiscordError.validation(.invalidValue) }
            if case .value = location { throw DiscordError.validation(.invalidValue) }
            if currentEntityType == .external, target != currentEntityType {
                guard case .value = channelID else { throw DiscordError.validation(.invalidValue) }
            }
        }
        if case .value(let start) = scheduledStartTime, case .value(let end) = scheduledEndTime {
            guard scheduledEventTimePrecedes(start, end) else { throw DiscordError.validation(.invalidValue) }
        }
        if case .value(let value) = status {
            guard let currentStatus, scheduledEventTransitionAllowed(from: currentStatus, to: value) else { throw DiscordError.validation(.invalidValue) }
        }
        var result: [String: JSONValue] = [:]
        try guildRequestField(name, name: "name", into: &result) { try guildRequestText($0, length: 1...100) }
        try guildRequestField(privacyLevel, name: "privacy_level", into: &result) { try guildRequestNumber($0.rawValue) }
        try guildRequestField(channelID, name: "channel_id", nullable: true, into: &result) { .string($0.description) }
        try guildRequestField(location, name: "entity_metadata", nullable: true, into: &result) { .object(["location": try guildRequestText($0, length: 1...100)]) }
        try guildRequestField(scheduledStartTime, name: "scheduled_start_time", into: &result) { .string($0.rawValue) }
        try guildRequestField(scheduledEndTime, name: "scheduled_end_time", nullable: true, into: &result) { .string($0.rawValue) }
        try guildRequestField(description, name: "description", nullable: true, into: &result) { try guildRequestText($0, length: 1...1000) }
        try guildRequestField(entityType, name: "entity_type", into: &result) { try guildRequestNumber($0.rawValue) }
        try guildRequestField(status, name: "status", into: &result) { try guildRequestNumber($0.rawValue) }
        try guildRequestField(image, name: "image", nullable: true, into: &result) { try scheduledEventImage($0) }
        try guildRequestField(recurrenceRule, name: "recurrence_rule", nullable: true, into: &result) { $0.jsonValue() }
        fields = result
    }

    /// Returns exact selected edits; context values never become request fields.
    /// - Returns: Immutable PATCH object, including an empty object for no selected edits.
    public func jsonValue() -> JSONValue { .object(fields) }
}

/// Validates stage creation without connecting voice or checking moderator permissions.
public struct StageInstanceCreate: GuildRequestPayload {
    /// Target channel, retained for rate admission and invalidation without parsing outgoing JSON.
    public let channelID: ChannelID
    private let fields: [String: JSONValue]

    /// Creates a validated API v10 stage body; the caller must be a stage moderator.
    /// - Parameters:
    ///   - channelID: Stage channel; type and existence remain server checks.
    ///   - topic: Exact topic of 1...120 Unicode scalars.
    ///   - privacyLevel: Absent by default, preserving guildOnly server default; deprecated public is rejected.
    ///   - sendStartNotification: Absent by default or nonnull Boolean. True additionally requires MENTION_EVERYONE.
    ///   - guildScheduledEventID: Optional nonnull event link; Discord checks hosting and lifecycle eligibility.
    /// - Throws: Safe invalid-value for invalid topic, forbidden nulls or deprecated public visibility.
    ///   Construction is synchronous and owns no transport, voice task or external resource.
    public init(channelID: ChannelID, topic: String, privacyLevel: Field<StageInstancePrivacyLevel> = .absent,
                sendStartNotification: Field<Bool> = .absent, guildScheduledEventID: Field<GuildScheduledEventID> = .absent) throws {
        self.channelID = channelID
        var result: [String: JSONValue] = ["channel_id": .string(channelID.description), "topic": try guildRequestText(topic, length: 1...120)]
        try guildRequestField(privacyLevel, name: "privacy_level", into: &result) {
            guard $0 == .guildOnly else { throw DiscordError.validation(.invalidValue) }; return try guildRequestNumber($0.rawValue)
        }
        try guildRequestField(sendStartNotification, name: "send_start_notification", into: &result) { .bool($0) }
        try guildRequestField(guildScheduledEventID, name: "guild_scheduled_event_id", into: &result) { .string($0.description) }
        fields = result
    }

    /// Returns the exact selected stage fields without adding defaults or sending a notification.
    /// - Returns: Validated immutable creation object; execution is separately explicit.
    public func jsonValue() -> JSONValue { .object(fields) }
}

/// Validated API v10 stage PATCH; moderator permissions remain checked by Discord.
public struct StageInstanceModify: GuildRequestPayload {
    private let fields: [String: JSONValue]

    /// Selects a topic or guildOnly visibility edit without fetching current stage state.
    /// - Parameters:
    ///   - topic: Absent or nonnull exact 1...120 scalar topic.
    ///   - privacyLevel: Absent or nonnull guildOnly; deprecated public is response-only.
    /// - Throws: Safe invalid-value for invalid topic, forbidden null or deprecated public visibility.
    ///   Construction is synchronous, side-effect free and does not create voice/Gateway tasks.
    public init(topic: Field<String> = .absent, privacyLevel: Field<StageInstancePrivacyLevel> = .absent) throws {
        var result: [String: JSONValue] = [:]
        try guildRequestField(topic, name: "topic", into: &result) { try guildRequestText($0, length: 1...120) }
        try guildRequestField(privacyLevel, name: "privacy_level", into: &result) {
            guard $0 == .guildOnly else { throw DiscordError.validation(.invalidValue) }; return try guildRequestNumber($0.rawValue)
        }
        fields = result
    }

    /// Returns exact selected edits without inferring snapshot freshness or applying them.
    /// - Returns: Immutable PATCH object, possibly empty.
    public func jsonValue() -> JSONValue { .object(fields) }
}

/// Compares exact timestamp instants without floating-point Date rounding or normalization.
/// - Parameters:
///   - start: Earlier candidate, preserving its source spelling.
///   - end: Later candidate, preserving its source spelling.
/// - Returns: True only when end is strictly later at nanosecond precision; no clock or I/O occurs.
func scheduledEventTimePrecedes(_ start: DiscordTimestamp, _ end: DiscordTimestamp) -> Bool {
    start.unixSeconds < end.unixSeconds || (start.unixSeconds == end.unixSeconds && start.nanosecond < end.nanosecond)
}

/// Evaluates current documented status edges, accepting equality for caller-owned no-op detection.
/// - Parameters:
///   - from: Known current status; unknown states cannot be represented as writable context.
///   - to: Known desired status.
/// - Returns: True for equality, scheduled->active/canceled or active->completed; terminal outgoing edges fail.
func scheduledEventTransitionAllowed(from: GuildScheduledEventStatus, to: GuildScheduledEventStatus) -> Bool {
    from == to || (from == .scheduled && (to == .active || to == .canceled)) || (from == .active && to == .completed)
}

/// Validates a bounded canonical event-cover image using the existing expression media transport validator.
/// - Parameter value: Exact JPEG/PNG/GIF/WebP/AVIF base64 data URI, nonempty and at most 1 MiB decoded.
/// - Returns: Original string JSON; image dimensions and content remain server checks.
/// - Throws: Safe syntax/unsupported-media errors or limit-exceeded before oversized base64 allocation.
func scheduledEventImage(_ value: String) throws -> JSONValue {
    try expressionRequestDataURI(value, mediaTypes: GuildEmojiCreate.imageMediaTypes, maximumBytes: 1_048_576)
}
