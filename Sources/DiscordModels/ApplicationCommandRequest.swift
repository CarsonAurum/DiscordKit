import DiscordCore
import Foundation

/// Validated command choice, retaining exact integer/number spelling and explicit localization presence.
public struct ApplicationCommandChoiceCreate: GuildRequestPayload {
    private let fields: [String: JSONValue]
    /// Validated choice scalar; its compatibility with the owning option is checked by that option.
    public let value: ApplicationCommandChoiceValue

    /// Validates display text and a bounded choice value without registering a command.
    /// - Parameters:
    ///   - name: Display name, 1...100 Unicode scalars, including spaces and mixed case.
    ///   - value: Text of at most 100 scalars or finite numeric value in -2^53...2^53; integer limits are checked by options.
    ///   - nameLocalizations: Omitted by default; null clears or a dictionary supplies 1...100-scalar localized names.
    /// - Throws: Invalid-value for invalid display text, locales or numeric bounds. No I/O or normalization occurs.
    public init(name: String, value: ApplicationCommandChoiceValue,
                nameLocalizations: Field<[String: String]> = .absent) throws {
        self.value = value
        var result = ["name": try guildRequestText(name, length: 1...100)]
        switch value {
        case .string(let text): result["value"] = try guildRequestText(text, length: 0...100)
        case .number(let number): result["value"] = try commandNumber(number, integer: false)
        }
        try commandLocalizations(nameLocalizations, key: "name_localizations", range: 1...100, into: &result)
        fields = result
    }

    /// Returns the bounded exact choice object for deliberate request construction.
    /// - Returns: Name, scalar value and any explicitly selected localizations, without logging or I/O.
    public func jsonValue() -> JSONValue { .object(fields) }
}

/// A validated option tree. Construction bounds every level and rejects unsupported discriminator combinations.
/// Commands support at most group → subcommand → leaf; no unbounded recursion or hidden fetching occurs.
public struct ApplicationCommandOptionCreate: GuildRequestPayload {
    private let fields: [String: JSONValue]
    /// Known option kind used for tree and choice validation.
    public let type: ApplicationCommandOptionType
    /// Exact validated option name, unique within its owning array.
    public let name: String
    /// Whether this leaf is required; omission preserves Discord's false default.
    public let required: Bool?

