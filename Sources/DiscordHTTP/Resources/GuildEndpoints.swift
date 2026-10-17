import DiscordCore
import DiscordModels
import DiscordTransport
import Foundation

/// API v10 Guild reference operations, verified 2026-10-16. Each descriptor adopts the shared
/// credential-scoped rate authority, finite retries, mutation ordering, cancellation and deadlines.
/// Mutations never replay ambiguous submissions. Reads coalesce by default; caching requires an
/// explicit positive TTL. Permissions, role hierarchy, intent approval and guild features remain
/// server-enforced; response snapshots never establish current authorization. No Gateway is required.
/// See https://docs.discord.com/developers/resources/guild.
public enum GuildEndpoints {
    /// Gets a guild snapshot. Counts are approximate and requested only through withCounts.
    /// - Parameters:
    ///   - guildID: Exact guild identifier and major rate partition.
    ///   - withCounts: Whether to include approximate membership/presence counts; default false.
    ///   - readPolicy: Scoped coalescing/freshness policy; nil disables reuse, default no completed caching.
    /// - Returns: A safe GET descriptor decoding the documented guild projection.
    /// - Throws: Descriptor errors now; API, transport or invalid-response errors during execution.
    public static func get(guildID: GuildID, withCounts: Bool = false,
                           readPolicy: ReadPolicy? = ReadPolicy()) throws -> Endpoint<Guild> {
        try guildRead(guildID, suffix: [], route: "/guilds/{guild.id}",
            query: [.init(name: "with_counts", value: String(withCounts))], readPolicy: readPolicy,
            decode: { try Guild(data: $0) })
    }

    /// Gets a discoverable guild preview without fetching its related resources.
    /// - Parameters:
    ///   - guildID: Exact guild and major rate partition; preview eligibility is server-checked.
    ///   - readPolicy: Optional scoped reuse; default coalesces without completed caching.
    /// - Returns: A safe GET descriptor preserving unknown guild-preview fields.
    /// - Throws: Descriptor errors; API/transport/schema failures during execution.
    public static func preview(guildID: GuildID, readPolicy: ReadPolicy? = ReadPolicy()) throws -> Endpoint<GuildPreview> {
        try guildRead(guildID, suffix: ["preview"], route: "/guilds/{guild.id}/preview", readPolicy: readPolicy,
            decode: { try GuildPreview(data: $0) })
    }

    /// Modifies guild settings with MANAGE_GUILD; changing COMMUNITY additionally requires ADMINISTRATOR.
    /// - Parameters:
    ///   - guildID: Target guild and major rate partition.
    ///   - request: Validated omission/null/value settings; no upstream feature entitlement is inferred.
    ///   - auditReason: Optional supported reason, at most 512 Unicode scalars.
    /// - Returns: An unsafe PATCH descriptor returning the updated guild and invalidating catalog snapshots.
    /// - Throws: Descriptor/audit errors now; API/transport or indeterminate mutation failures later.
    public static func modify(guildID: GuildID, request: GuildModify,
                              auditReason: String? = nil) throws -> Endpoint<Guild> {
        try guildMutation("PATCH", guildID, suffix: [], route: "/guilds/{guild.id}",
            payload: request.jsonValue(), auditReason: auditReason, decode: { try Guild(data: $0) })
    }

    /// Lists guild channels, excluding threads and channels Discord omits for visibility policy.
    /// - Parameters:
    ///   - guildID: Guild major rate partition; bot or eligible bearer authorization is accepted.
    ///   - readPolicy: Optional scoped reuse; default coalesces without completed caching.
    /// - Returns: A safe GET descriptor; empty arrays remain empty and no thread/member hydration occurs.
    /// - Throws: Descriptor errors; API/transport/schema failures during execution.
    public static func channels(guildID: GuildID, readPolicy: ReadPolicy? = ReadPolicy()) throws -> Endpoint<[Channel]> {
        try guildRead(guildID, suffix: ["channels"], route: "/guilds/{guild.id}/channels", authentication: .botOrBearer,
            readPolicy: readPolicy, decode: { try guildArray($0) { try Channel(data: $0) } })
    }

    /// Creates a type-aware guild channel with MANAGE_CHANNELS and overwrite grant eligibility.
    /// - Parameters:
    ///   - guildID: Guild major rate partition.
    ///   - request: Validated channel creation fields; guild boost limits remain server-enforced.
    ///   - auditReason: Optional supported reason, at most 512 Unicode scalars.
    /// - Returns: An unsafe POST descriptor requiring HTTP 201 with the created Channel.
    /// - Throws: Descriptor/audit errors; API/transport or uncertain mutation errors during execution.
    public static func createChannel(guildID: GuildID, request: GuildChannelCreate,
                                     auditReason: String? = nil) throws -> Endpoint<Channel> {
        try guildMutation("POST", guildID, suffix: ["channels"], route: "/guilds/{guild.id}/channels",
            payload: request.jsonValue(), auditReason: auditReason, successStatuses: [201], decode: { try Channel(data: $0) })
    }

    /// Reorders channels or moves one channel; MANAGE_CHANNELS and per-entry visibility rules apply.
    /// Parent moves additionally check destination authority; lockPermissions requires MANAGE_ROLES.
    /// - Parameters:
    ///   - guildID: Guild major rate partition.
    ///   - positions: Explicit array of 1...1,000 unique channel entries (local finite body policy).
    ///     At most one entry may supply parentID, including explicit null. No unrelated channel is fetched.
    /// - Returns: An unsafe PATCH descriptor requiring exactly empty HTTP 204 success.
    /// - Throws: Invalid duplicate/count/multiple-parent configuration or descriptor errors before I/O;
    ///   API/transport or uncertain mutation errors on execution. No audit header is documented for this route.
    public static func modifyChannelPositions(guildID: GuildID,
                                              positions: [GuildChannelPosition]) throws -> Endpoint<EmptyResponse> {
        guard (1...1_000).contains(positions.count), Set(positions.map(\.id)).count == positions.count,
              positions.filter({ if case .absent = $0.parentID { return false }; return true }).count <= 1
        else { throw DiscordError.validation(.invalidValue) }
        return try guildEmpty("PATCH", guildID, suffix: ["channels"], route: "/guilds/{guild.id}/channels",
            payload: .array(positions.map { $0.jsonValue() }))
    }

