// File: Sources/DiscordModels/ComputedPermissions.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import Foundation

/// Discord's computed permission snapshot for a guild/channel member or role.
/// API v10; verified 2026-11-05 against the Guild and Channel permission endpoints:
/// https://docs.discord.com/developers/resources/guild#get-guild-member-permissions and
/// https://docs.discord.com/developers/resources/channel#get-channel-member-permissions.
/// Guild and channel calculations have different scopes; the endpoint supplies that context.
/// A snapshot can become stale immediately and never establishes authorization for a later operation.
public struct ComputedPermissions: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Required, nonnull, arbitrary-width ASCII decimal permission bitfield, retaining leading zeroes.
    /// Unknown future bits remain exact; this value performs no local permission calculation or masking.
    public let permissions: String
    /// Complete original object, including unknown fields and exact numeric lexemes; diagnostics redact values.
    public let rawFields: [String: JSONValue]

    /// Parses one complete permission response under finite byte, depth and node bounds.
    /// - Parameters:
    ///   - data: UTF-8 JSON object containing a nonempty decimal-string `permissions` field.
    ///     Unknown keys are retained, duplicate keys and trailing documents are rejected.
    ///   - limits: Bounds for the entire object, including unknown subtrees; defaults to
    ///     1,048,576 bytes, depth 64 and 100,000 JSON values. Container depth must be in 1...128.
    /// - Throws: `JSONValueError` for invalid syntax, limits or exceeded bounds;
    ///   `DiscordError.transport(.invalidResponse)` for malformed required fields or a nonobject root.
    ///   Schema errors disclose no payload text. Correct the response or limits before retrying.
    /// Parsing is synchronous, performs no I/O or ownership changes and cannot observe task cancellation.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects an immutable permission object already admitted by its containing parser.
    /// - Parameters:
    ///   - value: Original object subtree whose complete document has passed `limits`.
    ///   - limits: Bounds from that root parse, reused for required-field validation.
    /// - Throws: Sanitized invalid-response errors for a nonobject root, missing/null/wrongly typed
    ///   permissions, or anything except nonempty ASCII decimal digits. No integer narrowing occurs.
    /// Construction is synchronous, shares immutable tree storage and performs no I/O or suspension.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        permissions = try object.required("permissions", String.self)
        try validateChannelPermissionBits(permissions)
        rawFields = object.resource.fields
    }
}
