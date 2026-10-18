import DiscordCore
import DiscordDSL
import DiscordModels

/// Whether a complete invocation may contain leaf names absent from its declared schema.
/// Rejection is the default; ignoring a future leaf never admits nested or focused arguments.
public enum UnknownArgumentPolicy: Sendable, Equatable {
    /// Fail before constructing arguments when any supplied leaf is undeclared.
    case reject
    /// Ignore undeclared ordinary scalar leaves after envelope and duplicate validation.
    case ignore
}

/// An explicit author-supplied fallback, distinguishing no fallback from an optional nil fallback.
/// Defaults apply only when the complete invocation omits an option; explicit null never defaults.
public enum ArgumentDefault<Value: Sendable>: Sendable {
    /// No fallback. Nonoptional codecs require a submitted option; optional codecs receive absence.
    case none
    /// Use this validated value when the entire option is absent, including a typed optional nil.
    case value(Value)
}

/// A sanitized schema or complete-invocation failure. Submitted scalars, resolved resources and
/// underlying codec/constructor errors are never retained or reflected by this diagnostic.
public struct ArgumentDiagnostic: Error, Sendable, Equatable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable {
    /// Stable failure categories independent of localized explanations or underlying errors.
    public enum Code: String, Sendable, Equatable {
        /// Invalid leaf registration, required ordering, localization or aggregate text admission.
        case invalidSchema
        /// A supplied fallback violates wire, choice, constraint or codec requirements.
        case invalidDefault
        /// A declared or submitted sibling array contains more than 25 options.
        case optionLimit
        /// Two declared or submitted siblings have the same name.
        case duplicateOption
        /// A submitted ordinary leaf is undeclared under the reject policy.
        case unknownOption
        /// A required option or a supplied leaf's scalar is absent.
        case missingValue
        /// A complete invocation supplied explicit null, which cannot represent omission.
        case nullValue
        /// The submitted discriminator or scalar does not match its declared leaf kind.
        case wrongType
        /// A leaf contains child options, including an explicit null options field.
        case nestedOption
        /// Autocomplete focus metadata is present in a complete invocation.
        case focusedOption
        /// A valid wire scalar could not be decoded by the selected codec.
        case invalidValue
        /// A scalar is outside its declared choice, length, range or channel constraints.
        case constraintViolation
        /// A constructor requested an undeclared, differently typed or differently configured descriptor.
        case descriptorMismatch
        /// The handwritten aggregate constructor failed after all leaf values were validated.
        case constructionFailed
    }

    /// Stable machine-readable failure category.
    public let code: Code
    /// Bounded declared command label, empty when the schema is not yet associated with a command.
    public let commandName: String
    /// Bounded declared option label; nil for untrusted unknown names and command-wide failures.
    public let optionName: String?
    /// Bounded author source coordinate; the file label is never resolved as a filesystem path.
    public let source: DefinitionSourceLocation

    /// Creates bounded display context without retaining submitted values or an underlying error.
    /// - Parameters:
    ///   - code: Stable failure category.
    ///   - commandName: Declared command label; default empty before command lowering, at most 128 UTF-8 bytes.
    ///   - optionName: Declared option label or nil; retained labels are limited to 128 UTF-8 bytes.
    ///   - source: Author coordinate, with the file identifier limited to 256 UTF-8 bytes.
    public init(code: Code, commandName: String = "", optionName: String? = nil,
                source: DefinitionSourceLocation) {
        self.code = code
        self.commandName = argumentBoundedLabel(commandName, maximumBytes: 128)
        self.optionName = optionName.map { argumentBoundedLabel($0, maximumBytes: 128) }
        self.source = argumentBoundedSource(source)
    }

    /// Adds the declared command identity to an error discovered while building its argument schema.
    /// - Parameter commandName: Already selected command label, bounded using the ordinary diagnostic policy.
    /// - Returns: The same failure, option and source with bounded command context replaced.
    public func contextualized(commandName: String) -> Self {
        Self(code: code, commandName: commandName, optionName: optionName, source: source)
    }

