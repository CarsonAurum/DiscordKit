// File: Tests/DiscordModelsTests/GatewayDispatchTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import Foundation
import Testing
@testable import DiscordModels

/// Exercises the complete named Gateway catalog with credential-free, bounded local fixtures.
/// Resource seeds use existing independently authored examples; Gateway extras cover every reviewed field.
@Suite struct GatewayDispatchTests {
    /// Decodes every documented dispatch, preserving full-width IDs, future field numbers and exact event identity.
    /// - Parameter name: Every current case-sensitive Gateway v10 dispatch name.
    @Test(arguments: GatewayDispatchName.allCases)
    func allDispatchFixtures(name: GatewayDispatchName) throws {
        let source = try #require(GatewayCatalogFixture.dispatchSources[name])
        guard case .object(var fields) = try JSONValue.parse(Data(source.utf8)) else {
            Issue.record("Dispatch fixture must be an object")
            return
        }
        fields["future_private"] = .number(try JSONNumber(rawValue: "1.23000000000000000001e1000"))
        let tree = JSONValue.object(fields)
        let data = try tree.serialized()
        let dispatch = try GatewayDispatch(name: name.rawValue, data: data)
        let projected = try GatewayDispatch(name: name.rawValue, value: tree)
        #expect(dispatch.name == name.rawValue)
        #expect(projected.name == name.rawValue)
        #expect(dispatch.jsonValue() == tree)
        #expect(projected.jsonValue() == tree)
        if case .unknown = dispatch { Issue.record("Current documented dispatch unexpectedly used unknown fallback") }
        #expect(dispatch.description == "GatewayDispatch(redacted)")
        #expect(dispatch.debugDescription == dispatch.description)
        #expect(dispatch.customMirror.children.count == 1)
        #expect(throws: DiscordError.transport(.invalidResponse)) {
            try GatewayDispatch(name: name.rawValue, data: Data("[]".utf8))
        }
    }

    /// Decodes the catalog on cooperative child-task stacks and bounds the enum's inline storage.
    /// This guards the regression where a large unboxed union overflowed async worker stacks before decoding.
    @Test func asyncDispatchDecodingUsesBoundedStorage() async throws {
        #expect(MemoryLayout<GatewayDispatch>.size <= 32)
        let total = try await withThrowingTaskGroup(of: Int.self) { group in
            for _ in 0..<4 {
                group.addTask {
                    var count = 0
                    for name in GatewayDispatchName.allCases {
                        let source = try #require(GatewayCatalogFixture.dispatchSources[name])
                        let dispatch = try GatewayDispatch(name: name.rawValue, data: Data(source.utf8))
                        #expect(dispatch.name == name.rawValue)
                        count += 1
                    }
                    return count
                }
            }
            var count = 0
            for try await subtotal in group { count += subtotal }
            return count
        }
        #expect(total == 4 * GatewayDispatchName.allCases.count)
    }

    /// Checks required/optional and nullable/nonnullable contracts for every Gateway-owned payload field.
    /// - Parameter fixture: Full payload, independent field matrix and both public and subtree constructors.
    @Test(arguments: GatewayCatalogFixture.payloads)
    func malformedDispatchFields(fixture: GatewayCatalogFixture) throws {
        guard case .object(var fields) = try JSONValue.parse(Data(fixture.source.utf8)) else {
            Issue.record("Payload fixture must be an object")
            return
        }
        fields["future_private"] = .number(try JSONNumber(rawValue: "1.23000000000000000001e1000"))
        let bytes = try JSONValue.object(fields).serialized()
        let payload = try fixture.parse(bytes, .default)
        let projected = try fixture.project(.object(fields), .default)
        #expect(payload.rawFields == fields)
        #expect(projected.rawFields == fields)
        #expect(payload.jsonValue() == .object(fields))
        #expect(payload.description.hasSuffix("(redacted)"))
        #expect(payload.debugDescription == payload.description)
        #expect(payload.customMirror.children.count == 1)
        for field in fixture.fields {
            var changed = fields
            changed.removeValue(forKey: field.name)
            if field.optional {
                #expect(try fixture.parse(JSONValue.object(changed).serialized(), .default).rawFields[field.name] == nil)
            } else {
                #expect(throws: DiscordError.transport(.invalidResponse)) {
                    try fixture.parse(JSONValue.object(changed).serialized(), .default)
                }
            }
            changed = fields
            changed[field.name] = .null
            if field.nullable {
                #expect(try fixture.parse(JSONValue.object(changed).serialized(), .default).rawFields[field.name] == .null)
            } else {
                #expect(throws: DiscordError.transport(.invalidResponse)) {
                    try fixture.parse(JSONValue.object(changed).serialized(), .default)
                }
            }
            changed[field.name] = field.array ? .bool(false) : .array([])
            #expect(throws: DiscordError.transport(.invalidResponse)) {
                try fixture.parse(JSONValue.object(changed).serialized(), .default)
            }
        }
        #expect(throws: JSONValueError.maximumBytesExceeded) {
            try fixture.parse(bytes, JSONLimits(maximumBytes: 1))
        }
        #expect(throws: JSONValueError.maximumNodesExceeded) {
            try fixture.parse(bytes, JSONLimits(maximumNodes: 1))
        }
        #expect(throws: DiscordError.transport(.invalidResponse)) { try fixture.parse(Data("null".utf8), .default) }
        #expect(throws: JSONValueError.self) { try fixture.parse(Data("{".utf8), .default) }
    }

    /// Verifies forward names/scalar data and enforces the same bounds on prebuilt trees as on byte input.
    @Test func unknownDispatchAndBounds() throws {
        let source = Data(#"{"private-token":"concealed","number":1.234567890123456789e999}"#.utf8)
        let tree = try JSONValue.parse(source)
        let dispatch = try GatewayDispatch(name: "FUTURE_PRIVATE_EVENT", data: source)
        guard case .unknown(let name, let value) = dispatch else { Issue.record("Unknown event lost"); return }
        #expect(name == "FUTURE_PRIVATE_EVENT")
        #expect(value == tree)
        #expect(dispatch.jsonValue() == tree)
        #expect(!dispatch.description.contains("PRIVATE"))
        for raw in ["null", "false", "[]", "1e999", #""future""#] {
            let data = Data(raw.utf8)
            #expect(try GatewayDispatch(name: "ready", data: data).jsonValue() == JSONValue.parse(data))
        }
        #expect(throws: JSONValueError.maximumBytesExceeded) {
            try GatewayDispatch(name: "FUTURE", value: tree, limits: JSONLimits(maximumBytes: 1))
        }
        #expect(throws: JSONValueError.maximumNodesExceeded) {
            try GatewayDispatch(name: "FUTURE", value: tree, limits: JSONLimits(maximumNodes: 1))
        }
        let nested = JSONValue.array([.array([.null])])
        #expect(throws: JSONValueError.maximumDepthExceeded) {
            try GatewayDispatch(name: "FUTURE", value: nested, limits: JSONLimits(maximumDepth: 1))
        }
        #expect(throws: JSONValueError.invalidLimits) {
            try GatewayDispatch(name: "FUTURE", value: .null, limits: JSONLimits(maximumBytes: 0))
        }
        #expect(throws: JSONValueError.self) {
            try GatewayDispatch(name: "FUTURE", data: Data(#"{"same":1,"same":2}"#.utf8))
        }
        #expect(GatewayDispatchName.allCases.count == 79)
        #expect(Set(GatewayDispatchName.allCases.map(\.rawValue)).count == 79)
    }

    /// Checks sparse updates, explicit clearing and unvalidated presence-user fields without synthesizing old state.
    @Test func presenceAndSparseUpdates() throws {
        let empty = try GatewayMessageUpdate(data: Data(#"{"id":"18446744073709551615","channel_id":"2"}"#.utf8))
        #expect(empty.id.rawValue == UInt64.max)
        #expect(empty.content == .absent)
        #expect(empty.editedTimestamp == .absent)
        #expect(empty.referencedMessage == .absent)
        #expect(empty.member == .absent)
        let clearing = try GatewayMessageUpdate(data: Data(#"{"id":"1","channel_id":"2","content":"","edited_timestamp":null,"referenced_message":null,"nonce":18446744073709551615000,"member":{"joined_at":null,"roles":[]}}"#.utf8))
        #expect(clearing.content == .value(""))
        #expect(clearing.editedTimestamp == .null)
        #expect(clearing.referencedMessage == .null)
        #expect(clearing.nonce == .value(.integer(try JSONNumber(rawValue: "18446744073709551615000"))))
        if case .value(let member) = clearing.member {
            #expect(member.joinedAt == .null)
            #expect(member.roles == .value([]))
            #expect(member.deaf == .absent)
        } else { Issue.record("Sparse member missing") }
        let user = try GatewayPresenceUser(data: Data(#"{"id":"18446744073709551615","username":false,"avatar":[1,null],"global_name":123.000}"#.utf8))
        #expect(user.id.rawValue == UInt64.max)
        #expect(user.rawFields["username"] == .bool(false))
        let partial = try GatewayPartialPresence(data: Data(#"{"user":{"id":"1"}}"#.utf8))
        #expect(partial.guildID == .absent)
        #expect(partial.activities == .absent)
        #expect(partial.status == .absent)
        let info = try GatewayChannelInfoChannel(data: Data(#"{"id":"1","status":null,"voice_start_time":null}"#.utf8))
        #expect(info.status == .null)
        #expect(info.voiceStartTime == .null)
        let absentInfo = try GatewayChannelInfoChannel(data: Data(#"{"id":"1"}"#.utf8))
        #expect(absentInfo.status == .absent)
        #expect(absentInfo.voiceStartTime == .absent)
        let voice = try GatewayVoiceServerUpdate(data: Data(#"{"token":"private-token","guild_id":"1","endpoint":null}"#.utf8))
        #expect(voice.endpoint == .null)
        #expect(!voice.description.contains("private-token"))
    }

    /// Separates guild outage markers, member removal, and available GUILD_CREATE resource payloads.
    @Test func guildAvailability() throws {
        let unavailableData = Data(#"{"id":"18446744073709551615","unavailable":true,"future":123.000}"#.utf8)
        let create = try GatewayGuildCreate(data: unavailableData)
        guard case .unavailable(let outage) = create else { Issue.record("Outage interpreted as full Guild"); return }
        #expect(outage.id.rawValue == UInt64.max)
        #expect(outage.unavailable == .value(true))
        #expect(create.jsonValue() == (try JSONValue.parse(unavailableData)))
        #expect(create.description == "GatewayGuildCreate(redacted)")
        #expect(create.debugDescription == create.description)
        #expect(create.customMirror.children.count == 1)
        let removal = try GatewayGuildAvailability(data: Data(#"{"id":"1"}"#.utf8))
        #expect(removal.unavailable == .absent)
        let availableSource = try #require(GatewayCatalogFixture.dispatchSources[.guildCreate])
        let available = try GatewayGuildCreate(data: Data(availableSource.utf8))
        guard case .available(let guild) = available else { Issue.record("Available Guild lost"); return }
        #expect(guild.guild.id.rawValue == UInt64.max)
        #expect(guild.members.count == 1)
        #expect(guild.voiceStates.count == 1)
        #expect(available.jsonValue() == (try JSONValue.parse(Data(availableSource.utf8))))
        for invalid in [#"{"id":"1","unavailable":null}"#, #"{"id":"1","unavailable":false}"#, #"{"id":"1"}"#] {
            #expect(throws: DiscordError.transport(.invalidResponse)) {
                try GatewayGuildCreate(data: Data(invalid.utf8))
            }
        }
    }

    /// Exercises finite floating point limits, exact integral default sound IDs and unknown enum variants.
    @Test func voiceEffectsRateLimitsAndActivities() throws {
        for sound in [#""18446744073709551615""#, "18446744073709551615", "0"] {
            let effect = try GatewayVoiceChannelEffect(data: Data("{\"channel_id\":\"1\",\"guild_id\":\"2\",\"user_id\":\"3\",\"sound_id\":\(sound),\"sound_volume\":0.2500,\"animation_type\":999}".utf8))
            #expect(effect.soundVolume == .value(0.25))
            if case .value(let animation) = effect.animationType {
                #expect(animation.rawValue == 999)
                #expect(animation.knownValue == nil)
            } else { Issue.record("Unknown animation lost") }
        }
        for sound in ["-1", "1.0", "1e0", "18446744073709551616", #""-1""#, "null", "true"] {
            #expect(throws: DiscordError.transport(.invalidResponse)) {
                try GatewayVoiceChannelEffect(data: Data("{\"channel_id\":\"1\",\"guild_id\":\"2\",\"user_id\":\"3\",\"sound_id\":\(sound)}".utf8))
            }
        }
        for volume in ["-0.1", "1.1", "1e999", #""1""#] {
            #expect(throws: DiscordError.transport(.invalidResponse)) {
                try GatewayVoiceChannelEffect(data: Data("{\"channel_id\":\"1\",\"guild_id\":\"2\",\"user_id\":\"3\",\"sound_volume\":\(volume)}".utf8))
            }
        }
        for volume in ["0", "1", "0.5", "1e-2"] {
            let effect = try GatewayVoiceChannelEffect(data: Data("{\"channel_id\":\"1\",\"guild_id\":\"2\",\"user_id\":\"3\",\"sound_volume\":\(volume)}".utf8))
            if case .value(let number) = effect.soundVolume { #expect((0...1).contains(number)) }
            else { Issue.record("Valid volume missing") }
        }
        let limited = try GatewayRateLimited(data: Data(#"{"opcode":8,"retry_after":1.2500,"meta":{"guild_id":"18446744073709551615","nonce":"private-nonce"}}"#.utf8))
        #expect(limited.retryAfter == 1.25)
        #expect(limited.memberMetadata?.guildID.rawValue == UInt64.max)
        #expect(limited.memberMetadata?.nonce == .value("private-nonce"))
        let future = try GatewayRateLimited(data: Data(#"{"opcode":999,"retry_after":0,"meta":[1.2500]}"#.utf8))
        #expect(future.memberMetadata == nil)
        #expect(future.metadata == .array([.number(try JSONNumber(rawValue: "1.2500"))]))
        for raw in [#"{"opcode":8,"retry_after":-1,"meta":{"guild_id":"1"}}"#, #"{"opcode":8,"retry_after":1e999,"meta":{"guild_id":"1"}}"#, #"{"opcode":8,"retry_after":0}"#, #"{"opcode":8,"retry_after":0,"meta":null}"#] {
            #expect(throws: DiscordError.transport(.invalidResponse)) { try GatewayRateLimited(data: Data(raw.utf8)) }
        }
        let activity = try GatewayReceivedActivity(data: Data(#"{"name":"private","type":999,"created_at":1844674407370955161,"status_display_type":999,"buttons":["Label"],"secrets":{"join":"private-join"},"flags":18446744073709551615}"#.utf8))
        #expect(activity.type.rawValue == 999)
        #expect(activity.type.knownValue == nil)
        #expect(activity.statusDisplayType == .value(RawValue(rawValue: 999)))
        #expect(activity.buttons == .value(["Label"]))
        #expect(activity.flags == .value(UInt64.max))
        #expect(GatewayReceivedActivityType.allCases.map(\.rawValue) == [0, 1, 2, 3, 4, 5])
        #expect(GatewayActivityStatusDisplayType.allCases.map(\.rawValue) == [0, 1, 2])
        #expect(GatewayReactionType.allCases.map(\.rawValue) == [0, 1])
        #expect(GatewayVoiceEffectAnimationType.allCases.map(\.rawValue) == [0, 1])
    }

    /// Rejects inconsistent shard/chunk pairs and exact-integer tokens that a Foundation array decoder could round.
    @Test func shardChunkAndIntegerBoundaries() throws {
        let source = try #require(GatewayCatalogFixture.dispatchSources[.ready])
        guard case .object(let base) = try JSONValue.parse(Data(source.utf8)) else { return }
        for pair in ["[0]", "[0,0]", "[-1,2]", "[2,2]", "[0,2,3]", "[0.0,2]", "[0,2e0]", "[false,2]", #"["0",2]"#, "[0,9223372036854775808]"] {
            var fields = base
            fields["shard"] = try JSONValue.parse(Data(pair.utf8))
            #expect(throws: DiscordError.transport(.invalidResponse)) { try GatewayReady(data: JSONValue.object(fields).serialized()) }
        }
        var zeroVersion = base
        zeroVersion["v"] = .number(try JSONNumber(rawValue: "0"))
        #expect(throws: DiscordError.transport(.invalidResponse)) {
            try GatewayReady(data: JSONValue.object(zeroVersion).serialized())
        }
        let guildSource = try #require(GatewayCatalogFixture.dispatchSources[.guildCreate])
        guard case .object(var invalidGuild) = try JSONValue.parse(Data(guildSource.utf8)) else { return }
        invalidGuild["member_count"] = .number(try JSONNumber(rawValue: "-1"))
        #expect(throws: DiscordError.transport(.invalidResponse)) {
            try GatewayAvailableGuild(data: JSONValue.object(invalidGuild).serialized())
        }
        for pair in ["[0]", "[1,2,3]", "[1.0,2]", "[1,2e0]"] {
            #expect(throws: DiscordError.transport(.invalidResponse)) { try GatewayActivityParty(data: Data("{\"size\":\(pair)}".utf8)) }
        }
        for pair in [(0,0),(-1,1),(1,1)] {
            #expect(throws: DiscordError.transport(.invalidResponse)) {
                try GatewayGuildMembersChunk(data: Data("{\"guild_id\":\"1\",\"members\":[],\"chunk_index\":\(pair.0),\"chunk_count\":\(pair.1)}".utf8))
            }
        }
        for count in [-1, 51] {
            #expect(throws: DiscordError.transport(.invalidResponse)) {
                try GatewayThreadMembersUpdate(data: Data("{\"id\":\"1\",\"guild_id\":\"2\",\"member_count\":\(count)}".utf8))
            }
        }
        for count in [0,50] {
            let update = try GatewayThreadMembersUpdate(data: Data("{\"id\":\"1\",\"guild_id\":\"2\",\"member_count\":\(count)}".utf8))
            #expect(update.memberCount == count)
        }
        for flags in ["", "-1", "1.0", "text"] {
            #expect(throws: DiscordError.transport(.invalidResponse)) {
                try GatewayReadyApplication(data: Data("{\"id\":\"1\",\"flags\":0,\"flags_new\":\"\(flags)\"}".utf8))
            }
        }
    }
}

/// One independent wire-field contract for systematic omission/null/type mutation tests.
struct GatewayCatalogField: Sendable {
    let name: String
    let optional: Bool
    let nullable: Bool
    let array: Bool
}

/// Credential-free payload fixture with bounded public and already-bounded subtree entry points.
struct GatewayCatalogFixture: Sendable, CustomStringConvertible {
    let name: String
    let source: String
    let fields: [GatewayCatalogField]
    let parse: @Sendable (Data, JSONLimits) throws -> any MessageResponseValue
    let project: @Sendable (JSONValue, JSONLimits) throws -> any MessageResponseValue

    /// Identifies the fixture without reflecting private JSON into parameterized test labels.
    var description: String { name }


    static let sources: [String: String] = [
        "GatewayGuildAvailability": #"{"id":"18446744073709551615","unavailable":false}"#,
        "GatewayReadyApplication": #"{"id":"18446744073709551615","flags":18446744073709551615,"flags_new":"1844674407370955161518446744073709551615"}"#,
        "GatewayReady": #"{"v":10,"user":{"id":"18446744073709551615","username":"private-user","discriminator":"0","global_name":null,"avatar":null},"guilds":[{"id":"18446744073709551615","unavailable":false}],"session_id":"private-session_id","resume_gateway_url":"private-resume_gateway_url","shard":[0,2],"application":{"id":"18446744073709551615","flags":18446744073709551615,"flags_new":"1844674407370955161518446744073709551615"}}"#,
        "GatewayResumed": #"{}"#,
        "GatewayAutoModerationActionExecution": #"{"guild_id":"18446744073709551615","action":{"type":999,"metadata":{}},"rule_id":"18446744073709551615","rule_trigger_type":999,"user_id":"18446744073709551615","channel_id":"18446744073709551615","message_id":"18446744073709551615","alert_system_message_id":"18446744073709551615","content":"private-content","matched_keyword":"private-matched_keyword","matched_content":"private-matched_content"}"#,
        "GatewayChannelInfoChannel": #"{"id":"18446744073709551615","status":"private-status","voice_start_time":1}"#,
        "GatewayChannelInfo": #"{"guild_id":"18446744073709551615","channels":[{"id":"18446744073709551615","status":"private-status","voice_start_time":1}]}"#,
        "GatewayVoiceChannelStatusUpdate": #"{"id":"18446744073709551615","guild_id":"18446744073709551615","status":"private-status"}"#,
        "GatewayVoiceChannelStartTimeUpdate": #"{"id":"18446744073709551615","guild_id":"18446744073709551615","voice_start_time":1}"#,
        "GatewayThreadCreate": #"{"id":"18446744073709551615","type":999,"name":"private-channel","flags":131072,"newly_created":true}"#,
        "GatewayThreadDelete": #"{"id":"18446744073709551615","guild_id":"18446744073709551615","parent_id":"18446744073709551615","type":999}"#,
        "GatewayThreadListSync": #"{"guild_id":"18446744073709551615","channel_ids":["18446744073709551615"],"threads":[{"id":"18446744073709551615","type":999,"name":"private-channel","flags":131072}],"members":[{"id":"18446744073709551615","user_id":"18446744073709551615","join_timestamp":"2026-10-16T12:34:56.123456789Z","flags":0,"member":{}}]}"#,
        "GatewayThreadMemberUpdate": #"{"id":"18446744073709551615","user_id":"18446744073709551615","join_timestamp":"2026-10-16T12:34:56.123456789Z","flags":0,"member":{},"guild_id":"18446744073709551615"}"#,
        "GatewayThreadAddedMember": #"{"id":"18446744073709551615","user_id":"18446744073709551615","join_timestamp":"2026-10-16T12:34:56.123456789Z","flags":0,"member":{},"presence":{"user":{"id":"18446744073709551615","username":{},"avatar":123},"guild_id":"18446744073709551615","status":"private-status","activities":[{"name":"private-name","type":999,"url":"private-url","created_at":1,"timestamps":{"start":1,"end":1},"application_id":"18446744073709551615","status_display_type":999,"details":"private-details","details_url":"private-details_url","state":"private-state","state_url":"private-state_url","emoji":{"name":"private-name","id":"18446744073709551615","animated":true},"party":{"id":"private-id","size":[2,10]},"assets":{"large_image":"private-large_image","large_text":"private-large_text","large_url":"private-large_url","small_image":"private-small_image","small_text":"private-small_text","small_url":"private-small_url","invite_cover_image":"private-invite_cover_image"},"secrets":{"join":"private-join","spectate":"private-spectate","match":"private-match"},"instance":true,"flags":18446744073709551615,"buttons":["private-buttons"]}],"client_status":{"desktop":"private-desktop","mobile":"private-mobile","web":"private-web","vr":"private-vr"}}}"#,
        "GatewayThreadMembersUpdate": #"{"id":"18446744073709551615","guild_id":"18446744073709551615","member_count":1,"added_members":[{"id":"18446744073709551615","user_id":"18446744073709551615","join_timestamp":"2026-10-16T12:34:56.123456789Z","flags":0,"member":{},"presence":{"user":{"id":"18446744073709551615","username":{},"avatar":123},"guild_id":"18446744073709551615","status":"private-status","activities":[{"name":"private-name","type":999,"url":"private-url","created_at":1,"timestamps":{"start":1,"end":1},"application_id":"18446744073709551615","status_display_type":999,"details":"private-details","details_url":"private-details_url","state":"private-state","state_url":"private-state_url","emoji":{"name":"private-name","id":"18446744073709551615","animated":true},"party":{"id":"private-id","size":[2,10]},"assets":{"large_image":"private-large_image","large_text":"private-large_text","large_url":"private-large_url","small_image":"private-small_image","small_text":"private-small_text","small_url":"private-small_url","invite_cover_image":"private-invite_cover_image"},"secrets":{"join":"private-join","spectate":"private-spectate","match":"private-match"},"instance":true,"flags":18446744073709551615,"buttons":["private-buttons"]}],"client_status":{"desktop":"private-desktop","mobile":"private-mobile","web":"private-web","vr":"private-vr"}}}],"removed_member_ids":["18446744073709551615"]}"#,
        "GatewayChannelPinsUpdate": #"{"guild_id":"18446744073709551615","channel_id":"18446744073709551615","last_pin_timestamp":"2026-10-16T12:34:56.123456789Z"}"#,
        "GatewayAvailableGuild": #"{"id":"18446744073709551615","name":"private-name","icon":null,"splash":null,"owner_id":"18446744073709551615","afk_channel_id":null,"afk_timeout":1,"verification_level":999,"default_message_notifications":999,"explicit_content_filter":999,"roles":[],"emojis":[],"features":["FUTURE_VARIANT"],"mfa_level":999,"application_id":null,"system_channel_id":null,"system_channel_flags":9223372036854775809,"rules_channel_id":null,"vanity_url_code":null,"description":null,"banner":null,"premium_tier":999,"preferred_locale":"private-preferred_locale","public_updates_channel_id":null,"nsfw_level":999,"premium_progress_bar_enabled":true,"safety_alerts_channel_id":null,"incidents_data":null,"joined_at":"2026-10-16T12:34:56.123456789Z","large":true,"unavailable":false,"member_count":1,"voice_states":[{"channel_id":"18446744073709551615","user_id":"18446744073709551615","session_id":"private-voice-session","deaf":false,"mute":false,"self_deaf":false,"self_mute":false,"self_video":false,"suppress":false,"request_to_speak_timestamp":null}],"members":[{"user":{"id":"18446744073709551615"},"roles":["18446744073709551615"],"joined_at":null,"deaf":false,"mute":false,"flags":0}],"channels":[{"id":"18446744073709551615","type":999,"name":"private-channel","flags":131072}],"threads":[{"id":"18446744073709551615","type":999,"name":"private-channel","flags":131072}],"presences":[{"user":{"id":"18446744073709551615","username":{},"avatar":123},"guild_id":"18446744073709551615","status":"private-status","activities":[{"name":"private-name","type":999,"url":"private-url","created_at":1,"timestamps":{"start":1,"end":1},"application_id":"18446744073709551615","status_display_type":999,"details":"private-details","details_url":"private-details_url","state":"private-state","state_url":"private-state_url","emoji":{"name":"private-name","id":"18446744073709551615","animated":true},"party":{"id":"private-id","size":[2,10]},"assets":{"large_image":"private-large_image","large_text":"private-large_text","large_url":"private-large_url","small_image":"private-small_image","small_text":"private-small_text","small_url":"private-small_url","invite_cover_image":"private-invite_cover_image"},"secrets":{"join":"private-join","spectate":"private-spectate","match":"private-match"},"instance":true,"flags":18446744073709551615,"buttons":["private-buttons"]}],"client_status":{"desktop":"private-desktop","mobile":"private-mobile","web":"private-web","vr":"private-vr"}}],"stage_instances":[{"id":"18446744073709551615","guild_id":"18446744073709551615","channel_id":"18446744073709551615","topic":"private-stage","privacy_level":999,"discoverable_disabled":true,"guild_scheduled_event_id":null}],"guild_scheduled_events":[{"id":"18446744073709551615","guild_id":"18446744073709551615","channel_id":null,"name":"private-event","scheduled_start_time":"2026-10-16T12:34:56.123456789Z","scheduled_end_time":null,"privacy_level":999,"status":999,"entity_type":999,"entity_id":null,"entity_metadata":null,"recurrence_rule":null}],"soundboard_sounds":[{"name":"private-sound","sound_id":"18446744073709551615","volume":0.25,"emoji_id":null,"emoji_name":"wave","available":true}]}"#,
        "GatewayGuildAuditLogEntryCreate": #"{"id":"18446744073709551615","target_id":null,"user_id":null,"action_type":999,"guild_id":"18446744073709551615"}"#,
        "GatewayGuildUser": #"{"guild_id":"18446744073709551615","user":{"id":"18446744073709551615","username":"private-user","discriminator":"0","global_name":null,"avatar":null}}"#,
        "GatewayGuildEmojisUpdate": #"{"guild_id":"18446744073709551615","emojis":[{"id":"18446744073709551615","name":"private-emoji"}]}"#,
        "GatewayGuildStickersUpdate": #"{"guild_id":"18446744073709551615","stickers":[{"id":"18446744073709551615","name":"private-sticker","description":null,"tags":"wave","type":999,"format_type":999}]}"#,
        "GatewayGuildIntegrationsUpdate": #"{"guild_id":"18446744073709551615"}"#,
        "GatewayGuildMemberAdd": #"{"user":{"id":"18446744073709551615"},"roles":["18446744073709551615"],"joined_at":null,"deaf":false,"mute":false,"flags":0,"guild_id":"18446744073709551615"}"#,
        "GatewayGuildMemberUpdate": #"{"guild_id":"18446744073709551615","roles":["18446744073709551615"],"user":{"id":"18446744073709551615","username":"private-user","discriminator":"0","global_name":null,"avatar":null},"nick":"private-nick","avatar":"private-avatar","banner":"private-banner","joined_at":"2026-10-16T12:34:56.123456789Z","premium_since":"2026-10-16T12:34:56.123456789Z","deaf":true,"mute":true,"pending":true,"communication_disabled_until":"2026-10-16T12:34:56.123456789Z","avatar_decoration_data":{"asset":"private-asset","sku_id":"18446744073709551615"},"collectibles":{"nameplate":null}}"#,
        "GatewayGuildMembersChunk": #"{"guild_id":"18446744073709551615","members":[{"user":{"id":"18446744073709551615"},"roles":["18446744073709551615"],"joined_at":null,"deaf":false,"mute":false,"flags":0}],"chunk_index":0,"chunk_count":1,"not_found":["18446744073709551615"],"presences":[{"user":{"id":"18446744073709551615","username":{},"avatar":123},"guild_id":"18446744073709551615","status":"private-status","activities":[{"name":"private-name","type":999,"url":"private-url","created_at":1,"timestamps":{"start":1,"end":1},"application_id":"18446744073709551615","status_display_type":999,"details":"private-details","details_url":"private-details_url","state":"private-state","state_url":"private-state_url","emoji":{"name":"private-name","id":"18446744073709551615","animated":true},"party":{"id":"private-id","size":[2,10]},"assets":{"large_image":"private-large_image","large_text":"private-large_text","large_url":"private-large_url","small_image":"private-small_image","small_text":"private-small_text","small_url":"private-small_url","invite_cover_image":"private-invite_cover_image"},"secrets":{"join":"private-join","spectate":"private-spectate","match":"private-match"},"instance":true,"flags":18446744073709551615,"buttons":["private-buttons"]}],"client_status":{"desktop":"private-desktop","mobile":"private-mobile","web":"private-web","vr":"private-vr"}}],"nonce":"private-nonce"}"#,
        "GatewayGuildRoleUpdate": #"{"guild_id":"18446744073709551615","role":{"id":"18446744073709551615","name":"private-name","color":1,"colors":{"primary_color":1,"secondary_color":1,"tertiary_color":1},"hoist":true,"position":1,"permissions":"184467440737095516161844674407370955161","managed":true,"mentionable":true,"flags":9223372036854775809}}"#,
        "GatewayGuildRoleDelete": #"{"guild_id":"18446744073709551615","role_id":"18446744073709551615"}"#,
        "GatewayScheduledEventUser": #"{"guild_scheduled_event_id":"18446744073709551615","user_id":"18446744073709551615","guild_id":"18446744073709551615"}"#,
        "GatewayGuildSoundboardSoundDelete": #"{"sound_id":"18446744073709551615","guild_id":"18446744073709551615"}"#,
        "GatewaySoundboardSounds": #"{"soundboard_sounds":[{"name":"private-sound","sound_id":"18446744073709551615","volume":0.25,"emoji_id":null,"emoji_name":"wave","available":true}],"guild_id":"18446744073709551615"}"#,
        "GatewayIntegrationUpdate": #"{"id":"18446744073709551615","name":"private-integration","type":"future_provider","enabled":true,"account":{"id":"provider:opaque","name":"private-account"},"guild_id":"18446744073709551615"}"#,
        "GatewayIntegrationDelete": #"{"id":"18446744073709551615","guild_id":"18446744073709551615","application_id":"18446744073709551615"}"#,
        "GatewayInviteApplication": #"{"id":"18446744073709551615","name":"private-name","icon":"private-icon","description":"private-description","cover_image":"private-cover_image","flags":18446744073709551615}"#,
        "GatewayInviteCreate": #"{"channel_id":"18446744073709551615","code":"private-code","created_at":"2026-10-16T12:34:56.123456789Z","guild_id":"18446744073709551615","inviter":{"id":"18446744073709551615","username":"private-user","discriminator":"0","global_name":null,"avatar":null},"max_age":1,"max_uses":1,"target_type":999,"target_user":{"id":"18446744073709551615","username":"private-user","discriminator":"0","global_name":null,"avatar":null},"target_application":{"id":"18446744073709551615","name":"private-name","icon":"private-icon","description":"private-description","cover_image":"private-cover_image","flags":18446744073709551615},"temporary":true,"uses":0,"expires_at":"2026-10-16T12:34:56.123456789Z","role_ids":["18446744073709551615"]}"#,
        "GatewayInviteDelete": #"{"channel_id":"18446744073709551615","guild_id":"18446744073709551615","code":"private-code"}"#,
        "GatewayMessageMention": #"{"id":"18446744073709551615","username":"private-user","discriminator":"0","global_name":null,"avatar":null,"member":{"user":{"id":"18446744073709551615","username":"secret text","discriminator":"0","global_name":null,"avatar":null,"bot":true,"collectibles":{}},"nick":"private-nick","avatar":"private-avatar","banner":"private-banner","roles":["18446744073709551615"],"joined_at":"2026-10-16T12:34:56.123456789Z","premium_since":"2026-10-16T12:34:56.123456789Z","deaf":true,"mute":true,"flags":18446744073709551615,"pending":true,"permissions":"1844674407370955161518446744073709551615","communication_disabled_until":"2026-10-16T12:34:56.123456789Z","avatar_decoration_data":{"asset":"private-asset","sku_id":"18446744073709551615"},"collectibles":{"nameplate":null}}}"#,
        "GatewayMessageCreate": #"{"id":"18446744073709551615","channel_id":"18446744073709551615","author":{"id":"18446744073709551615","username":"private-author","avatar":null},"content":"private-message","timestamp":"2026-10-16T12:34:56.123456789Z","edited_timestamp":null,"tts":false,"mention_everyone":false,"mentions":[{"id":"18446744073709551615","username":"private-user","discriminator":"0","global_name":null,"avatar":null,"member":{"user":{"id":"18446744073709551615","username":"secret text","discriminator":"0","global_name":null,"avatar":null,"bot":true,"collectibles":{}},"nick":"private-nick","avatar":"private-avatar","banner":"private-banner","roles":["18446744073709551615"],"joined_at":"2026-10-16T12:34:56.123456789Z","premium_since":"2026-10-16T12:34:56.123456789Z","deaf":true,"mute":true,"flags":18446744073709551615,"pending":true,"permissions":"1844674407370955161518446744073709551615","communication_disabled_until":"2026-10-16T12:34:56.123456789Z","avatar_decoration_data":{"asset":"private-asset","sku_id":"18446744073709551615"},"collectibles":{"nameplate":null}}}],"mention_roles":[],"attachments":[],"embeds":[],"pinned":false,"type":999,"guild_id":"18446744073709551615","member":{"user":{"id":"18446744073709551615","username":"secret text","discriminator":"0","global_name":null,"avatar":null,"bot":true,"collectibles":{}},"nick":"private-nick","avatar":"private-avatar","banner":"private-banner","roles":["18446744073709551615"],"joined_at":"2026-10-16T12:34:56.123456789Z","premium_since":"2026-10-16T12:34:56.123456789Z","deaf":true,"mute":true,"flags":18446744073709551615,"pending":true,"permissions":"1844674407370955161518446744073709551615","communication_disabled_until":"2026-10-16T12:34:56.123456789Z","avatar_decoration_data":{"asset":"private-asset","sku_id":"18446744073709551615"},"collectibles":{"nameplate":null}},"channel_type":999}"#,
        "GatewayMessageDelete": #"{"id":"18446744073709551615","channel_id":"18446744073709551615","guild_id":"18446744073709551615"}"#,
        "GatewayMessageDeleteBulk": #"{"ids":["18446744073709551615"],"channel_id":"18446744073709551615","guild_id":"18446744073709551615"}"#,
        "GatewayMessageReactionAdd": #"{"user_id":"18446744073709551615","channel_id":"18446744073709551615","message_id":"18446744073709551615","guild_id":"18446744073709551615","member":{"user":{"id":"18446744073709551615"},"roles":["18446744073709551615"],"joined_at":null,"deaf":false,"mute":false,"flags":0},"emoji":{"id":null,"name":"wave"},"message_author_id":"18446744073709551615","burst":true,"burst_colors":["private-burst_colors"],"type":999}"#,
        "GatewayMessageReactionRemove": #"{"user_id":"18446744073709551615","channel_id":"18446744073709551615","message_id":"18446744073709551615","guild_id":"18446744073709551615","emoji":{"id":null,"name":"wave"},"burst":true,"type":999}"#,
        "GatewayMessageReactionRemoveAll": #"{"channel_id":"18446744073709551615","message_id":"18446744073709551615","guild_id":"18446744073709551615"}"#,
        "GatewayMessageReactionRemoveEmoji": #"{"channel_id":"18446744073709551615","guild_id":"18446744073709551615","message_id":"18446744073709551615","emoji":{"id":null,"name":"wave"}}"#,
        "GatewayPresenceUser": #"{"id":"18446744073709551615","username":{},"avatar":123}"#,
        "GatewayClientStatus": #"{"desktop":"private-desktop","mobile":"private-mobile","web":"private-web","vr":"private-vr"}"#,
        "GatewayPresenceUpdate": #"{"user":{"id":"18446744073709551615","username":{},"avatar":123},"guild_id":"18446744073709551615","status":"private-status","activities":[{"name":"private-name","type":999,"url":"private-url","created_at":1,"timestamps":{"start":1,"end":1},"application_id":"18446744073709551615","status_display_type":999,"details":"private-details","details_url":"private-details_url","state":"private-state","state_url":"private-state_url","emoji":{"name":"private-name","id":"18446744073709551615","animated":true},"party":{"id":"private-id","size":[2,10]},"assets":{"large_image":"private-large_image","large_text":"private-large_text","large_url":"private-large_url","small_image":"private-small_image","small_text":"private-small_text","small_url":"private-small_url","invite_cover_image":"private-invite_cover_image"},"secrets":{"join":"private-join","spectate":"private-spectate","match":"private-match"},"instance":true,"flags":18446744073709551615,"buttons":["private-buttons"]}],"client_status":{"desktop":"private-desktop","mobile":"private-mobile","web":"private-web","vr":"private-vr"}}"#,
        "GatewayPartialPresence": #"{"user":{"id":"18446744073709551615","username":{},"avatar":123},"guild_id":"18446744073709551615","status":"private-status","activities":[{"name":"private-name","type":999,"url":"private-url","created_at":1,"timestamps":{"start":1,"end":1},"application_id":"18446744073709551615","status_display_type":999,"details":"private-details","details_url":"private-details_url","state":"private-state","state_url":"private-state_url","emoji":{"name":"private-name","id":"18446744073709551615","animated":true},"party":{"id":"private-id","size":[2,10]},"assets":{"large_image":"private-large_image","large_text":"private-large_text","large_url":"private-large_url","small_image":"private-small_image","small_text":"private-small_text","small_url":"private-small_url","invite_cover_image":"private-invite_cover_image"},"secrets":{"join":"private-join","spectate":"private-spectate","match":"private-match"},"instance":true,"flags":18446744073709551615,"buttons":["private-buttons"]}],"client_status":{"desktop":"private-desktop","mobile":"private-mobile","web":"private-web","vr":"private-vr"}}"#,
        "GatewayActivityTimestamps": #"{"start":1,"end":1}"#,
        "GatewayActivityEmoji": #"{"name":"private-name","id":"18446744073709551615","animated":true}"#,
        "GatewayActivityParty": #"{"id":"private-id","size":[2,10]}"#,
        "GatewayActivityAssets": #"{"large_image":"private-large_image","large_text":"private-large_text","large_url":"private-large_url","small_image":"private-small_image","small_text":"private-small_text","small_url":"private-small_url","invite_cover_image":"private-invite_cover_image"}"#,
        "GatewayActivitySecrets": #"{"join":"private-join","spectate":"private-spectate","match":"private-match"}"#,
        "GatewayReceivedActivity": #"{"name":"private-name","type":999,"url":"private-url","created_at":1,"timestamps":{"start":1,"end":1},"application_id":"18446744073709551615","status_display_type":999,"details":"private-details","details_url":"private-details_url","state":"private-state","state_url":"private-state_url","emoji":{"name":"private-name","id":"18446744073709551615","animated":true},"party":{"id":"private-id","size":[2,10]},"assets":{"large_image":"private-large_image","large_text":"private-large_text","large_url":"private-large_url","small_image":"private-small_image","small_text":"private-small_text","small_url":"private-small_url","invite_cover_image":"private-invite_cover_image"},"secrets":{"join":"private-join","spectate":"private-spectate","match":"private-match"},"instance":true,"flags":18446744073709551615,"buttons":["private-buttons"]}"#,
        "GatewayTypingStart": #"{"channel_id":"18446744073709551615","guild_id":"18446744073709551615","user_id":"18446744073709551615","timestamp":1,"member":{"user":{"id":"18446744073709551615"},"roles":["18446744073709551615"],"joined_at":null,"deaf":false,"mute":false,"flags":0}}"#,
        "GatewayVoiceChannelEffect": #"{"channel_id":"18446744073709551615","guild_id":"18446744073709551615","user_id":"18446744073709551615","emoji":{"id":null,"name":"wave"},"animation_type":999,"animation_id":1,"sound_id":"18446744073709551615","sound_volume":0.25}"#,
        "GatewayVoiceServerUpdate": #"{"token":"private-token","guild_id":"18446744073709551615","endpoint":"private-endpoint"}"#,
        "GatewayWebhooksUpdate": #"{"guild_id":"18446744073709551615","channel_id":"18446744073709551615"}"#,
        "GatewayMessagePollVote": #"{"user_id":"18446744073709551615","channel_id":"18446744073709551615","message_id":"18446744073709551615","guild_id":"18446744073709551615","answer_id":1}"#,
        "GatewayMemberRateLimitMetadata": #"{"guild_id":"18446744073709551615","nonce":"private-nonce"}"#,
        "GatewayRateLimited": #"{"opcode":8,"retry_after":0.25,"meta":{"guild_id":"18446744073709551615","nonce":"private-nonce"}}"#,
        "GatewayPartialGuildMember": #"{"user":{"id":"18446744073709551615","username":"secret text","discriminator":"0","global_name":null,"avatar":null,"bot":true,"collectibles":{}},"nick":"private-nick","avatar":"private-avatar","banner":"private-banner","roles":["18446744073709551615"],"joined_at":"2026-10-16T12:34:56.123456789Z","premium_since":"2026-10-16T12:34:56.123456789Z","deaf":true,"mute":true,"flags":18446744073709551615,"pending":true,"permissions":"1844674407370955161518446744073709551615","communication_disabled_until":"2026-10-16T12:34:56.123456789Z","avatar_decoration_data":{"asset":"private-asset","sku_id":"18446744073709551615"},"collectibles":{"nameplate":null}}"#,
        "GatewayMessageUpdate": #"{"id":"18446744073709551615","channel_id":"18446744073709551615","author":{"id":"18446744073709551615","username":"secret text","avatar":null,"discriminator":"secret text","global_name":"secret text","bot":true,"system":true,"mfa_enabled":true,"banner":"secret text","accent_color":1,"locale":"secret text","verified":true,"email":"secret text","flags":1,"public_flags":1,"premium_type":999,"avatar_decoration_data":{"id":"secret text","name":"secret text","type":1},"collectibles":{"id":"secret text","name":"secret text","type":1},"primary_guild":{"id":"secret text","name":"secret text","type":1},"member":{"id":"secret text","name":"secret text","type":1}},"content":"private-content","timestamp":"2026-10-16T12:34:56.123456789Z","edited_timestamp":"2026-10-16T12:34:56.123456789Z","tts":true,"mention_everyone":true,"mentions":[{"id":"18446744073709551615","username":"private-user","discriminator":"0","global_name":null,"avatar":null,"member":{"user":{"id":"18446744073709551615","username":"secret text","discriminator":"0","global_name":null,"avatar":null,"bot":true,"collectibles":{}},"nick":"private-nick","avatar":"private-avatar","banner":"private-banner","roles":["18446744073709551615"],"joined_at":"2026-10-16T12:34:56.123456789Z","premium_since":"2026-10-16T12:34:56.123456789Z","deaf":true,"mute":true,"flags":18446744073709551615,"pending":true,"permissions":"1844674407370955161518446744073709551615","communication_disabled_until":"2026-10-16T12:34:56.123456789Z","avatar_decoration_data":{"asset":"private-asset","sku_id":"18446744073709551615"},"collectibles":{"nameplate":null}}}],"mention_roles":["18446744073709551615"],"mention_channels":[{"id":"18446744073709551615","guild_id":"18446744073709551615","type":1,"name":"secret text"}],"attachments":[{"id":"18446744073709551615","filename":"secret text","title":"secret text","description":"secret text","content_type":"secret text","size":1,"url":"secret text","proxy_url":"secret text","height":1,"width":1,"placeholder":"secret text","placeholder_version":1,"ephemeral":true,"duration_secs":0.25,"waveform":"secret text","flags":1,"clip_participants":[{"id":"18446744073709551615","username":"secret text","avatar":null,"discriminator":"secret text","global_name":"secret text","bot":true,"system":true,"mfa_enabled":true,"banner":"secret text","accent_color":1,"locale":"secret text","verified":true,"email":"secret text","flags":1,"public_flags":1,"premium_type":999,"avatar_decoration_data":{"id":"secret text","name":"secret text","type":1},"collectibles":{"id":"secret text","name":"secret text","type":1},"primary_guild":{"id":"secret text","name":"secret text","type":1},"member":{"id":"secret text","name":"secret text","type":1}}],"clip_created_at":"2026-10-16T17:00:00.123456Z","application":{"id":"secret text","name":"secret text","type":1}}],"embeds":[{"title":"secret text","type":"future-kind","description":"secret text","url":"secret text","timestamp":"2026-10-16T17:00:00.123456Z","color":1,"footer":{"text":"secret text","icon_url":"secret text","proxy_icon_url":"secret text"},"image":{"url":"secret text","proxy_url":"secret text","height":1,"width":1,"content_type":"secret text","placeholder":"secret text","placeholder_version":1,"description":"secret text","flags":1},"thumbnail":{"url":"secret text","proxy_url":"secret text","height":1,"width":1,"content_type":"secret text","placeholder":"secret text","placeholder_version":1,"description":"secret text","flags":1},"video":{"url":"secret text","proxy_url":"secret text","height":1,"width":1,"content_type":"secret text","placeholder":"secret text","placeholder_version":1,"description":"secret text","flags":1},"provider":{"name":"secret text","url":"secret text"},"author":{"name":"secret text","url":"secret text","icon_url":"secret text","proxy_icon_url":"secret text"},"fields":[{"name":"secret text","value":"secret text","inline":true}],"components":[{"type":10,"content":"component text"}],"flags":1}],"reactions":[{"count":1,"count_details":{"burst":1,"normal":1},"me":true,"me_burst":true,"emoji":{"id":null,"name":"😀","animated":true},"burst_colors":["secret text"]}],"pinned":true,"webhook_id":"18446744073709551615","type":999,"activity":{"type":999,"party_id":"secret text"},"application":{"id":"secret text","name":"secret text","type":1},"application_id":"18446744073709551615","flags":18446744073709551615,"message_reference":{"type":999,"message_id":"18446744073709551615","channel_id":"18446744073709551615","guild_id":"18446744073709551615","fail_if_not_exists":true},"message_snapshots":[{"message":{"type":999,"content":"secret text","embeds":[{"title":"secret text","type":"future-kind","description":"secret text","url":"secret text","timestamp":"2026-10-16T17:00:00.123456Z","color":1,"footer":{"text":"secret text","icon_url":"secret text","proxy_icon_url":"secret text"},"image":{"url":"secret text","proxy_url":"secret text","height":1,"width":1,"content_type":"secret text","placeholder":"secret text","placeholder_version":1,"description":"secret text","flags":1},"thumbnail":{"url":"secret text","proxy_url":"secret text","height":1,"width":1,"content_type":"secret text","placeholder":"secret text","placeholder_version":1,"description":"secret text","flags":1},"video":{"url":"secret text","proxy_url":"secret text","height":1,"width":1,"content_type":"secret text","placeholder":"secret text","placeholder_version":1,"description":"secret text","flags":1},"provider":{"name":"secret text","url":"secret text"},"author":{"name":"secret text","url":"secret text","icon_url":"secret text","proxy_icon_url":"secret text"},"fields":[{"name":"secret text","value":"secret text","inline":true}],"components":[{"type":10,"content":"component text"}],"flags":1}],"attachments":[{"id":"18446744073709551615","filename":"secret text","title":"secret text","description":"secret text","content_type":"secret text","size":1,"url":"secret text","proxy_url":"secret text","height":1,"width":1,"placeholder":"secret text","placeholder_version":1,"ephemeral":true,"duration_secs":0.25,"waveform":"secret text","flags":1,"clip_participants":[{"id":"18446744073709551615","username":"secret text","avatar":null,"discriminator":"secret text","global_name":"secret text","bot":true,"system":true,"mfa_enabled":true,"banner":"secret text","accent_color":1,"locale":"secret text","verified":true,"email":"secret text","flags":1,"public_flags":1,"premium_type":999,"avatar_decoration_data":{"id":"secret text","name":"secret text","type":1},"collectibles":{"id":"secret text","name":"secret text","type":1},"primary_guild":{"id":"secret text","name":"secret text","type":1},"member":{"id":"secret text","name":"secret text","type":1}}],"clip_created_at":"2026-10-16T17:00:00.123456Z","application":{"id":"secret text","name":"secret text","type":1}}],"timestamp":"2026-10-16T17:00:00.123456Z","edited_timestamp":null,"flags":1,"mentions":[{"id":"18446744073709551615","username":"secret text","avatar":null,"discriminator":"secret text","global_name":"secret text","bot":true,"system":true,"mfa_enabled":true,"banner":"secret text","accent_color":1,"locale":"secret text","verified":true,"email":"secret text","flags":1,"public_flags":1,"premium_type":999,"avatar_decoration_data":{"id":"secret text","name":"secret text","type":1},"collectibles":{"id":"secret text","name":"secret text","type":1},"primary_guild":{"id":"secret text","name":"secret text","type":1},"member":{"id":"secret text","name":"secret text","type":1}}],"mention_roles":["18446744073709551615"],"stickers":[{"id":"secret text","name":"secret text","type":1}],"sticker_items":[{"id":"18446744073709551615","name":"secret text","format_type":999}],"components":[{"type":10,"content":"component text"}],"message_snapshots":[]}}],"interaction_metadata":{"id":"18446744073709551615","type":2,"user":{"id":"1","username":"user","avatar":null},"authorizing_integration_owners":{"0":"18446744073709551615"}},"interaction":{"id":"18446744073709551615","type":1,"name":"secret text","user":{"id":"18446744073709551615","username":"secret text","avatar":null,"discriminator":"secret text","global_name":"secret text","bot":true,"system":true,"mfa_enabled":true,"banner":"secret text","accent_color":1,"locale":"secret text","verified":true,"email":"secret text","flags":1,"public_flags":1,"premium_type":999,"avatar_decoration_data":{"id":"secret text","name":"secret text","type":1},"collectibles":{"id":"secret text","name":"secret text","type":1},"primary_guild":{"id":"secret text","name":"secret text","type":1},"member":{"id":"secret text","name":"secret text","type":1}},"member":{"id":"secret text","name":"secret text","type":1}},"thread":{"id":"secret text","name":"secret text","type":1},"components":[{"type":999}],"sticker_items":[{"id":"18446744073709551615","name":"secret text","format_type":999}],"stickers":[{"id":"secret text","name":"secret text","type":1}],"position":1,"role_subscription_data":{"role_subscription_listing_id":"18446744073709551615","tier_name":"secret text","total_months_subscribed":1,"is_renewal":true},"resolved":{"users":{"1":{"id":"1","username":"user","avatar":null}},"members":{"1":{}},"roles":{"2":{}},"channels":{"3":{}},"messages":{},"attachments":{}},"poll":{"question":{"text":"private-question"},"answers":[{"answer_id":1,"poll_media":{"text":"private-answer"}}],"expiry":null,"allow_multiselect":false,"layout_type":999},"call":{"participants":["18446744073709551615"],"ended_timestamp":"2026-10-16T17:00:00.123456Z"},"shared_client_theme":{"colors":["secret text"],"gradient_angle":1,"base_mix":1,"base_theme":999},"nonce":"private-nonce","referenced_message":{"id":"18446744073709551615","channel_id":"18446744073709551615","author":{"id":"18446744073709551615","username":"private-author","avatar":null},"content":"private-message","timestamp":"2026-10-16T12:34:56.123456789Z","edited_timestamp":null,"tts":false,"mention_everyone":false,"mentions":[],"mention_roles":[],"attachments":[],"embeds":[],"pinned":false,"type":999},"guild_id":"18446744073709551615","member":{"user":{"id":"18446744073709551615","username":"secret text","discriminator":"0","global_name":null,"avatar":null,"bot":true,"collectibles":{}},"nick":"private-nick","avatar":"private-avatar","banner":"private-banner","roles":["18446744073709551615"],"joined_at":"2026-10-16T12:34:56.123456789Z","premium_since":"2026-10-16T12:34:56.123456789Z","deaf":true,"mute":true,"flags":18446744073709551615,"pending":true,"permissions":"1844674407370955161518446744073709551615","communication_disabled_until":"2026-10-16T12:34:56.123456789Z","avatar_decoration_data":{"asset":"private-asset","sku_id":"18446744073709551615"},"collectibles":{"nameplate":null}},"channel_type":999}"#,
        "GuildApplicationCommandPermissions": #"{"id":"18446744073709551615","application_id":"18446744073709551615","guild_id":"18446744073709551615","permissions":[]}"#,
        "Guild": #"{"id":"18446744073709551615","name":"private-name","icon":null,"splash":null,"owner_id":"18446744073709551615","afk_channel_id":null,"afk_timeout":1,"verification_level":999,"default_message_notifications":999,"explicit_content_filter":999,"roles":[],"emojis":[],"features":["FUTURE_VARIANT"],"mfa_level":999,"application_id":null,"system_channel_id":null,"system_channel_flags":9223372036854775809,"rules_channel_id":null,"vanity_url_code":null,"description":null,"banner":null,"premium_tier":999,"preferred_locale":"private-preferred_locale","public_updates_channel_id":null,"nsfw_level":999,"premium_progress_bar_enabled":true,"safety_alerts_channel_id":null,"incidents_data":null}"#,
        "Interaction": #"{"id":"18446744073709551615","application_id":"18446744073709551615","type":1,"token":"private-token","version":1}"#,
        "User": #"{"id":"18446744073709551615","username":"private-user","discriminator":"0","global_name":null,"avatar":null}"#,
        "VoiceState": #"{"channel_id":"18446744073709551615","user_id":"18446744073709551615","session_id":"private-voice-session","deaf":false,"mute":false,"self_deaf":false,"self_mute":false,"self_video":false,"suppress":false,"request_to_speak_timestamp":null}"#,
        "AutoModerationRule": #"{"id":"18446744073709551615","guild_id":"18446744073709551615","name":"private-rule","creator_id":"18446744073709551615","event_type":999,"trigger_type":999,"trigger_metadata":{},"actions":[{"type":999}],"enabled":true,"exempt_roles":[],"exempt_channels":[]}"#,
        "Channel": #"{"id":"18446744073709551615","type":999,"name":"private-channel","flags":131072}"#,
        "Entitlement": #"{"id":"18446744073709551615","sku_id":"18446744073709551615","application_id":"18446744073709551615","type":8,"deleted":false,"starts_at":null,"ends_at":null}"#,
        "GuildScheduledEvent": #"{"id":"18446744073709551615","guild_id":"18446744073709551615","channel_id":null,"name":"private-event","scheduled_start_time":"2026-10-16T12:34:56.123456789Z","scheduled_end_time":null,"privacy_level":999,"status":999,"entity_type":999,"entity_id":null,"entity_metadata":null,"recurrence_rule":null}"#,
        "SoundboardSound": #"{"name":"private-sound","sound_id":"18446744073709551615","volume":0.25,"emoji_id":null,"emoji_name":"wave","available":true}"#,
        "StageInstance": #"{"id":"18446744073709551615","guild_id":"18446744073709551615","channel_id":"18446744073709551615","topic":"private-stage","privacy_level":999,"discoverable_disabled":true,"guild_scheduled_event_id":null}"#,
        "Subscription": #"{"id":"18446744073709551615","user_id":"18446744073709551615","sku_ids":["18446744073709551615"],"entitlement_ids":["18446744073709551615"],"current_period_start":"2026-10-16T12:34:56.123456789Z","current_period_end":"2026-10-16T12:34:56.123456789Z","status":999,"canceled_at":null,"renewal_sku_ids":null}"#,
    ]

    static let dispatchSources: [GatewayDispatchName: String] = [
        .ready: sources["GatewayReady"]!,
        .resumed: sources["GatewayResumed"]!,
        .rateLimited: sources["GatewayRateLimited"]!,
        .applicationCommandPermissionsUpdate: sources["GuildApplicationCommandPermissions"]!,
        .autoModerationRuleCreate: sources["AutoModerationRule"]!,
        .autoModerationRuleUpdate: sources["AutoModerationRule"]!,
        .autoModerationRuleDelete: sources["AutoModerationRule"]!,
        .autoModerationActionExecution: sources["GatewayAutoModerationActionExecution"]!,
        .channelCreate: sources["Channel"]!,
        .channelUpdate: sources["Channel"]!,
        .channelDelete: sources["Channel"]!,
        .channelInfo: sources["GatewayChannelInfo"]!,
        .channelPinsUpdate: sources["GatewayChannelPinsUpdate"]!,
        .threadCreate: sources["GatewayThreadCreate"]!,
        .threadUpdate: sources["Channel"]!,
        .threadDelete: sources["GatewayThreadDelete"]!,
        .threadListSync: sources["GatewayThreadListSync"]!,
        .threadMemberUpdate: sources["GatewayThreadMemberUpdate"]!,
        .threadMembersUpdate: sources["GatewayThreadMembersUpdate"]!,
        .entitlementCreate: sources["Entitlement"]!,
        .entitlementUpdate: sources["Entitlement"]!,
        .entitlementDelete: sources["Entitlement"]!,
        .guildCreate: sources["GatewayAvailableGuild"]!,
        .guildUpdate: sources["Guild"]!,
        .guildDelete: sources["GatewayGuildAvailability"]!,
        .guildAuditLogEntryCreate: sources["GatewayGuildAuditLogEntryCreate"]!,
        .guildBanAdd: sources["GatewayGuildUser"]!,
        .guildBanRemove: sources["GatewayGuildUser"]!,
        .guildEmojisUpdate: sources["GatewayGuildEmojisUpdate"]!,
        .guildStickersUpdate: sources["GatewayGuildStickersUpdate"]!,
        .guildIntegrationsUpdate: sources["GatewayGuildIntegrationsUpdate"]!,
        .guildMemberAdd: sources["GatewayGuildMemberAdd"]!,
        .guildMemberRemove: sources["GatewayGuildUser"]!,
        .guildMemberUpdate: sources["GatewayGuildMemberUpdate"]!,
        .guildMembersChunk: sources["GatewayGuildMembersChunk"]!,
        .guildRoleCreate: sources["GatewayGuildRoleUpdate"]!,
        .guildRoleUpdate: sources["GatewayGuildRoleUpdate"]!,
        .guildRoleDelete: sources["GatewayGuildRoleDelete"]!,
        .guildScheduledEventCreate: sources["GuildScheduledEvent"]!,
        .guildScheduledEventUpdate: sources["GuildScheduledEvent"]!,
        .guildScheduledEventDelete: sources["GuildScheduledEvent"]!,
        .guildScheduledEventUserAdd: sources["GatewayScheduledEventUser"]!,
        .guildScheduledEventUserRemove: sources["GatewayScheduledEventUser"]!,
        .guildSoundboardSoundCreate: sources["SoundboardSound"]!,
        .guildSoundboardSoundUpdate: sources["SoundboardSound"]!,
        .guildSoundboardSoundDelete: sources["GatewayGuildSoundboardSoundDelete"]!,
        .guildSoundboardSoundsUpdate: sources["GatewaySoundboardSounds"]!,
        .soundboardSounds: sources["GatewaySoundboardSounds"]!,
        .integrationCreate: sources["GatewayIntegrationUpdate"]!,
        .integrationUpdate: sources["GatewayIntegrationUpdate"]!,
        .integrationDelete: sources["GatewayIntegrationDelete"]!,
        .interactionCreate: sources["Interaction"]!,
        .inviteCreate: sources["GatewayInviteCreate"]!,
        .inviteDelete: sources["GatewayInviteDelete"]!,
        .messageCreate: sources["GatewayMessageCreate"]!,
        .messageUpdate: sources["GatewayMessageUpdate"]!,
        .messageDelete: sources["GatewayMessageDelete"]!,
        .messageDeleteBulk: sources["GatewayMessageDeleteBulk"]!,
        .messageReactionAdd: sources["GatewayMessageReactionAdd"]!,
        .messageReactionRemove: sources["GatewayMessageReactionRemove"]!,
        .messageReactionRemoveAll: sources["GatewayMessageReactionRemoveAll"]!,
        .messageReactionRemoveEmoji: sources["GatewayMessageReactionRemoveEmoji"]!,
        .presenceUpdate: sources["GatewayPresenceUpdate"]!,
        .stageInstanceCreate: sources["StageInstance"]!,
        .stageInstanceUpdate: sources["StageInstance"]!,
        .stageInstanceDelete: sources["StageInstance"]!,
        .subscriptionCreate: sources["Subscription"]!,
        .subscriptionUpdate: sources["Subscription"]!,
        .subscriptionDelete: sources["Subscription"]!,
        .typingStart: sources["GatewayTypingStart"]!,
        .userUpdate: sources["User"]!,
        .voiceChannelEffectSend: sources["GatewayVoiceChannelEffect"]!,
        .voiceChannelStartTimeUpdate: sources["GatewayVoiceChannelStartTimeUpdate"]!,
        .voiceChannelStatusUpdate: sources["GatewayVoiceChannelStatusUpdate"]!,
        .voiceStateUpdate: sources["VoiceState"]!,
        .voiceServerUpdate: sources["GatewayVoiceServerUpdate"]!,
        .webhooksUpdate: sources["GatewayWebhooksUpdate"]!,
        .messagePollVoteAdd: sources["GatewayMessagePollVote"]!,
        .messagePollVoteRemove: sources["GatewayMessagePollVote"]!,
    ]

    static let payloads: [Self] = [
        Self(name: "GatewayGuildAvailability", source: sources["GatewayGuildAvailability"]!,
             fields: [GatewayCatalogField(name: "id", optional: false, nullable: false, array: false), GatewayCatalogField(name: "unavailable", optional: true, nullable: false, array: false)],
             parse: { try GatewayGuildAvailability(data: $0, limits: $1) },
             project: { try GatewayGuildAvailability(value: $0, limits: $1) }),
        Self(name: "GatewayReadyApplication", source: sources["GatewayReadyApplication"]!,
             fields: [GatewayCatalogField(name: "id", optional: false, nullable: false, array: false), GatewayCatalogField(name: "flags", optional: false, nullable: false, array: false), GatewayCatalogField(name: "flags_new", optional: true, nullable: false, array: false)],
             parse: { try GatewayReadyApplication(data: $0, limits: $1) },
             project: { try GatewayReadyApplication(value: $0, limits: $1) }),
        Self(name: "GatewayReady", source: sources["GatewayReady"]!,
             fields: [GatewayCatalogField(name: "v", optional: false, nullable: false, array: false), GatewayCatalogField(name: "user", optional: false, nullable: false, array: false), GatewayCatalogField(name: "guilds", optional: false, nullable: false, array: true), GatewayCatalogField(name: "session_id", optional: false, nullable: false, array: false), GatewayCatalogField(name: "resume_gateway_url", optional: false, nullable: false, array: false), GatewayCatalogField(name: "shard", optional: true, nullable: false, array: true), GatewayCatalogField(name: "application", optional: false, nullable: false, array: false)],
             parse: { try GatewayReady(data: $0, limits: $1) },
             project: { try GatewayReady(value: $0, limits: $1) }),
        Self(name: "GatewayResumed", source: sources["GatewayResumed"]!,
             fields: [],
             parse: { try GatewayResumed(data: $0, limits: $1) },
             project: { try GatewayResumed(value: $0, limits: $1) }),
        Self(name: "GatewayAutoModerationActionExecution", source: sources["GatewayAutoModerationActionExecution"]!,
             fields: [GatewayCatalogField(name: "guild_id", optional: false, nullable: false, array: false), GatewayCatalogField(name: "action", optional: false, nullable: false, array: false), GatewayCatalogField(name: "rule_id", optional: false, nullable: false, array: false), GatewayCatalogField(name: "rule_trigger_type", optional: false, nullable: false, array: false), GatewayCatalogField(name: "user_id", optional: false, nullable: false, array: false), GatewayCatalogField(name: "channel_id", optional: true, nullable: false, array: false), GatewayCatalogField(name: "message_id", optional: true, nullable: false, array: false), GatewayCatalogField(name: "alert_system_message_id", optional: true, nullable: false, array: false), GatewayCatalogField(name: "content", optional: true, nullable: false, array: false), GatewayCatalogField(name: "matched_keyword", optional: false, nullable: true, array: false), GatewayCatalogField(name: "matched_content", optional: true, nullable: true, array: false)],
             parse: { try GatewayAutoModerationActionExecution(data: $0, limits: $1) },
             project: { try GatewayAutoModerationActionExecution(value: $0, limits: $1) }),
        Self(name: "GatewayChannelInfoChannel", source: sources["GatewayChannelInfoChannel"]!,
             fields: [GatewayCatalogField(name: "id", optional: false, nullable: false, array: false), GatewayCatalogField(name: "status", optional: true, nullable: true, array: false), GatewayCatalogField(name: "voice_start_time", optional: true, nullable: true, array: false)],
             parse: { try GatewayChannelInfoChannel(data: $0, limits: $1) },
             project: { try GatewayChannelInfoChannel(value: $0, limits: $1) }),
        Self(name: "GatewayChannelInfo", source: sources["GatewayChannelInfo"]!,
             fields: [GatewayCatalogField(name: "guild_id", optional: false, nullable: false, array: false), GatewayCatalogField(name: "channels", optional: false, nullable: false, array: true)],
             parse: { try GatewayChannelInfo(data: $0, limits: $1) },
             project: { try GatewayChannelInfo(value: $0, limits: $1) }),
        Self(name: "GatewayVoiceChannelStatusUpdate", source: sources["GatewayVoiceChannelStatusUpdate"]!,
             fields: [GatewayCatalogField(name: "id", optional: false, nullable: false, array: false), GatewayCatalogField(name: "guild_id", optional: false, nullable: false, array: false), GatewayCatalogField(name: "status", optional: false, nullable: true, array: false)],
             parse: { try GatewayVoiceChannelStatusUpdate(data: $0, limits: $1) },
             project: { try GatewayVoiceChannelStatusUpdate(value: $0, limits: $1) }),
        Self(name: "GatewayVoiceChannelStartTimeUpdate", source: sources["GatewayVoiceChannelStartTimeUpdate"]!,
             fields: [GatewayCatalogField(name: "id", optional: false, nullable: false, array: false), GatewayCatalogField(name: "guild_id", optional: false, nullable: false, array: false), GatewayCatalogField(name: "voice_start_time", optional: true, nullable: true, array: false)],
             parse: { try GatewayVoiceChannelStartTimeUpdate(data: $0, limits: $1) },
             project: { try GatewayVoiceChannelStartTimeUpdate(value: $0, limits: $1) }),
        Self(name: "GatewayThreadCreate", source: sources["GatewayThreadCreate"]!,
             fields: [GatewayCatalogField(name: "newly_created", optional: true, nullable: false, array: false)],
             parse: { try GatewayThreadCreate(data: $0, limits: $1) },
             project: { try GatewayThreadCreate(value: $0, limits: $1) }),
        Self(name: "GatewayThreadDelete", source: sources["GatewayThreadDelete"]!,
             fields: [GatewayCatalogField(name: "id", optional: false, nullable: false, array: false), GatewayCatalogField(name: "guild_id", optional: false, nullable: false, array: false), GatewayCatalogField(name: "parent_id", optional: false, nullable: false, array: false), GatewayCatalogField(name: "type", optional: false, nullable: false, array: false)],
             parse: { try GatewayThreadDelete(data: $0, limits: $1) },
             project: { try GatewayThreadDelete(value: $0, limits: $1) }),
        Self(name: "GatewayThreadListSync", source: sources["GatewayThreadListSync"]!,
             fields: [GatewayCatalogField(name: "guild_id", optional: false, nullable: false, array: false), GatewayCatalogField(name: "channel_ids", optional: true, nullable: false, array: true), GatewayCatalogField(name: "threads", optional: false, nullable: false, array: true), GatewayCatalogField(name: "members", optional: false, nullable: false, array: true)],
             parse: { try GatewayThreadListSync(data: $0, limits: $1) },
             project: { try GatewayThreadListSync(value: $0, limits: $1) }),
        Self(name: "GatewayThreadMemberUpdate", source: sources["GatewayThreadMemberUpdate"]!,
             fields: [GatewayCatalogField(name: "guild_id", optional: false, nullable: false, array: false)],
             parse: { try GatewayThreadMemberUpdate(data: $0, limits: $1) },
             project: { try GatewayThreadMemberUpdate(value: $0, limits: $1) }),
        Self(name: "GatewayThreadAddedMember", source: sources["GatewayThreadAddedMember"]!,
             fields: [GatewayCatalogField(name: "presence", optional: true, nullable: true, array: false)],
             parse: { try GatewayThreadAddedMember(data: $0, limits: $1) },
             project: { try GatewayThreadAddedMember(value: $0, limits: $1) }),
        Self(name: "GatewayThreadMembersUpdate", source: sources["GatewayThreadMembersUpdate"]!,
             fields: [GatewayCatalogField(name: "id", optional: false, nullable: false, array: false), GatewayCatalogField(name: "guild_id", optional: false, nullable: false, array: false), GatewayCatalogField(name: "member_count", optional: false, nullable: false, array: false), GatewayCatalogField(name: "added_members", optional: true, nullable: false, array: true), GatewayCatalogField(name: "removed_member_ids", optional: true, nullable: false, array: true)],
             parse: { try GatewayThreadMembersUpdate(data: $0, limits: $1) },
             project: { try GatewayThreadMembersUpdate(value: $0, limits: $1) }),
        Self(name: "GatewayChannelPinsUpdate", source: sources["GatewayChannelPinsUpdate"]!,
             fields: [GatewayCatalogField(name: "guild_id", optional: true, nullable: false, array: false), GatewayCatalogField(name: "channel_id", optional: false, nullable: false, array: false), GatewayCatalogField(name: "last_pin_timestamp", optional: true, nullable: true, array: false)],
             parse: { try GatewayChannelPinsUpdate(data: $0, limits: $1) },
             project: { try GatewayChannelPinsUpdate(value: $0, limits: $1) }),
        Self(name: "GatewayAvailableGuild", source: sources["GatewayAvailableGuild"]!,
             fields: [GatewayCatalogField(name: "joined_at", optional: false, nullable: false, array: false), GatewayCatalogField(name: "large", optional: false, nullable: false, array: false), GatewayCatalogField(name: "unavailable", optional: true, nullable: false, array: false), GatewayCatalogField(name: "member_count", optional: false, nullable: false, array: false), GatewayCatalogField(name: "voice_states", optional: false, nullable: false, array: true), GatewayCatalogField(name: "members", optional: false, nullable: false, array: true), GatewayCatalogField(name: "channels", optional: false, nullable: false, array: true), GatewayCatalogField(name: "threads", optional: false, nullable: false, array: true), GatewayCatalogField(name: "presences", optional: false, nullable: false, array: true), GatewayCatalogField(name: "stage_instances", optional: false, nullable: false, array: true), GatewayCatalogField(name: "guild_scheduled_events", optional: false, nullable: false, array: true), GatewayCatalogField(name: "soundboard_sounds", optional: false, nullable: false, array: true)],
             parse: { try GatewayAvailableGuild(data: $0, limits: $1) },
             project: { try GatewayAvailableGuild(value: $0, limits: $1) }),
        Self(name: "GatewayGuildAuditLogEntryCreate", source: sources["GatewayGuildAuditLogEntryCreate"]!,
             fields: [GatewayCatalogField(name: "guild_id", optional: false, nullable: false, array: false)],
             parse: { try GatewayGuildAuditLogEntryCreate(data: $0, limits: $1) },
             project: { try GatewayGuildAuditLogEntryCreate(value: $0, limits: $1) }),
        Self(name: "GatewayGuildUser", source: sources["GatewayGuildUser"]!,
             fields: [GatewayCatalogField(name: "guild_id", optional: false, nullable: false, array: false), GatewayCatalogField(name: "user", optional: false, nullable: false, array: false)],
             parse: { try GatewayGuildUser(data: $0, limits: $1) },
             project: { try GatewayGuildUser(value: $0, limits: $1) }),
        Self(name: "GatewayGuildEmojisUpdate", source: sources["GatewayGuildEmojisUpdate"]!,
             fields: [GatewayCatalogField(name: "guild_id", optional: false, nullable: false, array: false), GatewayCatalogField(name: "emojis", optional: false, nullable: false, array: true)],
             parse: { try GatewayGuildEmojisUpdate(data: $0, limits: $1) },
             project: { try GatewayGuildEmojisUpdate(value: $0, limits: $1) }),
        Self(name: "GatewayGuildStickersUpdate", source: sources["GatewayGuildStickersUpdate"]!,
             fields: [GatewayCatalogField(name: "guild_id", optional: false, nullable: false, array: false), GatewayCatalogField(name: "stickers", optional: false, nullable: false, array: true)],
             parse: { try GatewayGuildStickersUpdate(data: $0, limits: $1) },
             project: { try GatewayGuildStickersUpdate(value: $0, limits: $1) }),
        Self(name: "GatewayGuildIntegrationsUpdate", source: sources["GatewayGuildIntegrationsUpdate"]!,
             fields: [GatewayCatalogField(name: "guild_id", optional: false, nullable: false, array: false)],
             parse: { try GatewayGuildIntegrationsUpdate(data: $0, limits: $1) },
             project: { try GatewayGuildIntegrationsUpdate(value: $0, limits: $1) }),
        Self(name: "GatewayGuildMemberAdd", source: sources["GatewayGuildMemberAdd"]!,
             fields: [GatewayCatalogField(name: "guild_id", optional: false, nullable: false, array: false)],
             parse: { try GatewayGuildMemberAdd(data: $0, limits: $1) },
             project: { try GatewayGuildMemberAdd(value: $0, limits: $1) }),
        Self(name: "GatewayGuildMemberUpdate", source: sources["GatewayGuildMemberUpdate"]!,
             fields: [GatewayCatalogField(name: "guild_id", optional: false, nullable: false, array: false), GatewayCatalogField(name: "roles", optional: false, nullable: false, array: true), GatewayCatalogField(name: "user", optional: false, nullable: false, array: false), GatewayCatalogField(name: "nick", optional: true, nullable: true, array: false), GatewayCatalogField(name: "avatar", optional: false, nullable: true, array: false), GatewayCatalogField(name: "banner", optional: false, nullable: true, array: false), GatewayCatalogField(name: "joined_at", optional: false, nullable: true, array: false), GatewayCatalogField(name: "premium_since", optional: true, nullable: true, array: false), GatewayCatalogField(name: "deaf", optional: true, nullable: false, array: false), GatewayCatalogField(name: "mute", optional: true, nullable: false, array: false), GatewayCatalogField(name: "pending", optional: true, nullable: false, array: false), GatewayCatalogField(name: "communication_disabled_until", optional: true, nullable: true, array: false), GatewayCatalogField(name: "avatar_decoration_data", optional: true, nullable: true, array: false), GatewayCatalogField(name: "collectibles", optional: true, nullable: true, array: false)],
             parse: { try GatewayGuildMemberUpdate(data: $0, limits: $1) },
             project: { try GatewayGuildMemberUpdate(value: $0, limits: $1) }),
        Self(name: "GatewayGuildMembersChunk", source: sources["GatewayGuildMembersChunk"]!,
             fields: [GatewayCatalogField(name: "guild_id", optional: false, nullable: false, array: false), GatewayCatalogField(name: "members", optional: false, nullable: false, array: true), GatewayCatalogField(name: "chunk_index", optional: false, nullable: false, array: false), GatewayCatalogField(name: "chunk_count", optional: false, nullable: false, array: false), GatewayCatalogField(name: "not_found", optional: true, nullable: false, array: true), GatewayCatalogField(name: "presences", optional: true, nullable: false, array: true), GatewayCatalogField(name: "nonce", optional: true, nullable: false, array: false)],
             parse: { try GatewayGuildMembersChunk(data: $0, limits: $1) },
             project: { try GatewayGuildMembersChunk(value: $0, limits: $1) }),
        Self(name: "GatewayGuildRoleUpdate", source: sources["GatewayGuildRoleUpdate"]!,
             fields: [GatewayCatalogField(name: "guild_id", optional: false, nullable: false, array: false), GatewayCatalogField(name: "role", optional: false, nullable: false, array: false)],
             parse: { try GatewayGuildRoleUpdate(data: $0, limits: $1) },
             project: { try GatewayGuildRoleUpdate(value: $0, limits: $1) }),
        Self(name: "GatewayGuildRoleDelete", source: sources["GatewayGuildRoleDelete"]!,
             fields: [GatewayCatalogField(name: "guild_id", optional: false, nullable: false, array: false), GatewayCatalogField(name: "role_id", optional: false, nullable: false, array: false)],
             parse: { try GatewayGuildRoleDelete(data: $0, limits: $1) },
             project: { try GatewayGuildRoleDelete(value: $0, limits: $1) }),
        Self(name: "GatewayScheduledEventUser", source: sources["GatewayScheduledEventUser"]!,
             fields: [GatewayCatalogField(name: "guild_scheduled_event_id", optional: false, nullable: false, array: false), GatewayCatalogField(name: "user_id", optional: false, nullable: false, array: false), GatewayCatalogField(name: "guild_id", optional: false, nullable: false, array: false)],
             parse: { try GatewayScheduledEventUser(data: $0, limits: $1) },
             project: { try GatewayScheduledEventUser(value: $0, limits: $1) }),
        Self(name: "GatewayGuildSoundboardSoundDelete", source: sources["GatewayGuildSoundboardSoundDelete"]!,
             fields: [GatewayCatalogField(name: "sound_id", optional: false, nullable: false, array: false), GatewayCatalogField(name: "guild_id", optional: false, nullable: false, array: false)],
             parse: { try GatewayGuildSoundboardSoundDelete(data: $0, limits: $1) },
             project: { try GatewayGuildSoundboardSoundDelete(value: $0, limits: $1) }),
        Self(name: "GatewaySoundboardSounds", source: sources["GatewaySoundboardSounds"]!,
             fields: [GatewayCatalogField(name: "soundboard_sounds", optional: false, nullable: false, array: true), GatewayCatalogField(name: "guild_id", optional: false, nullable: false, array: false)],
             parse: { try GatewaySoundboardSounds(data: $0, limits: $1) },
             project: { try GatewaySoundboardSounds(value: $0, limits: $1) }),
        Self(name: "GatewayIntegrationUpdate", source: sources["GatewayIntegrationUpdate"]!,
             fields: [GatewayCatalogField(name: "guild_id", optional: false, nullable: false, array: false)],
             parse: { try GatewayIntegrationUpdate(data: $0, limits: $1) },
             project: { try GatewayIntegrationUpdate(value: $0, limits: $1) }),
        Self(name: "GatewayIntegrationDelete", source: sources["GatewayIntegrationDelete"]!,
             fields: [GatewayCatalogField(name: "id", optional: false, nullable: false, array: false), GatewayCatalogField(name: "guild_id", optional: false, nullable: false, array: false), GatewayCatalogField(name: "application_id", optional: true, nullable: false, array: false)],
             parse: { try GatewayIntegrationDelete(data: $0, limits: $1) },
             project: { try GatewayIntegrationDelete(value: $0, limits: $1) }),
        Self(name: "GatewayInviteApplication", source: sources["GatewayInviteApplication"]!,
             fields: [GatewayCatalogField(name: "id", optional: false, nullable: false, array: false), GatewayCatalogField(name: "name", optional: true, nullable: false, array: false), GatewayCatalogField(name: "icon", optional: true, nullable: true, array: false), GatewayCatalogField(name: "description", optional: true, nullable: false, array: false), GatewayCatalogField(name: "cover_image", optional: true, nullable: false, array: false), GatewayCatalogField(name: "flags", optional: true, nullable: false, array: false)],
             parse: { try GatewayInviteApplication(data: $0, limits: $1) },
             project: { try GatewayInviteApplication(value: $0, limits: $1) }),
        Self(name: "GatewayInviteCreate", source: sources["GatewayInviteCreate"]!,
             fields: [GatewayCatalogField(name: "channel_id", optional: false, nullable: false, array: false), GatewayCatalogField(name: "code", optional: false, nullable: false, array: false), GatewayCatalogField(name: "created_at", optional: false, nullable: false, array: false), GatewayCatalogField(name: "guild_id", optional: true, nullable: false, array: false), GatewayCatalogField(name: "inviter", optional: true, nullable: false, array: false), GatewayCatalogField(name: "max_age", optional: false, nullable: false, array: false), GatewayCatalogField(name: "max_uses", optional: false, nullable: false, array: false), GatewayCatalogField(name: "target_type", optional: true, nullable: false, array: false), GatewayCatalogField(name: "target_user", optional: true, nullable: false, array: false), GatewayCatalogField(name: "target_application", optional: true, nullable: false, array: false), GatewayCatalogField(name: "temporary", optional: false, nullable: false, array: false), GatewayCatalogField(name: "uses", optional: false, nullable: false, array: false), GatewayCatalogField(name: "expires_at", optional: false, nullable: true, array: false), GatewayCatalogField(name: "role_ids", optional: true, nullable: false, array: true)],
             parse: { try GatewayInviteCreate(data: $0, limits: $1) },
             project: { try GatewayInviteCreate(value: $0, limits: $1) }),
        Self(name: "GatewayInviteDelete", source: sources["GatewayInviteDelete"]!,
             fields: [GatewayCatalogField(name: "channel_id", optional: false, nullable: false, array: false), GatewayCatalogField(name: "guild_id", optional: true, nullable: false, array: false), GatewayCatalogField(name: "code", optional: false, nullable: false, array: false)],
             parse: { try GatewayInviteDelete(data: $0, limits: $1) },
             project: { try GatewayInviteDelete(value: $0, limits: $1) }),
        Self(name: "GatewayMessageMention", source: sources["GatewayMessageMention"]!,
             fields: [GatewayCatalogField(name: "member", optional: true, nullable: false, array: false)],
             parse: { try GatewayMessageMention(data: $0, limits: $1) },
             project: { try GatewayMessageMention(value: $0, limits: $1) }),
        Self(name: "GatewayMessageCreate", source: sources["GatewayMessageCreate"]!,
             fields: [GatewayCatalogField(name: "guild_id", optional: true, nullable: false, array: false), GatewayCatalogField(name: "member", optional: true, nullable: false, array: false), GatewayCatalogField(name: "mentions", optional: false, nullable: false, array: true), GatewayCatalogField(name: "channel_type", optional: true, nullable: false, array: false)],
             parse: { try GatewayMessageCreate(data: $0, limits: $1) },
             project: { try GatewayMessageCreate(value: $0, limits: $1) }),
        Self(name: "GatewayMessageDelete", source: sources["GatewayMessageDelete"]!,
             fields: [GatewayCatalogField(name: "id", optional: false, nullable: false, array: false), GatewayCatalogField(name: "channel_id", optional: false, nullable: false, array: false), GatewayCatalogField(name: "guild_id", optional: true, nullable: false, array: false)],
             parse: { try GatewayMessageDelete(data: $0, limits: $1) },
             project: { try GatewayMessageDelete(value: $0, limits: $1) }),
        Self(name: "GatewayMessageDeleteBulk", source: sources["GatewayMessageDeleteBulk"]!,
             fields: [GatewayCatalogField(name: "ids", optional: false, nullable: false, array: true), GatewayCatalogField(name: "channel_id", optional: false, nullable: false, array: false), GatewayCatalogField(name: "guild_id", optional: true, nullable: false, array: false)],
             parse: { try GatewayMessageDeleteBulk(data: $0, limits: $1) },
             project: { try GatewayMessageDeleteBulk(value: $0, limits: $1) }),
        Self(name: "GatewayMessageReactionAdd", source: sources["GatewayMessageReactionAdd"]!,
             fields: [GatewayCatalogField(name: "user_id", optional: false, nullable: false, array: false), GatewayCatalogField(name: "channel_id", optional: false, nullable: false, array: false), GatewayCatalogField(name: "message_id", optional: false, nullable: false, array: false), GatewayCatalogField(name: "guild_id", optional: true, nullable: false, array: false), GatewayCatalogField(name: "member", optional: true, nullable: false, array: false), GatewayCatalogField(name: "emoji", optional: false, nullable: false, array: false), GatewayCatalogField(name: "message_author_id", optional: true, nullable: false, array: false), GatewayCatalogField(name: "burst", optional: false, nullable: false, array: false), GatewayCatalogField(name: "burst_colors", optional: true, nullable: false, array: true), GatewayCatalogField(name: "type", optional: false, nullable: false, array: false)],
             parse: { try GatewayMessageReactionAdd(data: $0, limits: $1) },
             project: { try GatewayMessageReactionAdd(value: $0, limits: $1) }),
        Self(name: "GatewayMessageReactionRemove", source: sources["GatewayMessageReactionRemove"]!,
             fields: [GatewayCatalogField(name: "user_id", optional: false, nullable: false, array: false), GatewayCatalogField(name: "channel_id", optional: false, nullable: false, array: false), GatewayCatalogField(name: "message_id", optional: false, nullable: false, array: false), GatewayCatalogField(name: "guild_id", optional: true, nullable: false, array: false), GatewayCatalogField(name: "emoji", optional: false, nullable: false, array: false), GatewayCatalogField(name: "burst", optional: false, nullable: false, array: false), GatewayCatalogField(name: "type", optional: false, nullable: false, array: false)],
             parse: { try GatewayMessageReactionRemove(data: $0, limits: $1) },
             project: { try GatewayMessageReactionRemove(value: $0, limits: $1) }),
        Self(name: "GatewayMessageReactionRemoveAll", source: sources["GatewayMessageReactionRemoveAll"]!,
             fields: [GatewayCatalogField(name: "channel_id", optional: false, nullable: false, array: false), GatewayCatalogField(name: "message_id", optional: false, nullable: false, array: false), GatewayCatalogField(name: "guild_id", optional: true, nullable: false, array: false)],
             parse: { try GatewayMessageReactionRemoveAll(data: $0, limits: $1) },
             project: { try GatewayMessageReactionRemoveAll(value: $0, limits: $1) }),
        Self(name: "GatewayMessageReactionRemoveEmoji", source: sources["GatewayMessageReactionRemoveEmoji"]!,
             fields: [GatewayCatalogField(name: "channel_id", optional: false, nullable: false, array: false), GatewayCatalogField(name: "guild_id", optional: true, nullable: false, array: false), GatewayCatalogField(name: "message_id", optional: false, nullable: false, array: false), GatewayCatalogField(name: "emoji", optional: false, nullable: false, array: false)],
             parse: { try GatewayMessageReactionRemoveEmoji(data: $0, limits: $1) },
             project: { try GatewayMessageReactionRemoveEmoji(value: $0, limits: $1) }),
        Self(name: "GatewayPresenceUser", source: sources["GatewayPresenceUser"]!,
             fields: [GatewayCatalogField(name: "id", optional: false, nullable: false, array: false)],
             parse: { try GatewayPresenceUser(data: $0, limits: $1) },
             project: { try GatewayPresenceUser(value: $0, limits: $1) }),
        Self(name: "GatewayClientStatus", source: sources["GatewayClientStatus"]!,
             fields: [GatewayCatalogField(name: "desktop", optional: true, nullable: false, array: false), GatewayCatalogField(name: "mobile", optional: true, nullable: false, array: false), GatewayCatalogField(name: "web", optional: true, nullable: false, array: false), GatewayCatalogField(name: "vr", optional: true, nullable: false, array: false)],
             parse: { try GatewayClientStatus(data: $0, limits: $1) },
             project: { try GatewayClientStatus(value: $0, limits: $1) }),
        Self(name: "GatewayPresenceUpdate", source: sources["GatewayPresenceUpdate"]!,
             fields: [GatewayCatalogField(name: "user", optional: false, nullable: false, array: false), GatewayCatalogField(name: "guild_id", optional: false, nullable: false, array: false), GatewayCatalogField(name: "status", optional: false, nullable: false, array: false), GatewayCatalogField(name: "activities", optional: false, nullable: false, array: true), GatewayCatalogField(name: "client_status", optional: false, nullable: false, array: false)],
             parse: { try GatewayPresenceUpdate(data: $0, limits: $1) },
             project: { try GatewayPresenceUpdate(value: $0, limits: $1) }),
        Self(name: "GatewayPartialPresence", source: sources["GatewayPartialPresence"]!,
             fields: [GatewayCatalogField(name: "user", optional: false, nullable: false, array: false), GatewayCatalogField(name: "guild_id", optional: true, nullable: false, array: false), GatewayCatalogField(name: "status", optional: true, nullable: false, array: false), GatewayCatalogField(name: "activities", optional: true, nullable: false, array: true), GatewayCatalogField(name: "client_status", optional: true, nullable: false, array: false)],
             parse: { try GatewayPartialPresence(data: $0, limits: $1) },
             project: { try GatewayPartialPresence(value: $0, limits: $1) }),
        Self(name: "GatewayActivityTimestamps", source: sources["GatewayActivityTimestamps"]!,
             fields: [GatewayCatalogField(name: "start", optional: true, nullable: false, array: false), GatewayCatalogField(name: "end", optional: true, nullable: false, array: false)],
             parse: { try GatewayActivityTimestamps(data: $0, limits: $1) },
             project: { try GatewayActivityTimestamps(value: $0, limits: $1) }),
        Self(name: "GatewayActivityEmoji", source: sources["GatewayActivityEmoji"]!,
             fields: [GatewayCatalogField(name: "name", optional: false, nullable: false, array: false), GatewayCatalogField(name: "id", optional: true, nullable: false, array: false), GatewayCatalogField(name: "animated", optional: true, nullable: false, array: false)],
             parse: { try GatewayActivityEmoji(data: $0, limits: $1) },
             project: { try GatewayActivityEmoji(value: $0, limits: $1) }),
        Self(name: "GatewayActivityParty", source: sources["GatewayActivityParty"]!,
             fields: [GatewayCatalogField(name: "id", optional: true, nullable: false, array: false), GatewayCatalogField(name: "size", optional: true, nullable: false, array: true)],
             parse: { try GatewayActivityParty(data: $0, limits: $1) },
             project: { try GatewayActivityParty(value: $0, limits: $1) }),
        Self(name: "GatewayActivityAssets", source: sources["GatewayActivityAssets"]!,
             fields: [GatewayCatalogField(name: "large_image", optional: true, nullable: false, array: false), GatewayCatalogField(name: "large_text", optional: true, nullable: false, array: false), GatewayCatalogField(name: "large_url", optional: true, nullable: false, array: false), GatewayCatalogField(name: "small_image", optional: true, nullable: false, array: false), GatewayCatalogField(name: "small_text", optional: true, nullable: false, array: false), GatewayCatalogField(name: "small_url", optional: true, nullable: false, array: false), GatewayCatalogField(name: "invite_cover_image", optional: true, nullable: false, array: false)],
             parse: { try GatewayActivityAssets(data: $0, limits: $1) },
             project: { try GatewayActivityAssets(value: $0, limits: $1) }),
        Self(name: "GatewayActivitySecrets", source: sources["GatewayActivitySecrets"]!,
             fields: [GatewayCatalogField(name: "join", optional: true, nullable: false, array: false), GatewayCatalogField(name: "spectate", optional: true, nullable: false, array: false), GatewayCatalogField(name: "match", optional: true, nullable: false, array: false)],
             parse: { try GatewayActivitySecrets(data: $0, limits: $1) },
             project: { try GatewayActivitySecrets(value: $0, limits: $1) }),
        Self(name: "GatewayReceivedActivity", source: sources["GatewayReceivedActivity"]!,
             fields: [GatewayCatalogField(name: "name", optional: false, nullable: false, array: false), GatewayCatalogField(name: "type", optional: false, nullable: false, array: false), GatewayCatalogField(name: "url", optional: true, nullable: true, array: false), GatewayCatalogField(name: "created_at", optional: false, nullable: false, array: false), GatewayCatalogField(name: "timestamps", optional: true, nullable: false, array: false), GatewayCatalogField(name: "application_id", optional: true, nullable: false, array: false), GatewayCatalogField(name: "status_display_type", optional: true, nullable: true, array: false), GatewayCatalogField(name: "details", optional: true, nullable: true, array: false), GatewayCatalogField(name: "details_url", optional: true, nullable: true, array: false), GatewayCatalogField(name: "state", optional: true, nullable: true, array: false), GatewayCatalogField(name: "state_url", optional: true, nullable: true, array: false), GatewayCatalogField(name: "emoji", optional: true, nullable: true, array: false), GatewayCatalogField(name: "party", optional: true, nullable: false, array: false), GatewayCatalogField(name: "assets", optional: true, nullable: false, array: false), GatewayCatalogField(name: "secrets", optional: true, nullable: false, array: false), GatewayCatalogField(name: "instance", optional: true, nullable: false, array: false), GatewayCatalogField(name: "flags", optional: true, nullable: false, array: false), GatewayCatalogField(name: "buttons", optional: true, nullable: false, array: true)],
             parse: { try GatewayReceivedActivity(data: $0, limits: $1) },
             project: { try GatewayReceivedActivity(value: $0, limits: $1) }),
        Self(name: "GatewayTypingStart", source: sources["GatewayTypingStart"]!,
             fields: [GatewayCatalogField(name: "channel_id", optional: false, nullable: false, array: false), GatewayCatalogField(name: "guild_id", optional: true, nullable: false, array: false), GatewayCatalogField(name: "user_id", optional: false, nullable: false, array: false), GatewayCatalogField(name: "timestamp", optional: false, nullable: false, array: false), GatewayCatalogField(name: "member", optional: true, nullable: false, array: false)],
             parse: { try GatewayTypingStart(data: $0, limits: $1) },
             project: { try GatewayTypingStart(value: $0, limits: $1) }),
        Self(name: "GatewayVoiceChannelEffect", source: sources["GatewayVoiceChannelEffect"]!,
             fields: [GatewayCatalogField(name: "channel_id", optional: false, nullable: false, array: false), GatewayCatalogField(name: "guild_id", optional: false, nullable: false, array: false), GatewayCatalogField(name: "user_id", optional: false, nullable: false, array: false), GatewayCatalogField(name: "emoji", optional: true, nullable: true, array: false), GatewayCatalogField(name: "animation_type", optional: true, nullable: true, array: false), GatewayCatalogField(name: "animation_id", optional: true, nullable: false, array: false), GatewayCatalogField(name: "sound_id", optional: true, nullable: false, array: false), GatewayCatalogField(name: "sound_volume", optional: true, nullable: false, array: false)],
             parse: { try GatewayVoiceChannelEffect(data: $0, limits: $1) },
             project: { try GatewayVoiceChannelEffect(value: $0, limits: $1) }),
        Self(name: "GatewayVoiceServerUpdate", source: sources["GatewayVoiceServerUpdate"]!,
             fields: [GatewayCatalogField(name: "token", optional: false, nullable: false, array: false), GatewayCatalogField(name: "guild_id", optional: false, nullable: false, array: false), GatewayCatalogField(name: "endpoint", optional: false, nullable: true, array: false)],
             parse: { try GatewayVoiceServerUpdate(data: $0, limits: $1) },
             project: { try GatewayVoiceServerUpdate(value: $0, limits: $1) }),
        Self(name: "GatewayWebhooksUpdate", source: sources["GatewayWebhooksUpdate"]!,
             fields: [GatewayCatalogField(name: "guild_id", optional: false, nullable: false, array: false), GatewayCatalogField(name: "channel_id", optional: false, nullable: false, array: false)],
             parse: { try GatewayWebhooksUpdate(data: $0, limits: $1) },
             project: { try GatewayWebhooksUpdate(value: $0, limits: $1) }),
        Self(name: "GatewayMessagePollVote", source: sources["GatewayMessagePollVote"]!,
             fields: [GatewayCatalogField(name: "user_id", optional: false, nullable: false, array: false), GatewayCatalogField(name: "channel_id", optional: false, nullable: false, array: false), GatewayCatalogField(name: "message_id", optional: false, nullable: false, array: false), GatewayCatalogField(name: "guild_id", optional: true, nullable: false, array: false), GatewayCatalogField(name: "answer_id", optional: false, nullable: false, array: false)],
             parse: { try GatewayMessagePollVote(data: $0, limits: $1) },
             project: { try GatewayMessagePollVote(value: $0, limits: $1) }),
        Self(name: "GatewayMemberRateLimitMetadata", source: sources["GatewayMemberRateLimitMetadata"]!,
             fields: [GatewayCatalogField(name: "guild_id", optional: false, nullable: false, array: false), GatewayCatalogField(name: "nonce", optional: true, nullable: false, array: false)],
             parse: { try GatewayMemberRateLimitMetadata(data: $0, limits: $1) },
             project: { try GatewayMemberRateLimitMetadata(value: $0, limits: $1) }),
        Self(name: "GatewayRateLimited", source: sources["GatewayRateLimited"]!,
             fields: [GatewayCatalogField(name: "retry_after", optional: false, nullable: false, array: false), GatewayCatalogField(name: "meta", optional: false, nullable: false, array: false)],
             parse: { try GatewayRateLimited(data: $0, limits: $1) },
             project: { try GatewayRateLimited(value: $0, limits: $1) }),
        Self(name: "GatewayPartialGuildMember", source: sources["GatewayPartialGuildMember"]!,
             fields: [GatewayCatalogField(name: "user", optional: true, nullable: false, array: false), GatewayCatalogField(name: "nick", optional: true, nullable: true, array: false), GatewayCatalogField(name: "avatar", optional: true, nullable: true, array: false), GatewayCatalogField(name: "banner", optional: true, nullable: true, array: false), GatewayCatalogField(name: "roles", optional: true, nullable: false, array: true), GatewayCatalogField(name: "joined_at", optional: true, nullable: true, array: false), GatewayCatalogField(name: "premium_since", optional: true, nullable: true, array: false), GatewayCatalogField(name: "deaf", optional: true, nullable: false, array: false), GatewayCatalogField(name: "mute", optional: true, nullable: false, array: false), GatewayCatalogField(name: "flags", optional: true, nullable: false, array: false), GatewayCatalogField(name: "pending", optional: true, nullable: false, array: false), GatewayCatalogField(name: "permissions", optional: true, nullable: false, array: false), GatewayCatalogField(name: "communication_disabled_until", optional: true, nullable: true, array: false), GatewayCatalogField(name: "avatar_decoration_data", optional: true, nullable: true, array: false), GatewayCatalogField(name: "collectibles", optional: true, nullable: true, array: false)],
             parse: { try GatewayPartialGuildMember(data: $0, limits: $1) },
             project: { try GatewayPartialGuildMember(value: $0, limits: $1) }),
        Self(name: "GatewayMessageUpdate", source: sources["GatewayMessageUpdate"]!,
             fields: [GatewayCatalogField(name: "id", optional: false, nullable: false, array: false), GatewayCatalogField(name: "channel_id", optional: false, nullable: false, array: false), GatewayCatalogField(name: "author", optional: true, nullable: false, array: false), GatewayCatalogField(name: "content", optional: true, nullable: false, array: false), GatewayCatalogField(name: "timestamp", optional: true, nullable: false, array: false), GatewayCatalogField(name: "edited_timestamp", optional: true, nullable: true, array: false), GatewayCatalogField(name: "tts", optional: true, nullable: false, array: false), GatewayCatalogField(name: "mention_everyone", optional: true, nullable: false, array: false), GatewayCatalogField(name: "mentions", optional: true, nullable: false, array: true), GatewayCatalogField(name: "mention_roles", optional: true, nullable: false, array: true), GatewayCatalogField(name: "mention_channels", optional: true, nullable: false, array: true), GatewayCatalogField(name: "attachments", optional: true, nullable: false, array: true), GatewayCatalogField(name: "embeds", optional: true, nullable: false, array: true), GatewayCatalogField(name: "reactions", optional: true, nullable: false, array: true), GatewayCatalogField(name: "pinned", optional: true, nullable: false, array: false), GatewayCatalogField(name: "webhook_id", optional: true, nullable: false, array: false), GatewayCatalogField(name: "type", optional: true, nullable: false, array: false), GatewayCatalogField(name: "activity", optional: true, nullable: false, array: false), GatewayCatalogField(name: "application", optional: true, nullable: false, array: false), GatewayCatalogField(name: "application_id", optional: true, nullable: false, array: false), GatewayCatalogField(name: "flags", optional: true, nullable: false, array: false), GatewayCatalogField(name: "message_reference", optional: true, nullable: false, array: false), GatewayCatalogField(name: "message_snapshots", optional: true, nullable: false, array: true), GatewayCatalogField(name: "interaction_metadata", optional: true, nullable: false, array: false), GatewayCatalogField(name: "interaction", optional: true, nullable: false, array: false), GatewayCatalogField(name: "thread", optional: true, nullable: false, array: false), GatewayCatalogField(name: "components", optional: true, nullable: false, array: true), GatewayCatalogField(name: "sticker_items", optional: true, nullable: false, array: true), GatewayCatalogField(name: "stickers", optional: true, nullable: false, array: true), GatewayCatalogField(name: "position", optional: true, nullable: false, array: false), GatewayCatalogField(name: "role_subscription_data", optional: true, nullable: false, array: false), GatewayCatalogField(name: "resolved", optional: true, nullable: false, array: false), GatewayCatalogField(name: "poll", optional: true, nullable: false, array: false), GatewayCatalogField(name: "call", optional: true, nullable: false, array: false), GatewayCatalogField(name: "shared_client_theme", optional: true, nullable: false, array: false), GatewayCatalogField(name: "nonce", optional: true, nullable: false, array: false), GatewayCatalogField(name: "referenced_message", optional: true, nullable: true, array: false), GatewayCatalogField(name: "guild_id", optional: true, nullable: false, array: false), GatewayCatalogField(name: "member", optional: true, nullable: false, array: false), GatewayCatalogField(name: "channel_type", optional: true, nullable: false, array: false)],
             parse: { try GatewayMessageUpdate(data: $0, limits: $1) },
             project: { try GatewayMessageUpdate(value: $0, limits: $1) }),
    ]
}
