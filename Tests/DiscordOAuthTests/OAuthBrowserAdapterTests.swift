// File: Tests/DiscordOAuthTests/OAuthBrowserAdapterTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import Foundation
import Testing
@testable import DiscordOAuth

/// Host UI injection tests use synthetic callbacks and never open a browser or contact Discord.
@Suite struct OAuthBrowserAdapterTests {
    /// Accepts only the fixed authorization origin and bounded syntactically valid callback schemes.
    /// - Throws: Unexpected valid-request construction failure.
    @Test func requestValidationAndRedaction() throws {
        let url = URL(string: "https://discord.com/oauth2/authorize?state=synthetic-state")!
        let request = try OAuthBrowserRequest(authorizationURL: url, callbackScheme: "discordkit.test")
        #expect(request.authorizationURL == url)
        #expect(request.callbackScheme == "discordkit.test")
        #expect(request.prefersEphemeralSession)
        #expect(!String(describing: request).contains("synthetic-state"))
        #expect(!String(reflecting: request).contains("synthetic-state"))
        #expect(Mirror(reflecting: request).children.count == 1)
        let prefix = "https://discord.com/oauth2/authorize?state="
        let maximum = URL(string: prefix + String(repeating: "x", count: 65_536 - prefix.utf8.count))!
        #expect(try OAuthBrowserRequest(authorizationURL: maximum, callbackScheme: "app").authorizationURL == maximum)
        #expect(throws: DiscordError.validation(.invalidValue)) {
            try OAuthBrowserRequest(authorizationURL: URL(string: maximum.absoluteString + "x")!, callbackScheme: "app")
        }
        for scheme in ["", "1bad", "app:", "a b", "é", String(repeating: "a", count: 129)] {
            #expect(throws: DiscordError.validation(.invalidValue)) {
                try OAuthBrowserRequest(authorizationURL: url, callbackScheme: scheme)
            }
        }
        for text in ["http://discord.com/oauth2/authorize", "https://evil.example/oauth2/authorize",
                     "https://user@discord.com/oauth2/authorize", "https://discord.com:443/oauth2/authorize",
                     "https://discord.com/oauth2/authorize#secret", "https://discord.com/api/oauth2/authorize"] {
            #expect(throws: DiscordError.validation(.invalidValue)) {
                try OAuthBrowserRequest(authorizationURL: URL(string: text)!, callbackScheme: "app")
            }
        }
    }

    /// Presents once on the main actor, passes host preferences, and consumes the flow exactly once.
    /// - Throws: Unexpected flow or callback failure; all values are synthetic.
    @Test func browserCallbackUsesFlowValidation() async throws {
        let flow = try makeFlow()
        let adapter = OAuthBrowserAdapter { request in
            MainActor.assertIsolated()
            #expect(request.callbackScheme == "discord-1")
            #expect(!request.prefersEphemeralSession)
            return URL(string: "discord-1:/authorize/callback?code=synthetic-code&state=synthetic-state-0123456789abcdef&iss=https%3A%2F%2Fdiscord.com")!
        }
        let result = try await adapter.authorize(flow: flow, callbackScheme: "discord-1", prefersEphemeralSession: false)
        guard case .code = result else { Issue.record("Expected an authorization code"); return }
        await #expect(throws: (any Error).self) {
            try await adapter.authorize(flow: flow, callbackScheme: "discord-1", prefersEphemeralSession: false)
        }
    }

    /// Arbitrary OS failures are sanitized, cancellation stays typed, and neither consumes callback ownership.
    /// - Throws: Unexpected fixture construction failure.
    @Test func hostErrorsAndCancellationAreSafe() async throws {
        let flow = try makeFlow()
        let failed = OAuthBrowserAdapter { _ in throw URLError(.badURL, userInfo: [NSURLErrorFailingURLStringErrorKey: "secret"]) }
        await #expect(throws: OAuthBrowserFailure.presentationFailed) {
            try await failed.authorize(flow: flow, callbackScheme: "discord-1")
        }
        await #expect(throws: DiscordError.validation(.invalidValue)) {
            try await failed.authorize(flow: flow, callbackScheme: "wrong-scheme")
        }
        let cancelled = OAuthBrowserAdapter { _ in throw CancellationError() }
        await #expect(throws: CancellationError.self) {
            try await cancelled.authorize(flow: flow, callbackScheme: "discord-1")
        }
        let operation = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await cancelled.authorize(flow: flow, callbackScheme: "discord-1")
        }
        await #expect(throws: CancellationError.self) { try await operation.value }
        let cancelledAfterPresentation = OAuthBrowserAdapter { _ in
            withUnsafeCurrentTask { $0?.cancel() }
            return URL(string: "discord-1:/authorize/callback?code=synthetic-code&state=synthetic-state-0123456789abcdef&iss=https%3A%2F%2Fdiscord.com")!
        }
        let lateCancellation = Task {
            try await cancelledAfterPresentation.authorize(flow: flow, callbackScheme: "discord-1")
        }
        await #expect(throws: CancellationError.self) { try await lateCancellation.value }
    }

    /// Creates a deterministic code flow for host callback tests without generating live credentials.
    /// - Returns: Idle one-use flow bound to the synthetic redirect and state.
    /// - Throws: Flow validation errors if the fixture becomes invalid.
    private func makeFlow() throws -> OAuthAuthorizationFlow {
        try OAuthAuthorizationFlow(clientID: ApplicationID(rawValue: 1),
            redirectURI: URL(string: "discord-1:/authorize/callback")!, scopes: ["identify"],
            state: "synthetic-state-0123456789abcdef")
    }
}
