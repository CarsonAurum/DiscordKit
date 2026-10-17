import DiscordCore
import Foundation

/// An immutable, validated API v10 guild body with redacted default diagnostics.
///
/// Construct concrete request types with named parameters. Validation performs no I/O, permission
/// lookup, rate admission, pagination or retry; Discord checks current guild features, hierarchy,
/// ownership and permissions. `jsonValue()` deliberately exposes outgoing content and credentials,
/// so callers must keep that explicit representation out of diagnostics.
public protocol GuildRequestPayload: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// Produces a previously validated body while preserving absent, null and value distinctions.
    /// - Returns: The exact JSON body without fetching server state or adding omitted defaults.
    func jsonValue() -> JSONValue
}

extension GuildRequestPayload {
    /// Provides a stable diagnostic marker without exposing personal content, images or credentials.
    public var description: String { "\(Self.self)(redacted)" }
    /// Provides the same safe marker for debugging and collection descriptions.
    public var debugDescription: String { description }
    /// Prevents recursive reflection from exposing the outgoing body or nested credentials.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}

/// Forum/media thread-search tag matching, exposed by Discord's official API v10 OpenAPI preview.
/// The prose Guild channel-creation reference omits this compatibility setting; response unknown fields
/// remain preserved independently. See https://github.com/discord/discord-api-spec/blob/main/specs/openapi.json.
public enum GuildDefaultTagSetting: String, Sendable, CaseIterable {
    /// Search results must contain every tag selected in the search query.
    case matchAll = "match_all"
    /// Search results must contain at least one tag selected in the search query.
    case matchSome = "match_some"
}

/// API v10 PATCH /guilds/{guild.id}; requires MANAGE_GUILD, with ADMINISTRATOR for COMMUNITY changes.
/// See https://docs.discord.com/developers/resources/guild#modify-guild. Success emits Guild Update.
public struct GuildModify: GuildRequestPayload {
    private let fields: [String: JSONValue]

