// File: Tests/DiscordHTTPTests/ScheduledEventIntegrationTests.swift
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

/// Runs all ten Guild Scheduled Event and Stage Instance operations through injected real HTTP policy.
/// Fixtures are finite and deterministic; no Discord credentials, network, wall-clock delays or sleeps are required.
@Suite(.timeLimit(.minutes(1))) struct ScheduledEventIntegrationTests {
    /// Every operation transmits its exact versioned route, query, credential and validated JSON body once.
    /// Success status and response-body validation use the original typed decoder retained by the catalog.
    /// - Parameter index: Stable catalog position: event list/get/create/modify/delete/users and stage create/get/modify/delete.
    /// - Throws: Unexpected descriptor, body, response or execution failures fail the test.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: 0..<10) func success(index: Int) async throws {
        let (endpoint, bytes) = try ScheduledEventEndpointTests.catalog()[index]
        #expect(endpoint.authentication == .bot)
        #expect(endpoint.successStatuses == ([4, 9].contains(index) ? [204] : [200]))
        let transport = try ScriptedHTTPTransport(steps: [{ request in
            #expect(request.method == endpoint.method)
            #expect(request.url.host == "discord.com")
            #expect(request.url.path == "/api/v10/" + endpoint.path.joined(separator: "/"))
            let query = URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems?.map {
                QueryItem(name: $0.name, value: $0.value)
            } ?? []
            #expect(query == endpoint.query)
            let authorization = request.headers.filter { $0.name.lowercased() == "authorization" }
            #expect(authorization.count == 1)
            #expect(authorization.first?.value == "Bot synthetic")
            let reason = request.headers.first { $0.name.lowercased() == "x-audit-log-reason" }
            #expect(reason?.value.removingPercentEncoding == endpoint.auditReason)
            #expect((request.body != nil) == (endpoint.body != nil))
            let sent = try await ResponseBody.collect(request.body, maximumBytes: 1_048_576)
            #expect(sent == (endpoint.body?.bytes ?? Data()))
            if let expected = endpoint.body {
                #expect(request.headers.contains { $0.name.lowercased() == "content-type" && $0.value == "application/json" })
                #expect(try JSONValue.parse(sent) == JSONValue.parse(expected.bytes))
            }
            return try Self.response(bytes, status: [4, 9].contains(index) ? 204 : 200)
        }])
        let clock = ManualClock()
        let coordinator = RateLimitCoordinator(clock: clock)
        let client = RESTClient(credential: .bot(try BotToken("synthetic")), identity: RateLimitIdentity(),
            transport: transport, coordinator: coordinator, clock: clock, retryPolicy: .init(maximumAttempts: 1))
        #expect(try await client.execute(endpoint) == bytes)
        #expect(await transport.executionCount == 1)
        #expect(await coordinator.snapshot().activeCount == 0)
        #expect(await coordinator.snapshot().orderedOperationsCount == 0)
        #expect(clock.pendingSleepCount == 0)
        await coordinator.close()
    }

    /// Malformed success bodies fail rather than bypassing the original event/stage/empty-response schema.
    /// Null, wrong roots and incomplete nested event lists are rejected at the transport-policy boundary.
    /// - Parameter index: Every read and mutation, including strict empty HTTP 204 deletion.
    /// - Throws: Unexpected descriptor/setup failures fail the test; sanitized schema failures are asserted.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: 0..<10) func malformedSuccessBodies(index: Int) async throws {
        let endpoint = try ScheduledEventEndpointTests.catalog()[index].0
        var malformed = [Data("null".utf8), Data("{}".utf8), Data("[{}]".utf8)]
        if ![4, 9].contains(index) { malformed.append(Data()) }
        for bytes in malformed {
            let transport = try ScriptedHTTPTransport(steps: [{ request in
                await request.body?.close()
                return try Self.response(bytes, status: [4, 9].contains(index) ? 204 : 200)
            }])
            let clock = ManualClock()
            let coordinator = RateLimitCoordinator(clock: clock)
            let client = RESTClient(credential: .bot(try BotToken("synthetic")), identity: RateLimitIdentity(),
                transport: transport, coordinator: coordinator, clock: clock, retryPolicy: .init(maximumAttempts: 1))
            await #expect(throws: DiscordError.transport(.invalidResponse)) { try await client.execute(endpoint) }
            #expect(await transport.executionCount == 1)
            #expect(await coordinator.snapshot().activeCount == 0)
            #expect(await coordinator.snapshot().orderedOperationsCount == 0)
            #expect(clock.pendingSleepCount == 0)
            await coordinator.close()
        }
    }

    /// An unlisted 2xx status remains an API error even when its body matches the operation's model.
    /// This prevents creation or deletion from silently accepting undocumented success/status combinations.
    /// - Parameters:
    ///   - index: All ten current operations.
    ///   - status: Explicitly unaccepted success-class status, independent of response body validity.
    /// - Throws: Unexpected descriptor/setup errors fail the test; the exact API status is asserted.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: 0..<10, [201, 202, 205])
    func unexpectedSuccessStatus(index: Int, status: Int) async throws {
        let (endpoint, bytes) = try ScheduledEventEndpointTests.catalog()[index]
        let transport = try ScriptedHTTPTransport(steps: [{ request in
            await request.body?.close()
            return try Self.response(bytes, status: status)
        }])
        let clock = ManualClock()
        let coordinator = RateLimitCoordinator(clock: clock)
        let client = RESTClient(credential: .bot(try BotToken("synthetic")), identity: RateLimitIdentity(),
            transport: transport, coordinator: coordinator, clock: clock, retryPolicy: .init(maximumAttempts: 1))
        do { _ = try await client.execute(endpoint); Issue.record("Expected unlisted-status failure") }
        catch let error as APIResponseError { #expect(error.status == status) }
        #expect(await transport.executionCount == 1)
        #expect(await coordinator.snapshot().activeCount == 0)
        #expect(await coordinator.snapshot().orderedOperationsCount == 0)
        #expect(clock.pendingSleepCount == 0)
        await coordinator.close()
    }

    /// Validation, authentication, permission, absence and rate failures retain safe API evidence.
    /// Submitted unsafe server errors remain indeterminate and are never automatically replayed.
    /// - Parameters:
    ///   - index: Every event and stage operation.
    ///   - status: Finite scripted API failure, with a single-attempt retry budget.
    /// - Throws: Unexpected setup/execution failures fail the test; applicable safe error categories are asserted.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: 0..<10, [400, 401, 403, 404, 429, 500])
    func failures(index: Int, status: Int) async throws {
        let endpoint = try ScheduledEventEndpointTests.catalog()[index].0
        let transport = try ScriptedHTTPTransport(steps: [{ request in
            await request.body?.close()
            return try Self.response(Data(#"{"code":50035,"message":"private-event","errors":{"name":{"_errors":[{"code":"BAD","message":"private-event"}]}}}"#.utf8), status: status)
        }])
        let clock = ManualClock()
        let coordinator = RateLimitCoordinator(clock: clock)
        let client = RESTClient(credential: .bot(try BotToken("synthetic")), identity: RateLimitIdentity(),
            transport: transport, coordinator: coordinator, clock: clock, retryPolicy: .init(maximumAttempts: 1))
        do { _ = try await client.execute(endpoint); Issue.record("Expected API failure") }
        catch let error as APIResponseError {
            #expect(status < 500 || endpoint.retrySafety == .safe)
            #expect(error.status == status)
            #expect(error.code == 50035)
            #expect(error.withUnsafePayload { $0 != nil })
            #expect(!String(reflecting: error).contains("private-event"))
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

    /// Complete 429 rejection permits one bounded replay of each read and mutation with the same exact request body.
    /// A second rejection exhausts the configured budget as an API error, never an indeterminate mutation.
    /// A 250-millisecond rejection delay is observed through queued admission and advanced using the injected clock.
    /// - Parameters:
    ///   - index: Every event and stage operation, including strict HTTP 204 deletion.
    ///   - rejectedAgain: True rejects both attempts; false acknowledges the second with its typed success body.
    /// - Throws: Unexpected setup/body/execution errors fail the test; exhausted API rejection is asserted.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: 0..<10, [false, true])
    func explicitRateRejectionRetriesWithinBudget(index: Int, rejectedAgain: Bool) async throws {
        let (endpoint, bytes) = try ScheduledEventEndpointTests.catalog()[index]
        let rejected = Data(#"{"code":0,"message":"rate limited","retry_after":0.25,"global":false}"#.utf8)
        let first: ScriptedHTTPTransport.Step = { request in
            #expect(request.method == endpoint.method)
            #expect(try await ResponseBody.collect(request.body, maximumBytes: 1_048_576) == (endpoint.body?.bytes ?? Data()))
            return try Self.response(rejected, status: 429)
        }
        let second: ScriptedHTTPTransport.Step = { request in
            #expect(request.method == endpoint.method)
            #expect(request.url.path == "/api/v10/" + endpoint.path.joined(separator: "/"))
            #expect(try await ResponseBody.collect(request.body, maximumBytes: 1_048_576) == (endpoint.body?.bytes ?? Data()))
            return try Self.response(rejectedAgain ? rejected : bytes,
                status: rejectedAgain ? 429 : [4, 9].contains(index) ? 204 : 200)
        }
        let transport = try ScriptedHTTPTransport(steps: [first, second])
        let clock = ManualClock(), coordinator = RateLimitCoordinator(clock: clock)
        let client = RESTClient(credential: .bot(try BotToken("synthetic")), identity: RateLimitIdentity(),
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
            do { _ = try await task.value; Issue.record("Expected exhausted rejection") }
            catch let error as APIResponseError { #expect(error.status == 429) }
        } else {
            #expect(try await task.value == bytes)
        }
        #expect(await transport.executionCount == 2)
        #expect(await coordinator.snapshot().activeCount == 0)
        #expect(await coordinator.snapshot().queuedCount == 0)
        #expect(await coordinator.snapshot().orderedOperationsCount == 0)
        #expect(clock.pendingSleepCount == 0)
        await coordinator.close()
    }

    /// Missing and bearer-only credentials fail before transport transmission for all bot-only operations.
    /// No admission, ordered operation or timer is retained after credential validation fails.
    /// - Parameter index: Every catalog descriptor, including event retrieval.
    /// - Throws: Unexpected setup failures fail the test; missing-value validation is asserted explicitly.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: 0..<10) func authenticationMismatch(index: Int) async throws {
        let endpoint = try ScheduledEventEndpointTests.catalog()[index].0
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
        #expect(clock.pendingSleepCount == 0)
        await coordinator.close()
    }

    /// Connection failures preserve transport categories for safe reads and uncertain submission for mutations.
    /// One-attempt policy ensures no event/stage creation, edit or deletion is accidentally replayed.
    /// - Parameter index: Every current descriptor.
    /// - Throws: Unexpected setup failures fail the test; the exact safe/unsafe failure category is asserted.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: 0..<10) func transportFailure(index: Int) async throws {
        let endpoint = try ScheduledEventEndpointTests.catalog()[index].0
        let transport = try ScriptedHTTPTransport(steps: [{ _ in throw TransportFailure.closed }])
        let clock = ManualClock()
        let coordinator = RateLimitCoordinator(clock: clock)
        let client = RESTClient(credential: .bot(try BotToken("synthetic")), identity: RateLimitIdentity(),
            transport: transport, coordinator: coordinator, clock: clock, retryPolicy: .init(maximumAttempts: 1))
        do { _ = try await client.execute(endpoint); Issue.record("Expected transport failure") }
        catch let error as DiscordError {
            #expect(error == (endpoint.retrySafety == .unsafe
                ? .unknownMutationOutcome(.connectionLostAfterSubmission) : .transport(.connectionFailed)))
        }
        #expect(await transport.executionCount == 1)
        #expect(await coordinator.snapshot().activeCount == 0)
        #expect(await coordinator.snapshot().orderedOperationsCount == 0)
        #expect(clock.pendingSleepCount == 0)
        await coordinator.close()
    }

    /// A task already cancelled before execution sends no read or mutation and leaves every owner idle.
    /// - Parameter index: Every event/stage descriptor.
    /// - Throws: Unexpected setup failures fail the test; cooperative CancellationError is asserted.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: 0..<10) func cancelledBeforeSend(index: Int) async throws {
        let endpoint = try ScheduledEventEndpointTests.catalog()[index].0
        let transport = try ScriptedHTTPTransport(steps: [])
        let clock = ManualClock()
        let coordinator = RateLimitCoordinator(clock: clock)
        let client = RESTClient(credential: .bot(try BotToken("synthetic")), identity: RateLimitIdentity(),
            transport: transport, coordinator: coordinator, clock: clock)
        let task = Task { withUnsafeCurrentTask { $0?.cancel() }; return try await client.execute(endpoint) }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await transport.executionCount == 0)
        #expect(await coordinator.snapshot().activeCount == 0)
        #expect(await coordinator.snapshot().orderedOperationsCount == 0)
        #expect(clock.pendingSleepCount == 0)
        await coordinator.close()
    }

    /// Cancellation during a barrier-suspended exchange releases request/admission/order ownership before return.
    /// Safe reads cancel normally; possibly submitted mutations retain the explicit indeterminate category.
    /// - Parameter index: Every descriptor, with cancellation synchronized to actual transport entry.
    /// - Throws: Unexpected setup errors fail the test; cancellation categories and cleanup are asserted.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: 0..<10) func cancellationDuringExchange(index: Int) async throws {
        let endpoint = try ScheduledEventEndpointTests.catalog()[index].0
        let entered = TestBarrier(), gate = TestBarrier(), clock = ManualClock()
        let coordinator = RateLimitCoordinator(clock: clock)
        let transport = try ScriptedHTTPTransport(steps: [{ request in
            await request.body?.close()
            entered.open()
            try await gate.wait()
            return HTTPResponse(status: 204)
        }])
        let client = RESTClient(credential: .bot(try BotToken("synthetic")), identity: RateLimitIdentity(),
            transport: transport, coordinator: coordinator, clock: clock)
        let task = Task { try await client.execute(endpoint) }
        try await entered.wait()
        task.cancel()
        do { _ = try await task.value; Issue.record("Expected cancellation") }
        catch let error as DiscordError {
            #expect(endpoint.retrySafety == .unsafe)
            #expect(error == .unknownMutationOutcome(.cancelledAfterSubmission))
        } catch is CancellationError { #expect(endpoint.retrySafety == .safe) }
        #expect(gate.waitingCount == 0)
        #expect(await transport.executionCount == 1)
        #expect(await coordinator.snapshot().activeCount == 0)
        #expect(await coordinator.snapshot().orderedOperationsCount == 0)
        #expect(clock.pendingSleepCount == 0)
        await coordinator.close()
    }

    /// Equivalent reads coalesce across clients sharing their credential identity while foreign identities remain separate.
    /// Twenty registered subscribers require exactly two exchanges and release all shared-flight ownership on completion.
    /// - Parameter index: Event list/detail/users or stage detail, each eligible for default in-flight reuse.
    /// - Throws: Unexpected setup, cooperative cancellation or execution errors fail the test.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [0, 1, 5, 7]) func readsCoalesceWithinIdentity(index: Int) async throws {
        let (endpoint, bytes) = try ScheduledEventEndpointTests.catalog()[index]
        let gate = TestBarrier(), clock = ManualClock(), coalescer = RequestCoalescer()
        let coordinator = RateLimitCoordinator(clock: clock), identity = RateLimitIdentity()
        let step: ScriptedHTTPTransport.Step = { _ in
            try await gate.wait()
            return try Self.response(bytes)
        }
        let transport = try ScriptedHTTPTransport(steps: [step, step])
        let first = RESTClient(credential: .bot(try BotToken("shared")), identity: identity, transport: transport,
            coordinator: coordinator, clock: clock, coalescer: coalescer)
        let same = RESTClient(credential: .bot(try BotToken("shared")), identity: identity, transport: transport,
            coordinator: coordinator, clock: clock, coalescer: coalescer)
        let foreign = RESTClient(credential: .bot(try BotToken("foreign")), identity: RateLimitIdentity(), transport: transport,
            coordinator: coordinator, clock: clock, coalescer: coalescer)
        let tasks = (0..<20).map { number in
            Task { try await (number < 6 ? first : number < 12 ? same : foreign).execute(endpoint) }
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
        await coalescer.close()
        await coordinator.close()
    }

    /// Cancelling one shared subscriber leaves the other subscriber's exchange and response ownership alive.
    /// The final successful reader releases the flight, admission and timers without a replacement request.
    /// - Parameter index: Event list/detail/users or stage detail with default eligible-read coalescing.
    /// - Throws: Unexpected setup or surviving-reader failures fail the test; subscriber cancellation is asserted.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [0, 1, 5, 7]) func cancellingOneCoalescedSubscriber(index: Int) async throws {
        let (endpoint, bytes) = try ScheduledEventEndpointTests.catalog()[index]
        let gate = TestBarrier(), clock = ManualClock(), coalescer = RequestCoalescer()
        let coordinator = RateLimitCoordinator(clock: clock)
        let transport = try ScriptedHTTPTransport(steps: [{ _ in
            try await gate.wait()
            return try Self.response(bytes)
        }])
        let client = RESTClient(credential: .bot(try BotToken("synthetic")), identity: RateLimitIdentity(), transport: transport,
            coordinator: coordinator, clock: clock, coalescer: coalescer)
        let cancelled = Task { try await client.execute(endpoint) }
        let surviving = Task { try await client.execute(endpoint) }
        while await coalescer.snapshot().waiters < 2 { try Task.checkCancellation(); await Task.yield() }
        cancelled.cancel()
        await #expect(throws: CancellationError.self) { try await cancelled.value }
        #expect(await coalescer.snapshot().flights == 1)
        #expect(await coalescer.snapshot().waiters == 1)
        gate.open()
        #expect(try await surviving.value == bytes)
        #expect(await transport.executionCount == 1)
        #expect(await coalescer.snapshot().flights == 0)
        #expect(await coalescer.snapshot().waiters == 0)
        #expect(await coordinator.snapshot().activeCount == 0)
        #expect(clock.pendingSleepCount == 0)
        await coalescer.close()
        await coordinator.close()
    }

    /// Completed read reuse honors the supplied 60-second TTL and cannot cross a credential identity.
    /// Cache expiry is inclusive at exactly 60 seconds and is advanced without wall-clock sleeps or refresh tasks.
    /// - Parameter index: Every eligible event/stage read.
    /// - Throws: Unexpected setup, clock advancement or execution failures fail the test.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [0, 1, 5, 7]) func scopedTTLAndInclusiveExpiry(index: Int) async throws {
        let (original, bytes) = try ScheduledEventEndpointTests.catalog()[index]
        let endpoint = try Self.cached(original)
        let clock = ManualClock(), identity = RateLimitIdentity()
        let cache = ReadCache(clock: clock)
        let coordinator = RateLimitCoordinator(clock: clock)
        let step: ScriptedHTTPTransport.Step = { _ in try Self.response(bytes) }
        let transport = try ScriptedHTTPTransport(steps: [step, step, step, step])
        let first = RESTClient(credential: .bot(try BotToken("shared")), identity: identity, transport: transport,
            coordinator: coordinator, clock: clock, cache: cache)
        let same = RESTClient(credential: .bot(try BotToken("shared")), identity: identity, transport: transport,
            coordinator: coordinator, clock: clock, cache: cache)
        let foreign = RESTClient(credential: .bot(try BotToken("foreign")), identity: RateLimitIdentity(), transport: transport,
            coordinator: coordinator, clock: clock, cache: cache)
        #expect(try await first.execute(endpoint) == bytes)
        #expect(try await same.execute(endpoint) == bytes)
        #expect(await transport.executionCount == 1)
        #expect(try await foreign.execute(endpoint) == bytes)
        #expect(await transport.executionCount == 2)
        #expect(await cache.snapshot().entries == 2)
        try clock.advance(by: .seconds(59))
        #expect(try await same.execute(endpoint) == bytes)
        #expect(try await foreign.execute(endpoint) == bytes)
        #expect(await transport.executionCount == 2)
        try clock.advance(by: .seconds(1))
        #expect(await cache.snapshot().entries == 0)
        #expect(try await first.execute(endpoint) == bytes)
        #expect(try await foreign.execute(endpoint) == bytes)
        #expect(await transport.executionCount == 4)
        #expect(await cache.snapshot().entries == 2)
        #expect(await coordinator.snapshot().activeCount == 0)
        #expect(clock.pendingSleepCount == 0)
        await coordinator.close()
    }

    /// Invalid success bodies are never retained, allowing the next valid response to populate the opted-in cache.
    /// A later equivalent read reuses only the complete validated snapshot, without an extra exchange.
    /// - Parameter index: Event list/detail/users or stage detail with explicit completed-result caching.
    /// - Throws: Unexpected setup/execution errors fail the test; initial schema rejection is asserted.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [0, 1, 5, 7]) func malformedReadsNeverPopulateCache(index: Int) async throws {
        let (original, bytes) = try ScheduledEventEndpointTests.catalog()[index]
        let endpoint = try Self.cached(original)
        let transport = try ScriptedHTTPTransport(steps: [
            { _ in try Self.response(Data("{}".utf8)) }, { _ in try Self.response(bytes) }
        ])
        let clock = ManualClock()
        let cache = ReadCache(clock: clock), coordinator = RateLimitCoordinator(clock: clock)
        let client = RESTClient(credential: .bot(try BotToken("synthetic")), identity: RateLimitIdentity(), transport: transport,
            coordinator: coordinator, clock: clock, cache: cache, retryPolicy: .init(maximumAttempts: 1))
        await #expect(throws: DiscordError.transport(.invalidResponse)) { try await client.execute(endpoint) }
        #expect(await cache.snapshot().entries == 0)
        #expect(try await client.execute(endpoint) == bytes)
        #expect(await cache.snapshot().entries == 1)
        #expect(try await client.execute(endpoint) == bytes)
        #expect(await transport.executionCount == 2)
        #expect(await coordinator.snapshot().activeCount == 0)
        #expect(clock.pendingSleepCount == 0)
        await coordinator.close()
    }

    /// Each successful event/stage mutation evicts dependent snapshots only for its credential identity.
    /// - Parameter index: Every mutation including both strict HTTP 204 deletions.
    /// - Throws: Unexpected descriptor, decoder or execution errors fail the test.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [2, 3, 4, 6, 8, 9]) func writesInvalidateScopedSnapshots(index: Int) async throws {
        let catalog = try ScheduledEventEndpointTests.catalog()
        let read = try Self.cached(catalog[1].0), stage = try Self.cached(catalog[7].0)
        let eventBytes = catalog[1].1, stageBytes = catalog[7].1
        let (mutation, result) = catalog[index]
        let replies: [(Data, Int)] = [(eventBytes, 200), (stageBytes, 200), (eventBytes, 200),
            (result, [4, 9].contains(index) ? 204 : 200), (eventBytes, 200), (stageBytes, 200)]
        let transport = try ScriptedHTTPTransport(steps: replies.map { bytes, status in
            { request in await request.body?.close(); return try Self.response(bytes, status: status) }
        })
        let clock = ManualClock(), cache = ReadCache(clock: clock), coordinator = RateLimitCoordinator(clock: clock)
        let first = RESTClient(credential: .bot(try BotToken("first")), identity: RateLimitIdentity(), transport: transport,
            coordinator: coordinator, clock: clock, cache: cache)
        let foreign = RESTClient(credential: .bot(try BotToken("foreign")), identity: RateLimitIdentity(), transport: transport,
            coordinator: coordinator, clock: clock, cache: cache)
        #expect(try await first.execute(read) == eventBytes)
        #expect(try await first.execute(stage) == stageBytes)
        #expect(try await foreign.execute(read) == eventBytes)
        #expect(await cache.snapshot().entries == 3)
        #expect(try await first.execute(mutation) == result)
        #expect(await cache.snapshot().entries == 1)
        #expect(try await foreign.execute(read) == eventBytes)
        #expect(await transport.executionCount == 4)
        #expect(try await first.execute(read) == eventBytes)
        #expect(try await first.execute(stage) == stageBytes)
        #expect(await transport.executionCount == 6)
        #expect(await coordinator.snapshot().activeCount == 0)
        #expect(clock.pendingSleepCount == 0)
        await coordinator.close()
    }

    /// Copies an already erased catalog read while opting into completed-result caching with its actual tags.
    /// The original typed decoder remains retained, so malformed data cannot be accepted by the fixture wrapper.
    /// - Parameter endpoint: One safe catalog GET whose original eligibility and invalidation tags are preserved.
    /// - Returns: Equivalent descriptor with a positive 60-second TTL and no new mutation behavior.
    /// - Throws: Endpoint validation errors for an invalid fixture or incompatible read policy.
    private static func cached(_ endpoint: Endpoint<Data>) throws -> Endpoint<Data> {
        try Endpoint(method: endpoint.method, path: endpoint.path, route: endpoint.route, query: endpoint.query,
            authentication: endpoint.authentication, successStatuses: endpoint.successStatuses,
            majorParameter: endpoint.majorParameter, usesGlobalLimit: endpoint.usesGlobalLimit,
            auditReason: endpoint.auditReason, body: endpoint.body, headers: endpoint.headers,
            retrySafety: endpoint.retrySafety,
            readPolicy: ReadPolicy(coalescing: endpoint.readPolicy?.coalescing ?? true,
                timeToLive: .seconds(60), tags: endpoint.readPolicy?.tags ?? []),
            invalidates: endpoint.invalidates, bulk: endpoint.bulk, decode: endpoint.decode)
    }

    /// Produces one locally owned bounded response stream for consumption or cleanup by the real client.
    /// - Parameters:
    ///   - bytes: Complete JSON/error fixture; empty bytes mean an absent body, including strict deletion success.
    ///   - status: Explicit HTTP status, default 200; no success inference is made from body presence.
    /// - Returns: A finite scripted response with a learned 100-request route window and 99 remaining
    ///   requests, keeping cache tests independent of unknown-route provisional throttling. Explicit 429
    ///   responses still replace remaining admission with the body retry delay. No sockets, credentials,
    ///   cache effects or implicit retries are introduced by this fixture.
    /// - Throws: RequestBody validation errors for an invalid or oversized local fixture.
    private static func response(_ bytes: Data, status: Int = 200) throws -> HTTPResponse {
        HTTPResponse(status: status, headers: [
            .init(name: "X-RateLimit-Limit", value: "100"),
            .init(name: "X-RateLimit-Remaining", value: "99"),
            .init(name: "X-RateLimit-Reset-After", value: "1")
        ], body: bytes.isEmpty ? nil : try RequestBody(bytes: bytes, contentType: "application/json").makeStream())
    }
}
