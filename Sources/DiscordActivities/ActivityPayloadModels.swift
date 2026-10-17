import DiscordCore
import Foundation
// Reviewed against Discord Embedded App SDK revision 14264eccbf9e68d5d58c1aadbc7579e003e0dce6.
/// Authorization-code result. Exchange codes only through the caller-owned confidential backend; diagnostics redact them.
/// Construction is synchronous, validates modeled types, retains complete raw fields and starts no I/O.
public struct ActivityAuthorization: ActivityPayload {
    public let rawFields: [String: JSONValue]
    /// Wire `code`. Required and nonnull.
    public let code: String

    /// Validates this SDK object while preserving unknown keys and exact numeric spellings.
    /// - Parameter value: Object subtree already bounded by the enclosing document parser.
    /// - Throws: `ActivityCatalogError.invalidPayload` for absent required fields, forbidden null or wrong types.
    /// No transport ownership, task creation, suspension, mutation or automatic retries occur.
    public init(value: JSONValue) throws {
        let object = try ActivityObject(value)
        rawFields = object.fields
        self.code = try ActivityObject.string(object.required("code"))
    }
}

/// Application projection returned during Activity authentication.
/// Construction is synchronous, validates modeled types, retains complete raw fields and starts no I/O.
public struct ActivityApplication: ActivityPayload {
    public let rawFields: [String: JSONValue]
    /// Wire `description`. Required and nonnull.
    public let textDescription: String
    /// Wire `icon`. Optional; omission is distinct from explicit null.
    public let icon: Field<String>
    /// Wire `id`. Required and nonnull.
    public let id: String
    /// Wire `rpc_origins`. Optional; explicit null is rejected.
    public let rpcOrigins: Field<[String]>
    /// Wire `name`. Required and nonnull.
    public let name: String

    /// Validates this SDK object while preserving unknown keys and exact numeric spellings.
    /// - Parameter value: Object subtree already bounded by the enclosing document parser.
    /// - Throws: `ActivityCatalogError.invalidPayload` for absent required fields, forbidden null or wrong types.
    /// No transport ownership, task creation, suspension, mutation or automatic retries occur.
    public init(value: JSONValue) throws {
        let object = try ActivityObject(value)
        rawFields = object.fields
        self.textDescription = try ActivityObject.string(object.required("description"))
        self.icon = try object.field("icon", nullable: true) { try ActivityObject.string($0) }
        self.id = try ActivityObject.string(object.required("id"))
        self.rpcOrigins = try object.field("rpc_origins", nullable: false) { try ActivityObject.array($0) { try ActivityObject.string($0) } }
        self.name = try ActivityObject.string(object.required("name"))
    }
}

/// Authentication-specific user schema; public_flags is required by the pinned generated SDK schema.
/// Construction is synchronous, validates modeled types, retains complete raw fields and starts no I/O.
public struct ActivityAuthenticatedUser: ActivityPayload {
    public let rawFields: [String: JSONValue]
    /// Wire `username`. Required and nonnull.
    public let username: String
    /// Wire `discriminator`. Required and nonnull.
    public let discriminator: String
    /// Wire `id`. Required and nonnull.
    public let id: String
    /// Wire `avatar`. Optional; omission is distinct from explicit null.
    public let avatar: Field<String>
    /// Wire `public_flags`. Required and nonnull.
    public let publicFlags: JSONNumber
    /// Wire `global_name`. Optional; omission is distinct from explicit null.
    public let globalName: Field<String>

    /// Validates this SDK object while preserving unknown keys and exact numeric spellings.
    /// - Parameter value: Object subtree already bounded by the enclosing document parser.
    /// - Throws: `ActivityCatalogError.invalidPayload` for absent required fields, forbidden null or wrong types.
    /// No transport ownership, task creation, suspension, mutation or automatic retries occur.
    public init(value: JSONValue) throws {
        let object = try ActivityObject(value)
        rawFields = object.fields
        self.username = try ActivityObject.string(object.required("username"))
        self.discriminator = try ActivityObject.string(object.required("discriminator"))
        self.id = try ActivityObject.string(object.required("id"))
        self.avatar = try object.field("avatar", nullable: true) { try ActivityObject.string($0) }
        self.publicFlags = try ActivityObject.number(object.required("public_flags"))
        self.globalName = try object.field("global_name", nullable: true) { try ActivityObject.string($0) }
    }
}

/// Activity authentication result. Raw tokens and all associated profile data are redacted in diagnostics.
/// Construction is synchronous, validates modeled types, retains complete raw fields and starts no I/O.
public struct ActivityAuthentication: ActivityPayload {
    public let rawFields: [String: JSONValue]
    /// Wire `access_token`. Required and nonnull.
    public let accessToken: String
    /// Wire `user`. Required and nonnull.
    public let user: ActivityAuthenticatedUser
    /// Wire `scopes`. Required and nonnull.
    public let scopes: [ActivityOAuthScope]
    /// Wire `expires`. Required and nonnull.
    public let expires: String
    /// Wire `application`. Required and nonnull.
    public let application: ActivityApplication

    /// Validates this SDK object while preserving unknown keys and exact numeric spellings.
    /// - Parameter value: Object subtree already bounded by the enclosing document parser.
    /// - Throws: `ActivityCatalogError.invalidPayload` for absent required fields, forbidden null or wrong types.
    /// No transport ownership, task creation, suspension, mutation or automatic retries occur.
    public init(value: JSONValue) throws {
        let object = try ActivityObject(value)
        rawFields = object.fields
        self.accessToken = try ActivityObject.string(object.required("access_token"))
        self.user = try ActivityAuthenticatedUser(value: object.required("user"))
        self.scopes = try ActivityObject.array(object.required("scopes")) { try ActivityOAuthScope(value: $0) }
        self.expires = try ActivityObject.string(object.required("expires"))
        self.application = try ActivityApplication(value: object.required("application"))
    }
}

/// Avatar decoration from the common Activity user schema; distinct from the generated participant shape.
/// Construction is synchronous, validates modeled types, retains complete raw fields and starts no I/O.
public struct ActivityAvatarDecoration: ActivityPayload {
    public let rawFields: [String: JSONValue]
    /// Wire `asset`. Required and nonnull.
    public let asset: String
    /// Wire `sku_id`. Optional; explicit null is rejected.
    public let skuID: Field<String>

    /// Validates this SDK object while preserving unknown keys and exact numeric spellings.
    /// - Parameter value: Object subtree already bounded by the enclosing document parser.
    /// - Throws: `ActivityCatalogError.invalidPayload` for absent required fields, forbidden null or wrong types.
    /// No transport ownership, task creation, suspension, mutation or automatic retries occur.
    public init(value: JSONValue) throws {
        let object = try ActivityObject(value)
        rawFields = object.fields
        self.asset = try ActivityObject.string(object.required("asset"))
        self.skuID = try object.field("sku_id", nullable: false) { try ActivityObject.string($0) }
    }
}

/// Generated participant decoration, preserving the upstream camel-case skuId and expiresAt field names.
/// Construction is synchronous, validates modeled types, retains complete raw fields and starts no I/O.
public struct ActivityParticipantDecoration: ActivityPayload {
    public let rawFields: [String: JSONValue]
    /// Wire `asset`. Optional; omission is distinct from explicit null.
    public let asset: Field<String>
    /// Wire `skuId`. Optional; explicit null is rejected.
    public let skuID: Field<String>
    /// Wire `expiresAt`. Optional; explicit null is rejected.
    public let expiresAt: Field<JSONNumber>

    /// Validates this SDK object while preserving unknown keys and exact numeric spellings.
    /// - Parameter value: Object subtree already bounded by the enclosing document parser.
    /// - Throws: `ActivityCatalogError.invalidPayload` for absent required fields, forbidden null or wrong types.
    /// No transport ownership, task creation, suspension, mutation or automatic retries occur.
    public init(value: JSONValue) throws {
        let object = try ActivityObject(value)
        rawFields = object.fields
        self.asset = try object.field("asset", nullable: true) { try ActivityObject.string($0) }
        self.skuID = try object.field("skuId", nullable: false) { try ActivityObject.string($0) }
        self.expiresAt = try object.field("expiresAt", nullable: false) { try ActivityObject.number($0) }
    }
}

/// Common SDK user projection used by user, voice and message events; distinct from authentication and participant schemas.
/// Construction is synchronous, validates modeled types, retains complete raw fields and starts no I/O.
public struct ActivityUser: ActivityPayload {
    public let rawFields: [String: JSONValue]
    /// Wire `id`. Required and nonnull.
    public let id: String
    /// Wire `username`. Required and nonnull.
    public let username: String
    /// Wire `discriminator`. Required and nonnull.
    public let discriminator: String
    /// Wire `global_name`. Optional; omission is distinct from explicit null.
    public let globalName: Field<String>
    /// Wire `avatar`. Optional; omission is distinct from explicit null.
    public let avatar: Field<String>
    /// Wire `avatar_decoration_data`. Required; explicit null is preserved.
    public let avatarDecorationData: Nullable<ActivityAvatarDecoration>
    /// Wire `bot`. Required and nonnull.
    public let bot: Bool
    /// Wire `flags`. Optional; omission is distinct from explicit null.
    public let flags: Field<JSONNumber>
    /// Wire `premium_type`. Optional; omission is distinct from explicit null.
    public let premiumType: Field<JSONNumber>

    /// Validates this SDK object while preserving unknown keys and exact numeric spellings.
    /// - Parameter value: Object subtree already bounded by the enclosing document parser.
    /// - Throws: `ActivityCatalogError.invalidPayload` for absent required fields, forbidden null or wrong types.
    /// No transport ownership, task creation, suspension, mutation or automatic retries occur.
    public init(value: JSONValue) throws {
        let object = try ActivityObject(value)
        rawFields = object.fields
        self.id = try ActivityObject.string(object.required("id"))
        self.username = try ActivityObject.string(object.required("username"))
        self.discriminator = try ActivityObject.string(object.required("discriminator"))
        self.globalName = try object.field("global_name", nullable: true) { try ActivityObject.string($0) }
        self.avatar = try object.field("avatar", nullable: true) { try ActivityObject.string($0) }
        self.avatarDecorationData = try object.nullable("avatar_decoration_data") { try ActivityAvatarDecoration(value: $0) }
        self.bot = try ActivityObject.bool(object.required("bot"))
        self.flags = try object.field("flags", nullable: true) { try ActivityObject.number($0) }
        self.premiumType = try object.field("premium_type", nullable: true) { try ActivityObject.number($0) }
    }
}

/// Participant and GET_USER projection. Exact ID strings avoid precision loss, and unknown flags remain numeric lexemes.
/// Construction is synchronous, validates modeled types, retains complete raw fields and starts no I/O.
public struct ActivityParticipant: ActivityPayload {
    public let rawFields: [String: JSONValue]
    /// Wire `id`. Required and nonnull.
    public let id: String
    /// Wire `username`. Required and nonnull.
    public let username: String
    /// Wire `global_name`. Optional; omission is distinct from explicit null.
    public let globalName: Field<String>
    /// Wire `discriminator`. Required and nonnull.
    public let discriminator: String
    /// Wire `avatar`. Optional; omission is distinct from explicit null.
    public let avatar: Field<String>
    /// Wire `flags`. Required and nonnull.
    public let flags: JSONNumber
    /// Wire `bot`. Required and nonnull.
    public let bot: Bool
    /// Wire `avatar_decoration_data`. Optional; omission is distinct from explicit null.
    public let avatarDecorationData: Field<ActivityParticipantDecoration>
    /// Wire `premium_type`. Optional; omission is distinct from explicit null.
    public let premiumType: Field<JSONNumber>
    /// Wire `nickname`. Optional; explicit null is rejected.
    public let nickname: Field<String>

    /// Validates this SDK object while preserving unknown keys and exact numeric spellings.
    /// - Parameter value: Object subtree already bounded by the enclosing document parser.
    /// - Throws: `ActivityCatalogError.invalidPayload` for absent required fields, forbidden null or wrong types.
    /// No transport ownership, task creation, suspension, mutation or automatic retries occur.
    public init(value: JSONValue) throws {
        let object = try ActivityObject(value)
        rawFields = object.fields
        self.id = try ActivityObject.string(object.required("id"))
        self.username = try ActivityObject.string(object.required("username"))
        self.globalName = try object.field("global_name", nullable: true) { try ActivityObject.string($0) }
        self.discriminator = try ActivityObject.string(object.required("discriminator"))
        self.avatar = try object.field("avatar", nullable: true) { try ActivityObject.string($0) }
        self.flags = try ActivityObject.number(object.required("flags"))
        self.bot = try ActivityObject.bool(object.required("bot"))
        self.avatarDecorationData = try object.field("avatar_decoration_data", nullable: true) { try ActivityParticipantDecoration(value: $0) }
        self.premiumType = try object.field("premium_type", nullable: true) { try ActivityObject.number($0) }
        self.nickname = try object.field("nickname", nullable: false) { try ActivityObject.string($0) }
    }
}

/// Connected-participants response and update event, preserving host order and duplicate entries if supplied.
/// Construction is synchronous, validates modeled types, retains complete raw fields and starts no I/O.
public struct ActivityParticipants: ActivityPayload {
    public let rawFields: [String: JSONValue]
    /// Wire `participants`. Required and nonnull.
    public let participants: [ActivityParticipant]

