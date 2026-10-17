import DiscordCore
import DiscordModels
import DiscordTestSupport
import DiscordTransport
import Foundation
import Testing
@testable import DiscordHTTP

/// Exercises every Guild reference operation through real HTTP policy.
@Suite(.timeLimit(.minutes(1))) struct GuildCatalogIntegrationTests {
    /// Each descriptor sends one API v10 request with its exact authentication policy and decodes its success fixture.
    /// Public widgets suppress the configured bot credential; other descriptors use their declared authorization.
    /// - Parameter index: Stable operation position across all 45 Guild reference headings.
    /// - Throws: Unexpected fixture construction or HTTP execution errors fail the test; expected API, transport and cancellation failures are asserted locally.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: 0..<45) func success(index: Int) async throws {
        let (endpoint, bytes) = try GuildEndpointTests.catalog()[index]
        let step: ScriptedHTTPTransport.Step = { request in
            #expect(request.method == endpoint.method)
            #expect(request.url.host == "discord.com")
            #expect(request.url.path.hasPrefix("/api/v10/"))
            #expect(request.headers.contains { $0.name == "Authorization" && $0.value == "Bot synthetic" } == (endpoint.authentication != .none))
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
        #expect(clock.pendingSleepCount == 0)
        await coordinator.close()
    }

    /// Auth, permissions, validation, missing resources and rejected rate requests retain safe API evidence.
    /// - Parameters:
    ///   - index: Every public operation, including public widgets and deprecated nickname support.
    ///   - status: Scripted API failure; unsafe 5xx submissions preserve indeterminate mutation outcomes.
    /// - Throws: Unexpected fixture construction or HTTP execution errors fail the test; expected API, transport and cancellation failures are asserted locally.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: 0..<45, [400, 401, 403, 404, 429, 500])
    func failures(index: Int, status: Int) async throws {
        let endpoint = try GuildEndpointTests.catalog()[index].0
        let transport = try ScriptedHTTPTransport(steps: [{ request in
            await request.body?.close()
            return try Self.response(Data("{\"code\":50035,\"message\":\"private-evidence\",\"errors\":{\"name\":{\"_errors\":[{\"code\":\"BAD\",\"message\":\"private-evidence\"}]}}}".utf8), status: status)
        }])
        let clock = ManualClock()
        let coordinator = RateLimitCoordinator(clock: clock)
        let client = RESTClient(credential: .bot(try BotToken("synthetic")), identity: RateLimitIdentity(), transport: transport,
            coordinator: coordinator, clock: clock, retryPolicy: .init(maximumAttempts: 1))
        do { _ = try await client.execute(endpoint); Issue.record("Expected API failure") }
        catch let error as APIResponseError {
            #expect(status < 500 || endpoint.retrySafety == .safe)
            #expect(error.status == status)
            #expect(error.code == 50035)
            #expect(error.withUnsafePayload { $0 != nil })
            #expect(!String(reflecting: error).contains("private-evidence"))
        } catch let error as DiscordError {
            #expect(status == 500 && endpoint.retrySafety == .unsafe)
            #expect(error == .unknownMutationOutcome(.serverErrorAfterSubmission))
        }
        #expect(await transport.executionCount == 1)
        #expect(await coordinator.snapshot().activeCount == 0)
        #expect(await coordinator.snapshot().orderedOperationsCount == 0)
        #expect(clock.pendingSleepCount == 0)
        await coordinator.close()
    }

    /// A task cancelled before execution sends no request and leaves no admission, ordering or timer ownership.
    /// - Parameter index: Every descriptor in the finite current Guild catalog.
    /// - Throws: Unexpected fixture construction or HTTP execution errors fail the test; expected API, transport and cancellation failures are asserted locally.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: 0..<45) func cancelledBeforeSend(index: Int) async throws {
        let endpoint = try GuildEndpointTests.catalog()[index].0
        let transport = try ScriptedHTTPTransport(steps: [])
        let clock = ManualClock()
        let coordinator = RateLimitCoordinator(clock: clock)
        let client = RESTClient(credential: .bot(try BotToken("synthetic")), identity: RateLimitIdentity(), transport: transport,
            coordinator: coordinator, clock: clock)
        let task = Task { withUnsafeCurrentTask { $0?.cancel() }; return try await client.execute(endpoint) }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await transport.executionCount == 0)
        #expect(await coordinator.snapshot().activeCount == 0)
        #expect(await coordinator.snapshot().orderedOperationsCount == 0)
        #expect(clock.pendingSleepCount == 0)
        await coordinator.close()
    }

    /// Every operation rejects missing or bearer-only outer credentials before contacting the transport.
    /// - Parameter index: Catalog operation; bot-only descriptors reject bearer-only credentials.
    /// - Throws: Unexpected fixture construction or HTTP execution errors fail the test; expected API, transport and cancellation failures are asserted locally.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: 0..<45) func authenticationMismatch(index: Int) async throws {
        let endpoint = try GuildEndpointTests.catalog()[index].0
        let transport = try ScriptedHTTPTransport(steps: [])
        let clock = ManualClock()
        let coordinator = RateLimitCoordinator(clock: clock)
        let credentials: [Credential] = endpoint.authentication == .none ? [] :
            (endpoint.authentication == .botOrBearer ? [.none] : [.none, .bearer(try BearerToken("synthetic-bearer"))])
        for credential in credentials {
            let client = RESTClient(credential: credential, identity: RateLimitIdentity(), transport: transport,
                coordinator: coordinator, clock: clock)
            await #expect(throws: DiscordError.validation(.missingValue)) { try await client.execute(endpoint) }
        }
        #expect(await transport.executionCount == 0)
        #expect(await coordinator.snapshot().activeCount == 0)
        #expect(await coordinator.snapshot().orderedOperationsCount == 0)
        await coordinator.close()
    }

    /// Failing exchanges do not retry ambiguous mutations; safe reads retain their transport failure category.
    /// - Parameter index: Complete catalog position, each using a one-attempt budget.
    /// - Throws: Unexpected fixture construction or HTTP execution errors fail the test; expected API, transport and cancellation failures are asserted locally.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: 0..<45) func transportFailure(index: Int) async throws {
        let endpoint = try GuildEndpointTests.catalog()[index].0
        let transport = try ScriptedHTTPTransport(steps: [{ _ in throw TransportFailure.closed }])
        let clock = ManualClock()
        let coordinator = RateLimitCoordinator(clock: clock)
        let client = RESTClient(credential: .bot(try BotToken("synthetic")), identity: RateLimitIdentity(), transport: transport,
            coordinator: coordinator, clock: clock, retryPolicy: .init(maximumAttempts: 1))
        do { _ = try await client.execute(endpoint); Issue.record("Expected transport failure") }
        catch let error as DiscordError {
            if endpoint.retrySafety == .unsafe { #expect(error == .unknownMutationOutcome(.connectionLostAfterSubmission)) }
            else { #expect(error == .transport(.connectionFailed)) }
        }
        #expect(await transport.executionCount == 1)
        #expect(await coordinator.snapshot().activeCount == 0)
        #expect(await coordinator.snapshot().orderedOperationsCount == 0)
        await coordinator.close()
    }

    /// New-member success preserves 201 member versus 204 already-present results, with the OAuth grant only in JSON.
    /// - Parameter status: Both documented success alternatives are exercised through the real policy pipeline.
    /// - Throws: Unexpected payload, fixture or client execution failures fail the test.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [201, 204]) func memberJoinSuccessShapes(status: Int) async throws {
        let endpoint = try GuildEndpoints.addMember(guildID: .init(rawValue: 1), userID: .init(rawValue: UInt64.max),
            request: GuildMemberAdd(accessToken: "user-grant", nick: .value("nickname")))
        let transport = try ScriptedHTTPTransport(steps: [{ request in
            #expect(request.headers.contains { $0.name == "Authorization" && $0.value == "Bot synthetic" })
            #expect(!request.url.absoluteString.contains("user-grant"))
            let bytes = try await ResponseBody.collect(request.body, maximumBytes: 1_048_576)
            #expect(try JSONValue.parse(bytes) == .object(["access_token": .string("user-grant"), "nick": .string("nickname")]))
            return try Self.response(status == 201 ? Data(GuildEndpointTests.memberJSON.utf8) : Data(), status: status)
        }])
        let clock = ManualClock()
        let coordinator = RateLimitCoordinator(clock: clock)
        let client = RESTClient(credential: .bot(try BotToken("synthetic")), identity: RateLimitIdentity(), transport: transport,
            coordinator: coordinator, clock: clock)
        let member = try await client.execute(endpoint)
        #expect((member != nil) == (status == 201))
        #expect(await transport.executionCount == 1)
        #expect(await coordinator.snapshot().activeCount == 0)
        await coordinator.close()
    }

    /// Guild role/membership changes invalidate message and channel visibility snapshots only within their identity.
    /// - Throws: Unexpected descriptor, fixture or HTTP execution failures fail the test.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func visibilityInvalidation() async throws {
        let clock = ManualClock()
        let cache = ReadCache(clock: clock)
        let coordinator = RateLimitCoordinator(clock: clock)
        let channel = Data(#"{"id":"7","type":0}"#.utf8)
        let message = MessageEndpointTests.messageData()
        let transport = try ScriptedHTTPTransport(steps: [
            { _ in try Self.response(channel) }, { _ in try Self.response(message) },
            { _ in try Self.response(message) }, { _ in HTTPResponse(status: 204) },
            { _ in try Self.response(channel) }, { _ in try Self.response(message) }
        ])
        let first = RESTClient(credential: .bot(try BotToken("synthetic")), identity: RateLimitIdentity(), transport: transport,
            coordinator: coordinator, clock: clock, cache: cache)
        let second = RESTClient(credential: .bot(try BotToken("foreign")), identity: RateLimitIdentity(), transport: transport,
            coordinator: coordinator, clock: clock, cache: cache)
        let channelRead = try ChannelEndpoints.get(channelID: .init(rawValue: 7), readPolicy: .init(timeToLive: .seconds(60)))
        let messageRead = try MessageEndpoints.get(channelID: .init(rawValue: 7), messageID: .init(rawValue: 8), readPolicy: .init(timeToLive: .seconds(60)))
        #expect(messageRead.readPolicy?.tags.contains("message-catalog") == true)
        _ = try await first.execute(channelRead)
        _ = try await first.execute(messageRead)
        _ = try await second.execute(messageRead)
        #expect(await cache.snapshot().entries == 3)
        _ = try await first.execute(GuildEndpoints.addMemberRole(guildID: .init(rawValue: 1), userID: .init(rawValue: 2), roleID: .init(rawValue: 3)))
        #expect(await cache.snapshot().entries == 1)
        try clock.advance(by: .seconds(1))
        _ = try await first.execute(channelRead)
        _ = try await first.execute(messageRead)
        _ = try await second.execute(messageRead)
        #expect(await transport.executionCount == 6)
        #expect(await cache.snapshot().entries == 3)
        #expect(await coordinator.snapshot().activeCount == 0)
        await coordinator.close()
    }

    /// Every descriptor releases body/admission ownership when cancelled during a suspended exchange.
    /// - Parameter index: All 45 operations, including binary and credential-free public reads.
    /// - Throws: Unexpected configuration errors fail the test; cancellation categories are asserted.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: 0..<45) func cancellationDuringExchange(index: Int) async throws {
        let endpoint = try GuildEndpointTests.catalog()[index].0
        let entered = TestBarrier(), gate = TestBarrier(), clock = ManualClock()
        let coordinator = RateLimitCoordinator(clock: clock)
        let transport = try ScriptedHTTPTransport(steps: [{ request in
            await request.body?.close()
            entered.open()
            try await gate.wait()
            return HTTPResponse(status: 204)
        }])
        let client = RESTClient(credential: .bot(try BotToken("synthetic")), identity: RateLimitIdentity(), transport: transport,
            coordinator: coordinator, clock: clock)
        let task = Task { try await client.execute(endpoint) }
        try await entered.wait()
        task.cancel()
        do { _ = try await task.value; Issue.record("Expected cancellation") }
        catch let error as DiscordError {
            #expect(endpoint.retrySafety == .unsafe)
            #expect(error == .unknownMutationOutcome(.cancelledAfterSubmission))
        } catch is CancellationError { #expect(endpoint.retrySafety == .safe) }
        #expect(await transport.executionCount == 1)
        #expect(await coordinator.snapshot().activeCount == 0)
        #expect(await coordinator.snapshot().orderedOperationsCount == 0)
        #expect(clock.pendingSleepCount == 0)
        await coordinator.close()
    }

    /// Equivalent member reads coalesce without spawning profile hydration or extra guild requests.
    /// - Throws: Unexpected fixture or client failures fail the test.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func membersCoalesce() async throws {
        let gate = TestBarrier(), clock = ManualClock(), coalescer = RequestCoalescer()
        let coordinator = RateLimitCoordinator(clock: clock)
        let transport = try ScriptedHTTPTransport(steps: [{ _ in
            try await gate.wait()
            return try Self.response(Data(GuildEndpointTests.memberJSON.utf8))
        }])
        let client = RESTClient(credential: .bot(try BotToken("synthetic")), identity: RateLimitIdentity(), transport: transport,
            coordinator: coordinator, clock: clock, coalescer: coalescer)
        let endpoint = try GuildEndpoints.member(guildID: .init(rawValue: 1), userID: .init(rawValue: UInt64.max))
        let tasks = (0..<20).map { _ in Task { try await client.execute(endpoint) } }
        while await coalescer.snapshot().waiters < 20 { try Task.checkCancellation(); await Task.yield() }
        gate.open()
        for task in tasks { #expect(try await task.value.rawFields["user"] != nil) }
        #expect(await transport.executionCount == 1)
        #expect(await coalescer.snapshot().flights == 0)
        #expect(await coordinator.snapshot().activeCount == 0)
        await coalescer.close()
        await coordinator.close()
    }

    /// Supplies one bounded complete response stream without credentials, sockets or external state.
    /// - Parameters:
    ///   - bytes: Complete success/error fixture; empty bytes create an absent body.
    ///   - status: Explicit HTTP status, default 200.
    /// - Returns: One locally owned scripted response, consumed or closed by the REST client.
    /// - Throws: Local body validation errors for an oversized fixture.
    static func response(_ bytes: Data, status: Int = 200) throws -> HTTPResponse {
        HTTPResponse(status: status, body: bytes.isEmpty ? nil : try RequestBody(bytes: bytes, contentType: "application/json").makeStream())
    }
}
