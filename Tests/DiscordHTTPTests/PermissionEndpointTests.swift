// File: Tests/DiscordHTTPTests/PermissionEndpointTests.swift
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

/// Independent API v10 fixtures exercise all four server-computed permission retrieval routes.
@Suite(.timeLimit(.minutes(1))) struct PermissionEndpointTests {
    /// Descriptors retain exact high identifiers, normalized routes, bot authentication and finite shared read policy.
    /// - Parameter index: Guild member, guild role, channel member or channel role in that order.
    /// - Throws: Unexpected descriptor, credential, request or decoder errors fail the test.
    @Test(arguments: 0..<4) func descriptor(index: Int) throws {
        let endpoint = try Self.endpoint(index)
        let resource = index < 2 ? "guilds" : "channels"
        let target = index.isMultiple(of: 2) ? "member" : "role"
        let major = index < 2 ? "{guild.id}" : "{channel.id}"
        let targetID = index.isMultiple(of: 2) ? "{user.id}" : "{role.id}"
        let wire = try endpoint.makeRequest(credential: .bot(try BotToken("synthetic")), userAgent: "DiscordBot test")
        #expect(endpoint.method == "GET")
        #expect(endpoint.path == [resource, "18446744073709551615", "permissions", target, "9007199254740993"])
        #expect(endpoint.route == "/\(resource)/\(major)/permissions/\(target)/\(targetID)")
        #expect(wire.url.absoluteString == "https://discord.com/api/v10/\(resource)/18446744073709551615/permissions/\(target)/9007199254740993")
        #expect(wire.headers.contains { $0.name == "Authorization" && $0.value == "Bot synthetic" })
        #expect(endpoint.authentication == .bot)
        #expect(endpoint.successStatuses == [200])
        #expect(endpoint.majorParameter == "18446744073709551615")
        #expect(endpoint.retrySafety == .safe)
        #expect(endpoint.readPolicy?.coalescing == true)
        #expect(endpoint.readPolicy?.timeToLive == nil)
        #expect(endpoint.readPolicy?.tags.contains("channel-catalog") == true)
        #expect(endpoint.readPolicy?.tags.contains("guild-catalog") == (index < 2))
        #expect(endpoint.query.isEmpty)
        #expect(endpoint.body == nil)
        #expect(endpoint.auditReason == nil)
        #expect(endpoint.invalidates.isEmpty)
        #expect(endpoint.bulk == nil)
        #expect(try endpoint.decode(Self.bytes).permissions == "18446744073709551616000001")
        #expect(try endpoint.decode(Self.bytes).rawFields["future_secret"] == .string("private-permission"))
        for credential in [Credential.none, .bearer(try BearerToken("synthetic"))] {
            #expect(throws: DiscordError.validation(.missingValue)) {
                try endpoint.makeRequest(credential: credential, userAgent: "DiscordBot test")
            }
        }
    }

    /// Channel masking preserves omission/default and both explicit Boolean choices; request reuse keys separate them.
    /// Caller freshness, coalescing, custom tags and opt-out survive the resource catalog policy.
    /// - Throws: Unexpected descriptor/request errors fail the test.
    @Test func maskingAndReadPolicy() throws {
        let guild = GuildID(rawValue: UInt64.max), channel = ChannelID(rawValue: UInt64.max)
        let user = UserID(rawValue: 9_007_199_254_740_993), role = RoleID(rawValue: 9_007_199_254_740_993)
        let policy = ReadPolicy(coalescing: false, timeToLive: .seconds(2), tags: ["custom"])
        let endpoints = [
            try GuildEndpoints.memberPermissions(guildID: guild, userID: user, readPolicy: policy),
            try GuildEndpoints.rolePermissions(guildID: guild, roleID: role, readPolicy: policy),
            try ChannelEndpoints.memberPermissions(channelID: channel, userID: user, readPolicy: policy),
            try ChannelEndpoints.rolePermissions(channelID: channel, roleID: role, readPolicy: policy)
        ]
        for endpoint in endpoints {
            #expect(endpoint.readPolicy?.coalescing == false)
            #expect(endpoint.readPolicy?.timeToLive == .seconds(2))
            #expect(endpoint.readPolicy?.tags.contains("custom") == true)
        }
        #expect(try GuildEndpoints.memberPermissions(guildID: guild, userID: user, readPolicy: nil).readPolicy == nil)
        #expect(try GuildEndpoints.rolePermissions(guildID: guild, roleID: role, readPolicy: nil).readPolicy == nil)
        #expect(try ChannelEndpoints.memberPermissions(channelID: channel, userID: user, readPolicy: nil).readPolicy == nil)
        #expect(try ChannelEndpoints.rolePermissions(channelID: channel, roleID: role, readPolicy: nil).readPolicy == nil)
        for index in 2..<4 {
            let omitted = try Self.endpoint(index)
            for implicit in [false, true] {
                let endpoint = try Self.endpoint(index, implicit: implicit)
                #expect(endpoint.query == [.init(name: "implicit", value: String(implicit))])
                let wire = try endpoint.makeRequest(credential: .bot(try BotToken("synthetic")), userAgent: "test")
                #expect(URLComponents(url: wire.url, resolvingAgainstBaseURL: false)?.query == "implicit=\(implicit)")
                #expect(endpoint.cacheIdentity != omitted.cacheIdentity)
            }
            #expect(try Self.endpoint(index, implicit: false).cacheIdentity != Self.endpoint(index, implicit: true).cacheIdentity)
        }
        #expect(endpoints[0].cacheIdentity != endpoints[1].cacheIdentity)
        #expect(endpoints[2].cacheIdentity != endpoints[3].cacheIdentity)
    }

    /// Execution sends only the specified permission read, retaining unknown fields and refreshing repeated calls by default.
    /// Scripted rate headers admit both reads without waiting on the manual clock's provisional discovery window.
    /// - Parameter index: Each of the four routes, executed twice with completed caching disabled.
    /// - Throws: Unexpected setup, response or execution failures fail the test.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: 0..<4) func success(index: Int) async throws {
        let endpoint = try Self.endpoint(index, implicit: index >= 2 ? false : nil)
        let step: ScriptedHTTPTransport.Step = { request in
            #expect(request.method == "GET")
            #expect(request.url.path == "/api/v10/" + endpoint.path.joined(separator: "/"))
            #expect(request.url.query == (index >= 2 ? "implicit=false" : nil))
            #expect(request.headers.contains { $0.name == "Authorization" && $0.value == "Bot synthetic" })
            #expect(request.body == nil)
            return HTTPResponse(status: 200, headers: [
                .init(name: "X-RateLimit-Limit", value: "2"),
                .init(name: "X-RateLimit-Remaining", value: "1"),
                .init(name: "X-RateLimit-Reset-After", value: "1")
            ], body: try RequestBody(bytes: Self.bytes, contentType: "application/json").makeStream())
        }
        let transport = try ScriptedHTTPTransport(steps: [step, step])
        let clock = ManualClock(), coordinator = RateLimitCoordinator(clock: clock)
        let client = RESTClient(credential: .bot(try BotToken("synthetic")), identity: .init(),
            transport: transport, coordinator: coordinator, clock: clock)
        for _ in 0..<2 {
            let result = try await client.execute(endpoint)
            #expect(result.permissions == "18446744073709551616000001")
            #expect(result.rawFields["future_secret"] == .string("private-permission"))
        }
        #expect(await transport.executionCount == 2)
        #expect(await coordinator.snapshot().activeCount == 0)
        #expect(await coordinator.snapshot().orderedOperationsCount == 0)
        #expect(clock.pendingSleepCount == 0)
        await coordinator.close()
    }

    /// API denials, missing resources, exhausted rate/server failures and undocumented 2xx statuses preserve status evidence.
    /// - Parameters:
    ///   - index: Every computed-permission route.
    ///   - status: Independently scripted response status outside the documented HTTP 200 success.
    /// - Throws: Unexpected setup/execution failures fail the test; the exact API status is asserted.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: 0..<4, [202, 204, 400, 401, 403, 404, 429, 500])
    func apiFailures(index: Int, status: Int) async throws {
        let endpoint = try Self.endpoint(index)
        let transport = try ScriptedHTTPTransport(steps: [{ _ in
            try Self.response(Data(#"{"code":50001,"message":"private-permission"}"#.utf8), status: status)
        }])
        let clock = ManualClock(), coordinator = RateLimitCoordinator(clock: clock)
        let client = RESTClient(credential: .bot(try BotToken("synthetic")), identity: .init(),
            transport: transport, coordinator: coordinator, clock: clock, retryPolicy: .init(maximumAttempts: 1))
        do { _ = try await client.execute(endpoint); Issue.record("Expected API status failure") }
        catch let error as APIResponseError {
            #expect(error.status == status)
            #expect(!String(reflecting: error).contains("private-permission"))
        }
        #expect(await transport.executionCount == 1)
        #expect(await coordinator.snapshot().activeCount == 0)
        #expect(clock.pendingSleepCount == 0)
        await coordinator.close()
    }

    /// Malformed successful permission envelopes fail through the typed decoder without leaving admission resources.
    /// - Parameter index: Each route; missing/null/wrong-root bodies must never become empty permissions.
    /// - Throws: Unexpected setup errors fail the test; sanitized schema failures are asserted.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: 0..<4) func malformedSuccess(index: Int) async throws {
        let endpoint = try Self.endpoint(index)
        for source in ["{}", "null", "[]", #"{"permissions":null}"#, #"{"permissions":0}"#] {
            let transport = try ScriptedHTTPTransport(steps: [{ _ in
                try Self.response(Data(source.utf8))
            }])
            let clock = ManualClock(), coordinator = RateLimitCoordinator(clock: clock)
            let client = RESTClient(credential: .bot(try BotToken("synthetic")), identity: .init(),
                transport: transport, coordinator: coordinator, clock: clock)
            await #expect(throws: DiscordError.transport(.invalidResponse)) { try await client.execute(endpoint) }
            #expect(await transport.executionCount == 1)
            #expect(await coordinator.snapshot().activeCount == 0)
            #expect(clock.pendingSleepCount == 0)
            await coordinator.close()
        }
    }

    /// An explicit rate rejection uses shared admission and exactly one bounded retry, including exhaustion cleanup.
    /// - Parameters:
    ///   - index: Every permission retrieval route.
    ///   - rejectedAgain: Whether the second attempt also returns 429 and exhausts the two-attempt budget.
    /// - Throws: Unexpected setup or execution errors fail the test; the exhausted API status is asserted.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: 0..<4, [false, true]) func boundedRateRetry(index: Int, rejectedAgain: Bool) async throws {
        let endpoint = try Self.endpoint(index)
        let rejected = Data(#"{"code":0,"message":"rate limited","retry_after":0.25,"global":false}"#.utf8)
        let transport = try ScriptedHTTPTransport(steps: [
            { _ in try Self.response(rejected, status: 429) },
            { _ in try Self.response(rejectedAgain ? rejected : Self.bytes, status: rejectedAgain ? 429 : 200) }
        ])
        let clock = ManualClock(), coordinator = RateLimitCoordinator(clock: clock)
        let client = RESTClient(credential: .bot(try BotToken("synthetic")), identity: .init(),
            transport: transport, coordinator: coordinator, clock: clock, retryPolicy: .init(maximumAttempts: 2))
        let task = Task { try await client.execute(endpoint) }
        while true {
            let calls = await transport.executionCount
            let state = await coordinator.snapshot()
            if calls == 1 && state.activeCount == 0 && state.queuedCount == 1 { break }
            try Task.checkCancellation()
            await Task.yield()
        }
        try clock.advance(by: .milliseconds(249))
        #expect(await transport.executionCount == 1)
        try clock.advance(by: .seconds(1))
        if rejectedAgain {
            do { _ = try await task.value; Issue.record("Expected exhausted rate rejection") }
            catch let error as APIResponseError { #expect(error.status == 429) }
        } else {
            #expect(try await task.value.permissions == "18446744073709551616000001")
        }
        #expect(await transport.executionCount == 2)
        #expect(await coordinator.snapshot().activeCount == 0)
        #expect(await coordinator.snapshot().queuedCount == 0)
        #expect(clock.pendingSleepCount == 0)
        await coordinator.close()
    }

    /// Builds one independently selected descriptor while preserving its original typed decoder for execution tests.
    /// - Parameters:
    ///   - index: Guild member/role then channel member/role, in the finite range 0...3.
    ///   - implicit: Optional explicit channel masking query; guild operations have no masking query.
    /// - Returns: One exact GET descriptor with IDs above the JavaScript integer precision boundary.
    /// - Throws: Descriptor errors or invalid-value for a fixture index outside the complete four-operation catalog.
    private static func endpoint(_ index: Int, implicit: Bool? = nil) throws -> Endpoint<ComputedPermissions> {
        let guild = GuildID(rawValue: UInt64.max), channel = ChannelID(rawValue: UInt64.max)
        let user = UserID(rawValue: 9_007_199_254_740_993), role = RoleID(rawValue: 9_007_199_254_740_993)
        switch index {
        case 0: return try GuildEndpoints.memberPermissions(guildID: guild, userID: user)
        case 1: return try GuildEndpoints.rolePermissions(guildID: guild, roleID: role)
        case 2: return try ChannelEndpoints.memberPermissions(channelID: channel, userID: user, implicit: implicit)
        case 3: return try ChannelEndpoints.rolePermissions(channelID: channel, roleID: role, implicit: implicit)
        default: throw DiscordError.validation(.invalidValue)
        }
    }

    /// Creates a finite scripted JSON response, whose stream belongs to the REST execution pipeline.
    /// - Parameters:
    ///   - bytes: Complete response bytes without real user data or credentials.
    ///   - status: Scripted HTTP status, defaulting to the documented success 200.
    /// - Returns: A response with one bounded replayable body stream and no rate-limit headers.
    /// - Throws: Body construction errors for invalid local limits; fixtures are deliberately small.
    private static func response(_ bytes: Data, status: Int = 200) throws -> HTTPResponse {
        HTTPResponse(status: status, body: try RequestBody(bytes: bytes, contentType: "application/json").makeStream())
    }

    /// A future permission bitfield exceeding UInt64, with an unrelated field that must survive typed decoding.
    private static let bytes = Data(#"{"permissions":"18446744073709551616000001","future_secret":"private-permission"}"#.utf8)
}
