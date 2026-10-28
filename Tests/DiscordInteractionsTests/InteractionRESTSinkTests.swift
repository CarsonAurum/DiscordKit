// File: Tests/DiscordInteractionsTests/InteractionRESTSinkTests.swift
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
import DiscordInteractions

/// Executes normalized interaction response ownership through the existing real REST policy pipeline.
@Suite(.timeLimit(.minutes(1))) struct InteractionRESTSinkTests {
    /// Gateway receipt sends initial callbacks through dedicated HTTP admission and subsequent mutations through
    /// a different coordinator, preserving path credentials, no Authorization header and typed decoded messages.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func gatewayHTTPResponseAndContinuation() async throws {
        let clock = ManualClock(), input = try InteractionLifecycleTests.interaction()
        let initialTransport = try ScriptedHTTPTransport(steps: [{ request in
            #expect(request.method == "POST")
            #expect(request.url.path == "/api/v10/interactions/18446744073709551615/test-token/callback")
            #expect(!request.headers.contains { $0.name.lowercased() == "authorization" })
            #expect(try JSONValue.parse(await ResponseBody.collect(request.body, maximumBytes: 1024)) ==
                .object(["type": .number(JSONNumber(rawValue: "5")), "data": .object(["flags": .number(JSONNumber(rawValue: "64"))])]))
            return try HTTPResponse(status: 204)
        }])
        let responseBytes = Data(InteractionLifecycleTests.messageJSON.utf8)
        let continuationTransport = try ScriptedHTTPTransport(steps: [
            { request in
                #expect(request.method == "PATCH")
                #expect(request.url.path == "/api/v10/webhooks/9/test-token/messages/@original")
                #expect(!request.headers.contains { $0.name.lowercased() == "authorization" })
                let body = try await ResponseBody.collect(request.body, maximumBytes: 1024)
                #expect(try JSONValue.parse(body) == .object(["content": .string("done")]))
                return try Self.response(responseBytes)
            },
            { request in
                #expect(request.method == "POST")
                #expect(request.url.path == "/api/v10/webhooks/9/test-token")
                let body = try await ResponseBody.collect(request.body, maximumBytes: 1024)
                #expect(try JSONValue.parse(body) == .object(["content": .string("followup")]))
                return try Self.response(responseBytes)
            },
            { request in
                #expect(request.method == "DELETE")
                #expect(request.url.path == "/api/v10/webhooks/9/test-token/messages/@original")
                return try HTTPResponse(status: 204)
            },
        ])
        let initialCoordinator = RateLimitCoordinator(clock: clock), continuationCoordinator = RateLimitCoordinator(clock: clock)
        let identity = RateLimitIdentity()
        let initial = RESTClient(credential: .interaction(input.token), identity: identity,
            transport: initialTransport, coordinator: initialCoordinator, clock: clock, retryPolicy: .init(maximumAttempts: 1))
        let continuation = RESTClient(credential: .interaction(input.token), identity: identity,
            transport: continuationTransport, coordinator: continuationCoordinator, clock: clock, retryPolicy: .init(maximumAttempts: 1))
        let responder = InteractionResponder(interaction: input, deliveryMode: .gateway, clock: InteractionClock(clock),
            sink: .rest(interaction: input, initialClient: initial, continuationClient: continuation, clock: clock),
            admission: try InteractionAcknowledgementAdmission())
        try await responder.deferResponse(ephemeral: true)
        #expect(await initialTransport.executionCount == 1)
        #expect(await continuationTransport.executionCount == 0)
        #expect(try await responder.editOriginal(InteractionMessageEdit(content: .value("done"))).id.rawValue == UInt64.max)
        #expect(try await responder.followup(InteractionMessageCreate(content: .value("followup"))).content == "response")
        try await responder.deleteOriginal()
        #expect(await initialTransport.executionCount == 1)
        #expect(await continuationTransport.executionCount == 3)
        #expect(await initialCoordinator.snapshot().activeCount == 0)
        #expect(await continuationCoordinator.snapshot().activeCount == 0)
        #expect(clock.pendingSleepCount == 0)
        await initialCoordinator.close(); await continuationCoordinator.close()
    }

    /// REST 4xx rejection reopens the local initial slot while 5xx/connection loss remain explicitly indeterminate.
    /// - Parameter status: Definitive API rejection or ambiguous server response; zero injects transport loss.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [400, 500, 0]) func initialRESTFailures(status: Int) async throws {
        let clock = ManualClock(), input = try InteractionLifecycleTests.interaction()
        let transport = try ScriptedHTTPTransport(steps: [{ request in
            await request.body?.close()
            if status == 0 { throw DiscordError.transport(.disconnected) }
            return try Self.response(Data(#"{"code":50035}"#.utf8), status: status)
        }])
        let coordinator = RateLimitCoordinator(clock: clock)
        let client = RESTClient(credential: .interaction(input.token), identity: RateLimitIdentity(),
            transport: transport, coordinator: coordinator, clock: clock, retryPolicy: .init(maximumAttempts: 1))
        let responder = InteractionResponder(interaction: input, deliveryMode: .gateway, clock: InteractionClock(clock),
            sink: .rest(interaction: input, initialClient: client, continuationClient: client, clock: clock),
            admission: try InteractionAcknowledgementAdmission())
        await #expect(throws: (any Error).self) { try await responder.deferResponse() }
        #expect(await responder.snapshot() == (status == 400 ? .pending : .indeterminate))
        #expect(await transport.executionCount == 1)
        #expect(clock.pendingSleepCount == 0)
        await coordinator.close()
    }

    /// Builds a finite owned response body with generous explicit bucket metadata so virtual time never advances implicitly.
    /// - Parameters:
    ///   - bytes: Complete scripted JSON response, bounded by RequestBody's fixture size limit.
    ///   - status: HTTP response status, default success 200.
    /// - Returns: Independently owned body closed by the REST execution pipeline.
    /// - Throws: Request-body or stream validation errors for invalid fixtures.
    static func response(_ bytes: Data, status: Int = 200) throws -> HTTPResponse {
        HTTPResponse(status: status, headers: [.init(name: "X-RateLimit-Limit", value: "100"),
            .init(name: "X-RateLimit-Remaining", value: "99"), .init(name: "X-RateLimit-Reset-After", value: "1")],
            body: try RequestBody(bytes: bytes, contentType: "application/json").makeStream())
    }
}
