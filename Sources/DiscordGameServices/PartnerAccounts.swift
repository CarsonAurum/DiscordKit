// File: Sources/DiscordGameServices/PartnerAccounts.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import DiscordHTTP
import DiscordModels
import DiscordOAuth
import Foundation

/// External provider proof, distinct from a Discord bearer credential and redacted in diagnostics.
public enum ExternalAccountTokenTag: Sendable {}
/// Exact OIDC/Steam/EOS/provider proof; never log or persist without an explicit secure-storage policy.
public typealias ExternalAccountToken = Secret<ExternalAccountTokenTag>
/// Optional opaque identity token returned by provisional authentication; decoding does not verify its JWT claims.
public enum PartnerIdentityTokenTag: Sendable {}
/// Redacted provisional identity token, deliberately separate from bearer authorization.
public typealias PartnerIdentityToken = Secret<PartnerIdentityTokenTag>
/// Opaque console device-code credential, distinct from bearer access tokens.
public enum PartnerDeviceCodeTag: Sendable {}
/// Redacted device authorization code obtained by the host's approved device authorization flow.
public typealias PartnerDeviceCode = Secret<PartnerDeviceCodeTag>

/// Published partner-token JSON. A provisional account remains a limited identity; this response never
/// claims full Discord account creation, validates an ID-token JWT, or starts a native Social SDK session.
public struct PartnerTokenResponse: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// Standard bearer, expiry, scope and optional refresh-token fields with safe diagnostics.
    public let token: OAuthTokenResponse
    /// Optional exact id_token. Child exchange normally omits it; no identity claim is inferred.
    public let identityToken: PartnerIdentityToken?

    /// Parses one bounded response, retaining secrets only in explicitly redacted wrappers.
    /// - Parameter data: Complete JSON object, at most 64 KiB including unknown fields.
    /// - Throws: Bounded JSON errors or sanitized invalid-response errors for invalid optional identity tokens;
    ///   `OAuthTokenResponse` validates required bearer/expiry/scope fields. No token refresh or I/O occurs.
    public init(data: Data) throws {
        guard case .object(let fields) = try JSONValue.parse(data, limits: .init(maximumBytes: 65_536))
        else { throw DiscordError.transport(.invalidResponse) }
        token = try OAuthTokenResponse(data: data)
        if let value = fields["id_token"] {
            guard case .string(let value) = value else { throw DiscordError.transport(.invalidResponse) }
            guard value.utf8.count <= 32_768 else { throw DiscordError.transport(.invalidResponse) }
            do { identityToken = try PartnerIdentityToken(value) }
            catch { throw DiscordError.transport(.invalidResponse) }
        } else { identityToken = nil }
    }
    /// Conceals all bearer and identity token fields from interpolation.
    public var description: String { "PartnerTokenResponse(redacted)" }
    /// Uses the same safe marker for debug formatting.
    public var debugDescription: String { description }
    /// Prevents recursive reflection from exposing credential-bearing response data.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}

/// Explicit unmerge acknowledgement. The guide specifies no response schema/status beyond success;
/// retain optional bounded JSON without inventing a user, token, migration-complete or new-account result.
public struct PartnerAccountAcknowledgement: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// Deliberately inspected response, or nil for a bodyless success. May contain private account data.
    public let value: JSONValue?

    /// Decodes an optional response body without asserting asynchronous data migration has completed.
    /// - Parameter data: Empty response or complete JSON up to 64 KiB.
    /// - Throws: Bounded JSON parse errors for a nonempty malformed body; construction performs no I/O.
    public init(data: Data) throws {
        value = data.isEmpty ? nil : try JSONValue.parse(data, limits: .init(maximumBytes: 65_536))
    }
    /// Redacts any private acknowledgement fields.
    public var description: String { "PartnerAccountAcknowledgement(redacted)" }
    /// Returns the same safe diagnostic marker.
    public var debugDescription: String { description }
    /// Prevents reflective traversal of retained account data.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}

