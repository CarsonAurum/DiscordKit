// File: Tests/DiscordModelsTests/ApplicationCommandReplacementTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import DiscordModels
import Testing

/// Complete command-definition to PATCH conversion preserves managed defaults and omitted application settings.
@Suite struct ApplicationCommandReplacementTests {
    /// Every command kind gets valid known defaults while type and irrelevant slash options remain absent from PATCH.
    /// Repeated conversion is pure and leaves the source create body unchanged.
    /// - Parameter type: Every documented command kind, including global-only Activity entry points.
    /// - Throws: Unexpected valid fixture construction failures fail the test.
    @Test(arguments: ApplicationCommandType.allCases) func replacementDefaults(type: ApplicationCommandType) throws {
        let request = try ApplicationCommandCreate(name: "command", type: type,
            description: type == .chatInput || type == .primaryEntryPoint ? "Description" : nil)
        let original = request.jsonValue(), first = request.replacementChanges(), second = request.replacementChanges()
        #expect(first.type == type && first.jsonValue() == second.jsonValue())
        #expect(request.jsonValue() == original)
        guard case .object(let fields) = first.jsonValue() else { Issue.record("Expected edit object"); return }
        #expect(fields["type"] == nil && fields["name"] == .string("command"))
        #expect(fields["description"] == .string(type == .chatInput || type == .primaryEntryPoint ? "Description" : ""))
        #expect(fields["name_localizations"] == .null && fields["description_localizations"] == .null)
        #expect(fields["default_member_permissions"] == .null && fields["nsfw"] == .bool(false))
        #expect(fields["options"] == (type == .chatInput ? .array([]) : nil))
        for key in ["integration_types", "contexts", "handler", "dm_permission", "default_permission"] { #expect(fields[key] == nil) }
    }

    /// Explicit scalar/null/localization/options/install fields survive exactly; conversion adds no resetting omission.
    /// - Throws: Unexpected typed option, choice or command construction failures fail this test.
    @Test func explicitConfigurationIsExact() throws {
        let choice = try ApplicationCommandChoiceCreate(name: "One", value: .number(try JSONNumber(rawValue: "1")),
            nameLocalizations: .value(["de": "Eins"]))
        let option = try ApplicationCommandOptionCreate(type: .integer, name: "count", description: "Count",
            nameLocalizations: .value(["de": "anzahl"]), required: true, choices: [choice])
        let request = try ApplicationCommandCreate(name: "command", description: "Description",
            nameLocalizations: .value(["de": "befehl"]), descriptionLocalizations: .value(["de": "Beschreibung"]),
            options: [option], defaultMemberPermissions: .value("18446744073709551616"), dmPermission: .null,
            defaultPermission: false, integrationTypes: [.guildInstall, .userInstall], contexts: [.guild, .botDM], nsfw: true)
        guard case .object(var expected) = request.jsonValue() else { Issue.record("Expected create object"); return }
        expected.removeValue(forKey: "type")
        #expect(request.replacementChanges().jsonValue() == .object(expected))
        for handler in ApplicationCommandHandler.allCases {
            let entry = try ApplicationCommandCreate(name: "Launch", type: .primaryEntryPoint, description: "Activity", handler: handler)
            guard case .object(let fields) = entry.replacementChanges().jsonValue() else { Issue.record("Expected entry edit"); return }
            #expect(fields["handler"] == .number(try JSONNumber(rawValue: String(handler.rawValue))))
            #expect(fields["options"] == nil)
        }
    }
}
