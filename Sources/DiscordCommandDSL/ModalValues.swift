import DiscordCore
import DiscordModels

/// Admitted modal leaf values. Container/display components never enter this typed value space.
public enum ModalInput: Sendable, Equatable {
    case text(String)
    case selection([String])
    case radio(String?)
    case checked(Bool)
}

/// A synchronous modal codec; it performs no hydration, handler execution, persistence or I/O.
public protocol ModalValue: Sendable {
    static var modalComponentTypes: [ComponentType] {
        /// Returns the finite supported leaf kinds; the first is the default field kind.
        get
    }
    static var acceptsMissingModalInput: Bool {
        /// Reports whether omission is accepted separately from the input's value semantics.
        get
    }
    /// Converts one completely admitted modal leaf into an invocation-local value.
    /// - Parameter input: Missing leaf or validated scalar/selection without raw container fields.
    /// - Returns: Fresh decoded value without related-resource hydration.
    /// - Throws: Local conversion errors; built-in codecs use sanitized `ArgumentValueError` cases.
    static func decodeModalInput(_ input: ModalInput?) throws -> Self
}

public extension ModalValue {
    /// Requires a present field unless the codec explicitly accepts omission.
    static var acceptsMissingModalInput: Bool { false }
}

extension String: ModalValue {
    /// Accepts a text input or a selected radio value; text input is the default field kind.
    public static var modalComponentTypes: [ComponentType] { [.textInput, .radioGroup] }

    /// Preserves exact unnormalized text from an admitted text or radio field.
    /// - Parameter input: Present text/radio value; an unselected radio is an explicit null failure.
    /// - Returns: Exact submitted Unicode text, including an empty text input.
    /// - Throws: Missing, nullValue, or wrongKind for incompatible scalar families.
    public static func decodeModalInput(_ input: ModalInput?) throws -> String {
        switch input {
        case .text(let value), .radio(.some(let value)): return value
        case .radio(.none): throw ArgumentValueError.nullValue
        case .none: throw ArgumentValueError.missing
        default: throw ArgumentValueError.wrongKind
        }
    }
}

extension Bool: ModalValue {
    /// Accepts the explicit checked state of a checkbox.
    public static var modalComponentTypes: [ComponentType] { [.checkbox] }

    /// Decodes an explicit checked/unchecked state without truthiness coercion.
    /// - Parameter input: Present boolean checkbox state.
    /// - Returns: The exact submitted state, including false.
    /// - Throws: Missing or wrongKind for omission or another leaf family.
    public static func decodeModalInput(_ input: ModalInput?) throws -> Bool {
        guard let input else { throw ArgumentValueError.missing }
        guard case .checked(let value) = input else { throw ArgumentValueError.wrongKind }
        return value
    }
}

extension Optional: ModalValue where Wrapped: ModalValue {
    /// Reuses the wrapped codec's finite allowed leaf types and default.
    public static var modalComponentTypes: [ComponentType] { Wrapped.modalComponentTypes }
    /// Accepts an omitted field and a radio group's documented unselected null state.
    public static var acceptsMissingModalInput: Bool { true }

    /// Decodes omission or unselected radio as nil and forwards all present values unchanged.
    /// - Parameter input: Admitted leaf value or nil for an omitted declared field.
    /// - Returns: Nil for omission/unselected radio; otherwise the wrapped local value.
    /// - Throws: Wrapped codec failures for incompatible present input.
    public static func decodeModalInput(_ input: ModalInput?) throws -> Self {
        guard let input else { return nil }
        if case .radio(nil) = input { return nil }
        return try Wrapped.decodeModalInput(input)
    }
}

/// Selected strings or exact resource/upload snowflakes from one modal field. Resolved objects
/// remain on the immutable interaction snapshot and are never fetched automatically.
public struct ModalSelections: ModalValue, Equatable {
    public let values: [String]
    /// Supports all current select families, uploads and checkbox groups; string select is the default.
    public static var modalComponentTypes: [ComponentType] {
        [.stringSelect, .userSelect, .roleSelect, .mentionableSelect, .channelSelect, .fileUpload, .checkboxGroup]
    }

