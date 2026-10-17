import DiscordCore
import Foundation

/// Status of asynchronous invite allowlist CSV processing, API v10 verified 2026-10-16.
/// Response RawValue wrappers preserve future values; unspecified is not success.
public enum InviteTargetUsersJobStatus: Int, Sendable {
    case unspecified = 0
    case processing = 1
    case completed = 2
    case failed = 3
}

/// Complete asynchronous CSV-processing status. A successful upload acknowledges submission,
/// while only status completed reports successful processing. Server messages stay redacted.
/// Verified against the Invite reference and official discord-api-spec on 2026-10-16.
public struct InviteTargetUsersJob: MessageResponseValue, Equatable {
    public let status: RawValue<InviteTargetUsersJobStatus>
    public let totalUsers: UInt32
    public let processedUsers: UInt32
    public let createdAt: Nullable<DiscordTimestamp>
    public let completedAt: Nullable<DiscordTimestamp>
    public let errorMessage: Nullable<String>
    public let rawFields: [String: JSONValue]

    /// Parses every job-status field with exact future-field retention, without polling or sleeping.
    /// - Parameters:
    ///   - data: Complete UTF-8 JSON object containing all six documented status fields.
    ///   - limits: Whole-document byte/depth/node limits, default 1 MiB/64/100,000.
    /// - Throws: JSON syntax/bounds errors or sanitized invalid-response errors for omitted, mistyped,
    ///   forbidden-null, overflowing or fractional modeled values. Counts may span the full UInt32 range;
    ///   no undocumented relationship between counters/timestamps/status is imposed on snapshots.
    /// Construction is synchronous, performs no I/O, and transfers no resource ownership.
    public init(data: Data, limits: JSONLimits = .default) throws {
        let object = try PayloadObject(JSONValue.parse(data, limits: limits), limits: limits)
        status = try object.required("status", RawValue<InviteTargetUsersJobStatus>.self)
        totalUsers = try object.required("total_users", UInt32.self)
        processedUsers = try object.required("processed_users", UInt32.self)
        createdAt = try object.required("created_at", Nullable<DiscordTimestamp>.self)
        completedAt = try object.required("completed_at", Nullable<DiscordTimestamp>.self)
        errorMessage = try object.required("error_message", Nullable<String>.self)
        rawFields = object.resource.fields
    }
}

/// Complete field projection of the explicitly partial guild embedded within an invite.
/// An ID is required; partial-object omissions are preserved instead of hydrating a Guild.
public struct ChannelInviteGuild: MessageResponseValue, MessageTreeProjectable, Equatable {
    public let id: GuildID
    public let name: Field<String>
    public let splash: Field<String>
    public let banner: Field<String>
    public let guildDescription: Field<String>
    public let icon: Field<String>
    public let features: Field<[String]>
    public let verificationLevel: Field<Int>
    public let vanityURLCode: Field<String>
    public let nsfwLevel: Field<Int>
    public let nsfw: Field<Bool>
    public let premiumSubscriptionCount: Field<Int>
    public let rawFields: [String: JSONValue]

    /// Decodes a bounded partial guild snapshot with exact unknown-field preservation.
    /// - Parameters:
    ///   - data: UTF-8 object with required snowflake id and optional partial fields.
    ///   - limits: Whole-document JSON limits; defaults to the package's bounded parser policy.
    /// - Throws: Syntax/bounds errors or sanitized invalid-response errors for incompatible known fields.
    /// No permission, membership, freshness or current-guild authority is inferred; no I/O occurs.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects one partial guild from an already bounded immutable containing document.
    /// - Parameters:
    ///   - value: Object subtree with required ID; optional nulls follow the official InviteGuild schema.
    ///   - limits: Bounds already applied to the complete containing document.
    /// - Throws: Sanitized invalid-response for missing ID, forbidden null or incompatible known fields.
    /// Work is synchronous with no reparse, suspension, hydration or cache side effects.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        id = try object.required("id", GuildID.self)
        name = try object.field("name", String.self)
        splash = try object.field("splash", String.self, nullable: true)
        banner = try object.field("banner", String.self, nullable: true)
        guildDescription = try object.field("description", String.self, nullable: true)
        icon = try object.field("icon", String.self, nullable: true)
        features = try object.field("features", [String].self)
        verificationLevel = try object.field("verification_level", Int.self, nullable: true)
        vanityURLCode = try object.field("vanity_url_code", String.self, nullable: true)
        nsfwLevel = try object.field("nsfw_level", Int.self, nullable: true)
        nsfw = try object.field("nsfw", Bool.self, nullable: true)
        premiumSubscriptionCount = try object.field("premium_subscription_count", Int.self)
        rawFields = object.resource.fields
    }
}

/// Complete field projection of an invite's partial assigned role, without requiring full GuildRole fields.
/// Discord's written seven-field role contract and preview's optional permissions are preserved.
public struct ChannelInviteRole: MessageResponseValue, MessageTreeProjectable, Equatable {
    public let id: RoleID
    public let name: Field<String>
    public let position: Field<Int>
    public let color: Field<Int>
    public let colors: Field<GuildRoleColors>
    public let icon: Field<String>
    public let unicodeEmoji: Field<String>
    public let permissions: Field<String>
    public let rawFields: [String: JSONValue]

    /// Parses a partial role without fetching its guild or inferring assignment eligibility.
    /// - Parameters:
    ///   - data: Complete UTF-8 partial role object with required exact snowflake id.
    ///   - limits: Whole-document bounds covering all known and unknown fields.
    /// - Throws: Parser/bounds errors or sanitized invalid-response errors for malformed known fields.
    /// Missing partial fields remain absent, while nullable icon/emoji values preserve explicit null.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects one role subtree already checked under its containing document's parser bounds.
    /// - Parameters:
    ///   - value: Partial role object; no full role permission or hierarchy context is assumed.
    ///   - limits: Established outer bounds, reused for exact scalar decoding.
    /// - Throws: Sanitized invalid-response for missing ID, wrong types or invalid permission decimal strings.
    /// Construction is synchronous and retains exact unknown values without I/O or suspension.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        id = try object.required("id", RoleID.self)
        name = try object.field("name", String.self)
        position = try object.field("position", Int.self)
        color = try object.field("color", Int.self)
        colors = try object.messageField("colors", GuildRoleColors.self)
        icon = try object.field("icon", String.self, nullable: true)
        unicodeEmoji = try object.field("unicode_emoji", String.self, nullable: true)
        permissions = try object.field("permissions", String.self)
        if case .value(let permissions) = permissions { try validateChannelPermissionBits(permissions) }
        rawFields = object.resource.fields
    }
}
