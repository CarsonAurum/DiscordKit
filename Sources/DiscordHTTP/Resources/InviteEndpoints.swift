import DiscordCore
import DiscordModels
import Foundation

/// Complete public Invite REST operation catalog, API v10 verified 2026-10-16 against
/// https://docs.discord.com/developers/resources/invite and the official discord-api-spec.
/// All operations use the shared credential/rate authority. Invite codes remain redacted in diagnostics;
/// invite IDs do not create undocumented major-rate partitions. No operation hydrates related resources.
public enum InviteEndpoints {
    /// Resolves an invite in one request, optionally including approximate counts and a scheduled event.
    /// - Parameters:
    ///   - code: Exact opaque invite code, validated as one safe path segment.
    ///   - withCounts: Optional explicit count request; nil leaves it omitted and false is preserved.
    ///   - guildScheduledEventID: Optional scheduled event to include; invalid relations remain API errors.
    ///   - targetChannelID: Optional preview-schema target channel; nil omits it.
    ///   - targetMessageID: Optional preview-schema target message; nil omits it.
    ///   - authenticated: False uses the public operation without credentials; true requires a bot token.
    ///   - readPolicy: Optional scoped eligible-read reuse; default coalesces without completed caching.
    /// - Returns: Safe HTTP 200 GET; absent/expired codes remain ordinary API failures.
    /// - Throws: Descriptor validation errors before I/O; API/transport/schema failures during execution.
    /// Reuse retains complete query/authentication identity and never establishes current acceptance eligibility.
    public static func get(code: String, withCounts: Bool? = nil, guildScheduledEventID: GuildScheduledEventID? = nil,
                           targetChannelID: ChannelID? = nil, targetMessageID: MessageID? = nil,
                           authenticated: Bool = false, readPolicy: ReadPolicy? = ReadPolicy()) throws -> Endpoint<ChannelInvite> {
        var query: [QueryItem] = []
        if let withCounts { query.append(QueryItem(name: "with_counts", value: withCounts ? "true" : "false")) }
        if let guildScheduledEventID { query.append(QueryItem(name: "guild_scheduled_event_id", value: guildScheduledEventID.description)) }
        if let targetChannelID { query.append(QueryItem(name: "target_channel_id", value: targetChannelID.description)) }
        if let targetMessageID { query.append(QueryItem(name: "target_message_id", value: targetMessageID.description)) }
        return try Endpoint(method: "GET", path: ["invites", code], route: "/invites/{code}", query: query,
            authentication: authenticated ? .bot : .none, retrySafety: .safe,
            readPolicy: inviteReadPolicy(readPolicy), decode: { try ChannelInvite(data: $0) })
    }

    /// Revokes one invite with MANAGE_CHANNELS on its channel or MANAGE_GUILD across its guild.
    /// - Parameters:
    ///   - code: Exact opaque invite code; Discord checks current authority and existence.
    ///   - auditReason: Optional supported audit reason, at most 512 Unicode scalars before encoding.
    /// - Returns: Unsafe HTTP 200 DELETE with the revoked invite; emits Invite Delete upstream.
    /// - Throws: Descriptor/audit validation errors now; API, transport, schema or uncertain mutation outcomes later.
    /// Successful deletion invalidates scoped invite/channel/guild/audit reads; ambiguous sends never replay automatically.
    public static func delete(code: String, auditReason: String? = nil) throws -> Endpoint<ChannelInvite> {
        try Endpoint(method: "DELETE", path: ["invites", code], route: "/invites/{code}", authentication: .bot,
            auditReason: auditReason, invalidates: inviteTags, decode: { try ChannelInvite(data: $0) })
    }

    /// Exports the acceptance allowlist as bounded validated CSV, including its documented user_id header.
    /// - Parameters:
    ///   - code: Exact invite whose inviter, MANAGE_GUILD or VIEW_AUDIT_LOG authority Discord checks.
    ///   - maximumBytes: Local complete-response cap, 1...8 MiB, default 1 MiB; client transport caps also apply.
    ///   - maximumUsers: Local decoded-ID cap, 1...1,000,000, default 100,000; no upstream row limit is inferred.
    ///   - readPolicy: Optional scoped reuse, default coalescing only; bounds participate in wrapper identity
    ///     through disabled reuse below when they differ from defaults, preventing permissive-decoder sharing.
    /// - Returns: Safe HTTP 200 GET with exact original bytes and user IDs in wire order, including duplicates.
    /// - Throws: Invalid bounds/descriptor errors now; malformed header/rows, overflow/byte/item bounds,
    ///   API/authentication/permission or transport failures during execution. No per-user reads occur.
    public static func targetUsers(code: String, maximumBytes: Int = 1_048_576, maximumUsers: Int = 100_000,
                                   readPolicy: ReadPolicy? = ReadPolicy()) throws -> Endpoint<InviteTargetUsersCSV> {
        try inviteCSVConfiguration(maximumBytes: maximumBytes, maximumUsers: maximumUsers)
        return try Endpoint(method: "GET", path: ["invites", code, "target-users"], route: "/invites/{code}/target-users",
            authentication: .bot, retrySafety: .safe,
            readPolicy: maximumBytes == 1_048_576 && maximumUsers == 100_000 ? inviteReadPolicy(readPolicy) : nil,
            decode: { try InviteTargetUsersCSV(data: $0, maximumBytes: maximumBytes, maximumUsers: maximumUsers) })
    }

