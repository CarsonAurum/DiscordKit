// File: Tests/DiscordModelsTests/GuildTemplateTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import Foundation
import Testing
@testable import DiscordModels

/// Offline template schemas exercise written snapshots, preview supplements and exact placeholder identities.
@Suite struct GuildTemplateTests {
    /// Complete typed projections retain every written field and typed optional snapshot supplements.
    /// - Throws: Unexpected parsing or fixture projection errors fail this test.
    @Test func completeTemplateSnapshot() throws {
        let value = try GuildTemplate(data: Data(Self.template.utf8))
        #expect(value.code == "secret-code")
        #expect(value.name == "private-name")
        #expect(value.templateDescription == .null)
        #expect(value.usageCount == 10)
        #expect(value.creatorID.rawValue == .max)
        #expect(value.creator.id == value.creatorID)
        #expect(value.createdAt.rawValue == "2026-10-16T10:00:00Z")
        #expect(value.updatedAt.rawValue == "2026-10-16T11:00:00Z")
        #expect(value.sourceGuildID.rawValue == .max)
        #expect(value.isDirty == .null)
        let guild = value.serializedSourceGuild
        #expect(guild.name == .value("private-guild"))
        #expect(guild.snapshotDescription == .null)
        #expect(guild.region == .value("us-west"))
        #expect(guild.verificationLevel == .value(.init(rawValue: 0)))
        #expect(guild.defaultMessageNotifications == .value(.init(rawValue: 0)))
        #expect(guild.explicitContentFilter == .value(.init(rawValue: 0)))
        #expect(guild.preferredLocale == .value("en-US"))
        #expect(guild.afkChannelID == .null)
        #expect(guild.afkTimeout == .value(300))
        #expect(guild.systemChannelID == .value(.placeholder(1)))
        #expect(guild.systemChannelFlags == .value(0))
        #expect(guild.iconHash == .null)
        guard case .value(let roles) = guild.roles, case .value(let channels) = guild.channels else {
            Issue.record("Expected snapshot role and channel arrays"); return
        }
        let role = try #require(roles.first)
        #expect(role.id == 0)
        #expect(role.name == "@everyone")
        #expect(role.permissions == "104324689")
        #expect(role.color == 0)
        #expect(role.hoist == false)
        #expect(role.mentionable == true)
        #expect(role.icon == .null)
        #expect(role.unicodeEmoji == .value("🌲"))
        guard case .value(let colors) = role.colors else { Issue.record("Expected colors"); return }
        #expect(colors.primaryColor == 1)
        #expect(colors.secondaryColor == .null)
        #expect(colors.tertiaryColor == .value(2))
        let channel = try #require(channels.first)
        #expect(channel.id == .value(1))
        #expect(channel.type.knownValue == .guildForum)
        #expect(channel.name == .value("forum"))
        #expect(channel.position == .value(1))
        #expect(channel.topic == .null)
        #expect(channel.bitrate == .value(64_000))
        #expect(channel.userLimit == .value(0))
        #expect(channel.nsfw == .value(false))
        #expect(channel.rateLimitPerUser == .value(0))
        #expect(channel.parentID == .value(.placeholder(0)))
        #expect(channel.defaultAutoArchiveDuration == .null)
        #expect(channel.template == .value("snapshot"))
        #expect(channel.defaultThreadRateLimitPerUser == .null)
        #expect(channel.defaultSortOrder == .value(.init(rawValue: 0)))
        #expect(channel.defaultForumLayout == .value(.init(rawValue: 1)))
        #expect(channel.defaultTagSetting == .value("match_all"))
        #expect(channel.themeColor == .null)
        guard case .value(let overwrites) = channel.permissionOverwrites,
              case .value(let tags) = channel.availableTags,
              case .value(let reaction) = channel.defaultReactionEmoji else {
            Issue.record("Expected typed nested preview projections"); return
        }
        #expect(overwrites.first?.id == .placeholder(0))
        #expect(overwrites.first?.type.knownValue == .role)
        #expect(overwrites.first?.allow == "184467440737095516160000")
        #expect(overwrites.first?.deny == "0")
        #expect(tags.first?.id == .value(0))
        #expect(tags.first?.name == "tag")
        #expect(tags.first?.emojiID == .null)
        #expect(tags.first?.emojiName == .value("🌲"))
        #expect(tags.first?.moderated == .value(false))
        #expect(reaction.emojiName == .value("🌲"))
        #expect(try GuildTemplateSnapshot(data: Data("{}".utf8)).name == .absent)
    }

