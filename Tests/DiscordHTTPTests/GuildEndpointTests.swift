// File: Tests/DiscordHTTPTests/GuildEndpointTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import DiscordModels
@testable import DiscordHTTP
import DiscordTransport
import Foundation
import Testing

/// Guild REST descriptors are checked against independent API v10 method/path/status/auth fixtures.
@Suite struct GuildEndpointTests {
    /// Every documented operation has an exact v10 route, conservative replay policy and original decoder.
    /// - Throws: Unexpected fixture, request, descriptor or decoder errors fail this test.
    @Test func completeCatalog() throws {
        let expected: [(String, String)] = [
            ("GET", ""), ("GET", "/preview"), ("PATCH", ""), ("GET", "/channels"),
            ("POST", "/channels"), ("PATCH", "/channels"), ("GET", "/threads/active"),
            ("GET", "/members/18446744073709551615"), ("GET", "/members"), ("GET", "/members/search"),
            ("PUT", "/members/18446744073709551615"), ("PATCH", "/members/18446744073709551615"),
            ("PATCH", "/members/@me"), ("PATCH", "/members/@me/nick"),
            ("PUT", "/members/18446744073709551615/roles/18446744073709551615"),
            ("DELETE", "/members/18446744073709551615/roles/18446744073709551615"),
            ("DELETE", "/members/18446744073709551615"), ("GET", "/bans"),
            ("GET", "/bans/18446744073709551615"), ("PUT", "/bans/18446744073709551615"),
            ("DELETE", "/bans/18446744073709551615"), ("POST", "/bulk-ban"),
            ("GET", "/roles"), ("GET", "/roles/18446744073709551615"), ("GET", "/roles/member-counts"),
            ("POST", "/roles"), ("PATCH", "/roles"), ("PATCH", "/roles/18446744073709551615"),
            ("DELETE", "/roles/18446744073709551615"), ("GET", "/prune"), ("POST", "/prune"),
            ("GET", "/regions"), ("GET", "/invites"), ("GET", "/integrations"),
            ("DELETE", "/integrations/18446744073709551615"), ("GET", "/widget"), ("PATCH", "/widget"),
            ("GET", "/widget.json"), ("GET", "/vanity-url"), ("GET", "/widget.png"),
            ("GET", "/welcome-screen"), ("PATCH", "/welcome-screen"),
            ("GET", "/onboarding"), ("PUT", "/onboarding"), ("PUT", "/incident-actions")
        ]
        let catalog = try Self.catalog()
        #expect(catalog.count == 45)
        for (index, entry) in catalog.enumerated() {
            let (endpoint, fixture) = entry
            let request = try endpoint.makeRequest(credential: .bot(try BotToken("synthetic")), userAgent: "DiscordBot test")
            #expect(endpoint.method == expected[index].0)
            #expect(request.url.path == "/api/v10/guilds/18446744073709551615" + expected[index].1)
            #expect(request.url.host == "discord.com")
            #expect(endpoint.majorParameter == "18446744073709551615")
            let authentication: AuthenticationPolicy = [37, 39].contains(index) ? .none : (index == 3 ? .botOrBearer : .bot)
            #expect(endpoint.authentication == authentication)
            #expect(request.headers.contains { $0.name == "Authorization" } == (authentication != .none))
            let statuses: Set<Int> = index == 10 ? [201, 204] : (fixture.isEmpty ? [204] : (index == 4 ? [201] : [200]))
            #expect(endpoint.successStatuses == statuses)
            #expect(endpoint.retrySafety == (endpoint.method == "GET" ? .safe : .unsafe))
            #expect(endpoint.readPolicy?.coalescing == (endpoint.method == "GET" ? true : nil))
            #expect(endpoint.readPolicy?.timeToLive == nil)
            #expect(endpoint.method == "GET" ? endpoint.readPolicy?.tags.contains("guild-catalog") == true : endpoint.invalidates.contains("guild-catalog"))
            #expect(try endpoint.decode(fixture) == fixture)
            #expect(throws: (any Error).self) { try endpoint.decode(Data("null".utf8)) }
        }
    }

