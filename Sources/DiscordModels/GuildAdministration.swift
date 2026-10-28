// File: Sources/DiscordModels/GuildAdministration.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import Foundation

/// Prune count or job result. Explicit null means a prune was started without computing its count; decoding does not imply all removals have completed.
/// API v10; verified 2026-10-16 against https://docs.discord.com/developers/resources/guild,
/// the Permissions/Voice references and https://github.com/discord/discord-api-spec/blob/main/specs/openapi.json.
public struct GuildPruneCount: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Wire `pruned` value; required but explicitly nullable.
    public let pruned: Nullable<Int>
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
        pruned = try object.required("pruned", Nullable<Int>.self)
        if case .value(let count) = pruned, count < 0 { throw DiscordError.transport(.invalidResponse) }
        rawFields = object.resource.fields
    }
}

/// A voice region offered to this guild. IDs are opaque strings rather than snowflakes; deprecated regions should not be selected for new channels.
/// API v10; verified 2026-10-16 against https://docs.discord.com/developers/resources/guild,
/// the Permissions/Voice references and https://github.com/discord/discord-api-spec/blob/main/specs/openapi.json.
public struct GuildVoiceRegion: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Wire `id` value; required and nonnull.
    public let id: String
    /// Wire `name` value; required and nonnull.
    public let name: String
    /// Wire `optimal` value; required and nonnull.
    public let optimal: Bool
    /// Wire `deprecated` value; required and nonnull.
    public let deprecated: Bool
    /// Wire `custom` value; required and nonnull.
    public let custom: Bool
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
        id = try object.required("id", String.self)
        name = try object.required("name", String.self)
        optimal = try object.required("optimal", Bool.self)
        deprecated = try object.required("deprecated", Bool.self)
        custom = try object.required("custom", Bool.self)
        rawFields = object.resource.fields
    }
}

/// A complete documented guild Integration shape. Discord bot integrations omit syncing/subscriber fields; older integrations may omit user. Related User data remains explicitly partial.
/// API v10; verified 2026-10-16 against https://docs.discord.com/developers/resources/guild,
/// the Permissions/Voice references and https://github.com/discord/discord-api-spec/blob/main/specs/openapi.json.
public struct GuildIntegration: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Exact opaque integration identifier. The written table uses snowflakes, while the official external-connection schema permits provider strings; validate separately before constructing a GuildIntegrationID route input.
    public let id: String
    /// Integration name, explicitly nullable in the official variant schemas despite the written table string type.
    public let name: Nullable<String>
    /// Wire `type` value; required and nonnull.
    public let type: RawValue<GuildIntegrationType>
    /// Wire `enabled` value; required and nonnull.
    public let enabled: Bool
    /// Wire `syncing` value; optional and nonnull when present.
    public let syncing: Field<Bool>
    /// Subscriber role, absent for bot integrations and explicitly nullable in the external-connection schema.
    public let roleID: Field<RoleID>
    /// Wire `enable_emoticons` value; optional and nonnull when present.
    public let enableEmoticons: Field<Bool>
    /// Wire `expire_behavior` value; optional and nonnull when present.
    public let expireBehavior: Field<RawValue<GuildIntegrationExpireBehavior>>
    /// Subscriber expiration grace period in days.
    public let expireGracePeriod: Field<Int>
    /// Wire `user` value; optional and nonnull when present.
    public let user: Field<ChannelRecipient>
    /// Wire `account` value; required and nonnull.
    public let account: GuildIntegrationAccount
    /// Wire `synced_at` value; optional and nonnull when present.
    public let syncedAt: Field<DiscordTimestamp>
    /// Wire `subscriber_count` value; optional and nonnull when present.
    public let subscriberCount: Field<Int>
    /// Wire `revoked` value; optional and nonnull when present.
    public let revoked: Field<Bool>
    /// Wire `application` value; optional and nonnull when present.
    public let application: Field<GuildIntegrationApplication>
    /// Wire `scopes` value; optional and nonnull when present.
    public let scopes: Field<[String]>
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
        id = try object.required("id", String.self)
        name = try object.required("name", Nullable<String>.self)
        type = try object.required("type", RawValue<GuildIntegrationType>.self)
        enabled = try object.required("enabled", Bool.self)
        syncing = try object.field("syncing", Bool.self)
        roleID = try object.field("role_id", RoleID.self, nullable: true)
        enableEmoticons = try object.field("enable_emoticons", Bool.self)
        expireBehavior = try object.field("expire_behavior", RawValue<GuildIntegrationExpireBehavior>.self)
        expireGracePeriod = try object.field("expire_grace_period", Int.self)
        user = try object.messageField("user", ChannelRecipient.self)
        account = try object.messageModel("account", GuildIntegrationAccount.self)
        syncedAt = try object.field("synced_at", DiscordTimestamp.self)
        subscriberCount = try object.field("subscriber_count", Int.self)
        revoked = try object.field("revoked", Bool.self)
        application = try object.messageField("application", GuildIntegrationApplication.self)
        scopes = try object.field("scopes", [String].self)
        rawFields = object.resource.fields
    }
}

