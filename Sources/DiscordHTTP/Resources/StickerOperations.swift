// File: Sources/DiscordHTTP/Resources/StickerOperations.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import DiscordModels

/// Explicit caller-snapshot request reduction for guild sticker metadata, independent of Gateway or cache ownership.
public enum StickerOperations {
    /// Omits a metadata PATCH when every requested field exactly equals a caller-owned guild sticker.
    /// - Parameters:
    ///   - guildID: Owning guild; a present snapshot guild ID must match, while omission remains server-validated.
    ///   - current: Caller-owned sticker whose known type must be guild, even for an empty request.
    ///   - request: Validated metadata changes; absent keys are ignored and explicit null description is preserved.
    ///   - auditReason: Optional supported reason validated only when a mutation descriptor is needed.
    /// - Returns: Nil for matching or empty changes; otherwise one unsafe PATCH with no preliminary reads or uploads.
    /// - Throws: Invalid-value for standard/unknown types, mismatched or null snapshot guild IDs,
    ///   incompatible request roots or ordinary descriptor/audit errors. Snapshots imply no current permissions or freshness.
    public static func modifyGuildIfChanged(guildID: GuildID, current: Sticker, request: GuildStickerModify,
                                            auditReason: String? = nil) throws -> Endpoint<Sticker>? {
        guard current.type.knownValue == .guild else { throw DiscordError.validation(.invalidValue) }
        switch current.guildID {
        case .absent: break
        case .value(let owner) where owner == guildID: break
        default: throw DiscordError.validation(.invalidValue)
        }
        guard try expressionFieldsChanged(current.rawFields, request: request.jsonValue()) else { return nil }
        return try StickerEndpoints.modifyGuild(guildID: guildID, stickerID: current.id, request: request, auditReason: auditReason)
    }
}
