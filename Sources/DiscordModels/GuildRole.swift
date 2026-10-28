// File: Sources/DiscordModels/GuildRole.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import Foundation

/// A complete role metadata snapshot, including deprecated color and current gradient colors. Role ordering and permissions require guild/channel context and this value performs no permission resolution.
/// API v10; verified 2026-10-16 against https://docs.discord.com/developers/resources/guild,
/// the Permissions/Voice references and https://github.com/discord/discord-api-spec/blob/main/specs/openapi.json.
public struct GuildRole: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Wire `id` value; required and nonnull.
    public let id: RoleID
    /// Wire `name` value; required and nonnull.
    public let name: String
    /// Deprecated RGB integer; current APIs recommend the colors object. Preserved for wire compatibility.
    public let color: Int
    /// Wire `colors` value; required and nonnull.
    public let colors: GuildRoleColors
    /// Wire `hoist` value; required and nonnull.
    public let hoist: Bool
    /// Wire `icon` value; omission remains distinct from explicit null.
    public let icon: Field<String>
    /// Wire `unicode_emoji` value; omission remains distinct from explicit null.
    public let unicodeEmoji: Field<String>
    /// Role position; equal positions sort by role ID.
    public let position: Int
    /// Arbitrary-width decimal permission string; no native integer truncation or permission inference.
    public let permissions: String
    /// Wire `managed` value; required and nonnull.
    public let managed: Bool
    /// Wire `mentionable` value; required and nonnull.
    public let mentionable: Bool
    /// Wire `tags` value; optional and nonnull when present.
    public let tags: Field<GuildRoleTags>
    /// Exact role response bitfield; see GuildRoleFlags for currently named bits.
    public let flags: UInt64
    /// Complete original object, including unknown keys and exact numeric lexemes; diagnostics redact payloads.
    public let rawFields: [String: JSONValue]

    /// Parses one complete API v10 object synchronously with exact unknown-field retention.
    /// - Parameters:
    ///   - data: Complete UTF-8 JSON object, optionally surrounded by JSON whitespace. Required keys must
    ///     exist even when their values are nullable; duplicate keys and additional trailing documents are invalid.
    ///   - limits: Bounds for all content, including unknown subtrees: positive UTF-8 byte/node maxima and
    ///     container depth in 1...128. Defaults to 1,048,576 bytes, depth 64 and 100,000 total JSON values.
    /// - Throws: `JSONValueError` for invalid limits, invalid JSON/Unicode, duplicate keys or exceeded bounds;
    ///   `DiscordError.transport(.invalidResponse)` for missing, forbidden-null, mistyped or out-of-range
    ///   modeled fields. Schema error messages never include payload values. Correct input or limits before retrying.
    /// Parsing performs no I/O, suspension, cache mutation, credential access or resource ownership changes.
    /// Work completes synchronously and cannot observe cooperative task cancellation during decoding.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects a bounded immutable subtree without reparsing nested objects or normalizing unknown values.
    /// - Parameters:
    ///   - value: Original object subtree whose complete containing document already passed parser limits.
    ///   - limits: Bounds from that root parse, reused for scalar validation and exact integer decoding.
    /// - Throws: `DiscordError.transport(.invalidResponse)` for a nonobject root or a malformed modeled
    ///   field, including forbidden omission/null and incompatible exact integer, identifier or timestamp values
    ///   where those types are modeled. Payload text is not disclosed. Callers must correct the response/input.
    /// Construction is synchronous, shares immutable tree storage, and performs no I/O or ownership changes;
    /// it neither suspends nor checks task cancellation. Parser limits are a required caller-established invariant.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        id = try object.required("id", RoleID.self)
        name = try object.required("name", String.self)
        color = try object.required("color", Int.self)
        colors = try object.messageModel("colors", GuildRoleColors.self)
        hoist = try object.required("hoist", Bool.self)
        icon = try object.field("icon", String.self, nullable: true)
        unicodeEmoji = try object.field("unicode_emoji", String.self, nullable: true)
        position = try object.required("position", Int.self)
        permissions = try object.required("permissions", String.self)
        managed = try object.required("managed", Bool.self)
        mentionable = try object.required("mentionable", Bool.self)
        tags = try object.messageField("tags", GuildRoleTags.self)
        flags = try object.required("flags", UInt64.self)
        try validateChannelPermissionBits(permissions)
        rawFields = object.resource.fields
    }
}

