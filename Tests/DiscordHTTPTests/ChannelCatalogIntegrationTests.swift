// File: Tests/DiscordHTTPTests/ChannelCatalogIntegrationTests.swift
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

/// Exercises every channel-reference operation and the active-guild-thread route through real HTTP policy.
@Suite(.timeLimit(.minutes(1))) struct ChannelCatalogIntegrationTests {
    /// Each descriptor sends one authenticated API v10 request and decodes its realistic success fixture.
    /// - Parameter index: Stable operation position across all 24 channel headings and active guild threads.
    /// - Throws: Unexpected fixture construction or HTTP execution errors fail the test; expected API, transport and cancellation failures are asserted locally.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: 0..<25) func success(index: Int) async throws {
        let (endpoint, bytes) = try ChannelEndpointTests.catalog()[index]
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
        #expect(clock.pendingSleepCount == 0)
        await coordinator.close()
    }

    /// Auth, permissions, validation, missing resources and rejected rate requests retain safe API evidence.
    /// - Parameters:
    ///   - index: Every public operation, including the distinct forum-thread descriptor.
    ///   - status: Scripted API failure; unsafe 5xx submissions preserve indeterminate mutation outcomes.
    /// - Throws: Unexpected fixture construction or HTTP execution errors fail the test; expected API, transport and cancellation failures are asserted locally.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: 0..<25, [400, 401, 403, 404, 429, 500])
    func failures(index: Int, status: Int) async throws {
        let endpoint = try ChannelEndpointTests.catalog()[index].0
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
    /// - Parameter index: Every descriptor in the finite current channel catalog.
    /// - Throws: Unexpected fixture construction or HTTP execution errors fail the test; expected API, transport and cancellation failures are asserted locally.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: 0..<25) func cancelledBeforeSend(index: Int) async throws {
        let endpoint = try ChannelEndpointTests.catalog()[index].0
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
    /// - Parameter index: Catalog operation; recipient OAuth tokens remain request-body data rather than outer auth.
    /// - Throws: Unexpected fixture construction or HTTP execution errors fail the test; expected API, transport and cancellation failures are asserted locally.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: 0..<25) func authenticationMismatch(index: Int) async throws {
        let endpoint = try ChannelEndpointTests.catalog()[index].0
        let transport = try ScriptedHTTPTransport(steps: [])
        let clock = ManualClock()
        let coordinator = RateLimitCoordinator(clock: clock)
        for credential in [Credential.none, .bearer(try BearerToken("synthetic-bearer"))] {
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
    @Test(arguments: 0..<25) func transportFailure(index: Int) async throws {
        let endpoint = try ChannelEndpointTests.catalog()[index].0
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

    /// Group-DM recipient addition accepts its documented specification alternatives and rejects malformed snapshots.
    /// - Parameter status: HTTP 201 carries the resulting group channel; HTTP 204 returns no snapshot.
    /// - Throws: Unexpected fixture construction or HTTP execution errors fail the test; expected API, transport and cancellation failures are asserted locally.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [201, 204]) func recipientSuccessShapes(status: Int) async throws {
        let endpoint = try ChannelEndpoints.addRecipient(channelID: .init(rawValue: UInt64.max), userID: .init(rawValue: UInt64.max),
            request: GroupDMRecipientAdd(accessToken: "recipient-secret", nick: "recipient"))
        let channel = Data("{\"id\":\"18446744073709551615\",\"type\":3}".utf8)
        #expect(endpoint.successStatuses == [201, 204])
        #expect(try endpoint.decode(Data()) == nil)
        #expect(try endpoint.decode(channel)?.id.rawValue == UInt64.max)
        for malformed in ["null", "{}", "[]", "{\"id\":\"bad\",\"type\":3}"] {
            #expect(throws: (any Error).self) { try endpoint.decode(Data(malformed.utf8)) }
        }
        let transport = try ScriptedHTTPTransport(steps: [{ request in
            #expect(request.headers.contains { $0.name == "Authorization" && $0.value == "Bot outer-secret" })
            let body = try await ResponseBody.collect(request.body, maximumBytes: 1_048_576)
            #expect(try JSONValue.parse(body) == .object(["access_token": .string("recipient-secret"), "nick": .string("recipient")]))
            return try Self.response(status == 201 ? channel : Data(), status: status)
        }])
        let clock = ManualClock()
        let coordinator = RateLimitCoordinator(clock: clock)
        let client = RESTClient(credential: .bot(try BotToken("outer-secret")), identity: RateLimitIdentity(), transport: transport,
            coordinator: coordinator, clock: clock)
        let result = try await client.execute(endpoint)
        #expect(result?.id.rawValue == (status == 201 ? UInt64.max : nil))
        #expect(await transport.executionCount == 1)
        #expect(await coordinator.snapshot().activeCount == 0)
        #expect(await coordinator.snapshot().orderedOperationsCount == 0)
        await coordinator.close()
    }

    /// A local write invalidates other channel/active-thread reads within its identity while foreign caches stay intact.
    /// - Throws: Unexpected fixture construction or HTTP execution errors fail the test; expected API, transport and cancellation failures are asserted locally.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func authenticationScopedCatalogInvalidation() async throws {
        let clock = ManualClock()
        let coordinator = RateLimitCoordinator(clock: clock), cache = ReadCache(clock: clock)
        let initial = Data(ChannelEndpointTests.channelJSON.utf8)
        let changed = Data("{\"id\":\"18446744073709551615\",\"type\":0,\"name\":\"updated\"}".utf8)
        let transport = try ScriptedHTTPTransport(steps: [
            { _ in try Self.response(initial) }, { _ in try Self.response(initial) },
            { _ in HTTPResponse(status: 204) }, { _ in try Self.response(changed) }
        ])
        let first = RESTClient(credential: .bot(try BotToken("synthetic")), identity: RateLimitIdentity(), transport: transport,
            coordinator: coordinator, clock: clock, cache: cache)
        let second = RESTClient(credential: .bot(try BotToken("foreign")), identity: RateLimitIdentity(), transport: transport,
            coordinator: coordinator, clock: clock, cache: cache)
        let endpoint = try ChannelEndpoints.get(channelID: .init(rawValue: UInt64.max), readPolicy: .init(timeToLive: .seconds(10)))
        #expect(try await first.execute(endpoint).name == .absent)
        #expect(try await first.execute(endpoint).name == .absent)
        #expect(await transport.executionCount == 1)
        #expect(try await second.execute(endpoint).name == .absent)
        #expect(await cache.snapshot().entries == 2)
        _ = try await first.execute(ChannelEndpoints.joinThread(channelID: .init(rawValue: 2)))
        #expect(await cache.snapshot().entries == 1)
        // No server rate headers are scripted; allow the conservative one-second discovery window to reset.
        try clock.advance(by: .seconds(1))
        #expect(try await first.execute(endpoint).name == .value("updated"))
        #expect(try await second.execute(endpoint).name == .absent)
        #expect(await transport.executionCount == 4)
        #expect(await coordinator.snapshot().activeCount == 0)
        await coordinator.close()
    }

    /// Equivalent concurrent channel reads share one exchange without requesting related resources.
    /// - Throws: Unexpected fixture construction or HTTP execution errors fail the test; expected API, transport and cancellation failures are asserted locally.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func equivalentReadsCoalesce() async throws {
        let gate = TestBarrier(), clock = ManualClock(), coalescer = RequestCoalescer()
        let coordinator = RateLimitCoordinator(clock: clock)
        let transport = try ScriptedHTTPTransport(steps: [{ _ in
            try await gate.wait()
            return try Self.response(Data(ChannelEndpointTests.channelJSON.utf8))
        }])
        let client = RESTClient(credential: .bot(try BotToken("synthetic")), identity: RateLimitIdentity(), transport: transport,
            coordinator: coordinator, clock: clock, coalescer: coalescer)
        let endpoint = try ChannelEndpoints.get(channelID: .init(rawValue: UInt64.max))
        let tasks = (0..<20).map { _ in Task { try await client.execute(endpoint) } }
        while await coalescer.snapshot().waiters < 20 { try Task.checkCancellation(); await Task.yield() }
        while gate.waitingCount == 0 { try Task.checkCancellation(); await Task.yield() }
        #expect(await transport.executionCount == 1)
        gate.open()
        for task in tasks { #expect(try await task.value.id.rawValue == UInt64.max) }
        #expect(await coalescer.snapshot().flights == 0)
        #expect(await coordinator.snapshot().activeCount == 0)
        #expect(clock.pendingSleepCount == 0)
        await coalescer.close()
        await coordinator.close()
    }

    /// Forum multipart sources close exactly once on success, producer failure and cancellation during a pull.
    /// - Parameter mode: Zero completes, one fails in the source, and two cancels while the source is suspended.
    /// - Throws: Unexpected fixture construction or HTTP execution errors fail the test; expected API, transport and cancellation failures are asserted locally.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [0, 1, 2]) func forumUploadOwnership(mode: Int) async throws {
        let entered = TestBarrier(), gate = TestBarrier(), clock = ManualClock()
        let coordinator = RateLimitCoordinator(clock: clock)
        let source = ChannelUploadSource(mode: mode, entered: entered, gate: gate)
        let file = try MessageUploadFile(id: 0, filename: "post.bin", maximumBytes: 3) {
            try BodyStream(maximumChunkBytes: 3, next: { try await source.next() }, close: { await source.close() })
        }
        let request = try ForumThreadStart(name: "post", message: MessageCreate(content: .value("hello")))
        let endpoint = try ChannelEndpoints.startForumThread(channelID: .init(rawValue: 1), request: request, files: [file])
        #expect(await source.reads == 0)
        #expect(endpoint.body?.isStreaming == true)
        let transport = try ScriptedHTTPTransport(steps: [{ request in
            #expect(request.headers.contains { $0.name == "Content-Type" && $0.value.hasPrefix("multipart/form-data; boundary=") })
            let bytes = try await ResponseBody.collect(request.body, maximumBytes: 1_048_576)
            #expect(String(decoding: bytes, as: UTF8.self).contains("name=\"files[0]\""))
            return try Self.response(Data(ChannelEndpointTests.channelJSON.utf8), status: 201)
        }])
        let client = RESTClient(credential: .bot(try BotToken("synthetic")), identity: RateLimitIdentity(), transport: transport,
            coordinator: coordinator, clock: clock, retryPolicy: .init(maximumAttempts: 1))
        let task = Task { try await client.execute(endpoint) }
        if mode == 2 { try await entered.wait(); task.cancel() }
        if mode == 0 { #expect(try await task.value.id.rawValue == UInt64.max) }
        else {
            await #expect(throws: DiscordError.unknownMutationOutcome(mode == 2 ? .cancelledAfterSubmission : .connectionLostAfterSubmission)) { try await task.value }
        }
        #expect(await source.reads >= 1)
        #expect(await source.closes == 1)
        #expect(await transport.executionCount == 1)
        #expect(await coordinator.snapshot().activeCount == 0)
        #expect(await coordinator.snapshot().orderedOperationsCount == 0)
        #expect(clock.pendingSleepCount == 0)
        await coordinator.close()
    }

    /// Builds one independently owned JSON response stream; 204-style empty bodies remain absent.
    /// - Parameters:
    ///   - bytes: Complete finite fixture bytes, including intentionally malformed responses.
    ///   - status: Exact scripted HTTP status, default successful 200.
    /// - Returns: A response owned by the caller until execution collects and closes its body.
    /// - Throws: Request-body validation failures, indicating invalid test fixture setup.
    static func response(_ bytes: Data, status: Int = 200) throws -> HTTPResponse {
        HTTPResponse(status: status, body: bytes.isEmpty ? nil : try RequestBody(bytes: bytes, contentType: "application/json").makeStream())
    }
}

