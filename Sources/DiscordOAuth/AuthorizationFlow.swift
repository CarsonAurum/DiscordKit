// File: Sources/DiscordOAuth/AuthorizationFlow.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import Crypto
import DiscordCore
import Foundation

/// Closed OAuth failure categories. Untrusted descriptions, codes, URLs and tokens are never retained.
public enum OAuthError: String, Error, Sendable, Equatable {
    case invalidGrant, accessDenied, invalidState, invalidRedirect, invalidIssuer
    case malformedResponse, invalidRequest, unsupportedClient, authorizationFailed, alreadyConsumed
}

/// Marks a refresh token, which cannot be substituted for an access token.
public enum OAuthRefreshTokenTag: Sendable {}
/// A refresh credential whose ordinary formatting and reflection conceal its contents.
public typealias OAuthRefreshToken = Secret<OAuthRefreshTokenTag>
/// Marks a one-use authorization code received after redirect and state validation.
public enum OAuthAuthorizationCodeTag: Sendable {}
/// A redacted authorization-code value, unsuitable for bearer authentication.
public typealias OAuthCode = Secret<OAuthAuthorizationCodeTag>
/// Marks an RFC 7636 proof-key verifier.
public enum OAuthPKCEVerifierTag: Sendable {}
/// A redacted verifier. `OAuthPKCE` additionally enforces the RFC's syntax and size requirements.
public typealias OAuthPKCEVerifier = Secret<OAuthPKCEVerifierTag>

