// File: Sources/DiscordModels/Emoji.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import Foundation

/// An API v10 guild, application, Unicode or reaction emoji, verified 2026-10-16 against
/// https://docs.discord.com/developers/resources/emoji. Deleted custom emoji retain their ID
/// and null name; Unicode emoji have a null ID. Optional flags are never inferred from omission.
/// Subscription role eligibility, the separate premium limit of 25 and the prohibition on
/// converting normal/premium emoji require current guild state and remain Discord checks.
public struct Emoji: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Required nullable custom emoji ID; Unicode emoji use explicit null.
    public let id: Nullable<EmojiID>
    /// Required nullable name; unavailable/deleted reaction emoji can have an explicit null name.
    public let name: Nullable<String>
    /// Optional allowed role IDs, retaining server order and preserving omission versus an empty array.
    public let roles: Field<[RoleID]>
    /// Optional creator using the existing presence-aware user projection; unmodeled fields remain raw.
    public let user: Field<MessageAuthor>
    /// Optional requirement to surround the emoji name with colons.
    public let requireColons: Field<Bool>
    /// Optional integration-managed status.
    public let managed: Field<Bool>
    /// Optional animation flag; omitted does not imply static content.
    public let animated: Field<Bool>
    /// Optional current availability, including false after loss of Server Boosts.
    public let available: Field<Bool>
    /// Complete original object, retaining future fields and exact numeric lexemes.
    public let rawFields: [String: JSONValue]

    /// Parses a bounded immutable emoji without I/O, permission checks or suspension.
    /// - Parameters:
    ///   - data: Complete UTF-8 object with required nullable ID and name.
    ///   - limits: Whole-document bounds, including unknown fields; defaults to 1 MiB/64 depth/100,000 nodes.
    /// - Throws: JSON syntax/bounds errors or sanitized invalid-response errors for missing, malformed
    ///   or mistyped fields. Null is accepted only for the required ID/name; callers must correct invalid input.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects one already bounded emoji subtree without reparsing or applying mutation-only limits.
    /// - Parameters:
    ///   - value: Original object from a successfully bounded containing document.
    ///   - limits: Containing document bounds reused for scalar projection.
    /// - Throws: Sanitized invalid-response errors for incompatible fields, invalid snowflakes or malformed users.
    ///   Construction is synchronous, owns no external resources and does not inspect task cancellation.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        id = try object.required("id", Nullable<EmojiID>.self)
        name = try object.required("name", Nullable<String>.self)
        roles = try object.field("roles", [RoleID].self)
        user = try object.messageField("user", MessageAuthor.self)
        requireColons = try object.field("require_colons", Bool.self)
        managed = try object.field("managed", Bool.self)
        animated = try object.field("animated", Bool.self)
        available = try object.field("available", Bool.self)
        rawFields = object.resource.fields
    }
}

/// API v10 application emoji collection under its documented `items` envelope.
/// This snapshot does not establish upload capacity, current ownership or application authorization.
public struct ApplicationEmojiList: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Complete ordered emoji list; an empty list remains an empty list.
    public let items: [Emoji]
    /// Complete original envelope, including future collection metadata.
    public let rawFields: [String: JSONValue]

    /// Parses an application emoji collection without requests, pagination or background work.
    /// - Parameters:
    ///   - data: Complete UTF-8 object with required nonnull `items` array.
    ///   - limits: Bounds covering the envelope, every emoji and unknown nested values.
    /// - Throws: Parser/bounds errors or sanitized invalid-response errors for missing/mistyped arrays
    ///   or malformed elements. No partially projected list escapes a failed initializer.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects an already bounded collection, preserving response order and exact subtrees.
    /// - Parameters:
    ///   - value: Original nonnull envelope object from a bounded document.
    ///   - limits: Bounds established by that document; no independent per-item byte budget is added.
    /// - Throws: Sanitized invalid-response errors for incompatible roots, arrays or emoji fields.
    ///   Work is synchronous and side-effect free; cancellation and resource cleanup are inapplicable.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        items = try object.messageModels("items", Emoji.self)
        rawFields = object.resource.fields
    }
}
