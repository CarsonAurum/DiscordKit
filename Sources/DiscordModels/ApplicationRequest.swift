// File: Sources/DiscordModels/ApplicationRequest.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import Foundation

/// Current default install-link scopes accepted by Discord's official API v10 OpenAPI preview.
public enum ApplicationInstallScope: String, Sendable, CaseIterable {
    /// Permit application commands in the supported installation context.
    case applicationCommands = "applications.commands"
    /// Add the bot to a guild, subject to installer permissions.
    case bot
}

/// Validated default installation settings; outgoing permissions follow the written decimal-string contract.
/// The preview describes integer permissions instead; this API preserves the published resource's wire shape.
public struct ApplicationInstallParamsRequest: GuildRequestPayload {
    private let fields: [String: JSONValue]

    /// Validates finite default scopes and exact decimal permission digits without granting permissions.
    /// - Parameters:
    ///   - scopes: One or two distinct currently supported scopes; supplied order is preserved.
    ///   - permissions: Nonempty ASCII unsigned decimal string, including zero or future-width bits.
    /// - Throws: Sanitized invalid-value errors for empty/duplicate scopes or malformed permission digits.
    /// No I/O, permission lookup, normalization, suspension or external resource ownership occurs.
    public init(scopes: [ApplicationInstallScope], permissions: String) throws {
        guard !scopes.isEmpty, Set(scopes).count == scopes.count,
              !permissions.isEmpty, permissions.utf8.allSatisfy({ (48...57).contains($0) })
        else { throw DiscordError.validation(.invalidValue) }
        fields = ["scopes": .array(scopes.map { .string($0.rawValue) }), "permissions": .string(permissions)]
    }

    /// Returns the validated immutable default installation object without fetching current settings.
    /// - Returns: Exact ordered scopes and permission digits; callers own any deliberate payload logging.
    public func jsonValue() -> JSONValue { .object(fields) }
}

/// Presence-aware installation-context settings for the current application.
public struct ApplicationIntegrationTypeConfigurationRequest: GuildRequestPayload {
    private let fields: [String: JSONValue]

    /// Validates a context's optional default install parameters, preserving omission and preview-supported null.
    /// - Parameter oauth2InstallParams: Omitted by default; null clears preview settings, a value supplies validated defaults.
    /// - Throws: Sanitized payload validation errors; currently all states of this already validated nested value are allowed.
    /// The context's actual eligibility and supported scopes remain Discord authorization checks at execution.
    public init(oauth2InstallParams: Field<ApplicationInstallParamsRequest> = .absent) throws {
        var result: [String: JSONValue] = [:]
        try guildRequestField(oauth2InstallParams, name: "oauth2_install_params", nullable: true, into: &result) { $0.jsonValue() }
        fields = result
    }

    /// Returns only explicitly selected context defaults; an empty object does not synthesize an install policy.
    /// - Returns: Exact immutable context settings with absence/null preserved.
    public func jsonValue() -> JSONValue { .object(fields) }
}

/// Localized description form exposed by the official API v10 OpenAPI preview.
/// The written Application reference describes a simple string, available through ApplicationModify.description.
public struct ApplicationLocalizedDescription: GuildRequestPayload {
    private let fields: [String: JSONValue]

    /// Validates localized descriptions synchronously without selecting a locale or normalizing caller text.
    /// - Parameters:
    ///   - defaultValue: Required default text, 0...400 Unicode scalars including empty.
    ///   - localizations: Omitted by default; null clears translations, a dictionary supplies 0...400-scalar values.
    ///     Locale keys must be nonempty and control-free; Discord checks its current locale vocabulary.
    /// - Throws: Sanitized invalid-value errors for overlong text or empty/control-containing keys.
    public init(defaultValue: String, localizations: Field<[String: String]> = .absent) throws {
        var result = ["default": try guildRequestText(defaultValue, length: 0...400)]
        try guildRequestField(localizations, name: "localizations", nullable: true, into: &result) { values in
            guard values.keys.allSatisfy({ !$0.isEmpty && !$0.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) })
            else { throw DiscordError.validation(.invalidValue) }
            return .object(try values.mapValues { try guildRequestText($0, length: 0...400) })
        }
        fields = result
    }

    /// Returns the complete preview localization form with original locale keys and text.
    /// - Returns: Exact immutable object with required default text and selected translation presence.
    public func jsonValue() -> JSONValue { .object(fields) }
}