    /// Retains explicit local values without claiming remote existence, authorization or validation.
    /// - Parameter values: Caller-owned strings; submitted values are separately admitted by the schema.
    public init(_ values: [String]) { self.values = values }

    /// Wraps a fully admitted selection without network lookup or canonicalization.
    /// - Parameter input: Present selection array, including an explicitly empty selection.
    /// - Returns: Values in wire order; no sets or sorting alter application meaning.
    /// - Throws: Missing or wrongKind for omission or a scalar/checkbox leaf.
    public static func decodeModalInput(_ input: ModalInput?) throws -> Self {
        guard let input else { throw ArgumentValueError.missing }
        guard case .selection(let values) = input else { throw ArgumentValueError.wrongKind }
        return Self(values)
    }
}

/// One typed modal field descriptor. Explicit exact IDs do not interpolate or capture arbitrary input.
public struct ModalField<Value: ModalValue>: Sendable {
    public let customID: String
    public let componentType: ComponentType

    /// Validates finite field metadata without decoding input or invoking user behavior.
    /// - Parameters:
    ///   - customID: Exact identifier of 1...100 Unicode scalars.
    ///   - componentType: Optional explicit kind supported by the codec; nil selects its first kind.
    /// - Throws: Invalid-value for invalid IDs, empty codec kinds or unsupported selected kind.
    public init(customID: String, componentType: ComponentType? = nil) throws {
        let supported = Value.modalComponentTypes
        guard (1...100).contains(customID.unicodeScalars.count),
              let kind = componentType ?? supported.first,
              supported.contains(kind), [3, 4, 5, 6, 7, 8, 19, 21, 22, 23].contains(kind.rawValue)
        else { throw DiscordError.validation(.invalidValue) }
        self.customID = customID; self.componentType = kind
    }

    /// Erases the descriptor's result type while retaining its exact ID/kind and synchronous codec.
    public var erased: AnyModalField {
        AnyModalField(customID: customID, componentType: componentType,
            optional: Value.acceptsMissingModalInput, valueType: ObjectIdentifier(Value.self), decode: { try Value.decodeModalInput($0) })
    }
}

/// Finite erased descriptor consumed only by `ModalSchema`; no handler behavior is stored here.
public struct AnyModalField: Sendable {
    let customID: String
    let componentType: ComponentType
    let optional: Bool
    let valueType: ObjectIdentifier
    let decode: @Sendable (ModalInput?) throws -> any Sendable

    /// Stores the already validated descriptor and local conversion closure without executing it.
    /// - Parameters:
    ///   - customID: Exact validated field identity.
    ///   - componentType: Known supported modal leaf kind.
    ///   - optional: Whether missing fields are accepted.
    ///   - valueType: Exact generic codec identity, preventing implicit optional promotion during lookup.
    ///   - decode: Synchronous bounded codec; errors propagate without retaining raw values.
    fileprivate init(customID: String, componentType: ComponentType, optional: Bool, valueType: ObjectIdentifier,
        decode: @escaping @Sendable (ModalInput?) throws -> any Sendable) {
        self.customID = customID; self.componentType = componentType
        self.optional = optional; self.valueType = valueType; self.decode = decode
    }
}

/// Invocation-local decoded values, available only inside the schema's synchronous aggregate constructor.
public struct ModalDecodedValues: Sendable {
    fileprivate let values: [String: any Sendable]
    fileprivate let kinds: [String: ComponentType]
    fileprivate let types: [String: ObjectIdentifier]

