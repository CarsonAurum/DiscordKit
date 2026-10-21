import DiscordLogging
import DiscordCore
import DiscordHTTP
import DiscordModels
import Foundation

/// Explicit client authentication. Public PKCE clients must be enabled for that flow in the Developer Portal.
/// A public app must never embed a confidential client secret. No native Social SDK capability is implied.
/// Discord's [authorization-server metadata](https://discord.com/.well-known/oauth-authorization-server),
/// verified 2026-10-17, advertises client_secret_post and none for token/revocation authentication, S256 and issuer responses.
public enum OAuthClientAuthentication: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    case confidential(clientID: ApplicationID, secret: ClientSecret)
    case publicPKCE(clientID: ApplicationID)

    /// Returns the initiating application's nonsecret identity without revealing a secret.
    public var clientID: ApplicationID {
        switch self {
        case .confidential(let clientID, _), .publicPKCE(let clientID): clientID
        }
    }
    /// Conceals all associated authentication data during normal diagnostics.
    public var description: String { "OAuthClientAuthentication(redacted)" }
    /// Conceals all associated authentication data during debug diagnostics.
    public var debugDescription: String { description }
    /// Prevents reflection from walking client authentication data.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}

/// Partial guild data returned by advanced bot authorization. It is a snapshot, never proof of current membership.
public struct OAuthAuthorizedGuild: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let id: GuildID
    public let name: String
    private let fields: [String: JSONValue]

    /// Validates the required partial guild identity and retains unknown future fields under the outer JSON bounds.
    /// - Parameter value: Already bounded guild object; no child resources are fetched.
    /// - Throws: `OAuthError.malformedResponse` for missing or invalid identity/name.
    fileprivate init(_ value: JSONValue) throws {
        guard case .object(let fields) = value, case .string(let id) = fields["id"],
              let parsed = GuildID(id), case .string(let name) = fields["name"] else { throw OAuthError.malformedResponse }
        self.id = parsed; self.name = name; self.fields = fields
    }
    /// Explicitly lends the bounded original guild fields to a synchronous caller operation.
    /// - Parameter body: Consumer responsible for sensitive membership/profile information and any unknown secrets.
    /// - Returns: Consumer result; this may retain copies.
    /// - Throws: Rethrows consumer errors without payload diagnostics.
    public func withUnsafeFields<Value>(_ body: ([String: JSONValue]) throws -> Value) rethrows -> Value { try body(fields) }
    /// Conceals guild information in normal diagnostics.
    public var description: String { "OAuthAuthorizedGuild(redacted)" }
    /// Conceals guild information in debug diagnostics.
    public var debugDescription: String { description }
    /// Prevents recursive payload diagnostics.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}