    /// Validates guild settings without checking ownership, feature eligibility or channel membership.
    /// All `Field` parameters default to `.absent`, preserving server defaults or current values unless stated otherwise.
    /// - Parameters:
    ///   - name: Omitted or 2...100 Unicode scalars after trimming surrounding whitespace; null is forbidden.
    ///   - region: Deprecated nullable voice region; prefer channel RTC regions. Nonnull values must be nonempty.
    ///   - verificationLevel: Nullable documented verification level 0...4; null retains upstream semantics.
    ///   - defaultMessageNotifications: Nullable notification level 0...1.
    ///   - explicitContentFilter: Nullable content filter level 0...2.
    ///   - afkChannelID: Nullable voice channel used for AFK; null clears it.
    ///   - afkTimeout: Omitted or 60, 300, 900, 1800 or 3600 seconds; null is forbidden.
    ///   - icon: Nullable canonical base64 image or image data URI; null removes the icon.
    ///   - splash: Nullable canonical PNG/JPEG image data; current feature eligibility is checked by Discord.
    ///   - discoverySplash: Nullable discovery image; Discord checks dimensions, format and eligibility.
    ///   - banner: Nullable banner image; animation and feature availability are server checks.
    ///   - systemChannelID: Nullable channel for system notices.
    ///   - systemChannelFlags: Omitted or the documented six suppression bits; null/unknown bits are rejected.
    ///   - rulesChannelID: Nullable Community rules channel.
    ///   - publicUpdatesChannelID: Nullable Community administrator updates channel.
    ///   - preferredLocale: Nullable nonempty locale identifier; Discord validates current supported locales.
    ///   - features: Omitted or up to 1521 distinct nonempty feature strings; Discord decides which features are mutable.
    ///   - description: Nullable server description, up to 300 Unicode scalars in the official schema.
    ///   - premiumProgressBarEnabled: Omitted or boost progress-bar visibility; null is forbidden.
    ///   - safetyAlertsChannelID: Nullable Community safety-alert channel.
    ///   - homeHeader: Nullable canonical base64 home-header image or image data URI, supported by the official
    ///     OpenAPI preview although omitted from the prose reference; dimensions/eligibility remain server checks.
    /// - Throws: Safe validation errors for forbidden nulls, invalid known enum values, image syntax,
    ///   name/timeout bounds, unknown writable flag bits or duplicate/empty features; input is never echoed.
    public init(name: Field<String> = .absent, region: Field<String> = .absent,
                verificationLevel: Field<GuildVerificationLevel> = .absent,
                defaultMessageNotifications: Field<GuildDefaultMessageNotificationLevel> = .absent,
                explicitContentFilter: Field<GuildExplicitContentFilterLevel> = .absent,
                afkChannelID: Field<ChannelID> = .absent, afkTimeout: Field<Int> = .absent,
                icon: Field<String> = .absent, splash: Field<String> = .absent,
                discoverySplash: Field<String> = .absent, banner: Field<String> = .absent,
                systemChannelID: Field<ChannelID> = .absent, systemChannelFlags: Field<GuildSystemChannelFlags> = .absent,
                rulesChannelID: Field<ChannelID> = .absent, publicUpdatesChannelID: Field<ChannelID> = .absent,
                preferredLocale: Field<String> = .absent, features: Field<[String]> = .absent,
                description: Field<String> = .absent, premiumProgressBarEnabled: Field<Bool> = .absent,
                safetyAlertsChannelID: Field<ChannelID> = .absent, homeHeader: Field<String> = .absent) throws {
        var result: [String: JSONValue] = [:]
        try guildRequestField(name, name: "name", into: &result) {
            let trimmed = $0.trimmingCharacters(in: .whitespacesAndNewlines)
            guard (2...100).contains(trimmed.unicodeScalars.count) else { throw DiscordError.validation(.invalidValue) }
            return .string($0)
        }
        try guildRequestField(region, name: "region", nullable: true, into: &result) { try guildRequestNonempty($0) }
        try guildRequestField(verificationLevel, name: "verification_level", nullable: true, into: &result) { try guildRequestRange($0.rawValue, 0...4) }
        try guildRequestField(defaultMessageNotifications, name: "default_message_notifications", nullable: true, into: &result) { try guildRequestRange($0.rawValue, 0...1) }
        try guildRequestField(explicitContentFilter, name: "explicit_content_filter", nullable: true, into: &result) { try guildRequestRange($0.rawValue, 0...2) }
        try guildRequestField(afkChannelID, name: "afk_channel_id", nullable: true, into: &result) { .string($0.description) }
        try guildRequestField(afkTimeout, name: "afk_timeout", into: &result) {
            guard [60, 300, 900, 1_800, 3_600].contains($0) else { throw DiscordError.validation(.invalidValue) }
            return try guildRequestNumber($0)
        }
        for (name, field) in [("icon", icon), ("splash", splash), ("discovery_splash", discoverySplash), ("banner", banner)] {
            try guildRequestField(field, name: name, nullable: true, into: &result) { try guildRequestImage($0) }
        }
        try guildRequestField(systemChannelID, name: "system_channel_id", nullable: true, into: &result) { .string($0.description) }
        try guildRequestField(systemChannelFlags, name: "system_channel_flags", into: &result) {
            guard $0.rawValue & ~UInt64(63) == 0 else { throw DiscordError.validation(.invalidValue) }
            return try guildRequestNumber($0.rawValue)
        }
        try guildRequestField(rulesChannelID, name: "rules_channel_id", nullable: true, into: &result) { .string($0.description) }
        try guildRequestField(publicUpdatesChannelID, name: "public_updates_channel_id", nullable: true, into: &result) { .string($0.description) }
        try guildRequestField(preferredLocale, name: "preferred_locale", nullable: true, into: &result) { try guildRequestNonempty($0) }
        try guildRequestField(features, name: "features", into: &result) {
            guard $0.count <= 1_521, $0.allSatisfy({ !$0.isEmpty }), Set($0).count == $0.count else { throw DiscordError.validation(.invalidValue) }
            return .array($0.map { .string($0) })
        }
        try guildRequestField(description, name: "description", nullable: true, into: &result) { try guildRequestText($0, length: 0...300) }
        try guildRequestField(premiumProgressBarEnabled, name: "premium_progress_bar_enabled", into: &result) { .bool($0) }
        try guildRequestField(safetyAlertsChannelID, name: "safety_alerts_channel_id", nullable: true, into: &result) { .string($0.description) }
        try guildRequestField(homeHeader, name: "home_header", nullable: true, into: &result) { try guildRequestImage($0) }
        fields = result
    }

