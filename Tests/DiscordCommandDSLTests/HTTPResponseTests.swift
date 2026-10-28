// File: Tests/DiscordCommandDSLTests/HTTPResponseTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import Crypto
import DiscordCommandDSL
import DiscordCore
import DiscordDSL
import DiscordHTTP
import DiscordInteractions
import DiscordModels
import DiscordTestSupport
import DiscordTransport
import Foundation
import Testing

/// Deferred typed routes retain ordered response ownership through the complete signed HTTP application.
@Suite struct HTTPResponseTests {
    /// A signed typed command confirms inline defer before work and edits the original through an injected sink.
    /// Missing edit configuration propagates after the one confirmed defer, without retry or another HTTP response.
    /// - Parameter continuation: True injects an original-edit sink; false exercises explicit missing configuration.
    /// - Throws: Unexpected setup errors fail; a missing continuation capability is asserted precisely.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [false, true]) func signedDeferredCommand(continuation: Bool) async throws {
        let events = HTTPResponseEvents()
        let commands = try CommandCompilation.compile(SlashCommand(id: "ping", handler: HTTPDeferredPing(events: events)))
        let key = try Curve25519.Signing.PrivateKey(rawRepresentation: Data(repeating: 9, count: 32))
        let app = try CommandApplication(applicationID: .init(rawValue: 2), commands: commands,
            ingress: DiscordSignedIngress(verifier: SignedRequestVerifier(publicKey: ApplicationTests.hex(key.publicKey.rawRepresentation), now: { 1000 })),
            admission: InteractionAcknowledgementAdmission())
        let response = ScriptedHTTPResponder { response in
            #expect(response.status == 200)
            let bytes = try await ResponseBody.collect(response.body, maximumBytes: 1000)
            #expect(try JSONValue.parse(bytes) == JSONValue.parse(Data(#"{"type":5,"data":{"flags":64}}"#.utf8)))
            await events.append("defer")
        }
        let sink = InteractionResponseSink(initial: { _, _ in Issue.record("Continuation initial closure must be replaced by HTTP") },
            editOriginal: { edit, timeout in
                #expect(timeout > .zero && timeout <= .seconds(900))
                #expect(try edit.jsonValue() == .object(["content": .string("done")]))
                await events.append("edit")
                return try Message(data: Data(#"{"id":"1","channel_id":"2","author":{"id":"3","username":"fixture","discriminator":"0","avatar":null},"content":"done","timestamp":"2026-10-18T00:00:00Z","edited_timestamp":null,"tts":false,"mention_everyone":false,"mentions":[],"mention_roles":[],"attachments":[],"embeds":[],"pinned":false,"type":0}"#.utf8))
            })
        let exchange = try ApplicationTests.exchange(ApplicationTests.bytes(), responder: response)
        let clock = ManualClock()
        if continuation {
            try await app.handle(exchange, context: TransportContext(clock: clock), continuations: { _ in sink })
            #expect(await events.values == ["defer", "work", "edit"])
        } else {
            await #expect(throws: DiscordError.capabilityUnavailable(.missingConfiguration)) {
                try await app.handle(exchange, context: TransportContext(clock: clock))
            }
            #expect(await events.values == ["defer", "work"])
        }
        #expect(await response.reservationCount == 1)
        #expect(await response.completionCount == 1)
        #expect(clock.pendingSleepCount == 0)
    }
}

/// Empty handwritten arguments keep HTTP response testing independent of compiler plugins.
private struct HTTPEmptyArguments: CommandArguments {
    static var schema: CommandArgumentSchema<Self> {
        /// Validates the zero-option contract and constructs fresh empty values after full decoding.
        /// - Returns: Inert finite schema with no defaults or submitted values retained.
        /// - Throws: Unexpected schema initialization errors.
        get throws { try CommandArgumentSchema(options: []) { _ in Self() } }
    }
}

/// Deferred command whose event observation proves work starts after inline acknowledgement completes.
private struct HTTPDeferredPing: DeferredSlashCommandHandler {
    typealias Arguments = HTTPEmptyArguments
    let events: HTTPResponseEvents
    /// Matches the synthetic root slash envelope without performing registration or user work.
    var command: SlashCommandMetadata { .init(name: "ping", description: "Check deferred HTTP ownership") }
    /// Fixes the initial loading response to ephemeral before the test records handler execution.
    var responseVisibility: CommandResponseVisibility { .ephemeral }

    /// Records user work and produces one original edit without direct response authority.
    /// - Parameters:
    ///   - context: Typed authenticated snapshot; responder access is unavailable.
    ///   - arguments: Fresh validated empty arguments.
    /// - Returns: The sole original-message completion edit.
    /// - Throws: Existing edit model validation errors.
    func execute(_ context: DeferredCommandContext, arguments: Arguments) async throws -> DeferredMessageResponse {
        await events.append("work")
        return try DeferredMessageResponse(InteractionMessageEdit(content: .value("done")))
    }
}

/// Serializes three finite test markers so event assertions do not rely on task scheduling delays.
private actor HTTPResponseEvents {
    private(set) var values: [String] = []

    /// Adds one nonsecret known event in observed actor admission order.
    /// - Parameter value: Fixed defer/work/edit marker.
    func append(_ value: String) { values.append(value) }
}
