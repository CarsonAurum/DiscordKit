import DiscordCore
import DiscordModels
import DiscordTransport
import Foundation
import Testing
@testable import DiscordHTTP

/// Complete Guild Template descriptor contracts, with finite independent wire fixtures and no live Discord traffic.
@Suite struct GuildTemplateEndpointTests {
    /// Every current operation declares the exact versioned path, success body, guild partition and safe/unsafe policy.
    /// - Throws: Unexpected fixture or descriptor errors fail this test; credential mismatches are asserted.
    @Test func completeCatalog() throws {
        let catalog = try Self.catalog()
        #expect(catalog.count == 6)
        let methods = ["GET", "GET", "POST", "PUT", "PATCH", "DELETE"]
        let paths = ["guilds/templates/secret-code", "guilds/18446744073709551615/templates",
            "guilds/18446744073709551615/templates", "guilds/18446744073709551615/templates/secret-code",
            "guilds/18446744073709551615/templates/secret-code", "guilds/18446744073709551615/templates/secret-code"]
        let routes = ["/guilds/templates/{template.code}", "/guilds/{guild.id}/templates",
            "/guilds/{guild.id}/templates", "/guilds/{guild.id}/templates/{template.code}",
            "/guilds/{guild.id}/templates/{template.code}", "/guilds/{guild.id}/templates/{template.code}"]
        for (index, item) in catalog.enumerated() {
            let endpoint = item.0
            #expect(endpoint.method == methods[index])
            #expect(endpoint.route == routes[index])
            #expect(endpoint.successStatuses == [200])
            #expect(endpoint.majorParameter == (index == 0 ? nil : "18446744073709551615"))
            #expect(endpoint.retrySafety == (index < 2 ? .safe : .unsafe))
            #expect((endpoint.readPolicy != nil) == (index < 2))
            #expect(endpoint.invalidates.isEmpty == (index < 2))
            #expect(endpoint.auditReason == nil)
            #expect(endpoint.bulk == nil)
            #expect(endpoint.query.isEmpty)
            #expect(endpoint.usesGlobalLimit)
            let request = try endpoint.makeRequest(credential: .bot(try BotToken("synthetic")), userAgent: "test")
            #expect(request.url.absoluteString == "https://discord.com/api/v10/" + paths[index])
            #expect(request.headers.contains { $0.name == "Authorization" && $0.value == "Bot synthetic" })
            #expect(throws: DiscordError.validation(.missingValue)) {
                try endpoint.makeRequest(credential: .none, userAgent: "test")
            }
            #expect(try endpoint.decode(item.1) == item.1)
            if index == 2 {
                #expect(try JSONValue.parse(#require(endpoint.body?.storedBodyBytes)) == .object(["name": .string("created"), "description": .null]))
            } else if index == 4 {
                #expect(try JSONValue.parse(#require(endpoint.body?.storedBodyBytes)) == .object(["name": .string("changed")]))
            } else { #expect(endpoint.body == nil) }
        }
        let empty = try GuildTemplateEndpoints.list(guildID: .init(rawValue: 1)).decode(Data("[]".utf8))
        #expect(empty.isEmpty)
    }