    /// Produces only the stable category, excluding all retained contextual labels.
    public var description: String { "ArgumentDiagnostic(\(code.rawValue))" }
    /// Preserves the same sanitized formatting during debug output.
    public var debugDescription: String { description }
    /// Prevents reflective logging from traversing author labels or any future retained metadata.
    public var customMirror: Mirror { Mirror(self, children: ["code": code.rawValue]) }
}

/// A typed, inert leaf descriptor. Registration and decoding share the same exact type, choices
/// and constraints; constructing a descriptor never registers commands or executes a handler.
public struct ArgumentOption<Value: ArgumentValue>: Sendable {
    /// Validated existing-model leaf registration, suitable for independent command lowering.
    public let registration: ApplicationCommandOptionCreate
    /// Bounded author coordinate used in schema and invocation failures.
    public let source: DefinitionSourceLocation
    fileprivate let storage: AnyArgumentOption

    /// Exact validated Discord leaf name.
    public var name: String { registration.name }
    /// Erases only the generic argument type while retaining its decoder and registration fingerprint.
    public var erased: AnyArgumentOption { storage }

    /// Validates a typed leaf and its optional fallback synchronously, reusing the existing registration model.
    /// - Parameters:
    ///   - name: Discord lowercase slash-option name, 1...32 Unicode scalars.
    ///   - description: Explanation, 1...100 Unicode scalars.
    ///   - defaultValue: Explicit fallback, default none. Optional nil is `.value(nil)` and differs from none.
    ///   - nameLocalizations: Absent, null or complete localized name dictionary; default absent.
    ///   - descriptionLocalizations: Absent, null or complete localized descriptions; default absent.
    ///   - channelTypes: Optional distinct known channel filters; runtime constrained channels require resolved type data.
    ///   - minValue: Optional inclusive numeric minimum using the registration model's exact lexeme validation.
    ///   - maxValue: Optional inclusive numeric maximum, not less than the minimum.
    ///   - minLength: Optional inclusive string minimum in Unicode scalars, within 0...6000.
    ///   - maxLength: Optional inclusive string maximum in Unicode scalars, within 1...6000.
    ///   - fileTypes: Optional attachment picker filters. These are host hints and do not validate file content.
    ///   - source: Explicit author coordinate; nil captures the caller using fileID/line/column.
    ///     Only a bounded scalar-aligned file-label prefix is retained.
    ///   - fileID: Caller compiler file identifier, used only when source is nil; no source file is opened.
    ///   - line: Caller one-based source line, used only when source is nil; zero indicates unavailable.
    ///   - column: Caller one-based source column, used only when source is nil; zero indicates unavailable.
    /// - Throws: `ArgumentDiagnostic.invalidSchema` for invalid existing-model registration or codec choices,
    ///   or `invalidDefault` for an incompatible fallback. Underlying codec errors and fallback values are hidden.
    ///
    /// Requiredness is inferred: only nonoptional values without defaults are required. Autocomplete and
    /// structural options are reserved for later milestones. Custom codec code is synchronous author code,
    /// must terminate and avoid side effects, and is not sandboxed by the DSL.
    public init(name: String, description: String, defaultValue: ArgumentDefault<Value> = .none,
                nameLocalizations: Field<[String: String]> = .absent,
                descriptionLocalizations: Field<[String: String]> = .absent,
                channelTypes: [ChannelType]? = nil, minValue: JSONNumber? = nil,
                maxValue: JSONNumber? = nil, minLength: Int? = nil, maxLength: Int? = nil,
                fileTypes: [String]? = nil, source: DefinitionSourceLocation? = nil,
                fileID: String = #fileID, line: UInt = #line, column: UInt = #column) throws {
        let boundedSource = argumentBoundedSource(source ?? .init(fileID: fileID, line: line, column: column))
        let registration: ApplicationCommandOptionCreate
        let required: Bool
        switch defaultValue {
        case .none: required = !Value.isOptional
        case .value: required = false
        }
        do {
            guard Value.optionType.rawValue >= ApplicationCommandOptionType.string.rawValue else {
                throw ArgumentDiagnostic(code: .invalidSchema, optionName: name, source: boundedSource)
            }
            let choices = try Value.choices
            if Value.optionType == .number {
                let numericChoices = choices.compactMap { choice -> JSONNumber? in
                    guard case .number(let value) = choice.value else { return nil }
                    return value
                }
                guard ([minValue, maxValue].compactMap { $0 } + numericChoices).allSatisfy(argumentNumberWithinRange) else {
                    throw ArgumentDiagnostic(code: .invalidSchema, optionName: name, source: boundedSource)
                }
                if let minValue, let maxValue, argumentCompareNumbers(minValue, maxValue) > 0 {
                    throw ArgumentDiagnostic(code: .invalidSchema, optionName: name, source: boundedSource)
                }
            }
            registration = try ApplicationCommandOptionCreate(type: Value.optionType, name: name,
                description: description, nameLocalizations: nameLocalizations,
                descriptionLocalizations: descriptionLocalizations, required: required,
                choices: choices.isEmpty ? nil : choices, channelTypes: channelTypes,
                minValue: minValue, maxValue: maxValue, minLength: minLength, maxLength: maxLength,
                fileTypes: fileTypes)
        } catch {
            throw ArgumentDiagnostic(code: .invalidSchema, optionName: name, source: boundedSource)
        }
        let fallback: CachedArgument?
        do {
            switch defaultValue {
            case .none: fallback = nil
            case .value(let value):
                let raw = try value.argumentValue
                if case .absent = raw {
                    guard Value.isOptional else {
                        throw ArgumentDiagnostic(code: .invalidDefault, optionName: name, source: boundedSource)
                    }
                } else {
                    try argumentValidate(raw, registration: registration, resolved: .absent,
                                         commandName: "", source: boundedSource)
                }
                _ = try Value.decodeArgument(raw, resolved: .absent)
                fallback = CachedArgument(value: value, representation: raw)
            }
        } catch {
            throw ArgumentDiagnostic(code: .invalidDefault, optionName: name, source: boundedSource)
        }
        self.registration = registration
        self.source = boundedSource
        storage = AnyArgumentOption(registration: registration, source: boundedSource,
            valueType: ObjectIdentifier(Value.self), optional: Value.isOptional, fallback: fallback,
            decode: { raw, resolved in try Value.decodeArgument(raw, resolved: resolved) })
    }
}

