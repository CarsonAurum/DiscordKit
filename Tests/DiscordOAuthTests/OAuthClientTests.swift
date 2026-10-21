import DiscordLogging
import DiscordCore
import DiscordHTTP
import DiscordModels
import DiscordTestSupport
import DiscordTransport
import Foundation
import Testing
@testable import DiscordOAuth

/// Offline OAuth form/execution/response tests. All secrets are synthetic and no Discord or browser requests occur.
@Suite(.timeLimit(.minutes(1))) struct OAuthClientTests {
    /// Preserves omitted refresh tokens, scopes, typed webhook/guild variants and redacted token diagnostics.
    @Test func tokenResponseVariants() throws {
        let basic = try OAuthTokenResponse(data: Data(tokenJSON.utf8))
        #expect(basic.accessToken.withUnsafeValue { $0 } == "access_secret")
        #expect(basic.refreshToken?.withUnsafeValue { $0 } == "refresh_secret")
        #expect(basic.expiresIn == 60)
        #expect(basic.scopes == ["identify", "future.scope"])
        #expect(basic.webhook == nil)
        #expect(basic.guild == nil)
        let clientCredentials = try OAuthTokenResponse(data: Data("{\"access_token\":\"application_secret\",\"token_type\":\"bearer\",\"expires_in\":1,\"scope\":\"\",\"future\":\"unknown_secret\"}".utf8))
        #expect(clientCredentials.refreshToken == nil)
        #expect(clientCredentials.scopes.isEmpty)
        let enriched = try OAuthTokenResponse(data: Data("""
        {"access_token":"access_secret","token_type":"Bearer","expires_in":60,"scope":"bot webhook.incoming", "guild":{"id":"18446744073709551615","name":"Synthetic guild","future":"unknown_secret"}, "webhook":{"id":"18446744073709551615","type":1,"channel_id":"2","name":"Synthetic","avatar":null,"application_id":"1","token":"webhook_secret","url":"https://discord.com/api/webhooks/1/webhook_secret"}}
        """.utf8))
        #expect(enriched.guild?.id.rawValue == .max)
        #expect(enriched.guild?.name == "Synthetic guild")
        #expect(enriched.guild?.withUnsafeFields { $0["future"] } == .string("unknown_secret"))
        #expect(enriched.webhook?.id.rawValue == .max)
        guard case .value(let webhookToken) = enriched.webhook?.token else { Issue.record("Expected webhook token"); return }
        #expect(webhookToken.withUnsafeValue { $0 } == "webhook_secret")
        #expect(enriched.webhook?.withUnsafeURL { $0 } == "https://discord.com/api/webhooks/1/webhook_secret")
        #expect(basic.description == "OAuthTokenResponse(redacted)")
        #expect(String(reflecting: enriched) == "OAuthTokenResponse(redacted)")
        #expect(basic.customMirror.children.count == 1)
        #expect(enriched.guild?.description == "OAuthAuthorizedGuild(redacted)")
        #expect(enriched.guild?.debugDescription == enriched.guild?.description)
        #expect(enriched.guild?.customMirror.children.count == 1)
    }

    /// Rejects wrong/missing/null fields, nonintegral expiry, credential controls and invalid child variants safely.
    /// - Parameter json: A deliberately malformed token response, never sent to Discord.
    @Test(arguments: [
        "{}", "[]", "not JSON",
        "{\"access_token\":\"x\",\"token_type\":\"Bot\",\"expires_in\":1,\"scope\":\"identify\"}",
        "{\"access_token\":\"x\",\"token_type\":\"Bearer\",\"expires_in\":0,\"scope\":\"identify\"}",
        "{\"access_token\":\"x\",\"token_type\":\"Bearer\",\"expires_in\":-1,\"scope\":\"identify\"}",
        "{\"access_token\":\"x\",\"token_type\":\"Bearer\",\"expires_in\":1.0,\"scope\":\"identify\"}",
        "{\"access_token\":\"x\",\"token_type\":\"Bearer\",\"expires_in\":1e2,\"scope\":\"identify\"}",
        "{\"access_token\":\"x\",\"token_type\":\"Bearer\",\"expires_in\":99999999999999999999999999,\"scope\":\"identify\"}",
        "{\"access_token\":null,\"token_type\":\"Bearer\",\"expires_in\":1,\"scope\":\"identify\"}",
        "{\"access_token\":\"synthetic secret\",\"token_type\":\"Bearer\",\"expires_in\":1,\"scope\":\"identify\"}",
        "{\"access_token\":\"x\",\"token_type\":\"Bearer\",\"expires_in\":1,\"scope\":\" identify\"}",
        "{\"access_token\":\"x\",\"token_type\":\"Bearer\",\"expires_in\":1,\"scope\":\"identify\",\"refresh_token\":null}",
        "{\"access_token\":\"x\",\"token_type\":\"Bearer\",\"expires_in\":1,\"scope\":\"identify\",\"webhook\":null}",
        "{\"access_token\":\"x\",\"token_type\":\"Bearer\",\"expires_in\":1,\"scope\":\"identify\",\"guild\":{\"id\":\"bad\",\"name\":\"bad\"}}",
        "{\"access_token\":\"x\",\"access_token\":\"y\",\"token_type\":\"Bearer\",\"expires_in\":1,\"scope\":\"identify\"}"
    ]) func malformedTokenResponses(json: String) {
        #expect(throws: OAuthError.malformedResponse) { try OAuthTokenResponse(data: Data(json.utf8)) }
    }

    /// Enforces programmatic response lifetime/credential/scope bounds and documents zero-scope response support.
    @Test func tokenResponseInputBounds() throws {
        #expect(throws: OAuthError.invalidRequest) { try OAuthTokenResponse(accessToken: BearerToken("x"), expiresIn: 0, scopes: []) }
        #expect(throws: OAuthError.invalidRequest) { try OAuthTokenResponse(accessToken: BearerToken(String(repeating: "x", count: 8_193)), expiresIn: 1, scopes: []) }
        #expect(throws: OAuthError.invalidRequest) { try OAuthTokenResponse(accessToken: BearerToken("x"), refreshToken: OAuthRefreshToken(String(repeating: "x", count: 8_193)), expiresIn: 1, scopes: []) }
        #expect(throws: OAuthError.invalidRequest) { try OAuthTokenResponse(accessToken: BearerToken("x"), expiresIn: 1, scopes: ["bad scope"]) }
        #expect(throws: OAuthError.invalidRequest) { try oauthValidateScopes(Set((0..<129).map { "scope\($0)" })) }
        #expect(throws: OAuthError.invalidRequest) { try oauthValidateScopes(Set((0..<40).map { String(repeating: "x", count: 250) + String($0) })) }
        #expect(try oauthParseScopes("") == [])
        #expect(try oauthParseScopes("identify identify") == ["identify"])
    }

    /// Checks body-only confidential authentication, exactly-once escaping, explicit v10, S256 and optional merge grant fields.
    @Test func codeExchangeFormsAndClientMatching() async throws {
        let authorization = try await codeResult()
        let auth = OAuthClientAuthentication.confidential(clientID: .init(rawValue: 1), secret: try ClientSecret("secret+&=é"))
        let endpoint = try OAuthEndpoints.authorizationCode(authorization, authentication: auth,
            externalAuthType: "DISCORD_BOT_ISSUED_ACCESS_TOKEN", externalAuthToken: BearerToken("external+secret"))
        let request = try endpoint.makeRequest(credential: .bot(BotToken("unused_bot")), userAgent: "test")
        #expect(request.url.absoluteString == "https://discord.com/api/v10/oauth2/token")
        #expect(request.method == "POST")
        #expect(!request.headers.contains { $0.name.lowercased() == "authorization" })
        #expect(request.headers.contains { $0.name.lowercased() == "content-type" && $0.value == "application/x-www-form-urlencoded" })
        let body = try #require(endpoint.body)
        let form = String(decoding: body.bytes, as: UTF8.self)
        #expect(form.contains("client_secret=secret%2B%26%3D%C3%A9"))
        #expect(form.contains("code=synthetic%2Bcode"))
        #expect(form.contains("redirect_uri=https%3A%2F%2Fexample.com%2Fcallback"))
        #expect(form.contains("code_verifier="))
        #expect(form.contains("grant_type=authorization_code"))
        #expect(form.contains("external_auth_type=DISCORD_BOT_ISSUED_ACCESS_TOKEN"))
        #expect(form.contains("external_auth_token=external%2Bsecret"))
        #expect(endpoint.authentication == .none)
        #expect(endpoint.retrySafety == .unsafe)
        #expect(endpoint.readPolicy == nil)
        #expect(!String(reflecting: endpoint).contains("secret"))
        #expect(auth.clientID.rawValue == 1)
        #expect(auth.description == "OAuthClientAuthentication(redacted)")
        #expect(auth.debugDescription == auth.description)
        #expect(auth.customMirror.children.count == 1)
        await request.body?.close()
        let publicAuth = OAuthClientAuthentication.publicPKCE(clientID: .init(rawValue: 1))
        let publicForm = try #require(OAuthEndpoints.authorizationCode(authorization, authentication: publicAuth).body)
        #expect(!String(decoding: publicForm.bytes, as: UTF8.self).contains("client_secret"))
        #expect(throws: OAuthError.invalidRequest) { try OAuthEndpoints.authorizationCode(authorization, authentication: .publicPKCE(clientID: .init(rawValue: 2))) }
        #expect(throws: OAuthError.invalidRequest) { try OAuthEndpoints.authorizationCode(authorization, authentication: publicAuth, externalAuthType: "STEAM") }
        #expect(throws: OAuthError.invalidRequest) { try OAuthEndpoints.authorizationCode(authorization, authentication: publicAuth, externalAuthType: "bad type", externalAuthToken: BearerToken("x")) }
    }

    /// Exercises refresh/client credentials and both revocation hints, accepted acknowledgement variants and body bounds.
    @Test func refreshCredentialsAndRevocationDescriptors() throws {
        let auth = OAuthClientAuthentication.confidential(clientID: .init(rawValue: 1), secret: try ClientSecret("secret"))
        let refresh = try OAuthEndpoints.refresh(OAuthRefreshToken("refresh+secret"), authentication: auth)
        #expect(String(decoding: try #require(refresh.body).bytes, as: UTF8.self).contains("refresh_token=refresh%2Bsecret"))
        let credentials = try OAuthEndpoints.clientCredentials(scopes: ["identify", "applications.commands.update"], authentication: auth)
        let form = String(decoding: try #require(credentials.body).bytes, as: UTF8.self)
        #expect(form.contains("grant_type=client_credentials"))
        #expect(form.contains("scope=applications.commands.update+identify"))
        #expect(throws: OAuthError.unsupportedClient) { try OAuthEndpoints.clientCredentials(scopes: ["identify"], authentication: .publicPKCE(clientID: .init(rawValue: 1))) }
        #expect(throws: OAuthError.invalidRequest) { try OAuthEndpoints.clientCredentials(scopes: [], authentication: auth) }
        #expect(throws: OAuthError.invalidRequest) { try OAuthEndpoints.refresh(OAuthRefreshToken("x"), authentication: .publicPKCE(clientID: .init(rawValue: 0))) }
        #expect(throws: OAuthError.invalidRequest) { try OAuthEndpoints.refresh(OAuthRefreshToken(String(repeating: "x", count: 8_193)), authentication: auth) }
        let access = try OAuthEndpoints.revoke(accessToken: BearerToken("access"), authentication: auth)
        let refreshRevoke = try OAuthEndpoints.revoke(refreshToken: OAuthRefreshToken("refresh"), authentication: auth)
        #expect(access.path == ["oauth2", "token", "revoke"])
        #expect(access.successStatuses == [200, 204])
        #expect(String(decoding: try #require(access.body).bytes, as: UTF8.self).contains("token_type_hint=access_token"))
        #expect(String(decoding: try #require(refreshRevoke.body).bytes, as: UTF8.self).contains("token_type_hint=refresh_token"))
        _ = try access.decode(Data())
        _ = try access.decode(Data("{}".utf8))
        #expect(throws: OAuthError.malformedResponse) { try access.decode(Data("{\"token\":\"unexpected_secret\"}".utf8)) }
    }

    /// Executes every grant facade and revocation through a finite scripted REST pipeline without extra I/O or credential headers.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func facadeExecutesBoundedGrantSequence() async throws {
        let transport = try ScriptedHTTPTransport(steps: [
            { request in
                #expect(request.url.path == "/api/v10/oauth2/token")
                #expect(!request.headers.contains { $0.name == "Authorization" })
                return try oauthResponse(tokenJSON)
            }, { _ in try oauthResponse(tokenJSON) }, { _ in try oauthResponse(tokenJSON) },
            { _ in HTTPResponse(status: 200) }, { _ in try oauthResponse("{}") }
        ])
        let clock = ManualClock()
        let rate = RateLimitCoordinator(clock: clock)
        let rest = RESTClient(credential: .none, identity: RateLimitIdentity(), transport: transport, coordinator: rate, clock: clock)
        let client = OAuthClient(rest: rest, authentication: .confidential(clientID: .init(rawValue: 1), secret: try ClientSecret("secret")))
        #expect(await transport.executionCount == 0)
        #expect(try await client.exchange(codeResult()).expiresIn == 60)
        try clock.advance(by: .seconds(1))
        #expect(try await client.refresh(refreshToken: OAuthRefreshToken("refresh")).scopes.contains("identify"))
        try clock.advance(by: .seconds(1))
        #expect(try await client.clientCredentials(scopes: ["identify"]).refreshToken != nil)
        try await client.revoke(accessToken: BearerToken("access"))
        try clock.advance(by: .seconds(1))
        try await client.revoke(refreshToken: OAuthRefreshToken("refresh"))
        #expect(await transport.executionCount == 5)
        #expect(await rate.snapshot().activeCount == 0)
        #expect(client.description == "OAuthClient(redacted)")
        #expect(client.debugDescription == client.description)
        #expect(client.customMirror.children.count == 1)
        await rate.close()
    }

    /// Maps exact invalid_grant distinctly; arbitrary descriptions/codes never become recoverable refresh signals.
    /// - Parameters:
    ///   - code: Machine error field supplied by the test server.
    ///   - expected: Closed category exposed by OAuthClient.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [("invalid_grant", OAuthError.invalidGrant), ("access_denied", .accessDenied),
        ("invalid_request", .invalidRequest), ("synthetic_secret", .authorizationFailed)])
    func oauthErrorMapping(code: String, expected: OAuthError) async throws {
        let transport = try ScriptedHTTPTransport(steps: [{ _ in
            try oauthResponse("{\"error\":\"\(code)\",\"error_description\":\"synthetic_secret\"}", status: 400)
        }])
        let clock = ManualClock()
        let rate = RateLimitCoordinator(clock: clock)
        let rest = RESTClient(credential: .none, identity: RateLimitIdentity(), transport: transport, coordinator: rate, clock: clock, retryPolicy: .init(maximumAttempts: 1))
        let client = OAuthClient(rest: rest, authentication: .publicPKCE(clientID: .init(rawValue: 1)))
        await #expect(throws: expected) { try await client.refresh(refreshToken: OAuthRefreshToken("refresh")) }
        #expect(!String(reflecting: expected).contains("synthetic_secret"))
        #expect(await transport.executionCount == 1)
        #expect(await rate.snapshot().activeCount == 0)
        await rate.close()
    }

    /// Authentication/rate errors cannot masquerade as a revoked grant solely through a copied machine field.
    /// - Parameter status: Rejected non-400 status with an invalid_grant body; one finite attempt must fail generically.
    /// - Throws: Unexpected scripted fixture failures.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [401, 403, 429]) func invalidGrantRequiresOAuthBadRequest(status: Int) async throws {
        let transport = try ScriptedHTTPTransport(steps: [{ _ in
            try oauthResponse("{\"error\":\"invalid_grant\",\"retry_after\":0,\"error_description\":\"synthetic_secret\"}", status: status)
        }])
        let clock = ManualClock()
        let rate = RateLimitCoordinator(clock: clock)
        let rest = RESTClient(credential: .none, identity: RateLimitIdentity(), transport: transport,
            coordinator: rate, clock: clock, retryPolicy: .init(maximumAttempts: 1))
        let client = OAuthClient(rest: rest, authentication: .publicPKCE(clientID: .init(rawValue: 1)))
        await #expect(throws: OAuthError.authorizationFailed) { try await client.refresh(refreshToken: OAuthRefreshToken("refresh")) }
        #expect(await transport.executionCount == 1)
        #expect(await rate.snapshot().activeCount == 0)
        await rate.close()
    }

    /// A lost grant reply is indeterminate and never blindly replayed; already-cancelled callers perform no send.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func transportUncertaintyAndCancellation() async throws {
        let transport = try ScriptedHTTPTransport(steps: [{ _ in throw TestSupportFailure.scripted("synthetic_secret") }])
        let clock = ManualClock()
        let rate = RateLimitCoordinator(clock: clock)
        let rest = RESTClient(credential: .none, identity: RateLimitIdentity(), transport: transport, coordinator: rate, clock: clock)
        let client = OAuthClient(rest: rest, authentication: .publicPKCE(clientID: .init(rawValue: 1)))
        await #expect(throws: DiscordError.unknownMutationOutcome(.connectionLostAfterSubmission)) { try await client.refresh(refreshToken: OAuthRefreshToken("refresh")) }
        #expect(await transport.executionCount == 1)
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await client.refresh(refreshToken: OAuthRefreshToken("refresh"))
        }
        await #expect(throws: CancellationError.self) { try await cancelled.value }
        #expect(await transport.executionCount == 1)
        #expect(await rate.snapshot().activeCount == 0)
        await rate.close()
    }

    /// A complete 429 permits bounded replay; a suspended submitted grant reports cancellation/deadline uncertainty.
    /// - Throws: Unexpected fixture setup or virtual-clock failures. Gates prevent timing-dependent sleeps.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func rateRejectionCancellationAndDeadline() async throws {
        let clock = ManualClock()
        let rate = RateLimitCoordinator(clock: clock)
        let rejected = TestBarrier()
        let transport = try ScriptedHTTPTransport(steps: [{ _ in
            rejected.open()
            return try oauthResponse("{\"retry_after\":0.25,\"global\":true}", status: 429)
        }, { _ in try oauthResponse(tokenJSON) }])
        let rest = RESTClient(credential: .none, identity: RateLimitIdentity(), transport: transport, coordinator: rate, clock: clock)
        let client = OAuthClient(rest: rest, authentication: .publicPKCE(clientID: .init(rawValue: 1)))
        let task = Task { try await client.refresh(refreshToken: OAuthRefreshToken("refresh")) }
        try await rejected.wait()
        while await rate.snapshot().activeCount > 0 { try Task.checkCancellation(); await Task.yield() }
        try clock.advance(by: .milliseconds(249))
        #expect(await transport.executionCount == 1)
        try clock.advance(by: .seconds(1))
        #expect(try await task.value.expiresIn == 60)
        #expect(await transport.executionCount == 2)
        await rate.close()

        for timeout in [false, true] {
            let pending = TestBarrier()
            let entered = TestBarrier()
            let suspended = try ScriptedHTTPTransport(steps: [{ _ in
                entered.open(); try await pending.wait(); return try oauthResponse(tokenJSON)
            }])
            let suspendedClock = ManualClock()
            let suspendedRate = RateLimitCoordinator(clock: suspendedClock)
            let suspendedREST = RESTClient(credential: .none, identity: RateLimitIdentity(), transport: suspended,
                coordinator: suspendedRate, clock: suspendedClock, maximumExchangeDuration: .seconds(1))
            let suspendedClient = OAuthClient(rest: suspendedREST, authentication: .publicPKCE(clientID: .init(rawValue: 1)))
            let operation = Task { try await suspendedClient.refresh(refreshToken: OAuthRefreshToken("refresh")) }
            try await entered.wait()
            if timeout {
                try suspendedClock.advance(by: .seconds(1))
                await #expect(throws: DiscordError.unknownMutationOutcome(.deadlineAfterSubmission)) { try await operation.value }
            } else {
                operation.cancel()
                await #expect(throws: DiscordError.unknownMutationOutcome(.cancelledAfterSubmission)) { try await operation.value }
            }
            #expect(await suspended.executionCount == 1)
            #expect(await suspendedRate.snapshot().activeCount == 0)
            #expect(pending.waitingCount == 0)
            #expect(suspendedClock.pendingSleepCount == 0)
            await suspendedRate.close()
        }
    }

    /// Parses official partial authorization data, ISO timestamps and scoped user absence without over-projecting User.
    @Test func currentAuthorizationAndApplicationDescriptors() throws {
        let information = try OAuthAuthorizationInformation(data: Data("""
        {"application":{"id":"18446744073709551615","name":"Synthetic","icon":null,"future":"synthetic_secret"},"scopes":["identify","future.scope"],"expires":"2021-01-23T02:33:17.017000+00:00","user":{"id":"2","username":"Synthetic","avatar":null,"discriminator":"0","global_name":"Synthetic"}}
        """.utf8))
        #expect(information.application.id.rawValue == .max)
        #expect(information.application.name == "Synthetic")
        #expect(information.application.withUnsafeFields { $0["future"] } == .string("synthetic_secret"))
        #expect(information.application.description == "OAuthAuthorizationApplication(redacted)")
        #expect(information.application.debugDescription == information.application.description)
        #expect(information.application.customMirror.children.count == 1)
        #expect(information.scopes == ["identify", "future.scope"])
        #expect(information.user?.id.rawValue == 2)
        #expect(information.expires == "2021-01-23T02:33:17.017000+00:00")
        #expect(information.description == "OAuthAuthorizationInformation(redacted)")
        #expect(information.debugDescription == information.description)
        #expect(information.customMirror.children.count == 1)
        let noUser = try OAuthAuthorizationInformation(data: Data("{\"application\":{\"id\":\"1\",\"name\":\"Synthetic\"},\"scopes\":[],\"expires\":\"2030-01-01T00:00:00Z\"}".utf8))
        #expect(noUser.user == nil)
        #expect(throws: OAuthError.malformedResponse) { try OAuthAuthorizationInformation(data: Data("{\"application\":{\"id\":\"1\",\"name\":\"Synthetic\"},\"scopes\":[null],\"expires\":\"2030-01-01T00:00:00Z\"}".utf8)) }
        #expect(throws: OAuthError.malformedResponse) { try OAuthAuthorizationInformation(data: Data("{\"application\":{\"id\":\"1\",\"name\":\"Synthetic\"},\"scopes\":[],\"expires\":\"invalid\"}".utf8)) }
        #expect(try OAuthEndpoints.currentAuthorization().authentication == .bearer)
        #expect(try OAuthEndpoints.currentAuthorization().path == ["oauth2", "@me"])
        #expect(try OAuthEndpoints.currentBotApplication().authentication == .bot)
        #expect(try OAuthEndpoints.currentBotApplication().path == ["oauth2", "applications", "@me"])
    }
}

