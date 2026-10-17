import DiscordCore
import Foundation

/// Known invite kinds. Response RawValue wrappers preserve future integral variants.
public enum ChannelInviteType: Int, Sendable {
    /// An invitation to a guild channel.
    case guild = 0
    /// An invitation to a group DM.
    case groupDM = 1
    /// A friend invitation; not created by the channel-invite route.
    case friend = 2
}

/// Supported voice invite targets; these are independent of invite kind.
public enum ChannelInviteTargetType: Int, Sendable {
    /// A currently streaming user, supplied as targetUserID.
    case stream = 1
    /// An embedded application, supplied as targetApplicationID.
    case embeddedApplication = 2
}

/// Known invite flags with preservation of every unknown UInt64 response bit.
public struct ChannelInviteFlags: OptionSet, Sendable, Hashable {
    /// Complete unmodified wire bitset.
    public let rawValue: UInt64
    /// A guest invitation for a voice channel; it does not prove permission to join.
    public static let isGuestInvite = Self(rawValue: 1 << 0)

    /// Wraps an exact bitset without discarding future flags or authorizing an operation.
    /// - Parameter rawValue: Complete unsigned 64-bit integer bits, including unknown combinations.
    public init(rawValue: UInt64) { self.rawValue = rawValue }
}

/// An explicitly partial embedded Application snapshot returned within a channel invite.
/// This projection deliberately does not require the full Application resource's configuration fields
/// or claim Application catalog parity. The official InviteApplicationResponse schema permits a null
/// application type; partial-object omissions and future integral types remain distinct and unchanged.
/// API v10, reviewed 2026-10-16 against the Invite reference and official discord-api-spec schema.
public struct ChannelInviteApplication: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Required application snowflake, retaining the complete unsigned 64-bit identifier.
    public let id: ApplicationID
    /// Optional application name; omitted partial fields are not synthesized from other resources.
    public let name: Field<String>
    /// Optional application description text, concealed from ordinary diagnostics.
    public let applicationDescription: Field<String>
    /// Optional nullable icon hash; omission and explicitly unset icons remain distinct.
    public let icon: Field<String>
    /// Optional nullable raw application type, preserving future integral values without asserting enum support.
    public let type: Field<Int>
    /// Complete original object, including all other Application fields and exact future numeric spellings.
    public let rawFields: [String: JSONValue]

    /// Parses one partial invite Application object under bounds covering all known and unknown fields.
    /// - Parameters:
    ///   - data: Complete UTF-8 object with a required decimal-string id; all other projected fields are optional.
    ///   - limits: Whole-document byte, depth and node limits, defaulting to 1 MiB/64/100,000.
    /// - Throws: JSON syntax/bounds errors or sanitized invalid-response errors for a missing/malformed ID,
    ///   forbidden null, wrong field type, nonintegral type token or native integer overflow.
    /// Construction is synchronous, performs no I/O or hydration and does not establish installation eligibility.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects an already bounded immutable subtree while retaining every unmodeled Application field.
    /// - Parameters:
    ///   - value: Original object subtree whose complete outer document passed parser limits.
    ///   - limits: The same limits established by the containing document.
    /// - Throws: Sanitized invalid-response errors for missing or incompatible modeled values; payloads stay redacted.
    /// No reparsing of nested values, I/O, suspension or resource ownership changes occur.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        id = try object.required("id", ApplicationID.self)
        name = try object.field("name", String.self)
        applicationDescription = try object.field("description", String.self)
        icon = try object.field("icon", String.self, nullable: true)
        type = try object.field("type", Int.self, nullable: true)
        rawFields = object.resource.fields
    }
}