/// An ordered schema leaf retaining bounded registration metadata and its typed, synchronous codec.
/// Erasure never executes the decoder and cannot change the option's declared type or default.
public struct AnyArgumentOption: Sendable {
    /// Existing validated registration, including inferred requiredness and declared choices/constraints.
    public let registration: ApplicationCommandOptionCreate
    /// Bounded author coordinate associated with this exact descriptor.
    public let source: DefinitionSourceLocation
    fileprivate let valueType: ObjectIdentifier
    fileprivate let optional: Bool
    fileprivate let fallback: CachedArgument?
    fileprivate let decode: @Sendable (Field<JSONValue>, Field<InteractionResolvedData>) throws -> any Sendable

    /// Exact validated name, retaining declaration order through the owning schema array.
    public var name: String { registration.name }

    /// Retains an already validated typed descriptor without new codec execution or I/O.
    /// - Parameter option: The exact leaf descriptor whose registration and type fingerprint are retained.
    public init<Value: ArgumentValue>(_ option: ArgumentOption<Value>) {
        self = option.storage
    }

    /// Creates erasure exclusively from the typed descriptor's validated components.
    /// - Parameters:
    ///   - registration: Validated nonstructural leaf and inferred requiredness.
    ///   - source: Already bounded author coordinate.
    ///   - valueType: Exact Swift metatype identity, checked before typed decoder access.
    ///   - optional: Whether absent input is supported when no fallback exists.
    ///   - fallback: Validated typed fallback and exact raw fingerprint, or nil for no fallback.
    ///   - decode: Synchronous codec, invoked at most once per declared leaf per successful decode.
    fileprivate init(registration: ApplicationCommandOptionCreate, source: DefinitionSourceLocation,
                     valueType: ObjectIdentifier, optional: Bool, fallback: CachedArgument?,
                     decode: @escaping @Sendable (Field<JSONValue>, Field<InteractionResolvedData>) throws -> any Sendable) {
        self.registration = registration
        self.source = source
        self.valueType = valueType
        self.optional = optional
        self.fallback = fallback
        self.decode = decode
    }
}