    /// Explicit public/bot reads retain caller policies; unsafe opaque codes and invalid TTLs fail before I/O.
    /// - Throws: Unexpected valid descriptor errors fail the test; invalid path/policy cases are asserted.
    @Test func publicReadsPoliciesAndInvalidCodes() throws {
        let publicRead = try GuildTemplateEndpoints.get(code: "secret-code")
        #expect(publicRead.authentication == .none)
        for credential in [Credential.none, .bot(try BotToken("synthetic"))] {
            let request = try publicRead.makeRequest(credential: credential, userAgent: "test")
            #expect(!request.headers.contains { $0.name.lowercased() == "authorization" })
        }
        let policy = ReadPolicy(coalescing: false, timeToLive: .seconds(4), tags: ["caller"])
        for readPolicy in [try GuildTemplateEndpoints.get(code: "secret-code", readPolicy: policy).readPolicy,
                           try GuildTemplateEndpoints.list(guildID: .init(rawValue: 1), readPolicy: policy).readPolicy] {
            #expect(readPolicy?.coalescing == false)
            #expect(readPolicy?.timeToLive == .seconds(4))
            #expect(readPolicy?.tags == ["caller", "guild-template-catalog", "guild-catalog"])
        }
        #expect(try GuildTemplateEndpoints.get(code: "a", readPolicy: nil).readPolicy == nil)
        #expect(try GuildTemplateEndpoints.list(guildID: .init(rawValue: 1), readPolicy: nil).readPolicy == nil)
        for ttl in [Duration.zero, .seconds(-1)] {
            #expect(throws: DiscordError.validation(.invalidValue)) { try GuildTemplateEndpoints.get(code: "a", readPolicy: ReadPolicy(timeToLive: ttl)) }
            #expect(throws: DiscordError.validation(.invalidValue)) { try GuildTemplateEndpoints.list(guildID: .init(rawValue: 1), readPolicy: ReadPolicy(timeToLive: ttl)) }
        }
        for code in ["", ".", "..", "/", "a/b", "a\\b", "\n"] {
            #expect(throws: DiscordError.validation(.invalidValue)) { try GuildTemplateEndpoints.get(code: code) }
            #expect(throws: DiscordError.validation(.invalidValue)) { try GuildTemplateEndpoints.sync(guildID: .init(rawValue: 1), code: code) }
            #expect(throws: DiscordError.validation(.invalidValue)) { try GuildTemplateEndpoints.modify(guildID: .init(rawValue: 1), code: code, request: GuildTemplateModify()) }
            #expect(throws: DiscordError.validation(.invalidValue)) { try GuildTemplateEndpoints.delete(guildID: .init(rawValue: 1), code: code) }
        }
        let opaque = try GuildTemplateEndpoints.get(code: "opaque +?&日本")
        let request = try opaque.makeRequest(credential: .none, userAgent: "test")
        #expect(request.url.query == nil && request.url.fragment == nil)
        #expect(request.url.path.hasSuffix("opaque +?&日本"))
        #expect(!String(reflecting: opaque).contains("opaque"))
    }