    /// Produces immutable guild settings, preserving deprecated fields only when explicitly requested.
    /// - Returns: Exact PATCH object; empty means no settings were selected.
    public func jsonValue() -> JSONValue { .object(fields) }
}

/// API v10 POST /guilds/{guild.id}/channels; requires MANAGE_CHANNELS and respects the permission ceiling.
/// Success emits Channel Create. Server features and boost-dependent bitrate limits remain server checks.
public struct GuildChannelCreate: GuildRequestPayload {
    private let fields: [String: JSONValue]

    /// Validates the documented creation fields against the requested channel kind, defaulting to text.
    /// All `Field` parameters default to `.absent`, preserving server defaults or current values unless stated otherwise.
    /// - Parameters:
    ///   - name: Required 1...100 scalar name; Discord may normalize eligible characters.
    ///   - type: Nullable guild channel kind; absent/null uses the upstream text default. DMs/threads are rejected.
    ///   - topic: Nullable text/announcement/forum/media topic, up to the creation endpoint's 1024 scalars.
    ///   - bitrate: Nullable voice/stage bitrate, 8000...384000 bits/s for voice or 8000...64000 for stage.
    ///   - userLimit: Nullable voice 0...99 or stage 0...10000 participant limit; zero means unlimited.
    ///   - rateLimitPerUser: Nullable 0...21600 second slowmode on text/voice/stage/forum/media channels.
    ///   - position: Nullable exact signed sorting position; no unpublished numeric bound is imposed.
    ///   - permissionOverwrites: Nullable list of at most 100 guild overwrites with distinct target/type pairs.
    ///   - parentID: Nullable category parent for noncategory guild channels.
    ///   - nsfw: Nullable age restriction, documented on text/voice/announcement/stage/forum creation.
    ///   - rtcRegion: Nullable voice/stage region identifier; null requests automatic selection.
    ///   - videoQualityMode: Nullable voice/stage automatic/full camera mode.
    ///   - defaultAutoArchiveDuration: Nullable text/announcement/forum/media archive default in minutes: 60, 1440, 4320 or 10080.
    ///   - defaultReactionEmoji: Nullable forum/media default reaction.
    ///   - availableTags: Nullable forum/media tags, at most 20 with distinct supplied IDs.
    ///   - defaultSortOrder: Nullable forum/media activity/creation order.
    ///   - defaultForumLayout: Nullable forum-only list/gallery/not-set layout.
    ///   - defaultThreadRateLimitPerUser: Nullable 0...21600 second initial slowmode on text/announcement/forum/media threads.
    ///   - flags: Nullable writable type-compatible flags; unknown/read-only flags are rejected.
    ///   - defaultTagSetting: Nullable forum/media search-tag matching mode from the official OpenAPI
    ///     preview, omitted in the prose table; absence preserves upstream defaults.
    /// - Throws: Safe validation errors for type-incompatible settings, duplicate overwrites/tags,
    ///   unknown kinds or enum values, invalid names, ranges and flag combinations.
    public init(name: String, type: Field<ChannelType> = .absent, topic: Field<String> = .absent,
                bitrate: Field<Int> = .absent, userLimit: Field<Int> = .absent,
                rateLimitPerUser: Field<Int> = .absent, position: Field<Int> = .absent,
                permissionOverwrites: Field<[ChannelPermissionOverwrite]> = .absent,
                parentID: Field<ChannelID> = .absent, nsfw: Field<Bool> = .absent,
                rtcRegion: Field<String> = .absent, videoQualityMode: Field<ChannelVideoQualityMode> = .absent,
                defaultAutoArchiveDuration: Field<Int> = .absent,
                defaultReactionEmoji: Field<ChannelDefaultReactionRequest> = .absent,
                availableTags: Field<[ChannelForumTagRequest]> = .absent,
                defaultSortOrder: Field<ChannelSortOrder> = .absent,
                defaultForumLayout: Field<ChannelForumLayout> = .absent,
                defaultThreadRateLimitPerUser: Field<Int> = .absent, flags: Field<ChannelFlags> = .absent,
                defaultTagSetting: Field<GuildDefaultTagSetting> = .absent) throws {
        let kind: Int
        if case .value(let value) = type { kind = value.rawValue } else { kind = 0 }
        guard [0, 2, 4, 5, 13, 14, 15, 16].contains(kind) else { throw DiscordError.validation(.invalidValue) }
        var result: [String: JSONValue] = ["name": try guildRequestText(name, length: 1...100)]
        try guildRequestField(type, name: "type", nullable: true, into: &result) { try guildRequestNumber($0.rawValue) }
        try guildRequestField(topic, name: "topic", nullable: true, into: &result) { try guildRequestText($0, length: 0...1_024) }
        try guildRequestField(bitrate, name: "bitrate", nullable: true, into: &result) { try guildRequestRange($0, 8_000...(kind == 13 ? 64_000 : 384_000)) }
        try guildRequestField(userLimit, name: "user_limit", nullable: true, into: &result) { try guildRequestRange($0, 0...(kind == 13 ? 10_000 : 99)) }
        try guildRequestField(rateLimitPerUser, name: "rate_limit_per_user", nullable: true, into: &result) { try guildRequestRange($0, 0...21_600) }
        try guildRequestField(position, name: "position", nullable: true, into: &result) { try guildRequestNumber($0) }
        try guildRequestField(permissionOverwrites, name: "permission_overwrites", nullable: true, into: &result) {
            let keys = $0.map { "\($0.type.rawValue):\($0.id.description)" }
            guard $0.count <= 100, Set(keys).count == keys.count else { throw DiscordError.validation(.invalidValue) }
            return .array($0.map { $0.jsonValue() })
        }
        try guildRequestField(parentID, name: "parent_id", nullable: true, into: &result) { .string($0.description) }
        try guildRequestField(nsfw, name: "nsfw", nullable: true, into: &result) { .bool($0) }
        try guildRequestField(rtcRegion, name: "rtc_region", nullable: true, into: &result) { try guildRequestNonempty($0) }
        try guildRequestField(videoQualityMode, name: "video_quality_mode", nullable: true, into: &result) { try guildRequestRange($0.rawValue, 1...2) }
        try guildRequestField(defaultAutoArchiveDuration, name: "default_auto_archive_duration", nullable: true, into: &result) {
            guard [60, 1_440, 4_320, 10_080].contains($0) else { throw DiscordError.validation(.invalidValue) }
            return try guildRequestNumber($0)
        }
        try guildRequestField(defaultReactionEmoji, name: "default_reaction_emoji", nullable: true, into: &result) { $0.jsonValue() }
        try guildRequestField(availableTags, name: "available_tags", nullable: true, into: &result) {
            let ids = $0.compactMap(\.id)
            guard $0.count <= 20, Set(ids).count == ids.count else { throw DiscordError.validation(.invalidValue) }
            return .array($0.map { $0.jsonValue() })
        }
        try guildRequestField(defaultSortOrder, name: "default_sort_order", nullable: true, into: &result) { try guildRequestRange($0.rawValue, 0...1) }
        try guildRequestField(defaultForumLayout, name: "default_forum_layout", nullable: true, into: &result) { try guildRequestRange($0.rawValue, 0...2) }
        try guildRequestField(defaultThreadRateLimitPerUser, name: "default_thread_rate_limit_per_user", nullable: true, into: &result) { try guildRequestRange($0, 0...21_600) }
        try guildRequestField(flags, name: "flags", nullable: true, into: &result) {
            var mask: UInt64 = [0, 2, 5, 15, 16].contains(kind) ? 1 << 21 : 0
            if [15, 16].contains(kind) { mask |= 1 << 4 }
            if kind == 16 { mask |= 1 << 15 }
            guard $0.rawValue & ~mask == 0 else { throw DiscordError.validation(.invalidValue) }
            if $0.rawValue & (1 << 21) != 0, case .value(true) = nsfw { throw DiscordError.validation(.invalidValue) }
            return try guildRequestNumber($0.rawValue)
        }
        try guildRequestField(defaultTagSetting, name: "default_tag_setting", nullable: true, into: &result) { .string($0.rawValue) }
        var allowed: Set<String> = ["name", "type", "position", "permission_overwrites"]
        if [0, 5, 15, 16].contains(kind) { allowed.formUnion(["topic", "default_auto_archive_duration", "default_thread_rate_limit_per_user"]) }
        if [0, 2, 13, 15, 16].contains(kind) { allowed.insert("rate_limit_per_user") }
        if [0, 2, 5, 13, 15, 16].contains(kind) { allowed.insert("parent_id") }
        if [0, 2, 5, 13, 15].contains(kind) { allowed.insert("nsfw") }
        if [2, 13].contains(kind) { allowed.formUnion(["bitrate", "user_limit", "rtc_region", "video_quality_mode"]) }
        if [15, 16].contains(kind) { allowed.formUnion(["default_reaction_emoji", "available_tags", "default_sort_order", "default_tag_setting"]) }
        if kind == 15 { allowed.insert("default_forum_layout") }
        if [0, 2, 5, 15, 16].contains(kind) { allowed.insert("flags") }
        guard Set(result.keys).isSubset(of: allowed) else { throw DiscordError.validation(.invalidValue) }
        fields = result
    }