    /// Lists accessible active public/private threads, ordered by descending ID without pagination.
    /// - Parameters:
    ///   - guildID: Guild major rate partition.
    ///   - readPolicy: Optional scoped reuse; default coalesces without completed caching.
    /// - Returns: A safe GET descriptor retaining complete thread/member correlation.
    /// - Throws: Descriptor errors; API/transport/schema failures during execution.
    public static func activeThreads(guildID: GuildID, readPolicy: ReadPolicy? = ReadPolicy()) throws -> Endpoint<ActiveThreads> {
        try guildRead(guildID, suffix: ["threads", "active"], route: "/guilds/{guild.id}/threads/active",
            readPolicy: readPolicy, decode: { try ActiveThreads(data: $0) })
    }

    /// Gets one guild member; missing membership is a server 404 rather than an absent projection.
    /// - Parameters:
    ///   - guildID: Guild major rate partition.
    ///   - userID: Exact member user identifier.
    ///   - readPolicy: Optional scoped reuse; default coalesces without completed caching.
    /// - Returns: A safe GET descriptor preserving pending screening and unknown member fields.
    /// - Throws: Descriptor errors; API/transport/schema failures during execution.
    public static func member(guildID: GuildID, userID: UserID,
                              readPolicy: ReadPolicy? = ReadPolicy()) throws -> Endpoint<GuildMember> {
        try guildRead(guildID, suffix: ["members", userID.description], route: "/guilds/{guild.id}/members/{user.id}",
            readPolicy: readPolicy, decode: { try GuildMember(data: $0) })
    }

    /// Lists a single member page; this operation requires the application's GUILD_MEMBERS intent.
    /// - Parameters:
    ///   - guildID: Guild major rate partition.
    ///   - after: Optional exclusive user-ID cursor; omission uses Discord's zero starting point.
    ///   - limit: Optional 1...1,000 page limit; omission uses Discord's default of one.
    ///   - readPolicy: Optional scoped reuse; default coalesces without completed caching.
    /// - Returns: A safe GET descriptor, making one request without automatic member hydration.
    /// - Throws: Invalid page bounds or descriptor errors; API/transport/schema errors on execution.
    public static func members(guildID: GuildID, after: UserID? = nil, limit: Int? = nil,
                               readPolicy: ReadPolicy? = ReadPolicy()) throws -> Endpoint<[GuildMember]> {
        var query = try guildLimitQuery(limit)
        if let after { query.append(.init(name: "after", value: after.description)) }
        return try guildRead(guildID, suffix: ["members"], route: "/guilds/{guild.id}/members", query: query,
            readPolicy: readPolicy, decode: { try guildArray($0) { try GuildMember(data: $0) } })
    }

    /// Searches username/nickname prefixes; Discord publishes no continuation cursor for this route.
    /// - Parameters:
    ///   - guildID: Guild major rate partition.
    ///   - query: Exact prefix, including an empty string; descriptor metadata bounds apply.
    ///   - limit: Optional 1...1,000 result bound; omission uses Discord's default of one.
    ///   - readPolicy: Optional scoped reuse; query participates in the authentication-scoped key.
    /// - Returns: A safe GET descriptor returning one possibly truncated result array.
    /// - Throws: Invalid limit or descriptor bounds; API/transport/schema errors during execution.
    public static func searchMembers(guildID: GuildID, query: String, limit: Int? = nil,
                                     readPolicy: ReadPolicy? = ReadPolicy()) throws -> Endpoint<[GuildMember]> {
        try guildRead(guildID, suffix: ["members", "search"], route: "/guilds/{guild.id}/members/search",
            query: [.init(name: "query", value: query)] + guildLimitQuery(limit), readPolicy: readPolicy,
            decode: { try guildArray($0) { try GuildMember(data: $0) } })
    }

    /// Adds a user using their guilds.join OAuth grant; the outer credential is the same application's bot.
    /// The bot must be a member with CREATE_INSTANT_INVITE; optional settings need their own permissions.
    /// - Parameters:
    ///   - guildID: Target guild major rate partition.
    ///   - userID: User who granted the body token to the bot's application.
    ///   - request: Validated secret-bearing user grant and optional initial member settings.
    /// - Returns: An unsafe PUT descriptor accepting HTTP 201 member JSON or empty 204 (nil for existing membership).
    ///   The common decoder sees body bytes only and cannot associate each accepted shape with one status.
    /// - Throws: Descriptor errors; API/transport/schema or uncertain mutation failures on execution.
    public static func addMember(guildID: GuildID, userID: UserID,
                                 request: GuildMemberAdd) throws -> Endpoint<GuildMember?> {
        try guildMutation("PUT", guildID, suffix: ["members", userID.description], route: "/guilds/{guild.id}/members/{user.id}",
            payload: request.jsonValue(), successStatuses: [201, 204], decode: { $0.isEmpty ? nil : try GuildMember(data: $0) })
    }

    /// Changes one member's nickname, roles, voice state, flags or timeout using field-specific permissions.
    /// Moving requires CONNECT plus MOVE_MEMBERS; timeouts require MODERATE_MEMBERS and eligible hierarchy.
    /// - Parameters:
    ///   - guildID: Guild major rate partition.
    ///   - userID: Target member, without a preliminary fetch.
    ///   - request: Validated optional/nullable settings; state and hierarchy remain server-enforced.
    ///   - auditReason: Optional supported reason, at most 512 Unicode scalars.
    /// - Returns: An unsafe PATCH requiring written-reference HTTP 200 member JSON.
    /// - Throws: Descriptor/audit errors; API/transport/schema or uncertain mutation errors during execution.
    public static func modifyMember(guildID: GuildID, userID: UserID, request: GuildMemberModify,
                                    auditReason: String? = nil) throws -> Endpoint<GuildMember> {
        try guildMutation("PATCH", guildID, suffix: ["members", userID.description], route: "/guilds/{guild.id}/members/{user.id}",
            payload: request.jsonValue(), auditReason: auditReason, decode: { try GuildMember(data: $0) })
    }

    /// Changes the current bot member's profile; nickname changes require CHANGE_NICKNAME.
    /// - Parameters:
    ///   - guildID: Guild major rate partition.
    ///   - request: Validated nickname/banner/avatar/bio fields with explicit omission/null semantics.
    ///   - auditReason: Optional supported reason, at most 512 Unicode scalars.
    /// - Returns: An unsafe PATCH descriptor returning updated GuildMember JSON.
    /// - Throws: Descriptor/audit errors; API/transport/schema or uncertain mutation failures during execution.
    public static func modifyCurrentMember(guildID: GuildID, request: GuildCurrentMemberModify,
                                           auditReason: String? = nil) throws -> Endpoint<GuildMember> {
        try guildMutation("PATCH", guildID, suffix: ["members", "@me"], route: "/guilds/{guild.id}/members/@me",
            payload: request.jsonValue(), auditReason: auditReason, decode: { try GuildMember(data: $0) })
    }

