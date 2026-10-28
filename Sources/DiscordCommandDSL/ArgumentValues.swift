// File: Sources/DiscordCommandDSL/ArgumentValues.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import DiscordModels

/// Sanitized failures from typed argument conversion; submitted values and resolved objects are never retained.
public enum ArgumentValueError: Error, Sendable, Equatable {
    /// A required argument was omitted.
    case missing
    /// Explicit JSON null is forbidden by this codec.
    case nullValue
    /// The JSON scalar does not match the declared option kind.
    case wrongKind
    /// An integer or number lies outside Discord's documented range or the Swift representation.
    case outOfRange
    /// A declared choice schema is invalid or the submitted value is not one of its cases.
    case invalidChoice
    /// A snowflake is malformed or a resolved object's identifier contradicts its dictionary key.
    case invalidIdentifier
}

/// Synchronous scalar conversion shared by manual schemas and later authoring macros.
///
/// Implementations must perform bounded local work without fetching resources, creating tasks,
/// or invoking handlers. The schema validates the declared wire kind before calling a codec.
/// A codec may impose stronger local rules, but must preserve omitted versus explicit-null input.
public protocol ArgumentValue: Sendable {
    /// Existing API v10 leaf kind; subcommands and groups are not argument codecs.
    static var optionType: ApplicationCommandOptionType {
        /// Returns the deterministic existing leaf discriminator without tasks, I/O or handler execution.
        get
    }
    /// Deterministic, validated choices in declaration order; empty means unrestricted.
    /// - Throws: Local schema-validation errors for invalid user-defined choices.
    static var choices: [ApplicationCommandChoiceCreate] {
        /// Returns finite validated choices in declaration order, or an empty unrestricted list.
        /// - Throws: Local schema-validation errors; callers must reject failed schemas before registration.
        get throws
    }
    /// Whether omission is accepted; optional wrappers return true.
    static var isOptional: Bool {
        /// Returns whether absent input is accepted, without changing explicit-null handling or performing I/O.
        get
    }

    /// Converts one retained argument without hydrating related resources or altering input.
    /// - Parameters:
    ///   - value: Omission, explicit null, or the exact submitted scalar.
    ///   - resolved: Optional partial resources from this same interaction; no network fallback occurs.
    /// - Returns: The typed local value, with partial resource presence retained where applicable.
    /// - Throws: `ArgumentValueError` or a custom codec's local validation error. No suspension occurs.
    static func decodeArgument(_ value: Field<JSONValue>, resolved: Field<InteractionResolvedData>) throws -> Self

    /// Encodes a local value for explicit defaults and deterministic comparisons; nil optionals omit it.
    /// - Throws: Local validation errors when the in-memory value cannot be represented by this option.
    var argumentValue: Field<JSONValue> {
        /// Returns a deterministic scalar or explicit presence state without fetching related resources.
        /// - Throws: Local validation errors for values incompatible with this codec's declared option kind.
        get throws
    }
}

public extension ArgumentValue {
    /// Supplies no enumerated restriction for ordinary scalar/reference codecs.
    static var choices: [ApplicationCommandChoiceCreate] {
        /// Returns an empty unrestricted choice list synchronously; this default implementation never throws.
        get throws { [] }
    }
    /// Requires a present argument unless the codec explicitly supports omission.
    static var isOptional: Bool { false }
}

extension String: ArgumentValue {
    /// Declares a Discord string option without implicit coercion.
    public static var optionType: ApplicationCommandOptionType { .string }

    /// Decodes exact Unicode string content; length constraints belong to the option schema.
    /// - Parameters:
    ///   - value: Required string scalar; omission and null are distinct failures.
    ///   - resolved: Ignored partial resources; strings never trigger hydration.
    /// - Returns: The unnormalized submitted string, including empty text.
    /// - Throws: `ArgumentValueError.missing`, `.nullValue`, or `.wrongKind`.
    public static func decodeArgument(_ value: Field<JSONValue>, resolved: Field<InteractionResolvedData>) throws -> Self {
        guard case .string(let text) = try argumentScalar(value) else { throw ArgumentValueError.wrongKind }
        return text
    }

    /// Returns the exact string without normalization, I/O, or quoting changes in its JSON representation.
    public var argumentValue: Field<JSONValue> { .value(.string(self)) }
}

extension Bool: ArgumentValue {
    /// Declares a boolean option; numeric zero/one and strings are never coerced.
    public static var optionType: ApplicationCommandOptionType { .boolean }

