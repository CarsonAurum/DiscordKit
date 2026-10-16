import DiscordCore
import Foundation

/// Known Nitro subscription values. Unknown numeric values survive in `RawValue`.
public enum PremiumType: Int, Sendable {
    case none = 0, nitroClassic = 1, nitro = 2, nitroBasic = 3
}

/// A current-user response with typed identity and presence-aware profile fields.
/// This is a deliberately partial typed projection of Discord API v10, verified
/// 2026-10-16 against <https://docs.discord.com/developers/resources/user>.
/// `rawFields` retains every original field, including future numeric values.
/// Optional fields depend on OAuth scopes; absence never means an empty value.
public struct User: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let id: UserID
    public let username: String
    public let discriminator: String
    public let globalName: Nullable<String>
    public let avatar: Nullable<String>
    public let bot: Field<Bool>
    public let system: Field<Bool>
    public let mfaEnabled: Field<Bool>
    public let banner: Field<String>
    public let accentColor: Field<Int>
    public let locale: Field<String>
    public let verified: Field<Bool>
    public let email: Field<String>
    public let flags: Field<UInt64>
    public let publicFlags: Field<UInt64>
    public let premiumType: Field<RawValue<PremiumType>>
    /// Exact complete payload fields. Nested decoration, collectibles and primary-guild models remain untyped.
    public let rawFields: [String: JSONValue]

    /// Parses a complete, bounded user object without rounding unknown numeric fields.
    /// - Parameters:
    ///   - data: API v10 JSON object. Required nullable `global_name` and `avatar` must be present.
    ///   - limits: Explicit JSON byte/depth/node bounds, defaulting to 1 MiB/64/100,000.
    /// - Throws: Safe JSON parser errors or `DiscordError.transport(.invalidResponse)` for missing,
    ///   incorrectly typed or illegally null modeled fields. Extra fields are preserved without validation.
    ///
    /// Parsing is synchronous and performs no I/O. Large snowflakes use decimal strings; numeric
    /// discriminators follow exact JSON integer spelling rather than Foundation fractional coercion.
    public init(data: Data, limits: JSONLimits = .default) throws {
        let object = try ResourceObject(data: data, limits: limits)
        id = try object.required("id", as: UserID.self)
        username = try object.required("username", as: String.self)
        discriminator = try object.required("discriminator", as: String.self)
        globalName = try object.required("global_name", as: Nullable<String>.self)
        avatar = try object.required("avatar", as: Nullable<String>.self)
        bot = try object.field("bot", as: Bool.self)
        system = try object.field("system", as: Bool.self)
        mfaEnabled = try object.field("mfa_enabled", as: Bool.self)
        banner = try object.field("banner", as: String.self, nullable: true)
        accentColor = try object.field("accent_color", as: Int.self, nullable: true)
        locale = try object.field("locale", as: String.self)
        verified = try object.field("verified", as: Bool.self)
        email = try object.field("email", as: String.self, nullable: true)
        flags = try object.field("flags", as: UInt64.self)
        publicFlags = try object.field("public_flags", as: UInt64.self)
        premiumType = try object.field("premium_type", as: RawValue<PremiumType>.self)
        rawFields = object.fields
    }

    /// Conceals profile strings, email addresses and raw payloads in ordinary diagnostics.
    public var description: String { "User(redacted)" }
    /// Uses the same redacted marker during debug formatting.
    public var debugDescription: String { description }
    /// Prevents reflection-based logging from expanding personal data.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}

