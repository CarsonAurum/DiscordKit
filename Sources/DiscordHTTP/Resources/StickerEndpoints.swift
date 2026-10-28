// File: Sources/DiscordHTTP/Resources/StickerEndpoints.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import DiscordModels
import Foundation

/// Eight API v10 sticker operations, verified 2026-10-16 against the current Sticker reference
/// and official OpenAPI. Reads never hydrate stickers or packs individually; there is no documented
/// pagination. Guild writes use shared admission and finite cancellation/deadline/retry budgets.
/// See https://docs.discord.com/developers/resources/sticker.
public enum StickerEndpoints {
    /// Retrieves a sticker by global ID without requiring a caller-supplied guild ID.
    /// - Parameters:
    ///   - stickerID: Exact standard or guild sticker ID; visibility remains server-validated.
    ///   - readPolicy: Optional scoped reuse; default coalesces without completed caching, nil disables reuse.
    /// - Returns: A safe HTTP 200 GET accepting both sticker types and preserving unknown format/type values.
    ///   The current official OpenAPI requires a bot token for this route.
    /// - Throws: Descriptor errors before I/O; API/authentication/transport or invalid-sticker failures on execution.
    public static func get(stickerID: StickerID, readPolicy: ReadPolicy? = ReadPolicy()) throws -> Endpoint<Sticker> {
        try Endpoint(method: "GET", path: ["stickers", stickerID.description], route: "/stickers/{sticker.id}",
            authentication: .bot, retrySafety: .safe,
            readPolicy: expressionReadPolicy(readPolicy, tags: ["sticker-catalog", "guild-catalog"]),
            decode: { try Sticker(data: $0) })
    }

    /// Lists all currently available standard sticker packs in one request.
    /// - Parameter readPolicy: Optional scoped reuse; default coalesces without completed caching.
    /// - Returns: A safe HTTP 200 GET with the required sticker_packs envelope, including an empty array.
    ///   This public route deliberately omits credentials even when the client owns a bot token.
    /// - Throws: Descriptor errors before I/O; API/transport or invalid-envelope errors during execution.
    public static func listPacks(readPolicy: ReadPolicy? = ReadPolicy()) throws -> Endpoint<StickerPackList> {
        try Endpoint(method: "GET", path: ["sticker-packs"], route: "/sticker-packs", authentication: .none,
            retrySafety: .safe, readPolicy: expressionReadPolicy(readPolicy, tags: ["sticker-pack-catalog"]),
            decode: { try StickerPackList(data: $0) })
    }

    /// Gets a pack with its included sticker projections; no follow-up sticker requests occur.
    /// - Parameters:
    ///   - packID: Exact pack ID. Discord checks existence; a missing pack remains an API error.
    ///   - readPolicy: Optional scoped reuse; default coalesces, nil disables it, no default completed caching.
    /// - Returns: A safe HTTP 200 GET. The current official OpenAPI requires a bot token for this route.
    /// - Throws: Descriptor errors now; authentication/API/transport or invalid-pack errors during execution.
    public static func getPack(packID: StickerPackID, readPolicy: ReadPolicy? = ReadPolicy()) throws -> Endpoint<StickerPack> {
        try Endpoint(method: "GET", path: ["sticker-packs", packID.description], route: "/sticker-packs/{pack.id}",
            authentication: .bot, retrySafety: .safe,
            readPolicy: expressionReadPolicy(readPolicy, tags: ["sticker-pack-catalog"]),
            decode: { try StickerPack(data: $0) })
    }

    /// Lists one guild's stickers without extra per-sticker or uploader reads.
    /// - Parameters:
    ///   - guildID: Exact guild ID and major rate partition.
    ///   - readPolicy: Optional scoped reuse; default coalesces with no completed caching.
    /// - Returns: A safe HTTP 200 GET decoding an array, including empty. Uploader fields require
    ///   CREATE_GUILD_EXPRESSIONS or MANAGE_GUILD_EXPRESSIONS; Discord enforces their visibility.
    /// - Throws: Descriptor errors now; API/authentication/transport or invalid-array errors during execution.
    public static func listGuild(guildID: GuildID, readPolicy: ReadPolicy? = ReadPolicy()) throws -> Endpoint<[Sticker]> {
        try Endpoint(method: "GET", path: ["guilds", guildID.description, "stickers"], route: "/guilds/{guild.id}/stickers",
            authentication: .bot, majorParameter: guildID.description, retrySafety: .safe,
            readPolicy: expressionReadPolicy(readPolicy, tags: ["sticker-catalog", "guild-catalog"]),
            decode: { try guildArray($0) { try Sticker(data: $0) } })
    }

