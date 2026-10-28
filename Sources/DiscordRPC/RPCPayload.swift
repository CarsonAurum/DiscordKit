// File: Sources/DiscordRPC/RPCPayload.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import Foundation

/// Immutable lossless projection of an RPC object. RPC child schemas intentionally differ from REST.
/// Construction is synchronous, starts no tasks, suspends nowhere, and owns no transport or mutable state.
/// Unknown fields and numeric lexemes survive in `rawFields`; diagnostics always conceal payload contents.
public protocol RPCPayload: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// Original complete object, including future keys, nullable values and exact JSON number spellings.
    var rawFields: [String: JSONValue] {
        /// Reads the retained immutable RPC object synchronously without transport or parsing work.
        /// - Returns: Original known and unknown fields, nulls and exact numeric spellings.
        ///   Deliberate inspection bypasses diagnostic redaction; callers protect sensitive values.
        get
    }

    /// Validates one already-bounded RPC subtree and projects modeled fields.
    /// - Parameter value: Object parsed using JSONValue under caller-established whole-document limits.
    /// - Throws: `RPCCatalogError.invalidPayload` for missing, null or malformed modeled fields.
    /// This initializer does not independently bound an existing tree; use `init(data:limits:)` for untrusted bytes.
    init(value: JSONValue) throws
}

extension RPCPayload {
    /// Parses one complete RPC payload under explicit byte, node and depth limits.
    /// - Parameters:
    ///   - data: Complete UTF-8 JSON object; trailing content and duplicate keys are rejected.
    ///   - limits: Whole-document bounds, default 1 MiB, 64 containers and 100,000 values.
    /// - Throws: JSON syntax/limits errors or sanitized `RPCCatalogError.invalidPayload` projection errors.
    /// Parsing performs no I/O, cannot observe cancellation mid-parse, and never normalizes numeric lexemes.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits))
    }

    /// Conceals all data, including server error strings, OAuth codes, user profiles and activity secrets.
    public var description: String { "RPCPayload(redacted)" }
    /// Uses the same redaction for debugger-oriented descriptions and nested payload diagnostics.
    public var debugDescription: String { description }

    /// Prevents Mirror/dump from expanding authorization codes, user data or activity secrets.
    /// The constant child records redaction without copying or inspecting the original payload tree.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}

/// Shared exact-type reader for bounded RPC trees; errors contain no field names or payload values.
struct RPCObject {
    let fields: [String: JSONValue]

    /// Requires an object without copying or reserializing its immutable unknown subtrees.
    /// - Parameter value: Already-bounded RPC object.
    /// - Throws: Sanitized invalid-payload error for any nonobject value, including null.
    init(_ value: JSONValue) throws {
        guard case .object(let fields) = value else { throw RPCCatalogError.invalidPayload }
        self.fields = fields
    }

    /// Requires a present value while retaining explicit null for caller-specific nullable handling.
    /// - Parameter key: Documented wire field name.
    /// - Returns: Original immutable subtree.
    /// - Throws: Sanitized invalid-payload error if the field is omitted.
    func required(_ key: String) throws -> JSONValue {
        guard let value = fields[key] else { throw RPCCatalogError.invalidPayload }
        return value
    }

    /// Requires a string field without normalization.
    /// - Parameter key: Documented wire key.
    /// - Returns: Original Unicode string, including empty strings where the schema allows them.
    /// - Throws: Sanitized invalid-payload error for missing or nonstring values.
    func string(_ key: String) throws -> String { try Self.string(required(key)) }

    /// Requires a JSON string and rejects numeric coercion.
    /// - Parameter value: Original subtree.
    /// - Returns: Exact Unicode contents.
    /// - Throws: Sanitized invalid-payload error for any nonstring, including null.
    static func string(_ value: JSONValue) throws -> String {
        guard case .string(let result) = value else { throw RPCCatalogError.invalidPayload }
        return result
    }

    /// Requires a JSON boolean without accepting numeric zero/one.
    /// - Parameter value: Original subtree.
    /// - Returns: Boolean contents.
    /// - Throws: Sanitized invalid-payload error for any nonboolean value.
    static func bool(_ value: JSONValue) throws -> Bool {
        guard case .bool(let result) = value else { throw RPCCatalogError.invalidPayload }
        return result
    }