/// A redacted token result. Refresh omission is preserved for rotation policy; a missing token is not an instruction to clear one.
/// No automatic persistence, refresh task, expiry clock or bearer-client reconfiguration is started.
public struct OAuthTokenResponse: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let accessToken: BearerToken
    public let refreshToken: OAuthRefreshToken?
    /// Whole seconds from token issuance; coordinators conservatively anchor this to request start.
    public let expiresIn: Int
    public let scopes: Set<String>
    public let webhook: Webhook?
    public let guild: OAuthAuthorizedGuild?

    /// Creates a caller-owned token result for injected providers and secure-store restoration.
    /// - Parameters:
    ///   - accessToken: Nonempty redacted bearer credential, at most 8 KiB of UTF-8.
    ///   - refreshToken: Optional refresh credential, at most 8 KiB; nil preserves server omission.
    ///   - expiresIn: Positive relative lifetime in seconds; zero/negative values fail.
    ///   - scopes: Bounded RFC scope tokens; empty explicitly means no granted scopes.
    /// - Throws: `OAuthError.invalidRequest` for invalid lifetime, oversized credentials or malformed/bounded-out scopes.
    public init(accessToken: BearerToken, refreshToken: OAuthRefreshToken? = nil, expiresIn: Int, scopes: Set<String>) throws {
        try oauthValidateScopes(scopes)
        guard expiresIn > 0, accessToken.withUnsafeValue({ $0.utf8.count <= 8_192 }),
              refreshToken?.withUnsafeValue({ $0.utf8.count <= 8_192 }) ?? true else { throw OAuthError.invalidRequest }
        self.accessToken = accessToken; self.refreshToken = refreshToken; self.expiresIn = expiresIn; self.scopes = scopes
        webhook = nil; guild = nil
    }

    /// Parses Discord's token, advanced bot and incoming-webhook token-response variants under 1 MiB JSON bounds.
    /// - Parameter data: Complete JSON response. Access/refresh secrets are wrapped; unknown top-level fields are ignored.
    /// - Throws: `OAuthError.malformedResponse` for invalid JSON, duplicate keys, missing fields, non-Bearer token type,
    ///   invalid positive expiry, credential syntax/size, malformed scopes or malformed present webhook/guild data.
    /// No server-provided error description or raw payload is included in failures.
    public init(data: Data) throws {
        do {
            guard case .object(let fields) = try JSONValue.parse(data),
                  case .string(let access) = fields["access_token"], case .string(let type) = fields["token_type"],
                  type.lowercased() == "bearer", case .number(let expiry) = fields["expires_in"],
                  expiry.rawValue.utf8.allSatisfy({ (48...57).contains($0) }), let seconds = Int(expiry.rawValue),
                  case .string(let scope) = fields["scope"] else { throw OAuthError.malformedResponse }
            let refresh: OAuthRefreshToken?
            if let value = fields["refresh_token"] {
                guard case .string(let text) = value else { throw OAuthError.malformedResponse }
                refresh = try OAuthRefreshToken(text)
            } else { refresh = nil }
            let validated = try Self(accessToken: BearerToken(access), refreshToken: refresh, expiresIn: seconds, scopes: oauthParseScopes(scope))
            accessToken = validated.accessToken; refreshToken = validated.refreshToken
            expiresIn = validated.expiresIn; scopes = validated.scopes
            if let value = fields["webhook"] { webhook = try Webhook(data: value.serialized()) } else { webhook = nil }
            if let value = fields["guild"] { guild = try OAuthAuthorizedGuild(value) } else { guild = nil }
        } catch { throw OAuthError.malformedResponse }
    }
    /// Conceals every response field, including webhook URL/token and guild data.
    public var description: String { "OAuthTokenResponse(redacted)" }
    /// Conceals every response field during debug formatting.
    public var debugDescription: String { description }
    /// Prevents recursive reflection from exposing tokens or associated payloads.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}

/// Partial application in authorization information; no full Application-resource coverage is implied.
public struct OAuthAuthorizationApplication: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let id: ApplicationID
    public let name: String
    private let fields: [String: JSONValue]
    /// Projects required partial identity while retaining the bounded original object for forward compatibility.
    /// - Parameter value: Nonnull partial application object with string id/name.
    /// - Throws: `OAuthError.malformedResponse` for missing or invalid identity/name.
    fileprivate init(_ value: JSONValue) throws {
        guard case .object(let fields) = value, case .string(let id) = fields["id"],
              let parsed = ApplicationID(id), case .string(let name) = fields["name"] else { throw OAuthError.malformedResponse }
        self.id = parsed; self.name = name; self.fields = fields
    }
    /// Deliberately lends the original bounded application subtree to a synchronous consumer.
    /// - Parameter body: Consumer responsible for keeping any sensitive future fields out of diagnostics.
    /// - Returns: Consumer result; it may retain copied data.
    /// - Throws: Rethrows consumer errors without unsafe details.
    public func withUnsafeFields<Value>(_ body: ([String: JSONValue]) throws -> Value) rethrows -> Value { try body(fields) }
    /// Conceals payload fields during normal diagnostics.
    public var description: String { "OAuthAuthorizationApplication(redacted)" }
    /// Conceals payload fields during debug diagnostics.
    public var debugDescription: String { description }
    /// Prevents recursive payload diagnostics.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}

