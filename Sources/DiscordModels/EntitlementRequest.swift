// File: Sources/DiscordModels/EntitlementRequest.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore

/// Exactly one typed recipient for a test entitlement; the wire owner discriminator is derived from its ID domain.
public enum TestEntitlementOwner: Sendable, Equatable {
    /// Grants a test entitlement to a guild using wire owner_type 1.
    case guild(GuildID)
    /// Grants a test entitlement to a user using wire owner_type 2.
    case user(UserID)
}

/// API v10 POST /applications/{application.id}/entitlements test body. Requires the application's bot
/// credential; Discord checks SKU ownership and test eligibility. Test access is perpetual until deleted,
/// and users may need to reload their client. This value never issues a request or grants access locally.
public struct CreateTestEntitlementRequest: UserRequestPayload {
    private let fields: [String: JSONValue]

    /// Encodes a typed SKU and recipient without accepting mismatched owner ID/discriminator combinations.
    /// - Parameters:
    ///   - skuID: Exact offering ID; for subscriptions Discord documents using the type-5 subscription SKU.
    ///   - owner: Guild or user recipient with a domain-specific ID. All unsigned 64-bit IDs are retained,
    ///     including zero; resource existence, application ownership and eligibility remain Discord's checks.
    /// - Throws: Numeric JSON construction errors propagated by the shared encoder; the fixed documented
    ///   owner discriminators are always valid JSON integers, so typed caller input introduces no failure branch.
    /// Construction is synchronous with no I/O, tasks, scope lookup, hidden reads or state mutation.
    public init(skuID: SKUID, owner: TestEntitlementOwner) throws {
        let ownerID: String
        let ownerType: Int
        switch owner {
        case .guild(let id): ownerID = id.description; ownerType = 1
        case .user(let id): ownerID = id.description; ownerType = 2
        }
        fields = ["sku_id": .string(skuID.description), "owner_id": .string(ownerID),
            "owner_type": try guildRequestNumber(ownerType)]
    }

    /// Produces the three exact test-create fields without an application ID, omitted defaults or preliminary read.
    /// - Returns: Immutable JSON body; deliberate inspection exposes recipient IDs while ordinary diagnostics redact them.
    public func jsonValue() -> JSONValue { .object(fields) }
}
