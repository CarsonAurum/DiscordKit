import DiscordCore
import Foundation
import Testing
@testable import DiscordModels

/// Offline Lobby resource projections preserve all written fields, exact unknown JSON and wire presence.
/// Fixtures are independently authored and never make authenticated Discord requests or hydrate related resources.
@Suite struct LobbyModelTests {
    /// Complete lobby/member/channel snapshots retain exact 64-bit IDs, nullable metadata, unknown flags and nested data.
    /// - Throws: Unexpected projection or fixture failures fail the test.
    @Test func completeLobby() throws {
        let lobby = try Lobby(data: Self.bytes(kind: "lobby"))
        #expect(lobby.id.rawValue == UInt64.max)
        #expect(lobby.applicationID.rawValue == 9_007_199_254_740_993)
        #expect(lobby.metadata == .value(["topic": "Private party"]))
        let member = try #require(lobby.members.first)
        #expect(member.id.rawValue == UInt64.max)
        #expect(member.metadata == .null)
        #expect(member.flags == .value(.max))
        #expect(member.additionalName == .value("Twindly Shimmerleaf"))
        #expect(member.rawFields["future_member"] == .bool(true))
        guard case .value(let channel) = lobby.linkedChannel else { Issue.record("Missing linked channel"); return }
        #expect(channel.id.rawValue == 9_007_199_254_740_993)
        #expect(channel.type.knownValue == .guildText)
        #expect(channel.guildID == .value(.init(rawValue: .max)))
        #expect(channel.name == .value("private-guild-text"))
        #expect(channel.rawFields["future_channel"] == .number(try JSONNumber(rawValue: "1e99")))
        #expect(try lobby.jsonValue() == JSONValue.parse(Self.bytes(kind: "lobby")))
        #expect(lobby.rawFields["future"] == .number(try JSONNumber(rawValue: "12345678901234567890.123456789")))
        #expect(try Lobby(data: Self.bytes(kind: "lobby")) == lobby)
        #expect(lobby.customMirror.children.count == 1)
        #expect(!String(describing: lobby).contains("Private party"))
        #expect(!String(reflecting: lobby).contains("Twindly"))
    }

    /// Null metadata, empty members and an absent linked channel remain distinct from a populated snapshot.
    /// Preview-only flags and webhook configuration survive exact round-trip without becoming permission claims.
    /// - Throws: Unexpected fixture/projection failures fail the test.
    @Test func lobbyPresenceAndPreviewFields() throws {
        var fields = try Self.fields(kind: "lobby")
        fields["metadata"] = .null; fields["members"] = .array([]); fields["linked_channel"] = nil
        fields["flags"] = .number(try JSONNumber(rawValue: "4294967295"))
        fields["override_event_webhooks_url"] = .null
        let lobby = try Lobby(data: JSONValue.object(fields).serialized())
        #expect(lobby.metadata == .null && lobby.members.isEmpty && lobby.linkedChannel == .absent)
        #expect(lobby.rawFields["flags"] == fields["flags"])
        #expect(lobby.rawFields["override_event_webhooks_url"] == .null)
        #expect(lobby.jsonValue() == .object(fields))
        fields["metadata"] = .object([:])
        #expect(try Lobby(data: JSONValue.object(fields).serialized()).metadata == .value([:]))
    }