/// A handwritten argument aggregate whose schema constructs `Self` only after every declared leaf
/// has passed validation. Schema access is synchronous and may fail during command compilation.
public protocol CommandArguments: Sendable {
    /// Returns a finite ordered schema without tasks, handler execution, network or registration work.
    /// - Throws: `ArgumentDiagnostic` for invalid descriptors or any explicit author schema-building failure.
    static var schema: CommandArgumentSchema<Self> {
        /// Builds the finite local schema without suspension, runtime work or registration.
        /// - Throws: The author's synchronous schema-building or descriptor validation error.
        get throws
    }
}

/// An immutable typed lookup view over eagerly validated, cached values from one complete invocation.
/// The constructor may read a value repeatedly without rerunning its codec. Arbitrary handwritten
/// aggregate construction remains author code; the DSL does not prove that every field is consumed.
public struct ArgumentDecoder: Sendable {
    private let descriptors: [String: AnyArgumentOption]
    private let values: [String: CachedArgument]
    private let commandName: String
    private let source: DefinitionSourceLocation

    /// Retains the complete validated cache for one synchronous aggregate construction.
    /// - Parameters:
    ///   - descriptors: Unique declared name-to-descriptor map, with at most 25 entries.
    ///   - values: Eagerly validated values for every declared name, including omitted optional values.
    ///   - commandName: Declared command label for failures.
    ///   - source: Bounded schema source used when a lookup names an undeclared descriptor.
    fileprivate init(descriptors: [String: AnyArgumentOption], values: [String: CachedArgument],
                     commandName: String, source: DefinitionSourceLocation) {
        self.descriptors = descriptors
        self.values = values
        self.commandName = commandName
        self.source = source
    }

    /// Retrieves one cached value using the exact Swift type and registration/default fingerprint.
    /// - Parameter option: Descriptor used by this schema; an equivalent copied descriptor is permitted.
    /// - Returns: The already decoded value, including a typed optional nil or declared fallback.
    /// - Throws: `ArgumentDiagnostic.descriptorMismatch` for missing names, different Swift types,
    ///   registrations or fallback representations. This never invokes a codec or suspends.
    public func value<Value: ArgumentValue>(for option: ArgumentOption<Value>) throws -> Value {
        guard let declared = descriptors[option.name], let cached = values[option.name],
              declared.valueType == ObjectIdentifier(Value.self),
              declared.registration.jsonValue() == option.registration.jsonValue(),
              declared.fallback?.representation == option.storage.fallback?.representation,
              let value = cached.value as? Value else {
            throw ArgumentDiagnostic(code: .descriptorMismatch, commandName: commandName,
                                     optionName: option.name, source: descriptors[option.name]?.source ?? source)
        }
        return value
    }
}

