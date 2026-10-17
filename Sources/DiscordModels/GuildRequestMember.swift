import DiscordCore
import Foundation

/// API v10 PUT /guilds/{guild.id}/members/{user.id}, requiring a guilds.join OAuth token.
/// The bot authorization must belong to the same application and have CREATE_INSTANT_INVITE.
/// The server may return an existing-member empty response; pending screening is never bypassed locally.
public struct GuildMemberAdd: GuildRequestPayload {
    private let accessToken: BearerToken
    private let fields: [String: JSONValue]

    /// Validates optional member settings while retaining a separately redacted OAuth credential.
    /// All `Field` parameters default to `.absent`, preserving server defaults or current values unless stated otherwise.
    /// - Parameters:
    ///   - accessToken: Validated user OAuth token with guilds.join consent, at most 10240 characters; never emitted by diagnostics.
    ///   - nick: Omitted or exact nickname, at most 32 Unicode scalars; MANAGE_NICKNAMES is required.
    ///   - roles: Omitted or up to 250 distinct role IDs; requires MANAGE_ROLES and server hierarchy checks.
    ///   - mute: Omitted or voice mute state; requires MUTE_MEMBERS.
    ///   - deaf: Omitted or voice deafen state; requires DEAFEN_MEMBERS.
    /// - Throws: Safe validation errors for duplicate IDs or unsupported nulls. Nickname bounds follow the official OpenAPI preview.
    public init(accessToken: BearerToken, nick: Field<String> = .absent, roles: Field<[RoleID]> = .absent,
                mute: Field<Bool> = .absent, deaf: Field<Bool> = .absent) throws {
        guard accessToken.withUnsafeValue({ $0.unicodeScalars.count <= 10_240 }) else { throw DiscordError.validation(.limitExceeded) }
        var result: [String: JSONValue] = [:]
        try guildRequestField(nick, name: "nick", into: &result) { try guildRequestText($0, length: 0...32) }
        try guildRequestField(roles, name: "roles", into: &result) {
            guard $0.count <= 250 else { throw DiscordError.validation(.limitExceeded) }; return try guildRequestIDs($0)
        }
        try guildRequestField(mute, name: "mute", into: &result) { .bool($0) }
        try guildRequestField(deaf, name: "deaf", into: &result) { .bool($0) }
        self.accessToken = accessToken; fields = result
    }

    /// Validates raw credential syntax and delegates to the typed OAuth constructor.
    /// All `Field` parameters default to `.absent`, preserving server defaults or current values unless stated otherwise.
    /// - Parameters:
    ///   - accessToken: Nonempty user token of at most 10240 characters without whitespace, controls or an authorization prefix.
    ///   - nick: Omitted nickname; null is forbidden and server permissions remain authoritative.
    ///   - roles: Omitted or at most 250 distinct role IDs; empty explicitly assigns no roles.
    ///   - mute: Omitted or desired mute state.
    ///   - deaf: Omitted or desired deafen state.
    /// - Throws: Safe credential and request validation errors without including token or personal content.
    public init(accessToken: String, nick: Field<String> = .absent, roles: Field<[RoleID]> = .absent,
                mute: Field<Bool> = .absent, deaf: Field<Bool> = .absent) throws {
        try self.init(accessToken: BearerToken(accessToken), nick: nick, roles: roles, mute: mute, deaf: deaf)
    }

    /// Explicitly exposes the OAuth credential in the body for execution; keep this result out of logs.
    /// - Returns: Required access_token and validated optional settings; consent is checked only by Discord.
    public func jsonValue() -> JSONValue {
        accessToken.withUnsafeValue { token in
            var result = fields; result["access_token"] = .string(token); return .object(result)
        }
    }
}

/// API v10 PATCH /guilds/{guild.id}/members/{user.id}; each field has its own permission requirement.
/// Nicknames require MANAGE_NICKNAMES, roles MANAGE_ROLES, mute/deaf their respective moderation
/// permissions, voice moves MOVE_MEMBERS plus CONNECT, timeouts MODERATE_MEMBERS, and flags the
/// documented guild/role/moderation permission combinations. Current hierarchy is checked by Discord.
public struct GuildMemberModify: GuildRequestPayload {
    private let fields: [String: JSONValue]

