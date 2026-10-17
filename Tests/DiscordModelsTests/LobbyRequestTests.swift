import DiscordCore
import Testing
@testable import DiscordModels

/// Validated Lobby bodies preserve exact wire selections, reject published constraint failures and redact private data.
/// All tests are synchronous and offline; they assert request construction without performing Discord mutations.
@Suite struct LobbyRequestTests {
    /// Every optional default remains omitted, while selected IDs and the required root-array shape remain exact.
    /// Empty create/modify member replacements, explicit false removal and empty unlink objects remain distinct.
    /// - Throws: Unexpected valid request or JSON-number construction failures fail the test.
    @Test func defaultsAndPresence() throws {
        #expect(try CreateLobbyRequest().jsonValue() == .object([:]))
        #expect(try ModifyLobbyRequest().jsonValue() == .object([:]))
        #expect(try ModifyLobbyMemberRequest().jsonValue() == .object([:]))
        #expect(try CreateLobbyRequest(members: []).jsonValue() == .object(["members": .array([])]))
        #expect(try ModifyLobbyRequest(members: []).jsonValue() == .object(["members": .array([])]))
        #expect(try CreateLobbyRequest(metadata: .null).jsonValue() == .object(["metadata": .null]))
        #expect(try ModifyLobbyRequest(metadata: .value([:])).jsonValue() == .object(["metadata": .object([:])]))
        #expect(try CreateOrJoinLobbyRequest(secret: "").jsonValue() == .object(["secret": .string("")]))
        #expect(try SendLobbyMessageRequest(content: " ").jsonValue() == .object(["content": .string(" ")]))
        #expect(try LobbyMessageModerationRequest(metadata: [:]).jsonValue() == .object([:]))
        let id = UserID(rawValue: .max)
        let member = try LobbyMemberRequest(id: id)
        #expect(member.id == id && member.jsonValue() == .object(["id": .string("18446744073709551615")]))
        let absent = try BulkLobbyMemberRequest(id: id)
        let explicit = try BulkLobbyMemberRequest(id: id, removeMember: false)
        #expect(absent.id == id && absent.removeMember == nil && explicit.removeMember == false)
        #expect(absent.jsonValue() != explicit.jsonValue())
        #expect(explicit.jsonValue() == .object(["id": .string("18446744073709551615"), "remove_member": .bool(false)]))
        let bulk = try BulkUpdateLobbyMembersRequest(members: [absent])
        #expect(bulk.members.count == 1 && bulk.members[0].id == id)
        #expect(bulk.jsonValue() == .array([absent.jsonValue()]))
        #expect(LinkLobbyChannelRequest().channelID == nil)
        #expect(LinkLobbyChannelRequest().jsonValue() == .object([:]))
    }