    /// Adds one allowed user with inviter or MANAGE_GUILD authority; no user fetch is performed.
    /// - Parameters:
    ///   - code: Exact existing invite code.
    ///   - userID: Complete UInt64 acceptance target, retained as an exact decimal path component.
    /// - Returns: Unsafe PUT requiring empty HTTP 204 and invalidating scoped invite-related reads.
    /// - Throws: Descriptor errors now; API/permission/transport or uncertain mutation outcomes on execution.
    public static func addTargetUser(code: String, userID: UserID) throws -> Endpoint<EmptyResponse> {
        try inviteEmptyMutation("PUT", code: code, suffix: [userID.description], routeSuffix: "/{user.id}")
    }

    /// Removes one allowed user with inviter or MANAGE_GUILD authority; this does not revoke the invite.
    /// - Parameters:
    ///   - code: Exact existing invite code.
    ///   - userID: Complete acceptance target snowflake; no membership inference is made.
    /// - Returns: Unsafe DELETE requiring empty HTTP 204 and invalidating scoped invite-related reads.
    /// - Throws: Descriptor errors now; API/permission/transport or uncertain mutation outcomes during execution.
    public static func removeTargetUser(code: String, userID: UserID) throws -> Endpoint<EmptyResponse> {
        try inviteEmptyMutation("DELETE", code: code, suffix: [userID.description], routeSuffix: "/{user.id}")
    }

    /// Replaces the target allowlist with CSV processed asynchronously by Discord.
    /// - Parameters:
    ///   - code: Exact invite; caller must be its inviter or have MANAGE_GUILD.
    ///   - csv: Nonempty headerless single-column decimal UInt64 IDs; LF/CRLF and duplicates are preserved.
    ///   - maximumBytes: Local complete multipart cap including framing, 1...8 MiB, default 1 MiB.
    /// - Returns: Unsafe PUT requiring empty HTTP 204; this acknowledges upload, not completed processing.
    /// - Throws: Invalid CSV/bounds/descriptor errors before I/O; API validation, transport or uncertain outcomes later.
    /// Use targetUsersJob or the finite lazy InviteOperations workflow explicitly; no hidden polls are started.
    public static func updateTargetUsers(code: String, csv: Data, maximumBytes: Int = 1_048_576) throws -> Endpoint<EmptyResponse> {
        guard (1...8_388_608).contains(maximumBytes) else { throw DiscordError.validation(.invalidValue) }
        guard csv.count <= maximumBytes else { throw DiscordError.validation(.limitExceeded) }
        _ = try inviteCSVRows(csv, hasHeader: false, maximumUsers: nil, response: false)
        let body = try RequestBody.multipart([
            MultipartPart(name: "target_users_file", filename: "users.csv", contentType: "text/csv", bytes: csv),
        ], boundary: "DiscordKitInvite", maximumBytes: maximumBytes)
        return try inviteEmptyMutation("PUT", code: code, body: body)
    }

    /// Adds one legal upstream bulk group without silently packing unrelated mutations.
    /// - Parameters:
    ///   - code: Exact invite; inviter or MANAGE_GUILD authority is server-enforced.
    ///   - userIDs: 1...1,000 targets, preserving caller order and duplicates; duplicate effects are server-defined.
    /// - Returns: Unsafe POST requiring empty HTTP 204; no per-user response or partial-success promise is invented.
    /// - Throws: Count/body/descriptor errors now; API/permission/transport or uncertain outcomes on execution.
    public static func bulkAddTargetUsers(code: String, userIDs: [UserID]) throws -> Endpoint<EmptyResponse> {
        try inviteBulkMutation(code: code, userIDs: userIDs, removing: false)
    }

