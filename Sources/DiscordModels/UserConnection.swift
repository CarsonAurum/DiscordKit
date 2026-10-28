// File: Sources/DiscordModels/UserConnection.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import Foundation

/// Partial guild owned by GET /users/@me/guilds, with every response-schema field typed.
/// Verified 2026-10-16 against the User resource and official preview. These are caller-scoped
/// snapshots: owner and permissions do not establish current access or a fresh permission calculation.
public struct UserGuild: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Exact guild ID and exclusive pagination cursor.
    public let id: GuildID
    /// Guild display name.
    public let name: String
    /// Required nullable icon hash.
    public let icon: Nullable<String>
    /// Nullable banner, optional for written-reference compatibility and typed by the preview overlay.
    public let banner: Field<String>
    /// Whether the caller owns this guild at snapshot time.
    public let owner: Bool
    /// Arbitrary-width decimal permission bits; never parsed through floating point.
    public let permissions: String
    /// Ordered guild feature strings, retaining future values.
    public let features: [String]
    /// Optional nullable approximate total count when with_counts is requested; no capacity claim follows.
    public let approximateMemberCount: Field<Int>
    /// Optional nullable approximate nonoffline count when requested.
    public let approximatePresenceCount: Field<Int>
    /// Complete original object, including future keys and exact unknown numeric lexemes.
    public let rawFields: [String: JSONValue]

    /// Parses one immutable API v10 object, retaining exact unknown fields and redacting diagnostics.
    /// - Parameters:
    ///   - data: Complete UTF-8 object; required nullable keys must still be present.
    ///   - limits: Whole-document bounds, default 1 MiB, depth 64 and 100,000 nodes, including unknown data.
    /// - Throws: JSON syntax/bounds errors, or sanitized invalid-response errors for missing required keys,
    ///   forbidden nulls, wrong types or out-of-range exact integers. Parsing is synchronous, does not
    ///   suspend or observe cancellation, and owns no network resources, credentials, cache or mutable state.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects an original subtree after the containing document has passed the same parser bounds.
    /// - Parameters:
    ///   - value: Bounded nonnull object; immutable unknown subtrees remain shared with the parent.
    ///   - limits: Bounds established by the public root parse, reused for exact scalar decoding.
    /// - Throws: Sanitized invalid-response errors for a nonobject or malformed modeled field.
    ///   This synchronous initializer performs no I/O, suspension, authorization or ownership changes.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        id = try object.required("id", GuildID.self)
        name = try object.required("name", String.self)
        icon = try object.required("icon", Nullable<String>.self)
        banner = try object.field("banner", String.self, nullable: true)
        owner = try object.required("owner", Bool.self)
        permissions = try object.required("permissions", String.self)
        features = try object.required("features", [String].self)
        approximateMemberCount = try object.field("approximate_member_count", Int.self, nullable: true)
        approximatePresenceCount = try object.field("approximate_presence_count", Int.self, nullable: true)
        try validateChannelPermissionBits(permissions)
        rawFields = object.resource.fields
    }
}

/// API v10 external connection, verified against the User resource on 2026-10-16.
/// Opaque provider IDs are not Discord snowflakes. Nullable name and typed integration guild
/// are official preview overlays. Removed services may remain raw unknown values; absence from
/// this list never proves a user has no external account or that a token was revoked.
public struct UserConnection: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Opaque provider account ID; never coerced into a Discord snowflake.
    public let id: String
    /// Provider account name; explicit null is preserved from the official preview overlay.
    public let name: Nullable<String>
    /// Known or future provider service string.
    public let type: RawValue<UserConnectionService>
    /// Optional revoked indicator; absent does not assert a valid token.
    public let revoked: Field<Bool>
    /// Optional ordered partial integrations with typed provider account and guild.
    public let integrations: Field<[UserConnectionIntegration]>
    /// Whether this connection was verified at snapshot time.
    public let verified: Bool
    /// Whether friend synchronization is enabled.
    public let friendSync: Bool
    /// Whether related activities appear in presence updates.
    public let showActivity: Bool
    /// Whether a corresponding third-party OAuth2 token exists upstream.
    public let twoWayLink: Bool
    /// Visibility scope retaining future exact integer values.
    public let visibility: RawValue<UserConnectionVisibility>
    /// Complete original object, including future keys and exact unknown numeric lexemes.
    public let rawFields: [String: JSONValue]

    /// Parses one immutable API v10 object, retaining exact unknown fields and redacting diagnostics.
    /// - Parameters:
    ///   - data: Complete UTF-8 object; required nullable keys must still be present.
    ///   - limits: Whole-document bounds, default 1 MiB, depth 64 and 100,000 nodes, including unknown data.
    /// - Throws: JSON syntax/bounds errors, or sanitized invalid-response errors for missing required keys,
    ///   forbidden nulls, wrong types or out-of-range exact integers. Parsing is synchronous, does not
    ///   suspend or observe cancellation, and owns no network resources, credentials, cache or mutable state.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects an original subtree after the containing document has passed the same parser bounds.
    /// - Parameters:
    ///   - value: Bounded nonnull object; immutable unknown subtrees remain shared with the parent.
    ///   - limits: Bounds established by the public root parse, reused for exact scalar decoding.
    /// - Throws: Sanitized invalid-response errors for a nonobject or malformed modeled field.
    ///   This synchronous initializer performs no I/O, suspension, authorization or ownership changes.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        id = try object.required("id", String.self)
        name = try object.required("name", Nullable<String>.self)
        type = try object.required("type", RawValue<UserConnectionService>.self)
        revoked = try object.field("revoked", Bool.self)
        integrations = try object.messageArray("integrations", UserConnectionIntegration.self)
        verified = try object.required("verified", Bool.self)
        friendSync = try object.required("friend_sync", Bool.self)
        showActivity = try object.required("show_activity", Bool.self)
        twoWayLink = try object.required("two_way_link", Bool.self)
        visibility = try object.required("visibility", RawValue<UserConnectionVisibility>.self)
        rawFields = object.resource.fields
    }
}

