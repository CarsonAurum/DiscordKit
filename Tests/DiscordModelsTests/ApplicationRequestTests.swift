// File: Tests/DiscordModelsTests/ApplicationRequestTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import Foundation
import Testing
@testable import DiscordModels

/// Validated Application mutations exercise presence, published bounds and explicit preview compatibility forms.
@Suite struct ApplicationRequestTests {
    /// Every written and preview property emits the exact validated wire field with caller ordering preserved.
    /// - Throws: Unexpected valid request construction or JSON fixture errors fail this test.
    @Test func allFieldsAndDefaults() throws {
        let install = try ApplicationInstallParamsRequest(scopes: [.applicationCommands, .bot], permissions: "340282366920938463463374607431768211455")
        let config = try ApplicationIntegrationTypeConfigurationRequest(oauth2InstallParams: .value(install))
        let request = try ApplicationModify(customInstallURL: .value("https://example.test/install"), description: .value("description"),
            roleConnectionsVerificationURL: .value("https://example.test/roles"), installParams: .value(install),
            integrationTypesConfig: .value([.guildInstall: .value(config), .userInstall: .null]),
            flags: .value([.gatewayPresenceLimited, .gatewayGuildMembersLimited, .gatewayMessageContentLimited]),
            icon: .value("data:image/png;base64,AQ=="), coverImage: .null,
            interactionsEndpointURL: .value("https://example.test/interactions"), tags: .value(["one", "two"]),
            eventWebhooksURL: .value("https://example.test/events"), eventWebhooksStatus: .value(.enabled),
            eventWebhooksTypes: .value([.applicationAuthorized, .applicationDeauthorized]), teamID: .value(.init(rawValue: UInt64.max)),
            type: .value(.guildRoleSubscriptions), maxParticipants: .value(-1), explicitContentFilter: .value(.always))
        guard case .object(let fields) = request.jsonValue() else { Issue.record("Expected object"); return }
        #expect(fields.count == 17)
        #expect(fields["description"] == .string("description"))
        #expect(fields["custom_install_url"] == .string("https://example.test/install"))
        #expect(fields["role_connections_verification_url"] == .string("https://example.test/roles"))
        #expect(fields["install_params"] == install.jsonValue())
        #expect(fields["integration_types_config"] == .object(["0": config.jsonValue(), "1": .null]))
        #expect(fields["flags"] == .number(try JSONNumber(rawValue: "565248")))
        #expect(fields["flags_new"] == nil)
        #expect(fields["icon"] == .string("data:image/png;base64,AQ==") && fields["cover_image"] == .null)
        #expect(fields["interactions_endpoint_url"] == .string("https://example.test/interactions"))
        #expect(fields["tags"] == .array([.string("one"), .string("two")]))
        #expect(fields["event_webhooks_url"] == .string("https://example.test/events"))
        #expect(fields["event_webhooks_status"] == .number(try JSONNumber(rawValue: "2")))
        #expect(fields["event_webhooks_types"] == .array([.string("APPLICATION_AUTHORIZED"), .string("APPLICATION_DEAUTHORIZED")]))
        #expect(fields["team_id"] == .string("18446744073709551615"))
        #expect(fields["type"] == .number(try JSONNumber(rawValue: "4")))
        #expect(fields["max_participants"] == .number(try JSONNumber(rawValue: "-1")))
        #expect(fields["explicit_content_filter"] == .number(try JSONNumber(rawValue: "1")))
        #expect(try ApplicationModify().jsonValue() == .object([:]))
        #expect(try ApplicationIntegrationTypeConfigurationRequest().jsonValue() == .object([:]))
        #expect(try ApplicationIntegrationTypeConfigurationRequest(oauth2InstallParams: .null).jsonValue() == .object(["oauth2_install_params": .null]))
        for payload in [request as any GuildRequestPayload, install, config] {
            #expect(!String(describing: payload).contains("example.test"))
            #expect(!String(reflecting: payload).contains("340282"))
            #expect(Mirror(reflecting: payload).children.count == 1)
        }
    }

