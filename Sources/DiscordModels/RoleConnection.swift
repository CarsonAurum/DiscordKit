// File: Sources/DiscordModels/RoleConnection.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import Foundation

/// API v10 linked-role comparisons. Outgoing records require known cases; RawValue retains future responses.
public enum ApplicationRoleConnectionMetadataType: Int, Sendable, CaseIterable {
    /// User integer is less than or equal to the configured guild integer.
    case integerLessThanOrEqual = 1
    /// User integer is greater than or equal to the configured guild integer.
    case integerGreaterThanOrEqual = 2
    /// User integer equals the configured guild integer.
    case integerEqual = 3
    /// User integer differs from the configured guild integer.
    case integerNotEqual = 4
    /// User ISO8601 time is compared against configured days before the current date.
    case datetimeLessThanOrEqual = 5
    /// User ISO8601 time is compared against configured days before the current date.
    case datetimeGreaterThanOrEqual = 6
    /// User integer equals the configured guild value 1.
    case booleanEqual = 7
    /// User integer differs from the configured guild value 1.
    case booleanNotEqual = 8
}

/// API v10 application linked-role verification field. Optional localization maps accept
/// explicit null from the official preview overlay; response unknown comparison types survive.
/// Verified 2026-10-16 against the Application Role Connection Metadata resource.
public struct ApplicationRoleConnectionMetadata: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Known or future metadata comparison type; no comparison is evaluated locally.
    public let type: RawValue<ApplicationRoleConnectionMetadataType>
    /// Metadata dictionary key; response parsing preserves server text without applying outgoing restrictions.
    public let key: String
    /// Metadata display name.
    public let name: String
    /// Optional nullable translations, retaining future locale keys.
    public let nameLocalizations: Field<[String: String]>
    /// Human-readable metadata description; ordinary diagnostics remain redacted.
    public let metadataDescription: String
    /// Optional nullable translated descriptions.
    public let descriptionLocalizations: Field<[String: String]>
    /// Complete original object, including future keys and exact unknown numeric lexemes.
    public let rawFields: [String: JSONValue]

    /// Parses one immutable API v10 object, retaining exact unknown fields and redacting diagnostics.
    /// - Parameters:
    ///   - data: Complete UTF-8 object; required nullable keys must still be present.
    ///   - limits: Whole-document bounds, default 1 MiB, depth 64 and 100,000 nodes, including unknown data.
    /// - Throws: JSON syntax/bounds errors, or sanitized invalid-response errors for missing required keys,
    ///   forbidden nulls, wrong types or out-of-range exact integers. Parsing is synchronous, does not
    ///   suspend or observe cancellation, and owns no network resources, credentials, cache or mutable state.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects an original subtree after the containing document has passed the same parser bounds.
    /// - Parameters:
    ///   - value: Bounded nonnull object; immutable unknown subtrees remain shared with the parent.
    ///   - limits: Bounds established by the public root parse, reused for exact scalar decoding.
    /// - Throws: Sanitized invalid-response errors for a nonobject or malformed modeled field.
    ///   This synchronous initializer performs no I/O, suspension, authorization or ownership changes.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        type = try object.required("type", RawValue<ApplicationRoleConnectionMetadataType>.self)
        key = try object.required("key", String.self)
        name = try object.required("name", String.self)
        nameLocalizations = try object.field("name_localizations", [String: String].self, nullable: true)
        metadataDescription = try object.required("description", String.self)
        descriptionLocalizations = try object.field("description_localizations", [String: String].self, nullable: true)
        rawFields = object.resource.fields
    }
}

/// API v10 user/application linked-role record, with all official preview fields typed.
/// The prose nullable platform_name/metadata and preview optional properties are preserved
/// without inventing missing values; platform_username supplements the prose response table.
/// Snapshot metadata strings do not grant role eligibility, OAuth2 approval or current access.
public struct ApplicationRoleConnection: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Optional nullable connected-platform display name; no local ownership inference.
    public let platformName: Field<String>
    /// Optional nullable platform username from the official preview overlay.
    public let platformUsername: Field<String>
    /// Optional string-valued metadata dictionary; absence remains distinct from an empty object.
    public let metadata: Field<[String: String]>
    /// Complete original object, including future keys and exact unknown numeric lexemes.
    public let rawFields: [String: JSONValue]

    /// Parses one immutable API v10 object, retaining exact unknown fields and redacting diagnostics.
    /// - Parameters:
    ///   - data: Complete UTF-8 object; required nullable keys must still be present.
    ///   - limits: Whole-document bounds, default 1 MiB, depth 64 and 100,000 nodes, including unknown data.
    /// - Throws: JSON syntax/bounds errors, or sanitized invalid-response errors for missing required keys,
    ///   forbidden nulls, wrong types or out-of-range exact integers. Parsing is synchronous, does not
    ///   suspend or observe cancellation, and owns no network resources, credentials, cache or mutable state.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects an original subtree after the containing document has passed the same parser bounds.
    /// - Parameters:
    ///   - value: Bounded nonnull object; immutable unknown subtrees remain shared with the parent.
    ///   - limits: Bounds established by the public root parse, reused for exact scalar decoding.
    /// - Throws: Sanitized invalid-response errors for a nonobject or malformed modeled field.
    ///   This synchronous initializer performs no I/O, suspension, authorization or ownership changes.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        platformName = try object.field("platform_name", String.self, nullable: true)
        platformUsername = try object.field("platform_username", String.self, nullable: true)
        metadata = try object.field("metadata", [String: String].self)
        rawFields = object.resource.fields
    }
}