    /// Changes the current nickname through the deprecated route; prefer modifyCurrentMember.
    /// - Parameters:
    ///   - guildID: Guild major rate partition; CHANGE_NICKNAME is required.
    ///   - request: Optional nullable nickname; omitted fields retain upstream behavior.
    ///   - auditReason: Optional supported reason, at most 512 Unicode scalars.
    /// - Returns: An unsafe PATCH descriptor decoding the legacy nickname envelope.
    /// - Throws: Descriptor/audit errors; API/transport/schema or uncertain mutation failures during execution.
    @available(*, deprecated, message: "Use modifyCurrentMember(guildID:request:auditReason:).")
    public static func modifyCurrentUserNick(guildID: GuildID, request: GuildCurrentUserNickModify,
                                             auditReason: String? = nil) throws -> Endpoint<GuildNickname> {
        try guildMutation("PATCH", guildID, suffix: ["members", "@me", "nick"], route: "/guilds/{guild.id}/members/@me/nick",
            payload: request.jsonValue(), auditReason: auditReason, decode: { try GuildNickname(data: $0) })
    }

    /// Adds one member role with MANAGE_ROLES and hierarchy eligibility, without replacing other roles.
    /// - Parameters:
    ///   - guildID: Guild major rate partition.
    ///   - userID: Target user identifier.
    ///   - roleID: Role to add, without a preliminary role/member fetch.
    ///   - auditReason: Optional supported reason, at most 512 Unicode scalars.
    /// - Returns: An unsafe PUT descriptor requiring empty HTTP 204 success.
    /// - Throws: Descriptor/audit errors; API/transport or uncertain mutation failures during execution.
    public static func addMemberRole(guildID: GuildID, userID: UserID, roleID: RoleID,
                                     auditReason: String? = nil) throws -> Endpoint<EmptyResponse> {
        try guildEmpty("PUT", guildID, suffix: ["members", userID.description, "roles", roleID.description],
            route: "/guilds/{guild.id}/members/{user.id}/roles/{role.id}", auditReason: auditReason)
    }

    /// Removes one member role with MANAGE_ROLES and hierarchy eligibility.
    /// - Parameters:
    ///   - guildID: Guild major rate partition.
    ///   - userID: Target user identifier.
    ///   - roleID: Role to remove, without replacing the remaining roles.
    ///   - auditReason: Optional supported reason, at most 512 Unicode scalars.
    /// - Returns: An unsafe DELETE descriptor requiring empty HTTP 204 success.
    /// - Throws: Descriptor/audit errors; API/transport or uncertain mutation failures during execution.
    public static func removeMemberRole(guildID: GuildID, userID: UserID, roleID: RoleID,
                                        auditReason: String? = nil) throws -> Endpoint<EmptyResponse> {
        try guildEmpty("DELETE", guildID, suffix: ["members", userID.description, "roles", roleID.description],
            route: "/guilds/{guild.id}/members/{user.id}/roles/{role.id}", auditReason: auditReason)
    }

    /// Removes one guild member with KICK_MEMBERS and eligible role hierarchy.
    /// - Parameters:
    ///   - guildID: Guild major rate partition.
    ///   - userID: Member to remove; no implicit ban is created.
    ///   - auditReason: Optional supported reason, at most 512 Unicode scalars.
    /// - Returns: An unsafe DELETE descriptor requiring empty HTTP 204 success.
    /// - Throws: Descriptor/audit errors; API/transport or uncertain mutation failures during execution.
    public static func removeMember(guildID: GuildID, userID: UserID,
                                    auditReason: String? = nil) throws -> Endpoint<EmptyResponse> {
        try guildEmpty("DELETE", guildID, suffix: ["members", userID.description],
            route: "/guilds/{guild.id}/members/{user.id}", auditReason: auditReason)
    }

    /// Lists one ascending user-ID ban page; BAN_MEMBERS or VIEW_AUDIT_LOG is required.
    /// - Parameters:
    ///   - guildID: Guild major rate partition.
    ///   - before: Optional exclusive upper user-ID boundary; Discord gives it precedence over after.
    ///   - after: Optional exclusive lower user-ID boundary, ignored upstream when before is supplied.
    ///   - limit: Optional 1...1,000 page limit; omission uses upstream default 1,000.
    ///   - readPolicy: Optional scoped reuse; default coalesces without completed caching.
    /// - Returns: One safe GET descriptor; no follow-up page or user hydration is started.
    /// - Throws: Invalid page bound or descriptor errors; API/transport/schema errors on execution.
    public static func bans(guildID: GuildID, before: UserID? = nil, after: UserID? = nil, limit: Int? = nil,
                            readPolicy: ReadPolicy? = ReadPolicy()) throws -> Endpoint<[GuildBan]> {
        var query = try guildLimitQuery(limit)
        if let before { query.append(.init(name: "before", value: before.description)) }
        if let after { query.append(.init(name: "after", value: after.description)) }
        return try guildRead(guildID, suffix: ["bans"], route: "/guilds/{guild.id}/bans", query: query,
            readPolicy: readPolicy, decode: { try guildArray($0) { try GuildBan(data: $0) } })
    }

    /// Gets one ban using BAN_MEMBERS or VIEW_AUDIT_LOG; an unbanned user produces an API 404.
    /// - Parameters:
    ///   - guildID: Guild major rate partition.
    ///   - userID: Exact banned user identifier.
    ///   - readPolicy: Optional scoped reuse; default coalesces without completed caching.
    /// - Returns: A safe GET descriptor retaining nullable reason and exact user data.
    /// - Throws: Descriptor errors; API/transport/schema failures during execution.
    public static func ban(guildID: GuildID, userID: UserID,
                           readPolicy: ReadPolicy? = ReadPolicy()) throws -> Endpoint<GuildBan> {
        try guildRead(guildID, suffix: ["bans", userID.description], route: "/guilds/{guild.id}/bans/{user.id}",
            readPolicy: readPolicy, decode: { try GuildBan(data: $0) })
    }