    /// Reads one declared field with its original value type and exact component kind.
    /// - Parameter field: Same descriptor identity/kind used when declaring this schema.
    /// - Returns: Its decoded value, including nil optional values and empty selections.
    /// - Throws: WrongKind if the descriptor was not part of this schema or its generic type differs.
    public func value<Value: ModalValue>(for field: ModalField<Value>) throws -> Value {
        guard kinds[field.customID] == field.componentType, types[field.customID] == ObjectIdentifier(Value.self),
              let value = values[field.customID] as? Value
        else { throw ArgumentValueError.wrongKind }
        return value
    }
}

/// A typed modal submission aggregate with a finite schema; it creates fresh values for each invocation.
public protocol ModalValues: Sendable {
    static var schema: ModalSchema<Self> {
        /// Returns a deterministic inert schema without tasks, handler work or I/O.
        /// - Throws: Local descriptor/schema errors before contribution construction succeeds.
        get throws
    }
}

/// Bounded modal field schema and invocation-local aggregate constructor, independent of outgoing modal UI.
/// Every submitted field must be declared. Legacy rows and current label children share exact decoding.
public struct ModalSchema<Values: Sendable>: Sendable {
    private let fields: [AnyModalField]
    private let construct: @Sendable (ModalDecodedValues) throws -> Values
    let metadata: JSONValue

    /// Validates at most five unique descriptors without constructing values or running handlers.
    /// - Parameters:
    ///   - fields: Finite descriptors in deterministic authoring order; empty permits display-only submissions.
    ///   - construct: Synchronous fresh-value constructor, invoked once after all submitted fields pass admission.
    /// - Throws: Invalid-value for duplicate IDs or more than five fields.
    public init(fields: [AnyModalField], construct: @escaping @Sendable (ModalDecodedValues) throws -> Values) throws {
        guard fields.count <= 5, Set(fields.map(\.customID)).count == fields.count
        else { throw DiscordError.validation(.invalidValue) }
        self.fields = fields; self.construct = construct
        metadata = .array(try fields.map {
            .object(["custom_id": .string($0.customID), "type": .number(try JSONNumber(rawValue: String($0.componentType.rawValue))),
                "optional": .bool($0.optional)])
        })
    }

    /// Admits the complete finite tree before any codec, aggregate construction or handler invocation.
    /// - Parameter data: Bounded existing-model modal data from the exact authenticated interaction.
    /// - Returns: Fresh typed values after complete structural/type/ID/required-field admission.
    /// - Throws: Invalid-value for unsupported nesting/types, duplicate IDs, bounds, wrong kinds or undeclared
    ///   fields; codec/constructor errors propagate. No hydration, acknowledgement, retry or I/O occurs.
    public func decode(_ data: InteractionModalData) throws -> Values {
        let inputs = try modalInputs(data.components)
        let descriptors = Dictionary(uniqueKeysWithValues: fields.map { ($0.customID, $0) })
        for (id, submitted) in inputs {
            guard let field = descriptors[id], field.componentType == submitted.kind
            else { throw DiscordError.validation(.invalidValue) }
        }
        for field in fields where !field.optional && inputs[field.customID] == nil {
            throw ArgumentValueError.missing
        }
        var decoded: [String: any Sendable] = [:]
        for field in fields { decoded[field.customID] = try field.decode(inputs[field.customID]?.value) }
        return try construct(ModalDecodedValues(values: decoded,
            kinds: Dictionary(uniqueKeysWithValues: fields.map { ($0.customID, $0.componentType) }),
            types: Dictionary(uniqueKeysWithValues: fields.map { ($0.customID, $0.valueType) })))
    }
}