/// Isolated finite multipart source exposes demand and cleanup without wall-clock waits.
@available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
private actor ChannelUploadSource {
    let mode: Int
    let entered: TestBarrier
    let gate: TestBarrier
    var reads = 0
    var closes = 0

    /// Configures one test-owned source with completion, failure or cooperative suspended consumption.
    /// - Parameters:
    ///   - mode: Zero emits three bytes then EOF; one throws; two awaits cancellation at its first pull.
    ///   - entered: Opens when a pull starts, allowing deterministic cancellation after ownership transfers.
    ///   - gate: Suspension barrier released by cancellation or cleanup.
    init(mode: Int, entered: TestBarrier, gate: TestBarrier) { self.mode = mode; self.entered = entered; self.gate = gate }

    /// Records demand and executes the finite source script; cancellation is observed at its suspended barrier.
    /// - Returns: Three bytes on the first successful pull and nil at EOF.
    /// - Throws: `TransportFailure.closed` in failure mode or cooperative cancellation from the gate.
    func next() async throws -> Data? {
        reads += 1
        entered.open()
        if mode == 1 { throw TransportFailure.closed }
        if mode == 2 { try await gate.wait() }
        return reads == 1 ? Data([1, 2, 3]) : nil
    }

    /// Records resource release; the owning BodyStream must call this exactly once after any terminal path.
    func close() { closes += 1; gate.open() }
}