    /// Creates a ban with BAN_MEMBERS; optional history deletion remains explicit and irreversible upstream.
    /// - Parameters:
    ///   - guildID: Guild major rate partition.
    ///   - userID: User to ban, without a membership lookup.
    ///   - request: Validated deletion seconds or legacy days, both omitted by default.
    ///   - auditReason: Optional supported reason, at most 512 Unicode scalars.
    /// - Returns: An unsafe PUT descriptor requiring empty HTTP 204 success.
    /// - Throws: Descriptor/audit errors; API/transport or uncertain mutation failures during execution.
    public static func createBan(guildID: GuildID, userID: UserID, request: GuildBanCreate,
                                 auditReason: String? = nil) throws -> Endpoint<EmptyResponse> {
        try guildEmpty("PUT", guildID, suffix: ["bans", userID.description], route: "/guilds/{guild.id}/bans/{user.id}",
            payload: request.jsonValue(), auditReason: auditReason)
    }

    /// Removes one ban with BAN_MEMBERS; this operation does not automatically rejoin the user.
    /// - Parameters:
    ///   - guildID: Guild major rate partition.
    ///   - userID: Banned user to release.
    ///   - auditReason: Optional supported reason, at most 512 Unicode scalars.
    /// - Returns: An unsafe DELETE descriptor requiring empty HTTP 204 success.
    /// - Throws: Descriptor/audit errors; API/transport or uncertain mutation failures during execution.
    public static func removeBan(guildID: GuildID, userID: UserID,
                                 auditReason: String? = nil) throws -> Endpoint<EmptyResponse> {
        try guildEmpty("DELETE", guildID, suffix: ["bans", userID.description], route: "/guilds/{guild.id}/bans/{user.id}",
            auditReason: auditReason)
    }

    /// Executes Discord's documented bulk ban with BAN_MEMBERS plus MANAGE_GUILD.
    /// - Parameters:
    ///   - guildID: Guild major rate partition.
    ///   - request: Validated 1...200 distinct user IDs and optional deletion seconds.
    ///   - auditReason: Optional supported reason, at most 512 Unicode scalars.
    /// - Returns: One unsafe POST descriptor preserving banned/failed IDs; returned order is not promised.
    /// - Throws: Descriptor/audit errors; total failure API code 500000, ordinary API/transport errors,
    ///   or uncertain submission on execution. Failed users are never silently retried individually.
    public static func bulkBan(guildID: GuildID, request: GuildBulkBan,
                               auditReason: String? = nil) throws -> Endpoint<GuildBulkBanResult> {
        try guildMutation("POST", guildID, suffix: ["bulk-ban"], route: "/guilds/{guild.id}/bulk-ban",
            payload: request.jsonValue(), auditReason: auditReason,
            bulk: .init(maximumItems: 200, preservesOrder: false, permitsPartialResults: true,
                documentationURL: URL(string: "https://docs.discord.com/developers/resources/guild#bulk-guild-ban")!),
            decode: { try GuildBulkBanResult(data: $0) })
    }

    /// Lists all guild roles without fetching member assignments.
    /// - Parameters:
    ///   - guildID: Exact guild identifier and major rate partition.
    ///   - readPolicy: Scoped coalescing/freshness configuration; default no completed caching, nil disables reuse.
    /// - Returns: A safe GET descriptor preserving exact IDs and unknown fields; snapshots never prove authority.
    /// - Throws: Descriptor errors before I/O; API, transport and invalid-response failures during execution.
    public static func roles(guildID: GuildID, readPolicy: ReadPolicy? = ReadPolicy()) throws -> Endpoint<[GuildRole]> {
        try guildRead(guildID, suffix: ["roles"], route: "/guilds/{guild.id}/roles",
            readPolicy: readPolicy, decode: { try guildArray($0) { try GuildRole(data: $0) } })
    }

    /// Gets one role by its exact identifier; hierarchy is not inferred from its snapshot.
    /// - Parameters:
    ///   - guildID: Exact guild identifier and major rate partition.
    ///   - roleID: Exact role identifier; missing roles retain ordinary API failure semantics.
    ///   - readPolicy: Scoped coalescing/freshness configuration; default no completed caching, nil disables reuse.
    /// - Returns: A safe GET descriptor preserving exact IDs and unknown fields; snapshots never prove authority.
    /// - Throws: Descriptor errors before I/O; API, transport and invalid-response failures during execution.
    public static func role(guildID: GuildID, roleID: RoleID, readPolicy: ReadPolicy? = ReadPolicy()) throws -> Endpoint<GuildRole> {
        try guildRead(guildID, suffix: ["roles", roleID.description], route: "/guilds/{guild.id}/roles/{role.id}",
            readPolicy: readPolicy, decode: { try GuildRole(data: $0) })
    }

    /// Gets a role-ID to member-count map, excluding the everyone role.
    /// - Parameters:
    ///   - guildID: Exact guild identifier and major rate partition.
    ///   - readPolicy: Scoped coalescing/freshness configuration; default no completed caching, nil disables reuse.
    /// - Returns: A safe GET descriptor preserving exact IDs and unknown fields; snapshots never prove authority.
    /// - Throws: Descriptor errors before I/O; API, transport and invalid-response failures during execution.
    public static func roleMemberCounts(guildID: GuildID, readPolicy: ReadPolicy? = ReadPolicy()) throws -> Endpoint<GuildRoleMemberCounts> {
        try guildRead(guildID, suffix: ["roles", "member-counts"], route: "/guilds/{guild.id}/roles/member-counts",
            readPolicy: readPolicy, decode: { try GuildRoleMemberCounts(data: $0) })
    }

    /// Lists guild voice regions, including VIP regions for eligible guilds.
    /// - Parameters:
    ///   - guildID: Exact guild identifier and major rate partition.
    ///   - readPolicy: Scoped coalescing/freshness configuration; default no completed caching, nil disables reuse.
    /// - Returns: A safe GET descriptor preserving exact IDs and unknown fields; snapshots never prove authority.
    /// - Throws: Descriptor errors before I/O; API, transport and invalid-response failures during execution.
    public static func voiceRegions(guildID: GuildID, readPolicy: ReadPolicy? = ReadPolicy()) throws -> Endpoint<[GuildVoiceRegion]> {
        try guildRead(guildID, suffix: ["regions"], route: "/guilds/{guild.id}/regions",
            readPolicy: readPolicy, decode: { try guildArray($0) { try GuildVoiceRegion(data: $0) } })
    }