/// Current role colors, including gradient/holographic fields. Enhanced role color entitlement and fixed holographic combinations constrain requests; response values are preserved without guessing future constraints.
/// API v10; verified 2026-10-16 against https://docs.discord.com/developers/resources/guild,
/// the Permissions/Voice references and https://github.com/discord/discord-api-spec/blob/main/specs/openapi.json.
public struct GuildRoleColors: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Wire `primary_color` value; required and nonnull.
    public let primaryColor: Int
    /// Wire `secondary_color` value; required but explicitly nullable.
    public let secondaryColor: Nullable<Int>
    /// Wire `tertiary_color` value; required but explicitly nullable.
    public let tertiaryColor: Nullable<Int>
    /// Complete original object, including unknown keys and exact numeric lexemes; diagnostics redact payloads.
    public let rawFields: [String: JSONValue]

    /// Parses one complete API v10 object synchronously with exact unknown-field retention.
    /// - Parameters:
    ///   - data: Complete UTF-8 JSON object, optionally surrounded by JSON whitespace. Required keys must
    ///     exist even when their values are nullable; duplicate keys and additional trailing documents are invalid.
    ///   - limits: Bounds for all content, including unknown subtrees: positive UTF-8 byte/node maxima and
    ///     container depth in 1...128. Defaults to 1,048,576 bytes, depth 64 and 100,000 total JSON values.
    /// - Throws: `JSONValueError` for invalid limits, invalid JSON/Unicode, duplicate keys or exceeded bounds;
    ///   `DiscordError.transport(.invalidResponse)` for missing, forbidden-null, mistyped or out-of-range
    ///   modeled fields. Schema error messages never include payload values. Correct input or limits before retrying.
    /// Parsing performs no I/O, suspension, cache mutation, credential access or resource ownership changes.
    /// Work completes synchronously and cannot observe cooperative task cancellation during decoding.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects a bounded immutable subtree without reparsing nested objects or normalizing unknown values.
    /// - Parameters:
    ///   - value: Original object subtree whose complete containing document already passed parser limits.
    ///   - limits: Bounds from that root parse, reused for scalar validation and exact integer decoding.
    /// - Throws: `DiscordError.transport(.invalidResponse)` for a nonobject root or a malformed modeled
    ///   field, including forbidden omission/null and incompatible exact integer, identifier or timestamp values
    ///   where those types are modeled. Payload text is not disclosed. Callers must correct the response/input.
    /// Construction is synchronous, shares immutable tree storage, and performs no I/O or ownership changes;
    /// it neither suspends nor checks task cancellation. Parser limits are a required caller-established invariant.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        primaryColor = try object.required("primary_color", Int.self)
        secondaryColor = try object.required("secondary_color", Nullable<Int>.self)
        tertiaryColor = try object.required("tertiary_color", Nullable<Int>.self)
        rawFields = object.resource.fields
    }
}

