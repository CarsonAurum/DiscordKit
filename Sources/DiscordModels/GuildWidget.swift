// File: Sources/DiscordModels/GuildWidget.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import Foundation

/// Guild widget configuration. Null channel means the widget does not generate an invite; configuration does not establish public widget visibility.
/// API v10; verified 2026-10-16 against https://docs.discord.com/developers/resources/guild,
/// the Permissions/Voice references and https://github.com/discord/discord-api-spec/blob/main/specs/openapi.json.
public struct GuildWidgetSettings: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Wire `enabled` value; required and nonnull.
    public let enabled: Bool
    /// Wire `channel_id` value; required but explicitly nullable.
    public let channelID: Nullable<ChannelID>
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
        enabled = try object.required("enabled", Bool.self)
        channelID = try object.required("channel_id", Nullable<ChannelID>.self)
        rawFields = object.resource.fields
    }
}

/// A public guild widget with anonymized partial members and visible voice/stage channels. Widget IDs, discriminators and avatars are anonymized; never use these member IDs as real Discord identities or to hydrate guild members.
/// API v10; verified 2026-10-16 against https://docs.discord.com/developers/resources/guild,
/// the Permissions/Voice references and https://github.com/discord/discord-api-spec/blob/main/specs/openapi.json.
public struct GuildWidget: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Wire `id` value; required and nonnull.
    public let id: GuildID
    /// Wire `name` value; required and nonnull.
    public let name: String
    /// Wire `instant_invite` value; required but explicitly nullable.
    public let instantInvite: Nullable<String>
    /// Wire `channels` value; required and nonnull.
    public let channels: [GuildWidgetChannel]
    /// Wire `members` value; required and nonnull.
    public let members: [GuildWidgetMember]
    /// Wire `presence_count` value; required and nonnull.
    public let presenceCount: Int
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
        id = try object.required("id", GuildID.self)
        name = try object.required("name", String.self)
        instantInvite = try object.required("instant_invite", Nullable<String>.self)
        channels = try object.messageModels("channels", GuildWidgetChannel.self)
        members = try object.messageModels("members", GuildWidgetMember.self)
        presenceCount = try object.required("presence_count", Int.self)
        rawFields = object.resource.fields
    }
}

/// A widget-owned partial Channel projection. Only widget display fields are interpreted; missing data does not establish current channel type or permissions.
/// API v10; verified 2026-10-16 against https://docs.discord.com/developers/resources/guild,
/// the Permissions/Voice references and https://github.com/discord/discord-api-spec/blob/main/specs/openapi.json.
public struct GuildWidgetChannel: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Wire `id` value; required and nonnull.
    public let id: ChannelID
    /// Wire `name` value; optional and nonnull when present.
    public let name: Field<String>
    /// Wire `position` value; optional and nonnull when present.
    public let position: Field<Int>
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
        id = try object.required("id", ChannelID.self)
        name = try object.field("name", String.self)
        position = try object.field("position", Int.self)
        rawFields = object.resource.fields
    }
}

/// An anonymized widget member display projection. The opaque id is deliberately a String rather than UserID, and every non-widget User field remains exact without implying real identity.
/// API v10; verified 2026-10-16 against https://docs.discord.com/developers/resources/guild,
/// the Permissions/Voice references and https://github.com/discord/discord-api-spec/blob/main/specs/openapi.json.
public struct GuildWidgetMember: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Wire `id` value; required and nonnull.
    public let id: String
    /// Wire `username` value; optional and nonnull when present.
    public let username: Field<String>
    /// Wire `discriminator` value; optional and nonnull when present.
    public let discriminator: Field<String>
    /// Wire `avatar` value; omission remains distinct from explicit null.
    public let avatar: Field<String>
    /// Wire `status` value; optional and nonnull when present.
    public let status: Field<String>
    /// Wire `avatar_url` value; optional and nonnull when present.
    public let avatarURL: Field<String>
    /// Wire `deaf` value; optional and nonnull when present.
    public let deaf: Field<Bool>
    /// Wire `mute` value; optional and nonnull when present.
    public let mute: Field<Bool>
    /// Wire `self_deaf` value; optional and nonnull when present.
    public let selfDeaf: Field<Bool>
    /// Wire `self_mute` value; optional and nonnull when present.
    public let selfMute: Field<Bool>
    /// Wire `suppress` value; optional and nonnull when present.
    public let suppress: Field<Bool>
    /// Wire `channel_id` value; optional and nonnull when present.
    public let channelID: Field<ChannelID>
    /// Optional OpenAPI widget display activity; other User data remains an explicit partial projection.
    public let activity: Field<GuildWidgetActivity>
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
        username = try object.field("username", String.self)
        discriminator = try object.field("discriminator", String.self)
        avatar = try object.field("avatar", String.self, nullable: true)
        status = try object.field("status", String.self)
        avatarURL = try object.field("avatar_url", String.self)
        deaf = try object.field("deaf", Bool.self)
        mute = try object.field("mute", Bool.self)
        selfDeaf = try object.field("self_deaf", Bool.self)
        selfMute = try object.field("self_mute", Bool.self)
        suppress = try object.field("suppress", Bool.self)
        channelID = try object.field("channel_id", ChannelID.self)
        activity = try object.messageField("activity", GuildWidgetActivity.self)
        rawFields = object.resource.fields
    }
}

/// The guild-owned partial vanity invite result. Null code means no vanity URL; uses is a returned count and no Invite-family completion is implied.
/// API v10; verified 2026-10-16 against https://docs.discord.com/developers/resources/guild,
/// the Permissions/Voice references and https://github.com/discord/discord-api-spec/blob/main/specs/openapi.json.
public struct GuildVanityURL: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Wire `code` value; required but explicitly nullable.
    public let code: Nullable<String>
    /// Wire `uses` value; required and nonnull.
    public let uses: Int
    /// Optional nullable OpenAPI vanity configuration error envelope; a successful HTTP response may still include this diagnostic.
    public let error: Field<GuildVanityError>
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
        code = try object.required("code", Nullable<String>.self)
        uses = try object.required("uses", Int.self)
        error = try object.messageField("error", GuildVanityError.self, nullable: true)
        rawFields = object.resource.fields
    }
}

/// The documented public widget activity display metadata. Only its name is modeled; no full Activity resource, execution permission or application identity is inferred.
/// API v10; verified 2026-10-16 against https://docs.discord.com/developers/resources/guild,
/// the Permissions/Voice references and https://github.com/discord/discord-api-spec/blob/main/specs/openapi.json.
public struct GuildWidgetActivity: MessageResponseValue, MessageTreeProjectable, Equatable {
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
        name = try object.required("name", String.self)
        rawFields = object.resource.fields
    }
}

/// A vanity configuration diagnostic included in an otherwise successful response. The code and message are data; HTTP status and retry policy are handled separately. Diagnostics redact private message content.
/// API v10; verified 2026-10-16 against https://docs.discord.com/developers/resources/guild,
/// the Permissions/Voice references and https://github.com/discord/discord-api-spec/blob/main/specs/openapi.json.
public struct GuildVanityError: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Wire `message` value; required and nonnull.
    public let message: String
    /// Wire `code` value; required and nonnull.
    public let code: Int
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
        message = try object.required("message", String.self)
        code = try object.required("code", Int.self)
        rawFields = object.resource.fields
    }
}