    /// Lists guild invites with MANAGE_GUILD or VIEW_AUDIT_LOG. Metadata is included only with MANAGE_GUILD.
    /// - Parameters:
    ///   - guildID: Exact guild identifier and major rate partition.
    ///   - readPolicy: Scoped coalescing/freshness configuration; default no completed caching, nil disables reuse.
    /// - Returns: A safe GET descriptor preserving exact IDs and unknown fields; snapshots never prove authority.
    /// - Throws: Descriptor errors before I/O; API, transport and invalid-response failures during execution.
    public static func invites(guildID: GuildID, readPolicy: ReadPolicy? = ReadPolicy()) throws -> Endpoint<[ChannelInvite]> {
        try guildRead(guildID, suffix: ["invites"], route: "/guilds/{guild.id}/invites",
            readPolicy: readPolicy, decode: { try guildArray($0) { try ChannelInvite(data: $0) } })
    }

    /// Lists at most 50 guild integrations with MANAGE_GUILD. Discord publishes no continuation for additional integrations.
    /// - Parameters:
    ///   - guildID: Exact guild identifier and major rate partition.
    ///   - readPolicy: Scoped coalescing/freshness configuration; default no completed caching, nil disables reuse.
    /// - Returns: A safe GET descriptor preserving exact IDs and unknown fields; snapshots never prove authority.
    /// - Throws: Descriptor errors before I/O; API, transport and invalid-response failures during execution.
    public static func integrations(guildID: GuildID, readPolicy: ReadPolicy? = ReadPolicy()) throws -> Endpoint<[GuildIntegration]> {
        try guildRead(guildID, suffix: ["integrations"], route: "/guilds/{guild.id}/integrations",
            readPolicy: readPolicy, decode: { try guildArray($0) { try GuildIntegration(data: $0) } })
    }

    /// Gets private widget configuration with MANAGE_GUILD.
    /// - Parameters:
    ///   - guildID: Exact guild identifier and major rate partition.
    ///   - readPolicy: Scoped coalescing/freshness configuration; default no completed caching, nil disables reuse.
    /// - Returns: A safe GET descriptor preserving exact IDs and unknown fields; snapshots never prove authority.
    /// - Throws: Descriptor errors before I/O; API, transport and invalid-response failures during execution.
    public static func widgetSettings(guildID: GuildID, readPolicy: ReadPolicy? = ReadPolicy()) throws -> Endpoint<GuildWidgetSettings> {
        try guildRead(guildID, suffix: ["widget"], route: "/guilds/{guild.id}/widget",
            readPolicy: readPolicy, decode: { try GuildWidgetSettings(data: $0) })
    }

    /// Gets the public widget with anonymous member identifiers. Discord may create an invite for its configured channel.
    /// - Parameters:
    ///   - guildID: Exact guild identifier and major rate partition.
    ///   - readPolicy: Scoped coalescing/freshness configuration; default no completed caching, nil disables reuse.
    /// - Returns: A safe GET descriptor preserving exact IDs and unknown fields; snapshots never prove authority.
    /// - Throws: Descriptor errors before I/O; API, transport and invalid-response failures during execution.
    public static func widget(guildID: GuildID, readPolicy: ReadPolicy? = ReadPolicy()) throws -> Endpoint<GuildWidget> {
        try guildRead(guildID, suffix: ["widget.json"], route: "/guilds/{guild.id}/widget.json", authentication: .none,
            readPolicy: readPolicy, decode: { try GuildWidget(data: $0) })
    }

    /// Gets nullable vanity invite code and usage count with MANAGE_GUILD.
    /// - Parameters:
    ///   - guildID: Exact guild identifier and major rate partition.
    ///   - readPolicy: Scoped coalescing/freshness configuration; default no completed caching, nil disables reuse.
    /// - Returns: A safe GET descriptor preserving exact IDs and unknown fields; snapshots never prove authority.
    /// - Throws: Descriptor errors before I/O; API, transport and invalid-response failures during execution.
    public static func vanityURL(guildID: GuildID, readPolicy: ReadPolicy? = ReadPolicy()) throws -> Endpoint<GuildVanityURL> {
        try guildRead(guildID, suffix: ["vanity-url"], route: "/guilds/{guild.id}/vanity-url",
            readPolicy: readPolicy, decode: { try GuildVanityURL(data: $0) })
    }

    /// Gets the welcome screen; MANAGE_GUILD is required when the screen is disabled.
    /// - Parameters:
    ///   - guildID: Exact guild identifier and major rate partition.
    ///   - readPolicy: Scoped coalescing/freshness configuration; default no completed caching, nil disables reuse.
    /// - Returns: A safe GET descriptor preserving exact IDs and unknown fields; snapshots never prove authority.
    /// - Throws: Descriptor errors before I/O; API, transport and invalid-response failures during execution.
    public static func welcomeScreen(guildID: GuildID, readPolicy: ReadPolicy? = ReadPolicy()) throws -> Endpoint<GuildWelcomeScreen> {
        try guildRead(guildID, suffix: ["welcome-screen"], route: "/guilds/{guild.id}/welcome-screen",
            readPolicy: readPolicy, decode: { try GuildWelcomeScreen(data: $0) })
    }

    /// Gets the guild onboarding configuration without hydrating selected channels or roles.
    /// - Parameters:
    ///   - guildID: Exact guild identifier and major rate partition.
    ///   - readPolicy: Scoped coalescing/freshness configuration; default no completed caching, nil disables reuse.
    /// - Returns: A safe GET descriptor preserving exact IDs and unknown fields; snapshots never prove authority.
    /// - Throws: Descriptor errors before I/O; API, transport and invalid-response failures during execution.
    public static func onboarding(guildID: GuildID, readPolicy: ReadPolicy? = ReadPolicy()) throws -> Endpoint<GuildOnboarding> {
        try guildRead(guildID, suffix: ["onboarding"], route: "/guilds/{guild.id}/onboarding",
            readPolicy: readPolicy, decode: { try GuildOnboarding(data: $0) })
    }