    /// Count flags, exact cursors, comma-separated prune roles and search escaping preserve API semantics.
    /// - Throws: Unexpected descriptor/request/model fixture errors fail the test.
    @Test func queryContracts() throws {
        let guild = GuildID(rawValue: UInt64.max), user = UserID(rawValue: UInt64.max)
        #expect(try GuildEndpoints.get(guildID: guild).query == [.init(name: "with_counts", value: "false")])
        #expect(try GuildEndpoints.get(guildID: guild, withCounts: true).query == [.init(name: "with_counts", value: "true")])
        #expect(try GuildEndpoints.members(guildID: guild).query.isEmpty)
        let members = try GuildEndpoints.members(guildID: guild, after: user, limit: 1_000, readPolicy: nil)
        #expect(members.query == [.init(name: "limit", value: "1000"), .init(name: "after", value: user.description)])
        #expect(members.readPolicy == nil)
        let bans = try GuildEndpoints.bans(guildID: guild, before: user, after: .init(rawValue: 9_007_199_254_740_993), limit: 1)
        #expect(bans.query == [.init(name: "limit", value: "1"), .init(name: "before", value: user.description),
                              .init(name: "after", value: "9007199254740993")])
        #expect(try GuildEndpoints.bans(guildID: guild).query.isEmpty)
        let search = try GuildEndpoints.searchMembers(guildID: guild, query: "a +&?日本", limit: 1_000)
        #expect(search.query == [.init(name: "query", value: "a +&?日本"), .init(name: "limit", value: "1000")])
        let wire = try search.makeRequest(credential: .bot(try BotToken("synthetic")), userAgent: "test")
        #expect(wire.url.absoluteString.contains("a%20%2B%26%3F"))
        #expect(try GuildEndpoints.searchMembers(guildID: guild, query: "").query == [.init(name: "query", value: "")])
        #expect(try GuildEndpoints.pruneCount(guildID: guild).query.isEmpty)
        let prune = try GuildEndpoints.pruneCount(guildID: guild, days: 30,
            includeRoles: [.init(rawValue: UInt64.max), .init(rawValue: 9_007_199_254_740_993)])
        #expect(prune.query == [.init(name: "days", value: "30"),
            .init(name: "include_roles", value: "18446744073709551615,9007199254740993")])
        #expect(try GuildEndpoints.pruneCount(guildID: guild, days: 1).query.first?.value == "1")
    }

    /// Zero, negative, oversized and machine-extreme list bounds fail before any transport ownership.
    /// - Parameter limit: Invalid value outside the documented 1...1,000 range.
    /// - Throws: Only unexpected fixture construction errors; expected rejections are asserted locally.
    @Test(arguments: [0, -1, 1_001, Int.min, Int.max]) func invalidPagination(limit: Int) throws {
        let guild = GuildID(rawValue: 1)
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildEndpoints.members(guildID: guild, limit: limit) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildEndpoints.bans(guildID: guild, limit: limit) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildEndpoints.searchMembers(guildID: guild, query: "a", limit: limit) }
    }

    /// Prune windows, unique role filters and the published 100-role cap reject invalid configurations.
    /// - Throws: Unexpected descriptor construction errors fail the test.
    @Test func pruneBoundaries() throws {
        let guild = GuildID(rawValue: 1)
        for days in [Int.min, -1, 0, 31, Int.max] {
            #expect(throws: DiscordError.validation(.invalidValue)) { try GuildEndpoints.pruneCount(guildID: guild, days: days) }
        }
        #expect(throws: DiscordError.validation(.invalidValue)) {
            try GuildEndpoints.pruneCount(guildID: guild, includeRoles: [.init(rawValue: 1), .init(rawValue: 1)])
        }
        let roles = (0..<101).map { RoleID(rawValue: UInt64($0)) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildEndpoints.pruneCount(guildID: guild, includeRoles: roles) }
        #expect(try GuildEndpoints.pruneCount(guildID: guild, includeRoles: Array(roles.prefix(100))).query.count == 1)
    }

    /// Position arrays preserve explicit nulls and order while rejecting duplicates and multiple parent moves.
    /// - Throws: Unexpected request/descriptor/JSON errors fail the test.
    @Test func positionArrayRules() throws {
        let guild = GuildID(rawValue: 1), channel = ChannelID(rawValue: UInt64.max), role = RoleID(rawValue: UInt64.max)
        let first = try GuildChannelPosition(id: channel, position: .null, lockPermissions: .value(true), parentID: .null)
        let second = try GuildChannelPosition(id: .init(rawValue: 2), position: .value(Int.min))
        let endpoint = try GuildEndpoints.modifyChannelPositions(guildID: guild, positions: [first, second])
        #expect(try JSONValue.parse(#require(endpoint.body?.storedBodyBytes)) == .array([first.jsonValue(), second.jsonValue()]))
        #expect(endpoint.auditReason == nil)
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildEndpoints.modifyChannelPositions(guildID: guild, positions: []) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildEndpoints.modifyChannelPositions(guildID: guild, positions: [first, first]) }
        let otherParent = try GuildChannelPosition(id: .init(rawValue: 3), parentID: .value(.init(rawValue: 4)))
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildEndpoints.modifyChannelPositions(guildID: guild, positions: [first, otherParent]) }
        let roleFirst = try GuildRolePosition(id: role, position: .null)
        let roleSecond = try GuildRolePosition(id: .init(rawValue: 2), position: .value(Int.max))
        let reorder = try GuildEndpoints.modifyRolePositions(guildID: guild, positions: [roleFirst, roleSecond], auditReason: "reason +")
        #expect(try JSONValue.parse(#require(reorder.body?.storedBodyBytes)) == .array([roleFirst.jsonValue(), roleSecond.jsonValue()]))
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildEndpoints.modifyRolePositions(guildID: guild, positions: []) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildEndpoints.modifyRolePositions(guildID: guild, positions: [roleFirst, roleFirst]) }
        let channels = try (0..<1_001).map { try GuildChannelPosition(id: .init(rawValue: UInt64($0))) }
        let roles = try (0..<1_001).map { try GuildRolePosition(id: .init(rawValue: UInt64($0))) }
        #expect(try GuildEndpoints.modifyChannelPositions(guildID: guild, positions: Array(channels.prefix(1_000))).body != nil)
        #expect(try GuildEndpoints.modifyRolePositions(guildID: guild, positions: Array(roles.prefix(1_000))).body != nil)
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildEndpoints.modifyChannelPositions(guildID: guild, positions: channels) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildEndpoints.modifyRolePositions(guildID: guild, positions: roles) }
    }

    /// Explicit freshness/coalescing choices survive catalog augmentation; guild writes invalidate related reads.
    /// - Throws: Unexpected descriptor/request errors fail the test.
    @Test func scopedPolicyAndBulkMetadata() throws {
        let guild = GuildID(rawValue: UInt64.max)
        let read = try GuildEndpoints.get(guildID: guild, readPolicy: .init(coalescing: false, timeToLive: .seconds(2), tags: ["custom"]))
        #expect(read.readPolicy?.coalescing == false)
        #expect(read.readPolicy?.timeToLive == .seconds(2))
        #expect(read.readPolicy?.tags == ["custom", "guild-catalog", "channel-catalog"])
        #expect(try GuildEndpoints.get(guildID: guild, readPolicy: nil).readPolicy == nil)
        let bulk = try GuildEndpoints.bulkBan(guildID: guild, request: GuildBulkBan(userIDs: [.init(rawValue: UInt64.max)]), auditReason: "reason +")
        #expect(bulk.bulk?.maximumItems == 200)
        #expect(bulk.bulk?.preservesOrder == false)
        #expect(bulk.bulk?.permitsPartialResults == true)
        #expect(bulk.bulk?.documentationURL.absoluteString == "https://docs.discord.com/developers/resources/guild#bulk-guild-ban")
        #expect(bulk.invalidates == ["guild-catalog", "guild:18446744073709551615", "channel-catalog", "message-search", "message-catalog"])
        let wire = try bulk.makeRequest(credential: .bot(try BotToken("synthetic")), userAgent: "test")
        #expect(wire.headers.contains { $0.name == "X-Audit-Log-Reason" && $0.value == "reason%20%2B" })
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildEndpoints.bulkBan(guildID: guild, request: GuildBulkBan(userIDs: [.init(rawValue: 1)]), auditReason: "\n") }
        #expect(throws: DiscordError.validation(.invalidValue)) { try GuildEndpoints.modifyRole(guildID: guild, roleID: .init(rawValue: 1), request: GuildRoleModify(), auditReason: String(repeating: "a", count: 513)) }
    }

    /// Secret-bearing joins keep the user grant in bounded JSON and the bot credential solely in Authorization.
    /// - Throws: Unexpected payload/descriptor/request/model errors fail the test.
    @Test func memberJoinAndPayloads() throws {
        let guild = GuildID(rawValue: UInt64.max), user = UserID(rawValue: UInt64.max)
        let join = try GuildEndpoints.addMember(guildID: guild, userID: user,
            request: GuildMemberAdd(accessToken: "joining-user-secret", nick: .value("nickname")))
        #expect(try JSONValue.parse(#require(join.body?.storedBodyBytes)) == .object([
            "access_token": .string("joining-user-secret"), "nick": .string("nickname")]))
        let wire = try join.makeRequest(credential: .bot(try BotToken("outer-bot-secret")), userAgent: "test")
        #expect(wire.headers.contains { $0.name == "Authorization" && $0.value == "Bot outer-bot-secret" })
        #expect(!wire.url.absoluteString.contains("joining-user-secret"))
        #expect(!String(reflecting: join).contains("joining-user-secret"))
        #expect(!String(reflecting: join).contains("nickname"))
        #expect(try join.decode(Data()) == nil)
        #expect(try join.decode(Data(Self.memberJSON.utf8)) != nil)
        let modify = try GuildEndpoints.modifyMember(guildID: guild, userID: user,
            request: GuildMemberModify(nick: .null, roles: .value([]), channelID: .null))
        #expect(try JSONValue.parse(#require(modify.body?.storedBodyBytes)) == .object(["nick": .null, "roles": .array([]), "channel_id": .null]))
        #expect(modify.successStatuses == [200])
        let create = try GuildEndpoints.createRole(guildID: guild, request: GuildRoleCreate())
        #expect(try JSONValue.parse(#require(create.body?.storedBodyBytes)) == .object([:]))
        let prune = try GuildEndpoints.beginPrune(guildID: guild, request: GuildPrune(computePruneCount: .value(false)))
        #expect(try JSONValue.parse(#require(prune.body?.storedBodyBytes)) == .object(["compute_prune_count": .bool(false)]))
        #expect(try prune.decode(Data("{\"pruned\":null}".utf8)).rawFields["pruned"] == .null)
    }

    /// Public widgets omit credentials even for bot clients; image styles and PNG signature bounds are explicit.
    /// - Parameter style: Each documented widget image style.
    /// - Throws: Unexpected descriptor/request errors fail the test.
    @Test(arguments: GuildWidgetImageStyle.allCases) func publicWidget(style: GuildWidgetImageStyle) throws {
        let guild = GuildID(rawValue: UInt64.max)
        let image = try GuildEndpoints.widgetImage(guildID: guild, style: style)
        #expect(image.query == [.init(name: "style", value: style.rawValue)])
        for credential in [Credential.none, .bot(try BotToken("secret")), .bearer(try BearerToken("secret"))] {
            for endpoint in [image, try Self.erase(GuildEndpoints.widget(guildID: guild))] {
                let wire = try endpoint.makeRequest(credential: credential, userAgent: "test")
                #expect(!wire.headers.contains { $0.name == "Authorization" })
            }
        }
        #expect(try image.decode(Self.pngData) == Self.pngData)
        for invalid in [Data(), Data([137, 80, 78, 71, 13, 10, 26, 10]), Data("not-png".utf8), Data("{}".utf8)] {
            #expect(throws: DiscordError.transport(.invalidResponse)) { try image.decode(invalid) }
        }
        let channels = try GuildEndpoints.channels(guildID: guild)
        #expect(try channels.makeRequest(credential: .bearer(try BearerToken("bearer")), userAgent: "test").headers.contains { $0.name == "Authorization" && $0.value == "Bearer bearer" })
    }

    /// All collection decoders reject nonarrays and malformed elements while preserving empty responses.
    /// - Throws: Unexpected fixture or descriptor errors fail the test.
    @Test func collectionShapeRejection() throws {
        let catalog = try Self.catalog()
        for index in [3, 8, 9, 17, 22, 26, 31, 32, 33] {
            let endpoint = catalog[index].0
            #expect(try endpoint.decode(Data("[]".utf8)) == Data("[]".utf8))
            for bad in ["{}", "null", "[null]", "[{}]"] {
                #expect(throws: (any Error).self) { try endpoint.decode(Data(bad.utf8)) }
            }
        }
    }

    /// Supplies the complete official-reference order, retaining original typed decoding for integration tests.
    /// - Returns: Exactly 45 descriptor/success-body pairs, including legacy nick, active threads and public PNG.
    /// - Throws: Request/descriptor fixture errors, indicating invalid test setup rather than an expected failure.
    static func catalog() throws -> [(Endpoint<Data>, Data)] {
        let guild = GuildID(rawValue: UInt64.max), user = UserID(rawValue: UInt64.max), role = RoleID(rawValue: UInt64.max)
        let bytes = Data(guildJSON.utf8), member = Data(memberJSON.utf8), roles = Data("[\(roleJSON)]".utf8)
        let empty = Data(), list = Data("[]".utf8)
        return [
            (try erase(GuildEndpoints.get(guildID: guild)), bytes),
            (try erase(GuildEndpoints.preview(guildID: guild)), Data(previewJSON.utf8)),
            (try erase(GuildEndpoints.modify(guildID: guild, request: GuildModify(name: .value("updated")))), bytes),
            (try erase(GuildEndpoints.channels(guildID: guild)), Data("[\(ChannelEndpointTests.channelJSON)]".utf8)),
            (try erase(GuildEndpoints.createChannel(guildID: guild, request: GuildChannelCreate(name: "created"))), Data(ChannelEndpointTests.channelJSON.utf8)),
            (try erase(GuildEndpoints.modifyChannelPositions(guildID: guild, positions: [GuildChannelPosition(id: .init(rawValue: UInt64.max))])), empty),
            (try erase(GuildEndpoints.activeThreads(guildID: guild)), Data("{\"threads\":[],\"members\":[]}".utf8)),
            (try erase(GuildEndpoints.member(guildID: guild, userID: user)), member),
            (try erase(GuildEndpoints.members(guildID: guild)), Data("[\(memberJSON)]".utf8)),
            (try erase(GuildEndpoints.searchMembers(guildID: guild, query: "query")), Data("[\(memberJSON)]".utf8)),
            (try erase(GuildEndpoints.addMember(guildID: guild, userID: user, request: GuildMemberAdd(accessToken: "grant"))), member),
            (try erase(GuildEndpoints.modifyMember(guildID: guild, userID: user, request: GuildMemberModify(nick: .null))), member),
            (try erase(GuildEndpoints.modifyCurrentMember(guildID: guild, request: GuildCurrentMemberModify(nick: .null))), member),
            (try erase(GuildEndpoints.modifyCurrentUserNick(guildID: guild, request: GuildCurrentUserNickModify(nick: .null))), Data("{\"nick\":null}".utf8)),
            (try erase(GuildEndpoints.addMemberRole(guildID: guild, userID: user, roleID: role)), empty),
            (try erase(GuildEndpoints.removeMemberRole(guildID: guild, userID: user, roleID: role)), empty),
            (try erase(GuildEndpoints.removeMember(guildID: guild, userID: user)), empty),
            (try erase(GuildEndpoints.bans(guildID: guild)), Data("[\(banJSON)]".utf8)),
            (try erase(GuildEndpoints.ban(guildID: guild, userID: user)), Data(banJSON.utf8)),
            (try erase(GuildEndpoints.createBan(guildID: guild, userID: user, request: GuildBanCreate())), empty),
            (try erase(GuildEndpoints.removeBan(guildID: guild, userID: user)), empty),
            (try erase(GuildEndpoints.bulkBan(guildID: guild, request: GuildBulkBan(userIDs: [user]))), Data("{\"banned_users\":[\"18446744073709551615\"],\"failed_users\":[]}".utf8)),
            (try erase(GuildEndpoints.roles(guildID: guild)), roles),
            (try erase(GuildEndpoints.role(guildID: guild, roleID: role)), Data(roleJSON.utf8)),
            (try erase(GuildEndpoints.roleMemberCounts(guildID: guild)), Data("{\"18446744073709551615\":0}".utf8)),
            (try erase(GuildEndpoints.createRole(guildID: guild, request: GuildRoleCreate())), Data(roleJSON.utf8)),
            (try erase(GuildEndpoints.modifyRolePositions(guildID: guild, positions: [GuildRolePosition(id: role)])), roles),
            (try erase(GuildEndpoints.modifyRole(guildID: guild, roleID: role, request: GuildRoleModify(name: .null))), Data(roleJSON.utf8)),
            (try erase(GuildEndpoints.deleteRole(guildID: guild, roleID: role)), empty),
            (try erase(GuildEndpoints.pruneCount(guildID: guild)), Data("{\"pruned\":0}".utf8)),
            (try erase(GuildEndpoints.beginPrune(guildID: guild, request: GuildPrune(computePruneCount: .value(false)))), Data("{\"pruned\":null}".utf8)),
            (try erase(GuildEndpoints.voiceRegions(guildID: guild)), list),
            (try erase(GuildEndpoints.invites(guildID: guild)), Data("[\(ChannelEndpointTests.inviteJSON)]".utf8)),
            (try erase(GuildEndpoints.integrations(guildID: guild)), list),
            (try erase(GuildEndpoints.deleteIntegration(guildID: guild, integrationID: .init(rawValue: UInt64.max))), empty),
            (try erase(GuildEndpoints.widgetSettings(guildID: guild)), Data(widgetSettingsJSON.utf8)),
            (try erase(GuildEndpoints.modifyWidget(guildID: guild, request: GuildWidgetModify(enabled: .value(false)))), Data(widgetSettingsJSON.utf8)),
            (try erase(GuildEndpoints.widget(guildID: guild)), Data(widgetJSON.utf8)),
            (try erase(GuildEndpoints.vanityURL(guildID: guild)), Data("{\"code\":null,\"uses\":0}".utf8)),
            (try GuildEndpoints.widgetImage(guildID: guild), pngData),
            (try erase(GuildEndpoints.welcomeScreen(guildID: guild)), Data(welcomeJSON.utf8)),
            (try erase(GuildEndpoints.modifyWelcomeScreen(guildID: guild, request: GuildWelcomeScreenModify(description: .null))), Data(welcomeJSON.utf8)),
            (try erase(GuildEndpoints.onboarding(guildID: guild)), Data(onboardingJSON.utf8)),
            (try erase(GuildEndpoints.modifyOnboarding(guildID: guild, request: GuildOnboardingModify(enabled: .value(false)))), Data(onboardingJSON.utf8)),
            (try erase(GuildEndpoints.modifyIncidentActions(guildID: guild, request: GuildIncidentActionsModify(invitesDisabledUntil: .null))), Data(incidentJSON.utf8))
        ]
    }

    /// Independent minimal API fixture for guild success responses.
    static let guildJSON = #"{"id":"18446744073709551615","name":"fixture","icon":null,"splash":null,"owner_id":"9007199254740993","afk_channel_id":null,"afk_timeout":300,"verification_level":0,"default_message_notifications":0,"explicit_content_filter":0,"roles":[],"emojis":[],"features":[],"mfa_level":0,"application_id":null,"system_channel_id":null,"system_channel_flags":0,"rules_channel_id":null,"vanity_url_code":null,"description":null,"banner":null,"premium_tier":0,"preferred_locale":"en-US","public_updates_channel_id":null,"nsfw_level":0,"premium_progress_bar_enabled":false,"safety_alerts_channel_id":null,"incidents_data":null}"#

    /// Independent minimal API fixture for preview success responses.
    static let previewJSON = #"{"id":"18446744073709551615","name":"fixture","icon":null,"splash":null,"emojis":[],"features":[],"description":null,"discovery_splash":null,"approximate_member_count":0,"approximate_presence_count":0,"stickers":[]}"#

    /// Independent minimal API fixture for member success responses.
    static let memberJSON = #"{"user":{"id":"18446744073709551615"},"roles":[],"joined_at":null,"deaf":false,"mute":false,"flags":0}"#

    /// Independent minimal API fixture for role success responses.
    static let roleJSON = #"{"id":"18446744073709551615","name":"role","color":0,"colors":{"primary_color":0,"secondary_color":null,"tertiary_color":null},"hoist":false,"position":0,"permissions":"0","managed":false,"mentionable":false,"flags":0}"#

    /// Independent minimal API fixture for ban success responses.
    static let banJSON = #"{"reason":null,"user":{"id":"18446744073709551615"}}"#

    /// Independent minimal API fixture for widgetSettings success responses.
    static let widgetSettingsJSON = #"{"enabled":false,"channel_id":null}"#

    /// Independent minimal API fixture for widget success responses.
    static let widgetJSON = #"{"id":"18446744073709551615","name":"fixture","instant_invite":null,"channels":[],"members":[],"presence_count":0}"#

    /// Independent minimal API fixture for welcome success responses.
    static let welcomeJSON = #"{"description":null,"welcome_channels":[]}"#

    /// Independent minimal API fixture for onboarding success responses.
    static let onboardingJSON = #"{"guild_id":"18446744073709551615","prompts":[],"default_channel_ids":[],"enabled":false,"mode":0}"#

    /// Independent minimal API fixture for incident success responses.
    static let incidentJSON = #"{"invites_disabled_until":null,"dms_disabled_until":null}"#

    /// Binary fixture proves PNG signature handling without introducing an image-decoding dependency.
    static let pngData = Data([137, 80, 78, 71, 13, 10, 26, 10, 0])

    /// Erases only the result type while retaining all metadata and invoking the original typed decoder.
    /// - Parameter value: Typed descriptor whose response fixture must continue satisfying its model contract.
    /// - Returns: An equivalent raw-byte descriptor that first validates the original response decoder.
    /// - Throws: Descriptor validation errors before execution; typed decoding errors when the returned decoder runs.
    static func erase<T>(_ value: Endpoint<T>) throws -> Endpoint<Data> {
        try Endpoint(method: value.method, path: value.path, route: value.route, query: value.query,
            authentication: value.authentication, successStatuses: value.successStatuses, majorParameter: value.majorParameter,
            usesGlobalLimit: value.usesGlobalLimit, auditReason: value.auditReason, body: value.body, headers: value.headers,
            retrySafety: value.retrySafety, readPolicy: value.readPolicy, invalidates: value.invalidates, bulk: value.bulk,
            maximumQueryItems: 2_048, maximumMetadataBytes: 1_048_576,
            decode: { bytes in _ = try value.decode(bytes); return bytes })
    }
}
