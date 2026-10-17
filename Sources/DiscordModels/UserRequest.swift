import DiscordCore
import Foundation

/// Validated API v10 user/linked-role bodies. Ordinary diagnostics conceal personal data and tokens.
/// `jsonValue()` deliberately exposes outgoing content; it never performs network I/O, scope checking,
/// cache mutation or rate admission. Discord remains authoritative for current authorization and state.
public protocol UserRequestPayload: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// Produces an already validated immutable request, preserving absent and explicit null fields.
    /// - Returns: The exact JSON tree without adding omitted defaults or exposing it to diagnostics.
    func jsonValue() -> JSONValue
}

extension UserRequestPayload {
    /// Conceals account content and OAuth2 access tokens during ordinary formatting.
    public var description: String { "\(Self.self)(redacted)" }
    /// Returns the same redacted marker during debug formatting.
    public var debugDescription: String { description }
    /// Prevents recursive reflection from expanding retained personal data and token-bearing payloads.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}

/// API v10 PATCH /users/@me. Bot authentication is required by the official preview security policy.
/// The written reference permits all fields to be omitted; the preview's required username is not imposed.
public struct UserModify: UserRequestPayload {
    private let fields: [String: JSONValue]

    /// Validates account edits without sending them, fetching a profile or inferring token permissions.
    /// - Parameters:
    ///   - username: Optional nonnull username, 2...32 Unicode scalars after trimming whitespace.
    ///     Published forbidden substrings @, #, :, triple backticks and discord, and reserved everyone/here,
    ///     are checked case-insensitively. Text is preserved; Discord applies further unpublished rules and sanitization.
    ///   - avatar: Optional nullable canonical base64 image or image data URI; null clears the avatar.
    ///   - banner: Optional nullable image in the same syntax; null clears the banner. Eligibility is checked by Discord.
    /// - Throws: Safe validation errors for null username, published username violations or malformed image syntax.
    ///   Validation is synchronous, performs no I/O and makes no claim about image dimensions or accepted content.
    public init(username: Field<String> = .absent, avatar: Field<String> = .absent,
                banner: Field<String> = .absent) throws {
        var result: [String: JSONValue] = [:]
        try guildRequestField(username, name: "username", into: &result) { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            let lower = trimmed.lowercased()
            guard (2...32).contains(trimmed.unicodeScalars.count), !["everyone", "here"].contains(lower),
                  !["@", "#", ":", "```", "discord"].contains(where: { lower.contains($0) })
            else { throw DiscordError.validation(.invalidValue) }
            return .string(value)
        }
        try guildRequestField(avatar, name: "avatar", nullable: true, into: &result) { try guildRequestImage($0) }
        try guildRequestField(banner, name: "banner", nullable: true, into: &result) { try guildRequestImage($0) }
        fields = result
    }

    /// Produces the exact account PATCH, including explicitly selected image clears.
    /// - Returns: Immutable JSON object; empty means no edits were selected, without a hidden profile fetch.
    public func jsonValue() -> JSONValue { .object(fields) }
}

/// API v10 POST /users/@me/channels single-recipient DM. Construct only for an authorized user interaction;
/// the library never scans guild members or initiates unsolicited bulk DMs.
public struct UserDMCreate: UserRequestPayload {
    /// Exact recipient whose existing/new DM is requested; construction never sends a message.
    public let recipientID: UserID

    /// Selects one exact DM recipient without opening a channel or checking current messaging eligibility.
    /// - Parameter recipientID: Exact unsigned Discord user ID, retained as a decimal string on the wire.
    /// Construction is synchronous; Discord checks eligibility and can return an existing channel on execution.
    public init(recipientID: UserID) { self.recipientID = recipientID }

    /// Produces the required single-recipient body without adding group-DM fields.
    /// - Returns: An object containing only recipient_id as an exact decimal string.
    public func jsonValue() -> JSONValue { .object(["recipient_id": .string(recipientID.description)]) }
}

/// Legacy API v10 Create Group DM, originally intended for the deprecated GameBridge SDK.
/// Each participant must already have granted this application gdm.join. The documented limit of
/// ten active group DMs belongs to server state; it is not a fabricated recipient-array limit.
public struct UserGroupDMCreate: UserRequestPayload {
    private let fields: [String: JSONValue]

    /// Validates an explicit group-DM request without obtaining consent, inspecting token scope or opening a channel.
    /// - Parameters:
    ///   - accessTokens: Ordered distinct gdm.join access tokens. Empty is preserved because upstream publishes
    ///     no minimum; the official preview caps the array at 1,521 tokens and each token at 152,133 Unicode scalars.
    ///   - nicks: Exact user IDs mapped to nullable nicknames. Empty map is allowed; at most 1,521 entries are
    ///     retained. Nonnull nicknames follow the written 1...32 Unicode-scalar nickname rule; null uses the preview overlay.
    /// - Throws: Safe validation errors for duplicate/overlong tokens or invalid nickname/count bounds.
    ///   Secret text is exposed only deliberately by jsonValue(), never descriptions or reflection. No I/O occurs.
    public init(accessTokens: [BearerToken], nicks: [UserID: Nullable<String>] = [:]) throws {
        guard accessTokens.count <= 1_521, nicks.count <= 1_521 else { throw DiscordError.validation(.invalidValue) }
        let tokens = accessTokens.map { $0.withUnsafeValue { $0 } }
        guard Set(tokens).count == tokens.count,
              tokens.allSatisfy({ $0.unicodeScalars.count <= 152_133 })
        else { throw DiscordError.validation(.invalidValue) }
        var names: [String: JSONValue] = [:]
        for (id, nick) in nicks {
            switch nick {
            case .null: names[id.description] = .null
            case .value(let value): names[id.description] = try guildRequestText(value, length: 1...32)
            }
        }
        fields = ["access_tokens": .array(tokens.map { .string($0) }), "nicks": .object(names)]
    }

    /// Exposes the validated legacy body for deliberate HTTP transmission, including participant tokens.
    /// - Returns: Exact access_tokens array and user-ID nickname dictionary; keep this representation out of logs.
    public func jsonValue() -> JSONValue { .object(fields) }
}
