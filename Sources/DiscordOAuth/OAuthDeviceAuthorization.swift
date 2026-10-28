// File: Sources/DiscordOAuth/OAuthDeviceAuthorization.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordLogging
import DiscordCore
import DiscordHTTP
import Foundation

/// Marks an OAuth device verification code; it must never be displayed to the user.
public enum OAuthDeviceCodeTag: Sendable {}
/// A redacted device verification credential, distinct from an end-user verification code.
public typealias OAuthDeviceCode = Secret<OAuthDeviceCodeTag>

/// Bounded device-authorization instructions returned by Discord API v10.
///
/// The [published console flow](https://docs.discord.com/developers/discord-social-sdk/development-guides/account-linking-on-consoles)
/// was verified 2026-10-18. Applications explicitly present the user code and
/// verification URL; this value opens no browser, console overlay, or native SDK.
/// Ordinary formatting/reflection hides codes and the complete verification URL.
public struct OAuthDeviceAuthorization: Sendable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    /// Secret exchanged at the token endpoint; never display it in authorization UI.
    public let deviceCode: OAuthDeviceCode
    /// Short user-facing verification code; present only in the intended authorization UI.
    public let userCode: String
    /// Discord HTTPS activation URI without credentials or fragments.
    public let verificationURI: URL
    /// Optional user-code-bearing Discord activation URI for QR-code presentation.
    public let verificationURIComplete: URL?
    /// Positive lifetime in whole seconds, capped locally at 24 hours.
    public let expiresIn: Int
    /// Positive minimum polling interval in whole seconds; RFC 8628 default is five.
    public let interval: Int

    /// Validates a bounded device authorization response without external activity.
    /// - Parameter data: Complete JSON response, subject to the common 1 MiB parser limit.
    /// - Throws: `OAuthError.malformedResponse` for duplicate/missing/wrong fields,
    ///   invalid codes, nonintegral or out-of-policy durations, or foreign activation URLs.
    ///   Unknown fields are ignored; no payload text is retained in errors.
    public init(data: Data) throws {
        do {
            guard case .object(let fields) = try JSONValue.parse(data),
                case .string(let code) = fields["device_code"], code.utf8.count <= 8_192,
                case .string(let userCode) = fields["user_code"], userCode.utf8.count <= 256,
                case .string(let uri) = fields["verification_uri"],
                case .number(let expiry) = fields["expires_in"]
            else { throw OAuthError.malformedResponse }
            deviceCode = try OAuthDeviceCode(code)
            _ = try Secret<OAuthDeviceCodeTag>(userCode)
            self.userCode = userCode
            verificationURI = try Self.activationURI(uri)
            if let complete = fields["verification_uri_complete"] {
                guard case .string(let text) = complete else { throw OAuthError.malformedResponse }
                verificationURIComplete = try Self.activationURI(text)
            } else { verificationURIComplete = nil }
            expiresIn = try Self.positiveSeconds(expiry)
            if let value = fields["interval"] {
                guard case .number(let number) = value else { throw OAuthError.malformedResponse }
                interval = try Self.positiveSeconds(number)
            } else { interval = 5 }
        } catch { throw OAuthError.malformedResponse }
    }

    /// Validates Discord's exact published activation origin/path without following it.
    /// - Parameter text: URI of at most 8 KiB; optional activation query remains opaque.
    /// - Returns: HTTPS discord.com/activate URI without userinfo, a custom port, or fragments.
    /// - Throws: `OAuthError.malformedResponse` for unsafe or unsupported URI values.
    private static func activationURI(_ text: String) throws -> URL {
        guard text.utf8.count <= 8_192, let parts = URLComponents(string: text),
            parts.scheme == "https", parts.host == "discord.com", parts.path == "/activate",
            parts.user == nil, parts.password == nil, parts.port == nil, parts.fragment == nil,
            let url = parts.url else { throw OAuthError.malformedResponse }
        return url
    }

    /// Parses policy-bounded integral seconds without accepting fractions or exponent spellings.
    /// - Parameter value: Exact JSON numeric lexeme.
    /// - Returns: Whole seconds in `1...86_400`, permitting safe clock arithmetic.
    /// - Throws: `OAuthError.malformedResponse` for malformed, overflowing, or out-of-policy values.
    private static func positiveSeconds(_ value: JSONNumber) throws -> Int {
        guard value.rawValue.utf8.allSatisfy({ (48...57).contains($0) }),
            let seconds = Int(value.rawValue), (1...86_400).contains(seconds)
        else { throw OAuthError.malformedResponse }
        return seconds
    }

    /// Conceals the device and user codes and code-bearing activation URL.
    public var description: String { "OAuthDeviceAuthorization(redacted)" }
    /// Conceals authorization instructions in debug diagnostics.
    public var debugDescription: String { description }
    /// Prevents recursive diagnostics from traversing authorization instructions.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}