    /// Complete create/modify member replacement arrays and lobby metadata encode only their documented keys.
    /// Member display-name nulls clear, flags retain full-width future bits and IDs never pass through floating point.
    /// - Throws: Unexpected valid request construction failures fail the test.
    @Test func completeCreateAndModify() throws {
        let member = try LobbyMemberRequest(id: .init(rawValue: .max), metadata: .value(["character": "mage"]),
            flags: .init(rawValue: .max), additionalName: .value("Twindly Shimmerleaf"))
        let expectedMember: JSONValue = .object(["id": .string("18446744073709551615"),
            "metadata": .object(["character": .string("mage")]), "flags": .number(try JSONNumber(rawValue: "18446744073709551615")),
            "additional_name": .string("Twindly Shimmerleaf")])
        #expect(member.jsonValue() == expectedMember)
        let create = try CreateLobbyRequest(metadata: .value(["topic": "private"]), members: [member], idleTimeoutSeconds: 5)
        #expect(create.jsonValue() == .object(["metadata": .object(["topic": .string("private")]),
            "members": .array([expectedMember]), "idle_timeout_seconds": .number(try JSONNumber(rawValue: "5"))]))
        let clear = try LobbyMemberRequest(id: .init(rawValue: 0), metadata: .null, flags: [], additionalName: .null)
        #expect(clear.jsonValue() == .object(["id": .string("0"), "metadata": .null,
            "flags": .number(try JSONNumber(rawValue: "0")), "additional_name": .null]))
        let modify = try ModifyLobbyRequest(metadata: .null, members: [clear], idleTimeoutSeconds: 604800)
        #expect(modify.jsonValue() == .object(["metadata": .null, "members": .array([clear.jsonValue()]),
            "idle_timeout_seconds": .number(try JSONNumber(rawValue: "604800"))]))
    }

    /// Caller-owned create/join metadata maps retain independent omit/null/value choices and the original secret.
    /// - Throws: Unexpected valid request construction failures fail the test.
    @Test func completeCreateOrJoin() throws {
        let secret = "private-secret/\"é"
        let request = try CreateOrJoinLobbyRequest(secret: secret, idleTimeoutSeconds: 604800,
            lobbyMetadata: .value(["mode": "ranked"]), memberMetadata: .null)
        #expect(request.jsonValue() == .object(["secret": .string(secret),
            "idle_timeout_seconds": .number(try JSONNumber(rawValue: "604800")),
            "lobby_metadata": .object(["mode": .string("ranked")]), "member_metadata": .null]))
        #expect(try CreateOrJoinLobbyRequest(secret: "s", lobbyMetadata: .null, memberMetadata: .value([:])).jsonValue()
            == .object(["secret": .string("s"), "lobby_metadata": .null, "member_metadata": .object([:])]))
    }

    /// Upsert and bulk mutation fields preserve the same member edits without adding a body user ID to route upserts.
    /// Explicit removal entries keep caller order and do not turn a partial returned upsert array into success claims.
    /// - Throws: Unexpected valid request construction failures fail the test.
    @Test func completeMemberAndBulkMutations() throws {
        let upsert = try ModifyLobbyMemberRequest(metadata: .value(["mute": "true"]), flags: .canLinkLobby,
            additionalName: .value("Name"))
        #expect(upsert.jsonValue() == .object(["metadata": .object(["mute": .string("true")]),
            "flags": .number(try JSONNumber(rawValue: "1")), "additional_name": .string("Name")]))
        #expect(try ModifyLobbyMemberRequest(metadata: .null, additionalName: .null).jsonValue()
            == .object(["metadata": .null, "additional_name": .null]))
        let remove = try BulkLobbyMemberRequest(id: .init(rawValue: .max), metadata: .null,
            flags: .init(rawValue: .max), additionalName: .null, removeMember: true)
        let add = try BulkLobbyMemberRequest(id: .init(rawValue: 9_007_199_254_740_993),
            metadata: .value([:]), flags: [], additionalName: .value("New"), removeMember: false)
        let request = try BulkUpdateLobbyMembersRequest(members: [remove, add])
        #expect(request.members.map(\.id.rawValue) == [.max, 9_007_199_254_740_993])
        #expect(request.members[0].removeMember == true && request.members[1].removeMember == false)
        #expect(request.jsonValue() == .array([remove.jsonValue(), add.jsonValue()]))
        #expect(remove.jsonValue() == .object(["id": .string("18446744073709551615"), "metadata": .null,
            "flags": .number(try JSONNumber(rawValue: "18446744073709551615")),
            "additional_name": .null, "remove_member": .bool(true)]))
    }

    /// Link requests serialize a channel snowflake exactly, while nil means the documented empty unlink object.
    @Test func channelLinkAndUnlink() {
        let id = ChannelID(rawValue: .max)
        let request = LinkLobbyChannelRequest(channelID: id)
        #expect(request.channelID == id)
        #expect(request.jsonValue() == .object(["channel_id": .string("18446744073709551615")]))
        #expect(LinkLobbyChannelRequest(channelID: nil).jsonValue() == .object([:]))
    }

    /// Message fields preserve nonempty content, independent metadata presence and all exact unsigned flag bits.
    /// No undocumented content or dispatch-metadata size bound is borrowed from ordinary guild messages.
    /// - Throws: Unexpected valid request construction failures fail the test.
    @Test func completeMessagesAndPublishedBoundsOnly() throws {
        let request = try SendLobbyMessageRequest(content: "Private message", metadata: .value(["decision": "review"]), flags: .max)
        #expect(request.jsonValue() == .object(["content": .string("Private message"),
            "metadata": .object(["decision": .string("review")]), "flags": .number(try JSONNumber(rawValue: "18446744073709551615"))]))
        #expect(try SendLobbyMessageRequest(content: "x", metadata: .null, flags: 0).jsonValue()
            == .object(["content": .string("x"), "metadata": .null, "flags": .number(try JSONNumber(rawValue: "0"))]))
        #expect(try SendLobbyMessageRequest(content: "x", metadata: .value([:])).jsonValue()
            == .object(["content": .string("x"), "metadata": .object([:])]))
        let text = String(repeating: "x", count: 3000)
        #expect(try SendLobbyMessageRequest(content: text, metadata: .value([text: text])).jsonValue()
            == .object(["content": .string(text), "metadata": .object([text: .string(text)])]))
        #expect(throws: DiscordError.validation(.invalidValue)) { try SendLobbyMessageRequest(content: "") }
    }

    /// Published idle limits accept inclusive boundaries and reject adjacent/extreme values in every owning request.
    /// - Parameter timeout: Seconds at, inside or outside the published range.
    /// - Throws: Unexpected valid request construction failures fail the test.
    @Test(arguments: [Int.min, -1, 0, 4, 5, 50, 604800, 604801, Int.max]) func idleTimeouts(timeout: Int) throws {
        if (5...604800).contains(timeout) {
            let number = JSONValue.number(try JSONNumber(rawValue: String(timeout)))
            #expect(try CreateLobbyRequest(idleTimeoutSeconds: timeout).jsonValue() == .object(["idle_timeout_seconds": number]))
            #expect(try ModifyLobbyRequest(idleTimeoutSeconds: timeout).jsonValue() == .object(["idle_timeout_seconds": number]))
            #expect(try CreateOrJoinLobbyRequest(secret: "s", idleTimeoutSeconds: timeout).jsonValue()
                == .object(["secret": .string("s"), "idle_timeout_seconds": number]))
        } else {
            #expect(throws: DiscordError.validation(.invalidValue)) { try CreateLobbyRequest(idleTimeoutSeconds: timeout) }
            #expect(throws: DiscordError.validation(.invalidValue)) { try ModifyLobbyRequest(idleTimeoutSeconds: timeout) }
            #expect(throws: DiscordError.validation(.invalidValue)) { try CreateOrJoinLobbyRequest(secret: "s", idleTimeoutSeconds: timeout) }
        }
    }

    /// All member entry points share the inclusive 1...80 scalar name bound while preserving exact decomposed Unicode.
    /// - Parameter count: Name length at valid and adjacent invalid boundaries.
    /// - Throws: Unexpected valid request construction failures fail the test.
    @Test(arguments: [0, 1, 80, 81]) func additionalNameBounds(count: Int) throws {
        let name = String(repeating: "é", count: count)
        if (1...80).contains(count) {
            let expected = JSONValue.object(["id": .string("1"), "additional_name": .string(name)])
            #expect(try LobbyMemberRequest(id: .init(rawValue: 1), additionalName: .value(name)).jsonValue() == expected)
            #expect(try BulkLobbyMemberRequest(id: .init(rawValue: 1), additionalName: .value(name)).jsonValue() == expected)
            #expect(try ModifyLobbyMemberRequest(additionalName: .value(name)).jsonValue() == .object(["additional_name": .string(name)]))
        } else {
            #expect(throws: DiscordError.validation(.invalidValue)) { try LobbyMemberRequest(id: .init(rawValue: 1), additionalName: .value(name)) }
            #expect(throws: DiscordError.validation(.invalidValue)) { try BulkLobbyMemberRequest(id: .init(rawValue: 1), additionalName: .value(name)) }
            #expect(throws: DiscordError.validation(.invalidValue)) { try ModifyLobbyMemberRequest(additionalName: .value(name)) }
        }
        let decomposed = String(repeating: "e\u{301}", count: 40)
        #expect(try ModifyLobbyMemberRequest(additionalName: .value(decomposed)).jsonValue()
            == .object(["additional_name": .string(decomposed)]))
        #expect(throws: DiscordError.validation(.invalidValue)) {
            try ModifyLobbyMemberRequest(additionalName: .value(decomposed + "x"))
        }
    }

    /// Every lobby/member metadata entry point counts keys and values together, accepts empty/null maps and preserves text.
    /// - Throws: Unexpected valid request construction failures fail the test.
    @Test func metadataCombinedLength() throws {
        let metadata = ["k": String(repeating: "é", count: 999)]
        let value = Field<[String: String]>.value(metadata)
        let expected = JSONValue.object(metadata.mapValues { .string($0) })
        #expect(try CreateLobbyRequest(metadata: value).jsonValue() == .object(["metadata": expected]))
        #expect(try ModifyLobbyRequest(metadata: value).jsonValue() == .object(["metadata": expected]))
        #expect(try CreateOrJoinLobbyRequest(secret: "s", lobbyMetadata: value, memberMetadata: value).jsonValue()
            == .object(["secret": .string("s"), "lobby_metadata": expected, "member_metadata": expected]))
        #expect(try LobbyMemberRequest(id: .init(rawValue: 1), metadata: value).jsonValue()
            == .object(["id": .string("1"), "metadata": expected]))
        #expect(try ModifyLobbyMemberRequest(metadata: value).jsonValue() == .object(["metadata": expected]))
        #expect(try BulkLobbyMemberRequest(id: .init(rawValue: 1), metadata: value).jsonValue()
            == .object(["id": .string("1"), "metadata": expected]))
        for invalid in [["k": String(repeating: "x", count: 1000)], [String(repeating: "k", count: 1001): ""],
                        ["a": String(repeating: "x", count: 499), "b": String(repeating: "x", count: 500)]] {
            #expect(throws: DiscordError.validation(.invalidValue)) { try CreateLobbyRequest(metadata: .value(invalid)) }
            #expect(throws: DiscordError.validation(.invalidValue)) { try ModifyLobbyRequest(metadata: .value(invalid)) }
            #expect(throws: DiscordError.validation(.invalidValue)) { try CreateOrJoinLobbyRequest(secret: "s", lobbyMetadata: .value(invalid)) }
            #expect(throws: DiscordError.validation(.invalidValue)) { try CreateOrJoinLobbyRequest(secret: "s", memberMetadata: .value(invalid)) }
            #expect(throws: DiscordError.validation(.invalidValue)) { try LobbyMemberRequest(id: .init(rawValue: 1), metadata: .value(invalid)) }
            #expect(throws: DiscordError.validation(.invalidValue)) { try ModifyLobbyMemberRequest(metadata: .value(invalid)) }
            #expect(throws: DiscordError.validation(.invalidValue)) { try BulkLobbyMemberRequest(id: .init(rawValue: 1), metadata: .value(invalid)) }
        }
        #expect(try ModifyLobbyMemberRequest(metadata: .value(["": ""])).jsonValue()
            == .object(["metadata": .object(["": .string("")])]))
    }

    /// Create/join secrets accept published inclusive maximum lengths using Unicode scalars, preserving exact secret text.
    /// - Parameter count: Scalar length from empty to one above the published maximum.
    /// - Throws: Unexpected valid request construction failures fail the test.
    @Test(arguments: [0, 1, 250, 251]) func secretLengths(count: Int) throws {
        let secret = String(repeating: "é", count: count)
        if count <= 250 {
            #expect(try CreateOrJoinLobbyRequest(secret: secret).jsonValue() == .object(["secret": .string(secret)]))
        } else {
            #expect(throws: DiscordError.validation(.invalidValue)) { try CreateOrJoinLobbyRequest(secret: secret) }
        }
    }

    /// Membership replacement accepts 0...25 users; bulk mutations require 1...25 and preserve identity/order.
    /// - Parameter count: Empty, ordinary, maximum and oversized member counts.
    /// - Throws: Unexpected fixture or valid request construction failures fail the test.
    @Test(arguments: [0, 1, 25, 26]) func memberCounts(count: Int) throws {
        let members = try (0..<count).map { try LobbyMemberRequest(id: .init(rawValue: UInt64($0))) }
        let bulkMembers = try (0..<count).map { try BulkLobbyMemberRequest(id: .init(rawValue: UInt64($0))) }
        if count <= 25 {
            #expect(try CreateLobbyRequest(members: members).jsonValue() == .object(["members": .array(members.map { $0.jsonValue() })]))
            #expect(try ModifyLobbyRequest(members: members).jsonValue() == .object(["members": .array(members.map { $0.jsonValue() })]))
        } else {
            #expect(throws: DiscordError.validation(.invalidValue)) { try CreateLobbyRequest(members: members) }
            #expect(throws: DiscordError.validation(.invalidValue)) { try ModifyLobbyRequest(members: members) }
        }
        if (1...25).contains(count) {
            let bulk = try BulkUpdateLobbyMembersRequest(members: bulkMembers)
            #expect(bulk.members.map(\.id.rawValue) == (0..<count).map { UInt64($0) })
            #expect(bulk.jsonValue() == .array(bulkMembers.map { $0.jsonValue() }))
        } else {
            #expect(throws: DiscordError.validation(.invalidValue)) { try BulkUpdateLobbyMembersRequest(members: bulkMembers) }
        }
    }

    /// Duplicate IDs are rejected before ambiguous replacement or conflicting upsert/removal mutations can escape construction.
    /// - Throws: Unexpected individual entry construction failures fail the test.
    @Test func duplicateMembers() throws {
        let member = try LobbyMemberRequest(id: .init(rawValue: 1))
        #expect(throws: DiscordError.validation(.invalidValue)) { try CreateLobbyRequest(members: [member, member]) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try ModifyLobbyRequest(members: [member, member]) }
        let add = try BulkLobbyMemberRequest(id: .init(rawValue: 1))
        let remove = try BulkLobbyMemberRequest(id: .init(rawValue: 1), removeMember: true)
        #expect(throws: DiscordError.validation(.invalidValue)) { try BulkUpdateLobbyMembersRequest(members: [add, add]) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try BulkUpdateLobbyMembersRequest(members: [add, remove]) }
    }

    /// Moderation metadata uses its documented free-form root dictionary and independent count/key/value bounds.
    /// - Throws: Unexpected valid boundary construction failures fail the test.
    @Test func moderationMetadataBounds() throws {
        let key = String(repeating: "é", count: 1024)
        let value = String(repeating: "é", count: 2000)
        let metadata = [key: value, "a": "1", "b": "2", "c": "3", "": ""]
        #expect(try LobbyMessageModerationRequest(metadata: metadata).jsonValue() == .object(metadata.mapValues { .string($0) }))
        #expect(throws: DiscordError.validation(.invalidValue)) {
            try LobbyMessageModerationRequest(metadata: [key + "x": value])
        }
        #expect(throws: DiscordError.validation(.invalidValue)) {
            try LobbyMessageModerationRequest(metadata: [key: value + "x"])
        }
        var tooMany = metadata; tooMany["sixth"] = "value"
        #expect(throws: DiscordError.validation(.invalidValue)) { try LobbyMessageModerationRequest(metadata: tooMany) }
    }

    /// Every request's normal/debug/reflection paths redact secrets, content, user IDs and future flag values.
    /// Explicit JSON remains available and immutable for deliberate transmission.
    /// - Throws: Unexpected valid request construction failures fail the test.
    @Test func allRequestDiagnosticsRedacted() throws {
        let privateValue = "private-sensitive-value"
        let requests: [any LobbyRequestPayload] = [
            try CreateLobbyRequest(metadata: .value(["private": privateValue])),
            try ModifyLobbyRequest(metadata: .value(["private": privateValue])),
            try CreateOrJoinLobbyRequest(secret: privateValue),
            try LobbyMemberRequest(id: .init(rawValue: .max), additionalName: .value(privateValue)),
            try ModifyLobbyMemberRequest(additionalName: .value(privateValue)),
            try BulkLobbyMemberRequest(id: .init(rawValue: .max), additionalName: .value(privateValue)),
            try BulkUpdateLobbyMembersRequest(members: [BulkLobbyMemberRequest(id: .init(rawValue: .max), additionalName: .value(privateValue))]),
            LinkLobbyChannelRequest(channelID: .init(rawValue: .max)),
            try SendLobbyMessageRequest(content: privateValue),
            try LobbyMessageModerationRequest(metadata: ["private": privateValue])
        ]
        for request in requests {
            #expect(!String(describing: request).contains(privateValue))
            #expect(!String(reflecting: request).contains(privateValue))
            #expect(!String(reflecting: request).contains("18446744073709551615"))
            #expect(request.customMirror.children.count == 1)
            #expect(request.jsonValue() == request.jsonValue())
        }
    }
}
