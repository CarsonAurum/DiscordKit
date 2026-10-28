// File: Sources/DiscordHTTP/Resources/UserEndpoints.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import DiscordModels
import Foundation

/// All twelve written API v10 User operations, verified 2026-10-16 against
/// https://docs.discord.com/developers/resources/user, the Discord changelog and official OpenAPI preview.
/// HTTP adoption is independent of Gateway/OAuth2 exchange runtimes. Bearer-only operations require
/// caller-acquired consented tokens with the documented scopes; descriptors cannot introspect token scope.
/// Every request uses existing shared credential/route admission, finite rejected-429 retry budgets,
/// cancellation and deadlines. Mutations retain unsafe ambiguous-submission semantics; no background
/// hydration, unsolicited DM fan-out, automatic pagination or implicit completed cache is introduced.
public enum UserEndpoints {
    /// Gets the authenticated account's complete resource-owned User projection.
    /// - Parameter readPolicy: Optional scoped reuse; defaults to coalescing with no completed caching.
    ///   A positive TTL explicitly permits stale account data until expiry; nil disables reuse.
    /// - Returns: Safe GET /users/@me accepting bot or bearer. OAuth2 requires identify, email for email
    ///   visibility, and approved identify.premium for actual subscription level; zero can mean missing scope.
    /// - Throws: Descriptor/policy validation errors now; API, transport, cancellation or schema errors on execution.
    ///   No guild permissions, intents, pagination or prior profile request is required.
    public static func current(readPolicy: ReadPolicy? = ReadPolicy()) throws -> Endpoint<User> {
        try Endpoint(method: "GET", path: ["users", "@me"], authentication: .botOrBearer, retrySafety: .safe,
            readPolicy: expressionReadPolicy(readPolicy, tags: ["user-catalog"]), decode: { try User(data: $0) })
    }

    /// Gets one user's visible account data without fetching guild membership or relationships.
    /// - Parameters:
    ///   - userID: Exact user snowflake; this is not a Discord major rate-limit parameter.
    ///   - readPolicy: Optional scoped coalescing/freshness, defaulting to coalescing without completed caching.
    /// - Returns: Safe bot-authenticated GET /users/{user.id}, decoding required/null/optional User fields.
    /// - Throws: Descriptor/policy errors now; API permission/not-found, transport, cancellation or schema errors later.
    ///   A successful snapshot does not establish authorization to DM this user or view unrelated resources.
    public static func get(userID: UserID, readPolicy: ReadPolicy? = ReadPolicy()) throws -> Endpoint<User> {
        try Endpoint(method: "GET", path: ["users", userID.description], route: "/users/{user.id}",
            authentication: .bot, retrySafety: .safe,
            readPolicy: expressionReadPolicy(readPolicy, tags: ["user-catalog"]), decode: { try User(data: $0) })
    }

    /// Updates the current bot account, requiring the bot token under the official preview security contract.
    /// - Parameter request: Validated optional username/avatar/banner edits; empty edits remain one explicit request.
    /// - Returns: Unsafe PATCH /users/@me returning User and invalidating credential-scoped user/application
    ///   snapshots. Discord may randomize the discriminator after a username change and emit User Update.
    /// - Throws: Body/descriptor errors now; API, transport, cancellation, schema or indeterminate mutation errors later.
    ///   Further username/content/feature rules are checked by Discord; no preliminary read or hidden retry occurs.
    public static func modifyCurrent(request: UserModify) throws -> Endpoint<User> {
        try Endpoint(method: "PATCH", path: ["users", "@me"], authentication: .bot,
            body: try guildJSON(request.jsonValue()), invalidates: ["user-catalog", "application-catalog"],
            decode: { try User(data: $0) })
    }

