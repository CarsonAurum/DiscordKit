// File: Sources/DiscordModels/GuildTemplate.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import Foundation

/// An API v10 template with every written resource-owned field, verified 2026-10-16.
/// The serialized guild is a snapshot with integer placeholders, never a live guild or authorization grant.
/// Creator uses the existing partial User projection. No removed create-guild operation is exposed.
public struct GuildTemplate: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Wire `code`; required, nonnull. Omission and explicit null remain distinct.
    public let code: String
    /// Wire `name`; required, nonnull. Omission and explicit null remain distinct.
    public let name: String
    /// Wire `description`; required, nullable. Omission and explicit null remain distinct.
    public let templateDescription: Nullable<String>
    /// Wire `usage_count`; required, nonnull. Omission and explicit null remain distinct.
    public let usageCount: Int
    /// Wire `creator_id`; required, nonnull. Omission and explicit null remain distinct.
    public let creatorID: UserID
    /// Wire `creator`; required, nonnull. Omission and explicit null remain distinct.
    public let creator: MessageAuthor
    /// Wire `created_at`; required, nonnull. Omission and explicit null remain distinct.
    public let createdAt: DiscordTimestamp
    /// Wire `updated_at`; required, nonnull. Omission and explicit null remain distinct.
    public let updatedAt: DiscordTimestamp
    /// Wire `source_guild_id`; required, nonnull. Omission and explicit null remain distinct.
    public let sourceGuildID: GuildID
    /// Wire `serialized_source_guild`; required, nonnull. Omission and explicit null remain distinct.
    public let serializedSourceGuild: GuildTemplateSnapshot
    /// Wire `is_dirty`; required, nullable. Omission and explicit null remain distinct.
    public let isDirty: Nullable<Bool>
    /// Complete original object, including unknown fields and exact numeric spelling; ordinary diagnostics redact it.
    public let rawFields: [String: JSONValue]

    /// Parses an immutable template projection synchronously without I/O or related-resource hydration.
    /// - Parameters:
    ///   - data: Complete UTF-8 object; known fields must match their documented presence and types.
    ///   - limits: Whole-document byte, depth and node bounds, including every unknown subtree; default 1 MiB/64/100,000.
    /// - Throws: JSON syntax/bounds errors or sanitized invalid-response errors for missing, forbidden-null,
    ///   mistyped or overflowing fields. No partial object escapes failure and no external resource is acquired.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects an already bounded subtree while preserving unknown fields and original snapshot identifiers.
    /// - Parameters:
    ///   - value: Original object from a successfully bounded containing document.
    ///   - limits: That document's limits, reused for scalar projection without reparsing nested objects.
    /// - Throws: Sanitized invalid-response errors for incompatible known fields. Work is synchronous,
    ///   owns no external resources and does not infer permissions or current server state from a snapshot.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        code = try object.required("code", String.self)
        name = try object.required("name", String.self)
        templateDescription = try object.required("description", Nullable<String>.self)
        usageCount = try object.required("usage_count", Int.self)
        creatorID = try object.required("creator_id", UserID.self)
        creator = try object.messageModel("creator", MessageAuthor.self)
        createdAt = try object.required("created_at", DiscordTimestamp.self)
        updatedAt = try object.required("updated_at", DiscordTimestamp.self)
        sourceGuildID = try object.required("source_guild_id", GuildID.self)
        serializedSourceGuild = try object.messageModel("serialized_source_guild", GuildTemplateSnapshot.self)
        isDirty = try object.required("is_dirty", Nullable<Bool>.self)
        rawFields = object.resource.fields
    }
}