    /// Validates this SDK object while preserving unknown keys and exact numeric spellings.
    /// - Parameter value: Object subtree already bounded by the enclosing document parser.
    /// - Throws: `ActivityCatalogError.invalidPayload` for absent required fields, forbidden null or wrong types.
    /// No transport ownership, task creation, suspension, mutation or automatic retries occur.
    public init(value: JSONValue) throws {
        let object = try ActivityObject(value)
        rawFields = object.fields
        self.participants = try ActivityObject.array(object.required("participants")) { try ActivityParticipant(value: $0) }
    }
}

/// Guild member embedded in Activity messages; no REST cache completeness is implied.
/// Construction is synchronous, validates modeled types, retains complete raw fields and starts no I/O.
public struct ActivityGuildMember: ActivityPayload {
    public let rawFields: [String: JSONValue]
    /// Wire `user`. Required and nonnull.
    public let user: ActivityUser
    /// Wire `nick`. Optional; omission is distinct from explicit null.
    public let nick: Field<String>
    /// Wire `roles`. Required and nonnull.
    public let roles: [String]
    /// Wire `joined_at`. Required and nonnull.
    public let joinedAt: String
    /// Wire `deaf`. Required and nonnull.
    public let deaf: Bool
    /// Wire `mute`. Required and nonnull.
    public let mute: Bool

    /// Validates this SDK object while preserving unknown keys and exact numeric spellings.
    /// - Parameter value: Object subtree already bounded by the enclosing document parser.
    /// - Throws: `ActivityCatalogError.invalidPayload` for absent required fields, forbidden null or wrong types.
    /// No transport ownership, task creation, suspension, mutation or automatic retries occur.
    public init(value: JSONValue) throws {
        let object = try ActivityObject(value)
        rawFields = object.fields
        self.user = try ActivityUser(value: object.required("user"))
        self.nick = try object.field("nick", nullable: true) { try ActivityObject.string($0) }
        self.roles = try ActivityObject.array(object.required("roles")) { try ActivityObject.string($0) }
        self.joinedAt = try ActivityObject.string(object.required("joined_at"))
        self.deaf = try ActivityObject.bool(object.required("deaf"))
        self.mute = try ActivityObject.bool(object.required("mute"))
    }
}

/// Guild member avatar decoration, whose sku_id may be absent or null.
/// Construction is synchronous, validates modeled types, retains complete raw fields and starts no I/O.
public struct ActivityMemberDecoration: ActivityPayload {
    public let rawFields: [String: JSONValue]
    /// Wire `asset`. Required and nonnull.
    public let asset: String
    /// Wire `sku_id`. Optional; omission is distinct from explicit null.
    public let skuID: Field<String>

    /// Validates this SDK object while preserving unknown keys and exact numeric spellings.
    /// - Parameter value: Object subtree already bounded by the enclosing document parser.
    /// - Throws: `ActivityCatalogError.invalidPayload` for absent required fields, forbidden null or wrong types.
    /// No transport ownership, task creation, suspension, mutation or automatic retries occur.
    public init(value: JSONValue) throws {
        let object = try ActivityObject(value)
        rawFields = object.fields
        self.asset = try ActivityObject.string(object.required("asset"))
        self.skuID = try object.field("sku_id", nullable: true) { try ActivityObject.string($0) }
    }
}

/// CURRENT_GUILD_MEMBER_UPDATE projection scoped by its explicit guild and user identifiers.
/// Construction is synchronous, validates modeled types, retains complete raw fields and starts no I/O.
public struct ActivityGuildMemberUpdate: ActivityPayload {
    public let rawFields: [String: JSONValue]
    /// Wire `user_id`. Required and nonnull.
    public let userID: String
    /// Wire `nick`. Optional; omission is distinct from explicit null.
    public let nick: Field<String>
    /// Wire `guild_id`. Required and nonnull.
    public let guildID: String
    /// Wire `avatar`. Optional; omission is distinct from explicit null.
    public let avatar: Field<String>
    /// Wire `avatar_decoration_data`. Optional; omission is distinct from explicit null.
    public let avatarDecorationData: Field<ActivityMemberDecoration>
    /// Wire `color_string`. Optional; omission is distinct from explicit null.
    public let colorString: Field<String>

    /// Validates this SDK object while preserving unknown keys and exact numeric spellings.
    /// - Parameter value: Object subtree already bounded by the enclosing document parser.
    /// - Throws: `ActivityCatalogError.invalidPayload` for absent required fields, forbidden null or wrong types.
    /// No transport ownership, task creation, suspension, mutation or automatic retries occur.
    public init(value: JSONValue) throws {
        let object = try ActivityObject(value)
        rawFields = object.fields
        self.userID = try ActivityObject.string(object.required("user_id"))
        self.nick = try object.field("nick", nullable: true) { try ActivityObject.string($0) }
        self.guildID = try ActivityObject.string(object.required("guild_id"))
        self.avatar = try object.field("avatar", nullable: true) { try ActivityObject.string($0) }
        self.avatarDecorationData = try object.field("avatar_decoration_data", nullable: true) { try ActivityMemberDecoration(value: $0) }
        self.colorString = try object.field("color_string", nullable: true) { try ActivityObject.string($0) }
    }
}

/// Voice state flags from the Embedded App SDK common schema.
/// Construction is synchronous, validates modeled types, retains complete raw fields and starts no I/O.
public struct ActivityVoiceState: ActivityPayload {
    public let rawFields: [String: JSONValue]
    /// Wire `mute`. Required and nonnull.
    public let mute: Bool
    /// Wire `deaf`. Required and nonnull.
    public let deaf: Bool
    /// Wire `self_mute`. Required and nonnull.
    public let selfMute: Bool
    /// Wire `self_deaf`. Required and nonnull.
    public let selfDeaf: Bool
    /// Wire `suppress`. Required and nonnull.
    public let suppress: Bool

    /// Validates this SDK object while preserving unknown keys and exact numeric spellings.
    /// - Parameter value: Object subtree already bounded by the enclosing document parser.
    /// - Throws: `ActivityCatalogError.invalidPayload` for absent required fields, forbidden null or wrong types.
    /// No transport ownership, task creation, suspension, mutation or automatic retries occur.
    public init(value: JSONValue) throws {
        let object = try ActivityObject(value)
        rawFields = object.fields
        self.mute = try ActivityObject.bool(object.required("mute"))
        self.deaf = try ActivityObject.bool(object.required("deaf"))
        self.selfMute = try ActivityObject.bool(object.required("self_mute"))
        self.selfDeaf = try ActivityObject.bool(object.required("self_deaf"))
        self.suppress = try ActivityObject.bool(object.required("suppress"))
    }
}

/// VOICE_STATE_UPDATE and channel voice state projection; volume retains the exact host numeric spelling.
/// Construction is synchronous, validates modeled types, retains complete raw fields and starts no I/O.
public struct ActivityUserVoiceState: ActivityPayload {
    public let rawFields: [String: JSONValue]
    /// Wire `mute`. Required and nonnull.
    public let mute: Bool
    /// Wire `nick`. Required and nonnull.
    public let nick: String
    /// Wire `user`. Required and nonnull.
    public let user: ActivityUser
    /// Wire `voice_state`. Required and nonnull.
    public let voiceState: ActivityVoiceState
    /// Wire `volume`. Required and nonnull.
    public let volume: JSONNumber

    /// Validates this SDK object while preserving unknown keys and exact numeric spellings.
    /// - Parameter value: Object subtree already bounded by the enclosing document parser.
    /// - Throws: `ActivityCatalogError.invalidPayload` for absent required fields, forbidden null or wrong types.
    /// No transport ownership, task creation, suspension, mutation or automatic retries occur.
    public init(value: JSONValue) throws {
        let object = try ActivityObject(value)
        rawFields = object.fields
        self.mute = try ActivityObject.bool(object.required("mute"))
        self.nick = try ActivityObject.string(object.required("nick"))
        self.user = try ActivityUser(value: object.required("user"))
        self.voiceState = try ActivityVoiceState(value: object.required("voice_state"))
        self.volume = try ActivityObject.number(object.required("volume"))
    }
}

/// Embedded SDK emoji shape, including nullable optional fields and unknown future members.
/// Construction is synchronous, validates modeled types, retains complete raw fields and starts no I/O.
public struct ActivityEmoji: ActivityPayload {
    public let rawFields: [String: JSONValue]
    /// Wire `id`. Required and nonnull.
    public let id: String
    /// Wire `name`. Optional; omission is distinct from explicit null.
    public let name: Field<String>
    /// Wire `roles`. Optional; omission is distinct from explicit null.
    public let roles: Field<[String]>
    /// Wire `user`. Optional; omission is distinct from explicit null.
    public let user: Field<ActivityUser>
    /// Wire `require_colons`. Optional; omission is distinct from explicit null.
    public let requireColons: Field<Bool>
    /// Wire `managed`. Optional; omission is distinct from explicit null.
    public let managed: Field<Bool>
    /// Wire `animated`. Optional; omission is distinct from explicit null.
    public let animated: Field<Bool>
    /// Wire `available`. Optional; omission is distinct from explicit null.
    public let available: Field<Bool>

    /// Validates this SDK object while preserving unknown keys and exact numeric spellings.
    /// - Parameter value: Object subtree already bounded by the enclosing document parser.
    /// - Throws: `ActivityCatalogError.invalidPayload` for absent required fields, forbidden null or wrong types.
    /// No transport ownership, task creation, suspension, mutation or automatic retries occur.
    public init(value: JSONValue) throws {
        let object = try ActivityObject(value)
        rawFields = object.fields
        self.id = try ActivityObject.string(object.required("id"))
        self.name = try object.field("name", nullable: true) { try ActivityObject.string($0) }
        self.roles = try object.field("roles", nullable: true) { try ActivityObject.array($0) { try ActivityObject.string($0) } }
        self.user = try object.field("user", nullable: true) { try ActivityUser(value: $0) }
        self.requireColons = try object.field("require_colons", nullable: true) { try ActivityObject.bool($0) }
        self.managed = try object.field("managed", nullable: true) { try ActivityObject.bool($0) }
        self.animated = try object.field("animated", nullable: true) { try ActivityObject.bool($0) }
        self.available = try object.field("available", nullable: true) { try ActivityObject.bool($0) }
    }
}

/// Activity timestamp values. The upstream SDK numbers are retained without conversion or date-unit assumptions.
/// Construction is synchronous, validates modeled types, retains complete raw fields and starts no I/O.
public struct ActivityTimestamps: ActivityPayload {
    public let rawFields: [String: JSONValue]
    /// Wire `start`. Optional; explicit null is rejected.
    public let start: Field<JSONNumber>
    /// Wire `end`. Optional; explicit null is rejected.
    public let end: Field<JSONNumber>

    /// Validates this SDK object while preserving unknown keys and exact numeric spellings.
    /// - Parameter value: Object subtree already bounded by the enclosing document parser.
    /// - Throws: `ActivityCatalogError.invalidPayload` for absent required fields, forbidden null or wrong types.
    /// No transport ownership, task creation, suspension, mutation or automatic retries occur.
    public init(value: JSONValue) throws {
        let object = try ActivityObject(value)
        rawFields = object.fields
        self.start = try object.field("start", nullable: false) { try ActivityObject.number($0) }
        self.end = try object.field("end", nullable: false) { try ActivityObject.number($0) }
    }
}

/// Party projection retaining the SDK schema, which does not enforce a two-element size tuple for this surface.
/// Construction is synchronous, validates modeled types, retains complete raw fields and starts no I/O.
public struct ActivityParty: ActivityPayload {
    public let rawFields: [String: JSONValue]
    /// Wire `id`. Optional; omission is distinct from explicit null.
    public let id: Field<String>
    /// Wire `size`. Optional; omission is distinct from explicit null.
    public let size: Field<[JSONNumber]>

    /// Validates this SDK object while preserving unknown keys and exact numeric spellings.
    /// - Parameter value: Object subtree already bounded by the enclosing document parser.
    /// - Throws: `ActivityCatalogError.invalidPayload` for absent required fields, forbidden null or wrong types.
    /// No transport ownership, task creation, suspension, mutation or automatic retries occur.
    public init(value: JSONValue) throws {
        let object = try ActivityObject(value)
        rawFields = object.fields
        self.id = try object.field("id", nullable: true) { try ActivityObject.string($0) }
        self.size = try object.field("size", nullable: true) { try ActivityObject.array($0) { try ActivityObject.number($0) } }
    }
}

/// Rich Presence assets; field omission and explicit null remain distinct.
/// Construction is synchronous, validates modeled types, retains complete raw fields and starts no I/O.
public struct ActivityAssets: ActivityPayload {
    public let rawFields: [String: JSONValue]
    /// Wire `large_image`. Optional; omission is distinct from explicit null.
    public let largeImage: Field<String>
    /// Wire `large_text`. Optional; omission is distinct from explicit null.
    public let largeText: Field<String>
    /// Wire `large_url`. Optional; omission is distinct from explicit null.
    public let largeURL: Field<String>
    /// Wire `small_image`. Optional; omission is distinct from explicit null.
    public let smallImage: Field<String>
    /// Wire `small_text`. Optional; omission is distinct from explicit null.
    public let smallText: Field<String>
    /// Wire `small_url`. Optional; omission is distinct from explicit null.
    public let smallURL: Field<String>

