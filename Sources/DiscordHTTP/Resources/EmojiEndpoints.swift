// File: Sources/DiscordHTTP/Resources/EmojiEndpoints.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import DiscordModels
import Foundation

/// API v10 guild and application emoji management, verified 2026-10-16 against
/// https://docs.discord.com/developers/resources/emoji and Discord's official OpenAPI.
/// Guild emoji quotas are exceptional per-guild limits whose reported remaining count may be inaccurate;
/// these descriptors retain the guild partition and shared finite 429 retry budgets. Application emoji
/// require the owning app's bot token; they grant no REST quota increase or USE_EXTERNAL_EMOJIS requirement.
/// All operations use bounded HTTP execution independently of Gateway adoption.
public enum EmojiEndpoints {
    /// Lists one guild's emojis in one request, without per-emoji hydration or invented pagination.
    /// - Parameters:
    ///   - guildID: Guild ID and exact major rate partition.
    ///   - readPolicy: Optional scoped reuse; default coalesces with no completed-result caching.
    /// - Returns: A safe HTTP 200 GET decoding an array, including empty. Uploader visibility depends on
    ///   CREATE_GUILD_EXPRESSIONS or MANAGE_GUILD_EXPRESSIONS and remains server-enforced.
    /// - Throws: Descriptor validation errors now; authentication, API, transport or schema failures on execution.
    public static func listGuild(guildID: GuildID, readPolicy: ReadPolicy? = ReadPolicy()) throws -> Endpoint<[Emoji]> {
        try Endpoint(method: "GET", path: ["guilds", guildID.description, "emojis"], route: "/guilds/{guild.id}/emojis",
            authentication: .bot, majorParameter: guildID.description, retrySafety: .safe,
            readPolicy: expressionReadPolicy(readPolicy, tags: ["emoji-catalog", "guild-catalog"]),
            decode: { try guildArray($0) { try Emoji(data: $0) } })
    }

    /// Gets one guild emoji without fetching its roles or uploader separately.
    /// - Parameters:
    ///   - guildID: Owning guild and major rate partition; ownership is validated by Discord.
    ///   - emojiID: Exact custom emoji ID, without conversion through floating point.
    ///   - readPolicy: Optional scoped reuse; nil disables it, default has no completed-result caching.
    /// - Returns: A safe HTTP 200 GET. Uploader visibility requires MANAGE_GUILD_EXPRESSIONS, or
    ///   CREATE_GUILD_EXPRESSIONS when the caller created the emoji. Missing emojis remain API errors.
    /// - Throws: Descriptor errors now; API, permission, transport or malformed-response errors during execution.
    public static func getGuild(guildID: GuildID, emojiID: EmojiID,
                                readPolicy: ReadPolicy? = ReadPolicy()) throws -> Endpoint<Emoji> {
        try Endpoint(method: "GET", path: ["guilds", guildID.description, "emojis", emojiID.description],
            route: "/guilds/{guild.id}/emojis/{emoji.id}", authentication: .bot,
            majorParameter: guildID.description, retrySafety: .safe,
            readPolicy: expressionReadPolicy(readPolicy, tags: ["emoji-catalog", "guild-catalog"]),
            decode: { try Emoji(data: $0) })
    }

    /// Creates one guild emoji with CREATE_GUILD_EXPRESSIONS, required for bots since 2026-02-23.
    /// - Parameters:
    ///   - guildID: Target guild and exceptional per-guild emoji rate partition.
    ///   - request: Validated name, bounded image data URI and explicit eligible-role IDs.
    ///     Premium role mixing, available slots, actual image dimensions and authorization remain server checks.
    ///   - auditReason: Optional supported reason, at most 512 Unicode scalars before percent encoding.
    /// - Returns: An unsafe POST requiring HTTP 201 with the created emoji and invalidating related snapshots.
    /// - Throws: Body/descriptor/audit errors now; API, transport or uncertain submission outcomes during execution.
    ///   Ambiguous mutations never replay automatically; explicit 429 rejection uses the finite shared retry budget.
    public static func createGuild(guildID: GuildID, request: GuildEmojiCreate,
                                   auditReason: String? = nil) throws -> Endpoint<Emoji> {
        try expressionGuildMutation("POST", guildID: guildID, resource: "emojis", routeResource: "emojis",
            payload: request.jsonValue(), auditReason: auditReason, successStatuses: [201], catalog: "emoji-catalog",
            decode: { try Emoji(data: $0) })
    }

