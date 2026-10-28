// File: Tests/DiscordCommerceTests/CommerceIntegrationTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import DiscordHTTP
import DiscordModels
import DiscordTestSupport
import DiscordTransport
import Foundation
import Testing
@testable import DiscordCommerce

/// End-to-end local HTTP-policy coverage of authoritative verification followed by unsafe consumption.
@Suite(.timeLimit(.minutes(1))) struct CommerceIntegrationTests {
    static let receipt = Data(#"{"id":"1","application_id":"2","sku_id":"3","user_id":"4","type":1,"deleted":false,"starts_at":null,"ends_at":null,"consumed":false}"#.utf8)
    static let now = try! DiscordTimestamp(rawValue: "2026-10-17T00:00:00Z")

    /// Verification and consumption issue one exact authorized server GET and POST, releasing both admission reservations.
    /// - Throws: Unexpected setup, authoritative validation or execution failures fail the test.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func verifiedConsume() async throws {
        let transport = try ScriptedHTTPTransport(steps: [
            { request in
                #expect(request.method == "GET" && request.url.path == "/api/v10/applications/2/entitlements/1")
                #expect(request.headers.contains { $0.name == "Authorization" && $0.value == "Bot synthetic" })
                return try Self.response(Self.receipt, status: 200)
            },
            { request in
                #expect(request.method == "POST" && request.url.path == "/api/v10/applications/2/entitlements/1/consume")
                #expect(request.body == nil)
                return try Self.response(Data(), status: 204)
            }
        ])
        let clock = ManualClock(), identity = RateLimitIdentity()
        let coordinator = RateLimitCoordinator(clock: clock)
        let client = RESTClient(credential: .bot(try BotToken("synthetic")), identity: identity,
            transport: transport, coordinator: coordinator, clock: clock, retryPolicy: .init(maximumAttempts: 1))
        let verified = try await EntitlementVerification.consume(entitlementID: .init(rawValue: 1), requirement: Self.policy(),
            now: { Self.now }, fetch: { try await client.execute($0) }, consume: { try await client.execute($0) })
        #expect(verified.id == EntitlementID(rawValue: 1))
        #expect(await transport.executionCount == 2)
        #expect(await coordinator.snapshot().activeCount == 0)
        #expect(await coordinator.snapshot().orderedOperationsCount == 0)
        #expect(clock.pendingSleepCount == 0)
        await coordinator.close()
    }

    /// Invalid credentials stop after the authoritative GET; a submitted consume server failure remains indeterminate with no replay.
    /// - Parameter atConsume: True acknowledges the read and rejects the mutation with HTTP 500; false rejects the read with 401.
    /// - Throws: Unexpected setup errors fail the test; exact API/uncertainty outcomes are asserted.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [false, true]) func failures(atConsume: Bool) async throws {
        var steps: [ScriptedHTTPTransport.Step] = []
        if atConsume { steps.append { _ in try Self.response(Self.receipt, status: 200) } }
        steps.append { _ in try Self.response(Data(#"{"code":0,"message":"private-commerce-detail"}"#.utf8), status: atConsume ? 500 : 401) }
        let transport = try ScriptedHTTPTransport(steps: steps)
        let clock = ManualClock()
        let coordinator = RateLimitCoordinator(clock: clock)
        let client = RESTClient(credential: .bot(try BotToken("synthetic")), identity: RateLimitIdentity(),
            transport: transport, coordinator: coordinator, clock: clock, retryPolicy: .init(maximumAttempts: 1))
        do {
            _ = try await EntitlementVerification.consume(entitlementID: .init(rawValue: 1), requirement: Self.policy(),
                now: { Self.now }, fetch: { try await client.execute($0) }, consume: { try await client.execute($0) })
            Issue.record("expected authoritative failure")
        } catch let error as APIResponseError {
            #expect(!atConsume && error.status == 401 && !String(reflecting: error).contains("private-commerce-detail"))
        } catch let error as DiscordError {
            #expect(atConsume && error == .unknownMutationOutcome(.serverErrorAfterSubmission))
        }
        #expect(await transport.executionCount == (atConsume ? 2 : 1))
        #expect(await coordinator.snapshot().activeCount == 0)
        await coordinator.close()
    }

    /// Creates the fixed user consumable requirement; tests never accept a subscription status as a grant.
    /// - Returns: Server-owned exact app 2/SKU 3/user 4 policy, without side effects.
    private static func policy() -> EntitlementRequirement {
        EntitlementRequirement(applicationID: .init(rawValue: 2), skuID: .init(rawValue: 3),
            owner: .user(.init(rawValue: 4)), consumable: true)
    }

    /// Wraps one finite synthetic response with a learned budget preventing incidental provisional throttling.
    /// - Parameters:
    ///   - bytes: Exact JSON receipt/error or empty 204 payload.
    ///   - status: Explicit response status independent of body contents.
    /// - Returns: Owned response stream consumed and closed by RESTClient.
    /// - Throws: Local fixture body validation errors, with no network I/O.
    private static func response(_ bytes: Data, status: Int) throws -> HTTPResponse {
        HTTPResponse(status: status, headers: [
            .init(name: "X-RateLimit-Limit", value: "100"), .init(name: "X-RateLimit-Remaining", value: "99"),
            .init(name: "X-RateLimit-Reset-After", value: "1")],
            body: bytes.isEmpty ? nil : try RequestBody(bytes: bytes, contentType: "application/json").makeStream())
    }
}