    /// Converts only a present JSON boolean.
    /// - Parameters:
    ///   - value: Required boolean, preserving omitted and null error distinctions.
    ///   - resolved: Ignored local resource data.
    /// - Returns: The submitted boolean.
    /// - Throws: `ArgumentValueError.missing`, `.nullValue`, or `.wrongKind`.
    public static func decodeArgument(_ value: Field<JSONValue>, resolved: Field<InteractionResolvedData>) throws -> Self {
        guard case .bool(let flag) = try argumentScalar(value) else { throw ArgumentValueError.wrongKind }
        return flag
    }

    /// Returns the exact JSON boolean without allocating work or consulting resources.
    public var argumentValue: Field<JSONValue> { .value(.bool(self)) }
}

extension Int64: ArgumentValue {
    /// Declares an exact integer option in Discord's inclusive ±(2^53-1) range.
    public static var optionType: ApplicationCommandOptionType { .integer }

    /// Parses an integer lexeme directly, avoiding floating-point rounding of extreme values.
    /// - Parameters:
    ///   - value: Required JSON integer with no decimal point or exponent, matching existing model validation.
    ///   - resolved: Ignored local resource data.
    /// - Returns: The exact signed integer, including canonical numeric zero for `-0`.
    /// - Throws: Missing/null/wrong-kind errors or `.outOfRange` outside ±(2^53-1).
    public static func decodeArgument(_ value: Field<JSONValue>, resolved: Field<InteractionResolvedData>) throws -> Self {
        guard case .number(let number) = try argumentScalar(value),
              !number.rawValue.contains("."), !number.rawValue.lowercased().contains("e")
        else { throw ArgumentValueError.wrongKind }
        guard let result = Int64(number.rawValue), (-9_007_199_254_740_991...9_007_199_254_740_991).contains(result)
        else { throw ArgumentValueError.outOfRange }
        return result
    }

    /// Encodes the exact integer after enforcing Discord's safe integer range.
    /// - Throws: `ArgumentValueError.outOfRange` outside inclusive ±(2^53-1).
    public var argumentValue: Field<JSONValue> {
        /// Returns an exact decimal integer scalar without rounding or side effects.
        /// - Throws: `ArgumentValueError.outOfRange` outside inclusive ±(2^53-1); valid decimal construction cannot fail.
        get throws {
            guard (-9_007_199_254_740_991...9_007_199_254_740_991).contains(self) else { throw ArgumentValueError.outOfRange }
            return .value(.number(try JSONNumber(rawValue: String(self))))
        }
    }
}

extension Int: ArgumentValue {
    /// Declares an integer option bounded by both Discord and the platform's signed integer range.
    public static var optionType: ApplicationCommandOptionType { .integer }

    /// Decodes exact integer text before checking the platform representation.
    /// - Parameters:
    ///   - value: Required integer scalar; decimal/exponent spellings are rejected.
    ///   - resolved: Ignored local resource data.
    /// - Returns: The exact integer without floating-point conversion.
    /// - Throws: Missing/null/wrong-kind errors or `.outOfRange` for Discord/platform overflow.
    public static func decodeArgument(_ value: Field<JSONValue>, resolved: Field<InteractionResolvedData>) throws -> Self {
        let result = try Int64.decodeArgument(value, resolved: resolved)
        guard let integer = Int(exactly: result) else { throw ArgumentValueError.outOfRange }
        return integer
    }

    /// Encodes an exact decimal integer within Discord's safe range.
    /// - Throws: `ArgumentValueError.outOfRange` when a platform integer exceeds Discord's bound.
    public var argumentValue: Field<JSONValue> {
        /// Returns the same exact scalar as the signed 64-bit codec after applying Discord's range admission.
        /// - Throws: `ArgumentValueError.outOfRange` when this platform integer exceeds inclusive ±(2^53-1).
        get throws { try Int64(self).argumentValue }
    }
}

extension Double: ArgumentValue {
    /// Declares an ordinary IEEE-754 number option in Discord's inclusive ±2^53 range.
    public static var optionType: ApplicationCommandOptionType { .number }

    /// Converts a finite numeric lexeme after exact decimal range admission.
    /// Range checking precedes rounding, so `9007199254740993` cannot round into the accepted boundary.
    /// Small fractions may round or underflow according to `Double`; use a custom codec for decimal exactness.
    /// - Parameters:
    ///   - value: Required JSON number, including fractional or exponent syntax.
    ///   - resolved: Ignored local resource data.
    /// - Returns: A finite double in ±2^53; negative zero remains representable.
    /// - Throws: Missing/null/wrong-kind errors or `.outOfRange` for numeric overflow or range violations.
    public static func decodeArgument(_ value: Field<JSONValue>, resolved: Field<InteractionResolvedData>) throws -> Self {
        guard case .number(let number) = try argumentScalar(value) else { throw ArgumentValueError.wrongKind }
        guard argumentNumberWithinRange(number), let result = Double(number.rawValue), result.isFinite,
              abs(result) <= 9_007_199_254_740_992 else { throw ArgumentValueError.outOfRange }
        return result
    }