    /// Validates this SDK object while preserving unknown keys and exact numeric spellings.
    /// - Parameter value: Object subtree already bounded by the enclosing document parser.
    /// - Throws: `ActivityCatalogError.invalidPayload` for absent required fields, forbidden null or wrong types.
    /// No transport ownership, task creation, suspension, mutation or automatic retries occur.
    public init(value: JSONValue) throws {
        let object = try ActivityObject(value)
        rawFields = object.fields
        self.largeImage = try object.field("large_image", nullable: true) { try ActivityObject.string($0) }
        self.largeText = try object.field("large_text", nullable: true) { try ActivityObject.string($0) }
        self.largeURL = try object.field("large_url", nullable: true) { try ActivityObject.string($0) }
        self.smallImage = try object.field("small_image", nullable: true) { try ActivityObject.string($0) }
        self.smallText = try object.field("small_text", nullable: true) { try ActivityObject.string($0) }
        self.smallURL = try object.field("small_url", nullable: true) { try ActivityObject.string($0) }
        if case .value(let url) = largeURL { try activityResponseURL(url) }
        if case .value(let url) = smallURL { try activityResponseURL(url) }
    }
}

/// Rich Presence secret fields. Values are explicit for protocol use and always redacted from ordinary diagnostics.
/// Construction is synchronous, validates modeled types, retains complete raw fields and starts no I/O.
public struct ActivitySecrets: ActivityPayload {
    public let rawFields: [String: JSONValue]
    /// Wire `join`. Optional; explicit null is rejected.
    public let join: Field<String>
    /// Wire `match`. Optional; explicit null is rejected.
    public let match: Field<String>

    /// Validates this SDK object while preserving unknown keys and exact numeric spellings.
    /// - Parameter value: Object subtree already bounded by the enclosing document parser.
    /// - Throws: `ActivityCatalogError.invalidPayload` for absent required fields, forbidden null or wrong types.
    /// No transport ownership, task creation, suspension, mutation or automatic retries occur.
    public init(value: JSONValue) throws {
        let object = try ActivityObject(value)
        rawFields = object.fields
        self.join = try object.field("join", nullable: false) { try ActivityObject.string($0) }
        self.match = try object.field("match", nullable: false) { try ActivityObject.string($0) }
    }
}

/// SET_ACTIVITY response using the common SDK Activity shape, including exact numeric types and all nullable fields.
/// Construction is synchronous, validates modeled types, retains complete raw fields and starts no I/O.
public struct ActivityRichPresence: ActivityPayload {
    public let rawFields: [String: JSONValue]
    /// Wire `name`. Required and nonnull.
    public let name: String
    /// Wire `type`. Required and nonnull.
    public let type: JSONNumber
    /// Wire `url`. Optional; omission is distinct from explicit null.
    public let url: Field<String>
    /// Wire `created_at`. Optional; omission is distinct from explicit null.
    public let createdAt: Field<JSONNumber>
    /// Wire `timestamps`. Optional; omission is distinct from explicit null.
    public let timestamps: Field<ActivityTimestamps>
    /// Wire `application_id`. Optional; omission is distinct from explicit null.
    public let applicationID: Field<String>
    /// Wire `details`. Optional; omission is distinct from explicit null.
    public let details: Field<String>
    /// Wire `details_url`. Optional; omission is distinct from explicit null.
    public let detailsURL: Field<String>
    /// Wire `state`. Optional; omission is distinct from explicit null.
    public let state: Field<String>
    /// Wire `state_url`. Optional; omission is distinct from explicit null.
    public let stateURL: Field<String>
    /// Wire `emoji`. Optional; omission is distinct from explicit null.
    public let emoji: Field<ActivityEmoji>
    /// Wire `party`. Optional; omission is distinct from explicit null.
    public let party: Field<ActivityParty>
    /// Wire `assets`. Optional; omission is distinct from explicit null.
    public let assets: Field<ActivityAssets>
    /// Wire `secrets`. Optional; omission is distinct from explicit null.
    public let secrets: Field<ActivitySecrets>
    /// Wire `instance`. Optional; omission is distinct from explicit null.
    public let instance: Field<Bool>
    /// Wire `flags`. Optional; omission is distinct from explicit null.
    public let flags: Field<JSONNumber>

    /// Validates this SDK object while preserving unknown keys and exact numeric spellings.
    /// - Parameter value: Object subtree already bounded by the enclosing document parser.
    /// - Throws: `ActivityCatalogError.invalidPayload` for absent required fields, forbidden null or wrong types.
    /// No transport ownership, task creation, suspension, mutation or automatic retries occur.
    public init(value: JSONValue) throws {
        let object = try ActivityObject(value)
        rawFields = object.fields
        self.name = try ActivityObject.string(object.required("name"))
        self.type = try ActivityObject.number(object.required("type"))
        self.url = try object.field("url", nullable: true) { try ActivityObject.string($0) }
        self.createdAt = try object.field("created_at", nullable: true) { try ActivityObject.number($0) }
        self.timestamps = try object.field("timestamps", nullable: true) { try ActivityTimestamps(value: $0) }
        self.applicationID = try object.field("application_id", nullable: true) { try ActivityObject.string($0) }
        self.details = try object.field("details", nullable: true) { try ActivityObject.string($0) }
        self.detailsURL = try object.field("details_url", nullable: true) { try ActivityObject.string($0) }
        self.state = try object.field("state", nullable: true) { try ActivityObject.string($0) }
        self.stateURL = try object.field("state_url", nullable: true) { try ActivityObject.string($0) }
        self.emoji = try object.field("emoji", nullable: true) { try ActivityEmoji(value: $0) }
        self.party = try object.field("party", nullable: true) { try ActivityParty(value: $0) }
        self.assets = try object.field("assets", nullable: true) { try ActivityAssets(value: $0) }
        self.secrets = try object.field("secrets", nullable: true) { try ActivitySecrets(value: $0) }
        self.instance = try object.field("instance", nullable: true) { try ActivityObject.bool($0) }
        self.flags = try object.field("flags", nullable: true) { try ActivityObject.number($0) }
        if case .value(let url) = detailsURL { try activityResponseURL(url) }
        if case .value(let url) = stateURL { try activityResponseURL(url) }
    }
}

/// Emoji in generated relationship presence, whose name is required and id optional.
/// Construction is synchronous, validates modeled types, retains complete raw fields and starts no I/O.
public struct ActivityPresenceEmoji: ActivityPayload {
    public let rawFields: [String: JSONValue]
    /// Wire `name`. Required and nonnull.
    public let name: String
    /// Wire `id`. Optional; omission is distinct from explicit null.
    public let id: Field<String>
    /// Wire `animated`. Optional; omission is distinct from explicit null.
    public let animated: Field<Bool>

    /// Validates this SDK object while preserving unknown keys and exact numeric spellings.
    /// - Parameter value: Object subtree already bounded by the enclosing document parser.
    /// - Throws: `ActivityCatalogError.invalidPayload` for absent required fields, forbidden null or wrong types.
    /// No transport ownership, task creation, suspension, mutation or automatic retries occur.
    public init(value: JSONValue) throws {
        let object = try ActivityObject(value)
        rawFields = object.fields
        self.name = try ActivityObject.string(object.required("name"))
        self.id = try object.field("id", nullable: true) { try ActivityObject.string($0) }
        self.animated = try object.field("animated", nullable: true) { try ActivityObject.bool($0) }
    }
}

/// Generated relationship presence assets; present fields are not nullable in the pinned source.
/// Construction is synchronous, validates modeled types, retains complete raw fields and starts no I/O.
public struct ActivityPresenceAssets: ActivityPayload {
    public let rawFields: [String: JSONValue]
    /// Wire `large_image`. Optional; explicit null is rejected.
    public let largeImage: Field<String>
    /// Wire `large_text`. Optional; explicit null is rejected.
    public let largeText: Field<String>
    /// Wire `large_url`. Optional; explicit null is rejected.
    public let largeURL: Field<String>
    /// Wire `small_image`. Optional; explicit null is rejected.
    public let smallImage: Field<String>
    /// Wire `small_text`. Optional; explicit null is rejected.
    public let smallText: Field<String>
    /// Wire `small_url`. Optional; explicit null is rejected.
    public let smallURL: Field<String>

    /// Validates this SDK object while preserving unknown keys and exact numeric spellings.
    /// - Parameter value: Object subtree already bounded by the enclosing document parser.
    /// - Throws: `ActivityCatalogError.invalidPayload` for absent required fields, forbidden null or wrong types.
    /// No transport ownership, task creation, suspension, mutation or automatic retries occur.
    public init(value: JSONValue) throws {
        let object = try ActivityObject(value)
        rawFields = object.fields
        self.largeImage = try object.field("large_image", nullable: false) { try ActivityObject.string($0) }
        self.largeText = try object.field("large_text", nullable: false) { try ActivityObject.string($0) }
        self.largeURL = try object.field("large_url", nullable: false) { try ActivityObject.string($0) }
        self.smallImage = try object.field("small_image", nullable: false) { try ActivityObject.string($0) }
        self.smallText = try object.field("small_text", nullable: false) { try ActivityObject.string($0) }
        self.smallURL = try object.field("small_url", nullable: false) { try ActivityObject.string($0) }
    }
}

/// Generated relationship party projection. A supplied size must have exactly two elements.
/// Construction is synchronous, validates modeled types, retains complete raw fields and starts no I/O.
public struct ActivityPresenceParty: ActivityPayload {
    public let rawFields: [String: JSONValue]
    /// Wire `id`. Optional; explicit null is rejected.
    public let id: Field<String>
    /// Wire `size`. Optional; explicit null is rejected.
    public let size: Field<[JSONNumber]>
    /// Wire `privacy`. Optional; explicit null is rejected.
    public let privacy: Field<JSONNumber>

    /// Validates this SDK object while preserving unknown keys and exact numeric spellings.
    /// - Parameter value: Object subtree already bounded by the enclosing document parser.
    /// - Throws: `ActivityCatalogError.invalidPayload` for absent required fields, forbidden null or wrong types.
    /// No transport ownership, task creation, suspension, mutation or automatic retries occur.
    public init(value: JSONValue) throws {
        let object = try ActivityObject(value)
        rawFields = object.fields
        self.id = try object.field("id", nullable: false) { try ActivityObject.string($0) }
        self.size = try object.field("size", nullable: false) { try ActivityObject.array($0) { try ActivityObject.number($0) } }
        self.privacy = try object.field("privacy", nullable: false) { try ActivityObject.number($0) }
        if case .value(let size) = size, size.count != 2 { throw ActivityCatalogError.invalidPayload }
    }
}

/// Relationship presence Activity shape. This generated schema differs from the common SET_ACTIVITY response shape.
/// Construction is synchronous, validates modeled types, retains complete raw fields and starts no I/O.
public struct ActivityPresenceActivity: ActivityPayload {
    public let rawFields: [String: JSONValue]
    /// Wire `session_id`. Optional; explicit null is rejected.
    public let sessionID: Field<String>
    /// Wire `type`. Optional; explicit null is rejected.
    public let type: Field<JSONNumber>
    /// Wire `name`. Required and nonnull.
    public let name: String
    /// Wire `url`. Optional; omission is distinct from explicit null.
    public let url: Field<String>
    /// Wire `application_id`. Optional; explicit null is rejected.
    public let applicationID: Field<String>
    /// Wire `status_display_type`. Optional; explicit null is rejected.
    public let statusDisplayType: Field<JSONNumber>
    /// Wire `state`. Optional; explicit null is rejected.
    public let state: Field<String>
    /// Wire `state_url`. Optional; explicit null is rejected.
    public let stateURL: Field<String>
    /// Wire `details`. Optional; explicit null is rejected.
    public let details: Field<String>
    /// Wire `details_url`. Optional; explicit null is rejected.
    public let detailsURL: Field<String>
    /// Wire `emoji`. Optional; omission is distinct from explicit null.
    public let emoji: Field<ActivityPresenceEmoji>
    /// Wire `assets`. Optional; explicit null is rejected.
    public let assets: Field<ActivityPresenceAssets>
    /// Wire `timestamps`. Optional; explicit null is rejected.
    public let timestamps: Field<ActivityTimestamps>
    /// Wire `party`. Optional; explicit null is rejected.
    public let party: Field<ActivityPresenceParty>
    /// Wire `secrets`. Optional; explicit null is rejected.
    public let secrets: Field<ActivitySecrets>
    /// Wire `sync_id`. Optional; explicit null is rejected.
    public let syncID: Field<String>
    /// Wire `created_at`. Optional; explicit null is rejected.
    public let createdAt: Field<JSONNumber>
    /// Wire `instance`. Optional; explicit null is rejected.
    public let instance: Field<Bool>
    /// Wire `flags`. Optional; explicit null is rejected.
    public let flags: Field<JSONNumber>
    /// Wire `metadata`. Optional; explicit null is rejected.
    public let metadata: Field<ActivityMetadata>
    /// Wire `platform`. Optional; explicit null is rejected.
    public let platform: Field<String>
    /// Wire `supported_platforms`. Optional; explicit null is rejected.
    public let supportedPlatforms: Field<[String]>
    /// Wire `buttons`. Optional; explicit null is rejected.
    public let buttons: Field<[String]>
    /// Wire `hangStatus`. Optional; explicit null is rejected.
    public let hangStatus: Field<String>

