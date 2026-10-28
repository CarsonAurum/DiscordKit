// File: Tests/DiscordOAuthTests/AuthorizationFlowTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import Foundation
import Testing
@testable import DiscordOAuth

/// Deterministic browser-flow tests use synthetic callbacks and RFC fixtures without launching UI or network work.
@Suite struct OAuthAuthorizationFlowTests {
    /// Confirms RFC 7636 Appendix B S256 output, generated verifier bounds and redacted descriptions/reflection.
    @Test func proofKeyVectorAndGeneration() throws {
        let proof = try OAuthPKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        #expect(proof.challenge == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        #expect(proof.verifier.withUnsafeValue { $0 } == "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        let generated = OAuthPKCE.generate()
        #expect(generated.verifier.withUnsafeValue { $0.utf8.count } == 43)
        #expect(generated.challenge.utf8.count == 43)
        #expect(!generated.challenge.contains("="))
        #expect(generated.challenge != OAuthPKCE.generate().challenge)
        #expect(String(describing: proof) == "OAuthPKCE(redacted)")
        #expect(String(reflecting: proof) == "OAuthPKCE(redacted)")
        #expect(proof.customMirror.children.count == 1)
        #expect(throws: OAuthError.invalidRequest) { try OAuthPKCE(verifier: String(repeating: "x", count: 42)) }
        #expect(throws: OAuthError.invalidRequest) { try OAuthPKCE(verifier: String(repeating: "x", count: 129)) }
        #expect(throws: OAuthError.invalidRequest) { try OAuthPKCE(verifier: String(repeating: "x", count: 42) + "+") }
        #expect(throws: OAuthError.invalidRequest) { try OAuthPKCE(verifier: String(repeating: "x", count: 42) + "é") }
        _ = try OAuthPKCE(verifier: String(repeating: "~", count: 128))
    }

    /// Checks sorted scopes, fresh default nonces, install metadata, safe origin and one validated code result.
    @Test func codeAuthorizationAndSingleUse() async throws {
        let flow = try OAuthAuthorizationFlow(clientID: ApplicationID(rawValue: .max), redirectURI: redirect(),
            scopes: ["identify", "bot", "applications.commands"], state: nonce,
            installationContext: .guild, prompt: .consent, permissions: "18446744073709551616",
            guildID: GuildID(rawValue: .max), disableGuildSelection: true)
        let query = try #require(URLComponents(url: flow.authorizationURL, resolvingAgainstBaseURL: false)?.queryItems)
        let values = Dictionary(uniqueKeysWithValues: query.map { ($0.name, $0.value ?? "") })
        #expect(flow.authorizationURL.host == "discord.com")
        #expect(flow.authorizationURL.path == "/oauth2/authorize")
        #expect(values["client_id"] == "18446744073709551615")
        #expect(values["scope"] == "applications.commands bot identify")
        #expect(values["code_challenge_method"] == "S256")
        #expect(values["integration_type"] == "0")
        #expect(values["guild_id"] == "18446744073709551615")
        #expect(values["disable_guild_select"] == "true")
        #expect(values["prompt"] == "consent")
        #expect(values["permissions"] == "18446744073709551616")
        let result = try await flow.consumeCallback(callback())
        guard case .code(let code) = result else { Issue.record("Expected code result"); return }
        #expect(code.code.withUnsafeValue { $0 } == "synthetic_code")
        #expect(code.redirectURI == flow.redirectURI)
        #expect(code.clientID.rawValue == .max)
        #expect(!String(reflecting: code).contains("synthetic_code"))
        #expect(code.description == "OAuthAuthorizationCode(redacted)")
        #expect(code.customMirror.children.count == 1)
        await #expect(throws: OAuthError.alreadyConsumed) { try await flow.consumeCallback(callback()) }
        #expect(flow.description == "OAuthAuthorizationFlow(redacted)")
        #expect(flow.debugDescription == flow.description)
        #expect(flow.customMirror.children.count == 1)
        let first = try OAuthAuthorizationFlow(clientID: .init(rawValue: 1), redirectURI: redirect(), scopes: ["identify"])
        let second = try OAuthAuthorizationFlow(clientID: .init(rawValue: 1), redirectURI: redirect(), scopes: ["identify"])
        #expect(first.authorizationURL != second.authorizationURL)
    }

    /// Rejects mismatched origin/path/registered query, issuer/state and duplicate fields without trusting extra hints.
    /// - Parameters:
    ///   - suffix: Deliberately invalid callback query or fragment.
    ///   - expected: Closed expected error category.
    @Test(arguments: [
        ("?code=x&state=wrong&iss=https%3A%2F%2Fdiscord.com", OAuthError.invalidState),
        ("?code=x&iss=https%3A%2F%2Fdiscord.com", .invalidState),
        ("?code=x&state=0123456789abcdefghijklmnopqrstuv", .invalidIssuer),
        ("?code=x&state=0123456789abcdefghijklmnopqrstuv&iss=https%3A%2F%2Fevil.example", .invalidIssuer),
        ("?code=x&code=y&state=0123456789abcdefghijklmnopqrstuv&iss=https%3A%2F%2Fdiscord.com", .malformedResponse),
        ("?code=x&state=0123456789abcdefghijklmnopqrstuv&%73tate=z&iss=https%3A%2F%2Fdiscord.com", .malformedResponse),
        ("?code=x&state=0123456789abcdefghijklmnopqrstuv&iss=https%3A%2F%2Fdiscord.com#access_token=x", .invalidRedirect)
    ]) func rejectedCallbacks(suffix: String, expected: OAuthError) async throws {
        let flow = try basicFlow()
        let url = try #require(URL(string: "https://example.com/callback" + suffix))
        await #expect(throws: expected) { try await flow.consumeCallback(url) }
        guard case .code = try await flow.consumeCallback(callback()) else { Issue.record("Valid recovery callback failed"); return }
    }

