// File: Tests/DiscordHTTPTests/EgressGlobalIntegrationTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import DiscordTestSupport
import DiscordTransport
import Foundation
import Testing
@testable import DiscordHTTP

/// Exercises the REST pipeline's selection of credential-global, outbound-IP-global and exempt scopes.
/// Synthetic credentials reach only scripted transports; a bounded recording adapter delegates every
/// admission and completion to the real authority so assertions also verify ownership cleanup.
@Suite struct EgressGlobalIntegrationTests {
    /// Header-free operations select the shared IP budget regardless of the client's credential category.
    /// Bot requests retain credential-global admission, while interaction reads retain their outbound-IP
    /// identity for invalid-response protection without consuming either global allowance.
    /// - Parameter category: Bound webhook, header-authenticated bot, exempt interaction, or unbound anonymous
    ///   descriptor executed with either no credential or a bot credential that must remain unsent.
    /// - Throws: Unexpected descriptor, admission, transport or completion errors fail the test.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: ["webhook", "bot", "interaction", "unbound-none", "unbound-bot"])
    func pipelineSelectsApplicableGlobalBudget(category: String) async throws {
        let clock = ManualClock(), store = EgressRecordingStore()
        let coordinator = RateLimitCoordinator(clock: clock, store: store)
        let identity = RateLimitIdentity(), egress = UUID()
        let secret = "synthetic-\(category)-private-token"
        let credential: Credential
        let endpoint: Endpoint<Data>
        switch category {
        case "webhook":
            let token = try WebhookToken(secret)
            credential = .webhook(WebhookID(rawValue: 1), token)
            endpoint = try Endpoint(method: "GET", path: ["webhooks", "1", secret],
                route: "/webhooks/{webhook.id}/{webhook.token}", authentication: .none,
                pathCredential: credential, majorParameter: "1", retrySafety: .safe, decode: { $0 })
        case "bot":
            credential = .bot(try BotToken(secret))
            endpoint = try Endpoint(method: "GET", path: ["users", "@me"], route: "/users/@me",
                authentication: .bot, retrySafety: .safe, decode: { $0 })
        case "interaction":
            credential = .interaction(try InteractionToken(secret))
            endpoint = try Endpoint(method: "GET", path: ["webhooks", "2", secret, "messages", "@original"],
                route: "/webhooks/{application.id}/{interaction.token}/messages/@original", authentication: .none,
                pathCredential: credential, majorParameter: "2", usesGlobalLimit: false,
                retrySafety: .safe, decode: { $0 })
        default:
            credential = category == "unbound-bot" ? .bot(try BotToken(secret)) : .none
            endpoint = try Endpoint(method: "GET", path: ["voice", "regions"], route: "/voice/regions",
                authentication: .none, retrySafety: .safe, decode: { $0 })
        }
        let transport = try ScriptedHTTPTransport(steps: [{ request in
            let authorization = request.headers.filter { $0.name.lowercased() == "authorization" }
            if category == "bot" {
                #expect(authorization.count == 1)
                #expect(authorization.first?.value == "Bot \(secret)")
            } else {
                #expect(authorization.isEmpty)
                #expect(request.headers.allSatisfy { !$0.value.contains(secret) })
            }
            return HTTPResponse(status: 200)
        }])
        let client = RESTClient(credential: credential, identity: identity, transport: transport,
            coordinator: coordinator, clock: clock, retryPolicy: .init(maximumAttempts: 1), egress: egress)
        #expect(try await client.execute(endpoint).isEmpty)
        let observed = await store.requests
        let request = try #require(observed.first)
        #expect(observed.count == 1)
        #expect(request.identity == identity)
        #expect(request.egress == egress)
        #expect(request.usesGlobalLimit == (category != "interaction"))
        #expect(request.usesEgressGlobalLimit == (category != "bot" && category != "interaction"))
        #expect(request.route == "GET " + endpoint.route)
        #expect(request.majorResource == (endpoint.majorParameter ?? ""))
        #expect(request.queuedBytes == endpoint.accountedMetadataBytes)
        #expect(!request.route.contains(secret) && !request.majorResource.contains(secret))
        #expect(!request.description.contains(secret) && !request.debugDescription.contains(secret))
        #expect(Mirror(reflecting: request).children.count == 1)
        #expect(await transport.executionCount == 1)
        let snapshot = await coordinator.snapshot()
        #expect(snapshot.activeCount == 0 && snapshot.queuedCount == 0 && snapshot.queuedBytes == 0)
        #expect(snapshot.orderedOperationsCount == 0)
        #expect(snapshot.metadataCount == (category == "interaction" ? 1 : 2))
        #expect(clock.pendingSleepCount == 0)
        await coordinator.close()
    }

