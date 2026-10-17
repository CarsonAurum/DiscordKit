import DiscordCore
import DiscordModels
import DiscordTransport
import Foundation
import Testing
@testable import DiscordHTTP

/// Independent wire, authentication and payload fixtures for every current moderation operation.
@Suite struct ModerationEndpointTests {
    /// All six operations expose explicit v10 routes, guild admission, conservative replay and exact success decoders.
    /// - Throws: Unexpected descriptor, body or fixture failures fail this test.
    @Test func completeCatalog() throws {
        let expected = [("GET", "audit-logs"), ("GET", "auto-moderation/rules"),
            ("GET", "auto-moderation/rules/18446744073709551615"), ("POST", "auto-moderation/rules"),
            ("PATCH", "auto-moderation/rules/18446744073709551615"),
            ("DELETE", "auto-moderation/rules/18446744073709551615")]
        let catalog = try Self.catalog()
        #expect(catalog.count == 6)
        for (index, item) in catalog.enumerated() {
            let (endpoint, bytes) = item
            let request = try endpoint.makeRequest(credential: .bot(try BotToken("synthetic")), userAgent: "DiscordBot test")
            #expect(request.method == expected[index].0)
            #expect(request.url.absoluteString == "https://discord.com/api/v10/guilds/18446744073709551615/" + expected[index].1)
            #expect(endpoint.route == "/guilds/{guild.id}/" + (index == 0 ? "audit-logs" : "auto-moderation/rules" + ([2, 4, 5].contains(index) ? "/{rule.id}" : "")))
            #expect(endpoint.authentication == .bot)
            #expect(endpoint.majorParameter == "18446744073709551615")
            #expect(endpoint.usesGlobalLimit)
            #expect(endpoint.successStatuses == (index == 5 ? [204] : [200]))
            #expect(endpoint.retrySafety == (index < 3 ? .safe : .unsafe))
            #expect(endpoint.readPolicy?.coalescing == (index < 3 ? true : nil))
            #expect(endpoint.readPolicy?.timeToLive == nil)
            #expect(endpoint.bulk == nil)
            #expect((endpoint.body != nil) == [3, 4].contains(index))
            #expect(try endpoint.decode(bytes) == bytes)
            for bad in [Data("null".utf8), Data("{}".utf8), Data("true".utf8)] {
                #expect(throws: (any Error).self) { try endpoint.decode(bad) }
            }
            if index != 1 && index != 5 { #expect(throws: (any Error).self) { try endpoint.decode(Data("[]".utf8)) } }
            if index != 5 { #expect(throws: (any Error).self) { try endpoint.decode(Data()) } }
            #expect(!String(reflecting: endpoint).contains("guilds"))
        }
        let empty = try AutoModerationEndpoints.list(guildID: .init(rawValue: 1)).decode(Data("[]".utf8))
        #expect(empty.isEmpty)
    }

    /// Optional actor/action/cursor/count filters preserve exact integers and mutually exclusive paging directions.
    /// - Throws: Unexpected descriptor errors fail this test; invalid limits are asserted explicitly.
    @Test func auditQueryContracts() throws {
        let guild = GuildID(rawValue: UInt64.max), id = AuditLogEntryID(rawValue: UInt64.max)
        #expect(try AuditLogEndpoints.get(guildID: guild).query.isEmpty)
        let endpoint = try AuditLogEndpoints.get(guildID: guild, userID: .init(rawValue: UInt64.max),
            actionType: .init(.autoModerationRuleCreate), position: .before(id), limit: 100)
        #expect(endpoint.query == [.init(name: "user_id", value: "18446744073709551615"),
            .init(name: "action_type", value: "140"), .init(name: "before", value: "18446744073709551615"),
            .init(name: "limit", value: "100")])
        #expect(try AuditLogEndpoints.get(guildID: guild, actionType: .init(rawValue: 999), position: .after(.init(rawValue: 0)), limit: 1).query == [
            .init(name: "action_type", value: "999"), .init(name: "after", value: "0"), .init(name: "limit", value: "1")])
        #expect(AuditLogPosition.before(id) == .before(id))
        #expect(AuditLogPosition.before(id) != .after(id))
        for limit in [Int.min, -1, 0, 101, Int.max] {
            #expect(throws: DiscordError.validation(.invalidValue)) { try AuditLogEndpoints.get(guildID: guild, limit: limit) }
        }
    }

    /// Caller policies survive augmentation, nil disables reuse and writes invalidate both moderation catalogs.
    /// - Throws: Unexpected descriptor/request errors fail this test.
    @Test func policyAndAuditReasons() throws {
        let guild = GuildID(rawValue: 1), rule = AutoModerationRuleID(rawValue: 2)
        let policy = ReadPolicy(coalescing: false, timeToLive: .seconds(2), tags: ["custom"])
        let audit = try AuditLogEndpoints.get(guildID: guild, readPolicy: policy)
        #expect(audit.readPolicy?.tags == ["custom", "audit-log-catalog", "guild-catalog", "channel-catalog", "message-search"])
        #expect(audit.readPolicy?.coalescing == false)
        #expect(audit.readPolicy?.timeToLive == .seconds(2))
        #expect(try AuditLogEndpoints.get(guildID: guild, readPolicy: nil).readPolicy == nil)
        for endpoint in [try GuildEndpointTests.erase(AutoModerationEndpoints.list(guildID: guild, readPolicy: policy)),
                         try GuildEndpointTests.erase(AutoModerationEndpoints.get(guildID: guild, ruleID: rule, readPolicy: policy))] {
            #expect(endpoint.readPolicy?.tags == ["custom", "auto-moderation-catalog", "guild-catalog"])
            #expect(endpoint.readPolicy?.coalescing == false)
            #expect(endpoint.readPolicy?.timeToLive == .seconds(2))
        }
        #expect(try AutoModerationEndpoints.list(guildID: guild, readPolicy: nil).readPolicy == nil)
        #expect(try AutoModerationEndpoints.get(guildID: guild, ruleID: rule, readPolicy: nil).readPolicy == nil)
        for (endpoint, _) in try Self.catalog().suffix(3) {
            #expect(endpoint.invalidates == ["guild-catalog", "guild:18446744073709551615", "channel-catalog", "message-search", "message-catalog", "auto-moderation-catalog", "audit-log-catalog"])
        }
        let reason = "reason +&日本"
        let deletion = try AutoModerationEndpoints.delete(guildID: guild, ruleID: rule, auditReason: reason)
        let wire = try deletion.makeRequest(credential: .bot(try BotToken("synthetic")), userAgent: "test")
        #expect(wire.headers.contains { $0.name == "X-Audit-Log-Reason" && $0.value == "reason%20%2B%26%E6%97%A5%E6%9C%AC" })
        #expect(!String(reflecting: deletion).contains(reason))
        #expect(try AutoModerationEndpoints.delete(guildID: guild, ruleID: rule, auditReason: String(repeating: "a", count: 512)).auditReason?.count == 512)
        for reason in ["\n", String(repeating: "a", count: 513)] {
            #expect(throws: DiscordError.validation(.invalidValue)) { try AutoModerationEndpoints.delete(guildID: guild, ruleID: rule, auditReason: reason) }
            #expect(throws: DiscordError.validation(.invalidValue)) {
                try AutoModerationEndpoints.create(guildID: guild, request: Self.creation(), auditReason: reason)
            }
            #expect(throws: DiscordError.validation(.invalidValue)) {
                try AutoModerationEndpoints.modify(guildID: guild, ruleID: rule,
                    request: AutoModerationModifyRequest(triggerType: .spam), auditReason: reason)
            }
        }
    }

    /// Validated request JSON reaches creation/patch unchanged and modification never sends trigger_type.
    /// - Throws: Unexpected payload/descriptor errors fail this test.
    @Test func requestBodies() throws {
        let create = try Self.creation()
        let endpoint = try AutoModerationEndpoints.create(guildID: .init(rawValue: 1), request: create)
        #expect(try JSONValue.parse(#require(endpoint.body?.storedBodyBytes)) == create.jsonValue())
        let modify = try AutoModerationModifyRequest(triggerType: .spam, name: .value("changed"), enabled: .value(true))
        let edit = try AutoModerationEndpoints.modify(guildID: .init(rawValue: 1), ruleID: .init(rawValue: 2), request: modify)
        #expect(try JSONValue.parse(#require(edit.body?.storedBodyBytes)) == .object(["name": .string("changed"), "enabled": .bool(true)]))
    }

    /// Builds a finite six-operation catalog while invoking each original typed decoder through erasure.
    /// - Returns: Ordered audit/list/get/create/modify/delete descriptors with independent successful JSON bytes.
    /// - Throws: Unexpected local payload/descriptor validation errors.
    static func catalog() throws -> [(Endpoint<Data>, Data)] {
        let guild = GuildID(rawValue: UInt64.max), rule = AutoModerationRuleID(rawValue: UInt64.max)
        let data = Data(ruleJSON.utf8)
        return [
            (try GuildEndpointTests.erase(AuditLogEndpoints.get(guildID: guild)), auditData()),
            (try GuildEndpointTests.erase(AutoModerationEndpoints.list(guildID: guild)), Data(("[" + ruleJSON + "]").utf8)),
            (try GuildEndpointTests.erase(AutoModerationEndpoints.get(guildID: guild, ruleID: rule)), data),
            (try GuildEndpointTests.erase(AutoModerationEndpoints.create(guildID: guild, request: creation())), data),
            (try GuildEndpointTests.erase(AutoModerationEndpoints.modify(guildID: guild, ruleID: rule,
                request: AutoModerationModifyRequest(triggerType: .spam, name: .value("changed")))), data),
            (try GuildEndpointTests.erase(AutoModerationEndpoints.delete(guildID: guild, ruleID: rule)), Data())
        ]
    }

    /// Constructs a legal spam-block rule without requiring trigger metadata or network state.
    /// - Returns: Validated request containing one block-message action and no optional settings.
    /// - Throws: Unexpected validation errors fail callers' fixture setup.
    static func creation() throws -> AutoModerationCreateRequest {
        try AutoModerationCreateRequest(name: "fixture", eventType: .messageSend, triggerType: .spam,
            actions: [AutoModerationActionRequest(type: .blockMessage)])
    }

    /// Encodes a complete required audit envelope with exact entries and one correlated user.
    /// - Parameter ids: Exact entry IDs in caller order; default empty. Each target/user is explicitly nullable.
    /// - Returns: UTF-8 API v10 envelope including every required collection and retained future values.
    static func auditData(_ ids: [UInt64] = []) -> Data {
        let entries = ids.map { "{\"id\":\"\($0)\",\"target_id\":null,\"user_id\":null,\"action_type\":140}" }.joined(separator: ",")
        return Data(("{\"application_commands\":[],\"audit_log_entries\":[" + entries + "],\"auto_moderation_rules\":[],\"guild_scheduled_events\":[],\"integrations\":[],\"threads\":[],\"users\":[{\"id\":\"7\",\"username\":\"actor\",\"discriminator\":\"0\",\"avatar\":null}],\"webhooks\":[]}").utf8)
    }

    /// Independent complete response fixture, deliberately using the maximum unsigned snowflake.
    static let ruleJSON = #"{"id":"18446744073709551615","guild_id":"18446744073709551615","name":"fixture","creator_id":"7","event_type":1,"trigger_type":3,"trigger_metadata":{},"actions":[{"type":1}],"enabled":false,"exempt_roles":[],"exempt_channels":[]}"#
}