/// An RFC 7636 S256 verifier/challenge pair; there is no downgrade to the plain method.
public struct OAuthPKCE: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let verifier: OAuthPKCEVerifier
    public let challenge: String

    /// Validates a caller-owned high-entropy verifier and computes its unpadded base64url SHA-256 challenge.
    /// - Parameter verifier: Exactly 43...128 ASCII unreserved characters; callers must supply fresh randomness.
    /// - Throws: `OAuthError.invalidRequest` for invalid syntax or length. This does not verify entropy.
    public init(verifier: String) throws {
        guard (43...128).contains(verifier.utf8.count), verifier.utf8.allSatisfy({ byte in
            (65...90).contains(byte) || (97...122).contains(byte) || (48...57).contains(byte) || [45, 46, 95, 126].contains(byte)
        }) else { throw OAuthError.invalidRequest }
        self.verifier = try OAuthPKCEVerifier(verifier)
        challenge = oauthBase64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    /// Generates a fresh 256-bit verifier using the operating system's system random generator.
    /// - Returns: An S256 pair with a 43-character verifier. No tasks, persistence or I/O ownership begins.
    public static func generate() -> Self {
        // A 32-byte unpadded base64url string always satisfies the initializer's checked grammar.
        try! Self(verifier: oauthRandomNonce())
    }

    /// Conceals the verifier and challenge in normal diagnostics.
    public var description: String { "OAuthPKCE(redacted)" }
    /// Conceals the verifier and challenge in debug diagnostics.
    public var debugDescription: String { description }
    /// Prevents recursive diagnostic traversal into the verifier.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}

/// Supported authorization redirects; implicit compatibility requires an explicit selection.
public enum OAuthAuthorizationMode: Sendable {
    case authorizationCode
    /// Prototype/legacy interoperability only: fragments carry access tokens and cannot provide refresh tokens.
    case implicitCompatibility
}

/// Discord installation-context query values; the application must enable the selected context in its portal.
public enum OAuthInstallationContext: Int, Sendable {
    case guild = 0, user = 1
}

/// Discord's documented existing-consent behavior. Passthrough scopes still require authorization.
public enum OAuthPrompt: String, Sendable { case consent, none }

/// Advisory approval metadata, never proof that Discord approved a requesting application.
public enum OAuthScopeAvailability: Sendable, Equatable {
    case ordinary, approvalRequired, unavailable, unknown

    /// Classifies selected scopes using the OAuth2 and Social SDK references verified 2026-10-17.
    /// - Parameter scope: Exact case-sensitive scope spelling; future scopes remain unknown.
    /// - Returns: Advisory availability. A grant, portal configuration and endpoint policy still apply.
    public static func classify(_ scope: String) -> Self {
        if ["activities.read", "activities.write"].contains(scope) { return .unavailable }
        if ["applications.builds.upload", "dm_channels.read", "identify.premium", "relationships.read", "rpc",
            "rpc.activities.write", "rpc.notifications.read", "rpc.voice.read", "rpc.voice.write", "voice",
            "sdk.social_layer"].contains(scope) { return .approvalRequired }
        if ["applications.builds.read", "applications.commands", "applications.commands.update",
            "applications.commands.permissions.update", "applications.entitlements", "applications.store.update", "bot",
            "connections", "email", "gdm.join", "guilds", "guilds.join", "guilds.members.read", "identify",
            "messages.read", "role_connections.write", "webhook.incoming", "application_identities.write",
            "openid", "sdk.social_layer_presence"].contains(scope) { return .ordinary }
        return .unknown
    }
}

/// Redirect-validated code and its exact initiating application, redirect URI and proof key.
/// Creating a value does not redeem the code. Exchange it once and never log callback URLs.
public struct OAuthAuthorizationCode: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let clientID: ApplicationID
    public let code: OAuthCode
    public let redirectURI: URL
    public let pkce: OAuthPKCE

    /// Captures a successful, authenticated redirect for the token endpoint.
    /// - Parameters:
    ///   - clientID: Application that initiated the authorization.
    ///   - code: Nonempty bounded secret extracted only after redirect/state/issuer checks.
    ///   - redirectURI: Exact registered URI used to start this flow.
    ///   - pkce: S256 proof key bound to the authorization request.
    fileprivate init(clientID: ApplicationID, code: OAuthCode, redirectURI: URL, pkce: OAuthPKCE) {
        self.clientID = clientID; self.code = code; self.redirectURI = redirectURI; self.pkce = pkce
    }
    /// Conceals the code, redirect URI and verifier.
    public var description: String { "OAuthAuthorizationCode(redacted)" }
    /// Conceals all payload in debug diagnostics.
    public var debugDescription: String { description }
    /// Prevents recursive diagnostic traversal into the code and proof key.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}

/// A single accepted redirect result. Associated secret-bearing values redact their own diagnostics.
public enum OAuthAuthorizationResult: Sendable {
    case code(OAuthAuthorizationCode)
    case implicit(OAuthTokenResponse)
}

/// Owns a single state-bound browser authorization. Construction creates no tasks, browser or network I/O.
/// The app binds this actor to its authenticated session and applies its own timeout and persistence policy.
/// Callback validation is synchronous within actor isolation, preventing concurrent replay acceptance.
public actor OAuthAuthorizationFlow: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public nonisolated let authorizationURL: URL
    public nonisolated let redirectURI: URL
    private let clientID: ApplicationID
    private let state: String
    private let pkce: OAuthPKCE?
    private let mode: OAuthAuthorizationMode
    private var consumed = false

    /// Builds Discord's authorization URL with fresh state and S256 by default.
    /// - Parameters:
    ///   - clientID: Nonzero application snowflake; credentials are never placed in this URL.
    ///   - redirectURI: Exact registered HTTPS, loopback HTTP, or `discord-<clientID>:/authorize/callback` URI.
    ///     Query parameters are preserved verbatim but must not collide with OAuth response fields; fragments/userinfo fail.
    ///   - scopes: One to 128 distinct case-sensitive RFC 6749 scope tokens, each at most 256 UTF-8 bytes, total at most 8 KiB.
    ///   - mode: Code flow by default; implicit compatibility is an explicit legacy choice and forbids role_connections.write.
    ///   - pkce: Caller-owned fresh proof key or nil to generate one for code flow; implicit flow forbids a proof key.
    ///   - state: Optional fresh, secret, unguessable session nonce, 32...256 ASCII unreserved characters; nil generates 256 bits.
    ///   - installationContext: Optional enabled guild/user installation context, relevant to applications.commands.
    ///   - prompt: Optional documented consent behavior.
    ///   - permissions: Optional nonnegative decimal bot permissions, at most 256 digits; requires bot scope.
    ///   - guildID: Optional nonzero preferred guild; it is a UI hint and never membership evidence.
    ///   - disableGuildSelection: Locks the preferred guild; requires guildID, default false.
    /// - Throws: `OAuthError.invalidRequest` for invalid bounded inputs or incompatible flow options;
    ///   `.invalidRedirect` for unsafe redirects. Scope approval and portal configuration remain server checks.
    public init(clientID: ApplicationID, redirectURI: URL, scopes: Set<String>,
                mode: OAuthAuthorizationMode = .authorizationCode, pkce: OAuthPKCE? = nil, state: String? = nil,
                installationContext: OAuthInstallationContext? = nil, prompt: OAuthPrompt? = nil,
                permissions: String? = nil, guildID: GuildID? = nil, disableGuildSelection: Bool = false) throws {
        try oauthValidateScopes(scopes, allowEmpty: false)
        guard clientID.rawValue != 0, guildID?.rawValue != 0,
              !disableGuildSelection || guildID != nil,
              permissions.map({ scopes.contains("bot") && !$0.isEmpty && $0.utf8.count <= 256 && $0.utf8.allSatisfy({ (48...57).contains($0) }) }) ?? true,
              installationContext == nil || scopes.contains("applications.commands"),
              installationContext != .user || (!scopes.contains("bot") && permissions == nil && guildID == nil)
        else { throw OAuthError.invalidRequest }
        try oauthValidateRedirect(redirectURI, clientID: clientID)
        let nonce = state ?? oauthRandomNonce()
        guard (32...256).contains(nonce.utf8.count), nonce.utf8.allSatisfy({ byte in
            (65...90).contains(byte) || (97...122).contains(byte) || (48...57).contains(byte) || [45, 46, 95, 126].contains(byte)
        }) else { throw OAuthError.invalidRequest }
        let proof: OAuthPKCE?
        switch mode {
        case .authorizationCode: proof = pkce ?? OAuthPKCE.generate()
        case .implicitCompatibility:
            guard pkce == nil, !scopes.contains("role_connections.write"), !scopes.contains("webhook.incoming") else { throw OAuthError.invalidRequest }
            proof = nil
        }
        var components = URLComponents(string: "https://discord.com/oauth2/authorize")!
        var fields = [URLQueryItem(name: "client_id", value: clientID.description),
            URLQueryItem(name: "response_type", value: proof == nil ? "token" : "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI.absoluteString),
            URLQueryItem(name: "scope", value: scopes.sorted().joined(separator: " ")), URLQueryItem(name: "state", value: nonce)]
        if let proof { fields += [URLQueryItem(name: "code_challenge", value: proof.challenge), URLQueryItem(name: "code_challenge_method", value: "S256")] }
        if let installationContext { fields.append(URLQueryItem(name: "integration_type", value: String(installationContext.rawValue))) }
        if let prompt { fields.append(URLQueryItem(name: "prompt", value: prompt.rawValue)) }
        if let permissions { fields.append(URLQueryItem(name: "permissions", value: permissions)) }
        if let guildID { fields.append(URLQueryItem(name: "guild_id", value: guildID.description)) }
        if disableGuildSelection { fields.append(URLQueryItem(name: "disable_guild_select", value: "true")) }
        components.queryItems = fields
        // URLComponents leaves literal plus signs unescaped; OAuth query consumers interpret them as spaces.
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        authorizationURL = components.url!; self.redirectURI = redirectURI; self.clientID = clientID
        self.state = nonce; self.pkce = proof; self.mode = mode
    }

    /// Validates and consumes one success or denial redirect without redeeming a code or storing tokens.
    /// - Parameter callback: Complete returned URL, at most 16 KiB. Treat it as secret and never log it.
    /// - Returns: A code result for exchange or a refresh-token-free implicit result.
    /// - Throws: Closed errors for redirect, duplicate/malformed fields, mismatched/missing state or issuer,
    ///   denial, malformed success, or replay. Failed origin/state/issuer checks do not consume the flow;
    ///   an authenticated callback consumes it even on denial or malformed payload. Cancellation before validation
    ///   throws `CancellationError` without consuming the flow. No suspension occurs within actor isolation.
    public func consumeCallback(_ callback: URL) throws -> OAuthAuthorizationResult {
        try Task.checkCancellation()
        guard !consumed else { throw OAuthError.alreadyConsumed }
        guard callback.absoluteString.utf8.count <= 16_384,
              var incoming = URLComponents(url: callback, resolvingAgainstBaseURL: false),
              var expected = URLComponents(url: redirectURI, resolvingAgainstBaseURL: false)
        else { throw OAuthError.invalidRedirect }
        let registeredQuery = expected.percentEncodedQuery
        let query = incoming.percentEncodedQuery
        let fragment = incoming.percentEncodedFragment
        incoming.percentEncodedQuery = nil; incoming.percentEncodedFragment = nil
        expected.percentEncodedQuery = nil
        guard incoming.string == expected.string else { throw OAuthError.invalidRedirect }
        let encoded: String
        switch mode {
        case .authorizationCode:
            guard fragment == nil else { throw OAuthError.invalidRedirect }
            if let registeredQuery {
                guard let query, query.hasPrefix(registeredQuery + "&") else { throw OAuthError.invalidRedirect }
                encoded = String(query.dropFirst(registeredQuery.utf8.count + 1))
            } else { encoded = query ?? "" }
        case .implicitCompatibility:
            guard query == registeredQuery else { throw OAuthError.invalidRedirect }
            encoded = fragment ?? ""
        }
        let fields = try oauthDecodeQuery(encoded)
        guard fields["state"] == state else { throw OAuthError.invalidState }
        guard fields["iss"] == "https://discord.com" else { throw OAuthError.invalidIssuer }
        consumed = true
        if let error = fields["error"] {
            guard fields["code"] == nil, fields["access_token"] == nil else { throw OAuthError.malformedResponse }
            throw error == "access_denied" ? OAuthError.accessDenied : OAuthError.authorizationFailed
        }
        switch mode {
        case .authorizationCode:
            guard let value = fields["code"], value.utf8.count <= 4_096,
                  let code = try? OAuthCode(value), fields["access_token"] == nil, let pkce
            else { throw OAuthError.malformedResponse }
            return .code(OAuthAuthorizationCode(clientID: clientID, code: code, redirectURI: redirectURI, pkce: pkce))
        case .implicitCompatibility:
            guard fields["code"] == nil, fields["refresh_token"] == nil,
                  let access = fields["access_token"], let token = try? BearerToken(access),
                  fields["token_type"]?.lowercased() == "bearer", let expiry = fields["expires_in"],
                  expiry.utf8.allSatisfy({ (48...57).contains($0) }), let seconds = Int(expiry), let scope = fields["scope"]
            else { throw OAuthError.malformedResponse }
            do { return .implicit(try OAuthTokenResponse(accessToken: token, expiresIn: seconds, scopes: oauthParseScopes(scope))) }
            catch { throw OAuthError.malformedResponse }
        }
    }

    /// Conceals the state-bearing authorization URL and proof key.
    public nonisolated var description: String { "OAuthAuthorizationFlow(redacted)" }
    /// Uses the same redacted diagnostic during debug formatting.
    public nonisolated var debugDescription: String { description }
    /// Prevents recursive diagnostics from revealing authorization state.
    public nonisolated var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}

/// Encodes bytes as unpadded RFC 4648 base64url, with no secret diagnostics.
/// - Parameter bytes: Bytes already bounded by the caller.
/// - Returns: URL-safe ASCII without padding or whitespace.
private func oauthBase64URL(_ bytes: Data) -> String {
    bytes.base64EncodedString().replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
}

/// Creates a 256-bit state/verifier nonce from the standard library's system entropy source.
/// - Returns: A fresh 43-character base64url string. Its lifetime and secure storage belong to the caller.
private func oauthRandomNonce() -> String {
    var generator = SystemRandomNumberGenerator()
    return oauthBase64URL(Data((0..<32).map { _ in UInt8.random(in: .min ... .max, using: &generator) }))
}

/// Validates bounded RFC 6749 scope-token syntax without asserting server support or approval.
/// - Parameters:
///   - scopes: Distinct case-sensitive tokens; future tokens are accepted.
///   - allowEmpty: Whether a response may contain no granted scopes.
/// - Throws: `OAuthError.invalidRequest` for malformed tokens or local resource-limit violations.
func oauthValidateScopes(_ scopes: Set<String>, allowEmpty: Bool = true) throws {
    guard scopes.count <= 128, allowEmpty || !scopes.isEmpty,
          scopes.reduce(0, { $0 + $1.utf8.count }) <= 8_192,
          scopes.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 256 && $0.utf8.allSatisfy({ $0 == 33 || (35...91).contains($0) || (93...126).contains($0) }) })
    else { throw OAuthError.invalidRequest }
}

