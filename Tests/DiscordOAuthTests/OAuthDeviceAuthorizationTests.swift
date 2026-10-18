import DiscordCore
import DiscordHTTP
import DiscordTestSupport
import DiscordTransport
import Foundation
import Testing
@testable import DiscordOAuth

/// Synthetic backend device-flow tests; no Discord, console, browser, credentials, or real sleeps are used.
@Suite(.timeLimit(.minutes(1))) struct OAuthDeviceAuthorizationTests {
    /// Returns fixed synthetic backend authentication, never a production credential.
    /// - Returns: A nonzero client and test-only client secret containing form-sensitive characters.
    /// - Throws: Credential syntax errors if the fixture becomes malformed.
    private func authentication() throws -> OAuthClientAuthentication {
        .confidential(clientID: ApplicationID(rawValue: 42), secret: try ClientSecret("client+secret"))
    }

    /// Composes a finite script with a manual clock and no implicit execution.
    /// - Parameters:
    ///   - steps: Ordered synthetic HTTP behavior.
    ///   - maximumPolls: Fixed poll budget, default 128.
    ///   - clock: Shared deterministic clock; default a fresh instance.
    /// - Returns: Device owner plus transport/rate authorities for execution and cleanup assertions.
    /// - Throws: Fixture, credential, or flow validation failures.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    private func fixture(
        _ steps: [ScriptedHTTPTransport.Step], maximumPolls: Int = 128, clock: ManualClock = ManualClock()
    ) throws -> (OAuthDeviceAuthorizationFlow<ManualClock>, ScriptedHTTPTransport,
                  RateLimitCoordinator<ManualClock>, ManualClock) {
        let transport = try ScriptedHTTPTransport(steps: steps)
        let rate = RateLimitCoordinator(clock: clock)
        let rest = RESTClient(credential: .none, identity: RateLimitIdentity(), transport: transport,
                              coordinator: rate, clock: clock, retryPolicy: .init(maximumAttempts: 1))
        return (try OAuthDeviceAuthorizationFlow(rest: rest, authentication: authentication(), clock: clock,
                                                 maximumPolls: maximumPolls), transport, rate, clock)
    }

    /// Preserves exact codes and optional instructions while all ordinary diagnostics remain redacted.
    @Test func responseAndDiagnostics() throws {
        let response = try OAuthDeviceAuthorization(data: Data(deviceAuthorizationJSON.utf8))
        #expect(response.deviceCode.withUnsafeValue { $0 } == "device+secret")
        #expect(response.userCode == "ABCD-EFGH")
        #expect(response.verificationURI.absoluteString == "https://discord.com/activate")
        #expect(response.verificationURIComplete?.absoluteString == "https://discord.com/activate?user_code=ABCD-EFGH")
        #expect(response.expiresIn == 300 && response.interval == 5)
        #expect(response.description == "OAuthDeviceAuthorization(redacted)")
        #expect(response.debugDescription == response.description)
        #expect(String(reflecting: response) == response.description)
        #expect(response.customMirror.children.count == 1)
        let minimal = try OAuthDeviceAuthorization(data: Data("""
        {"device_code":"d","user_code":"u","verification_uri":"https://discord.com/activate","expires_in":1,"future":"ignored"}
        """.utf8))
        #expect(minimal.verificationURIComplete == nil && minimal.interval == 5)
    }

    /// Rejects malformed codes, nonintegral/lifetime limits, wrong types, duplicates, and foreign or deceptive activation URLs.
    @Test func malformedResponseBounds() {
        let mutations: [(String, String)] = [
            ("\"device+secret\"", "null"), ("device+secret", ""), ("device+secret", "bad secret"),
            ("device+secret", String(repeating: "x", count: 8_193)),
            ("ABCD-EFGH", ""), ("ABCD-EFGH", String(repeating: "x", count: 257)),
            ("\"expires_in\":300", "\"expires_in\":0"), ("\"expires_in\":300", "\"expires_in\":-1"),
            ("\"expires_in\":300", "\"expires_in\":1.0"), ("\"expires_in\":300", "\"expires_in\":1e2"),
            ("\"expires_in\":300", "\"expires_in\":86401"),
            ("\"expires_in\":300", "\"expires_in\":999999999999999999999999999"),
            ("\"interval\":5", "\"interval\":0"), ("\"interval\":5", "\"interval\":null"),
            ("\"verification_uri_complete\":\"https://discord.com/activate?user_code=ABCD-EFGH\"", "\"verification_uri_complete\":null"),
            ("https://discord.com/activate", "http://discord.com/activate"),
            ("https://discord.com/activate", "https://evil.example/activate"),
            ("https://discord.com/activate", "https://discord.com.evil.example/activate"),
            ("https://discord.com/activate", "https://user@discord.com/activate"),
            ("https://discord.com/activate", "https://discord.com:443/activate"),
            ("https://discord.com/activate", "https://discord.com/activate#fragment"),
            ("https://discord.com/activate", "https://discord.com/other"),
            ("\"device_code\":", "\"device_code\":\"duplicate\",\"device_code\":")
        ]
        for (before, after) in mutations {
            let json = deviceAuthorizationJSON.replacingOccurrences(of: before, with: after)
            #expect(throws: OAuthError.malformedResponse) { try OAuthDeviceAuthorization(data: Data(json.utf8)) }
        }
        for json in ["{}", "[]", "null", "not-json"] {
            #expect(throws: OAuthError.malformedResponse) { try OAuthDeviceAuthorization(data: Data(json.utf8)) }
        }
        let longestURI = deviceAuthorizationJSON.replacingOccurrences(of: "https://discord.com/activate", with:
            "https://discord.com/activate?x=" + String(repeating: "x", count: 8_192))
        #expect(throws: OAuthError.malformedResponse) { try OAuthDeviceAuthorization(data: Data(longestURI.utf8)) }
    }

    /// Exact forms preserve literal plus signs, use versioned unsafe routes, and admit no bearer/bot header or read reuse.
    @Test func publishedDescriptorForms() throws {
        let auth = try authentication()
        let authorize = try OAuthDeviceAuthorizationEndpoints.authorize(scopes: ["sdk.social_layer", "identify"], authentication: auth)
        #expect(authorize.path == ["oauth2", "device", "authorize"])
        #expect(authorize.method == "POST" && authorize.authentication == .none)
        #expect(authorize.retrySafety == .unsafe && authorize.readPolicy == nil)
        #expect(String(decoding: try #require(authorize.body).bytes, as: UTF8.self) ==
                "scope=identify+sdk.social_layer&client_id=42&client_secret=client%2Bsecret")
        #expect(try authorize.decode(Data(deviceAuthorizationJSON.utf8)).interval == 5)
        let exchange = try OAuthDeviceAuthorizationEndpoints.exchange(deviceCode: OAuthDeviceCode("device+secret"), authentication: auth)
        #expect(exchange.path == ["oauth2", "token"])
        #expect(exchange.authentication == .none && exchange.retrySafety == .unsafe && exchange.readPolicy == nil)
        #expect(String(decoding: try #require(exchange.body).bytes, as: UTF8.self) ==
                "grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Adevice_code&device_code=device%2Bsecret&client_id=42&client_secret=client%2Bsecret")
        #expect(try exchange.decode(Data(deviceTokenJSON.utf8)).accessToken.withUnsafeValue { $0 } == "access_secret")
        let merge = try OAuthDeviceAuthorizationEndpoints.exchange(deviceCode: OAuthDeviceCode("device"), authentication: auth,
            externalAuthType: "OIDC", externalAuthToken: BearerToken("provisional+secret"))
        let mergeForm = String(decoding: try #require(merge.body).bytes, as: UTF8.self)
        #expect(mergeForm.contains("external_auth_type=OIDC&external_auth_token=provisional%2Bsecret"))
        #expect(!String(reflecting: exchange).contains("device+secret"))
        #expect(exchange.headers.isEmpty && authorize.headers.isEmpty)
    }

    /// Local validation rejects public/native-client inference, zero clients, oversized secrets/codes, and unpaired merge data.
    @Test func descriptorInputValidation() throws {
        let auth = try authentication()
        let code = try OAuthDeviceCode("d")
        #expect(throws: OAuthError.unsupportedClient) {
            try OAuthDeviceAuthorizationEndpoints.authorize(scopes: ["identify"], authentication: .publicPKCE(clientID: .init(rawValue: 1)))
        }
        #expect(throws: OAuthError.unsupportedClient) {
            try OAuthDeviceAuthorizationEndpoints.exchange(deviceCode: code, authentication: .publicPKCE(clientID: .init(rawValue: 1)))
        }
        #expect(throws: OAuthError.invalidRequest) { try OAuthDeviceAuthorizationEndpoints.authorize(scopes: [], authentication: auth) }
        #expect(throws: OAuthError.invalidRequest) { try OAuthDeviceAuthorizationEndpoints.authorize(scopes: ["bad scope"], authentication: auth) }
        #expect(throws: OAuthError.invalidRequest) {
            try OAuthDeviceAuthorizationEndpoints.authorize(scopes: ["identify"], authentication:
                .confidential(clientID: .init(rawValue: 0), secret: ClientSecret("s")))
        }
        #expect(throws: OAuthError.invalidRequest) {
            try OAuthDeviceAuthorizationEndpoints.authorize(scopes: ["identify"], authentication:
                .confidential(clientID: .init(rawValue: 1), secret: ClientSecret(String(repeating: "s", count: 8_193))))
        }
        #expect(throws: OAuthError.invalidRequest) {
            try OAuthDeviceAuthorizationEndpoints.exchange(deviceCode: OAuthDeviceCode(String(repeating: "d", count: 8_193)), authentication: auth)
        }
        #expect(throws: OAuthError.invalidRequest) {
            try OAuthDeviceAuthorizationEndpoints.exchange(deviceCode: code, authentication: auth, externalAuthType: "OIDC")
        }
        #expect(throws: OAuthError.invalidRequest) {
            try OAuthDeviceAuthorizationEndpoints.exchange(deviceCode: code, authentication: auth, externalAuthToken: BearerToken("p"))
        }
        for type in ["", "bad type", "oidc", String(repeating: "A", count: 129)] {
            #expect(throws: OAuthError.invalidRequest) {
                try OAuthDeviceAuthorizationEndpoints.exchange(deviceCode: code, authentication: auth,
                    externalAuthType: type, externalAuthToken: BearerToken("p"))
            }
        }
    }

    /// Construction and early polls send nothing; pending/slow-down persist exact minimum intervals and token success is one-use.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func explicitPollSequenceAndPersistentSlowDown() async throws {
        let (flow, transport, rate, clock) = try fixture([
            { request in
                #expect(request.url.path == "/api/v10/oauth2/device/authorize")
                #expect(!request.headers.contains { $0.name.lowercased() == "authorization" })
                return try deviceHTTPResponse(deviceAuthorizationJSON)
            },
            { _ in try deviceHTTPResponse("{\"error\":\"authorization_pending\"}", status: 400) },
            { _ in try deviceHTTPResponse("{\"error\":\"slow_down\"}", status: 400) },
            { _ in try deviceHTTPResponse("{\"error\":\"authorization_pending\"}", status: 400) },
            { request in
                #expect(request.url.path == "/api/v10/oauth2/token")
                #expect(!request.headers.contains { $0.name.lowercased() == "authorization" })
                return try deviceHTTPResponse(deviceTokenJSON)
            }
        ])
        #expect(await transport.executionCount == 0)
        await #expect(throws: OAuthDeviceAuthorizationError.notStarted) { try await flow.poll() }
        _ = try await flow.start(scopes: ["sdk.social_layer"])
        await #expect(throws: OAuthDeviceAuthorizationError.alreadyStarted) { try await flow.start(scopes: ["identify"]) }
        guard case .waiting(let initialWait) = try await flow.poll() else { Issue.record("Expected wait"); return }
        #expect(initialWait == .seconds(5))
        #expect(await transport.executionCount == 1)
        try clock.advance(by: .seconds(5))
        guard case .pending(let pendingWait) = try await flow.poll() else { Issue.record("Expected pending"); return }
        #expect(pendingWait == .seconds(5))
        try clock.advance(by: .seconds(5))
        guard case .slowDown(let slowerWait) = try await flow.poll() else { Issue.record("Expected slow down"); return }
        #expect(slowerWait == .seconds(10))
        try clock.advance(by: .seconds(9))
        guard case .waiting(let remaining) = try await flow.poll() else { Issue.record("Expected wait"); return }
        #expect(remaining == .seconds(1))
        #expect(await transport.executionCount == 3)
        try clock.advance(by: .seconds(1))
        guard case .pending(let persistentWait) = try await flow.poll() else { Issue.record("Expected pending"); return }
        #expect(persistentWait == .seconds(10))
        try clock.advance(by: .seconds(10))
        guard case .authorized(let token) = try await flow.poll() else { Issue.record("Expected token"); return }
        #expect(token.refreshToken?.withUnsafeValue { $0 } == "refresh_secret")
        #expect(token.scopes == ["sdk.social_layer"])
        await #expect(throws: OAuthDeviceAuthorizationError.authorizationFailed) { try await flow.poll() }
        #expect(await transport.executionCount == 5)
        #expect(clock.pendingSleepCount == 0)
        #expect(flow.description == "OAuthDeviceAuthorizationFlow(redacted)")
        #expect(flow.debugDescription == flow.description && flow.customMirror.children.count == 1)
        #expect(await rate.snapshot().activeCount == 0)
        await rate.close()
    }

    /// Only HTTP 400 pending/slow-down can continue; denial, expiry, unknown codes, and arbitrary secret descriptions terminate safely.
    /// - Parameters:
    ///   - code: Synthetic OAuth machine error; never a real credential.
    ///   - status: HTTP status required to distinguish OAuth grant failures.
    ///   - expected: Exact closed public error expected from the flow.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [("access_denied", 400, OAuthDeviceAuthorizationError.accessDenied),
                      ("expired_token", 400, .expired), ("unknown_secret", 400, .authorizationFailed),
                      ("authorization_pending", 403, .authorizationFailed), ("slow_down", 401, .authorizationFailed)])
    func terminalGrantErrors(code: String, status: Int, expected: OAuthDeviceAuthorizationError) async throws {
        let (flow, transport, rate, clock) = try fixture([
            { _ in try deviceHTTPResponse(deviceAuthorizationJSON) },
            { _ in try deviceHTTPResponse("{\"error\":\"\(code)\",\"error_description\":\"never expose secret\"}", status: status) }
        ])
        _ = try await flow.start(scopes: ["sdk.social_layer"])
        try clock.advance(by: .seconds(5))
        await #expect(throws: expected) { try await flow.poll() }
        await #expect(throws: OAuthDeviceAuthorizationError.authorizationFailed) { try await flow.poll() }
        #expect(await transport.executionCount == 2)
        await rate.close()
    }

    /// Poll count and local expiry end the flow without an extra request; no timer or sleeper exists.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func pollBudgetAndLocalExpiry() async throws {
        let (limited, limitedTransport, limitedRate, clock) = try fixture([
            { _ in try deviceHTTPResponse(deviceAuthorizationJSON) },
            { _ in try deviceHTTPResponse("{\"error\":\"authorization_pending\"}", status: 400) }
        ], maximumPolls: 1)
        _ = try await limited.start(scopes: ["sdk.social_layer"])
        try clock.advance(by: .seconds(5))
        _ = try await limited.poll()
        try clock.advance(by: .seconds(5))
        await #expect(throws: OAuthDeviceAuthorizationError.pollLimitExceeded) { try await limited.poll() }
        #expect(await limitedTransport.executionCount == 2)
        await limitedRate.close()
        let (expired, expiredTransport, expiredRate, expiryClock) = try fixture([{ _ in try deviceHTTPResponse(deviceAuthorizationJSON) }])
        _ = try await expired.start(scopes: ["sdk.social_layer"])
        try expiryClock.advance(by: .seconds(300))
        await #expect(throws: OAuthDeviceAuthorizationError.expired) { try await expired.poll() }
        #expect(await expiredTransport.executionCount == 1)
        #expect(expiryClock.pendingSleepCount == 0)
        await expiredRate.close()
    }

    /// Conservative request-start expiry rejects late authorization instructions and late tokens without adopting credentials.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func lateStartAndTokenAreRejected() async throws {
        let startClock = ManualClock()
        let short = deviceAuthorizationJSON.replacingOccurrences(of: "\"expires_in\":300", with: "\"expires_in\":1")
        let (lateStart, startTransport, startRate, _) = try fixture([{ _ in
            try startClock.advance(by: .seconds(2))
            return try deviceHTTPResponse(short)
        }], clock: startClock)
        await #expect(throws: OAuthDeviceAuthorizationError.expired) { try await lateStart.start(scopes: ["identify"]) }
        #expect(await startTransport.executionCount == 1)
        await startRate.close()
        let pollClock = ManualClock()
        let shortPoll = deviceAuthorizationJSON.replacingOccurrences(of: "\"expires_in\":300", with: "\"expires_in\":6")
        let (latePoll, pollTransport, pollRate, _) = try fixture([
            { _ in try deviceHTTPResponse(shortPoll) },
            { _ in try pollClock.advance(by: .seconds(2)); return try deviceHTTPResponse(deviceTokenJSON) }
        ], clock: pollClock)
        _ = try await latePoll.start(scopes: ["identify"])
        try pollClock.advance(by: .seconds(5))
        await #expect(throws: OAuthDeviceAuthorizationError.expired) { try await latePoll.poll() }
        #expect(await pollTransport.executionCount == 2)
        await pollRate.close()
    }

    /// Explicit cancellation fences an in-flight start result, concurrent operations are rejected, and cleanup is idempotent.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func cancelDuringStartAndBusyAdmission() async throws {
        let entered = TestBarrier()
        let pending = TestBarrier()
        let (flow, transport, rate, clock) = try fixture([{ _ in
            entered.open(); try await pending.wait(); return try deviceHTTPResponse(deviceAuthorizationJSON)
        }])
        let operation = Task { try await flow.start(scopes: ["identify"]) }
        try await entered.wait()
        await #expect(throws: OAuthDeviceAuthorizationError.busy) { try await flow.start(scopes: ["identify"]) }
        await #expect(throws: OAuthDeviceAuthorizationError.busy) { try await flow.poll() }
        await flow.cancel()
        await flow.cancel()
        pending.open()
        await #expect(throws: OAuthDeviceAuthorizationError.cancelled) { try await operation.value }
        await #expect(throws: OAuthDeviceAuthorizationError.cancelled) { try await flow.poll() }
        await #expect(throws: OAuthDeviceAuthorizationError.cancelled) { try await flow.start(scopes: ["identify"]) }
        #expect(await transport.executionCount == 1)
        #expect(clock.pendingSleepCount == 0 && pending.waitingCount == 0)
        #expect(await rate.snapshot().activeCount == 0)
        await rate.close()
    }

    /// Explicit cancellation during a token request rejects its later success while one in-flight request remains bounded.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func cancelDuringPoll() async throws {
        let entered = TestBarrier()
        let pending = TestBarrier()
        let (flow, transport, rate, clock) = try fixture([
            { _ in try deviceHTTPResponse(deviceAuthorizationJSON) },
            { _ in entered.open(); try await pending.wait(); return try deviceHTTPResponse(deviceTokenJSON) }
        ])
        _ = try await flow.start(scopes: ["identify"])
        try clock.advance(by: .seconds(5))
        let operation = Task { try await flow.poll() }
        try await entered.wait()
        await #expect(throws: OAuthDeviceAuthorizationError.busy) { try await flow.poll() }
        await flow.cancel()
        pending.open()
        await #expect(throws: OAuthDeviceAuthorizationError.cancelled) { try await operation.value }
        #expect(await transport.executionCount == 2)
        #expect(await rate.snapshot().activeCount == 0)
        await rate.close()
    }

    /// Caller-task cancellation before start performs no send; cancellation after submission remains an indeterminate mutation.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func taskCancellationAndTransportUncertainty() async throws {
        let entered = TestBarrier()
        let pending = TestBarrier()
        let (flow, transport, rate, clock) = try fixture([{ _ in
            entered.open(); try await pending.wait(); return try deviceHTTPResponse(deviceAuthorizationJSON)
        }])
        let before = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await flow.start(scopes: ["identify"])
        }
        await #expect(throws: CancellationError.self) { try await before.value }
        #expect(await transport.executionCount == 0)
        let submitted = Task { try await flow.start(scopes: ["identify"]) }
        try await entered.wait()
        submitted.cancel()
        await #expect(throws: DiscordError.unknownMutationOutcome(.cancelledAfterSubmission)) { try await submitted.value }
        #expect(await transport.executionCount == 1)
        #expect(pending.waitingCount == 0 && clock.pendingSleepCount == 0)
        await #expect(throws: OAuthDeviceAuthorizationError.authorizationFailed) { try await flow.poll() }
        await rate.close()
    }

    /// Backend errors consume start, invalid local scopes preserve an unstarted flow, and constructor budgets reject bad input.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func startupValidationAndFailures() async throws {
        let (flow, transport, rate, clock) = try fixture([{ _ in
            try deviceHTTPResponse("{\"error\":\"secret\",\"error_description\":\"secret\"}", status: 400)
        }])
        await #expect(throws: OAuthError.invalidRequest) { try await flow.start(scopes: []) }
        #expect(await transport.executionCount == 0)
        await #expect(throws: OAuthDeviceAuthorizationError.authorizationFailed) { try await flow.start(scopes: ["identify"]) }
        await #expect(throws: OAuthDeviceAuthorizationError.alreadyStarted) { try await flow.start(scopes: ["identify"]) }
        #expect(await transport.executionCount == 1)
        let rest = RESTClient(credential: .none, identity: RateLimitIdentity(), transport: transport, coordinator: rate, clock: clock)
        #expect(throws: OAuthError.unsupportedClient) {
            try OAuthDeviceAuthorizationFlow(rest: rest, authentication: .publicPKCE(clientID: .init(rawValue: 1)), clock: clock)
        }
        for budget in [0, -1, 4_097] {
            #expect(throws: OAuthError.invalidRequest) {
                try OAuthDeviceAuthorizationFlow(rest: rest, authentication: authentication(), clock: clock, maximumPolls: budget)
            }
        }
        #expect(throws: OAuthError.invalidRequest) {
            try OAuthDeviceAuthorizationFlow(rest: rest, authentication:
                .confidential(clientID: .init(rawValue: 0), secret: ClientSecret("s")), clock: clock)
        }
        await rate.close()
    }
}

/// Complete synthetic authorize response used only by in-memory test transports.
private let deviceAuthorizationJSON = """
{"device_code":"device+secret","user_code":"ABCD-EFGH","verification_uri":"https://discord.com/activate","verification_uri_complete":"https://discord.com/activate?user_code=ABCD-EFGH","expires_in":300,"interval":5}
"""

/// Complete synthetic token response without any real Discord credentials.
private let deviceTokenJSON = """
{"access_token":"access_secret","refresh_token":"refresh_secret","token_type":"Bearer","expires_in":600,"scope":"sdk.social_layer"}
"""

/// Creates a bounded owned JSON response for local device-flow scripts.
/// - Parameters:
///   - text: Synthetic response body; all secrets are deliberately fake.
///   - status: HTTP success or OAuth error status; defaults to 200.
/// - Returns: Response with a fresh closeable body stream owned by the REST pipeline.
/// - Throws: Request-body construction failure for invalid fixture bounds.
private func deviceHTTPResponse(_ text: String, status: Int = 200) throws -> HTTPResponse {
    HTTPResponse(status: status, body: try RequestBody(bytes: Data(text.utf8), contentType: "application/json").makeStream())
}
