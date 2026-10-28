// File: Tests/DiscordInteractionsTests/IngressLoggingTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordHTTP
import DiscordLogging
import DiscordTestSupport
import DiscordTransport
import Foundation
import Testing
@testable import DiscordInteractions

/// Signed ingress captures operational events while retaining exact-byte authentication ownership.
@Suite struct IngressLoggingTests {
    /// Unverified requests disclose only a static rejection event, with no headers, body or URL.
    /// - Throws: Unexpected cryptographic fixture, body, or request execution failure.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func rejectedSignatureDoesNotLogSubmittedData() async throws {
        let recorder = LogRecorder()
        let ingress = try DiscordLog.$loggerFactory.withValue({ recorder.makeLogger($0) }) {
            try DiscordSignedIngress(verifier: SignedIngressTests.verifier())
        }
        #expect(recorder.entries.isEmpty)
        let secret = "private_header_body_url"
        let request = HTTPRequest(method: "POST", url: try #require(URL(string: "https://example.invalid/\(secret)")),
            headers: [.init(name: "Authorization", value: secret)],
            body: try RequestBody(bytes: Data(secret.utf8), contentType: "application/json").makeStream())
        let response = try await DiscordLog.$loggerFactory.withValue({ recorder.makeLogger($0) }) {
            try await ingress.process(request: request, context: TransportContext(clock: ManualClock())) { _ in
                Issue.record("Unverified request reached handler")
                return HTTPResponse(status: 204)
            }
        }
        #expect(response.status == 401)
        #expect(await ingress.activeRequestCount() == 0)
        #expect(recorder.entries.contains { $0.level == .debug && $0.metadata["dk.event"] == "interactions.ingress.rejected" })
        let events = recorder.entries.compactMap { $0.metadata["dk.event"]?.description }
        #expect(events == ["interactions.ingress.started", "interactions.ingress.admitted",
            "interactions.ingress.headers_validated", "interactions.ingress.body_reading",
            "interactions.ingress.body_read", "interactions.ingress.verifying",
            "interactions.ingress.cleanup_started", "interactions.ingress.cleanup_completed",
            "interactions.ingress.rejected", "interactions.ingress.released"])
        #expect(recorder.entries.last?.metadata["dk.active"]?.description == "0")
        #expect(!String(describing: recorder.entries.map { ($0.message, $0.metadata) }).contains(secret))
        #expect(recorder.entries.allSatisfy { $0.label == "discordkit.interactions.ingress" })
    }
}