/// An integration provider account. Its identifier is an opaque external string and must never be coerced to a Discord snowflake.
/// API v10; verified 2026-10-16 against https://docs.discord.com/developers/resources/guild,
/// the Permissions/Voice references and https://github.com/discord/discord-api-spec/blob/main/specs/openapi.json.
public struct GuildIntegrationAccount: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Wire `id` value; required and nonnull.
    public let id: String
    /// Wire `name` value; required and nonnull.
    public let name: String
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
        id = try object.required("id", String.self)
        name = try object.required("name", String.self)
        rawFields = object.resource.fields
    }
}

/// The integration-owned Application envelope, not full Application resource parity. The optional bot is an explicit partial User projection; unknown Application data remains exact.
/// API v10; verified 2026-10-16 against https://docs.discord.com/developers/resources/guild,
/// the Permissions/Voice references and https://github.com/discord/discord-api-spec/blob/main/specs/openapi.json.
public struct GuildIntegrationApplication: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Wire `id` value; required and nonnull.
    public let id: ApplicationID
    /// Wire `name` value; required and nonnull.
    public let name: String
    /// Wire `icon` value; required but explicitly nullable.
    public let icon: Nullable<String>
    /// Wire `description` value; required and nonnull.
    public let applicationDescription: String
    /// Wire `bot` value; optional and nonnull when present.
    public let bot: Field<ChannelRecipient>
    /// OpenAPI Application type; future integer values and explicit null survive. Optional for written-table compatibility.
    public let type: Field<RawValue<GuildIntegrationApplicationType>>
    /// Wire `cover_image` value; optional and nonnull when present.
    public let coverImage: Field<String>
    /// Wire `primary_sku_id` value; optional and nonnull when present.
    public let primarySKUID: Field<SKUID>
    /// OpenAPI legacy flags including unknown bits; optional for written-table compatibility.
    public let flags: Field<UInt64>
    /// OpenAPI complete arbitrary-width flag text; optional for written-table compatibility.
    public let flagsNew: Field<String>
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
        id = try object.required("id", ApplicationID.self)
        name = try object.required("name", String.self)
        icon = try object.required("icon", Nullable<String>.self)
        applicationDescription = try object.required("description", String.self)
        bot = try object.messageField("bot", ChannelRecipient.self)
        type = try object.field("type", RawValue<GuildIntegrationApplicationType>.self, nullable: true)
        coverImage = try object.field("cover_image", String.self)
        primarySKUID = try object.field("primary_sku_id", SKUID.self)
        flags = try object.field("flags", UInt64.self)
        flagsNew = try object.field("flags_new", String.self)
        rawFields = object.resource.fields
    }
}

/// Guild incident actions and optional detection timestamps. Null action times disable the corresponding action; null detection is distinct from absent detection data. Timestamp parsing performs no clock lookup, duration validation or enforcement.
/// API v10; verified 2026-10-16 against https://docs.discord.com/developers/resources/guild,
/// the Permissions/Voice references and https://github.com/discord/discord-api-spec/blob/main/specs/openapi.json.
public struct GuildIncidentsData: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Wire `invites_disabled_until` value; required but explicitly nullable.
    public let invitesDisabledUntil: Nullable<DiscordTimestamp>
    /// Wire `dms_disabled_until` value; required but explicitly nullable.
    public let dmsDisabledUntil: Nullable<DiscordTimestamp>
    /// Wire `dm_spam_detected_at` value; omission remains distinct from explicit null.
    public let dmSpamDetectedAt: Field<DiscordTimestamp>
    /// Wire `raid_detected_at` value; omission remains distinct from explicit null.
    public let raidDetectedAt: Field<DiscordTimestamp>
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
        invitesDisabledUntil = try object.required("invites_disabled_until", Nullable<DiscordTimestamp>.self)
        dmsDisabledUntil = try object.required("dms_disabled_until", Nullable<DiscordTimestamp>.self)
        dmSpamDetectedAt = try object.field("dm_spam_detected_at", DiscordTimestamp.self, nullable: true)
        raidDetectedAt = try object.field("raid_detected_at", DiscordTimestamp.self, nullable: true)
        rawFields = object.resource.fields
    }
}
