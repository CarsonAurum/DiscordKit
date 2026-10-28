// File: Sources/DiscordModels/Guild.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import Foundation

/// A complete REST Guild snapshot with exact optional presence, nullable values and future fields. Discovery splash is conditional on DISCOVERABLE; Gateway-only fields remain raw and unavailable guilds use GuildUnavailable. Related users, emoji and stickers are explicit partial projections. Decoding is not a permission, membership, entitlement or capacity check.
/// API v10; verified 2026-10-16 against https://docs.discord.com/developers/resources/guild,
/// the Permissions/Voice references and https://github.com/discord/discord-api-spec/blob/main/specs/openapi.json.
public struct Guild: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Wire `id` value; required and nonnull.
    public let id: GuildID
    /// Wire `name` value; required and nonnull.
    public let name: String
    /// Wire `icon` value; required but explicitly nullable.
    public let icon: Nullable<String>
    /// Wire `icon_hash` value; omission remains distinct from explicit null.
    public let iconHash: Field<String>
    /// Wire `splash` value; required but explicitly nullable.
    public let splash: Nullable<String>
    /// Wire `discovery_splash` value; omission remains distinct from explicit null.
    public let discoverySplash: Field<String>
    /// Wire `owner` value; optional and nonnull when present.
    public let owner: Field<Bool>
    /// Wire `owner_id` value; required and nonnull.
    public let ownerID: UserID
    /// Invoking user permission bits excluding overwrites/implicit permissions; arbitrary-width decimal text remains exact.
    public let permissions: Field<String>
    /// Deprecated guild voice region; new voice configuration uses Channel.rtcRegion.
    public let region: Field<String>
    /// Wire `afk_channel_id` value; required but explicitly nullable.
    public let afkChannelID: Nullable<ChannelID>
    /// AFK timeout in seconds; response values are retained without enforcing mutation limits.
    public let afkTimeout: Int
    /// Wire `widget_enabled` value; optional and nonnull when present.
    public let widgetEnabled: Field<Bool>
    /// Wire `widget_channel_id` value; omission remains distinct from explicit null.
    public let widgetChannelID: Field<ChannelID>
    /// Wire `verification_level` value; required and nonnull.
    public let verificationLevel: RawValue<GuildVerificationLevel>
    /// Wire `default_message_notifications` value; required and nonnull.
    public let defaultMessageNotifications: RawValue<GuildDefaultMessageNotificationLevel>
    /// Wire `explicit_content_filter` value; required and nonnull.
    public let explicitContentFilter: RawValue<GuildExplicitContentFilterLevel>
    /// Wire `roles` value; required and nonnull.
    public let roles: [GuildRole]
    /// Related emoji partial projections; unmodeled Emoji resource fields remain exact.
    public let emojis: [PartialEmoji]
    /// Wire `features` value; required and nonnull.
    public let features: [RawValue<GuildFeature>]
    /// Wire `mfa_level` value; required and nonnull.
    public let mfaLevel: RawValue<GuildMFALevel>
    /// Wire `application_id` value; required but explicitly nullable.
    public let applicationID: Nullable<ApplicationID>
    /// Wire `system_channel_id` value; required but explicitly nullable.
    public let systemChannelID: Nullable<ChannelID>
    /// Exact system channel response bits, including future flags; see GuildSystemChannelFlags.
    public let systemChannelFlags: UInt64
    /// Wire `rules_channel_id` value; required but explicitly nullable.
    public let rulesChannelID: Nullable<ChannelID>
    /// Wire `max_presences` value; omission remains distinct from explicit null.
    public let maxPresences: Field<Int>
    /// Wire `max_members` value; optional and nonnull when present.
    public let maxMembers: Field<Int>
    /// Wire `vanity_url_code` value; required but explicitly nullable.
    public let vanityURLCode: Nullable<String>
    /// Wire `description` value; required but explicitly nullable.
    public let guildDescription: Nullable<String>
    /// Wire `banner` value; required but explicitly nullable.
    public let banner: Nullable<String>
    /// Wire `premium_tier` value; required and nonnull.
    public let premiumTier: RawValue<GuildPremiumTier>
    /// Wire `premium_subscription_count` value; optional and nonnull when present.
    public let premiumSubscriptionCount: Field<Int>
    /// Wire `preferred_locale` value; required and nonnull.
    public let preferredLocale: String
    /// Wire `public_updates_channel_id` value; required but explicitly nullable.
    public let publicUpdatesChannelID: Nullable<ChannelID>
    /// Wire `max_video_channel_users` value; optional and nonnull when present.
    public let maxVideoChannelUsers: Field<Int>
    /// Wire `max_stage_video_channel_users` value; optional and nonnull when present.
    public let maxStageVideoChannelUsers: Field<Int>
    /// Wire `approximate_member_count` value; optional and nonnull when present.
    public let approximateMemberCount: Field<Int>
    /// Wire `approximate_presence_count` value; optional and nonnull when present.
    public let approximatePresenceCount: Field<Int>
    /// Wire `welcome_screen` value; optional and nonnull when present.
    public let welcomeScreen: Field<GuildWelcomeScreen>
    /// Wire `nsfw_level` value; required and nonnull.
    public let nsfwLevel: RawValue<GuildNSFWLevel>
    /// Related Sticker partial projections; complete Sticker support belongs to its resource batch.
    public let stickers: Field<[MessageRelatedResource]>
    /// Wire `premium_progress_bar_enabled` value; required and nonnull.
    public let premiumProgressBarEnabled: Bool
    /// Wire `safety_alerts_channel_id` value; required but explicitly nullable.
    public let safetyAlertsChannelID: Nullable<ChannelID>
    /// Wire `incidents_data` value; required but explicitly nullable.
    public let incidentsData: Nullable<GuildIncidentsData>
    /// OpenAPI-only home header asset hash; omission and explicit null remain distinct for compatibility with the written Guild table.
    public let homeHeader: Field<String>
    /// Legacy age-restriction response flag retained alongside nsfwLevel; OpenAPI-only optional compatibility projection.
    public let nsfw: Field<Bool>
    /// OpenAPI-only timestamp of the progress-bar user update; absent/null remain distinct.
    public let premiumProgressBarEnabledUserUpdatedAt: Field<DiscordTimestamp>
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
        icon = try object.required("icon", Nullable<String>.self)
        iconHash = try object.field("icon_hash", String.self, nullable: true)
        splash = try object.required("splash", Nullable<String>.self)
        discoverySplash = try object.field("discovery_splash", String.self, nullable: true)
        owner = try object.field("owner", Bool.self)
        ownerID = try object.required("owner_id", UserID.self)
        permissions = try object.field("permissions", String.self)
        region = try object.field("region", String.self, nullable: true)
        afkChannelID = try object.required("afk_channel_id", Nullable<ChannelID>.self)
        afkTimeout = try object.required("afk_timeout", Int.self)
        widgetEnabled = try object.field("widget_enabled", Bool.self)
        widgetChannelID = try object.field("widget_channel_id", ChannelID.self, nullable: true)
        verificationLevel = try object.required("verification_level", RawValue<GuildVerificationLevel>.self)
        defaultMessageNotifications = try object.required("default_message_notifications", RawValue<GuildDefaultMessageNotificationLevel>.self)
        explicitContentFilter = try object.required("explicit_content_filter", RawValue<GuildExplicitContentFilterLevel>.self)
        roles = try object.messageModels("roles", GuildRole.self)
        emojis = try object.messageModels("emojis", PartialEmoji.self)
        features = try object.required("features", [RawValue<GuildFeature>].self)
        mfaLevel = try object.required("mfa_level", RawValue<GuildMFALevel>.self)
        applicationID = try object.required("application_id", Nullable<ApplicationID>.self)
        systemChannelID = try object.required("system_channel_id", Nullable<ChannelID>.self)
        systemChannelFlags = try object.required("system_channel_flags", UInt64.self)
        rulesChannelID = try object.required("rules_channel_id", Nullable<ChannelID>.self)
        maxPresences = try object.field("max_presences", Int.self, nullable: true)
        maxMembers = try object.field("max_members", Int.self)
        vanityURLCode = try object.required("vanity_url_code", Nullable<String>.self)
        guildDescription = try object.required("description", Nullable<String>.self)
        banner = try object.required("banner", Nullable<String>.self)
        premiumTier = try object.required("premium_tier", RawValue<GuildPremiumTier>.self)
        premiumSubscriptionCount = try object.field("premium_subscription_count", Int.self)
        preferredLocale = try object.required("preferred_locale", String.self)
        publicUpdatesChannelID = try object.required("public_updates_channel_id", Nullable<ChannelID>.self)
        maxVideoChannelUsers = try object.field("max_video_channel_users", Int.self)
        maxStageVideoChannelUsers = try object.field("max_stage_video_channel_users", Int.self)
        approximateMemberCount = try object.field("approximate_member_count", Int.self)
        approximatePresenceCount = try object.field("approximate_presence_count", Int.self)
        welcomeScreen = try object.messageField("welcome_screen", GuildWelcomeScreen.self)
        nsfwLevel = try object.required("nsfw_level", RawValue<GuildNSFWLevel>.self)
        stickers = try object.messageArray("stickers", MessageRelatedResource.self)
        premiumProgressBarEnabled = try object.required("premium_progress_bar_enabled", Bool.self)
        safetyAlertsChannelID = try object.required("safety_alerts_channel_id", Nullable<ChannelID>.self)
        switch try object.messageField("incidents_data", GuildIncidentsData.self, nullable: true) {
        case .absent: throw DiscordError.transport(.invalidResponse)
        case .null: incidentsData = .null
        case .value(let model): incidentsData = .value(model)
        }
        homeHeader = try object.field("home_header", String.self, nullable: true)
        nsfw = try object.field("nsfw", Bool.self)
        premiumProgressBarEnabledUserUpdatedAt = try object.field("premium_progress_bar_enabled_user_updated_at", DiscordTimestamp.self, nullable: true)
        if case .value(let bits) = permissions { try validateChannelPermissionBits(bits) }
        rawFields = object.resource.fields
    }
}

