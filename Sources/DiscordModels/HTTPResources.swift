// File: Sources/DiscordModels/HTTPResources.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import Foundation

/// Shared bounded JSON projection retaining exact unmodeled values for both resources.
struct ResourceObject {
    let fields: [String: JSONValue]
    let limits: JSONLimits

    /// Requires a complete JSON object before any typed field is inspected.
    /// - Parameters:
    ///   - data: Complete untrusted UTF-8 JSON bytes.
    ///   - limits: Bounds shared by parsing and per-field serialization.
    /// - Throws: Safe parser errors or invalid-response errors for a scalar/array root.
    init(data: Data, limits: JSONLimits) throws {
        guard case .object(let fields) = try JSONValue.parse(data, limits: limits)
        else { throw DiscordError.transport(.invalidResponse) }
        self.fields = fields; self.limits = limits
    }

    /// Decodes a required typed field while sanitizing Foundation decoding errors.
    /// - Parameters:
    ///   - name: Exact API field key; missing keys fail even for `Nullable` types.
    ///   - type: Expected Swift scalar/container type.
    /// - Returns: The validated typed value.
    /// - Throws: Safe invalid-response errors for missing fields, type/range mismatch or nonintegral number lexemes.
    func required<Value: Decodable>(_ name: String, as type: Value.Type) throws -> Value {
        guard let value = fields[name] else { throw DiscordError.transport(.invalidResponse) }
        if case .number(let number) = value {
            guard !number.rawValue.contains("."), !number.rawValue.contains("e"), !number.rawValue.contains("E")
            else { throw DiscordError.transport(.invalidResponse) }
        }
        do { return try JSONDecoder().decode(type, from: value.serialized(limits: limits)) }
        catch { throw DiscordError.transport(.invalidResponse) }
    }

    /// Retains a required nullable nested object without a lossy Codable bridge.
    /// - Parameter name: Exact API key; omission and nonobject, nonnull payloads are rejected.
    /// - Returns: Explicit null or the original object, including all nested numeric lexemes.
    /// - Throws: `DiscordError.transport(.invalidResponse)` for missing keys or incompatible roots.
    ///
    /// Parsing already enforced the caller's JSON limits. No additional allocation-heavy
    /// serialization, I/O or suspension occurs; nested schema validation remains outside this helper.
    func nullableObject(_ name: String) throws -> Nullable<JSONValue> {
        guard let value = fields[name] else { throw DiscordError.transport(.invalidResponse) }
        switch value {
        case .null: return .null
        case .object: return .value(value)
        default: throw DiscordError.transport(.invalidResponse)
        }
    }

    /// Preserves absent, explicit-null and present optional field states.
    /// - Parameters:
    ///   - name: Exact API field key.
    ///   - type: Non-null payload type.
    ///   - nullable: Whether upstream permits explicit null; defaults to `false`.
    /// - Returns: `.absent`, permitted `.null`, or a validated `.value`.
    /// - Throws: Safe invalid-response errors for forbidden null or a malformed present value.
    func field<Value: Decodable>(_ name: String, as type: Value.Type, nullable: Bool = false) throws -> Field<Value> {
        guard let value = fields[name] else { return .absent }
        if value == .null {
            guard nullable else { throw DiscordError.transport(.invalidResponse) }
            return .null
        }
        return .value(try required(name, as: type))
    }
}