/// Partial connection integration. The written reference permits partial guild integrations;
/// the official ConnectedAccountIntegrationResponse adds a guild and omits name. Optional
/// name/guild preserve both shapes; additional integration fields remain exact in rawFields.
public struct UserConnectionIntegration: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Opaque integration ID from the connected-account preview; not forced to a snowflake.
    public let id: String
    /// Known or future integration service spelling.
    public let type: RawValue<GuildIntegrationType>
    /// Optional nullable integration display name from the partial guild-integration variant.
    public let name: Field<String>
    /// Provider account with its own opaque ID and name.
    public let account: UserConnectionAccount
    /// Optional typed integration guild from the official preview overlay.
    public let guild: Field<UserConnectionGuild>
    /// Complete original object, including future keys and exact unknown numeric lexemes.
    public let rawFields: [String: JSONValue]

    /// Parses one immutable API v10 object, retaining exact unknown fields and redacting diagnostics.
    /// - Parameters:
    ///   - data: Complete UTF-8 object; required nullable keys must still be present.
    ///   - limits: Whole-document bounds, default 1 MiB, depth 64 and 100,000 nodes, including unknown data.
    /// - Throws: JSON syntax/bounds errors, or sanitized invalid-response errors for missing required keys,
    ///   forbidden nulls, wrong types or out-of-range exact integers. Parsing is synchronous, does not
    ///   suspend or observe cancellation, and owns no network resources, credentials, cache or mutable state.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects an original subtree after the containing document has passed the same parser bounds.
    /// - Parameters:
    ///   - value: Bounded nonnull object; immutable unknown subtrees remain shared with the parent.
    ///   - limits: Bounds established by the public root parse, reused for exact scalar decoding.
    /// - Throws: Sanitized invalid-response errors for a nonobject or malformed modeled field.
    ///   This synchronous initializer performs no I/O, suspension, authorization or ownership changes.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        id = try object.required("id", String.self)
        type = try object.required("type", RawValue<GuildIntegrationType>.self)
        name = try object.field("name", String.self, nullable: true)
        account = try object.messageModel("account", UserConnectionAccount.self)
        guild = try object.messageField("guild", UserConnectionGuild.self)
        rawFields = object.resource.fields
    }
}

/// The complete small guild snapshot owned by a connected-account integration preview.
/// No full Guild hydration, membership inference or authorization lookup occurs.
public struct UserConnectionGuild: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Exact Discord guild ID.
    public let id: GuildID
    /// Guild display name.
    public let name: String
    /// Required nullable guild icon hash.
    public let icon: Nullable<String>
    /// Complete original object, including future keys and exact unknown numeric lexemes.
    public let rawFields: [String: JSONValue]

    /// Parses one immutable API v10 object, retaining exact unknown fields and redacting diagnostics.
    /// - Parameters:
    ///   - data: Complete UTF-8 object; required nullable keys must still be present.
    ///   - limits: Whole-document bounds, default 1 MiB, depth 64 and 100,000 nodes, including unknown data.
    /// - Throws: JSON syntax/bounds errors, or sanitized invalid-response errors for missing required keys,
    ///   forbidden nulls, wrong types or out-of-range exact integers. Parsing is synchronous, does not
    ///   suspend or observe cancellation, and owns no network resources, credentials, cache or mutable state.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects an original subtree after the containing document has passed the same parser bounds.
    /// - Parameters:
    ///   - value: Bounded nonnull object; immutable unknown subtrees remain shared with the parent.
    ///   - limits: Bounds established by the public root parse, reused for exact scalar decoding.
    /// - Throws: Sanitized invalid-response errors for a nonobject or malformed modeled field.
    ///   This synchronous initializer performs no I/O, suspension, authorization or ownership changes.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        id = try object.required("id", GuildID.self)
        name = try object.required("name", String.self)
        icon = try object.required("icon", Nullable<String>.self)
        rawFields = object.resource.fields
    }
}

/// Provider account owned by a user connection integration. The official AccountResponse preview
/// requires id and name while permitting name to be null. This distinct projection does not weaken
/// the Guild resource's independently documented nonnull account name contract.
public struct UserConnectionAccount: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Exact opaque external account ID, never interpreted as a Discord snowflake.
    public let id: String
    /// Required provider account name, or explicit null under the connected-account preview overlay.
    public let name: Nullable<String>
    /// Complete original object, including future fields and exact numeric lexemes.
    public let rawFields: [String: JSONValue]

    /// Parses the immutable provider account without fetching an external profile or evaluating consent.
    /// - Parameters:
    ///   - data: Complete UTF-8 object containing required id and nullable name keys.
    ///   - limits: Whole-document bounds, default 1 MiB, depth 64 and 100,000 nodes, including unknown fields.
    /// - Throws: JSON syntax/bounds errors or sanitized invalid-response for missing keys, wrong types or null id.
    ///   Parsing is synchronous, performs no I/O, and owns no token, network resource or mutable cache.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects the original account subtree after its containing connection document passed parser bounds.
    /// - Parameters:
    ///   - value: Bounded nonnull object whose unknown values remain immutable and exact.
    ///   - limits: Bounds established by the containing root parse, reused for scalar validation.
    /// - Throws: Sanitized invalid-response for a nonobject, missing required field or wrong scalar type.
    ///   No I/O, suspension, token access or ownership changes occur during projection.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        id = try object.required("id", String.self)
        name = try object.required("name", Nullable<String>.self)
        rawFields = object.resource.fields
    }
}
