import DiscordLogging
import DiscordCore
import DiscordHTTP
import DiscordModels
import Foundation

/// Progress from an explicit reconciliation. Unmanaged registrations are never deleted or bulk-overwritten.
public struct CommandSyncReport: Sendable {
    /// Number of desired definitions already equivalent under known API v10 defaults.
    public let unchangedCount: Int
    /// Acknowledged create/edit results in desired-definition order; permission/eligibility checks remain server-owned.
    public let written: [ApplicationCommand]

    /// Records finite acknowledged progress without implying that later failed submissions did not take effect.
    /// - Parameters:
    ///   - unchangedCount: Count of equivalent managed commands encountered so far.
    ///   - written: Successfully acknowledged managed upserts; no unmanaged registrations are included.
    fileprivate init(unchangedCount: Int, written: [ApplicationCommand]) {
        self.unchangedCount = unchangedCount; self.written = written
    }
}

/// A stopped reconciliation with explicit acknowledged progress and the original failure.
/// An indeterminate underlying mutation must be reconciled with a new fetch, never blindly replayed.
public struct CommandSyncFailure: Error, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// Finite progress acknowledged before the failed definition; no rollback is attempted.
    public let completed: CommandSyncReport
    /// Zero-based desired-definition position that stopped processing; subsequent definitions were not attempted.
    public let failedDefinitionIndex: Int
    /// Exact underlying REST/cancellation failure for deliberate inspection; ordinary diagnostics redact it.
    public let underlyingError: any Error

    /// Retains precise partial progress without formatting credentials, names or server data.
    /// - Parameters:
    ///   - completed: Acknowledged no-op/upsert progress; failed writes may independently have taken effect.
    ///   - failedDefinitionIndex: Position that failed; may have been cancelled before transmission.
    ///   - underlyingError: Original failure, including REST indeterminate-outcome evidence.
    fileprivate init(completed: CommandSyncReport, failedDefinitionIndex: Int, underlyingError: any Error) {
        self.completed = completed; self.failedDefinitionIndex = failedDefinitionIndex; self.underlyingError = underlyingError
    }

    /// Safe diagnostic containing only a closed marker and finite progress counts.
    public var description: String { "CommandSyncFailure(index: \(failedDefinitionIndex), acknowledgedWrites: \(completed.written.count))" }
    /// Uses the same diagnostic without exposing the retained underlying error or response fields.
    public var debugDescription: String { description }
    /// Prevents reflective traversal into original transport errors, command names and response payloads.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}