    /// Creates a role with MANAGE_ROLES; role icon and enhanced color features remain server-enforced.
    /// - Parameters:
    ///   - guildID: Exact target guild identifier and major rate partition.
    ///   - request: Validated explicit request; absent fields retain upstream state and nulls clear only where allowed.
    ///   - auditReason: Optional supported reason, at most 512 Unicode scalars.
    /// - Returns: An unsafe POST descriptor returning HTTP 200 JSON and invalidating scoped catalog snapshots.
    /// - Throws: Descriptor or audit errors before I/O; API/transport/schema or uncertain mutation failures on execution.
    public static func createRole(guildID: GuildID, request: GuildRoleCreate, auditReason: String? = nil) throws -> Endpoint<GuildRole> {
        try guildMutation("POST", guildID, suffix: ["roles"], route: "/guilds/{guild.id}/roles",
            payload: request.jsonValue(), auditReason: auditReason, decode: { try GuildRole(data: $0) })
    }

    /// Changes role settings with MANAGE_ROLES and hierarchy eligibility; every setting is optional and nullable.
    /// - Parameters:
    ///   - guildID: Exact target guild identifier and major rate partition.
    ///   - roleID: Target role identifier; no preliminary role/member fetch occurs.
    ///   - request: Validated explicit request; absent fields retain upstream state and nulls clear only where allowed.
    ///   - auditReason: Optional supported reason, at most 512 Unicode scalars.
    /// - Returns: An unsafe PATCH descriptor returning HTTP 200 JSON and invalidating scoped catalog snapshots.
    /// - Throws: Descriptor or audit errors before I/O; API/transport/schema or uncertain mutation failures on execution.
    public static func modifyRole(guildID: GuildID, roleID: RoleID, request: GuildRoleModify, auditReason: String? = nil) throws -> Endpoint<GuildRole> {
        try guildMutation("PATCH", guildID, suffix: ["roles", roleID.description], route: "/guilds/{guild.id}/roles/{role.id}",
            payload: request.jsonValue(), auditReason: auditReason, decode: { try GuildRole(data: $0) })
    }

    /// Changes public-widget configuration with MANAGE_GUILD; no widget or invite is fetched locally.
    /// - Parameters:
    ///   - guildID: Exact target guild identifier and major rate partition.
    ///   - request: Validated explicit request; absent fields retain upstream state and nulls clear only where allowed.
    ///   - auditReason: Optional supported reason, at most 512 Unicode scalars.
    /// - Returns: An unsafe PATCH descriptor returning HTTP 200 JSON and invalidating scoped catalog snapshots.
    /// - Throws: Descriptor or audit errors before I/O; API/transport/schema or uncertain mutation failures on execution.
    public static func modifyWidget(guildID: GuildID, request: GuildWidgetModify, auditReason: String? = nil) throws -> Endpoint<GuildWidgetSettings> {
        try guildMutation("PATCH", guildID, suffix: ["widget"], route: "/guilds/{guild.id}/widget",
            payload: request.jsonValue(), auditReason: auditReason, decode: { try GuildWidgetSettings(data: $0) })
    }

    /// Changes the guild welcome screen with MANAGE_GUILD; optional nulls retain their documented wire meaning.
    /// - Parameters:
    ///   - guildID: Exact target guild identifier and major rate partition.
    ///   - request: Validated explicit request; absent fields retain upstream state and nulls clear only where allowed.
    ///   - auditReason: Optional supported reason, at most 512 Unicode scalars.
    /// - Returns: An unsafe PATCH descriptor returning HTTP 200 JSON and invalidating scoped catalog snapshots.
    /// - Throws: Descriptor or audit errors before I/O; API/transport/schema or uncertain mutation failures on execution.
    public static func modifyWelcomeScreen(guildID: GuildID, request: GuildWelcomeScreenModify, auditReason: String? = nil) throws -> Endpoint<GuildWelcomeScreen> {
        try guildMutation("PATCH", guildID, suffix: ["welcome-screen"], route: "/guilds/{guild.id}/welcome-screen",
            payload: request.jsonValue(), auditReason: auditReason, decode: { try GuildWelcomeScreen(data: $0) })
    }

    /// Changes onboarding with MANAGE_GUILD plus MANAGE_ROLES; effective-channel eligibility remains server-enforced.
    /// - Parameters:
    ///   - guildID: Exact target guild identifier and major rate partition.
    ///   - request: Validated explicit request; absent fields retain upstream state and nulls clear only where allowed.
    ///   - auditReason: Optional supported reason, at most 512 Unicode scalars.
    /// - Returns: An unsafe PUT descriptor returning HTTP 200 JSON and invalidating scoped catalog snapshots.
    /// - Throws: Descriptor or audit errors before I/O; API/transport/schema or uncertain mutation failures on execution.
    public static func modifyOnboarding(guildID: GuildID, request: GuildOnboardingModify, auditReason: String? = nil) throws -> Endpoint<GuildOnboarding> {
        try guildMutation("PUT", guildID, suffix: ["onboarding"], route: "/guilds/{guild.id}/onboarding",
            payload: request.jsonValue(), auditReason: auditReason, decode: { try GuildOnboarding(data: $0) })
    }

    /// Changes invite/DM incident mitigation with MANAGE_GUILD; timestamps are bounded by the validated request.
    /// - Parameters:
    ///   - guildID: Exact target guild identifier and major rate partition.
    ///   - request: Validated explicit request; absent fields retain upstream state and nulls clear only where allowed.
    /// - Returns: An unsafe PUT descriptor returning HTTP 200 JSON and invalidating scoped catalog snapshots.
    /// - Throws: Descriptor or audit errors before I/O; API/transport/schema or uncertain mutation failures on execution.
    public static func modifyIncidentActions(guildID: GuildID, request: GuildIncidentActionsModify) throws -> Endpoint<GuildIncidentsData> {
        try guildMutation("PUT", guildID, suffix: ["incident-actions"], route: "/guilds/{guild.id}/incident-actions",
            payload: request.jsonValue(), decode: { try GuildIncidentsData(data: $0) })
    }

    /// Reorders guild roles with MANAGE_ROLES and role-hierarchy eligibility.
    /// - Parameters:
    ///   - guildID: Guild major rate partition.
    ///   - positions: Explicit 1...1,000 unique role entries (local finite body policy); null positions are retained.
    ///   - auditReason: Optional supported reason, at most 512 Unicode scalars.
    /// - Returns: An unsafe PATCH descriptor returning the complete updated role array in HTTP 200.
    /// - Throws: Duplicate IDs, invalid local count or descriptor/audit errors; API/transport/schema or uncertain submission later.
    public static func modifyRolePositions(guildID: GuildID, positions: [GuildRolePosition],
                                            auditReason: String? = nil) throws -> Endpoint<[GuildRole]> {
        guard (1...1_000).contains(positions.count), Set(positions.map(\.id)).count == positions.count
        else { throw DiscordError.validation(.invalidValue) }
        return try guildMutation("PATCH", guildID, suffix: ["roles"], route: "/guilds/{guild.id}/roles",
            payload: .array(positions.map { $0.jsonValue() }), auditReason: auditReason,
            decode: { try guildArray($0) { try GuildRole(data: $0) } })
    }

