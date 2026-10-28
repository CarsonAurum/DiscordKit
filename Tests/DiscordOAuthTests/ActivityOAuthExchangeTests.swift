// File: Tests/DiscordOAuthTests/ActivityOAuthExchangeTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import DiscordHTTP
import DiscordOAuth
import Foundation
import Testing

/// Offline Activity-specific backend code exchange; no iframe, credentials or live Discord requests are used.
@Suite struct ActivityOAuthExchangeTests {
    /// Verifies the documented confidential form, secret redaction, single escaping and optional S256 proof.
    @Test func confidentialExchange() throws {
        let authentication = OAuthClientAuthentication.confidential(clientID: .init(rawValue: .max), secret: try ClientSecret("server+secret"))
        let endpoint = try OAuthEndpoints.activityAuthorizationCode(OAuthCode("one+code&secret"), authentication: authentication)
        let form = String(decoding: try #require(endpoint.body).bytes, as: UTF8.self)
        #expect(endpoint.method == "POST" && endpoint.successStatuses == [200])
        #expect(form.contains("code=one%2Bcode%26secret") && form.contains("client_secret=server%2Bsecret"))
        #expect(form.contains("client_id=18446744073709551615") && form.contains("grant_type=authorization_code"))
        #expect(!form.contains("redirect_uri") && !form.contains("code_verifier"))
        #expect(!String(reflecting: endpoint).contains("server+secret"))
        let proof = try OAuthPKCE(verifier: String(repeating: "a", count: 43))
        let protected = try OAuthEndpoints.activityAuthorizationCode(OAuthCode("code"), authentication: authentication, pkceVerifier: proof.verifier)
        #expect(String(decoding: try #require(protected.body).bytes, as: UTF8.self).contains("code_verifier=" + String(repeating: "a", count: 43)))
        let response = try endpoint.decode(Data("{\"access_token\":\"synthetic\",\"token_type\":\"Bearer\",\"expires_in\":60,\"scope\":\"identify\"}".utf8))
        #expect(response.scopes == ["identify"])
    }

    /// Rejects public clients, zero application IDs, malformed proof keys and oversized codes before submission.
    @Test func invalidBackendInput() throws {
        #expect(throws: OAuthError.unsupportedClient) { try OAuthEndpoints.activityAuthorizationCode(OAuthCode("code"), authentication: .publicPKCE(clientID: .init(rawValue: 1))) }
        #expect(throws: OAuthError.invalidRequest) { try OAuthEndpoints.activityAuthorizationCode(OAuthCode("code"), authentication: .confidential(clientID: .init(rawValue: 0), secret: ClientSecret("secret"))) }
        let authentication = OAuthClientAuthentication.confidential(clientID: .init(rawValue: 1), secret: try ClientSecret("secret"))
        #expect(throws: OAuthError.invalidRequest) { try OAuthEndpoints.activityAuthorizationCode(OAuthCode("code"), authentication: authentication, pkceVerifier: OAuthPKCEVerifier("short")) }
        #expect(throws: OAuthError.invalidRequest) { try OAuthEndpoints.activityAuthorizationCode(OAuthCode(String(repeating: "x", count: 8_193)), authentication: authentication) }
    }
}
