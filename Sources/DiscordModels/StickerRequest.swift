// File: Sources/DiscordModels/StickerRequest.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import Foundation

/// Validated API v10 PATCH /guilds/{guild.id}/stickers/{sticker.id} metadata body.
/// Own stickers require CREATE_GUILD_EXPRESSIONS or MANAGE_GUILD_EXPRESSIONS; other stickers
/// require MANAGE_GUILD_EXPRESSIONS. The server emits Guild Stickers Update on success.
/// Creating a sticker requires multipart file fields and is provided by the HTTP upload helper.
public struct GuildStickerModify: GuildRequestPayload {
    private let fields: [String: JSONValue]

    /// Validates selected metadata while preserving exact Unicode and omission/null distinctions.
    /// - Parameters:
    ///   - name: Absent by default or nonnull name of 2...30 Unicode scalars.
    ///   - description: Absent by default, explicit null to clear, or text of 2...100 Unicode scalars.
    ///     Empty text is accepted only by multipart creation; modification follows the written nullable schema.
    ///   - tags: Absent by default or nonnull autocomplete text of at most 200 Unicode scalars; empty text
    ///     is permitted by the written maximum-only rule. Discord validates suggestion semantics.
    /// - Throws: Safe invalid-value errors for forbidden nulls or text outside these bounds. Character
    ///   counts follow the repository's scalar policy; Discord remains authoritative on exact Unicode limits.
    ///   Construction is synchronous, owns no resources and performs no requests, logging or suspension.
    public init(name: Field<String> = .absent, description: Field<String> = .absent,
                tags: Field<String> = .absent) throws {
        var result: [String: JSONValue] = [:]
        try guildRequestField(name, name: "name", into: &result) { try guildRequestText($0, length: 2...30) }
        try guildRequestField(description, name: "description", nullable: true, into: &result) {
            try guildRequestText($0, length: 2...100)
        }
        try guildRequestField(tags, name: "tags", into: &result) { try guildRequestText($0, length: 0...200) }
        fields = result
    }

    /// Returns the validated metadata update without uploading or modifying media bytes.
    /// - Returns: Exact selected fields, including explicit null description; empty selections produce `{}`.
    public func jsonValue() -> JSONValue { .object(fields) }
}