    /// Encodes a finite double using Swift's round-trip numeric spelling.
    /// - Throws: `ArgumentValueError.outOfRange` for NaN, infinity, or magnitude greater than 2^53.
    public var argumentValue: Field<JSONValue> {
        /// Returns Swift's round-trip finite number spelling as an inert JSON scalar.
        /// - Throws: `ArgumentValueError.outOfRange` for NaN, infinities or magnitude above 2^53.
        get throws {
            guard isFinite, abs(self) <= 9_007_199_254_740_992 else { throw ArgumentValueError.outOfRange }
            return .value(.number(try JSONNumber(rawValue: String(self))))
        }
    }
}

extension Optional: ArgumentValue where Wrapped: ArgumentValue {
    /// Reuses the wrapped wire kind; omission does not create a new Discord option kind.
    public static var optionType: ApplicationCommandOptionType { Wrapped.optionType }
    /// Reuses wrapped declaration-order choices and their schema-validation failures.
    public static var choices: [ApplicationCommandChoiceCreate] {
        /// Returns the wrapped codec's deterministic validated choices without altering omission semantics.
        /// - Throws: Any local choice-schema validation error from the wrapped codec.
        get throws { try Wrapped.choices }
    }
    /// Marks the option as omittable independently from its wrapped codec's rules.
    public static var isOptional: Bool { true }

    /// Converts omission to nil while forwarding every present state, including explicit null, to the wrapped codec.
    /// - Parameters:
    ///   - value: An absent argument becomes nil; explicit null does not silently become omission.
    ///   - resolved: Same-interaction resources forwarded unchanged.
    /// - Returns: Nil for absence, otherwise a decoded wrapped value.
    /// - Throws: The wrapped codec's errors, including null rejection for built-in codecs.
    public static func decodeArgument(_ value: Field<JSONValue>, resolved: Field<InteractionResolvedData>) throws -> Self {
        if case .absent = value { return nil }
        return try .some(Wrapped.decodeArgument(value, resolved: resolved))
    }

    /// Omits nil and encodes present wrapped values, preserving custom explicit-null behavior.
    /// - Throws: Errors from the wrapped codec when a present value cannot be represented.
    public var argumentValue: Field<JSONValue> {
        /// Returns absence for nil or the wrapped codec's exact scalar/presence representation for a present value.
        /// - Throws: Any local encoding error from a present wrapped value; nil itself never throws.
        get throws {
            switch self {
            case .none: return .absent
            case .some(let value): return try value.argumentValue
            }
        }
    }
}

/// Opt-in string-backed choices; case order determines registration order without invoking application work.
/// Each declaration must contain 1...25 unique cases with valid 1...100-scalar display names and values at most 100 scalars.
public protocol StringArgumentChoice: ArgumentValue, RawRepresentable, CaseIterable where RawValue == String, AllCases: Sendable {
    /// Human-readable registration name; defaults to the exact raw value.
    var choiceName: String {
        /// Returns deterministic display text without tasks, I/O or registration; the choices getter validates its bounds.
        get
    }
}

public extension StringArgumentChoice {
    /// Declares the existing string option kind for every explicit choice case.
    static var optionType: ApplicationCommandOptionType { .string }
    /// Uses the raw value as display text unless the conforming enum overrides this property.
    var choiceName: String { rawValue }

    /// Validates all cases before producing deterministic registration choices.
    /// - Throws: `ArgumentValueError.invalidChoice` for empty/excessive/duplicate cases or invalid display/value text.
    static var choices: [ApplicationCommandChoiceCreate] {
        /// Returns 1...25 unique, existing-model-validated choices in explicit declaration order.
        /// - Throws: `ArgumentValueError.invalidChoice` for empty/excessive/duplicate cases or invalid names/raw values.
        get throws {
            var result: [ApplicationCommandChoiceCreate] = []
            var values = Set<String>()
            for choice in allCases {
                guard result.count < 25, values.insert(choice.rawValue).inserted else { throw ArgumentValueError.invalidChoice }
                do { result.append(try ApplicationCommandChoiceCreate(name: choice.choiceName, value: .string(choice.rawValue))) }
                catch { throw ArgumentValueError.invalidChoice }
            }
            guard !result.isEmpty else { throw ArgumentValueError.invalidChoice }
            return result
        }
    }

