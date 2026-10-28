// File: Sources/DiscordModels/EmojiRequest.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import Foundation

/// Validated API v10 POST /guilds/{guild.id}/emojis body; CREATE_GUILD_EXPRESSIONS is required.
/// Discord checks 128x128 dimensions, image content, role eligibility and current guild capacity.
/// Premium and normal roles cannot be mixed and an emoji's premium category cannot be converted
/// after creation; IDs alone cannot establish either condition. Guild emoji routes have unusual
/// per-guild quotas and can return 429 even when their reported quota appears available.
public struct GuildEmojiCreate: GuildRequestPayload {
    private let fields: [String: JSONValue]

    /// Validates creation syntax and bounded image bytes without media decoding or network requests.
    /// - Parameters:
    ///   - name: Exact name of 2...32 Unicode scalars per the official OpenAPI preview; no normalization occurs.
    ///   - image: Canonical base64 data URI using image/jpeg, image/png, image/gif, image/webp or image/avif;
    ///     decoded bytes must be nonempty and at most 262144 bytes (256 KiB). Dimensions/content remain server checks.
    ///   - roles: Distinct allowed role IDs, defaulting to an explicit empty array. At most 1521 IDs follow
    ///     the official preview's transport cap; null elements are excluded by the written array-of-IDs schema.
    /// - Throws: Safe invalid-value errors for invalid text, media syntax or duplicate roles; limit-exceeded
    ///   errors for excessive image bytes or roles. No input appears in errors. Construction is synchronous.
    public init(name: String, image: String, roles: [RoleID] = []) throws {
        fields = ["name": try guildRequestText(name, length: 2...32),
                  "image": try expressionRequestDataURI(image, mediaTypes: Self.imageMediaTypes, maximumBytes: 262_144),
                  "roles": try expressionRequestRoles(roles)]
    }

    /// Supported upload media types from the written Emoji Formats reference, including newer WebP/AVIF.
    static let imageMediaTypes: Set<String> = ["image/jpeg", "image/png", "image/gif", "image/webp", "image/avif"]

    /// Returns the validated body without adding inferred premium state or checking permissions.
    /// - Returns: Exact name, data URI and ordered role IDs; serialization deliberately exposes upload content.
    public func jsonValue() -> JSONValue { .object(fields) }
}

/// Validated API v10 PATCH /guilds/{guild.id}/emojis/{emoji.id} body. Own emoji require
/// CREATE_GUILD_EXPRESSIONS or MANAGE_GUILD_EXPRESSIONS; other emoji require MANAGE_GUILD_EXPRESSIONS.
/// The server checks premium category immutability and subscription/non-subscription role compatibility.
public struct GuildEmojiModify: GuildRequestPayload {
    private let fields: [String: JSONValue]

    /// Validates explicitly selected changes without fetching or merging current emoji state.
    /// - Parameters:
    ///   - name: Omitted by default, otherwise a nonnull name of 2...32 Unicode scalars.
    ///   - roles: Omitted by default, explicit null per the written reference, or at most 1521 distinct
    ///     role IDs. An empty array and null remain distinct; neither infers the emoji's premium category.
    /// - Throws: Safe invalid-value errors for null/invalid names or duplicate roles; limit-exceeded for
    ///   too many roles. Work is synchronous, side-effect free and has no suspension or resource ownership.
    public init(name: Field<String> = .absent, roles: Field<[RoleID]> = .absent) throws {
        var result: [String: JSONValue] = [:]
        try guildRequestField(name, name: "name", into: &result) { try guildRequestText($0, length: 2...32) }
        try guildRequestField(roles, name: "roles", nullable: true, into: &result) { try expressionRequestRoles($0) }
        fields = result
    }

    /// Returns exact selected changes; an empty object remains a deliberate empty PATCH body.
    /// - Returns: Object preserving absent/null/value roles and the exact selected name.
    public func jsonValue() -> JSONValue { .object(fields) }
}

/// Validated API v10 POST /applications/{application.id}/emojis body, authenticated with the
/// application's bot token. Application emoji can be used without USE_EXTERNAL_EMOJIS; Discord
/// checks ownership and the independent application limit of 2000 emoji.
public struct ApplicationEmojiCreate: GuildRequestPayload {
    private let fields: [String: JSONValue]

    /// Validates application emoji upload syntax without decoding the image or fetching capacity.
    /// - Parameters:
    ///   - name: Exact name of 2...32 Unicode scalars, following the official OpenAPI preview.
    ///   - image: Canonical JPEG/PNG/GIF/WebP/AVIF image data URI, nonempty and at most 256 KiB
    ///     decoded bytes. Discord validates the documented 128x128 dimensions and actual media content.
    /// - Throws: Safe invalid-value errors for text/media syntax, or limit-exceeded for excessive bytes.
    ///   No I/O, suspension, logging, cancellation observation or external resource ownership occurs.
    public init(name: String, image: String) throws {
        fields = ["name": try guildRequestText(name, length: 2...32),
                  "image": try expressionRequestDataURI(image, mediaTypes: GuildEmojiCreate.imageMediaTypes,
                                                        maximumBytes: 262_144)]
    }