    /// Deletes one role with MANAGE_ROLES and eligible hierarchy; upstream member assignments change too.
    /// - Parameters:
    ///   - guildID: Guild major rate partition.
    ///   - roleID: Exact role to remove, without a preliminary read.
    ///   - auditReason: Optional supported reason, at most 512 Unicode scalars.
    /// - Returns: An unsafe DELETE descriptor requiring empty HTTP 204 success.
    /// - Throws: Descriptor/audit errors; API/transport or uncertain mutation failures during execution.
    public static func deleteRole(guildID: GuildID, roleID: RoleID,
                                   auditReason: String? = nil) throws -> Endpoint<EmptyResponse> {
        try guildEmpty("DELETE", guildID, suffix: ["roles", roleID.description],
            route: "/guilds/{guild.id}/roles/{role.id}", auditReason: auditReason)
    }

    /// Counts inactive members eligible for pruning. Requires MANAGE_GUILD plus KICK_MEMBERS,
    /// or ADMINISTRATOR when the guild has PRUNE_REQUIRES_ADMIN. No deletion occurs here.
    /// - Parameters:
    ///   - guildID: Guild major rate partition.
    ///   - days: Optional inactivity window, 1...30 days; omission uses upstream seven days.
    ///   - includeRoles: At most 100 unique role IDs, comma-delimited in the query;
    ///     empty omits the filter. Members with additional roles are excluded by Discord.
    ///   - readPolicy: Optional scoped reuse; default coalesces without completed caching.
    /// - Returns: A safe GET descriptor returning the nullable pruned count envelope.
    /// - Throws: Invalid window/role count/duplicates or descriptor errors; API/transport/schema errors on execution.
    public static func pruneCount(guildID: GuildID, days: Int? = nil, includeRoles: [RoleID] = [],
                                  readPolicy: ReadPolicy? = ReadPolicy()) throws -> Endpoint<GuildPruneCount> {
        guard days.map({ (1...30).contains($0) }) ?? true,
              includeRoles.count <= 100, Set(includeRoles).count == includeRoles.count
        else { throw DiscordError.validation(.invalidValue) }
        var query: [QueryItem] = []
        if let days { query.append(.init(name: "days", value: String(days))) }
        if !includeRoles.isEmpty { query.append(.init(name: "include_roles", value: includeRoles.map(\.description).joined(separator: ","))) }
        return try guildRead(guildID, suffix: ["prune"], route: "/guilds/{guild.id}/prune", query: query,
            readPolicy: readPolicy, decode: { try GuildPruneCount(data: $0) })
    }

    /// Begins an explicit member prune; permissions match pruneCount and server role eligibility is authoritative.
    /// - Parameters:
    ///   - guildID: Guild major rate partition.
    ///   - request: Validated days, optional role filter and compute-count choice; false can return null count.
    ///   - auditReason: Optional supported reason, at most 512 Unicode scalars; prefer this over legacy body reason.
    /// - Returns: An unsafe POST descriptor returning the nullable count without polling or member fan-out.
    /// - Throws: Descriptor/audit errors; API/transport/schema or uncertain mutation failures during execution.
    public static func beginPrune(guildID: GuildID, request: GuildPrune,
                                  auditReason: String? = nil) throws -> Endpoint<GuildPruneCount> {
        try guildMutation("POST", guildID, suffix: ["prune"], route: "/guilds/{guild.id}/prune",
            payload: request.jsonValue(), auditReason: auditReason, decode: { try GuildPruneCount(data: $0) })
    }

    /// Deletes an integration with MANAGE_GUILD; Discord also deletes associated webhooks and kicks its bot.
    /// - Parameters:
    ///   - guildID: Guild major rate partition.
    ///   - integrationID: Exact integration identifier, without an integration-list request.
    ///   - auditReason: Optional supported reason, at most 512 Unicode scalars.
    /// - Returns: An unsafe DELETE descriptor requiring empty HTTP 204 success.
    /// - Throws: Descriptor/audit errors; API/transport or uncertain mutation failures during execution.
    public static func deleteIntegration(guildID: GuildID, integrationID: GuildIntegrationID,
                                          auditReason: String? = nil) throws -> Endpoint<EmptyResponse> {
        try guildEmpty("DELETE", guildID, suffix: ["integrations", integrationID.description],
            route: "/guilds/{guild.id}/integrations/{integration.id}", auditReason: auditReason)
    }

    /// Gets a public PNG widget without sending authorization or following asset redirects.
    /// - Parameters:
    ///   - guildID: Guild major rate partition; no permissions or authentication are required.
    ///   - style: Documented image layout; default shield.
    ///   - readPolicy: Optional scoped reuse; default coalesces without completed caching.
    /// - Returns: A safe GET descriptor returning nonempty bytes with the PNG signature. The client's
    ///   maximumResponseBytes caps collection (default 8 MiB); this is not a full image decoder.
    /// - Throws: Descriptor errors; API/transport failure, empty or non-PNG signature response during execution.
    public static func widgetImage(guildID: GuildID, style: GuildWidgetImageStyle = .shield,
                                   readPolicy: ReadPolicy? = ReadPolicy()) throws -> Endpoint<Data> {
        try guildRead(guildID, suffix: ["widget.png"], route: "/guilds/{guild.id}/widget.png",
            query: [.init(name: "style", value: style.rawValue)], authentication: .none, readPolicy: readPolicy,
            decode: { bytes in
                guard bytes.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]), bytes.count > 8
                else { throw DiscordError.transport(.invalidResponse) }
                return bytes
            })
    }
}

/// Serializes already-validated guild request JSON with exact numeric spellings and bounded bytes.
/// - Parameter value: Explicit semantic payload; response models are never implicitly sent as requests.
/// - Returns: A materialized JSON body bounded by the default 1 MiB JSON serialization limit
///   and the existing 8 MiB request-body cap; the tighter JSON bound applies here.
/// - Throws: JSON/body serialization or limit errors before any I/O or resource acquisition.
func guildJSON(_ value: JSONValue) throws -> RequestBody {
    try RequestBody(bytes: value.serialized(), contentType: "application/json")
}