    /// Every optional member field preserves omission, nullable metadata and explicit zero flags without defaults.
    /// Response names/maps are not rejected using outgoing bounds that could change independently upstream.
    /// - Throws: Unexpected fixture/projection failures fail the test.
    @Test func memberPresenceAndCapabilities() throws {
        var fields = try Self.fields(kind: "member")
        for name in ["metadata", "flags", "additional_name"] { fields[name] = nil }
        let absent = try LobbyMember(data: JSONValue.object(fields).serialized())
        #expect(absent.metadata == .absent && absent.flags == .absent && absent.additionalName == .absent)
        fields["metadata"] = .object([:]); fields["flags"] = .number(try JSONNumber(rawValue: "0"))
        fields["additional_name"] = .string("")
        let empty = try LobbyMember(data: JSONValue.object(fields).serialized())
        #expect(empty.metadata == .value([:]) && empty.flags == .value(0) && empty.additionalName == .value(""))
        #expect(empty != absent)
        fields["metadata"] = .object(["": .string(String(repeating: "x", count: 1001))])
        #expect(try LobbyMember(data: JSONValue.object(fields).serialized()).metadata == .value(["": String(repeating: "x", count: 1001)]))
        let flags = LobbyMemberFlags(rawValue: .max)
        #expect(flags.contains(.canLinkLobby))
        #expect(LobbyMemberFlags.canLinkLobby.rawValue == 1)
        #expect(LobbyMemberFlags(rawValue: 0).isEmpty)
        let future = LobbyMemberFlags(rawValue: 1 << 63)
        #expect(!future.contains(.canLinkLobby))
        #expect(future.union(.canLinkLobby).rawValue == (UInt64(1) << 63) | 1)
    }

    /// Message snapshots project full author data, captured display names and independent nullable metadata maps.
    /// Future kinds/flags and exact unknown numeric values round-trip without coercion or hidden forwarding inference.
    /// - Throws: Unexpected fixture/projection failures fail the test.
    @Test func completeMessageAndHistoricalName() throws {
        let message = try LobbyMessage(data: Self.bytes(kind: "message"))
        #expect(message.id.rawValue == .max)
        #expect(message.type.knownValue == .default)
        #expect(message.content == "Private message")
        #expect(message.lobbyID.rawValue == 9_007_199_254_740_993)
        #expect(message.channelID.rawValue == message.lobbyID.rawValue)
        #expect(message.author.id.rawValue == .max && message.author.username == "private-user")
        #expect(message.author.discriminator == "0" && message.author.globalName == .null && message.author.avatar == .null)
        #expect(message.author.rawFields["future_user"] == .bool(true))
        guard case .value(let snapshot) = message.lobbyMember else { Issue.record("Missing author-name snapshot"); return }
        #expect(snapshot.additionalName == "Name at send time")
        #expect(snapshot.rawFields["future_snapshot"] == .bool(true))
        #expect(message.metadata == .value(["dispatch": "private-value"]))
        #expect(message.moderationMetadata == .value(["decision": "review"]))
        #expect(message.flags == .max && message.applicationID.rawValue == 3)
        #expect(try message.jsonValue() == JSONValue.parse(Self.bytes(kind: "message")))
        #expect(!String(describing: message).contains("Private message"))
        #expect(!String(reflecting: message.author).contains("private-user"))
        #expect(message.customMirror.children.count == 1 && snapshot.customMirror.children.count == 1)
        #expect(!String(reflecting: snapshot).contains("Name at send time"))
    }

    /// Optional dispatch/moderation data and author-name snapshots remain absent rather than fabricated for history.
    /// Null maps, empty maps, empty content and future integral kinds are preserved without local semantic rewriting.
    /// - Parameter rawType: Known, future or negative integral message kind.
    /// - Throws: Unexpected fixture/projection failures fail the test.
    @Test(arguments: [0, 99, -1]) func messagePresenceAndFutureKinds(rawType: Int) throws {
        var fields = try Self.fields(kind: "message")
        fields["type"] = .number(try JSONNumber(rawValue: String(rawType)))
        fields["content"] = .string(""); fields["lobby_member"] = nil
        fields["metadata"] = nil; fields["moderation_metadata"] = nil
        let history = try LobbyMessage(data: JSONValue.object(fields).serialized())
        #expect(history.type.rawValue == rawType && history.type.knownValue == MessageType(rawValue: rawType))
        #expect(history.content.isEmpty && history.lobbyMember == .absent)
        #expect(history.metadata == .absent && history.moderationMetadata == .absent)
        fields["metadata"] = .null; fields["moderation_metadata"] = .object([:])
        let maps = try LobbyMessage(data: JSONValue.object(fields).serialized())
        #expect(maps.metadata == .null && maps.moderationMetadata == .value([:]))
        #expect(maps != history)
    }