    /// Changes optional emoji name/roles; null roles remain an explicit wire instruction.
    /// - Parameters:
    ///   - guildID: Owning guild and major rate partition.
    ///   - emojiID: Exact custom emoji target; no hidden ownership or permission read occurs.
    ///   - request: Validated optional changes; omission retains server state.
    ///   - auditReason: Optional supported reason, at most 512 Unicode scalars before encoding.
    /// - Returns: An unsafe HTTP 200 PATCH. Caller-created emojis require CREATE_GUILD_EXPRESSIONS or
    ///   MANAGE_GUILD_EXPRESSIONS; other emojis require MANAGE_GUILD_EXPRESSIONS. Discord checks current authority.
    /// - Throws: Body/descriptor/audit errors now; API, transport, invalid-response or uncertain mutation outcomes later.
    public static func modifyGuild(guildID: GuildID, emojiID: EmojiID, request: GuildEmojiModify,
                                   auditReason: String? = nil) throws -> Endpoint<Emoji> {
        try expressionGuildMutation("PATCH", guildID: guildID, resource: "emojis", routeResource: "emojis",
            id: emojiID.description, routeID: "emoji.id", payload: request.jsonValue(), auditReason: auditReason,
            catalog: "emoji-catalog", decode: { try Emoji(data: $0) })
    }

    /// Deletes a guild emoji; caller-created/other emoji permissions match modifyGuild.
    /// - Parameters:
    ///   - guildID: Exact owning guild and exceptional per-guild emoji rate partition.
    ///   - emojiID: Exact custom emoji target; missing emojis remain API errors.
    ///   - auditReason: Optional supported reason, at most 512 Unicode scalars before encoding.
    /// - Returns: One unsafe DELETE requiring empty HTTP 204 and invalidating scoped emoji/guild/audit reads.
    /// - Throws: Descriptor/audit errors now; API, transport or uncertain deletion outcomes during execution.
    public static func deleteGuild(guildID: GuildID, emojiID: EmojiID,
                                   auditReason: String? = nil) throws -> Endpoint<EmptyResponse> {
        try expressionGuildMutation("DELETE", guildID: guildID, resource: "emojis", routeResource: "emojis",
            id: emojiID.description, routeID: "emoji.id", auditReason: auditReason, successStatuses: [204],
            catalog: "emoji-catalog", decode: { try EmptyResponse(data: $0) })
    }

    /// Lists application-owned emojis using its bot token, preserving the documented items envelope.
    /// - Parameters:
    ///   - applicationID: Owning app; Discord validates that the bot token belongs to it.
    ///   - readPolicy: Optional credential-scoped reuse; default coalesces without completed caching.
    /// - Returns: A safe HTTP 200 GET, including an empty items list. No pagination or extra reads are invented.
    /// - Throws: Descriptor errors now; authorization/API/transport or invalid-envelope failures during execution.
    public static func listApplication(applicationID: ApplicationID,
                                       readPolicy: ReadPolicy? = ReadPolicy()) throws -> Endpoint<ApplicationEmojiList> {
        try Endpoint(method: "GET", path: ["applications", applicationID.description, "emojis"],
            route: "/applications/{application.id}/emojis", authentication: .bot, retrySafety: .safe,
            readPolicy: expressionReadPolicy(readPolicy, tags: ["application-emoji-catalog"]),
            decode: { try ApplicationEmojiList(data: $0) })
    }