/// Publicly documented confidential backend device-flow descriptors, without execution.
///
/// These manual server-to-server operations require a configured Discord application
/// and an eligible verified account. Console middleware approval and target-console
/// developer approval remain application prerequisites. SDK-managed public-client
/// token acquisition and native authorization overlays are separate unimplemented APIs.
public enum OAuthDeviceAuthorizationEndpoints {
    /// Requests device/user codes with a bounded form body and no bearer/bot header.
    /// - Parameters:
    ///   - scopes: Nonempty bounded OAuth scopes, subject to application approval and user consent.
    ///   - authentication: Confidential backend credentials; embedded/public clients are rejected.
    /// - Returns: Unsafe POST /api/v10/oauth2/device/authorize descriptor; no cache/replay opt-in.
    /// - Throws: `OAuthError.unsupportedClient` for public clients, invalid-request errors
    ///   for malformed scope/client/secret sizes, and bounded body/descriptor errors.
    ///   Execution uses injected shared HTTP admission and must not replay an ambiguous submission.
    public static func authorize(scopes: Set<String>, authentication: OAuthClientAuthentication)
        throws -> Endpoint<OAuthDeviceAuthorization>
    {
        try oauthValidateScopes(scopes, allowEmpty: false)
        return try Endpoint(
            method: "POST", path: ["oauth2", "device", "authorize"], authentication: .none,
            body: form(fields: [QueryItem(name: "scope", value: scopes.sorted().joined(separator: " "))],
                       authentication: authentication),
            decode: { try OAuthDeviceAuthorization(data: $0) }
        )
    }

    /// Exchanges one device code using the published RFC 8628 grant type.
    /// - Parameters:
    ///   - deviceCode: Current secret from a not-yet-expired authorization session, at most 8 KiB.
    ///   - authentication: Confidential backend credentials matching the initiating application.
    ///   - externalAuthType: Optional uppercase provider type for the published provisional-account merge variant.
    ///   - externalAuthToken: Optional provisional token paired with `externalAuthType`; never an account ID.
    /// - Returns: Unsafe, uncached POST /api/v10/oauth2/token descriptor with standard redacted token decoding.
    /// - Throws: Unsupported-client or invalid-request errors for local validation;
    ///   execution may return authorization_pending, slow_down, denial, expiry, or safe HTTP failures.
    ///   The caller must enforce polling interval/expiry; `OAuthDeviceAuthorizationFlow` owns that local policy.
    public static func exchange(
        deviceCode: OAuthDeviceCode, authentication: OAuthClientAuthentication,
        externalAuthType: String? = nil, externalAuthToken: BearerToken? = nil
    ) throws -> Endpoint<OAuthTokenResponse> {
        guard (externalAuthType == nil) == (externalAuthToken == nil),
            externalAuthType.map({ !$0.isEmpty && $0.utf8.count <= 128 && $0.utf8.allSatisfy({
                (65...90).contains($0) || (48...57).contains($0) || $0 == 95
            }) }) ?? true else { throw OAuthError.invalidRequest }
        var fields = [QueryItem(name: "grant_type", value: "urn:ietf:params:oauth:grant-type:device_code"),
                      QueryItem(name: "device_code", value: deviceCode.withUnsafeValue { $0 })]
        if let externalAuthType, let externalAuthToken {
            fields += [QueryItem(name: "external_auth_type", value: externalAuthType),
                       QueryItem(name: "external_auth_token", value: externalAuthToken.withUnsafeValue { $0 })]
        }
        return try Endpoint(method: "POST", path: ["oauth2", "token"], authentication: .none,
                            body: form(fields: fields, authentication: authentication),
                            decode: { try OAuthTokenResponse(data: $0) })
    }

