import DiscordCore
import DiscordModels
import Foundation

/// All six current API v10 Guild Template operations, verified 2026-10-16 against
/// https://docs.discord.com/developers/resources/guild-template and the official OpenAPI preview.
/// Guild creation from a template is removed upstream and is deliberately not exposed.
/// Mutations use shared credential/guild admission and finite rejected-429 retries; an ambiguous
/// submission remains indeterminate. No Gateway adoption, hidden hydration or list pagination is required.
public enum GuildTemplateEndpoints {
    /// Retrieves a public template snapshot by its opaque code without fetching related guilds or users.
    /// - Parameters:
    ///   - code: Nonempty single path segment; unsafe separators/control characters fail descriptor validation.
    ///   - authenticated: False by default sends anonymously; true requires bot authentication under preview compatibility.
    ///   - readPolicy: Optional explicit reuse policy, default coalesces with no completed caching. Public and bot results
    ///     retain their separate authentication scopes; a positive TTL is required to cache snapshots.
    /// - Returns: Safe HTTP 200 GET decoding a complete template and partial serialized guild.
    /// - Throws: Descriptor/policy errors now; API, transport, cancellation or malformed-response failures on execution.
    public static func get(code: String, authenticated: Bool = false,
                           readPolicy: ReadPolicy? = ReadPolicy()) throws -> Endpoint<GuildTemplate> {
        try Endpoint(method: "GET", path: ["guilds", "templates", code], route: "/guilds/templates/{template.code}",
            authentication: authenticated ? .bot : .none, retrySafety: .safe,
            readPolicy: expressionReadPolicy(readPolicy, tags: ["guild-template-catalog", "guild-catalog"]),
            decode: { try GuildTemplate(data: $0) })
    }

    /// Retrieves all templates of one guild in server order, requiring MANAGE_GUILD and the bot token.
    /// - Parameters:
    ///   - guildID: Exact guild ID and major rate partition; a snapshot ID never substitutes for this value.
    ///   - readPolicy: Optional scoped reuse, default coalesces without completed caching; nil disables reuse.
    /// - Returns: Safe HTTP 200 GET of an array, including empty. No cursor, prefetch or per-template reads are invented.
    /// - Throws: Descriptor/policy errors now; authentication, permissions, API, transport or schema failures on execution.
    public static func list(guildID: GuildID, readPolicy: ReadPolicy? = ReadPolicy()) throws -> Endpoint<[GuildTemplate]> {
        try Endpoint(method: "GET", path: ["guilds", guildID.description, "templates"],
            route: "/guilds/{guild.id}/templates", authentication: .bot, majorParameter: guildID.description,
            retrySafety: .safe, readPolicy: expressionReadPolicy(readPolicy, tags: ["guild-template-catalog", "guild-catalog"]),
            decode: { try guildArray($0) { try GuildTemplate(data: $0) } })
    }

    /// Creates a snapshot template from an existing guild with MANAGE_GUILD, without creating a guild.
    /// - Parameters:
    ///   - guildID: Existing source guild and major rate partition; Discord checks current permissions.
    ///   - request: Validated required name and optional nullable description.
    /// - Returns: Unsafe HTTP 200 POST returning the created template and invalidating scoped template/guild reads.
    /// - Throws: Body/descriptor errors now; API, cancellation, transport, schema or indeterminate-submission failures later.
    public static func create(guildID: GuildID, request: GuildTemplateCreate) throws -> Endpoint<GuildTemplate> {
        try templateMutation("POST", guildID: guildID, payload: request.jsonValue())
    }

    /// Synchronizes the serialized snapshot with the existing source guild's current state, requiring MANAGE_GUILD.
    /// - Parameters:
    ///   - guildID: Existing source guild and major rate partition.
    ///   - code: Opaque template code; Discord checks that it belongs to this guild.
    /// - Returns: Unsafe HTTP 200 PUT returning the synchronized template. No request body or hidden preliminary read occurs.
    /// - Throws: Descriptor errors now; permission/API/transport/schema or indeterminate outcomes on execution.
    ///   Snapshot is_dirty alone does not justify skipping synchronization of unobserved external changes.
    public static func sync(guildID: GuildID, code: String) throws -> Endpoint<GuildTemplate> {
        try templateMutation("PUT", guildID: guildID, code: code)
    }

    /// Changes template name/description with MANAGE_GUILD, retaining the serialized source snapshot.
    /// - Parameters:
    ///   - guildID: Source guild and major rate partition.
    ///   - code: Opaque template code owned by the guild; ownership is checked by Discord.
    ///   - request: Validated optional changes, preserving null versus empty description.
    /// - Returns: Unsafe HTTP 200 PATCH returning the template. Empty changes still send one request.
    /// - Throws: Body/descriptor errors now; authentication/API/transport/schema or uncertain mutation failures later.
    public static func modify(guildID: GuildID, code: String, request: GuildTemplateModify) throws -> Endpoint<GuildTemplate> {
        try templateMutation("PATCH", guildID: guildID, code: code, payload: request.jsonValue())
    }

    /// Deletes one template with MANAGE_GUILD; the source guild remains independently owned by Discord.
    /// - Parameters:
    ///   - guildID: Exact source guild and major rate partition.
    ///   - code: Opaque code to delete, validated as one nonempty path segment.
    /// - Returns: Unsafe HTTP 200 DELETE returning the deleted template, rather than an invented empty 204 response.
    /// - Throws: Descriptor errors now; API, transport, cancellation, schema or indeterminate deletion failures on execution.
    public static func delete(guildID: GuildID, code: String) throws -> Endpoint<GuildTemplate> {
        try templateMutation("DELETE", guildID: guildID, code: code)
    }
}

/// Constructs a single guild-owned template mutation through ordinary shared HTTP policy.
/// - Parameters:
///   - method: Explicit POST, PUT, PATCH or DELETE; all retain unsafe replay semantics.
///   - guildID: Existing source guild and exact major rate partition.
///   - code: Optional code for an individual template; nil selects the collection create route.
///   - payload: Optional validated metadata object; nil sends no body.
/// - Returns: HTTP 200 template descriptor invalidating credential-scoped template, guild and audit snapshots.
/// - Throws: Bounded JSON/body or descriptor validation errors, including unsafe code segments.
///   No tasks, rate reservations, network I/O or preliminary reads begin during construction.
private func templateMutation(_ method: String, guildID: GuildID, code: String? = nil,
                              payload: JSONValue? = nil) throws -> Endpoint<GuildTemplate> {
    try Endpoint(method: method, path: ["guilds", guildID.description, "templates"] + (code.map { [$0] } ?? []),
        route: "/guilds/{guild.id}/templates" + (code == nil ? "" : "/{template.code}"),
        authentication: .bot, majorParameter: guildID.description, body: try payload.map { try guildJSON($0) },
        invalidates: guildTags(guildID).union(["guild-template-catalog", "audit-log-catalog"]),
        decode: { try GuildTemplate(data: $0) })
}
