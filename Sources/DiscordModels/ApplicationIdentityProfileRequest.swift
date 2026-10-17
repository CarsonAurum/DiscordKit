import DiscordCore
import Foundation

/// Exact external account key for API v10 identity lookup and deletion. The provider namespace remains
/// open; NONE denotes a profile-only identity. This value neither authenticates nor links an account.
public struct ApplicationIdentityKey: UserRequestPayload {
    /// Exact provider type, retained for its path segment without uppercasing or normalization.
    public let providerType: String
    /// External account identifier, retained as one safe path segment.
    public let providerIssuedUserID: String
    /// Optional provider disambiguation key; nil omits the query/body field and empty is preserved.
    public let providerID: String?

    /// Validates a bounded account key without querying existing linkage or inferring deletion eligibility.
    /// - Parameters:
    ///   - providerType: Nonempty safe path segment, at most 1,024 UTF-8 bytes; future values are allowed.
    ///   - providerIssuedUserID: Nonempty safe path segment, at most 4,096 UTF-8 bytes; never parsed as a snowflake.
    ///   - providerID: Optional exact disambiguation string, at most 4,096 UTF-8 bytes without control characters;
    ///     empty remains explicit because lookup and delete parameters are caller-owned, not response normalization.
    /// - Throws: Sanitized invalid-value errors for local byte bounds, separators, dot segments or controls.
    ///   These finite local bounds are not claims about undocumented upstream length limits. No I/O occurs.
    public init(providerType: String, providerIssuedUserID: String, providerID: String? = nil) throws {
        try identityProfilePath(providerType, maximumBytes: 1_024)
        try identityProfilePath(providerIssuedUserID, maximumBytes: 4_096)
        if let providerID {
            guard providerID.utf8.count <= 4_096,
                  !providerID.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
            else { throw DiscordError.validation(.invalidValue) }
        }
        self.providerType = providerType
        self.providerIssuedUserID = providerIssuedUserID
        self.providerID = providerID
    }

    /// Produces only the optional provider disambiguation object accepted by the delete operation.
    /// - Returns: Empty object when providerID is nil, otherwise an exact provider_id string.
    ///   Provider type and external account ID remain path parameters and are never duplicated in the body.
    public func jsonValue() -> JSONValue {
        .object(providerID.map { ["provider_id": .string($0)] } ?? [:])
    }
}

extension ApplicationIdentityProfileMedia {
    /// Constructs an outgoing media reference using a bounded absolute HTTP(S) URL.
    /// - Parameter url: At most 2,048 Unicode scalars; requires a host and forbids user information,
    ///   whitespace and controls. The URL must be publicly reachable by Discord when used in a request.
    /// - Throws: Sanitized invalid-value errors for URL syntax/local bounds. DNS and public reachability
    ///   remain Discord checks; construction is synchronous and never fetches the resource.
    public init(url: String) throws {
        let value = try applicationRequestURL(url)
        try self.init(value: .object(["url": value]), limits: .default)
    }
}

/// Preconfigured fields for a complete replacement stats document. Every parameter defaults to
/// omission; this type cannot represent explicit null because the written PATCH schema does not allow it.
public struct ApplicationIdentityProfilePrimaryUpdate: UserRequestPayload {
    private let fields: [String: JSONValue]

