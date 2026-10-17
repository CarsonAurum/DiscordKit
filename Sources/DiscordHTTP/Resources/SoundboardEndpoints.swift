import DiscordCore
import DiscordModels
import Foundation

/// Seven API v10 Soundboard operations, verified 2026-10-16 against the current written reference
/// and official OpenAPI. Shared HTTP policy owns finite admission/retry/deadline and response budgets;
/// these descriptors neither open voice connections nor require adoption of the optional voice runtime.
/// See https://docs.discord.com/developers/resources/soundboard.
public enum SoundboardEndpoints {
    /// Lists default sounds in one request without fetching CDN audio or hydrating users.
    /// - Parameter readPolicy: Optional scoped reuse; default coalesces without completed caching.
    /// - Returns: One safe HTTP 200 GET decoding an ordered array, including empty. Bot authentication is required.
    /// - Throws: Descriptor errors now; authentication/API/transport or invalid-sound errors during execution.
    public static func listDefault(readPolicy: ReadPolicy? = ReadPolicy()) throws -> Endpoint<[SoundboardSound]> {
        try Endpoint(method: "GET", path: ["soundboard-default-sounds"], route: "/soundboard-default-sounds",
            authentication: .bot, retrySafety: .safe,
            readPolicy: expressionReadPolicy(readPolicy, tags: ["default-soundboard-catalog"]),
            decode: { try guildArray($0) { try SoundboardSound(data: $0) } })
    }

    /// Lists one guild's sounds with the documented items envelope and no invented pagination.
    /// - Parameters:
    ///   - guildID: Exact guild ID and major rate partition.
    ///   - readPolicy: Optional scoped reuse; nil disables reuse, default has no completed caching.
    /// - Returns: One safe HTTP 200 GET. Uploader fields are visible with CREATE_GUILD_EXPRESSIONS
    ///   or MANAGE_GUILD_EXPRESSIONS, as enforced by Discord for each request.
    /// - Throws: Descriptor errors now; authentication/API/transport or invalid-envelope failures during execution.
    public static func listGuild(guildID: GuildID,
                                 readPolicy: ReadPolicy? = ReadPolicy()) throws -> Endpoint<GuildSoundboardSoundList> {
        try Endpoint(method: "GET", path: ["guilds", guildID.description, "soundboard-sounds"],
            route: "/guilds/{guild.id}/soundboard-sounds", authentication: .bot,
            majorParameter: guildID.description, retrySafety: .safe,
            readPolicy: expressionReadPolicy(readPolicy, tags: ["soundboard-catalog", "guild-catalog"]),
            decode: { try GuildSoundboardSoundList(data: $0) })
    }

    /// Gets one guild sound with optional uploader visibility matching listGuild.
    /// - Parameters:
    ///   - guildID: Exact owning guild and major rate partition; ownership is server-checked.
    ///   - soundID: Exact sound ID, preserving the full UInt64 range including small default-style IDs.
    ///   - readPolicy: Optional scoped reuse; default coalesces without completed caching.
    /// - Returns: One safe HTTP 200 GET; absent sounds remain API errors, never cached synthetic absence.
    /// - Throws: Descriptor errors now; API/authentication/transport or malformed-sound failures on execution.
    public static func getGuild(guildID: GuildID, soundID: SoundboardSoundID,
                                readPolicy: ReadPolicy? = ReadPolicy()) throws -> Endpoint<SoundboardSound> {
        try Endpoint(method: "GET", path: ["guilds", guildID.description, "soundboard-sounds", soundID.description],
            route: "/guilds/{guild.id}/soundboard-sounds/{sound.id}", authentication: .bot,
            majorParameter: guildID.description, retrySafety: .safe,
            readPolicy: expressionReadPolicy(readPolicy, tags: ["soundboard-catalog", "guild-catalog"]),
            decode: { try SoundboardSound(data: $0) })
    }