    /// Validates this SDK object while preserving unknown keys and exact numeric spellings.
    /// - Parameter value: Object subtree already bounded by the enclosing document parser.
    /// - Throws: `ActivityCatalogError.invalidPayload` for absent required fields, forbidden null or wrong types.
    /// No transport ownership, task creation, suspension, mutation or automatic retries occur.
    public init(value: JSONValue) throws {
        let object = try ActivityObject(value)
        rawFields = object.fields
        self.sessionID = try object.field("session_id", nullable: false) { try ActivityObject.string($0) }
        self.type = try object.field("type", nullable: false) { try ActivityObject.number($0) }
        self.name = try ActivityObject.string(object.required("name"))
        self.url = try object.field("url", nullable: true) { try ActivityObject.string($0) }
        self.applicationID = try object.field("application_id", nullable: false) { try ActivityObject.string($0) }
        self.statusDisplayType = try object.field("status_display_type", nullable: false) { try ActivityObject.number($0) }
        self.state = try object.field("state", nullable: false) { try ActivityObject.string($0) }
        self.stateURL = try object.field("state_url", nullable: false) { try ActivityObject.string($0) }
        self.details = try object.field("details", nullable: false) { try ActivityObject.string($0) }
        self.detailsURL = try object.field("details_url", nullable: false) { try ActivityObject.string($0) }
        self.emoji = try object.field("emoji", nullable: true) { try ActivityPresenceEmoji(value: $0) }
        self.assets = try object.field("assets", nullable: false) { try ActivityPresenceAssets(value: $0) }
        self.timestamps = try object.field("timestamps", nullable: false) { try ActivityTimestamps(value: $0) }
        self.party = try object.field("party", nullable: false) { try ActivityPresenceParty(value: $0) }
        self.secrets = try object.field("secrets", nullable: false) { try ActivitySecrets(value: $0) }
        self.syncID = try object.field("sync_id", nullable: false) { try ActivityObject.string($0) }
        self.createdAt = try object.field("created_at", nullable: false) { try ActivityObject.number($0) }
        self.instance = try object.field("instance", nullable: false) { try ActivityObject.bool($0) }
        self.flags = try object.field("flags", nullable: false) { try ActivityObject.number($0) }
        self.metadata = try object.field("metadata", nullable: false) { try ActivityMetadata(value: $0) }
        self.platform = try object.field("platform", nullable: false) { try ActivityObject.string($0) }
        self.supportedPlatforms = try object.field("supported_platforms", nullable: false) { try ActivityObject.array($0) { try ActivityObject.string($0) } }
        self.buttons = try object.field("buttons", nullable: false) { try ActivityObject.array($0) { try ActivityObject.string($0) } }
        self.hangStatus = try object.field("hangStatus", nullable: false) { try ActivityObject.string($0) }
    }
}

/// Opaque metadata object; unknown members are preserved without inventing schemas.
/// Construction is synchronous, validates modeled types, retains complete raw fields and starts no I/O.
public struct ActivityMetadata: ActivityPayload {
    public let rawFields: [String: JSONValue]

    /// Validates this SDK object while preserving unknown keys and exact numeric spellings.
    /// - Parameter value: Object subtree already bounded by the enclosing document parser.
    /// - Throws: `ActivityCatalogError.invalidPayload` for absent required fields, forbidden null or wrong types.
    /// No transport ownership, task creation, suspension, mutation or automatic retries occur.
    public init(value: JSONValue) throws {
        let object = try ActivityObject(value)
        rawFields = object.fields
    }
}

/// Relationship presence retaining unknown status spellings verbatim.
/// Construction is synchronous, validates modeled types, retains complete raw fields and starts no I/O.
public struct ActivityPresence: ActivityPayload {
    public let rawFields: [String: JSONValue]
    /// Wire `status`. Required and nonnull.
    public let status: String
    /// Wire `activity`. Optional; omission is distinct from explicit null.
    public let activity: Field<ActivityPresenceActivity>

    /// Validates this SDK object while preserving unknown keys and exact numeric spellings.
    /// - Parameter value: Object subtree already bounded by the enclosing document parser.
    /// - Throws: `ActivityCatalogError.invalidPayload` for absent required fields, forbidden null or wrong types.
    /// No transport ownership, task creation, suspension, mutation or automatic retries occur.
    public init(value: JSONValue) throws {
        let object = try ActivityObject(value)
        rawFields = object.fields
        self.status = try ActivityObject.string(object.required("status"))
        self.activity = try object.field("activity", nullable: true) { try ActivityPresenceActivity(value: $0) }
    }
}

/// Relationship response or update, preserving unknown relationship type numbers and optional presence.
/// Construction is synchronous, validates modeled types, retains complete raw fields and starts no I/O.
public struct ActivityRelationship: ActivityPayload {
    public let rawFields: [String: JSONValue]
    /// Wire `type`. Required and nonnull.
    public let type: JSONNumber
    /// Wire `user`. Required and nonnull.
    public let user: ActivityParticipant
    /// Wire `presence`. Optional; explicit null is rejected.
    public let presence: Field<ActivityPresence>

    /// Validates this SDK object while preserving unknown keys and exact numeric spellings.
    /// - Parameter value: Object subtree already bounded by the enclosing document parser.
    /// - Throws: `ActivityCatalogError.invalidPayload` for absent required fields, forbidden null or wrong types.
    /// No transport ownership, task creation, suspension, mutation or automatic retries occur.
    public init(value: JSONValue) throws {
        let object = try ActivityObject(value)
        rawFields = object.fields
        self.type = try ActivityObject.number(object.required("type"))
        self.user = try ActivityParticipant(value: object.required("user"))
        self.presence = try object.field("presence", nullable: false) { try ActivityPresence(value: $0) }
    }
}

/// Ordered relationships response. relationships.read requires acceptance of the current Social SDK terms.
/// Construction is synchronous, validates modeled types, retains complete raw fields and starts no I/O.
public struct ActivityRelationships: ActivityPayload {
    public let rawFields: [String: JSONValue]
    /// Wire `relationships`. Required and nonnull.
    public let relationships: [ActivityRelationship]

    /// Validates this SDK object while preserving unknown keys and exact numeric spellings.
    /// - Parameter value: Object subtree already bounded by the enclosing document parser.
    /// - Throws: `ActivityCatalogError.invalidPayload` for absent required fields, forbidden null or wrong types.
    /// No transport ownership, task creation, suspension, mutation or automatic retries occur.
    public init(value: JSONValue) throws {
        let object = try ActivityObject(value)
        rawFields = object.fields
        self.relationships = try ActivityObject.array(object.required("relationships")) { try ActivityRelationship(value: $0) }
    }
}

/// SDK SKU price, preserving the amount exactly rather than treating it as a floating-point currency value.
/// Construction is synchronous, validates modeled types, retains complete raw fields and starts no I/O.
public struct ActivityPrice: ActivityPayload {
    public let rawFields: [String: JSONValue]
    /// Wire `amount`. Required and nonnull.
    public let amount: JSONNumber
    /// Wire `currency`. Required and nonnull.
    public let currency: String

    /// Validates this SDK object while preserving unknown keys and exact numeric spellings.
    /// - Parameter value: Object subtree already bounded by the enclosing document parser.
    /// - Throws: `ActivityCatalogError.invalidPayload` for absent required fields, forbidden null or wrong types.
    /// No transport ownership, task creation, suspension, mutation or automatic retries occur.
    public init(value: JSONValue) throws {
        let object = try ActivityObject(value)
        rawFields = object.fields
        self.amount = try ActivityObject.number(object.required("amount"))
        self.currency = try ActivityObject.string(object.required("currency"))
    }
}

/// Embedded-app SKU projection. Client SKU data is display information, not server entitlement verification.
/// Construction is synchronous, validates modeled types, retains complete raw fields and starts no I/O.
public struct ActivitySKU: ActivityPayload {
    public let rawFields: [String: JSONValue]
    /// Wire `id`. Required and nonnull.
    public let id: String
    /// Wire `name`. Required and nonnull.
    public let name: String
    /// Wire `type`. Required and nonnull.
    public let type: JSONNumber
    /// Wire `price`. Required and nonnull.
    public let price: ActivityPrice
    /// Wire `application_id`. Required and nonnull.
    public let applicationID: String
    /// Wire `flags`. Required and nonnull.
    public let flags: JSONNumber
    /// Wire `release_date`. Required; explicit null is preserved.
    public let releaseDate: Nullable<String>

    /// Validates this SDK object while preserving unknown keys and exact numeric spellings.
    /// - Parameter value: Object subtree already bounded by the enclosing document parser.
    /// - Throws: `ActivityCatalogError.invalidPayload` for absent required fields, forbidden null or wrong types.
    /// No transport ownership, task creation, suspension, mutation or automatic retries occur.
    public init(value: JSONValue) throws {
        let object = try ActivityObject(value)
        rawFields = object.fields
        self.id = try ActivityObject.string(object.required("id"))
        self.name = try ActivityObject.string(object.required("name"))
        self.type = try ActivityObject.number(object.required("type"))
        self.price = try ActivityPrice(value: object.required("price"))
        self.applicationID = try ActivityObject.string(object.required("application_id"))
        self.flags = try ActivityObject.number(object.required("flags"))
        self.releaseDate = try object.nullable("release_date") { try ActivityObject.string($0) }
    }
}

/// Ordered embedded-app SKU response; an empty array is valid.
/// Construction is synchronous, validates modeled types, retains complete raw fields and starts no I/O.
public struct ActivitySKUs: ActivityPayload {
    public let rawFields: [String: JSONValue]
    /// Wire `skus`. Required and nonnull.
    public let skus: [ActivitySKU]

    /// Validates this SDK object while preserving unknown keys and exact numeric spellings.
    /// - Parameter value: Object subtree already bounded by the enclosing document parser.
    /// - Throws: `ActivityCatalogError.invalidPayload` for absent required fields, forbidden null or wrong types.
    /// No transport ownership, task creation, suspension, mutation or automatic retries occur.
    public init(value: JSONValue) throws {
        let object = try ActivityObject(value)
        rawFields = object.fields
        self.skus = try ActivityObject.array(object.required("skus")) { try ActivitySKU(value: $0) }
    }
}

/// Embedded-app entitlement projection. This client-controlled data must never grant server authorization.
/// Construction is synchronous, validates modeled types, retains complete raw fields and starts no I/O.
public struct ActivityEntitlement: ActivityPayload {
    public let rawFields: [String: JSONValue]
    /// Wire `id`. Required and nonnull.
    public let id: String
    /// Wire `sku_id`. Required and nonnull.
    public let skuID: String
    /// Wire `application_id`. Required and nonnull.
    public let applicationID: String
    /// Wire `user_id`. Required and nonnull.
    public let userID: String
    /// Wire `gift_code_flags`. Required and nonnull.
    public let giftCodeFlags: JSONNumber
    /// Wire `type`. Required and nonnull.
    public let type: JSONNumber
    /// Wire `gifter_user_id`. Optional; omission is distinct from explicit null.
    public let gifterUserID: Field<String>
    /// Wire `branches`. Optional; omission is distinct from explicit null.
    public let branches: Field<[String]>
    /// Wire `starts_at`. Optional; omission is distinct from explicit null.
    public let startsAt: Field<String>
    /// Wire `ends_at`. Optional; omission is distinct from explicit null.
    public let endsAt: Field<String>
    /// Wire `parent_id`. Optional; omission is distinct from explicit null.
    public let parentID: Field<String>
    /// Wire `consumed`. Optional; omission is distinct from explicit null.
    public let consumed: Field<Bool>
    /// Wire `deleted`. Optional; omission is distinct from explicit null.
    public let deleted: Field<Bool>
    /// Wire `gift_code_batch_id`. Optional; omission is distinct from explicit null.
    public let giftCodeBatchID: Field<String>

    /// Validates this SDK object while preserving unknown keys and exact numeric spellings.
    /// - Parameter value: Object subtree already bounded by the enclosing document parser.
    /// - Throws: `ActivityCatalogError.invalidPayload` for absent required fields, forbidden null or wrong types.
    /// No transport ownership, task creation, suspension, mutation or automatic retries occur.
    public init(value: JSONValue) throws {
        let object = try ActivityObject(value)
        rawFields = object.fields
        self.id = try ActivityObject.string(object.required("id"))
        self.skuID = try ActivityObject.string(object.required("sku_id"))
        self.applicationID = try ActivityObject.string(object.required("application_id"))
        self.userID = try ActivityObject.string(object.required("user_id"))
        self.giftCodeFlags = try ActivityObject.number(object.required("gift_code_flags"))
        self.type = try ActivityObject.number(object.required("type"))
        self.gifterUserID = try object.field("gifter_user_id", nullable: true) { try ActivityObject.string($0) }
        self.branches = try object.field("branches", nullable: true) { try ActivityObject.array($0) { try ActivityObject.string($0) } }
        self.startsAt = try object.field("starts_at", nullable: true) { try ActivityObject.string($0) }
        self.endsAt = try object.field("ends_at", nullable: true) { try ActivityObject.string($0) }
        self.parentID = try object.field("parent_id", nullable: true) { try ActivityObject.string($0) }
        self.consumed = try object.field("consumed", nullable: true) { try ActivityObject.bool($0) }
        self.deleted = try object.field("deleted", nullable: true) { try ActivityObject.bool($0) }
        self.giftCodeBatchID = try object.field("gift_code_batch_id", nullable: true) { try ActivityObject.string($0) }
    }
}

