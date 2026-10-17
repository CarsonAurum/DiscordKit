import DiscordCore
import Foundation

/// API v10 role colors, including the documented gradient/holographic styles.
/// ENHANCED_ROLE_COLORS is required for secondary/tertiary colors; the server checks guild eligibility.
/// See https://docs.discord.com/developers/topics/permissions#role-colors-object.
public struct GuildRoleColorsRequest: GuildRequestPayload {
    private let fields: [String: JSONValue]

    /// Validates RGB components and Discord's fixed holographic color triple.
    /// All `Field` parameters default to `.absent`, preserving server defaults or current values unless stated otherwise.
    /// - Parameters:
    ///   - primaryColor: Required 24-bit RGB integer 0...16777215; zero selects no primary color.
    ///   - secondaryColor: Optional gradient RGB value in the same range; nil serializes as null.
    ///   - tertiaryColor: Optional holographic RGB value; if nonnil, the exact required triple is
    ///     primary 11127295, secondary 16759788, tertiary 16761760. Nil serializes as null.
    /// - Throws: Safe validation errors for out-of-range RGB values or unsupported holographic triples.
    public init(primaryColor: Int, secondaryColor: Int? = nil, tertiaryColor: Int? = nil) throws {
        var result: [String: JSONValue] = ["primary_color": try guildRequestRange(primaryColor, 0...0xFF_FFFF),
                                         "secondary_color": .null, "tertiary_color": .null]
        if let secondaryColor { result["secondary_color"] = try guildRequestRange(secondaryColor, 0...0xFF_FFFF) }
        if let tertiaryColor {
            result["tertiary_color"] = try guildRequestRange(tertiaryColor, 0...0xFF_FFFF)
            guard primaryColor == 11_127_295, secondaryColor == 16_759_788, tertiaryColor == 16_761_760
            else { throw DiscordError.validation(.invalidValue) }
        }
        fields = result
    }

    /// Produces the complete colors object with explicit nullable gradient components.
    /// - Returns: Exact integral RGB values without floating-point conversion or feature lookup.
    public func jsonValue() -> JSONValue { .object(fields) }
}

/// API v10 POST /guilds/{guild.id}/roles; requires MANAGE_ROLES and emits Guild Role Create.
/// The colors object supersedes the deprecated single color field; feature eligibility is checked upstream.
public struct GuildRoleCreate: GuildRequestPayload {
    private let fields: [String: JSONValue]

    /// Validates explicitly selected creation settings while retaining Discord's omitted defaults.
    /// All `Field` parameters default to `.absent`, preserving server defaults or current values unless stated otherwise.
    /// - Parameters:
    ///   - name: Omitted or role name of 1...100 scalars, following the official OpenAPI preview.
    ///   - permissions: Omitted or nonempty unsigned ASCII decimal permissions of arbitrary width.
    ///   - color: Deprecated omitted 24-bit RGB color; cannot be combined with a nonnull colors object.
    ///   - colors: Omitted modern solid/gradient/holographic colors; prefer this over color.
    ///   - hoist: Omitted or whether the role appears separately in the sidebar.
    ///   - icon: Nullable canonical base64 image or data URI; ROLE_ICONS and image eligibility are server checks.
    ///   - unicodeEmoji: Nullable Unicode emoji of 1...100 scalars; cannot be nonnull together with icon.
    ///   - mentionable: Omitted or whether members may mention the role.
    /// - Throws: Safe validation errors for unsupported nulls, malformed decimal/image syntax, overlong names,
    ///   out-of-range RGB values or conflicting color/icon selectors. Inputs are excluded from diagnostics.
    public init(name: Field<String> = .absent, permissions: Field<String> = .absent,
                color: Field<Int> = .absent, colors: Field<GuildRoleColorsRequest> = .absent,
                hoist: Field<Bool> = .absent, icon: Field<String> = .absent,
                unicodeEmoji: Field<String> = .absent, mentionable: Field<Bool> = .absent) throws {
        fields = try guildRequestRoleFields(nullable: false, name: name, permissions: permissions, color: color,
            colors: colors, hoist: hoist, icon: icon, unicodeEmoji: unicodeEmoji, mentionable: mentionable)
    }

    /// Produces the validated role-creation body without adding the upstream defaults.
    /// - Returns: Exact object; an empty object requests Discord's default new role.
    public func jsonValue() -> JSONValue { .object(fields) }
}

/// API v10 PATCH /guilds/{guild.id}/roles/{role.id}; requires MANAGE_ROLES and emits Guild Role Update.
/// Every documented field is optional and nullable; Discord checks hierarchy, features and permission ceilings.
public struct GuildRoleModify: GuildRequestPayload {
    private let fields: [String: JSONValue]

