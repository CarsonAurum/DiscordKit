// File: Tests/DiscordHTTPTests/MessageCatalogIntegrationTests.swift
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

/// Applies common real HTTP execution assertions to every one of the 22 resource descriptors.
@Suite(.timeLimit(.minutes(1))) struct MessageCatalogIntegrationTests {
    /// Each public route reaches the shared bot-authenticated pipeline and decodes its declared success.
    /// - Parameter index: Stable descriptor index from the complete current written-reference catalog.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: 0..<22) func success(index: Int) async throws {
        let (endpoint, bytes) = try Self.catalog()[index]
        let step: ScriptedHTTPTransport.Step = { request in
            #expect(request.method == endpoint.method)
            #expect(request.url.host == "discord.com")
            #expect(request.url.path.hasPrefix("/api/v10/"))
            #expect(request.headers.contains { $0.name == "Authorization" && $0.value == "Bot synthetic" })
            if let body = request.body { _ = try await ResponseBody.collect(body, maximumBytes: 1_048_576) }
            return HTTPResponse(status: endpoint.successStatuses.min()!, body: bytes.isEmpty ? nil : try RequestBody(bytes: bytes, contentType: "application/json").makeStream())
        }
        let transport = try ScriptedHTTPTransport(steps: [step])
        let clock = ManualClock()
        let coordinator = RateLimitCoordinator(clock: clock)
        let client = RESTClient(credential: .bot(try BotToken("synthetic")), identity: RateLimitIdentity(), transport: transport,
                                coordinator: coordinator, clock: clock, retryPolicy: .init(maximumAttempts: 1))
        #expect(try await client.execute(endpoint) == bytes)
        #expect(await transport.executionCount == 1)
        #expect(await coordinator.snapshot().activeCount == 0)
        #expect(await coordinator.snapshot().orderedOperationsCount == 0)
        await coordinator.close()
    }

    /// Every operation retains applicable API errors; unsafe server failures remain indeterminate.
    /// - Parameters:
    ///   - index: One of the complete 22 current/deprecated message and poll operations.
    ///   - status: Local validation/auth/permission/not-found/rate/server failure returned by the finite peer.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: 0..<22, [400, 401, 403, 404, 429, 500])
    func failures(index: Int, status: Int) async throws {
        let endpoint = try Self.catalog()[index].0
        let step: ScriptedHTTPTransport.Step = { request in
            await request.body?.close()
            return HTTPResponse(status: status, body: try RequestBody(bytes: Data("{\"code\":50035,\"message\":\"private\",\"errors\":{\"content\":{\"_errors\":[{\"code\":\"BAD\",\"message\":\"private\"}]}}}".utf8), contentType: "application/json").makeStream())
        }
        let transport = try ScriptedHTTPTransport(steps: [step])
        let clock = ManualClock()
        let coordinator = RateLimitCoordinator(clock: clock)
        let client = RESTClient(credential: .bot(try BotToken("synthetic")), identity: RateLimitIdentity(), transport: transport,
                                coordinator: coordinator, clock: clock, retryPolicy: .init(maximumAttempts: 1))
        do { _ = try await client.execute(endpoint); Issue.record("Expected failure") }
        catch let error as APIResponseError {
            #expect(status < 500 || endpoint.retrySafety == .safe)
            #expect(error.status == status)
            #expect(error.code == 50035)
            #expect(error.withUnsafePayload { $0 != nil })
            #expect(!String(reflecting: error).contains("private"))
        } catch let error as DiscordError {
            #expect(status == 500 && endpoint.retrySafety == .unsafe)
            #expect(error == .unknownMutationOutcome(.serverErrorAfterSubmission))
        }
        #expect(await transport.executionCount == 1)
        #expect(await coordinator.snapshot().activeCount == 0)
        #expect(await coordinator.snapshot().orderedOperationsCount == 0)
        await coordinator.close()
    }

    /// Every operation fails before transmission under caller cancellation, leaving no reservation.
    /// - Parameter index: Current/deprecated descriptor to execute from an already cancelled task.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: 0..<22) func cancelledBeforeSend(index: Int) async throws {
        let endpoint = try Self.catalog()[index].0
        let transport = try ScriptedHTTPTransport(steps: [])
        let clock = ManualClock()
        let coordinator = RateLimitCoordinator(clock: clock)
        let client = RESTClient(credential: .bot(try BotToken("synthetic")), identity: RateLimitIdentity(), transport: transport,
                                coordinator: coordinator, clock: clock)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await client.execute(endpoint)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await transport.executionCount == 0)
        #expect(await coordinator.snapshot().activeCount == 0)
        #expect(clock.pendingSleepCount == 0)
        await coordinator.close()
    }

    /// Catalogs one constructor and one valid fixture per currently available written-reference route.
    /// - Returns: Exactly 22 pairs; generic return types are erased only after retaining the original decoder.
    /// - Throws: A fixture/descriptor validation error, indicating invalid test setup.
    private static func catalog() throws -> [(Endpoint<Data>, Data)] {
        let c = ChannelID(rawValue: UInt64.max), m = MessageID(rawValue: 9_007_199_254_740_993)
        let msg = MessageEndpointTests.messageData(), empty = Data(), list = Data("[]".utf8)
        let e = ReactionEmoji.unicode("🔥")
        let now: UInt64 = 1_792_152_000_000
        let id = try MessageID(timestampMilliseconds: now)
        return [
            (try erase(MessageEndpoints.history(channelID: c)), list),
            (try erase(MessageEndpoints.search(guildID: .init(rawValue: 1), query: MessageSearchQuery())), Data("{\"doing_deep_historical_index\":false,\"total_results\":0,\"messages\":[]}".utf8)),
            (try erase(MessageEndpoints.get(channelID: c, messageID: m)), msg),
            (try erase(MessageEndpoints.create(channelID: c, request: MessageCreate(content: .value("hello")))), msg),
            (try erase(MessageEndpoints.crosspost(channelID: c, messageID: m)), msg),
            (try erase(MessageEndpoints.createReaction(channelID: c, messageID: m, emoji: e)), empty),
            (try erase(MessageEndpoints.deleteOwnReaction(channelID: c, messageID: m, emoji: e)), empty),
            (try erase(MessageEndpoints.deleteUserReaction(channelID: c, messageID: m, emoji: e, userID: .init(rawValue: 1))), empty),
            (try erase(MessageEndpoints.reactions(channelID: c, messageID: m, emoji: e)), list),
            (try erase(MessageEndpoints.deleteAllReactions(channelID: c, messageID: m)), empty),
            (try erase(MessageEndpoints.deleteEmojiReactions(channelID: c, messageID: m, emoji: e)), empty),
            (try erase(MessageEndpoints.edit(channelID: c, messageID: m, request: MessageEdit(content: .null))), msg),
            (try erase(MessageEndpoints.delete(channelID: c, messageID: m)), empty),
            (try erase(MessageEndpoints.bulkDelete(channelID: c, messageIDs: [id, .init(rawValue: id.rawValue + 1)], nowMilliseconds: now)), empty),
            (try erase(MessageEndpoints.pins(channelID: c)), Data("{\"items\":[],\"has_more\":false}".utf8)),
            (try erase(MessageEndpoints.pin(channelID: c, messageID: m)), empty),
            (try erase(MessageEndpoints.unpin(channelID: c, messageID: m)), empty),
            (try erase(MessageEndpoints.legacyPins(channelID: c)), list),
            (try erase(MessageEndpoints.legacyPin(channelID: c, messageID: m)), empty),
            (try erase(MessageEndpoints.legacyUnpin(channelID: c, messageID: m)), empty),
            (try erase(PollEndpoints.voters(channelID: c, messageID: m, answerID: 1)), Data("{\"users\":[]}".utf8)),
            (try erase(PollEndpoints.end(channelID: c, messageID: m)), msg),
        ]
    }

    /// Preserves all admission/auth/body/status/invalidation metadata while checking the typed decoder.
    /// - Parameter value: A resource descriptor whose response type is immaterial to common policy checks.
    /// - Returns: A descriptor returning the original bytes only after the original decoder succeeds.
    /// - Throws: Endpoint validation failures; execution-time model errors remain in the original decode closure.
    private static func erase<T>(_ value: Endpoint<T>) throws -> Endpoint<Data> {
        try Endpoint(method: value.method, path: value.path, route: value.route, query: value.query,
            authentication: value.authentication, successStatuses: value.successStatuses, majorParameter: value.majorParameter,
            usesGlobalLimit: value.usesGlobalLimit, auditReason: value.auditReason, body: value.body, headers: value.headers,
            retrySafety: value.retrySafety, readPolicy: value.readPolicy, invalidates: value.invalidates, bulk: value.bulk,
            maximumQueryItems: 2_048, maximumMetadataBytes: 1_048_576, decode: { bytes in _ = try value.decode(bytes); return bytes })
    }
}