/// Current event-webhook subscription names in the official API v10 OpenAPI preview.
/// Response Application.eventWebhooksTypes deliberately retains future strings instead of rejecting them.
public enum ApplicationWebhookEventType: String, Sendable, CaseIterable {
    /// A user or guild authorized the application.
    case applicationAuthorized = "APPLICATION_AUTHORIZED"
    /// A user or guild deauthorized the application.
    case applicationDeauthorized = "APPLICATION_DEAUTHORIZED"
    /// An entitlement was created.
    case entitlementCreate = "ENTITLEMENT_CREATE"
    /// An entitlement was deleted.
    case entitlementDelete = "ENTITLEMENT_DELETE"
    /// An entitlement changed.
    case entitlementUpdate = "ENTITLEMENT_UPDATE"
    /// A game direct message was created.
    case gameDirectMessageCreate = "GAME_DIRECT_MESSAGE_CREATE"
    /// A game direct message was deleted.
    case gameDirectMessageDelete = "GAME_DIRECT_MESSAGE_DELETE"
    /// A game direct message changed.
    case gameDirectMessageUpdate = "GAME_DIRECT_MESSAGE_UPDATE"
    /// A lobby message was created.
    case lobbyMessageCreate = "LOBBY_MESSAGE_CREATE"
    /// A lobby message was deleted.
    case lobbyMessageDelete = "LOBBY_MESSAGE_DELETE"
    /// A lobby message changed.
    case lobbyMessageUpdate = "LOBBY_MESSAGE_UPDATE"
    /// A user enrolled in a quest.
    case questUserEnrollment = "QUEST_USER_ENROLLMENT"
}

/// Validated API v10 PATCH /applications/@me settings, authorized by the application's bot token.
/// Only selected fields change. Discord verifies URL challenges, ownership, eligibility and image dimensions.
/// Written fields and nullable/preview-only extensions remain explicit; flags_new is response-only.
public struct ApplicationModify: GuildRequestPayload {
    private let fields: [String: JSONValue]