    /// Validates nullable member updates without reading voice state, hierarchy or permission state.
    /// All `Field` parameters default to `.absent`, preserving server defaults or current values unless stated otherwise.
    /// - Parameters:
    ///   - nick: Absent leaves unchanged; nullable nickname text, at most 32 scalars, is transmitted exactly.
    ///   - roles: Nullable replacement list of at most 350 distinct role IDs, following the official preview schema.
    ///   - mute: Nullable mute state; Discord rejects changes to members not connected to voice.
    ///   - deaf: Nullable deafen state; current voice membership remains a server check.
    ///   - channelID: Nullable target voice channel; null explicitly disconnects the member.
    ///   - communicationDisabledUntil: Nullable timeout deadline no more than 28 days ahead; null removes timeout.
    ///   - flags: Nullable member flags; only BYPASSES_VERIFICATION (bit 2) is writable.
    ///   - referenceTime: Finite validation clock snapshot, defaulting to construction time; not transmitted.
    ///     Inject this value for deterministic tests and construct near execution because Discord rechecks the deadline.
    /// - Throws: Safe validation errors for duplicate roles, read-only/unknown flags, invalid reference times
    ///   or timeout timestamps outside the inclusive current-time through 28-day window.
    public init(nick: Field<String> = .absent, roles: Field<[RoleID]> = .absent,
                mute: Field<Bool> = .absent, deaf: Field<Bool> = .absent,
                channelID: Field<ChannelID> = .absent,
                communicationDisabledUntil: Field<DiscordTimestamp> = .absent,
                flags: Field<GuildMemberFlags> = .absent, referenceTime: Date = Date()) throws {
        var result: [String: JSONValue] = [:]
        try guildRequestField(nick, name: "nick", nullable: true, into: &result) { try guildRequestText($0, length: 0...32) }
        try guildRequestField(roles, name: "roles", nullable: true, into: &result) {
            guard $0.count <= 350 else { throw DiscordError.validation(.limitExceeded) }; return try guildRequestIDs($0)
        }
        try guildRequestField(mute, name: "mute", nullable: true, into: &result) { .bool($0) }
        try guildRequestField(deaf, name: "deaf", nullable: true, into: &result) { .bool($0) }
        try guildRequestField(channelID, name: "channel_id", nullable: true, into: &result) { .string($0.description) }
        try guildRequestField(communicationDisabledUntil, name: "communication_disabled_until", nullable: true, into: &result) {
            try guildRequestDeadline($0, referenceTime: referenceTime, maximumSeconds: 28 * 86_400)
        }
        try guildRequestField(flags, name: "flags", nullable: true, into: &result) {
            guard $0.rawValue & ~UInt64(1 << 2) == 0 else { throw DiscordError.validation(.invalidValue) }
            return try guildRequestNumber($0.rawValue)
        }
        fields = result
    }

    /// Produces exact nullable member updates; explicit null voice channel requests disconnection.
    /// - Returns: Immutable PATCH body, with no inferred state or automatic role merging.
    public func jsonValue() -> JSONValue { .object(fields) }
}

/// API v10 PATCH /guilds/{guild.id}/members/@me, including current guild profile fields.
/// Nickname changes require CHANGE_NICKNAME; upstream account/feature availability remains authoritative.
public struct GuildCurrentMemberModify: GuildRequestPayload {
    private let fields: [String: JSONValue]

    /// Validates nullable current-member profile settings using the official published schema bounds.
    /// All `Field` parameters default to `.absent`, preserving server defaults or current values unless stated otherwise.
    /// - Parameters:
    ///   - nick: Omitted or nullable nickname of at most 32 scalars; null removes the guild nickname.
    ///   - banner: Nullable canonical base64 banner image or image data URI; dimensions/features are server checks.
    ///   - avatar: Nullable canonical base64 avatar image or image data URI; null removes the guild avatar.
    ///   - bio: Nullable exact guild bio of at most 300 scalars; null clears it.
    /// - Throws: Safe validation errors for malformed image transport syntax without exposing image or profile content.
    public init(nick: Field<String> = .absent, banner: Field<String> = .absent,
                avatar: Field<String> = .absent, bio: Field<String> = .absent) throws {
        var result: [String: JSONValue] = [:]
        try guildRequestField(nick, name: "nick", nullable: true, into: &result) { try guildRequestText($0, length: 0...32) }
        try guildRequestField(banner, name: "banner", nullable: true, into: &result) { try guildRequestImage($0) }
        try guildRequestField(avatar, name: "avatar", nullable: true, into: &result) { try guildRequestImage($0) }
        try guildRequestField(bio, name: "bio", nullable: true, into: &result) { try guildRequestText($0, length: 0...300) }
        fields = result
    }

