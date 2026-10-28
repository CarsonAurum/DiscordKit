// File: Sources/DiscordModels/GuildMember.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import Foundation

/// A guild-owned member snapshot. The related User remains an explicit partial ChannelRecipient projection. Omitted user is valid in message events; joinedAt can be null for voice guests. Membership Screening uses pending true before acceptance and false after the Guild Member Update; no undocumented screening form API is assumed.
/// API v10; verified 2026-10-16 against https://docs.discord.com/developers/resources/guild,
/// the Permissions/Voice references and https://github.com/discord/discord-api-spec/blob/main/specs/openapi.json.
public struct GuildMember: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Wire `user` value; optional and nonnull when present.
    public let user: Field<ChannelRecipient>
    /// Wire `nick` value; omission remains distinct from explicit null.
    public let nick: Field<String>
    /// Wire `avatar` value; omission remains distinct from explicit null.
    public let avatar: Field<String>
    /// Wire `banner` value; omission remains distinct from explicit null.
    public let banner: Field<String>
    /// Wire `roles` value; required and nonnull.
    public let roles: [RoleID]
    /// Wire `joined_at` value; required but explicitly nullable.
    public let joinedAt: Nullable<DiscordTimestamp>
    /// Wire `premium_since` value; omission remains distinct from explicit null.
    public let premiumSince: Field<DiscordTimestamp>
    /// Wire `deaf` value; required and nonnull.
    public let deaf: Bool
    /// Wire `mute` value; required and nonnull.
    public let mute: Bool
    /// Exact member flags, retaining future bits; see GuildMemberFlags. Only BYPASSES_VERIFICATION is currently editable.
    public let flags: UInt64
    /// Whether Membership Screening remains incomplete. Absence does not assert acceptance; Guild events include an explicit Boolean.
    public let pending: Field<Bool>
    /// Interaction channel permissions including overwrites as arbitrary-width decimal text; current authorization is not established.
    public let permissions: Field<String>
    /// Timeout expiry; null or a past timestamp means no active timeout. No clock or permission inference occurs while decoding.
    public let communicationDisabledUntil: Field<DiscordTimestamp>
    /// Wire `avatar_decoration_data` value; omission remains distinct from explicit null.
    public let avatarDecorationData: Field<MessageRelatedResource>
    /// Wire `collectibles` value; omission remains distinct from explicit null.
    public let collectibles: Field<MessageRelatedResource>
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
        user = try object.messageField("user", ChannelRecipient.self)
        nick = try object.field("nick", String.self, nullable: true)
        avatar = try object.field("avatar", String.self, nullable: true)
        banner = try object.field("banner", String.self, nullable: true)
        roles = try object.required("roles", [RoleID].self)
        joinedAt = try object.required("joined_at", Nullable<DiscordTimestamp>.self)
        premiumSince = try object.field("premium_since", DiscordTimestamp.self, nullable: true)
        deaf = try object.required("deaf", Bool.self)
        mute = try object.required("mute", Bool.self)
        flags = try object.required("flags", UInt64.self)
        pending = try object.field("pending", Bool.self)
        permissions = try object.field("permissions", String.self)
        communicationDisabledUntil = try object.field("communication_disabled_until", DiscordTimestamp.self, nullable: true)
        avatarDecorationData = try object.messageField("avatar_decoration_data", MessageRelatedResource.self, nullable: true)
        collectibles = try object.messageField("collectibles", MessageRelatedResource.self, nullable: true)
        if case .value(let bits) = permissions { try validateChannelPermissionBits(bits) }
        rawFields = object.resource.fields
    }
}

/// One guild ban with nullable private reason and an explicit partial User projection. Pagination uses user IDs and full authorization/error behavior belongs to the HTTP operation.
/// API v10; verified 2026-10-16 against https://docs.discord.com/developers/resources/guild,
/// the Permissions/Voice references and https://github.com/discord/discord-api-spec/blob/main/specs/openapi.json.
public struct GuildBan: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Wire `reason` value; required but explicitly nullable.
    public let reason: Nullable<String>
    /// Wire `user` value; required and nonnull.
    public let user: ChannelRecipient
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
        reason = try object.required("reason", Nullable<String>.self)
        user = try object.messageModel("user", ChannelRecipient.self)
        rawFields = object.resource.fields
    }
}

/// A partial-success bulk-ban result retaining banned and failed ID lists in server order. Failure can mean an existing ban or a user that could not be banned; the response does not claim transactional behavior.
/// API v10; verified 2026-10-16 against https://docs.discord.com/developers/resources/guild,
/// the Permissions/Voice references and https://github.com/discord/discord-api-spec/blob/main/specs/openapi.json.
public struct GuildBulkBanResult: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Wire `banned_users` value; required and nonnull.
    public let bannedUsers: [UserID]
    /// Wire `failed_users` value; required and nonnull.
    public let failedUsers: [UserID]
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
        bannedUsers = try object.required("banned_users", [UserID].self)
        failedUsers = try object.required("failed_users", [UserID].self)
        rawFields = object.resource.fields
    }
}

/// The deprecated current-user nickname endpoint response. Prefer modifying the current GuildMember; null clears the nickname.
/// API v10; verified 2026-10-16 against https://docs.discord.com/developers/resources/guild,
/// the Permissions/Voice references and https://github.com/discord/discord-api-spec/blob/main/specs/openapi.json.
public struct GuildNickname: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Wire `nick` value; required but explicitly nullable.
    public let nick: Nullable<String>
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
        nick = try object.required("nick", Nullable<String>.self)
        rawFields = object.resource.fields
    }
}