/// API v10 partner operations verified 2026-10-17 against the provisional-account and publisher guides.
/// Construction starts no tasks/I/O. Use a shared REST rate authority and backend-only bot/client secrets.
/// All mutations are unsafe to replay after uncertain submission; provisioning/access remains Discord-owned.
public enum PartnerAccountEndpoints {
    /// Creates or reauthenticates a limited account for one server-authenticated external identity.
    /// - Parameters:
    ///   - externalUserID: Exact game account key, 1...4,096 UTF-8 bytes under a local bound; never a bearer token.
    ///   - preferredGlobalName: Optional display name, locally bounded to 1...32 characters without controls.
    /// - Returns: Bot-only POST /partner-sdk/token/bot with a redacted bearer/optional ID-token response.
    /// - Throws: Input/body/descriptor errors now; missing provisioning, linked-full-account (530010), credential,
    ///   API, transport or cancellation errors on execution. Reauthenticate with this endpoint at expiry;
    ///   no OAuth refresh, automatic linking, migration or full-account creation occurs.
    public static func provisionalBot(externalUserID: String, preferredGlobalName: String? = nil) throws -> Endpoint<PartnerTokenResponse> {
        try partnerText(externalUserID, maximumBytes: 4_096)
        var fields: [String: JSONValue] = ["external_user_id": .string(externalUserID)]
        if let preferredGlobalName {
            try partnerName(preferredGlobalName)
            fields["preferred_global_name"] = .string(preferredGlobalName)
        }
        return try partnerToken(path: ["token", "bot"], authentication: .bot, fields: fields)
    }

    /// Exchanges a configured external-provider proof on the confidential backend.
    /// - Parameters:
    ///   - applicationID: Nonzero approved application or publisher ID; never a child ID for publisher authentication.
    ///   - clientSecret: Backend-held application secret; must never be shipped in public clients.
    ///   - externalAuthType: Exact documented provider discriminator, 1...128 UTF-8 bytes; future values retained.
    ///   - externalAuthToken: Fresh proof from the configured provider, at most 32 KiB under local request bounds.
    /// - Returns: Header-free JSON POST /partner-sdk/token. Client proof is carried only in a redacted body.
    /// - Throws: Local bounds/descriptor errors now; provider configuration/expiry/credential/API/transport errors
    ///   later. OIDC refresh-token grants are deprecated; reacquire provider proof and repeat explicitly at expiry.
    public static func provisionalExternal(applicationID: ApplicationID, clientSecret: ClientSecret,
        externalAuthType: String, externalAuthToken: ExternalAccountToken) throws -> Endpoint<PartnerTokenResponse> {
        try partnerToken(path: ["token"], authentication: .none,
            fields: externalFields(applicationID: applicationID, clientSecret: clientSecret,
                externalAuthType: externalAuthType, externalAuthToken: externalAuthToken))
    }

    /// Explicitly severs a bot-created identity link, invalidating user access/refresh tokens and sessions upstream.
    /// - Parameter externalUserID: Same server-authenticated account key used for bot provisioning, not its token.
    /// - Returns: Bot-only POST /partner-sdk/provisional-accounts/unmerge/bot accepting successful 2xx replies.
    /// - Throws: Input/body/descriptor errors now; API/transport/cancellation failures later, with uncertain submitted
    ///   outcomes requiring reconciliation. Discord creates a fresh provisional identity and migrates data;
    ///   no local automatic reauthentication, full-account deletion or synchronous migration guarantee is added.
    public static func unmergeBot(externalUserID: String) throws -> Endpoint<PartnerAccountAcknowledgement> {
        try partnerText(externalUserID, maximumBytes: 4_096)
        return try partnerUnmerge(path: ["provisional-accounts", "unmerge", "bot"], authentication: .bot,
            fields: ["external_user_id": .string(externalUserID)])
    }

    /// Explicitly unmerges a provider-created identity using its configured confidential-client proof.
    /// - Parameters:
    ///   - applicationID: Nonzero approved authenticating application/publisher, never a publisher child.
    ///   - clientSecret: Backend-held matching client secret.
    ///   - externalAuthType: Exact provider discriminator, locally 1...128 UTF-8 bytes.
    ///   - externalAuthToken: Same external identity proof used to authenticate, locally at most 32 KiB.
    /// - Returns: Header-free POST /partner-sdk/provisional-accounts/unmerge, with redacted JSON credentials.
    /// - Throws: Local bounds/descriptor or execution errors as for `unmergeBot`. Successful unmerge invalidates
    ///   all user tokens/sessions upstream; caller must invalidate its secure store and dependent child lineage.
    public static func unmergeExternal(applicationID: ApplicationID, clientSecret: ClientSecret,
        externalAuthType: String, externalAuthToken: ExternalAccountToken) throws -> Endpoint<PartnerAccountAcknowledgement> {
        try partnerUnmerge(path: ["provisional-accounts", "unmerge"], authentication: .none,
            fields: externalFields(applicationID: applicationID, clientSecret: clientSecret,
                externalAuthType: externalAuthType, externalAuthToken: externalAuthToken))
    }