/// A partial serialized guild within a template, preserving placeholder IDs and exact unknown JSON.
/// Optional fields reflect the written partial-guild contract; newer preview-only fields may be omitted.
/// This snapshot cannot be supplied as a live Guild: its IDs are local placeholders and it has no live membership.
public struct GuildTemplateSnapshot: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Wire `name`; optional, nonnull. Omission and explicit null remain distinct.
    public let name: Field<String>
    /// Wire `description`; optional, nullable. Omission and explicit null remain distinct.
    public let snapshotDescription: Field<String>
    /// Wire `region`; optional, nullable. Omission and explicit null remain distinct.
    public let region: Field<String>
    /// Wire `verification_level`; optional, nonnull. Omission and explicit null remain distinct.
    public let verificationLevel: Field<RawValue<GuildVerificationLevel>>
    /// Wire `default_message_notifications`; optional, nonnull. Omission and explicit null remain distinct.
    public let defaultMessageNotifications: Field<RawValue<GuildDefaultMessageNotificationLevel>>
    /// Wire `explicit_content_filter`; optional, nonnull. Omission and explicit null remain distinct.
    public let explicitContentFilter: Field<RawValue<GuildExplicitContentFilterLevel>>
    /// Wire `preferred_locale`; optional, nonnull. Omission and explicit null remain distinct.
    public let preferredLocale: Field<String>
    /// Wire `afk_channel_id`; optional, nullable. Omission and explicit null remain distinct.
    public let afkChannelID: Field<GuildTemplateReference>
    /// Wire `afk_timeout`; optional, nonnull. Omission and explicit null remain distinct.
    public let afkTimeout: Field<Int>
    /// Wire `system_channel_id`; optional, nullable. Omission and explicit null remain distinct.
    public let systemChannelID: Field<GuildTemplateReference>
    /// Wire `system_channel_flags`; optional, nonnull. Omission and explicit null remain distinct.
    public let systemChannelFlags: Field<UInt64>
    /// Wire `roles`; optional, nonnull. Omission and explicit null remain distinct.
    public let roles: Field<[GuildTemplateRole]>
    /// Wire `channels`; optional, nonnull. Omission and explicit null remain distinct.
    public let channels: Field<[GuildTemplateChannel]>
    /// Wire `icon_hash`; optional, nullable. Omission and explicit null remain distinct.
    public let iconHash: Field<String>
    /// Complete original object, including unknown fields and exact numeric spelling; ordinary diagnostics redact it.
    public let rawFields: [String: JSONValue]

    /// Parses an immutable template projection synchronously without I/O or related-resource hydration.
    /// - Parameters:
    ///   - data: Complete UTF-8 object; known fields must match their documented presence and types.
    ///   - limits: Whole-document byte, depth and node bounds, including every unknown subtree; default 1 MiB/64/100,000.
    /// - Throws: JSON syntax/bounds errors or sanitized invalid-response errors for missing, forbidden-null,
    ///   mistyped or overflowing fields. No partial object escapes failure and no external resource is acquired.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects an already bounded subtree while preserving unknown fields and original snapshot identifiers.
    /// - Parameters:
    ///   - value: Original object from a successfully bounded containing document.
    ///   - limits: That document's limits, reused for scalar projection without reparsing nested objects.
    /// - Throws: Sanitized invalid-response errors for incompatible known fields. Work is synchronous,
    ///   owns no external resources and does not infer permissions or current server state from a snapshot.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        name = try object.field("name", String.self)
        snapshotDescription = try object.field("description", String.self, nullable: true)
        region = try object.field("region", String.self, nullable: true)
        verificationLevel = try object.field("verification_level", RawValue<GuildVerificationLevel>.self)
        defaultMessageNotifications = try object.field("default_message_notifications", RawValue<GuildDefaultMessageNotificationLevel>.self)
        explicitContentFilter = try object.field("explicit_content_filter", RawValue<GuildExplicitContentFilterLevel>.self)
        preferredLocale = try object.field("preferred_locale", String.self)
        afkChannelID = try object.field("afk_channel_id", GuildTemplateReference.self, nullable: true)
        afkTimeout = try object.field("afk_timeout", Int.self)
        systemChannelID = try object.field("system_channel_id", GuildTemplateReference.self, nullable: true)
        systemChannelFlags = try object.field("system_channel_flags", UInt64.self)
        roles = try object.messageArray("roles", GuildTemplateRole.self)
        channels = try object.messageArray("channels", GuildTemplateChannel.self)
        iconHash = try object.field("icon_hash", String.self, nullable: true)
        rawFields = object.resource.fields
    }
}

