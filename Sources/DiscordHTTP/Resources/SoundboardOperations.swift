import DiscordCore
import DiscordModels

/// Explicit metadata request reduction for caller-owned guild sound snapshots, without opening voice or fetching audio.
public enum SoundboardOperations {
    /// Omits a guild sound PATCH when every requested metadata field equals the caller's snapshot.
    /// - Parameters:
    ///   - guildID: Owning guild; a present snapshot owner must match. Absent ownership is left to Discord.
    ///   - current: Caller-owned sound snapshot; no freshness, availability or permission is inferred.
    ///   - request: Validated metadata changes; omission is ignored, explicit null remains an instruction.
    ///   - auditReason: Optional supported reason validated only for a necessary mutation descriptor.
    /// - Returns: Nil for empty/matching edits or one unsafe PATCH. Exact numeric lexemes compare conservatively;
    ///   e.g. 1 and 1.0 may yield a redundant write. Playback is never deduplicated from metadata.
    /// - Throws: Invalid-value for mismatched/null ownership or an incompatible request root; descriptor/audit errors propagate.
    ///   A default-sound snapshot without guild ownership cannot prove mutation eligibility; Discord is authoritative.
    public static func modifyGuildIfChanged(guildID: GuildID, current: SoundboardSound,
        request: GuildSoundboardSoundModify, auditReason: String? = nil) throws -> Endpoint<SoundboardSound>? {
        switch current.guildID {
        case .absent: break
        case .value(let owner) where owner == guildID: break
        default: throw DiscordError.validation(.invalidValue)
        }
        guard try expressionFieldsChanged(current.rawFields, request: request.jsonValue()) else { return nil }
        return try SoundboardEndpoints.modifyGuild(guildID: guildID, soundID: current.soundID,
            request: request, auditReason: auditReason)
    }
}