    /// Binds query-bearing redirects exactly and consumes authenticated denials/malformed successes once.
    @Test func registeredQueryDenialAndMalformedSuccess() async throws {
        let flow = try OAuthAuthorizationFlow(clientID: .init(rawValue: 1), redirectURI: redirect("https://example.com/callback?tenant=a%2Bb"), scopes: ["identify"], state: nonce)
        await #expect(throws: OAuthError.invalidRedirect) { try await flow.consumeCallback(callback()) }
        let good = redirect("https://example.com/callback?tenant=a%2Bb&code=x&state=\(nonce)&iss=https%3A%2F%2Fdiscord.com")
        guard case .code = try await flow.consumeCallback(good) else { Issue.record("Query-bound redirect failed"); return }
        let literalPlus = try OAuthAuthorizationFlow(clientID: .init(rawValue: 1), redirectURI: redirect("https://example.com/callback?tenant=a+b"), scopes: ["future+scope"], state: nonce)
        #expect(literalPlus.authorizationURL.absoluteString.contains("future%2Bscope"))
        #expect(literalPlus.authorizationURL.absoluteString.contains("tenant%3Da%2Bb"))
        let denial = try basicFlow()
        await #expect(throws: OAuthError.accessDenied) { try await denial.consumeCallback(callback(fields: "error=access_denied&error_description=synthetic_secret")) }
        await #expect(throws: OAuthError.alreadyConsumed) { try await denial.consumeCallback(callback()) }
        let unknown = try basicFlow()
        await #expect(throws: OAuthError.authorizationFailed) { try await unknown.consumeCallback(callback(fields: "error=unknown_secret")) }
        let missing = try basicFlow()
        await #expect(throws: OAuthError.malformedResponse) { try await missing.consumeCallback(callback(fields: "guild_id=1")) }
        await #expect(throws: OAuthError.alreadyConsumed) { try await missing.consumeCallback(callback()) }
        for value in ["https://evil.example/callback", "https://example.com/other", "https://example.com:443/callback", "https://example.com/callback/"] {
            let invalid = try basicFlow()
            await #expect(throws: OAuthError.invalidRedirect) { try await invalid.consumeCallback(callback(base: value)) }
        }
    }

    /// Exercises explicit implicit compatibility, required fragments, refresh omission and legacy scope restrictions.
    @Test func implicitCompatibility() async throws {
        let flow = try OAuthAuthorizationFlow(clientID: .init(rawValue: 1), redirectURI: redirect(), scopes: ["identify"], mode: .implicitCompatibility, state: nonce)
        let fragment = "access_token=synthetic_token&token_type=Bearer&expires_in=30&scope=identify&state=\(nonce)&iss=https%3A%2F%2Fdiscord.com"
        await #expect(throws: OAuthError.invalidRedirect) { try await flow.consumeCallback(redirect("https://example.com/callback?" + fragment)) }
        let result = try await flow.consumeCallback(redirect("https://example.com/callback#" + fragment))
        guard case .implicit(let token) = result else { Issue.record("Expected implicit token"); return }
        #expect(token.accessToken.withUnsafeValue { $0 } == "synthetic_token")
        #expect(token.refreshToken == nil)
        #expect(token.expiresIn == 30)
        #expect(token.scopes == ["identify"])
        #expect(!flow.authorizationURL.absoluteString.contains("code_challenge"))
        #expect(throws: OAuthError.invalidRequest) { try OAuthAuthorizationFlow(clientID: .init(rawValue: 1), redirectURI: redirect(), scopes: ["role_connections.write"], mode: .implicitCompatibility) }
        #expect(throws: OAuthError.invalidRequest) { try OAuthAuthorizationFlow(clientID: .init(rawValue: 1), redirectURI: redirect(), scopes: ["identify"], mode: .implicitCompatibility, pkce: .generate()) }
    }