/// Channel invite response including the complete invite/metadata field surface.
/// Embedded Guild/Application/Role snapshots are explicitly partial and never hydrated.
/// Scheduled events and channels use their complete resource projections.
/// API v10, verified 2026-10-16 against the official Channel and Invite references.
public struct ChannelInvite: MessageResponseValue, Equatable {
    /// Required invite kind; future integral variants survive.
    public let type: RawValue<ChannelInviteType>
    /// Required opaque invitation code. Ordinary diagnostics conceal it.
    public let code: String
    /// Optional partial guild snapshot; no permission or membership inference is made.
    public let guild: Field<ChannelInviteGuild>
    /// Required nullable partial channel; id/type are required for present objects.
    public let channel: Nullable<Channel>
    /// Optional inviter snapshot; unknown user-family fields remain in rawFields.
    public let inviter: Field<MessageAuthor>
    /// Optional target variant, including unknown future integral values.
    public let targetType: Field<RawValue<ChannelInviteTargetType>>
    /// Optional stream target user; no presence is inferred from targetType alone.
    public let targetUser: Field<MessageAuthor>
    /// Optional explicitly partial embedded-application snapshot, including nullable raw application type.
    public let targetApplication: Field<ChannelInviteApplication>
    /// Optional nullable approximate online count; not a real-time presence guarantee.
    /// Explicit null is accepted for compatibility with the official schema despite the written table's nonnullable marker.
    public let approximatePresenceCount: Field<Int>
    /// Optional nullable approximate member count; not a capacity claim.
    /// Explicit null is preserved for compatibility with the official schema's nullable response variant.
    public let approximateMemberCount: Field<Int>
    /// Required nullable expiry; null denotes no specified expiration.
    public let expiresAt: Nullable<DiscordTimestamp>
    /// Optional complete scheduled event, present only for applicable invite retrieval.
    public let guildScheduledEvent: Field<GuildScheduledEvent>
    /// Optional complete flag bitset; bit 0 is IS_GUEST_INVITE. Unknown bits survive.
    public let flags: Field<UInt64>
    /// Optional nullable partial role snapshots assigned upon acceptance; original order survives.
    /// Explicit null follows the official schema even though the written Invite table omits a nullable marker.
    public let roles: Field<[ChannelInviteRole]>
    /// Metadata use count; required when requiresMetadata is true at initialization.
    public let uses: Field<Int>
    /// Metadata maximum uses, zero for unlimited; omission is preserved for ordinary invites.
    public let maxUses: Field<Int>
    /// Metadata lifetime in seconds, zero for never; omission is preserved.
    public let maxAge: Field<Int>
    /// Metadata temporary-membership setting, without a default inferred on responses.
    public let temporary: Field<Bool>
    /// Metadata creation time preserving offset and nanosecond precision.
    public let createdAt: Field<DiscordTimestamp>
    /// Optional guild identifier exposed by the official preview schema; no hidden lookup occurs.
    public let guildID: Field<GuildID>
    /// Optional target channel/message retained from the official preview, independently of invite target kind.
    public let targetChannelID: Field<ChannelID>
    public let targetMessageID: Field<MessageID>
    /// Optional contact and nickname-change flags; no relationship/permission inference is made.
    public let isContact: Field<Bool>
    public let isNicknameChangeable: Field<Bool>
    /// Optional friend-invite count from the official preview; omission remains distinct from zero.
    public let friendsCount: Field<Int>
    /// Complete exact original object including unknown fields.
    public let rawFields: [String: JSONValue]