    /// Lists one page of the current account's partial guild snapshots, including the new large-bot shard query.
    /// - Parameters:
    ///   - query: Optional validated bounds/cursors/counts/shard. Nil preserves the server's default limit of 200.
    ///     Large-bot deployments must supply the REST storage shard, from zero through max_concurrency minus one;
    ///     it differs from Gateway shard ID. Use UserGuildsQuery.largeBotSharding to require explicit selection locally.
    ///   - readPolicy: Optional scoped reuse, default coalescing without completed caching; pagination helpers disable it.
    /// - Returns: Safe bot-or-bearer GET /users/@me/guilds. OAuth2 requires guilds. A preview-permitted top-level
    ///   null is preserved separately from an empty array. with_counts controls optional approximate counts.
    /// - Throws: Descriptor/policy errors now; API 400 for an unselected required shard, authorization/API/transport
    ///   or schema failures later. This descriptor never iterates shards or pages automatically.
    public static func guilds(query: UserGuildsQuery? = nil,
                              readPolicy: ReadPolicy? = ReadPolicy()) throws -> Endpoint<Nullable<[UserGuild]>> {
        try Endpoint(method: "GET", path: ["users", "@me", "guilds"], query: query?.queryItems() ?? [],
            authentication: .botOrBearer, retrySafety: .safe,
            readPolicy: expressionReadPolicy(readPolicy, tags: ["guild-catalog", "user-guild-catalog"]),
            decode: { try userNullableArray($0) { try UserGuild(data: $0) } })
    }

    /// Gets the authenticated user's current member snapshot in one guild.
    /// - Parameters:
    ///   - guildID: Exact guild ID and major rate partition; no other member is queried.
    ///   - readPolicy: Optional scoped reuse; default coalesces without completed caching.
    /// - Returns: Safe bearer-only GET /users/@me/guilds/{guild.id}/member, requiring guilds.members.read.
    ///   Existing GuildMember projects related user data explicitly partially while retaining every raw key.
    /// - Throws: Descriptor/policy errors now; scope, membership, API, cancellation, transport or schema failures later.
    ///   No privileged Gateway intent, bot credential fallback or hidden membership hydration is used.
    public static func guildMember(guildID: GuildID,
                                   readPolicy: ReadPolicy? = ReadPolicy()) throws -> Endpoint<GuildMember> {
        try Endpoint(method: "GET", path: ["users", "@me", "guilds", guildID.description, "member"],
            route: "/users/@me/guilds/{guild.id}/member", authentication: .bearer, majorParameter: guildID.description,
            retrySafety: .safe, readPolicy: expressionReadPolicy(readPolicy, tags: guildTags(guildID)),
            decode: { try GuildMember(data: $0) })
    }

    /// Leaves one guild as the authenticated bot, without deleting the guild or operating on another member.
    /// - Parameter guildID: Exact guild to leave and major rate partition; Discord checks current ownership/state.
    /// - Returns: Unsafe bot-only DELETE /users/@me/guilds/{guild.id} requiring an empty 204 response,
    ///   invalidating guild/user-guild visibility. Discord emits Guild Delete and Guild Member Remove.
    /// - Throws: Descriptor errors now; API, cancellation, transport, malformed nonempty 204 or indeterminate outcome later.
    ///   The official preview permits bot authentication only; possession of an unrelated bearer token is insufficient.
    public static func leaveGuild(guildID: GuildID) throws -> Endpoint<EmptyResponse> {
        try Endpoint(method: "DELETE", path: ["users", "@me", "guilds", guildID.description],
            route: "/users/@me/guilds/{guild.id}", authentication: .bot, successStatuses: [204],
            majorParameter: guildID.description, invalidates: guildTags(guildID).union(["user-guild-catalog"]),
            decode: { try EmptyResponse(data: $0) })
    }