/// A template role using an integer placeholder ID and exact, arbitrary-width permission digits.
/// The written example uses integer permissions; the preview uses strings. Both survive in rawFields.
/// Newer colors, icon and unicode_emoji fields may be absent from the written partial snapshot.
public struct GuildTemplateRole: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Wire `id`; required, nonnull. Omission and explicit null remain distinct.
    public let id: Int
    /// Wire `name`; required, nonnull. Omission and explicit null remain distinct.
    public let name: String
    /// Wire `permissions`; required, nonnull. Omission and explicit null remain distinct.
    public let permissions: String
    /// Wire `color`; required, nonnull. Omission and explicit null remain distinct.
    public let color: Int
    /// Wire `colors`; optional, nullable. Omission and explicit null remain distinct.
    public let colors: Field<GuildRoleColors>
    /// Wire `hoist`; required, nonnull. Omission and explicit null remain distinct.
    public let hoist: Bool
    /// Wire `mentionable`; required, nonnull. Omission and explicit null remain distinct.
    public let mentionable: Bool
    /// Wire `icon`; optional, nullable. Omission and explicit null remain distinct.
    public let icon: Field<String>
    /// Wire `unicode_emoji`; optional, nullable. Omission and explicit null remain distinct.
    public let unicodeEmoji: Field<String>
    /// Complete original object, including unknown fields and exact numeric spelling; ordinary diagnostics redact it.
    public let rawFields: [String: JSONValue]

    /// Parses an immutable template projection synchronously without I/O or related-resource hydration.
    /// - Parameters:
    ///   - data: Complete UTF-8 object; known fields must match their documented presence and types.
    ///   - limits: Whole-document byte, depth and node bounds, including every unknown subtree; default 1 MiB/64/100,000.
    /// - Throws: JSON syntax/bounds errors or sanitized invalid-response errors for missing, forbidden-null,
    ///   mistyped or overflowing fields. No partial object escapes failure and no external resource is acquired.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects an already bounded subtree while preserving unknown fields and original snapshot identifiers.
    /// - Parameters:
    ///   - value: Original object from a successfully bounded containing document.
    ///   - limits: That document's limits, reused for scalar projection without reparsing nested objects.
    /// - Throws: Sanitized invalid-response errors for incompatible known fields. Work is synchronous,
    ///   owns no external resources and does not infer permissions or current server state from a snapshot.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        id = try object.required("id", Int.self)
        name = try object.required("name", String.self)
        permissions = try templatePermissionDigits(object, name: "permissions")
        color = try object.required("color", Int.self)
        colors = try object.messageField("colors", GuildRoleColors.self, nullable: true)
        hoist = try object.required("hoist", Bool.self)
        mentionable = try object.required("mentionable", Bool.self)
        icon = try object.field("icon", String.self, nullable: true)
        unicodeEmoji = try object.field("unicode_emoji", String.self, nullable: true)
        rawFields = object.resource.fields
    }
}