    /// Parses an ordinary invite without requiring the separately documented metadata extension.
    /// - Parameters:
    ///   - data: Complete UTF-8 object with required type/code/channel/expires_at fields.
    ///   - limits: Whole-document JSON byte, node and depth bounds; defaults to 1 MiB/100,000/64.
    /// - Throws: Parser/bounds or safe invalid-response errors for incompatible known fields.
    /// No I/O, credential access, suspension or related-resource fetching occurs.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(data: data, requiresMetadata: false, limits: limits)
    }

    /// Parses the same invite contract, optionally requiring all five metadata-extension fields.
    /// - Parameters:
    ///   - data: Complete UTF-8 invite object; unknown keys/numeric lexemes remain exact.
    ///   - requiresMetadata: True for GET channel invites; false for ordinary/create responses.
    ///   - limits: Whole-document parser and scalar projection bounds, default .default.
    /// - Throws: Parser/bounds errors or sanitized invalid-response errors, including missing metadata
    ///   when requested. Negative metadata/counts, forbidden nulls and wrong roots are rejected.
    public init(data: Data, requiresMetadata: Bool, limits: JSONLimits = .default) throws {
        let object = try PayloadObject(JSONValue.parse(data, limits: limits), limits: limits)
        type = try object.required("type", RawValue<ChannelInviteType>.self)
        code = try object.required("code", String.self)
        guild = try object.messageField("guild", ChannelInviteGuild.self)
        guard let value = object.resource.fields["channel"] else { throw DiscordError.transport(.invalidResponse) }
        channel = value == .null ? .null : .value(try Channel(value: value, limits: limits))
        inviter = try object.messageField("inviter", MessageAuthor.self)
        targetType = try object.field("target_type", RawValue<ChannelInviteTargetType>.self)
        targetUser = try object.messageField("target_user", MessageAuthor.self)
        targetApplication = try object.messageField("target_application", ChannelInviteApplication.self)
        approximatePresenceCount = try object.field("approximate_presence_count", Int.self, nullable: true)
        approximateMemberCount = try object.field("approximate_member_count", Int.self, nullable: true)
        expiresAt = try object.required("expires_at", Nullable<DiscordTimestamp>.self)
        guildScheduledEvent = try object.messageField("guild_scheduled_event", GuildScheduledEvent.self)
        flags = try object.field("flags", UInt64.self)
        roles = try object.nested("roles", nullable: true) { value in
            guard case .array(let values) = value else { throw DiscordError.transport(.invalidResponse) }
            return try values.map { try ChannelInviteRole(value: $0, limits: limits) }
        }
        uses = try object.field("uses", Int.self)
        maxUses = try object.field("max_uses", Int.self)
        maxAge = try object.field("max_age", Int.self)
        temporary = try object.field("temporary", Bool.self)
        createdAt = try object.field("created_at", DiscordTimestamp.self)
        for field in [approximatePresenceCount, approximateMemberCount, uses, maxUses, maxAge] {
            if case .value(let count) = field, count < 0 { throw DiscordError.transport(.invalidResponse) }
        }
        if requiresMetadata {
            for key in ["uses", "max_uses", "max_age", "temporary", "created_at"] {
                guard object.resource.fields[key] != nil else { throw DiscordError.transport(.invalidResponse) }
            }
        }
        guildID = try object.field("guild_id", GuildID.self)
        targetChannelID = try object.field("target_channel_id", ChannelID.self)
        targetMessageID = try object.field("target_message_id", MessageID.self)
        isContact = try object.field("is_contact", Bool.self)
        isNicknameChangeable = try object.field("is_nickname_changeable", Bool.self)
        friendsCount = try object.field("friends_count", Int.self)
        if case .value(let count) = friendsCount, count < 0 { throw DiscordError.transport(.invalidResponse) }
        rawFields = object.resource.fields
    }
}