    /// Decodes only explicitly enumerated cases after validating the declared choice schema.
    /// - Parameters:
    ///   - value: Required string scalar; no case folding or normalization occurs.
    ///   - resolved: Ignored partial resources.
    /// - Returns: The matching explicit case.
    /// - Throws: Missing/null/wrong-kind errors or `.invalidChoice` for schema/submitted-case failures.
    static func decodeArgument(_ value: Field<JSONValue>, resolved: Field<InteractionResolvedData>) throws -> Self {
        _ = try choices
        let text = try String.decodeArgument(value, resolved: resolved)
        guard let result = Self(rawValue: text), allCases.contains(where: { $0.rawValue == text })
        else { throw ArgumentValueError.invalidChoice }
        return result
    }

    /// Encodes a declared choice after validating its membership and full registration schema.
    /// - Throws: `ArgumentValueError.invalidChoice` for invalid schema or a manually constructed noncase value.
    var argumentValue: Field<JSONValue> {
        /// Returns the exact raw string only after validating schema and explicit case membership.
        /// - Throws: `ArgumentValueError.invalidChoice` when schema validation or case membership fails.
        get throws {
            _ = try Self.choices
            guard Self.allCases.contains(where: { $0.rawValue == rawValue }) else { throw ArgumentValueError.invalidChoice }
            return .value(.string(rawValue))
        }
    }
}

/// A selected user ID and same-interaction partial user/member observations; no resource is fetched.
public struct UserReference: ArgumentValue, Equatable {
    public let id: UserID
    public let user: Field<MessageAuthor>
    public let member: Field<MessageRelatedResource>
    /// Declares the existing user option kind without requiring resolved data.
    public static var optionType: ApplicationCommandOptionType { .user }

    /// Retains an explicit local user reference without I/O or existence/permission checks.
    /// - Parameters:
    ///   - id: Exact unsigned user snowflake, including all 64 bits.
    ///   - user: Same-interaction partial user observation; absent by default.
    ///   - member: Same-interaction partial guild member observation; absent by default.
    public init(id: UserID, user: Field<MessageAuthor> = .absent, member: Field<MessageRelatedResource> = .absent) {
        self.id = id; self.user = user; self.member = member
    }

    /// Resolves only dictionary observations supplied with this interaction, preserving missing/null categories.
    /// - Parameters:
    ///   - value: Required decimal user snowflake string; no numeric coercion occurs.
    ///   - resolved: Same-interaction partial maps, never an instruction to hydrate.
    /// - Returns: User/member fields at the selected ID, or their retained missing/null states.
    /// - Throws: Missing/null/wrong-kind/invalid-identifier errors, including contradictory resolved user IDs.
    public static func decodeArgument(_ value: Field<JSONValue>, resolved: Field<InteractionResolvedData>) throws -> Self {
        let text = try argumentIdentifier(value)
        let id = UserID(text)!
        let user = argumentResolved(resolved, map: \.users, identifier: text)
        if case .value(let object) = user, object.id != id { throw ArgumentValueError.invalidIdentifier }
        return Self(id: id, user: user, member: argumentResolved(resolved, map: \.members, identifier: text))
    }

    /// Encodes the selected identifier as a string; partial observations do not enter an option scalar.
    public var argumentValue: Field<JSONValue> { .value(.string(id.description)) }
}

/// A selected channel ID and its optional partial observation; no complete-channel shape or authority is inferred.
public struct ChannelReference: ArgumentValue, Equatable {
    public let id: ChannelID
    public let channel: Field<MessageRelatedResource>
    /// Declares the existing channel option kind, including partial/category channels.
    public static var optionType: ApplicationCommandOptionType { .channel }

    /// Retains an explicit channel ID and independently supplied partial data.
    /// - Parameters:
    ///   - id: Exact unsigned channel identifier.
    ///   - channel: Partial observation, absent by default; construction performs no fetching or authorization.
    public init(id: ChannelID, channel: Field<MessageRelatedResource> = .absent) {
        self.id = id; self.channel = channel
    }

    /// Selects the partial channel at the supplied snowflake while retaining resource presence.
    /// - Parameters:
    ///   - value: Required decimal channel ID string.
    ///   - resolved: Same-interaction partial maps; absent/null states are preserved.
    /// - Returns: The typed ID and local partial channel observation without hydration.
    /// - Throws: Missing/null/wrong-kind/invalid-identifier errors, including contradictory partial IDs.
    public static func decodeArgument(_ value: Field<JSONValue>, resolved: Field<InteractionResolvedData>) throws -> Self {
        let text = try argumentIdentifier(value)
        let channel = argumentResolved(resolved, map: \.channels, identifier: text)
        try argumentValidateRelatedID(channel, identifier: text)
        return Self(id: ChannelID(text)!, channel: channel)
    }

    /// Encodes only the canonical decimal channel ID without projecting partial data.
    public var argumentValue: Field<JSONValue> { .value(.string(id.description)) }
}

