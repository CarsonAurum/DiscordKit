import DiscordCore
import Foundation

/// A voice region shared by global and guild-specific REST region catalogs.
/// IDs are opaque strings; deprecated regions should not be selected for new voice/Stage channels.
/// This spelling reuses the complete, presence-checked `GuildVoiceRegion` representation.
public typealias VoiceRegion = GuildVoiceRegion

/// Complete written API v10 voice-state structure, verified 2026-10-16 against
/// https://docs.discord.com/developers/resources/voice. This immutable REST/Gateway-compatible
/// snapshot does not join channels, own a voice connection, or establish current permissions.
public struct VoiceState: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Optional, nonnull guild identifier; absent outside guild-scoped payloads.
    public let guildID: Field<GuildID>
    /// Required nullable channel identifier; null represents a disconnected user.
    public let channelID: Nullable<ChannelID>
    /// Required user identifier, retaining the full unsigned 64-bit snowflake range.
    public let userID: UserID
    /// Optional nonnull guild member; related user remains the existing partial projection.
    public let member: Field<GuildMember>
    /// Required opaque session identifier; explicit raw access must be kept out of diagnostics.
    public let sessionID: String
    /// Whether the server has deafened the user.
    public let deaf: Bool
    /// Whether the server has muted the user.
    public let mute: Bool
    /// Whether the user's local client is deafened.
    public let selfDeaf: Bool
    /// Whether the user's local microphone is muted.
    public let selfMute: Bool
    /// Optional nonnull Go Live status; absence does not assert false.
    public let selfStream: Field<Bool>
    /// Whether the user's camera is enabled.
    public let selfVideo: Bool
    /// Whether speaking is suppressed, independently of mute settings.
    public let suppress: Bool
    /// Required nullable request-to-speak time, retaining exact fractional digits and offset.
    public let requestToSpeakTimestamp: Nullable<DiscordTimestamp>
    /// Complete original object, including unknown fields and exact numeric spelling; diagnostics redact it.
    public let rawFields: [String: JSONValue]

    /// Parses one bounded immutable snapshot synchronously without I/O or background work.
    /// - Parameters:
    ///   - data: Complete UTF-8 JSON object; documented required fields must be present, including nullable keys.
    ///   - limits: Whole-document byte/depth/node bounds, including unknown subtrees; defaults to 1 MiB/64/100,000.
    /// - Throws: `JSONValueError` for syntax, duplicate keys or exceeded bounds; sanitized
    ///   `DiscordError.transport(.invalidResponse)` for missing, forbidden-null, malformed or overflowing fields.
    /// No partial snapshot escapes failure, no external resource is acquired, and decoding does not suspend.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects a subtree after its complete containing document has passed JSON bounds.
    /// - Parameters:
    ///   - value: Original bounded object, including exact future values and numeric lexemes.
    ///   - limits: Root parser bounds reused for nested/scalar validation without reparsing the whole document.
    /// - Throws: Sanitized invalid-response errors for a nonobject root or incompatible known fields.
    /// Work is synchronous, shares immutable JSON storage and has no state, permission or ownership effects.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        guildID = try object.field("guild_id", GuildID.self)
        channelID = try object.required("channel_id", Nullable<ChannelID>.self)
        userID = try object.required("user_id", UserID.self)
        member = try object.messageField("member", GuildMember.self)
        sessionID = try object.required("session_id", String.self)
        deaf = try object.required("deaf", Bool.self)
        mute = try object.required("mute", Bool.self)
        selfDeaf = try object.required("self_deaf", Bool.self)
        selfMute = try object.required("self_mute", Bool.self)
        selfStream = try object.field("self_stream", Bool.self)
        selfVideo = try object.required("self_video", Bool.self)
        suppress = try object.required("suppress", Bool.self)
        requestToSpeakTimestamp = try object.required("request_to_speak_timestamp", Nullable<DiscordTimestamp>.self)
        rawFields = object.resource.fields
    }
}