/// Splits a bounded wire scope string, rejecting empty interior tokens and malformed syntax.
/// - Parameter text: Space-delimited RFC scope tokens, or empty when no scopes were granted.
/// - Returns: Unique case-sensitive scope tokens. Duplicate server tokens are harmlessly collapsed.
/// - Throws: `OAuthError.invalidRequest` for malformed or oversized scope strings.
func oauthParseScopes(_ text: String) throws -> Set<String> {
    guard text.utf8.count <= 8_192 else { throw OAuthError.invalidRequest }
    let result = text.isEmpty ? Set<String>() : Set(text.split(separator: " ", omittingEmptySubsequences: false).map(String.init))
    try oauthValidateScopes(result)
    return result
}

/// Validates the supported exact registered redirect contract without contacting Discord.
/// - Parameters:
///   - url: Registered callback URI, at most 4 KiB, without fragments or userinfo.
///   - clientID: Application whose documented mobile scheme is permitted.
/// - Throws: `OAuthError.invalidRedirect` for unsafe scheme, address or reserved query fields.
private func oauthValidateRedirect(_ url: URL, clientID: ApplicationID) throws {
    guard url.absoluteString.utf8.count <= 4_096,
          let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
          components.user == nil, components.password == nil, components.fragment == nil,
          !url.absoluteString.unicodeScalars.contains(where: { $0.properties.generalCategory == .control })
    else { throw OAuthError.invalidRedirect }
    let scheme = components.scheme?.lowercased()
    let allowed = (scheme == "https" && components.host?.isEmpty == false) ||
        (scheme == "http" && ["127.0.0.1", "[::1]", "::1"].contains(components.host ?? "")) ||
        (scheme == "discord-\(clientID)" && components.host == nil && components.path == "/authorize/callback")
    let reserved: Set<String> = ["code", "state", "iss", "error", "error_description", "access_token", "token_type", "expires_in", "scope", "refresh_token"]
    guard allowed else { throw OAuthError.invalidRedirect }
    if let query = components.percentEncodedQuery {
        do { guard Set(try oauthDecodeQuery(query).keys).isDisjoint(with: reserved) else { throw OAuthError.invalidRedirect } }
        catch { throw OAuthError.invalidRedirect }
    }
}

/// Decodes a bounded application/x-www-form-urlencoded callback while rejecting ambiguity.
/// - Parameter text: Already separated percent-encoded query or fragment fields.
/// - Returns: At most 64 unique decoded fields. Literal plus means space; percent-encoded plus is retained.
/// - Throws: `OAuthError.malformedResponse` for missing values, duplicates, malformed escapes or excess fields.
private func oauthDecodeQuery(_ text: String) throws -> [String: String] {
    let parts = text.split(separator: "&", omittingEmptySubsequences: false)
    guard !text.isEmpty, parts.count <= 64 else { throw OAuthError.malformedResponse }
    var result: [String: String] = [:]
    for part in parts {
        let pair = part.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
        guard pair.count == 2,
              let name = pair[0].replacingOccurrences(of: "+", with: " ").removingPercentEncoding,
              let value = pair[1].replacingOccurrences(of: "+", with: " ").removingPercentEncoding,
              !name.isEmpty, result[name] == nil,
              !name.unicodeScalars.contains(where: { $0.properties.generalCategory == .control }),
              !value.unicodeScalars.contains(where: { $0.properties.generalCategory == .control })
        else { throw OAuthError.malformedResponse }
        result[name] = value
    }
    return result
}