    /// Validates finite exact stats without reading or merging an existing profile.
    /// - Parameters:
    ///   - season: Optional season text, zero through 100 Unicode scalars; null is invalid.
    ///   - rankName: Optional rank_name text, zero through 100 Unicode scalars; null is invalid.
    ///   - highestRank: Optional highest_rank text, zero through 100 Unicode scalars; null is invalid.
    ///   - featuredPlayedCharacter: Optional featured_played_character text, zero through 100 Unicode scalars; null is invalid.
    ///   - rankImage: Optional rank_image HTTP(S) asset, at most 2,048 scalars; null is invalid, reachability is a server check.
    ///   - highestRankImage: Optional highest_rank_image HTTP(S) asset, at most 2,048 scalars; null is invalid, reachability is a server check.
    ///   - featuredPlayedCharacterImage: Optional featured_played_character_image HTTP(S) asset, at most 2,048 scalars; null is invalid, reachability is a server check.
    ///   - playtimeHours: Optional exact JSON decimal hours, preserving arbitrary precision; null is invalid.
    ///   - totalWins: Optional exact integral total_wins; decimal/exponent spellings and null are invalid. No undocumented sign/range restriction is invented.
    ///   - currentPeriodWins: Optional exact integral current_period_wins; decimal/exponent spellings and null are invalid. No undocumented sign/range restriction is invented.
    ///   - totalGames: Optional exact integral total_games; decimal/exponent spellings and null are invalid. No undocumented sign/range restriction is invented.
    ///   - currentPeriodGames: Optional exact integral current_period_games; decimal/exponent spellings and null are invalid. No undocumented sign/range restriction is invented.
    ///   - totalKills: Optional exact integral total_kills; decimal/exponent spellings and null are invalid. No undocumented sign/range restriction is invented.
    ///   - currentPeriodKills: Optional exact integral current_period_kills; decimal/exponent spellings and null are invalid. No undocumented sign/range restriction is invented.
    ///   - totalAssists: Optional exact integral total_assists; decimal/exponent spellings and null are invalid. No undocumented sign/range restriction is invented.
    ///   - currentPeriodAssists: Optional exact integral current_period_assists; decimal/exponent spellings and null are invalid. No undocumented sign/range restriction is invented.
    ///   - totalDeaths: Optional exact integral total_deaths; decimal/exponent spellings and null are invalid. No undocumented sign/range restriction is invented.
    ///   - currentPeriodDeaths: Optional exact integral current_period_deaths; decimal/exponent spellings and null are invalid. No undocumented sign/range restriction is invented.
    /// - Throws: Sanitized invalid-value errors for nulls, excessive text, invalid media URLs or nonintegral counts.
    ///   JSON serialization can report finite document bounds; validation performs no I/O or state mutation.
    public init(season: Field<String> = .absent,
                rankName: Field<String> = .absent,
                highestRank: Field<String> = .absent,
                featuredPlayedCharacter: Field<String> = .absent,
                rankImage: Field<ApplicationIdentityProfileMedia> = .absent,
                highestRankImage: Field<ApplicationIdentityProfileMedia> = .absent,
                featuredPlayedCharacterImage: Field<ApplicationIdentityProfileMedia> = .absent,
                playtimeHours: Field<JSONNumber> = .absent,
                totalWins: Field<JSONNumber> = .absent,
                currentPeriodWins: Field<JSONNumber> = .absent,
                totalGames: Field<JSONNumber> = .absent,
                currentPeriodGames: Field<JSONNumber> = .absent,
                totalKills: Field<JSONNumber> = .absent,
                currentPeriodKills: Field<JSONNumber> = .absent,
                totalAssists: Field<JSONNumber> = .absent,
                currentPeriodAssists: Field<JSONNumber> = .absent,
                totalDeaths: Field<JSONNumber> = .absent,
                currentPeriodDeaths: Field<JSONNumber> = .absent) throws {
        var result: [String: JSONValue] = [:]
        try guildRequestField(season, name: "season", into: &result) { try guildRequestText($0, length: 0...100) }
        try guildRequestField(rankName, name: "rank_name", into: &result) { try guildRequestText($0, length: 0...100) }
        try guildRequestField(highestRank, name: "highest_rank", into: &result) { try guildRequestText($0, length: 0...100) }
        try guildRequestField(featuredPlayedCharacter, name: "featured_played_character", into: &result) { try guildRequestText($0, length: 0...100) }
        try guildRequestField(rankImage, name: "rank_image", into: &result) { .object(["url": try applicationRequestURL($0.url)]) }
        try guildRequestField(highestRankImage, name: "highest_rank_image", into: &result) { .object(["url": try applicationRequestURL($0.url)]) }
        try guildRequestField(featuredPlayedCharacterImage, name: "featured_played_character_image", into: &result) { .object(["url": try applicationRequestURL($0.url)]) }
        try guildRequestField(playtimeHours, name: "playtime_hours", into: &result) { .number($0) }
        try guildRequestField(totalWins, name: "total_wins", into: &result) { try identityProfileInteger($0) }
        try guildRequestField(currentPeriodWins, name: "current_period_wins", into: &result) { try identityProfileInteger($0) }
        try guildRequestField(totalGames, name: "total_games", into: &result) { try identityProfileInteger($0) }
        try guildRequestField(currentPeriodGames, name: "current_period_games", into: &result) { try identityProfileInteger($0) }
        try guildRequestField(totalKills, name: "total_kills", into: &result) { try identityProfileInteger($0) }
        try guildRequestField(currentPeriodKills, name: "current_period_kills", into: &result) { try identityProfileInteger($0) }
        try guildRequestField(totalAssists, name: "total_assists", into: &result) { try identityProfileInteger($0) }
        try guildRequestField(currentPeriodAssists, name: "current_period_assists", into: &result) { try identityProfileInteger($0) }
        try guildRequestField(totalDeaths, name: "total_deaths", into: &result) { try identityProfileInteger($0) }
        try guildRequestField(currentPeriodDeaths, name: "current_period_deaths", into: &result) { try identityProfileInteger($0) }
        fields = result
    }