/// Ordered embedded-app entitlements response; independent server verification remains required for fulfillment.
/// Construction is synchronous, validates modeled types, retains complete raw fields and starts no I/O.
public struct ActivityEntitlements: ActivityPayload {
    public let rawFields: [String: JSONValue]
    /// Wire `entitlements`. Required and nonnull.
    public let entitlements: [ActivityEntitlement]

    /// Validates this SDK object while preserving unknown keys and exact numeric spellings.
    /// - Parameter value: Object subtree already bounded by the enclosing document parser.
    /// - Throws: `ActivityCatalogError.invalidPayload` for absent required fields, forbidden null or wrong types.
    /// No transport ownership, task creation, suspension, mutation or automatic retries occur.
    public init(value: JSONValue) throws {
        let object = try ActivityObject(value)
        rawFields = object.fields
        self.entitlements = try ActivityObject.array(object.required("entitlements")) { try ActivityEntitlement(value: $0) }
    }
}

/// Channel permission response accepting the SDK string or native-integer bridge representation without precision loss.
/// Construction is synchronous, validates modeled types, retains complete raw fields and starts no I/O.
public struct ActivityPermissions: ActivityPayload {
    public let rawFields: [String: JSONValue]
    /// Wire `permissions`. Required and nonnull.
    public let permissions: ActivityPermissionValue

    /// Validates this SDK object while preserving unknown keys and exact numeric spellings.
    /// - Parameter value: Object subtree already bounded by the enclosing document parser.
    /// - Throws: `ActivityCatalogError.invalidPayload` for absent required fields, forbidden null or wrong types.
    /// No transport ownership, task creation, suspension, mutation or automatic retries occur.
    public init(value: JSONValue) throws {
        let object = try ActivityObject(value)
        rawFields = object.fields
        self.permissions = try ActivityPermissionValue(value: object.required("permissions"))
    }
}

/// Optional platform behavior switches. Each key may later disappear, so omission remains observable.
/// Construction is synchronous, validates modeled types, retains complete raw fields and starts no I/O.
public struct ActivityPlatformBehaviors: ActivityPayload {
    public let rawFields: [String: JSONValue]
    /// Wire `iosKeyboardResizesView`. Optional; explicit null is rejected.
    public let iosKeyboardResizesView: Field<Bool>

    /// Validates this SDK object while preserving unknown keys and exact numeric spellings.
    /// - Parameter value: Object subtree already bounded by the enclosing document parser.
    /// - Throws: `ActivityCatalogError.invalidPayload` for absent required fields, forbidden null or wrong types.
    /// No transport ownership, task creation, suspension, mutation or automatic retries occur.
    public init(value: JSONValue) throws {
        let object = try ActivityObject(value)
        rawFields = object.fields
        self.iosKeyboardResizesView = try object.field("iosKeyboardResizesView", nullable: false) { try ActivityObject.bool($0) }
    }
}

/// External-link outcome. Explicit null is the pre-December-2024 unknown result; it is not coerced to success.
/// Construction is synchronous, validates modeled types, retains complete raw fields and starts no I/O.
public struct ActivityExternalLink: ActivityPayload {
    public let rawFields: [String: JSONValue]
    /// Wire `opened`. Required; explicit null is preserved.
    public let opened: Nullable<Bool>

    /// Validates this SDK object while preserving unknown keys and exact numeric spellings.
    /// - Parameter value: Object subtree already bounded by the enclosing document parser.
    /// - Throws: `ActivityCatalogError.invalidPayload` for absent required fields, forbidden null or wrong types.
    /// No transport ownership, task creation, suspension, mutation or automatic retries occur.
    public init(value: JSONValue) throws {
        let object = try ActivityObject(value)
        rawFields = object.fields
        self.opened = try object.nullable("opened") { try ActivityObject.bool($0) }
    }
}

/// Interactive picture-in-picture configuration returned by SET_CONFIG.
/// Construction is synchronous, validates modeled types, retains complete raw fields and starts no I/O.
public struct ActivityConfig: ActivityPayload {
    public let rawFields: [String: JSONValue]
    /// Wire `use_interactive_pip`. Required and nonnull.
    public let useInteractivePIP: Bool

    /// Validates this SDK object while preserving unknown keys and exact numeric spellings.
    /// - Parameter value: Object subtree already bounded by the enclosing document parser.
    /// - Throws: `ActivityCatalogError.invalidPayload` for absent required fields, forbidden null or wrong types.
    /// No transport ownership, task creation, suspension, mutation or automatic retries occur.
    public init(value: JSONValue) throws {
        let object = try ActivityObject(value)
        rawFields = object.fields
        self.useInteractivePIP = try ActivityObject.bool(object.required("use_interactive_pip"))
    }
}

/// User locale returned by USER_SETTINGS_GET_LOCALE; unknown future locale spellings remain intact.
/// Construction is synchronous, validates modeled types, retains complete raw fields and starts no I/O.
public struct ActivityLocale: ActivityPayload {
    public let rawFields: [String: JSONValue]
    /// Wire `locale`. Required and nonnull.
    public let locale: String

    /// Validates this SDK object while preserving unknown keys and exact numeric spellings.
    /// - Parameter value: Object subtree already bounded by the enclosing document parser.
    /// - Throws: `ActivityCatalogError.invalidPayload` for absent required fields, forbidden null or wrong types.
    /// No transport ownership, task creation, suspension, mutation or automatic retries occur.
    public init(value: JSONValue) throws {
        let object = try ActivityObject(value)
        rawFields = object.fields
        self.locale = try ActivityObject.string(object.required("locale"))
    }
}

/// Hardware-acceleration prompt outcome; available on the documented web host only.
/// Construction is synchronous, validates modeled types, retains complete raw fields and starts no I/O.
public struct ActivityHardwareAcceleration: ActivityPayload {
    public let rawFields: [String: JSONValue]
    /// Wire `enabled`. Required and nonnull.
    public let enabled: Bool

    /// Validates this SDK object while preserving unknown keys and exact numeric spellings.
    /// - Parameter value: Object subtree already bounded by the enclosing document parser.
    /// - Throws: `ActivityCatalogError.invalidPayload` for absent required fields, forbidden null or wrong types.
    /// No transport ownership, task creation, suspension, mutation or automatic retries occur.
    public init(value: JSONValue) throws {
        let object = try ActivityObject(value)
        rawFields = object.fields
        self.enabled = try ActivityObject.bool(object.required("enabled"))
    }
}

/// Source-only quest result. Host availability and access requirements are unspecified in the public reference.
/// Construction is synchronous, validates modeled types, retains complete raw fields and starts no I/O.
public struct ActivityQuest: ActivityPayload {
    public let rawFields: [String: JSONValue]
    /// Wire `quest_id`. Required and nonnull.
    public let questID: String
    /// Wire `enrolled_at`. Optional; omission is distinct from explicit null.
    public let enrolledAt: Field<String>
    /// Wire `completed_at`. Optional; omission is distinct from explicit null.
    public let completedAt: Field<String>
    /// Wire `external_cta_url`. Required and nonnull.
    public let externalCTAURL: String

    /// Validates this SDK object while preserving unknown keys and exact numeric spellings.
    /// - Parameter value: Object subtree already bounded by the enclosing document parser.
    /// - Throws: `ActivityCatalogError.invalidPayload` for absent required fields, forbidden null or wrong types.
    /// No transport ownership, task creation, suspension, mutation or automatic retries occur.
    public init(value: JSONValue) throws {
        let object = try ActivityObject(value)
        rawFields = object.fields
        self.questID = try ActivityObject.string(object.required("quest_id"))
        self.enrolledAt = try object.field("enrolled_at", nullable: true) { try ActivityObject.string($0) }
        self.completedAt = try object.field("completed_at", nullable: true) { try ActivityObject.string($0) }
        self.externalCTAURL = try ActivityObject.string(object.required("external_cta_url"))
    }
}

/// Source-only quest enrollment query result; omitted, null and nonnull enrollment dates remain distinct.
/// Construction is synchronous, validates modeled types, retains complete raw fields and starts no I/O.
public struct ActivityQuestEnrollment: ActivityPayload {
    public let rawFields: [String: JSONValue]
    /// Wire `quest_id`. Required and nonnull.
    public let questID: String
    /// Wire `is_enrolled`. Required and nonnull.
    public let isEnrolled: Bool
    /// Wire `enrolled_at`. Optional; omission is distinct from explicit null.
    public let enrolledAt: Field<String>

    /// Validates this SDK object while preserving unknown keys and exact numeric spellings.
    /// - Parameter value: Object subtree already bounded by the enclosing document parser.
    /// - Throws: `ActivityCatalogError.invalidPayload` for absent required fields, forbidden null or wrong types.
    /// No transport ownership, task creation, suspension, mutation or automatic retries occur.
    public init(value: JSONValue) throws {
        let object = try ActivityObject(value)
        rawFields = object.fields
        self.questID = try ActivityObject.string(object.required("quest_id"))
        self.isEnrolled = try ActivityObject.bool(object.required("is_enrolled"))
        self.enrolledAt = try object.field("enrolled_at", nullable: true) { try ActivityObject.string($0) }
    }
}

/// Source-only quest enrollment event, whose enrolled_at is required and nonnull in the pinned event schema.
/// Construction is synchronous, validates modeled types, retains complete raw fields and starts no I/O.
public struct ActivityQuestEnrollmentUpdate: ActivityPayload {
    public let rawFields: [String: JSONValue]
    /// Wire `quest_id`. Required and nonnull.
    public let questID: String
    /// Wire `is_enrolled`. Required and nonnull.
    public let isEnrolled: Bool
    /// Wire `enrolled_at`. Required and nonnull.
    public let enrolledAt: String

    /// Validates this SDK object while preserving unknown keys and exact numeric spellings.
    /// - Parameter value: Object subtree already bounded by the enclosing document parser.
    /// - Throws: `ActivityCatalogError.invalidPayload` for absent required fields, forbidden null or wrong types.
    /// No transport ownership, task creation, suspension, mutation or automatic retries occur.
    public init(value: JSONValue) throws {
        let object = try ActivityObject(value)
        rawFields = object.fields
        self.questID = try ActivityObject.string(object.required("quest_id"))
        self.isEnrolled = try ActivityObject.bool(object.required("is_enrolled"))
        self.enrolledAt = try ActivityObject.string(object.required("enrolled_at"))
        try activityDate(enrolledAt)
    }
}

/// Uploaded image URL. The SDK documents an ephemeral attachment URL, not permanent storage.
/// Construction is synchronous, validates modeled types, retains complete raw fields and starts no I/O.
public struct ActivityImageUpload: ActivityPayload {
    public let rawFields: [String: JSONValue]
    /// Wire `image_url`. Required and nonnull.
    public let imageURL: String

    /// Validates this SDK object while preserving unknown keys and exact numeric spellings.
    /// - Parameter value: Object subtree already bounded by the enclosing document parser.
    /// - Throws: `ActivityCatalogError.invalidPayload` for absent required fields, forbidden null or wrong types.
    /// No transport ownership, task creation, suspension, mutation or automatic retries occur.
    public init(value: JSONValue) throws {
        let object = try ActivityObject(value)
        rawFields = object.fields
        self.imageURL = try ActivityObject.string(object.required("image_url"))
    }
}

/// Source-only proxy-ticket refresh response. Ticket contents are redacted in diagnostics and reflection.
/// Construction is synchronous, validates modeled types, retains complete raw fields and starts no I/O.
public struct ActivityProxyTicket: ActivityPayload {
    public let rawFields: [String: JSONValue]
    /// Wire `ticket`. Required and nonnull.
    public let ticket: String

    /// Validates this SDK object while preserving unknown keys and exact numeric spellings.
    /// - Parameter value: Object subtree already bounded by the enclosing document parser.
    /// - Throws: `ActivityCatalogError.invalidPayload` for absent required fields, forbidden null or wrong types.
    /// No transport ownership, task creation, suspension, mutation or automatic retries occur.
    public init(value: JSONValue) throws {
        let object = try ActivityObject(value)
        rawFields = object.fields
        self.ticket = try ActivityObject.string(object.required("ticket"))
    }
}

/// Boolean result shared by source-only interaction sharing and quest timer commands.
/// Construction is synchronous, validates modeled types, retains complete raw fields and starts no I/O.
public struct ActivitySuccess: ActivityPayload {
    public let rawFields: [String: JSONValue]
    /// Wire `success`. Required and nonnull.
    public let success: Bool

    /// Validates this SDK object while preserving unknown keys and exact numeric spellings.
    /// - Parameter value: Object subtree already bounded by the enclosing document parser.
    /// - Throws: `ActivityCatalogError.invalidPayload` for absent required fields, forbidden null or wrong types.
    /// No transport ownership, task creation, suspension, mutation or automatic retries occur.
    public init(value: JSONValue) throws {
        let object = try ActivityObject(value)
        rawFields = object.fields
        self.success = try ActivityObject.bool(object.required("success"))
    }
}

