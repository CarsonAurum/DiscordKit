import DiscordCore
import DiscordModels
import Foundation

/// Complete written API v10 Voice REST resource, verified 2026-10-16 against
/// https://docs.discord.com/developers/resources/voice. Guild-specific regions remain available through
/// `GuildEndpoints.voiceRegions`. These descriptors use shared credential-scoped admission, bounded
/// retries and mutation ordering; they do not open voice/Gateway connections or require Gateway intents.
public enum VoiceEndpoints {
    /// Lists voice regions usable for voice or Stage channel rtc_region settings, without pagination.
    /// - Parameter readPolicy: Optional credential-scoped coalescing/freshness; default coalesces with no completed cache.
    /// - Returns: Safe HTTP 200 GET descriptor preserving opaque IDs, empty arrays and exact unknown fields.
    /// - Throws: Descriptor/policy errors now; authentication/API/transport/schema failures at execution.
    public static func listRegions(readPolicy: ReadPolicy? = ReadPolicy()) throws -> Endpoint<[VoiceRegion]> {
        try Endpoint(method: "GET", path: ["voice", "regions"], route: "/voice/regions", authentication: .bot,
            retrySafety: .safe, readPolicy: voiceReadPolicy(readPolicy, tags: ["voice-region-catalog"]),
            decode: { try guildArray($0) { try VoiceRegion(data: $0) } })
    }

    /// Gets the current credential user's guild voice state, including nullable disconnection/request fields.
    /// - Parameters:
    ///   - guildID: Guild major rate partition; no membership or voice channel is fetched separately.
    ///   - readPolicy: Optional credential-scoped reuse; default coalesces without retaining a completed snapshot.
    /// - Returns: Safe HTTP 200 GET descriptor; missing state remains a server API error.
    /// - Throws: Descriptor/policy errors now; authentication/API/transport/schema failures during execution.
    public static func currentUserState(guildID: GuildID,
                                        readPolicy: ReadPolicy? = ReadPolicy()) throws -> Endpoint<VoiceState> {
        try voiceStateRead(guildID: guildID, user: "@me", readPolicy: readPolicy)
    }

    /// Gets another user's guild voice state. CONNECT to their channel is required if they are connected.
    /// - Parameters:
    ///   - guildID: Exact guild and major rate partition.
    ///   - userID: Target user identifier; no member/channel hydration is performed.
    ///   - readPolicy: Optional scoped reuse; default coalesces with no completed cache.
    /// - Returns: Safe HTTP 200 GET descriptor retaining all written voice-state fields.
    /// - Throws: Descriptor/policy errors now; authentication/permission/API/transport/schema errors later.
    public static func userState(guildID: GuildID, userID: UserID,
                                 readPolicy: ReadPolicy? = ReadPolicy()) throws -> Endpoint<VoiceState> {
        try voiceStateRead(guildID: guildID, user: userID.description, readPolicy: readPolicy)
    }

    /// Changes the current user's suppression/request status in an already joined Stage channel.
    /// MUTE_MEMBERS is needed to unsuppress and REQUEST_TO_SPEAK to request; self-suppression and clearing
    /// are allowed. Discord validates present/future timestamps and emits Voice State Update on success.
    /// - Parameters:
    ///   - guildID: Guild major rate partition and conservative cache invalidation scope.
    ///   - request: Validated optional/nullable edits, including an explicitly empty object.
    /// - Returns: Unsafe PATCH descriptor requiring exactly empty HTTP 204 success. No audit header is documented.
    /// - Throws: Body/descriptor errors now; API/transport or explicit indeterminate submission errors later.
    /// Ambiguous writes are never replayed; complete 429 rejections use the shared bounded retry budget.
    public static func modifyCurrentUserState(guildID: GuildID,
                                              request: CurrentUserVoiceStateModify) throws -> Endpoint<EmptyResponse> {
        try voiceStateMutation(guildID: guildID, user: "@me", payload: request.jsonValue())
    }