/// Snapshot of GET /oauth2/@me. Returned scopes describe this bearer authorization, not future eligibility.
public struct OAuthAuthorizationInformation: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let application: OAuthAuthorizationApplication
    public let scopes: Set<String>
    public let expires: String
    /// Optional partial User object: identify-gated fields may differ from the complete User resource's baseline.
    public let user: MessageAuthor?

    /// Parses a bounded current-authorization response while preserving an optional partial user as an owned resource.
    /// - Parameter data: Complete JSON with application, scope array and RFC3339 expiration timestamp.
    /// - Throws: `OAuthError.malformedResponse` for bounded JSON errors, malformed identity/scopes/timestamp or present user.
    /// This does not create a timer, refresh credentials, or establish the authorization is still current.
    public init(data: Data) throws {
        do {
            guard case .object(let fields) = try JSONValue.parse(data), let app = fields["application"],
                  case .array(let values) = fields["scopes"], values.count <= 128,
                  case .string(let expires) = fields["expires"], expires.utf8.count <= 128,
                  ((try? Date(expires, strategy: .iso8601)) != nil ||
                   (try? Date(expires, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true))) != nil)
            else { throw OAuthError.malformedResponse }
            let scopes = try Set(values.map { value in
                guard case .string(let text) = value else { throw OAuthError.malformedResponse }; return text
            })
            try oauthValidateScopes(scopes)
            application = try OAuthAuthorizationApplication(app); self.scopes = scopes; self.expires = expires
            if let value = fields["user"] { user = try MessageAuthor(data: value.serialized()) } else { user = nil }
        } catch { throw OAuthError.malformedResponse }
    }
    /// Conceals all authorization and user fields in diagnostics.
    public var description: String { "OAuthAuthorizationInformation(redacted)" }
    /// Conceals payload fields during debug formatting.
    public var debugDescription: String { description }
    /// Prevents recursive payload diagnostics.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}

/// Explicit API v10 OAuth descriptors. All grants/revocations use bounded form bodies, header-free client authentication,
/// no read reuse and unsafe submission semantics. Discord's server/resource/global admission remains in the injected REST pipeline.
public enum OAuthEndpoints {
    /// Exchanges one Activity AUTHORIZE code exclusively on a confidential backend, independently of redirect flows.
    /// The [official Activity tutorial](https://docs.discord.com/developers/activities/building-an-activity#step-5-authorizing--authenticating-users)
    /// uses code/client_id/client_secret/grant_type without a redirect URI; the Discord host owns iframe authorization.
    /// - Parameters:
    ///   - code: Single-use code from an authenticated Activity host and an application-authenticated backend session.
    ///     The backend must bind this request to its expected application/user session and enforce replay/CSRF policy.
    ///   - authentication: Confidential application credentials stored only on the backend. Public PKCE clients fail.
    ///   - pkceVerifier: Matching S256 verifier only if code_challenge was sent to AUTHORIZE; nil matches the tutorial.
    ///     Present values must satisfy RFC 7636's 43...128 unreserved ASCII characters; entropy is caller-owned.
    /// - Returns: Unsafe POST /api/v10/oauth2/token descriptor with form-only client authentication and bounded response.
    ///   It is never read-coalesced or automatically replayed after ambiguous submission. No I/O or storage occurs here.
    /// - Throws: `OAuthError.unsupportedClient` for public clients, `OAuthError.invalidRequest` for malformed proof/size,
    ///   or bounded descriptor/body errors. Execution may reject expired/reused/foreign codes; obtain fresh host consent.
    public static func activityAuthorizationCode(_ code: OAuthCode, authentication: OAuthClientAuthentication,
                                                 pkceVerifier: OAuthPKCEVerifier? = nil) throws -> Endpoint<OAuthTokenResponse> {
        guard case .confidential = authentication else { throw OAuthError.unsupportedClient }
        var fields = [QueryItem(name: "grant_type", value: "authorization_code"),
                      QueryItem(name: "code", value: code.withUnsafeValue { $0 })]
        if let pkceVerifier {
            let proof = try OAuthPKCE(verifier: pkceVerifier.withUnsafeValue { $0 })
            fields.append(QueryItem(name: "code_verifier", value: proof.verifier.withUnsafeValue { $0 }))
        }
        return try token(fields: fields, authentication: authentication)
    }

