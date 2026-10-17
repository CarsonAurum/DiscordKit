import DiscordCore
import DiscordModels

/// Explicit snapshot command registration reconciliation, independent of Gateway, routers or background sync.
public enum ApplicationCommandOperations {
    /// Omits a replacement only when the caller's complete supplied snapshots prove exact configuration equivalence.
    /// - Parameters:
    ///   - applicationID: Expected owner, checked for every snapshot before comparison or descriptor creation.
    ///   - guildID: Nil for global catalog; otherwise every snapshot must belong to the exact target guild.
    ///   - current: Complete caller-owned catalog, at most 131 unique IDs and name/type identities. Obtain full localization
    ///     dictionaries explicitly when needed; localized singular fields alone cannot prove equivalence.
    ///   - request: Complete bounded destructive replacement, including empty to remove all. Omitted fields follow known
    ///     defaults where documented; app-configured defaults or incomplete localizations conservatively require a write.
    /// - Returns: Nil for proven no-op or one ordinary unsafe bulk PUT. No hidden reads, tasks, I/O or prefetch occur.
    /// - Throws: Invalid-value for mismatched scope/owner, duplicate current identities or excess snapshots;
    ///   body/descriptor errors for changed requests. Stale snapshots do not establish server state or permissions.
    public static func bulkOverwriteIfChanged(applicationID: ApplicationID, guildID: GuildID? = nil,
        current: [ApplicationCommand], request: BulkApplicationCommands) throws -> Endpoint<[ApplicationCommand]>? {
        guard current.count <= 131, Set(current.map(\.id)).count == current.count,
              Set(current.map { item in
                  let kind: Int
                  if case .value(let type) = item.type { kind = type.rawValue } else { kind = 1 }
                  return "\(kind):\(item.name)"
              }).count == current.count,
              current.allSatisfy({ item in
                  item.applicationID == applicationID && (guildID.map { item.guildID == .value($0) } ?? (item.guildID == .absent))
              }) else { throw DiscordError.validation(.invalidValue) }
        let endpoint = try ApplicationCommandEndpoints.bulkOverwrite(applicationID: applicationID, guildID: guildID, request: request)
        guard current.count == request.commands.count else { return endpoint }
        var matched: Set<ApplicationCommandID> = []
        for desired in request.commands {
            let candidates = current.filter { item in
                if let id = desired.id { return item.id == id }
                return item.name == desired.command.name && item.type == .value(RawValue(desired.command.type))
            }
            guard candidates.count == 1, let snapshot = candidates.first, matched.insert(snapshot.id).inserted,
                  commandConfigurationMatches(snapshot.rawFields, desired: desired.command.jsonValue(), global: guildID == nil)
            else { return endpoint }
        }
        return nil
    }
}

/// Conservatively compares a complete registration with a supplied snapshot under documented create defaults.
/// - Parameters:
///   - current: Exact current command fields, including complete dictionaries when available.
///   - desired: Validated complete create object; omitted defaults cannot be assumed to match configured install defaults.
///   - global: True requires explicit matching install/context settings; guild scope has no application-configured context defaults.
/// - Returns: True only if every writable field is equivalent and no omitted server field would be reset differently.
///   Nested options compare exact trees after removing read-only localized singular fields; unknown nested fields force a write.
private func commandConfigurationMatches(_ current: [String: JSONValue], desired: JSONValue, global: Bool) -> Bool {
    guard case .object(let requested) = desired else { return false }
    guard current["name_localizations"] != nil, current["description_localizations"] != nil else { return false }
    if global {
        guard requested["integration_types"] != nil, requested["contexts"] != nil,
              current["integration_types"] != nil, current["contexts"] != nil else { return false }
    }
    let defaults: [String: JSONValue] = ["description": .string(""), "options": .array([]),
        "name_localizations": .null, "description_localizations": .null, "default_member_permissions": .null,
        "default_permission": .bool(true), "dm_permission": .bool(true), "nsfw": .bool(false)]
    let keys: Set<String> = Set(defaults.keys).union(["name", "type", "integration_types", "contexts", "handler"])
    for key in keys {
        let expected = requested[key] ?? defaults[key]
        let observed = current[key] ?? defaults[key]
        if key == "name_localizations" || key == "description_localizations" {
            let singular = key == "name_localizations" ? "name_localized" : "description_localized"
            if current[key] == nil && current[singular] != nil { return false }
        }
        guard commandComparableValue(observed) == commandComparableValue(expected) else { return false }
    }
    return true
}

/// Removes response-only localized singular fields recursively while retaining every unknown configurable field.
/// - Parameter value: Optional bounded command subtree; nil means an unknown or omitted default and remains nil.
/// - Returns: Exact comparison tree with name_localized/description_localized removed; no normalization of numbers/text occurs.
private func commandComparableValue(_ value: JSONValue?) -> JSONValue? {
    guard let value else { return nil }
    switch value {
    case .array(let values): return .array(values.compactMap { commandComparableValue($0) })
    case .object(let values):
        return .object(values.filter { $0.key != "name_localized" && $0.key != "description_localized" }.compactMapValues { commandComparableValue($0) })
    default: return value
    }
}