    /// Invite codes and standalone historical-name snapshots retain unknown exact JSON while all diagnostics redact them.
    /// - Throws: Unexpected fixture/projection failures fail the test.
    @Test func inviteAndStandaloneSnapshot() throws {
        let invite = try LobbyInvite(data: Self.bytes(kind: "invite"))
        #expect(invite.code == "private-invite")
        #expect(try invite.jsonValue() == JSONValue.parse(Self.bytes(kind: "invite")))
        #expect(!String(describing: invite).contains("private-invite"))
        #expect(!String(reflecting: invite).contains("private-invite"))
        #expect(invite.customMirror.children.count == 1)
        let snapshot = try LobbyMessageMemberSnapshot(data: Self.bytes(kind: "snapshot"))
        #expect(snapshot.additionalName == "Name at send time")
        #expect(try snapshot.jsonValue() == JSONValue.parse(Self.bytes(kind: "snapshot")))
        #expect(!String(describing: snapshot).contains("Name at send time"))
        #expect(try LobbyMessageMemberSnapshot(data: Self.bytes(kind: "snapshot")) == snapshot)
        #expect(try LobbyInvite(data: Self.bytes(kind: "invite")) == invite)
    }

    /// Required values reject missing keys, incompatible types and forbidden nulls; required nullable metadata accepts null.
    /// - Parameter kind: One of the five independently authored Lobby response fixture families.
    /// - Throws: Unexpected fixture failures fail the test; schema failures must produce safe invalid-response errors.
    @Test(arguments: ["lobby", "member", "message", "snapshot", "invite"]) func requiredFields(kind: String) throws {
        let names: [String]
        switch kind {
        case "lobby": names = ["id", "application_id", "metadata", "members"]
        case "member": names = ["id"]
        case "message": names = ["id", "type", "content", "lobby_id", "channel_id", "author", "flags", "application_id"]
        case "snapshot": names = ["additional_name"]
        default: names = ["code"]
        }
        for name in names {
            for invalid: JSONValue? in [nil, .null, .bool(false)] {
                if kind == "lobby" && name == "metadata" && invalid == .null { continue }
                var fields = try Self.fields(kind: kind); fields[name] = invalid
                #expect(throws: DiscordError.transport(.invalidResponse)) {
                    try Self.parse(kind: kind, data: JSONValue.object(fields).serialized())
                }
            }
        }
        for invalid in [JSONValue.array([]), .null, .string("private"), .bool(false)] {
            #expect(throws: DiscordError.transport(.invalidResponse)) {
                try Self.parse(kind: kind, data: invalid.serialized())
            }
        }
    }

    /// Known optional fields reject wrong types and forbidden nulls instead of dropping invalid nested content.
    /// Nested members, authors, channel objects and name snapshots validate recursively under the root bounds.
    /// - Throws: Unexpected fixture failures fail the test.
    @Test func malformedNestedAndOptionalFields() throws {
        for (kind, names) in [("lobby", ["linked_channel"]), ("member", ["metadata", "flags", "additional_name"]),
                              ("message", ["lobby_member", "metadata", "moderation_metadata"])] {
            for name in names {
                for invalid in [JSONValue.bool(false), .array([])] {
                    var fields = try Self.fields(kind: kind); fields[name] = invalid
                    #expect(throws: DiscordError.transport(.invalidResponse)) {
                        try Self.parse(kind: kind, data: JSONValue.object(fields).serialized())
                    }
                }
                if !["metadata", "moderation_metadata"].contains(name) {
                    var fields = try Self.fields(kind: kind); fields[name] = .null
                    #expect(throws: DiscordError.transport(.invalidResponse)) {
                        try Self.parse(kind: kind, data: JSONValue.object(fields).serialized())
                    }
                }
            }
        }
        for (kind, name, invalid) in [("lobby", "members", JSONValue.array([.object([:])])),
            ("lobby", "members", .object([:])), ("lobby", "linked_channel", .object(["id": .string("1")])),
            ("message", "author", .object(["id": .string("1")])), ("message", "lobby_member", .object([:]))] {
            var fields = try Self.fields(kind: kind); fields[name] = invalid
            #expect(throws: DiscordError.transport(.invalidResponse)) {
                try Self.parse(kind: kind, data: JSONValue.object(fields).serialized())
            }
        }
        for (kind, name) in [("lobby", "metadata"), ("member", "metadata"),
                             ("message", "metadata"), ("message", "moderation_metadata")] {
            var fields = try Self.fields(kind: kind); fields[name] = .object(["private": .bool(false)])
            #expect(throws: DiscordError.transport(.invalidResponse)) {
                try Self.parse(kind: kind, data: JSONValue.object(fields).serialized())
            }
        }
    }

    /// ID strings reject overflow, nondecimal and numeric forms, while kinds/flags reject fractions, exponents and overflow.
    /// - Parameter kind: Lobby, member or message resource containing exact identifiers.
    /// - Throws: Unexpected fixture/numeric construction failures fail the test.
    @Test(arguments: ["lobby", "member", "message"]) func exactIDsAndNumbers(kind: String) throws {
        let ids: [String]
        switch kind {
        case "lobby": ids = ["id", "application_id"]
        case "message": ids = ["id", "application_id", "lobby_id", "channel_id"]
        default: ids = ["id"]
        }
        for name in ids {
            for invalid in [JSONValue.string("18446744073709551616"), .string(""), .string("-1"),
                            .string("1.5"), .string("0x10"), .number(try JSONNumber(rawValue: "1"))] {
                var fields = try Self.fields(kind: kind); fields[name] = invalid
                #expect(throws: DiscordError.transport(.invalidResponse)) {
                    try Self.parse(kind: kind, data: JSONValue.object(fields).serialized())
                }
            }
        }
        if kind != "lobby" {
            for name in kind == "message" ? ["flags", "type"] : ["flags"] {
                for number in ["1.5", "1e0", "18446744073709551616"] {
                    var fields = try Self.fields(kind: kind)
                    fields[name] = .number(try JSONNumber(rawValue: number))
                    #expect(throws: DiscordError.transport(.invalidResponse)) {
                        try Self.parse(kind: kind, data: JSONValue.object(fields).serialized())
                    }
                }
            }
            var fields = try Self.fields(kind: kind); fields["flags"] = .number(try JSONNumber(rawValue: "-1"))
            #expect(throws: DiscordError.transport(.invalidResponse)) {
                try Self.parse(kind: kind, data: JSONValue.object(fields).serialized())
            }
        }
    }

    /// Byte/node/depth limits cover unknown JSON, and malformed/duplicate/trailing input fails all public parsers.
    /// Equality against internal subtree projections confirms nested construction follows the same schema.
    /// - Parameter kind: Response fixture family.
    /// - Throws: Unexpected valid fixture/subtree failures fail the test.
    @Test(arguments: ["lobby", "member", "message", "snapshot", "invite"]) func parserBoundsAndSyntax(kind: String) throws {
        let bytes = Self.bytes(kind: kind)
        #expect(throws: JSONValueError.maximumBytesExceeded) {
            try Self.parse(kind: kind, data: bytes, limits: .init(maximumBytes: bytes.count - 1))
        }
        #expect(throws: JSONValueError.maximumNodesExceeded) {
            try Self.parse(kind: kind, data: bytes, limits: .init(maximumNodes: 1))
        }
        var fields = try Self.fields(kind: kind); fields["unknown"] = .object(["deep": .object([:])])
        #expect(throws: JSONValueError.maximumDepthExceeded) {
            try Self.parse(kind: kind, data: JSONValue.object(fields).serialized(), limits: .init(maximumDepth: 1))
        }
        #expect(throws: JSONValueError.self) { try Self.parse(kind: kind, data: Data(#"{"id":"1","id":"2"}"#.utf8)) }
        #expect(throws: JSONValueError.self) { try Self.parse(kind: kind, data: bytes + Data(" {}".utf8)) }
        #expect(throws: JSONValueError.invalidLimits) {
            try Self.parse(kind: kind, data: bytes, limits: .init(maximumDepth: 129))
        }
        let root = try JSONValue.parse(bytes)
        switch kind {
        case "lobby": #expect(try Lobby(value: root, limits: .default) == Lobby(data: bytes))
        case "member": #expect(try LobbyMember(value: root, limits: .default) == LobbyMember(data: bytes))
        case "message": #expect(try LobbyMessage(value: root, limits: .default) == LobbyMessage(data: bytes))
        case "snapshot": #expect(try LobbyMessageMemberSnapshot(value: root, limits: .default) == LobbyMessageMemberSnapshot(data: bytes))
        default: #expect(try LobbyInvite(value: root, limits: .default) == LobbyInvite(data: bytes))
        }
    }

    /// Returns independently authored complete resource fixtures with full-width identifiers and exact future numbers.
    /// - Parameter kind: Lobby, member, message, historical-name snapshot or invite family.
    /// - Returns: Complete UTF-8 object without Foundation numeric normalization.
    private static func bytes(kind: String) -> Data {
        switch kind {
        case "lobby": return Data(#"{"id":"18446744073709551615","application_id":"9007199254740993","metadata":{"topic":"Private party"},"members":[{"id":"18446744073709551615","metadata":null,"flags":18446744073709551615,"additional_name":"Twindly Shimmerleaf","future_member":true}],"linked_channel":{"id":"9007199254740993","type":0,"guild_id":"18446744073709551615","name":"private-guild-text","future_channel":1e99},"future":12345678901234567890.123456789}"#.utf8)
        case "member": return Data(#"{"id":"18446744073709551615","metadata":{"private":"value"},"flags":18446744073709551615,"additional_name":"Twindly Shimmerleaf","future":12345678901234567890.123456789}"#.utf8)
        case "message": return Data(#"{"id":"18446744073709551615","type":0,"content":"Private message","lobby_id":"9007199254740993","channel_id":"9007199254740993","author":{"id":"18446744073709551615","username":"private-user","discriminator":"0","global_name":null,"avatar":null,"future_user":true},"lobby_member":{"additional_name":"Name at send time","future_snapshot":true},"metadata":{"dispatch":"private-value"},"moderation_metadata":{"decision":"review"},"flags":18446744073709551615,"application_id":"3","future":12345678901234567890.123456789}"#.utf8)
        case "snapshot": return Data(#"{"additional_name":"Name at send time","future":12345678901234567890.123456789}"#.utf8)
        default: return Data(#"{"code":"private-invite","future":12345678901234567890.123456789}"#.utf8)
        }
    }

    /// Extracts exact fixture keys for isolated malformed-field mutations.
    /// - Parameter kind: Resource family accepted by bytes(kind:).
    /// - Returns: Original object fields, including unknown numeric lexemes.
    /// - Throws: Fixture JSON errors or a safe invalid-response error if a fixture unexpectedly ceases to be an object.
    private static func fields(kind: String) throws -> [String: JSONValue] {
        guard case .object(let fields) = try JSONValue.parse(bytes(kind: kind))
        else { throw DiscordError.transport(.invalidResponse) }
        return fields
    }

    /// Runs one public parser through a shared negative-test boundary with no external I/O.
    /// - Parameters:
    ///   - kind: Lobby response fixture family.
    ///   - data: Independently authored valid or deliberately malformed complete JSON.
    ///   - limits: Whole-document bounds; defaults to production limits.
    /// - Throws: Selected parser's JSON syntax/bounds or sanitized schema errors, asserted by callers.
    private static func parse(kind: String, data: Data, limits: JSONLimits = .default) throws {
        switch kind {
        case "lobby": _ = try Lobby(data: data, limits: limits)
        case "member": _ = try LobbyMember(data: data, limits: limits)
        case "message": _ = try LobbyMessage(data: data, limits: limits)
        case "snapshot": _ = try LobbyMessageMemberSnapshot(data: data, limits: limits)
        default: _ = try LobbyInvite(data: data, limits: limits)
        }
    }
}