/// A partial template channel with integer placeholder ID and type, including preview forum settings.
/// Written examples omit newer fields, so these remain optional. References accept documented integer
/// placeholders and preview decimal-string snowflakes without conflating their original representation.
public struct GuildTemplateChannel: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Wire `id`; required, nullable. Omission and explicit null remain distinct.
    public let id: Nullable<Int>
    /// Wire `type`; required, nonnull. Omission and explicit null remain distinct.
    public let type: RawValue<ChannelType>
    /// Wire `name`; optional, nullable. Omission and explicit null remain distinct.
    public let name: Field<String>
    /// Wire `position`; optional, nullable. Omission and explicit null remain distinct.
    public let position: Field<Int>
    /// Wire `topic`; optional, nullable. Omission and explicit null remain distinct.
    public let topic: Field<String>
    /// Wire `bitrate`; optional, nonnull. Omission and explicit null remain distinct.
    public let bitrate: Field<Int>
    /// Wire `user_limit`; optional, nonnull. Omission and explicit null remain distinct.
    public let userLimit: Field<Int>
    /// Wire `nsfw`; optional, nonnull. Omission and explicit null remain distinct.
    public let nsfw: Field<Bool>
    /// Wire `rate_limit_per_user`; optional, nonnull. Omission and explicit null remain distinct.
    public let rateLimitPerUser: Field<Int>
    /// Wire `parent_id`; optional, nullable. Omission and explicit null remain distinct.
    public let parentID: Field<GuildTemplateReference>
    /// Wire `default_auto_archive_duration`; optional, nullable. Omission and explicit null remain distinct.
    public let defaultAutoArchiveDuration: Field<Int>
    /// Wire `permission_overwrites`; optional, nonnull. Omission and explicit null remain distinct.
    public let permissionOverwrites: Field<[GuildTemplateOverwrite]>
    /// Wire `available_tags`; optional, nullable. Omission and explicit null remain distinct.
    public let availableTags: Field<[GuildTemplateTag]>
    /// Wire `template`; optional, nonnull. Omission and explicit null remain distinct.
    public let template: Field<String>
    /// Wire `default_reaction_emoji`; optional, nullable. Omission and explicit null remain distinct.
    public let defaultReactionEmoji: Field<DefaultReaction>
    /// Wire `default_thread_rate_limit_per_user`; optional, nullable. Omission and explicit null remain distinct.
    public let defaultThreadRateLimitPerUser: Field<Int>
    /// Wire `default_sort_order`; optional, nullable. Omission and explicit null remain distinct.
    public let defaultSortOrder: Field<RawValue<ChannelSortOrder>>
    /// Wire `default_forum_layout`; optional, nullable. Omission and explicit null remain distinct.
    public let defaultForumLayout: Field<RawValue<ChannelForumLayout>>
    /// Wire `default_tag_setting`; optional, nullable. Omission and explicit null remain distinct.
    public let defaultTagSetting: Field<String>
    /// Wire `theme_color`; optional, nullable. Omission and explicit null remain distinct.
    public let themeColor: Field<Int>
    /// Complete original object, including unknown fields and exact numeric spelling; ordinary diagnostics redact it.
    public let rawFields: [String: JSONValue]

    /// Parses an immutable template projection synchronously without I/O or related-resource hydration.
    /// - Parameters:
    ///   - data: Complete UTF-8 object; known fields must match their documented presence and types.
    ///   - limits: Whole-document byte, depth and node bounds, including every unknown subtree; default 1 MiB/64/100,000.
    /// - Throws: JSON syntax/bounds errors or sanitized invalid-response errors for missing, forbidden-null,
    ///   mistyped or overflowing fields. No partial object escapes failure and no external resource is acquired.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects an already bounded subtree while preserving unknown fields and original snapshot identifiers.
    /// - Parameters:
    ///   - value: Original object from a successfully bounded containing document.
    ///   - limits: That document's limits, reused for scalar projection without reparsing nested objects.
    /// - Throws: Sanitized invalid-response errors for incompatible known fields. Work is synchronous,
    ///   owns no external resources and does not infer permissions or current server state from a snapshot.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        id = try object.required("id", Nullable<Int>.self)
        type = try object.required("type", RawValue<ChannelType>.self)
        name = try object.field("name", String.self, nullable: true)
        position = try object.field("position", Int.self, nullable: true)
        topic = try object.field("topic", String.self, nullable: true)
        bitrate = try object.field("bitrate", Int.self)
        userLimit = try object.field("user_limit", Int.self)
        nsfw = try object.field("nsfw", Bool.self)
        rateLimitPerUser = try object.field("rate_limit_per_user", Int.self)
        parentID = try object.field("parent_id", GuildTemplateReference.self, nullable: true)
        defaultAutoArchiveDuration = try object.field("default_auto_archive_duration", Int.self, nullable: true)
        permissionOverwrites = try object.messageArray("permission_overwrites", GuildTemplateOverwrite.self)
        availableTags = try object.nested("available_tags", nullable: true) { value in
            guard case .array(let values) = value else { throw DiscordError.transport(.invalidResponse) }
            return try values.map { try GuildTemplateTag(value: $0, limits: limits) }
        }
        template = try object.field("template", String.self)
        defaultReactionEmoji = try object.messageField("default_reaction_emoji", DefaultReaction.self, nullable: true)
        defaultThreadRateLimitPerUser = try object.field("default_thread_rate_limit_per_user", Int.self, nullable: true)
        defaultSortOrder = try object.field("default_sort_order", RawValue<ChannelSortOrder>.self, nullable: true)
        defaultForumLayout = try object.field("default_forum_layout", RawValue<ChannelForumLayout>.self, nullable: true)
        defaultTagSetting = try object.field("default_tag_setting", String.self, nullable: true)
        themeColor = try object.field("theme_color", Int.self, nullable: true)
        rawFields = object.resource.fields
    }
}

