// File: Tests/DiscordModelsTests/VoiceStateTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import Foundation
import Testing
@testable import DiscordModels

/// Complete voice-state schema and outgoing Stage edits, using bounded independent JSON fixtures.
@Suite struct VoiceStateTests {
    /// Full unsigned identifiers, nested guest members, optional stream status and exact timestamps survive decoding.
    /// Unknown numeric lexemes and private session values remain available only through explicit access.
    /// - Throws: Unexpected fixture parsing/projection failures fail the test.
    @Test func completeProjectionAndDiagnostics() throws {
        let value = try JSONValue.parse(Self.populated)
        let model = try VoiceState(data: Data(Self.populated.utf8))
        let projected = try VoiceState(value: value, limits: .default)
        #expect(model == projected)
        #expect(model.guildID == .value(.init(rawValue: UInt64.max)))
        #expect(model.channelID == .value(.init(rawValue: UInt64.max)))
        #expect(model.userID.rawValue == UInt64.max)
        #expect(model.sessionID == "private-session")
        #expect(model.deaf && !model.mute && model.selfDeaf && !model.selfMute)
        #expect(model.selfStream == .value(true))
        #expect(model.selfVideo && model.suppress)
        #expect(model.requestToSpeakTimestamp == .value(try DiscordTimestamp(rawValue: "2026-10-16T12:34:56.123456789+00:00")))
        guard case .value(let member) = model.member else { Issue.record("Expected member"); return }
        #expect(member.joinedAt == .null)
        #expect(member.roles.map(\.rawValue) == [UInt64.max])
        #expect(model.jsonValue() == value)
        #expect(try model.jsonValue().serialized() == value.serialized())
        #expect(!model.description.contains("private-"))
        #expect(!model.debugDescription.contains("private-"))
        #expect(!String(reflecting: model).contains("private-"))
        #expect(Mirror(reflecting: model).children.count == 1)
        let minimal = try VoiceState(data: Data(Self.minimal.utf8))
        #expect(minimal.guildID == .absent && minimal.member == .absent && minimal.selfStream == .absent)
        #expect(minimal.channelID == .null && minimal.requestToSpeakTimestamp == .null)
        #expect(!minimal.deaf && !minimal.mute && !minimal.selfDeaf && !minimal.selfMute)
        #expect(!minimal.selfVideo && !minimal.suppress)
    }

