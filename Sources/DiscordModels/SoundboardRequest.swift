import DiscordCore
import Foundation

/// Validated API v10 POST /guilds/{guild.id}/soundboard-sounds body; CREATE_GUILD_EXPRESSIONS
/// is required and success emits Guild Soundboard Sound Create. Discord validates MP3/Ogg content,
/// the maximum 5.2-second duration, current guild capacity and selector eligibility.
public struct GuildSoundboardSoundCreate: GuildRequestPayload {
    private let fields: [String: JSONValue]

    /// Validates bounded upload syntax and selected settings without audio decoding or network activity.
    /// - Parameters:
    ///   - name: Exact sound name of 2...32 Unicode scalars.
    ///   - sound: Canonical base64 data URI using audio/mpeg (MP3) or audio/ogg, with nonempty decoded
    ///     data at most 512000 bytes. This conservative local decimal-kilobyte cap follows the written
    ///     reference's ambiguous "512kb"; sticker uploads separately use its explicit 512 KiB cap.
    ///   - volume: Absent by default (Discord defaults to 1), null, or a finite value in 0...1 inclusive.
    ///   - emojiID: Absent by default, null, or exact custom emoji snowflake.
    ///   - emojiName: Absent by default, null, or Unicode selector of 1...32 scalars per the official preview.
    ///     Both selector fields remain independent as documented; actual emoji compatibility is checked upstream.
    /// - Throws: Safe invalid-value errors for invalid text/media/volume, or limit-exceeded for oversized
    ///   decoded audio. Work is synchronous; no I/O, logging, cancellation suspension or resource ownership occurs.
    public init(name: String, sound: String, volume: Field<Double> = .absent,
                emojiID: Field<EmojiID> = .absent, emojiName: Field<String> = .absent) throws {
        var result = try soundboardRequestSettings(volume: volume, emojiID: emojiID, emojiName: emojiName)
        result["name"] = try guildRequestText(name, length: 2...32)
        result["sound"] = try expressionRequestDataURI(sound, mediaTypes: ["audio/mpeg", "audio/ogg"], maximumBytes: 512_000)
        fields = result
    }

    /// Returns the validated upload and exact optional/null settings without adding upstream defaults.
    /// - Returns: Immutable body; explicit serialization deliberately exposes the encoded audio.
    public func jsonValue() -> JSONValue { .object(fields) }
}

/// Validated API v10 PATCH /guilds/{guild.id}/soundboard-sounds/{sound.id} metadata body.
/// Own sounds need CREATE_GUILD_EXPRESSIONS or MANAGE_GUILD_EXPRESSIONS; others need
/// MANAGE_GUILD_EXPRESSIONS. Media replacement is not part of this endpoint.
public struct GuildSoundboardSoundModify: GuildRequestPayload {
    private let fields: [String: JSONValue]

    /// Validates selected changes without fetching, merging or mutating a current sound snapshot.
    /// - Parameters:
    ///   - name: Absent by default or a nonnull name of 2...32 Unicode scalars.
    ///   - volume: Absent by default, null, or a finite value in 0...1 inclusive.
    ///   - emojiID: Absent by default, null to clear, or exact custom emoji ID.
    ///   - emojiName: Absent by default, null to clear, or selector of 1...32 Unicode scalars.
    ///     Emoji validity and the independently documented selector combination remain server checks.
    /// - Throws: Safe invalid-value errors for null/invalid names, invalid emoji text or nonfinite/out-of-range
    ///   volumes. Work is synchronous and side-effect free; no tasks, resources or cancellation suspension occur.
    public init(name: Field<String> = .absent, volume: Field<Double> = .absent,
                emojiID: Field<EmojiID> = .absent, emojiName: Field<String> = .absent) throws {
        var result = try soundboardRequestSettings(volume: volume, emojiID: emojiID, emojiName: emojiName)
        try guildRequestField(name, name: "name", into: &result) { try guildRequestText($0, length: 2...32) }
        fields = result
    }

    /// Returns exact selected changes without inferring no-op state from an older server snapshot.
    /// - Returns: Immutable PATCH object preserving omitted/null settings; empty selections produce `{}`.
    public func jsonValue() -> JSONValue { .object(fields) }
}

/// Validated API v10 POST /channels/{channel.id}/send-soundboard-sound body.
/// Requires SPEAK and USE_SOUNDBOARD, plus USE_EXTERNAL_SOUNDS for another guild's sound.
/// The caller must already be connected to the destination voice channel without deaf, self_deaf,
/// mute or suppress. This body neither establishes a voice connection nor guarantees these live conditions.
public struct SoundboardSoundSend: GuildRequestPayload {
    private let fields: [String: JSONValue]

    /// Constructs one explicit play request without discovering or inferring a sound's source guild.
    /// - Parameters:
    ///   - soundID: Required exact sound ID, including small default-sound IDs.
    ///   - sourceGuildID: Absent by default, nullable per the official OpenAPI preview, or source guild.
    ///     An explicit source guild is required when playing another server's sound; callers supply
    ///     that context because this synchronous value cannot infer current destination ownership.
    /// - Throws: Only safe field-encoding validation errors; every typed ID is already representable.
    ///   Work is synchronous and has no I/O, tasks, resource ownership or cancellation suspension.
    public init(soundID: SoundboardSoundID, sourceGuildID: Field<GuildID> = .absent) throws {
        var result: [String: JSONValue] = ["sound_id": .string(soundID.description)]
        try guildRequestField(sourceGuildID, name: "source_guild_id", nullable: true, into: &result) {
            .string($0.description)
        }
        fields = result
    }

    /// Returns the exact sound/source selection without checking current voice state or playing audio.
    /// - Returns: Required sound ID and only explicitly selected source-guild presence.
    public func jsonValue() -> JSONValue { .object(fields) }
}

/// Encodes shared soundboard volume and emoji settings with exact omission/null semantics.
/// - Parameters:
///   - volume: Omitted, null, or finite normalized volume in 0...1 inclusive.
///   - emojiID: Omitted, null, or custom emoji ID; no current resource lookup occurs.
///   - emojiName: Omitted, null, or unnormalized text of 1...32 Unicode scalars.
/// - Returns: Immutable selected wire fields, potentially empty, with independently documented selectors.
/// - Throws: Safe invalid-value errors for out-of-range/nonfinite volume or invalid emoji-name length;
///   JSON numeric errors only if finite Double formatting violates JSON grammar. No input is logged.
func soundboardRequestSettings(volume: Field<Double>, emojiID: Field<EmojiID>,
                               emojiName: Field<String>) throws -> [String: JSONValue] {
    var result: [String: JSONValue] = [:]
    try guildRequestField(volume, name: "volume", nullable: true, into: &result) {
        guard $0.isFinite, (0...1).contains($0) else { throw DiscordError.validation(.invalidValue) }
        return .number(try JSONNumber(rawValue: String($0)))
    }
    try guildRequestField(emojiID, name: "emoji_id", nullable: true, into: &result) { .string($0.description) }
    try guildRequestField(emojiName, name: "emoji_name", nullable: true, into: &result) {
        try guildRequestText($0, length: 1...32)
    }
    return result
}