    /// Validates nullable role changes while preserving arbitrary-width permission decimals.
    /// All `Field` parameters default to `.absent`, preserving server defaults or current values unless stated otherwise.
    /// - Parameters:
    ///   - name: Nullable role name of 1...100 scalars; absent leaves unchanged.
    ///   - permissions: Nullable permissions; values must be nonempty ASCII unsigned decimals of arbitrary width.
    ///   - color: Deprecated nullable 24-bit RGB value; cannot be combined with nonnull colors.
    ///   - colors: Nullable modern solid/gradient/holographic colors; unknown feature eligibility remains upstream.
    ///   - hoist: Nullable sidebar grouping setting.
    ///   - icon: Nullable canonical base64 icon or image data URI; null clears the icon.
    ///   - unicodeEmoji: Nullable emoji of 1...100 scalars; cannot be nonnull together with icon.
    ///   - mentionable: Nullable mentionability setting.
    /// - Throws: Safe validation errors for malformed decimals/images, overlong names, out-of-range RGB
    ///   values or conflicting color/icon selectors. Null semantics remain exactly as requested.
    public init(name: Field<String> = .absent, permissions: Field<String> = .absent,
                color: Field<Int> = .absent, colors: Field<GuildRoleColorsRequest> = .absent,
                hoist: Field<Bool> = .absent, icon: Field<String> = .absent,
                unicodeEmoji: Field<String> = .absent, mentionable: Field<Bool> = .absent) throws {
        fields = try guildRequestRoleFields(nullable: true, name: name, permissions: permissions, color: color,
            colors: colors, hoist: hoist, icon: icon, unicodeEmoji: unicodeEmoji, mentionable: mentionable)
    }

    /// Produces exact role changes without inferring the previously selected icon/color style.
    /// - Returns: Immutable nullable PATCH body, empty when no setting was selected.
    public func jsonValue() -> JSONValue { .object(fields) }
}

/// One API v10 PATCH /guilds/{guild.id}/roles entry; the endpoint requires MANAGE_ROLES.
/// Hierarchy limits and equal-position ordering by ID are applied by Discord, not inferred locally.
public struct GuildRolePosition: GuildRequestPayload {
    public let id: RoleID
    private let fields: [String: JSONValue]

    /// Constructs one partial role-position entry with exact signed numeric precision.
    /// All `Field` parameters default to `.absent`, preserving server defaults or current values unless stated otherwise.
    /// - Parameters:
    ///   - id: Required role snowflake, retained as an unsigned decimal string.
    ///   - position: Omitted, null or signed sorting position; no unpublished range is imposed.
    /// - Throws: Only numeric formatting validation errors; Swift integral formatting is canonical JSON.
    public init(id: RoleID, position: Field<Int> = .absent) throws {
        self.id = id
        var result: [String: JSONValue] = ["id": .string(id.description)]
        try guildRequestField(position, name: "position", nullable: true, into: &result) { try guildRequestNumber($0) }
        fields = result
    }

    /// Produces one role sorting entry without sorting, renumbering or collapsing equal positions.
    /// - Returns: Required role ID and the explicitly selected nullable position.
    public func jsonValue() -> JSONValue { .object(fields) }
}

/// API v10 POST /guilds/{guild.id}/prune; requires MANAGE_GUILD and KICK_MEMBERS, or ADMINISTRATOR
/// when PRUNE_REQUIRES_ADMIN is enabled. This explicit mutation can remove multiple inactive members.
public struct GuildPrune: GuildRequestPayload {
    private let fields: [String: JSONValue]

    /// Validates prune parameters without evaluating membership or computing a local count.
    /// All `Field` parameters default to `.absent`, preserving server defaults or current values unless stated otherwise.
    /// - Parameters:
    ///   - days: Omitted or 1...30 inactivity days; omitted defaults to seven upstream.
    ///   - computePruneCount: Omitted or count switch; false is recommended for large guilds and returns null pruned.
    ///   - includeRoles: Omitted or at most 100 distinct roles eligible for pruning; members with extra roles remain excluded upstream.
    ///   - reason: Deprecated JSON reason; prefer the endpoint's audit-log header. No unpublished cap is imposed.
    /// - Throws: Safe validation errors for invalid day bounds, duplicate IDs or forbidden nulls.
    public init(days: Field<Int> = .absent, computePruneCount: Field<Bool> = .absent,
                includeRoles: Field<[RoleID]> = .absent, reason: Field<String> = .absent) throws {
        var result: [String: JSONValue] = [:]
        try guildRequestField(days, name: "days", into: &result) { try guildRequestRange($0, 1...30) }
        try guildRequestField(computePruneCount, name: "compute_prune_count", into: &result) { .bool($0) }
        try guildRequestField(includeRoles, name: "include_roles", into: &result) {
            guard $0.count <= 100 else { throw DiscordError.validation(.limitExceeded) }; return try guildRequestIDs($0)
        }
        try guildRequestField(reason, name: "reason", into: &result) { .string($0) }
        fields = result
    }

