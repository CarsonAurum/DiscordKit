// File: Sources/DiscordModels/Soundboard.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import Foundation

/// Marker distinguishing soundboard sound identifiers from other Discord snowflakes.
public enum SoundboardSoundTag: Sendable {}
/// Exact unsigned identifier, including small IDs used by Discord's default sounds.
public typealias SoundboardSoundID = Snowflake<SoundboardSoundTag>

/// Complete API v10 default/guild sound snapshot, verified 2026-10-16 against
/// https://docs.discord.com/developers/resources/soundboard. Availability, Nitro/external use and
/// voice-state permissions remain server-state checks; parsing never downloads or plays sound.
public struct SoundboardSound: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Required name, retained exactly without request-only text limits.
    public let name: String
    /// Required sound snowflake; default sounds can use small IDs such as 1.
    public let soundID: SoundboardSoundID
    /// Required finite volume; exact numeric spelling remains raw and response values are not mutation-clamped.
    public let volume: Double
    /// Required nullable custom emoji ID.
    public let emojiID: Nullable<EmojiID>
    /// Required nullable Unicode emoji; null remains distinct from an empty string.
    public let emojiName: Nullable<String>
    /// Optional owner, ordinarily absent on default sounds.
    public let guildID: Field<GuildID>
    /// Required current availability, including false after lost Server Boosts.
    public let available: Bool
    /// Optional creator using the existing user projection with unknown fields preserved.
    public let user: Field<MessageAuthor>
    /// Complete original object with exact numeric lexemes and future fields.
    public let rawFields: [String: JSONValue]

    /// Parses a bounded immutable sound without I/O, voice connection or permission lookups.
    /// - Parameters:
    ///   - data: Complete UTF-8 sound object, including required nullable emoji selectors.
    ///   - limits: Whole-document bounds including unknown fields; defaults to 1 MiB/64 depth/100,000 nodes.
    /// - Throws: JSON syntax/bounds errors or sanitized invalid-response errors for malformed fields,
    ///   invalid IDs, missing values, forbidden nulls or a nonnumeric/nonfinite volume.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects one already bounded sound subtree with floating-point numeric support.
    /// - Parameters:
    ///   - value: Original object subtree from a complete bounded parse.
    ///   - limits: Containing document bounds reused for scalar decoding.
    /// - Throws: Sanitized invalid-response errors for incompatible fields or malformed nested users.
    ///   Work is synchronous and side-effect free; no resources, tasks or cancellation suspension are introduced.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        name = try object.required("name", String.self)
        soundID = try object.required("sound_id", SoundboardSoundID.self)
        guard case .value(let decodedVolume) = try object.messageNumber("volume")
        else { throw DiscordError.transport(.invalidResponse) }
        volume = decodedVolume
        emojiID = try object.required("emoji_id", Nullable<EmojiID>.self)
        emojiName = try object.required("emoji_name", Nullable<String>.self)
        guildID = try object.field("guild_id", GuildID.self)
        available = try object.required("available", Bool.self)
        user = try object.messageField("user", MessageAuthor.self)
        rawFields = object.resource.fields
    }
}

/// API v10 guild soundboard collection under its documented `items` envelope.
public struct GuildSoundboardSoundList: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Complete ordered sound list; empty collections remain empty.
    public let items: [SoundboardSound]
    /// Complete original envelope, preserving unknown collection metadata.
    public let rawFields: [String: JSONValue]

    /// Parses a bounded collection without media fetching, pagination, I/O or suspension.
    /// - Parameters:
    ///   - data: Complete UTF-8 envelope with required nonnull `items` array.
    ///   - limits: Whole-tree bounds shared by every sound and unknown nested field.
    /// - Throws: JSON syntax/bounds errors or sanitized invalid-response errors for missing/mistyped
    ///   arrays or malformed elements. A failed initializer exposes no partially projected list.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects an already bounded collection while preserving order and unknown subtrees.
    /// - Parameters:
    ///   - value: Original envelope object from a complete bounded root.
    ///   - limits: Root bounds reused for exact scalar validation within sound objects.
    /// - Throws: Sanitized invalid-response errors for incompatible envelope or nested sound fields.
    ///   Work is synchronous and side-effect free with no resources or cancellation suspension.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        items = try object.messageModels("items", SoundboardSound.self)
        rawFields = object.resource.fields
    }
}
