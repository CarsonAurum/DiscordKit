import DiscordCore
import DiscordModels
import DiscordTransport
import Foundation
import Testing
@testable import DiscordHTTP

/// All five written Voice resource operation contracts, with independent bounded wire fixtures.
@Suite struct VoiceEndpointTests {
    /// Every descriptor has an exact v10 path, normalized route, credential policy, guild partition and success shape.
    /// - Throws: Unexpected fixture/descriptor failures fail the test; missing or incompatible credentials are asserted.
    @Test func completeCatalog() throws {
        let catalog = try Self.catalog()
        #expect(catalog.count == 5)
        let paths = ["voice/regions", "guilds/18446744073709551615/voice-states/@me",
            "guilds/18446744073709551615/voice-states/18446744073709551615",
            "guilds/18446744073709551615/voice-states/@me",
            "guilds/18446744073709551615/voice-states/18446744073709551615"]
        let routes = ["/voice/regions", "/guilds/{guild.id}/voice-states/@me", "/guilds/{guild.id}/voice-states/{user.id}",
            "/guilds/{guild.id}/voice-states/@me", "/guilds/{guild.id}/voice-states/{user.id}"]
        for (index, item) in catalog.enumerated() {
            let endpoint = item.0
            #expect(endpoint.method == (index < 3 ? "GET" : "PATCH"))
            #expect(endpoint.route == routes[index])
            #expect(endpoint.successStatuses == (index < 3 ? [200] : [204]))
            #expect(endpoint.authentication == .bot)
            #expect(endpoint.majorParameter == (index == 0 ? nil : "18446744073709551615"))
            #expect(endpoint.retrySafety == (index < 3 ? .safe : .unsafe))
            #expect((endpoint.readPolicy != nil) == (index < 3))
            #expect(endpoint.invalidates.isEmpty == (index < 3))
            #expect(endpoint.auditReason == nil && endpoint.bulk == nil)
            #expect(endpoint.query.isEmpty && endpoint.headers.isEmpty && endpoint.usesGlobalLimit)
            let request = try endpoint.makeRequest(credential: .bot(try BotToken("synthetic")), userAgent: "test")
            #expect(request.url.absoluteString == "https://discord.com/api/v10/" + paths[index])
            #expect(request.headers.contains { $0.name == "Authorization" && $0.value == "Bot synthetic" })
            for credential in [Credential.none, .bearer(try BearerToken("synthetic"))] {
                #expect(throws: DiscordError.validation(.missingValue)) { try endpoint.makeRequest(credential: credential, userAgent: "test") }
            }
            #expect(try endpoint.decode(item.1) == item.1)
            if index == 3 {
                #expect(try JSONValue.parse(#require(endpoint.body?.storedBodyBytes)) == .object([
                    "channel_id": .string("18446744073709551615"), "suppress": .bool(false), "request_to_speak_timestamp": .null]))
            } else if index == 4 {
                #expect(try JSONValue.parse(#require(endpoint.body?.storedBodyBytes)) == .object(["suppress": .bool(true)]))
            } else { #expect(endpoint.body == nil) }
            for malformed in ["null", "{}", "[{}]", #""bad""#] {
                #expect(throws: DiscordError.transport(.invalidResponse)) { try endpoint.decode(Data(malformed.utf8)) }
            }
            if index < 3 { #expect(throws: JSONValueError.self) { try endpoint.decode(Data()) } }
        }
        #expect(try VoiceEndpoints.listRegions().decode(Data("[]".utf8)).isEmpty)
        let alias = try GuildEndpoints.voiceRegions(guildID: .init(rawValue: 1)).decode(Data("[]".utf8))
        #expect(alias.isEmpty)
    }

    /// All read policies preserve explicit coalescing/TTL/tags and nil semantics; invalid TTLs fail before I/O.
    /// Voice-state writes intersect guild/state read tags so existing guild and Stage mutations remain compatible.
    /// - Throws: Unexpected descriptor failures fail the test; invalid TTL failures are asserted.
    @Test func readPoliciesAndInvalidation() throws {
        let guild = GuildID(rawValue: 1), user = UserID(rawValue: 2)
        let policy = ReadPolicy(coalescing: false, timeToLive: .seconds(5), tags: ["caller"])
        let reads = try [Self.erase(VoiceEndpoints.listRegions(readPolicy: policy)),
            Self.erase(VoiceEndpoints.currentUserState(guildID: guild, readPolicy: policy)),
            Self.erase(VoiceEndpoints.userState(guildID: guild, userID: user, readPolicy: policy))]
        for (index, read) in reads.enumerated() {
            #expect(read.readPolicy?.coalescing == false)
            #expect(read.readPolicy?.timeToLive == .seconds(5))
            #expect(read.readPolicy?.tags == (index == 0 ? ["caller", "voice-region-catalog"] :
                ["caller", "voice-state-catalog", "guild-catalog", "channel-catalog"]))
        }
        #expect(try VoiceEndpoints.listRegions(readPolicy: nil).readPolicy == nil)
        #expect(try VoiceEndpoints.currentUserState(guildID: guild, readPolicy: nil).readPolicy == nil)
        #expect(try VoiceEndpoints.userState(guildID: guild, userID: user, readPolicy: nil).readPolicy == nil)
        for ttl in [Duration.zero, .seconds(-1)] {
            let invalid = ReadPolicy(timeToLive: ttl)
            #expect(throws: DiscordError.validation(.invalidValue)) { try VoiceEndpoints.listRegions(readPolicy: invalid) }
            #expect(throws: DiscordError.validation(.invalidValue)) { try VoiceEndpoints.currentUserState(guildID: guild, readPolicy: invalid) }
            #expect(throws: DiscordError.validation(.invalidValue)) { try VoiceEndpoints.userState(guildID: guild, userID: user, readPolicy: invalid) }
        }
        for endpoint in try [Self.erase(VoiceEndpoints.modifyCurrentUserState(guildID: guild, request: .init())),
                              Self.erase(VoiceEndpoints.modifyUserState(guildID: guild, userID: user, request: .init()))] {
            #expect(endpoint.invalidates == guildTags(guild).union(["voice-state-catalog"]))
            #expect(try JSONValue.parse(#require(endpoint.body?.storedBodyBytes)) == .object([:]))
            _ = try endpoint.decode(Data())
        }
        #expect(try VoiceEndpoints.modifyCurrentUserState(guildID: guild,
            request: .init(requestToSpeakTimestamp: .value(.init(rawValue: "2026-10-16T12:34:56.123456789+00:00"))))
            .body?.storedBodyBytes == JSONValue.object([
                "request_to_speak_timestamp": .string("2026-10-16T12:34:56.123456789+00:00")]).serialized())
    }

    /// Supplies every written Voice operation with an independent valid success fixture and its original decoder retained.
    /// - Returns: Ordered global regions/current state/user state/current edit/user edit descriptors and expected bytes.
    /// - Throws: Fixture body or descriptor validation errors; no network or credentials are accessed.
    static func catalog() throws -> [(Endpoint<Data>, Data)] {
        let guild = GuildID(rawValue: UInt64.max), user = UserID(rawValue: UInt64.max)
        return try [
            (erase(VoiceEndpoints.listRegions()), Data("[\(regionJSON)]".utf8)),
            (erase(VoiceEndpoints.currentUserState(guildID: guild)), Data(stateJSON.utf8)),
            (erase(VoiceEndpoints.userState(guildID: guild, userID: user)), Data(stateJSON.utf8)),
            (erase(VoiceEndpoints.modifyCurrentUserState(guildID: guild,
                request: .init(channelID: .value(.init(rawValue: UInt64.max)), suppress: .value(false), requestToSpeakTimestamp: .null))), Data()),
            (erase(VoiceEndpoints.modifyUserState(guildID: guild, userID: user,
                request: .init(suppress: .value(true)))), Data())
        ]
    }

    /// Copies descriptor metadata while retaining the typed decoder before returning original bytes for integration assertions.
    /// - Parameter endpoint: Immutable production descriptor; its authentication, retry and cache contracts remain unchanged.
    /// - Returns: Equivalent bytes descriptor with original schema validation and exact success statuses.
    /// - Throws: Descriptor validation errors if the production fixture cannot be represented identically.
    static func erase<T: Sendable>(_ endpoint: Endpoint<T>) throws -> Endpoint<Data> {
        try Endpoint(method: endpoint.method, path: endpoint.path, route: endpoint.route, query: endpoint.query,
            authentication: endpoint.authentication, successStatuses: endpoint.successStatuses,
            majorParameter: endpoint.majorParameter, usesGlobalLimit: endpoint.usesGlobalLimit,
            auditReason: endpoint.auditReason, body: endpoint.body, headers: endpoint.headers,
            retrySafety: endpoint.retrySafety, readPolicy: endpoint.readPolicy, invalidates: endpoint.invalidates,
            bulk: endpoint.bulk, decode: { _ = try endpoint.decode($0); return $0 })
    }

    /// Complete written region object with opaque identifier and exact future JSON.
    static let regionJSON = #"{"id":"private-region","name":"Private Region","optimal":true,"deprecated":false,"custom":false,"future_private":1.234567890123456789e1000}"#
    /// Complete written state object retaining private session data, nullable fields and maximum user identifiers.
    static let stateJSON = #"{"guild_id":"18446744073709551615","channel_id":null,"user_id":"18446744073709551615","session_id":"private-session","deaf":false,"mute":false,"self_deaf":false,"self_mute":true,"self_video":false,"suppress":false,"request_to_speak_timestamp":null,"future_private":1.234567890123456789e1000}"#
}
