// File: Sources/DiscordModels/Entitlement.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import Foundation

/// Written API v10 entitlement snapshot, verified 2026-10-16 against
/// https://docs.discord.com/developers/resources/entitlement. Normal reads, premium interaction data and
/// perpetual partial test-create responses share this model; test responses omit start/end/subscription fields.
/// The official OpenAPI preview additionally permits null guild IDs; preview-only fulfillment/gifting fields
/// remain unprojected in `rawFields` and do not imply support for those separate feature surfaces.
/// The snapshot does not infer present access, freshness or consumption success; callers apply their own
/// offering/owner/time/deletion/consumption policy to authoritative entitlement data.
public struct Entitlement: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Exact entitlement identifier.
    public let id: EntitlementID
    /// Offering to which this entitlement applies.
    public let skuID: SKUID
    /// Parent application identifier.
    public let applicationID: ApplicationID
    /// Granted user, when supplied; explicit null is forbidden by the written resource.
    public let userID: Field<UserID>
    /// Entitlement origin, including future integral values.
    public let type: RawValue<EntitlementType>
    /// Whether Discord reports this entitlement deleted.
    public let deleted: Bool
    /// Validity start; null is permitted, and absence is preserved for perpetual test entitlements.
    public let startsAt: Field<DiscordTimestamp>
    /// Validity end; null is permitted, and absence is preserved for perpetual test entitlements.
    public let endsAt: Field<DiscordTimestamp>
    /// Granted guild, when supplied; the official OpenAPI preview's explicit null remains distinct from absence.
    public let guildID: Field<GuildID>
    /// Consumption state for consumable offerings; omission does not mean false.
    public let consumed: Field<Bool>
    /// Related subscription, additively projected from official examples; absent for test entitlements.
    public let subscriptionID: Field<SubscriptionID>
    /// Complete original object, retaining unknown fields and numeric lexemes; ordinary diagnostics redact it.
    public let rawFields: [String: JSONValue]

    /// Parses one immutable entitlement without granting perks, fetching owners or consuming an item.
    /// - Parameters:
    ///   - data: Complete UTF-8 JSON object from a REST response or trusted premium interaction context.
    ///   - limits: Bounds for the entire document including unknown fields; default is 1 MiB/64/100,000.
    /// - Throws: `JSONValueError` for malformed/duplicate/trailing JSON, invalid limits or exceeded bounds;
    ///   sanitized `DiscordError.transport(.invalidResponse)` for missing core keys, forbidden nulls, wrong
    ///   scalar types, invalid IDs/timestamps, nonintegral kinds or overflowing numbers. Correct input before retrying.
    /// Parsing is synchronous with no I/O, suspension, task cancellation check or external resource ownership.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects a bounded entitlement subtree while retaining partial test-response lifecycle presence.
    /// - Parameters:
    ///   - value: Original object whose complete outer document already satisfied parser limits.
    ///   - limits: The same root-document bounds, reused for exact scalar validation.
    /// - Throws: Sanitized invalid-response errors for a nonobject or malformed modeled field; scalar
    ///   serialization may report limit errors. Future kinds and extra fields are retained without policy inference.
    /// Construction neither suspends nor mutates state and does not require owners or timestamps to be hydrated.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        id = try object.required("id", EntitlementID.self)
        skuID = try object.required("sku_id", SKUID.self)
        applicationID = try object.required("application_id", ApplicationID.self)
        userID = try object.field("user_id", UserID.self)
        type = try object.required("type", RawValue<EntitlementType>.self)
        deleted = try object.required("deleted", Bool.self)
        startsAt = try object.field("starts_at", DiscordTimestamp.self, nullable: true)
        endsAt = try object.field("ends_at", DiscordTimestamp.self, nullable: true)
        guildID = try object.field("guild_id", GuildID.self, nullable: true)
        consumed = try object.field("consumed", Bool.self)
        subscriptionID = try object.field("subscription_id", SubscriptionID.self)
        rawFields = object.resource.fields
    }
}