    /// Materializes bounded form-only client authentication consistent with existing OAuth descriptors.
    /// - Parameters:
    ///   - fields: Fixed grant fields, each capped at 8 KiB of UTF-8.
    ///   - authentication: Confidential credentials retained only inside a redacted request body.
    /// - Returns: At most 64 KiB of form data with client_id/client_secret; never URL userinfo or bearer headers.
    /// - Throws: Unsupported-client, invalid-request, or bounded request-body validation errors.
    private static func form(fields: [QueryItem], authentication: OAuthClientAuthentication) throws -> RequestBody {
        guard case .confidential(let clientID, let secret) = authentication else { throw OAuthError.unsupportedClient }
        guard clientID.rawValue != 0, secret.withUnsafeValue({ $0.utf8.count <= 8_192 }),
            fields.allSatisfy({ ($0.value?.utf8.count ?? 0) <= 8_192 }) else { throw OAuthError.invalidRequest }
        return try RequestBody.form(fields + [QueryItem(name: "client_id", value: clientID.description),
                                              QueryItem(name: "client_secret", value: secret.withUnsafeValue { $0 })],
                                    maximumBytes: 65_536)
    }
}

/// Closed local device-flow failures, without server descriptions or credentials.
public enum OAuthDeviceAuthorizationError: Error, Equatable, Sendable {
    /// Start must be called explicitly before polling.
    case notStarted
    /// This one-use flow already admitted a start operation.
    case alreadyStarted
    /// Another start/poll operation is currently awaiting HTTP completion.
    case busy
    /// The conservative local lifetime or server expired_token signal ended the flow.
    case expired
    /// The authorizing user explicitly denied the request.
    case accessDenied
    /// The caller's fixed token-request budget has been exhausted.
    case pollLimitExceeded
    /// Explicit cancellation invalidated the flow and any later in-flight result.
    case cancelled
    /// An unrecognized OAuth error or an already-consumed successful/failed flow cannot continue.
    case authorizationFailed
}

/// One explicit poll result; associated credentials remain redacted in diagnostics.
public enum OAuthDevicePollResult: Sendable {
    /// No request was sent because the minimum interval has not elapsed.
    case waiting(retryAfter: Duration)
    /// Discord returned authorization_pending; wait at least this long before retrying.
    case pending(retryAfter: Duration)
    /// Discord returned slow_down; the persistent interval increased by five seconds.
    case slowDown(retryAfter: Duration)
    /// A token was issued exactly once; persistence and token-coordinator adoption remain caller-owned.
    case authorized(OAuthTokenResponse)
}