/// Inspects a modal's two-level current or legacy shape before invoking any application codec.
/// - Parameter roots: One through five display, label, or legacy row roots from a parser-bounded tree.
/// - Returns: Unique exact field IDs with their known kind and admitted value.
/// - Throws: Invalid-value for unsupported/ambiguous nesting, duplicate IDs, absent values or excessive inputs.
private func modalInputs(_ roots: [MessageComponent]) throws -> [String: (kind: ComponentType, value: ModalInput)] {
    guard (1...5).contains(roots.count) else { throw DiscordError.validation(.invalidValue) }
    var result: [String: (kind: ComponentType, value: ModalInput)] = [:]
    var numericIDs: Set<UInt32> = []
    for root in roots {
        try modalNumericID(root, seen: &numericIDs)
        guard case .absent = root.value, case .absent = root.values else { throw DiscordError.validation(.invalidValue) }
        let child: MessageComponent
        switch root.type.knownValue {
        case .actionRow:
            guard case .value(let children) = root.components, children.count == 1,
                  children[0].type.knownValue == .textInput, case .absent = root.component,
                  case .absent = root.accessory, case .absent = root.customID
            else { throw DiscordError.validation(.invalidValue) }
            child = children[0]
        case .label:
            guard case .value(let value) = root.component, case .absent = root.components,
                  case .absent = root.accessory, case .absent = root.customID
            else { throw DiscordError.validation(.invalidValue) }
            child = value
        case .textDisplay:
            guard case .absent = root.components, case .absent = root.component,
                  case .absent = root.accessory, case .absent = root.customID,
                  case .absent = root.value, case .absent = root.values
            else { throw DiscordError.validation(.invalidValue) }
            continue
        default: throw DiscordError.validation(.invalidValue)
        }
        try modalNumericID(child, seen: &numericIDs)
        guard case .value(let id) = child.customID, (1...100).contains(id.unicodeScalars.count),
              result[id] == nil, let kind = child.type.knownValue,
              case .absent = child.components, case .absent = child.component, case .absent = child.accessory
        else { throw DiscordError.validation(.invalidValue) }
        let input: ModalInput
        switch kind {
        case .textInput:
            guard case .value(.text(let text)) = child.value, text.unicodeScalars.count <= 4_000,
                  case .absent = child.values else { throw DiscordError.validation(.invalidValue) }
            input = .text(text)
        case .radioGroup:
            guard case .absent = child.values else { throw DiscordError.validation(.invalidValue) }
            switch child.value {
            case .null: input = .radio(nil)
            case .value(.text(let text)) where text.unicodeScalars.count <= 100: input = .radio(text)
            default: throw DiscordError.validation(.invalidValue)
            }
        case .checkbox:
            guard case .value(.checked(let checked)) = child.value, case .absent = child.values
            else { throw DiscordError.validation(.invalidValue) }
            input = .checked(checked)
        case .stringSelect, .userSelect, .roleSelect, .mentionableSelect, .channelSelect, .fileUpload, .checkboxGroup:
            guard case .value(let values) = child.values, case .absent = child.value,
                  values.count <= ([ComponentType.fileUpload, .checkboxGroup].contains(kind) ? 10 : 25),
                  Set(values).count == values.count, values.allSatisfy({ $0.unicodeScalars.count <= 100 })
            else { throw DiscordError.validation(.invalidValue) }
            if [.userSelect, .roleSelect, .mentionableSelect, .channelSelect, .fileUpload].contains(kind) {
                guard values.allSatisfy({ UserID($0) != nil }) else { throw DiscordError.validation(.invalidValue) }
            }
            input = .selection(values)
        default: throw DiscordError.validation(.invalidValue)
        }
        result[id] = (kind, input)
    }
    return result
}

/// Rejects duplicate explicit nonzero component IDs without treating zero as an assigned ID.
/// - Parameters:
///   - component: Current parser-bounded root or leaf being admitted.
///   - seen: Global per-submission numeric identity set, mutated synchronously.
/// - Throws: Invalid-value for a repeated nonzero ID; omitted and zero IDs remain valid.
private func modalNumericID(_ component: MessageComponent, seen: inout Set<UInt32>) throws {
    if case .value(let id) = component.id, id != 0, !seen.insert(id).inserted {
        throw DiscordError.validation(.invalidValue)
    }
}
