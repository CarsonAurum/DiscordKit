// File: Sources/DiscordHTTP/Resources/GuildTemplateOperations.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import DiscordModels

/// Opt-in template request reduction over caller-owned snapshots, without I/O or implicit freshness.
public enum GuildTemplateOperations {
    /// Omits an exact metadata no-op against an explicitly supplied template snapshot.
    /// - Parameters:
    ///   - guildID: Expected source guild, checked against the snapshot before returning any descriptor.
    ///   - current: Caller-owned template snapshot; its code identifies the mutation. Staleness remains caller-owned.
    ///   - request: Validated metadata changes; omitted fields do not participate and null differs from empty text.
    /// - Returns: Nil for empty/matching changes, or one ordinary unsafe PATCH. No guild snapshot sync is inferred.
    /// - Throws: Invalid-value for a mismatched source guild; descriptor/body errors for changed requests.
    ///   This synchronous helper starts no tasks or requests and does not establish current ownership or permissions.
    public static func modifyIfChanged(guildID: GuildID, current: GuildTemplate,
                                       request: GuildTemplateModify) throws -> Endpoint<GuildTemplate>? {
        guard current.sourceGuildID == guildID else { throw DiscordError.validation(.invalidValue) }
        guard try expressionFieldsChanged(current.rawFields, request: request.jsonValue()) else { return nil }
        return try GuildTemplateEndpoints.modify(guildID: guildID, code: current.code, request: request)
    }
}