/// A Gateway unavailable guild marker, deliberately separate from the complete REST Guild shape. True denotes offline or not yet supplied guild information.
/// API v10; verified 2026-10-16 against https://docs.discord.com/developers/resources/guild,
/// the Permissions/Voice references and https://github.com/discord/discord-api-spec/blob/main/specs/openapi.json.
public struct GuildUnavailable: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Wire `id` value; required and nonnull.
    public let id: GuildID
    /// Wire `unavailable` value; required and nonnull.
    public let unavailable: Bool
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
        unavailable = try object.required("unavailable", Bool.self)
        rawFields = object.resource.fields
    }
}

/// A discoverable guild preview; approximate counts do not establish authorization, current presence or complete member inventory.
/// API v10; verified 2026-10-16 against https://docs.discord.com/developers/resources/guild,
/// the Permissions/Voice references and https://github.com/discord/discord-api-spec/blob/main/specs/openapi.json.
public struct GuildPreview: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Wire `id` value; required and nonnull.
    public let id: GuildID
    /// Wire `name` value; required and nonnull.
    public let name: String
    /// Wire `icon` value; required but explicitly nullable.
    public let icon: Nullable<String>
    /// Wire `splash` value; required but explicitly nullable.
    public let splash: Nullable<String>
    /// Wire `discovery_splash` value; required but explicitly nullable.
    public let discoverySplash: Nullable<String>
    /// Wire `emojis` value; required and nonnull.
    public let emojis: [PartialEmoji]
    /// Wire `features` value; required and nonnull.
    public let features: [RawValue<GuildFeature>]
    /// Wire `approximate_member_count` value; required and nonnull.
    public let approximateMemberCount: Int
    /// Wire `approximate_presence_count` value; required and nonnull.
    public let approximatePresenceCount: Int
    /// Wire `description` value; required but explicitly nullable.
    public let guildDescription: Nullable<String>
    /// Wire `stickers` value; required and nonnull.
    public let stickers: [MessageRelatedResource]
    /// OpenAPI-only home header asset hash; omission and explicit null remain distinct for compatibility with the written Guild table.
    public let homeHeader: Field<String>
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
        icon = try object.required("icon", Nullable<String>.self)
        splash = try object.required("splash", Nullable<String>.self)
        discoverySplash = try object.required("discovery_splash", Nullable<String>.self)
        emojis = try object.messageModels("emojis", PartialEmoji.self)
        features = try object.required("features", [RawValue<GuildFeature>].self)
        approximateMemberCount = try object.required("approximate_member_count", Int.self)
        approximatePresenceCount = try object.required("approximate_presence_count", Int.self)
        guildDescription = try object.required("description", Nullable<String>.self)
        stickers = try object.messageModels("stickers", MessageRelatedResource.self)
        homeHeader = try object.field("home_header", String.self, nullable: true)
        rawFields = object.resource.fields
    }
}
