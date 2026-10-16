import DiscordCore
import Foundation
import Testing
@testable import DiscordModels

/// Checks the initial typed projections against realistic API v10 shapes and future additions.
@Suite struct HTTPResourceTests {
    /// Decodes a large-ID user, preserving required nulls, optional absence, future enums and number spelling.
    @Test func userPresenceAndUnknownValues() throws {
        let user = try User(data: Data("""
        {"id":"18446744073709551615","username":"Nelly","discriminator":"0","global_name":null,"avatar":"a_hash",
         "bot":true,"system":false,"mfa_enabled":true,"banner":null,"accent_color":16711680,"locale":"en-US",
         "verified":true,"email":null,"flags":64,"public_flags":131072,"premium_type":99,
         "future":{"number":123456789012345678901234567890,"value":1.2300},
         "avatar_decoration_data":{"asset":"a_test","sku_id":"1144058844004233369"}}
        """.utf8))
        #expect(user.id.rawValue == UInt64.max)
        #expect(user.username == "Nelly")
        #expect(user.discriminator == "0")
        #expect(user.globalName == .null)
        #expect(user.avatar == .value("a_hash"))
        #expect(user.bot == .value(true))
        #expect(user.system == .value(false))
        #expect(user.mfaEnabled == .value(true))
        #expect(user.banner == .null)
        #expect(user.accentColor == .value(16_711_680))
        #expect(user.locale == .value("en-US"))
        #expect(user.verified == .value(true))
        #expect(user.email == .null)
        #expect(user.flags == .value(64))
        #expect(user.publicFlags == .value(131_072))
        #expect(user.premiumType == .value(RawValue(rawValue: 99)))
        if case .value(let premium) = user.premiumType { #expect(premium.knownValue == nil) }
        let future = try #require(user.rawFields["future"])
        #expect(String(decoding: try future.serialized(), as: UTF8.self).contains("1.2300"))
        #expect(String(decoding: try future.serialized(), as: UTF8.self).contains("123456789012345678901234567890"))
        #expect(user.rawFields["avatar_decoration_data"] != nil)
        #expect(String(describing: user) == "User(redacted)")
        #expect(String(reflecting: user) == "User(redacted)")
        #expect(Mirror(reflecting: user).children.count == 1)
    }

    /// Verifies optional absent/value/null cases and recognized premium values without collapsing scope omissions.
    @Test func minimalUserAndNullableAlternates() throws {
        let minimal = try User(data: fixtureUser())
        #expect(minimal.globalName == .value("Display"))
        #expect(minimal.avatar == .null)
        #expect(minimal.email == .absent)
        #expect(minimal.bot == .absent)
        #expect(minimal.premiumType == .absent)
        let populated = try User(data: fixtureUser(extra: "\"banner\":\"banner\",\"accent_color\":null,\"email\":\"a@example.test\",\"premium_type\":3"))
        #expect(populated.banner == .value("banner"))
        #expect(populated.accentColor == .null)
        #expect(populated.email == .value("a@example.test"))
        #expect(populated.premiumType == .value(RawValue(.nitroBasic)))
        #expect(minimal == (try User(data: fixtureUser())))
    }

    /// Rejects absent required nullable fields, wrong types, malformed IDs and forbidden optional nulls.
    /// - Parameter fragment: One modeled field replacement that violates the published user schema.
    @Test(arguments: ["\"id\":1", "\"id\":\"18446744073709551616\"", "\"username\":null", "\"discriminator\":1",
                      "\"bot\":null", "\"flags\":-1", "\"premium_type\":1.00000000000000001", "\"public_flags\":1e1"])
    func rejectsMalformedUserFields(fragment: String) throws {
        var fields: [String: JSONValue] = try userFields()
        guard case .object(let replacement) = try JSONValue.parse("{" + fragment + "}") else { return }
        fields.merge(replacement) { _, new in new }
        #expect(throws: DiscordError.transport(.invalidResponse)) { try User(data: JSONValue.object(fields).serialized()) }
    }

    /// Every required user field must be present; nullability does not imply key omission.
    /// - Parameter field: Required v10 key removed from an otherwise valid minimal object.
    @Test(arguments: ["id", "username", "discriminator", "global_name", "avatar"])
    func requiredUserFields(field: String) throws {
        var fields = try userFields(); fields.removeValue(forKey: field)
        #expect(throws: DiscordError.transport(.invalidResponse)) { try User(data: JSONValue.object(fields).serialized()) }
    }

    /// Decodes current application fields while retaining nested partial objects and arbitrary-width future flags.
    @Test func applicationProjectionAndUnknownFields() throws {
        let data = try fixtureApplication(extra: """
        "rpc_origins":["https://example.test"],"guild_id":"18446744073709551615","flags":8192,
        "flags_new":"340282366920938463463374607431768211455","approximate_guild_count":5,
        "approximate_user_install_count":10,"interactions_endpoint_url":null,"tags":["utility"],
        "owner":{"id":"1","username":"partial"},"new_status":999,"new_number":1e1000
        """)
        let app = try Application(data: data)
        #expect(app.id.rawValue == UInt64.max)
        #expect(app.name == "Example")
        #expect(app.icon == .null)
        #expect(app.applicationDescription == "A bot")
        #expect(app.botPublic)
        #expect(!app.botRequireCodeGrant)
        #expect(app.verifyKey == "public-key")
        #expect(app.team == .null)
        #expect(app.rpcOrigins == .value(["https://example.test"]))
        #expect(app.guildID == .value(GuildID(rawValue: UInt64.max)))
        #expect(app.flags == .value(8192))
        #expect(app.flagsNew == .value("340282366920938463463374607431768211455"))
        #expect(app.approximateGuildCount == .value(5))
        #expect(app.approximateUserInstallCount == .value(10))
        #expect(app.interactionsEndpointURL == .null)
        #expect(app.tags == .value(["utility"]))
        #expect(app.rawFields["owner"] != nil)
        #expect(app.rawFields["new_number"] == .number(try JSONNumber(rawValue: "1e1000")))
        #expect(String(describing: app) == "Application(redacted)")
        #expect(String(reflecting: app) == "Application(redacted)")
        #expect(Mirror(reflecting: app).children.count == 1)
        #expect(app == (try Application(data: data)))
    }

    /// Covers absent optional application fields and a non-null team without imposing an incomplete nested schema.
    @Test func applicationAlternateNullability() throws {
        var fields = try applicationFields()
        fields["team"] = .object(["members": .array([]), "id": .string("1")])
        fields["icon"] = .string("icon-hash")
        fields["interactions_endpoint_url"] = .string("https://example.test/interactions")
        let app = try Application(data: JSONValue.object(fields).serialized())
        #expect(app.team == .value(.object(["members": .array([]), "id": .string("1")])))
        #expect(app.icon == .value("icon-hash"))
        #expect(app.interactionsEndpointURL == .value("https://example.test/interactions"))
        #expect(app.flags == .absent)
        #expect(app.flagsNew == .absent)
        #expect(app.tags == .absent)
    }

    /// Requires every mandatory application key, including nullable team/icon fields.
    /// - Parameter field: Required application field removed from a valid fixture.
    @Test(arguments: ["id", "name", "icon", "description", "bot_public", "bot_require_code_grant", "verify_key", "team"])
    func requiredApplicationFields(field: String) throws {
        var fields = try applicationFields(); fields.removeValue(forKey: field)
        #expect(throws: DiscordError.transport(.invalidResponse)) { try Application(data: JSONValue.object(fields).serialized()) }
    }

    /// Rejects invalid team roots, optional nulls and integer coercions without leaking raw decoder text.
    /// - Parameter fragment: Invalid field patch applied to an otherwise complete fixture.
    @Test(arguments: ["\"team\":[]", "\"name\":null", "\"flags_new\":123", "\"flags\":null", "\"tags\":[1]",
                      "\"approximate_guild_count\":1.01", "\"guild_id\":\"not-an-id\""])
    func rejectsMalformedApplicationFields(fragment: String) throws {
        var fields = try applicationFields()
        guard case .object(let replacement) = try JSONValue.parse("{" + fragment + "}") else { return }
        fields.merge(replacement) { _, new in new }
        #expect(throws: DiscordError.transport(.invalidResponse)) { try Application(data: JSONValue.object(fields).serialized()) }
    }

    /// Confirms malformed/nonobject JSON and parser bounds fail before model projection.
    @Test func malformedAndBoundedPayloads() throws {
        #expect(throws: JSONValueError.self) { try User(data: Data("{".utf8)) }
        #expect(throws: DiscordError.transport(.invalidResponse)) { try User(data: Data("[]".utf8)) }
        #expect(throws: DiscordError.transport(.invalidResponse)) { try Application(data: Data("null".utf8)) }
        #expect(throws: JSONValueError.maximumBytesExceeded) { try User(data: fixtureUser(), limits: JSONLimits(maximumBytes: 1)) }
        #expect(throws: JSONValueError.maximumDepthExceeded) { try Application(data: fixtureApplication(extra: "\"future\":{}"), limits: JSONLimits(maximumDepth: 1)) }
    }

    /// Supplies a complete minimal user with optional fields supplied separately.
    /// - Parameter extra: Comma-separated additional JSON object members, or empty text.
    /// - Returns: UTF-8 fixture bytes; no production serialization is used.
    private func fixtureUser(extra: String = "") -> Data {
        Data(("{\"id\":\"1\",\"username\":\"user\",\"discriminator\":\"0\",\"global_name\":\"Display\",\"avatar\":null" + (extra.isEmpty ? "" : "," + extra) + "}").utf8)
    }

    /// Parses minimal user fields for targeted missing-key and type patches.
    /// - Returns: A valid minimal user object with required nullable keys.
    /// - Throws: Fixture parsing errors, which indicate invalid test setup.
    private func userFields() throws -> [String: JSONValue] {
        guard case .object(let fields) = try JSONValue.parse(fixtureUser()) else { throw DiscordError.validation(.invalidValue) }
        return fields
    }

    /// Builds a minimal current application with required nullable and scalar members.
    /// - Parameter extra: Additional JSON object members, or empty text.
    /// - Returns: Complete UTF-8 fixture bytes with an unsigned-maximum application snowflake.
    private func fixtureApplication(extra: String = "") -> Data {
        Data(("{\"id\":\"18446744073709551615\",\"name\":\"Example\",\"icon\":null,\"description\":\"A bot\",\"bot_public\":true,\"bot_require_code_grant\":false,\"verify_key\":\"public-key\",\"team\":null" + (extra.isEmpty ? "" : "," + extra) + "}").utf8)
    }

    /// Parses application fields for one-field schema failure tests.
    /// - Returns: Valid minimal application fields.
    /// - Throws: Safe fixture parsing errors if setup is malformed.
    private func applicationFields() throws -> [String: JSONValue] {
        guard case .object(let fields) = try JSONValue.parse(fixtureApplication()) else { throw DiscordError.validation(.invalidValue) }
        return fields
    }
}
