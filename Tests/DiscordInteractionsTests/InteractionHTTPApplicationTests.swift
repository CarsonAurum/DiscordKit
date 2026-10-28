// File: Tests/DiscordInteractionsTests/InteractionHTTPApplicationTests.swift
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
@testable import DiscordInteractions

/// Exercises the complete signed HTTP-only composition, including early inline response and structured cleanup.
@Suite(.timeLimit(.minutes(1))) struct InteractionHTTPApplicationTests {
    /// Makes a minimal current interaction; autocomplete and commands include their required context fields.
    /// - Parameter type: Written interaction kind, default application command.
    /// - Returns: Exact fixture bytes with a synthetic nonsecret continuation token.
    static func fixture(type: Int = 2) -> Data {
        if type == 1 { return Data(#"{"id":"1","application_id":"2","type":1,"token":"test","version":1}"#.utf8) }
        return Data("""
        {"id":"1","application_id":"2","type":\(type),"token":"test","version":1,
         "data":{"id":"3","name":"ping","type":1},"app_permissions":"0","entitlements":[],
         "authorizing_integration_owners":{},"attachment_size_limit":1000}
        """.utf8)
    }

    /// Builds an application using one shared verifier and independent acknowledgement admission.
    /// - Parameter autoDefer: Optional explicit defer policy.
    /// - Returns: Idle HTTP-only application, without network or timers.
    /// - Throws: Invalid fixture limits or key errors.
    static func application(autoDefer: InteractionAutoDeferPolicy? = nil) throws -> InteractionHTTPApplication {
        try InteractionHTTPApplication(applicationID: .init(rawValue: 2),
            ingress: DiscordSignedIngress(verifier: SignedIngressTests.verifier(.allowIdenticalRetries)),
            admission: InteractionAcknowledgementAdmission(), autoDefer: autoDefer)
    }

    /// Creates an exchange with an actual Ed25519 signature over the unmodified body.
    /// - Parameters:
    ///   - bytes: Original fixture JSON or malformed bytes.
    ///   - responder: Test response owner recording exact HTTP transmission.
    /// - Returns: A signed single-use request/response pair.
    /// - Throws: Signing or stream construction errors.
    static func exchange(_ bytes: Data, responder: any HTTPResponder) throws -> HTTPExchange {
        try HTTPExchange(request: SignedIngressTests.request(bytes, fields: SignedIngressTests.headers(bytes)), responder: responder)
    }

    /// PING bypasses user handlers and yields the exact PONG callback with one reserved HTTP response.
    /// - Throws: Unexpected composition/signature/response failures fail the test.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func signedPing() async throws {
        let responder = ScriptedHTTPResponder { response in
            #expect(response.status == 200)
            #expect(response.headers.contains(HTTPHeader(name: "Content-Type", value: "application/json")))
            let bytes = try await ResponseBody.collect(response.body, maximumBytes: 100)
            #expect(try JSONValue.parse(bytes) == .object(["type": .number(try JSONNumber(rawValue: "1"))]))
        }
        try await Self.application().handle(Self.exchange(Self.fixture(type: 1), responder: responder),
            context: TransportContext(clock: ManualClock())) { _ in Issue.record("PING invoked user handler") }
        #expect(await responder.reservationCount == 1)
        #expect(await responder.completionCount == 1)
    }

    /// PONG transmission failures remain observable after the response slot is consumed; no fallback sends a second response.
    /// - Throws: Setup/signature failures fail the test; the exact injected transport failure must propagate.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func pingTransmissionFailure() async throws {
        let responder = ScriptedHTTPResponder { _ in throw TestSupportFailure.scripted("pong-send-failed") }
        await #expect(throws: TestSupportFailure.scripted("pong-send-failed")) {
            try await Self.application().handle(Self.exchange(Self.fixture(type: 1), responder: responder),
                context: TransportContext(clock: ManualClock())) { _ in Issue.record("PING invoked user handler") }
        }
        #expect(await responder.reservationCount == 1)
        #expect(await responder.completionCount == 0)
    }

    /// Unknown input, malformed JSON and wrong applications fail before handler dispatch with bounded status responses.
    /// - Parameter bytes: Authenticated but invalid/wrong-application document.
    /// - Throws: Unexpected fixture/transport errors fail the test.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [Data("bad".utf8), Data(#"{"id":"1","application_id":"99","type":1,"token":"test","version":1}"#.utf8)])
    func invalidAuthenticatedInput(bytes: Data) async throws {
        let expected = bytes.first == 98 ? 400 : 403
        let responder = ScriptedHTTPResponder { response in #expect(response.status == expected) }
        try await Self.application().handle(Self.exchange(bytes, responder: responder), context: TransportContext(clock: ManualClock())) { _ in
            Issue.record("Invalid input reached handler")
        }
        #expect(await responder.completionCount == 1)
    }

    /// Command routing receives the normalized HTTP context and immediately sends a typed reply once.
    /// - Throws: Unexpected setup/model/lifecycle errors fail the test.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func immediateReply() async throws {
        let responder = ScriptedHTTPResponder { response in
            #expect(response.status == 200)
            let payload = try JSONValue.parse(await ResponseBody.collect(response.body, maximumBytes: 1000))
            #expect(payload == .object(["type": .number(try JSONNumber(rawValue: "4")), "data": .object(["content": .string("pong")])]))
        }
        try await Self.application().handle(Self.exchange(Self.fixture(), responder: responder), context: TransportContext(clock: ManualClock())) { context in
            #expect(context.deliveryMode == .http)
            #expect(context.interaction.id.rawValue == 1)
            try await context.responder.reply(InteractionMessageCreate(content: .value("pong")))
        }
        #expect(await responder.completionCount == 1)
    }

    /// Handler failure before acknowledgement sends 500 and remains observable; no-op handlers also fail with 500.
    /// - Throws: Unexpected setup/response errors fail the test; the original handler failure is asserted.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func handlerFailureAndMissingResponse() async throws {
        for fail in [false, true] {
            let responder = ScriptedHTTPResponder { response in #expect(response.status == 500) }
            let exchange = try Self.exchange(Self.fixture(), responder: responder)
            let application = try Self.application(), context = TransportContext(clock: ManualClock())
            if fail {
                await #expect(throws: TestSupportFailure.self) {
                    try await application.handle(exchange, context: context) { _ in throw TestSupportFailure.scripted("private input") }
                }
            } else { try await application.handle(exchange, context: context) { _ in } }
            #expect(await responder.reservationCount == 1)
        }
    }

    /// Auto-defer sends before three seconds while slow handler work remains structured and explicitly owned.
    /// - Throws: Unexpected virtual-clock, signature or lifecycle errors fail the test.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func earlyInlineDeferWhileHandlerContinues() async throws {
        let timer = TestBarrier(), deferred = TestBarrier(), release = TestBarrier()
        let clock = ManualClock(onSleepScheduled: { timer.open() })
        let responder = ScriptedHTTPResponder { response in
            #expect(response.status == 200)
            let payload = try JSONValue.parse(await ResponseBody.collect(response.body, maximumBytes: 1000))
            #expect(payload == .object(["type": .number(try JSONNumber(rawValue: "5")), "data": .object(["flags": .number(try JSONNumber(rawValue: "64"))])]))
            deferred.open()
        }
        let application = try Self.application(autoDefer: .init(mode: .message(ephemeral: true)))
        let exchange = try Self.exchange(Self.fixture(), responder: responder)
        let task = Task {
            try await application.handle(exchange, context: TransportContext(clock: clock)) { context in
                try await release.wait()
                for _ in 0..<10_000 {
                    if await context.responder.snapshot() != .acknowledging { break }
                    await Task.yield()
                }
                #expect(await context.responder.snapshot() == .acknowledged(.deferredChannelMessageWithSource))
            }
        }
        try await timer.wait()
        try clock.advance(by: .seconds(2))
        try await deferred.wait()
        for _ in 0..<10_000 {
            if await responder.completionCount > 0 { break }
            await Task.yield()
        }
        #expect(await responder.completionCount == 1)
        release.open()
        try await task.value
        #expect(await responder.reservationCount == 1)
        #expect(clock.pendingSleepCount == 0)
    }

    /// An enabled auto-defer policy never starts a defer timer for autocomplete.
    /// - Throws: Unexpected fixture/response errors fail the test.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func autocompleteSkipsAutoDefer() async throws {
        let clock = ManualClock(), application = try Self.application(autoDefer: .init(mode: .message(ephemeral: true)))
        let responder = ScriptedHTTPResponder { response in
            let payload = try JSONValue.parse(await ResponseBody.collect(response.body, maximumBytes: 1000))
            #expect(payload == .object(["type": .number(try JSONNumber(rawValue: "8")), "data": .object(["choices": .array([])])]))
        }
        try await application.handle(Self.exchange(Self.fixture(type: 4), responder: responder), context: TransportContext(clock: clock)) { context in
            #expect(clock.pendingSleepCount == 0)
            try await context.responder.respond(.autocomplete([]))
        }
        #expect(await responder.completionCount == 1)
        #expect(clock.pendingSleepCount == 0)
    }
}
