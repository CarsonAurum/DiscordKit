// File: Tests/DiscordHTTPTests/ApplicationCommandIntegrationTests.swift
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

/// Runs all 15 application command operations through injected real HTTP policy.
/// Fixtures are finite and deterministic; no Discord credentials, network, wall-clock delays or sleeps are required.
@Suite(.timeLimit(.minutes(1))) struct ApplicationCommandIntegrationTests {
    /// Every operation transmits its exact versioned route, query, credential and validated JSON body once.
    /// Success status and response-body validation use the original typed decoder retained by the catalog.
    /// - Parameter index: Stable position in the complete 15-operation command catalog.
    /// - Throws: Unexpected descriptor, body, response or execution failures fail the test.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: 0..<15) func success(index: Int) async throws {
        let (endpoint, bytes) = try ApplicationCommandEndpointTests.catalog()[index]
        #expect(endpoint.authentication == .botOrBearer || endpoint.authentication == .bearer)
        #expect(!endpoint.successStatuses.isEmpty)
        let successStatus = try #require(endpoint.successStatuses.first)
        let transport = try ScriptedHTTPTransport(steps: [{ request in
            #expect(request.method == endpoint.method)
            #expect(request.url.host == "discord.com")
            #expect(request.url.path == "/api/v10/" + endpoint.path.joined(separator: "/"))
            let query = URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems?.map {
                QueryItem(name: $0.name, value: $0.value)
            } ?? []
            #expect(query == endpoint.query)
            let authorization = request.headers.filter { $0.name.lowercased() == "authorization" }
            #expect(authorization.count == (endpoint.authentication == .none ? 0 : 1))
            #expect(authorization.first?.value == (endpoint.authentication == .none ? nil : "Bearer synthetic"))
            let reason = request.headers.first { $0.name.lowercased() == "x-audit-log-reason" }
            #expect(reason?.value.removingPercentEncoding == endpoint.auditReason)
            #expect((request.body != nil) == (endpoint.body != nil))
            let sent = try await ResponseBody.collect(request.body, maximumBytes: 1_048_576)
            #expect(sent == (endpoint.body?.bytes ?? Data()))
            if let expected = endpoint.body {
                #expect(request.headers.contains { $0.name.lowercased() == "content-type" && $0.value == expected.contentType })
                if expected.contentType == "application/json" {
                    #expect(try JSONValue.parse(sent) == JSONValue.parse(expected.bytes))
                }
            }
            return try Self.response(bytes, status: successStatus)
        }])
        let clock = ManualClock()
        let coordinator = RateLimitCoordinator(clock: clock)
        let client = RESTClient(credential: .bearer(try BearerToken("synthetic")), identity: RateLimitIdentity(),
            transport: transport, coordinator: coordinator, clock: clock, retryPolicy: .init(maximumAttempts: 1))
        #expect(try await client.execute(endpoint) == bytes)
        #expect(await transport.executionCount == 1)
        #expect(await coordinator.snapshot().activeCount == 0)
        #expect(await coordinator.snapshot().orderedOperationsCount == 0)
        #expect(clock.pendingSleepCount == 0)
        await coordinator.close()
    }

    /// Malformed success bodies fail rather than bypassing the original command/envelope/empty-response schema.
    /// Null, wrong roots and incomplete nested command lists are rejected at the transport-policy boundary.
    /// - Parameter index: Every read and mutation, including the deleted command response.
    /// - Throws: Unexpected descriptor/setup failures fail the test; sanitized schema failures are asserted.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: 0..<15) func malformedSuccessBodies(index: Int) async throws {
        let endpoint = try ApplicationCommandEndpointTests.catalog()[index].0
        var malformed = [Data("null".utf8), Data("{}".utf8), Data("[{}]".utf8)]
        if !endpoint.successStatuses.contains(204) { malformed.append(Data()) }
        for bytes in malformed {
            let transport = try ScriptedHTTPTransport(steps: [{ request in
                await request.body?.close()
                return try Self.response(bytes, status: endpoint.successStatuses.first!)
            }])
            let clock = ManualClock()
            let coordinator = RateLimitCoordinator(clock: clock)
            let client = RESTClient(credential: .bearer(try BearerToken("synthetic")), identity: RateLimitIdentity(),
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
    /// This prevents registration, replacement or deletion from silently accepting undocumented success/status combinations.
    /// - Parameters:
    ///   - index: All 15 current operations.
    ///   - status: Explicitly unaccepted success-class status, independent of response body validity.
    /// - Throws: Unexpected descriptor/setup errors fail the test; the exact API status is asserted.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: 0..<15, [202, 205, 206])
    func unexpectedSuccessStatus(index: Int, status: Int) async throws {
        let (endpoint, bytes) = try ApplicationCommandEndpointTests.catalog()[index]
        let transport = try ScriptedHTTPTransport(steps: [{ request in
            await request.body?.close()
            return try Self.response(bytes, status: status)
        }])
        let clock = ManualClock()
        let coordinator = RateLimitCoordinator(clock: clock)
        let client = RESTClient(credential: .bearer(try BearerToken("synthetic")), identity: RateLimitIdentity(),
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
    ///   - index: Every command operation.
    ///   - status: Finite scripted API failure, with a single-attempt retry budget.
    /// - Throws: Unexpected setup/execution failures fail the test; applicable safe error categories are asserted.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: 0..<15, [400, 401, 403, 404, 429, 500])
    func failures(index: Int, status: Int) async throws {
        let endpoint = try ApplicationCommandEndpointTests.catalog()[index].0
        let transport = try ScriptedHTTPTransport(steps: [{ request in
            await request.body?.close()
            return try Self.response(Data(#"{"code":50035,"message":"private-command","errors":{"name":{"_errors":[{"code":"BAD","message":"private-command"}]}}}"#.utf8), status: status)
        }])
        let clock = ManualClock()
        let coordinator = RateLimitCoordinator(clock: clock)
        let client = RESTClient(credential: .bearer(try BearerToken("synthetic")), identity: RateLimitIdentity(),
            transport: transport, coordinator: coordinator, clock: clock, retryPolicy: .init(maximumAttempts: 1))
        do { _ = try await client.execute(endpoint); Issue.record("Expected API failure") }
        catch let error as APIResponseError {
            #expect(status < 500 || endpoint.retrySafety == .safe)
            #expect(error.status == status)
            #expect(error.code == 50035)
            #expect(error.withUnsafePayload { $0 != nil })
            #expect(!String(reflecting: error).contains("private-command"))
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
    ///   - index: Every command operation, including command deletion.
    ///   - rejectedAgain: True rejects both attempts; false acknowledges the second with its typed success body.
    /// - Throws: Unexpected setup/body/execution errors fail the test; exhausted API rejection is asserted.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: 0..<15, [false, true])
    func explicitRateRejectionRetriesWithinBudget(index: Int, rejectedAgain: Bool) async throws {
        let (endpoint, bytes) = try ApplicationCommandEndpointTests.catalog()[index]
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
                status: rejectedAgain ? 429 : endpoint.successStatuses.first!)
        }
        let transport = try ScriptedHTTPTransport(steps: [first, second])
        let clock = ManualClock(), coordinator = RateLimitCoordinator(clock: clock)
        let client = RESTClient(credential: .bearer(try BearerToken("synthetic")), identity: RateLimitIdentity(),
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

    /// Missing credentials fail before transmission; permission writes additionally reject bot credentials.
    /// No admission, ordered operation or timer is retained after credential validation fails.
    /// - Parameter index: Every catalog descriptor, including authenticated command retrieval.
    /// - Throws: Unexpected setup failures fail the test; missing-value validation is asserted explicitly.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: 0..<15) func authenticationMismatch(index: Int) async throws {
        let endpoint = try ApplicationCommandEndpointTests.catalog()[index].0
        guard endpoint.authentication != .none else { return }
        let transport = try ScriptedHTTPTransport(steps: [])
        let clock = ManualClock()
        let coordinator = RateLimitCoordinator(clock: clock)
        for credential in [Credential.none] + (endpoint.authentication == .bearer ? [.bot(try BotToken("synthetic-bot"))] : []) {
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
    /// One-attempt policy ensures no command creation, synchronization, edit or deletion is accidentally replayed.
    /// - Parameter index: Every current descriptor.
    /// - Throws: Unexpected setup failures fail the test; the exact safe/unsafe failure category is asserted.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: 0..<15) func transportFailure(index: Int) async throws {
        let endpoint = try ApplicationCommandEndpointTests.catalog()[index].0
        let transport = try ScriptedHTTPTransport(steps: [{ _ in throw TransportFailure.closed }])
        let clock = ManualClock()
        let coordinator = RateLimitCoordinator(clock: clock)
        let client = RESTClient(credential: .bearer(try BearerToken("synthetic")), identity: RateLimitIdentity(),
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
    /// - Parameter index: Every command descriptor.
    /// - Throws: Unexpected setup failures fail the test; cooperative CancellationError is asserted.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: 0..<15) func cancelledBeforeSend(index: Int) async throws {
        let endpoint = try ApplicationCommandEndpointTests.catalog()[index].0
        let transport = try ScriptedHTTPTransport(steps: [])
        let clock = ManualClock()
        let coordinator = RateLimitCoordinator(clock: clock)
        let client = RESTClient(credential: .bearer(try BearerToken("synthetic")), identity: RateLimitIdentity(),
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
    @Test(arguments: 0..<15) func cancellationDuringExchange(index: Int) async throws {
        let endpoint = try ApplicationCommandEndpointTests.catalog()[index].0
        let entered = TestBarrier(), gate = TestBarrier(), clock = ManualClock()
        let coordinator = RateLimitCoordinator(clock: clock)
        let transport = try ScriptedHTTPTransport(steps: [{ request in
            await request.body?.close()
            entered.open()
            try await gate.wait()
            return HTTPResponse(status: 204)
        }])
        let client = RESTClient(credential: .bearer(try BearerToken("synthetic")), identity: RateLimitIdentity(),
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
    /// - Parameter index: Each safe command GET with default in-flight reuse.
    /// - Throws: Unexpected setup, cooperative cancellation or execution errors fail the test.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: Self.readIndices) func readsCoalesceWithinIdentity(index: Int) async throws {
        let (endpoint, bytes) = try ApplicationCommandEndpointTests.catalog()[index]
        let gate = TestBarrier(), clock = ManualClock(), coalescer = RequestCoalescer()
        let coordinator = RateLimitCoordinator(clock: clock), identity = RateLimitIdentity()
        let step: ScriptedHTTPTransport.Step = { _ in
            try await gate.wait()
            return try Self.response(bytes)
        }
        let transport = try ScriptedHTTPTransport(steps: [step, step])
        let first = RESTClient(credential: .bearer(try BearerToken("shared")), identity: identity, transport: transport,
            coordinator: coordinator, clock: clock, coalescer: coalescer)
        let same = RESTClient(credential: .bearer(try BearerToken("shared")), identity: identity, transport: transport,
            coordinator: coordinator, clock: clock, coalescer: coalescer)
        let foreign = RESTClient(credential: .bearer(try BearerToken("foreign")), identity: RateLimitIdentity(), transport: transport,
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
    /// - Parameter index: Each safe command GET with default in-flight reuse.
    /// - Throws: Unexpected setup or surviving-reader failures fail the test; subscriber cancellation is asserted.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: Self.readIndices) func cancellingOneCoalescedSubscriber(index: Int) async throws {
        let (endpoint, bytes) = try ApplicationCommandEndpointTests.catalog()[index]
        let gate = TestBarrier(), clock = ManualClock(), coalescer = RequestCoalescer()
        let coordinator = RateLimitCoordinator(clock: clock)
        let transport = try ScriptedHTTPTransport(steps: [{ _ in
            try await gate.wait()
            return try Self.response(bytes)
        }])
        let client = RESTClient(credential: .bearer(try BearerToken("synthetic")), identity: RateLimitIdentity(), transport: transport,
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
    /// - Parameter index: Every eligible command read.
    /// - Throws: Unexpected setup, clock advancement or execution failures fail the test.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: Self.readIndices) func scopedTTLAndInclusiveExpiry(index: Int) async throws {
        let (original, bytes) = try ApplicationCommandEndpointTests.catalog()[index]
        let endpoint = try Self.cached(original)
        let clock = ManualClock(), identity = RateLimitIdentity()
        let cache = ReadCache(clock: clock)
        let coordinator = RateLimitCoordinator(clock: clock)
        let step: ScriptedHTTPTransport.Step = { _ in try Self.response(bytes) }
        let transport = try ScriptedHTTPTransport(steps: [step, step, step, step])
        let first = RESTClient(credential: .bearer(try BearerToken("shared")), identity: identity, transport: transport,
            coordinator: coordinator, clock: clock, cache: cache)
        let same = RESTClient(credential: .bearer(try BearerToken("shared")), identity: identity, transport: transport,
            coordinator: coordinator, clock: clock, cache: cache)
        let foreign = RESTClient(credential: .bearer(try BearerToken("foreign")), identity: RateLimitIdentity(), transport: transport,
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
    /// - Parameter index: Each safe command GET with explicit completed-result caching.
    /// - Throws: Unexpected setup/execution errors fail the test; initial schema rejection is asserted.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: Self.readIndices) func malformedReadsNeverPopulateCache(index: Int) async throws {
        let (original, bytes) = try ApplicationCommandEndpointTests.catalog()[index]
        let endpoint = try Self.cached(original)
        let transport = try ScriptedHTTPTransport(steps: [
            { _ in try Self.response(Data("{}".utf8)) }, { _ in try Self.response(bytes) }
        ])
        let clock = ManualClock()
        let cache = ReadCache(clock: clock), coordinator = RateLimitCoordinator(clock: clock)
        let client = RESTClient(credential: .bearer(try BearerToken("synthetic")), identity: RateLimitIdentity(), transport: transport,
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

    /// Every observed command mutation evicts matching snapshots only within its authentication identity.
    /// Matching catalog tags cover list/detail and related guild/audit reads without automatic refreshes.
    /// - Parameter index: Each command mutation with documented invalidation tags.
    /// - Throws: Unexpected fixture, descriptor, cache or execution errors fail this test.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: Self.mutationIndices) func writesInvalidateScopedSnapshots(index: Int) async throws {
        let catalog = try ApplicationCommandEndpointTests.catalog()
        let (mutation, result) = catalog[index]
        let matching = catalog.filter {
            $0.0.method == "GET" && !($0.0.readPolicy?.tags ?? []).isDisjoint(with: mutation.invalidates)
        }
        #expect(!matching.isEmpty)
        let reads = try matching.map { (try Self.cached($0.0), $0.1) }
        let replies = reads + reads + [(mutation, result)] + reads
        let steps: [ScriptedHTTPTransport.Step] = replies.map { endpoint, bytes in
            { request in
                await request.body?.close()
                return try Self.response(bytes, status: endpoint.successStatuses.first!)
            }
        }
        let transport = try ScriptedHTTPTransport(steps: steps), clock = ManualClock()
        let cache = ReadCache(clock: clock), coordinator = RateLimitCoordinator(clock: clock)
        let first = RESTClient(credential: .bearer(try BearerToken("synthetic")), identity: RateLimitIdentity(),
            transport: transport, coordinator: coordinator, clock: clock, cache: cache)
        let foreign = RESTClient(credential: .bearer(try BearerToken("foreign")), identity: RateLimitIdentity(),
            transport: transport, coordinator: coordinator, clock: clock, cache: cache)
        for (read, bytes) in reads { #expect(try await first.execute(read) == bytes) }
        for (read, bytes) in reads { #expect(try await foreign.execute(read) == bytes) }
        #expect(await cache.snapshot().entries == reads.count * 2)
        #expect(try await first.execute(mutation) == result)
        #expect(await cache.snapshot().entries == reads.count)
        for (read, bytes) in reads { #expect(try await foreign.execute(read) == bytes) }
        #expect(await transport.executionCount == reads.count * 2 + 1)
        for (read, bytes) in reads { #expect(try await first.execute(read) == bytes) }
        #expect(await transport.executionCount == reads.count * 3 + 1)
        #expect(await cache.snapshot().entries == reads.count * 2)
        #expect(await coordinator.snapshot().activeCount == 0)
        #expect(await coordinator.snapshot().orderedOperationsCount == 0)
        #expect(clock.pendingSleepCount == 0)
        await coordinator.close()
    }

    /// Definitively rejected mutations retain opted-in snapshots until expiry and never perform hidden reads.
    /// - Parameters:
    ///   - index: Every command create/edit/delete with matching read tags.
    ///   - status: Server validation, permission or explicit rate rejection under a one-attempt policy.
    /// - Throws: Unexpected setup or execution errors fail the test; rejected API status is asserted.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: Self.mutationIndices, [400, 403, 429])
    func rejectedWritesPreserveSnapshots(index: Int, status: Int) async throws {
        let catalog = try ApplicationCommandEndpointTests.catalog(), mutation = catalog[index].0
        let match = try #require(catalog.first {
            $0.0.method == "GET" && !($0.0.readPolicy?.tags ?? []).isDisjoint(with: mutation.invalidates)
        })
        let read = try Self.cached(match.0), bytes = match.1
        let transport = try ScriptedHTTPTransport(steps: [
            { _ in try Self.response(bytes) },
            { request in
                await request.body?.close()
                return try Self.response(Data(#"{"code":50013,"message":"private-command"}"#.utf8), status: status)
            }
        ])
        let clock = ManualClock(), cache = ReadCache(clock: clock), coordinator = RateLimitCoordinator(clock: clock)
        let client = RESTClient(credential: .bearer(try BearerToken("synthetic")), identity: RateLimitIdentity(),
            transport: transport, coordinator: coordinator, clock: clock, cache: cache, retryPolicy: .init(maximumAttempts: 1))
        #expect(try await client.execute(read) == bytes)
        do { _ = try await client.execute(mutation); Issue.record("Expected rejected command mutation") }
        catch let error as APIResponseError { #expect(error.status == status) }
        #expect(await cache.snapshot().entries == 1)
        #expect(try await client.execute(read) == bytes)
        #expect(await transport.executionCount == 2)
        #expect(await coordinator.snapshot().activeCount == 0)
        #expect(clock.pendingSleepCount == 0)
        await coordinator.close()
    }

    /// Matching complete snapshots issue zero requests; a changed desired catalog sends exactly one destructive PUT.
    /// - Throws: Unexpected fixture/request/execution errors fail the test; no hidden reads or synchronization are permitted.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func snapshotReconciliationRequestCounts() async throws {
        let current = try ApplicationCommand(data: Data(ApplicationCommandEndpointTests.guildJSON.utf8))
        let bytes = Data(("[" + ApplicationCommandEndpointTests.guildJSON + "]").utf8)
        let transport = try ScriptedHTTPTransport(steps: [{ request in
            #expect(request.method == "PUT")
            #expect(request.url.path.hasSuffix("/guilds/3/commands"))
            await request.body?.close()
            return try Self.response(bytes)
        }])
        let clock = ManualClock(), coordinator = RateLimitCoordinator(clock: clock)
        let client = RESTClient(credential: .bearer(try BearerToken("synthetic")), identity: RateLimitIdentity(),
            transport: transport, coordinator: coordinator, clock: clock)
        let same = try BulkApplicationCommands(commands: [ApplicationCommandRegistration(command:
            ApplicationCommandCreate(name: "command", description: "description"))])
        let noOp = try ApplicationCommandOperations.bulkOverwriteIfChanged(applicationID: current.applicationID,
            guildID: .init(rawValue: 3), current: [current], request: same)
        #expect(noOp == nil)
        if let noOp { _ = try await client.execute(noOp) }
        #expect(await transport.executionCount == 0)
        let changedRequest = try BulkApplicationCommands(commands: [ApplicationCommandRegistration(command:
            ApplicationCommandCreate(name: "changed", description: "description"))])
        let changed = try #require(try ApplicationCommandOperations.bulkOverwriteIfChanged(applicationID: current.applicationID,
            guildID: .init(rawValue: 3), current: [current], request: changedRequest))
        #expect(try await client.execute(changed).first?.id == current.id)
        #expect(await transport.executionCount == 1)
        #expect(await coordinator.snapshot().activeCount == 0)
        #expect(clock.pendingSleepCount == 0)
        await coordinator.close()
    }

    /// Both new-registration 201 and name/type-upsert 200 are accepted through actual shared HTTP execution.
    /// - Parameters:
    ///   - index: Global and guild create descriptors.
    ///   - status: Each documented successful creation/overwrite status.
    /// - Throws: Unexpected execution/decoding errors fail this test.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [1, 7], [200, 201]) func creationAndOverwriteStatuses(index: Int, status: Int) async throws {
        let (endpoint, bytes) = try ApplicationCommandEndpointTests.catalog()[index]
        let transport = try ScriptedHTTPTransport(steps: [{ request in
            await request.body?.close()
            return try Self.response(bytes, status: status)
        }])
        let clock = ManualClock(), coordinator = RateLimitCoordinator(clock: clock)
        let client = RESTClient(credential: .bearer(try BearerToken("synthetic")), identity: RateLimitIdentity(),
            transport: transport, coordinator: coordinator, clock: clock)
        #expect(try await client.execute(endpoint) == bytes)
        #expect(await transport.executionCount == 1)
        #expect(await coordinator.snapshot().activeCount == 0)
        await coordinator.close()
    }

    /// Stable positions of every command and permission mutation in the 15-operation catalog.
    static let mutationIndices = [1, 3, 4, 5, 7, 9, 10, 11, 14]
    /// Stable positions of all six safe command and permission reads.
    static let readIndices = [0, 2, 6, 8, 12, 13]

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