    /// Exchanges an approved publisher bearer for one child-game bearer without changing application hierarchy.
    /// - Parameters:
    ///   - parentAccessToken: Current publisher bearer; parent authentication cannot initialize the child SDK.
    ///   - childApplicationID: Nonzero child already linked by Discord; requesting linkage itself is intentionally absent.
    ///   - parentClientSecret: Backend-only publisher secret, at most 8 KiB, matching the approved confidential hierarchy.
    /// - Returns: Header-free POST /partner-sdk/child-token. No child refresh token is supplied by the contract.
    /// - Throws: Bounds/body/descriptor errors now; provisioning/hierarchy/credentials/API/transport errors later.
    ///   A response containing a refresh token fails with sanitized invalid-response because child tokens cannot refresh.
    ///   Child expiry equals the parent's remaining expiry. Refreshing the parent leaves old child expiry unchanged;
    ///   revoke parent to invalidate all children; revoke an individual child with that child's application credentials.
    ///   Linking an existing child deletes its tokens/lobbies/identities/provisionals/relationships irreversibly upstream.
    public static func publisherChild(parentAccessToken: BearerToken, childApplicationID: ApplicationID,
        parentClientSecret: ClientSecret) throws -> Endpoint<PartnerTokenResponse> {
        guard childApplicationID.rawValue != 0 else { throw DiscordError.validation(.invalidValue) }
        let parent = try parentAccessToken.withUnsafeValue { value in
            try partnerText(value, maximumBytes: 32_768); return value
        }
        return try partnerToken(path: ["child-token"], authentication: .none, fields: [
            "parent_access_token": .string(parent), "child_application_id": .string(childApplicationID.description),
            "parent_client_secret": .string(partnerSecret(parentClientSecret))], rejectRefreshToken: true)
    }

    /// Exchanges a host-obtained console device code while explicitly merging an external provisional identity.
    /// - Parameters:
    ///   - applicationID: Nonzero approved authenticating application/publisher.
    ///   - clientSecret: Confidential backend secret; never embed in game binaries.
    ///   - deviceCode: Device code issued by the host's approved RFC 8628 console flow.
    ///   - externalAuthType: Configured provider type; bot provisionals use DISCORD_BOT_ISSUED_ACCESS_TOKEN.
    ///   - externalAuthToken: Provider proof; for bot provisionals use its returned access token, never external_user_id.
    /// - Returns: Unsafe header-free OAuth form POST /oauth2/token; response contains the merged user's token.
    /// - Throws: Local validation or execution errors. Migration proceeds asynchronously after exchange; consent,
    ///   verification and device-code polling remain host-owned. No automatic merge runs at startup.
    public static func mergeDeviceCode(applicationID: ApplicationID, clientSecret: ClientSecret,
        deviceCode: PartnerDeviceCode, externalAuthType: String,
        externalAuthToken: ExternalAccountToken) throws -> Endpoint<OAuthTokenResponse> {
        guard applicationID.rawValue != 0 else { throw DiscordError.validation(.invalidValue) }
        try partnerText(externalAuthType, maximumBytes: 128)
        let external = try externalAuthToken.withUnsafeValue { value in
            try partnerText(value, maximumBytes: 32_768); return value
        }
        let fields = [QueryItem(name: "grant_type", value: "urn:ietf:params:oauth:grant-type:device_code"),
            .init(name: "client_id", value: applicationID.description),
            .init(name: "client_secret", value: try partnerSecret(clientSecret)),
            .init(name: "device_code", value: try partnerSecret(deviceCode)),
            .init(name: "external_auth_type", value: externalAuthType),
            .init(name: "external_auth_token", value: external)]
        return try Endpoint(method: "POST", path: ["oauth2", "token"], authentication: .none,
            body: RequestBody.form(fields, maximumBytes: 65_536), decode: { try OAuthTokenResponse(data: $0) })
    }
}

/// Validates exact nonempty partner input under finite local bounds, without normalizing identity keys.
/// - Parameters:
///   - value: Caller-owned exact text; whitespace is allowed in identifiers, controls are rejected.
///   - maximumBytes: Inclusive positive UTF-8 byte cap fixed by the calling operation.
/// - Throws: Sanitized invalid-value errors for empty/control/oversized input. No state changes occur.
private func partnerText(_ value: String, maximumBytes: Int) throws {
    guard !value.isEmpty, value.utf8.count <= maximumBytes,
          !value.unicodeScalars.contains(where: { $0.properties.generalCategory == .control })
    else { throw DiscordError.validation(.invalidValue) }
}