/// Derives conservative invalidation for guild visibility, roles, member state and related resources.
/// - Parameter guildID: Direct target whose named tag supplements the shared catalogs.
/// - Returns: Authentication-scoped guild/channel/message/search tags; no cross-identity cache is affected.
///   Catalog invalidation trades hit rate for correctness where related channel IDs are unavailable.
func guildTags(_ guildID: GuildID) -> Set<String> {
    ["guild-catalog", "guild:\(guildID)", "channel-catalog", "message-search", "message-catalog"]
}

/// Adds guild catalog invalidation while retaining caller freshness and coalescing choices.
/// - Parameter policy: Optional reuse configuration; nil disables all reuse.
/// - Returns: The supplied choices with guild/channel catalog tags; no caching is enabled implicitly.
func guildReadPolicy(_ policy: ReadPolicy?) -> ReadPolicy? {
    policy.map { ReadPolicy(coalescing: $0.coalescing, timeToLive: $0.timeToLive,
        tags: $0.tags.union(["guild-catalog", "channel-catalog"])) }
}

/// Constructs one safe guild GET using exact route segments and the shared scoped read policy.
/// - Parameters:
///   - guildID: Exact guild major rate partition.
///   - suffix: Unescaped relative route segments after guilds/guildID.
///   - route: Stable normalized route used by credential-sharing admission.
///   - query: Ordered raw query fields, default empty; the descriptor validates finite metadata bounds.
///   - authentication: Outer credential contract, default bot; public widgets explicitly select none.
///   - readPolicy: Explicit optional scoped coalescing/freshness policy.
///   - decode: Complete bounded response decoder, retaining operation-specific empty/shape semantics.
/// - Returns: One safe descriptor; no network call, background task or follow-up request begins.
/// - Throws: Descriptor metadata/policy validation errors; decode/API failures occur only during execution.
func guildRead<T: Sendable>(_ guildID: GuildID, suffix: [String], route: String, query: [QueryItem] = [],
                           authentication: AuthenticationPolicy = .bot, readPolicy: ReadPolicy?,
                           decode: @escaping @Sendable (Data) throws -> T) throws -> Endpoint<T> {
    try Endpoint(method: "GET", path: ["guilds", guildID.description] + suffix, route: route,
        query: query, authentication: authentication, majorParameter: guildID.description,
        retrySafety: .safe, readPolicy: guildReadPolicy(readPolicy), decode: decode)
}

/// Constructs one unsafe guild mutation with conservative related-resource invalidation.
/// - Parameters:
///   - method: Explicit POST, PATCH, PUT or DELETE HTTP method.
///   - guildID: Guild major rate partition.
///   - suffix: Raw route segments after guilds/guildID.
///   - route: Stable normalized admission route.
///   - payload: Optional validated semantic JSON; nil sends no body.
///   - auditReason: Optional supported reason, at most 512 Unicode scalars; default nil.
///   - successStatuses: Exact accepted success statuses; default 200.
///   - bulk: Optional documented bulk contract; default nil, never automatically combines operations.
///   - decode: Complete bounded response decoder specific to the endpoint.
/// - Returns: One unsafe descriptor; mutation ordering/retry/cancellation is applied at execution.
/// - Throws: JSON/body/descriptor/audit validation errors before I/O; API/transport or uncertain outcomes later.
func guildMutation<T: Sendable>(_ method: String, _ guildID: GuildID, suffix: [String], route: String,
                               payload: JSONValue? = nil, auditReason: String? = nil,
                               successStatuses: Set<Int> = [200], bulk: BulkOperationMetadata? = nil,
                               decode: @escaping @Sendable (Data) throws -> T) throws -> Endpoint<T> {
    try Endpoint(method: method, path: ["guilds", guildID.description] + suffix, route: route,
        authentication: .bot, successStatuses: successStatuses, majorParameter: guildID.description,
        auditReason: auditReason, body: payload.map { try guildJSON($0) }, invalidates: guildTags(guildID),
        bulk: bulk, decode: decode)
}

/// Constructs a guild mutation with exact empty HTTP 204 semantics.
/// - Parameters:
///   - method: Explicit PATCH, PUT or DELETE method.
///   - guildID: Guild major rate partition.
///   - suffix: Raw route segments following guilds/guildID.
///   - route: Stable normalized admission route.
///   - payload: Optional validated JSON; nil sends no body.
///   - auditReason: Optional supported reason, at most 512 Unicode scalars.
/// - Returns: One unsafe descriptor requiring no response bytes; no I/O happens at construction.
/// - Throws: Body/descriptor/audit validation errors; API/transport or uncertain mutation failures later.
func guildEmpty(_ method: String, _ guildID: GuildID, suffix: [String], route: String,
                payload: JSONValue? = nil, auditReason: String? = nil) throws -> Endpoint<EmptyResponse> {
    try guildMutation(method, guildID, suffix: suffix, route: route, payload: payload,
        auditReason: auditReason, successStatuses: [204], decode: { try EmptyResponse(data: $0) })
}

/// Decodes a bounded JSON collection while preserving numeric spellings for each model decoder.
/// - Parameters:
///   - data: Complete response bytes, bounded first by the REST client and then JSONValue's parser.
///   - decode: Model decoder for each item, preserving the original array order.
/// - Returns: Typed items, including an empty array when the server returns one.
/// - Throws: JSON/model errors or invalid-response for a nonarray envelope; no partial array escapes.
func guildArray<T: Sendable>(_ data: Data, decode: (Data) throws -> T) throws -> [T] {
    guard case .array(let values) = try JSONValue.parse(data) else { throw DiscordError.transport(.invalidResponse) }
    return try values.map { try decode($0.serialized()) }
}

/// Validates optional guild pagination limits without adding a default the caller did not request.
/// - Parameter limit: Optional positive result count through 1,000; nil preserves server defaults.
/// - Returns: An empty query or one exact decimal limit field.
/// - Throws: Safe invalid-value for zero, negative or excessive limits before I/O.
func guildLimitQuery(_ limit: Int?) throws -> [QueryItem] {
    guard let limit else { return [] }
    guard (1...1_000).contains(limit) else { throw DiscordError.validation(.invalidValue) }
    return [.init(name: "limit", value: String(limit))]
}