/// Finite declaration-order argument registration and decoding, independent of any network host.
/// Each complete invocation validates all envelopes and every declared codec before aggregate
/// construction. No partial argument aggregate escapes on failure and no handler is owned here.
public struct CommandArgumentSchema<Arguments: Sendable>: Sendable {
    /// Existing-model registrations in exact author order, including required-before-optional ordering.
    public let options: [ApplicationCommandOptionCreate]
    /// Typed erasures aligned exactly with `options`; their author coordinates support diagnostics.
    public let descriptors: [AnyArgumentOption]
    /// Explicit unknown-leaf admission policy; default rejection.
    public let unknownOptions: UnknownArgumentPolicy
    /// Bounded schema coordinate used for command-wide and aggregate-construction failures.
    public let source: DefinitionSourceLocation
    private let byName: [String: AnyArgumentOption]
    private let construct: @Sendable (ArgumentDecoder) throws -> Arguments

    /// Deterministic author metadata for shared definition admission and offline description comparison.
    /// Includes exact ordered registrations, default presence/value fingerprints, the unknown policy and
    /// bounded source coordinates. It includes author defaults deliberately; it never contains submitted data,
    /// executable closures or resolved resources. Source coordinates use exact decimal strings.
    public var metadata: JSONValue {
        .object([
            "options": .array(descriptors.map { descriptor in
                let fallback: JSONValue
                switch descriptor.fallback?.representation {
                case nil: fallback = .object(["state": .string("none")])
                case .absent?: fallback = .object(["state": .string("absent")])
                case .null?: fallback = .object(["state": .string("null")])
                case .value(let value)?: fallback = .object(["state": .string("value"), "value": value])
                }
                return .object(["registration": descriptor.registration.jsonValue(),
                                "default": fallback, "source": argumentSourceMetadata(descriptor.source)])
            }),
            "unknown_options": .string(unknownOptions == .reject ? "reject" : "ignore"),
            "source": argumentSourceMetadata(source)
        ])
    }

    /// Admits a complete ordered leaf schema using the existing command model's aggregate validation.
    /// - Parameters:
    ///   - options: At most 25 unique descriptors, with required leaves before optional/defaulted leaves.
    ///     Aggregate localized registration text remains subject to the existing 8000-scalar command bound.
    ///   - unknownOptions: Reject undeclared complete leaves by default; explicit ignore supports compatible extension.
    ///   - source: Explicit author schema coordinate; nil captures fileID/line/column, bounded without file access.
    ///   - fileID: Caller compiler file identifier, used only when source is nil.
    ///   - line: Caller one-based source line, used only when source is nil; zero indicates unavailable.
    ///   - column: Caller one-based source column, used only when source is nil; zero indicates unavailable.
    ///   - construct: Synchronous, Sendable aggregate constructor called only after all leaf values validate.
    ///     It must terminate and avoid side effects; owned code creates no tasks, suspension or I/O.
    /// - Throws: `ArgumentDiagnostic` for excessive count, duplicate names, required ordering or aggregate text.
    ///   This retains the constructor without executing it or any leaf codec.
    public init(options: [AnyArgumentOption], unknownOptions: UnknownArgumentPolicy = .reject,
                source: DefinitionSourceLocation? = nil, fileID: String = #fileID,
                line: UInt = #line, column: UInt = #column,
                construct: @escaping @Sendable (ArgumentDecoder) throws -> Arguments) throws {
        let boundedSource = argumentBoundedSource(source ?? .init(fileID: fileID, line: line, column: column))
        guard options.count <= 25 else {
            throw ArgumentDiagnostic(code: .optionLimit, source: boundedSource)
        }
        var byName: [String: AnyArgumentOption] = [:]
        for option in options {
            guard byName.updateValue(option, forKey: option.name) == nil else {
                throw ArgumentDiagnostic(code: .duplicateOption, optionName: option.name, source: option.source)
            }
        }
        do {
            _ = try ApplicationCommandCreate(name: "a", description: "b",
                                             options: options.map(\.registration))
        } catch {
            throw ArgumentDiagnostic(code: .invalidSchema, source: boundedSource)
        }
        self.options = options.map(\.registration)
        descriptors = options
        self.unknownOptions = unknownOptions
        self.source = boundedSource
        self.byName = byName
        self.construct = construct
    }