/// Explicit finite command registration, with one fresh list and only changed per-command creates/edits.
/// Construction and router adoption do not reconcile automatically. Name/type identifies managed entries;
/// omitted definitions, renames and other applications' registrations are never interpreted as deletions.
/// Share one reconciler per application/catalog to avoid local overlapping writes; external writers retain
/// the ordinary snapshot race, and multiple processes require caller-owned distributed coordination.
public actor CommandReconciler {
    private let applicationID: ApplicationID
    private let guildID: GuildID?
    private let definitions: [CommandDefinition]
    private var synchronizing = false

    /// Validates the entire desired catalog and scope before any fetch or mutation can occur.
    /// - Parameters:
    ///   - applicationID: Exact owner of every registration and the injected REST credential.
    ///   - guildID: Nil for the independent global catalog, otherwise one guild catalog; default nil.
    ///   - definitions: Managed definitions only, at most 131 global or 130 guild and within documented type caps.
    ///     Duplicate name/type identities are rejected. Empty definitions perform a read and zero writes.
    ///   - maximumDefinitionBytes: Positive aggregate encoded definition budget, default 1 MiB;
    ///     includes all locale dictionaries/options rather than only command names.
    /// - Throws: Invalid-value for bounds, duplicates, kind caps or incompatible global/guild fields;
    ///   limitExceeded for aggregate bytes; ordinary endpoint body/serialization validation errors.
    ///   Every definition is validated before ownership is adopted, including entries after an invalid entry.
    public init(applicationID: ApplicationID, guildID: GuildID? = nil,
        definitions: [CommandDefinition], maximumDefinitionBytes: Int = 1_048_576) throws {
        guard maximumDefinitionBytes > 0 else { throw DiscordError.validation(.invalidValue) }
        _ = try BulkApplicationCommands(commands: definitions.map { ApplicationCommandRegistration(command: $0.request) })
        var total = 0
        for definition in definitions {
            let endpoint = try ApplicationCommandEndpoints.create(applicationID: applicationID,
                guildID: guildID, request: definition.request)
            let bytes = endpoint.body?.bytes.count ?? 0
            guard bytes <= maximumDefinitionBytes - total else { throw DiscordError.validation(.limitExceeded) }
            total += bytes
        }
        self.applicationID = applicationID; self.guildID = guildID; self.definitions = definitions
    }

    /// Fetches full localizations, compares canonical known configurations, and applies changed managed definitions sequentially.
    /// Known omitted scalar/collection defaults and response-only localized fields do not create writes.
    /// Omitted integration_types/contexts/handler and deprecated DM/default-permission settings remain application-owned;
    /// provide them explicitly to manage those settings. Existing commands use PATCH by stable ID, preserving omitted settings.
    /// Numeric option values preserve exact lexemes; no lossy floating-point normalization occurs.
    /// - Parameters:
    ///   - client: Injected ordinary REST client with shared credential/rate authority; never an initial-ack lane.
    ///     Bot or application Bearer credentials need ordinary command-registration permissions and daily create budget.
    ///   - deadline: Optional overall inclusive deadline in the client's clock domain, reused by every exchange.
    /// - Returns: No-op count and acknowledged changed registrations. Identical complete definitions send zero writes;
    ///   one uncached GET still occurs. Unmanaged commands are left untouched, including when definitions is empty.
    /// - Throws: Cancellation, fresh-read/schema/scope failures, limitExceeded for overlapping calls or server catalogs
    ///   beyond documented caps, or CommandSyncFailure with partial progress after a desired definition fails.
    ///   REST rejected-429 retries remain bounded by the client; ambiguous writes are not replayed here.
    ///   No background tasks, implicit startup writes, deletion, bulk replacement or rollback occurs.
    public func synchronize<C: Clock>(using client: RESTClient<C>, deadline: C.Instant? = nil) async throws -> CommandSyncReport where C.Duration == Duration {
        try Task.checkCancellation()
        guard !synchronizing else { throw DiscordError.validation(.limitExceeded) }
        synchronizing = true
        DiscordLog.makeLogger("commands").debug("Explicit command synchronization started", metadata: ["dk.event": "commands.sync.started", "dk.definitions": .stringConvertible(definitions.count)])
        defer { synchronizing = false }
        let endpoint = try ApplicationCommandEndpoints.list(applicationID: applicationID,
            guildID: guildID, withLocalizations: true, readPolicy: nil)
        let current = try await client.execute(endpoint, deadline: deadline)
        guard current.count <= (guildID == nil ? 131 : 130) else { throw DiscordError.validation(.limitExceeded) }
        var byIdentity: [String: ApplicationCommand] = [:], ids: Set<ApplicationCommandID> = []
        for command in current {
            guard command.applicationID == applicationID,
                  guildID.map({ command.guildID == .value($0) }) ?? (command.guildID == .absent),
                  ids.insert(command.id).inserted else { throw DiscordError.transport(.invalidResponse) }
            let type: Int
            if case .value(let kind) = command.type { type = kind.rawValue } else { type = 1 }
            let identity = "\(type):\(command.name)"
            guard byIdentity.updateValue(command, forKey: identity) == nil else { throw DiscordError.transport(.invalidResponse) }
        }
        var unchanged = 0, written: [ApplicationCommand] = []
        for (index, definition) in definitions.enumerated() {
            do {
                try Task.checkCancellation()
                let identity = "\(definition.request.type.rawValue):\(definition.request.name)"
                if let existing = byIdentity[identity], commandMatches(existing, desired: definition.request) {
                    unchanged += 1
                } else {
                    let change: Endpoint<ApplicationCommand>
                    if let existing = byIdentity[identity] {
                        change = try ApplicationCommandEndpoints.modify(applicationID: applicationID,
                            commandID: existing.id, guildID: guildID, request: definition.request.replacementChanges())
                    } else {
                        change = try ApplicationCommandEndpoints.create(applicationID: applicationID,
                            guildID: guildID, request: definition.request)
                    }
                    written.append(try await client.execute(change, deadline: deadline))
                }
            } catch {
                DiscordLog.makeLogger("commands").debug("Command synchronization stopped with partial progress", metadata: ["dk.event": "commands.sync.partial", "dk.written": .stringConvertible(written.count), "dk.unchanged": .stringConvertible(unchanged)])
                throw CommandSyncFailure(completed: CommandSyncReport(unchangedCount: unchanged, written: written),
                    failedDefinitionIndex: index, underlyingError: error)
            }
        }
        DiscordLog.makeLogger("commands").debug("Command synchronization completed", metadata: ["dk.event": "commands.sync.completed", "dk.written": .stringConvertible(written.count), "dk.unchanged": .stringConvertible(unchanged)])
        return CommandSyncReport(unchangedCount: unchanged, written: written)
    }
}