    /// Validates one complete option with type-specific fields and bounded children.
    /// - Parameters:
    ///   - type: One of the eleven documented option kinds; unknown outgoing kinds are not accepted.
    ///   - name: 1...32 scalars satisfying Discord's lowercase Unicode slash-name grammar.
    ///   - description: Required 1...100 scalar explanation.
    ///   - nameLocalizations: Omitted/null/dictionary of names following the same naming rules.
    ///   - descriptionLocalizations: Omitted/null/dictionary of 1...100 scalar descriptions.
    ///   - required: Optional leaf requirement, default nil; forbidden on subcommands/groups even when false.
    ///   - choices: Optional 0...25 choices for string/integer/number, compatible with the selected kind.
    ///   - options: Optional 0...25 children; groups contain only subcommands and subcommands only leaves.
    ///   - channelTypes: Optional distinct known channel filters, permitted only for channel options.
    ///   - minValue: Optional exact numeric minimum for integer/number options; must not exceed maxValue.
    ///   - maxValue: Optional exact numeric maximum; integers are in ±(2^53-1), numbers in ±2^53.
    ///   - minLength: Optional string minimum in 0...6000, no greater than maxLength.
    ///   - maxLength: Optional string maximum in 1...6000.
    ///   - autocomplete: Optional string/integer/number autocomplete; true is incompatible with any choices array.
    ///   - fileTypes: Optional 0...10 attachment filters: image/video/audio or dot-prefixed extensions,
    ///     at most 16 scalars each per preview. Case-insensitive duplicates are rejected; content validation remains caller-owned.
    /// - Throws: Invalid-value for incompatible fields, duplicate names/filters, ordering/nesting, locale/text/number limits;
    ///   limitExceeded when the combined localized text exceeds 8000 scalars. Entire construction is synchronous and immutable.
    public init(type: ApplicationCommandOptionType, name: String, description: String,
                nameLocalizations: Field<[String: String]> = .absent,
                descriptionLocalizations: Field<[String: String]> = .absent,
                required: Bool? = nil, choices: [ApplicationCommandChoiceCreate]? = nil,
                options: [ApplicationCommandOptionCreate]? = nil, channelTypes: [ChannelType]? = nil,
                minValue: JSONNumber? = nil, maxValue: JSONNumber? = nil,
                minLength: Int? = nil, maxLength: Int? = nil, autocomplete: Bool? = nil,
                fileTypes: [String]? = nil) throws {
        self.type = type; self.name = name; self.required = required
        var result = ["type": try guildRequestNumber(type.rawValue), "name": try commandName(name, slash: true),
                      "description": try guildRequestText(description, length: 1...100)]
        try commandLocalizations(nameLocalizations, key: "name_localizations", range: 1...32, slash: true, into: &result)
        try commandLocalizations(descriptionLocalizations, key: "description_localizations", range: 1...100, into: &result)
        let container = type == .subcommand || type == .subcommandGroup
        guard !container || required == nil else { throw DiscordError.validation(.invalidValue) }
        if let required { result["required"] = .bool(required) }
        if let choices {
            guard [.string, .integer, .number].contains(type), choices.count <= 25, autocomplete != true
            else { throw DiscordError.validation(.invalidValue) }
            for choice in choices {
                switch (type, choice.value) {
                case (.string, .string): break
                case (.integer, .number(let number)): _ = try commandNumber(number, integer: true)
                case (.number, .number): break
                default: throw DiscordError.validation(.invalidValue)
                }
            }
            result["choices"] = .array(choices.map { $0.jsonValue() })
        }
        if let options {
            guard container, options.allSatisfy({ type == .subcommandGroup ? $0.type == .subcommand : $0.type.rawValue >= 3 })
            else { throw DiscordError.validation(.invalidValue) }
            result["options"] = try commandOptions(options)
        }
        if let channelTypes {
            guard type == .channel, Set(channelTypes.map(\.rawValue)).count == channelTypes.count
            else { throw DiscordError.validation(.invalidValue) }
            result["channel_types"] = .array(try channelTypes.map { try guildRequestNumber($0.rawValue) })
        }
        if minValue != nil || maxValue != nil {
            guard type == .integer || type == .number else { throw DiscordError.validation(.invalidValue) }
            if let minValue { result["min_value"] = try commandNumber(minValue, integer: type == .integer) }
            if let maxValue { result["max_value"] = try commandNumber(maxValue, integer: type == .integer) }
            if let minValue, let maxValue, let minimum = Double(minValue.rawValue), let maximum = Double(maxValue.rawValue), minimum > maximum {
                throw DiscordError.validation(.invalidValue)
            }
        }
        if minLength != nil || maxLength != nil {
            guard type == .string else { throw DiscordError.validation(.invalidValue) }
            if let minLength { result["min_length"] = try guildRequestRange(minLength, 0...6000) }
            if let maxLength { result["max_length"] = try guildRequestRange(maxLength, 1...6000) }
            guard (minLength ?? 0) <= (maxLength ?? 6000) else { throw DiscordError.validation(.invalidValue) }
        }
        if let autocomplete {
            guard [.string, .integer, .number].contains(type) else { throw DiscordError.validation(.invalidValue) }
            result["autocomplete"] = .bool(autocomplete)
        }
        if let fileTypes {
            guard type == .attachment, fileTypes.count <= 10,
                  Set(fileTypes.map { $0.lowercased() }).count == fileTypes.count,
                  fileTypes.allSatisfy({ text in
                      (1...16).contains(text.unicodeScalars.count) &&
                      (["image", "video", "audio"].contains(text) ||
                       (text.hasPrefix(".") && text.count > 1 && !text.contains("/") && !text.contains("\\") &&
                        !text.unicodeScalars.contains(where: { $0.properties.isWhitespace || $0.properties.generalCategory == .control })))
                  }) else { throw DiscordError.validation(.invalidValue) }
            result["file_types"] = .array(fileTypes.map { .string($0) })
        }
        guard commandTextSize(.object(result)) <= 8000 else { throw DiscordError.validation(.limitExceeded) }
        fields = result
    }

