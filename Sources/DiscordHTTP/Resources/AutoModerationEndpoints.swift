import DiscordCore
import DiscordModels
import Foundation

/// The five current API v10 Auto Moderation operations, verified 2026-10-16 against
/// https://docs.discord.com/developers/resources/auto-moderation. All require MANAGE_GUILD;
/// timeout actions additionally require MODERATE_MEMBERS. Discord checks current permissions,
/// rule quotas, channel existence and rule semantics. No Gateway, permission inference or hidden reads occur.
public enum AutoModerationEndpoints {
    /// Lists all rules configured for one guild without invented pagination or per-rule requests.
    /// - Parameters:
    ///   - guildID: Exact guild ID and major rate partition.
    ///   - readPolicy: Optional scoped reuse; default coalesces without completed caching.
    /// - Returns: A safe HTTP 200 GET descriptor returning rules in upstream order, including an empty list.
    /// - Throws: Descriptor validation errors now; auth/API/transport or malformed-array failures on execution.
    public static func list(guildID: GuildID, readPolicy: ReadPolicy? = ReadPolicy()) throws -> Endpoint<[AutoModerationRule]> {
        try Endpoint(method: "GET", path: ["guilds", guildID.description, "auto-moderation", "rules"],
            route: "/guilds/{guild.id}/auto-moderation/rules", authentication: .bot,
            majorParameter: guildID.description, retrySafety: .safe, readPolicy: autoModerationReadPolicy(readPolicy),
            decode: { try guildArray($0) { try AutoModerationRule(data: $0) } })
    }

    /// Retrieves a single rule; a missing rule remains a server API error rather than cached absence.
    /// - Parameters:
    ///   - guildID: Exact owning guild ID and major rate partition.
    ///   - ruleID: Exact rule snowflake; existence and guild ownership are checked by Discord.
    ///   - readPolicy: Optional scoped reuse; default coalesces without completed caching.
    /// - Returns: A safe HTTP 200 GET descriptor retaining all modeled and unknown rule fields.
    /// - Throws: Descriptor errors now; permission/API/transport/schema failures on execution.
    public static func get(guildID: GuildID, ruleID: AutoModerationRuleID,
                           readPolicy: ReadPolicy? = ReadPolicy()) throws -> Endpoint<AutoModerationRule> {
        try Endpoint(method: "GET", path: ["guilds", guildID.description, "auto-moderation", "rules", ruleID.description],
            route: "/guilds/{guild.id}/auto-moderation/rules/{rule.id}", authentication: .bot,
            majorParameter: guildID.description, retrySafety: .safe, readPolicy: autoModerationReadPolicy(readPolicy),
            decode: { try AutoModerationRule(data: $0) })
    }

    /// Creates one validated rule, leaving guild-wide trigger quotas and authorization to Discord.
    /// - Parameters:
    ///   - guildID: Exact guild ID and major rate partition.
    ///   - request: Validated complete creation payload; omitted enabled retains the server default false.
    ///   - auditReason: Optional URL-encoded audit reason, at most 512 Unicode scalars before encoding.
    /// - Returns: One unsafe POST descriptor requiring HTTP 200 with the created rule. No mutation packing occurs.
    /// - Throws: Body/descriptor/audit validation errors now; API/transport or indeterminate submission outcomes later.
    ///   Ambiguous mutations are never replayed automatically; rejected 429 retries use the shared finite budget.
    public static func create(guildID: GuildID, request: AutoModerationCreateRequest,
                              auditReason: String? = nil) throws -> Endpoint<AutoModerationRule> {
        try autoModerationMutation("POST", guildID: guildID, payload: request.jsonValue(), auditReason: auditReason,
            decode: { try AutoModerationRule(data: $0) })
    }