/// A selected role ID and optional same-interaction partial observation; permission authority remains external.
public struct RoleReference: ArgumentValue, Equatable {
    public let id: RoleID
    public let role: Field<MessageRelatedResource>
    /// Declares the existing role option kind without imposing a complete role schema.
    public static var optionType: ApplicationCommandOptionType { .role }

    /// Retains a role reference without checking server existence or permissions.
    /// - Parameters:
    ///   - id: Exact unsigned role identifier.
    ///   - role: Partial local role observation; defaults to absent.
    public init(id: RoleID, role: Field<MessageRelatedResource> = .absent) {
        self.id = id; self.role = role
    }

    /// Selects only the same-interaction partial role at the exact submitted identifier.
    /// - Parameters:
    ///   - value: Required decimal role ID string; malformed or overflowing IDs fail.
    ///   - resolved: Optional partial maps; no lookup is issued outside the supplied data.
    /// - Returns: The role ID with retained observation presence.
    /// - Throws: Missing/null/wrong-kind/invalid-identifier errors, including contradictory role IDs.
    public static func decodeArgument(_ value: Field<JSONValue>, resolved: Field<InteractionResolvedData>) throws -> Self {
        let text = try argumentIdentifier(value)
        let role = argumentResolved(resolved, map: \.roles, identifier: text)
        try argumentValidateRelatedID(role, identifier: text)
        return Self(id: RoleID(text)!, role: role)
    }

    /// Encodes only the canonical decimal role ID without authorization or resource fetching.
    public var argumentValue: Field<JSONValue> { .value(.string(id.description)) }
}

/// A selected attachment ID with optional resolved metadata; URLs remain inert untrusted strings.
public struct AttachmentReference: ArgumentValue, Equatable {
    public let id: AttachmentID
    public let attachment: Field<MessageAttachment>
    /// Declares the existing attachment option kind; downloading and content validation remain application-owned.
    public static var optionType: ApplicationCommandOptionType { .attachment }

    /// Retains an attachment ID and optional metadata without opening any URL.
    /// - Parameters:
    ///   - id: Exact unsigned attachment snowflake.
    ///   - attachment: Same-interaction attachment metadata; defaults to absent.
    public init(id: AttachmentID, attachment: Field<MessageAttachment> = .absent) {
        self.id = id; self.attachment = attachment
    }

    /// Selects only the attachment metadata supplied by this interaction.
    /// - Parameters:
    ///   - value: Required decimal attachment ID string.
    ///   - resolved: Partial resource maps; missing/null states remain distinct.
    /// - Returns: The selected ID and inert metadata without fetching its URLs.
    /// - Throws: Missing/null/wrong-kind/invalid-identifier errors, including contradictory attachment IDs.
    public static func decodeArgument(_ value: Field<JSONValue>, resolved: Field<InteractionResolvedData>) throws -> Self {
        let text = try argumentIdentifier(value)
        let id = AttachmentID(text)!
        let attachment = argumentResolved(resolved, map: \.attachments, identifier: text)
        if case .value(let object) = attachment, object.id != id { throw ArgumentValueError.invalidIdentifier }
        return Self(id: id, attachment: attachment)
    }

    /// Encodes only the canonical decimal attachment ID; no URL or file content enters the scalar.
    public var argumentValue: Field<JSONValue> { .value(.string(id.description)) }
}

/// Marker for a mentionable whose user-versus-role domain may remain unresolved.
public enum MentionableTag: Sendable {}
/// Exact unsigned mentionable ID; unresolved values are not guessed to be users or roles.
public typealias MentionableID = Snowflake<MentionableTag>

/// An unresolved-capable mentionable retaining independent user/member/role observations and presence states.
public struct MentionableReference: ArgumentValue, Equatable {
    public let id: MentionableID
    public let user: Field<MessageAuthor>
    public let member: Field<MessageRelatedResource>
    public let role: Field<MessageRelatedResource>
    /// Declares the existing mentionable option kind without inventing a domain for missing observations.
    public static var optionType: ApplicationCommandOptionType { .mentionable }

    /// Retains mentionable observations without selecting an authority or hydrating unknown data.
    /// - Parameters:
    ///   - id: Exact unsigned selected identifier.
    ///   - user: Same-interaction user observation, absent by default.
    ///   - member: Same-interaction member observation, absent by default.
    ///   - role: Same-interaction role observation, absent by default.
    public init(id: MentionableID, user: Field<MessageAuthor> = .absent,
                member: Field<MessageRelatedResource> = .absent, role: Field<MessageRelatedResource> = .absent) {
        self.id = id; self.user = user; self.member = member; self.role = role
    }

