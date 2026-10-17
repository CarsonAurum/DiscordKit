import DiscordCore
import Foundation
import Testing
@testable import DiscordModels

/// Presence, precision, future-variant and bounded outgoing coverage for the complete identity-profile family.
@Suite struct ApplicationIdentityProfileTests {
    static let identity = #"{"provider_type":"FUTURE","provider_id":"account","provider_issued_user_id":"external%id","user_id":"18446744073709551615","future":1e1000}"#
    static let primary = #"{"season":"Season 3","rank_name":"Silver","rank_image":{"url":"https://example.com/rank","future":1.20},"highest_rank":"Gold","highest_rank_image":{"url":"https://example.com/high"},"featured_played_character":"Hero","featured_played_character_image":{"url":"https://example.com/hero"},"playtime_hours":69.4100,"total_wins":184467440737095516159999,"current_period_wins":-0,"total_games":3,"current_period_games":4,"total_kills":5,"current_period_kills":6,"total_assists":7,"current_period_assists":8,"total_deaths":9,"current_period_deaths":10,"future":2e1000}"#

    /// Wrapped lookups preserve exact external tuples, maximum snowflakes and unknown fields; empty results remain successful.
    /// - Throws: Unexpected model/fixture failures fail the test; missing and forbidden-null states are checked separately.
    @Test func identityLookups() throws {
        let value = try ApplicationIdentity(data: Data(Self.identity.utf8))
        #expect(value.providerType == "FUTURE")
        #expect(value.providerID == .value("account"))
        #expect(value.providerIssuedUserID == "external%id")
        #expect(value.userID == .value(.init(rawValue: UInt64.max)))
        #expect(value.rawFields["future"] == .number(try JSONNumber(rawValue: "1e1000")))
        let wrapped = try ApplicationIdentityList(data: Data("{\"identities\":[\(Self.identity)],\"future\":true}".utf8))
        #expect(wrapped.identities == [value])
        #expect(wrapped.rawFields["future"] == .bool(true))
        #expect(try ApplicationIdentityList(data: Data(#"{"identities":[]}"#.utf8)).identities.isEmpty)
        let minimum = try ApplicationIdentity(data: Data(#"{"provider_type":"NONE","provider_issued_user_id":"x"}"#.utf8))
        #expect(minimum.providerID == .absent && minimum.userID == .absent)
        #expect(try ApplicationIdentity(data: Data(#"{"provider_type":"NONE","provider_id":"","provider_issued_user_id":"x"}"#.utf8)).providerID == .value(""))
        #expect(value.description == "ApplicationIdentity(redacted)")
        #expect(!value.debugDescription.contains("external%id"))
        #expect(value.customMirror.children.count == 1)
        #expect(try value.jsonValue().serialized() == JSONValue.parse(Data(Self.identity.utf8)).serialized())
    }

    /// All primary strings/media and ten integral counters remain typed without decimal or large-integer rounding.
    /// - Throws: Unexpected model parsing fails the test; assertions cover every named primary field.
    @Test func primaryStats() throws {
        let value = try ApplicationIdentityProfilePrimary(data: Data(Self.primary.utf8))
        #expect(value.season == .value("Season 3") && value.rankName == .value("Silver"))
        #expect(value.highestRank == .value("Gold") && value.featuredPlayedCharacter == .value("Hero"))
        #expect(Self.present(value.rankImage)?.url == "https://example.com/rank")
        #expect(Self.present(value.highestRankImage)?.url == "https://example.com/high")
        #expect(Self.present(value.featuredPlayedCharacterImage)?.url == "https://example.com/hero")
        #expect(value.playtimeHours == .value(try JSONNumber(rawValue: "69.4100")))
        let actual = [value.totalWins, value.currentPeriodWins, value.totalGames, value.currentPeriodGames,
            value.totalKills, value.currentPeriodKills, value.totalAssists, value.currentPeriodAssists,
            value.totalDeaths, value.currentPeriodDeaths]
        let expected = ["184467440737095516159999", "-0", "3", "4", "5", "6", "7", "8", "9", "10"]
        #expect(actual == (try expected.map { .value(try JSONNumber(rawValue: $0)) }))
        #expect(value.rawFields["future"] == .number(try JSONNumber(rawValue: "2e1000")))
        let empty = try ApplicationIdentityProfilePrimary(data: Data("{}".utf8))
        #expect(empty.season == .absent && empty.rankImage == .absent && empty.playtimeHours == .absent)
        #expect(empty.totalWins == .absent && empty.currentPeriodDeaths == .absent)
    }

    /// Known dynamic variants validate matching value types; future discriminators retain their original value exactly.
    /// - Throws: Unexpected model/number/media construction fails the test.
    @Test func dynamicVariants() throws {
        let string = try ApplicationIdentityProfileDynamicField(data: Data(#"{"type":1,"name":"text","value":"hello"}"#.utf8))
        let number = try ApplicationIdentityProfileDynamicField(data: Data(#"{"type":2,"name":"number","value":123.4500}"#.utf8))
        let media = try ApplicationIdentityProfileDynamicField(data: Data(#"{"type":3,"name":"asset","value":{"url":"https://example.com/a","future":true}}"#.utf8))
        let future = try ApplicationIdentityProfileDynamicField(data: Data(#"{"type":99,"name":"new","value":{"v":1e1000},"future":true}"#.utf8))
        #expect(string.type.knownValue == .string && string.name == "text" && string.value == .string("hello"))
        #expect(number.value == .number(try JSONNumber(rawValue: "123.4500")))
        if case .media(let value) = media.value { #expect(value.url == "https://example.com/a" && value.rawFields["future"] == .bool(true)) }
        else { Issue.record("Expected typed media") }
        #expect(future.type.rawValue == 99 && future.type.knownValue == nil)
        #expect(future.value == .unknown(.object(["v": .number(try JSONNumber(rawValue: "1e1000"))])))
        #expect(try ApplicationIdentityProfileDynamicField(data: Data(#"{"type":99,"name":"new","value":null}"#.utf8)).value == .unknown(.null))
    }

    /// Complete profiles require nullable username/metadata/data keys, retaining typed nested stats and arbitrary metadata.
    /// - Throws: Unexpected fixture parsing fails the test; required-nullable and absent nested semantics are asserted.
    @Test func profilePresence() throws {
        let null = try ApplicationIdentityProfile(data: Data(#"{"username":null,"metadata":null,"data":null,"future":1e1000}"#.utf8))
        #expect(null.username == .null && null.metadata == .null && null.data == .null)
        let profile = try ApplicationIdentityProfile(data: Data("{\"username\":\"name\",\"metadata\":{\"x\":1e1000},\"data\":{\"primary\":\(Self.primary),\"dynamic\":[]},\"future\":true}".utf8))
        #expect(profile.username == .value("name"))
        #expect(profile.metadata == .value(["x": .number(try JSONNumber(rawValue: "1e1000"))]))
        guard case .value(let data) = profile.data else { Issue.record("Expected typed stats"); return }
        #expect(data.dynamic == .value([]))
        #expect(Self.present(data.primary)?.season == .value("Season 3"))
        let emptyData = try ApplicationIdentityProfileData(data: Data("{}".utf8))
        #expect(emptyData.primary == .absent && emptyData.dynamic == .absent)
        #expect(profile.rawFields["future"] == .bool(true))
        #expect(!String(reflecting: profile).contains("name"))
    }

    /// Each missing/null/wrong-root/wrong-scalar case fails safely across all response types, including exact integer checks.
    /// - Parameter fixture: Invalid complete identity-profile response fixture.
    /// - Throws: Only unexpected harness errors escape; every decoder rejection is asserted.
    @Test(arguments: ["null", "[]", "{}", #"{"username":null,"metadata":null}"#, #"{"username":12,"metadata":null,"data":null}"#, #"{"username":null,"metadata":[],"data":null}"#, #"{"username":null,"metadata":null,"data":{"primary":null}}"#, #"{"username":null,"metadata":null,"data":{"dynamic":null}}"#, #"{"username":null,"metadata":null,"data":{"dynamic":[{}]}}"#])
    func invalidProfiles(fixture: String) throws {
        #expect(throws: DiscordError.transport(.invalidResponse)) { try ApplicationIdentityProfile(data: Data(fixture.utf8)) }
    }

    /// Optional primary members reject explicit null/wrong types; integral counters reject fractional/exponent lexemes.
    /// - Parameters:
    ///   - field: Every modeled primary field, classified by its expected wire representation.
    ///   - bad: Null, Boolean, array or another universally invalid scalar/container value.
    /// - Throws: Unexpected harness errors fail the test.
    @Test(arguments: ["season", "rank_name", "highest_rank", "featured_played_character", "rank_image", "highest_rank_image", "featured_played_character_image", "playtime_hours", "total_wins", "current_period_wins", "total_games", "current_period_games", "total_kills", "current_period_kills", "total_assists", "current_period_assists", "total_deaths", "current_period_deaths"], ["null", "true", "[]"])
    func invalidPrimaryFields(field: String, bad: String) throws {
        #expect(throws: DiscordError.transport(.invalidResponse)) {
            try ApplicationIdentityProfilePrimary(data: Data("{\"\(field)\":\(bad)}".utf8))
        }
    }

    /// Incomplete identity tuples, nullable optional fields and malformed large snowflakes never become valid account mappings.
    /// - Parameter fixture: Invalid tuple or wrapped identity array.
    /// - Throws: Unexpected harness errors fail the test.
    @Test(arguments: ["{}", #"{"provider_type":"NONE"}"#, #"{"provider_issued_user_id":"x"}"#, #"{"provider_type":1,"provider_issued_user_id":"x"}"#, #"{"provider_type":"NONE","provider_id":null,"provider_issued_user_id":"x"}"#, #"{"provider_type":"NONE","provider_issued_user_id":"x","user_id":"18446744073709551616"}"#])
    func invalidIdentities(fixture: String) throws {
        #expect(throws: DiscordError.transport(.invalidResponse)) { try ApplicationIdentity(data: Data(fixture.utf8)) }
        #expect(throws: DiscordError.transport(.invalidResponse)) { try ApplicationIdentityList(data: Data("{\"identities\":[\(fixture)]}".utf8)) }
    }

    /// Dynamic discriminators and known value shapes are strict; unknown complete variants remain separately supported.
    /// - Parameter fixture: Malformed dynamic-field JSON object.
    /// - Throws: Unexpected harness errors fail the test.
    @Test(arguments: ["{}", #"{"type":1,"name":"x","value":null}"#, #"{"type":1,"name":"x","value":3}"#, #"{"type":2,"name":"x","value":"3"}"#, #"{"type":2,"name":"x","value":true}"#, #"{"type":3,"name":"x","value":{}}"#, #"{"type":3,"name":"x","value":{"url":null}}"#, #"{"type":1.0,"name":"x","value":"y"}"#, #"{"type":1e0,"name":"x","value":"y"}"#, #"{"type":1,"name":null,"value":"y"}"#, #"{"type":99,"name":"x"}"#])
    func invalidDynamicFields(fixture: String) throws {
        #expect(throws: DiscordError.transport(.invalidResponse)) { try ApplicationIdentityProfileDynamicField(data: Data(fixture.utf8)) }
    }

    /// Root bounds cover unknown fields and nested models, while malformed or duplicate/trailing JSON is rejected first.
    /// - Throws: Unexpected harness errors fail the test; precise parser categories are asserted.
    @Test func documentBoundsAndSyntax() throws {
        let bytes = Data(Self.identity.utf8)
        #expect(throws: JSONValueError.maximumBytesExceeded) {
            try ApplicationIdentity(data: bytes, limits: .init(maximumBytes: bytes.count - 1))
        }
        #expect(throws: JSONValueError.maximumNodesExceeded) {
            try ApplicationIdentity(data: bytes, limits: .init(maximumNodes: 2))
        }
        #expect(throws: JSONValueError.maximumDepthExceeded) {
            try ApplicationIdentityList(data: Data("{\"identities\":[\(Self.identity)]}".utf8), limits: .init(maximumDepth: 2))
        }
        for malformed in ["{", "{}{}", #"{"identities":[],"identities":[]}"#] {
            #expect(throws: JSONValueError.self) { try ApplicationIdentityList(data: Data(malformed.utf8)) }
        }
        for malformed in ["null", "{}", #"{"identities":null}"#, #"{"identities":{}}"#] {
            #expect(throws: DiscordError.transport(.invalidResponse)) { try ApplicationIdentityList(data: Data(malformed.utf8)) }
        }
        for bad in ["1.0", "1e2", "-1.001"] {
            #expect(throws: DiscordError.transport(.invalidResponse)) {
                try ApplicationIdentityProfilePrimary(data: Data("{\"total_wins\":\(bad)}".utf8))
            }
        }
    }
    /// Extracts an associated present value for focused nested assertions without weakening production presence types.
    /// - Parameter field: The already parsed optional field; absent and null return nil.
    /// - Returns: Associated value only when explicitly present; no state mutation occurs.
    private static func present<Value>(_ field: Field<Value>) -> Value? {
        if case .value(let value) = field { return value }
        return nil
    }

}