    /// Returns exact application creation fields without guild-only role settings.
    /// - Returns: Validated name and original image data URI, deliberately exposing upload content.
    public func jsonValue() -> JSONValue { .object(fields) }
}

/// Validated API v10 PATCH /applications/{application.id}/emojis/{emoji.id} metadata body.
/// The official OpenAPI preview permits omission of the name; the written reference describes
/// its string value without an explicit optional marker. An omitted name produces an empty body
/// object and does not infer the current server value. Ownership and authentication remain server checks.
public struct ApplicationEmojiModify: GuildRequestPayload {
    private let fields: [String: JSONValue]

    /// Validates an optionally selected rename without inspecting current state or allowing guild-only roles.
    /// - Parameter name: Absent by default, following the official preview's partial request schema;
    ///   otherwise a nonnull name of 2...32 Unicode scalars. Explicit null is invalid and no normalization occurs.
    /// - Throws: Safe invalid-value errors for null or out-of-range text. Construction is synchronous,
    ///   side-effect free and has no I/O, logging, resource ownership, tasks or cancellation suspension.
    public init(name: Field<String> = .absent) throws {
        var result: [String: JSONValue] = [:]
        try guildRequestField(name, name: "name", into: &result) { try guildRequestText($0, length: 2...32) }
        fields = result
    }

    /// Validates one explicit rename without inspecting current state or permitting guild-only roles.
    /// - Parameter name: Exact nonnull name of 2...32 Unicode scalars; no normalization occurs.
    /// - Throws: Safe invalid-value errors for out-of-range text, delegated to the presence-aware initializer.
    ///   Construction is synchronous and side-effect free with no I/O, logging, cancellation suspension,
    ///   external resource ownership or background tasks. Existing explicit rename call sites remain compatible.
    public init(name: String) throws {
        try self.init(name: .value(name))
    }

    /// Returns the validated selection without adding omitted fields or inferring a no-op from server state.
    /// - Returns: An object containing the selected name, or an empty object when the name was omitted.
    public func jsonValue() -> JSONValue { .object(fields) }
}

/// Validates a bounded canonical media data URI before any base64 decoding allocation.
/// - Parameters:
///   - value: Exact data URI; raw base64, extra parameters, whitespace and URL-safe base64 are rejected.
///   - mediaTypes: Explicit allowed lowercase media types owned by the calling endpoint family.
///   - maximumBytes: Positive local maximum decoded bytes whose encoded size and 64-byte URI-header
///     allowance fit in Int; current callers use fixed published/conservative caps.
/// - Returns: The original URI as a JSON string, preserving caller bytes without normalization.
/// - Throws: Safe invalid-value errors for malformed syntax, unsupported media, noncanonical base64 or
///   empty decoded data; limit-exceeded for encoded/decoded content beyond the cap. Work is synchronous
///   and linear in bounded input length after the preallocation check; no media parsing or I/O occurs.
func expressionRequestDataURI(_ value: String, mediaTypes: Set<String>, maximumBytes: Int) throws -> JSONValue {
    guard maximumBytes > 0 else { throw DiscordError.validation(.invalidValue) }
    let encodedGroups = maximumBytes / 3 + (maximumBytes % 3 == 0 ? 0 : 1)
    let (maximumEncodedBytes, overflow) = encodedGroups.multipliedReportingOverflow(by: 4)
    guard !overflow, maximumEncodedBytes <= Int.max - 64 else { throw DiscordError.validation(.invalidValue) }
    guard value.utf8.count <= maximumEncodedBytes + 64 else { throw DiscordError.validation(.limitExceeded) }
    guard value.hasPrefix("data:"), let separator = value.range(of: ";base64,"),
          mediaTypes.contains(String(value[value.index(value.startIndex, offsetBy: 5)..<separator.lowerBound]))
    else { throw DiscordError.validation(.invalidValue) }
    let encoded = String(value[separator.upperBound...])
    guard encoded.utf8.count <= maximumEncodedBytes else { throw DiscordError.validation(.limitExceeded) }
    guard let decoded = Data(base64Encoded: encoded), !decoded.isEmpty,
          decoded.base64EncodedString() == encoded else { throw DiscordError.validation(.invalidValue) }
    guard decoded.count <= maximumBytes else { throw DiscordError.validation(.limitExceeded) }
    return .string(value)
}

/// Applies the official preview's transport collection bound before encoding typed allowed-role IDs.
/// - Parameter roles: Ordered role IDs; an empty array selects no restrictions and null is handled by callers.
/// - Returns: Decimal-string array retaining all unsigned bits and caller order.
/// - Throws: Safe limit-exceeded for more than 1521 IDs, or invalid-value for duplicates. Guild role
///   membership, premium eligibility and category immutability remain server checks; no I/O occurs.
func expressionRequestRoles(_ roles: [RoleID]) throws -> JSONValue {
    guard roles.count <= 1_521 else { throw DiscordError.validation(.limitExceeded) }
    return try guildRequestIDs(roles)
}