    /// Exchanges a redirect-validated authorization code, preserving its exact redirect and S256 verifier.
    /// - Parameters:
    ///   - authorization: One redirect-validated code result. The caller must avoid redeeming copied values repeatedly.
    ///   - authentication: Matching confidential client or deliberately enabled public PKCE client.
    ///   - externalAuthType: Optional provisional-account merge credential type; paired with externalAuthToken.
    ///   - externalAuthToken: Optional redacted provisional access token; never an external user identifier.
    /// - Returns: Unsafe POST /oauth2/token descriptor; HTTP 200 decodes a bounded redacted token response.
    /// - Throws: Closed invalid-request errors for client mismatch/unpaired merge fields; bounded body/descriptor errors now.
    ///   Execution can fail with OAuth/API/admission/transport errors or indeterminate submitted mutation outcomes.
    public static func authorizationCode(_ authorization: OAuthAuthorizationCode, authentication: OAuthClientAuthentication,
                                         externalAuthType: String? = nil, externalAuthToken: BearerToken? = nil) throws -> Endpoint<OAuthTokenResponse> {
        guard authorization.clientID == authentication.clientID,
              (externalAuthType == nil) == (externalAuthToken == nil),
              externalAuthType.map({ !$0.isEmpty && $0.utf8.count <= 128 && $0.utf8.allSatisfy({ (65...90).contains($0) || (48...57).contains($0) || $0 == 95 }) }) ?? true
        else { throw OAuthError.invalidRequest }
        var fields = [QueryItem(name: "grant_type", value: "authorization_code"),
            QueryItem(name: "code", value: authorization.code.withUnsafeValue { $0 }),
            QueryItem(name: "redirect_uri", value: authorization.redirectURI.absoluteString),
            QueryItem(name: "code_verifier", value: authorization.pkce.verifier.withUnsafeValue { $0 })]
        if let externalAuthType, let externalAuthToken {
            fields += [QueryItem(name: "external_auth_type", value: externalAuthType),
                QueryItem(name: "external_auth_token", value: externalAuthToken.withUnsafeValue { $0 })]
        }
        return try token(fields: fields, authentication: authentication)
    }

    /// Exchanges a refresh credential without caching or replaying an ambiguous send.
    /// - Parameters:
    ///   - refreshToken: The current stored refresh token. A successful response can rotate it.
    ///   - authentication: Owning confidential client or configured public client.
    /// - Returns: Unsafe POST /oauth2/token descriptor. Omitted refresh tokens remain nil for store policy.
    /// - Throws: Local size/client/body validation failures now; execution follows shared bounded HTTP policy.
    public static func refresh(_ refreshToken: OAuthRefreshToken, authentication: OAuthClientAuthentication) throws -> Endpoint<OAuthTokenResponse> {
        try token(fields: [QueryItem(name: "grant_type", value: "refresh_token"),
            QueryItem(name: "refresh_token", value: refreshToken.withUnsafeValue { $0 })], authentication: authentication)
    }

    /// Requests an application bearer using confidential client credentials.
    /// - Parameters:
    ///   - scopes: Nonempty bounded requested scopes; Discord/team restrictions and approval remain server checks.
    ///   - authentication: Must be confidential; public PKCE has no client-credentials grant.
    /// - Returns: Unsafe POST /oauth2/token descriptor; client-credentials responses generally omit a refresh token.
    /// - Throws: `OAuthError.unsupportedClient` for public clients; scope/body/descriptor validation failures now.
    public static func clientCredentials(scopes: Set<String>, authentication: OAuthClientAuthentication) throws -> Endpoint<OAuthTokenResponse> {
        guard case .confidential = authentication else { throw OAuthError.unsupportedClient }
        try oauthValidateScopes(scopes, allowEmpty: false)
        return try token(fields: [QueryItem(name: "grant_type", value: "client_credentials"),
            QueryItem(name: "scope", value: scopes.sorted().joined(separator: " "))], authentication: authentication)
    }

