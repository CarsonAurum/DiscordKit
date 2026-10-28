// File: Sources/DiscordActivities/ActivityPayload.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import Foundation

/// A lossless typed Activity object, using the Embedded App SDK's own schemas rather than REST or RPC projections.
/// Complete original fields and unknown numeric spellings are retained; ordinary diagnostics always redact them.
public protocol ActivityPayload: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// Original complete object, including unknown keys and exact numeric lexemes.
    var rawFields: [String: JSONValue] {
        /// Reads the immutable original Activity object without reparsing, I/O or redaction.
        /// - Returns: All original keys and exact JSON number lexemes, including unknown fields.
        ///   Callers must deliberately protect private payload data when inspecting this value.
        get
    }

    /// Validates a bounded subtree and initializes the typed immutable projection.
    /// - Parameter value: An object already parsed under the surrounding frame's resource limits.
    /// - Throws: `ActivityCatalogError.invalidPayload` for absent required fields, forbidden nulls or incompatible types.
    /// Construction is synchronous and starts no tasks, performs no I/O and owns no external resources.
    init(value: JSONValue) throws
}

extension ActivityPayload {
    /// Parses complete untrusted object bytes under explicit bounds and then projects typed fields.
    /// - Parameters:
    ///   - data: One complete UTF-8 JSON object; duplicate keys are rejected.
    ///   - limits: Whole-object bounds; defaults to 1 MiB, depth 64 and 100,000 values.
    /// - Throws: JSON syntax/limit errors or sanitized projection errors. Unknown fields remain available in rawFields.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits))
    }

    /// Conceals user data, tokens, URLs, error strings and Activity secrets in interpolation.
    public var description: String { "ActivityPayload(redacted)" }
    /// Conceals payload contents in debugger descriptions.
    public var debugDescription: String { description }
    /// Prevents dump and recursive reflection from expanding sensitive payload storage.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}

/// Exact-type reader used only after whole-document JSON bounds have been enforced.
struct ActivityObject {
    let fields: [String: JSONValue]

    /// Requires an object without normalizing its original child values.
    /// - Parameter value: Already-bounded subtree.
    /// - Throws: Sanitized invalid-payload error for a nonobject, including null.
    init(_ value: JSONValue) throws {
        guard case .object(let fields) = value else { throw ActivityCatalogError.invalidPayload }
        self.fields = fields
    }

    /// Requires a present field and preserves explicit null for caller-specific handling.
    /// - Parameter key: Exact wire field name.
    /// - Returns: Original subtree.
    /// - Throws: Sanitized invalid-payload error for an omitted field.
    func required(_ key: String) throws -> JSONValue {
        guard let value = fields[key] else { throw ActivityCatalogError.invalidPayload }
        return value
    }

    /// Requires a string without coercing numbers or normalizing Unicode.
    /// - Parameter value: Original subtree.
    /// - Returns: Exact string, including empty strings when allowed by the schema.
    /// - Throws: Invalid-payload error for every nonstring, including null.
    static func string(_ value: JSONValue) throws -> String {
        guard case .string(let string) = value else { throw ActivityCatalogError.invalidPayload }
        return string
    }

    /// Requires a boolean without accepting numeric zero or one.
    /// - Parameter value: Original subtree.
    /// - Returns: Exact boolean value.
    /// - Throws: Invalid-payload error for every nonboolean.
    static func bool(_ value: JSONValue) throws -> Bool {
        guard case .bool(let result) = value else { throw ActivityCatalogError.invalidPayload }
        return result
    }

    /// Requires a number and retains arbitrary precision and unknown enum values.
    /// - Parameter value: Original subtree.
    /// - Returns: Exact validated numeric token.
    /// - Throws: Invalid-payload error for strings, booleans, containers or null.
    static func number(_ value: JSONValue) throws -> JSONNumber {
        guard case .number(let result) = value else { throw ActivityCatalogError.invalidPayload }
        return result
    }

