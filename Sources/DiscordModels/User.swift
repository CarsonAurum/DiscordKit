import DiscordCore
import Foundation

/// Complete resource-owned API v10 User fields, verified 2026-10-16 against
/// https://docs.discord.com/developers/resources/user and the official OpenAPI preview.
/// The five required baseline fields retain existing API compatibility; optional OAuth2 fields remain
/// presence-aware and never imply an approved scope, current permissions or active subscription.
public struct User: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Exact unsigned user snowflake; never converted through floating point.
    public let id: UserID
    /// Account username. Decoding performs no normalization or current authorization inference.
    public let username: String
    /// Discord tag discriminator, retaining the migrated-account value "0".
    public let discriminator: String
    /// Required nullable display name; missing and null are distinct.
    public let globalName: Nullable<String>
    /// Required nullable avatar hash; this model never fetches an asset URL.
    public let avatar: Nullable<String>
    /// Whether the user belongs to an OAuth2 application; absent does not assert false.
    public let bot: Field<Bool>
    /// Optional official Discord System user indicator.
    public let system: Field<Bool>
    /// Optional multi-factor authentication status visible under the identify scope.
    public let mfaEnabled: Field<Bool>
    /// Optional nullable banner hash; omission remains distinct from an explicitly cleared banner.
    public let banner: Field<String>
    /// Optional nullable banner color; exact integer spellings and native range are checked.
    public let accentColor: Field<Int>
    /// Optional selected locale; future spellings remain unchanged.
    public let locale: Field<String>
    /// Optional email verification status, requiring the email OAuth2 scope for visibility.
    public let verified: Field<Bool>
    /// Optional nullable email address, requiring email scope; ordinary diagnostics conceal it.
    public let email: Field<String>
    /// Optional exact user flag bits, including future unsigned bits; see UserFlags.
    public let flags: Field<UInt64>
    /// Optional exact public flag bits, preserving all future bits.
    public let publicFlags: Field<UInt64>
    /// Optional Nitro type, retaining future integral values. Without approved identify.premium scope Discord returns zero regardless of subscription.
    public let premiumType: Field<RawValue<PremiumType>>
    /// Optional nullable typed avatar-decoration metadata, including exact SKU identity.
    public let avatarDecorationData: Field<UserAvatarDecoration>
    /// Optional nullable typed collectibles; future collection keys survive in rawFields.
    public let collectibles: Field<UserCollectibles>
    /// Optional nullable primary guild identity; decoding does not assert current membership or tag eligibility.
    public let primaryGuild: Field<UserPrimaryGuild>
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
        id = try object.required("id", UserID.self)
        username = try object.required("username", String.self)
        discriminator = try object.required("discriminator", String.self)
        globalName = try object.required("global_name", Nullable<String>.self)
        avatar = try object.required("avatar", Nullable<String>.self)
        bot = try object.field("bot", Bool.self)
        system = try object.field("system", Bool.self)
        mfaEnabled = try object.field("mfa_enabled", Bool.self)
        banner = try object.field("banner", String.self, nullable: true)
        accentColor = try object.field("accent_color", Int.self, nullable: true)
        locale = try object.field("locale", String.self)
        verified = try object.field("verified", Bool.self)
        email = try object.field("email", String.self, nullable: true)
        flags = try object.field("flags", UInt64.self)
        publicFlags = try object.field("public_flags", UInt64.self)
        premiumType = try object.field("premium_type", RawValue<PremiumType>.self)
        avatarDecorationData = try object.messageField("avatar_decoration_data", UserAvatarDecoration.self, nullable: true)
        collectibles = try object.messageField("collectibles", UserCollectibles.self, nullable: true)
        primaryGuild = try object.messageField("primary_guild", UserPrimaryGuild.self, nullable: true)
        rawFields = object.resource.fields
    }
}

/// API v10 avatar-decoration data. The written SKU snowflake is nullable in the official
/// OpenAPI overlay; explicit null remains distinct from a missing required SKU. No CDN request occurs.
public struct UserAvatarDecoration: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Avatar-decoration asset hash, retained without URL construction or fetching.
    public let asset: String
    /// Required exact SKU snowflake, or explicit null accepted by the official preview overlay.
    public let skuID: Nullable<SKUID>
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
        asset = try object.required("asset", String.self)
        skuID = try object.required("sku_id", Nullable<SKUID>.self)
        rawFields = object.resource.fields
    }
}

/// API v10 user collectibles excluding avatar decorations and profile effects.
/// The written optional nameplate also accepts explicit null from the official preview overlay.
public struct UserCollectibles: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Optional nullable nameplate; an empty collection is distinct from a null whole collection.
    public let nameplate: Field<UserNameplate>
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
        nameplate = try object.messageField("nameplate", UserNameplate.self, nullable: true)
        rawFields = object.resource.fields
    }
}

/// API v10 nameplate data. Unknown palette strings remain represented without guessing a known case.
public struct UserNameplate: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Exact nameplate SKU identifier.
    public let skuID: SKUID
    /// Nameplate asset path; never interpreted as an authorized destination.
    public let asset: String
    /// Upstream label, currently unused and permitted to be empty.
    public let label: String
    /// Known or future background palette spelling.
    public let palette: RawValue<UserNameplatePalette>
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
        skuID = try object.required("sku_id", SKUID.self)
        asset = try object.required("asset", String.self)
        label = try object.required("label", String.self)
        palette = try object.required("palette", RawValue<UserNameplatePalette>.self)
        rawFields = object.resource.fields
    }
}

/// API v10 primary guild identity. Every inner key is required and nullable;
/// Discord can clear an identity after eligibility changes, while false identityEnabled represents
/// a user manually hiding the tag. The snapshot never asserts membership or authorization.
public struct UserPrimaryGuild: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Nullable primary guild ID; no guild is fetched.
    public let identityGuildID: Nullable<GuildID>
    /// True displays the tag, false manually hides it, and null can represent a system-cleared identity.
    public let identityEnabled: Nullable<Bool>
    /// Nullable server tag text; response parsing preserves content without imposing outgoing limits.
    public let tag: Nullable<String>
    /// Nullable server-tag badge hash; no CDN fetch occurs.
    public let badge: Nullable<String>
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
        identityGuildID = try object.required("identity_guild_id", Nullable<GuildID>.self)
        identityEnabled = try object.required("identity_enabled", Nullable<Bool>.self)
        tag = try object.required("tag", Nullable<String>.self)
        badge = try object.required("badge", Nullable<String>.self)
        rawFields = object.resource.fields
    }
}
