// File: Tests/DiscordHTTPTests/ChannelEndpointTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import DiscordModels
import DiscordTestSupport
import DiscordTransport
import Foundation
import Testing
@testable import DiscordHTTP

/// Verifies exact routes, presence-aware payloads, query units and reuse metadata for the channel catalog.
@Suite(.timeLimit(.minutes(1))) struct ChannelEndpointTests {
    /// The complete public catalog has exact verbs, statuses, bot authorization and major-rate partitions.
    /// - Throws: Unexpected descriptor/fixture construction, decoding or required-value assertion errors fail the test; expected rejections are asserted locally.
    @Test func routeCatalog() throws {
        let expected: [(String, String)] = [
            ("GET", ""), ("PATCH", ""), ("PUT", "/voice-status"), ("DELETE", ""),
            ("PUT", "/permissions/18446744073709551615"), ("GET", "/invites"), ("POST", "/invites"),
            ("DELETE", "/permissions/18446744073709551615"), ("POST", "/followers"), ("POST", "/typing"),
            ("PUT", "/recipients/18446744073709551615"), ("DELETE", "/recipients/18446744073709551615"),
            ("POST", "/messages/9007199254740993/threads"), ("POST", "/threads"), ("POST", "/threads"),
            ("PUT", "/thread-members/@me"), ("PUT", "/thread-members/18446744073709551615"),
            ("DELETE", "/thread-members/@me"), ("DELETE", "/thread-members/18446744073709551615"),
            ("GET", "/thread-members/18446744073709551615"), ("GET", "/thread-members"),
            ("GET", "/threads/archived/public"), ("GET", "/threads/archived/private"),
            ("GET", "/users/@me/threads/archived/private"), ("GET", "/guilds/18446744073709551615/threads/active")
        ]
        let catalog = try Self.catalog()
        #expect(catalog.count == expected.count)
        for (index, entry) in catalog.enumerated() {
            let (endpoint, fixture) = entry
            let request = try endpoint.makeRequest(credential: .bot(try BotToken("synthetic")), userAgent: "DiscordBot test")
            #expect(endpoint.method == expected[index].0)
            #expect(request.url.path == "/api/v10" + (index == 24 ? expected[index].1 : "/channels/18446744073709551615" + expected[index].1))
            #expect(endpoint.authentication == .bot)
            #expect(endpoint.majorParameter == "18446744073709551615")
            let expectedStatuses: Set<Int> = index == 10 ? [201, 204] : (fixture.isEmpty ? [204] : ((12...14).contains(index) ? [201] : [200]))
            #expect(endpoint.successStatuses == expectedStatuses)
            #expect(endpoint.retrySafety == (endpoint.method == "GET" ? .safe : .unsafe))
            #expect(endpoint.readPolicy?.coalescing == (endpoint.method == "GET" ? true : nil))
            #expect(endpoint.readPolicy?.timeToLive == nil)
            #expect(endpoint.method == "GET" ? endpoint.readPolicy?.tags.contains("channel-catalog") == true : endpoint.invalidates.contains("channel-catalog"))
            #expect(try endpoint.decode(fixture) == fixture)
            #expect(throws: (any Error).self) { try endpoint.decode(Data("null".utf8)) }
        }
    }

    /// V10 member pagination is opt-in, and timestamp versus ID archive cursors retain exact units and spelling.
    /// - Throws: Unexpected descriptor/fixture construction, decoding or required-value assertion errors fail the test; expected rejections are asserted locally.
    @Test func paginationQueries() throws {
        let channel = ChannelID(rawValue: UInt64.max), user = UserID(rawValue: UInt64.max)
        let timestamp = try DiscordTimestamp(rawValue: "2026-10-16T12:34:56.123456789+00:00")
        let legacy = try ChannelEndpoints.threadMembers(channelID: channel)
        #expect(legacy.query == [.init(name: "with_member", value: "false")])
        let members = try ChannelEndpoints.threadMembers(channelID: channel, withMember: true, after: user, limit: 100, readPolicy: nil)
        #expect(members.query == [.init(name: "with_member", value: "true"), .init(name: "after", value: user.description), .init(name: "limit", value: "100")])
        #expect(members.readPolicy == nil)
        #expect(try members.decode(Data("[]".utf8)).isEmpty)
        #expect(try members.decode(Data("[\(Self.memberJSON)]".utf8)).count == 1)
        let member = try ChannelEndpoints.threadMember(channelID: channel, userID: user, withMember: true)
        #expect(member.query == [.init(name: "with_member", value: "true")])
        let publicThreads = try ChannelEndpoints.publicArchivedThreads(channelID: channel, before: timestamp, limit: 1)
        let privateThreads = try ChannelEndpoints.privateArchivedThreads(channelID: channel, before: timestamp, limit: 100)
        let joined = try ChannelEndpoints.joinedPrivateArchivedThreads(channelID: channel, before: channel, limit: 1)
        for endpoint in [publicThreads, privateThreads] { #expect(endpoint.query.first == .init(name: "before", value: timestamp.rawValue)) }
        #expect(joined.query.first == .init(name: "before", value: channel.description))
        #expect(try ChannelEndpoints.publicArchivedThreads(channelID: channel).query.isEmpty)
        #expect(try ChannelEndpoints.activeGuildThreads(guildID: .init(rawValue: 1)).query.isEmpty)
        #expect(try publicThreads.makeRequest(credential: .bot(try BotToken("synthetic")), userAgent: "test").url.absoluteString.contains("123456789%2B00%3A00"))
    }

    /// Invalid legacy cursor combinations and all zero, negative, excessive and extreme page bounds fail locally.
    /// - Parameter limit: Every invalid bounded pagination value, including machine extremes.
    /// - Throws: Unexpected descriptor/fixture construction, decoding or required-value assertion errors fail the test; expected rejections are asserted locally.
    @Test(arguments: [0, -1, 101, Int.min, Int.max]) func invalidPagination(limit: Int) throws {
        let channel = ChannelID(rawValue: 1)
        #expect(throws: DiscordError.validation(.invalidValue)) { try ChannelEndpoints.threadMembers(channelID: channel, limit: 1) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try ChannelEndpoints.threadMembers(channelID: channel, after: .init(rawValue: 1)) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try ChannelEndpoints.threadMembers(channelID: channel, withMember: true, limit: limit) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try ChannelEndpoints.publicArchivedThreads(channelID: channel, limit: limit) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try ChannelEndpoints.privateArchivedThreads(channelID: channel, limit: limit) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try ChannelEndpoints.joinedPrivateArchivedThreads(channelID: channel, limit: limit) }
    }

    /// Read-policy opt-outs, TTLs and caller tags survive augmentation; followed-channel writes invalidate both sides.
    /// - Throws: Unexpected descriptor/fixture construction, decoding or required-value assertion errors fail the test; expected rejections are asserted locally.
    @Test func scopedMetadataAndAuditReasons() throws {
        let channel = ChannelID(rawValue: UInt64.max), target = ChannelID(rawValue: 2)
        let get = try ChannelEndpoints.get(channelID: channel, readPolicy: .init(coalescing: false, timeToLive: .seconds(2), tags: ["custom"]))
        #expect(get.readPolicy?.tags == ["custom", "channel-catalog"])
        #expect(get.readPolicy?.coalescing == false)
        #expect(get.readPolicy?.timeToLive == .seconds(2))
        #expect(try ChannelEndpoints.get(channelID: channel, readPolicy: nil).readPolicy == nil)
        let follow = try ChannelEndpoints.follow(channelID: channel, targetChannelID: target, auditReason: "review + reason")
        #expect(follow.invalidates.contains("messages:\(channel)"))
        #expect(follow.invalidates.contains("messages:\(target)"))
        #expect(follow.invalidates.contains("message-search"))
        #expect(try JSONValue.parse(#require(follow.body?.storedBodyBytes)) == .object(["webhook_channel_id": .string("2")]))
        let request = try follow.makeRequest(credential: .bot(try BotToken("synthetic")), userAgent: "test")
        #expect(request.headers.contains { $0.name == "X-Audit-Log-Reason" && $0.value == "review%20%2B%20reason" })
        #expect(throws: DiscordError.validation(.invalidValue)) { try ChannelEndpoints.delete(channelID: channel, auditReason: "\n") }
        #expect(throws: DiscordError.validation(.invalidValue)) { try ChannelEndpoints.follow(channelID: channel, targetChannelID: target, auditReason: String(repeating: "a", count: 513)) }
    }

    /// Every JSON-owning operation preserves explicit nulls, arbitrary-width permission strings and nested thread fields.
    /// - Throws: Unexpected descriptor/fixture construction, decoding or required-value assertion errors fail the test; expected rejections are asserted locally.
    @Test func requestPayloadsAndRecipientIsolation() throws {
        let channel = ChannelID(rawValue: UInt64.max)
        let modify = try ChannelEndpoints.modify(channelID: channel,
            request: ChannelModify(channelType: .guildText, name: .value("renamed"), topic: .null))
        #expect(try JSONValue.parse(#require(modify.body?.storedBodyBytes)) == .object(["name": .string("renamed"), "topic": .null]))
        let status = try ChannelEndpoints.setVoiceStatus(channelID: channel, request: VoiceChannelStatus(status: nil))
        #expect(try JSONValue.parse(#require(status.body?.storedBodyBytes)) == .object(["status": .null]))
        let permissions = try ChannelEndpoints.editPermissions(channelID: channel, overwriteID: .init(rawValue: UInt64.max),
            request: ChannelPermissionEdit(type: .member, allow: .value("340282366920938463463374607431768211456"), deny: .null))
        #expect(try JSONValue.parse(#require(permissions.body?.storedBodyBytes)) == .object([
            "type": .number(try JSONNumber(rawValue: "1")), "allow": .string("340282366920938463463374607431768211456"), "deny": .null]))
        let recipient = try ChannelEndpoints.addRecipient(channelID: channel, userID: .init(rawValue: UInt64.max),
            request: GroupDMRecipientAdd(accessToken: "recipient-secret", nick: "private-nickname"))
        #expect(try JSONValue.parse(#require(recipient.body?.storedBodyBytes)) == .object(["access_token": .string("recipient-secret"), "nick": .string("private-nickname")]))
        let wire = try recipient.makeRequest(credential: .bot(try BotToken("outer-secret")), userAgent: "test")
        #expect(wire.headers.contains { $0.name == "Authorization" && $0.value == "Bot outer-secret" })
        #expect(!wire.url.absoluteString.contains("recipient-secret"))
        #expect(!String(reflecting: recipient).contains("recipient-secret"))
        #expect(!String(reflecting: recipient).contains("private-nickname"))
        let thread = try ChannelEndpoints.startThread(channelID: channel,
            request: ThreadStartWithoutMessage(name: "private", invitable: false, rateLimitPerUser: .null))
        #expect(try JSONValue.parse(#require(thread.body?.storedBodyBytes)) == .object([
            "name": .string("private"), "invitable": .bool(false), "rate_limit_per_user": .null]))
        let fromMessage = try ChannelEndpoints.startThreadFromMessage(channelID: channel, messageID: .init(rawValue: 1),
            request: ThreadStartFromMessage(name: "reply", autoArchiveDuration: 60))
        #expect(try JSONValue.parse(#require(fromMessage.body?.storedBodyBytes)) == .object([
            "name": .string("reply"), "auto_archive_duration": .number(try JSONNumber(rawValue: "60"))]))
        let forum = try ChannelEndpoints.startForumThread(channelID: channel,
            request: ForumThreadStart(name: "post", message: MessageCreate(content: .value("hello")), appliedTags: [.init(rawValue: UInt64.max)]))
        #expect(try JSONValue.parse(#require(forum.body?.storedBodyBytes)) == .object([
            "name": .string("post"), "message": .object(["content": .string("hello")]), "applied_tags": .array([.string(channel.description)])]))
    }

    /// Invites require exact list metadata, reject malformed collection envelopes and preserve nullable channels.
    /// - Throws: Unexpected descriptor/fixture construction, decoding or required-value assertion errors fail the test; expected rejections are asserted locally.
    @Test func inviteResponseAndBodies() throws {
        let channel = ChannelID(rawValue: UInt64.max)
        let list = try ChannelEndpoints.invites(channelID: channel)
        #expect(try list.decode(Data("[\(Self.inviteJSON)]".utf8)).count == 1)
        #expect(throws: (any Error).self) { try list.decode(Data("[{\"type\":0,\"code\":\"test\",\"channel\":null,\"expires_at\":null}]".utf8)) }
        for bad in ["{}", "null", "[null]"] { #expect(throws: (any Error).self) { try list.decode(Data(bad.utf8)) } }
        let create = try ChannelEndpoints.createInvite(channelID: channel)
        #expect(try JSONValue.parse(#require(create.body?.storedBodyBytes)) == .object([:]))
        #expect(try create.decode(Data(Self.inviteJSON.utf8)).code == "test")
        let csv = Data("18446744073709551615\n18446744073709551615\n".utf8)
        let upload = try ChannelEndpoints.createInvite(channelID: channel, targetUsersCSV: csv)
        #expect(upload.body?.contentType.hasPrefix("multipart/form-data; boundary=") == true)
        for maximum in [0, -1, 8 * 1_048_576 + 1] {
            #expect(throws: DiscordError.self) { try ChannelEndpoints.createInvite(channelID: channel, maximumBytes: maximum) }
        }
        for malformed in [Data(), Data("user_id\ninvalid\n".utf8), Data("user_id\n1,2\n".utf8), Data([0xff])] {
            #expect(throws: DiscordError.self) { try ChannelEndpoints.createInvite(channelID: channel, targetUsersCSV: malformed) }
        }
        #expect(throws: JSONValueError.maximumBytesExceeded) { try ChannelEndpoints.createInvite(channelID: channel, targetUsersCSV: csv, maximumBytes: 1) }
    }

    /// Common HTTP integration retains original decoders while erasing only their generic return types.
    /// - Returns: Exactly 25 descriptor/fixture pairs, in current written channel-reference order plus active threads.
    /// - Throws: Invalid fixture/request/descriptor errors, indicating a broken test setup.
    static func catalog() throws -> [(Endpoint<Data>, Data)] {
        let channel = ChannelID(rawValue: UInt64.max), user = UserID(rawValue: UInt64.max)
        let bytes = Data(channelJSON.utf8), empty = Data(), list = Data("[]".utf8)
        let overwrite = ChannelOverwriteTargetID(rawValue: UInt64.max)
        let forum = Data("{\"id\":\"18446744073709551615\",\"type\":11,\"message\":\(String(decoding: MessageEndpointTests.messageData(), as: UTF8.self))}".utf8)
        return [
            (try erase(ChannelEndpoints.get(channelID: channel)), bytes),
            (try erase(ChannelEndpoints.modify(channelID: channel, request: ChannelModify(channelType: .guildText, name: .value("updated")))), bytes),
            (try erase(ChannelEndpoints.setVoiceStatus(channelID: channel, request: VoiceChannelStatus(status: nil))), empty),
            (try erase(ChannelEndpoints.delete(channelID: channel)), bytes),
            (try erase(ChannelEndpoints.editPermissions(channelID: channel, overwriteID: overwrite, request: ChannelPermissionEdit(type: .role))), empty),
            (try erase(ChannelEndpoints.invites(channelID: channel)), Data("[\(inviteJSON)]".utf8)),
            (try erase(ChannelEndpoints.createInvite(channelID: channel)), Data(inviteJSON.utf8)),
            (try erase(ChannelEndpoints.deletePermission(channelID: channel, overwriteID: overwrite)), empty),
            (try erase(ChannelEndpoints.follow(channelID: channel, targetChannelID: .init(rawValue: 2))), Data("{\"channel_id\":\"18446744073709551615\",\"webhook_id\":\"9007199254740993\"}".utf8)),
            (try erase(ChannelEndpoints.typing(channelID: channel)), empty),
            (try erase(ChannelEndpoints.addRecipient(channelID: channel, userID: user, request: GroupDMRecipientAdd(accessToken: BearerToken("recipient-token"), nick: "recipient"))), Data("{\"id\":\"18446744073709551615\",\"type\":3}".utf8)),
            (try erase(ChannelEndpoints.removeRecipient(channelID: channel, userID: user)), empty),
            (try erase(ChannelEndpoints.startThreadFromMessage(channelID: channel, messageID: .init(rawValue: 9_007_199_254_740_993), request: ThreadStartFromMessage(name: "thread"))), bytes),
            (try erase(ChannelEndpoints.startThread(channelID: channel, request: ThreadStartWithoutMessage(name: "thread"))), bytes),
            (try erase(ChannelEndpoints.startForumThread(channelID: channel, request: ForumThreadStart(name: "post", message: MessageCreate(content: .value("hello"))))), forum),
            (try erase(ChannelEndpoints.joinThread(channelID: channel)), empty),
            (try erase(ChannelEndpoints.addThreadMember(channelID: channel, userID: user)), empty),
            (try erase(ChannelEndpoints.leaveThread(channelID: channel)), empty),
            (try erase(ChannelEndpoints.removeThreadMember(channelID: channel, userID: user)), empty),
            (try erase(ChannelEndpoints.threadMember(channelID: channel, userID: user)), Data(memberJSON.utf8)),
            (try erase(ChannelEndpoints.threadMembers(channelID: channel)), list),
            (try erase(ChannelEndpoints.publicArchivedThreads(channelID: channel)), Data("{\"threads\":[],\"members\":[],\"has_more\":false}".utf8)),
            (try erase(ChannelEndpoints.privateArchivedThreads(channelID: channel)), Data("{\"threads\":[],\"members\":[],\"has_more\":false}".utf8)),
            (try erase(ChannelEndpoints.joinedPrivateArchivedThreads(channelID: channel)), Data("{\"threads\":[],\"members\":[],\"has_more\":false}".utf8)),
            (try erase(ChannelEndpoints.activeGuildThreads(guildID: .init(rawValue: UInt64.max))), Data("{\"threads\":[],\"members\":[]}".utf8))
        ]
    }

    /// Minimal channel fixture preserves the largest unsigned ID without optional resource hydration.
    static let channelJSON = "{\"id\":\"18446744073709551615\",\"type\":0}"
    /// Thread membership fixture includes exact optional IDs and the required timestamp and notification flags.
    static let memberJSON = "{\"id\":\"18446744073709551615\",\"user_id\":\"18446744073709551615\",\"join_timestamp\":\"2026-10-16T00:00:00Z\",\"flags\":0}"
    /// Invite list fixture includes every required metadata field while retaining a nullable inaccessible channel.
    static let inviteJSON = "{\"type\":0,\"code\":\"test\",\"channel\":null,\"expires_at\":null,\"uses\":0,\"max_uses\":0,\"max_age\":86400,\"temporary\":false,\"created_at\":\"2026-10-16T00:00:00Z\"}"

    /// Preserves auth, routing, admission, body, reuse and invalidation metadata while checking the original decoder.
    /// - Parameter value: A typed channel descriptor whose decoded fixture shape remains enforced.
    /// - Returns: The same operation returning raw bytes after its original typed decoder succeeds.
    /// - Throws: Descriptor validation failures; original response failures occur when the returned decoder runs.
    private static func erase<T>(_ value: Endpoint<T>) throws -> Endpoint<Data> {
        try Endpoint(method: value.method, path: value.path, route: value.route, query: value.query,
            authentication: value.authentication, successStatuses: value.successStatuses, majorParameter: value.majorParameter,
            usesGlobalLimit: value.usesGlobalLimit, auditReason: value.auditReason, body: value.body, headers: value.headers,
            retrySafety: value.retrySafety, readPolicy: value.readPolicy, invalidates: value.invalidates, bulk: value.bulk,
            maximumQueryItems: 2_048, maximumMetadataBytes: 1_048_576, decode: { bytes in _ = try value.decode(bytes); return bytes })
    }
}