    /// Gets a guild sticker, retaining optional uploader and availability without inferring permission.
    /// - Parameters:
    ///   - guildID: Owning guild and major rate partition; Discord validates ownership.
    ///   - stickerID: Exact target sticker ID, preserving the entire UInt64 range.
    ///   - readPolicy: Optional scoped reuse; nil disables reuse, default no completed caching.
    /// - Returns: A safe HTTP 200 GET. Uploader visibility matches listGuild; no hidden permission read occurs.
    /// - Throws: Descriptor errors now; API/transport/authentication or malformed-sticker errors on execution.
    public static func getGuild(guildID: GuildID, stickerID: StickerID,
                                readPolicy: ReadPolicy? = ReadPolicy()) throws -> Endpoint<Sticker> {
        try Endpoint(method: "GET", path: ["guilds", guildID.description, "stickers", stickerID.description],
            route: "/guilds/{guild.id}/stickers/{sticker.id}", authentication: .bot,
            majorParameter: guildID.description, retrySafety: .safe,
            readPolicy: expressionReadPolicy(readPolicy, tags: ["sticker-catalog", "guild-catalog"]),
            decode: { try Sticker(data: $0) })
    }

    /// Creates one guild sticker with a bounded multipart file upload and CREATE_GUILD_EXPRESSIONS.
    /// - Parameters:
    ///   - guildID: Target guild and major rate partition.
    ///   - name: Sticker name, 2...30 Unicode scalars.
    ///   - description: Description, empty or 2...100 Unicode scalars; sent as an explicit multipart field.
    ///   - tags: Autocomplete tags, at most 200 Unicode scalars including empty, without splitting the upstream convention.
    ///   - file: Owned PNG, APNG, GIF or Lottie JSON bytes, bounded to 512 KiB before framing.
    ///     Discord checks 320x320 dimensions, maximum five-second animation and Lottie guild-feature eligibility.
    ///   - maximumRequestBytes: Local complete-body cap, default 1 MiB including framing; StickerUpload validates bounds.
    ///   - auditReason: Optional supported reason, at most 512 Unicode scalars before encoding.
    /// - Returns: One unsafe POST requiring HTTP 201 with the created sticker; no remote media fetch occurs.
    /// - Throws: Invalid text/media/body/audit limits or serialization errors now; permissions, guild slots,
    ///   API/transport/schema or uncertain submission outcomes later. Ambiguous uploads never replay automatically.
    public static func createGuild(guildID: GuildID, name: String, description: String, tags: String,
        file: StickerUploadFile, maximumRequestBytes: Int = 1_048_576, auditReason: String? = nil) throws -> Endpoint<Sticker> {
        let body = try StickerUpload.body(name: name, description: description, tags: tags, file: file,
            maximumRequestBytes: maximumRequestBytes)
        return try expressionGuildMutation("POST", guildID: guildID, resource: "stickers", routeResource: "stickers",
            body: body, auditReason: auditReason, successStatuses: [201], catalog: "sticker-catalog",
            decode: { try Sticker(data: $0) })
    }

    /// Changes sticker metadata without reuploading its file or modifying format/type.
    /// - Parameters:
    ///   - guildID: Exact owning guild and major rate partition.
    ///   - stickerID: Exact target sticker; Discord validates ownership and current eligibility.
    ///   - request: Validated optional name/description/tags; null description explicitly clears it.
    ///   - auditReason: Optional supported reason, at most 512 Unicode scalars before encoding.
    /// - Returns: One unsafe HTTP 200 PATCH. Caller-created stickers require CREATE_GUILD_EXPRESSIONS
    ///   or MANAGE_GUILD_EXPRESSIONS; other stickers require MANAGE_GUILD_EXPRESSIONS.
    /// - Throws: Body/descriptor/audit errors before I/O; API/transport/schema or uncertain submission outcomes later.
    public static func modifyGuild(guildID: GuildID, stickerID: StickerID, request: GuildStickerModify,
                                   auditReason: String? = nil) throws -> Endpoint<Sticker> {
        try expressionGuildMutation("PATCH", guildID: guildID, resource: "stickers", routeResource: "stickers",
            id: stickerID.description, routeID: "sticker.id", payload: request.jsonValue(), auditReason: auditReason,
            catalog: "sticker-catalog", decode: { try Sticker(data: $0) })
    }

    /// Deletes one guild sticker with the same caller-created/other permissions as modifyGuild.
    /// - Parameters:
    ///   - guildID: Exact owning guild and major rate partition.
    ///   - stickerID: Exact sticker target; a missing sticker remains an API error.
    ///   - auditReason: Optional supported reason, at most 512 Unicode scalars before encoding.
    /// - Returns: One unsafe DELETE requiring empty HTTP 204 and invalidating related scoped snapshots.
    /// - Throws: Descriptor/audit errors now; API/transport or uncertain deletion outcomes on execution.
    public static func deleteGuild(guildID: GuildID, stickerID: StickerID,
                                   auditReason: String? = nil) throws -> Endpoint<EmptyResponse> {
        try expressionGuildMutation("DELETE", guildID: guildID, resource: "stickers", routeResource: "stickers",
            id: stickerID.description, routeID: "sticker.id", auditReason: auditReason, successStatuses: [204],
            catalog: "sticker-catalog", decode: { try EmptyResponse(data: $0) })
    }
}