/// SHARE_LINK response preserving all three generated outcome flags.
/// Construction is synchronous, validates modeled types, retains complete raw fields and starts no I/O.
public struct ActivityShareLink: ActivityPayload {
    public let rawFields: [String: JSONValue]
    /// Wire `success`. Required and nonnull.
    public let success: Bool
    /// Wire `didCopyLink`. Required and nonnull.
    public let didCopyLink: Bool
    /// Wire `didSendMessage`. Required and nonnull.
    public let didSendMessage: Bool

    /// Validates this SDK object while preserving unknown keys and exact numeric spellings.
    /// - Parameter value: Object subtree already bounded by the enclosing document parser.
    /// - Throws: `ActivityCatalogError.invalidPayload` for absent required fields, forbidden null or wrong types.
    /// No transport ownership, task creation, suspension, mutation or automatic retries occur.
    public init(value: JSONValue) throws {
        let object = try ActivityObject(value)
        rawFields = object.fields
        self.success = try ActivityObject.bool(object.required("success"))
        self.didCopyLink = try ActivityObject.bool(object.required("didCopyLink"))
        self.didSendMessage = try ActivityObject.bool(object.required("didSendMessage"))
    }
}

/// Host configuration received with READY. No origin trust decision is inferred from these payload strings.
/// Construction is synchronous, validates modeled types, retains complete raw fields and starts no I/O.
public struct ActivityReadyConfig: ActivityPayload {
    public let rawFields: [String: JSONValue]
    /// Wire `cdn_host`. Optional; explicit null is rejected.
    public let cdnHost: Field<String>
    /// Wire `api_endpoint`. Required and nonnull.
    public let apiEndpoint: String
    /// Wire `environment`. Required and nonnull.
    public let environment: String

    /// Validates this SDK object while preserving unknown keys and exact numeric spellings.
    /// - Parameter value: Object subtree already bounded by the enclosing document parser.
    /// - Throws: `ActivityCatalogError.invalidPayload` for absent required fields, forbidden null or wrong types.
    /// No transport ownership, task creation, suspension, mutation or automatic retries occur.
    public init(value: JSONValue) throws {
        let object = try ActivityObject(value)
        rawFields = object.fields
        self.cdnHost = try object.field("cdn_host", nullable: false) { try ActivityObject.string($0) }
        self.apiEndpoint = try ActivityObject.string(object.required("api_endpoint"))
        self.environment = try ActivityObject.string(object.required("environment"))
    }
}

/// Basic READY user shape; distinct from authenticated and current-user payloads.
/// Construction is synchronous, validates modeled types, retains complete raw fields and starts no I/O.
public struct ActivityReadyUser: ActivityPayload {
    public let rawFields: [String: JSONValue]
    /// Wire `id`. Required and nonnull.
    public let id: String
    /// Wire `username`. Required and nonnull.
    public let username: String
    /// Wire `discriminator`. Required and nonnull.
    public let discriminator: String
    /// Wire `avatar`. Optional; explicit null is rejected.
    public let avatar: Field<String>

    /// Validates this SDK object while preserving unknown keys and exact numeric spellings.
    /// - Parameter value: Object subtree already bounded by the enclosing document parser.
    /// - Throws: `ActivityCatalogError.invalidPayload` for absent required fields, forbidden null or wrong types.
    /// No transport ownership, task creation, suspension, mutation or automatic retries occur.
    public init(value: JSONValue) throws {
        let object = try ActivityObject(value)
        rawFields = object.fields
        self.id = try ActivityObject.string(object.required("id"))
        self.username = try ActivityObject.string(object.required("username"))
        self.discriminator = try ActivityObject.string(object.required("discriminator"))
        self.avatar = try object.field("avatar", nullable: false) { try ActivityObject.string($0) }
    }
}

/// READY payload. Session ownership and one-shot readiness admission belong to ActivityClient.
/// Construction is synchronous, validates modeled types, retains complete raw fields and starts no I/O.
public struct ActivityReady: ActivityPayload {
    public let rawFields: [String: JSONValue]
    /// Wire `v`. Required and nonnull.
    public let version: JSONNumber
    /// Wire `config`. Required and nonnull.
    public let config: ActivityReadyConfig
    /// Wire `user`. Optional; explicit null is rejected.
    public let user: Field<ActivityReadyUser>

    /// Validates this SDK object while preserving unknown keys and exact numeric spellings.
    /// - Parameter value: Object subtree already bounded by the enclosing document parser.
    /// - Throws: `ActivityCatalogError.invalidPayload` for absent required fields, forbidden null or wrong types.
    /// No transport ownership, task creation, suspension, mutation or automatic retries occur.
    public init(value: JSONValue) throws {
        let object = try ActivityObject(value)
        rawFields = object.fields
        self.version = try ActivityObject.number(object.required("v"))
        self.config = try ActivityReadyConfig(value: object.required("config"))
        self.user = try object.field("user", nullable: false) { try ActivityReadyUser(value: $0) }
    }
}

/// SPEAKING_START or SPEAKING_STOP payload; lobby and channel IDs are independently optional.
/// Construction is synchronous, validates modeled types, retains complete raw fields and starts no I/O.
public struct ActivitySpeaking: ActivityPayload {
    public let rawFields: [String: JSONValue]
    /// Wire `lobby_id`. Optional; explicit null is rejected.
    public let lobbyID: Field<String>
    /// Wire `channel_id`. Optional; explicit null is rejected.
    public let channelID: Field<String>
    /// Wire `user_id`. Required and nonnull.
    public let userID: String

    /// Validates this SDK object while preserving unknown keys and exact numeric spellings.
    /// - Parameter value: Object subtree already bounded by the enclosing document parser.
    /// - Throws: `ActivityCatalogError.invalidPayload` for absent required fields, forbidden null or wrong types.
    /// No transport ownership, task creation, suspension, mutation or automatic retries occur.
    public init(value: JSONValue) throws {
        let object = try ActivityObject(value)
        rawFields = object.fields
        self.lobbyID = try object.field("lobby_id", nullable: false) { try ActivityObject.string($0) }
        self.channelID = try object.field("channel_id", nullable: false) { try ActivityObject.string($0) }
        self.userID = try ActivityObject.string(object.required("user_id"))
    }
}

/// Layout update preserving unknown numeric layout modes.
/// Construction is synchronous, validates modeled types, retains complete raw fields and starts no I/O.
public struct ActivityLayoutUpdate: ActivityPayload {
    public let rawFields: [String: JSONValue]
    /// Wire `layout_mode`. Required and nonnull.
    public let layoutMode: JSONNumber

    /// Validates this SDK object while preserving unknown keys and exact numeric spellings.
    /// - Parameter value: Object subtree already bounded by the enclosing document parser.
    /// - Throws: `ActivityCatalogError.invalidPayload` for absent required fields, forbidden null or wrong types.
    /// No transport ownership, task creation, suspension, mutation or automatic retries occur.
    public init(value: JSONValue) throws {
        let object = try ActivityObject(value)
        rawFields = object.fields
        self.layoutMode = try ActivityObject.number(object.required("layout_mode"))
    }
}

/// Orientation update retaining both numeric screen orientation and the deprecated orientation string.
/// Construction is synchronous, validates modeled types, retains complete raw fields and starts no I/O.
public struct ActivityOrientationUpdate: ActivityPayload {
    public let rawFields: [String: JSONValue]
    /// Wire `screen_orientation`. Required and nonnull.
    public let screenOrientation: JSONNumber
    /// Wire `orientation`. Required and nonnull.
    public let orientation: String

    /// Validates this SDK object while preserving unknown keys and exact numeric spellings.
    /// - Parameter value: Object subtree already bounded by the enclosing document parser.
    /// - Throws: `ActivityCatalogError.invalidPayload` for absent required fields, forbidden null or wrong types.
    /// No transport ownership, task creation, suspension, mutation or automatic retries occur.
    public init(value: JSONValue) throws {
        let object = try ActivityObject(value)
        rawFields = object.fields
        self.screenOrientation = try ActivityObject.number(object.required("screen_orientation"))
        self.orientation = try ActivityObject.string(object.required("orientation"))
    }
}

/// Thermal-state update retaining unknown numeric states for future compatibility.
/// Construction is synchronous, validates modeled types, retains complete raw fields and starts no I/O.
public struct ActivityThermalUpdate: ActivityPayload {
    public let rawFields: [String: JSONValue]
    /// Wire `thermal_state`. Required and nonnull.
    public let thermalState: JSONNumber

    /// Validates this SDK object while preserving unknown keys and exact numeric spellings.
    /// - Parameter value: Object subtree already bounded by the enclosing document parser.
    /// - Throws: `ActivityCatalogError.invalidPayload` for absent required fields, forbidden null or wrong types.
    /// No transport ownership, task creation, suspension, mutation or automatic retries occur.
    public init(value: JSONValue) throws {
        let object = try ActivityObject(value)
        rawFields = object.fields
        self.thermalState = try ActivityObject.number(object.required("thermal_state"))
    }
}

/// ENTITLEMENT_CREATE payload. The public reference still marks this event unavailable during Developer Preview.
/// Construction is synchronous, validates modeled types, retains complete raw fields and starts no I/O.
public struct ActivityEntitlementCreate: ActivityPayload {
    public let rawFields: [String: JSONValue]
    /// Wire `entitlement`. Required and nonnull.
    public let entitlement: ActivityEntitlement

    /// Validates this SDK object while preserving unknown keys and exact numeric spellings.
    /// - Parameter value: Object subtree already bounded by the enclosing document parser.
    /// - Throws: `ActivityCatalogError.invalidPayload` for absent required fields, forbidden null or wrong types.
    /// No transport ownership, task creation, suspension, mutation or automatic retries occur.
    public init(value: JSONValue) throws {
        let object = try ActivityObject(value)
        rawFields = object.fields
        self.entitlement = try ActivityEntitlement(value: object.required("entitlement"))
    }
}

/// Source-only ACTIVITY_JOIN event. Join secrets are explicit for caller use and redacted from diagnostics.
/// Construction is synchronous, validates modeled types, retains complete raw fields and starts no I/O.
public struct ActivityJoin: ActivityPayload {
    public let rawFields: [String: JSONValue]
    /// Wire `applicationId`. Required and nonnull.
    public let applicationID: String
    /// Wire `secret`. Required and nonnull.
    public let secret: String

    /// Validates this SDK object while preserving unknown keys and exact numeric spellings.
    /// - Parameter value: Object subtree already bounded by the enclosing document parser.
    /// - Throws: `ActivityCatalogError.invalidPayload` for absent required fields, forbidden null or wrong types.
    /// No transport ownership, task creation, suspension, mutation or automatic retries occur.
    public init(value: JSONValue) throws {
        let object = try ActivityObject(value)
        rawFields = object.fields
        self.applicationID = try ActivityObject.string(object.required("applicationId"))
        self.secret = try ActivityObject.string(object.required("secret"))
    }
}

/// Structured host ERROR payload; the error message is retained explicitly and redacted from diagnostics.
/// Construction is synchronous, validates modeled types, retains complete raw fields and starts no I/O.
public struct ActivityHostError: ActivityPayload {
    public let rawFields: [String: JSONValue]
    /// Wire `code`. Required and nonnull.
    public let code: JSONNumber
    /// Wire `message`. Optional; explicit null is rejected.
    public let message: Field<String>

    /// Validates this SDK object while preserving unknown keys and exact numeric spellings.
    /// - Parameter value: Object subtree already bounded by the enclosing document parser.
    /// - Throws: `ActivityCatalogError.invalidPayload` for absent required fields, forbidden null or wrong types.
    /// No transport ownership, task creation, suspension, mutation or automatic retries occur.
    public init(value: JSONValue) throws {
        let object = try ActivityObject(value)
        rawFields = object.fields
        self.code = try ActivityObject.number(object.required("code"))
        self.message = try object.field("message", nullable: false) { try ActivityObject.string($0) }
    }
}

/// Subscription-control acknowledgement identifying the accepted event name.
/// Construction is synchronous, validates modeled types, retains complete raw fields and starts no I/O.
public struct ActivitySubscriptionResponse: ActivityPayload {
    public let rawFields: [String: JSONValue]
    /// Wire `evt`. Required and nonnull.
    public let event: String

    /// Validates this SDK object while preserving unknown keys and exact numeric spellings.
    /// - Parameter value: Object subtree already bounded by the enclosing document parser.
    /// - Throws: `ActivityCatalogError.invalidPayload` for absent required fields, forbidden null or wrong types.
    /// No transport ownership, task creation, suspension, mutation or automatic retries occur.
    public init(value: JSONValue) throws {
        let object = try ActivityObject(value)
        rawFields = object.fields
        self.event = try ActivityObject.string(object.required("evt"))
    }
}

/// Channel mention embedded in an Activity message.
/// Construction is synchronous, validates modeled types, retains complete raw fields and starts no I/O.
public struct ActivityChannelMention: ActivityPayload {
    public let rawFields: [String: JSONValue]
    /// Wire `id`. Required and nonnull.
    public let id: String
    /// Wire `guild_id`. Required and nonnull.
    public let guildID: String
    /// Wire `type`. Required and nonnull.
    public let type: JSONNumber
    /// Wire `name`. Required and nonnull.
    public let name: String