/// A template permission overwrite retaining integer-placeholder or string references and exact bits.
/// Permission strings have no native integer-width limit; unknown overwrite types remain readable.
public struct GuildTemplateOverwrite: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Wire `id`; required, nonnull. Omission and explicit null remain distinct.
    public let id: GuildTemplateReference
    /// Wire `type`; required, nonnull. Omission and explicit null remain distinct.
    public let type: RawValue<ChannelOverwriteType>
    /// Wire `allow`; required, nonnull. Omission and explicit null remain distinct.
    public let allow: String
    /// Wire `deny`; required, nonnull. Omission and explicit null remain distinct.
    public let deny: String
    /// Complete original object, including unknown fields and exact numeric spelling; ordinary diagnostics redact it.
    public let rawFields: [String: JSONValue]

    /// Parses an immutable template projection synchronously without I/O or related-resource hydration.
    /// - Parameters:
    ///   - data: Complete UTF-8 object; known fields must match their documented presence and types.
    ///   - limits: Whole-document byte, depth and node bounds, including every unknown subtree; default 1 MiB/64/100,000.
    /// - Throws: JSON syntax/bounds errors or sanitized invalid-response errors for missing, forbidden-null,
    ///   mistyped or overflowing fields. No partial object escapes failure and no external resource is acquired.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects an already bounded subtree while preserving unknown fields and original snapshot identifiers.
    /// - Parameters:
    ///   - value: Original object from a successfully bounded containing document.
    ///   - limits: That document's limits, reused for scalar projection without reparsing nested objects.
    /// - Throws: Sanitized invalid-response errors for incompatible known fields. Work is synchronous,
    ///   owns no external resources and does not infer permissions or current server state from a snapshot.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        id = try object.required("id", GuildTemplateReference.self)
        type = try object.required("type", RawValue<ChannelOverwriteType>.self)
        allow = try templatePermissionDigits(object, name: "allow")
        deny = try templatePermissionDigits(object, name: "deny")
        rawFields = object.resource.fields
    }
}