    /// Validates and decodes one complete leaf invocation in declaration order, without handler execution.
    /// - Parameters:
    ///   - options: Submitted leaves, at most 25. Supplied null, missing values, nested options and focus metadata fail.
    ///   - resolved: Retained interaction resolution data, default absent; no resources are fetched or authorized here.
    ///   - commandName: Declared command label used only as bounded diagnostic context.
    /// - Returns: Exactly one aggregate from the cached validated leaves, preserving nil/default distinctions.
    /// - Throws: `ArgumentDiagnostic` for malformed, unknown, duplicate, missing or incompatible leaves,
    ///   failed codecs, descriptor mismatches or aggregate construction failure. Underlying errors are redacted.
    ///
    /// All supplied envelopes are checked before codecs run. Each present or omitted optional codec is
    /// evaluated once; validated explicit fallbacks reuse their retained value. Runtime is bounded by 25
    /// leaves plus scalar/registration text and injected codec/constructor work. No tasks, I/O or suspension occur.
    public func decode(options: [InteractionCommandOption], resolved: Field<InteractionResolvedData> = .absent,
                       commandName: String) throws -> Arguments {
        guard options.count <= 25 else {
            throw ArgumentDiagnostic(code: .optionLimit, commandName: commandName, source: source)
        }
        var submitted: [String: InteractionCommandOption] = [:]
        for option in options {
            let declared = byName[option.name]
            let failureSource = declared?.source ?? source
            let safeName = declared?.name
            guard submitted.updateValue(option, forKey: option.name) == nil else {
                throw ArgumentDiagnostic(code: .duplicateOption, commandName: commandName,
                                         optionName: safeName, source: failureSource)
            }
            guard case .absent = option.options else {
                throw ArgumentDiagnostic(code: .nestedOption, commandName: commandName,
                                         optionName: safeName, source: failureSource)
            }
            guard case .absent = option.focused else {
                throw ArgumentDiagnostic(code: .focusedOption, commandName: commandName,
                                         optionName: safeName, source: failureSource)
            }
            if case .absent = option.value {
                throw ArgumentDiagnostic(code: .missingValue, commandName: commandName,
                                         optionName: safeName, source: failureSource)
            }
            if case .null = option.value {
                throw ArgumentDiagnostic(code: .nullValue, commandName: commandName,
                                         optionName: safeName, source: failureSource)
            }
            guard let declared else {
                guard unknownOptions == .ignore else {
                    throw ArgumentDiagnostic(code: .unknownOption, commandName: commandName, source: source)
                }
                guard option.type.rawValue >= ApplicationCommandOptionType.string.rawValue,
                      case .value(let scalar) = option.value,
                      argumentWireShape(scalar, type: option.type.knownValue) else {
                    throw ArgumentDiagnostic(code: .wrongType, commandName: commandName, source: source)
                }
                continue
            }
            guard option.type.knownValue == declared.registration.type else {
                throw ArgumentDiagnostic(code: .wrongType, commandName: commandName,
                                         optionName: declared.name, source: declared.source)
            }
            try argumentValidate(option.value, registration: declared.registration, resolved: resolved,
                                 commandName: commandName, source: declared.source)
        }
        var values: [String: CachedArgument] = [:]
        for descriptor in descriptors {
            let raw: Field<JSONValue>
            if let submitted = submitted[descriptor.name] {
                raw = submitted.value
            } else if let fallback = descriptor.fallback {
                values[descriptor.name] = fallback
                continue
            } else {
                guard descriptor.optional else {
                    throw ArgumentDiagnostic(code: .missingValue, commandName: commandName,
                                             optionName: descriptor.name, source: descriptor.source)
                }
                raw = .absent
            }
            do {
                values[descriptor.name] = CachedArgument(value: try descriptor.decode(raw, resolved), representation: raw)
            } catch {
                throw ArgumentDiagnostic(code: .invalidValue, commandName: commandName,
                                         optionName: descriptor.name, source: descriptor.source)
            }
        }
        do {
            return try construct(ArgumentDecoder(descriptors: byName, values: values,
                                                 commandName: commandName, source: source))
        } catch let diagnostic as ArgumentDiagnostic {
            throw diagnostic.contextualized(commandName: commandName)
        } catch {
            throw ArgumentDiagnostic(code: .constructionFailed, commandName: commandName, source: source)
        }
    }
}