/// Fixed redacted token payload shared by scripted successful grant responses.
private let tokenJSON = "{\"access_token\":\"access_secret\",\"refresh_token\":\"refresh_secret\",\"token_type\":\"Bearer\",\"expires_in\":60,\"scope\":\"identify future.scope\"}"

/// Produces one real flow-validated synthetic authorization code, including percent-encoded literal plus handling.
/// - Returns: Bound code for application 1 with a fresh generated verifier.
/// - Throws: Unexpected validation errors from the fixed valid test flow and callback.
private func codeResult() async throws -> OAuthAuthorizationCode {
    let state = "0123456789abcdefghijklmnopqrstuv"
    let flow = try OAuthAuthorizationFlow(clientID: .init(rawValue: 1), redirectURI: URL(string: "https://example.com/callback")!, scopes: ["identify"], state: state)
    let result = try await flow.consumeCallback(URL(string: "https://example.com/callback?code=synthetic%2Bcode&state=\(state)&iss=https%3A%2F%2Fdiscord.com")!)
    guard case .code(let code) = result else { throw OAuthError.malformedResponse }
    return code
}

/// Builds one bounded scripted response stream and transfers ownership to the REST pipeline.
/// - Parameters:
///   - text: Synthetic complete JSON response.
///   - status: HTTP status, default 200.
/// - Returns: Pull-based HTTP response whose stream closes after its single chunk.
/// - Throws: Unexpected body construction errors for the finite fixture.
private func oauthResponse(_ text: String, status: Int = 200) throws -> HTTPResponse {
    HTTPResponse(status: status, body: try RequestBody(bytes: Data(text.utf8), contentType: "application/json").makeStream())
}