/// A current-application response with explicit nullability and unknown-field preservation.
/// This is a partial typed projection, not complete application/team/guild parity.
/// API v10 source: <https://docs.discord.com/developers/resources/application>, verified 2026-10-16.
public struct Application: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let id: ApplicationID
    public let name: String
    public let icon: Nullable<String>
    public let applicationDescription: String
    public let botPublic: Bool
    public let botRequireCodeGrant: Bool
    public let verifyKey: String
    /// Required nullable team payload; nested team members are retained without a typed support claim.
    public let team: Nullable<JSONValue>
    public let rpcOrigins: Field<[String]>
    public let guildID: Field<GuildID>
    public let flags: Field<UInt64>
    /// Full response-only flag bitset string, retaining values beyond native integer widths.
    public let flagsNew: Field<String>
    public let approximateGuildCount: Field<Int>
    public let approximateUserInstallCount: Field<Int>
    public let interactionsEndpointURL: Field<String>
    public let tags: Field<[String]>
    /// Complete raw object, preserving partial bot/owner objects and all newly added fields.
    public let rawFields: [String: JSONValue]

    /// Parses a current-application snapshot under explicit JSON resource bounds.
    /// - Parameters:
    ///   - data: Complete JSON application object; required nullable icon/team fields must be present.
    ///   - limits: Byte/depth/node bounds, with standard defaults.
    /// - Throws: Safe parser errors or `DiscordError.transport(.invalidResponse)` for missing,
    ///   malformed or illegally null modeled fields. Unknown/nested fields retain exact JSON lexemes.
    ///
    /// No credentials, network I/O or ownership transitions occur. Server validity of verification
    /// keys and URLs is not established by decoding; none is used as an authenticated destination.
    public init(data: Data, limits: JSONLimits = .default) throws {
        let object = try ResourceObject(data: data, limits: limits)
        id = try object.required("id", as: ApplicationID.self)
        name = try object.required("name", as: String.self)
        icon = try object.required("icon", as: Nullable<String>.self)
        applicationDescription = try object.required("description", as: String.self)
        botPublic = try object.required("bot_public", as: Bool.self)
        botRequireCodeGrant = try object.required("bot_require_code_grant", as: Bool.self)
        verifyKey = try object.required("verify_key", as: String.self)
        guard let rawTeam = object.fields["team"], rawTeam == .null || {
            if case .object = rawTeam { return true }; return false
        }() else { throw DiscordError.transport(.invalidResponse) }
        team = rawTeam == .null ? .null : .value(rawTeam)
        rpcOrigins = try object.field("rpc_origins", as: [String].self)
        guildID = try object.field("guild_id", as: GuildID.self)
        flags = try object.field("flags", as: UInt64.self)
        flagsNew = try object.field("flags_new", as: String.self)
        approximateGuildCount = try object.field("approximate_guild_count", as: Int.self)
        approximateUserInstallCount = try object.field("approximate_user_install_count", as: Int.self)
        interactionsEndpointURL = try object.field("interactions_endpoint_url", as: String.self, nullable: true)
        tags = try object.field("tags", as: [String].self)
        rawFields = object.fields
    }

    /// Redacts application configuration and raw payloads from ordinary diagnostics.
    public var description: String { "Application(redacted)" }
    /// Uses the same redacted marker during debug formatting.
    public var debugDescription: String { description }
    /// Prevents reflection from expanding server-provided configuration strings.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}

/// Shared bounded JSON projection retaining exact unmodeled values for both resources.
private struct ResourceObject {
    let fields: [String: JSONValue]
    let limits: JSONLimits

    /// Requires a complete JSON object before any typed field is inspected.
    /// - Parameters:
    ///   - data: Complete untrusted UTF-8 JSON bytes.
    ///   - limits: Bounds shared by parsing and per-field serialization.
    /// - Throws: Safe parser errors or invalid-response errors for a scalar/array root.
    init(data: Data, limits: JSONLimits) throws {
        guard case .object(let fields) = try JSONValue.parse(data, limits: limits)
        else { throw DiscordError.transport(.invalidResponse) }
        self.fields = fields; self.limits = limits
    }

    /// Decodes a required typed field while sanitizing Foundation decoding errors.
    /// - Parameters:
    ///   - name: Exact API field key; missing keys fail even for `Nullable` types.
    ///   - type: Expected Swift scalar/container type.
    /// - Returns: The validated typed value.
    /// - Throws: Safe invalid-response errors for missing fields, type/range mismatch or nonintegral number lexemes.
    func required<Value: Decodable>(_ name: String, as type: Value.Type) throws -> Value {
        guard let value = fields[name] else { throw DiscordError.transport(.invalidResponse) }
        if case .number(let number) = value {
            guard !number.rawValue.contains("."), !number.rawValue.contains("e"), !number.rawValue.contains("E")
            else { throw DiscordError.transport(.invalidResponse) }
        }
        do { return try JSONDecoder().decode(type, from: value.serialized(limits: limits)) }
        catch { throw DiscordError.transport(.invalidResponse) }
    }

    /// Preserves absent, explicit-null and present optional field states.
    /// - Parameters:
    ///   - name: Exact API field key.
    ///   - type: Non-null payload type.
    ///   - nullable: Whether upstream permits explicit null; defaults to `false`.
    /// - Returns: `.absent`, permitted `.null`, or a validated `.value`.
    /// - Throws: Safe invalid-response errors for forbidden null or a malformed present value.
    func field<Value: Decodable>(_ name: String, as type: Value.Type, nullable: Bool = false) throws -> Field<Value> {
        guard let value = fields[name] else { return .absent }
        if value == .null {
            guard nullable else { throw DiscordError.transport(.invalidResponse) }
            return .null
        }
        return .value(try required(name, as: type))
    }
}
