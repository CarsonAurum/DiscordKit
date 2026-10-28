// File: Tests/DiscordModelsTests/ScheduledEventModelTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import Foundation
import Testing
@testable import DiscordModels

/// Exact, bounded scheduled-event and stage projections with deterministic API v10 fixtures.
@Suite struct ScheduledEventModelTests {
    /// Complete event/recurrence/RSVP/exception and stage fields retain large IDs and unknown payloads.
    /// - Throws: Unexpected fixture/projection failures fail the test.
    @Test func completeProjections() throws {
        let event = try GuildScheduledEvent(data: Data(ScheduledEventModelFixture.event.utf8))
        #expect(event.id.rawValue == .max)
        #expect(event.guildID.rawValue == .max)
        #expect(event.channelID == .null)
        #expect(event.creatorID == .null)
        #expect(event.name == "private-event")
        #expect(event.eventDescription == .value("private-description"))
        #expect(event.scheduledStartTime.rawValue == "2030-01-01T00:00:00.000000001Z")
        #expect(event.scheduledEndTime == .value(try DiscordTimestamp(rawValue: "2030-01-01T01:00:00Z")))
        #expect(event.privacyLevel.knownValue == .guildOnly)
        #expect(event.status.knownValue == .scheduled)
        #expect(event.entityType.knownValue == .external)
        #expect(event.entityID == .null)
        guard case .value(let metadata) = event.entityMetadata else { Issue.record("Expected metadata"); return }
        #expect(metadata.location == .value("private-location"))
        #expect(try ScheduledEventEntityMetadata(data: Data("{}".utf8)).location == .absent)
        guard case .value(let rule) = event.recurrenceRule else { Issue.record("Expected recurrence"); return }
        #expect(rule.start == event.scheduledStartTime)
        #expect(rule.end == .null)
        #expect(rule.frequency.knownValue == .weekly)
        #expect(rule.interval == 2)
        #expect(rule.byWeekday == .value([.init(.wednesday)]))
        #expect(rule.byNWeekday == .null)
        #expect(rule.byMonth == .null)
        #expect(rule.byMonthDay == .null)
        #expect(rule.byYearDay == .null)
        #expect(rule.count == .null)
        #expect(event.userCount == .value(3))
        #expect(event.image == .null)
        guard case .value(let creator) = event.creator, case .value(let rsvp) = event.userRSVP,
              case .value(let exceptions) = event.exceptions else { Issue.record("Expected preview extras"); return }
        #expect(creator.id.rawValue == 9)
        #expect(rsvp.user == .absent)
        #expect(rsvp.userID == .value(.init(rawValue: 9)))
        #expect(rsvp.response == .value(.init(.interested)))
        #expect(rsvp.exceptionID == .null)
        #expect(exceptions.count == 1)
        #expect(exceptions[0].eventID == event.id)
        #expect(exceptions[0].id.rawValue == .max)
        #expect(exceptions[0].scheduledStartTime == .null)
        #expect(exceptions[0].scheduledEndTime == .null)
        #expect(exceptions[0].isCanceled)
        let user = try GuildScheduledEventUser(data: Data(ScheduledEventModelFixture.user.utf8))
        #expect(user.guildScheduledEventID == event.id)
        guard case .value(let member) = user.member else { Issue.record("Expected member"); return }
        #expect(member.roles.isEmpty)
        #expect(member.joinedAt == .null)
        let stage = try StageInstance(data: Data(ScheduledEventModelFixture.stage.utf8))
        #expect(stage.id.rawValue == .max)
        #expect(stage.guildID.rawValue == .max)
        #expect(stage.channelID.rawValue == .max)
        #expect(stage.topic == "private-topic")
        #expect(stage.privacyLevel.knownValue == .public)
        #expect(stage.discoverableDisabled)
        #expect(stage.guildScheduledEventID == .value(event.id))
        #expect(event.rawFields["future"] == .number(try JSONNumber(rawValue: "1.2300e+100")))
        #expect(!String(reflecting: event).contains("private"))
        #expect(!String(reflecting: stage).contains("private"))
        #expect(Mirror(reflecting: event).children.count == 1)
        #expect(try GuildScheduledEvent(data: event.jsonValue().serialized()) == event)
    }