    /// Gets one application emoji with its optional uploader projection and retained unknown fields.
    /// - Parameters:
    ///   - applicationID: Exact owning app; the supplied bot token must belong to it.
    ///   - emojiID: Exact custom emoji ID.
    ///   - readPolicy: Optional credential-scoped reuse; nil disables reuse, default has no completed caching.
    /// - Returns: A safe HTTP 200 GET; missing resources remain API errors. App IDs do not invent a major partition.
    /// - Throws: Descriptor errors now; authentication/API/transport or malformed-emoji failures during execution.
    public static func getApplication(applicationID: ApplicationID, emojiID: EmojiID,
                                      readPolicy: ReadPolicy? = ReadPolicy()) throws -> Endpoint<Emoji> {
        try Endpoint(method: "GET", path: ["applications", applicationID.description, "emojis", emojiID.description],
            route: "/applications/{application.id}/emojis/{emoji.id}", authentication: .bot, retrySafety: .safe,
            readPolicy: expressionReadPolicy(readPolicy, tags: ["application-emoji-catalog"]),
            decode: { try Emoji(data: $0) })
    }

    /// Uploads one bounded application emoji; Discord enforces app ownership, image dimensions and 2,000 slots.
    /// - Parameters:
    ///   - applicationID: Owning application whose bot token authorizes this operation.
    ///   - request: Validated name and image data URI bounded to 256 KiB decoded image bytes.
    /// - Returns: One unsafe HTTP 201 POST with the created emoji; there is no supported audit reason or role list.
    /// - Throws: Body/descriptor errors before I/O; API/transport/schema or uncertain submission outcomes later.
    public static func createApplication(applicationID: ApplicationID, request: ApplicationEmojiCreate) throws -> Endpoint<Emoji> {
        try applicationEmojiMutation("POST", applicationID: applicationID, payload: request.jsonValue(),
            successStatuses: [201], decode: { try Emoji(data: $0) })
    }

    /// Applies an optional application emoji rename without modifying image data or roles.
    /// - Parameters:
    ///   - applicationID: Owning application; its bot token is required.
    ///   - emojiID: Exact custom emoji target; existence is server-validated.
    ///   - request: Validated optional name; omission sends an empty object per the official OpenAPI
    ///     preview's partial schema. No preliminary snapshot fetch or implicit no-op suppression occurs.
    /// - Returns: One unsafe HTTP 200 PATCH, invalidating application emoji snapshots only within the credential scope.
    /// - Throws: Body/descriptor errors now; API/transport/schema or uncertain mutation outcomes on execution.
    public static func modifyApplication(applicationID: ApplicationID, emojiID: EmojiID,
                                         request: ApplicationEmojiModify) throws -> Endpoint<Emoji> {
        try applicationEmojiMutation("PATCH", applicationID: applicationID, emojiID: emojiID,
            payload: request.jsonValue(), decode: { try Emoji(data: $0) })
    }

    /// Deletes one application emoji without any implicit reconciliation or audit-log header.
    /// - Parameters:
    ///   - applicationID: Owning application; its bot token is required.
    ///   - emojiID: Exact target emoji; a missing emoji remains an API error.
    /// - Returns: One unsafe DELETE requiring empty HTTP 204. Ambiguous deletions are never automatically replayed.
    /// - Throws: Descriptor errors now; API/transport or uncertain submission outcomes during execution.
    public static func deleteApplication(applicationID: ApplicationID, emojiID: EmojiID) throws -> Endpoint<EmptyResponse> {
        try applicationEmojiMutation("DELETE", applicationID: applicationID, emojiID: emojiID,
            successStatuses: [204], decode: { try EmptyResponse(data: $0) })
    }
}

/// Preserves caller freshness/coalescing choices while adding expression visibility invalidation.
/// - Parameters:
///   - policy: Optional reuse configuration; nil disables coalescing and caching entirely.
///   - tags: Finite catalog tags; credential scope is applied by the existing client authority.
/// - Returns: Equivalent reuse choices and unioned tags, without enabling completed caching implicitly.
func expressionReadPolicy(_ policy: ReadPolicy?, tags: Set<String>) -> ReadPolicy? {
    policy.map { ReadPolicy(coalescing: $0.coalescing, timeToLive: $0.timeToLive, tags: $0.tags.union(tags)) }
}