    /// Produces the validated creation body without adding the default channel type.
    /// - Returns: Required name and every explicitly selected nullable optional setting.
    public func jsonValue() -> JSONValue { .object(fields) }
}

/// One API v10 PATCH /guilds/{guild.id}/channels entry; permission checks depend on changed fields.
/// Reordering requires MANAGE_CHANNELS; parent changes require access and destination permission,
/// and lock-permissions additionally requires MANAGE_ROLES. The endpoint checks array-wide constraints.
public struct GuildChannelPosition: GuildRequestPayload {
    public let id: ChannelID
    public let parentID: Field<ChannelID>
    private let fields: [String: JSONValue]

    /// Validates one position/parent/flags entry without fetching current channel state.
    /// All `Field` parameters default to `.absent`, preserving server defaults or current values unless stated otherwise.
    /// - Parameters:
    ///   - id: Required channel snowflake, preserving all unsigned bits.
    ///   - position: Nullable signed sorting position; equal positions are sorted by ID upstream.
    ///   - lockPermissions: Nullable permission-sync switch when moving to a new category.
    ///   - parentID: Absent leaves the parent unchanged; null moves out of a category.
    ///   - flags: Nullable writable channel bits; type-specific eligibility remains a server check.
    /// - Throws: Safe validation errors for read-only/unknown flag bits or numeric formatting failure.
    ///   At most one entry may send `parent_id` in a request; the endpoint validates the complete list.
    public init(id: ChannelID, position: Field<Int> = .absent, lockPermissions: Field<Bool> = .absent,
                parentID: Field<ChannelID> = .absent, flags: Field<ChannelFlags> = .absent) throws {
        self.id = id; self.parentID = parentID
        var result: [String: JSONValue] = ["id": .string(id.description)]
        try guildRequestField(position, name: "position", nullable: true, into: &result) { try guildRequestNumber($0) }
        try guildRequestField(lockPermissions, name: "lock_permissions", nullable: true, into: &result) { .bool($0) }
        try guildRequestField(parentID, name: "parent_id", nullable: true, into: &result) { .string($0.description) }
        try guildRequestField(flags, name: "flags", nullable: true, into: &result) {
            guard $0.rawValue & ~UInt64((1 << 1) | (1 << 4) | (1 << 15) | (1 << 21)) == 0 else { throw DiscordError.validation(.invalidValue) }
            return try guildRequestNumber($0.rawValue)
        }
        fields = result
    }