    /// Returns the immutable type-checked option subtree without allocating tasks or checking server availability.
    /// - Returns: Complete option JSON, preserving absent fields and localization nulls.
    public func jsonValue() -> JSONValue { .object(fields) }
}

/// Complete validated create/upsert body for one command. Guild restrictions are checked by the descriptor.
/// Creating the same name/type overwrites that command; Discord's daily create budget still applies.
public struct ApplicationCommandCreate: GuildRequestPayload {
    private let fields: [String: JSONValue]
    /// Kind used to validate guild compatibility and per-type replacement caps.
    public let type: ApplicationCommandType
    /// Name used to reject duplicate entries in an explicit replacement.
    public let name: String

    /// Validates complete command registration, including localized cumulative text and option trees.
    /// - Parameters:
    ///   - name: 1...32 scalars; slash commands use lowercase Unicode grammar, other kinds allow spaces/mixed case.
    ///   - type: Known command kind, default chatInput; entry points are global-only and require server Activity eligibility.
    ///   - description: Required 1...100 scalars for chat/entry commands; nil or empty for user/message commands.
    ///   - nameLocalizations: Omitted/null/name dictionary following the selected kind's naming rules.
    ///   - descriptionLocalizations: Omitted/null/description dictionary; unsupported on user/message commands except clearing.
    ///   - options: Omitted by default or at most 25 unique, ordered slash options; other kinds cannot contain them.
    ///   - defaultMemberPermissions: Omitted/null/canonical arbitrary-width nonnegative permission digits; null means unrestricted.
    ///   - dmPermission: Deprecated optional nullable global DM visibility; prefer contexts.
    ///   - defaultPermission: Deprecated optional default-enabled setting, retained only on explicit selection.
    ///   - integrationTypes: Optional nonempty distinct global install kinds; eligibility/defaults remain server decisions.
    ///   - contexts: Optional nonempty distinct global interaction contexts; guild writes reject this global-only field.
    ///   - nsfw: Optional age-restriction flag, default omitted.
    ///   - handler: Optional entry-point handler; forbidden on other kinds, Activity eligibility remains server-validated.
    /// - Throws: Invalid-value for incompatible/invalid fields; limitExceeded above 8000 longest-localized text scalars.
    ///   No HTTP calls, permission checks, scope validation or background registration occurs.
    public init(name: String, type: ApplicationCommandType = .chatInput, description: String? = nil,
                nameLocalizations: Field<[String: String]> = .absent,
                descriptionLocalizations: Field<[String: String]> = .absent,
                options: [ApplicationCommandOptionCreate]? = nil,
                defaultMemberPermissions: Field<String> = .absent, dmPermission: Field<Bool> = .absent,
                defaultPermission: Bool? = nil, integrationTypes: [ApplicationIntegrationType]? = nil,
                contexts: [InteractionContextType]? = nil, nsfw: Bool? = nil,
                handler: ApplicationCommandHandler? = nil) throws {
        self.name = name; self.type = type
        var result = try commandFields(type: type, name: .value(name), description: description.map { .value($0) } ?? .absent,
            nameLocalizations: nameLocalizations, descriptionLocalizations: descriptionLocalizations,
            options: options, defaultMemberPermissions: defaultMemberPermissions, dmPermission: dmPermission,
            defaultPermission: defaultPermission, integrationTypes: integrationTypes, contexts: contexts, nsfw: nsfw, handler: handler)
        if type == .chatInput || type == .primaryEntryPoint {
            guard description != nil else { throw DiscordError.validation(.missingValue) }
        }
        result["type"] = try guildRequestNumber(type.rawValue)
        fields = result
    }