/// Retains an already validated Sendable value alongside its exact default/schema fingerprint.
fileprivate struct CachedArgument: Sendable {
    let value: any Sendable
    let representation: Field<JSONValue>
}

/// Validates leaf wire shape and constraints independently of a custom codec's implementation.
/// - Parameters:
///   - field: Present scalar; absence/null are reported separately and never coerced.
///   - registration: Existing validated leaf metadata, including scalar bounds, choices and channel filters.
///   - resolved: Retained resource maps; constrained channels require a matching known resolved type.
///   - commandName: Declared diagnostic command label, not submitted values.
///   - source: Bounded author coordinate for this exact leaf.
/// - Throws: Sanitized `ArgumentDiagnostic` for missing/null, wrong scalar shape, unsupported wire range,
///   choices or constraints. Attachment filters remain host picker hints, with content validation caller-owned.
private func argumentValidate(_ field: Field<JSONValue>, registration: ApplicationCommandOptionCreate,
                              resolved: Field<InteractionResolvedData>, commandName: String,
                              source: DefinitionSourceLocation) throws {
    let value: JSONValue
    switch field {
    case .absent:
        throw ArgumentDiagnostic(code: .missingValue, commandName: commandName, optionName: registration.name, source: source)
    case .null:
        throw ArgumentDiagnostic(code: .nullValue, commandName: commandName, optionName: registration.name, source: source)
    case .value(let supplied): value = supplied
    }
    guard argumentWireShape(value, type: registration.type) else {
        throw ArgumentDiagnostic(code: .wrongType, commandName: commandName, optionName: registration.name, source: source)
    }
    guard case .object(let fields) = registration.jsonValue() else { return }
    var valid = true
    if case .string(let text) = value {
        let count = text.unicodeScalars.count
        if case .number(let minimum) = fields["min_length"], let minimum = Int(minimum.rawValue) { valid = valid && count >= minimum }
        if case .number(let maximum) = fields["max_length"], let maximum = Int(maximum.rawValue) { valid = valid && count <= maximum }
    }
    if case .number(let number) = value {
        if case .number(let minimum) = fields["min_value"] { valid = valid && argumentCompareNumbers(number, minimum) >= 0 }
        if case .number(let maximum) = fields["max_value"] { valid = valid && argumentCompareNumbers(number, maximum) <= 0 }
    }
    if case .array(let choices) = fields["choices"], !choices.isEmpty {
        valid = valid && choices.contains { choice in
            guard case .object(let fields) = choice, let choiceValue = fields["value"] else { return false }
            return argumentScalarEqual(value, choiceValue)
        }
    }
    if case .array(let channels) = fields["channel_types"], case .string(let id) = value {
        if case .value(let resolved) = resolved, case .value(let map) = resolved.channels,
           let channel = map[id] ?? UInt64(id).flatMap({ map[String($0)] }), case .value(let kind) = channel.type {
            valid = valid && channels.contains { channel in
                guard case .number(let number) = channel else { return false }
                return Int(number.rawValue) == kind
            }
        } else { valid = false }
    }
    guard valid else {
        throw ArgumentDiagnostic(code: .constraintViolation, commandName: commandName,
                                 optionName: registration.name, source: source)
    }
}