    /// Produces one immutable array entry, preserving null parent and null sorting settings.
    /// - Returns: Required channel ID and explicitly selected fields.
    public func jsonValue() -> JSONValue { .object(fields) }
}

/// Inserts a presence-aware value into an object, rejecting unsupported nulls before encoding.
/// - Parameters:
///   - field: Omitted, null or typed request value.
///   - name: Discord's exact JSON field name.
///   - nullable: Whether null is documented; defaults to false.
///   - fields: Object under construction; invalid partial state never escapes an initializer.
///   - encode: Synchronous validation/encoding closure, invoked only for a value.
/// - Throws: Safe invalid-value errors for forbidden nulls, or errors from `encode`.
func guildRequestField<Value>(_ field: Field<Value>, name: String, nullable: Bool = false,
                              into fields: inout [String: JSONValue], encode: (Value) throws -> JSONValue) throws {
    switch field {
    case .absent: break
    case .null:
        guard nullable else { throw DiscordError.validation(.invalidValue) }; fields[name] = .null
    case .value(let value): fields[name] = try encode(value)
    }
}

/// Encodes an integral value without conversion through floating-point JSON bridges.
/// - Parameter value: Exact signed or unsigned integer, including the platform extremes.
/// - Returns: A canonical decimal JSON number with all bits preserved.
/// - Throws: Numeric validation errors only if integer formatting violates JSON grammar.
func guildRequestNumber<Value: BinaryInteger>(_ value: Value) throws -> JSONValue {
    .number(try JSONNumber(rawValue: String(value)))
}

/// Validates the documented inclusive range of an integer setting.
/// - Parameters:
///   - value: Requested setting in the units documented by the caller.
///   - range: Inclusive published bounds; no guild-specific state is inferred.
/// - Returns: Exact JSON integer.
/// - Throws: Safe invalid-value errors outside the range, or JSON numeric validation failure.
func guildRequestRange(_ value: Int, _ range: ClosedRange<Int>) throws -> JSONValue {
    guard range.contains(value) else { throw DiscordError.validation(.invalidValue) }
    return try guildRequestNumber(value)
}

/// Validates Unicode scalar length while preserving the caller's exact string.
/// - Parameters:
///   - value: Unnormalized string, never included in failure diagnostics.
///   - length: Inclusive published character limits interpreted as Unicode scalars.
/// - Returns: The original string as JSON.
/// - Throws: A safe invalid-value error for a length outside the supplied bounds.
func guildRequestText(_ value: String, length: ClosedRange<Int>) throws -> JSONValue {
    guard length.contains(value.unicodeScalars.count) else { throw DiscordError.validation(.invalidValue) }
    return .string(value)
}

/// Rejects empty identifiers without claiming to validate current server-supported values.
/// - Parameter value: Exact region, locale or emoji string supplied by the caller.
/// - Returns: The unchanged nonempty string.
/// - Throws: A safe invalid-value error for empty input.
func guildRequestNonempty(_ value: String) throws -> JSONValue {
    guard !value.isEmpty else { throw DiscordError.validation(.invalidValue) }
    return .string(value)
}

/// Checks canonical base64 image transport syntax without decoding dimensions or guessing feature availability.
/// - Parameter value: Nonempty canonical base64 or an image data URI containing that base64.
/// - Returns: Original unchanged text; explicit serialization is the only content exposure.
/// - Throws: Safe invalid-value errors for malformed image data URIs, noncanonical base64 or empty bytes.
func guildRequestImage(_ value: String) throws -> JSONValue {
    let encoded: String
    if value.hasPrefix("data:") {
        guard let separator = value.range(of: ";base64,"), value.hasPrefix("data:image/"),
              value[..<separator.lowerBound].count > "data:image/".count
        else { throw DiscordError.validation(.invalidValue) }
        encoded = String(value[separator.upperBound...])
    } else { encoded = value }
    guard let data = Data(base64Encoded: encoded), !data.isEmpty, data.base64EncodedString() == encoded
    else { throw DiscordError.validation(.invalidValue) }
    return .string(value)
}

/// Encodes caller-ordered distinct snowflakes without converting them to JSON numbers.
/// - Parameter values: Exact typed IDs; empty arrays explicitly select none.
/// - Returns: Decimal-string array retaining input order and UInt64 extremes.
/// - Throws: A safe invalid-value error for duplicate IDs; no undocumented collection cap is imposed.
func guildRequestIDs<Tag>(_ values: [Snowflake<Tag>]) throws -> JSONValue {
    guard Set(values).count == values.count else { throw DiscordError.validation(.invalidValue) }
    return .array(values.map { .string($0.description) })
}

/// Validates a future timestamp against an explicitly injectable wall-clock snapshot.
/// - Parameters:
///   - value: Lossless timestamp to transmit; spelling and offset are preserved.
///   - referenceTime: Finite wall-clock instant used only for validation; not serialized.
///   - maximumSeconds: Published maximum duration in seconds, inclusive.
/// - Returns: Exact timestamp string; the server rechecks the deadline when processing the request.
/// - Throws: A safe invalid-value error for past, overlong or nonfinite reference times.
func guildRequestDeadline(_ value: DiscordTimestamp, referenceTime: Date, maximumSeconds: TimeInterval) throws -> JSONValue {
    let delta = value.date.timeIntervalSince(referenceTime)
    guard referenceTime.timeIntervalSince1970.isFinite, delta >= 0, delta <= maximumSeconds
    else { throw DiscordError.validation(.invalidValue) }
    return .string(value.rawValue)
}