    /// Opens or reuses a single-recipient DM initiated by an authorized user interaction.
    /// - Parameter request: Exact recipient ID; no member enumeration, consent inference or automatic DM loop occurs.
    /// - Returns: Unsafe bot-only POST /users/@me/channels decoding a DM Channel (type 1) and invalidating
    ///   channel visibility. Discord returns an existing DM when present; aggressive creation can be blocked/rate limited.
    /// - Throws: Body/descriptor errors now; eligibility/API/transport/schema or indeterminate submission failures later.
    ///   There is no retry of ambiguous submissions and no automatically sent message after channel creation.
    public static func createDM(request: UserDMCreate) throws -> Endpoint<Channel> {
        try Endpoint(method: "POST", path: ["users", "@me", "channels"], authentication: .bot,
            body: try guildJSON(request.jsonValue()), invalidates: ["channel-catalog"], decode: { data in
                let channel = try Channel(data: data)
                guard channel.type.knownValue == .dm else { throw DiscordError.transport(.invalidResponse) }
                return channel
            })
    }

    /// Creates a legacy application-managed group DM for explicitly consented gdm.join participants.
    /// - Parameter request: Distinct participant OAuth2 access tokens and explicit nickname map; tokens stay in the body.
    /// - Returns: Unsafe bot-only POST /users/@me/channels decoding a group-DM Channel (type 3). The GameBridge
    ///   use case is deprecated, only ten active group DMs are permitted upstream, and success can emit Channel Create.
    /// - Throws: Body/descriptor errors now; eligibility/limit/API/transport/schema or indeterminate submission errors later.
    ///   No token exchange, participant invitation fan-out or active-channel counting request is performed.
    public static func createGroupDM(request: UserGroupDMCreate) throws -> Endpoint<Channel> {
        try Endpoint(method: "POST", path: ["users", "@me", "channels"], authentication: .bot,
            body: try guildJSON(request.jsonValue()), invalidates: ["channel-catalog"], decode: { data in
                let channel = try Channel(data: data)
                guard channel.type.knownValue == .groupDM else { throw DiscordError.transport(.invalidResponse) }
                return channel
            })
    }

    /// Lists the current user's visible external connections without provider token retrieval or hydration.
    /// - Parameter readPolicy: Optional scoped reuse; default coalescing with no completed caching. Positive TTL
    ///   explicitly permits stale private connection data until expiry; nil disables all reuse.
    /// - Returns: Safe bot-or-bearer GET /users/@me/connections. OAuth2 requires connections; bot support follows
    ///   the official preview overlay. Preview null is distinct from an empty list. Deprecated Riot and Battle.net
    ///   accounts are no longer returned; future service spellings remain raw, and no replacement is invented.
    /// - Throws: Descriptor/policy errors now; token scope/API, transport, cancellation or schema failures later.
    public static func connections(readPolicy: ReadPolicy? = ReadPolicy()) throws -> Endpoint<Nullable<[UserConnection]>> {
        try Endpoint(method: "GET", path: ["users", "@me", "connections"], authentication: .botOrBearer,
            retrySafety: .safe, readPolicy: expressionReadPolicy(readPolicy, tags: ["user-connection-catalog"]),
            decode: { try userNullableArray($0) { try UserConnection(data: $0) } })
    }

    /// Gets the caller's linked-role record for the application specified by the bearer token's scope grant.
    /// - Parameters:
    ///   - applicationID: Exact application ID; it is not a Discord major rate-limit parameter.
    ///   - readPolicy: Optional scoped reuse; default coalesces with no completed caching.
    /// - Returns: Safe bearer-only GET /users/@me/applications/{application.id}/role-connection, requiring
    ///   role_connections.write for that application. Optional preview properties preserve omission and explicit null.
    /// - Throws: Descriptor/policy errors now; wrong application/scope, API/transport/cancellation/schema failures later.
    ///   The record does not establish current guild-role eligibility and no role assignment is performed.
    public static func roleConnection(applicationID: ApplicationID,
                                      readPolicy: ReadPolicy? = ReadPolicy()) throws -> Endpoint<ApplicationRoleConnection> {
        try Endpoint(method: "GET", path: ["users", "@me", "applications", applicationID.description, "role-connection"],
            route: "/users/@me/applications/{application.id}/role-connection", authentication: .bearer,
            retrySafety: .safe, readPolicy: expressionReadPolicy(readPolicy, tags: ["user-role-connection-catalog"]),
            decode: { try ApplicationRoleConnection(data: $0) })
    }