    /// Modifies a rule without changing trigger_type, which the written PATCH contract does not expose.
    /// - Parameters:
    ///   - guildID: Exact owning guild ID and major rate partition.
    ///   - ruleID: Exact target rule ID.
    ///   - request: Validated optional edits using caller-supplied trigger context; no context fetch occurs.
    ///   - auditReason: Optional reason, at most 512 Unicode scalars before URL encoding.
    /// - Returns: One unsafe PATCH descriptor requiring HTTP 200 with the updated rule.
    /// - Throws: Serialization/descriptor/audit errors now; server permission/state/validation errors,
    ///   transport errors or uncertain mutation outcomes at execution. Stale context remains server-validated.
    public static func modify(guildID: GuildID, ruleID: AutoModerationRuleID, request: AutoModerationModifyRequest,
                              auditReason: String? = nil) throws -> Endpoint<AutoModerationRule> {
        try autoModerationMutation("PATCH", guildID: guildID, ruleID: ruleID,
            payload: request.jsonValue(), auditReason: auditReason, decode: { try AutoModerationRule(data: $0) })
    }

    /// Deletes one rule with exact empty HTTP 204 success semantics.
    /// - Parameters:
    ///   - guildID: Exact guild ID and major rate partition.
    ///   - ruleID: Rule to delete; missing rules remain API errors.
    ///   - auditReason: Optional reason, at most 512 Unicode scalars before encoding.
    /// - Returns: One unsafe DELETE descriptor; success invalidates scoped rule and audit snapshots.
    /// - Throws: Descriptor/audit errors now; API/transport or uncertain deletion outcomes on execution.
    public static func delete(guildID: GuildID, ruleID: AutoModerationRuleID,
                              auditReason: String? = nil) throws -> Endpoint<EmptyResponse> {
        try autoModerationMutation("DELETE", guildID: guildID, ruleID: ruleID, auditReason: auditReason,
            successStatuses: [204], decode: { try EmptyResponse(data: $0) })
    }
}

/// Adds rule and permission invalidation while preserving caller reuse choices.
/// - Parameter policy: Optional caller policy; nil disables all reuse, including coalescing.
/// - Returns: Equivalent freshness/coalescing with moderation and guild catalog tags. No cache is populated.
func autoModerationReadPolicy(_ policy: ReadPolicy?) -> ReadPolicy? {
    policy.map { ReadPolicy(coalescing: $0.coalescing, timeToLive: $0.timeToLive,
        tags: $0.tags.union(["auto-moderation-catalog", "guild-catalog"])) }
}

/// Constructs one conservative mutation with shared guild admission and moderation/audit invalidation.
/// - Parameters:
///   - method: Explicit POST, PATCH or DELETE verb; replay safety remains unsafe.
///   - guildID: Exact owning guild and major rate partition.
///   - ruleID: Optional target; nil addresses the collection for creation.
///   - payload: Optional validated JSON; nil sends no request body.
///   - auditReason: Optional supported reason, validated by Endpoint before any I/O.
///   - successStatuses: Exact accepted statuses; default 200, deletion uses only 204.
///   - decode: Operation-specific complete response decoder.
/// - Returns: A bounded immutable descriptor without executing or starting tasks.
/// - Throws: JSON/body or descriptor validation errors. Server state and submission failures occur at execution.
func autoModerationMutation<T: Sendable>(_ method: String, guildID: GuildID, ruleID: AutoModerationRuleID? = nil,
    payload: JSONValue? = nil, auditReason: String? = nil, successStatuses: Set<Int> = [200],
    decode: @escaping @Sendable (Data) throws -> T) throws -> Endpoint<T> {
    let suffix = ruleID.map { [$0.description] } ?? []
    return try Endpoint(method: method, path: ["guilds", guildID.description, "auto-moderation", "rules"] + suffix,
        route: "/guilds/{guild.id}/auto-moderation/rules" + (ruleID == nil ? "" : "/{rule.id}"),
        authentication: .bot, successStatuses: successStatuses, majorParameter: guildID.description,
        auditReason: auditReason, body: payload.map { try guildJSON($0) },
        invalidates: guildTags(guildID).union(["auto-moderation-catalog", "audit-log-catalog"]), decode: decode)
}
