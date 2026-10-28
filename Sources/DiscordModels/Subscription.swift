// File: Sources/DiscordModels/Subscription.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import Foundation

/// Complete written API v10 recurring-payment snapshot, verified 2026-10-16 against
/// https://docs.discord.com/developers/resources/subscription. A subscription's ID determines its initial
/// start; period timestamps change on renewal and cancellation moves it to ending with a cancellation time.
/// Status is independent of current access: evaluate entitlements for perks, never status or period alone.
/// The official OpenAPI preview permits an explicit null country in addition to the written field's omission.
public struct Subscription: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Exact recurring subscription identifier; its snowflake encodes subscription creation time.
    public let id: SubscriptionID
    /// Subscribed user.
    public let userID: UserID
    /// Subscribed offerings in original wire order, including an empty list if supplied.
    public let skuIDs: [SKUID]
    /// Associated entitlement identifiers in original wire order; the list may be empty.
    public let entitlementIDs: [EntitlementID]
    /// Offerings selected for renewal; explicit null remains distinct from an empty list.
    public let renewalSKUIDs: Nullable<[SKUID]>
    /// Start of the current billing period; not an authorization decision or immutable creation date.
    public let currentPeriodStart: DiscordTimestamp
    /// End of the current billing period; status can remain active beyond this time while payment retries.
    public let currentPeriodEnd: DiscordTimestamp
    /// Payment lifecycle state, retaining future integral values; never sufficient to grant perks.
    public let status: RawValue<SubscriptionStatus>
    /// Cancellation time, or explicit null when no cancellation is recorded.
    public let canceledAt: Nullable<DiscordTimestamp>
    /// Payment-source country; omitted unless queried using a private OAuth scope. The official OpenAPI
    /// preview's explicit null is preserved separately from absence; no locale or payment-source inference occurs.
    public let country: Field<String>
    /// Complete original object, preserving unknown fields and numeric lexemes; diagnostics conceal it.
    public let rawFields: [String: JSONValue]

    /// Parses one billing snapshot without loading entitlements, calculating access or scheduling renewals.
    /// - Parameters:
    ///   - data: Complete UTF-8 JSON object, with duplicate keys and trailing documents rejected.
    ///   - limits: Whole-document byte/depth/node bounds including unknown fields; default is 1 MiB/64/100,000.
    /// - Throws: `JSONValueError` for syntax, duplicate keys, invalid bounds or exceeded limits; sanitized
    ///   `DiscordError.transport(.invalidResponse)` for missing, forbidden-null, mistyped or out-of-range known
    ///   fields, invalid IDs/timestamps or nonintegral lifecycle states. Correct malformed input before retrying.
    /// Construction is synchronous, owns no network resources and performs no I/O, suspension or cancellation check.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects a bounded recurring-payment subtree without imposing access or cross-field lifecycle rules.
    /// - Parameters:
    ///   - value: Immutable object subtree whose complete outer document already passed parser limits.
    ///   - limits: Root-document bounds reused for scalar validation and exact integral discriminators.
    /// - Throws: Sanitized invalid-response errors for nonobjects or malformed modeled fields; scalar
    ///   serialization may report limit errors. Unknown states and unusual period/status combinations survive.
    /// This synchronous projection performs no state mutation, suspension, network I/O or authorization inference.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        id = try object.required("id", SubscriptionID.self)
        userID = try object.required("user_id", UserID.self)
        skuIDs = try object.required("sku_ids", [SKUID].self)
        entitlementIDs = try object.required("entitlement_ids", [EntitlementID].self)
        renewalSKUIDs = try object.required("renewal_sku_ids", Nullable<[SKUID]>.self)
        currentPeriodStart = try object.required("current_period_start", DiscordTimestamp.self)
        currentPeriodEnd = try object.required("current_period_end", DiscordTimestamp.self)
        status = try object.required("status", RawValue<SubscriptionStatus>.self)
        canceledAt = try object.required("canceled_at", Nullable<DiscordTimestamp>.self)
        country = try object.field("country", String.self, nullable: true)
        rawFields = object.resource.fields
    }
}
