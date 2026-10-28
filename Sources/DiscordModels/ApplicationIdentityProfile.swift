// File: Sources/DiscordModels/ApplicationIdentityProfile.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import Foundation

/// External application account returned by the API v10 identity resource. Provider strings remain open
/// for future providers. The optional user ID is projected from the documented lookup examples; this
/// snapshot grants no ownership, consent, freshness or authority to delete the linked account.
public struct ApplicationIdentity: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Exact provider type, including NONE for profile-only identities and future provider strings.
    public let providerType: String
    /// Provider disambiguation key; omitted when absent or empty upstream, never nullable.
    public let providerID: Field<String>
    /// Exact external account identifier; this is not a Discord snowflake.
    public let providerIssuedUserID: String
    /// Discord user from lookup examples; omitted values remain absent, never guessed.
    public let userID: Field<UserID>
    /// Complete original object, retaining unknown fields and exact numeric spellings; diagnostics redact it.
    public let rawFields: [String: JSONValue]

    /// Parses a complete API v10 object without network access, suspension, or state mutation.
    /// - Parameters:
    ///   - data: UTF-8 JSON object, including any unknown fields to retain.
    ///   - limits: Whole-document byte/depth/node bounds; defaults to 1 MiB/64/100,000.
    /// - Throws: JSON syntax/bounds errors, or sanitized invalid-response errors for missing,
    ///   forbidden-null, incorrectly typed or malformed modeled fields. Correct the source before retrying.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects an immutable subtree after the complete containing document passed its resource bounds.
    /// - Parameters:
    ///   - value: Original object subtree, including forward-compatible unmodeled keys.
    ///   - limits: The same limits used to parse the containing document.
    /// - Throws: Sanitized invalid-response errors for invalid modeled fields; no I/O or cleanup is needed.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        providerType = try object.required("provider_type", String.self)
        providerID = try object.field("provider_id", String.self)
        providerIssuedUserID = try object.required("provider_issued_user_id", String.self)
        userID = try object.field("user_id", UserID.self)
        rawFields = object.resource.fields
    }
}

/// Wrapped identity lookup result. An empty identities array reports no matches; it is not an
/// error and does not cause another request. Ordering and one-to-one matching are not inferred.
public struct ApplicationIdentityList: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Exact returned identities in server order; zero matches are represented by an empty array.
    public let identities: [ApplicationIdentity]
    /// Complete original object, retaining unknown fields and exact numeric spellings; diagnostics redact it.
    public let rawFields: [String: JSONValue]

    /// Parses a complete API v10 object without network access, suspension, or state mutation.
    /// - Parameters:
    ///   - data: UTF-8 JSON object, including any unknown fields to retain.
    ///   - limits: Whole-document byte/depth/node bounds; defaults to 1 MiB/64/100,000.
    /// - Throws: JSON syntax/bounds errors, or sanitized invalid-response errors for missing,
    ///   forbidden-null, incorrectly typed or malformed modeled fields. Correct the source before retrying.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects an immutable subtree after the complete containing document passed its resource bounds.
    /// - Parameters:
    ///   - value: Original object subtree, including forward-compatible unmodeled keys.
    ///   - limits: The same limits used to parse the containing document.
    /// - Throws: Sanitized invalid-response errors for invalid modeled fields; no I/O or cleanup is needed.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        guard case .value(let identities) = try object.array("identities", transform: {
            try ApplicationIdentity(value: $0, limits: limits)
        }) else { throw DiscordError.transport(.invalidResponse) }
        self.identities = identities
        rawFields = object.resource.fields
    }
}

/// Media reference for an application identity stat. URLs remain response data; parsing never fetches
/// assets, resolves DNS or establishes public reachability.
public struct ApplicationIdentityProfileMedia: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Exact asset URL string; server reachability is not inferred from a response snapshot.
    public let url: String
    /// Complete original object, retaining unknown fields and exact numeric spellings; diagnostics redact it.
    public let rawFields: [String: JSONValue]

    /// Parses a complete API v10 object without network access, suspension, or state mutation.
    /// - Parameters:
    ///   - data: UTF-8 JSON object, including any unknown fields to retain.
    ///   - limits: Whole-document byte/depth/node bounds; defaults to 1 MiB/64/100,000.
    /// - Throws: JSON syntax/bounds errors, or sanitized invalid-response errors for missing,
    ///   forbidden-null, incorrectly typed or malformed modeled fields. Correct the source before retrying.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects an immutable subtree after the complete containing document passed its resource bounds.
    /// - Parameters:
    ///   - value: Original object subtree, including forward-compatible unmodeled keys.
    ///   - limits: The same limits used to parse the containing document.
    /// - Throws: Sanitized invalid-response errors for invalid modeled fields; no I/O or cleanup is needed.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        url = try object.required("url", String.self)
        rawFields = object.resource.fields
    }
}

