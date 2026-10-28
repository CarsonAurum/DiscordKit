// File: Sources/DiscordCore/Field.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

/// Presence of a request or partial-update field, preserving omission separately from JSON null.
///
/// Use the keyed-container helpers when encoding model properties: a single-value
/// encoder cannot omit its containing key. This is a synchronous value with no
/// resource ownership, network activity, or hidden state transitions.
public enum Field<Value> {
    /// Leave the field out of a request or retain the existing value in a partial update.
    case absent
    /// Explicitly clear a nullable field. Endpoint-specific validation remains the caller's responsibility.
    case null
    /// Set the field to the associated value.
    case value(Value)
}

extension Field: Sendable where Value: Sendable {}
extension Field: Equatable where Value: Equatable {}
extension Field: Hashable where Value: Hashable {}

extension KeyedEncodingContainer {
    /// Encodes request-field presence without collapsing omission and explicit null.
    ///
    /// `.absent` performs no encoding and does not remove a previously encoded key;
    /// encode each key at most once. This helper neither validates endpoint-specific
    /// nullability nor performs I/O beyond the supplied encoder's own behavior.
    /// - Parameters:
    ///   - field: Omission, explicit null, or a value to encode at `key`.
    ///   - key: The containing object's coding key.
    /// - Throws: Any error produced by encoding the non-absent value or null.
    public mutating func encodeField<Value: Encodable>(_ field: Field<Value>, forKey key: Key) throws {
        switch field {
        case .absent: break
        case .null: try encodeNil(forKey: key)
        case .value(let value): try encode(value, forKey: key)
        }
    }
}

extension KeyedDecodingContainer {
    /// Decodes all three presence states of a partial object.
    ///
    /// Unlike `decodeIfPresent`, this preserves the distinction between a missing
    /// key and a key whose JSON value is null. Complete response snapshots should
    /// use a required `Nullable` property when missing data is an error.
    /// - Parameters:
    ///   - type: The non-null payload type; its decoder validates present values.
    ///   - key: The containing object's coding key.
    /// - Returns: `.absent` for a missing key, `.null` for explicit null, otherwise `.value`.
    /// - Throws: Decoder errors for an invalid present value or unreadable null marker.
    public func decodeField<Value: Decodable>(_ type: Value.Type, forKey key: Key) throws -> Field<Value> {
        guard contains(key) else { return .absent }
        if try decodeNil(forKey: key) { return .null }
        return .value(try decode(type, forKey: key))
    }
}

/// A required response field whose payload may explicitly be null.
///
/// A synthesized keyed `Decodable` model containing this type rejects a missing
/// key, while accepting null. This models Discord's distinction between nullable
/// types and optional field names: <https://docs.discord.com/developers/reference#nullable-and-optional-resource-fields>.
public enum Nullable<Value> {
    /// The server explicitly supplied JSON null.
    case null
    /// The server supplied a non-null value.
    case value(Value)
}

extension Nullable: Sendable where Value: Sendable {}
extension Nullable: Equatable where Value: Equatable {}
extension Nullable: Hashable where Value: Hashable {}

extension Nullable: Decodable where Value: Decodable {
    /// Decodes a present response value, preserving explicit null.
    /// - Parameter decoder: A decoder already positioned at a required field or standalone value.
    /// - Throws: Container or payload decoding errors. Missing keyed fields are rejected by the containing model.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        self = container.decodeNil() ? .null : .value(try container.decode(Value.self))
    }
}

extension Nullable: Encodable where Value: Encodable {
    /// Encodes the supplied response representation as null or its payload.
    /// - Parameter encoder: The destination encoder; this method does not omit keys.
    /// - Throws: Encoder errors for explicit null or the associated payload.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .value(let value): try container.encode(value)
        }
    }
}
