// File: Tests/DiscordModelsTests/ExpressionModelTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import Foundation
import Testing
@testable import DiscordModels

/// Deterministic expression fixtures cover the complete written API schemas, future fields,
/// nullable/deleted forms and bounded redaction without live Discord requests or credentials.
@Suite struct ExpressionModelTests {
    /// Guild/application, Unicode, animated, unavailable and deleted forms preserve every written field.
    /// Premium role IDs remain exact without inventing subscription eligibility from a role snowflake.
    /// - Throws: Unexpected parsing, projection or serialization failures fail the test.
    @Test func completeEmojiForms() throws {
        let emoji = try Emoji(data: Data(ExpressionModelFixture.emoji.utf8))
        #expect(emoji.id == .value(.init(rawValue: .max)))
        #expect(emoji.name == .value("private-emoji"))
        #expect(emoji.roles == .value([.init(rawValue: .max), .init(rawValue: 0)]))
        #expect(emoji.requireColons == .value(true))
        #expect(emoji.managed == .value(false))
        #expect(emoji.animated == .value(true))
        #expect(emoji.available == .value(false))
        guard case .value(let user) = emoji.user else { Issue.record("Expected creator"); return }
        #expect(user.id.rawValue == .max)
        #expect(user.username == "private-user")
        #expect(user.rawFields["future"] == .number(try JSONNumber(rawValue: "1.2300e+100")))
        let unicode = try Emoji(data: Data(#"{"id":null,"name":"🔥"}"#.utf8))
        #expect(unicode.id == .null)
        #expect(unicode.name == .value("🔥"))
        #expect(unicode.roles == .absent)
        #expect(unicode.user == .absent)
        #expect(unicode.requireColons == .absent)
        #expect(unicode.managed == .absent)
        #expect(unicode.animated == .absent)
        #expect(unicode.available == .absent)
        let deleted = try Emoji(data: Data(#"{"id":"18446744073709551615","name":null}"#.utf8))
        #expect(deleted.id == emoji.id)
        #expect(deleted.name == .null)
        let roles = try Emoji(data: Data(#"{"id":"1","name":"a","roles":[],"animated":false}"#.utf8))
        #expect(roles.roles == .value([]))
        #expect(roles.animated == .value(false))
        let list = try ApplicationEmojiList(data: JSONValue.object(["items": .array([emoji.jsonValue(), unicode.jsonValue(), deleted.jsonValue()]),
            "future": .string("private-envelope")]).serialized())
        #expect(list.items == [emoji, unicode, deleted])
        #expect(list.rawFields["future"] == .string("private-envelope"))
        #expect(try ApplicationEmojiList(data: Data(#"{"items":[]}"#.utf8)).items.isEmpty)
    }

    /// Every sticker and pack field retains exact identifiers, nested order, availability and format values.
    /// Mutation-only text restrictions are not applied to response snapshots or future origins/formats.
    /// - Throws: Unexpected fixture parsing or projection failures fail the test.
    @Test func completeStickerAndPacks() throws {
        let sticker = try Sticker(data: Data(ExpressionModelFixture.sticker.utf8))
        #expect(sticker.id.rawValue == .max)
        #expect(sticker.packID == .value(.init(rawValue: .max)))
        #expect(sticker.name == "private-sticker")
        #expect(sticker.stickerDescription == .value("private-description"))
        #expect(sticker.tags == "hello, wave")
        #expect(sticker.type.knownValue == .standard)
        #expect(sticker.formatType.knownValue == .lottie)
        #expect(sticker.available == .value(false))
        #expect(sticker.guildID == .value(.init(rawValue: 0)))
        #expect(sticker.sortValue == .value(Int.min))
        guard case .value(let user) = sticker.user else { Issue.record("Expected uploader"); return }
        #expect(user.id.rawValue == .max)
        let pack = try StickerPack(data: Data(ExpressionModelFixture.pack.utf8))
        #expect(pack.id.rawValue == .max)
        #expect(pack.stickers == [sticker])
        #expect(pack.name == "private-pack")
        #expect(pack.skuID.rawValue == .max)
        #expect(pack.coverStickerID == .value(sticker.id))
        #expect(pack.packDescription == "private-description")
        #expect(pack.bannerAssetID == .value(.init(rawValue: .max)))
        let packs = try StickerPackList(data: Data(ExpressionModelFixture.packs.utf8))
        #expect(packs.stickerPacks == [pack])
        #expect(try StickerPackList(data: Data(#"{"sticker_packs":[]}"#.utf8)).stickerPacks.isEmpty)
        let minimal = try Sticker(data: Data(#"{"id":"0","name":"","description":null,"tags":"","type":2,"format_type":1}"#.utf8))
        #expect(minimal.packID == .absent)
        #expect(minimal.guildID == .absent)
        #expect(minimal.user == .absent)
        #expect(minimal.sortValue == .absent)
        #expect(minimal.available == .absent)
        #expect(minimal.stickerDescription == .null)
        #expect(minimal.type.knownValue == .guild)
        let emptyPack = try StickerPack(data: Data(#"{"id":"0","stickers":[],"name":"","sku_id":"0","description":""}"#.utf8))
        #expect(emptyPack.stickers.isEmpty)
        #expect(emptyPack.coverStickerID == .absent)
        #expect(emptyPack.bannerAssetID == .absent)
        #expect(StickerType.allCases.map(\.rawValue) == [1, 2])
        for code in [1, 2, 3, 4, Int.min, Int.max] {
            var fields = minimal.rawFields
            fields["format_type"] = .number(try JSONNumber(rawValue: String(code)))
            fields["type"] = .number(try JSONNumber(rawValue: String(code)))
            fields["tags"] = .string(String(repeating: "x", count: 201))
            let parsed = try Sticker(value: .object(fields), limits: .default)
            #expect(parsed.formatType.rawValue == code)
            #expect(parsed.formatType.knownValue == MessageStickerFormatType(rawValue: code))
            #expect(parsed.type.rawValue == code)
            #expect(parsed.type.knownValue == StickerType(rawValue: code))
            #expect(parsed.tags.unicodeScalars.count == 201)
        }
    }

    /// Default/guild sounds support small and maximum IDs, nullable selectors and fractional volume lexemes.
    /// Finite response values beyond writable volume limits are retained for forward compatibility.
    /// - Throws: Unexpected parsing, projection or serialization failures fail the test.
    @Test func completeSoundboardForms() throws {
        let sound = try SoundboardSound(data: Data(ExpressionModelFixture.sound.utf8))
        #expect(sound.name == "private-sound")
        #expect(sound.soundID.rawValue == .max)
        #expect(sound.volume == 0.25)
        #expect(sound.emojiID == .value(.init(rawValue: .max)))
        #expect(sound.emojiName == .null)
        #expect(sound.guildID == .value(.init(rawValue: 0)))
        #expect(!sound.available)
        guard case .value(let user) = sound.user else { Issue.record("Expected uploader"); return }
        #expect(user.id.rawValue == .max)
        let defaults = try SoundboardSound(data: Data(#"{"name":"quack","sound_id":"1","volume":1.0,"emoji_id":null,"emoji_name":"🦆","available":true}"#.utf8))
        #expect(defaults.soundID.rawValue == 1)
        #expect(defaults.volume == 1)
        #expect(defaults.emojiID == .null)
        #expect(defaults.emojiName == .value("🦆"))
        #expect(defaults.guildID == .absent)
        #expect(defaults.user == .absent)
        #expect(defaults.available)
        let list = try GuildSoundboardSoundList(data: Data(ExpressionModelFixture.sounds.utf8))
        #expect(list.items == [sound, defaults])
        #expect(try GuildSoundboardSoundList(data: Data(#"{"items":[]}"#.utf8)).items.isEmpty)
        for token in ["0", "-0", "1", "0.2500", "2.5e-1", "-1", "2", "1e-999"] {
            var fields = sound.rawFields
            fields["volume"] = .number(try JSONNumber(rawValue: token))
            let parsed = try SoundboardSound(value: .object(fields), limits: .default)
            #expect(parsed.volume == Double(token))
            #expect(parsed.rawFields["volume"] == fields["volume"])
        }
        for token in ["1e999", "-1e999", #""0.5""#, "true", "[]", "{}"] {
            var fields = sound.rawFields
            fields["volume"] = try JSONValue.parse(token)
            #expect(throws: DiscordError.transport(.invalidResponse)) {
                try SoundboardSound(value: .object(fields), limits: .default)
            }
        }
    }

    /// Each field in all seven public schemas rejects omission/null/type mismatches according to its contract.
    /// Optional fields preserve omission and required nullable fields accept only explicit null, not omission.
    /// - Throws: Unexpected trusted-fixture serialization/parsing fails the test.
    @Test func completeFieldContracts() throws {
        for fixture in ExpressionModelFixture.all {
            for (key, optional, nullable) in fixture.fields {
                var fields = try object(fixture.source)
                fields[key] = nil
                let missing = try JSONValue.object(fields).serialized()
                if optional { #expect(try fixture.parse(missing, .default).rawFields[key] == nil) }
                else { #expect(throws: DiscordError.transport(.invalidResponse)) { try fixture.parse(missing, .default) } }
                fields[key] = .null
                let null = try JSONValue.object(fields).serialized()
                if nullable { #expect(try fixture.parse(null, .default).rawFields[key] == .null) }
                else { #expect(throws: DiscordError.transport(.invalidResponse)) { try fixture.parse(null, .default) } }
                fields[key] = .object([:])
                #expect(throws: DiscordError.transport(.invalidResponse)) {
                    try fixture.parse(JSONValue.object(fields).serialized(), .default)
                }
            }
        }
        for (source, key, parse) in [
            (ExpressionModelFixture.emoji, "roles", { @Sendable data in _ = try Emoji(data: data) }),
            (ExpressionModelFixture.application, "items", { @Sendable data in _ = try ApplicationEmojiList(data: data) }),
            (ExpressionModelFixture.pack, "stickers", { @Sendable data in _ = try StickerPack(data: data) }),
            (ExpressionModelFixture.packs, "sticker_packs", { @Sendable data in _ = try StickerPackList(data: data) }),
            (ExpressionModelFixture.sounds, "items", { @Sendable data in _ = try GuildSoundboardSoundList(data: data) })
        ] {
            for invalid: JSONValue in [.null, .bool(false), .array([]), .object([:])] {
                var fields = try object(source)
                fields[key] = .array([invalid])
                #expect(throws: DiscordError.transport(.invalidResponse)) { try parse(JSONValue.object(fields).serialized()) }
            }
        }
    }

    /// All expression snowflakes and exact integer fields reject rounded, signed or overflowing values.
    /// Existing Snowflake compatibility accepts leading zeros while raw response fields preserve their spelling.
    /// - Throws: Unexpected fixture parsing or numeric token construction fails the test.
    @Test func malformedIdentifiersAndNumbers() throws {
        let invalidIDs = ["", "-1", "+1", "1.0", "1e0", "18446744073709551616", "private-id", "١"]
        for (index, key) in [(0, "id"), (2, "id"), (2, "pack_id"), (2, "guild_id"),
                             (3, "id"), (3, "sku_id"), (3, "cover_sticker_id"), (3, "banner_asset_id"),
                             (5, "sound_id"), (5, "emoji_id"), (5, "guild_id")] {
            let fixture = ExpressionModelFixture.all[index]
            for invalid in invalidIDs {
                var fields = try object(fixture.source)
                fields[key] = .string(invalid)
                #expect(throws: DiscordError.transport(.invalidResponse)) {
                    try fixture.parse(JSONValue.object(fields).serialized(), .default)
                }
            }
        }
        for key in ["type", "format_type", "sort_value"] {
            for token in ["1.0", "1e0", "1.000000000000000001", "1e-999", "18446744073709551616", #""1""#, "true"] {
                var fields = try object(ExpressionModelFixture.sticker)
                fields[key] = try JSONValue.parse(token)
                #expect(throws: DiscordError.transport(.invalidResponse)) {
                    try Sticker(value: .object(fields), limits: .default)
                }
            }
        }
        for fixture in ExpressionModelFixture.all {
            let root = try JSONValue.parse(fixture.source)
            #expect(try fixture.parse(root.serialized(), .default).jsonValue() == root)
        }
        let padded = try Emoji(data: Data(#"{"id":"0001","name":"padded"}"#.utf8))
        #expect(padded.id == .value(.init(rawValue: 1)))
        #expect(padded.rawFields["id"] == .string("0001"))
    }

    /// All entry points bound whole trees before projection and conceal modeled/unknown content in diagnostics.
    /// Duplicate keys, trailing documents, invalid roots and byte/depth/node/configuration failures remain explicit.
    /// - Throws: Unexpected trusted-fixture parsing or serialization fails the test.
    @Test func parserBoundsAndRedaction() throws {
        for fixture in ExpressionModelFixture.all {
            let data = Data(fixture.source.utf8)
            let parsed = try fixture.parse(data, .default)
            #expect(parsed.rawFields["future"] == .number(try JSONNumber(rawValue: "18446744073709551616")))
            #expect(parsed.description.hasSuffix("(redacted)"))
            #expect(parsed.debugDescription == parsed.description)
            #expect(!String(reflecting: parsed).contains("private-"))
            #expect(parsed.customMirror.children.count == 1)
            #expect(parsed.jsonValue() == parsed.jsonValue())
            #expect(try fixture.parse(parsed.jsonValue().serialized(), .default).jsonValue() == parsed.jsonValue())
            #expect(try fixture.parse(data, .init(maximumBytes: data.count)).jsonValue() == parsed.jsonValue())
            #expect(throws: JSONValueError.maximumBytesExceeded) {
                try fixture.parse(data, .init(maximumBytes: data.count - 1))
            }
            #expect(throws: JSONValueError.maximumNodesExceeded) { try fixture.parse(data, .init(maximumNodes: 1)) }
            #expect(throws: JSONValueError.invalidLimits) { try fixture.parse(data, .init(maximumDepth: 129)) }
            var fields = parsed.rawFields
            fields["unknown_nested"] = .object(["nested": .object([:])])
            #expect(throws: JSONValueError.maximumDepthExceeded) {
                try fixture.parse(JSONValue.object(fields).serialized(), .init(maximumDepth: 1))
            }
            for source in ["null", "false", "1", #""private-root""#, "[]"] {
                #expect(throws: DiscordError.transport(.invalidResponse)) { try fixture.parse(Data(source.utf8), .default) }
            }
            #expect(throws: (any Error).self) { try fixture.parse(Data(#"{"id":"1","id":"2"}"#.utf8), .default) }
            #expect(throws: (any Error).self) { try fixture.parse(data + Data("{}".utf8), .default) }
        }
    }

    /// Extracts the immutable trusted object for isolated per-field contract mutations.
    /// - Parameter source: Complete valid JSON object fixture.
    /// - Returns: Its original fields without numeric normalization.
    /// - Throws: Parser errors, or a recorded failure if the trusted source is not an object.
    private func object(_ source: String) throws -> [String: JSONValue] {
        guard case .object(let fields) = try JSONValue.parse(source) else {
            Issue.record("Expected object fixture")
            throw DiscordError.validation(.invalidValue)
        }
        return fields
    }
}

/// Independently parsed schemas and exact optional/nullable contracts used by the exhaustive field loop.
private struct ExpressionModelFixture: Sendable {
    let source: String
    let fields: [(String, Bool, Bool)]
    let parse: @Sendable (Data, JSONLimits) throws -> any MessageResponseValue

    static let user = #"{"id":"18446744073709551615","username":"private-user","avatar":null,"future":1.2300e+100}"#
    static let emoji = #"{"id":"18446744073709551615","name":"private-emoji","roles":["18446744073709551615","0"],"user":USER,"require_colons":true,"managed":false,"animated":true,"available":false,"future":18446744073709551616}"#.replacingOccurrences(of: "USER", with: user)
    static let application = "{\"items\":[\(emoji)],\"future\":18446744073709551616}"
    static let sticker = #"{"id":"18446744073709551615","pack_id":"18446744073709551615","name":"private-sticker","description":"private-description","tags":"hello, wave","type":1,"format_type":3,"available":false,"guild_id":"0","user":USER,"sort_value":-9223372036854775808,"future":18446744073709551616}"#.replacingOccurrences(of: "USER", with: user)
    static let pack = "{\"id\":\"18446744073709551615\",\"stickers\":[\(sticker)],\"name\":\"private-pack\",\"sku_id\":\"18446744073709551615\",\"cover_sticker_id\":\"18446744073709551615\",\"description\":\"private-description\",\"banner_asset_id\":\"18446744073709551615\",\"future\":18446744073709551616}"
    static let packs = "{\"sticker_packs\":[\(pack)],\"future\":18446744073709551616}"
    static let sound = #"{"name":"private-sound","sound_id":"18446744073709551615","volume":0.2500,"emoji_id":"18446744073709551615","emoji_name":null,"guild_id":"0","available":false,"user":USER,"future":18446744073709551616}"#.replacingOccurrences(of: "USER", with: user)
    static let sounds = "{\"items\":[\(sound),{\"name\":\"quack\",\"sound_id\":\"1\",\"volume\":1.0,\"emoji_id\":null,\"emoji_name\":\"🦆\",\"available\":true}],\"future\":18446744073709551616}"

    static let all: [Self] = [
        .init(source: emoji, fields: [("id", false, true), ("name", false, true)] +
            ["roles", "user", "require_colons", "managed", "animated", "available"].map { ($0, true, false) },
            parse: { try Emoji(data: $0, limits: $1) }),
        .init(source: application, fields: [("items", false, false)], parse: { try ApplicationEmojiList(data: $0, limits: $1) }),
        .init(source: sticker, fields: ["id", "name", "tags", "type", "format_type"].map { ($0, false, false) } +
            [("description", false, true)] + ["pack_id", "available", "guild_id", "user", "sort_value"].map { ($0, true, false) },
            parse: { try Sticker(data: $0, limits: $1) }),
        .init(source: pack, fields: ["id", "stickers", "name", "sku_id", "description"].map { ($0, false, false) } +
            ["cover_sticker_id", "banner_asset_id"].map { ($0, true, false) },
            parse: { try StickerPack(data: $0, limits: $1) }),
        .init(source: packs, fields: [("sticker_packs", false, false)], parse: { try StickerPackList(data: $0, limits: $1) }),
        .init(source: sound, fields: ["name", "sound_id", "volume", "available"].map { ($0, false, false) } +
            [("emoji_id", false, true), ("emoji_name", false, true)] + ["guild_id", "user"].map { ($0, true, false) },
            parse: { try SoundboardSound(data: $0, limits: $1) }),
        .init(source: sounds, fields: [("items", false, false)], parse: { try GuildSoundboardSoundList(data: $0, limits: $1) })
    ]
}