    /// Returns the immutable upsert JSON without performing command registration.
    /// - Returns: Complete bounded create body with explicit type and preserved omitted/default/null semantics.
    public func jsonValue() -> JSONValue { .object(fields) }
}

/// Presence-aware validated command edit. The existing type is context only and is never sent in PATCH.
public struct ApplicationCommandModify: GuildRequestPayload {
    private let fields: [String: JSONValue]
    /// Caller-supplied existing kind, used for name/option/handler validation; Discord remains authoritative.
    public let type: ApplicationCommandType

    /// Validates selected changes without fetching the existing command. Every supplied collection replaces that field.
    /// - Parameters:
    ///   - type: Existing command kind, default chatInput, not encoded and cannot change through this operation.
    ///   - name: Omitted or a valid kind-specific 1...32 scalar name; null is forbidden.
    ///   - description: Omitted or a 1...100 scalar chat/entry description; user/message descriptions may only be empty.
    ///   - nameLocalizations: Omitted/null/localized names, replacing the complete dictionary when supplied.
    ///   - descriptionLocalizations: Omitted/null/localized descriptions following the command kind.
    ///   - options: Optional complete replacement slash-option array, including empty to clear.
    ///   - defaultMemberPermissions: Omitted/null/nonnegative exact permission digits.
    ///   - dmPermission: Deprecated omitted/null/boolean global DM setting.
    ///   - defaultPermission: Deprecated optional default-enabled flag.
    ///   - integrationTypes: Optional nonempty distinct global install contexts.
    ///   - contexts: Optional nonempty distinct global interaction contexts.
    ///   - nsfw: Optional age restriction; omission retains the existing value.
    ///   - handler: Optional entry-point-only interaction handler.
    /// - Throws: Invalid-value or limitExceeded for incompatible fields, bounds or text budget. Server scope, permissions,
    ///   and final combined text size with omitted existing fields remain server checks; no I/O or normalization occurs.
    public init(type: ApplicationCommandType = .chatInput, name: Field<String> = .absent,
                description: Field<String> = .absent, nameLocalizations: Field<[String: String]> = .absent,
                descriptionLocalizations: Field<[String: String]> = .absent,
                options: [ApplicationCommandOptionCreate]? = nil, defaultMemberPermissions: Field<String> = .absent,
                dmPermission: Field<Bool> = .absent, defaultPermission: Bool? = nil,
                integrationTypes: [ApplicationIntegrationType]? = nil, contexts: [InteractionContextType]? = nil,
                nsfw: Bool? = nil, handler: ApplicationCommandHandler? = nil) throws {
        self.type = type
        fields = try commandFields(type: type, name: name, description: description,
            nameLocalizations: nameLocalizations, descriptionLocalizations: descriptionLocalizations,
            options: options, defaultMemberPermissions: defaultMemberPermissions, dmPermission: dmPermission,
            defaultPermission: defaultPermission, integrationTypes: integrationTypes, contexts: contexts, nsfw: nsfw, handler: handler)
    }

    /// Returns exactly the selected PATCH fields, including an empty object for an explicit empty edit.
    /// - Returns: Immutable replacement fields; omitted values remain omitted.
    public func jsonValue() -> JSONValue { .object(fields) }
}

/// One explicit bulk registration entry; optional stable ID supports preserving existing registrations.
public struct ApplicationCommandRegistration: GuildRequestPayload {
    /// Validated complete desired registration.
    public let command: ApplicationCommandCreate
    /// Optional existing command ID, omitted for name/type upsert semantics.
    public let id: ApplicationCommandID?

    /// Stores a complete validated registration and optional ID without querying current state.
    /// - Parameters:
    ///   - command: Immutable validated command, including its known kind and exact name.
    ///   - id: Existing ID if known; ownership is verified by Discord during execution, default nil.
    public init(command: ApplicationCommandCreate, id: ApplicationCommandID? = nil) {
        self.command = command; self.id = id
    }

