// File: Sources/DiscordHTTP/Resources/EmojiOperations.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import DiscordModels

/// Explicit request reduction over caller-owned emoji snapshots, without I/O, tasks or implicit freshness.
public enum EmojiOperations {
    /// Skips a guild PATCH when every explicitly requested field equals the caller's snapshot.
    /// - Parameters:
    ///   - guildID: Owning guild, checked by Discord at execution; emoji objects do not carry guild ownership.
    ///   - current: Caller-owned custom emoji snapshot. A null ID is invalid even for an otherwise empty edit.
    ///   - request: Validated optional fields. Omission does not participate; null and absent remain distinct.
    ///   - auditReason: Optional supported reason; validated only when a mutation is needed.
    /// - Returns: Nil for matching/empty changes, or one ordinary unsafe PATCH. Role arrays compare in exact order.
    /// - Throws: Invalid-value for a Unicode/null-ID emoji or incompatible request root; descriptor/audit errors propagate.
    ///   Stale snapshots retain ordinary reconciliation races and never establish current permissions or premium eligibility.
    public static func modifyGuildIfChanged(guildID: GuildID, current: Emoji, request: GuildEmojiModify,
                                            auditReason: String? = nil) throws -> Endpoint<Emoji>? {
        guard case .value(let id) = current.id else { throw DiscordError.validation(.invalidValue) }
        guard try expressionFieldsChanged(current.rawFields, request: request.jsonValue()) else { return nil }
        return try EmojiEndpoints.modifyGuild(guildID: guildID, emojiID: id, request: request, auditReason: auditReason)
    }

    /// Skips an application emoji PATCH when its name is omitted or equals the caller-owned snapshot.
    /// - Parameters:
    ///   - applicationID: Owning app; its bot token and emoji ownership are checked by Discord during execution.
    ///   - current: Custom emoji snapshot; null-ID Unicode emoji cannot identify application resources.
    ///   - request: Validated optional name; unknown snapshot fields do not force a write.
    /// - Returns: Nil for an omitted/matching name, or one ordinary unsafe PATCH without reads or audit headers.
    /// - Throws: Invalid-value for a null ID or incompatible request root; normal descriptor errors propagate.
    ///   No snapshot freshness, app ownership or current authorization is inferred locally.
    public static func modifyApplicationIfChanged(applicationID: ApplicationID, current: Emoji,
                                                  request: ApplicationEmojiModify) throws -> Endpoint<Emoji>? {
        guard case .value(let id) = current.id else { throw DiscordError.validation(.invalidValue) }
        guard try expressionFieldsChanged(current.rawFields, request: request.jsonValue()) else { return nil }
        return try EmojiEndpoints.modifyApplication(applicationID: applicationID, emojiID: id, request: request)
    }
}

/// Compares only explicit request keys against exact caller-owned response fields.
/// - Parameters:
///   - current: Original raw snapshot fields; absent keys remain distinct from null or empty values.
///   - request: Validated request JSON, required to have an object root.
/// - Returns: True when any requested value differs, false for an empty or fully matching request.
///   Arrays retain order, and numeric lexical differences conservatively produce a mutation.
/// - Throws: Invalid-value for a nonobject request before any descriptor creation or I/O.
func expressionFieldsChanged(_ current: [String: JSONValue], request: JSONValue) throws -> Bool {
    guard case .object(let fields) = request else { throw DiscordError.validation(.invalidValue) }
    return fields.contains { current[$0.key] != $0.value }
}
