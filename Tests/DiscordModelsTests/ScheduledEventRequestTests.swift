// File: Tests/DiscordModelsTests/ScheduledEventRequestTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import Foundation
import Testing
@testable import DiscordModels

/// Validates every event/stage request field, hosting dependency and current recurrence/status restriction.
@Suite struct ScheduledEventRequestTests {
    /// Both channel kinds and external events encode exact required fields, selected nullable extras and Unicode names.
    /// - Throws: Unexpected request/serialization errors fail the test.
    @Test func creationAndStageBodies() throws {
        let start = try DiscordTimestamp(rawValue: "2030-01-01T00:00:00.000000001Z")
        let end = try DiscordTimestamp(rawValue: "2030-01-01T00:00:00.000000002Z")
        for kind in [GuildScheduledEventEntityType.stageInstance, .voice] {
            let request = try GuildScheduledEventCreate(name: "a", entityType: kind, scheduledStartTime: start,
                channelID: .init(rawValue: .max), scheduledEndTime: end, description: .null, image: .null, recurrenceRule: .null)
            guard case .object(let fields) = request.jsonValue() else { Issue.record("Expected object"); return }
            #expect(fields["channel_id"] == .string("18446744073709551615"))
            #expect(fields["entity_metadata"] == nil)
            #expect(fields["entity_type"] == .number(try JSONNumber(rawValue: String(kind.rawValue))))
            #expect(fields["description"] == .null && fields["image"] == .null && fields["recurrence_rule"] == .null)
            #expect(fields["scheduled_start_time"] == .string(start.rawValue))
            #expect(fields["scheduled_end_time"] == .string(end.rawValue))
        }
        let rule = try ScheduledEventRecurrenceRequest(start: start, frequency: .weekly, byWeekday: [.monday])
        let external = try GuildScheduledEventCreate(name: String(repeating: "🐶", count: 100), entityType: .external,
            scheduledStartTime: start, location: "there", scheduledEndTime: end, description: .value("description"),
            image: .value("data:image/png;base64,AQ=="), recurrenceRule: .value(rule))
        guard case .object(let fields) = external.jsonValue() else { Issue.record("Expected object"); return }
        #expect(fields["channel_id"] == .null)
        #expect(fields["entity_metadata"] == .object(["location": .string("there")]))
        #expect(fields["privacy_level"] == .number(try JSONNumber(rawValue: "2")))
        #expect(fields["recurrence_rule"] == rule.jsonValue())
        #expect(!String(reflecting: external).contains("there"))
        let stage = try StageInstanceCreate(channelID: .init(rawValue: .max), topic: "topic", privacyLevel: .value(.guildOnly),
            sendStartNotification: .value(true), guildScheduledEventID: .value(.init(rawValue: .max)))
        #expect(stage.channelID.rawValue == .max)
        #expect(stage.jsonValue() == .object(["channel_id": .string("18446744073709551615"), "topic": .string("topic"),
            "privacy_level": .number(try JSONNumber(rawValue: "2")), "send_start_notification": .bool(true),
            "guild_scheduled_event_id": .string("18446744073709551615")]))
        #expect(try StageInstanceCreate(channelID: .init(rawValue: 1), topic: "t").jsonValue() == .object(["channel_id": .string("1"), "topic": .string("t")]))
        #expect(try StageInstanceModify().jsonValue() == .object([:]))
        #expect(try StageInstanceModify(topic: .value("new"), privacyLevel: .value(.guildOnly)).jsonValue() == .object(["topic": .string("new"), "privacy_level": .number(try JSONNumber(rawValue: "2"))]))
    }

    /// Creation rejects missing hosting companions, impossible times, invalid names/descriptions and bounded image violations.
    /// - Throws: Unexpected fixture setup errors fail the test; validation errors are explicitly asserted.
    @Test func invalidCreation() throws {
        let start = try DiscordTimestamp(rawValue: "2030-01-01T00:00:00Z")
        for kind in GuildScheduledEventEntityType.allCases {
            #expect(throws: DiscordError.validation(.invalidValue)) { try GuildScheduledEventCreate(name: "x", entityType: kind, scheduledStartTime: start) }
        }
        for name in ["", String(repeating: "x", count: 101)] {
            #expect(throws: DiscordError.validation(.invalidValue)) { try GuildScheduledEventCreate(name: name, entityType: .voice, scheduledStartTime: start, channelID: .init(rawValue: 1)) }
        }
        for description in ["", String(repeating: "x", count: 1001)] {
            #expect(throws: DiscordError.validation(.invalidValue)) { try GuildScheduledEventCreate(name: "x", entityType: .voice, scheduledStartTime: start, channelID: .init(rawValue: 1), description: .value(description)) }
        }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildScheduledEventCreate(name: "x", entityType: .voice, scheduledStartTime: start, channelID: .init(rawValue: 1), location: "wrong") }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildScheduledEventCreate(name: "x", entityType: .external, scheduledStartTime: start, channelID: .init(rawValue: 1), location: "place", scheduledEndTime: start) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildScheduledEventCreate(name: "x", entityType: .voice, scheduledStartTime: start, channelID: .init(rawValue: 1), scheduledEndTime: start) }
        for image in ["AQ==", "data:text/plain;base64,AQ==", "data:image/png;base64,", "data:image/png;base64,AR=="] {
            #expect(throws: DiscordError.validation(.invalidValue)) { try GuildScheduledEventCreate(name: "x", entityType: .voice, scheduledStartTime: start, channelID: .init(rawValue: 1), image: .value(image)) }
        }
        #expect(throws: DiscordError.validation(.limitExceeded)) {
            try GuildScheduledEventCreate(name: "x", entityType: .voice, scheduledStartTime: start, channelID: .init(rawValue: 1), image: .value("data:image/png;base64," + Data(repeating: 1, count: 1_048_577).base64EncodedString()))
        }
        for topic in ["", String(repeating: "x", count: 121)] {
            #expect(throws: DiscordError.validation(.invalidValue)) { try StageInstanceCreate(channelID: .init(rawValue: 1), topic: topic) }
            #expect(throws: DiscordError.validation(.invalidValue)) { try StageInstanceModify(topic: .value(topic)) }
        }
        for level in [Field<StageInstancePrivacyLevel>.null, .value(.public)] {
            #expect(throws: DiscordError.validation(.invalidValue)) { try StageInstanceCreate(channelID: .init(rawValue: 1), topic: "t", privacyLevel: level) }
            #expect(throws: DiscordError.validation(.invalidValue)) { try StageInstanceModify(privacyLevel: level) }
        }
        #expect(throws: DiscordError.validation(.invalidValue)) { try StageInstanceCreate(channelID: .init(rawValue: 1), topic: "t", sendStartNotification: .null) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try StageInstanceCreate(channelID: .init(rawValue: 1), topic: "t", guildScheduledEventID: .null) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try StageInstanceModify(topic: .null) }
    }

    /// PATCH preserves selected fields and rejects missing conversion companions and invalid status edges.
    /// - Throws: Unexpected fixture/request errors fail the test.
    @Test func modifications() throws {
        let start = try DiscordTimestamp(rawValue: "2030-01-01T00:00:00Z"), end = try DiscordTimestamp(rawValue: "2030-01-01T01:00:00Z")
        #expect(try GuildScheduledEventModify(currentEntityType: .voice).jsonValue() == .object([:]))
        let edit = try GuildScheduledEventModify(currentEntityType: .voice, currentStatus: .scheduled, name: .value("new"),
            privacyLevel: .value(.guildOnly), channelID: .null, location: .value("there"), scheduledStartTime: .value(start),
            scheduledEndTime: .value(end), description: .null, entityType: .value(.external), status: .value(.active), image: .null, recurrenceRule: .null)
        guard case .object(let fields) = edit.jsonValue() else { Issue.record("Expected object"); return }
        #expect(fields.count == 11)
        #expect(fields["entity_metadata"] == .object(["location": .string("there")]))
        #expect(fields["description"] == .null && fields["recurrence_rule"] == .null)
        #expect(edit.currentEntityType == .voice && edit.currentStatus == .scheduled)
        #expect(try GuildScheduledEventModify(currentEntityType: .external, channelID: .value(.init(rawValue: 3)), location: .null,
            scheduledEndTime: .null, entityType: .value(.stageInstance)).jsonValue() != .object([:]))
        for kind in GuildScheduledEventEntityType.allCases {
            #expect(throws: DiscordError.validation(.invalidValue)) { try GuildScheduledEventModify(currentEntityType: kind, name: .null) }
            #expect(throws: DiscordError.validation(.invalidValue)) { try GuildScheduledEventModify(currentEntityType: kind, privacyLevel: .null) }
            #expect(throws: DiscordError.validation(.invalidValue)) { try GuildScheduledEventModify(currentEntityType: kind, entityType: .null) }
            #expect(throws: DiscordError.validation(.invalidValue)) { try GuildScheduledEventModify(currentEntityType: kind, status: .null) }
            #expect(throws: DiscordError.validation(.invalidValue)) { try GuildScheduledEventModify(currentEntityType: kind, scheduledStartTime: .null) }
            #expect(throws: DiscordError.validation(.invalidValue)) { try GuildScheduledEventModify(currentEntityType: kind, status: .value(.active)) }
        }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildScheduledEventModify(currentEntityType: .voice, location: .value("discarded")) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildScheduledEventModify(currentEntityType: .voice, channelID: .null) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildScheduledEventModify(currentEntityType: .external, scheduledEndTime: .null) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildScheduledEventModify(currentEntityType: .external, location: .null) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildScheduledEventModify(currentEntityType: .external, entityType: .value(.voice)) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildScheduledEventModify(currentEntityType: .voice, channelID: .null, location: .value("there"), entityType: .value(.external)) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildScheduledEventModify(currentEntityType: .voice, scheduledStartTime: .value(end), scheduledEndTime: .value(start)) }
        for from in GuildScheduledEventStatus.allCases {
            for to in GuildScheduledEventStatus.allCases {
                let valid = from == to || (from == .scheduled && [.active, .canceled].contains(to)) || (from == .active && to == .completed)
                if valid { _ = try GuildScheduledEventModify(currentEntityType: .voice, currentStatus: from, status: .value(to)) }
                else { #expect(throws: DiscordError.validation(.invalidValue)) { try GuildScheduledEventModify(currentEntityType: .voice, currentStatus: from, status: .value(to)) } }
            }
        }
    }

    /// Every documented recurrence form encodes correctly and forbidden combinations fail locally.
    /// - Throws: Unexpected timestamp/request errors fail the test; invalid combinations are explicitly rejected.
    @Test func recurrenceRules() throws {
        let start = try DiscordTimestamp(rawValue: "2030-01-01T00:00:00Z")
        let nth = try ScheduledEventNWeekdayRequest(n: 5, day: .wednesday)
        #expect(nth.jsonValue() == .object(["n": .number(try JSONNumber(rawValue: "5")), "day": .number(try JSONNumber(rawValue: "2"))]))
        for n in [Int.min, -1, 0, 6, Int.max] { #expect(throws: DiscordError.validation(.invalidValue)) { try ScheduledEventNWeekdayRequest(n: n, day: .monday) } }
        for days in [[0,1,2,3,4], [1,2,3,4,5], [6,0,1,2,3], [4,5], [5,6], [6,0]] {
            let rule = try ScheduledEventRecurrenceRequest(start: start, frequency: .daily, byWeekday: days.map { ScheduledEventWeekday(rawValue: $0)! })
            guard case .object(let fields) = rule.jsonValue() else { Issue.record("Expected rule"); return }
            #expect(fields["by_weekday"] == .array(try days.map { .number(try JSONNumber(rawValue: String($0))) }))
        }
        _ = try ScheduledEventRecurrenceRequest(start: start, frequency: .weekly, interval: 2, byWeekday: [.wednesday])
        _ = try ScheduledEventRecurrenceRequest(start: start, frequency: .monthly, byNWeekday: [nth])
        for day in [-1, 1, 29] { _ = try ScheduledEventRecurrenceRequest(start: start, frequency: .yearly, byMonth: [.february], byMonthDay: [day]) }
        for frequency in ScheduledEventRecurrenceFrequency.allCases {
            for interval in [0, 3, Int.max] { #expect(throws: DiscordError.validation(.invalidValue)) { try ScheduledEventRecurrenceRequest(start: start, frequency: frequency, interval: interval) } }
            if frequency != .weekly { #expect(throws: DiscordError.validation(.invalidValue)) { try ScheduledEventRecurrenceRequest(start: start, frequency: frequency, interval: 2) } }
        }
        for days in [[], [.monday], [.monday,.monday], [.monday,.wednesday]] as [[ScheduledEventWeekday]] {
            #expect(throws: DiscordError.validation(.invalidValue)) { try ScheduledEventRecurrenceRequest(start: start, frequency: .daily, byWeekday: days) }
        }
        #expect(throws: DiscordError.validation(.invalidValue)) { try ScheduledEventRecurrenceRequest(start: start, frequency: .weekly, byWeekday: [.monday,.tuesday]) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try ScheduledEventRecurrenceRequest(start: start, frequency: .monthly, byWeekday: [.monday]) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try ScheduledEventRecurrenceRequest(start: start, frequency: .weekly, byNWeekday: [nth]) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try ScheduledEventRecurrenceRequest(start: start, frequency: .monthly, byNWeekday: []) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try ScheduledEventRecurrenceRequest(start: start, frequency: .weekly, byWeekday: [.monday], byNWeekday: [nth]) }
        for days in [[0], [30], [1,2], []] as [[Int]] {
            #expect(throws: DiscordError.validation(.invalidValue)) { try ScheduledEventRecurrenceRequest(start: start, frequency: .yearly, byMonth: [.february], byMonthDay: days) }
        }
        #expect(throws: DiscordError.validation(.invalidValue)) { try ScheduledEventRecurrenceRequest(start: start, frequency: .yearly, byMonth: [.july]) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try ScheduledEventRecurrenceRequest(start: start, frequency: .monthly, byMonth: [.july], byMonthDay: [24]) }
    }
}