/// Admits the exact ordinary wire scalar before any user-defined codec can reinterpret it.
/// - Parameters:
///   - value: Submitted scalar, still retaining exact number and snowflake spellings.
///   - type: Known declared leaf kind; nil admits an explicitly ignored future kind's ordinary scalar shape.
/// - Returns: Whether the scalar matches the kind and Discord numeric/string bounds. Snowflakes preserve
///   decimal leading zeros while requiring an exactly representable UInt64 identity; no hydration occurs.
private func argumentWireShape(_ value: JSONValue, type: ApplicationCommandOptionType?) -> Bool {
    switch (type, value) {
    case (.string?, .string(let text)), (nil, .string(let text)): return text.unicodeScalars.count <= 6000
    case (.boolean?, .bool), (nil, .bool): return true
    case (.integer?, .number(let number)):
        return !number.rawValue.contains(".") && !number.rawValue.lowercased().contains("e") &&
            Int64(number.rawValue).map { (-9_007_199_254_740_991...9_007_199_254_740_991).contains($0) } == true
    case (.number?, .number(let number)), (nil, .number(let number)):
        return argumentNumberWithinRange(number) &&
            Double(number.rawValue).map { $0.isFinite && abs($0) <= 9_007_199_254_740_992 } == true
    case (.user?, .string(let id)), (.channel?, .string(let id)), (.role?, .string(let id)),
         (.mentionable?, .string(let id)), (.attachment?, .string(let id)):
        return !id.isEmpty && id.utf8.allSatisfy { (48...57).contains($0) } && UInt64(id) != nil
    default: return false
    }
}

/// Compares validated choice scalars by wire meaning while retaining exact lexemes elsewhere.
/// - Parameters:
///   - lhs: Validated submitted string or finite in-range number.
///   - rhs: Existing-model choice string or finite in-range number.
/// - Returns: Exact string or mathematical decimal equality, so `1` and `1.0` agree without rounding fractions.
private func argumentScalarEqual(_ lhs: JSONValue, _ rhs: JSONValue) -> Bool {
    switch (lhs, rhs) {
    case (.number(let lhs), .number(let rhs)): argumentCompareNumbers(lhs, rhs) == 0
    default: lhs == rhs
    }
}

/// Encodes bounded author source coordinates for deterministic shared metadata accounting.
/// - Parameter source: Coordinate already bounded by descriptor/schema admission.
/// - Returns: File label and exact decimal line/column strings; strings avoid fallible numeric construction.
private func argumentSourceMetadata(_ source: DefinitionSourceLocation) -> JSONValue {
    .object(["file_id": .string(source.fileID), "line": .string(String(source.line)),
             "column": .string(String(source.column))])
}

/// Bounds an author coordinate without file access or retaining arbitrarily large source labels.
/// - Parameter source: Original coordinate; one-based line/column values are preserved exactly.
/// - Returns: The coordinate with a control-free file identifier of at most 256 UTF-8 bytes.
private func argumentBoundedSource(_ source: DefinitionSourceLocation) -> DefinitionSourceLocation {
    .init(fileID: argumentBoundedLabel(source.fileID, maximumBytes: 256), line: source.line, column: source.column)
}

/// Copies complete Unicode scalars into a finite label while omitting control characters.
/// - Parameters:
///   - value: Author or declared identity label, never a submitted scalar value.
///   - maximumBytes: Nonnegative fixed bound chosen by the diagnostic or descriptor implementation.
/// - Returns: A scalar-aligned prefix within the UTF-8 bound, with ASCII controls omitted.
private func argumentBoundedLabel(_ value: String, maximumBytes: Int) -> String {
    var result = ""
    var count = 0
    for scalar in value.unicodeScalars {
        guard scalar.value >= 32, scalar.value != 127 else { continue }
        let part = String(scalar)
        guard part.utf8.count <= maximumBytes - count else { break }
        result.append(part)
        count += part.utf8.count
    }
    return result
}
