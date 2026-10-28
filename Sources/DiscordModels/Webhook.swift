// File: Sources/DiscordModels/Webhook.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import Foundation

/// API v10 webhook types; response wrappers preserve future integer values.
public enum WebhookType: Int, Sendable { case incoming = 1, channelFollower = 2, application = 3 }

/// Complete written API v10 webhook projection, verified 2026-10-16 against the Webhook Resource.
/// Token and execution URL are credentials. Ordinary formatting and reflection conceal all fields;
/// explicit unsafe access remains the caller's responsibility and does not guarantee memory erasure.
public struct Webhook: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let id: WebhookID
    public let type: RawValue<WebhookType>
    public let guildID: Field<GuildID>
    public let channelID: Nullable<ChannelID>
    public let user: Field<MessageAuthor>
    public let name: Nullable<String>
    public let avatar: Nullable<String>
    public let token: Field<WebhookToken>
    public let applicationID: Nullable<ApplicationID>
    public let sourceGuild: Field<WebhookSourceGuild>
    public let sourceChannel: Field<WebhookSourceChannel>
    private let fields: [String: JSONValue]

    /// Parses all written fields under complete document bounds without network or related-resource reads.
    /// - Parameters:
    ///   - data: Complete webhook object; optional fields preserve omission and documented nullable values.
    ///   - limits: Whole-document JSON byte, depth and node caps, default 1 MiB/64/100,000.
    /// - Throws: Bounded JSON errors or sanitized invalid-response errors for missing/null/mistyped fields,
    ///   invalid snowflakes or malformed tokens. Incoming, follower and application variants are accepted.
    public init(data: Data, limits: JSONLimits = .default) throws {
        let object = try PayloadObject(JSONValue.parse(data, limits: limits), limits: limits)
        id = try object.required("id", WebhookID.self)
        type = try object.required("type", RawValue<WebhookType>.self)
        guildID = try object.field("guild_id", GuildID.self, nullable: true)
        channelID = try object.required("channel_id", Nullable<ChannelID>.self)
        user = try object.messageField("user", MessageAuthor.self)
        name = try object.required("name", Nullable<String>.self)
        avatar = try object.required("avatar", Nullable<String>.self)
        applicationID = try object.required("application_id", Nullable<ApplicationID>.self)
        token = try object.nested("token") { value in
            guard case .string(let text) = value, let token = try? WebhookToken(text) else {
                throw DiscordError.transport(.invalidResponse)
            }
            return token
        }
        sourceGuild = try object.messageField("source_guild", WebhookSourceGuild.self)
        sourceChannel = try object.messageField("source_channel", WebhookSourceChannel.self)
        _ = try object.field("url", String.self)
        fields = object.resource.fields
    }

    /// Deliberately exposes the original credential-bearing object, including optional `url` and unknown fields.
    /// - Parameter body: Synchronous operation; do not log, reflect or forward the resulting secrets.
    /// - Returns: The closure result, which may itself retain copied credentials.
    /// - Throws: Rethrows closure errors without adding payload diagnostics.
    public func withUnsafeFields<Result>(_ body: ([String: JSONValue]) throws -> Result) rethrows -> Result { try body(fields) }
    /// Deliberately exposes the optional execution URL, which can embed a webhook token.
    /// - Parameter body: Synchronous consumer receiving the exact URL string or nil when omitted.
    /// - Returns: Consumer result; callers own subsequent credential handling.
    /// - Throws: Rethrows consumer errors only.
    public func withUnsafeURL<Result>(_ body: (String?) throws -> Result) rethrows -> Result {
        let url: String? = if case .string(let value) = fields["url"] { value } else { nil }
        return try body(url)
    }
    /// Conceals all payload and credential fields from normal formatting.
    public var description: String { "Webhook(redacted)" }
    /// Conceals payload and credentials from debug formatting.
    public var debugDescription: String { description }
    /// Conceals retained raw JSON, URLs and typed tokens from reflective diagnostics.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}

/// Written follower-webhook source guild subset; other guild fields remain exact unknown JSON.
public struct WebhookSourceGuild: MessageResponseValue, MessageTreeProjectable, Equatable {
    public let id: GuildID
    public let name: String
    public let icon: Nullable<String>
    public let rawFields: [String: JSONValue]

    /// Parses a bounded source guild without interpreting its visibility as a current permission grant.
    /// - Parameters:
    ///   - data: Complete partial-guild object containing id, name and nullable icon.
    ///   - limits: Whole-object parser limits, defaulting to shared JSON bounds.
    /// - Throws: Syntax/bounds errors or sanitized missing/null/type errors.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }
    /// Projects an already bounded nested source guild without repeated JSON serialization.
    /// - Parameters:
    ///   - value: Exact original subtree.
    ///   - limits: Limits established for the complete containing webhook.
    /// - Throws: Sanitized invalid-response errors for incompatible fields.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        id = try object.required("id", GuildID.self)
        name = try object.required("name", String.self)
        icon = try object.required("icon", Nullable<String>.self)
        rawFields = object.resource.fields
    }
}

/// Written follower-webhook source channel subset, independent of fetching or adopting Channel.
public struct WebhookSourceChannel: MessageResponseValue, MessageTreeProjectable, Equatable {
    public let id: ChannelID
    public let name: String
    public let rawFields: [String: JSONValue]

    /// Parses a bounded source-channel object without I/O or hydration.
    /// - Parameters:
    ///   - data: Complete object containing id and name, with arbitrary future fields preserved.
    ///   - limits: Complete JSON parser bounds, defaulting to shared limits.
    /// - Throws: JSON bounds/syntax or sanitized missing/null/type errors.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }
    /// Projects an immutable channel subtree after its containing root has passed parser bounds.
    /// - Parameters:
    ///   - value: Exact source-channel object.
    ///   - limits: Bounds used for the containing document.
    /// - Throws: Sanitized invalid-response errors for incompatible known fields.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        id = try object.required("id", ChannelID.self)
        name = try object.required("name", String.self)
        rawFields = object.resource.fields
    }
}