    /// Validates this SDK object while preserving unknown keys and exact numeric spellings.
    /// - Parameter value: Object subtree already bounded by the enclosing document parser.
    /// - Throws: `ActivityCatalogError.invalidPayload` for absent required fields, forbidden null or wrong types.
    /// No transport ownership, task creation, suspension, mutation or automatic retries occur.
    public init(value: JSONValue) throws {
        let object = try ActivityObject(value)
        rawFields = object.fields
        self.id = try ActivityObject.string(object.required("id"))
        self.guildID = try ActivityObject.string(object.required("guild_id"))
        self.type = try ActivityObject.number(object.required("type"))
        self.name = try ActivityObject.string(object.required("name"))
    }
}

/// Message attachment with original numeric sizes and nullable dimensions.
/// Construction is synchronous, validates modeled types, retains complete raw fields and starts no I/O.
public struct ActivityAttachment: ActivityPayload {
    public let rawFields: [String: JSONValue]
    /// Wire `id`. Required and nonnull.
    public let id: String
    /// Wire `filename`. Required and nonnull.
    public let filename: String
    /// Wire `size`. Required and nonnull.
    public let size: JSONNumber
    /// Wire `url`. Required and nonnull.
    public let url: String
    /// Wire `proxy_url`. Required and nonnull.
    public let proxyURL: String
    /// Wire `height`. Optional; omission is distinct from explicit null.
    public let height: Field<JSONNumber>
    /// Wire `width`. Optional; omission is distinct from explicit null.
    public let width: Field<JSONNumber>

    /// Validates this SDK object while preserving unknown keys and exact numeric spellings.
    /// - Parameter value: Object subtree already bounded by the enclosing document parser.
    /// - Throws: `ActivityCatalogError.invalidPayload` for absent required fields, forbidden null or wrong types.
    /// No transport ownership, task creation, suspension, mutation or automatic retries occur.
    public init(value: JSONValue) throws {
        let object = try ActivityObject(value)
        rawFields = object.fields
        self.id = try ActivityObject.string(object.required("id"))
        self.filename = try ActivityObject.string(object.required("filename"))
        self.size = try ActivityObject.number(object.required("size"))
        self.url = try ActivityObject.string(object.required("url"))
        self.proxyURL = try ActivityObject.string(object.required("proxy_url"))
        self.height = try object.field("height", nullable: true) { try ActivityObject.number($0) }
        self.width = try object.field("width", nullable: true) { try ActivityObject.number($0) }
    }
}

/// Message embed footer.
/// Construction is synchronous, validates modeled types, retains complete raw fields and starts no I/O.
public struct ActivityEmbedFooter: ActivityPayload {
    public let rawFields: [String: JSONValue]
    /// Wire `text`. Required and nonnull.
    public let text: String
    /// Wire `icon_url`. Optional; omission is distinct from explicit null.
    public let iconURL: Field<String>
    /// Wire `proxy_icon_url`. Optional; omission is distinct from explicit null.
    public let proxyIconURL: Field<String>

    /// Validates this SDK object while preserving unknown keys and exact numeric spellings.
    /// - Parameter value: Object subtree already bounded by the enclosing document parser.
    /// - Throws: `ActivityCatalogError.invalidPayload` for absent required fields, forbidden null or wrong types.
    /// No transport ownership, task creation, suspension, mutation or automatic retries occur.
    public init(value: JSONValue) throws {
        let object = try ActivityObject(value)
        rawFields = object.fields
        self.text = try ActivityObject.string(object.required("text"))
        self.iconURL = try object.field("icon_url", nullable: true) { try ActivityObject.string($0) }
        self.proxyIconURL = try object.field("proxy_icon_url", nullable: true) { try ActivityObject.string($0) }
    }
}

/// Embed image or thumbnail projection.
/// Construction is synchronous, validates modeled types, retains complete raw fields and starts no I/O.
public struct ActivityImage: ActivityPayload {
    public let rawFields: [String: JSONValue]
    /// Wire `url`. Optional; omission is distinct from explicit null.
    public let url: Field<String>
    /// Wire `proxy_url`. Optional; omission is distinct from explicit null.
    public let proxyURL: Field<String>
    /// Wire `height`. Optional; omission is distinct from explicit null.
    public let height: Field<JSONNumber>
    /// Wire `width`. Optional; omission is distinct from explicit null.
    public let width: Field<JSONNumber>

    /// Validates this SDK object while preserving unknown keys and exact numeric spellings.
    /// - Parameter value: Object subtree already bounded by the enclosing document parser.
    /// - Throws: `ActivityCatalogError.invalidPayload` for absent required fields, forbidden null or wrong types.
    /// No transport ownership, task creation, suspension, mutation or automatic retries occur.
    public init(value: JSONValue) throws {
        let object = try ActivityObject(value)
        rawFields = object.fields
        self.url = try object.field("url", nullable: true) { try ActivityObject.string($0) }
        self.proxyURL = try object.field("proxy_url", nullable: true) { try ActivityObject.string($0) }
        self.height = try object.field("height", nullable: true) { try ActivityObject.number($0) }
        self.width = try object.field("width", nullable: true) { try ActivityObject.number($0) }
    }
}

/// Embed video projection, distinct from images because proxy_url is not part of its schema.
/// Construction is synchronous, validates modeled types, retains complete raw fields and starts no I/O.
public struct ActivityVideo: ActivityPayload {
    public let rawFields: [String: JSONValue]
    /// Wire `url`. Optional; omission is distinct from explicit null.
    public let url: Field<String>
    /// Wire `height`. Optional; omission is distinct from explicit null.
    public let height: Field<JSONNumber>
    /// Wire `width`. Optional; omission is distinct from explicit null.
    public let width: Field<JSONNumber>

    /// Validates this SDK object while preserving unknown keys and exact numeric spellings.
    /// - Parameter value: Object subtree already bounded by the enclosing document parser.
    /// - Throws: `ActivityCatalogError.invalidPayload` for absent required fields, forbidden null or wrong types.
    /// No transport ownership, task creation, suspension, mutation or automatic retries occur.
    public init(value: JSONValue) throws {
        let object = try ActivityObject(value)
        rawFields = object.fields
        self.url = try object.field("url", nullable: true) { try ActivityObject.string($0) }
        self.height = try object.field("height", nullable: true) { try ActivityObject.number($0) }
        self.width = try object.field("width", nullable: true) { try ActivityObject.number($0) }
    }
}

/// Message embed provider.
/// Construction is synchronous, validates modeled types, retains complete raw fields and starts no I/O.
public struct ActivityEmbedProvider: ActivityPayload {
    public let rawFields: [String: JSONValue]
    /// Wire `name`. Optional; omission is distinct from explicit null.
    public let name: Field<String>
    /// Wire `url`. Optional; omission is distinct from explicit null.
    public let url: Field<String>

    /// Validates this SDK object while preserving unknown keys and exact numeric spellings.
    /// - Parameter value: Object subtree already bounded by the enclosing document parser.
    /// - Throws: `ActivityCatalogError.invalidPayload` for absent required fields, forbidden null or wrong types.
    /// No transport ownership, task creation, suspension, mutation or automatic retries occur.
    public init(value: JSONValue) throws {
        let object = try ActivityObject(value)
        rawFields = object.fields
        self.name = try object.field("name", nullable: true) { try ActivityObject.string($0) }
        self.url = try object.field("url", nullable: true) { try ActivityObject.string($0) }
    }
}

/// Message embed author.
/// Construction is synchronous, validates modeled types, retains complete raw fields and starts no I/O.
public struct ActivityEmbedAuthor: ActivityPayload {
    public let rawFields: [String: JSONValue]
    /// Wire `name`. Optional; omission is distinct from explicit null.
    public let name: Field<String>
    /// Wire `url`. Optional; omission is distinct from explicit null.
    public let url: Field<String>
    /// Wire `icon_url`. Optional; omission is distinct from explicit null.
    public let iconURL: Field<String>
    /// Wire `proxy_icon_url`. Optional; omission is distinct from explicit null.
    public let proxyIconURL: Field<String>

    /// Validates this SDK object while preserving unknown keys and exact numeric spellings.
    /// - Parameter value: Object subtree already bounded by the enclosing document parser.
    /// - Throws: `ActivityCatalogError.invalidPayload` for absent required fields, forbidden null or wrong types.
    /// No transport ownership, task creation, suspension, mutation or automatic retries occur.
    public init(value: JSONValue) throws {
        let object = try ActivityObject(value)
        rawFields = object.fields
        self.name = try object.field("name", nullable: true) { try ActivityObject.string($0) }
        self.url = try object.field("url", nullable: true) { try ActivityObject.string($0) }
        self.iconURL = try object.field("icon_url", nullable: true) { try ActivityObject.string($0) }
        self.proxyIconURL = try object.field("proxy_icon_url", nullable: true) { try ActivityObject.string($0) }
    }
}

/// Message embed field; inline is required in the SDK schema.
/// Construction is synchronous, validates modeled types, retains complete raw fields and starts no I/O.
public struct ActivityEmbedField: ActivityPayload {
    public let rawFields: [String: JSONValue]
    /// Wire `name`. Required and nonnull.
    public let name: String
    /// Wire `value`. Required and nonnull.
    public let value: String
    /// Wire `inline`. Required and nonnull.
    public let inline: Bool

    /// Validates this SDK object while preserving unknown keys and exact numeric spellings.
    /// - Parameter value: Object subtree already bounded by the enclosing document parser.
    /// - Throws: `ActivityCatalogError.invalidPayload` for absent required fields, forbidden null or wrong types.
    /// No transport ownership, task creation, suspension, mutation or automatic retries occur.
    public init(value: JSONValue) throws {
        let object = try ActivityObject(value)
        rawFields = object.fields
        self.name = try ActivityObject.string(object.required("name"))
        self.value = try ActivityObject.string(object.required("value"))
        self.inline = try ActivityObject.bool(object.required("inline"))
    }
}

/// Message embed preserving every common SDK field and unknown children.
/// Construction is synchronous, validates modeled types, retains complete raw fields and starts no I/O.
public struct ActivityEmbed: ActivityPayload {
    public let rawFields: [String: JSONValue]
    /// Wire `title`. Optional; omission is distinct from explicit null.
    public let title: Field<String>
    /// Wire `type`. Optional; omission is distinct from explicit null.
    public let type: Field<String>
    /// Wire `description`. Optional; omission is distinct from explicit null.
    public let textDescription: Field<String>
    /// Wire `url`. Optional; omission is distinct from explicit null.
    public let url: Field<String>
    /// Wire `timestamp`. Optional; omission is distinct from explicit null.
    public let timestamp: Field<String>
    /// Wire `color`. Optional; omission is distinct from explicit null.
    public let color: Field<JSONNumber>
    /// Wire `footer`. Optional; omission is distinct from explicit null.
    public let footer: Field<ActivityEmbedFooter>
    /// Wire `image`. Optional; omission is distinct from explicit null.
    public let image: Field<ActivityImage>
    /// Wire `thumbnail`. Optional; omission is distinct from explicit null.
    public let thumbnail: Field<ActivityImage>
    /// Wire `video`. Optional; omission is distinct from explicit null.
    public let video: Field<ActivityVideo>
    /// Wire `provider`. Optional; omission is distinct from explicit null.
    public let provider: Field<ActivityEmbedProvider>
    /// Wire `author`. Optional; omission is distinct from explicit null.
    public let author: Field<ActivityEmbedAuthor>
    /// Wire `fields`. Optional; omission is distinct from explicit null.
    public let fields: Field<[ActivityEmbedField]>

    /// Validates this SDK object while preserving unknown keys and exact numeric spellings.
    /// - Parameter value: Object subtree already bounded by the enclosing document parser.
    /// - Throws: `ActivityCatalogError.invalidPayload` for absent required fields, forbidden null or wrong types.
    /// No transport ownership, task creation, suspension, mutation or automatic retries occur.
    public init(value: JSONValue) throws {
        let object = try ActivityObject(value)
        rawFields = object.fields
        self.title = try object.field("title", nullable: true) { try ActivityObject.string($0) }
        self.type = try object.field("type", nullable: true) { try ActivityObject.string($0) }
        self.textDescription = try object.field("description", nullable: true) { try ActivityObject.string($0) }
        self.url = try object.field("url", nullable: true) { try ActivityObject.string($0) }
        self.timestamp = try object.field("timestamp", nullable: true) { try ActivityObject.string($0) }
        self.color = try object.field("color", nullable: true) { try ActivityObject.number($0) }
        self.footer = try object.field("footer", nullable: true) { try ActivityEmbedFooter(value: $0) }
        self.image = try object.field("image", nullable: true) { try ActivityImage(value: $0) }
        self.thumbnail = try object.field("thumbnail", nullable: true) { try ActivityImage(value: $0) }
        self.video = try object.field("video", nullable: true) { try ActivityVideo(value: $0) }
        self.provider = try object.field("provider", nullable: true) { try ActivityEmbedProvider(value: $0) }
        self.author = try object.field("author", nullable: true) { try ActivityEmbedAuthor(value: $0) }
        self.fields = try object.field("fields", nullable: true) { try ActivityObject.array($0) { try ActivityEmbedField(value: $0) } }
    }
}