    /// Produces the current-member profile update while preserving explicit removals.
    /// - Returns: Immutable PATCH body; empty is a valid no-change request.
    public func jsonValue() -> JSONValue { .object(fields) }
}

/// Deprecated API v10 PATCH /guilds/{guild.id}/members/@me/nick; prefer GuildCurrentMemberModify.
/// Requires CHANGE_NICKNAME and may emit Guild Member Update. Retained for explicit compatibility only.
public struct GuildCurrentUserNickModify: GuildRequestPayload {
    private let fields: [String: JSONValue]

    /// Constructs the deprecated nickname-only payload with exact presence semantics.
    /// - Parameter nick: Absent leaves unchanged; null removes the nickname; text of at most 32 scalars is sent unchanged.
    /// - Throws: A safe validation error for a nickname longer than 32 Unicode scalars.
    public init(nick: Field<String> = .absent) throws {
        var result: [String: JSONValue] = [:]
        try guildRequestField(nick, name: "nick", nullable: true, into: &result) { try guildRequestText($0, length: 0...32) }
        fields = result
    }

    /// Produces the deprecated nickname update without rewriting it to another endpoint.
    /// - Returns: Empty, null or exact string nickname object as selected.
    public func jsonValue() -> JSONValue { .object(fields) }
}

/// API v10 PUT /guilds/{guild.id}/bans/{user.id}; requires BAN_MEMBERS and respects hierarchy.
/// The deprecated day field is available for compatibility; prefer second-granularity deletion.
public struct GuildBanCreate: GuildRequestPayload {
    private let fields: [String: JSONValue]

    /// Validates message deletion duration without silently selecting between conflicting spellings.
    /// All `Field` parameters default to `.absent`, preserving server defaults or current values unless stated otherwise.
    /// - Parameters:
    ///   - deleteMessageSeconds: Omitted or 0...604800 seconds of messages to delete; default is zero upstream.
    ///   - deleteMessageDays: Deprecated omitted or 0...7 days; cannot be combined with the seconds field.
    /// - Throws: Safe validation errors for nulls, out-of-range durations or both fields being supplied.
    public init(deleteMessageSeconds: Field<Int> = .absent, deleteMessageDays: Field<Int> = .absent) throws {
        var result: [String: JSONValue] = [:]
        try guildRequestField(deleteMessageSeconds, name: "delete_message_seconds", into: &result) { try guildRequestRange($0, 0...604_800) }
        try guildRequestField(deleteMessageDays, name: "delete_message_days", into: &result) { try guildRequestRange($0, 0...7) }
        guard result.count <= 1 else { throw DiscordError.validation(.invalidValue) }
        fields = result
    }

    /// Produces a single-ban body; omission retains Discord's zero-deletion default.
    /// - Returns: Validated duration object without selecting or fetching the user.
    public func jsonValue() -> JSONValue { .object(fields) }
}

/// API v10 POST /guilds/{guild.id}/bulk-ban; requires BAN_MEMBERS and MANAGE_GUILD.
/// Discord returns per-user success/failure; the request never promises an atomic outcome.
public struct GuildBulkBan: GuildRequestPayload {
    public let userIDs: [UserID]
    private let fields: [String: JSONValue]

    /// Validates one explicit bounded bulk ban without splitting it into hidden requests.
    /// All `Field` parameters default to `.absent`, preserving server defaults or current values unless stated otherwise.
    /// - Parameters:
    ///   - userIDs: One through 200 distinct user snowflakes, retained in caller order.
    ///   - deleteMessageSeconds: Omitted or 0...604800 seconds of messages to delete; null is forbidden.
    /// - Throws: Safe validation errors for empty/overlong/duplicate IDs, nulls or invalid deletion duration.
    public init(userIDs: [UserID], deleteMessageSeconds: Field<Int> = .absent) throws {
        guard (1...200).contains(userIDs.count) else { throw DiscordError.validation(.invalidValue) }
        var result: [String: JSONValue] = ["user_ids": try guildRequestIDs(userIDs)]
        try guildRequestField(deleteMessageSeconds, name: "delete_message_seconds", into: &result) { try guildRequestRange($0, 0...604_800) }
        self.userIDs = userIDs; fields = result
    }

    /// Produces one explicit bulk body, preserving ordering and exact snowflake precision.
    /// - Returns: Required user_ids plus the explicitly requested deletion window.
    public func jsonValue() -> JSONValue { .object(fields) }
}
