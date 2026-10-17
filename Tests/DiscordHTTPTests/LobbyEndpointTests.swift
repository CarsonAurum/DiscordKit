import DiscordCore
import DiscordModels
import DiscordTransport
import Foundation
import Testing
@testable import DiscordHTTP

/// Exact wire contracts for every written Lobby operation, without live Discord requests.
@Suite struct LobbyEndpointTests {
    /// All 16 operations preserve normalized routes, credential category, strict status and unsafe write policy.
    /// Maximum snowflakes, explicit nulls and linked-channel distinction survive production decoding.
    /// - Throws: Unexpected fixture, body, descriptor or decoding errors fail the test.
    @Test func completeCatalog() throws {
        let methods = ["POST", "PUT", "GET", "PATCH", "DELETE", "PUT", "POST", "DELETE", "DELETE", "PATCH", "PATCH", "POST", "GET", "PUT", "POST", "POST"]
        let routes = ["/lobbies", "/lobbies", "/lobbies/{lobby.id}", "/lobbies/{lobby.id}", "/lobbies/{lobby.id}",
            "/lobbies/{lobby.id}/members/{user.id}", "/lobbies/{lobby.id}/members/bulk", "/lobbies/{lobby.id}/members/{user.id}",
            "/lobbies/{lobby.id}/members/@me", "/lobbies/{lobby.id}/channel-linking", "/lobbies/{lobby.id}/channel-linking",
            "/lobbies/{lobby.id}/messages", "/lobbies/{lobby.id}/messages", "/lobbies/{lobby.id}/messages/{message.id}/moderation-metadata",
            "/lobbies/{lobby.id}/members/@me/invites", "/lobbies/{lobby.id}/members/{user.id}/invites"]
        let bodyIndices = [0, 1, 3, 5, 6, 9, 10, 11, 13], bearerIndices = [1, 8, 9, 10, 11, 12, 14]
        let catalog = try Self.catalog()
        #expect(catalog.count == 16)
        for (index, item) in catalog.enumerated() {
            let (endpoint, bytes) = item
            #expect(endpoint.method == methods[index] && endpoint.route == routes[index])
            #expect(endpoint.path.joined(separator: "/") == routes[index].replacingOccurrences(of: "{lobby.id}", with: Self.maximumID)
                .replacingOccurrences(of: "{user.id}", with: Self.maximumID).replacingOccurrences(of: "{message.id}", with: Self.maximumID).dropFirst())
            #expect(endpoint.authentication == (bearerIndices.contains(index) ? .bearer : .bot))
            #expect(endpoint.successStatuses == ([4, 7, 8, 13].contains(index) ? [204] : [0, 11].contains(index) ? [201] : [200]))
            #expect(endpoint.retrySafety == (Self.readIndices.contains(index) ? .safe : .unsafe))
            #expect((endpoint.readPolicy != nil) == Self.readIndices.contains(index))
            #expect(endpoint.invalidates == (Self.readIndices.contains(index) ? [] : lobbyTags))
            #expect(endpoint.majorParameter == nil && endpoint.usesGlobalLimit)
            #expect(endpoint.auditReason == nil && endpoint.headers.isEmpty)
            #expect((endpoint.body != nil) == bodyIndices.contains(index))
            #expect((endpoint.bulk != nil) == (index == 6))
            let request = try endpoint.makeRequest(credential: Self.credential(endpoint), userAgent: "test")
            #expect(request.url.path == "/api/v10/" + endpoint.path.joined(separator: "/"))
            #expect(try endpoint.decode(bytes) == bytes)
            for badCredential in [Credential.none, try Self.credential(endpoint, opposite: true)] {
                #expect(throws: DiscordError.validation(.missingValue)) {
                    try endpoint.makeRequest(credential: badCredential, userAgent: "test")
                }
            }
            for malformed in ["null", "{}", "[{}]", #""bad""#] {
                #expect(throws: DiscordError.transport(.invalidResponse)) { try endpoint.decode(Data(malformed.utf8)) }
            }
        }
        let bulk = catalog[6].0
        #expect(bulk.bulk?.maximumItems == 25 && bulk.bulk?.preservesOrder == false && bulk.bulk?.permitsPartialResults == true)
        #expect(bulk.bulk?.documentationURL.absoluteString == "https://docs.discord.com/developers/resources/lobby#bulk-update-lobby-members")
        #expect(try JSONValue.parse(#require(catalog[10].0.body?.bytes)) == .object([:]))
        #expect(try JSONValue.parse(#require(catalog[9].0.body?.bytes)) == .object(["channel_id": .string(Self.maximumID)]))
        #expect(try JSONValue.parse(#require(catalog[13].0.body?.bytes)) == .object(["decision": .string("reviewed")]))
    }

    /// Recent messages have only a limit, including both boundaries; no cursor or automatic traversal is invented.
    /// Caller freshness choices survive intact, nil disables reuse and invalid TTLs fail before I/O.
    /// - Throws: Unexpected valid descriptor or fixture errors fail the test; invalid values are asserted.
    @Test func recentBoundsAndReadPolicy() throws {
        let id = LobbyID(rawValue: 1)
        #expect(try LobbyEndpoints.messages(lobbyID: id).query.isEmpty)
        for limit in [1, 200] {
            #expect(try LobbyEndpoints.messages(lobbyID: id, limit: limit).query == [.init(name: "limit", value: String(limit))])
        }
        for limit in [Int.min, -1, 0, 201, Int.max] {
            #expect(throws: DiscordError.validation(.invalidValue)) { try LobbyEndpoints.messages(lobbyID: id, limit: limit) }
        }
        for policy in [ReadPolicy(coalescing: false, timeToLive: .seconds(3), tags: ["caller"]), nil] {
            for endpoint in try [Self.erase(LobbyEndpoints.get(lobbyID: id, readPolicy: policy)),
                Self.erase(LobbyEndpoints.messages(lobbyID: id, readPolicy: policy))] {
                #expect(endpoint.readPolicy?.coalescing == policy?.coalescing)
                #expect(endpoint.readPolicy?.timeToLive == policy?.timeToLive)
                #expect(endpoint.readPolicy?.tags == policy.map { $0.tags.union(lobbyTags) })
            }
        }
        for ttl in [Duration.zero, .seconds(-1)] {
            #expect(throws: DiscordError.validation(.invalidValue)) { try LobbyEndpoints.get(lobbyID: id, readPolicy: .init(timeToLive: ttl)) }
            #expect(throws: DiscordError.validation(.invalidValue)) { try LobbyEndpoints.messages(lobbyID: id, readPolicy: .init(timeToLive: ttl)) }
        }
        let related = try [
            Self.erase(ChannelEndpoints.get(channelID: .init(rawValue: 1))),
            Self.erase(MessageEndpoints.get(channelID: .init(rawValue: 1), messageID: .init(rawValue: 2))),
            Self.erase(GuildEndpoints.get(guildID: .init(rawValue: 1))),
            Self.erase(InviteEndpoints.get(code: "related-invite", authenticated: true))
        ]
        for (mutation, _) in try Self.catalog() where mutation.retrySafety == .unsafe {
            for read in related {
                let tags = try #require(read.readPolicy).tags
                #expect(!mutation.invalidates.isDisjoint(with: tags))
            }
        }
        let messages = try LobbyEndpoints.messages(lobbyID: id, limit: 1)
        #expect(try messages.decode(Data("[]".utf8)).isEmpty)
        #expect(throws: DiscordError.transport(.invalidResponse)) {
            try messages.decode(Data("[\(Self.messageJSON),\(Self.messageJSON)]".utf8))
        }
        #expect(throws: DiscordError.transport(.invalidResponse)) {
            try LobbyEndpoints.messages(lobbyID: id).decode(Data(("[" + Array(repeating: Self.messageJSON, count: 51).joined(separator: ",") + "]").utf8))
        }
    }

    /// Bulk results permit empty/silent partial upserts, preserve wire order and reject corrupt identity correlation.
    /// Removed entries never count as successful upserts, even when the server includes them erroneously.
    /// - Throws: Unexpected valid construction/decoding fails the test; invalid response identities are asserted.
    @Test func bulkResponseCorrelation() throws {
        let members = try [BulkLobbyMemberRequest(id: .init(rawValue: 1)), .init(id: .init(rawValue: 2)),
            .init(id: .init(rawValue: 3), removeMember: true)]
        let endpoint = try LobbyEndpoints.bulkUpdateMembers(lobbyID: .init(rawValue: 4), request: .init(members: members))
        #expect(try endpoint.decode(Data("[]".utf8)).isEmpty)
        #expect(try endpoint.decode(Data(#"[{"id":"2"},{"id":"1"}]"#.utf8)).map(\.id.rawValue) == [2, 1])
        #expect(try endpoint.decode(Data(#"[{"id":"2"}]"#.utf8)).map(\.id.rawValue) == [2])
        for malformed in [#"[{"id":"1"},{"id":"1"}]"#, #"[{"id":"3"}]"#, #"[{"id":"4"}]"#, "null"] {
            #expect(throws: DiscordError.transport(.invalidResponse)) { try endpoint.decode(Data(malformed.utf8)) }
        }
        let removed = try LobbyEndpoints.bulkUpdateMembers(lobbyID: .init(rawValue: 4),
            request: .init(members: [.init(id: .init(rawValue: 3), removeMember: true)]))
        #expect(try removed.decode(Data("[]".utf8)).isEmpty)
    }

    /// Builds all written operations retaining their original typed decoder and realistic independent fixtures.
    /// - Returns: Stable 16-operation catalog for descriptor and real HTTP policy integration checks.
    /// - Throws: Validated body or descriptor errors synchronously; this helper performs no I/O.
    static func catalog() throws -> [(Endpoint<Data>, Data)] {
        let id = LobbyID(rawValue: UInt64.max), user = UserID(rawValue: UInt64.max)
        return try [
            (erase(LobbyEndpoints.create(request: .init(metadata: .null, members: [], idleTimeoutSeconds: 5))), Data(lobbyJSON.utf8)),
            (erase(LobbyEndpoints.createOrJoin(request: .init(secret: "private-secret", lobbyMetadata: .null,
                memberMetadata: .value([:])))), Data(lobbyJSON.utf8)),
            (erase(LobbyEndpoints.get(lobbyID: id)), Data(lobbyJSON.utf8)),
            (erase(LobbyEndpoints.modify(lobbyID: id, request: .init(metadata: .null, members: []))), Data(lobbyJSON.utf8)),
            (erase(LobbyEndpoints.delete(lobbyID: id)), Data()),
            (erase(LobbyEndpoints.addMember(lobbyID: id, userID: user, request: .init(metadata: .null,
                flags: .canLinkLobby, additionalName: .null))), Data(memberJSON.utf8)),
            (erase(LobbyEndpoints.bulkUpdateMembers(lobbyID: id, request: .init(members: [.init(id: user)]))), Data("[\(memberJSON)]".utf8)),
            (erase(LobbyEndpoints.removeMember(lobbyID: id, userID: user)), Data()),
            (erase(LobbyEndpoints.leave(lobbyID: id)), Data()),
            (erase(LobbyEndpoints.linkChannel(lobbyID: id, channelID: .init(rawValue: UInt64.max))), Data(linkedLobbyJSON.utf8)),
            (erase(LobbyEndpoints.unlinkChannel(lobbyID: id)), Data(lobbyJSON.utf8)),
            (erase(LobbyEndpoints.sendMessage(lobbyID: id, request: .init(content: "private-message", metadata: .null, flags: 0))), Data(messageJSON.utf8)),
            (erase(LobbyEndpoints.messages(lobbyID: id)), Data("[\(messageJSON)]".utf8)),
            (erase(LobbyEndpoints.updateMessageModeration(lobbyID: id, messageID: .init(rawValue: UInt64.max),
                request: .init(metadata: ["decision": "reviewed"]))), Data()),
            (erase(LobbyEndpoints.createChannelInviteForSelf(lobbyID: id)), Data(#"{"code":"private-code"}"#.utf8)),
            (erase(LobbyEndpoints.createChannelInviteForUser(lobbyID: id, userID: user)), Data(#"{"code":"private-code"}"#.utf8))
        ]
    }

    /// Preserves request policy and original decoding while exposing response bytes for a heterogeneous catalog.
    /// - Parameter endpoint: Typed production descriptor without a path-carried credential.
    /// - Returns: Byte descriptor whose decoder first executes the complete original production decoder.
    /// - Throws: Descriptor validation errors if equivalent policy cannot be represented.
    static func erase<T: Sendable>(_ endpoint: Endpoint<T>) throws -> Endpoint<Data> {
        try Endpoint(method: endpoint.method, path: endpoint.path, route: endpoint.route, query: endpoint.query,
            authentication: endpoint.authentication, successStatuses: endpoint.successStatuses,
            majorParameter: endpoint.majorParameter, usesGlobalLimit: endpoint.usesGlobalLimit,
            auditReason: endpoint.auditReason, body: endpoint.body, headers: endpoint.headers,
            retrySafety: endpoint.retrySafety, readPolicy: endpoint.readPolicy, invalidates: endpoint.invalidates,
            bulk: endpoint.bulk, decode: { _ = try endpoint.decode($0); return $0 })
    }

    /// Selects a synthetic accepted credential or its intentionally invalid opposite without inspecting secrets.
    /// - Parameters:
    ///   - endpoint: Exact descriptor whose bot or bearer requirement is tested.
    ///   - opposite: False selects accepted authentication; true selects the rejected other credential category.
    /// - Returns: Deterministic non-live bot/bearer credential for local tests only.
    /// - Throws: Token validation errors if the synthetic fixture becomes invalid.
    static func credential<T>(_ endpoint: Endpoint<T>, opposite: Bool = false) throws -> Credential {
        let bot = (endpoint.authentication == .bot) != opposite
        return bot ? .bot(try BotToken("synthetic")) : .bearer(try BearerToken("synthetic"))
    }

    static let readIndices = [2, 12]
    static let maximumID = "18446744073709551615"
    static let lobbyJSON = #"{"id":"18446744073709551615","application_id":"18446744073709551615","metadata":null,"members":[],"future":1.234567890123456789e1000}"#
    static let linkedLobbyJSON = #"{"id":"18446744073709551615","application_id":"18446744073709551615","metadata":{},"members":[],"linked_channel":{"id":"123","type":0}}"#
    static let memberJSON = #"{"id":"18446744073709551615","metadata":null,"flags":1,"additional_name":"Player"}"#
    static let messageJSON = #"{"id":"18446744073709551615","type":0,"content":"private-message","lobby_id":"18446744073709551615","channel_id":"18446744073709551615","author":{"id":"1","username":"player","discriminator":"0","global_name":null,"avatar":null},"flags":0,"application_id":"18446744073709551615","lobby_member":{"additional_name":"Player"},"future":1.234567890123456789e1000}"#
}
