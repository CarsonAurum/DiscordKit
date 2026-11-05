// File: Sources/DiscordHTTP/Resources/PermissionEndpoints.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import DiscordModels

extension GuildEndpoints {
    /// Gets a member's computed guild permissions, combining every assigned role with `@everyone`.
    /// API v10; verified 2026-11-05 against
    /// https://docs.discord.com/developers/resources/guild#get-guild-member-permissions.
    /// Uses bot authentication and the shared credential-global/guild rate authority, bounded retries,
    /// cancellation and deadlines. Discord publishes no additional intent or permission requirement here.
    /// - Parameters:
    ///   - guildID: Exact guild identifier and major rate partition.
    ///   - userID: Exact target member identifier; missing membership remains an ordinary API failure.
    ///   - readPolicy: Optional scoped reuse; default coalesces without completed caching, nil disables reuse.
    /// - Returns: One safe GET descriptor accepting HTTP 200 permission JSON; no pagination, member hydration,
    ///   local permission calculation or I/O occurs during construction. Results are snapshots, not future authority.
    /// - Throws: Descriptor validation errors now; API, transport, schema or response-bound errors on execution.
    public static func memberPermissions(guildID: GuildID, userID: UserID,
                                         readPolicy: ReadPolicy? = ReadPolicy()) throws -> Endpoint<ComputedPermissions> {
        try guildRead(guildID, suffix: ["permissions", "member", userID.description],
            route: "/guilds/{guild.id}/permissions/member/{user.id}", readPolicy: readPolicy,
            decode: { try ComputedPermissions(data: $0) })
    }

    /// Gets the guild permissions granted by one role together with `@everyone`.
    /// Other roles and member-specific restrictions are excluded. API v10; verified 2026-11-05 against
    /// https://docs.discord.com/developers/resources/guild#get-guild-role-permissions.
    /// Uses bot authentication and shared credential-global/guild admission, bounded safe retries,
    /// cancellation and deadlines. Discord publishes no additional intent or permission requirement here.
    /// - Parameters:
    ///   - guildID: Exact guild identifier and major rate partition.
    ///   - roleID: Exact role identifier; unknown roles remain ordinary API failures.
    ///   - readPolicy: Optional scoped reuse; default coalesces without completed caching, nil disables reuse.
    /// - Returns: A safe HTTP 200 GET descriptor retaining the exact permission bitfield and unknown fields.
    ///   Construction performs no I/O; there is no pagination or follow-up fetch. A role result is not a member result.
    /// - Throws: Descriptor validation errors now; API, transport, schema or response-bound errors on execution.
    public static func rolePermissions(guildID: GuildID, roleID: RoleID,
                                       readPolicy: ReadPolicy? = ReadPolicy()) throws -> Endpoint<ComputedPermissions> {
        try guildRead(guildID, suffix: ["permissions", "role", roleID.description],
            route: "/guilds/{guild.id}/permissions/role/{role.id}", readPolicy: readPolicy,
            decode: { try ComputedPermissions(data: $0) })
    }
}

extension ChannelEndpoints {
    /// Gets a member's channel permissions, including their roles and member-specific overwrites.
    /// Threads use the parent channel's overwrites. Requires VIEW_CHANNEL and additionally CONNECT for
    /// voice/stage channels. Discord enforces eligibility; no local membership or permission fetch occurs.
    /// API v10; verified 2026-11-05 against
    /// https://docs.discord.com/developers/resources/channel#get-channel-member-permissions.
    /// Uses bot authentication, shared credential-global/channel admission, bounded safe retries,
    /// cancellation and deadlines; there is no pagination.
    /// - Parameters:
    ///   - channelID: Channel or thread identifier and exact major rate partition.
    ///   - userID: Exact target member identifier; inaccessible/absent targets remain ordinary API failures.
    ///   - implicit: Whether Discord masks permissions for missing VIEW_CHANNEL or voice/stage CONNECT.
    ///     Nil omits the query and uses Discord's default true. Discord does not apply this masking to bot targets,
    ///     even when true is requested. Explicit false asks for the unmasked calculation.
    ///   - readPolicy: Optional scoped reuse; default coalesces without completed caching, nil disables reuse.
    ///     The target and implicit query participate in the credential-scoped reuse key.
    /// - Returns: One safe GET descriptor accepting HTTP 200 permission JSON. Snapshots can become stale;
    ///   they do not establish authorization for subsequent operations. Construction performs no I/O.
    /// - Throws: Descriptor validation errors now; API, transport, schema or response-bound errors on execution.
    public static func memberPermissions(channelID: ChannelID, userID: UserID, implicit: Bool? = nil,
                                         readPolicy: ReadPolicy? = ReadPolicy()) throws -> Endpoint<ComputedPermissions> {
        try Endpoint(method: "GET", path: ["channels", channelID.description, "permissions", "member", userID.description],
            route: "/channels/{channel.id}/permissions/member/{user.id}",
            query: implicit.map { [.init(name: "implicit", value: String($0))] } ?? [],
            authentication: .bot, majorParameter: channelID.description, retrySafety: .safe,
            readPolicy: channelReadPolicy(readPolicy), decode: { try ComputedPermissions(data: $0) })
    }

    /// Gets the permissions granted by one role and `@everyone`, applying their channel overwrites.
    /// Other roles and member-specific overwrites are excluded. Threads use their parent's overwrites.
    /// Requires VIEW_CHANNEL and additionally CONNECT for voice/stage channels; Discord enforces eligibility.
    /// API v10; verified 2026-11-05 against
    /// https://docs.discord.com/developers/resources/channel#get-channel-role-permissions.
    /// Uses bot authentication, shared credential-global/channel admission, bounded safe retries,
    /// cancellation and deadlines; no pagination or follow-up fetch is performed.
    /// - Parameters:
    ///   - channelID: Channel or thread identifier and exact major rate partition.
    ///   - roleID: Exact role identifier; inaccessible/absent targets remain ordinary API failures.
    ///   - implicit: Whether Discord masks permissions for missing VIEW_CHANNEL or voice/stage CONNECT.
    ///     Nil omits the query, using Discord's default true; explicit false requests an unmasked calculation.
    ///   - readPolicy: Optional scoped reuse; default coalesces without completed caching, nil disables reuse.
    ///     The target and implicit query participate in the credential-scoped reuse key.
    /// - Returns: One safe GET descriptor accepting HTTP 200 permission JSON without local calculation.
    ///   Construction performs no I/O; a role snapshot is not a member result or future authorization.
    /// - Throws: Descriptor validation errors now; API, transport, schema or response-bound errors on execution.
    public static func rolePermissions(channelID: ChannelID, roleID: RoleID, implicit: Bool? = nil,
                                       readPolicy: ReadPolicy? = ReadPolicy()) throws -> Endpoint<ComputedPermissions> {
        try Endpoint(method: "GET", path: ["channels", channelID.description, "permissions", "role", roleID.description],
            route: "/channels/{channel.id}/permissions/role/{role.id}",
            query: implicit.map { [.init(name: "implicit", value: String($0))] } ?? [],
            authentication: .bot, majorParameter: channelID.description, retrySafety: .safe,
            readPolicy: channelReadPolicy(readPolicy), decode: { try ComputedPermissions(data: $0) })
    }
}