    /// Selects independent observations for a user-or-role ID without requiring complete resolved resources.
    /// - Parameters:
    ///   - value: Required decimal mentionable snowflake string.
    ///   - resolved: Same-interaction resources, with absent/null categories preserved independently.
    /// - Returns: The exact ID and available observations; missing data causes no hidden requests.
    /// - Throws: Missing/null/wrong-kind/invalid-identifier errors for malformed or contradictory resolved IDs.
    public static func decodeArgument(_ value: Field<JSONValue>, resolved: Field<InteractionResolvedData>) throws -> Self {
        let text = try argumentIdentifier(value)
        let user = argumentResolved(resolved, map: \.users, identifier: text)
        let role = argumentResolved(resolved, map: \.roles, identifier: text)
        if case .value(let object) = user, object.id.rawValue != UInt64(text)! { throw ArgumentValueError.invalidIdentifier }
        try argumentValidateRelatedID(role, identifier: text)
        return Self(id: MentionableID(text)!, user: user,
                    member: argumentResolved(resolved, map: \.members, identifier: text), role: role)
    }

    /// Encodes only the selected snowflake string, retaining domain uncertainty in local observations.
    public var argumentValue: Field<JSONValue> { .value(.string(id.description)) }
}

/// Extracts a required nonnull scalar while normalizing both explicit JSON-null representations to one error.
/// - Parameter field: Exact argument presence supplied by the interaction/schema.
/// - Returns: The present nonnull value without type coercion.
/// - Throws: `ArgumentValueError.missing` or `.nullValue`; type checks belong to the caller.
private func argumentScalar(_ field: Field<JSONValue>) throws -> JSONValue {
    switch field {
    case .absent: throw ArgumentValueError.missing
    case .null, .value(.null): throw ArgumentValueError.nullValue
    case .value(let value): return value
    }
}

/// Extracts one full-width decimal snowflake string without using a floating-point intermediate.
/// - Parameter value: Required argument presence; strings may contain leading zeroes, matching `Snowflake`.
/// - Returns: Exact original decimal spelling for resolved-map lookup.
/// - Throws: Missing/null/wrong-kind errors or `.invalidIdentifier` for nondigits, signs, whitespace or overflow.
private func argumentIdentifier(_ value: Field<JSONValue>) throws -> String {
    guard case .string(let text) = try argumentScalar(value) else { throw ArgumentValueError.wrongKind }
    guard UserID(text) != nil else { throw ArgumentValueError.invalidIdentifier }
    return text
}

/// Looks up a partial resource without flattening null/absence at either resolved-object or category level.
/// - Parameters:
///   - resolved: Whole interaction resource presence; explicit null propagates.
///   - map: The selected typed dictionary projection.
///   - identifier: Validated exact decimal ID; original spelling takes precedence over its canonical equivalent.
/// - Returns: The category's null/absent state, the matching value, or absent for a missing key.
private func argumentResolved<Value>(
    _ resolved: Field<InteractionResolvedData>, map: KeyPath<InteractionResolvedData, Field<[String: Value]>>,
    identifier: String
) -> Field<Value> {
    switch resolved {
    case .absent: return .absent
    case .null: return .null
    case .value(let object):
        switch object[keyPath: map] {
        case .absent: return .absent
        case .null: return .null
        case .value(let values):
            guard let result = values[identifier] ?? values[String(UInt64(identifier)!)] else { return .absent }
            return .value(result)
        }
    }
}

/// Rejects contradictory IDs on partial role/channel observations without requiring an ID field.
/// - Parameters:
///   - resource: Partial observation; missing/null objects or missing IDs remain accepted.
///   - identifier: Already validated selected decimal snowflake.
/// - Throws: `ArgumentValueError.invalidIdentifier` when a supplied partial ID is invalid or numerically different.
private func argumentValidateRelatedID(_ resource: Field<MessageRelatedResource>, identifier: String) throws {
    if case .value(let object) = resource, case .value(let text) = object.id {
        guard let id = UserID(text), id.rawValue == UInt64(identifier)! else { throw ArgumentValueError.invalidIdentifier }
    }
}