    /// Missing and null required fields, malformed nested roots and fractional integral tokens fail safely.
    /// - Throws: Unexpected fixture/serialization errors fail the test; schema rejections are asserted.
    @Test func invalidProjections() throws {
        let constructors: [(String, [String], (Data) throws -> Void)] = [
            (ScheduledEventModelFixture.event, ["id", "guild_id", "name", "channel_id", "scheduled_start_time", "scheduled_end_time", "privacy_level", "status", "entity_type", "entity_id", "entity_metadata", "recurrence_rule"], { _ = try GuildScheduledEvent(data: $0) }),
            (ScheduledEventModelFixture.rule, ["start", "frequency", "interval", "by_weekday", "by_n_weekday", "by_month", "by_month_day"], { _ = try ScheduledEventRecurrenceRule(data: $0) }),
            (ScheduledEventModelFixture.stage, ["id", "guild_id", "channel_id", "topic", "privacy_level", "discoverable_disabled", "guild_scheduled_event_id"], { _ = try StageInstance(data: $0) }),
            (#"{"n":1,"day":2}"#, ["n", "day"], { _ = try ScheduledEventNWeekday(data: $0) }),
            (ScheduledEventModelFixture.exception, ["event_id", "event_exception_id", "scheduled_start_time", "scheduled_end_time", "is_canceled"], { _ = try ScheduledEventException(data: $0) })]
        for (source, required, decode) in constructors {
            guard case .object(let fields) = try JSONValue.parse(source) else { Issue.record("Expected fixture"); return }
            for key in required {
                var changed = fields; changed[key] = nil
                #expect(throws: DiscordError.transport(.invalidResponse)) { try decode(JSONValue.object(changed).serialized()) }
                changed[key] = ["name", "topic"].contains(key) ? .bool(true) : .string("malformed")
                #expect(throws: DiscordError.transport(.invalidResponse)) { try decode(JSONValue.object(changed).serialized()) }
            }
            for bad in ["null", "[]", "true", "0", "\"x\""] {
                #expect(throws: DiscordError.transport(.invalidResponse)) { try decode(Data(bad.utf8)) }
            }
        }
        for key in ["privacy_level", "status", "entity_type", "user_count"] {
            for token in ["1.0000000000000000000001", "1e0", "18446744073709551616"] {
                var fields = try GuildScheduledEvent(data: Data(ScheduledEventModelFixture.event.utf8)).rawFields
                fields[key] = .number(try JSONNumber(rawValue: token))
                #expect(throws: DiscordError.transport(.invalidResponse)) { try GuildScheduledEvent(data: JSONValue.object(fields).serialized()) }
            }
        }
        for key in ["by_weekday", "by_month", "by_month_day", "by_year_day"] {
            var fields = try ScheduledEventRecurrenceRule(data: Data(ScheduledEventModelFixture.rule.utf8)).rawFields
            fields[key] = .array([.number(try JSONNumber(rawValue: "1.000000000000000000001"))])
            #expect(throws: DiscordError.transport(.invalidResponse)) { try ScheduledEventRecurrenceRule(data: JSONValue.object(fields).serialized()) }
        }
        for source in [#"{"guild_scheduled_event_id":"1"}"#, #"{"guild_scheduled_event_id":"1","user_id":"9"}"#, #"{"guild_scheduled_event_id":"1","user_id":"8","user":{"id":"9","username":"a","discriminator":"0","avatar":null}}"#] {
            #expect(throws: DiscordError.transport(.invalidResponse)) { try GuildScheduledEventUser(data: Data(source.utf8)) }
        }
        #expect(throws: DiscordError.transport(.invalidResponse)) { try ScheduledEventEntityMetadata(data: Data(#"{"location":null}"#.utf8)) }
    }

    /// Nullable recurrence arrays and optional response fields validate every nested scalar without rounding.
    /// - Throws: Unexpected fixture/serialization errors fail the test; malformed nested and forbidden-null cases are asserted.
    @Test func nestedRecurrenceAndOptionalValidation() throws {
        let ruleJSON = #"{"start":"2030-01-01T00:00:00Z","frequency":999,"interval":99,"by_weekday":[999],"by_n_weekday":[{"n":5,"day":999}],"by_month":[999],"by_month_day":[-1,31],"by_year_day":[1,364],"count":10}"#
        let rule = try ScheduledEventRecurrenceRule(data: Data(ruleJSON.utf8))
        #expect(rule.frequency.knownValue == nil)
        #expect(rule.interval == 99)
        #expect(rule.end == .absent)
        #expect(rule.byWeekday == .value([.init(rawValue: 999)]))
        #expect(rule.byMonth == .value([.init(rawValue: 999)]))
        #expect(rule.byMonthDay == .value([-1,31]))
        #expect(rule.byYearDay == .value([1,364]))
        #expect(rule.count == .value(10))
        guard case .value(let weekdays) = rule.byNWeekday else { Issue.record("Expected ordinal weekday"); return }
        #expect(weekdays.first?.n == 5 && weekdays.first?.day.rawValue == 999)
        let event = try GuildScheduledEvent(data: Data(ScheduledEventModelFixture.event.utf8))
        for key in ["creator", "user_count", "guild_scheduled_event_exceptions"] {
            var fields = event.rawFields; fields[key] = .null
            #expect(throws: DiscordError.transport(.invalidResponse)) { try GuildScheduledEvent(data: JSONValue.object(fields).serialized()) }
        }
        var negativeCount = event.rawFields; negativeCount["user_count"] = .number(try JSONNumber(rawValue: "-1"))
        #expect(throws: DiscordError.transport(.invalidResponse)) { try GuildScheduledEvent(data: JSONValue.object(negativeCount).serialized()) }
        for key in ["by_weekday", "by_n_weekday", "by_month", "by_month_day", "by_year_day"] {
            for invalid in [JSONValue.bool(true), .array([.null]), .array([.string("1")])] {
                var fields = rule.rawFields; fields[key] = invalid
                #expect(throws: DiscordError.transport(.invalidResponse)) { try ScheduledEventRecurrenceRule(data: JSONValue.object(fields).serialized()) }
            }
        }
        let rsvp = try GuildScheduledEventUser(data: Data(#"{"guild_scheduled_event_id":"1","user_id":"9","user":{"id":"9","username":"a","discriminator":"0","avatar":null},"response":999}"#.utf8))
        #expect(rsvp.userID == .value(.init(rawValue: 9)))
        #expect(rsvp.response == .value(.init(rawValue: 999)))
        #expect(rsvp.exceptionID == .absent)
        let stage = try StageInstance(data: Data(ScheduledEventModelFixture.stage.utf8))
        var stageFields = stage.rawFields; stageFields["privacy_level"] = .number(try JSONNumber(rawValue: "999")); stageFields["guild_scheduled_event_id"] = .null
        let futureStage = try StageInstance(data: JSONValue.object(stageFields).serialized())
        #expect(futureStage.privacyLevel.knownValue == nil)
        #expect(futureStage.guildScheduledEventID == .null)
    }

    /// Future enums and response-only limits survive while optional null/absence stays exact and bounds cover unknown data.
    /// - Throws: Unexpected model/projection errors fail the test.
    @Test func futurePresenceAndBounds() throws {
        var fields = try GuildScheduledEvent(data: Data(ScheduledEventModelFixture.event.utf8)).rawFields
        for key in ["creator_id", "creator", "description", "user_count", "image", "user_rsvp", "guild_scheduled_event_exceptions"] { fields[key] = nil }
        for key in ["privacy_level", "status", "entity_type"] { fields[key] = .number(try JSONNumber(rawValue: "999")) }
        fields["entity_metadata"] = .null; fields["recurrence_rule"] = .null
        let model = try GuildScheduledEvent(data: JSONValue.object(fields).serialized())
        #expect(model.creatorID == .absent)
        #expect(model.creator == .absent)
        #expect(model.eventDescription == .absent)
        #expect(model.userCount == .absent)
        #expect(model.image == .absent)
        #expect(model.userRSVP == .absent)
        #expect(model.exceptions == .absent)
        #expect(model.status.knownValue == nil)
        #expect(model.entityType.rawValue == 999)
        #expect(model.privacyLevel.rawValue == 999)
        #expect(model.entityMetadata == .null)
        #expect(model.recurrenceRule == .null)
        let weekday = try ScheduledEventNWeekday(data: Data(#"{"n":999,"day":999}"#.utf8))
        #expect(weekday.n == 999 && weekday.day.knownValue == nil)
        #expect(GuildScheduledEventEntityType.allCases.map(\.rawValue) == [1, 2, 3])
        #expect(ScheduledEventRecurrenceFrequency.allCases.map(\.rawValue) == [0, 1, 2, 3])
        #expect(ScheduledEventWeekday.allCases.map(\.rawValue) == Array(0...6))
        #expect(ScheduledEventMonth.allCases.map(\.rawValue) == Array(1...12))
        #expect(GuildScheduledEventStatus.allCases.map(\.rawValue) == [1, 2, 3, 4])
        #expect(StageInstancePrivacyLevel.allCases.map(\.rawValue) == [1, 2])
        #expect(throws: (any Error).self) { try GuildScheduledEvent(data: Data(ScheduledEventModelFixture.event.utf8), limits: .init(maximumBytes: 10)) }
        #expect(throws: (any Error).self) { try GuildScheduledEvent(data: Data(#"{"id":"1","id":"2"}"#.utf8)) }
    }
}

/// Finite handwritten fixtures independently cover documented nullable responses and preview extras.
enum ScheduledEventModelFixture {
    static let rule = #"{"start":"2030-01-01T00:00:00.000000001Z","end":null,"frequency":2,"interval":2,"by_weekday":[2],"by_n_weekday":null,"by_month":null,"by_month_day":null,"by_year_day":null,"count":null}"#
    static let exception = #"{"event_id":"18446744073709551615","event_exception_id":"18446744073709551615","scheduled_start_time":null,"scheduled_end_time":null,"is_canceled":true}"#
    static let event = #"{"id":"18446744073709551615","guild_id":"18446744073709551615","channel_id":null,"creator_id":null,"name":"private-event","description":"private-description","scheduled_start_time":"2030-01-01T00:00:00.000000001Z","scheduled_end_time":"2030-01-01T01:00:00Z","privacy_level":2,"status":1,"entity_type":3,"entity_id":null,"entity_metadata":{"location":"private-location"},"creator":{"id":"9","username":"creator","discriminator":"0","avatar":null},"user_count":3,"image":null,"recurrence_rule":\#(rule),"user_rsvp":{"guild_scheduled_event_id":"18446744073709551615","user_id":"9","response":1,"guild_scheduled_event_exception_id":null},"guild_scheduled_event_exceptions":[\#(exception)],"future":1.2300e+100}"#
    static let user = #"{"guild_scheduled_event_id":"18446744073709551615","user":{"id":"9","username":"subscriber","discriminator":"0","avatar":null},"member":{"roles":[],"joined_at":null,"deaf":false,"mute":false,"flags":0}}"#
    static let stage = #"{"id":"18446744073709551615","guild_id":"18446744073709551615","channel_id":"18446744073709551615","topic":"private-topic","privacy_level":1,"discoverable_disabled":true,"guild_scheduled_event_id":"18446744073709551615"}"#
}