/// A preview forum tag within a template; its nullable integer ID is a placeholder rather than a snowflake.
public struct GuildTemplateTag: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Wire `id`; required, nullable. Omission and explicit null remain distinct.
    public let id: Nullable<Int>
    /// Wire `name`; required, nonnull. Omission and explicit null remain distinct.
    public let name: String
    /// Wire `emoji_id`; required, nullable. Omission and explicit null remain distinct.
    public let emojiID: Nullable<EmojiID>
    /// Wire `emoji_name`; required, nullable. Omission and explicit null remain distinct.
    public let emojiName: Nullable<String>
    /// Wire `moderated`; required, nullable. Omission and explicit null remain distinct.
    public let moderated: Nullable<Bool>
    /// Complete original object, including unknown fields and exact numeric spelling; ordinary diagnostics redact it.
    public let rawFields: [String: JSONValue]

    /// Parses an immutable template projection synchronously without I/O or related-resource hydration.
    /// - Parameters:
    ///   - data: Complete UTF-8 object; known fields must match their documented presence and types.
    ///   - limits: Whole-document byte, depth and node bounds, including every unknown subtree; default 1 MiB/64/100,000.
    /// - Throws: JSON syntax/bounds errors or sanitized invalid-response errors for missing, forbidden-null,
    ///   mistyped or overflowing fields. No partial object escapes failure and no external resource is acquired.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects an already bounded subtree while preserving unknown fields and original snapshot identifiers.
    /// - Parameters:
    ///   - value: Original object from a successfully bounded containing document.
    ///   - limits: That document's limits, reused for scalar projection without reparsing nested objects.
    /// - Throws: Sanitized invalid-response errors for incompatible known fields. Work is synchronous,
    ///   owns no external resources and does not infer permissions or current server state from a snapshot.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        id = try object.required("id", Nullable<Int>.self)
        name = try object.required("name", String.self)
        emojiID = try object.required("emoji_id", Nullable<EmojiID>.self)
        emojiName = try object.required("emoji_name", Nullable<String>.self)
        moderated = try object.required("moderated", Nullable<Bool>.self)
        rawFields = object.resource.fields
    }
}

/// A serialized-template channel or overwrite reference with its original wire representation.
/// Integer placeholders are local to a snapshot. Decimal-string references are accepted for the
/// official preview's alternative form; neither representation authorizes live resource operations.
public enum GuildTemplateReference: Decodable, Sendable, Equatable {
    /// An integer placeholder, including negative values, zero and every native Int boundary.
    case placeholder(Int)
    /// A canonical unsigned decimal snowflake string, validated without numeric rounding.
    case snowflake(String)

    /// Decodes one integral placeholder or canonical decimal-string reference without I/O.
    /// - Parameter decoder: A decoder positioned at a nonnull reference; containing objects preserve null separately.
    /// - Throws: Sanitized invalid-response errors for fractional, malformed, overflowing or nonnumeric values.
    ///   The containing exact-JSON projection rejects fractional/exponent integer tokens before decoding.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) {
            guard let id = ChannelID(value), id.description == value else { throw DiscordError.transport(.invalidResponse) }
            self = .snowflake(value)
        } else {
            self = .placeholder(try container.decode(Int.self))
        }
    }
}

/// Reads arbitrary-width nonnegative permission digits from the written integer or preview string form.
/// - Parameters:
///   - object: Bounded containing snapshot; unknown fields and original numeric tokens remain untouched.
///   - name: Required field key, such as permissions, allow or deny.
/// - Returns: Exact decimal digits without narrowing to a native bitset or computing effective permissions.
/// - Throws: Sanitized invalid-response errors for missing, negative, fractional, exponent or nondigit values.
///   Parsing is synchronous, has no external side effects and is bounded by the containing document.
private func templatePermissionDigits(_ object: PayloadObject, name: String) throws -> String {
    let digits: String
    switch object.resource.fields[name] {
    case .string(let value): digits = value
    case .number(let value): digits = value.rawValue
    default: throw DiscordError.transport(.invalidResponse)
    }
    guard !digits.isEmpty, digits.utf8.allSatisfy({ (48...57).contains($0) }) else {
        throw DiscordError.transport(.invalidResponse)
    }
    return digits
}