    /// Every modeled field checks required/optional, nullability and wrong types independently.
    /// Empty partial snapshots remain valid; all required template fields remain required.
    /// - Throws: Unexpected trusted fixture serialization fails this test.
    @Test func fieldContracts() throws {
        for (text, fields, parse) in Self.schemas {
            guard case .object(let fixture) = try JSONValue.parse(text) else { Issue.record("Expected object"); continue }
            for (key, optional, nullable) in fields {
                var changed = fixture
                changed[key] = nil
                let missing = try JSONValue.object(changed).serialized()
                if optional { #expect(try parse(missing, .default).rawFields[key] == nil) }
                else { #expect(throws: DiscordError.transport(.invalidResponse)) { try parse(missing, .default) } }
                changed[key] = .null
                let null = try JSONValue.object(changed).serialized()
                if nullable { #expect(try parse(null, .default).rawFields[key] == .null) }
                else { #expect(throws: DiscordError.transport(.invalidResponse)) { try parse(null, .default) } }
                changed[key] = .bool(true)
                if key == "is_dirty" || key == "hoist" || key == "mentionable" || key == "moderated" || key == "nsfw" {
                    changed[key] = .string("true")
                }
                #expect(throws: DiscordError.transport(.invalidResponse)) { try parse(JSONValue.object(changed).serialized(), .default) }
            }
            for bad in ["null", "[]", "true", "1", "\"x\""] {
                #expect(throws: DiscordError.transport(.invalidResponse)) { try parse(Data(bad.utf8), .default) }
            }
        }
    }

    /// Placeholder references preserve both official forms, reject unsafe values and retain unknown variants.
    /// Integer permission tokens never round or truncate to UInt64, while decimal strings remain exact.
    /// - Throws: Unexpected trusted fixture mutation/parse errors fail this test.
    @Test func exactIdentifiersPermissionsAndFutureValues() throws {
        for token in ["-1", String(Int.min), "0", String(Int.max), "\"18446744073709551615\""] {
            let value = try GuildTemplateSnapshot(data: Data(("{\"system_channel_id\":" + token + "}").utf8))
            let expected: GuildTemplateReference = token.first == "\"" ? .snowflake("18446744073709551615") : .placeholder(Int(token)!)
            #expect(value.systemChannelID == .value(expected))
        }
        for token in ["1.0", "1e0", "18446744073709551616", "\"01\"", "\"invalid\"", "[]", "{}", "false"] {
            #expect(throws: DiscordError.transport(.invalidResponse)) {
                try GuildTemplateSnapshot(data: Data(("{\"system_channel_id\":" + token + "}").utf8))
            }
        }
        let role = try GuildTemplateRole(data: Data(Self.role.utf8))
        for token in ["0", "184467440737095516160000000000000000000000", "\"184467440737095516160000000000000000000000\""] {
            var fields = role.rawFields
            fields["permissions"] = try JSONValue.parse(token)
            fields["id"] = .number(try JSONNumber(rawValue: String(Int.max)))
            let parsed = try GuildTemplateRole(value: .object(fields), limits: .default)
            #expect(parsed.id == .max)
            #expect(parsed.permissions == token.replacingOccurrences(of: "\"", with: ""))
            #expect(parsed.rawFields["permissions"] == fields["permissions"])
        }
        for token in ["-1", "1.5", "1e4", "\"+1\"", "\"1.2\"", "\"\""] {
            var fields = role.rawFields; fields["permissions"] = try JSONValue.parse(token)
            #expect(throws: DiscordError.transport(.invalidResponse)) { try GuildTemplateRole(value: .object(fields), limits: .default) }
        }
        let channel = try GuildTemplateChannel(data: Data(Self.channel.utf8))
        var fields = channel.rawFields
        fields["type"] = .number(try JSONNumber(rawValue: "999"))
        fields["default_sort_order"] = .number(try JSONNumber(rawValue: "999"))
        fields["default_forum_layout"] = .number(try JSONNumber(rawValue: "999"))
        fields["default_tag_setting"] = .string("future")
        let future = try GuildTemplateChannel(value: .object(fields), limits: .default)
        #expect(future.type.rawValue == 999 && future.type.knownValue == nil)
        #expect(future.defaultSortOrder == .value(.init(rawValue: 999)))
        #expect(future.defaultForumLayout == .value(.init(rawValue: 999)))
        #expect(future.defaultTagSetting == .value("future"))
    }

    /// Whole-document parser limits include unknown subtrees and diagnostics conceal codes, users and snapshots.
    /// - Throws: Unexpected trusted fixture errors fail this test; intentional bounds/syntax failures are asserted.
    @Test func boundsUnknownFieldsAndRedaction() throws {
        for (text, _, parse) in Self.schemas {
            guard case .object(var fields) = try JSONValue.parse(text) else { Issue.record("Expected object"); continue }
            let exact = try JSONValue.parse("{\"future\":1.2300e+100}")
            fields["unknown"] = exact
            let bytes = try JSONValue.object(fields).serialized()
            let value = try parse(bytes, .default)
            #expect(value.rawFields["unknown"] == exact)
            #expect(value.jsonValue() == .object(fields))
            #expect(value.description == value.debugDescription)
            #expect(!String(reflecting: value).contains("private"))
            #expect(!String(describing: value).contains("secret-code"))
            #expect(value.customMirror.children.count == 1)
            #expect(throws: (any Error).self) { try parse(bytes, JSONLimits(maximumBytes: bytes.count - 1)) }
            #expect(throws: (any Error).self) { try parse(bytes, JSONLimits(maximumDepth: 1)) }
            #expect(throws: (any Error).self) { try parse(bytes, JSONLimits(maximumNodes: 1)) }
            #expect(throws: (any Error).self) { try parse(Data("{\"id\":0,\"id\":0}".utf8), .default) }
        }
    }

    /// Names and descriptions enforce inclusive Unicode-scalar bounds while retaining omission, null and empty.
    /// - Throws: Unexpected legal request encoding fails this test; invalid boundaries are asserted.
    @Test func requestMetadataBoundaries() throws {
        for name in ["a", String(repeating: "a", count: 100), String(repeating: "🌲", count: 100)] {
            let create = try GuildTemplateCreate(name: name, description: .null)
            #expect(create.jsonValue() == .object(["name": .string(name), "description": .null]))
            let modify = try GuildTemplateModify(name: .value(name), description: .value(""))
            #expect(modify.jsonValue() == .object(["name": .string(name), "description": .string("")]))
            #expect(!String(reflecting: create).contains(name + "\""))
            #expect(create.description == create.debugDescription)
            #expect(create.customMirror.children.count == 1)
            #expect(modify.description == modify.debugDescription)
            #expect(modify.customMirror.children.count == 1)
        }
        #expect(try GuildTemplateCreate(name: "a").jsonValue() == .object(["name": .string("a")]))
        #expect(try GuildTemplateModify().jsonValue() == .object([:]))
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildTemplateModify(name: .null) }
        for name in ["", String(repeating: "a", count: 101)] {
            #expect(throws: DiscordError.validation(.invalidValue)) { try GuildTemplateCreate(name: name) }
            #expect(throws: DiscordError.validation(.invalidValue)) { try GuildTemplateModify(name: .value(name)) }
        }
        for description in ["", String(repeating: "🌲", count: 120)] {
            #expect(try GuildTemplateCreate(name: "a", description: .value(description)).jsonValue() == .object(["name": .string("a"), "description": .string(description)]))
            #expect(try GuildTemplateModify(description: .value(description)).jsonValue() == .object(["description": .string(description)]))
        }
        #expect(try GuildTemplateModify(description: .null).jsonValue() == .object(["description": .null]))
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildTemplateCreate(name: "a", description: .value(String(repeating: "a", count: 121))) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildTemplateModify(description: .value(String(repeating: "a", count: 121))) }
    }

    /// Complete offline GuildTemplate fixture, containing written values and optional preview supplements.
    static let template = #"{"code":"secret-code","name":"private-name","description":null,"usage_count":10,"creator_id":"18446744073709551615","creator":{"id":"18446744073709551615","username":"private-user","discriminator":"0","avatar":null},"created_at":"2026-10-16T10:00:00Z","updated_at":"2026-10-16T11:00:00Z","source_guild_id":"18446744073709551615","serialized_source_guild":{"name":"private-guild","description":null,"region":"us-west","verification_level":0,"default_message_notifications":0,"explicit_content_filter":0,"preferred_locale":"en-US","afk_channel_id":null,"afk_timeout":300,"system_channel_id":1,"system_channel_flags":0,"roles":[{"id":0,"name":"@everyone","permissions":104324689,"color":0,"colors":{"primary_color":1,"secondary_color":null,"tertiary_color":2},"hoist":false,"mentionable":true,"icon":null,"unicode_emoji":"🌲"}],"channels":[{"id":1,"type":15,"name":"forum","position":1,"topic":null,"bitrate":64000,"user_limit":0,"nsfw":false,"rate_limit_per_user":0,"parent_id":0,"default_auto_archive_duration":null,"permission_overwrites":[{"id":0,"type":0,"allow":"184467440737095516160000","deny":0}],"available_tags":[{"id":0,"name":"tag","emoji_id":null,"emoji_name":"🌲","moderated":false}],"template":"snapshot","default_reaction_emoji":{"emoji_id":null,"emoji_name":"🌲"},"default_thread_rate_limit_per_user":null,"default_sort_order":0,"default_forum_layout":1,"default_tag_setting":"match_all","theme_color":null}],"icon_hash":null},"is_dirty":null}"#

    /// Complete offline GuildTemplateSnapshot fixture, containing written values and optional preview supplements.
    static let snapshot = #"{"name":"private-guild","description":null,"region":"us-west","verification_level":0,"default_message_notifications":0,"explicit_content_filter":0,"preferred_locale":"en-US","afk_channel_id":null,"afk_timeout":300,"system_channel_id":1,"system_channel_flags":0,"roles":[{"id":0,"name":"@everyone","permissions":104324689,"color":0,"colors":{"primary_color":1,"secondary_color":null,"tertiary_color":2},"hoist":false,"mentionable":true,"icon":null,"unicode_emoji":"🌲"}],"channels":[{"id":1,"type":15,"name":"forum","position":1,"topic":null,"bitrate":64000,"user_limit":0,"nsfw":false,"rate_limit_per_user":0,"parent_id":0,"default_auto_archive_duration":null,"permission_overwrites":[{"id":0,"type":0,"allow":"184467440737095516160000","deny":0}],"available_tags":[{"id":0,"name":"tag","emoji_id":null,"emoji_name":"🌲","moderated":false}],"template":"snapshot","default_reaction_emoji":{"emoji_id":null,"emoji_name":"🌲"},"default_thread_rate_limit_per_user":null,"default_sort_order":0,"default_forum_layout":1,"default_tag_setting":"match_all","theme_color":null}],"icon_hash":null}"#

    /// Complete offline GuildTemplateRole fixture, containing written values and optional preview supplements.
    static let role = #"{"id":0,"name":"@everyone","permissions":104324689,"color":0,"colors":{"primary_color":1,"secondary_color":null,"tertiary_color":2},"hoist":false,"mentionable":true,"icon":null,"unicode_emoji":"🌲"}"#

    /// Complete offline GuildTemplateChannel fixture, containing written values and optional preview supplements.
    static let channel = #"{"id":1,"type":15,"name":"forum","position":1,"topic":null,"bitrate":64000,"user_limit":0,"nsfw":false,"rate_limit_per_user":0,"parent_id":0,"default_auto_archive_duration":null,"permission_overwrites":[{"id":0,"type":0,"allow":"184467440737095516160000","deny":0}],"available_tags":[{"id":0,"name":"tag","emoji_id":null,"emoji_name":"🌲","moderated":false}],"template":"snapshot","default_reaction_emoji":{"emoji_id":null,"emoji_name":"🌲"},"default_thread_rate_limit_per_user":null,"default_sort_order":0,"default_forum_layout":1,"default_tag_setting":"match_all","theme_color":null}"#

    /// Complete offline GuildTemplateOverwrite fixture, containing written values and optional preview supplements.
    static let overwrite = #"{"id":0,"type":0,"allow":"184467440737095516160000","deny":0}"#

    /// Complete offline GuildTemplateTag fixture, containing written values and optional preview supplements.
    static let tag = #"{"id":0,"name":"tag","emoji_id":null,"emoji_name":"🌲","moderated":false}"#

    /// Per-field presence contracts and original decoders used for exhaustive malformed-input checks.
    static let schemas: [(String, [(String, Bool, Bool)], @Sendable (Data, JSONLimits) throws -> any MessageResponseValue)] = [
        (template, [("code", false, false),("name", false, false),("description", false, true),("usage_count", false, false),("creator_id", false, false),("creator", false, false),("created_at", false, false),("updated_at", false, false),("source_guild_id", false, false),("serialized_source_guild", false, false),("is_dirty", false, true)], { try GuildTemplate(data: $0, limits: $1) }),
        (snapshot, [("name", true, false),("description", true, true),("region", true, true),("verification_level", true, false),("default_message_notifications", true, false),("explicit_content_filter", true, false),("preferred_locale", true, false),("afk_channel_id", true, true),("afk_timeout", true, false),("system_channel_id", true, true),("system_channel_flags", true, false),("roles", true, false),("channels", true, false),("icon_hash", true, true)], { try GuildTemplateSnapshot(data: $0, limits: $1) }),
        (role, [("id", false, false),("name", false, false),("permissions", false, false),("color", false, false),("colors", true, true),("hoist", false, false),("mentionable", false, false),("icon", true, true),("unicode_emoji", true, true)], { try GuildTemplateRole(data: $0, limits: $1) }),
        (channel, [("id", false, true),("type", false, false),("name", true, true),("position", true, true),("topic", true, true),("bitrate", true, false),("user_limit", true, false),("nsfw", true, false),("rate_limit_per_user", true, false),("parent_id", true, true),("default_auto_archive_duration", true, true),("permission_overwrites", true, false),("available_tags", true, true),("template", true, false),("default_reaction_emoji", true, true),("default_thread_rate_limit_per_user", true, true),("default_sort_order", true, true),("default_forum_layout", true, true),("default_tag_setting", true, true),("theme_color", true, true)], { try GuildTemplateChannel(data: $0, limits: $1) }),
        (overwrite, [("id", false, false),("type", false, false),("allow", false, false),("deny", false, false)], { try GuildTemplateOverwrite(data: $0, limits: $1) }),
        (tag, [("id", false, true),("name", false, false),("emoji_id", false, true),("emoji_name", false, true),("moderated", false, true)], { try GuildTemplateTag(data: $0, limits: $1) }),
    ]
}