    /// Adds the optional stable ID to the complete registration object.
    /// - Returns: Exact bulk entry; no read, comparison, mutation or I/O occurs.
    public func jsonValue() -> JSONValue {
        guard case .object(var result) = command.jsonValue() else { return command.jsonValue() }
        if let id { result["id"] = .string(id.description) }
        return .object(result)
    }
}

/// Explicit finite destructive replacement of all command types in one scope, never chunked automatically.
public struct BulkApplicationCommands: GuildRequestPayload {
    /// Complete desired entries; empty intentionally removes every command in the selected scope.
    public let commands: [ApplicationCommandRegistration]

    /// Bounds an explicit replacement and rejects duplicate name/type or stable-ID identities.
    /// - Parameter commands: At most 131 entries: 100 slash, 15 user, 15 message and one global entry point;
    ///   guild endpoints additionally reject entry points. Empty means remove all, not no work.
    /// - Throws: Invalid-value for duplicate identities or per-kind counts above the documented scope caps.
    ///   The JSON pipeline separately enforces a complete 1 MiB encoded-body limit. No I/O or chunking occurs.
    public init(commands: [ApplicationCommandRegistration]) throws {
        guard commands.count <= 131,
              Set(commands.map { "\($0.command.type.rawValue):\($0.command.name)" }).count == commands.count,
              Set(commands.compactMap(\.id)).count == commands.compactMap(\.id).count
        else { throw DiscordError.validation(.invalidValue) }
        for type in ApplicationCommandType.allCases {
            let maximum = type == .chatInput ? 100 : (type == .primaryEntryPoint ? 1 : 15)
            guard commands.filter({ $0.command.type == type }).count <= maximum else { throw DiscordError.validation(.invalidValue) }
        }
        self.commands = commands
    }

    /// Encodes the complete replacement list in caller order, without hiding destructive empty semantics.
    /// - Returns: Immutable array; Discord does not promise response order matches this input order.
    public func jsonValue() -> JSONValue { .array(commands.map { $0.jsonValue() }) }
}

/// One typed outgoing permission overwrite, including @everyone and all-channel guild-derived constants.
public struct ApplicationCommandPermissionOverwrite: GuildRequestPayload {
    private let fields: [String: JSONValue]
    /// Exact role/user/channel or permission-constant identifier.
    public let id: ApplicationCommandPermissionTargetID
    /// Known target kind; unknown response values cannot be written accidentally.
    public let type: ApplicationCommandPermissionType
    /// True allows the target; false denies it within Discord's full permission system.
    public let permission: Bool

    /// Stores a typed overwrite without inferring membership, hierarchy or command invocation authority.
    /// - Parameters:
    ///   - id: Exact target ID; @everyone uses guild_id and all channels uses guild_id - 1.
    ///   - type: Role, user or channel; target existence and constant compatibility remain server checks.
    ///   - permission: Explicit allow/deny flag.
    /// - Throws: Numeric encoding errors only if a documented integral kind violates JSON number grammar.
    public init(id: ApplicationCommandPermissionTargetID, type: ApplicationCommandPermissionType, permission: Bool) throws {
        self.id = id; self.type = type; self.permission = permission
        fields = ["id": .string(id.description), "type": try guildRequestNumber(type.rawValue), "permission": .bool(permission)]
    }

    /// Encodes a target without converting its snowflake through floating point.
    /// - Returns: Exact id/type/permission object; deliberate callers own subsequent logging.
    public func jsonValue() -> JSONValue {
        .object(fields)
    }
}

/// Complete replacement of one command's guild permission overrides, requiring scoped user Bearer authorization.
public struct ApplicationCommandPermissionsModify: GuildRequestPayload {
    private let fields: [String: JSONValue]