    /// Requires an array and applies a typed projection in wire order.
    /// - Parameters:
    ///   - value: Original array subtree.
    ///   - transform: Pure synchronous validation of each element.
    /// - Returns: Ordered typed elements, including an empty array when supplied.
    /// - Throws: Invalid-payload error for nonarrays, or an element's projection failure.
    static func array<T>(_ value: JSONValue, _ transform: (JSONValue) throws -> T) throws -> [T] {
        guard case .array(let values) = value else { throw ActivityCatalogError.invalidPayload }
        return try values.map(transform)
    }

    /// Reads optional presence without conflating omission and explicit null.
    /// - Parameters:
    ///   - key: Exact documented field name.
    ///   - nullable: Whether explicit null is accepted; defaults to false.
    ///   - transform: Validation for a present, nonnull value.
    /// - Returns: Absent, null, or typed value; unknown fields remain in the original object.
    /// - Throws: Invalid-payload error for forbidden null, or the transform's validation error.
    func field<T>(_ key: String, nullable: Bool = false, _ transform: (JSONValue) throws -> T) throws -> Field<T> {
        guard let value = fields[key] else { return .absent }
        if value == .null {
            guard nullable else { throw ActivityCatalogError.invalidPayload }
            return .null
        }
        return .value(try transform(value))
    }

    /// Reads a required field that permits explicit null.
    /// - Parameters:
    ///   - key: Exact documented field name; omission is invalid.
    ///   - transform: Validation for a nonnull value.
    /// - Returns: Explicit null or the typed value.
    /// - Throws: Invalid-payload error for omission or the transform's failure.
    func nullable<T>(_ key: String, _ transform: (JSONValue) throws -> T) throws -> Nullable<T> {
        let value = try required(key)
        return value == .null ? .null : .value(try transform(value))
    }

    /// Retains unconstrained schema values verbatim, including explicit null.
    /// - Parameter value: Any bounded subtree.
    /// - Returns: The original value without allocation or coercion.
    static func identity(_ value: JSONValue) -> JSONValue { value }

    /// Requires a string or numeric enum value, retaining future variants and exact spellings.
    /// - Parameter value: Original enum-like subtree.
    /// - Returns: The original string or number.
    /// - Throws: Invalid-payload error for other types.
    static func scalarCode(_ value: JSONValue) throws -> JSONValue {
        switch value {
        case .string, .number: return value
        default: throw ActivityCatalogError.invalidPayload
        }
    }
}

/// A command response whose schema permits a null or otherwise empty object.
/// Unknown object members are preserved instead of discarded by the upstream validator.
public struct ActivityEmptyResponse: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let value: Nullable<[String: JSONValue]>

    /// Validates the SDK's nullable empty-object response.
    /// - Parameter value: Null or an object, including an object with future members.
    /// - Throws: `ActivityCatalogError.invalidPayload` for every other type.
    public init(value: JSONValue) throws {
        if value == .null { self.value = .null }
        else { self.value = .value(try ActivityObject(value).fields) }
    }
    /// Conceals any future object members.
    public var description: String { "ActivityEmptyResponse(redacted)" }
    /// Conceals any future object members in debugger output.
    public var debugDescription: String { description }
    /// Prevents reflection from expanding unknown sensitive fields.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}

/// Nullable array returned by START_PURCHASE; client results are advisory and never grant server entitlement.
public struct ActivityPurchaseResponse: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let entitlements: Nullable<[ActivityEntitlement]>

    /// Projects purchase results without trusting them for server authorization.
    /// - Parameter value: Explicit null or an ordered array of Activity entitlement objects.
    /// - Throws: Invalid-payload error for incompatible types or a malformed entitlement.
    public init(value: JSONValue) throws {
        entitlements = value == .null ? .null : .value(try ActivityObject.array(value, ActivityEntitlement.init(value:)))
    }
    /// Conceals user and purchase data.
    public var description: String { "ActivityPurchaseResponse(redacted)" }
    /// Conceals purchase data in debugger output.
    public var debugDescription: String { description }
    /// Prevents reflection from exposing entitlement details.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}

