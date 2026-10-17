import DiscordCore
import Foundation

/// One outgoing API v10 linked-role metadata definition. All limits come from the written
/// Application Role Connection Metadata resource; nullable localization clears supplement it
/// from the official preview. Responses have a separate forward-compatible model.
public struct ApplicationRoleConnectionMetadataRecord: UserRequestPayload {
    /// Validated dictionary key, retained for duplicate detection during whole-list replacement.
    public let key: String
    private let fields: [String: JSONValue]

    /// Validates one application-owned verification field without changing guild roles or user metadata.
    /// - Parameters:
    ///   - type: One of the eight documented integer/date/Boolean comparison operations.
    ///   - key: Dictionary key of 1...50 ASCII lowercase letters, digits or underscores; no normalization occurs.
    ///   - name: Display name, 1...100 Unicode scalars.
    ///   - description: Display description, 1...200 Unicode scalars.
    ///   - nameLocalizations: Optional nullable dictionary, up to 1,521 locale entries. Keys must be current
    ///     official locales; each value is null to clear or a 1...100-scalar translation. Default omission preserves state.
    ///   - descriptionLocalizations: Same presence/locale rules, with 1...200-scalar nonnull translations.
    /// - Throws: Safe invalid-value errors for key grammar, lengths, locale keys, counts or invalid translation text.
    ///   Construction is synchronous and performs no I/O, role eligibility calculation or scope inference.
    public init(type: ApplicationRoleConnectionMetadataType, key: String, name: String, description: String,
                nameLocalizations: Field<[String: Nullable<String>]> = .absent,
                descriptionLocalizations: Field<[String: Nullable<String>]> = .absent) throws {
        try validateRoleConnectionKey(key)
        self.key = key
        var result: [String: JSONValue] = ["type": try guildRequestNumber(type.rawValue), "key": .string(key),
            "name": try guildRequestText(name, length: 1...100),
            "description": try guildRequestText(description, length: 1...200)]
        try guildRequestField(nameLocalizations, name: "name_localizations", nullable: true, into: &result) {
            try roleConnectionLocalizations($0, maximumLength: 100)
        }
        try guildRequestField(descriptionLocalizations, name: "description_localizations", nullable: true, into: &result) {
            try roleConnectionLocalizations($0, maximumLength: 200)
        }
        fields = result
    }

    /// Produces the exact metadata record, without adding absent localization dictionaries.
    /// - Returns: Immutable definition object; this never evaluates the comparison against user or guild state.
    public func jsonValue() -> JSONValue { .object(fields) }
}

/// Full replacement of an application's metadata records. Empty arrays explicitly remove all records;
/// top-level null is a distinct clear form accepted by the official preview overlay.
public struct ApplicationRoleConnectionMetadataUpdate: UserRequestPayload {
    private let value: JSONValue

    /// Validates a finite replacement list without fetching, merging or mutating existing definitions.
    /// - Parameter records: Explicit null, or an ordered array of zero through five distinct-key records.
    /// - Throws: Safe invalid-value errors for more than five records or duplicate dictionary keys.
    ///   This synchronous validation owns no network resources and performs no hidden read or write.
    public init(records: Nullable<[ApplicationRoleConnectionMetadataRecord]>) throws {
        switch records {
        case .null: value = .null
        case .value(let records):
            guard records.count <= 5, Set(records.map(\.key)).count == records.count
            else { throw DiscordError.validation(.invalidValue) }
            value = .array(records.map { $0.jsonValue() })
        }
    }

    /// Produces the replacement array or deliberate top-level null without silently merging server state.
    /// - Returns: Exact validated JSON root; empty array and null retain distinct caller intent.
    public func jsonValue() -> JSONValue { value }
}

/// API v10 PUT current user application role connection. Requires that application's OAuth2
/// role_connections.write scope. Platform strings and the metadata dictionary may explicitly clear
/// with null under the official preview overlay; the written reference only lists optional values.
public struct ApplicationRoleConnectionUpdate: UserRequestPayload {
    private let fields: [String: JSONValue]