/// Compares a validated decimal lexeme with ±2^53 before any floating-point conversion.
/// Shared schema admission uses the same guard for custom codecs, preserving registration/decoding parity.
/// This linear scan uses bounded exponent accumulation and cannot overflow on enormous JSON exponents.
/// - Parameter number: Grammar-validated finite-syntax JSON number of any lexeme length.
/// - Returns: Whether its exact mathematical magnitude is at most 9,007,199,254,740,992.
func argumentNumberWithinRange(_ number: JSONNumber) -> Bool {
    let bytes = Array(number.rawValue.utf8)
    var mantissa: [UInt8] = []
    var decimalDigits = 0
    var index = bytes.first == 45 ? 1 : 0
    var fraction = false
    while index < bytes.count, bytes[index] != 69, bytes[index] != 101 {
        if bytes[index] == 46 { fraction = true }
        else {
            mantissa.append(bytes[index])
            if !fraction { decimalDigits += 1 }
        }
        index += 1
    }
    guard let firstNonzero = mantissa.firstIndex(where: { $0 != 48 }) else { return true }
    var exponent = 0
    var negativeExponent = false
    if index < bytes.count {
        index += 1
        if bytes[index] == 43 || bytes[index] == 45 {
            negativeExponent = bytes[index] == 45
            index += 1
        }
        let cap = bytes.count + 32
        while index < bytes.count {
            exponent = min(cap, exponent * 10 + Int(bytes[index] - 48))
            index += 1
        }
    }
    let integerDigits = decimalDigits - firstNonzero + (negativeExponent ? -exponent : exponent)
    if integerDigits < 16 { return true }
    if integerDigits > 16 { return false }
    let boundary = Array("9007199254740992".utf8)
    let significant = mantissa[firstNonzero...]
    for offset in 0..<max(boundary.count, significant.count) {
        let digit = offset < significant.count ? significant[significant.startIndex + offset] : 48
        let maximum = offset < boundary.count ? boundary[offset] : 48
        if digit < maximum { return true }
        if digit > maximum { return false }
    }
    return true
}

/// Compares exact mathematical JSON numbers without floating-point rounding or exponent overflow.
/// Fractional trailing zeroes, exponent spellings and signed zero compare numerically; lexeme equality remains unchanged.
/// Work and temporary storage are linear in the two input lexeme lengths, including arbitrarily long exponents.
/// - Parameters:
///   - lhs: Complete grammar-validated JSON number on the left.
///   - rhs: Complete grammar-validated JSON number on the right.
/// - Returns: Minus one, zero, or one when the left number is respectively smaller, equal, or greater.
func argumentCompareNumbers(_ lhs: JSONNumber, _ rhs: JSONNumber) -> Int {
    let left = ArgumentDecimalNumber(lhs)
    let right = ArgumentDecimalNumber(rhs)
    if left.digits.isEmpty, right.digits.isEmpty { return 0 }
    if left.digits.isEmpty { return right.negative ? 1 : -1 }
    if right.digits.isEmpty { return left.negative ? -1 : 1 }
    if left.negative != right.negative { return left.negative ? -1 : 1 }
    let direction = left.negative ? -1 : 1
    let exponentOrder = left.exponent.compared(to: right.exponent)
    if exponentOrder != 0 { return direction * exponentOrder }
    for index in 0..<max(left.digits.count, right.digits.count) {
        let leftDigit = index < left.digits.count ? left.digits[index] : 0
        let rightDigit = index < right.digits.count ? right.digits[index] : 0
        if leftDigit != rightDigit { return direction * (leftDigit < rightDigit ? -1 : 1) }
    }
    return 0
}

/// Internal scientific-decimal view with exact significant digits and an arbitrary-width decimal position.
private struct ArgumentDecimalNumber {
    let negative: Bool
    let digits: [UInt8]
    let exponent: ArgumentDecimalExponent

    /// Splits a valid numeric lexeme without decimal rounding, retaining zeros needed for exact digit comparisons.
    /// - Parameter number: Grammar-validated JSON number; this initializer performs no I/O or validation callbacks.
    init(_ number: JSONNumber) {
        let bytes = Array(number.rawValue.utf8)
        let negative = bytes.first == 45
        var index = negative ? 1 : 0
        var mantissa: [UInt8] = []
        var integerDigits = 0
        var fraction = false
        while index < bytes.count, bytes[index] != 69, bytes[index] != 101 {
            if bytes[index] == 46 { fraction = true }
            else {
                mantissa.append(bytes[index] - 48)
                if !fraction { integerDigits += 1 }
            }
            index += 1
        }
        var negativeExponent = false
        var exponentDigits: [UInt8] = []
        if index < bytes.count {
            index += 1
            if bytes[index] == 43 || bytes[index] == 45 {
                negativeExponent = bytes[index] == 45
                index += 1
            }
            exponentDigits = bytes[index...].map { $0 - 48 }
        }
        let initial = ArgumentDecimalExponent(negative: negativeExponent, digits: exponentDigits)
        if let firstNonzero = mantissa.firstIndex(where: { $0 != 0 }) {
            self.negative = negative
            digits = Array(mantissa[firstNonzero...])
            exponent = initial.adding(integerDigits - firstNonzero)
        } else {
            self.negative = false
            digits = []
            exponent = ArgumentDecimalExponent(negative: false, digits: [0])
        }
    }
}