/// One-use explicit device authorization with no background polling, storage, or native UI.
///
/// The caller starts only after a user request, displays returned instructions, and
/// invokes `poll()` when appropriate. This actor enforces RFC 8628 minimum intervals,
/// persistent slow-down increments, a conservative request-start lifetime, and a fixed
/// poll budget. HTTP authorities are injected/shared. No library task or timer is
/// created; cancellation of the calling task propagates through the HTTP pipeline.
public actor OAuthDeviceAuthorizationFlow<C: Clock>: CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable where C.Duration == Duration
{
    private let rest: RESTClient<C>
    private let authentication: OAuthClientAuthentication
    private let clock: C
    private let maximumPolls: Int
    private var started = false
    private var busy = false
    private var finished = false
    private var cancelled = false
    private var authorization: OAuthDeviceAuthorization?
    private var expiresAt: C.Instant?
    private var nextPollAt: C.Instant?
    private var pollingInterval: Duration = .seconds(5)
    private var polls = 0

    /// Creates an inert single-session backend owner without network calls or tasks.
    /// - Parameters:
    ///   - rest: Separately owned shared REST pipeline; descriptors suppress bearer/bot headers.
    ///   - authentication: Confidential backend credentials; public/embedded clients fail locally.
    ///   - clock: Monotonic clock shared with the REST pipeline, including deterministic test clocks.
    ///   - maximumPolls: Fixed token-request budget in `1...4_096`; defaults to 128.
    /// - Throws: `OAuthError.unsupportedClient` for public clients or `.invalidRequest` for invalid poll budget/client ID.
    public init(rest: RESTClient<C>, authentication: OAuthClientAuthentication, clock: C, maximumPolls: Int = 128) throws {
        guard case .confidential = authentication else { throw OAuthError.unsupportedClient }
        guard authentication.clientID.rawValue != 0, (1...4_096).contains(maximumPolls) else { throw OAuthError.invalidRequest }
        self.rest = rest
        self.authentication = authentication
        self.clock = clock
        self.maximumPolls = maximumPolls
    }

    /// Explicitly obtains user-facing authorization instructions once, after user intent.
    /// - Parameter scopes: Requested bounded nonempty scopes; Discord/user approval is authoritative.
    /// - Returns: Redacted display instructions with a secret device code retained for polling.
    /// - Throws: Local OAuth validation, closed device-flow state/API failures, cancellation,
    ///   bounded HTTP failures, or indeterminate submitted outcomes. Any admitted start
    ///   failure consumes this flow; obtain fresh user intent and create a new instance.
    public func start(scopes: Set<String>) async throws -> OAuthDeviceAuthorization {
        try Task.checkCancellation()
        guard !cancelled else { throw OAuthDeviceAuthorizationError.cancelled }
        guard !busy else { throw OAuthDeviceAuthorizationError.busy }
        guard !started, !finished else { throw OAuthDeviceAuthorizationError.alreadyStarted }
        let endpoint = try OAuthDeviceAuthorizationEndpoints.authorize(scopes: scopes, authentication: authentication)
        let logger = DiscordLog.makeLogger("oauth.device")
        logger.trace("Device authorization started", metadata: ["dk.event": "oauth.device.started"])
        started = true
        busy = true
        let requestStart = clock.now
        defer { busy = false }
        do {
            let result: OAuthDeviceAuthorization
            do {
                logger.trace("Device authorization HTTP admitted", metadata: ["dk.event": "oauth.device.http.admitted"])
                result = try await rest.execute(endpoint)
                logger.trace("Device authorization response decoded", metadata: ["dk.event": "oauth.device.response.decoded"])
            }
            catch is APIResponseError { throw OAuthDeviceAuthorizationError.authorizationFailed }
            try Task.checkCancellation()
            guard !cancelled else { throw OAuthDeviceAuthorizationError.cancelled }
            let expiry = requestStart.advanced(by: .seconds(result.expiresIn))
            guard clock.now < expiry else { throw OAuthDeviceAuthorizationError.expired }
            authorization = result
            expiresAt = expiry
            pollingInterval = .seconds(result.interval)
            nextPollAt = clock.now.advanced(by: pollingInterval)
            logger.info("Device authorization instructions admitted", metadata: ["dk.event": "oauth.device.instructions"])
            return result
        } catch {
            if error is CancellationError || Task.isCancelled {
                logger.trace("Device authorization cancelled", metadata: ["dk.event": "oauth.device.cancelled"])
            } else {
                logger.error("Device authorization failed", metadata: ["dk.event": "oauth.device.failed"])
            }
            finish()
            throw error
        }
    }

    /// Attempts at most one due token request and never sleeps or schedules another poll.
    /// - Returns: Wait/pending/slow-down delay, or one redacted token result on success.
    /// - Throws: Closed state/expiry/denial/poll-limit/API failures, caller cancellation,
    ///   or safe HTTP/indeterminate-submission errors. Terminal errors consume the flow
    ///   and erase retained codes; busy and premature polling do not consume its budget.
    ///   HTTP 400 authorization_pending and slow_down are the only retriable OAuth errors.
    public func poll() async throws -> OAuthDevicePollResult {
        try Task.checkCancellation()
        guard !cancelled else { throw OAuthDeviceAuthorizationError.cancelled }
        guard !busy else { throw OAuthDeviceAuthorizationError.busy }
        guard started else { throw OAuthDeviceAuthorizationError.notStarted }
        guard !finished, let authorization, let expiresAt, let nextPollAt else {
            throw OAuthDeviceAuthorizationError.authorizationFailed
        }
        guard clock.now < expiresAt else { finish(); throw OAuthDeviceAuthorizationError.expired }
        if clock.now < nextPollAt {
            DiscordLog.makeLogger("oauth.device").trace("Device token poll deferred until due", metadata: ["dk.event": "oauth.device.poll.waiting",
                "dk.polls": .stringConvertible(polls)])
            return .waiting(retryAfter: clock.now.duration(to: nextPollAt))
        }
        guard polls < maximumPolls else { finish(); throw OAuthDeviceAuthorizationError.pollLimitExceeded }
        let logger = DiscordLog.makeLogger("oauth.device")
        logger.trace("Device token poll started", metadata: ["dk.event": "oauth.device.poll.started",
            "dk.polls": .stringConvertible(polls), "dk.maximum_polls": .stringConvertible(maximumPolls)])
        busy = true
        polls += 1
        defer { busy = false }
        do {
            let endpoint = try OAuthDeviceAuthorizationEndpoints.exchange(deviceCode: authorization.deviceCode, authentication: authentication)
            do {
                let tokens = try await rest.execute(endpoint)
                try Task.checkCancellation()
                guard !cancelled else { throw OAuthDeviceAuthorizationError.cancelled }
                guard clock.now < expiresAt else { throw OAuthDeviceAuthorizationError.expired }
                finish()
                logger.info("Device authorization completed", metadata: ["dk.event": "oauth.device.authorized"])
                return .authorized(tokens)
            } catch let error as APIResponseError {
                try Task.checkCancellation()
                guard !cancelled else { throw OAuthDeviceAuthorizationError.cancelled }
                guard clock.now < expiresAt else { throw OAuthDeviceAuthorizationError.expired }
                let code = error.withUnsafePayload { value -> String? in
                    guard case .object(let fields) = value, case .string(let code) = fields["error"] else { return nil }
                    return code
                }
                guard error.status == 400 else { throw OAuthDeviceAuthorizationError.authorizationFailed }
                switch code {
                case "authorization_pending":
                    logger.trace("Device authorization pending", metadata: ["dk.event": "oauth.device.pending"])
                    self.nextPollAt = clock.now.advanced(by: pollingInterval)
                    return .pending(retryAfter: pollingInterval)
                case "slow_down":
                    logger.notice("Device polling interval increased", metadata: ["dk.event": "oauth.device.slow_down"])
                    pollingInterval += .seconds(5)
                    self.nextPollAt = clock.now.advanced(by: pollingInterval)
                    return .slowDown(retryAfter: pollingInterval)
                case "access_denied": throw OAuthDeviceAuthorizationError.accessDenied
                case "expired_token": throw OAuthDeviceAuthorizationError.expired
                default: throw OAuthDeviceAuthorizationError.authorizationFailed
                }
            }
        } catch {
            if error is CancellationError || Task.isCancelled {
                logger.trace("Device token poll cancelled", metadata: ["dk.event": "oauth.device.poll.cancelled"])
            } else {
                logger.error("Device token polling terminated", metadata: ["dk.event": "oauth.device.poll.failed"])
            }
            finish()
            throw error
        }
    }

    /// Invalidates the flow, erases retained instructions, and rejects in-flight results.
    ///
    /// Idempotent; this starts no cleanup task and does not close the separately owned
    /// REST transport. To interrupt an outstanding HTTP request as well, cancel its
    /// calling task; submission may already have happened and cannot be undone.
    public func cancel() {
        if !cancelled {
            DiscordLog.makeLogger("oauth.device").debug("Device authorization cancelled", metadata: ["dk.event": "oauth.device.closed"])
        }
        cancelled = true
        finish()
    }

    /// Releases retained codes and scheduling state after a terminal outcome.
    /// Swift strings do not promise cryptographic memory erasure; caller copies remain caller-owned.
    private func finish() {
        finished = true
        authorization = nil
        expiresAt = nil
        nextPollAt = nil
    }

    /// Conceals credentials, instructions, and injected owners during ordinary formatting.
    public nonisolated var description: String { "OAuthDeviceAuthorizationFlow(redacted)" }
    /// Conceals credentials and state during debug formatting.
    public nonisolated var debugDescription: String { description }
    /// Prevents reflection from traversing retained codes or backend credentials.
    public nonisolated var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}
