import DiscordCore

/// Validated API v10 template creation metadata. Requires MANAGE_GUILD at execution;
/// templates snapshot existing guilds and this body does not create a guild.
public struct GuildTemplateCreate: GuildRequestPayload {
    private let fields: [String: JSONValue]

    /// Validates the complete create body synchronously, preserving exact text and optional description presence.
    /// - Parameters:
    ///   - name: Required name of 1...100 Unicode scalars; no trimming or normalization occurs.
    ///   - description: Omitted by default; null or 0...120 Unicode scalars, including empty, are permitted.
    /// - Throws: Sanitized invalid-value errors for text outside these bounds. No I/O, resource ownership,
    ///   permission lookup or background work occurs; Discord checks current guild permissions and eligibility.
    public init(name: String, description: Field<String> = .absent) throws {
        var result = ["name": try guildRequestText(name, length: 1...100)]
        try guildRequestField(description, name: "description", nullable: true, into: &result) {
            try guildRequestText($0, length: 0...120)
        }
        fields = result
    }

    /// Returns the immutable validated body without synthesizing an omitted description.
    /// - Returns: The exact create object; deliberate access transfers responsibility for safe logging to callers.
    public func jsonValue() -> JSONValue { .object(fields) }
}

/// Validated API v10 template metadata changes. Omission retains current server values;
/// changing metadata does not synchronize the serialized guild snapshot.
public struct GuildTemplateModify: GuildRequestPayload {
    private let fields: [String: JSONValue]

    /// Validates optional metadata changes without fetching current state or checking MANAGE_GUILD.
    /// - Parameters:
    ///   - name: Omitted by default; a present name has 1...100 Unicode scalars. Null is forbidden.
    ///   - description: Omitted by default; null clears it and a value has 0...120 Unicode scalars.
    /// - Throws: Sanitized invalid-value errors for a null name or text outside the published bounds.
    ///   Empty changes are allowed and are sent unless the caller explicitly chooses snapshot reconciliation.
    public init(name: Field<String> = .absent, description: Field<String> = .absent) throws {
        var result: [String: JSONValue] = [:]
        try guildRequestField(name, name: "name", into: &result) { try guildRequestText($0, length: 1...100) }
        try guildRequestField(description, name: "description", nullable: true, into: &result) {
            try guildRequestText($0, length: 0...120)
        }
        fields = result
    }

    /// Returns only explicitly requested fields without collapsing absent, null and empty text.
    /// - Returns: Exact metadata PATCH object, including an empty object for an empty change.
    public func jsonValue() -> JSONValue { .object(fields) }
}
