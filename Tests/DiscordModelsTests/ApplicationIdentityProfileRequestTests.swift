// File: Tests/DiscordModelsTests/ApplicationIdentityProfileRequestTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import Foundation
import Testing
@testable import DiscordModels

/// Request validation and explicit snapshot reconciliation for the API v10 identity-profile family.
@Suite struct ApplicationIdentityProfileRequestTests {
    /// Provider tuples retain open types, exact Unicode/percent characters and absent/empty provider disambiguation.
    /// Local path and text bounds are enforced before endpoint construction, without exposing account data in diagnostics.
    /// - Throws: Unexpected key or JSON construction fails the test.
    @Test func providerKeys() throws {
        let nilKey = try ApplicationIdentityKey(providerType: "FUTURE", providerIssuedUserID: "external%雪")
        #expect(nilKey.providerType == "FUTURE" && nilKey.providerIssuedUserID == "external%雪")
        #expect(nilKey.providerID == nil && nilKey.jsonValue() == .object([:]))
        let key = try ApplicationIdentityKey(providerType: "NONE", providerIssuedUserID: "x", providerID: "")
        #expect(key.jsonValue() == .object(["provider_id": .string("")]))
        #expect(key.description == "ApplicationIdentityKey(redacted)" && !key.debugDescription.contains("NONE"))
        #expect(key.customMirror.children.count == 1)
        for path in ["", ".", "..", "a/b", "a\\b", "a\u{0}", "a\n"] {
            #expect(throws: DiscordError.validation(.invalidValue)) { try ApplicationIdentityKey(providerType: path, providerIssuedUserID: "x") }
            #expect(throws: DiscordError.validation(.invalidValue)) { try ApplicationIdentityKey(providerType: "NONE", providerIssuedUserID: path) }
        }
        #expect(throws: DiscordError.validation(.invalidValue)) {
            try ApplicationIdentityKey(providerType: String(repeating: "a", count: 1_025), providerIssuedUserID: "x")
        }
        #expect(throws: DiscordError.validation(.invalidValue)) {
            try ApplicationIdentityKey(providerType: "NONE", providerIssuedUserID: String(repeating: "a", count: 4_097))
        }
        for provider in ["x\u{0}", String(repeating: "a", count: 4_097)] {
            #expect(throws: DiscordError.validation(.invalidValue)) {
                try ApplicationIdentityKey(providerType: "NONE", providerIssuedUserID: "x", providerID: provider)
            }
        }
        #expect(try ApplicationIdentityKey(providerType: String(repeating: "a", count: 1_024),
            providerIssuedUserID: String(repeating: "a", count: 4_096), providerID: String(repeating: "a", count: 4_096)).providerID?.count == 4_096)
    }

    /// Every primary property emits its exact wire key; huge integral and decimal lexemes never round or overflow.
    /// - Throws: Unexpected primary/media construction fails the test.
    @Test func completePrimary() throws {
        let number = try JSONNumber(rawValue: "184467440737095516159999")
        let decimal = try JSONNumber(rawValue: "69.4100")
        let media = try ApplicationIdentityProfileMedia(url: "https://example.com/rank?q=1#asset")
        let primary = try ApplicationIdentityProfilePrimaryUpdate(season: .value("s"), rankName: .value("r"),
            highestRank: .value("h"), featuredPlayedCharacter: .value("c"), rankImage: .value(media),
            highestRankImage: .value(media), featuredPlayedCharacterImage: .value(media), playtimeHours: .value(decimal),
            totalWins: .value(number), currentPeriodWins: .value(number), totalGames: .value(number), currentPeriodGames: .value(number),
            totalKills: .value(number), currentPeriodKills: .value(number), totalAssists: .value(number), currentPeriodAssists: .value(number),
            totalDeaths: .value(number), currentPeriodDeaths: .value(number))
        guard case .object(let fields) = primary.jsonValue() else { Issue.record("Expected object"); return }
        #expect(fields.count == 18)
        for field in ["total_wins", "current_period_wins", "total_games", "current_period_games", "total_kills", "current_period_kills",
            "total_assists", "current_period_assists", "total_deaths", "current_period_deaths"] { #expect(fields[field] == .number(number)) }
        #expect(fields["season"] == .string("s") && fields["rank_name"] == .string("r"))
        #expect(fields["highest_rank"] == .string("h") && fields["featured_played_character"] == .string("c"))
        #expect(fields["playtime_hours"] == .number(decimal))
        for field in ["rank_image", "highest_rank_image", "featured_played_character_image"] { #expect(fields[field] == media.jsonValue()) }
        #expect(try ApplicationIdentityProfilePrimaryUpdate().jsonValue() == .object([:]))
        #expect(try ApplicationIdentityProfilePrimaryUpdate(season: .value(String(repeating: "雪", count: 100))).jsonValue()
            == .object(["season": .string(String(repeating: "雪", count: 100))]))
        #expect(try ApplicationIdentityProfilePrimaryUpdate(rankName: .value(""), totalWins: .value(try JSONNumber(rawValue: "-0"))).jsonValue()
            == .object(["rank_name": .string(""), "total_wins": .number(try JSONNumber(rawValue: "-0"))]))
    }

    /// Every primary parameter rejects explicit null instead of translating it into omission or a clear.
    /// - Parameter index: Every optional primary parameter in declaration order.
    /// - Throws: Unexpected test harness construction fails the test.
    @Test(arguments: 0..<18) func rejectsPrimaryNull(index: Int) throws {
        let invalid: [() throws -> ApplicationIdentityProfilePrimaryUpdate] = [
            { try .init(season: .null) }, { try .init(rankName: .null) }, { try .init(highestRank: .null) },
            { try .init(featuredPlayedCharacter: .null) }, { try .init(rankImage: .null) }, { try .init(highestRankImage: .null) },
            { try .init(featuredPlayedCharacterImage: .null) }, { try .init(playtimeHours: .null) }, { try .init(totalWins: .null) },
            { try .init(currentPeriodWins: .null) }, { try .init(totalGames: .null) }, { try .init(currentPeriodGames: .null) },
            { try .init(totalKills: .null) }, { try .init(currentPeriodKills: .null) }, { try .init(totalAssists: .null) },
            { try .init(currentPeriodAssists: .null) }, { try .init(totalDeaths: .null) }, { try .init(currentPeriodDeaths: .null) }]
        #expect(throws: DiscordError.validation(.invalidValue)) { try invalid[index]() }
    }

    /// Text overflow and nonintegral count lexemes are rejected across every primary request member sharing those validators.
    /// - Throws: Unexpected harness errors fail the test.
    @Test func invalidPrimaryValues() throws {
        let text = Field.value(String(repeating: "x", count: 101))
        let strings: [() throws -> ApplicationIdentityProfilePrimaryUpdate] = [
            { try .init(season: text) }, { try .init(rankName: text) }, { try .init(highestRank: text) }, { try .init(featuredPlayedCharacter: text) }]
        for invalid in strings { #expect(throws: DiscordError.validation(.invalidValue)) { try invalid() } }
        for spelling in ["1.0", "1e2", "-0.1"] {
            let number = Field.value(try JSONNumber(rawValue: spelling))
            let numbers: [() throws -> ApplicationIdentityProfilePrimaryUpdate] = [
                { try .init(totalWins: number) }, { try .init(currentPeriodWins: number) }, { try .init(totalGames: number) },
                { try .init(currentPeriodGames: number) }, { try .init(totalKills: number) }, { try .init(currentPeriodKills: number) },
                { try .init(totalAssists: number) }, { try .init(currentPeriodAssists: number) }, { try .init(totalDeaths: number) },
                { try .init(currentPeriodDeaths: number) }]
            for invalid in numbers { #expect(throws: DiscordError.validation(.invalidValue)) { try invalid() } }
        }
    }

    /// Known dynamic variants preserve exact values and derive matching type codes; unknown outgoing variants and text overflow fail.
    /// - Throws: Unexpected dynamic/media/number construction fails the test.
    @Test func dynamicRequests() throws {
        let number = try JSONNumber(rawValue: "1.2300e999")
        let media = try ApplicationIdentityProfileMedia(url: "https://example.com/asset")
        let values: [ApplicationIdentityDynamicFieldValue] = [.string(""), .number(number), .media(media)]
        let encoded: [JSONValue] = [.string(""), .number(number), media.jsonValue()]
        for index in values.indices {
            #expect(try ApplicationIdentityDynamicField(name: "key", value: values[index]).jsonValue() == .object([
                "type": .number(try JSONNumber(rawValue: String(index + 1))), "name": .string("key"), "value": encoded[index]]))
        }
        #expect(try ApplicationIdentityDynamicField(name: String(repeating: "雪", count: 100), value: .string(String(repeating: "雪", count: 100))).jsonValue()
            != .object([:]))
        #expect(throws: DiscordError.validation(.invalidValue)) { try ApplicationIdentityDynamicField(name: "x", value: .unknown(.null)) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try ApplicationIdentityDynamicField(name: String(repeating: "a", count: 101), value: .string("x")) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try ApplicationIdentityDynamicField(name: "x", value: .string(String(repeating: "a", count: 101))) }
    }

    /// Outgoing media requires finite absolute HTTP(S) syntax, and response-only media cannot bypass request URL validation.
    /// - Parameter bad: Invalid or locally excessive URL text.
    /// - Throws: Unexpected response fixture parsing fails the test.
    @Test(arguments: ["", "relative.png", "file:///private/asset", "https://", "https://user:pass@example.com/a", "https://example.com/a b", "https://example.com/a\n", "https://example.com/" + String(repeating: "a", count: 2_049)])
    func invalidMedia(bad: String) throws {
        #expect(throws: DiscordError.validation(.invalidValue)) { try ApplicationIdentityProfileMedia(url: bad) }
        let media = try ApplicationIdentityProfileMedia(data: JSONValue.object(["url": .string(bad)]).serialized())
        #expect(throws: DiscordError.validation(.invalidValue)) { try ApplicationIdentityDynamicField(name: "x", value: .media(media)) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try ApplicationIdentityProfilePrimaryUpdate(rankImage: .value(media)) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try ApplicationIdentityProfilePrimaryUpdate(highestRankImage: .value(media)) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try ApplicationIdentityProfilePrimaryUpdate(featuredPlayedCharacterImage: .value(media)) }
    }

    /// Full replacements distinguish omitted/empty primary and dynamic values; count and serialized data limits apply before I/O.
    /// The exclusive local 10,000-byte cap covers escaped UTF-8 JSON, independent of the outer body size.
    /// - Throws: Unexpected fixture/request construction fails the test; overflow categories are asserted.
    @Test func replacementAndBounds() throws {
        #expect(try ApplicationIdentityProfileDataUpdate().jsonValue() == .object([:]))
        #expect(try ApplicationIdentityProfileDataUpdate(primary: .init(), dynamic: []).jsonValue()
            == .object(["primary": .object([:]), "dynamic": .array([])]))
        let field = try ApplicationIdentityDynamicField(name: "key", value: .string("x"))
        #expect(try ApplicationIdentityProfileDataUpdate(dynamic: Array(repeating: field, count: 30)).jsonValue()
            == .object(["dynamic": .array(Array(repeating: field.jsonValue(), count: 30))]))
        #expect(throws: DiscordError.validation(.invalidValue)) { try ApplicationIdentityProfileDataUpdate(dynamic: Array(repeating: field, count: 31)) }
        let atLimit = try Self.dataFields(serializedBytes: 9_999)
        #expect(try ApplicationIdentityProfileDataUpdate(dynamic: atLimit).jsonValue().serialized().count == 9_999)
        #expect(throws: JSONValueError.maximumBytesExceeded) {
            try ApplicationIdentityProfileDataUpdate(dynamic: Self.dataFields(serializedBytes: 10_000))
        }
        let request = try ApplicationIdentityProfileUpdate(username: .value(String(repeating: "雪", count: 1_024)),
            data: .value(.init(dynamic: atLimit)))
        #expect(try request.jsonValue().serialized().count > 10_000)
        #expect(try ApplicationIdentityProfileUpdate(username: .value("")).jsonValue() == .object(["username": .string("")]))
        #expect(try ApplicationIdentityProfileUpdate().jsonValue() == .object([:]))
        #expect(throws: DiscordError.validation(.invalidValue)) { try ApplicationIdentityProfileUpdate(username: .null) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try ApplicationIdentityProfileUpdate(data: .null) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try ApplicationIdentityProfileUpdate(username: .value(String(repeating: "a", count: 1_025))) }
    }

    /// Snapshot reconciliation suppresses only fully satisfied explicit fields and retains complete replacement bodies on any difference.
    /// Unknown existing stats are not silently copied; exact number spelling differences remain explicit changes.
    /// - Throws: Unexpected request/model construction fails the test.
    @Test func snapshotReconciliation() throws {
        let current = try ApplicationIdentityProfile(data: Data(#"{"username":"same","metadata":{"private":true},"data":{"primary":{"total_wins":10}}}"#.utf8))
        #expect(try ApplicationIdentityProfileUpdate().reconciling(against: current) == nil)
        #expect(try ApplicationIdentityProfileUpdate(username: .value("same")).reconciling(against: current) == nil)
        let same = try ApplicationIdentityProfileUpdate(data: .value(.init(primary: .init(totalWins: .value(try JSONNumber(rawValue: "10"))))))
        #expect(same.reconciling(against: current) == nil)
        let replace = try ApplicationIdentityProfileUpdate(username: .value("same"), data: .value(.init()))
        #expect(replace.reconciling(against: current)?.jsonValue() == replace.jsonValue())
        #expect(replace.jsonValue() == .object(["username": .string("same"), "data": .object([:])]))
        let changedUsername = try ApplicationIdentityProfileUpdate(username: .value("different"))
        #expect(changedUsername.reconciling(against: current)?.jsonValue() == changedUsername.jsonValue())
        let unknown = try ApplicationIdentityProfile(data: Data(#"{"username":"same","metadata":null,"data":{"primary":{"total_wins":10},"future":true}}"#.utf8))
        #expect(same.reconciling(against: unknown)?.jsonValue() == same.jsonValue())
        let precise = try ApplicationIdentityProfile(data: Data(#"{"username":null,"metadata":null,"data":{"primary":{"playtime_hours":1.00}}}"#.utf8))
        let normalized = try ApplicationIdentityProfileUpdate(data: .value(.init(primary: .init(playtimeHours: .value(try JSONNumber(rawValue: "1.0"))))))
        #expect(normalized.reconciling(against: precise)?.jsonValue() == normalized.jsonValue())
    }

    /// Builds five individually valid media fields whose enclosing data object has an exact chosen serialized byte length.
    /// - Parameter serializedBytes: Desired object bytes near the 10,000-byte boundary; helper assumptions are test-only.
    /// - Returns: Five ordered fields with HTTP(S) URLs below the per-URL cap.
    /// - Throws: Unexpected media/JSON construction fails the test; the computed exact size is asserted.
    private static func dataFields(serializedBytes: Int) throws -> [ApplicationIdentityDynamicField] {
        let prefix = "https://example.com/"
        var fields = try (0..<5).map { index in
            try ApplicationIdentityDynamicField(name: String(index), value: .media(.init(url: prefix + String(repeating: "x", count: index < 4 ? 1_981 : 0))))
        }
        let initialBytes = try JSONValue.object(["dynamic": .array(fields.map { $0.jsonValue() })]).serialized().count
        fields[4] = try ApplicationIdentityDynamicField(name: "4", value: .media(.init(url: prefix + String(repeating: "x", count: serializedBytes - initialBytes))))
        #expect(try JSONValue.object(["dynamic": .array(fields.map { $0.jsonValue() })]).serialized().count == serializedBytes)
        return fields
    }
}
