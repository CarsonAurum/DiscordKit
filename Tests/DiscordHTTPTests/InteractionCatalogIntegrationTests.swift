import DiscordCore
import DiscordModels
import DiscordTestSupport
import DiscordTransport
import Foundation
import Testing
@testable import DiscordHTTP

/// Executes every interaction-response descriptor through injected HTTP admission, retry and response validation.
/// Fixtures and synchronization are deterministic; no live Discord requests, real credentials or sleeps occur.
@Suite(.timeLimit(.minutes(1))) struct InteractionCatalogIntegrationTests {
    /// Every descriptor transmits exactly once with the path token, no Authorization and its validated body.
    /// The callback's 200/204 result distinction and every original/follow-up Message decoder remain in the pipeline.
    /// - Parameter index: All nine public descriptors representing eight documented operations.
    /// - Throws: Unexpected descriptor/body/transport/response failures fail the test.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: 0..<9) func successfulExchanges(index: Int) async throws {
        let (endpoint, bytes) = try InteractionEndpointTests.catalog()[index]
        let status = try #require(endpoint.successStatuses.first)
        let transport = try ScriptedHTTPTransport(steps: [{ request in
            #expect(request.method == endpoint.method)
            #expect(request.url.host == "discord.com")
            #expect(request.url.path == "/api/v10/" + endpoint.path.joined(separator: "/"))
            #expect(!request.headers.contains { $0.name.lowercased() == "authorization" })
            let sent = try await ResponseBody.collect(request.body, maximumBytes: 1_048_576)
            #expect(sent == (endpoint.body?.bytes ?? Data()))
            #expect(URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems?.count ?? 0 == endpoint.query.count)
            return try Self.response(bytes, status: status)
        }])
        let clock = ManualClock(), coordinator = RateLimitCoordinator(clock: clock)
        let client = RESTClient(credential: .interaction(try InteractionEndpointTests.token()), identity: RateLimitIdentity(),
            transport: transport, coordinator: coordinator, clock: clock, retryPolicy: .init(maximumAttempts: 1))
        #expect(try await client.execute(endpoint) == bytes)
        #expect(await transport.executionCount == 1)
        #expect(await coordinator.snapshot().activeCount == 0)
        #expect(await coordinator.snapshot().orderedOperationsCount == 0)
        #expect(clock.pendingSleepCount == 0)
        await coordinator.close()
    }

    /// Missing or mismatched continuation credentials are rejected before any request, admission or timer exists.
    /// A matching token carried as a different credential category is still not an interaction credential.
    /// - Parameter index: Every descriptor, including eligible original/follow-up reads.
    /// - Throws: Unexpected fixture/setup failures fail the test; missing-value validation is explicitly asserted.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: 0..<9) func pathAuthenticationBeforeAdmission(index: Int) async throws {
        let endpoint = try InteractionEndpointTests.catalog()[index].0
        let transport = try ScriptedHTTPTransport(steps: [])
        let clock = ManualClock(), coordinator = RateLimitCoordinator(clock: clock)
        for credential in [Credential.none, .bot(try BotToken("bot")), .interaction(try InteractionToken("wrong"))] {
            let client = RESTClient(credential: credential, identity: RateLimitIdentity(), transport: transport,
                coordinator: coordinator, clock: clock)
            await #expect(throws: DiscordError.validation(.missingValue)) { try await client.execute(endpoint) }
        }
        #expect(await transport.executionCount == 0)
        #expect(await coordinator.snapshot().activeCount == 0)
        #expect(await coordinator.snapshot().orderedOperationsCount == 0)
        #expect(clock.pendingSleepCount == 0)
        await coordinator.close()
    }

    /// Every operation rejects malformed success bodies using its original typed model or strict empty decoder.
    /// - Parameter index: Every callback/original/follow-up descriptor.
    /// - Throws: Unexpected setup errors fail the test; safe invalid-response errors are asserted.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: 0..<9) func malformedSuccess(index: Int) async throws {
        let endpoint = try InteractionEndpointTests.catalog()[index].0
        for json in ["null", "{}", "[{}]"] {
            let transport = try ScriptedHTTPTransport(steps: [{ request in
                await request.body?.close()
                return try Self.response(Data(json.utf8), status: endpoint.successStatuses.first!)
            }])
            let clock = ManualClock(), coordinator = RateLimitCoordinator(clock: clock)
            let client = RESTClient(credential: .interaction(try InteractionEndpointTests.token()), identity: RateLimitIdentity(),
                transport: transport, coordinator: coordinator, clock: clock, retryPolicy: .init(maximumAttempts: 1))
            await #expect(throws: DiscordError.transport(.invalidResponse)) { try await client.execute(endpoint) }
            #expect(await transport.executionCount == 1)
            #expect(await coordinator.snapshot().activeCount == 0)
            #expect(await coordinator.snapshot().orderedOperationsCount == 0)
            #expect(clock.pendingSleepCount == 0)
            await coordinator.close()
        }
    }

    /// Validation/auth/permission/expiry/rate failures retain safe API evidence, while unsafe server errors stay indeterminate.
    /// Errors conceal server-provided descriptions and tokens in ordinary diagnostics.
    /// - Parameters:
    ///   - index: Every interaction operation.
    ///   - status: Scripted API rejection or server failure with a single-attempt retry budget.
    /// - Throws: Unexpected setup failures fail the test; precise safe/unsafe error categories are asserted.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: 0..<9, [400, 401, 403, 404, 429, 500])
    func apiFailures(index: Int, status: Int) async throws {
        let endpoint = try InteractionEndpointTests.catalog()[index].0
        let transport = try ScriptedHTTPTransport(steps: [{ request in
            await request.body?.close()
            return try Self.response(Data(#"{"code":10062,"message":"private-interaction-error"}"#.utf8), status: status)
        }])
        let clock = ManualClock(), coordinator = RateLimitCoordinator(clock: clock)
        let client = RESTClient(credential: .interaction(try InteractionEndpointTests.token()), identity: RateLimitIdentity(),
            transport: transport, coordinator: coordinator, clock: clock, retryPolicy: .init(maximumAttempts: 1))
        do { _ = try await client.execute(endpoint); Issue.record("Expected API failure") }
        catch let error as APIResponseError {
            #expect(status < 500 || endpoint.retrySafety == .safe)
            #expect(error.status == status)
            #expect(error.code == 10062)
            #expect(!String(reflecting: error).contains("private-interaction-error"))
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

    /// Explicit rejected 429 responses permit one bounded replay; request content and the same path token survive unchanged.
    /// Exhaustion returns the rejection rather than inventing a successful callback or uncertain mutation outcome.
    /// - Parameters:
    ///   - index: Every read/mutation descriptor.
    ///   - rejectAgain: True rejects both attempts; false returns the typed success on the second attempt.
    /// - Throws: Unexpected setup/clock/body failures fail the test; exhausted rejections are asserted explicitly.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: 0..<9, [false, true])
    func rejectedRateLimitReplay(index: Int, rejectAgain: Bool) async throws {
        let (endpoint, bytes) = try InteractionEndpointTests.catalog()[index]
        let rejected = Data(#"{"code":0,"message":"rate limited","retry_after":0.25,"global":false}"#.utf8)
        let step: ScriptedHTTPTransport.Step = { request in
            #expect(try await ResponseBody.collect(request.body, maximumBytes: 1_048_576) == (endpoint.body?.bytes ?? Data()))
            return try Self.response(rejected, status: 429)
        }
        let second: ScriptedHTTPTransport.Step = { request in
            #expect(request.url.path == "/api/v10/" + endpoint.path.joined(separator: "/"))
            #expect(!request.headers.contains { $0.name.lowercased() == "authorization" })
            #expect(try await ResponseBody.collect(request.body, maximumBytes: 1_048_576) == (endpoint.body?.bytes ?? Data()))
            return try Self.response(rejectAgain ? rejected : bytes, status: rejectAgain ? 429 : endpoint.successStatuses.first!)
        }
        let transport = try ScriptedHTTPTransport(steps: [step, second])
        let clock = ManualClock(), coordinator = RateLimitCoordinator(clock: clock)
        let client = RESTClient(credential: .interaction(try InteractionEndpointTests.token()), identity: RateLimitIdentity(),
            transport: transport, coordinator: coordinator, clock: clock, retryPolicy: .init(maximumAttempts: 2))
        let task = Task { try await client.execute(endpoint) }
        while true {
            let calls = await transport.executionCount, state = await coordinator.snapshot()
            if calls == 1 && state.activeCount == 0 && state.queuedCount == 1 { break }
            try Task.checkCancellation(); await Task.yield()
        }
        try clock.advance(by: .milliseconds(249))
        #expect(await transport.executionCount == 1)
        try clock.advance(by: .seconds(1))
        if rejectAgain {
            do { _ = try await task.value; Issue.record("Expected exhausted rejection") }
            catch let error as APIResponseError { #expect(error.status == 429) }
        } else { #expect(try await task.value == bytes) }
        #expect(await transport.executionCount == 2)
        #expect(await coordinator.snapshot().activeCount == 0)
        #expect(await coordinator.snapshot().queuedCount == 0)
        #expect(await coordinator.snapshot().orderedOperationsCount == 0)
        #expect(clock.pendingSleepCount == 0)
        await coordinator.close()
    }

    /// Transport loss preserves ordinary read failures and indeterminate mutation outcomes without replaying submissions.
    /// - Parameter index: Every descriptor, including initial acknowledgements and message deletion.
    /// - Throws: Unexpected setup failures fail the test; exact failure categories are asserted.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: 0..<9) func transportLoss(index: Int) async throws {
        let endpoint = try InteractionEndpointTests.catalog()[index].0
        let transport = try ScriptedHTTPTransport(steps: [{ _ in throw TransportFailure.closed }])
        let clock = ManualClock(), coordinator = RateLimitCoordinator(clock: clock)
        let client = RESTClient(credential: .interaction(try InteractionEndpointTests.token()), identity: RateLimitIdentity(),
            transport: transport, coordinator: coordinator, clock: clock, retryPolicy: .init(maximumAttempts: 1))
        do { _ = try await client.execute(endpoint); Issue.record("Expected transport failure") }
        catch let error as DiscordError {
            #expect(error == (endpoint.retrySafety == .safe ? .transport(.connectionFailed) : .unknownMutationOutcome(.connectionLostAfterSubmission)))
        }
        #expect(await transport.executionCount == 1)
        #expect(await coordinator.snapshot().activeCount == 0)
        #expect(await coordinator.snapshot().orderedOperationsCount == 0)
        #expect(clock.pendingSleepCount == 0)
        await coordinator.close()
    }

    /// Cancellation before work sends nothing; cancellation during a synchronized exchange releases all owners.
    /// Submitted writes remain indeterminate while reads propagate cooperative cancellation normally.
    /// - Parameters:
    ///   - index: Every descriptor.
    ///   - duringExchange: True cancels after the transport-entry barrier, false before execute starts.
    /// - Throws: Unexpected setup failures fail the test; appropriate cancellation outcomes are explicitly asserted.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: 0..<9, [false, true])
    func cancellation(index: Int, duringExchange: Bool) async throws {
        let endpoint = try InteractionEndpointTests.catalog()[index].0
        let entered = TestBarrier(), gate = TestBarrier(), clock = ManualClock()
        let coordinator = RateLimitCoordinator(clock: clock)
        let transport = try ScriptedHTTPTransport(steps: [{ request in
            await request.body?.close(); entered.open()
            try await gate.wait()
            return HTTPResponse(status: 204)
        }])
        let client = RESTClient(credential: .interaction(try InteractionEndpointTests.token()), identity: RateLimitIdentity(),
            transport: transport, coordinator: coordinator, clock: clock)
        let task = Task {
            if !duringExchange { withUnsafeCurrentTask { $0?.cancel() } }
            return try await client.execute(endpoint)
        }
        if duringExchange { try await entered.wait(); task.cancel() }
        do { _ = try await task.value; Issue.record("Expected cancellation") }
        catch let error as DiscordError {
            #expect(duringExchange && endpoint.retrySafety == .unsafe)
            #expect(error == .unknownMutationOutcome(.cancelledAfterSubmission))
        } catch is CancellationError { #expect(!duringExchange || endpoint.retrySafety == .safe) }
        #expect(gate.waitingCount == 0)
        #expect(await transport.executionCount == (duringExchange ? 1 : 0))
        #expect(await coordinator.snapshot().activeCount == 0)
        #expect(await coordinator.snapshot().orderedOperationsCount == 0)
        #expect(clock.pendingSleepCount == 0)
        await coordinator.close()
    }

    /// Equivalent token-scoped reads coalesce for concurrent clients while a different token/identity has its own exchange.
    /// Twenty registered subscribers use exactly two bounded exchanges, with all flight/admission ownership released.
    /// - Parameter original: True selects the original read; false selects a follow-up read.
    /// - Throws: Unexpected descriptor/synchronization/response errors fail the test.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [false, true]) func readsCoalesceByTokenIdentity(original: Bool) async throws {
        let app = ApplicationID(rawValue: 2), token = try InteractionEndpointTests.token(), other = try InteractionToken("other-token")
        let endpoint = try InteractionEndpointTests.erase(original ?
            InteractionEndpoints.getOriginalResponse(applicationID: app, token: token) :
            InteractionEndpoints.getFollowup(applicationID: app, token: token, messageID: .init(rawValue: 3)))
        let foreignEndpoint = try InteractionEndpointTests.erase(original ?
            InteractionEndpoints.getOriginalResponse(applicationID: app, token: other) :
            InteractionEndpoints.getFollowup(applicationID: app, token: other, messageID: .init(rawValue: 3)))
        let bytes = Data(InteractionEndpointTests.messageJSON.utf8)
        let gate = TestBarrier(), clock = ManualClock(), coalescer = RequestCoalescer()
        let coordinator = RateLimitCoordinator(clock: clock), identity = RateLimitIdentity()
        let step: ScriptedHTTPTransport.Step = { _ in try await gate.wait(); return try Self.response(bytes, status: 200) }
        let transport = try ScriptedHTTPTransport(steps: [step, step])
        let first = RESTClient(credential: .interaction(token), identity: identity, transport: transport,
            coordinator: coordinator, clock: clock, coalescer: coalescer)
        let same = RESTClient(credential: .interaction(token), identity: identity, transport: transport,
            coordinator: coordinator, clock: clock, coalescer: coalescer)
        let foreign = RESTClient(credential: .interaction(other), identity: RateLimitIdentity(), transport: transport,
            coordinator: coordinator, clock: clock, coalescer: coalescer)
        let tasks = (0..<20).map { number in
            Task { try await (number < 6 ? first : number < 12 ? same : foreign).execute(number < 12 ? endpoint : foreignEndpoint) }
        }
        while await coalescer.snapshot().waiters < 20 { try Task.checkCancellation(); await Task.yield() }
        #expect(await coalescer.snapshot().flights == 2)
        gate.open()
        for task in tasks { #expect(try await task.value == bytes) }
        #expect(await transport.executionCount == 2)
        #expect(await coalescer.snapshot().flights == 0)
        #expect(await coalescer.snapshot().waiters == 0)
        #expect(await coordinator.snapshot().activeCount == 0)
        #expect(clock.pendingSleepCount == 0)
        await coalescer.close(); await coordinator.close()
    }

    /// Constructs one finite scripted response with an owned body stream and explicit status.
    /// - Parameters:
    ///   - bytes: Exact complete response bytes, including empty 204 success.
    ///   - status: Scripted HTTP result status; no semantic success inference occurs here.
    /// - Returns: Independently owned response body, closed by the production HTTP policy.
    /// - Throws: BodyStream validation errors if the finite fixture violates stream bounds.
    static func response(_ bytes: Data, status: Int) throws -> HTTPResponse {
        HTTPResponse(status: status, headers: [.init(name: "X-RateLimit-Limit", value: "100"),
            .init(name: "X-RateLimit-Remaining", value: "99"), .init(name: "X-RateLimit-Reset-After", value: "1")],
            body: bytes.isEmpty ? nil : try RequestBody(bytes: bytes, contentType: "application/json").makeStream())
    }
}