    /// Produces one explicit prune request without fetching or silently broadening eligible roles.
    /// - Returns: Exact body, retaining omitted defaults and explicit false/empty selections.
    public func jsonValue() -> JSONValue { .object(fields) }
}

/// API v10 PATCH /guilds/{guild.id}/widget; requires MANAGE_GUILD and emits Guild Update.
public struct GuildWidgetModify: GuildRequestPayload {
    private let fields: [String: JSONValue]

    /// Validates widget settings without generating an invite or checking channel visibility.
    /// All `Field` parameters default to `.absent`, preserving server defaults or current values unless stated otherwise.
    /// - Parameters:
    ///   - enabled: Omitted or widget visibility; null is not supported by the settings schema.
    ///   - channelID: Omitted leaves unchanged; null disables invite generation; a value chooses its channel.
    /// - Throws: A safe validation error if enabled is explicitly null.
    public init(enabled: Field<Bool> = .absent, channelID: Field<ChannelID> = .absent) throws {
        var result: [String: JSONValue] = [:]
        try guildRequestField(enabled, name: "enabled", into: &result) { .bool($0) }
        try guildRequestField(channelID, name: "channel_id", nullable: true, into: &result) { .string($0.description) }
        fields = result
    }

    /// Produces exact widget settings without generating or exposing an invite.
    /// - Returns: Immutable PATCH body including an explicit null invite channel when selected.
    public func jsonValue() -> JSONValue { .object(fields) }
}

/// Builds the shared role field set, preserving the create/modify nullability distinction.
/// - Parameters:
///   - nullable: True for modifications where every documented field accepts null; false for creation.
///   - name: Optional role name, 1...100 Unicode scalars when nonnull.
///   - permissions: Arbitrary-width ASCII unsigned decimal permissions when nonnull.
///   - color: Deprecated optional RGB integer.
///   - colors: Modern optional complete colors object.
///   - hoist: Optional sidebar grouping flag.
///   - icon: Always-nullable icon transport string.
///   - unicodeEmoji: Always-nullable Unicode emoji of 1...100 scalars.
///   - mentionable: Optional mentionability flag.
/// - Returns: Validated body fields without adding defaults or mutating resources.
/// - Throws: Safe validation errors for unsupported nulls, invalid scalar/RGB ranges,
///   malformed decimal/image syntax or simultaneously nonnull color or icon alternatives.
private func guildRequestRoleFields(nullable: Bool, name: Field<String>, permissions: Field<String>,
                                    color: Field<Int>, colors: Field<GuildRoleColorsRequest>, hoist: Field<Bool>,
                                    icon: Field<String>, unicodeEmoji: Field<String>, mentionable: Field<Bool>) throws -> [String: JSONValue] {
    var result: [String: JSONValue] = [:]
    try guildRequestField(name, name: "name", nullable: nullable, into: &result) { try guildRequestText($0, length: 1...100) }
    try guildRequestField(permissions, name: "permissions", nullable: nullable, into: &result) {
        guard !$0.isEmpty, $0.utf8.allSatisfy({ (48...57).contains($0) }) else { throw DiscordError.validation(.invalidValue) }
        return .string($0)
    }
    try guildRequestField(color, name: "color", nullable: nullable, into: &result) { try guildRequestRange($0, 0...0xFF_FFFF) }
    try guildRequestField(colors, name: "colors", nullable: nullable, into: &result) { $0.jsonValue() }
    try guildRequestField(hoist, name: "hoist", nullable: nullable, into: &result) { .bool($0) }
    try guildRequestField(icon, name: "icon", nullable: true, into: &result) { try guildRequestImage($0) }
    try guildRequestField(unicodeEmoji, name: "unicode_emoji", nullable: true, into: &result) { try guildRequestText($0, length: 1...100) }
    try guildRequestField(mentionable, name: "mentionable", nullable: nullable, into: &result) { .bool($0) }
    if case .value = color, case .value = colors { throw DiscordError.validation(.invalidValue) }
    if case .value = icon, case .value = unicodeEmoji { throw DiscordError.validation(.invalidValue) }
    return result
}