    /// Requires a JSON number while preserving its spelling and arbitrary precision.
    /// - Parameter value: Original subtree.
    /// - Returns: Exact validated lexeme; no floating-point conversion occurs.
    /// - Throws: Sanitized invalid-payload error for strings, booleans, null and containers.
    static func number(_ value: JSONValue) throws -> JSONNumber {
        guard case .number(let result) = value else { throw RPCCatalogError.invalidPayload }
        return result
    }

    /// Requires a native-range canonical integral number, rejecting exponents and fractional spellings.
    /// - Parameter value: Original subtree.
    /// - Returns: Exact native integer; no rounding occurs.
    /// - Throws: Sanitized invalid-payload error for nonintegers, overflow or a different JSON type.
    static func integer(_ value: JSONValue) throws -> Int {
        let number = try number(value)
        guard let result = Int(number.rawValue), String(result) == number.rawValue else { throw RPCCatalogError.invalidPayload }
        return result
    }

    /// Requires a present exact native integer field.
    /// - Parameter key: Documented wire key.
    /// - Returns: Canonical integer without rounding.
    /// - Throws: Sanitized invalid-payload error for missing, malformed or out-of-range values.
    func integer(_ key: String) throws -> Int { try Self.integer(required(key)) }

    /// Requires a present array and retains element order.
    /// - Parameter key: Documented wire key.
    /// - Returns: Exact original element trees, including unknown nested data.
    /// - Throws: Sanitized invalid-payload error for absent, null or nonarray values.
    func array(_ key: String) throws -> [JSONValue] {
        guard case .array(let result) = try required(key) else { throw RPCCatalogError.invalidPayload }
        return result
    }

    /// Requires an exact nonzero snowflake encoded as a decimal JSON string.
    /// - Parameter key: Documented wire key; the return context selects the resource tag.
    /// - Returns: Exact unsigned 64-bit resource identity, including values above 2^53.
    /// - Throws: Sanitized invalid-payload error for missing, numeric, zero, malformed or overflowing IDs.
    func id<Tag>(_ key: String) throws -> Snowflake<Tag> { try Self.identifier(required(key)) }

    /// Projects an exact nonzero snowflake without floating-point conversion.
    /// - Parameter value: Decimal-string subtree.
    /// - Returns: Exact resource-tagged identity.
    /// - Throws: Sanitized invalid-payload error for other types, zero, malformed or overflowing strings.
    static func identifier<Tag>(_ value: JSONValue) throws -> Snowflake<Tag> {
        guard let result = Snowflake<Tag>(try string(value)), result.rawValue != 0 else { throw RPCCatalogError.invalidPayload }
        return result
    }

    /// Projects optional fields without conflating omitted, explicit null and a present value.
    /// - Parameters:
    ///   - key: Documented wire key.
    ///   - nullable: Whether explicit null is accepted; defaults to false.
    ///   - transform: Synchronous typed projection of a present nonnull subtree.
    /// - Returns: Original presence state with a validated associated value.
    /// - Throws: Sanitized invalid-payload error for forbidden null, or the transform's projection error.
    func field<T>(_ key: String, nullable: Bool = false, _ transform: (JSONValue) throws -> T) throws -> Field<T> {
        guard let value = fields[key] else { return .absent }
        if value == .null {
            guard nullable else { throw RPCCatalogError.invalidPayload }
            return .null
        }
        return .value(try transform(value))
    }

    /// Projects a required nullable field while rejecting omission.
    /// - Parameters:
    ///   - key: Documented wire key.
    ///   - transform: Synchronous typed projection of a nonnull value.
    /// - Returns: Explicit null or the projected payload.
    /// - Throws: Sanitized invalid-payload error for missing values or transform validation failure.
    func nullable<T>(_ key: String, _ transform: (JSONValue) throws -> T) throws -> Nullable<T> {
        let value = try required(key)
        return value == .null ? .null : .value(try transform(value))
    }
}
