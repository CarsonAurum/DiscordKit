// File: Tests/DiscordModelsTests/InviteModelTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import Foundation
import Testing
@testable import DiscordModels

/// Complete invite-owned model fixtures cover current fields, strict scalar contracts and exact future-data retention.
@Suite struct InviteModelTests {
    /// All six required job fields preserve explicit null, maximum counters, terminal/future statuses and redaction.
    /// - Parameter status: Every known status plus an unknown future integral value.
    /// - Throws: Unexpected bounded parser/schema errors fail the test.
    @Test(arguments: [0, 1, 2, 3, 999]) func jobFields(status: Int) throws {
        let data = Data("{\"status\":\(status),\"total_users\":4294967295,\"processed_users\":4294967295,\"created_at\":null,\"completed_at\":null,\"error_message\":\"private-message\",\"future\":1.2300e1000}".utf8)
        let job = try InviteTargetUsersJob(data: data)
        #expect(job.status.rawValue == status)
        #expect(job.status.knownValue == InviteTargetUsersJobStatus(rawValue: status))
        #expect(job.totalUsers == UInt32.max && job.processedUsers == UInt32.max)
        #expect(job.createdAt == .null && job.completedAt == .null && job.errorMessage == .value("private-message"))
        #expect(job.rawFields["future"] == .number(try JSONNumber(rawValue: "1.2300e1000")))
        #expect(try job.jsonValue().serialized() == JSONValue.parse(data).serialized())
        #expect(!String(reflecting: job).contains("private-message"))
        #expect(!String(describing: job).contains("private-message"))
        #expect(Mirror(reflecting: job).children.count == 1)
        let dated = try InviteTargetUsersJob(data: Data(Self.jobJSON.utf8))
        #expect(dated.status.knownValue == .completed && dated.totalUsers == 0 && dated.processedUsers == 0)
        if case .value(let date) = dated.createdAt { #expect(date.nanosecond == 123_456_789) }
        else { Issue.record("Expected nonnull creation timestamp") }
        #expect(dated.completedAt != .null && dated.errorMessage == .null)
    }

    /// Every required job field rejects omission; nullable fields accept only their documented scalar alternatives.
    /// - Parameter patch: One malformed, forbidden-null, fractional, overflowing, or mistyped job field.
    /// - Throws: Unexpected fixture/parser errors fail the test; schema errors are asserted locally.
    @Test(arguments: [#""status":null"#, #""status":1e0"#, #""status":"2""#, #""total_users":null"#,
                      #""total_users":-1"#, #""total_users":4294967296"#, #""total_users":0.0"#,
                      #""processed_users":-1"#, #""processed_users":"0""#, #""processed_users":4294967296"#,
                      #""created_at":false"#, #""created_at":"bad""#, #""completed_at":1"#, #""error_message":[]"#])
    func malformedJobs(patch: String) throws {
        var fields = try Self.object(Self.jobJSON)
        fields.merge(try Self.object("{" + patch + "}")) { _, replacement in replacement }
        #expect(throws: DiscordError.transport(.invalidResponse)) { try InviteTargetUsersJob(data: JSONValue.object(fields).serialized()) }
        for key in ["status", "total_users", "processed_users", "created_at", "completed_at", "error_message"] {
            var missing = try Self.object(Self.jobJSON)
            missing.removeValue(forKey: key)
            #expect(throws: DiscordError.transport(.invalidResponse)) { try InviteTargetUsersJob(data: JSONValue.object(missing).serialized()) }
        }
    }

    /// Partial guild and role objects project every documented embedded field without requiring unrelated full resources.
    /// - Throws: Unexpected fixture/model/parser errors fail the test.
    @Test func partialGuildAndRoleFields() throws {
        let guild = try ChannelInviteGuild(data: Data(Self.guildJSON.utf8))
        #expect(guild.id.rawValue == UInt64.max && guild.name == .value("private-guild"))
        #expect(guild.splash == .null && guild.banner == .value("banner") && guild.guildDescription == .null)
        #expect(guild.icon == .null && guild.features == .value(["UNKNOWN_FUTURE_FEATURE"]))
        #expect(guild.verificationLevel == .null && guild.vanityURLCode == .null && guild.nsfwLevel == .value(999))
        #expect(guild.nsfw == .null && guild.premiumSubscriptionCount == .value(7))
        #expect(guild.rawFields["future"] == .number(try JSONNumber(rawValue: "1e1000")))
        let role = try ChannelInviteRole(data: Data(Self.roleJSON.utf8))
        #expect(role.id.rawValue == UInt64.max && role.name == .value("private-role"))
        #expect(role.position == .value(3) && role.color == .value(0xFFFFFF))
        if case .value(let colors) = role.colors { #expect(colors.primaryColor == 0 && colors.secondaryColor == .null && colors.tertiaryColor == .null) }
        else { Issue.record("Expected projected role colors") }
        #expect(role.icon == .null && role.unicodeEmoji == .value("🔥"))
        #expect(role.permissions == .value("1844674407370955161618446744073709551616"))
        #expect(role.rawFields["future"] == .number(try JSONNumber(rawValue: "1.2300")))
        for value in [guild.description, guild.debugDescription, role.description, role.debugDescription] { #expect(!value.contains("private")) }
        #expect(guild.customMirror.children.count == 1 && role.customMirror.children.count == 1)
        let partialGuild = try ChannelInviteGuild(data: Data(#"{"id":"1"}"#.utf8))
        #expect(partialGuild.name == .absent && partialGuild.banner == .absent && partialGuild.nsfw == .absent)
        let partialRole = try ChannelInviteRole(data: Data(#"{"id":"2"}"#.utf8))
        #expect(partialRole.colors == .absent && partialRole.permissions == .absent && partialRole.icon == .absent)
        let invite = try ChannelInvite(data: Data(("{\"type\":0,\"code\":\"secret-code\",\"channel\":null,\"expires_at\":null,\"guild\":" + Self.guildJSON + ",\"roles\":[" + Self.roleJSON + "],\"guild_id\":\"18446744073709551615\",\"target_channel_id\":\"18446744073709551615\",\"target_message_id\":\"18446744073709551615\",\"is_contact\":false,\"is_nickname_changeable\":true,\"friends_count\":0}").utf8))
        #expect(invite.guild == .value(guild) && invite.roles == .value([role]))
        #expect(invite.guildID == .value(.init(rawValue: UInt64.max)))
        #expect(invite.targetChannelID == .value(.init(rawValue: UInt64.max)) && invite.targetMessageID == .value(.init(rawValue: UInt64.max)))
        #expect(invite.isContact == .value(false) && invite.isNicknameChangeable == .value(true) && invite.friendsCount == .value(0))
        #expect(invite.guildScheduledEvent == .absent)
    }

    /// Embedded partial fields reject malformed known data while omissions and supported null variants remain intact.
    /// - Throws: Unexpected fixture/model/parser errors fail the test.
    @Test func malformedPartialFields() throws {
        for patch in [#""id":null"#, #""id":1"#, #""name":null"#, #""features":null"#,
                      #""features":[1]"#, #""splash":3"#, #""description":[]"#, #""nsfw":0"#,
                      #""verification_level":1e0"#, #""premium_subscription_count":null"#] {
            var fields = try Self.object(Self.guildJSON)
            fields.merge(try Self.object("{" + patch + "}")) { _, value in value }
            #expect(throws: DiscordError.transport(.invalidResponse)) { try ChannelInviteGuild(data: JSONValue.object(fields).serialized()) }
        }
        for patch in [#""id":null"#, #""name":null"#, #""position":"3""#, #""color":1.0"#,
                      #""colors":null"#, #""colors":{}"#, #""icon":false"#, #""unicode_emoji":[]"#,
                      #""permissions":"-1""#, #""permissions":"""#] {
            var fields = try Self.object(Self.roleJSON)
            fields.merge(try Self.object("{" + patch + "}")) { _, value in value }
            #expect(throws: DiscordError.transport(.invalidResponse)) { try ChannelInviteRole(data: JSONValue.object(fields).serialized()) }
        }
        for patch in [#""guild_id":null"#, #""target_channel_id":1"#, #""target_message_id":"-1""#,
                      #""is_contact":null"#, #""is_nickname_changeable":0"#, #""friends_count":-1"#,
                      #""guild_scheduled_event":{"id":"1"}"#] {
            var fields = try Self.object(#"{"type":0,"code":"c","channel":null,"expires_at":null}"#)
            fields.merge(try Self.object("{" + patch + "}")) { _, value in value }
            #expect(throws: DiscordError.transport(.invalidResponse)) { try ChannelInvite(data: JSONValue.object(fields).serialized()) }
        }
    }

    /// Public model initializers apply whole-document bounds and reject invalid roots/missing IDs without leaking contents.
    /// - Throws: Unexpected fixture construction errors fail the test.
    @Test func boundsRootsAndRoundTrips() throws {
        let initializers: [(Data, JSONLimits) throws -> JSONValue] = [
            { try InviteTargetUsersJob(data: $0, limits: $1).jsonValue() },
            { try ChannelInviteGuild(data: $0, limits: $1).jsonValue() },
            { try ChannelInviteRole(data: $0, limits: $1).jsonValue() },
        ]
        for (index, initialize) in initializers.enumerated() {
            let data = Data([Self.jobJSON, Self.guildJSON, Self.roleJSON][index].utf8)
            #expect(try initialize(data, .default) == JSONValue.parse(data))
            for bad in ["{}", "null", "[]", "true", "1"] {
                #expect(throws: DiscordError.transport(.invalidResponse)) { try initialize(Data(bad.utf8), .default) }
            }
            #expect(throws: JSONValueError.maximumBytesExceeded) { try initialize(data, JSONLimits(maximumBytes: 1)) }
            #expect(throws: JSONValueError.maximumNodesExceeded) { try initialize(data, JSONLimits(maximumNodes: 1)) }
            #expect(throws: JSONValueError.self) { try initialize(Data("{".utf8), .default) }
        }
        let nested = Data(#"{"id":"1","future":{"nested":{"value":1}}}"#.utf8)
        #expect(throws: JSONValueError.maximumDepthExceeded) { try ChannelInviteGuild(data: nested, limits: JSONLimits(maximumDepth: 1)) }
        #expect(throws: JSONValueError.maximumDepthExceeded) { try ChannelInviteRole(data: nested, limits: JSONLimits(maximumDepth: 1)) }
    }

    /// Parses a trusted independent fixture as mutable fields for one-field malformed variants.
    /// - Parameter source: Complete UTF-8 JSON object fixture.
    /// - Returns: Exact fields; nonobject fixtures fail the test through require.
    /// - Throws: Bounded parser or test assertion failure for invalid local fixture data.
    private static func object(_ source: String) throws -> [String: JSONValue] {
        guard case .object(let fields) = try JSONValue.parse(source) else { throw DiscordError.validation(.invalidValue) }
        return fields
    }

    static let jobJSON = #"{"status":2,"total_users":0,"processed_users":0,"created_at":"2026-10-16T12:00:00.123456789Z","completed_at":"2026-10-16T12:00:01Z","error_message":null}"#
    static let guildJSON = #"{"id":"18446744073709551615","name":"private-guild","splash":null,"banner":"banner","description":null,"icon":null,"features":["UNKNOWN_FUTURE_FEATURE"],"verification_level":null,"vanity_url_code":null,"nsfw_level":999,"nsfw":null,"premium_subscription_count":7,"future":1e1000}"#
    static let roleJSON = #"{"id":"18446744073709551615","name":"private-role","position":3,"color":16777215,"colors":{"primary_color":0,"secondary_color":null,"tertiary_color":null},"icon":null,"unicode_emoji":"🔥","permissions":"1844674407370955161618446744073709551616","future":1.2300}"#
}