/// Validates a display name before a bot provisioning request.
/// - Parameter value: Exact desired name, locally limited to 1...32 Swift characters and 128 UTF-8 bytes.
/// - Throws: Sanitized invalid-value errors for empty, control-containing or oversized names; server moderation remains authoritative.
private func partnerName(_ value: String) throws {
    try partnerText(value, maximumBytes: 128)
    guard value.count <= 32 else { throw DiscordError.validation(.invalidValue) }
}

/// Materializes exact confidential external-exchange fields once, keeping proof out of descriptor metadata.
/// - Parameters:
///   - applicationID: Nonzero authenticating approved application or publisher.
///   - clientSecret: Confidential client proof retained only in the returned request body.
///   - externalAuthType: Open provider discriminator bounded to 128 bytes.
///   - externalAuthToken: Provider proof bounded to 32 KiB.
/// - Returns: JSON fields common to exchange and explicit unmerge, without extra default keys.
/// - Throws: Sanitized validation errors for invalid provider discriminator/proof bounds.
private func externalFields(applicationID: ApplicationID, clientSecret: ClientSecret,
    externalAuthType: String, externalAuthToken: ExternalAccountToken) throws -> [String: JSONValue] {
    guard applicationID.rawValue != 0 else { throw DiscordError.validation(.invalidValue) }
    try partnerText(externalAuthType, maximumBytes: 128)
    return try externalAuthToken.withUnsafeValue { value in
        try partnerText(value, maximumBytes: 32_768)
        return ["client_id": .string(applicationID.description), "client_secret": .string(try partnerSecret(clientSecret)),
            "external_auth_type": .string(externalAuthType), "external_auth_token": .string(value)]
    }
}

/// Exposes a credential only after applying the shared finite local client/device proof bound.
/// - Parameter value: Typed secret previously validated for nonempty/whitespace/control syntax.
/// - Returns: Exact secret, at most 8,192 UTF-8 bytes, for immediate placement in a redacted body.
/// - Throws: Sanitized invalid-value if the proof exceeds the local cap; no content appears in the error.
private func partnerSecret<Tag>(_ value: Secret<Tag>) throws -> String {
    try value.withUnsafeValue { text in
        try partnerText(text, maximumBytes: 8_192)
        return text
    }
}

/// Produces one bounded partner JSON token descriptor with no inferred replay/cache policy.
/// - Parameters:
///   - path: Fixed action segments below partner-sdk.
///   - authentication: Bot header or none for body-authenticated confidential exchange.
///   - fields: Exact already validated JSON fields, including explicitly supplied secrets.
///   - rejectRefreshToken: Reject any child response carrying refresh_token; defaults false for provisional exchange.
/// - Returns: Unsafe HTTP 200 operation; execution uses the caller's shared ordinary REST authority.
/// - Throws: JSON/body/descriptor bounds errors synchronously; no request is sent.
private func partnerToken(path: [String], authentication: AuthenticationPolicy,
    fields: [String: JSONValue], rejectRefreshToken: Bool = false) throws -> Endpoint<PartnerTokenResponse> {
    try Endpoint(method: "POST", path: ["partner-sdk"] + path, authentication: authentication,
        body: RequestBody(bytes: JSONValue.object(fields).serialized(limits: .init(maximumBytes: 65_536)),
            contentType: "application/json", maximumBytes: 65_536), decode: {
                let response = try PartnerTokenResponse(data: $0)
                guard !rejectRefreshToken || response.token.refreshToken == nil
                else { throw DiscordError.transport(.invalidResponse) }
                return response
            })
}

/// Produces one explicit destructive unmerge without assuming an undocumented response schema.
/// - Parameters:
///   - path: Fixed bot or external unmerge route below partner-sdk.
///   - authentication: Exact bot or body-authentication policy.
///   - fields: Validated identity/proof payload; all ordinary descriptor diagnostics redact its body.
/// - Returns: Unsafe operation accepting any successful 2xx status because the guide supplies no narrower status contract.
/// - Throws: JSON/body/descriptor bounds errors before I/O; migration outcome is established only by execution.
private func partnerUnmerge(path: [String], authentication: AuthenticationPolicy,
    fields: [String: JSONValue]) throws -> Endpoint<PartnerAccountAcknowledgement> {
    try Endpoint(method: "POST", path: ["partner-sdk"] + path, authentication: authentication,
        successStatuses: Set(200...299),
        body: RequestBody(bytes: JSONValue.object(fields).serialized(limits: .init(maximumBytes: 65_536)),
            contentType: "application/json", maximumBytes: 65_536), decode: { try PartnerAccountAcknowledgement(data: $0) })
}