    /// Validates the finite replacement without checking caller scopes, guild permissions or target hierarchy.
    /// - Parameter permissions: At most 100 distinct target/type pairs; empty clears the command's explicit overrides.
    /// - Throws: Invalid-value for excess entries or duplicate target/type pairs. No disabled batch route is used.
    public init(permissions: [ApplicationCommandPermissionOverwrite]) throws {
        guard permissions.count <= 100,
              Set(permissions.map { "\($0.type.rawValue):\($0.id)" }).count == permissions.count
        else { throw DiscordError.validation(.invalidValue) }
        fields = ["permissions": .array(permissions.map { $0.jsonValue() })]
    }

    /// Returns the exact permission replacement object without evaluating effective authorization.
    /// - Returns: A required permissions array, including empty to clear; no I/O or caching occurs.
    public func jsonValue() -> JSONValue { .object(fields) }
}

/// Validates a command/option name against the written Unicode grammar, preserving exact spelling.
/// - Parameters:
///   - text: Name with 1...32 Unicode scalars; text is never embedded in failures.
///   - slash: True requires lowercase letters, numbers, Devanagari/Thai marks, hyphen, underscore or U+02BC.
/// - Returns: Original text as JSON without normalization or case conversion.
/// - Throws: Invalid-value for bounds, uppercase cased letters or grammar mismatch; no I/O occurs.
private func commandName(_ text: String, slash: Bool) throws -> JSONValue {
    _ = try guildRequestText(text, length: 1...32)
    if slash {
        let pattern = "\\A[-_\\u02BC\\p{L}\\p{N}\\p{sc=Deva}\\p{sc=Thai}]{1,32}\\z"
        guard text == text.lowercased(), text.range(of: pattern, options: .regularExpression) != nil
        else { throw DiscordError.validation(.invalidValue) }
    }
    return .string(text)
}

/// Inserts a nullable localization dictionary after validating current official locale keys and all values.
/// - Parameters:
///   - field: Omitted, null or complete localization replacement, including an empty dictionary.
///   - key: Exact JSON dictionary name.
///   - range: Inclusive Unicode-scalar value bounds.
///   - slash: Whether localized values follow slash-name grammar; defaults false.
///   - fields: In-progress immutable-request builder; no partial result escapes on failure.
/// - Throws: Invalid-value for unsupported locales, too many entries, value lengths or naming grammar.
private func commandLocalizations(_ field: Field<[String: String]>, key: String, range: ClosedRange<Int>,
                                  slash: Bool = false, into fields: inout [String: JSONValue]) throws {
    let locales: Set<String> = ["id", "da", "de", "en-GB", "en-US", "es-ES", "es-419", "fr", "hr", "it", "lt", "hu", "nl", "no", "pl", "pt-BR", "ro", "fi", "sv-SE", "vi", "tr", "cs", "el", "bg", "ru", "uk", "hi", "th", "zh-CN", "ja", "zh-TW", "ko"]
    try guildRequestField(field, name: key, nullable: true, into: &fields) { values in
        guard values.count <= 34, Set(values.keys).isSubset(of: locales) else { throw DiscordError.validation(.invalidValue) }
        return .object(try values.mapValues { text in
            _ = try guildRequestText(text, length: range)
            return slash ? try commandName(text, slash: true) : .string(text)
        })
    }
}

/// Validates finite exact option numeric bounds without rounding integer tokens.
/// - Parameters:
///   - number: Original numeric lexeme; exponent/fraction forms are allowed only for number options.
///   - integer: True requires an exact Int64 decimal token in ±(2^53-1); false permits finite ±2^53.
/// - Returns: Original number token unchanged.
/// - Throws: Invalid-value for unsupported spelling, overflow, nonfinite or out-of-range values.
private func commandNumber(_ number: JSONNumber, integer: Bool) throws -> JSONValue {
    if integer {
        guard let value = Int64(number.rawValue), (-9_007_199_254_740_991...9_007_199_254_740_991).contains(value)
        else { throw DiscordError.validation(.invalidValue) }
    } else {
        guard let value = Double(number.rawValue), value.isFinite, commandNumberWithinMagnitude(number)
        else { throw DiscordError.validation(.invalidValue) }
    }
    return .number(number)
}