    /// Metadata reconciliation uses exact requested keys, skips empty/no-op changes and checks source ownership.
    /// - Throws: Unexpected fixture/request errors fail this test; mismatched source guilds are asserted.
    @Test func snapshotNoOpReconciliation() throws {
        let current = try GuildTemplate(data: Data(Self.templateJSON.utf8)), guild = current.sourceGuildID
        for request in [try GuildTemplateModify(), try GuildTemplateModify(name: .value("private-name")),
                        try GuildTemplateModify(description: .null)] {
            #expect(try GuildTemplateOperations.modifyIfChanged(guildID: guild, current: current, request: request) == nil)
        }
        for request in [try GuildTemplateModify(name: .value("changed")),
                        try GuildTemplateModify(description: .value("")), try GuildTemplateModify(description: .value("new"))] {
            let endpoint = try #require(try GuildTemplateOperations.modifyIfChanged(guildID: guild, current: current, request: request))
            #expect(endpoint.method == "PATCH")
            #expect(endpoint.path == ["guilds", guild.description, "templates", "secret-code"])
            #expect(try JSONValue.parse(#require(endpoint.body?.storedBodyBytes)) == request.jsonValue())
        }
        #expect(throws: DiscordError.validation(.invalidValue)) {
            try GuildTemplateOperations.modifyIfChanged(guildID: .init(rawValue: 1), current: current, request: GuildTemplateModify())
        }
    }

    /// Builds all six current operations with their original typed decoders and independent expected response bytes.
    /// - Returns: Stable operation order get/list/create/sync/modify/delete; all request bodies are bounded immutable data.
    /// - Throws: Unexpected fixture/descriptor validation errors fail catalog consumers.
    static func catalog() throws -> [(Endpoint<Data>, Data)] {
        let guild = GuildID(rawValue: UInt64.max), bytes = Data(templateJSON.utf8)
        return [
            (try erase(GuildTemplateEndpoints.get(code: "secret-code", authenticated: true)), bytes),
            (try erase(GuildTemplateEndpoints.list(guildID: guild)), Data(("[" + templateJSON + "]").utf8)),
            (try erase(GuildTemplateEndpoints.create(guildID: guild, request: GuildTemplateCreate(name: "created", description: .null))), bytes),
            (try erase(GuildTemplateEndpoints.sync(guildID: guild, code: "secret-code")), bytes),
            (try erase(GuildTemplateEndpoints.modify(guildID: guild, code: "secret-code", request: GuildTemplateModify(name: .value("changed")))), bytes),
            (try erase(GuildTemplateEndpoints.delete(guildID: guild, code: "secret-code")), bytes),
        ]
    }

    /// Preserves production wire policy and validates the original typed response before returning its exact bytes.
    /// - Parameter endpoint: Typed template descriptor whose decoder must remain authoritative for schema tests.
    /// - Returns: Equivalent descriptor with a bytes result, without tasks, I/O or altered retry/cache eligibility.
    /// - Throws: Descriptor validation errors if production policy cannot be represented unchanged.
    static func erase<T: Sendable>(_ endpoint: Endpoint<T>) throws -> Endpoint<Data> {
        try Endpoint(method: endpoint.method, path: endpoint.path, route: endpoint.route, query: endpoint.query,
            authentication: endpoint.authentication, successStatuses: endpoint.successStatuses,
            majorParameter: endpoint.majorParameter, usesGlobalLimit: endpoint.usesGlobalLimit,
            auditReason: endpoint.auditReason, body: endpoint.body, headers: endpoint.headers,
            retrySafety: endpoint.retrySafety, readPolicy: endpoint.readPolicy, invalidates: endpoint.invalidates,
            bulk: endpoint.bulk, decode: { _ = try endpoint.decode($0); return $0 })
    }

    /// Independent complete written template fixture with typed partial snapshot supplements.
    static let templateJSON = #"{"code":"secret-code","name":"private-name","description":null,"usage_count":10,"creator_id":"18446744073709551615","creator":{"id":"18446744073709551615","username":"private-user","discriminator":"0","avatar":null},"created_at":"2026-10-16T10:00:00Z","updated_at":"2026-10-16T11:00:00Z","source_guild_id":"18446744073709551615","serialized_source_guild":{"name":"private-guild","description":null,"region":"us-west","verification_level":0,"default_message_notifications":0,"explicit_content_filter":0,"preferred_locale":"en-US","afk_channel_id":null,"afk_timeout":300,"system_channel_id":1,"system_channel_flags":0,"roles":[{"id":0,"name":"@everyone","permissions":104324689,"color":0,"colors":{"primary_color":1,"secondary_color":null,"tertiary_color":2},"hoist":false,"mentionable":true,"icon":null,"unicode_emoji":"🌲"}],"channels":[{"id":1,"type":15,"name":"forum","position":1,"topic":null,"bitrate":64000,"user_limit":0,"nsfw":false,"rate_limit_per_user":0,"parent_id":0,"default_auto_archive_duration":null,"permission_overwrites":[{"id":0,"type":0,"allow":"184467440737095516160000","deny":0}],"available_tags":[{"id":0,"name":"tag","emoji_id":null,"emoji_name":"🌲","moderated":false}],"template":"snapshot","default_reaction_emoji":{"emoji_id":null,"emoji_name":"🌲"},"default_thread_rate_limit_per_user":null,"default_sort_order":0,"default_forum_layout":1,"default_tag_setting":"match_all","theme_color":null}],"icon_hash":null},"is_dirty":null}"#
}