    /// Updates the authenticated user's linked-role record, requiring application-specific role_connections.write consent.
    /// - Parameters:
    ///   - applicationID: Exact application selected by the caller; the server validates bearer-token ownership.
    ///   - request: Validated optional platform strings and at most five metadata values; absence and null remain distinct.
    /// - Returns: Unsafe bearer-only PUT returning ApplicationRoleConnection and invalidating caller-scoped linked-role reads.
    /// - Throws: Body/descriptor errors now; scope/API/transport/schema failures or indeterminate submission later.
    ///   No definition fetch, metadata-type guess, guild role assignment or hidden comparison occurs.
    public static func updateRoleConnection(applicationID: ApplicationID,
                                            request: ApplicationRoleConnectionUpdate) throws -> Endpoint<ApplicationRoleConnection> {
        try Endpoint(method: "PUT", path: ["users", "@me", "applications", applicationID.description, "role-connection"],
            route: "/users/@me/applications/{application.id}/role-connection", authentication: .bearer,
            body: try guildJSON(request.jsonValue()), invalidates: ["user-role-connection-catalog"],
            decode: { try ApplicationRoleConnection(data: $0) })
    }

    /// Deletes the current user's application role connection using application-specific role_connections.write consent.
    /// - Parameter applicationID: Exact application whose user connection is removed, never a bot-token fallback.
    /// - Returns: Unsafe bearer-only DELETE requiring empty HTTP 204 and invalidating linked-role snapshots.
    /// - Throws: Descriptor errors now; scope/API/transport/schema failures or indeterminate deletion later.
    ///   This operation is present in the current written User resource and official preview; no older omission is assumed.
    public static func deleteRoleConnection(applicationID: ApplicationID) throws -> Endpoint<EmptyResponse> {
        try Endpoint(method: "DELETE", path: ["users", "@me", "applications", applicationID.description, "role-connection"],
            route: "/users/@me/applications/{application.id}/role-connection", authentication: .bearer, successStatuses: [204],
            invalidates: ["user-role-connection-catalog"], decode: { try EmptyResponse(data: $0) })
    }
}

extension DiscordEndpoints {
    /// Preserves the original currentUser API while adopting the complete User projection and shared invalidation tags.
    /// - Parameter readPolicy: Optional scoped coalescing/freshness, default coalescing without completed caching.
    /// - Returns: The same safe bot-or-bearer GET descriptor as UserEndpoints.current, requiring identify for OAuth2.
    /// - Throws: Descriptor/policy validation errors now; ordinary API/transport/schema errors only upon execution.
    ///   Construction performs no I/O or credential inspection and does not open a Gateway connection.
    public static func currentUser(readPolicy: ReadPolicy? = ReadPolicy()) throws -> Endpoint<User> {
        try UserEndpoints.current(readPolicy: readPolicy)
    }
}

/// Decodes an official preview nullable array without treating explicit null as an empty collection.
/// - Parameters:
///   - data: Complete response bytes, parsed under standard whole-document JSON bounds.
///   - decode: Synchronous model decoder for each exact serialized original subtree, in wire order.
/// - Returns: Explicit null or a complete array, including empty; invalid elements never yield partial success.
/// - Throws: JSON bounds/syntax/model errors or sanitized invalid-response for any nonarray, nonnull root.
///   No I/O, suspension, cache access or hidden pagination occurs during decoding.
func userNullableArray<T: Sendable>(_ data: Data, decode: (Data) throws -> T) throws -> Nullable<[T]> {
    let value = try JSONValue.parse(data)
    if value == .null { return .null }
    guard case .array(let values) = value else { throw DiscordError.transport(.invalidResponse) }
    return .value(try values.map { try decode($0.serialized()) })
}