/// Proves equality for known writable configuration after removing server metadata and normalizing known defaults.
/// - Parameters:
///   - current: Snapshot fetched with full localization dictionaries; singular-only translations cannot prove equality.
///   - desired: Complete validated typed registration, preserving explicit null and optional configuration choices.
/// - Returns: True only for equivalent known configuration; unknown top-level metadata is ignored.
///   Context/install/handler fields omitted from desired are intentionally unmanaged rather than guessed app defaults.
private func commandMatches(_ current: ApplicationCommand, desired: ApplicationCommandCreate) -> Bool {
    guard case .object(let requested) = desired.jsonValue(), !incompleteCommandLocalizations(.object(current.rawFields)) else { return false }
    let keys: Set<String> = ["type", "name", "description", "name_localizations", "description_localizations", "options",
        "default_member_permissions", "dm_permission", "default_permission", "nsfw", "integration_types", "contexts", "handler"]
    var observed = current.rawFields.filter { keys.contains($0.key) }
    for key in ["integration_types", "contexts", "handler", "dm_permission", "default_permission"] where requested[key] == nil {
        observed.removeValue(forKey: key)
    }
    return canonicalCommandFields(observed, kind: 0) == canonicalCommandFields(requested, kind: 0)
}

/// Detects a localized singular projection without its full dictionary at any known command-tree level.
/// - Parameter value: Bounded command/option/choice tree already parsed under the REST response byte/depth limits.
/// - Returns: True when full localization comparison cannot be proved; all other missing dictionaries mean no translations.
private func incompleteCommandLocalizations(_ value: JSONValue) -> Bool {
    switch value {
    case .object(let object):
        for key in ["name", "description"] where object["\(key)_localized"] != nil && object["\(key)_localizations"] == nil { return true }
        return ["options", "choices"].contains { object[$0].map(incompleteCommandLocalizations) ?? false }
    case .array(let array): return array.contains(where: incompleteCommandLocalizations)
    default: return false
    }
}

/// Canonicalizes one known command, option or choice level while preserving array order and exact number lexemes.
/// - Parameters:
///   - fields: Known writable fields from the desired object or bounded response.
///   - kind: Zero for a command, one for an option or two for a choice.
/// - Returns: Immutable comparison tree with known defaults made explicit, localization dictionaries normalized,
///   install/context set order ignored, and response-only/unknown nested metadata excluded.
private func canonicalCommandFields(_ fields: [String: JSONValue], kind: Int) -> JSONValue {
    let defaults: [String: JSONValue]
    let keys: Set<String>
    switch kind {
    case 0:
        defaults = ["type": .number(try! JSONNumber(rawValue: "1")), "description": .string(""),
            "options": .array([]), "name_localizations": .null, "description_localizations": .null,
            "default_member_permissions": .null, "dm_permission": .bool(true), "default_permission": .bool(true), "nsfw": .bool(false)]
        keys = Set(defaults.keys).union(["name", "integration_types", "contexts", "handler"])
    case 1:
        defaults = ["required": .bool(false), "autocomplete": .bool(false), "choices": .array([]), "options": .array([]),
            "channel_types": .array([]), "file_types": .array([]), "name_localizations": .null, "description_localizations": .null]
        keys = Set(defaults.keys).union(["name", "description", "type", "min_value", "max_value", "min_length", "max_length"])
    default:
        defaults = ["name_localizations": .null]
        keys = ["name", "value", "name_localizations"]
    }
    var result = defaults
    for (key, value) in fields where keys.contains(key) { result[key] = value }
    for key in ["name_localizations", "description_localizations"] {
        if case .object(let dictionary) = result[key], dictionary.isEmpty { result[key] = .null }
    }
    for (key, childKind) in [("options", 1), ("choices", 2)] {
        if case .array(let children) = result[key] {
            result[key] = .array(children.map { value in
                guard case .object(let child) = value else { return value }
                return canonicalCommandFields(child, kind: childKind)
            })
        }
    }
    for key in ["integration_types", "contexts", "channel_types", "file_types"] {
        if case .array(let values) = result[key] {
            result[key] = .array(values.sorted { canonicalCommandScalar($0) < canonicalCommandScalar($1) })
        }
    }
    return .object(result)
}

/// Supplies deterministic ordering keys for known set-valued command arrays without interpreting numeric values.
/// - Parameter value: Validated numeric discriminator or attachment extension string.
/// - Returns: Exact scalar spelling; unsupported shapes use an empty key and remain unequal to typed request arrays.
private func canonicalCommandScalar(_ value: JSONValue) -> String {
    switch value { case .number(let number): number.rawValue; case .string(let text): text; default: "" }
}