    /// Produces only explicitly selected primary fields, preserving exact numeric spellings.
    /// - Returns: Validated object; absence does not request a merge when used in a data replacement.
    public func jsonValue() -> JSONValue { .object(fields) }
}

/// One validated known dynamic stat for outgoing API v10 stats documents.
public struct ApplicationIdentityDynamicField: UserRequestPayload {
    private let fields: [String: JSONValue]

    /// Validates a named stat and derives its discriminator from the typed value without coercion.
    /// - Parameters:
    ///   - name: Data key, zero through 100 Unicode scalars; retained exactly and not used as a display label.
    ///   - value: Text up to 100 scalars, exact JSON number, or bounded HTTP(S) media reference.
    ///     Future unknown variants are response-only and rejected; widget-config Custom Strings are a separate surface.
    /// - Throws: Sanitized invalid-value errors for excessive text, unknown variants or invalid media URLs.
    ///   Numbers use RFC 8259 lexemes and never round through Double. No I/O or external mutation occurs.
    public init(name: String, value: ApplicationIdentityDynamicFieldValue) throws {
        let type: Int
        let encoded: JSONValue
        switch value {
        case .string(let text): type = 1; encoded = try guildRequestText(text, length: 0...100)
        case .number(let number): type = 2; encoded = .number(number)
        case .media(let media): type = 3; encoded = .object(["url": try applicationRequestURL(media.url)])
        case .unknown: throw DiscordError.validation(.invalidValue)
        }
        fields = ["type": try guildRequestNumber(type), "name": try guildRequestText(name, length: 0...100), "value": encoded]
    }

    /// Produces the exact known discriminator, data key and typed value.
    /// - Returns: Immutable stat object; no deduplication or mutation of neighboring fields occurs.
    public func jsonValue() -> JSONValue { .object(fields) }
}

/// A complete replacement data object, locally bounded below 10,000 serialized UTF-8 bytes.
/// This conservative decimal-KB limit avoids assuming 10 KiB; the written error says less than 10 KB.
public struct ApplicationIdentityProfileDataUpdate: UserRequestPayload {
    private let fields: [String: JSONValue]

    /// Validates the full desired stats document without fetching or merging previously stored fields.
    /// - Parameters:
    ///   - primary: Optional preconfigured stat object; nil omits it from the replacement, removing prior primary data.
    ///   - dynamic: Optional ordered array of zero through 30 validated fields; nil omits it from the replacement,
    ///     removing prior dynamic data. Duplicate keys remain explicit because the written reference forbids none.
    /// - Throws: Sanitized invalid-value errors for more than 30 fields; JSONValueError for serialized data at
    ///   or above 10,000 bytes, nesting or node limits. The data limit excludes the outer HTTP body and username.
    ///   Empty object is a deliberate full stats clear. This synchronous initializer owns no tasks or resources.
    public init(primary: ApplicationIdentityProfilePrimaryUpdate? = nil,
                dynamic: [ApplicationIdentityDynamicField]? = nil) throws {
        guard (dynamic?.count ?? 0) <= 30 else { throw DiscordError.validation(.invalidValue) }
        var result: [String: JSONValue] = [:]
        if let primary { result["primary"] = primary.jsonValue() }
        if let dynamic { result["dynamic"] = .array(dynamic.map { $0.jsonValue() }) }
        _ = try JSONValue.object(result).serialized(limits: JSONLimits(maximumBytes: 9_999))
        fields = result
    }