/// Explicit channel-invite creation parameters. Validation occurs in jsonValue and at descriptor
/// construction; no defaults are silently materialized. Discord validates stream/application/role eligibility.
public struct ChannelInviteCreate: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let maxAge: Int?
    public let maxUses: Int?
    public let temporary: Bool?
    public let unique: Bool?
    public let targetType: ChannelInviteTargetType?
    public let targetUserID: UserID?
    public let targetApplicationID: ApplicationID?
    public let targetUserIDs: [UserID]?
    public let roleIDs: [RoleID]?

    /// Stores finite invite parameters without performing I/O. Call jsonValue or construct a descriptor to validate.
    /// - Parameters:
    ///   - maxAge: Optional lifetime in seconds, 0...604,800; zero never expires; nil leaves default 86,400.
    ///   - maxUses: Optional use count, 0...100; zero unlimited; nil leaves server default zero.
    ///   - temporary: Optional temporary-membership policy; nil leaves false upstream.
    ///   - unique: Optional forced-new-code choice; nil permits upstream reuse.
    ///   - targetType: Optional stream or embedded-application target; corresponding ID is required.
    ///   - targetUserID: Stream target, required only with targetType stream; cannot accompany application target.
    ///   - targetApplicationID: Embedded app target, required only with matching targetType.
    ///   - targetUserIDs: Optional acceptance allowlist of at most 1,000 exact IDs; mutually exclusive with CSV.
    ///   - roleIDs: Optional explicit assigned roles; local bound 250, server MANAGE_ROLES/hierarchy checks apply.
    public init(maxAge: Int? = nil, maxUses: Int? = nil, temporary: Bool? = nil, unique: Bool? = nil,
                targetType: ChannelInviteTargetType? = nil, targetUserID: UserID? = nil,
                targetApplicationID: ApplicationID? = nil, targetUserIDs: [UserID]? = nil, roleIDs: [RoleID]? = nil) {
        self.maxAge = maxAge; self.maxUses = maxUses; self.temporary = temporary; self.unique = unique
        self.targetType = targetType; self.targetUserID = targetUserID; self.targetApplicationID = targetApplicationID
        self.targetUserIDs = targetUserIDs; self.roleIDs = roleIDs
    }

    /// Validates and encodes every documented non-file creation field. An empty input yields `{}`.
    /// - Returns: Exact JSON request object; nil fields remain omitted, explicit empty ID lists remain empty.
    /// - Throws: Safe invalid-value errors for range violations, duplicate role IDs, oversized lists,
    ///   inconsistent target IDs or IDs without a target type. CSV conflicts are checked by the HTTP descriptor.
    public func jsonValue() throws -> JSONValue {
        guard maxAge.map({ (0...604_800).contains($0) }) ?? true,
              maxUses.map({ (0...100).contains($0) }) ?? true,
              targetUserIDs.map({ $0.count <= 1_000 }) ?? true,
              roleIDs.map({ $0.count <= 250 && Set($0).count == $0.count }) ?? true
        else { throw DiscordError.validation(.invalidValue) }
        switch targetType {
        case .stream: guard targetUserID != nil, targetApplicationID == nil else { throw DiscordError.validation(.invalidValue) }
        case .embeddedApplication: guard targetApplicationID != nil, targetUserID == nil else { throw DiscordError.validation(.invalidValue) }
        case nil: guard targetUserID == nil, targetApplicationID == nil else { throw DiscordError.validation(.invalidValue) }
        }
        var fields: [String: JSONValue] = [:]
        if let maxAge { fields["max_age"] = .number(try JSONNumber(rawValue: String(maxAge))) }
        if let maxUses { fields["max_uses"] = .number(try JSONNumber(rawValue: String(maxUses))) }
        if let temporary { fields["temporary"] = .bool(temporary) }
        if let unique { fields["unique"] = .bool(unique) }
        if let targetType { fields["target_type"] = .number(try JSONNumber(rawValue: String(targetType.rawValue))) }
        if let targetUserID { fields["target_user_id"] = .string(targetUserID.description) }
        if let targetApplicationID { fields["target_application_id"] = .string(targetApplicationID.description) }
        if let targetUserIDs { fields["target_user_ids"] = .array(targetUserIDs.map { .string($0.description) }) }
        if let roleIDs { fields["role_ids"] = .array(roleIDs.map { .string($0.description) }) }
        return .object(fields)
    }

    /// Conceals IDs, target information and invite configuration from ordinary diagnostics.
    public var description: String { "ChannelInviteCreate(redacted)" }
    /// Conceals the same data from debug descriptions.
    public var debugDescription: String { description }
    /// Prevents reflective diagnostics from traversing request fields.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}
