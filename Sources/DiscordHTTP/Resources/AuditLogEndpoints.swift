import DiscordCore
import DiscordModels
import Foundation

/// A single exclusive audit entry boundary. Choosing one direction avoids the undocumented
/// precedence of simultaneous before/after query parameters. Zero is a legal oldest-first boundary.
public enum AuditLogPosition: Sendable, Equatable {
    /// Entries below this ID, newest first.
    case before(AuditLogEntryID)
    /// Entries above this ID, oldest first.
    case after(AuditLogEntryID)
}

/// API v10 audit retrieval, verified 2026-10-16 against
/// https://docs.discord.com/developers/resources/audit-log. VIEW_AUDIT_LOG is required;
/// entries expire upstream after 45 days. Snapshot data cannot establish current permission.
/// Descriptors use the common credential-scoped rate authority, finite retries and cancellation.
public enum AuditLogEndpoints {
    /// Retrieves one filtered audit envelope, including referenced resources without follow-up hydration.
    /// - Parameters:
    ///   - guildID: Exact guild ID and major rate partition.
    ///   - userID: Optional actor filter; nil omits the filter.
    ///   - actionType: Optional known or future integral action code; nil includes all actions.
    ///   - position: Optional exclusive boundary; nil uses newest-first server defaults. After is oldest first.
    ///   - limit: Optional count in 1...100; nil preserves the server default of 50.
    ///   - readPolicy: Optional identity-scoped reuse policy; default coalesces with no completed caching.
    ///     Positive TTL caching is opt-in; external actions can remain unseen until expiration.
    /// - Returns: One safe GET descriptor accepting HTTP 200 and preserving the complete envelope.
    /// - Throws: Invalid-value for an invalid limit or descriptor metadata; API/auth/transport/schema
    ///   failures occur at execution. Construction is synchronous and performs no I/O or permission check.
    public static func get(guildID: GuildID, userID: UserID? = nil,
                           actionType: RawValue<AuditLogEvent>? = nil, position: AuditLogPosition? = nil,
                           limit: Int? = nil, readPolicy: ReadPolicy? = ReadPolicy()) throws -> Endpoint<AuditLog> {
        var query: [QueryItem] = []
        if let userID { query.append(.init(name: "user_id", value: userID.description)) }
        if let actionType { query.append(.init(name: "action_type", value: String(actionType.rawValue))) }
        switch position {
        case .before(let id): query.append(.init(name: "before", value: id.description))
        case .after(let id): query.append(.init(name: "after", value: id.description))
        case nil: break
        }
        if let limit {
            guard (1...100).contains(limit) else { throw DiscordError.validation(.invalidValue) }
            query.append(.init(name: "limit", value: String(limit)))
        }
        let policy = readPolicy.map { ReadPolicy(coalescing: $0.coalescing, timeToLive: $0.timeToLive,
            tags: $0.tags.union(["audit-log-catalog", "guild-catalog", "channel-catalog", "message-search"])) }
        return try Endpoint(method: "GET", path: ["guilds", guildID.description, "audit-logs"],
            route: "/guilds/{guild.id}/audit-logs", query: query, authentication: .bot,
            majorParameter: guildID.description, retrySafety: .safe, readPolicy: policy,
            decode: { try AuditLog(data: $0) })
    }
}
