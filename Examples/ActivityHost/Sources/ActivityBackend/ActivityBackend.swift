// File: Examples/ActivityHost/Sources/ActivityBackend/ActivityBackend.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCommerce
import DiscordCore
import DiscordHTTP
import DiscordModels
import DiscordOAuth

/// Server-only integration. Deploy independently from ActivityHostSupport and browser assets.
public enum ActivityBackend {
    /// Builds the confidential code exchange after the server validates the caller's application session and replay policy.
    /// - Parameters:
    ///   - code: Code received over an authenticated HTTPS backend request, bound to this application session.
    ///   - applicationID: Server configuration, never selected by iframe input.
    ///   - secret: Backend-owned confidential secret; never return it or the full token response to the iframe.
    /// - Returns: OAuth request descriptor for the server's injected REST pipeline; no I/O starts here.
    /// - Throws: Invalid code/secret/ID or bounded descriptor/body failures. Do not replay ambiguous exchanges.
    public static func exchange(code: OAuthCode, applicationID: ApplicationID, secret: ClientSecret) throws -> Endpoint<OAuthTokenResponse> {
        try OAuthEndpoints.activityAuthorizationCode(code, authentication: .confidential(clientID: applicationID, secret: secret))
    }

    /// Verifies client purchase hints using authoritative entitlement checks and exact server-owned policy.
    /// - Parameters:
    ///   - hints: Host ID array, empty success array, or nil for asynchronous completion. Never an authorization decision.
    ///   - requirement: Server-selected application/SKU and user derived from authenticated session identity.
    ///   - now: Trusted backend clock, called after authoritative reads.
    ///   - fetch: Server-owned GET entitlement executor using its shared credential/rate authority.
    /// - Returns: Verified snapshots, empty verified array, or nil requiring a later server check. Only grant on verified data.
    /// - Throws: Cancellation, malformed IDs/duplicates/over-100 hints, policy rejection or backend transport/API failure.
    /// Durable ENTITLEMENT_CREATE webhook processing can trigger the same check; browser events remain hints.
    public static func verifyPurchase(hints: [String]?, requirement: EntitlementRequirement,
        now: @Sendable () -> DiscordTimestamp,
        fetch: @Sendable (Endpoint<Entitlement>) async throws -> Entitlement) async throws -> [Entitlement]? {
        let ids: [EntitlementID]?
        if let hints {
            guard hints.count <= 100 else { throw EntitlementVerificationError.invalidPurchaseAcknowledgement }
            ids = try hints.map { value in
                guard let id = EntitlementID(value) else { throw EntitlementVerificationError.invalidPurchaseAcknowledgement }
                return id
            }
        } else { ids = nil }
        return try await ActivityPurchasing.purchase(requirement: requirement, now: now, startPurchase: { _ in ids }, fetch: fetch)
    }
}