/// Nullable GET_USER result. An explicit null means the host did not return a user.
public struct ActivityUserResponse: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let user: Nullable<ActivityParticipant>

    /// Validates the nullable GET_USER shape.
    /// - Parameter value: Null or a generated-schema participant object.
    /// - Throws: Invalid-payload error for wrong types or a malformed user object.
    public init(value: JSONValue) throws {
        user = value == .null ? .null : .value(try ActivityParticipant(value: value))
    }
    /// Conceals user-profile contents.
    public var description: String { "ActivityUserResponse(redacted)" }
    /// Conceals profile contents in debugger descriptions.
    public var debugDescription: String { description }
    /// Prevents reflection from expanding the user object.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}

/// Lossless permission bitset representation accepted from the Activity bridge.
/// Decimal strings and JSON integral numbers are kept distinct, avoiding JavaScript precision conversion.
public struct ActivityPermissionValue: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let rawValue: JSONValue
    public let decimalRepresentation: String

    /// Validates a nonnegative decimal bitset without imposing a 64-bit limit.
    /// - Parameter value: A nonempty ASCII decimal string or nonnegative integral JSON token.
    /// - Throws: Invalid-payload error for negative, fractional, exponent, empty or nondecimal input.
    /// Existing trees must be bounded by the caller. This value performs no bitwise authorization by itself.
    public init(value: JSONValue) throws {
        let text: String
        switch value {
        case .string(let string): text = string
        case .number(let number): text = number.rawValue
        default: throw ActivityCatalogError.invalidPayload
        }
        guard !text.isEmpty, text.utf8.allSatisfy({ (48...57).contains($0) })
        else { throw ActivityCatalogError.invalidPayload }
        rawValue = value
        decimalRepresentation = text
    }
    /// Conceals the bitset from ordinary diagnostics.
    public var description: String { "ActivityPermissionValue(redacted)" }
    /// Conceals debugger-oriented output.
    public var debugDescription: String { description }
    /// Prevents reflective expansion of permission values.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}