/// An arbitrary-width signed decimal integer used only for exact scientific exponent ordering.
private struct ArgumentDecimalExponent {
    let negative: Bool
    let digits: [UInt8]

    /// Canonicalizes an unsigned digit sequence and suppresses negative zero.
    /// - Parameters:
    ///   - negative: Desired sign; ignored for zero magnitude.
    ///   - digits: Big-endian decimal digits in 0...9; empty denotes zero. Internal callers guarantee valid digits.
    init(negative: Bool, digits: [UInt8]) {
        let significant = Array(digits.drop(while: { $0 == 0 }))
        self.digits = significant.isEmpty ? [0] : significant
        self.negative = negative && !significant.isEmpty
    }

    /// Adds the finite mantissa decimal-position adjustment without truncating a large explicit exponent.
    /// - Parameter adjustment: Signed mantissa digit-position offset, bounded by that input's lexeme length.
    /// - Returns: The exact canonical arbitrary-width sum; this creates no runtime resource ownership.
    func adding(_ adjustment: Int) -> Self {
        let other = Self(negative: adjustment < 0, digits: String(adjustment.magnitude).utf8.map { $0 - 48 })
        if negative == other.negative {
            return Self(negative: negative, digits: argumentAddDigits(digits, other.digits))
        }
        let order = argumentCompareDigits(digits, other.digits)
        if order == 0 { return Self(negative: false, digits: [0]) }
        if order > 0 { return Self(negative: negative, digits: argumentSubtractDigits(digits, other.digits)) }
        return Self(negative: other.negative, digits: argumentSubtractDigits(other.digits, digits))
    }

    /// Orders signed arbitrary-width exponents using canonical magnitude digits.
    /// - Parameter other: Another canonical exponent; no numeric machine conversion occurs.
    /// - Returns: Minus one, zero, or one according to signed mathematical order.
    func compared(to other: Self) -> Int {
        if negative != other.negative { return negative ? -1 : 1 }
        return argumentCompareDigits(digits, other.digits) * (negative ? -1 : 1)
    }
}

/// Orders canonical nonempty unsigned decimal digit arrays without numeric conversion.
/// - Parameters:
///   - lhs: Big-endian 0...9 digits without leading zeros except canonical zero.
///   - rhs: Another canonical magnitude with the same digit invariant.
/// - Returns: Minus one, zero, or one according to unsigned mathematical order.
private func argumentCompareDigits(_ lhs: [UInt8], _ rhs: [UInt8]) -> Int {
    if lhs.count != rhs.count { return lhs.count < rhs.count ? -1 : 1 }
    for index in lhs.indices where lhs[index] != rhs[index] { return lhs[index] < rhs[index] ? -1 : 1 }
    return 0
}

/// Adds canonical unsigned decimal digit arrays with an explicit bounded carry.
/// - Parameters:
///   - lhs: Nonempty big-endian 0...9 magnitude digits.
///   - rhs: Nonempty big-endian 0...9 magnitude digits.
/// - Returns: Big-endian sum; its optional leading zero is normalized by the exponent initializer.
private func argumentAddDigits(_ lhs: [UInt8], _ rhs: [UInt8]) -> [UInt8] {
    let count = max(lhs.count, rhs.count)
    var result = Array(repeating: UInt8(0), count: count + 1)
    var carry = 0
    for offset in 0..<count {
        let left = offset < lhs.count ? Int(lhs[lhs.count - offset - 1]) : 0
        let right = offset < rhs.count ? Int(rhs[rhs.count - offset - 1]) : 0
        let sum = left + right + carry
        result[count - offset] = UInt8(sum % 10)
        carry = sum / 10
    }
    result[0] = UInt8(carry)
    return result
}

/// Subtracts one canonical magnitude from a known greater-or-equal magnitude using decimal borrow.
/// - Parameters:
///   - lhs: Nonempty big-endian magnitude at least as large as rhs, guaranteed by the caller's comparison.
///   - rhs: Nonempty big-endian smaller-or-equal magnitude digits in 0...9.
/// - Returns: Nonnegative difference; the exponent initializer removes leading zeroes.
private func argumentSubtractDigits(_ lhs: [UInt8], _ rhs: [UInt8]) -> [UInt8] {
    var result = Array(repeating: UInt8(0), count: lhs.count)
    var borrow = 0
    for offset in 0..<lhs.count {
        let index = lhs.count - offset - 1
        let right = offset < rhs.count ? Int(rhs[rhs.count - offset - 1]) : 0
        var difference = Int(lhs[index]) - right - borrow
        if difference < 0 { difference += 10; borrow = 1 }
        else { borrow = 0 }
        result[index] = UInt8(difference)
    }
    return result
}