extension OAuthClientTests {
    /// Captures successful/rejected/failed grants through native SwiftLog without exposing credentials,
    /// scopes, response fields or arbitrary transport error text; construction remains silent.
    /// - Throws: Unexpected fixture or successful grant failures.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func structuredLoggingRedactsGrantMaterial() async throws {
        let recorder = LogRecorder()
        try await DiscordLog.$loggerFactory.withValue({ recorder.makeLogger($0) }) {
            let transport = try ScriptedHTTPTransport(steps: [
                { _ in try oauthResponse(tokenJSON) },
                { _ in try oauthResponse("{\"error\":\"invalid_grant\",\"error_description\":\"private-response-secret\"}", status: 400) },
                { _ in throw TestSupportFailure.scripted("private-transport-secret") }
            ])
            let clock = ManualClock()
            let rate = RateLimitCoordinator(clock: clock)
            let rest = RESTClient(credential: .none, identity: RateLimitIdentity(), transport: transport,
                coordinator: rate, clock: clock, retryPolicy: .init(maximumAttempts: 1))
            let client = OAuthClient(rest: rest, authentication: .publicPKCE(clientID: .init(rawValue: 1)))
            #expect(recorder.entries.isEmpty)
            _ = try await client.refresh(refreshToken: OAuthRefreshToken("private-refresh-secret"))
            // Headerless responses retain the route's conservative one-second pacing.
            // Advance virtual time between completed calls so the fixture needs no sleeper.
            try clock.advance(by: .seconds(1))
            await #expect(throws: OAuthError.invalidGrant) {
                try await client.refresh(refreshToken: OAuthRefreshToken("private-refresh-secret"))
            }
            try clock.advance(by: .seconds(1))
            await #expect(throws: DiscordError.unknownMutationOutcome(.connectionLostAfterSubmission)) {
                try await client.refresh(refreshToken: OAuthRefreshToken("private-refresh-secret"))
            }
            #expect(await transport.executionCount == 3)
            #expect(await rate.snapshot().activeCount == 0)
            #expect(clock.pendingSleepCount == 0)
            await rate.close()
        }
        let entries = recorder.entries.filter { $0.label == "discordkit.oauth.http" }
        #expect(entries.contains { $0.level == .trace && $0.metadata["dk.event"] == "oauth.request.started" })
        #expect(entries.contains { $0.level == .debug && $0.metadata["dk.event"] == "oauth.request.completed" })
        #expect(entries.contains { $0.level == .debug && $0.metadata["dk.event"] == "oauth.request.rejected" })
        #expect(entries.contains { $0.level == .debug && $0.metadata["dk.event"] == "oauth.request.failed" })
        let rendered = recorder.entries.map { $0.message + String(describing: $0.metadata) }.joined()
        for secret in ["private-refresh-secret", "private-response-secret", "private-transport-secret", "access_secret", "refresh_secret", "future.scope"] {
            #expect(!rendered.contains(secret))
        }
        let events = entries.compactMap { $0.metadata["dk.event"]?.description }
        let started = try #require(events.firstIndex(of: "oauth.exchange.started"))
        let admitted = try #require(events.firstIndex(of: "oauth.request.http.admitted"))
        let decoded = try #require(events.firstIndex(of: "oauth.request.response.decoded"))
        let completed = try #require(events.firstIndex(of: "oauth.exchange.completed"))
        #expect(started < admitted && admitted < decoded && decoded < completed)
        #expect(entries.contains { $0.metadata["dk.event"] == "oauth.request.failed" && $0.metadata["dk.failure"] == "execution" })
        #expect(entries.allSatisfy { $0.metadata["dk.module"] == "oauth" && $0.metadata["dk.trace_id"] != nil })
    }
}