    /// Validates a user's explicit application connection without calculating linked-role eligibility.
    /// - Parameters:
    ///   - platformName: Optional nullable vanity platform name, at most 50 Unicode scalars; empty is permitted.
    ///   - platformUsername: Optional nullable platform username, at most 100 scalars; empty is permitted.
    ///   - metadata: Optional nullable map of at most five keys matching definition-key grammar, each mapped
    ///     to a string of 1...100 Unicode scalars under the preview schema. Values remain stringified;
    ///     the library does not guess which integer/date/Boolean definition they reference. Empty map is valid.
    /// - Throws: Safe invalid-value errors for length, dictionary count, key grammar or empty/overlong metadata.
    ///   Validation is synchronous with no I/O, profile fetch, token introspection or permission inference.
    public init(platformName: Field<String> = .absent, platformUsername: Field<String> = .absent,
                metadata: Field<[String: String]> = .absent) throws {
        var result: [String: JSONValue] = [:]
        try guildRequestField(platformName, name: "platform_name", nullable: true, into: &result) {
            try guildRequestText($0, length: 0...50)
        }
        try guildRequestField(platformUsername, name: "platform_username", nullable: true, into: &result) {
            try guildRequestText($0, length: 0...100)
        }
        try guildRequestField(metadata, name: "metadata", nullable: true, into: &result) { values in
            guard values.count <= 5 else { throw DiscordError.validation(.invalidValue) }
            var encoded: [String: JSONValue] = [:]
            for (key, value) in values {
                try validateRoleConnectionKey(key)
                encoded[key] = try guildRequestText(value, length: 1...100)
            }
            return .object(encoded)
        }
        fields = result
    }

    /// Produces immutable explicitly selected platform and metadata changes without a preliminary read.
    /// - Returns: Exact presence-aware JSON object; empty object sends one ordinary update when executed.
    public func jsonValue() -> JSONValue { .object(fields) }
}

/// Validates the shared dictionary-key grammar used by definitions and user connection metadata.
/// - Parameter key: Exact unnormalized key, 1...50 lowercase ASCII letters, digits or underscores.
/// - Throws: A sanitized invalid-value error for any length or scalar violation. No I/O or state mutation occurs.
private func validateRoleConnectionKey(_ key: String) throws {
    guard (1...50).contains(key.utf8.count), key.utf8.allSatisfy({
        (97...122).contains($0) || (48...57).contains($0) || $0 == 95
    }) else { throw DiscordError.validation(.invalidValue) }
}

/// Encodes bounded localization dictionaries while retaining explicit per-locale null clears.
/// - Parameters:
///   - values: At most 1,521 locale-to-nullable-string entries; empty maps are valid.
///   - maximumLength: Inclusive nonnull Unicode-scalar translation cap, 100 or 200 at current callers.
/// - Returns: Exact dictionary with original locale spelling and text; no implicit fallback locale is added.
/// - Throws: Safe invalid-value for unsupported locale keys, invalid counts or translation lengths.
///   The current official locale list is pinned to the 2026-10-16 preview; no network fetch occurs here.
private func roleConnectionLocalizations(_ values: [String: Nullable<String>], maximumLength: Int) throws -> JSONValue {
    let locales: Set<String> = ["ar", "bg", "cs", "da", "de", "el", "en-GB", "en-US", "es-419", "es-ES", "fi", "fr", "he", "hi", "hr", "hu", "id", "it", "ja", "ko", "lt", "nl", "no", "pl", "pt-BR", "ro", "ru", "sv-SE", "th", "tr", "uk", "vi", "zh-CN", "zh-TW"]
    guard values.count <= 1_521 else { throw DiscordError.validation(.invalidValue) }
    var result: [String: JSONValue] = [:]
    for (locale, value) in values {
        guard locales.contains(locale) else { throw DiscordError.validation(.invalidValue) }
        switch value {
        case .null: result[locale] = .null
        case .value(let text): result[locale] = try guildRequestText(text, length: 1...maximumLength)
        }
    }
    return .object(result)
}