/// Typed data carried by all exported Activity events; unknown names and data remain lossless.
/// Event scopes, host availability, subscription admission and lifecycle are independent of data decoding.
public enum ActivityEventPayload: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    case ready(ActivityReady)
    case voiceStateUpdate(ActivityUserVoiceState)
    case speakingStart(ActivitySpeaking)
    case speakingStop(ActivitySpeaking)
    case activityLayoutModeUpdate(ActivityLayoutUpdate)
    case orientationUpdate(ActivityOrientationUpdate)
    case currentUserUpdate(ActivityUser)
    case currentGuildMemberUpdate(ActivityGuildMemberUpdate)
    case entitlementCreate(ActivityEntitlementCreate)
    case thermalStateUpdate(ActivityThermalUpdate)
    case activityInstanceParticipantsUpdate(ActivityParticipants)
    case relationshipUpdate(ActivityRelationship)
    case activityJoin(ActivityJoin)
    case questEnrollmentStatusUpdate(ActivityQuestEnrollmentUpdate)
    case error(ActivityHostError)
    case unknown(name: ActivityEventName, value: JSONValue)

    /// Decodes a data subtree according to the exact event name while preserving future event payloads.
    /// - Parameters:
    ///   - name: Exact host event name; no case normalization occurs.
    ///   - value: Complete event data already bounded by the frame parser.
    /// - Throws: Invalid-payload error for malformed known events; unknown event data is retained without schema invention.
    /// Parsing is synchronous, owns no subscription, and does not invoke handlers or acknowledge the host.
    public init(name: ActivityEventName, value: JSONValue) throws {
        switch name {
        case .ready: self = .ready(try ActivityReady(value: value))
        case .voiceStateUpdate: self = .voiceStateUpdate(try ActivityUserVoiceState(value: value))
        case .speakingStart: self = .speakingStart(try ActivitySpeaking(value: value))
        case .speakingStop: self = .speakingStop(try ActivitySpeaking(value: value))
        case .activityLayoutModeUpdate: self = .activityLayoutModeUpdate(try ActivityLayoutUpdate(value: value))
        case .orientationUpdate: self = .orientationUpdate(try ActivityOrientationUpdate(value: value))
        case .currentUserUpdate: self = .currentUserUpdate(try ActivityUser(value: value))
        case .currentGuildMemberUpdate: self = .currentGuildMemberUpdate(try ActivityGuildMemberUpdate(value: value))
        case .entitlementCreate: self = .entitlementCreate(try ActivityEntitlementCreate(value: value))
        case .thermalStateUpdate: self = .thermalStateUpdate(try ActivityThermalUpdate(value: value))
        case .activityInstanceParticipantsUpdate: self = .activityInstanceParticipantsUpdate(try ActivityParticipants(value: value))
        case .relationshipUpdate: self = .relationshipUpdate(try ActivityRelationship(value: value))
        case .activityJoin: self = .activityJoin(try ActivityJoin(value: value))
        case .questEnrollmentStatusUpdate: self = .questEnrollmentStatusUpdate(try ActivityQuestEnrollmentUpdate(value: value))
        case .error: self = .error(try ActivityHostError(value: value))
        default: self = .unknown(name: name, value: value)
        }
    }
    /// Conceals event data and unknown future payloads.
    public var description: String { "ActivityEventPayload(redacted)" }
    /// Conceals data in debugger output.
    public var debugDescription: String { description }
    /// Prevents reflection from exposing associated payloads or unknown future secrets.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}

/// Unknown-preserving OAuth scope union returned by the generated authentication schema.
/// String names and numeric unhandled values retain their exact spelling instead of being collapsed to -1.
public struct ActivityOAuthScope: Sendable, Equatable {
    public let rawValue: JSONValue

    /// Validates a scope name or unhandled numeric code, preserving future additions.
    /// - Parameter value: Exact string or number subtree from the authenticated scopes array.
    /// - Throws: Invalid-payload error for null, arrays, objects or booleans.
    public init(value: JSONValue) throws { rawValue = try ActivityObject.scalarCode(value) }
}

/// Validates the generated event schema's ISO calendar-date string without locale, time-zone or clock dependencies.
/// - Parameter value: Exact `YYYY-MM-DD` spelling, including leap-day validation on the proleptic Gregorian calendar.
/// - Throws: Invalid-payload error for malformed dates, impossible days, or timestamp/time-zone suffixes.
func activityDate(_ value: String) throws {
    let bytes = Array(value.utf8)
    guard bytes.count == 10, bytes[4] == 45, bytes[7] == 45,
          bytes.enumerated().allSatisfy({ $0.offset == 4 || $0.offset == 7 || (48...57).contains($0.element) }),
          let year = Int(value.prefix(4)), let month = Int(String(value.dropFirst(5).prefix(2))),
          let day = Int(value.suffix(2)), (1...12).contains(month) else { throw ActivityCatalogError.invalidPayload }
    let leap = year.isMultiple(of: 4) && (!year.isMultiple(of: 100) || year.isMultiple(of: 400))
    let days = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
    guard (1...days[month - 1]).contains(day) else { throw ActivityCatalogError.invalidPayload }
}

/// Validates the common SDK response fields explicitly declared as URL strings.
/// - Parameter text: Exact URL string; unknown fields and other plain-string URL fields are not interpreted.
/// - Throws: Invalid-payload error for a malformed absolute URL. No request, origin approval or navigation occurs.
func activityResponseURL(_ text: String) throws {
    do { _ = try activityURL(text) }
    catch { throw ActivityCatalogError.invalidPayload }
}