/// Role ownership and subscription metadata. Null sentinel tags mean true; absence means false. Explicit false, true or any nonnull sentinel value is invalid.
/// API v10; verified 2026-10-16 against https://docs.discord.com/developers/resources/guild,
/// the Permissions/Voice references and https://github.com/discord/discord-api-spec/blob/main/specs/openapi.json.
public struct GuildRoleTags: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Wire `bot_id` value; optional and nonnull when present.
    public let botID: Field<UserID>
    /// Wire `integration_id` value; optional and nonnull when present.
    public let integrationID: Field<GuildIntegrationID>
    /// Wire `premium_subscriber` value; only explicit null is valid when present; omission remains absent.
    public let premiumSubscriber: Field<JSONValue>
    /// Wire `subscription_listing_id` value; optional and nonnull when present.
    public let subscriptionListingID: Field<RoleSubscriptionListingID>
    /// Wire `available_for_purchase` value; only explicit null is valid when present; omission remains absent.
    public let availableForPurchase: Field<JSONValue>
    /// Wire `guild_connections` value; only explicit null is valid when present; omission remains absent.
    public let guildConnections: Field<JSONValue>
    /// Complete original object, including unknown keys and exact numeric lexemes; diagnostics redact payloads.
    public let rawFields: [String: JSONValue]

    /// Parses one complete API v10 object synchronously with exact unknown-field retention.
    /// - Parameters:
    ///   - data: Complete UTF-8 JSON object, optionally surrounded by JSON whitespace. Required keys must
    ///     exist even when their values are nullable; duplicate keys and additional trailing documents are invalid.
    ///   - limits: Bounds for all content, including unknown subtrees: positive UTF-8 byte/node maxima and
    ///     container depth in 1...128. Defaults to 1,048,576 bytes, depth 64 and 100,000 total JSON values.
    /// - Throws: `JSONValueError` for invalid limits, invalid JSON/Unicode, duplicate keys or exceeded bounds;
    ///   `DiscordError.transport(.invalidResponse)` for missing, forbidden-null, mistyped or out-of-range
    ///   modeled fields. Schema error messages never include payload values. Correct input or limits before retrying.
    /// Parsing performs no I/O, suspension, cache mutation, credential access or resource ownership changes.
    /// Work completes synchronously and cannot observe cooperative task cancellation during decoding.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects a bounded immutable subtree without reparsing nested objects or normalizing unknown values.
    /// - Parameters:
    ///   - value: Original object subtree whose complete containing document already passed parser limits.
    ///   - limits: Bounds from that root parse, reused for scalar validation and exact integer decoding.
    /// - Throws: `DiscordError.transport(.invalidResponse)` for a nonobject root or a malformed modeled
    ///   field, including forbidden omission/null and incompatible exact integer, identifier or timestamp values
    ///   where those types are modeled. Payload text is not disclosed. Callers must correct the response/input.
    /// Construction is synchronous, shares immutable tree storage, and performs no I/O or ownership changes;
    /// it neither suspends nor checks task cancellation. Parser limits are a required caller-established invariant.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        botID = try object.field("bot_id", UserID.self)
        integrationID = try object.field("integration_id", GuildIntegrationID.self)
        if let sentinel = object.resource.fields["premium_subscriber"] {
            guard sentinel == .null else { throw DiscordError.transport(.invalidResponse) }
            premiumSubscriber = .null
        } else { premiumSubscriber = .absent }
        subscriptionListingID = try object.field("subscription_listing_id", RoleSubscriptionListingID.self)
        if let sentinel = object.resource.fields["available_for_purchase"] {
            guard sentinel == .null else { throw DiscordError.transport(.invalidResponse) }
            availableForPurchase = .null
        } else { availableForPurchase = .absent }
        if let sentinel = object.resource.fields["guild_connections"] {
            guard sentinel == .null else { throw DiscordError.transport(.invalidResponse) }
            guildConnections = .null
        } else { guildConnections = .absent }
        rawFields = object.resource.fields
    }
}

/// A dynamic role-ID to member-count response map. The @everyone role is omitted by Discord.
/// Every key must be an exact snowflake string and every count a nonnegative native integer.
/// Decoding performs no permission checks, member hydration or network requests.
public struct GuildRoleMemberCounts: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Complete count map, including zero counts and the maximum unsigned role identifier.
    public let counts: [RoleID: Int]
    /// Exact original dictionary and integer spelling; diagnostic formatting redacts values.
    public let rawFields: [String: JSONValue]

    /// Parses a complete count map synchronously within whole-document parser limits.
    /// - Parameters:
    ///   - data: Complete UTF-8 JSON object mapping decimal snowflake keys to nonnegative integer tokens.
    ///   - limits: Positive byte/node maxima and a depth in 1...128; defaults are 1,048,576 UTF-8 bytes,
    ///     64 nested containers and 100,000 values, counting the complete root.
    /// - Throws: `JSONValueError` for syntax, Unicode, duplicate JSON keys or invalid/exceeded bounds;
    ///   `DiscordError.transport(.invalidResponse)` for invalid keys/counts or duplicate numeric IDs such as
    ///   both "1" and "01". Correct the input or bounds before retrying. No I/O, suspension or task-cancellation check occurs.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Validates one bounded dynamic map without accepting fractional/exponent integer spellings.
    /// - Parameters:
    ///   - value: Original object subtree from a document that already passed parser bounds.
    ///   - limits: The root parser limits, reused for exact native count validation.
    /// - Throws: `DiscordError.transport(.invalidResponse)` for nonobject roots, invalid snowflake keys,
    ///   aliasing keys such as "1"/"01", negative counts, noninteger lexemes or counts above Int.max.
    ///   The error never discloses a key or count; correct the containing response before retrying.
    /// Construction shares immutable raw storage and performs no I/O, suspension, cancellation checks or
    /// ownership changes. The caller must have established whole-document parser limits before entry.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        var decoded: [RoleID: Int] = [:]
        for key in object.resource.fields.keys {
            guard let identifier = RoleID(key) else { throw DiscordError.transport(.invalidResponse) }
            let count = try object.required(key, Int.self)
            guard count >= 0, decoded[identifier] == nil else { throw DiscordError.transport(.invalidResponse) }
            decoded[identifier] = count
        }
        counts = decoded
        rawFields = object.resource.fields
    }
}