/// Compares an exact JSON numeric magnitude with 2^53 without a floating-point boundary round-down.
/// - Parameter number: Grammar-validated finite numeric lexeme; signs, fractions and exponent notation are retained.
/// - Returns: True when the exact magnitude is at most 9007199254740992, including underflow-scale fractions and zero.
///   Work is linear in the bounded request lexeme; no expanded exponent-sized buffer or arbitrary-width arithmetic is allocated.
private func commandNumberWithinMagnitude(_ number: JSONNumber) -> Bool {
    let unsigned = number.rawValue.hasPrefix("-") ? String(number.rawValue.dropFirst()) : number.rawValue
    let parts = unsigned.split(whereSeparator: { $0 == "e" || $0 == "E" })
    let mantissa = String(parts[0])
    let digits = mantissa.filter { $0 != "." }
    let leadingZeros = digits.prefix(while: { $0 == "0" }).count
    let significant = String(digits.dropFirst(leadingZeros))
    guard !significant.isEmpty else { return true }
    let exponent: Int
    if parts.count == 2 {
        guard let parsed = Int(parts[1]) else { return parts[1].hasPrefix("-") }
        exponent = parsed
    } else { exponent = 0 }
    if exponent < -mantissa.count - 32 { return true }
    if exponent > mantissa.count + 32 { return false }
    let wholeDigits = mantissa.prefix(while: { $0 != "." }).count
    let width = wholeDigits - leadingZeros + exponent
    if width < 16 { return true }
    if width > 16 { return false }
    let prefix = String(significant.prefix(16))
    let padded = prefix + String(repeating: "0", count: 16 - prefix.count)
    let boundary = "9007199254740992"
    if padded != boundary { return padded < boundary }
    return significant.dropFirst(16).allSatisfy { $0 == "0" }
}

/// Validates a single bounded sibling-option list and required-before-optional ordering.
/// - Parameter options: At most 25 immutable options with unique names; structural kinds cannot mix with leaves.
/// - Returns: Exact ordered option array.
/// - Throws: Invalid-value for duplicates, size, mixed structural/leaf kinds or a required leaf after an optional leaf.
private func commandOptions(_ options: [ApplicationCommandOptionCreate]) throws -> JSONValue {
    guard options.count <= 25, Set(options.map(\.name)).count == options.count,
          !options.contains(where: { $0.type.rawValue <= 2 }) || options.allSatisfy({ $0.type.rawValue <= 2 })
    else { throw DiscordError.validation(.invalidValue) }
    var optionalSeen = false
    for option in options where option.type.rawValue >= 3 {
        if option.required == true {
            guard !optionalSeen else { throw DiscordError.validation(.invalidValue) }
        } else { optionalSeen = true }
    }
    return .array(options.map { $0.jsonValue() })
}

/// Counts longest-localized name/description and textual choice-value scalars across a bounded command tree.
/// - Parameter value: Validated option or command object/array, with depth bounded by the concrete request constructors.
/// - Returns: Total Unicode scalars, using each field's longest localization including the base value; numeric values add zero.
private func commandTextSize(_ value: JSONValue) -> Int {
    switch value {
    case .array(let values): return values.reduce(0) { $0 + commandTextSize($1) }
    case .object(let fields):
        var count = 0
        for key in ["name", "description"] {
            let base: Int
            if case .string(let text) = fields[key] { base = text.unicodeScalars.count } else { base = 0 }
            let localized: [Int]
            if case .object(let values) = fields[key + "_localizations"] {
                localized = values.values.compactMap { if case .string(let text) = $0 { text.unicodeScalars.count } else { nil } }
            } else { localized = [] }
            count += max(base, localized.max() ?? 0)
        }
        if case .string(let text) = fields["value"] { count += text.unicodeScalars.count }
        count += commandTextSize(fields["options"] ?? .null) + commandTextSize(fields["choices"] ?? .null)
        return count
    default: return 0
    }
}