    /// Changes another user's Stage suppression with MUTE_MEMBERS, without joining or moving the user.
    /// Unsuppressing non-bots sets a server request time; suppression clears it. Emits Voice State Update.
    /// - Parameters:
    ///   - guildID: Guild major rate partition and conservative cache invalidation scope.
    ///   - userID: Exact target user, whose current membership/channel remains server-validated.
    ///   - request: Validated Stage channel/suppression edits; no current-user-only timestamp can be supplied.
    /// - Returns: Unsafe PATCH descriptor requiring empty HTTP 204 success and no undocumented audit reason.
    /// - Throws: Body/descriptor errors now; auth/permission/API/transport or indeterminate outcome errors at execution.
    /// The shared retry budget handles complete 429 rejection; uncertain writes are not replayed.
    public static func modifyUserState(guildID: GuildID, userID: UserID,
                                       request: UserVoiceStateModify) throws -> Endpoint<EmptyResponse> {
        try voiceStateMutation(guildID: guildID, user: userID.description, payload: request.jsonValue())
    }
}

/// Retains caller reuse choices while adding the exact conservative resource invalidation tags.
/// - Parameters:
///   - policy: Optional reuse policy; nil disables coalescing and completed caching.
///   - tags: Authentication-scoped resource catalogs invalidated by relevant mutations.
/// - Returns: The caller's coalescing/TTL settings plus resource tags; no freshness is enabled implicitly.
func voiceReadPolicy(_ policy: ReadPolicy?, tags: Set<String>) -> ReadPolicy? {
    policy.map { ReadPolicy(coalescing: $0.coalescing, timeToLive: $0.timeToLive, tags: $0.tags.union(tags)) }
}

/// Constructs a voice-state GET with stable current-user versus named-user normalized routes.
/// - Parameters:
///   - guildID: Exact guild major partition.
///   - user: Validated decimal user identifier or literal @me, supplied only by typed public constructors.
///   - readPolicy: Optional caller reuse policy; nil disables reuse.
/// - Returns: Safe HTTP 200 descriptor with bounded complete state decoding and guild/voice invalidation tags.
/// - Throws: Descriptor/policy validation errors before I/O. No tasks, resources or voice session are created.
func voiceStateRead(guildID: GuildID, user: String, readPolicy: ReadPolicy?) throws -> Endpoint<VoiceState> {
    try Endpoint(method: "GET", path: ["guilds", guildID.description, "voice-states", user],
        route: "/guilds/{guild.id}/voice-states/" + (user == "@me" ? "@me" : "{user.id}"),
        authentication: .bot, majorParameter: guildID.description, retrySafety: .safe,
        readPolicy: voiceReadPolicy(readPolicy, tags: ["voice-state-catalog", "guild-catalog", "channel-catalog"]),
        decode: { try VoiceState(data: $0) })
}

/// Constructs an unsafe Stage voice-state PATCH without hidden reads, joins or background tasks.
/// - Parameters:
///   - guildID: Guild major rate partition and invalidation scope.
///   - user: Typed public caller's decimal user identifier or literal @me.
///   - payload: Previously validated JSON object, preserving omission and nullable request clearing.
/// - Returns: Empty-204 descriptor invalidating voice/guild/channel/member-related snapshots.
/// - Throws: JSON/body/descriptor errors before I/O; server state and uncertain writes remain execution concerns.
func voiceStateMutation(guildID: GuildID, user: String, payload: JSONValue) throws -> Endpoint<EmptyResponse> {
    try Endpoint(method: "PATCH", path: ["guilds", guildID.description, "voice-states", user],
        route: "/guilds/{guild.id}/voice-states/" + (user == "@me" ? "@me" : "{user.id}"),
        authentication: .bot, successStatuses: [204], majorParameter: guildID.description,
        body: guildJSON(payload), invalidates: guildTags(guildID).union(["voice-state-catalog"]),
        decode: { try EmptyResponse(data: $0) })
}