    /// Revokes an access token and every active token associated with that authorization, per Discord's contract.
    /// - Parameters:
    ///   - accessToken: Access credential to revoke; the response never echoes it.
    ///   - authentication: Owning configured client authentication.
    /// - Returns: Unsafe POST /oauth2/token/revoke accepting documented HTTP 200 empty or empty-object acknowledgement,
    ///   and 204 compatibility. Acknowledgement does not itself erase local secure storage.
    /// - Throws: Local client/body/descriptor errors now; submitted uncertainty requires caller reconciliation.
    public static func revoke(accessToken: BearerToken, authentication: OAuthClientAuthentication) throws -> Endpoint<EmptyResponse> {
        try revocation(token: accessToken.withUnsafeValue { $0 }, hint: "access_token", authentication: authentication)
    }

    /// Revokes a refresh token and its associated authorization tokens.
    /// - Parameters:
    ///   - refreshToken: Refresh credential to revoke.
    ///   - authentication: Owning configured client authentication.
    /// - Returns: The same bounded acknowledgement descriptor as access-token revocation, with refresh_token hint.
    /// - Throws: Local client/body/descriptor errors now; HTTP/API/transport/cancellation failures on execution.
    public static func revoke(refreshToken: OAuthRefreshToken, authentication: OAuthClientAuthentication) throws -> Endpoint<EmptyResponse> {
        try revocation(token: refreshToken.withUnsafeValue { $0 }, hint: "refresh_token", authentication: authentication)
    }

    /// Gets the current bearer authorization without retained read reuse.
    /// - Returns: Safe, bearer-authenticated GET /oauth2/@me; HTTP 200 partial application/user snapshot.
    /// - Throws: Descriptor errors now; bearer/API/transport/decode/admission failures at execution.
    public static func currentAuthorization() throws -> Endpoint<OAuthAuthorizationInformation> {
        try Endpoint(method: "GET", path: ["oauth2", "@me"], authentication: .bearer,
            retrySafety: .safe, decode: { try OAuthAuthorizationInformation(data: $0) })
    }

    /// Gets the bot's application through the OAuth reference's documented compatibility route.
    /// - Returns: Safe bot-authenticated GET /oauth2/applications/@me with complete owned Application projection.
    /// - Throws: Descriptor errors now; bot/API/transport/decode/admission failures at execution.
    public static func currentBotApplication() throws -> Endpoint<Application> {
        try Endpoint(method: "GET", path: ["oauth2", "applications", "@me"], authentication: .bot,
            retrySafety: .safe, decode: { try Application(data: $0) })
    }

    /// Wraps finite grant fields in the versioned token descriptor without header authentication.
    /// - Parameters:
    ///   - fields: Owned grant-specific form fields; token strings never enter route metadata.
    ///   - authentication: Appends client_id and, only for confidential clients, client_secret.
    /// - Returns: Unsafe, uncached HTTP 200 token descriptor with a 64 KiB body cap.
    /// - Throws: Client or bounded-body/descriptor errors, without untrusted input diagnostics.
    private static func token(fields: [QueryItem], authentication: OAuthClientAuthentication) throws -> Endpoint<OAuthTokenResponse> {
        try Endpoint(method: "POST", path: ["oauth2", "token"], authentication: .none,
            body: form(fields: fields, authentication: authentication), decode: { try OAuthTokenResponse(data: $0) })
    }

    /// Encodes one bounded client-authenticated revocation descriptor with explicit success variants.
    /// - Parameters:
    ///   - token: Raw secret used only to build the bounded form body; never retained in diagnostics.
    ///   - hint: Closed caller-owned access_token or refresh_token value.
    ///   - authentication: Client ID and optional confidential secret.
    /// - Returns: Unsafe descriptor accepting empty bytes or an exact empty object on 200/204.
    /// - Throws: Bounded form/descriptor errors now; malformed nonempty success responses fail safely later.
    private static func revocation(token: String, hint: String, authentication: OAuthClientAuthentication) throws -> Endpoint<EmptyResponse> {
        try Endpoint(method: "POST", path: ["oauth2", "token", "revoke"], authentication: .none, successStatuses: [200, 204],
            body: form(fields: [QueryItem(name: "token", value: token), QueryItem(name: "token_type_hint", value: hint)], authentication: authentication), decode: { data in
                if !data.isEmpty {
                    guard case .object(let value) = try JSONValue.parse(data), value.isEmpty else { throw OAuthError.malformedResponse }
                }
                return try EmptyResponse(data: Data())
            })
    }