/// Builds shared create/edit fields with exact presence, known-kind compatibility and cumulative text validation.
/// - Parameters:
///   - type: Existing or desired kind used for validation, never inferred from mutable server state.
///   - name: Omitted or nonnull kind-specific name.
///   - description: Omitted or kind-specific description; null is forbidden.
///   - nameLocalizations: Nullable complete name dictionary.
///   - descriptionLocalizations: Nullable complete description dictionary.
///   - options: Optional entire slash option list.
///   - defaultMemberPermissions: Nullable canonical exact permission digits.
///   - dmPermission: Deprecated nullable global DM visibility.
///   - defaultPermission: Deprecated optional enabled-by-default flag.
///   - integrationTypes: Optional nonempty distinct install kinds.
///   - contexts: Optional nonempty distinct interaction contexts.
///   - nsfw: Optional age restriction.
///   - handler: Optional entry-point-only handler; eligibility is checked by Discord.
/// - Returns: Bounded validated object fields; edit omissions preserve server values.
/// - Throws: Invalid-value for unsupported combinations/values, or limitExceeded above 8000 localized scalars.
private func commandFields(type: ApplicationCommandType, name: Field<String>, description: Field<String>,
    nameLocalizations: Field<[String: String]>, descriptionLocalizations: Field<[String: String]>,
    options: [ApplicationCommandOptionCreate]?, defaultMemberPermissions: Field<String>, dmPermission: Field<Bool>,
    defaultPermission: Bool?, integrationTypes: [ApplicationIntegrationType]?, contexts: [InteractionContextType]?,
    nsfw: Bool?, handler: ApplicationCommandHandler?) throws -> [String: JSONValue] {
    var result: [String: JSONValue] = [:]
    try guildRequestField(name, name: "name", into: &result) { try commandName($0, slash: type == .chatInput) }
    let descriptive = type == .chatInput || type == .primaryEntryPoint
    try guildRequestField(description, name: "description", into: &result) {
        try guildRequestText($0, length: descriptive ? 1...100 : 0...0)
    }
    try commandLocalizations(nameLocalizations, key: "name_localizations", range: 1...32, slash: type == .chatInput, into: &result)
    if !descriptive, case .value(let values) = descriptionLocalizations, !values.isEmpty {
        throw DiscordError.validation(.invalidValue)
    }
    try commandLocalizations(descriptionLocalizations, key: "description_localizations", range: 1...100, into: &result)
    if let options {
        guard type == .chatInput else { throw DiscordError.validation(.invalidValue) }
        result["options"] = try commandOptions(options)
    }
    try guildRequestField(defaultMemberPermissions, name: "default_member_permissions", nullable: true, into: &result) {
        guard !$0.isEmpty, $0.utf8.allSatisfy({ (48...57).contains($0) }), $0 == "0" || $0.first != "0", $0.count <= 1024
        else { throw DiscordError.validation(.invalidValue) }
        return .string($0)
    }
    try guildRequestField(dmPermission, name: "dm_permission", nullable: true, into: &result) { .bool($0) }
    if let defaultPermission { result["default_permission"] = .bool(defaultPermission) }
    if let integrationTypes {
        guard !integrationTypes.isEmpty, Set(integrationTypes.map(\.rawValue)).count == integrationTypes.count
        else { throw DiscordError.validation(.invalidValue) }
        result["integration_types"] = .array(try integrationTypes.map { try guildRequestNumber($0.rawValue) })
    }
    if let contexts {
        guard !contexts.isEmpty, Set(contexts.map(\.rawValue)).count == contexts.count else { throw DiscordError.validation(.invalidValue) }
        result["contexts"] = .array(try contexts.map { try guildRequestNumber($0.rawValue) })
    }
    if let nsfw { result["nsfw"] = .bool(nsfw) }
    if let handler {
        guard type == .primaryEntryPoint else { throw DiscordError.validation(.invalidValue) }
        result["handler"] = try guildRequestNumber(handler.rawValue)
    }
    guard commandTextSize(.object(result)) <= 8000 else { throw DiscordError.validation(.limitExceeded) }
    return result
}
