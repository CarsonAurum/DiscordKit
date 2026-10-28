// File: Tests/DiscordHTTPTests/UserEndpointTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import DiscordModels
import DiscordTransport
import Foundation
import Testing
@testable import DiscordHTTP

/// Exact descriptors for all twelve User operations and both application role metadata operations.
@Suite struct UserEndpointTests {
    static let userJSON = #"{"id":"18446744073709551615","username":"account","discriminator":"0","global_name":null,"avatar":null}"#
    static let guildJSON = #"{"id":"18446744073709551615","name":"guild","icon":null,"banner":null,"owner":true,"permissions":"184467440737095516160000","features":[]}"#
    static let memberJSON = #"{"roles":[],"joined_at":null,"deaf":false,"mute":false,"flags":0}"#
    static let dmJSON = #"{"id":"18446744073709551615","type":1,"recipients":[]}"#
    static let groupJSON = #"{"id":"18446744073709551615","type":3,"recipients":[],"name":null,"icon":null,"owner_id":"1"}"#
    static let connectionJSON = #"{"id":"external/id","name":null,"type":"future-service","verified":false,"friend_sync":false,"show_activity":false,"two_way_link":false,"visibility":99,"integrations":[{"id":"external/integration","type":"twitch","account":{"id":"provider/id","name":null},"guild":{"id":"1","name":"g","icon":null}}]}"#
    static let roleJSON = #"{"platform_name":null,"platform_username":null,"metadata":{}}"#
    static let metadataJSON = #"{"type":99,"key":"score","name":"Score","description":"Description"}"#

