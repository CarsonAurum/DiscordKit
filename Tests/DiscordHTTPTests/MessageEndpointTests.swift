import DiscordCore
import DiscordModels
import DiscordTestSupport
import DiscordTransport
import Foundation
import Testing
@testable import DiscordHTTP

/// Verifies the complete 5A route surface and wire/auth/policy boundaries with scripted peers.
@Suite(.timeLimit(.minutes(1))) struct MessageEndpointTests {
    let channel = ChannelID(rawValue: UInt64.max)
    let message = MessageID(rawValue: 9_007_199_254_740_993)

    /// Every documented empty-result mutation has its exact current or deprecated route,
    /// conservative replay policy, major partition, credential header and empty decoder.
    @Test func emptyMutationCatalog() throws {
        let emoji = ReactionEmoji.unicode("🔥")
        let entries: [(Endpoint<EmptyResponse>, String, String)] = [
            (try MessageEndpoints.createReaction(channelID: channel, messageID: message, emoji: emoji), "PUT", "/messages/\(message)/reactions/%F0%9F%94%A5/@me"),
            (try MessageEndpoints.deleteOwnReaction(channelID: channel, messageID: message, emoji: emoji), "DELETE", "/messages/\(message)/reactions/%F0%9F%94%A5/@me"),
            (try MessageEndpoints.deleteUserReaction(channelID: channel, messageID: message, emoji: emoji, userID: UserID(rawValue: UInt64.max)), "DELETE", "/messages/\(message)/reactions/%F0%9F%94%A5/18446744073709551615"),
            (try MessageEndpoints.deleteAllReactions(channelID: channel, messageID: message), "DELETE", "/messages/\(message)/reactions"),
            (try MessageEndpoints.deleteEmojiReactions(channelID: channel, messageID: message, emoji: emoji), "DELETE", "/messages/\(message)/reactions/%F0%9F%94%A5"),
            (try MessageEndpoints.delete(channelID: channel, messageID: message, auditReason: "review + reason"), "DELETE", "/messages/\(message)"),
            (try MessageEndpoints.pin(channelID: channel, messageID: message, auditReason: "review + reason"), "PUT", "/messages/pins/\(message)"),
            (try MessageEndpoints.unpin(channelID: channel, messageID: message), "DELETE", "/messages/pins/\(message)"),
            (try MessageEndpoints.legacyPin(channelID: channel, messageID: message), "PUT", "/pins/\(message)"),
            (try MessageEndpoints.legacyUnpin(channelID: channel, messageID: message), "DELETE", "/pins/\(message)"),
        ]
        for (endpoint, method, suffix) in entries {
            let request = try wire(endpoint)
            #expect(endpoint.method == method)
            #expect(request.url.absoluteString == "https://discord.com/api/v10/channels/\(channel)" + suffix)
            #expect(endpoint.authentication == .bot)
            #expect(endpoint.majorParameter == channel.description)
            #expect(endpoint.successStatuses == [204])
            #expect(endpoint.retrySafety == .unsafe)
            #expect(endpoint.readPolicy == nil)
            #expect(endpoint.invalidates.contains("messages:\(channel)"))
            #expect(try endpoint.decode(Data()) == EmptyResponse(data: Data()))
            #expect(throws: DiscordError.transport(.invalidResponse)) { try endpoint.decode(Data("unexpected".utf8)) }
            if endpoint.auditReason != nil {
                #expect(request.headers.contains { $0.name == "X-Audit-Log-Reason" && $0.value == "review%20%2B%20reason" })
            }
        }
    }

    /// Current message/poll reads and mutations retain typed status policy and exact IDs.
    /// Read tags include the shared message-catalog visibility scope so guild membership/role
    /// changes can invalidate cached reads, while caller TTL/custom tags remain intact.
    /// - Throws: Unexpected descriptor, codec, request or fixture construction failures fail the test.
    @Test func typedDescriptorCatalog() throws {
        let get = try MessageEndpoints.get(channelID: channel, messageID: message,
                                          readPolicy: .init(timeToLive: .seconds(2), tags: ["custom"]))
        #expect(try wire(get).url.path == "/api/v10/channels/\(channel)/messages/\(message)")
        #expect(get.readPolicy?.tags == ["custom", "message-search", "message-catalog", "messages:\(channel)"])
        #expect(get.readPolicy?.timeToLive == .seconds(2))
        #expect(try get.decode(Self.messageData()).id == message)
        #expect(throws: (any Error).self) { try get.decode(Data("{}".utf8)) }
        let create = try MessageEndpoints.create(channelID: channel, request: MessageCreate(content: .value("hello")))
        let edit = try MessageEndpoints.edit(channelID: channel, messageID: message, request: MessageEdit(content: .null))
        let crosspost = try MessageEndpoints.crosspost(channelID: channel, messageID: message)
        let end = try PollEndpoints.end(channelID: channel, messageID: message)
        for (endpoint, method, suffix) in [(create, "POST", "messages"), (edit, "PATCH", "messages/\(message)"),
                                         (crosspost, "POST", "messages/\(message)/crosspost"), (end, "POST", "polls/\(message)/expire")] {
            #expect(try wire(endpoint).url.path == "/api/v10/channels/\(channel)/" + suffix)
            #expect(endpoint.method == method)
            #expect(endpoint.authentication == .bot)
            #expect(endpoint.successStatuses == [200])
            #expect(endpoint.retrySafety == .unsafe)
            #expect(endpoint.invalidates == ["message-search", "messages:\(channel)"])
            #expect(try endpoint.decode(Self.messageData()).id == message)
        }
        #expect(try JSONValue.parse(#require(create.body?.storedBodyBytes)) == .object(["content": .string("hello")]))
        #expect(try JSONValue.parse(#require(edit.body?.storedBodyBytes)) == .object(["content": .null]))
    }

    /// History only accepts one typed cursor, exact snowflakes and supported page bounds.
    /// - Parameter position: Each supported cursor, plus the initial newest-page case.
    @Test(arguments: [nil, MessageHistoryPosition.before(MessageID(rawValue: UInt64.max)),
                      .after(MessageID(rawValue: 0)), .around(MessageID(rawValue: 42))])
    func historyCursors(position: MessageHistoryPosition?) throws {
        let endpoint = try MessageEndpoints.history(channelID: channel, position: position, limit: 100, readPolicy: nil)
        let query = try #require(URLComponents(url: wire(endpoint).url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(query.first == URLQueryItem(name: "limit", value: "100"))
        #expect(query.count == (position == nil ? 1 : 2))
        switch position {
        case .before(let id): #expect(query.last == .init(name: "before", value: id.description))
        case .after(let id): #expect(query.last == .init(name: "after", value: id.description))
        case .around(let id): #expect(query.last == .init(name: "around", value: id.description))
        case nil: break
        }
        #expect(endpoint.retrySafety == .safe)
        #expect(endpoint.readPolicy == nil)
        #expect(try endpoint.decode(Data("[]".utf8)).isEmpty)
        #expect(throws: (any Error).self) { try endpoint.decode(Data("[null]".utf8)) }
        #expect(throws: (any Error).self) { try endpoint.decode(Data("{}".utf8)) }
        let legacy = try MessageEndpoints.legacyPins(channelID: channel)
        #expect(try wire(legacy).url.path == "/api/v10/channels/\(channel)/pins")
        #expect(try legacy.decode(Data("[]".utf8)).isEmpty)
    }

    /// Reaction/voter pagination encodes burst variants, custom emoji and exact after-user IDs.
    @Test func reactionsVotersAndPinQueries() throws {
        let custom = ReactionEmoji.custom(name: "party", id: Snowflake<EmojiTag>(rawValue: UInt64.max))
        let reactions = try MessageEndpoints.reactions(channelID: channel, messageID: message, emoji: custom,
                                                       type: .burst, after: UserID(rawValue: UInt64.max), limit: 100)
        let request = try wire(reactions)
        #expect(request.url.absoluteString.contains("party%3A18446744073709551615"))
        #expect(request.url.absoluteString.contains("type=1&limit=100&after=18446744073709551615"))
        #expect(reactions.retrySafety == .safe)
        #expect(try reactions.decode(Data("[]".utf8)).isEmpty)
        #expect(try reactions.decode(Data("[\(Self.userJSON)]".utf8)).first?.id.rawValue == UInt64.max)
        #expect(throws: (any Error).self) { try reactions.decode(Data("[{}]".utf8)) }
        let voters = try PollEndpoints.voters(channelID: channel, messageID: message, answerID: 3,
                                             after: UserID(rawValue: 0), limit: 1, readPolicy: nil)
        #expect(try wire(voters).url.absoluteString.hasSuffix("/polls/\(message)/answers/3?limit=1&after=0"))
        #expect(voters.readPolicy == nil)
        #expect(try voters.decode(Data("{\"users\":[\(Self.userJSON)],\"future\":true}".utf8)).count == 1)
        for malformed in ["{}", "null", "{\"users\":null}", "{\"users\":[{}]}"] {
            #expect(throws: (any Error).self) { try voters.decode(Data(malformed.utf8)) }
        }
        let before = try DiscordTimestamp(rawValue: "2026-10-16T12:34:56.123456+00:00")
        let pins = try MessageEndpoints.pins(channelID: channel, before: before, limit: 1)
        #expect(try wire(pins).url.absoluteString.hasSuffix("?limit=1&before=2026-10-16T12%3A34%3A56.123456%2B00%3A00"))
        #expect(try pins.decode(Data("{\"items\":[],\"has_more\":false}".utf8)).items.isEmpty)
        #expect(throws: (any Error).self) { try pins.decode(Data("{}".utf8)) }
    }

    /// Rejects invalid operation limits and malformed emoji before starting a request.
    /// - Parameter limit: Zero, negative, oversized and extreme page counts.
    @Test(arguments: [0, -1, 101, Int.max, Int.min]) func invalidLimits(limit: Int) throws {
        #expect(throws: DiscordError.self) { try MessageEndpoints.history(channelID: channel, limit: limit) }
        #expect(throws: DiscordError.self) { try MessageEndpoints.reactions(channelID: channel, messageID: message, emoji: .unicode("x"), limit: limit) }
        #expect(throws: DiscordError.self) { try MessageEndpoints.pins(channelID: channel, limit: limit) }
        #expect(throws: DiscordError.self) { try PollEndpoints.voters(channelID: channel, messageID: message, answerID: 1, limit: limit) }
        #expect(throws: DiscordError.self) { try PollEndpoints.voters(channelID: channel, messageID: message, answerID: 0) }
    }

    /// Raw emoji route values reject traversal/control/empty data and encode reserved characters once.
    /// - Parameter text: An invalid raw Unicode emoji segment.
    @Test(arguments: ["", ".", "..", "a/b", "a\\b", "a\n"]) func invalidEmoji(text: String) throws {
        #expect(throws: DiscordError.self) { try MessageEndpoints.createReaction(channelID: channel, messageID: message, emoji: .unicode(text)) }
        #expect(throws: DiscordError.self) { try ReactionEmoji.custom(name: "", id: .init(rawValue: 1)).segment() }
        #expect(throws: DiscordError.self) { try ReactionEmoji.custom(name: "a:b", id: .init(rawValue: 1)).segment() }
        let encoded = try MessageEndpoints.reactions(channelID: channel, messageID: message, emoji: .unicode("%#?"))
        #expect(try wire(encoded).url.absoluteString.contains("%25%23%3F"))
    }

    /// Bulk descriptors enforce inclusive age/count boundaries, duplicate rejection and audit metadata.
    @Test func bulkDeleteBoundaries() throws {
        let now: UInt64 = 1_792_152_000_000
        let cutoff = now - 14 * 24 * 60 * 60 * 1_000
        let oldest = try MessageID(timestampMilliseconds: cutoff)
        let newest = try MessageID(timestampMilliseconds: now)
        let endpoint = try MessageEndpoints.bulkDelete(channelID: channel, messageIDs: [oldest, newest],
                                                       nowMilliseconds: now, auditReason: "moderation")
        #expect(endpoint.bulk?.maximumItems == 100)
        #expect(endpoint.bulk?.permitsPartialResults == false)
        #expect(endpoint.successStatuses == [204])
        #expect(endpoint.method == "POST")
        #expect(endpoint.retrySafety == .unsafe)
        #expect(try wire(endpoint).url.path.hasSuffix("/messages/bulk-delete"))
        #expect(try JSONValue.parse(#require(endpoint.body?.storedBodyBytes)) == .object(["messages": .array([.string(oldest.description), .string(newest.description)])]))
        #expect(try endpoint.decode(Data()) == EmptyResponse(data: Data()))
        for ids in [[], [newest], [newest, newest], [try MessageID(timestampMilliseconds: cutoff - 1), newest]] {
            #expect(throws: DiscordError.self) { try MessageEndpoints.bulkDelete(channelID: channel, messageIDs: ids, nowMilliseconds: now) }
        }
        let hundred = (0..<100).map { MessageID(rawValue: newest.rawValue + UInt64($0)) }
        #expect(try MessageEndpoints.bulkDelete(channelID: channel, messageIDs: hundred, nowMilliseconds: now).bulk?.maximumItems == 100)
        #expect(throws: DiscordError.self) { try MessageEndpoints.bulkDelete(channelID: channel, messageIDs: hundred + [oldest], nowMilliseconds: now) }
        #expect(throws: DiscordError.self) { try MessageEndpoints.delete(channelID: channel, messageID: message, auditReason: "\n") }
    }

    /// Search's two success shapes are distinct; filters repeat without brackets and never enable caching.
    @Test func searchQueryAndIndexing() throws {
        let query = try MessageSearchQuery(limit: 25, offset: 25, maximumID: message, minimumID: MessageID(rawValue: 0),
            slop: 100, content: "space + &", channelIDs: [channel, ChannelID(rawValue: 1)],
            authorTypes: [.bot, .excludeWebhook], authorIDs: [UserID(rawValue: UInt64.max)], mentions: [.init(rawValue: 1)],
            mentionRoleIDs: [.init(rawValue: 2)], mentionEveryone: false, repliedToUserIDs: [.init(rawValue: 3)],
            repliedToMessageIDs: [.init(rawValue: 4)], pinned: true, has: [.poll, .excludeFile], embedTypes: [.gif],
            embedProviders: ["Tenor"], linkHostnames: ["example.test"], attachmentFilenames: ["name a"],
            attachmentExtensions: ["txt"], sortBy: .relevance, sortOrder: .asc, includeNSFW: true)
        let endpoint = try MessageEndpoints.search(guildID: .init(rawValue: UInt64.max), query: query)
        let wire = try wire(endpoint)
        #expect(wire.url.path == "/api/v10/guilds/18446744073709551615/messages/search")
        #expect(wire.url.absoluteString.contains("content=space%20%2B%20%26"))
        #expect(endpoint.query.filter { $0.name == "channel_id" }.count == 2)
        #expect(endpoint.query.contains(.init(name: "mentions_role_id", value: "2")))
        #expect(endpoint.query.contains(.init(name: "has", value: "-file")))
        #expect(endpoint.query.contains(.init(name: "mention_everyone", value: "false")))
        #expect(endpoint.query.contains(.init(name: "sort_order", value: "asc")))
        #expect(endpoint.query.last == .init(name: "offset", value: "25"))
        #expect(try query.queryItems(offset: 50).last?.value == "50")
        #expect(endpoint.successStatuses == [200, 202])
        #expect(endpoint.readPolicy == nil)
        #expect(endpoint.majorParameter == nil)
        switch try endpoint.decode(Data("{\"code\":110000,\"message\":\"Index not yet available\",\"documents_indexed\":0,\"retry_after\":0.25}".utf8)) {
        case .indexing: break
        default: Issue.record("Expected indexing")
        }
        switch try endpoint.decode(Data("{\"doing_deep_historical_index\":false,\"total_results\":0,\"messages\":[]}".utf8)) {
        case .results(let result): #expect(result.totalResults == 0)
        default: Issue.record("Expected results")
        }
        #expect(!String(reflecting: query).contains("name a"))
        #expect(query.customMirror.children.count == 1)
        let large = try MessageSearchQuery(channelIDs: Array(repeating: channel, count: 500))
        #expect(try MessageEndpoints.search(guildID: .init(rawValue: 1), query: large).query.count == 502)
    }

    /// Filter-specific limits are validated independently, including exact character/count boundaries.
    @Test func searchValidation() throws {
        #expect(throws: DiscordError.self) { try MessageSearchQuery(limit: 0) }
        #expect(throws: DiscordError.self) { try MessageSearchQuery(limit: 26) }
        #expect(throws: DiscordError.self) { try MessageSearchQuery(offset: 9_976) }
        #expect(throws: DiscordError.self) { try MessageSearchQuery(slop: -1) }
        #expect(throws: DiscordError.self) { try MessageSearchQuery(slop: 101) }
        #expect(throws: DiscordError.self) { try MessageSearchQuery(content: String(repeating: "a", count: 1_025)) }
        #expect(throws: DiscordError.self) { try MessageSearchQuery(channelIDs: Array(repeating: channel, count: 501)) }
        #expect(throws: DiscordError.self) { try MessageSearchQuery(authorIDs: Array(repeating: UserID(rawValue: 1), count: 101)) }
        #expect(throws: DiscordError.self) { try MessageSearchQuery(mentions: Array(repeating: UserID(rawValue: 1), count: 101)) }
        #expect(throws: DiscordError.self) { try MessageSearchQuery(mentionRoleIDs: Array(repeating: RoleID(rawValue: 1), count: 101)) }
        #expect(throws: DiscordError.self) { try MessageSearchQuery(repliedToUserIDs: Array(repeating: UserID(rawValue: 1), count: 101)) }
        #expect(throws: DiscordError.self) { try MessageSearchQuery(repliedToMessageIDs: Array(repeating: message, count: 101)) }
        #expect(throws: DiscordError.self) { try MessageSearchQuery(embedProviders: [String(repeating: "a", count: 257)]) }
        #expect(throws: DiscordError.self) { try MessageSearchQuery(embedProviders: Array(repeating: "a", count: 101)) }
        #expect(throws: DiscordError.self) { try MessageSearchQuery(attachmentFilenames: [String(repeating: "a", count: 1_025)]) }
        #expect(throws: DiscordError.self) { try MessageSearchQuery(attachmentFilenames: Array(repeating: "a", count: 101)) }
        #expect(throws: DiscordError.self) { try MessageSearchQuery(attachmentExtensions: Array(repeating: "txt", count: 101)) }
        #expect(throws: DiscordError.self) { try MessageSearchQuery(attachmentExtensions: [String(repeating: "a", count: 257)]) }
        #expect(throws: DiscordError.self) { try MessageSearchQuery(linkHostnames: [String(repeating: "a", count: 257)]) }
        #expect(throws: DiscordError.self) { try MessageSearchQuery(linkHostnames: Array(repeating: "a", count: 101)) }
        #expect(throws: DiscordError.self) { try MessageSearchQuery(authorTypes: Array(repeating: .bot, count: 7)) }
        #expect(throws: DiscordError.self) { try MessageSearchQuery(has: Array(repeating: .poll, count: 19)) }
        #expect(throws: DiscordError.self) { try MessageSearchQuery(embedTypes: Array(repeating: .gif, count: 6)) }
        #expect(throws: DiscordError.self) { try MessageSearchQuery().queryItems(offset: -1) }
        let exact = try MessageSearchQuery(limit: 1, offset: 9_975, slop: 0, content: String(repeating: "🌟", count: 1_024),
            embedProviders: Array(repeating: String(repeating: "a", count: 256), count: 100),
            attachmentFilenames: Array(repeating: String(repeating: "b", count: 1_024), count: 100))
        #expect(try MessageEndpoints.search(guildID: .init(rawValue: 1), query: exact).accountedMetadataBytes > 100_000)
        #expect(MessageSearchAuthor.allCases.count == 6)
        #expect(MessageSearchHas.allCases.count == 18)
        #expect(MessageSearchEmbed.allCases.map(\.rawValue) == ["image", "video", "gif", "sound", "article"])
        #expect(MessageReactionType.allCases.map(\.rawValue) == [0, 1])
    }

    /// Every descriptor rejects bearer/absent auth and retains safe API failure evidence.
    /// - Parameter status: Applicable authentication/permission/missing/validation/rate/server failures.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [400, 401, 403, 404, 429, 500]) func apiFailureIntegration(status: Int) async throws {
        let endpoint = try MessageEndpoints.get(channelID: channel, messageID: message)
        #expect(throws: DiscordError.self) { try endpoint.makeRequest(credential: .none, userAgent: "test") }
        #expect(throws: DiscordError.self) { try endpoint.makeRequest(credential: .bearer(try BearerToken("synthetic")), userAgent: "test") }
        let transport = try ScriptedHTTPTransport(steps: [{ _ in
            HTTPResponse(status: status, body: try RequestBody(bytes: Data("{\"code\":50035,\"message\":\"private-body\"}".utf8), contentType: "application/json").makeStream())
        }])
        let clock = ManualClock()
        let coordinator = RateLimitCoordinator(clock: clock)
        let client = RESTClient(credential: .bot(try BotToken("synthetic")), identity: RateLimitIdentity(), transport: transport,
                                coordinator: coordinator, clock: clock, retryPolicy: .init(maximumAttempts: 1))
        do { _ = try await client.execute(endpoint); Issue.record("Expected failure") }
        catch let error as APIResponseError {
            #expect(error.status == status)
            #expect(error.code == 50035)
            #expect(!String(reflecting: error).contains("private-body"))
        }
        #expect(await transport.executionCount == 1)
        #expect(await coordinator.snapshot().activeCount == 0)
        await coordinator.close()
    }

    /// Upload IDs are checked before dictionary construction, and body mutation failures remain indeterminate.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func uploadAndAmbiguousMutation() async throws {
        let file = try MessageUploadFile(id: 0, filename: "a.txt", contentType: "text/plain", bytes: Data("a".utf8))
        #expect(throws: DiscordError.self) { try MessageEndpoints.create(channelID: channel, request: MessageCreate(content: .value("a")), files: [file, file]) }
        let transport = try ScriptedHTTPTransport(steps: [{ _ in throw TestSupportFailure.scripted("hidden") }])
        let clock = ManualClock()
        let coordinator = RateLimitCoordinator(clock: clock)
        let client = RESTClient(credential: .bot(try BotToken("synthetic")), identity: RateLimitIdentity(),
                                transport: transport, coordinator: coordinator, clock: clock)
        await #expect(throws: DiscordError.unknownMutationOutcome(.connectionLostAfterSubmission)) {
            try await client.execute(MessageEndpoints.create(channelID: channel, request: MessageCreate(content: .value("a"))))
        }
        #expect(await transport.executionCount == 1)
        #expect(await coordinator.snapshot().activeCount == 0)
        await coordinator.close()
    }

    /// Supplies one synthetic bot header without exposing real credentials or starting a body producer.
    /// - Parameter endpoint: Typed descriptor under inspection.
    /// - Returns: Owned request; body consumers must collect/close any provided stream separately.
    /// - Throws: Descriptor credential-policy validation errors.
    private func wire<T>(_ endpoint: Endpoint<T>) throws -> HTTPRequest {
        try endpoint.makeRequest(credential: .bot(try BotToken("synthetic")), userAgent: "DiscordBot (https://example.test, test)")
    }

    /// Complete minimal message shared by descriptor tests; all IDs exceed floating-point exactness.
    /// - Returns: UTF-8 message bytes with a valid webhook-style author.
    static func messageData() -> Data {
        Data("""
        {"id":"9007199254740993","channel_id":"18446744073709551615","author":{"id":"1","username":"author","discriminator":"0","global_name":null,"avatar":null},"content":"hello","timestamp":"2026-10-16T00:00:00Z","edited_timestamp":null,"tts":false,"mention_everyone":false,"mentions":[],"mention_roles":[],"attachments":[],"embeds":[],"pinned":false,"type":0}
        """.utf8)
    }

    static let userJSON = "{\"id\":\"18446744073709551615\",\"username\":\"user\",\"discriminator\":\"0\",\"global_name\":null,\"avatar\":null}"
}
