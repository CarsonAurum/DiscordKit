import DiscordCore
import DiscordModels
import DiscordTransport
import Foundation
import Testing
@testable import DiscordHTTP

/// Exact route, status, authentication, query/body and dependency metadata for all ten event/stage operations.
@Suite struct ScheduledEventEndpointTests {
    /// Every descriptor targets API v10 with bot auth, strict statuses and conservative mutation replay semantics.
    /// - Throws: Unexpected fixture, descriptor, authentication or response projection errors fail the test.
    @Test func completeCatalog() throws {
        let catalog = try Self.catalog()
        #expect(catalog.count == 10)
        let methods = ["GET", "GET", "POST", "PATCH", "DELETE", "GET", "POST", "GET", "PATCH", "DELETE"]
        let collection = ["guilds", "18446744073709551615", "scheduled-events"]
        let target = collection + ["18446744073709551615"]
        let paths = [collection, target, collection, target, target, target + ["users"], ["stage-instances"],
            ["stage-instances", "18446744073709551615"], ["stage-instances", "18446744073709551615"], ["stage-instances", "18446744073709551615"]]
        for (index, item) in catalog.enumerated() {
            let (endpoint, bytes) = item
            #expect(endpoint.method == methods[index])
            #expect(endpoint.path == paths[index])
            #expect(endpoint.majorParameter == "18446744073709551615")
            #expect(endpoint.authentication == .bot)
            #expect(endpoint.usesGlobalLimit)
            #expect(endpoint.successStatuses == ([4, 9].contains(index) ? [204] : [200]))
            #expect(endpoint.retrySafety == (methods[index] == "GET" ? .safe : .unsafe))
            #expect(endpoint.readPolicy?.coalescing == (methods[index] == "GET" ? true : nil))
            #expect(endpoint.readPolicy?.timeToLive == nil)
            #expect(endpoint.bulk == nil)
            #expect((endpoint.body != nil) == [2, 3, 6, 8].contains(index))
            #expect(try endpoint.decode(bytes) == bytes)
            #expect(endpoint.auditReason == nil)
            #expect(!endpoint.route.contains("18446744073709551615"))
            let request = try endpoint.makeRequest(credential: .bot(try BotToken("synthetic")), userAgent: "test")
            #expect(request.url.absoluteString == "https://discord.com/api/v10/" + paths[index].joined(separator: "/"))
            #expect(request.headers.contains { $0.name == "Authorization" && $0.value == "Bot synthetic" })
            for credential in [Credential.none, .bearer(try BearerToken("synthetic"))] {
                #expect(throws: DiscordError.validation(.missingValue)) { try endpoint.makeRequest(credential: credential, userAgent: "test") }
            }
            for bad in ["null", "{}", "[{}]", "true"] {
                #expect(throws: (any Error).self) { try endpoint.decode(Data(bad.utf8)) }
            }
            if ![0,5].contains(index) { #expect(throws: (any Error).self) { try endpoint.decode(Data("[]".utf8)) } }
            if ![4,9].contains(index) { #expect(throws: (any Error).self) { try endpoint.decode(Data()) } }
            #expect(!String(reflecting: endpoint).contains("18446744073709551615"))
        }
        #expect(try GuildScheduledEventEndpoints.list(guildID: .init(rawValue: 1)).decode(Data("[]".utf8)).isEmpty)
        #expect(try GuildScheduledEventEndpoints.users(guildID: .init(rawValue: 1), eventID: .init(rawValue: 1)).decode(Data("[]".utf8)).isEmpty)
    }

    /// Count/member switches preserve true/false/omission and exclusive user boundaries preserve full unsigned IDs.
    /// - Throws: Unexpected setup or valid query errors fail the test; invalid limit/schema errors are asserted.
    @Test func queriesAndSubscriberValidation() throws {
        let guild = GuildID(rawValue: 1), event = GuildScheduledEventID(rawValue: .max)
        #expect(try GuildScheduledEventEndpoints.list(guildID: guild, withUserCount: false).query == [.init(name: "with_user_count", value: "false")])
        #expect(try GuildScheduledEventEndpoints.get(guildID: guild, eventID: event, withUserCount: true).query == [.init(name: "with_user_count", value: "true")])
        for before in [false, true] {
            let endpoint = try GuildScheduledEventEndpoints.users(guildID: guild, eventID: event, limit: 100,
                withMember: false, position: before ? .before(.init(rawValue: .max)) : .after(.init(rawValue: 0)))
            #expect(endpoint.query == [.init(name: "limit", value: "100"), .init(name: "with_member", value: "false"),
                .init(name: before ? "before" : "after", value: before ? "18446744073709551615" : "0")])
            #expect(try endpoint.decode(Self.usersData([1, 9_007_199_254_740_993])).count == 2)
        }
        for limit in [Int.min, 0, 101, Int.max] {
            #expect(throws: DiscordError.validation(.invalidValue)) { try GuildScheduledEventEndpoints.users(guildID: guild, eventID: event, limit: limit) }
        }
        let bounded = try GuildScheduledEventEndpoints.users(guildID: guild, eventID: event, limit: 2, position: .after(.init(rawValue: 10)))
        for ids in [[10], [9], [12,11], [11,11], [11,12,13]] as [[UInt64]] {
            #expect(throws: DiscordError.transport(.invalidResponse)) { try bounded.decode(Self.usersData(ids)) }
        }
        #expect(throws: DiscordError.transport(.invalidResponse)) { try bounded.decode(Self.usersData([11], eventID: 2)) }
        #expect(throws: DiscordError.transport(.invalidResponse)) {
            try bounded.decode(Data(#"[{"guild_scheduled_event_id":"18446744073709551615","user_id":"11","response":1}]"#.utf8))
        }
    }

    /// Scoped reuse preserves caller policies and mutation invalidation includes all event/stage/invite dependents.
    /// - Throws: Unexpected fixture/descriptor errors fail the test; bad policy and reason rejections are asserted.
    @Test func policiesAndAudit() throws {
        let guild = GuildID(rawValue: 1), event = GuildScheduledEventID(rawValue: 2), channel = ChannelID(rawValue: 3)
        let reads: [(ReadPolicy?) throws -> Endpoint<Data>] = [
            { try Self.erase(GuildScheduledEventEndpoints.list(guildID: guild, readPolicy: $0)) },
            { try Self.erase(GuildScheduledEventEndpoints.get(guildID: guild, eventID: event, readPolicy: $0)) },
            { try Self.erase(GuildScheduledEventEndpoints.users(guildID: guild, eventID: event, readPolicy: $0)) },
            { try Self.erase(StageInstanceEndpoints.get(channelID: channel, readPolicy: $0)) }]
        for make in reads {
            let endpoint = try make(ReadPolicy(coalescing: false, timeToLive: .seconds(2), tags: ["caller"]))
            #expect(endpoint.readPolicy?.coalescing == false)
            #expect(endpoint.readPolicy?.timeToLive == .seconds(2))
            #expect(endpoint.readPolicy?.tags.isSuperset(of: ["caller", "scheduled-event-catalog", "stage-instance-catalog", "invite-catalog"]) == true)
            #expect(try make(nil).readPolicy == nil)
            #expect(throws: DiscordError.validation(.invalidValue)) { try make(ReadPolicy(timeToLive: .zero)) }
        }
        for (endpoint, _) in try Self.catalog() where endpoint.method != "GET" {
            #expect(endpoint.invalidates.isSuperset(of: ["scheduled-event-catalog", "stage-instance-catalog", "invite-catalog", "audit-log-catalog", "guild-catalog"]))
            #expect(endpoint.readPolicy == nil)
        }
        let mutations: [(String) throws -> Endpoint<Data>] = [
            { try Self.erase(GuildScheduledEventEndpoints.create(guildID: guild, request: Self.creation(), auditReason: $0)) },
            { try Self.erase(GuildScheduledEventEndpoints.modify(guildID: guild, eventID: event, request: GuildScheduledEventModify(currentEntityType: .voice), auditReason: $0)) },
            { try Self.erase(StageInstanceEndpoints.create(request: StageInstanceCreate(channelID: channel, topic: "topic"), auditReason: $0)) },
            { try Self.erase(StageInstanceEndpoints.modify(channelID: channel, request: StageInstanceModify(), auditReason: $0)) },
            { try Self.erase(StageInstanceEndpoints.delete(channelID: channel, auditReason: $0)) }]
        for make in mutations {
            let endpoint = try make("why +&日本")
            let request = try endpoint.makeRequest(credential: .bot(try BotToken("synthetic")), userAgent: "test")
            #expect(request.headers.contains { $0.name == "X-Audit-Log-Reason" && $0.value == "why%20%2B%26%E6%97%A5%E6%9C%AC" })
            for reason in ["\n", String(repeating: "x", count: 513)] {
                #expect(throws: DiscordError.validation(.invalidValue)) { try make(reason) }
            }
        }
    }

    /// The maximum accepted decoded cover image remains transmittable after canonical base64 expansion.
    /// - Throws: Unexpected boundary request/body serialization errors fail the test.
    @Test func boundedCoverSerialization() throws {
        let image = "data:image/png;base64," + Data(repeating: 1, count: 1_048_576).base64EncodedString()
        let request = try GuildScheduledEventCreate(name: "cover", entityType: .voice,
            scheduledStartTime: DiscordTimestamp(rawValue: "2030-01-01T00:00:00Z"), channelID: .init(rawValue: 1), image: .value(image))
        let endpoint = try GuildScheduledEventEndpoints.create(guildID: .init(rawValue: 1), request: request)
        let bytes = try #require(endpoint.body?.storedBodyBytes)
        #expect(bytes.count > 1_048_576 && bytes.count <= 2_097_152)
        #expect(try JSONValue.parse(bytes, limits: .init(maximumBytes: 2_097_152)) == request.jsonValue())
        let modification = try GuildScheduledEventModify(currentEntityType: .voice, image: .value(image))
        let edited = try GuildScheduledEventEndpoints.modify(guildID: .init(rawValue: 1), eventID: .init(rawValue: 2), request: modification)
        #expect(try JSONValue.parse(#require(edited.body?.storedBodyBytes), limits: .init(maximumBytes: 2_097_152)) == modification.jsonValue())
    }

    /// Returns every production descriptor with a handwritten independent complete success fixture.
    /// - Returns: Stable list/get/create/modify/delete/users and create/get/modify/delete stage catalog order.
    /// - Throws: Unexpected descriptor/body validation errors fail fixture users.
    static func catalog() throws -> [(Endpoint<Data>, Data)] {
        let guild = GuildID(rawValue: .max), eventID = GuildScheduledEventID(rawValue: .max), channel = ChannelID(rawValue: .max)
        let event = Data(eventJSON.utf8), stage = Data(stageJSON.utf8)
        return [
            (try erase(GuildScheduledEventEndpoints.list(guildID: guild)), Data(("[" + eventJSON + "]").utf8)),
            (try erase(GuildScheduledEventEndpoints.get(guildID: guild, eventID: eventID)), event),
            (try erase(GuildScheduledEventEndpoints.create(guildID: guild, request: creation())), event),
            (try erase(GuildScheduledEventEndpoints.modify(guildID: guild, eventID: eventID, request: GuildScheduledEventModify(currentEntityType: .voice, name: .value("new")))), event),
            (try erase(GuildScheduledEventEndpoints.delete(guildID: guild, eventID: eventID)), Data()),
            (try erase(GuildScheduledEventEndpoints.users(guildID: guild, eventID: eventID)), try usersData([9])),
            (try erase(StageInstanceEndpoints.create(request: StageInstanceCreate(channelID: channel, topic: "private-topic"))), stage),
            (try erase(StageInstanceEndpoints.get(channelID: channel)), stage),
            (try erase(StageInstanceEndpoints.modify(channelID: channel, request: StageInstanceModify(topic: .value("new")))), stage),
            (try erase(StageInstanceEndpoints.delete(channelID: channel)), Data())]
    }

    /// Preserves all production metadata and invokes the original decoder before returning fixture bytes.
    /// - Parameter endpoint: Production descriptor whose model schema must remain authoritative in integration tests.
    /// - Returns: Equivalent descriptor erased only after complete typed decoding succeeds.
    /// - Throws: Descriptor validation errors for invalid copied metadata.
    static func erase<T: Sendable>(_ endpoint: Endpoint<T>) throws -> Endpoint<Data> {
        try Endpoint(method: endpoint.method, path: endpoint.path, route: endpoint.route, query: endpoint.query,
            authentication: endpoint.authentication, successStatuses: endpoint.successStatuses,
            majorParameter: endpoint.majorParameter, usesGlobalLimit: endpoint.usesGlobalLimit,
            auditReason: endpoint.auditReason, body: endpoint.body, headers: endpoint.headers,
            retrySafety: endpoint.retrySafety, readPolicy: endpoint.readPolicy, invalidates: endpoint.invalidates,
            bulk: endpoint.bulk, decode: { _ = try endpoint.decode($0); return $0 })
    }

    /// Makes one channel-backed event creation with deterministic future timestamps and no live state.
    /// - Returns: Validated voice event request with exact maximum-width channel ID.
    /// - Throws: Unexpected timestamp/request validation errors fail fixture users.
    static func creation() throws -> GuildScheduledEventCreate {
        try GuildScheduledEventCreate(name: "private-event", entityType: .voice,
            scheduledStartTime: DiscordTimestamp(rawValue: "2030-01-01T00:00:00Z"), channelID: .init(rawValue: .max))
    }

    /// Produces an independently specified subscriber array with exact user identifiers.
    /// - Parameters:
    ///   - ids: User IDs in the requested order, including malformed duplicate/reverse test cases.
    ///   - eventID: Owning event, default maximum; alternative values exercise foreign-event rejection.
    /// - Returns: Complete bounded subscriber JSON with partial Users and no member hydration.
    /// - Throws: JSON serialization errors for local fixture construction.
    static func usersData(_ ids: [UInt64], eventID: UInt64 = .max) throws -> Data {
        try JSONValue.array(ids.map { .object(["guild_scheduled_event_id": .string(String(eventID)),
            "user": .object(["id": .string(String($0)), "username": .string("subscriber"),
                "discriminator": .string("0"), "avatar": .null])]) }).serialized()
    }

    static let eventJSON = #"{"id":"18446744073709551615","guild_id":"18446744073709551615","channel_id":"18446744073709551615","creator_id":null,"name":"private-event","description":null,"scheduled_start_time":"2030-01-01T00:00:00Z","scheduled_end_time":"2030-01-01T01:00:00Z","privacy_level":2,"status":1,"entity_type":2,"entity_id":null,"entity_metadata":null,"recurrence_rule":null}"#
    static let stageJSON = #"{"id":"18446744073709551615","guild_id":"18446744073709551615","channel_id":"18446744073709551615","topic":"private-topic","privacy_level":2,"discoverable_disabled":false,"guild_scheduled_event_id":null}"#
}