/// Constructs one bounded guild expression mutation through the existing shared execution pipeline.
/// - Parameters:
///   - method: Explicit unsafe HTTP mutation verb; no replay policy is inferred from the method.
///   - guildID: Owning guild and major rate partition, retained for emoji's exceptional guild quotas.
///   - resource: Literal collection path segment such as emojis, stickers or soundboard-sounds.
///   - routeResource: Stable collection segment in the normalized route.
///   - id: Optional exact target ID; nil addresses the collection.
///   - routeID: Optional normalized target placeholder without braces; required when id is supplied.
///   - payload: Optional validated JSON payload; nil sends no body unless body is supplied.
///   - body: Optional already-bounded multipart body; never used with payload.
///   - auditReason: Optional supported reason, at most 512 Unicode scalars before encoding.
///   - successStatuses: Exact allowed statuses, default 200; creation uses 201, deletion 204.
///   - catalog: Expression-family tag invalidated with guild, message, channel and audit catalogs.
///   - decode: Synchronous complete-response decoder; errors are surfaced by ordinary client execution.
/// - Returns: One immutable unsafe descriptor, starting no tasks, reads or network operations.
/// - Throws: Invalid-value for conflicting bodies or inconsistent target placeholders; JSON/body/descriptor errors propagate.
func expressionGuildMutation<T: Sendable>(_ method: String, guildID: GuildID, resource: String, routeResource: String,
    id: String? = nil, routeID: String? = nil, payload: JSONValue? = nil, body: RequestBody? = nil,
    auditReason: String? = nil, successStatuses: Set<Int> = [200], catalog: String,
    decode: @escaping @Sendable (Data) throws -> T) throws -> Endpoint<T> {
    guard (id == nil) == (routeID == nil), payload == nil || body == nil else { throw DiscordError.validation(.invalidValue) }
    return try Endpoint(method: method, path: ["guilds", guildID.description, resource] + (id.map { [$0] } ?? []),
        route: "/guilds/{guild.id}/" + routeResource + (routeID.map { "/{\($0)}" } ?? ""),
        authentication: .bot, successStatuses: successStatuses, majorParameter: guildID.description,
        auditReason: auditReason, body: try body ?? payload.map { try guildJSON($0) },
        invalidates: guildTags(guildID).union([catalog, "audit-log-catalog"]), decode: decode)
}

/// Builds one application emoji mutation without inventing guild quotas, audit support or application major keys.
/// - Parameters:
///   - method: Explicit unsafe POST, PATCH or DELETE.
///   - applicationID: Exact app path ID; its bot token must authorize the operation.
///   - emojiID: Optional exact target emoji; nil selects collection creation.
///   - payload: Optional validated JSON request; nil sends no body.
///   - successStatuses: Exact success codes; default 200, creation 201, deletion 204.
///   - decode: Complete operation-specific decoder; empty deletion is validated by EmptyResponse.
/// - Returns: One unsafe descriptor with scoped application emoji invalidation and ordinary global admission.
/// - Throws: JSON/body/descriptor errors before I/O; execution failures occur through the ordinary shared pipeline.
func applicationEmojiMutation<T: Sendable>(_ method: String, applicationID: ApplicationID, emojiID: EmojiID? = nil,
    payload: JSONValue? = nil, successStatuses: Set<Int> = [200],
    decode: @escaping @Sendable (Data) throws -> T) throws -> Endpoint<T> {
    try Endpoint(method: method, path: ["applications", applicationID.description, "emojis"] + (emojiID.map { [$0.description] } ?? []),
        route: "/applications/{application.id}/emojis" + (emojiID == nil ? "" : "/{emoji.id}"),
        authentication: .bot, successStatuses: successStatuses, body: payload.map { try guildJSON($0) },
        invalidates: ["application-emoji-catalog"], decode: decode)
}