/// Optional preconfigured API v10 game stats. Numeric lexemes are never routed through floating-point
/// conversion. Response projections preserve future fields but do not apply request-only text or byte caps.
public struct ApplicationIdentityProfilePrimary: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Optional season text; omission is preserved and explicit null is invalid.
    public let season: Field<String>
    /// Optional rank_name text; omission is preserved and explicit null is invalid.
    public let rankName: Field<String>
    /// Optional highest_rank text; omission is preserved and explicit null is invalid.
    public let highestRank: Field<String>
    /// Optional featured_played_character text; omission is preserved and explicit null is invalid.
    public let featuredPlayedCharacter: Field<String>
    /// Optional rank_image media reference; omission is preserved and explicit null is invalid.
    public let rankImage: Field<ApplicationIdentityProfileMedia>
    /// Optional highest_rank_image media reference; omission is preserved and explicit null is invalid.
    public let highestRankImage: Field<ApplicationIdentityProfileMedia>
    /// Optional featured_played_character_image media reference; omission is preserved and explicit null is invalid.
    public let featuredPlayedCharacterImage: Field<ApplicationIdentityProfileMedia>
    /// Optional decimal hours; original numeric spelling and precision remain intact.
    public let playtimeHours: Field<JSONNumber>
    /// Optional integral total_wins count, retaining arbitrary precision and exact spelling.
    public let totalWins: Field<JSONNumber>
    /// Optional integral current_period_wins count, retaining arbitrary precision and exact spelling.
    public let currentPeriodWins: Field<JSONNumber>
    /// Optional integral total_games count, retaining arbitrary precision and exact spelling.
    public let totalGames: Field<JSONNumber>
    /// Optional integral current_period_games count, retaining arbitrary precision and exact spelling.
    public let currentPeriodGames: Field<JSONNumber>
    /// Optional integral total_kills count, retaining arbitrary precision and exact spelling.
    public let totalKills: Field<JSONNumber>
    /// Optional integral current_period_kills count, retaining arbitrary precision and exact spelling.
    public let currentPeriodKills: Field<JSONNumber>
    /// Optional integral total_assists count, retaining arbitrary precision and exact spelling.
    public let totalAssists: Field<JSONNumber>
    /// Optional integral current_period_assists count, retaining arbitrary precision and exact spelling.
    public let currentPeriodAssists: Field<JSONNumber>
    /// Optional integral total_deaths count, retaining arbitrary precision and exact spelling.
    public let totalDeaths: Field<JSONNumber>
    /// Optional integral current_period_deaths count, retaining arbitrary precision and exact spelling.
    public let currentPeriodDeaths: Field<JSONNumber>
    /// Complete original object, retaining unknown fields and exact numeric spellings; diagnostics redact it.
    public let rawFields: [String: JSONValue]

    /// Parses a complete API v10 object without network access, suspension, or state mutation.
    /// - Parameters:
    ///   - data: UTF-8 JSON object, including any unknown fields to retain.
    ///   - limits: Whole-document byte/depth/node bounds; defaults to 1 MiB/64/100,000.
    /// - Throws: JSON syntax/bounds errors, or sanitized invalid-response errors for missing,
    ///   forbidden-null, incorrectly typed or malformed modeled fields. Correct the source before retrying.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects an immutable subtree after the complete containing document passed its resource bounds.
    /// - Parameters:
    ///   - value: Original object subtree, including forward-compatible unmodeled keys.
    ///   - limits: The same limits used to parse the containing document.
    /// - Throws: Sanitized invalid-response errors for invalid modeled fields; no I/O or cleanup is needed.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        season = try object.field("season", String.self)
        rankName = try object.field("rank_name", String.self)
        highestRank = try object.field("highest_rank", String.self)
        featuredPlayedCharacter = try object.field("featured_played_character", String.self)
        rankImage = try object.nested("rank_image") { try ApplicationIdentityProfileMedia(value: $0, limits: limits) }
        highestRankImage = try object.nested("highest_rank_image") { try ApplicationIdentityProfileMedia(value: $0, limits: limits) }
        featuredPlayedCharacterImage = try object.nested("featured_played_character_image") { try ApplicationIdentityProfileMedia(value: $0, limits: limits) }
        playtimeHours = try object.nested("playtime_hours") { try identityProfileNumber($0) }
        totalWins = try object.nested("total_wins") { try identityProfileNumber($0, integral: true) }
        currentPeriodWins = try object.nested("current_period_wins") { try identityProfileNumber($0, integral: true) }
        totalGames = try object.nested("total_games") { try identityProfileNumber($0, integral: true) }
        currentPeriodGames = try object.nested("current_period_games") { try identityProfileNumber($0, integral: true) }
        totalKills = try object.nested("total_kills") { try identityProfileNumber($0, integral: true) }
        currentPeriodKills = try object.nested("current_period_kills") { try identityProfileNumber($0, integral: true) }
        totalAssists = try object.nested("total_assists") { try identityProfileNumber($0, integral: true) }
        currentPeriodAssists = try object.nested("current_period_assists") { try identityProfileNumber($0, integral: true) }
        totalDeaths = try object.nested("total_deaths") { try identityProfileNumber($0, integral: true) }
        currentPeriodDeaths = try object.nested("current_period_deaths") { try identityProfileNumber($0, integral: true) }
        rawFields = object.resource.fields
    }
}