    /// Explicit clears and empty values remain distinct from omission for all preview-nullable PATCH fields.
    /// - Throws: Unexpected valid clear/empty request construction errors fail the test.
    @Test func nullableAndEmptyStates() throws {
        let clears = try ApplicationModify(customInstallURL: .null, description: .null,
            roleConnectionsVerificationURL: .null, installParams: .null, integrationTypesConfig: .null,
            flags: .null, icon: .null, coverImage: .null, interactionsEndpointURL: .null,
            tags: .null, eventWebhooksURL: .null, eventWebhooksStatus: .null, eventWebhooksTypes: .null,
            teamID: .null, type: .null, maxParticipants: .null, explicitContentFilter: .null)
        guard case .object(let fields) = clears.jsonValue() else { Issue.record("Expected clears"); return }
        #expect(fields.count == 17 && fields.values.allSatisfy { $0 == .null })
        #expect(try ApplicationModify(localizedDescription: .null).jsonValue() == .object(["description": .null]))
        let empty = try ApplicationModify(description: .value(""), flags: .value([]), tags: .value([]), eventWebhooksTypes: .value([]))
        #expect(empty.jsonValue() == .object(["description": .string(""), "flags": .number(try JSONNumber(rawValue: "0")), "tags": .array([]), "event_webhooks_types": .array([])]))
        #expect(try ApplicationModify(maxParticipants: .value(Int(Int32.max))).jsonValue() == .object(["max_participants": .number(try JSONNumber(rawValue: "2147483647"))]))
        #expect(try ApplicationModify(eventWebhooksStatus: .value(.disabled)).jsonValue() == .object(["event_webhooks_status": .number(try JSONNumber(rawValue: "1"))]))
        #expect(try ApplicationModify(explicitContentFilter: .value(.inherit)).jsonValue() == .object(["explicit_content_filter": .number(try JSONNumber(rawValue: "0"))]))
    }

    /// Text limits count Unicode scalars, tags are bounded/distinct and localized preview descriptions are explicit.
    /// - Throws: Unexpected valid boundary/localization construction errors fail the test; invalid boundaries are asserted.
    @Test func textBoundsAndLocalizedDescription() throws {
        let maximum = String(repeating: "é", count: 400)
        #expect(try ApplicationModify(description: .value(maximum)).jsonValue() == .object(["description": .string(maximum)]))
        #expect(throws: DiscordError.validation(.invalidValue)) { try ApplicationModify(description: .value(maximum + "x")) }
        let localized = try ApplicationLocalizedDescription(defaultValue: maximum, localizations: .value(["en-US": "", "future": "hello"]))
        #expect(localized.jsonValue() == .object(["default": .string(maximum), "localizations": .object(["en-US": .string(""), "future": .string("hello")])]))
        #expect(try ApplicationModify(localizedDescription: .value(localized)).jsonValue() == .object(["description": localized.jsonValue()]))
        #expect(try ApplicationLocalizedDescription(defaultValue: "").jsonValue() == .object(["default": .string("")]))
        #expect(try ApplicationLocalizedDescription(defaultValue: "d", localizations: .null).jsonValue() == .object(["default": .string("d"), "localizations": .null]))
        #expect(throws: DiscordError.validation(.invalidValue)) { try ApplicationLocalizedDescription(defaultValue: maximum + "x") }
        #expect(throws: DiscordError.validation(.invalidValue)) { try ApplicationLocalizedDescription(defaultValue: "d", localizations: .value(["en-US": maximum + "x"])) }
        for key in ["", "en\nUS"] {
            #expect(throws: DiscordError.validation(.invalidValue)) { try ApplicationLocalizedDescription(defaultValue: "d", localizations: .value([key: "value"])) }
        }
        for description in [Field<String>.null, .value("")] {
            #expect(throws: DiscordError.validation(.invalidValue)) { try ApplicationModify(description: description, localizedDescription: .value(localized)) }
        }
        #expect(try ApplicationModify(tags: .value((0..<5).map { String(repeating: String($0), count: 20) })).jsonValue() != .object([:]))
        #expect(throws: DiscordError.validation(.invalidValue)) { try ApplicationModify(tags: .value([String(repeating: "x", count: 21)])) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try ApplicationModify(tags: .value(["x", "x"])) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try ApplicationModify(tags: .value((0..<6).map(String.init))) }
    }

