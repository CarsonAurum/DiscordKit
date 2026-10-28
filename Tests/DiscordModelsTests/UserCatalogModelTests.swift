// File: Tests/DiscordModelsTests/UserCatalogModelTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import Foundation
import Testing
@testable import DiscordModels

/// Deterministic User and linked-role projections, including written/preview compatibility overlays.
/// Every response initializer is exercised with its complete owned fields and sanitized malformed variants.
@Suite struct UserCatalogModelTests {
    static let user = Data(#"{"id":"18446744073709551615","username":"account","discriminator":"0","global_name":null,"avatar":null}"#.utf8)
    static let guild = Data(#"{"id":"18446744073709551615","name":"guild","icon":null,"banner":null,"owner":true,"permissions":"184467440737095516160000","features":["FUTURE_FEATURE"]}"#.utf8)
    static let connection = Data(#"{"id":"opaque:provider/id","name":null,"type":"future-service","verified":true,"friend_sync":false,"show_activity":true,"two_way_link":false,"visibility":99}"#.utf8)
    static let metadata = Data(#"{"type":99,"key":"score","name":"Score","description":"Score description"}"#.utf8)

    /// All owned fields retain presence/null, unknown values and native/exact snowflakes without hydrating resources.
    /// - Throws: Unexpected valid fixture decoding or parser errors fail this test.
    @Test func completeUserAndNestedValues() throws {
        var fields = try #require(try JSONValue.parse(Self.user).objectFields)
        fields.merge([
            "bot": .bool(true), "system": .bool(false), "mfa_enabled": .bool(true), "banner": .null,
            "accent_color": .number(try JSONNumber(rawValue: "16777215")), "locale": .string("future-locale"),
            "verified": .bool(true), "email": .string("private@example.test"),
            "flags": .number(try JSONNumber(rawValue: "18446744073709551615")),
            "public_flags": .number(try JSONNumber(rawValue: "18446744073709551615")),
            "premium_type": .number(try JSONNumber(rawValue: "999")),
            "avatar_decoration_data": .object(["asset": .string("decoration"), "sku_id": .string("18446744073709551615"), "future": .number(try JSONNumber(rawValue: "1.2300"))]),
            "collectibles": .object(["nameplate": .object(["sku_id": .string("18446744073709551615"), "asset": .string("path/"), "label": .string(""), "palette": .string("future-palette")])]),
            "primary_guild": .object(["identity_guild_id": .string("18446744073709551615"), "identity_enabled": .bool(false), "tag": .string("GILD"), "badge": .null]),
            "future": .number(try JSONNumber(rawValue: "9.00000000000000000001e+99"))
        ], uniquingKeysWith: { _, new in new })
        let decoded = try User(data: JSONValue.object(fields).serialized())
        #expect(decoded.id.rawValue == UInt64.max)
        #expect(decoded.bot == .value(true)); #expect(decoded.system == .value(false))
        #expect(decoded.mfaEnabled == .value(true)); #expect(decoded.banner == .null)
        #expect(decoded.accentColor == .value(16_777_215)); #expect(decoded.locale == .value("future-locale"))
        #expect(decoded.verified == .value(true)); #expect(decoded.email == .value("private@example.test"))
        #expect(decoded.flags == .value(UInt64.max)); #expect(decoded.publicFlags == .value(UInt64.max))
        #expect(decoded.premiumType == .value(.init(rawValue: 999)))
        if case .value(let decoration) = decoded.avatarDecorationData {
            #expect(decoration.asset == "decoration"); #expect(decoration.skuID == .value(.init(rawValue: UInt64.max)))
            #expect(decoration.rawFields["future"] == .number(try JSONNumber(rawValue: "1.2300")))
        } else { Issue.record("Expected avatar decoration") }
        if case .value(let collection) = decoded.collectibles, case .value(let nameplate) = collection.nameplate {
            #expect(nameplate.skuID.rawValue == UInt64.max); #expect(nameplate.asset == "path/")
            #expect(nameplate.label.isEmpty); #expect(nameplate.palette.rawValue == "future-palette")
            #expect(nameplate.palette.knownValue == nil)
        } else { Issue.record("Expected nameplate") }
        if case .value(let identity) = decoded.primaryGuild {
            #expect(identity.identityGuildID == .value(.init(rawValue: UInt64.max)))
            #expect(identity.identityEnabled == .value(false)); #expect(identity.tag == .value("GILD")); #expect(identity.badge == .null)
        } else { Issue.record("Expected primary guild") }
        #expect(decoded.rawFields == fields)
        #expect(decoded.jsonValue() == .object(fields))
        #expect(!String(describing: decoded).contains("private@example"))
        #expect(!String(reflecting: decoded).contains("future-locale"))
        #expect(decoded.customMirror.children.count == 1)
        let baseline = try User(data: Self.user)
        #expect(baseline.globalName == .null); #expect(baseline.avatar == .null)
        #expect(baseline.bot == .absent); #expect(baseline.avatarDecorationData == .absent)
        #expect(baseline.collectibles == .absent); #expect(baseline.primaryGuild == .absent)
    }

    /// Optional nullable nested overlays preserve all three states, including a system-cleared primary identity.
    /// - Throws: Unexpected parser/schema failures fail the test.
    @Test func nullAndEmptyNestedOverlays() throws {
        var fields = try #require(try JSONValue.parse(Self.user).objectFields)
        for key in ["avatar_decoration_data", "collectibles", "primary_guild", "email", "banner", "accent_color"] { fields[key] = .null }
        let nulls = try User(data: JSONValue.object(fields).serialized())
        #expect(nulls.avatarDecorationData == .null); #expect(nulls.collectibles == .null); #expect(nulls.primaryGuild == .null)
        #expect(nulls.email == .null); #expect(nulls.banner == .null); #expect(nulls.accentColor == .null)
        let cleared = try UserPrimaryGuild(data: Data(#"{"identity_guild_id":null,"identity_enabled":null,"tag":null,"badge":null}"#.utf8))
        #expect(cleared.identityGuildID == .null); #expect(cleared.identityEnabled == .null)
        #expect(cleared.tag == .null); #expect(cleared.badge == .null)
        #expect(try UserCollectibles(data: Data("{}".utf8)).nameplate == .absent)
        #expect(try UserCollectibles(data: Data(#"{"nameplate":null}"#.utf8)).nameplate == .null)
        #expect(try UserAvatarDecoration(data: Data(#"{"asset":"a","sku_id":null}"#.utf8)).skuID == .null)
        let empty = try ApplicationRoleConnection(data: Data("{}".utf8))
        #expect(empty.platformName == .absent); #expect(empty.platformUsername == .absent); #expect(empty.metadata == .absent)
        let role = try ApplicationRoleConnection(data: Data(#"{"platform_name":null,"platform_username":null,"metadata":{}}"#.utf8))
        #expect(role.platformName == .null); #expect(role.platformUsername == .null); #expect(role.metadata == .value([:]))
        let meta = try ApplicationRoleConnectionMetadata(data: Data(#"{"type":1,"key":"a","name":"A","description":"D","name_localizations":null,"description_localizations":{"future":"unknown"}}"#.utf8))
        #expect(meta.type.knownValue == .integerLessThanOrEqual)
        #expect(meta.nameLocalizations == .null); #expect(meta.descriptionLocalizations == .value(["future": "unknown"]))
    }

    /// Connection-specific and guild-list fields use typed provider snapshots and exact arbitrary-width permissions.
    /// - Throws: Unexpected decoding failures fail the test.
    @Test func guildsConnectionsAndMetadata() throws {
        let guild = try UserGuild(data: Self.guild)
        #expect(guild.id.rawValue == UInt64.max); #expect(guild.icon == .null); #expect(guild.banner == .null)
        #expect(guild.owner); #expect(guild.permissions == "184467440737095516160000")
        #expect(guild.features == ["FUTURE_FEATURE"]); #expect(guild.approximateMemberCount == .absent)
        var guildFields = guild.rawFields
        guildFields.removeValue(forKey: "banner")
        guildFields["approximate_member_count"] = .null
        guildFields["approximate_presence_count"] = .number(try JSONNumber(rawValue: "9223372036854775807"))
        let counts = try UserGuild(data: JSONValue.object(guildFields).serialized())
        #expect(counts.banner == .absent); #expect(counts.approximateMemberCount == .null)
        #expect(counts.approximatePresenceCount == .value(Int.max))
        var fields = try #require(try JSONValue.parse(Self.connection).objectFields)
        fields["revoked"] = .bool(false)
        fields["integrations"] = try JSONValue.parse(Data(#"[{"id":"opaque/integration","type":"future","name":null,"account":{"id":"external/id","name":"provider"},"guild":{"id":"18446744073709551615","name":"g","icon":null},"future":1.2300}]"#.utf8))
        let connection = try UserConnection(data: JSONValue.object(fields).serialized())
        #expect(connection.id == "opaque:provider/id"); #expect(connection.name == .null)
        #expect(connection.type.knownValue == nil); #expect(connection.type.rawValue == "future-service")
        #expect(connection.visibility.rawValue == 99); #expect(connection.visibility.knownValue == nil)
        #expect(connection.verified); #expect(!connection.friendSync); #expect(connection.showActivity); #expect(!connection.twoWayLink)
        #expect(connection.revoked == .value(false))
        if case .value(let integrations) = connection.integrations, let integration = integrations.first {
            #expect(integrations.count == 1); #expect(integration.id == "opaque/integration")
            #expect(integration.type.rawValue == "future"); #expect(integration.name == .null)
            #expect(integration.account.id == "external/id"); #expect(integration.account.name == .value("provider"))
            if case .value(let guild) = integration.guild {
                #expect(guild.id.rawValue == UInt64.max); #expect(guild.name == "g"); #expect(guild.icon == .null)
            } else { Issue.record("Expected typed guild") }
            #expect(integration.rawFields["future"] == .number(try JSONNumber(rawValue: "1.2300")))
        } else { Issue.record("Expected integration") }
        let nullableAccount = try UserConnectionAccount(data: Data(#"{"id":"external","name":null,"future":1.2300}"#.utf8))
        #expect(nullableAccount.id == "external"); #expect(nullableAccount.name == .null)
        #expect(nullableAccount.rawFields["future"] == .number(try JSONNumber(rawValue: "1.2300")))
        let partial = try UserConnectionIntegration(data: Data(#"{"id":"1","type":"twitch","account":{"id":"external","name":"p"}}"#.utf8))
        #expect(partial.name == .absent); #expect(partial.guild == .absent)
        let meta = try ApplicationRoleConnectionMetadata(data: Self.metadata)
        #expect(meta.type.rawValue == 99); #expect(meta.type.knownValue == nil)
        #expect(meta.key == "score"); #expect(meta.name == "Score"); #expect(meta.metadataDescription == "Score description")
        #expect(meta.nameLocalizations == .absent); #expect(meta.descriptionLocalizations == .absent)
        let role = try ApplicationRoleConnection(data: Data(#"{"platform_name":"platform","platform_username":"name","metadata":{"score":"10","future":"1.2300"}}"#.utf8))
        #expect(role.platformName == .value("platform")); #expect(role.platformUsername == .value("name"))
        #expect(role.metadata == .value(["score": "10", "future": "1.2300"]))
    }

    /// Every new initializer rejects each missing required key and mistyped modeled field without leaking values.
    /// Nullable required keys accept null, while nonnullable keys reject it. Unknown JSON remains bounded/exact.
    /// - Throws: Unexpected valid fixture or test construction errors fail the test.
    @Test func everyModelRejectsMalformedFields() throws {
        for fixture in try Self.fixtures() {
            let (bytes, required, nullable, decode) = fixture
            let fields = try #require(try JSONValue.parse(bytes).objectFields)
            #expect(try decode(bytes) == fields)
            for key in required {
                var missing = fields; missing.removeValue(forKey: key)
                #expect(throws: DiscordError.transport(.invalidResponse)) { try decode(JSONValue.object(missing).serialized()) }
                var null = fields; null[key] = .null
                if !nullable.contains(key) {
                    #expect(throws: DiscordError.transport(.invalidResponse)) { try decode(JSONValue.object(null).serialized()) }
                }
            }
            for key in fields.keys {
                var invalid = fields; invalid[key] = .array([.null])
                #expect(throws: DiscordError.transport(.invalidResponse)) { try decode(JSONValue.object(invalid).serialized()) }
            }
            for invalid in [Data("null".utf8), Data("[]".utf8), Data("1".utf8)] {
                #expect(throws: DiscordError.transport(.invalidResponse)) { try decode(invalid) }
            }
            #expect(throws: (any Error).self) { try decode(Data("{".utf8)) }
            #expect(throws: (any Error).self) { try decode(Data(#"{"id":"secret","id":"other"}"#.utf8)) }
            var extended = fields; extended["future"] = .number(try JSONNumber(rawValue: "1.2300e+100"))
            #expect(try decode(JSONValue.object(extended).serialized()) == extended)
        }
        #expect(throws: (any Error).self) { try User(data: Self.user, limits: .init(maximumBytes: 8, maximumDepth: 2, maximumNodes: 2)) }
    }

    /// Optional nonnullable scalars reject null; integer parsing rejects fractional/exponent spellings and overflow.
    /// - Throws: Unexpected fixture construction errors fail the test; every malformed response is asserted.
    @Test func optionalTypesAndNumericLexemes() throws {
        let baseline = try #require(try JSONValue.parse(Self.user).objectFields)
        for key in ["bot", "system", "mfa_enabled", "locale", "verified", "flags", "public_flags", "premium_type"] {
            var fields = baseline; fields[key] = .null
            #expect(throws: DiscordError.transport(.invalidResponse)) { try User(data: JSONValue.object(fields).serialized()) }
        }
        for key in ["flags", "public_flags", "premium_type", "accent_color"] {
            for token in ["1.0", "1e0", "18446744073709551616", "-18446744073709551616"] {
                var fields = baseline; fields[key] = .number(try JSONNumber(rawValue: token))
                #expect(throws: DiscordError.transport(.invalidResponse)) { try User(data: JSONValue.object(fields).serialized()) }
            }
        }
        for key in ["avatar_decoration_data", "collectibles", "primary_guild"] {
            var fields = baseline; fields[key] = .object([:])
            if key != "collectibles" {
                #expect(throws: DiscordError.transport(.invalidResponse)) { try User(data: JSONValue.object(fields).serialized()) }
            }
        }
        for invalid in ["", "-1", "+1", "1e5", "1 2", "１２"] {
            var fields = try #require(try JSONValue.parse(Self.guild).objectFields); fields["permissions"] = .string(invalid)
            #expect(throws: DiscordError.transport(.invalidResponse)) { try UserGuild(data: JSONValue.object(fields).serialized()) }
        }
        #expect(throws: DiscordError.transport(.invalidResponse)) { try ApplicationRoleConnection(data: Data(#"{"metadata":{"score":10}}"#.utf8)) }
        #expect(throws: DiscordError.transport(.invalidResponse)) { try ApplicationRoleConnection(data: Data(#"{"metadata":null}"#.utf8)) }
        #expect(throws: DiscordError.transport(.invalidResponse)) { try ApplicationRoleConnectionMetadata(data: Data(#"{"type":1.0,"key":"x","name":"n","description":"d"}"#.utf8)) }
    }

    /// Known flag/enum values match upstream while unknown bits and future raw values remain accessible.
    /// - Throws: Unexpected known value construction errors fail the test.
    @Test func knownValuesAndForwardCompatibility() throws {
        let flags: [UserFlags] = [.staff, .partner, .hypeSquad, .bugHunterLevel1, .houseBravery,
            .houseBrilliance, .houseBalance, .earlySupporter, .teamPseudoUser, .bugHunterLevel2,
            .verifiedBot, .verifiedDeveloper, .certifiedModerator, .botHTTPInteractions]
        #expect(flags.map(\.rawValue) == [0, 1, 2, 3, 6, 7, 8, 9, 10, 14, 16, 17, 18, 19].map { UInt64(1) << $0 })
        #expect(UserFlags(rawValue: UInt64.max).contains(.staff))
        #expect(UserFlags(rawValue: UInt64.max).rawValue == UInt64.max)
        #expect(UserNameplatePalette.allCases.count == 11); #expect(UserNameplatePalette.bubbleGum.rawValue == "bubble_gum")
        #expect(UserConnectionService.allCases.count == 23)
        #expect(UserConnectionService.amazonMusic.rawValue == "amazon-music")
        #expect(UserConnectionVisibility.allCases.map(\.rawValue) == [0, 1])
        #expect(ApplicationRoleConnectionMetadataType.allCases.map(\.rawValue) == Array(1...8))
    }

    /// Provides independent valid schemas and required/nullable key inventories for every new response initializer.
    /// - Returns: Exact fixtures, required keys, nullable required keys and a type-erased raw-field decoder.
    /// - Throws: No expected errors; the signature permits uniform future fixture validation.
    static func fixtures() throws -> [(Data, [String], Set<String>, @Sendable (Data) throws -> [String: JSONValue])] {
        [
            (user, ["id", "username", "discriminator", "global_name", "avatar"], ["global_name", "avatar"], { try User(data: $0).rawFields }),
            (Data(#"{"asset":"a","sku_id":"18446744073709551615"}"#.utf8), ["asset", "sku_id"], ["sku_id"], { try UserAvatarDecoration(data: $0).rawFields }),
            (Data(#"{"nameplate":null}"#.utf8), [], [], { try UserCollectibles(data: $0).rawFields }),
            (Data(#"{"sku_id":"1","asset":"a","label":"","palette":"cobalt"}"#.utf8), ["sku_id", "asset", "label", "palette"], [], { try UserNameplate(data: $0).rawFields }),
            (Data(#"{"identity_guild_id":null,"identity_enabled":null,"tag":null,"badge":null}"#.utf8), ["identity_guild_id", "identity_enabled", "tag", "badge"], ["identity_guild_id", "identity_enabled", "tag", "badge"], { try UserPrimaryGuild(data: $0).rawFields }),
            (guild, ["id", "name", "icon", "owner", "permissions", "features"], ["icon"], { try UserGuild(data: $0).rawFields }),
            (connection, ["id", "name", "type", "verified", "friend_sync", "show_activity", "two_way_link", "visibility"], ["name"], { try UserConnection(data: $0).rawFields }),
            (Data(#"{"id":"x","type":"future","account":{"id":"p","name":"p"},"guild":{"id":"1","name":"g","icon":null}}"#.utf8), ["id", "type", "account"], [], { try UserConnectionIntegration(data: $0).rawFields }),
            (Data(#"{"id":"1","name":"g","icon":null}"#.utf8), ["id", "name", "icon"], ["icon"], { try UserConnectionGuild(data: $0).rawFields }),
            (Data(#"{"id":"external","name":null}"#.utf8), ["id", "name"], ["name"], { try UserConnectionAccount(data: $0).rawFields }),
            (metadata, ["type", "key", "name", "description"], [], { try ApplicationRoleConnectionMetadata(data: $0).rawFields }),
            (Data(#"{"platform_name":"p","platform_username":null,"metadata":{}}"#.utf8), [], [], { try ApplicationRoleConnection(data: $0).rawFields })
        ]
    }
}

private extension JSONValue {
    /// Extracts an object only for deterministic fixture construction; does not accept scalar or array roots.
    /// - Returns: Exact object fields, or nil for a nonobject value. This performs no I/O or mutation.
    var objectFields: [String: JSONValue]? {
        if case .object(let fields) = self { return fields }
        return nil
    }
}