/// Known API v10 dynamic stat discriminators; response wrappers preserve unknown integral values.
public enum ApplicationIdentityDynamicFieldType: Int, Sendable {
    /// Text value; widget presentation labels are configured separately.
    case string = 1
    /// Exact JSON numeric value, including fractional values.
    case number = 2
    /// Media reference containing an asset URL.
    case media = 3
}

/// Typed dynamic stat payload, preserving a future variant's original value without guessing its schema.
public enum ApplicationIdentityDynamicFieldValue: Sendable, Equatable {
    /// Text as returned or explicitly supplied.
    case string(String)
    /// Arbitrary-precision numeric spelling.
    case number(JSONNumber)
    /// Typed asset reference; construction never fetches the asset.
    case media(ApplicationIdentityProfileMedia)
    /// Original value associated with a future dynamic discriminator; outgoing requests reject this case.
    case unknown(JSONValue)
}

/// One named custom stat. Known discriminators validate their matching value type; future integral
/// discriminators retain their original value and unknown fields. Names are data keys, not player labels.
public struct ApplicationIdentityProfileDynamicField: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Known or future integral dynamic discriminator.
    public let type: RawValue<ApplicationIdentityDynamicFieldType>
    /// Exact data key used by the widget editor.
    public let name: String
    /// Type-checked known value or untouched future value.
    public let value: ApplicationIdentityDynamicFieldValue
    /// Complete original object, retaining unknown fields and exact numeric spellings; diagnostics redact it.
    public let rawFields: [String: JSONValue]

    /// Parses a complete API v10 object without network access, suspension, or state mutation.
    /// - Parameters:
    ///   - data: UTF-8 JSON object, including any unknown fields to retain.
    ///   - limits: Whole-document byte/depth/node bounds; defaults to 1 MiB/64/100,000.
    /// - Throws: JSON syntax/bounds errors, or sanitized invalid-response errors for missing,
    ///   forbidden-null, incorrectly typed or malformed modeled fields. Correct the source before retrying.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects an immutable subtree after the complete containing document passed its resource bounds.
    /// - Parameters:
    ///   - value: Original object subtree, including forward-compatible unmodeled keys.
    ///   - limits: The same limits used to parse the containing document.
    /// - Throws: Sanitized invalid-response errors for invalid modeled fields; no I/O or cleanup is needed.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        type = try object.required("type", RawValue<ApplicationIdentityDynamicFieldType>.self)
        name = try object.required("name", String.self)
        guard let raw = object.resource.fields["value"] else { throw DiscordError.transport(.invalidResponse) }
        switch type.knownValue {
        case .string: self.value = .string(try object.required("value", String.self))
        case .number: self.value = .number(try identityProfileNumber(raw))
        case .media: self.value = .media(try ApplicationIdentityProfileMedia(value: raw, limits: limits))
        case nil: self.value = .unknown(raw)
        }
        rawFields = object.resource.fields
    }
}