    /// Globally limited bound webhook operations fail before any admission or network work when egress
    /// is missing; supplied scope cannot substitute for a matching typed path credential either.
    /// - Throws: Unexpected descriptor or dependency construction errors fail the test.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func webhookRequiresEgressBeforeAdmission() async throws {
        let token = try WebhookToken("synthetic-webhook-private-token")
        let credential = Credential.webhook(WebhookID(rawValue: 1), token)
        let endpoint = try Endpoint<Data>(method: "GET", path: ["webhooks", "1", token.withUnsafeValue { $0 }],
            route: "/webhooks/{webhook.id}/{webhook.token}", authentication: .none,
            pathCredential: credential, majorParameter: "1", retrySafety: .safe, decode: { $0 })
        let clock = ManualClock(), store = EgressRecordingStore()
        let coordinator = RateLimitCoordinator(clock: clock, store: store)
        let transport = try ScriptedHTTPTransport(steps: [])
        for (supplied, egress) in [(credential, Optional<UUID>.none), (Credential.none, UUID())] {
            let client = RESTClient(credential: supplied, identity: .init(), transport: transport,
                coordinator: coordinator, clock: clock, egress: egress)
            await #expect(throws: DiscordError.validation(.missingValue)) { try await client.execute(endpoint) }
        }
        #expect(await store.requests.isEmpty)
        #expect(await transport.executionCount == 0)
        let snapshot = await coordinator.snapshot()
        #expect(snapshot.activeCount == 0 && snapshot.metadataCount == 0)
        #expect(snapshot.queuedCount == 0 && snapshot.queuedBytes == 0 && snapshot.orderedOperationsCount == 0)
        #expect(clock.pendingSleepCount == 0)
        await coordinator.close()
    }
}

/// Test-only, sixteen-attempt recording boundary above the real in-process rate authority.
/// Records contain the same secret-free scopes that a distributed authority would receive.
@available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
private actor EgressRecordingStore: RateLimitStore {
    typealias Instant = ManualClock.Instant
    private let store = InProcessRateLimitStore<Instant>()
    private(set) var requests: [RateLimitRequest] = []

    /// Records one attempted admission and forwards it without modifying scopes, timing or ownership.
    /// - Parameters:
    ///   - request: Actual RESTClient-generated scopes, retained in a bounded test-only buffer.
    ///   - now: Injected monotonic observation instant used by the real authority.
    /// - Returns: The real authority's admission or retry decision.
    /// - Throws: `TestSupportFailure.capacityExceeded` beyond sixteen recordings, or authority failures.
    func reserve(_ request: RateLimitRequest, now: Instant) async throws -> RateLimitAdmission<Instant> {
        guard requests.count < 16 else { throw TestSupportFailure.capacityExceeded }
        requests.append(request)
        return try await store.reserve(request, now: now)
    }

    /// Forwards response learning and ownership cleanup to the issuing authority.
    /// - Parameters:
    ///   - reservation: Exact unmodified reservation issued during admission.
    ///   - status: HTTP status observed by RESTClient.
    ///   - headers: Bounded response headers used to learn rate windows.
    ///   - retryAfter: Optional relative 429 body delay, expressed as a duration.
    ///   - global: Decoded global rejection flag.
    ///   - now: Injected response observation instant.
    /// - Throws: The real authority's ownership, expiration or metadata-learning failures.
    func complete(_ reservation: RateLimitReservation<Instant>, status: Int, headers: [HTTPHeader],
                  retryAfter: Duration?, global: Bool, now: Instant) async throws {
        try await store.complete(reservation, status: status, headers: headers,
            retryAfter: retryAfter, global: global, now: now)
    }

    /// Forwards failed-send cleanup without refunding any global or route quota.
    /// - Parameters:
    ///   - reservation: Previously admitted ownership token.
    ///   - outcome: Whether sending was excluded or remained uncertain.
    ///   - now: Injected cleanup instant for expiration checks.
    /// - Throws: The real authority's ownership or expiration failures.
    func release(_ reservation: RateLimitReservation<Instant>, outcome: RateLimitReleaseOutcome, now: Instant) async throws {
        try await store.release(reservation, outcome: outcome, now: now)
    }

    /// Exposes real aggregate ownership and metadata counts without request labels or secrets.
    /// - Returns: Actual authority counts after earlier awaited admissions and completions.
    func snapshot() async -> SchedulingSnapshot { await store.snapshot() }
}