    /// Validates selected application edits without fetching server state or performing URL verification requests.
    /// Every Field defaults to absent, preserving current settings. Empty edits remain explicit empty PATCH bodies.
    /// - Parameters:
    ///   - customInstallURL: Nullable absolute HTTP(S) custom install URL, at most 2048 scalars; null uses preview clearing.
    ///   - description: Nullable written-reference string, 0...400 scalars; cannot be selected with localizedDescription.
    ///   - localizedDescription: Nullable preview localized object; mutually exclusive with description.
    ///   - roleConnectionsVerificationURL: Nullable HTTP(S) verification URL, at most 2048 scalars.
    ///   - installParams: Nullable default settings; permissions retain the written string representation.
    ///   - integrationTypesConfig: Nullable dictionary with one or two supported context keys; nullable values are preview-supported.
    ///   - flags: Nullable legacy integer containing only the three mutable limited-intent bits; zero clears them.
    ///   - icon: Nullable canonical base64 or image data URI; null removes the icon.
    ///   - coverImage: Nullable canonical base64 or image data URI; null removes the cover.
    ///   - interactionsEndpointURL: Nullable HTTP(S) URL, at most 2048 scalars; Discord performs its interaction PING validation.
    ///   - tags: Nullable array with at most five distinct tags, each 0...20 scalars; empty means no tags.
    ///   - eventWebhooksURL: Nullable HTTP(S) URL, at most 2048 scalars; Discord verifies endpoint behavior.
    ///   - eventWebhooksStatus: Nullable disabled/enabled state; disabledByDiscord is response-only and rejected.
    ///   - eventWebhooksTypes: Nullable distinct current event subscriptions, preserving caller order; empty unsubscribes all.
    ///   - teamID: Nullable preview team transfer; Discord controls ownership and transfer eligibility, which may be irreversible.
    ///   - type: Nullable preview application category; only known current categories can be requested.
    ///   - maxParticipants: Nullable preview activity participant maximum in -1...Int32.max; -1 follows server semantics.
    ///   - explicitContentFilter: Nullable preview interaction scanning policy.
    /// - Throws: Sanitized invalid-value errors for conflicting descriptions, malformed URLs/images, text/array/numeric
    ///   bounds, duplicate values, forbidden flag bits or response-only webhook status. No outgoing request starts here.
    public init(customInstallURL: Field<String> = .absent, description: Field<String> = .absent,
                localizedDescription: Field<ApplicationLocalizedDescription> = .absent,
                roleConnectionsVerificationURL: Field<String> = .absent,
                installParams: Field<ApplicationInstallParamsRequest> = .absent,
                integrationTypesConfig: Field<[ApplicationIntegrationType: Nullable<ApplicationIntegrationTypeConfigurationRequest>]> = .absent,
                flags: Field<ApplicationFlags> = .absent, icon: Field<String> = .absent,
                coverImage: Field<String> = .absent, interactionsEndpointURL: Field<String> = .absent,
                tags: Field<[String]> = .absent, eventWebhooksURL: Field<String> = .absent,
                eventWebhooksStatus: Field<ApplicationEventWebhookStatus> = .absent,
                eventWebhooksTypes: Field<[ApplicationWebhookEventType]> = .absent,
                teamID: Field<ApplicationTeamID> = .absent, type: Field<ApplicationType> = .absent,
                maxParticipants: Field<Int> = .absent,
                explicitContentFilter: Field<ApplicationExplicitContentFilter> = .absent) throws {
        var result: [String: JSONValue] = [:]
        for (key, field) in [("custom_install_url", customInstallURL),
            ("role_connections_verification_url", roleConnectionsVerificationURL),
            ("interactions_endpoint_url", interactionsEndpointURL), ("event_webhooks_url", eventWebhooksURL)] {
            try guildRequestField(field, name: key, nullable: true, into: &result) { try applicationRequestURL($0) }
        }
        if case .absent = description {} else if case .absent = localizedDescription {} else {
            throw DiscordError.validation(.invalidValue)
        }
        try guildRequestField(description, name: "description", nullable: true, into: &result) { try guildRequestText($0, length: 0...400) }
        try guildRequestField(localizedDescription, name: "description", nullable: true, into: &result) { $0.jsonValue() }
        try guildRequestField(installParams, name: "install_params", nullable: true, into: &result) { $0.jsonValue() }
        try guildRequestField(integrationTypesConfig, name: "integration_types_config", nullable: true, into: &result) { values in
            guard (1...2).contains(values.count) else { throw DiscordError.validation(.invalidValue) }
            return .object(Dictionary(uniqueKeysWithValues: values.map { key, value in
                switch value {
                case .null: return (String(key.rawValue), JSONValue.null)
                case .value(let configuration): return (String(key.rawValue), configuration.jsonValue())
                }
            }))
        }
        try guildRequestField(flags, name: "flags", nullable: true, into: &result) { value in
            let mutable: ApplicationFlags = [.gatewayPresenceLimited, .gatewayGuildMembersLimited, .gatewayMessageContentLimited]
            guard value.subtracting(mutable).isEmpty else { throw DiscordError.validation(.invalidValue) }
            return try guildRequestNumber(value.rawValue)
        }
        for (key, field) in [("icon", icon), ("cover_image", coverImage)] {
            try guildRequestField(field, name: key, nullable: true, into: &result) { try guildRequestImage($0) }
        }
        try guildRequestField(tags, name: "tags", nullable: true, into: &result) { values in
            guard values.count <= 5, Set(values).count == values.count else { throw DiscordError.validation(.invalidValue) }
            return .array(try values.map { try guildRequestText($0, length: 0...20) })
        }
        try guildRequestField(eventWebhooksStatus, name: "event_webhooks_status", nullable: true, into: &result) { value in
            guard value != .disabledByDiscord else { throw DiscordError.validation(.invalidValue) }
            return try guildRequestNumber(value.rawValue)
        }
        try guildRequestField(eventWebhooksTypes, name: "event_webhooks_types", nullable: true, into: &result) { values in
            guard Set(values).count == values.count else { throw DiscordError.validation(.invalidValue) }
            return .array(values.map { .string($0.rawValue) })
        }
        try guildRequestField(teamID, name: "team_id", nullable: true, into: &result) { .string($0.description) }
        try guildRequestField(type, name: "type", nullable: true, into: &result) { try guildRequestNumber($0.rawValue) }
        try guildRequestField(maxParticipants, name: "max_participants", nullable: true, into: &result) { try guildRequestRange($0, -1...Int(Int32.max)) }
        try guildRequestField(explicitContentFilter, name: "explicit_content_filter", nullable: true, into: &result) { try guildRequestNumber($0.rawValue) }
        fields = result
    }

    /// Returns the immutable selected PATCH fields, retaining explicit clears, empty values and preview forms.
    /// - Returns: Exact validated object; no response-only flags_new value is ever emitted.
    public func jsonValue() -> JSONValue { .object(fields) }
}

/// Validates an absolute configured application URL without resolving DNS, opening sockets or following redirects.
/// - Parameter value: Original HTTP(S) URL, at most 2048 Unicode scalars, with a nonempty host and no user information.
/// - Returns: Unchanged URL text; query strings and fragments are preserved as explicit caller configuration.
/// - Throws: Sanitized invalid-value errors for whitespace/controls, relative URLs, missing hosts or other schemes.
/// Server challenges, public reachability and installation/interaction/webhook compatibility remain Discord checks.
func applicationRequestURL(_ value: String) throws -> JSONValue {
    guard value.unicodeScalars.count <= 2_048,
          !value.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.contains($0) || CharacterSet.controlCharacters.contains($0) }),
          let components = URLComponents(string: value), let scheme = components.scheme?.lowercased(),
          ["https", "http"].contains(scheme), let host = components.host, !host.isEmpty,
          components.user == nil, components.password == nil, components.url != nil
    else { throw DiscordError.validation(.invalidValue) }
    return .string(value)
}