/// Complete stored stats document. On PATCH this whole document is replaced when supplied; an
/// omitted member in a replacement is removed rather than merged from any prior snapshot.
public struct ApplicationIdentityProfileData: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Optional preconfigured stats object; absence differs from an empty object.
    public let primary: Field<ApplicationIdentityProfilePrimary>
    /// Optional ordered dynamic fields; absence differs from an empty array.
    public let dynamic: Field<[ApplicationIdentityProfileDynamicField]>
    /// Complete original object, retaining unknown fields and exact numeric spellings; diagnostics redact it.
    public let rawFields: [String: JSONValue]

    /// Parses a complete API v10 object without network access, suspension, or state mutation.
    /// - Parameters:
    ///   - data: UTF-8 JSON object, including any unknown fields to retain.
    ///   - limits: Whole-document byte/depth/node bounds; defaults to 1 MiB/64/100,000.
    /// - Throws: JSON syntax/bounds errors, or sanitized invalid-response errors for missing,
    ///   forbidden-null, incorrectly typed or malformed modeled fields. Correct the source before retrying.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects an immutable subtree after the complete containing document passed its resource bounds.
    /// - Parameters:
    ///   - value: Original object subtree, including forward-compatible unmodeled keys.
    ///   - limits: The same limits used to parse the containing document.
    /// - Throws: Sanitized invalid-response errors for invalid modeled fields; no I/O or cleanup is needed.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        primary = try object.nested("primary") { try ApplicationIdentityProfilePrimary(value: $0, limits: limits) }
        dynamic = try object.array("dynamic") { try ApplicationIdentityProfileDynamicField(value: $0, limits: limits) }
        rawFields = object.resource.fields
    }
}

/// API v10 application identity profile, verified 2026-10-16 against the official Application Identity
/// Profile resource. Required nullable keys stay distinct from malformed missing keys. Metadata is
/// stored for application use; it does not become a supported outgoing PATCH parameter.
public struct ApplicationIdentityProfile: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// External username or explicit null; the key is required in complete profile responses.
    public let username: Nullable<String>
    /// Application-owned arbitrary object or explicit null; exact nested values remain available.
    public let metadata: Nullable<[String: JSONValue]>
    /// Complete stats document or explicit null; this snapshot never causes background synchronization.
    public let data: Nullable<ApplicationIdentityProfileData>
    /// Complete original object, retaining unknown fields and exact numeric spellings; diagnostics redact it.
    public let rawFields: [String: JSONValue]

    /// Parses a complete API v10 object without network access, suspension, or state mutation.
    /// - Parameters:
    ///   - data: UTF-8 JSON object, including any unknown fields to retain.
    ///   - limits: Whole-document byte/depth/node bounds; defaults to 1 MiB/64/100,000.
    /// - Throws: JSON syntax/bounds errors, or sanitized invalid-response errors for missing,
    ///   forbidden-null, incorrectly typed or malformed modeled fields. Correct the source before retrying.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects an immutable subtree after the complete containing document passed its resource bounds.
    /// - Parameters:
    ///   - value: Original object subtree, including forward-compatible unmodeled keys.
    ///   - limits: The same limits used to parse the containing document.
    /// - Throws: Sanitized invalid-response errors for invalid modeled fields; no I/O or cleanup is needed.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        username = try identityProfileRequiredNullable(object.field("username", String.self, nullable: true))
        metadata = try identityProfileRequiredNullable(object.nested("metadata", nullable: true) { value in
            guard case .object(let fields) = value else { throw DiscordError.transport(.invalidResponse) }
            return fields
        })
        data = try identityProfileRequiredNullable(object.nested("data", nullable: true) {
            try ApplicationIdentityProfileData(value: $0, limits: limits)
        })
        rawFields = object.resource.fields
    }
}

/// Requires a JSON number while retaining its exact spelling and arbitrary precision.
/// - Parameters:
///   - value: Already bounded scalar; strings and booleans do not coerce into numbers.
///   - integral: When true, accepts only an integer lexeme without a decimal point or exponent; default false.
/// - Returns: Original numeric lexeme; no arithmetic, rounding or finite machine-range conversion occurs.
/// - Throws: Sanitized invalid-response errors for nonnumbers or noninteger count lexemes.
private func identityProfileNumber(_ value: JSONValue, integral: Bool = false) throws -> JSONNumber {
    guard case .number(let number) = value,
          !integral || !number.rawValue.contains(where: { $0 == "." || $0 == "e" || $0 == "E" })
    else { throw DiscordError.transport(.invalidResponse) }
    return number
}

/// Converts present nullable field state into a required nullable value without collapsing missing keys.
/// - Parameter field: Synchronously projected field; null is allowed but omission violates the complete schema.
/// - Returns: Explicit null or the present typed value; no external state or resource is modified.
/// - Throws: Sanitized invalid-response errors for an absent key.
private func identityProfileRequiredNullable<Value>(_ field: Field<Value>) throws -> Nullable<Value> {
    switch field {
    case .absent: throw DiscordError.transport(.invalidResponse)
    case .null: return .null
    case .value(let value): return .value(value)
    }
}