/// Message reaction projection.
/// Construction is synchronous, validates modeled types, retains complete raw fields and starts no I/O.
public struct ActivityReaction: ActivityPayload {
    public let rawFields: [String: JSONValue]
    /// Wire `count`. Required and nonnull.
    public let count: JSONNumber
    /// Wire `me`. Required and nonnull.
    public let me: Bool
    /// Wire `emoji`. Required and nonnull.
    public let emoji: ActivityEmoji

    /// Validates this SDK object while preserving unknown keys and exact numeric spellings.
    /// - Parameter value: Object subtree already bounded by the enclosing document parser.
    /// - Throws: `ActivityCatalogError.invalidPayload` for absent required fields, forbidden null or wrong types.
    /// No transport ownership, task creation, suspension, mutation or automatic retries occur.
    public init(value: JSONValue) throws {
        let object = try ActivityObject(value)
        rawFields = object.fields
        self.count = try ActivityObject.number(object.required("count"))
        self.me = try ActivityObject.bool(object.required("me"))
        self.emoji = try ActivityEmoji(value: object.required("emoji"))
    }
}

/// Message Activity attachment projection.
/// Construction is synchronous, validates modeled types, retains complete raw fields and starts no I/O.
public struct ActivityMessageActivity: ActivityPayload {
    public let rawFields: [String: JSONValue]
    /// Wire `type`. Required and nonnull.
    public let type: JSONNumber
    /// Wire `party_id`. Optional; omission is distinct from explicit null.
    public let partyID: Field<String>

    /// Validates this SDK object while preserving unknown keys and exact numeric spellings.
    /// - Parameter value: Object subtree already bounded by the enclosing document parser.
    /// - Throws: `ActivityCatalogError.invalidPayload` for absent required fields, forbidden null or wrong types.
    /// No transport ownership, task creation, suspension, mutation or automatic retries occur.
    public init(value: JSONValue) throws {
        let object = try ActivityObject(value)
        rawFields = object.fields
        self.type = try ActivityObject.number(object.required("type"))
        self.partyID = try object.field("party_id", nullable: true) { try ActivityObject.string($0) }
    }
}

/// Application embedded in a message Activity attachment.
/// Construction is synchronous, validates modeled types, retains complete raw fields and starts no I/O.
public struct ActivityMessageApplication: ActivityPayload {
    public let rawFields: [String: JSONValue]
    /// Wire `id`. Required and nonnull.
    public let id: String
    /// Wire `cover_image`. Optional; omission is distinct from explicit null.
    public let coverImage: Field<String>
    /// Wire `description`. Required and nonnull.
    public let textDescription: String
    /// Wire `icon`. Optional; omission is distinct from explicit null.
    public let icon: Field<String>
    /// Wire `name`. Required and nonnull.
    public let name: String

    /// Validates this SDK object while preserving unknown keys and exact numeric spellings.
    /// - Parameter value: Object subtree already bounded by the enclosing document parser.
    /// - Throws: `ActivityCatalogError.invalidPayload` for absent required fields, forbidden null or wrong types.
    /// No transport ownership, task creation, suspension, mutation or automatic retries occur.
    public init(value: JSONValue) throws {
        let object = try ActivityObject(value)
        rawFields = object.fields
        self.id = try ActivityObject.string(object.required("id"))
        self.coverImage = try object.field("cover_image", nullable: true) { try ActivityObject.string($0) }
        self.textDescription = try ActivityObject.string(object.required("description"))
        self.icon = try object.field("icon", nullable: true) { try ActivityObject.string($0) }
        self.name = try ActivityObject.string(object.required("name"))
    }
}

/// Message reference preserving independently omitted and nullable resource identifiers.
/// Construction is synchronous, validates modeled types, retains complete raw fields and starts no I/O.
public struct ActivityMessageReference: ActivityPayload {
    public let rawFields: [String: JSONValue]
    /// Wire `message_id`. Optional; omission is distinct from explicit null.
    public let messageID: Field<String>
    /// Wire `channel_id`. Optional; omission is distinct from explicit null.
    public let channelID: Field<String>
    /// Wire `guild_id`. Optional; omission is distinct from explicit null.
    public let guildID: Field<String>

    /// Validates this SDK object while preserving unknown keys and exact numeric spellings.
    /// - Parameter value: Object subtree already bounded by the enclosing document parser.
    /// - Throws: `ActivityCatalogError.invalidPayload` for absent required fields, forbidden null or wrong types.
    /// No transport ownership, task creation, suspension, mutation or automatic retries occur.
    public init(value: JSONValue) throws {
        let object = try ActivityObject(value)
        rawFields = object.fields
        self.messageID = try object.field("message_id", nullable: true) { try ActivityObject.string($0) }
        self.channelID = try object.field("channel_id", nullable: true) { try ActivityObject.string($0) }
        self.guildID = try object.field("guild_id", nullable: true) { try ActivityObject.string($0) }
    }
}

/// Full common SDK message projection. Unspecified sticker and referenced_message schemas stay lossless JSON values.
/// Construction is synchronous, validates modeled types, retains complete raw fields and starts no I/O.
public struct ActivityMessage: ActivityPayload {
    public let rawFields: [String: JSONValue]
    /// Wire `id`. Required and nonnull.
    public let id: String
    /// Wire `channel_id`. Required and nonnull.
    public let channelID: String
    /// Wire `guild_id`. Optional; omission is distinct from explicit null.
    public let guildID: Field<String>
    /// Wire `author`. Optional; omission is distinct from explicit null.
    public let author: Field<ActivityUser>
    /// Wire `member`. Optional; omission is distinct from explicit null.
    public let member: Field<ActivityGuildMember>
    /// Wire `content`. Required and nonnull.
    public let content: String
    /// Wire `timestamp`. Required and nonnull.
    public let timestamp: String
    /// Wire `edited_timestamp`. Optional; omission is distinct from explicit null.
    public let editedTimestamp: Field<String>
    /// Wire `tts`. Required and nonnull.
    public let tts: Bool
    /// Wire `mention_everyone`. Required and nonnull.
    public let mentionEveryone: Bool
    /// Wire `mentions`. Required and nonnull.
    public let mentions: [ActivityUser]
    /// Wire `mention_roles`. Required and nonnull.
    public let mentionRoles: [String]
    /// Wire `mention_channels`. Required and nonnull.
    public let mentionChannels: [ActivityChannelMention]
    /// Wire `attachments`. Required and nonnull.
    public let attachments: [ActivityAttachment]
    /// Wire `embeds`. Required and nonnull.
    public let embeds: [ActivityEmbed]
    /// Wire `reactions`. Optional; omission is distinct from explicit null.
    public let reactions: Field<[ActivityReaction]>
    /// Wire `nonce`. Optional; omission is distinct from explicit null.
    public let nonce: Field<JSONValue>
    /// Wire `pinned`. Required and nonnull.
    public let pinned: Bool
    /// Wire `webhook_id`. Optional; omission is distinct from explicit null.
    public let webhookID: Field<String>
    /// Wire `type`. Required and nonnull.
    public let type: JSONNumber
    /// Wire `activity`. Optional; omission is distinct from explicit null.
    public let activity: Field<ActivityMessageActivity>
    /// Wire `application`. Optional; omission is distinct from explicit null.
    public let application: Field<ActivityMessageApplication>
    /// Wire `message_reference`. Optional; omission is distinct from explicit null.
    public let messageReference: Field<ActivityMessageReference>
    /// Wire `flags`. Optional; omission is distinct from explicit null.
    public let flags: Field<JSONNumber>
    /// Wire `stickers`. Optional; omission is distinct from explicit null.
    public let stickers: Field<[JSONValue]>
    /// Wire `referenced_message`. Optional; omission is distinct from explicit null.
    public let referencedMessage: Field<JSONValue>

    /// Validates this SDK object while preserving unknown keys and exact numeric spellings.
    /// - Parameter value: Object subtree already bounded by the enclosing document parser.
    /// - Throws: `ActivityCatalogError.invalidPayload` for absent required fields, forbidden null or wrong types.
    /// No transport ownership, task creation, suspension, mutation or automatic retries occur.
    public init(value: JSONValue) throws {
        let object = try ActivityObject(value)
        rawFields = object.fields
        self.id = try ActivityObject.string(object.required("id"))
        self.channelID = try ActivityObject.string(object.required("channel_id"))
        self.guildID = try object.field("guild_id", nullable: true) { try ActivityObject.string($0) }
        self.author = try object.field("author", nullable: true) { try ActivityUser(value: $0) }
        self.member = try object.field("member", nullable: true) { try ActivityGuildMember(value: $0) }
        self.content = try ActivityObject.string(object.required("content"))
        self.timestamp = try ActivityObject.string(object.required("timestamp"))
        self.editedTimestamp = try object.field("edited_timestamp", nullable: true) { try ActivityObject.string($0) }
        self.tts = try ActivityObject.bool(object.required("tts"))
        self.mentionEveryone = try ActivityObject.bool(object.required("mention_everyone"))
        self.mentions = try ActivityObject.array(object.required("mentions")) { try ActivityUser(value: $0) }
        self.mentionRoles = try ActivityObject.array(object.required("mention_roles")) { try ActivityObject.string($0) }
        self.mentionChannels = try ActivityObject.array(object.required("mention_channels")) { try ActivityChannelMention(value: $0) }
        self.attachments = try ActivityObject.array(object.required("attachments")) { try ActivityAttachment(value: $0) }
        self.embeds = try ActivityObject.array(object.required("embeds")) { try ActivityEmbed(value: $0) }
        self.reactions = try object.field("reactions", nullable: true) { try ActivityObject.array($0) { try ActivityReaction(value: $0) } }
        self.nonce = try object.field("nonce", nullable: true) { ActivityObject.identity($0) }
        self.pinned = try ActivityObject.bool(object.required("pinned"))
        self.webhookID = try object.field("webhook_id", nullable: true) { try ActivityObject.string($0) }
        self.type = try ActivityObject.number(object.required("type"))
        self.activity = try object.field("activity", nullable: true) { try ActivityMessageActivity(value: $0) }
        self.application = try object.field("application", nullable: true) { try ActivityMessageApplication(value: $0) }
        self.messageReference = try object.field("message_reference", nullable: true) { try ActivityMessageReference(value: $0) }
        self.flags = try object.field("flags", nullable: true) { try ActivityObject.number($0) }
        self.stickers = try object.field("stickers", nullable: true) { try ActivityObject.array($0) { ActivityObject.identity($0) } }
        self.referencedMessage = try object.field("referenced_message", nullable: true) { ActivityObject.identity($0) }
        if case .value(let value) = nonce { _ = try ActivityObject.scalarCode(value) }
    }
}

/// GET_CHANNEL result using the SDK response schema. Guild channels require guilds; GDM additionally requires approved dm_channels.read.
/// Construction is synchronous, validates modeled types, retains complete raw fields and starts no I/O.
public struct ActivityChannel: ActivityPayload {
    public let rawFields: [String: JSONValue]
    /// Wire `id`. Required and nonnull.
    public let id: String
    /// Wire `type`. Required and nonnull.
    public let type: JSONNumber
    /// Wire `guild_id`. Optional; omission is distinct from explicit null.
    public let guildID: Field<String>
    /// Wire `name`. Optional; omission is distinct from explicit null.
    public let name: Field<String>
    /// Wire `topic`. Optional; omission is distinct from explicit null.
    public let topic: Field<String>
    /// Wire `bitrate`. Optional; omission is distinct from explicit null.
    public let bitrate: Field<JSONNumber>
    /// Wire `user_limit`. Optional; omission is distinct from explicit null.
    public let userLimit: Field<JSONNumber>
    /// Wire `position`. Optional; omission is distinct from explicit null.
    public let position: Field<JSONNumber>
    /// Wire `voice_states`. Required and nonnull.
    public let voiceStates: [ActivityUserVoiceState]
    /// Wire `messages`. Required and nonnull.
    public let messages: [ActivityMessage]

    /// Validates this SDK object while preserving unknown keys and exact numeric spellings.
    /// - Parameter value: Object subtree already bounded by the enclosing document parser.
    /// - Throws: `ActivityCatalogError.invalidPayload` for absent required fields, forbidden null or wrong types.
    /// No transport ownership, task creation, suspension, mutation or automatic retries occur.
    public init(value: JSONValue) throws {
        let object = try ActivityObject(value)
        rawFields = object.fields
        self.id = try ActivityObject.string(object.required("id"))
        self.type = try ActivityObject.number(object.required("type"))
        self.guildID = try object.field("guild_id", nullable: true) { try ActivityObject.string($0) }
        self.name = try object.field("name", nullable: true) { try ActivityObject.string($0) }
        self.topic = try object.field("topic", nullable: true) { try ActivityObject.string($0) }
        self.bitrate = try object.field("bitrate", nullable: true) { try ActivityObject.number($0) }
        self.userLimit = try object.field("user_limit", nullable: true) { try ActivityObject.number($0) }
        self.position = try object.field("position", nullable: true) { try ActivityObject.number($0) }
        self.voiceStates = try ActivityObject.array(object.required("voice_states")) { try ActivityUserVoiceState(value: $0) }
        self.messages = try ActivityObject.array(object.required("messages")) { try ActivityMessage(value: $0) }
    }
}