    /// Invalid URLs, media, mutable flag combinations, numeric bounds and duplicate subscriptions fail before I/O.
    /// - Throws: Unexpected fixture errors fail the test; every invalid request is expected to sanitize input.
    @Test func invalidPayloadBranches() throws {
        for url in ["", "relative", "ftp://example.test", "https://", "https://user:secret@example.test", "https://example.test/a b", "https://example.test/\n", "https://example.test/" + String(repeating: "a", count: 2048)] {
            for field in 0..<4 {
                #expect(throws: DiscordError.validation(.invalidValue)) {
                    switch field {
                    case 0: return try ApplicationModify(customInstallURL: .value(url))
                    case 1: return try ApplicationModify(roleConnectionsVerificationURL: .value(url))
                    case 2: return try ApplicationModify(interactionsEndpointURL: .value(url))
                    default: return try ApplicationModify(eventWebhooksURL: .value(url))
                    }
                }
            }
        }
        #expect(try applicationRequestURL("HTTP://example.test/path?one=two#fragment") == .string("HTTP://example.test/path?one=two#fragment"))
        for image in ["", "no-image", "data:image/png,AQ==", "data:;base64,AQ==", "data:image/png;base64,AB=="] {
            #expect(throws: DiscordError.validation(.invalidValue)) { try ApplicationModify(icon: .value(image)) }
            #expect(throws: DiscordError.validation(.invalidValue)) { try ApplicationModify(coverImage: .value(image)) }
        }
        #expect(try ApplicationModify(icon: .value("AQ=="), coverImage: .value("data:image/jpeg;base64,AQ==")).jsonValue() != .object([:]))
        for bits in [ApplicationFlags.gatewayPresence, .applicationCommandBadge, .init(rawValue: 1 << 63), .init(rawValue: UInt64.max)] {
            #expect(throws: DiscordError.validation(.invalidValue)) { try ApplicationModify(flags: .value(bits)) }
        }
        for count in [-2, Int.min, Int.max, Int(Int32.max) + 1] {
            #expect(throws: DiscordError.validation(.invalidValue)) { try ApplicationModify(maxParticipants: .value(count)) }
        }
        #expect(throws: DiscordError.validation(.invalidValue)) { try ApplicationModify(eventWebhooksStatus: .value(.disabledByDiscord)) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try ApplicationModify(eventWebhooksTypes: .value([.applicationAuthorized, .applicationAuthorized])) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try ApplicationModify(integrationTypesConfig: .value([:])) }
        #expect(try ApplicationModify(eventWebhooksTypes: .value(ApplicationWebhookEventType.allCases)).jsonValue() != .object([:]))
        for digits in ["", "-1", "+1", "1.0", "1e1", "١", " 1"] {
            #expect(throws: DiscordError.validation(.invalidValue)) { try ApplicationInstallParamsRequest(scopes: [.bot], permissions: digits) }
        }
        #expect(throws: DiscordError.validation(.invalidValue)) { try ApplicationInstallParamsRequest(scopes: [], permissions: "0") }
        #expect(throws: DiscordError.validation(.invalidValue)) { try ApplicationInstallParamsRequest(scopes: [.bot, .bot], permissions: "0") }
        #expect(try ApplicationInstallParamsRequest(scopes: [.applicationCommands], permissions: "0000").jsonValue() == .object(["scopes": .array([.string("applications.commands")]), "permissions": .string("0000")]))
        #expect(ApplicationInstallScope.allCases.count == 2)
    }
}