    /// Produces the complete replacement without inserting omitted stats or preserving prior unknown fields.
    /// - Returns: Exact bounded data object, including an explicit empty object when selected by the caller.
    public func jsonValue() -> JSONValue { .object(fields) }
}

/// API v10 profile PATCH body. Username and data are independently optional and nonnull. Supplying
/// data replaces every stored stat; metadata is response-only in the written parameter table.
public struct ApplicationIdentityProfileUpdate: UserRequestPayload {
    private let fields: [String: JSONValue]

    /// Validates explicit username and full stats replacements without performing preliminary reads.
    /// - Parameters:
    ///   - username: Optional exact external username, zero through 1,024 Unicode scalars; null is rejected.
    ///   - data: Optional complete desired stats document; null is rejected. Omission preserves all stored stats,
    ///     whereas an empty supplied object removes prior primary/dynamic fields. Default omits both fields.
    /// - Throws: Sanitized invalid-value errors for null or excessive username text. No I/O, credential introspection,
    ///   automatic fetch, background synchronization, hidden merging or mutation replay occurs during construction.
    public init(username: Field<String> = .absent,
                data: Field<ApplicationIdentityProfileDataUpdate> = .absent) throws {
        var result: [String: JSONValue] = [:]
        try guildRequestField(username, name: "username", into: &result) { try guildRequestText($0, length: 0...1_024) }
        try guildRequestField(data, name: "data", into: &result) { $0.jsonValue() }
        fields = result
    }

    /// Produces the validated PATCH fields without adding metadata, provider keys or absent defaults.
    /// - Returns: Exact explicit mutation object; an empty request still executes if passed directly to an endpoint.
    public func jsonValue() -> JSONValue { .object(fields) }

    /// Suppresses an entirely satisfied explicit mutation using only a caller-supplied snapshot.
    /// - Parameter snapshot: Previously obtained profile; caller owns freshness and ordering with other writers.
    /// - Returns: Nil if every supplied field equals the snapshot's exact JSON tree, including an empty request;
    ///   otherwise the original complete request. Numeric lexeme differences count as changes. This never edits,
    ///   fetches or merges the stats document, and cannot prevent concurrent writers or stale-snapshot decisions.
    public func reconciling(against snapshot: ApplicationIdentityProfile) -> ApplicationIdentityProfileUpdate? {
        fields.allSatisfy { snapshot.rawFields[$0.key] == $0.value } ? nil : self
    }
}

/// Enforces a safe finite opaque path segment without percent-decoding or normalizing account identifiers.
/// - Parameters:
///   - value: Original nonempty segment; percent signs and Unicode are allowed for later single encoding.
///   - maximumBytes: Inclusive positive local UTF-8 cap supplied by the caller.
/// - Throws: Sanitized invalid-value errors for byte overflow, dot segments, separators or controls. No I/O occurs.
func identityProfilePath(_ value: String, maximumBytes: Int) throws {
    guard !value.isEmpty, value.utf8.count <= maximumBytes, value != ".", value != "..",
          !value.contains("/"), !value.contains("\\"),
          !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    else { throw DiscordError.validation(.invalidValue) }
}

/// Validates exact outgoing count lexemes without introducing machine integer overflow or rounding.
/// - Parameter number: Grammar-validated JSON number; decimal/exponent spellings are not integer fields.
/// - Returns: The original integer JSON value, including negative zero and arbitrary precision.
/// - Throws: Sanitized invalid-value errors for a decimal point or exponent. No arithmetic or I/O occurs.
private func identityProfileInteger(_ number: JSONNumber) throws -> JSONValue {
    guard !number.rawValue.contains(where: { $0 == "." || $0 == "e" || $0 == "E" })
    else { throw DiscordError.validation(.invalidValue) }
    return .number(number)
}