    /// Removes one legal upstream bulk group with no fallback to per-user requests.
    /// - Parameters:
    ///   - code: Exact invite; inviter or MANAGE_GUILD authority is server-enforced.
    ///   - userIDs: 1...1,000 exact targets in caller order; duplicates are retained.
    /// - Returns: Unsafe POST requiring empty HTTP 204, with documented bulk limit metadata.
    /// - Throws: Count/body/descriptor errors before I/O; API/transport or uncertain mutation outcomes later.
    public static func bulkDeleteTargetUsers(code: String, userIDs: [UserID]) throws -> Endpoint<EmptyResponse> {
        try inviteBulkMutation(code: code, userIDs: userIDs, removing: true)
    }

    /// Reads asynchronous CSV-processing progress once; no successful upload is inferred to mean completion.
    /// - Parameter code: Exact invite; inviter, MANAGE_GUILD or VIEW_AUDIT_LOG authority is required.
    /// - Returns: Safe HTTP 200 GET with all status fields; read reuse is disabled so polling can observe progress.
    /// - Throws: Descriptor errors now; API/permission/transport or schema failures during execution.
    public static func targetUsersJob(code: String) throws -> Endpoint<InviteTargetUsersJob> {
        try Endpoint(method: "GET", path: ["invites", code, "target-users", "job-status"],
            route: "/invites/{code}/target-users/job-status", authentication: .bot,
            retrySafety: .safe, decode: { try InviteTargetUsersJob(data: $0) })
    }
}

/// Conservative credential-scoped family tags; mutation visibility can affect channel/guild invite listings.
let inviteTags: Set<String> = ["invite-catalog", "channel-catalog", "guild-catalog", "audit-log-catalog"]

/// Adds finite invite-family invalidation tags while preserving caller freshness choices.
/// - Parameter policy: Nil disables reuse; nonnil preserves TTL/coalescing and caller tags.
/// - Returns: Equivalent configuration unioned with invite visibility tags; no cache is consulted or populated.
func inviteReadPolicy(_ policy: ReadPolicy?) -> ReadPolicy? {
    policy.map { ReadPolicy(coalescing: $0.coalescing, timeToLive: $0.timeToLive, tags: $0.tags.union(inviteTags)) }
}

/// Constructs one ordinary unsafe allowlist mutation without a hidden follow-up request.
/// - Parameters:
///   - method: Explicit mutation method.
///   - code: Invite code validated by Endpoint as one safe opaque component.
///   - suffix: Optional literal or exact user-ID path components following target-users.
///   - routeSuffix: Matching stable normalized path suffix, default empty.
///   - body: Optional already bounded replayable request body.
///   - bulk: Optional documented upstream bulk metadata, never used to merge requests.
/// - Returns: Bot-only descriptor requiring empty HTTP 204 and invalidating scoped invite-family tags.
/// - Throws: Descriptor/bounds validation errors before I/O; no task or resource ownership is created.
func inviteEmptyMutation(_ method: String, code: String, suffix: [String] = [], routeSuffix: String = "",
                         body: RequestBody? = nil, bulk: BulkOperationMetadata? = nil) throws -> Endpoint<EmptyResponse> {
    try Endpoint(method: method, path: ["invites", code, "target-users"] + suffix,
        route: "/invites/{code}/target-users" + routeSuffix, authentication: .bot,
        successStatuses: [204], body: body, invalidates: inviteTags, bulk: bulk,
        decode: { try EmptyResponse(data: $0) })
}

/// Validates and constructs one documented bulk-add/delete request with exact ID encoding.
/// - Parameters:
///   - code: Exact invitation code, validated as one safe path component.
///   - userIDs: Nonempty list no larger than the official 1,000-user operation limit.
///   - removing: True selects bulk-delete; false selects bulk-add.
/// - Returns: One unsafe replayable JSON POST, preserving all requested IDs.
/// - Throws: Invalid-value for illegal counts or ordinary body/descriptor validation errors.
func inviteBulkMutation(code: String, userIDs: [UserID], removing: Bool) throws -> Endpoint<EmptyResponse> {
    guard (1...1_000).contains(userIDs.count) else { throw DiscordError.validation(.invalidValue) }
    let suffix = removing ? "bulk-delete" : "bulk-add"
    let payload = JSONValue.object(["user_ids": .array(userIDs.map { .string($0.description) })])
    return try inviteEmptyMutation("POST", code: code, suffix: [suffix], routeSuffix: "/" + suffix,
        body: guildJSON(payload), bulk: BulkOperationMetadata(maximumItems: 1_000, preservesOrder: false,
            permitsPartialResults: false, documentationURL: URL(string: "https://docs.discord.com/developers/resources/invite")!))
}