    /// Every written field enforces its documented presence, nullable contract and type, including nested member failures.
    /// - Throws: Unexpected valid-fixture serialization failures fail the test; exact sanitized schema errors are asserted.
    @Test func requiredOptionalNullableAndMalformedFields() throws {
        guard case .object(let original) = try JSONValue.parse(Self.populated) else { Issue.record("Root"); return }
        let optional: Set<String> = ["guild_id", "member", "self_stream"]
        let nullable: Set<String> = ["channel_id", "request_to_speak_timestamp"]
        let invalid: [String: [String]] = [
            "guild_id": ["true", "1", #""18446744073709551616""#, #""invalid""#],
            "channel_id": ["false", "1", #""18446744073709551616""#],
            "user_id": ["true", "1", #""18446744073709551616""#],
            "member": ["[]", "false", "{}", #"{"roles":[],"joined_at":null,"deaf":false,"mute":false,"flags":true}"#],
            "session_id": ["false", "1", "{}"],
            "deaf": ["0", #""false""#, "{}"], "mute": ["0", #""false""#],
            "self_deaf": ["0", #""false""#], "self_mute": ["0", #""false""#],
            "self_stream": ["0", #""false""#], "self_video": ["0", #""false""#],
            "suppress": ["0", #""false""#],
            "request_to_speak_timestamp": ["true", "1", #""2026-02-30T00:00:00Z""#, #""bad""#]
        ]
        #expect(invalid.count == 13)
        for (name, failures) in invalid {
            var missing = original
            missing[name] = nil
            if optional.contains(name) {
                #expect(try VoiceState(value: .object(missing), limits: .default).rawFields[name] == nil)
            } else {
                #expect(throws: DiscordError.transport(.invalidResponse)) {
                    try VoiceState(data: JSONValue.object(missing).serialized())
                }
            }
            var null = original
            null[name] = .null
            if nullable.contains(name) {
                #expect(try VoiceState(value: .object(null), limits: .default).rawFields[name] == .null)
            } else {
                #expect(throws: DiscordError.transport(.invalidResponse)) { try VoiceState(value: .object(null), limits: .default) }
            }
            for failure in failures {
                var malformed = original
                malformed[name] = try JSONValue.parse(failure)
                #expect(throws: DiscordError.transport(.invalidResponse)) {
                    try VoiceState(data: JSONValue.object(malformed).serialized())
                }
                #expect(throws: DiscordError.transport(.invalidResponse)) {
                    try VoiceState(value: .object(malformed), limits: .default)
                }
            }
        }
    }

    /// Complete-document JSON bounds include unknown nested content; malformed roots, duplicate keys and syntax fail.
    /// - Throws: Unexpected fixture setup errors fail the test; expected parser/schema failures are asserted.
    @Test func parserBoundsAndInvalidRoots() throws {
        let bytes = Data(Self.populated.utf8)
        #expect(throws: JSONValueError.maximumBytesExceeded) { try VoiceState(data: bytes, limits: .init(maximumBytes: 1)) }
        #expect(throws: JSONValueError.maximumDepthExceeded) { try VoiceState(data: bytes, limits: .init(maximumDepth: 1)) }
        #expect(throws: JSONValueError.maximumNodesExceeded) { try VoiceState(data: bytes, limits: .init(maximumNodes: 1)) }
        for source in ["{", "{}{}", #"{"user_id":"1","user_id":"2"}"#] {
            #expect(throws: JSONValueError.self) { try VoiceState(data: Data(source.utf8)) }
        }
        for source in ["[]", "null", "false", "1", #""private-root""#] {
            #expect(throws: DiscordError.transport(.invalidResponse)) { try VoiceState(data: Data(source.utf8)) }
        }
        let region = try VoiceRegion(data: Data(#"{"id":"private-region","name":"Private","optimal":true,"deprecated":false,"custom":true}"#.utf8))
        #expect(region.id == "private-region" && region.optimal && !region.deprecated && region.custom)
    }

    /// Every combination of absent/null/value inputs preserves exact writable fields and rejects unsupported nulls.
    /// Timestamp clearing and exact spelling are current-user-only; empty bodies stay empty and diagnostics redact them.
    /// - Throws: Unexpected valid construction/timestamp errors fail the test; forbidden-null failures are asserted.
    @Test func outgoingEditsPresenceAndRedaction() throws {
        let channels: [Field<ChannelID>] = [.absent, .null, .value(.init(rawValue: UInt64.max))]
        let suppressions: [Field<Bool>] = [.absent, .null, .value(false), .value(true)]
        let timestamp = try DiscordTimestamp(rawValue: "2026-10-16T12:34:56.123456789+00:00")
        let timestamps: [Field<DiscordTimestamp>] = [.absent, .null, .value(timestamp)]
        for channel in channels {
            for suppression in suppressions {
                if channel == .null || suppression == .null {
                    #expect(throws: DiscordError.validation(.invalidValue)) {
                        try UserVoiceStateModify(channelID: channel, suppress: suppression)
                    }
                    for time in timestamps {
                        #expect(throws: DiscordError.validation(.invalidValue)) {
                            try CurrentUserVoiceStateModify(channelID: channel, suppress: suppression, requestToSpeakTimestamp: time)
                        }
                    }
                    continue
                }
                var expected: [String: JSONValue] = [:]
                if case .value(let channel) = channel { expected["channel_id"] = .string(channel.description) }
                if case .value(let suppression) = suppression { expected["suppress"] = .bool(suppression) }
                let other = try UserVoiceStateModify(channelID: channel, suppress: suppression)
                #expect(other.jsonValue() == .object(expected))
                #expect(!other.description.contains("184467"))
                #expect(other.customMirror.children.count == 1)
                for time in timestamps {
                    var currentExpected = expected
                    switch time {
                    case .absent: break
                    case .null: currentExpected["request_to_speak_timestamp"] = .null
                    case .value(let time): currentExpected["request_to_speak_timestamp"] = .string(time.rawValue)
                    }
                    let current = try CurrentUserVoiceStateModify(channelID: channel, suppress: suppression, requestToSpeakTimestamp: time)
                    #expect(current.jsonValue() == .object(currentExpected))
                    #expect(!current.description.contains("2026-"))
                    #expect(!current.debugDescription.contains("184467"))
                    #expect(Mirror(reflecting: current).children.count == 1)
                }
            }
        }
        #expect(try CurrentUserVoiceStateModify().jsonValue() == .object([:]))
        #expect(try UserVoiceStateModify().jsonValue() == .object([:]))
    }

    /// Complete written voice state with optional fields omitted and both nullable fields explicitly cleared.
    static let minimal = #"{"channel_id":null,"user_id":"1","session_id":"","deaf":false,"mute":false,"self_deaf":false,"self_mute":false,"self_video":false,"suppress":false,"request_to_speak_timestamp":null}"#
    /// Populated snapshot with maximum snowflakes, guest member, high-precision timestamp and exact future JSON.
    static let populated = #"{"guild_id":"18446744073709551615","channel_id":"18446744073709551615","user_id":"18446744073709551615","member":{"roles":["18446744073709551615"],"joined_at":null,"deaf":false,"mute":true,"flags":16},"session_id":"private-session","deaf":true,"mute":false,"self_deaf":true,"self_mute":false,"self_stream":true,"self_video":true,"suppress":true,"request_to_speak_timestamp":"2026-10-16T12:34:56.123456789+00:00","future_private":{"exact":1.234567890123456789e1000}}"#
}