    /// Rejects malformed local inputs before browser use, preserving public-client native and loopback redirects.
    @Test func inputValidationAndScopeMetadata() throws {
        for url in ["http://example.com/callback", "https://user:password@example.com/callback", "https://example.com/callback#fragment", "file:///callback", "discord-2:/authorize/callback", "https://example.com/callback?state=existing"] {
            #expect(throws: OAuthError.invalidRedirect) { try OAuthAuthorizationFlow(clientID: .init(rawValue: 1), redirectURI: redirect(url), scopes: ["identify"]) }
        }
        for url in ["http://127.0.0.1:54321/callback", "http://[::1]:54321/callback", "discord-1:/authorize/callback"] {
            _ = try OAuthAuthorizationFlow(clientID: .init(rawValue: 1), redirectURI: redirect(url), scopes: ["identify"])
        }
        let invalidScopes: [Set<String>] = [[], ["identify email"], ["quote\""], ["back\\slash"], [String(repeating: "x", count: 257)]]
        for scopes in invalidScopes {
            #expect(throws: OAuthError.invalidRequest) { try OAuthAuthorizationFlow(clientID: .init(rawValue: 1), redirectURI: redirect(), scopes: scopes) }
        }
        #expect(throws: OAuthError.invalidRequest) { try OAuthAuthorizationFlow(clientID: .init(rawValue: 0), redirectURI: redirect(), scopes: ["identify"]) }
        #expect(throws: OAuthError.invalidRequest) { try OAuthAuthorizationFlow(clientID: .init(rawValue: 1), redirectURI: redirect(), scopes: ["identify"], state: "short") }
        #expect(throws: OAuthError.invalidRequest) { try OAuthAuthorizationFlow(clientID: .init(rawValue: 1), redirectURI: redirect(), scopes: ["identify"], installationContext: .guild) }
        #expect(throws: OAuthError.invalidRequest) { try OAuthAuthorizationFlow(clientID: .init(rawValue: 1), redirectURI: redirect(), scopes: ["applications.commands", "bot"], installationContext: .user) }
        #expect(throws: OAuthError.invalidRequest) { try OAuthAuthorizationFlow(clientID: .init(rawValue: 1), redirectURI: redirect(), scopes: ["identify"], permissions: "1") }
        #expect(throws: OAuthError.invalidRequest) { try OAuthAuthorizationFlow(clientID: .init(rawValue: 1), redirectURI: redirect(), scopes: ["bot"], permissions: "-1") }
        #expect(throws: OAuthError.invalidRequest) { try OAuthAuthorizationFlow(clientID: .init(rawValue: 1), redirectURI: redirect(), scopes: ["bot"], disableGuildSelection: true) }
        #expect(OAuthScopeAvailability.classify("identify") == .ordinary)
        #expect(OAuthScopeAvailability.classify("openid") == .ordinary)
        #expect(OAuthScopeAvailability.classify("sdk.social_layer_presence") == .ordinary)
        #expect(OAuthScopeAvailability.classify("sdk.social_layer") == .approvalRequired)
        #expect(OAuthScopeAvailability.classify("voice") == .approvalRequired)
        #expect(OAuthScopeAvailability.classify("activities.read") == .unavailable)
        #expect(OAuthScopeAvailability.classify("future.scope") == .unknown)
        _ = try OAuthAuthorizationFlow(clientID: .init(rawValue: 1), redirectURI: redirect(), scopes: ["future.scope", "applications.commands"], installationContext: .user, prompt: OAuthPrompt.none)
    }

    /// Concurrent callbacks admit exactly one caller; a cancelled caller cannot consume an otherwise valid flow.
    @Test func concurrentAndCancelledCallbacks() async throws {
        let flow = try basicFlow()
        let accepted = await withTaskGroup(of: Bool.self, returning: Int.self) { group in
            for _ in 0..<20 { group.addTask { (try? await flow.consumeCallback(callback())) != nil } }
            var accepted = 0
            for await result in group where result { accepted += 1 }
            return accepted
        }
        #expect(accepted == 1)
        let cancelledFlow = try basicFlow()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await cancelledFlow.consumeCallback(callback())
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        _ = try await cancelledFlow.consumeCallback(callback())
    }
}

/// Stable synthetic state sufficient for deterministic checks; never used in a live authorization.
private let nonce = "0123456789abcdefghijklmnopqrstuv"

/// Creates a known-good synthetic redirect URL, failing the test rather than invoking network work.
/// - Parameter value: Absolute literal URL, defaulting to a synthetic HTTPS callback.
/// - Returns: The parsed URL.
private func redirect(_ value: String = "https://example.com/callback") -> URL { URL(string: value)! }

/// Creates one deterministic code flow with a fixed test-only nonce.
/// - Returns: Fresh actor with an unconsumed callback state.
/// - Throws: Unexpected validation failures for the fixed valid inputs.
private func basicFlow() throws -> OAuthAuthorizationFlow {
    try OAuthAuthorizationFlow(clientID: .init(rawValue: 1), redirectURI: redirect(), scopes: ["identify"], state: nonce)
}

/// Appends an authenticated synthetic callback payload to a callback origin.
/// - Parameters:
///   - fields: Code/error payload, defaulting to a nonempty test code.
///   - base: Callback URI used for origin/path mismatch checks.
/// - Returns: URL carrying known state and issuer; its secrets are test-only.
private func callback(fields: String = "code=synthetic_code", base: String = "https://example.com/callback") -> URL {
    redirect(base + "?" + fields + "&state=\(nonce)&iss=https%3A%2F%2Fdiscord.com")
}
