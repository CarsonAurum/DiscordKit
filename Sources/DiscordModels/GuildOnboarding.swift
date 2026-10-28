// File: Sources/DiscordModels/GuildOnboarding.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import Foundation

/// The guild welcome screen and its channels in display order. Up to five channels are documented for mutations; decoding does not authorize URLs, grant access or impose request-only limits.
/// API v10; verified 2026-10-16 against https://docs.discord.com/developers/resources/guild,
/// the Permissions/Voice references and https://github.com/discord/discord-api-spec/blob/main/specs/openapi.json.
public struct GuildWelcomeScreen: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Wire `description` value; required but explicitly nullable.
    public let welcomeDescription: Nullable<String>
    /// Wire `welcome_channels` value; required and nonnull.
    public let welcomeChannels: [GuildWelcomeChannel]
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
        welcomeDescription = try object.required("description", Nullable<String>.self)
        welcomeChannels = try object.messageModels("welcome_channels", GuildWelcomeChannel.self)
        rawFields = object.resource.fields
    }
}

/// One welcome screen channel and its nullable custom/Unicode emoji display metadata.
/// API v10; verified 2026-10-16 against https://docs.discord.com/developers/resources/guild,
/// the Permissions/Voice references and https://github.com/discord/discord-api-spec/blob/main/specs/openapi.json.
public struct GuildWelcomeChannel: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Wire `channel_id` value; required and nonnull.
    public let channelID: ChannelID
    /// Wire `description` value; required and nonnull.
    public let channelDescription: String
    /// Wire `emoji_id` value; required but explicitly nullable.
    public let emojiID: Nullable<EmojiID>
    /// Wire `emoji_name` value; required but explicitly nullable.
    public let emojiName: Nullable<String>
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
        channelID = try object.required("channel_id", ChannelID.self)
        channelDescription = try object.required("description", String.self)
        emojiID = try object.required("emoji_id", Nullable<EmojiID>.self)
        emojiName = try object.required("emoji_name", Nullable<String>.self)
        rawFields = object.resource.fields
    }
}

/// The complete documented guild onboarding configuration, with original prompt order and future mode values preserved. Enabling constraints and permission checks belong to the mutation and Discord server, not this snapshot.
/// API v10; verified 2026-10-16 against https://docs.discord.com/developers/resources/guild,
/// the Permissions/Voice references and https://github.com/discord/discord-api-spec/blob/main/specs/openapi.json.
public struct GuildOnboarding: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Wire `guild_id` value; required and nonnull.
    public let guildID: GuildID
    /// Wire `prompts` value; required and nonnull.
    public let prompts: [GuildOnboardingPrompt]
    /// Wire `default_channel_ids` value; required and nonnull.
    public let defaultChannelIDs: [ChannelID]
    /// Wire `enabled` value; required and nonnull.
    public let enabled: Bool
    /// Wire `mode` value; required and nonnull.
    public let mode: RawValue<GuildOnboardingMode>
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
        guildID = try object.required("guild_id", GuildID.self)
        prompts = try object.messageModels("prompts", GuildOnboardingPrompt.self)
        defaultChannelIDs = try object.required("default_channel_ids", [ChannelID].self)
        enabled = try object.required("enabled", Bool.self)
        mode = try object.required("mode", RawValue<GuildOnboardingMode>.self)
        rawFields = object.resource.fields
    }
}

/// One guild onboarding prompt. Unknown prompt types survive; required and inOnboarding describe server configuration rather than proof a member completed screening.
/// API v10; verified 2026-10-16 against https://docs.discord.com/developers/resources/guild,
/// the Permissions/Voice references and https://github.com/discord/discord-api-spec/blob/main/specs/openapi.json.
public struct GuildOnboardingPrompt: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Wire `id` value; required and nonnull.
    public let id: GuildOnboardingPromptID
    /// Wire `type` value; required and nonnull.
    public let type: RawValue<GuildOnboardingPromptType>
    /// Wire `options` value; required and nonnull.
    public let options: [GuildOnboardingOption]
    /// Wire `title` value; required and nonnull.
    public let title: String
    /// Wire `single_select` value; required and nonnull.
    public let singleSelect: Bool
    /// Wire `required` value; required and nonnull.
    public let required: Bool
    /// Wire `in_onboarding` value; required and nonnull.
    public let inOnboarding: Bool
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
        id = try object.required("id", GuildOnboardingPromptID.self)
        type = try object.required("type", RawValue<GuildOnboardingPromptType>.self)
        options = try object.messageModels("options", GuildOnboardingOption.self)
        title = try object.required("title", String.self)
        singleSelect = try object.required("single_select", Bool.self)
        required = try object.required("required", Bool.self)
        inOnboarding = try object.required("in_onboarding", Bool.self)
        rawFields = object.resource.fields
    }
}

/// A prompt option with assigned channel/role IDs and emoji representation. Responses use emoji; mutation echoes may expose separate emoji fields. The related Emoji remains explicitly partial.
/// API v10; verified 2026-10-16 against https://docs.discord.com/developers/resources/guild,
/// the Permissions/Voice references and https://github.com/discord/discord-api-spec/blob/main/specs/openapi.json.
public struct GuildOnboardingOption: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Wire `id` value; required and nonnull.
    public let id: GuildOnboardingOptionID
    /// Wire `channel_ids` value; required and nonnull.
    public let channelIDs: [ChannelID]
    /// Wire `role_ids` value; required and nonnull.
    public let roleIDs: [RoleID]
    /// Wire `emoji` value; optional and nonnull when present.
    public let emoji: Field<PartialEmoji>
    /// Wire `emoji_id` value; optional and nonnull when present.
    public let emojiID: Field<EmojiID>
    /// Wire `emoji_name` value; optional and nonnull when present.
    public let emojiName: Field<String>
    /// Wire `emoji_animated` value; optional and nonnull when present.
    public let emojiAnimated: Field<Bool>
    /// Wire `title` value; required and nonnull.
    public let title: String
    /// Wire `description` value; required but explicitly nullable.
    public let optionDescription: Nullable<String>
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
        id = try object.required("id", GuildOnboardingOptionID.self)
        channelIDs = try object.required("channel_ids", [ChannelID].self)
        roleIDs = try object.required("role_ids", [RoleID].self)
        emoji = try object.messageField("emoji", PartialEmoji.self)
        emojiID = try object.field("emoji_id", EmojiID.self)
        emojiName = try object.field("emoji_name", String.self)
        emojiAnimated = try object.field("emoji_animated", Bool.self)
        title = try object.required("title", String.self)
        optionDescription = try object.required("description", Nullable<String>.self)
        rawFields = object.resource.fields
    }
}