    /// Exact routes, credentials, success statuses, request bodies and replay/reuse policy match each operation contract.
    /// - Throws: Unexpected descriptor/fixture errors fail this test; missing and mismatched credentials are asserted.
    @Test func completeCatalog() throws {
        let catalog = try Self.catalog()
        #expect(catalog.count == 14)
        let methods = ["GET", "GET", "PATCH", "GET", "GET", "DELETE", "POST", "POST", "GET", "GET", "PUT", "DELETE", "GET", "PUT"]
        let routes = ["/users/@me", "/users/{user.id}", "/users/@me", "/users/@me/guilds",
            "/users/@me/guilds/{guild.id}/member", "/users/@me/guilds/{guild.id}", "/users/@me/channels", "/users/@me/channels",
            "/users/@me/connections", "/users/@me/applications/{application.id}/role-connection",
            "/users/@me/applications/{application.id}/role-connection", "/users/@me/applications/{application.id}/role-connection",
            "/applications/{application.id}/role-connections/metadata", "/applications/{application.id}/role-connections/metadata"]
        let authentication: [AuthenticationPolicy] = [.botOrBearer, .bot, .bot, .botOrBearer, .bearer, .bot,
            .bot, .bot, .botOrBearer, .bearer, .bearer, .bearer, .bot, .bot]
        for (index, item) in catalog.enumerated() {
            let endpoint = item.0
            #expect(endpoint.method == methods[index]); #expect(endpoint.route == routes[index])
            #expect(endpoint.authentication == authentication[index])
            #expect(endpoint.successStatuses == ([5, 11].contains(index) ? [204] : [200]))
            #expect(endpoint.majorParameter == ([4, 5].contains(index) ? "18446744073709551615" : nil))
            #expect(endpoint.retrySafety == (methods[index] == "GET" ? .safe : .unsafe))
            #expect((endpoint.readPolicy != nil) == (methods[index] == "GET"))
            #expect(endpoint.invalidates.isEmpty == (methods[index] == "GET"))
            #expect(endpoint.auditReason == nil); #expect(endpoint.bulk == nil); #expect(endpoint.usesGlobalLimit)
            #expect(try endpoint.decode(item.1) == item.1)
            let credential = try Self.credential(for: endpoint)
            let wire = try endpoint.makeRequest(credential: credential, userAgent: "test")
            #expect(wire.url.path == "/api/v10/" + endpoint.path.joined(separator: "/"))
            #expect(wire.headers.contains { $0.name.lowercased() == "authorization" && $0.value == (endpoint.authentication == .bearer ? "Bearer synthetic" : "Bot synthetic") })
            #expect(throws: DiscordError.validation(.missingValue)) { try endpoint.makeRequest(credential: .none, userAgent: "test") }
            if endpoint.authentication == .bearer {
                #expect(throws: DiscordError.validation(.missingValue)) { try endpoint.makeRequest(credential: .bot(BotToken("synthetic")), userAgent: "test") }
            } else if endpoint.authentication == .bot {
                #expect(throws: DiscordError.validation(.missingValue)) { try endpoint.makeRequest(credential: .bearer(BearerToken("synthetic")), userAgent: "test") }
            } else {
                #expect(try endpoint.makeRequest(credential: .bearer(BearerToken("synthetic")), userAgent: "test").headers.contains { $0.value == "Bearer synthetic" })
            }
            if index == 3 {
                #expect(endpoint.query == [.init(name: "before", value: "18446744073709551615"), .init(name: "after", value: "1"),
                    .init(name: "limit", value: "200"), .init(name: "shard", value: "3"), .init(name: "with_counts", value: "true")])
            } else { #expect(endpoint.query.isEmpty) }
            #expect((endpoint.body != nil) == [2, 6, 7, 10, 13].contains(index))
        }
        #expect(try JSONValue.parse(#require(catalog[2].0.body?.storedBodyBytes)) == .object(["username": .string("changed"), "avatar": .null]))
        #expect(try JSONValue.parse(#require(catalog[6].0.body?.storedBodyBytes)) == .object(["recipient_id": .string("18446744073709551615")]))
        #expect(try JSONValue.parse(#require(catalog[7].0.body?.storedBodyBytes)) == .object(["access_tokens": .array([.string("participant")]), "nicks": .object(["18446744073709551615": .null])]))
        #expect(try JSONValue.parse(#require(catalog[10].0.body?.storedBodyBytes)) == .object(["platform_name": .null, "metadata": .object(["score": .string("12")])]))
        #expect(try JSONValue.parse(#require(catalog[13].0.body?.storedBodyBytes)) == .array([]))
    }

    /// Each eligible read preserves explicit coalescing/TTL choices and exact invalidation tags; invalid TTLs reject early.
    /// Existing currentUser forwards the same full model/policy contract without changing its public scalar API.
    /// - Throws: Unexpected valid descriptor errors fail the test; invalid policies are asserted explicitly.
    @Test func policiesAndCurrentUserCompatibility() throws {
        for policy in [ReadPolicy(coalescing: false, timeToLive: .seconds(4), tags: ["caller"]), ReadPolicy(), nil] {
            let reads = try Self.reads(policy: policy)
            for endpoint in reads {
                #expect(endpoint.readPolicy?.coalescing == policy?.coalescing)
                #expect(endpoint.readPolicy?.timeToLive == policy?.timeToLive)
                if policy != nil { #expect(endpoint.readPolicy?.tags.contains("caller") == (policy?.tags.contains("caller") == true)) }
                #expect(endpoint.body == nil)
            }
            let old = try DiscordEndpoints.currentUser(readPolicy: policy), current = try UserEndpoints.current(readPolicy: policy)
            #expect(old.method == current.method); #expect(old.path == current.path); #expect(old.readPolicy == current.readPolicy)
            #expect(try old.decode(Data(Self.userJSON.utf8)) == current.decode(Data(Self.userJSON.utf8)))
        }
        for ttl in [Duration.zero, .seconds(-1)] {
            #expect(throws: DiscordError.validation(.invalidValue)) { try Self.reads(policy: ReadPolicy(timeToLive: ttl)) }
            #expect(throws: DiscordError.validation(.invalidValue)) { try DiscordEndpoints.currentUser(readPolicy: .init(timeToLive: ttl)) }
        }
    }

    /// Preview-null lists and clears are represented explicitly; wrong envelope types, invalid array members and DM variants reject.
    /// - Throws: Unexpected descriptor or valid schema errors fail the test.
    @Test func nullablePreviewOverlaysAndDMVariants() throws {
        let application = ApplicationID(rawValue: 1)
        let connectionResponse = try UserEndpoints.connections().decode(Data(("[" + Self.connectionJSON + "]").utf8))
        if case .value(let connections) = connectionResponse, let connection = connections.first,
           case .value(let integrations) = connection.integrations,
           let integration = integrations.first {
            #expect(integration.account.id == "provider/id"); #expect(integration.account.name == .null)
        } else { Issue.record("Expected typed nullable provider account through connections endpoint") }
        #expect(try UserEndpoints.guilds().query.isEmpty)
        #expect(try UserEndpoints.guilds().decode(Data("null".utf8)) == .null)
        #expect(try UserEndpoints.guilds().decode(Data("[]".utf8)) == .value([]))
        #expect(try UserEndpoints.connections().decode(Data("null".utf8)) == .null)
        #expect(try UserEndpoints.connections().decode(Data("[]".utf8)) == .value([]))
        #expect(try ApplicationRoleConnectionMetadataEndpoints.get(applicationID: application).decode(Data("null".utf8)) == .null)
        #expect(try ApplicationRoleConnectionMetadataEndpoints.get(applicationID: application).decode(Data("[]".utf8)) == .value([]))
        let clear = try ApplicationRoleConnectionMetadataEndpoints.update(applicationID: application, request: .init(records: .null))
        #expect(try JSONValue.parse(#require(clear.body?.storedBodyBytes)) == .null)
        #expect(try clear.decode(Data("null".utf8)) == .null)
        for endpoint in try Self.catalog().map(\.0) {
            for invalid in [Data("[null]".utf8), Data("1".utf8), Data(#"{"required":"missing"}"#.utf8)] {
                if endpoint.path.last == "role-connection", endpoint.method != "DELETE", invalid.first == UInt8(ascii: "{") { continue }
                #expect(throws: DiscordError.transport(.invalidResponse)) { try endpoint.decode(invalid) }
            }
        }
        let dm = try UserEndpoints.createDM(request: .init(recipientID: .init(rawValue: 1)))
        let group = try UserEndpoints.createGroupDM(request: .init(accessTokens: []))
        #expect(throws: DiscordError.transport(.invalidResponse)) { try dm.decode(Data(Self.groupJSON.utf8)) }
        #expect(throws: DiscordError.transport(.invalidResponse)) { try group.decode(Data(Self.dmJSON.utf8)) }
        #expect(throws: DiscordError.transport(.invalidResponse)) { try dm.decode(Data(#"{"id":"1","type":99}"#.utf8)) }
    }

    /// Explicit matching account edits start no mutation; actual changes produce one unsafe current-account PATCH.
    /// - Throws: Unexpected valid model/request/descriptor errors fail this test.
    @Test func noOpAccountEdits() throws {
        let current = try User(data: Data(Self.userJSON.utf8))
        for request in [try UserModify(), try UserModify(username: .value("account"), avatar: .null)] {
            #expect(try UserOperations.modifyIfChanged(current: current, request: request) == nil)
        }
        for request in [try UserModify(username: .value("changed")), try UserModify(banner: .null)] {
            let endpoint = try #require(try UserOperations.modifyIfChanged(current: current, request: request))
            #expect(endpoint.method == "PATCH"); #expect(endpoint.path == ["users", "@me"])
            #expect(try JSONValue.parse(#require(endpoint.body?.storedBodyBytes)) == request.jsonValue())
        }
    }

    /// Response avatar/banner hashes can be valid base64 text without representing the same uploaded bytes.
    /// Exact spelling collisions must always send an image upload; explicit null clears can still prove a no-op.
    /// - Parameter field: Each independent uploaded-image field, avatar and banner.
    /// - Throws: Unexpected fixture/request/descriptor errors fail this regression test.
    @Test(arguments: ["avatar", "banner"]) func imageHashesNeverProveUploadNoOps(field: String) throws {
        let spelling = "abcdabcdabcdabcdabcdabcdabcdabcd"
        #expect(Data(base64Encoded: spelling)?.base64EncodedString() == spelling)
        var raw = try User(data: Data(Self.userJSON.utf8)).rawFields
        raw[field] = .string(spelling)
        let snapshot = try User(data: JSONValue.object(raw).serialized())
        let upload = try UserModify(avatar: field == "avatar" ? .value(spelling) : .absent,
            banner: field == "banner" ? .value(spelling) : .absent)
        let endpoint = try #require(try UserOperations.modifyIfChanged(current: snapshot, request: upload))
        #expect(endpoint.method == "PATCH")
        #expect(try JSONValue.parse(#require(endpoint.body?.storedBodyBytes)) == .object([field: .string(spelling)]))
        let clear = try UserModify(avatar: field == "avatar" ? .null : .absent,
            banner: field == "banner" ? .null : .absent)
        #expect(try UserOperations.modifyIfChanged(current: snapshot, request: clear) != nil)
        raw[field] = .null
        let cleared = try User(data: JSONValue.object(raw).serialized())
        #expect(try UserOperations.modifyIfChanged(current: cleared, request: clear) == nil)
    }

    /// Builds all fourteen descriptors with independent complete response fixtures and their original typed decoders.
    /// - Returns: Current/get/modify user, guilds/member/leave, DM/group DM, connections, role get/update/delete,
    ///   metadata get/update in stable order. Every mutation body remains bounded immutable bytes.
    /// - Throws: Descriptor/request/fixture validation errors fail catalog consumers; no I/O occurs here.
    static func catalog() throws -> [(Endpoint<Data>, Data)] {
        let user = UserID(rawValue: UInt64.max), guild = GuildID(rawValue: UInt64.max), application = ApplicationID(rawValue: UInt64.max)
        return [
            (try erase(UserEndpoints.current()), Data(userJSON.utf8)),
            (try erase(UserEndpoints.get(userID: user)), Data(userJSON.utf8)),
            (try erase(UserEndpoints.modifyCurrent(request: .init(username: .value("changed"), avatar: .null))), Data(userJSON.utf8)),
            (try erase(UserEndpoints.guilds(query: .init(before: guild, after: .init(rawValue: 1), limit: 200,
                shard: .init(index: 3, maxConcurrency: 4), withCounts: true, largeBotSharding: true))), Data(("[" + guildJSON + "]").utf8)),
            (try erase(UserEndpoints.guildMember(guildID: guild)), Data(memberJSON.utf8)),
            (try erase(UserEndpoints.leaveGuild(guildID: guild)), Data()),
            (try erase(UserEndpoints.createDM(request: .init(recipientID: user))), Data(dmJSON.utf8)),
            (try erase(UserEndpoints.createGroupDM(request: .init(accessTokens: [BearerToken("participant")], nicks: [user: .null]))), Data(groupJSON.utf8)),
            (try erase(UserEndpoints.connections()), Data(("[" + connectionJSON + "]").utf8)),
            (try erase(UserEndpoints.roleConnection(applicationID: application)), Data(roleJSON.utf8)),
            (try erase(UserEndpoints.updateRoleConnection(applicationID: application, request: .init(platformName: .null, metadata: .value(["score": "12"])))), Data(roleJSON.utf8)),
            (try erase(UserEndpoints.deleteRoleConnection(applicationID: application)), Data()),
            (try erase(ApplicationRoleConnectionMetadataEndpoints.get(applicationID: application)), Data(("[" + metadataJSON + "]").utf8)),
            (try erase(ApplicationRoleConnectionMetadataEndpoints.update(applicationID: application, request: .init(records: .value([])))), Data(("[" + metadataJSON + "]").utf8))
        ]
    }

    /// Constructs every eligible read under one caller-selected policy so nil/default/TTL behavior is checked uniformly.
    /// - Parameter policy: Optional reuse configuration forwarded unchanged except for conservative resource tag union.
    /// - Returns: All seven unique safe reads in stable catalog order, starting no tasks or network operations.
    /// - Throws: Descriptor/policy errors, especially nonpositive TTLs; no partial read list escapes.
    static func reads(policy: ReadPolicy?) throws -> [Endpoint<Data>] {
        [try erase(UserEndpoints.current(readPolicy: policy)), try erase(UserEndpoints.get(userID: .init(rawValue: 1), readPolicy: policy)),
         try erase(UserEndpoints.guilds(readPolicy: policy)), try erase(UserEndpoints.guildMember(guildID: .init(rawValue: 1), readPolicy: policy)),
         try erase(UserEndpoints.connections(readPolicy: policy)), try erase(UserEndpoints.roleConnection(applicationID: .init(rawValue: 1), readPolicy: policy)),
         try erase(ApplicationRoleConnectionMetadataEndpoints.get(applicationID: .init(rawValue: 1), readPolicy: policy))]
    }

    /// Keeps production descriptor policy and the original typed decoder while exposing bytes for common integration tests.
    /// - Parameter endpoint: Complete immutable production descriptor; no policy or resource metadata is dropped.
    /// - Returns: Equivalent descriptor returning exact response bytes only after successful original schema validation.
    /// - Throws: Descriptor validation errors if policy cannot be represented exactly; no I/O occurs.
    static func erase<T: Sendable>(_ endpoint: Endpoint<T>) throws -> Endpoint<Data> {
        try Endpoint(method: endpoint.method, path: endpoint.path, route: endpoint.route, query: endpoint.query,
            authentication: endpoint.authentication, successStatuses: endpoint.successStatuses,
            majorParameter: endpoint.majorParameter, usesGlobalLimit: endpoint.usesGlobalLimit,
            auditReason: endpoint.auditReason, body: endpoint.body, headers: endpoint.headers,
            retrySafety: endpoint.retrySafety, readPolicy: endpoint.readPolicy, invalidates: endpoint.invalidates,
            bulk: endpoint.bulk, decode: { _ = try endpoint.decode($0); return $0 })
    }

    /// Selects synthetic credentials satisfying a descriptor without using a real Discord token or inferring scope.
    /// - Parameter endpoint: Descriptor whose declared authentication is under test.
    /// - Returns: A synthetic bearer for bearer-only operations, otherwise a synthetic bot token.
    /// - Throws: Only unexpected synthetic secret validation errors; this does not perform token exchange or I/O.
    static func credential(for endpoint: Endpoint<Data>) throws -> Credential {
        endpoint.authentication == .bearer ? .bearer(try BearerToken("synthetic")) : .bot(try BotToken("synthetic"))
    }
}