    /// Adds owned client authentication fields and percent-encodes each form value exactly once.
    /// - Parameters:
    ///   - fields: Finite internal grant fields whose individual values are capped at 8 KiB.
    ///   - authentication: Nonzero client ID; confidential secrets are submitted in the body, never URL/userinfo.
    /// - Returns: Redacted materialized form body capped at 64 KiB.
    /// - Throws: Closed invalid-request/client errors or safe body-size validation failures.
    private static func form(fields: [QueryItem], authentication: OAuthClientAuthentication) throws -> RequestBody {
        guard authentication.clientID.rawValue != 0,
              fields.allSatisfy({ ($0.value?.utf8.count ?? 0) <= 8_192 }) else { throw OAuthError.invalidRequest }
        var fields = fields + [QueryItem(name: "client_id", value: authentication.clientID.description)]
        if case .confidential(_, let secret) = authentication {
            guard secret.withUnsafeValue({ $0.utf8.count <= 8_192 }) else { throw OAuthError.invalidRequest }
            fields.append(QueryItem(name: "client_secret", value: secret.withUnsafeValue { $0 }))
        }
        return try RequestBody.form(fields, maximumBytes: 65_536)
    }
}

/// Independently adopted OAuth execution through an injected, separately owned REST client.
/// Construction starts no tasks or network I/O. Share HTTP/rate authorities across workers and refresh coordinators
/// across consumers of one authorization; OAuth token exchanges are never eligible read-coalescing operations.
public struct OAuthClient<C: Clock>: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable where C.Duration == Duration {
    private let rest: RESTClient<C>
    private let authentication: OAuthClientAuthentication

    /// Binds a client-authentication mode to an existing bounded HTTP pipeline without taking ownership of it.
    /// - Parameters:
    ///   - rest: Header-free REST pipeline, normally credential .none, with shared IP/egress admission and finite retry budgets.
    ///     Endpoint authentication .none prevents any configured bot/bearer header from reaching token requests.
    ///   - authentication: Confidential server credentials or explicitly configured public PKCE client; never inferred.
    public init(rest: RESTClient<C>, authentication: OAuthClientAuthentication) { self.rest = rest; self.authentication = authentication }

    /// Exchanges one redirect-validated code, optionally merging a provisional account in the same grant.
    /// - Parameters:
    ///   - authorization: Validated single-use code result; copies are not automatically coordinated by this value facade.
    ///   - externalAuthType: Optional documented merge credential-type spelling.
    ///   - externalAuthToken: Optional provisional access token paired with externalAuthType.
    /// - Returns: Bounded redacted token result. Caller or token coordinator owns persistence and expiry.
    /// - Throws: Closed OAuth invalid-grant/failure categories, local validation or safe bounded HTTP errors.
    ///   Ambiguous submitted requests are not blindly retried; 429 server rejection follows the injected finite budget.
    public func exchange(_ authorization: OAuthAuthorizationCode, externalAuthType: String? = nil,
                         externalAuthToken: BearerToken? = nil) async throws -> OAuthTokenResponse {
        try await execute(OAuthEndpoints.authorizationCode(authorization, authentication: authentication,
            externalAuthType: externalAuthType, externalAuthToken: externalAuthToken))
    }

    /// Exchanges the current refresh token. Coordinate simultaneous refreshes through OAuthTokenCoordinator.
    /// - Parameter refreshToken: Current redacted refresh credential; successful rotation must persist atomically.
    /// - Returns: New token response, preserving refresh-token omission.
    /// - Throws: `.invalidGrant` only for an explicit OAuth invalid_grant response, plus closed OAuth/HTTP failures.
    public func refresh(refreshToken: OAuthRefreshToken) async throws -> OAuthTokenResponse {
        try await execute(OAuthEndpoints.refresh(refreshToken, authentication: authentication))
    }

    /// Requests an application bearer via the confidential-client credentials grant.
    /// - Parameter scopes: Nonempty, bounded requested scopes, subject to Discord/team approval policy.
    /// - Returns: New application bearer token; no scheduled work or persistence starts.
    /// - Throws: `.unsupportedClient` for public PKCE clients, plus closed OAuth and bounded HTTP failures.
    public func clientCredentials(scopes: Set<String>) async throws -> OAuthTokenResponse {
        try await execute(OAuthEndpoints.clientCredentials(scopes: scopes, authentication: authentication))
    }