    /// Creates one guild sound using CREATE_GUILD_EXPRESSIONS and a bounded MP3/Ogg data URI.
    /// - Parameters:
    ///   - guildID: Target guild and major rate partition.
    ///   - request: Validated name, sound bytes, optional nullable volume and custom/Unicode emoji.
    ///     Discord checks the maximum 5.2-second duration, audio validity, available slots and permissions.
    ///   - auditReason: Optional supported reason, at most 512 Unicode scalars before percent encoding.
    /// - Returns: One unsafe HTTP 201 POST, retaining the created sound and invalidating related snapshots.
    /// - Throws: Body/descriptor/audit errors now; API/transport/schema or uncertain submission outcomes later.
    ///   Ambiguous creations never replay automatically; explicitly rejected 429s use the finite shared retry budget.
    public static func createGuild(guildID: GuildID, request: GuildSoundboardSoundCreate,
                                   auditReason: String? = nil) throws -> Endpoint<SoundboardSound> {
        try expressionGuildMutation("POST", guildID: guildID, resource: "soundboard-sounds", routeResource: "soundboard-sounds",
            payload: request.jsonValue(), auditReason: auditReason, successStatuses: [201], catalog: "soundboard-catalog",
            decode: { try SoundboardSound(data: $0) })
    }

    /// Changes optional sound metadata without replacing its audio bytes.
    /// - Parameters:
    ///   - guildID: Exact owning guild and major rate partition.
    ///   - soundID: Exact sound target; ownership and current availability remain server-validated.
    ///   - request: Validated optional name/nullable volume/emoji changes; omission retains server state.
    ///   - auditReason: Optional supported reason, at most 512 Unicode scalars before encoding.
    /// - Returns: One unsafe HTTP 200 PATCH. Caller-created sounds require CREATE_GUILD_EXPRESSIONS
    ///   or MANAGE_GUILD_EXPRESSIONS; other sounds require MANAGE_GUILD_EXPRESSIONS.
    /// - Throws: Body/descriptor/audit errors now; API/transport/schema or uncertain mutation outcomes during execution.
    public static func modifyGuild(guildID: GuildID, soundID: SoundboardSoundID, request: GuildSoundboardSoundModify,
                                   auditReason: String? = nil) throws -> Endpoint<SoundboardSound> {
        try expressionGuildMutation("PATCH", guildID: guildID, resource: "soundboard-sounds", routeResource: "soundboard-sounds",
            id: soundID.description, routeID: "sound.id", payload: request.jsonValue(), auditReason: auditReason,
            catalog: "soundboard-catalog", decode: { try SoundboardSound(data: $0) })
    }

    /// Deletes one guild sound with the same caller-created/other permissions as modifyGuild.
    /// - Parameters:
    ///   - guildID: Exact owning guild and major rate partition.
    ///   - soundID: Exact sound target; a missing sound remains an API error.
    ///   - auditReason: Optional supported reason, at most 512 Unicode scalars before encoding.
    /// - Returns: One unsafe DELETE requiring empty HTTP 204, with scoped sound/guild/audit invalidation.
    /// - Throws: Descriptor/audit errors now; API/transport or uncertain deletion outcomes during execution.
    public static func deleteGuild(guildID: GuildID, soundID: SoundboardSoundID,
                                   auditReason: String? = nil) throws -> Endpoint<EmptyResponse> {
        try expressionGuildMutation("DELETE", guildID: guildID, resource: "soundboard-sounds", routeResource: "soundboard-sounds",
            id: soundID.description, routeID: "sound.id", auditReason: auditReason, successStatuses: [204],
            catalog: "soundboard-catalog", decode: { try EmptyResponse(data: $0) })
    }

    /// Plays one sound in a voice channel to which the bot is already connected.
    /// - Parameters:
    ///   - channelID: Exact connected voice channel and channel major rate partition.
    ///   - request: Validated sound ID and optional sourceGuildID; the source is required for another guild's sound.
    /// - Returns: One unsafe POST requiring empty HTTP 204. Discord requires SPEAK and USE_SOUNDBOARD,
    ///   plus USE_EXTERNAL_SOUNDS for another guild's sound, and a connected voice state with deaf, self_deaf,
    ///   mute and suppress all false. This operation opens no voice transport and changes no sound metadata.
    /// - Throws: Body/descriptor errors now; permission/voice-state/API/transport or uncertain playback outcomes later.
    ///   Ambiguous playback never replays automatically; no audit reason, hidden voice join or cache invalidation occurs.
    public static func send(channelID: ChannelID, request: SoundboardSoundSend) throws -> Endpoint<EmptyResponse> {
        try Endpoint(method: "POST", path: ["channels", channelID.description, "send-soundboard-sound"],
            route: "/channels/{channel.id}/send-soundboard-sound", authentication: .bot,
            successStatuses: [204], majorParameter: channelID.description, body: guildJSON(request.jsonValue()),
            decode: { try EmptyResponse(data: $0) })
    }
}
