import DiscordCore
import Foundation
import Testing
@testable import DiscordModels

/// Verifies channel-owned invite contracts without claiming completion of the Invite resource batch.
@Suite struct ChannelInviteTests {
    /// Every documented invite/metadata field is projected; unknown enums, bits and numeric lexemes survive.
    /// - Throws: Unexpected invite/fixture validation, bounded JSON or required-value assertion errors fail the test; expected rejections are asserted locally.
    @Test func completeResponseAndRedaction() throws {
        let source = """
        {"type":999,"code":"secret-code","channel":{"id":"18446744073709551615","type":15},
         "guild":{"id":"1","future":1.2300},"inviter":{"id":"2","username":"private","avatar":null},
         "target_type":999,"target_user":{"id":"3","username":"streamer","avatar":null},
         "target_application":{"id":"4"},"approximate_presence_count":0,"approximate_member_count":100,
         "expires_at":null,"guild_scheduled_event":{"id":"5"},"flags":9223372036854775809,
         "roles":[{"id":"6","name":"role"}],"uses":0,"max_uses":100,"max_age":604800,
         "temporary":false,"created_at":"2026-10-16T12:00:00.123456789+00:00","future":1e1000}
        """
        let invite = try ChannelInvite(data: Data(source.utf8), requiresMetadata: true)
        #expect(invite.type.rawValue == 999 && invite.type.knownValue == nil)
        #expect(invite.code == "secret-code")
        if case .value(let channel) = invite.channel { #expect(channel.id.rawValue == UInt64.max) }
        else { Issue.record("Expected present channel") }
        #expect(invite.inviter.channelInviteValue?.id.rawValue == 2)
        #expect(invite.targetUser.channelInviteValue?.id.rawValue == 3)
        #expect(invite.targetType.channelInviteValue?.knownValue == nil)
        #expect(invite.targetApplication.channelInviteValue?.rawFields["id"] == .string("4"))
        #expect(invite.targetApplication.channelInviteValue?.id == ApplicationID(rawValue: 4))
        #expect(invite.guild.channelInviteValue?.rawFields["future"] == .number(try JSONNumber(rawValue: "1.2300")))
        #expect(invite.guildScheduledEvent.channelInviteValue?.rawFields["id"] == .string("5"))
        #expect(invite.approximatePresenceCount == .value(0))
        #expect(invite.approximateMemberCount == .value(100))
        #expect(invite.expiresAt == .null)
        #expect(invite.flags == .value(9_223_372_036_854_775_809))
        #expect(invite.roles.channelInviteValue?.count == 1)
        #expect(invite.uses == .value(0) && invite.maxUses == .value(100) && invite.maxAge == .value(604_800))
        #expect(invite.temporary == .value(false))
        #expect(invite.createdAt.channelInviteValue?.nanosecond == 123_456_789)
        #expect(try invite.jsonValue().serialized() == JSONValue.parse(Data(source.utf8)).serialized())
        #expect(!String(describing: invite).contains("secret-code"))
        #expect(!String(reflecting: invite).contains("secret-code"))
        #expect(Mirror(reflecting: invite).children.count == 1)
    }

    /// Required nullable values retain null, optional values retain absence, and metadata is independently required.
    /// - Throws: Unexpected invite/fixture validation, bounded JSON or required-value assertion errors fail the test; expected rejections are asserted locally.
    @Test func presenceAndMetadata() throws {
        let bytes = Data("{\"type\":0,\"code\":\"c\",\"channel\":null,\"expires_at\":null}".utf8)
        let invite = try ChannelInvite(data: bytes)
        #expect(invite.channel == .null && invite.expiresAt == .null)
        #expect(invite.uses == .absent && invite.createdAt == .absent && invite.guild == .absent)
        #expect(throws: DiscordError.transport(.invalidResponse)) { try ChannelInvite(data: bytes, requiresMetadata: true) }
        #expect(ChannelInviteType.guild.rawValue == 0 && ChannelInviteType.groupDM.rawValue == 1 && ChannelInviteType.friend.rawValue == 2)
        #expect(ChannelInviteTargetType.stream.rawValue == 1 && ChannelInviteTargetType.embeddedApplication.rawValue == 2)
        let flags = ChannelInviteFlags(rawValue: UInt64.max)
        #expect(flags.contains(.isGuestInvite) && flags.rawValue == UInt64.max)
        #expect(ChannelInviteFlags.isGuestInvite.rawValue == 1)
    }

    /// Invite Application type permits null and omission independently; future integers and unknown nested fields survive.
    /// Both the public partial initializer and containing invite use the same bounded subtree projection.
    /// - Throws: Unexpected invite/fixture validation, bounded JSON or required-value assertion errors fail the test; expected rejections are asserted locally.
    @Test func targetApplicationNullableTypeAndUnknownData() throws {
        let future = JSONValue.number(try JSONNumber(rawValue: "1.230000000000000000001e1000"))
        var application: [String: JSONValue] = [
            "id": .string("18446744073709551615"), "name": .string("secret app"),
            "description": .string("secret description"), "icon": .null,
            "future": .object(["exact": future]),
        ]
        let variants: [JSONValue?] = [nil, .null, .number(try JSONNumber(rawValue: "4")),
            .number(try JSONNumber(rawValue: "999999")), .number(try JSONNumber(rawValue: String(Int.min))),
            .number(try JSONNumber(rawValue: String(Int.max)))]
        for variant in variants {
            application["type"] = variant
            let bytes = try JSONValue.object(application).serialized()
            let direct = try ChannelInviteApplication(data: bytes)
            let nested = try #require(try inviteWithApplication(.object(application)).targetApplication.channelInviteValue)
            #expect(direct == nested)
            #expect(direct.id.rawValue == UInt64.max)
            #expect(direct.name == .value("secret app"))
            #expect(direct.applicationDescription == .value("secret description"))
            #expect(direct.icon == .null)
            #expect(direct.rawFields == application)
            #expect(direct.jsonValue() == .object(application))
            switch variant {
            case nil: #expect(direct.type == .absent)
            case .null?: #expect(direct.type == .null)
            case .number(let number)?: #expect(direct.type == .value(try #require(Int(number.rawValue))))
            default: Issue.record("Unexpected trusted type variant")
            }
            #expect(!direct.description.contains("secret"))
            #expect(!direct.debugDescription.contains("secret"))
            #expect(!String(reflecting: direct).contains("secret"))
            #expect(direct.customMirror.children.count == 1)
        }
        let minimal = try ChannelInviteApplication(data: Data(#"{"id":"5"}"#.utf8))
        #expect(minimal.name == .absent)
        #expect(minimal.applicationDescription == .absent)
        #expect(minimal.icon == .absent)
        #expect(minimal.type == .absent)
        #expect(try ChannelInviteApplication(data: Data(#"{"id":"5","icon":"hash"}"#.utf8)).icon == .value("hash"))
        #expect(try inviteWithApplication(nil).targetApplication == .absent)
        #expect(throws: DiscordError.transport(.invalidResponse)) { try inviteWithApplication(.null) }
    }

    /// Known partial Application fields retain their wire contracts while unmodeled data remains unconstrained and exact.
    /// - Parameter replacement: Missing ID, forbidden null, malformed snowflake, wrong field type or inexact integer token.
    /// - Throws: Unexpected invite/fixture validation, bounded JSON or required-value assertion errors fail the test; expected rejections are asserted locally.
    @Test(arguments: [#""id":null"#, #""id":1"#, #""id":"18446744073709551616""#, #""id":"-1""#,
                      #""name":null"#, #""name":[]"#, #""description":null"#, #""description":{}"#,
                      #""icon":1"#, #""type":"4""#, #""type":[]"#, #""type":4.000000000000000001"#,
                      #""type":4e0"#, #""type":9223372036854775808"#])
    func invalidTargetApplicationFields(replacement: String) throws {
        var application: [String: JSONValue] = ["id": .string("5")]
        guard case .object(let patch) = try JSONValue.parse("{" + replacement + "}") else { return }
        application.merge(patch) { _, updated in updated }
        #expect(throws: DiscordError.transport(.invalidResponse)) {
            try ChannelInviteApplication(data: JSONValue.object(application).serialized())
        }
        #expect(throws: DiscordError.transport(.invalidResponse)) { try inviteWithApplication(.object(application)) }
    }

    /// Standalone and nested partial Applications enforce outer byte/depth/node bounds and reject missing IDs or scalar roots.
    /// - Throws: Unexpected invite/fixture validation, bounded JSON or required-value assertion errors fail the test; expected rejections are asserted locally.
    @Test func targetApplicationBoundsAndRoots() throws {
        let application = try JSONValue.parse(#"{"id":"5","future_secret":{"nested":[{"value":1e1000}]}}"#)
        let bytes = try application.serialized()
        let invite = try inviteWithApplication(application)
        #expect(throws: JSONValueError.maximumBytesExceeded) {
            try ChannelInviteApplication(data: bytes, limits: JSONLimits(maximumBytes: 1))
        }
        #expect(throws: JSONValueError.maximumDepthExceeded) {
            try ChannelInviteApplication(data: bytes, limits: JSONLimits(maximumDepth: 1))
        }
        #expect(throws: JSONValueError.maximumNodesExceeded) {
            try ChannelInviteApplication(data: bytes, limits: JSONLimits(maximumNodes: 1))
        }
        #expect(throws: JSONValueError.maximumDepthExceeded) {
            try ChannelInvite(data: invite.jsonValue().serialized(), limits: JSONLimits(maximumDepth: 2))
        }
        for body in ["{}", "[]", "null", "true"] {
            #expect(throws: DiscordError.transport(.invalidResponse)) { try ChannelInviteApplication(data: Data(body.utf8)) }
        }
        #expect(throws: DiscordError.transport(.invalidResponse)) { try inviteWithApplication(.object([:])) }
        #expect(throws: JSONValueError.self) { try ChannelInviteApplication(data: Data("{".utf8)) }
    }

    /// The official response schema permits null count/role variants even though the written table omits nullable markers.
    /// Omission, null, zero and an empty role list remain distinct; nonnullable invite fields retain strict validation.
    /// - Throws: Unexpected invite/fixture validation, bounded JSON or required-value assertion errors fail the test; expected rejections are asserted locally.
    @Test func nullableSchemaCompatibility() throws {
        let nulls = try ChannelInvite(data: Data(#"{"type":0,"code":"c","channel":null,"expires_at":null,"approximate_presence_count":null,"approximate_member_count":null,"roles":null}"#.utf8))
        #expect(nulls.approximatePresenceCount == .null)
        #expect(nulls.approximateMemberCount == .null)
        #expect(nulls.roles == .null)
        #expect(nulls.rawFields["approximate_presence_count"] == .null)
        #expect(nulls.rawFields["approximate_member_count"] == .null)
        #expect(nulls.rawFields["roles"] == .null)
        let missing = try inviteWithApplication(nil)
        #expect(missing.approximatePresenceCount == .absent)
        #expect(missing.approximateMemberCount == .absent)
        #expect(missing.roles == .absent)
        let populated = try ChannelInvite(data: Data(#"{"type":0,"code":"c","channel":null,"expires_at":null,"approximate_presence_count":0,"approximate_member_count":0,"roles":[]}"#.utf8))
        #expect(populated.approximatePresenceCount == .value(0))
        #expect(populated.approximateMemberCount == .value(0))
        #expect(populated.roles == .value([]))
        for patch in [#""roles":false"#, #""roles":[null]"#, #""approximate_presence_count":-1"#,
                      #""approximate_member_count":1e0"#, #""approximate_member_count":1.5"#] {
            var fields = nulls.rawFields
            guard case .object(let updated) = try JSONValue.parse("{" + patch + "}") else { return }
            fields.merge(updated) { _, value in value }
            #expect(throws: DiscordError.transport(.invalidResponse)) { try ChannelInvite(data: JSONValue.object(fields).serialized()) }
        }
    }

    /// Malformed required/optional fields and resource bounds fail without leaking decoder payloads.
    /// - Parameter replacement: One wrong type, forbidden null, nonintegral or negative count.
    /// - Throws: Unexpected invite/fixture validation, bounded JSON or required-value assertion errors fail the test; expected rejections are asserted locally.
    @Test(arguments: ["\"type\":1.0", "\"type\":null", "\"code\":7", "\"channel\":[]",
                      "\"expires_at\":42", "\"roles\":[null]", "\"guild\":null", "\"uses\":-1",
                      "\"max_age\":1e1", "\"temporary\":null", "\"created_at\":\"invalid\"", "\"inviter\":{}"])
    func invalidResponse(replacement: String) throws {
        var fields: [String: JSONValue] = ["type": .number(try JSONNumber(rawValue: "0")), "code": .string("c"),
                                         "channel": .null, "expires_at": .null]
        guard case .object(let updated) = try JSONValue.parse(Data(("{" + replacement + "}").utf8)) else { return }
        fields.merge(updated) { _, new in new }
        #expect(throws: DiscordError.transport(.invalidResponse)) { try ChannelInvite(data: JSONValue.object(fields).serialized()) }
        #expect(throws: (any Error).self) { try ChannelInvite(data: Data("{}".utf8), limits: JSONLimits(maximumBytes: 1)) }
    }

    /// Exact request boundaries preserve explicit empty lists, zeros and false values without inventing defaults.
    /// - Throws: Unexpected invite/fixture validation, bounded JSON or required-value assertion errors fail the test; expected rejections are asserted locally.
    @Test func creationFieldsAndTargets() throws {
        #expect(try ChannelInviteCreate().jsonValue() == .object([:]))
        let request = ChannelInviteCreate(maxAge: 604_800, maxUses: 100, temporary: false, unique: true,
            targetType: .stream, targetUserID: .init(rawValue: UInt64.max), targetUserIDs: [], roleIDs: [.init(rawValue: 42)])
        guard case .object(let fields) = try request.jsonValue() else { Issue.record("Expected object"); return }
        #expect(fields["max_age"] == .number(try JSONNumber(rawValue: "604800")))
        #expect(fields["target_user_id"] == .string("18446744073709551615"))
        #expect(fields["target_type"] == .number(try JSONNumber(rawValue: "1")))
        #expect(fields["temporary"] == .bool(false) && fields["unique"] == .bool(true))
        #expect(fields["target_user_ids"] == .array([]) && fields["role_ids"] == .array([.string("42")]))
        #expect(try ChannelInviteCreate(maxAge: 0, maxUses: 0).jsonValue() != .object([:]))
        #expect(try ChannelInviteCreate(targetType: .embeddedApplication, targetApplicationID: .init(rawValue: 99)).jsonValue() != .object([:]))
        #expect(try ChannelInviteCreate(targetUserIDs: (0..<1_000).map { .init(rawValue: UInt64($0)) }).jsonValue() != .object([:]))
        #expect(!String(reflecting: request).contains("18446744073709551615"))
        #expect(Mirror(reflecting: request).children.count == 1)
    }

    /// Invalid ranges, cross-target combinations and explicit finite list limits fail before transmission.
    /// - Throws: Unexpected invite/fixture validation, bounded JSON or required-value assertion errors fail the test; expected rejections are asserted locally.
    @Test func invalidCreation() throws {
        let requests = [ChannelInviteCreate(maxAge: -1), .init(maxAge: 604_801), .init(maxUses: -1), .init(maxUses: 101),
            .init(targetType: .stream), .init(targetType: .embeddedApplication), .init(targetUserID: .init(rawValue: 1)),
            .init(targetApplicationID: .init(rawValue: 1)),
            .init(targetType: .stream, targetUserID: .init(rawValue: 1), targetApplicationID: .init(rawValue: 2)),
            .init(targetType: .embeddedApplication, targetUserID: .init(rawValue: 1), targetApplicationID: .init(rawValue: 2)),
            .init(targetUserIDs: Array(repeating: .init(rawValue: 1), count: 1_001)),
            .init(roleIDs: [.init(rawValue: 1), .init(rawValue: 1)]),
            .init(roleIDs: (0...250).map { .init(rawValue: UInt64($0)) })]
        for request in requests { #expect(throws: DiscordError.validation(.invalidValue)) { try request.jsonValue() } }
    }

    /// Builds one local ordinary invite around an exact optional target Application subtree.
    /// - Parameter application: Nil omits target_application; JSON null and malformed objects are passed through for validation tests.
    /// - Returns: Parsed invite with all unrelated optional fields absent.
    /// - Throws: Bounded parser or sanitized schema errors from the production invite decoder.
    private func inviteWithApplication(_ application: JSONValue?) throws -> ChannelInvite {
        var fields: [String: JSONValue] = ["type": .number(try JSONNumber(rawValue: "0")), "code": .string("c"),
                                         "channel": .null, "expires_at": .null]
        fields["target_application"] = application
        return try ChannelInvite(data: JSONValue.object(fields).serialized())
    }
}

private extension Field {
    /// Extracts a present test value without conflating explicit null and absence in production APIs.
    /// - Returns: The associated value for assertions, or nil for null/absent fields.
    var channelInviteValue: Value? {
        if case .value(let value) = self { value } else { nil }
    }
}