    /// Revokes the supplied access token and associated authorization tokens remotely.
    /// - Parameter accessToken: Credential to revoke. Local secure-store erasure is a separate caller-owned transaction.
    /// - Throws: Closed OAuth failures and safe bounded HTTP errors; uncertain submitted outcomes require reconciliation.
    public func revoke(accessToken: BearerToken) async throws {
        _ = try await execute(OAuthEndpoints.revoke(accessToken: accessToken, authentication: authentication))
    }

    /// Revokes the supplied refresh token and associated authorization tokens remotely.
    /// - Parameter refreshToken: Credential to revoke; the secure-store owner remains responsible for erasure.
    /// - Throws: Closed OAuth failures and safe bounded HTTP errors; cancellation/transport after submission can be uncertain.
    public func revoke(refreshToken: OAuthRefreshToken) async throws {
        _ = try await execute(OAuthEndpoints.revoke(refreshToken: refreshToken, authentication: authentication))
    }

    /// Maps only recognized OAuth machine error codes; raw descriptions and payloads never escape this facade.
    /// - Parameter endpoint: Bounded OAuth descriptor with header-free client authentication.
    /// - Returns: Descriptor result after coordinated HTTP execution.
    /// - Throws: Explicit invalidGrant/accessDenied/invalidRequest or fixed authorizationFailed for API errors;
    ///   transport/admission/cancellation/uncertainty errors propagate with their existing safe categories.
    private func execute<Value: Sendable>(_ endpoint: Endpoint<Value>) async throws -> Value {
        return try await DiscordLog.withOperation("oauth.http", event: "oauth.exchange") {
            try await executeOwned(endpoint)
        }
    }

    /// Executes the credential-bearing descriptor within an inherited diagnostic scope.
    /// - Parameter endpoint: Original request whose URL, headers and body remain unlogged.
    /// - Returns: The unchanged coordinated HTTP result.
    /// - Throws: Recognized OAuth or original sanitized execution failures.
    private func executeOwned<Value: Sendable>(_ endpoint: Endpoint<Value>) async throws -> Value {
        let logger = DiscordLog.makeLogger("oauth.http")
        logger.trace("OAuth request started", metadata: ["dk.event": "oauth.request.started"])
        do {
            logger.trace("OAuth coordinated HTTP execution admitted", metadata: ["dk.event": "oauth.request.http.admitted"])
            let response = try await rest.execute(endpoint)
            logger.trace("OAuth response decoded", metadata: ["dk.event": "oauth.request.response.decoded"])
            logger.debug("OAuth request completed", metadata: ["dk.event": "oauth.request.completed"])
            return response
        }
        catch let error as APIResponseError {
            logger.debug("OAuth request rejected", metadata: ["dk.event": "oauth.request.rejected",
                "dk.status": .stringConvertible(error.status)])
            let code = error.withUnsafePayload { value -> String? in
                guard case .object(let fields) = value, case .string(let code) = fields["error"] else { return nil }; return code
            }
            switch code {
            case "invalid_grant" where error.status == 400: throw OAuthError.invalidGrant
            case "access_denied": throw OAuthError.accessDenied
            case "invalid_request": throw OAuthError.invalidRequest
            default: throw OAuthError.authorizationFailed
            }
        } catch {
            if error is CancellationError || Task.isCancelled {
                logger.trace("OAuth request cancelled", metadata: ["dk.event": "oauth.request.cancelled"])
            } else {
                logger.debug("OAuth request failed", metadata: ["dk.event": "oauth.request.failed",
                    "dk.failure": .string("execution")])
            }
            throw error
        }
    }
    /// Conceals the HTTP pipeline and client authentication.
    public var description: String { "OAuthClient(redacted)" }
    /// Conceals the HTTP pipeline and client authentication in debug diagnostics.
    public var debugDescription: String { description }
    /// Prevents recursive diagnostics from traversing injected owners.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}
