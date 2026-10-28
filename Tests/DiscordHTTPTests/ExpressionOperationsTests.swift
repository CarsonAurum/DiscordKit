// File: Tests/DiscordHTTPTests/ExpressionOperationsTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import DiscordModels
import DiscordTestSupport
import DiscordTransport
import Foundation
import Testing
@testable import DiscordHTTP

/// Presence-aware explicit request reduction over caller snapshots, with no hidden execution or hydration.
@Suite struct ExpressionOperationsTests {
    /// All four public no-op helpers avoid actual transport calls; changed snapshots execute exactly one PATCH apiece.
    /// Every emitted body matches the validated request and no permission, uploader or media hydration occurs.
    /// - Throws: Unexpected fixture/request/descriptor or real policy execution errors fail this test.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func noOpAndChangedRequestCounts() async throws {
        let guild = GuildID(rawValue: UInt64.max), app = ApplicationID(rawValue: UInt64.max)
        let emoji = try Emoji(data: Data(ExpressionEndpointTests.emojiJSON.utf8))
        let sticker = try Sticker(data: Data(ExpressionEndpointTests.stickerJSON.utf8))
        let sound = try SoundboardSound(data: Data(ExpressionEndpointTests.soundJSON.utf8))
        let noOps: [Endpoint<Data>?] = [
            try EmojiOperations.modifyGuildIfChanged(guildID: guild, current: emoji,
                request: GuildEmojiModify(name: .value("fixture"))).map { try ExpressionEndpointTests.erase($0) },
            try EmojiOperations.modifyApplicationIfChanged(applicationID: app, current: emoji,
                request: ApplicationEmojiModify(name: "fixture")).map { try ExpressionEndpointTests.erase($0) },
            try EmojiOperations.modifyApplicationIfChanged(applicationID: app, current: emoji,
                request: ApplicationEmojiModify()).map { try ExpressionEndpointTests.erase($0) },
            try StickerOperations.modifyGuildIfChanged(guildID: guild, current: sticker,
                request: GuildStickerModify(description: .null)).map { try ExpressionEndpointTests.erase($0) },
            try SoundboardOperations.modifyGuildIfChanged(guildID: guild, current: sound,
                request: GuildSoundboardSoundModify(volume: .value(0.5))).map { try ExpressionEndpointTests.erase($0) },
        ]
        let renamed = JSONValue.object(["name": .string("renamed")])
        let mutations: [(Endpoint<Data>, Data)] = [
            (try ExpressionEndpointTests.erase(#require(try EmojiOperations.modifyGuildIfChanged(guildID: guild, current: emoji,
                request: GuildEmojiModify(name: .value("renamed"))))), Data(ExpressionEndpointTests.emojiJSON.utf8)),
            (try ExpressionEndpointTests.erase(#require(try EmojiOperations.modifyApplicationIfChanged(applicationID: app, current: emoji,
                request: ApplicationEmojiModify(name: "renamed")))), Data(ExpressionEndpointTests.emojiJSON.utf8)),
            (try ExpressionEndpointTests.erase(#require(try StickerOperations.modifyGuildIfChanged(guildID: guild, current: sticker,
                request: GuildStickerModify(name: .value("renamed"))))), Data(ExpressionEndpointTests.stickerJSON.utf8)),
            (try ExpressionEndpointTests.erase(#require(try SoundboardOperations.modifyGuildIfChanged(guildID: guild, current: sound,
                request: GuildSoundboardSoundModify(name: .value("renamed"))))), Data(ExpressionEndpointTests.soundJSON.utf8)),
        ]
        let steps: [ScriptedHTTPTransport.Step] = mutations.map { endpoint, bytes in
            { request in
                #expect(request.method == "PATCH")
                #expect(request.url.path == "/api/v10/" + endpoint.path.joined(separator: "/"))
                let body = try await ResponseBody.collect(request.body, maximumBytes: 1_048_576)
                #expect(try JSONValue.parse(body) == renamed)
                return HTTPResponse(status: 200, headers: [
                    HTTPHeader(name: "X-RateLimit-Limit", value: "100"),
                    HTTPHeader(name: "X-RateLimit-Remaining", value: "99"),
                    HTTPHeader(name: "X-RateLimit-Reset-After", value: "1")],
                    body: try RequestBody(bytes: bytes, contentType: "application/json").makeStream())
            }
        }
        let transport = try ScriptedHTTPTransport(steps: steps)
        let clock = ManualClock()
        let coordinator = RateLimitCoordinator(clock: clock)
        let client = RESTClient(credential: .bot(try BotToken("synthetic")), identity: RateLimitIdentity(),
            transport: transport, coordinator: coordinator, clock: clock, retryPolicy: .init(maximumAttempts: 1))
        for possible in noOps {
            #expect(possible == nil)
            if let endpoint = possible { _ = try await client.execute(endpoint) }
        }
        #expect(await transport.executionCount == 0)
        for (index, item) in mutations.enumerated() {
            #expect(try await client.execute(item.0) == item.1)
            #expect(await transport.executionCount == index + 1)
        }
        #expect(await coordinator.snapshot().activeCount == 0)
        #expect(await coordinator.snapshot().orderedOperationsCount == 0)
        #expect(clock.pendingSleepCount == 0)
        await coordinator.close()
    }

    /// Guild and application emoji no-op helpers compare explicit keys and reject Unicode/null-ID targets.
    /// - Throws: Unexpected request/model/descriptor errors fail this test.
    @Test func emojiReconciliation() throws {
        let guild = GuildID(rawValue: UInt64.max), app = ApplicationID(rawValue: UInt64.max)
        let current = try Emoji(data: Data(ExpressionEndpointTests.emojiJSON.utf8))
        #expect(try EmojiOperations.modifyGuildIfChanged(guildID: guild, current: current, request: GuildEmojiModify()) == nil)
        #expect(try EmojiOperations.modifyGuildIfChanged(guildID: guild, current: current,
            request: GuildEmojiModify(name: .value("fixture"), roles: .value([.init(rawValue: UInt64.max)])), auditReason: "\n") == nil)
        #expect(try EmojiOperations.modifyApplicationIfChanged(applicationID: app, current: current,
            request: ApplicationEmojiModify(name: "fixture")) == nil)
        #expect(try EmojiOperations.modifyApplicationIfChanged(applicationID: app, current: current,
            request: ApplicationEmojiModify()) == nil)
        for change in [try GuildEmojiModify(name: .value("renamed")), try GuildEmojiModify(roles: .null),
                       try GuildEmojiModify(roles: .value([]))] {
            let endpoint = try #require(try EmojiOperations.modifyGuildIfChanged(guildID: guild, current: current,
                request: change, auditReason: "why"))
            #expect(endpoint.path == ["guilds", guild.description, "emojis", "18446744073709551615"])
            #expect(endpoint.auditReason == "why")
            #expect(endpoint.retrySafety == .unsafe)
            #expect(try JSONValue.parse(#require(endpoint.body?.storedBodyBytes)) == change.jsonValue())
            #expect(throws: DiscordError.validation(.invalidValue)) {
                try EmojiOperations.modifyGuildIfChanged(guildID: guild, current: current, request: change, auditReason: "\n")
            }
        }
        let appRequest = try ApplicationEmojiModify(name: "renamed")
        let appEdit = try #require(try EmojiOperations.modifyApplicationIfChanged(applicationID: app, current: current, request: appRequest))
        #expect(appEdit.path == ["applications", app.description, "emojis", "18446744073709551615"])
        #expect(try JSONValue.parse(#require(appEdit.body?.storedBodyBytes)) == appRequest.jsonValue())
        let unicode = try Emoji(data: Data(#"{"id":null,"name":"🔥"}"#.utf8))
        #expect(throws: DiscordError.validation(.invalidValue)) {
            try EmojiOperations.modifyGuildIfChanged(guildID: guild, current: unicode, request: GuildEmojiModify())
        }
        #expect(throws: DiscordError.validation(.invalidValue)) {
            try EmojiOperations.modifyApplicationIfChanged(applicationID: app, current: unicode, request: ApplicationEmojiModify(name: "fixture"))
        }
        var raw = current.rawFields
        raw["roles"] = nil
        let missingRoles = try Emoji(data: JSONValue.object(raw).serialized())
        #expect(try EmojiOperations.modifyGuildIfChanged(guildID: guild, current: missingRoles, request: GuildEmojiModify(roles: .value([]))) != nil)
    }

    /// Sticker edits distinguish null/absent description and enforce the snapshot's guild/type context even for no-ops.
    /// - Throws: Unexpected fixture/request/descriptor errors fail this test.
    @Test func stickerReconciliation() throws {
        let guild = GuildID(rawValue: UInt64.max)
        let current = try Sticker(data: Data(ExpressionEndpointTests.stickerJSON.utf8))
        #expect(try StickerOperations.modifyGuildIfChanged(guildID: guild, current: current, request: GuildStickerModify()) == nil)
        #expect(try StickerOperations.modifyGuildIfChanged(guildID: guild, current: current,
            request: GuildStickerModify(name: .value("fixture"), description: .null, tags: .value("wave")), auditReason: "\n") == nil)
        for change in [try GuildStickerModify(name: .value("renamed")),
                       try GuildStickerModify(description: .value("changed")), try GuildStickerModify(tags: .value("new"))] {
            let endpoint = try #require(try StickerOperations.modifyGuildIfChanged(guildID: guild, current: current,
                request: change, auditReason: "why"))
            #expect(endpoint.path == ["guilds", guild.description, "stickers", current.id.description])
            #expect(endpoint.auditReason == "why")
            #expect(try JSONValue.parse(#require(endpoint.body?.storedBodyBytes)) == change.jsonValue())
            #expect(throws: DiscordError.validation(.invalidValue)) {
                try StickerOperations.modifyGuildIfChanged(guildID: guild, current: current, request: change, auditReason: "\n")
            }
        }
        #expect(throws: DiscordError.validation(.invalidValue)) {
            try StickerOperations.modifyGuildIfChanged(guildID: .init(rawValue: 1), current: current, request: GuildStickerModify())
        }
        for origin in [1, 999] {
            var raw = current.rawFields
            raw["type"] = .number(try JSONNumber(rawValue: String(origin)))
            let other = try Sticker(data: JSONValue.object(raw).serialized())
            #expect(throws: DiscordError.validation(.invalidValue)) {
                try StickerOperations.modifyGuildIfChanged(guildID: guild, current: other, request: GuildStickerModify())
            }
        }
        var raw = current.rawFields
        raw["guild_id"] = nil
        let absentOwner = try Sticker(data: JSONValue.object(raw).serialized())
        #expect(try StickerOperations.modifyGuildIfChanged(guildID: guild, current: absentOwner, request: GuildStickerModify()) == nil)
        #expect(try StickerOperations.modifyGuildIfChanged(guildID: guild, current: absentOwner,
            request: GuildStickerModify(name: .value("renamed"))) != nil)
    }

    /// Sound metadata comparison handles every explicit field, null selectors, exact volume lexemes and absent ownership.
    /// - Throws: Unexpected fixture/request/descriptor errors fail this test.
    @Test func soundReconciliation() throws {
        let guild = GuildID(rawValue: UInt64.max)
        let current = try SoundboardSound(data: Data(ExpressionEndpointTests.soundJSON.utf8))
        #expect(try SoundboardOperations.modifyGuildIfChanged(guildID: guild, current: current, request: GuildSoundboardSoundModify()) == nil)
        #expect(try SoundboardOperations.modifyGuildIfChanged(guildID: guild, current: current,
            request: GuildSoundboardSoundModify(name: .value("fixture"), volume: .value(0.5),
                emojiID: .value(.init(rawValue: UInt64.max)), emojiName: .null), auditReason: "\n") == nil)
        for change in [try GuildSoundboardSoundModify(name: .value("renamed")), try GuildSoundboardSoundModify(volume: .value(1)),
                       try GuildSoundboardSoundModify(volume: .null), try GuildSoundboardSoundModify(emojiID: .null),
                       try GuildSoundboardSoundModify(emojiID: .null, emojiName: .value("🔥"))] {
            let endpoint = try #require(try SoundboardOperations.modifyGuildIfChanged(guildID: guild, current: current,
                request: change, auditReason: "why"))
            #expect(endpoint.path == ["guilds", guild.description, "soundboard-sounds", current.soundID.description])
            #expect(endpoint.auditReason == "why")
            #expect(endpoint.retrySafety == .unsafe)
            #expect(try JSONValue.parse(#require(endpoint.body?.storedBodyBytes)) == change.jsonValue())
            #expect(throws: DiscordError.validation(.invalidValue)) {
                try SoundboardOperations.modifyGuildIfChanged(guildID: guild, current: current, request: change, auditReason: "\n")
            }
        }
        #expect(throws: DiscordError.validation(.invalidValue)) {
            try SoundboardOperations.modifyGuildIfChanged(guildID: .init(rawValue: 1), current: current, request: GuildSoundboardSoundModify())
        }
        var raw = current.rawFields
        raw["guild_id"] = nil
        let absentOwner = try SoundboardSound(data: JSONValue.object(raw).serialized())
        #expect(try SoundboardOperations.modifyGuildIfChanged(guildID: guild, current: absentOwner, request: GuildSoundboardSoundModify()) == nil)
        #expect(try SoundboardOperations.modifyGuildIfChanged(guildID: guild, current: absentOwner,
            request: GuildSoundboardSoundModify(name: .value("renamed"))) != nil)
        raw["volume"] = .number(try JSONNumber(rawValue: "0.50"))
        let lexicalVolume = try SoundboardSound(data: JSONValue.object(raw).serialized())
        #expect(try SoundboardOperations.modifyGuildIfChanged(guildID: guild, current: lexicalVolume,
            request: GuildSoundboardSoundModify(volume: .value(0.5))) != nil)
    }

    /// Shared helper failures and ordering comparisons are exercised directly without changing public visibility.
    /// - Throws: Unexpected comparison/descriptor errors fail this test.
    @Test func sharedHelperValidation() throws {
        #expect(try expressionFieldsChanged(["x": .null], request: .object([:])) == false)
        #expect(try expressionFieldsChanged(["x": .null], request: .object(["x": .null])) == false)
        #expect(try expressionFieldsChanged([:], request: .object(["x": .null])))
        #expect(try expressionFieldsChanged(["roles": .array([.string("1"), .string("2")])],
            request: .object(["roles": .array([.string("2"), .string("1")])])) == true)
        for nonobject in [JSONValue.null, .array([]), .string("bad"), .bool(false)] {
            #expect(throws: DiscordError.validation(.invalidValue)) { try expressionFieldsChanged([:], request: nonobject) }
        }
        let body = try RequestBody(bytes: Data("{}".utf8), contentType: "application/json")
        #expect(throws: DiscordError.validation(.invalidValue)) {
            try expressionGuildMutation("POST", guildID: .init(rawValue: 1), resource: "emojis", routeResource: "emojis",
                payload: .object([:]), body: body, catalog: "emoji-catalog", decode: { $0 })
        }
        #expect(throws: DiscordError.validation(.invalidValue)) {
            try expressionGuildMutation("DELETE", guildID: .init(rawValue: 1), resource: "emojis", routeResource: "emojis",
                id: "1", catalog: "emoji-catalog", decode: { $0 })
        }
        #expect(throws: DiscordError.validation(.invalidValue)) {
            try expressionGuildMutation("DELETE", guildID: .init(rawValue: 1), resource: "emojis", routeResource: "emojis",
                routeID: "emoji.id", catalog: "emoji-catalog", decode: { $0 })
        }
    }
}
