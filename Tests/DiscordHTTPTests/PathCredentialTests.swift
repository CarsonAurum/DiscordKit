import DiscordCore
import DiscordTestSupport
import DiscordTransport
import Foundation
import Testing
@testable import DiscordHTTP

/// Exact path-token binding and early authentication validation, using synthetic secrets only.
@Suite struct PathCredentialTests {
    /// Builds a bounded webhook read whose route metadata contains no secret.
    /// - Parameters:
    ///   - token: Synthetic path secret.
    ///   - readPolicy: Optional reuse contract for cache boundary regressions.
    /// - Returns: Token-bound safe descriptor returning exact response bytes.
    /// - Throws: Descriptor validation failures.
    private func webhook(_ token: WebhookToken, readPolicy: ReadPolicy? = nil) throws -> Endpoint<Data> {
        try Endpoint(method: "GET", path: ["webhooks", "1", token.withUnsafeValue { $0 }],
            route: "/webhooks/{webhook.id}/{webhook.token}", authentication: .none,
            pathCredential: .webhook(WebhookID(rawValue: 1), token), majorParameter: "1",
            retrySafety: .safe, readPolicy: readPolicy, decode: { $0 })
    }

    /// Matching webhook credentials encode one path segment and never emit Authorization.
    /// - Throws: Unexpected descriptor or request construction failures.
    @Test func webhookBindingAndRedaction() throws {
        let token = try WebhookToken("synthetic?percent%hash#token")
        let credential = Credential.webhook(WebhookID(rawValue: 1), token)
        let endpoint = try webhook(token)
        let request = try endpoint.makeRequest(credential: credential, userAgent: "local")
        #expect(request.url.absoluteString.contains("synthetic%3Fpercent%25hash%23token"))
        #expect(request.headers.allSatisfy { $0.name.lowercased() != "authorization" })
        #expect(endpoint.route == "/webhooks/{webhook.id}/{webhook.token}")
        #expect(endpoint.majorParameter == "1")
        let unbound = try Endpoint<Data>(method: "GET", path: endpoint.path, route: endpoint.route,
            authentication: .none, majorParameter: "1", retrySafety: .safe, decode: { $0 })
        #expect(endpoint.cacheIdentity != unbound.cacheIdentity)
        #expect(!String(reflecting: endpoint).contains("synthetic"))
        #expect(!String(describing: Mirror(reflecting: endpoint)).contains("synthetic"))
        for credential in [Credential.none, .bot(try BotToken("synthetic")), .bearer(try BearerToken("synthetic")),
                           .interaction(try InteractionToken("synthetic")),
                           .webhook(WebhookID(rawValue: 2), token),
                           .webhook(WebhookID(rawValue: 1), try WebhookToken("wrong"))] {
            #expect(throws: DiscordError.validation(.missingValue)) {
                try endpoint.makeRequest(credential: credential, userAgent: "local")
            }
        }
    }

    /// Interaction bindings work for callback and original/follow-up routes but reject token category substitution.
    /// - Throws: Unexpected request construction failures.
    @Test func interactionBinding() throws {
        let token = try InteractionToken("synthetic")
        for path in [["interactions", "1", "synthetic", "callback"], ["webhooks", "2", "synthetic", "messages", "@original"]] {
            let route = "/" + path[0] + (path[0] == "interactions" ? "/{interaction.id}" : "/{application.id}") +
                "/{interaction.token}" + (path.count == 4 ? "/callback" : "/messages/@original")
            let endpoint = try Endpoint<Data>(method: "POST", path: path, route: route, authentication: .none,
                pathCredential: .interaction(token), usesGlobalLimit: false, decode: { $0 })
            #expect(try endpoint.makeRequest(credential: .interaction(token), userAgent: "local").headers.count == 1)
            #expect(throws: DiscordError.validation(.missingValue)) {
                try endpoint.validateCredential(.interaction(InteractionToken("wrong")))
            }
            #expect(throws: DiscordError.validation(.missingValue)) {
                try endpoint.validateCredential(.webhook(WebhookID(rawValue: 2), WebhookToken("synthetic")))
            }
        }
    }

    /// Binding validation rejects malformed paths, wrong credentials, literal rate routes and header-auth mixing.
    /// - Throws: Unexpected secret construction failures.
    @Test func invalidBindings() throws {
        let token = try WebhookToken("synthetic")
        let bound = Credential.webhook(WebhookID(rawValue: 1), token)
        for (path, route, auth, credential) in [
            (["webhooks", "1", "synthetic"], nil, AuthenticationPolicy.none, bound),
            (["webhooks", "1", "synthetic"], "/webhooks/1/synthetic", .none, bound),
            (["webhooks", "1", "synthetic"], "/webhooks/{webhook.id}/synthetic/{webhook.token}", .none, bound),
            (["webhooks", "1", "synthetic"], "/webhooks/{webhook.id}/{webhook.token}/synthetic", .none, bound),
            (["webhooks", "1", "synthetic", "synthetic"], "/webhooks/{webhook.id}/{webhook.token}/synthetic", .none, bound),
            (["webhooks", "1", "wrong"], "/webhooks/{id}/{webhook.token}", .none, bound),
            (["webhooks", "2", "synthetic"], "/webhooks/{id}/{webhook.token}", .none, bound),
            (["other", "1", "synthetic"], "/other/{id}/{webhook.token}", .none, bound),
            (["webhooks", "1", "synthetic"], "/webhooks/{id}/{webhook.token}", .bot, bound),
            (["webhooks", "1", "synthetic"], "/webhooks/{id}/{webhook.token}", .none, Credential.none),
            (["interactions", "x", "synthetic"], "/interactions/{id}/{interaction.token}", .none, .interaction(try InteractionToken("synthetic")))
        ] {
            #expect(throws: DiscordError.validation(.invalidValue)) {
                try Endpoint<Data>(method: "GET", path: path, route: route, authentication: auth,
                    pathCredential: credential, decode: { $0 })
            }
        }
    }

    /// Authentication failures occur before cached response reuse or transport work, even with a reused opaque identity.
    /// - Throws: Unexpected setup/execution failures.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func cachedReadCannotBypassCredentialBinding() async throws {
        let clock = ManualClock()
        let coordinator = RateLimitCoordinator(clock: clock)
        let cache = ReadCache(clock: clock)
        let identity = RateLimitIdentity()
        let egress = UUID()
        let token = try WebhookToken("synthetic")
        let endpoint = try webhook(token, readPolicy: .init(timeToLive: .seconds(30)))
        let transport = try ScriptedHTTPTransport(steps: [{ _ in
            HTTPResponse(status: 200, body: try RequestBody(bytes: Data("ok".utf8), contentType: "application/json").makeStream())
        }])
        let valid = RESTClient(credential: .webhook(WebhookID(rawValue: 1), token), identity: identity,
            transport: transport, coordinator: coordinator, clock: clock, cache: cache, egress: egress)
        #expect(try await valid.execute(endpoint) == Data("ok".utf8))
        #expect(try await valid.execute(endpoint) == Data("ok".utf8))
        for credential in [Credential.none, .webhook(WebhookID(rawValue: 1), try WebhookToken("wrong"))] {
            let invalid = RESTClient(credential: credential, identity: identity, transport: transport,
                coordinator: coordinator, clock: clock, cache: cache, egress: egress)
            await #expect(throws: DiscordError.validation(.missingValue)) { try await invalid.execute(endpoint) }
        }
        let missingEgress = RESTClient(credential: .webhook(WebhookID(rawValue: 1), token), identity: identity,
            transport: transport, coordinator: coordinator, clock: clock, cache: cache)
        await #expect(throws: DiscordError.validation(.missingValue)) { try await missingEgress.execute(endpoint) }
        #expect(await transport.executionCount == 1)
        #expect(await coordinator.snapshot().activeCount == 0)
        await coordinator.close()
    }

    /// Header credential validation also precedes reuse, closing the same boundary for existing typed reads.
    /// - Throws: Unexpected setup/execution failures.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func headerValidationAndUnboundCompatibility() async throws {
        let endpoint = try Endpoint<Data>(method: "GET", path: ["users", "@me"], authentication: .bot,
            retrySafety: .safe, readPolicy: .init(timeToLive: .seconds(30)), decode: { $0 })
        let clock = ManualClock()
        let coordinator = RateLimitCoordinator(clock: clock)
        let cache = ReadCache(clock: clock)
        let identity = RateLimitIdentity()
        let transport = try ScriptedHTTPTransport(steps: [{ _ in HTTPResponse(status: 200) }])
        let valid = RESTClient(credential: .bot(try BotToken("synthetic")), identity: identity,
            transport: transport, coordinator: coordinator, clock: clock, cache: cache)
        #expect(try await valid.execute(endpoint).isEmpty)
        let invalid = RESTClient(credential: .none, identity: identity, transport: transport,
            coordinator: coordinator, clock: clock, cache: cache)
        await #expect(throws: DiscordError.validation(.missingValue)) { try await invalid.execute(endpoint) }
        #expect(await transport.executionCount == 1)
        let unbound = try Endpoint<Data>(method: "GET", path: ["voice", "regions"], authentication: .none, decode: { $0 })
        #expect(try unbound.makeRequest(credential: .bot(BotToken("synthetic")), userAgent: "local").headers.count == 1)
        await coordinator.close()
    }
}
