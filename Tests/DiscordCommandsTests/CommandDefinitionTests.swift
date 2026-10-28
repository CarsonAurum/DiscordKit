// File: Tests/DiscordCommandsTests/CommandDefinitionTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import DiscordModels
import Foundation
import Testing
@testable import DiscordCommands

/// Exercises macro-free definitions through their observable validated wire payloads, with no Discord access.
@Suite struct CommandDefinitionTests {
    /// Every current option kind remains available through the existing typed validators and ordered builder.
    /// Conditional and loop statements preserve declaration order and all numeric/text/ID kinds survive unchanged.
    /// - Throws: Unexpected valid option/definition construction errors fail this test.
    @Test func typedOptionsAndBuilderBranches() throws {
        let kinds = ApplicationCommandOptionType.allCases.filter { $0 != .subcommand && $0 != .subcommandGroup }
        let options = try kinds.enumerated().map { try ApplicationCommandOptionCreate(type: $0.element, name: "value\($0.offset)", description: "Argument") }
        let definition = try CommandDefinition.slash(name: "test", description: "Description") {
            options[0]
            [options[1]]
            if true { options[2] }
            if false { options[3] } else { options[3] }
            for option in options.dropFirst(4) { option }
        }
        guard case .object(let body) = definition.request.jsonValue() else { Issue.record("Expected command object"); return }
        #expect(body["options"] == .array(options.map { $0.jsonValue() }))
        #expect(definition.request.type == .chatInput)
        #expect(try CommandDefinition.slash(name: "empty", description: "No arguments").request.name == "empty")
        #expect(CommandOptionsBuilder.buildOptional(nil).isEmpty)
        #expect(CommandOptionsBuilder.buildBlock().isEmpty)
        #expect(CommandOptionsBuilder.buildEither(first: options).count == kinds.count)
        #expect(CommandOptionsBuilder.buildArray([]).isEmpty)
    }

    /// Builders retain all localized/configuration fields and the advanced request-adoption escape hatch.
    /// User/message context-menu names can contain spaces and mixed case; only entry points accept handlers.
    /// - Parameter type: Both documented context-menu kinds.
    /// - Throws: Unexpected valid name/localization/permission/context construction errors fail this test.
    @Test(arguments: [ApplicationCommandType.user, .message]) func menuAndAdvancedFields(type: ApplicationCommandType) throws {
        let menu = try CommandDefinition.contextMenu(name: "Inspect Target", type: type,
            nameLocalizations: .value(["de": "Ziel Anzeigen"]), defaultMemberPermissions: .value("18446744073709551616"),
            integrationTypes: [.guildInstall, .userInstall], contexts: [.guild, .botDM, .privateChannel], nsfw: true)
        let adopted = CommandDefinition(menu.request)
        #expect(adopted.request.jsonValue() == menu.request.jsonValue())
        #expect(menu.request.type == type)
        guard case .object(let fields) = menu.request.jsonValue() else { Issue.record("Expected command object"); return }
        #expect(fields["name_localizations"] == .object(["de": .string("Ziel Anzeigen")]))
        #expect(fields["default_member_permissions"] == .string("18446744073709551616"))
        #expect(fields["nsfw"] == .bool(true))
        let slash = try CommandDefinition.slash(name: "localized", description: "Description",
            nameLocalizations: .value(["de": "lokal"]), descriptionLocalizations: .value(["de": "Beschreibung"]),
            defaultMemberPermissions: .null, integrationTypes: [.guildInstall], contexts: [.guild], nsfw: true)
        guard case .object(let slashFields) = slash.request.jsonValue() else { Issue.record("Expected slash object"); return }
        #expect(slashFields["description_localizations"] == .object(["de": .string("Beschreibung")]))
        #expect(slashFields["default_member_permissions"] == .null)
        for handler in ApplicationCommandHandler.allCases {
            let entry = try CommandDefinition.entryPoint(name: "Launch", description: "Activity", handler: handler)
            #expect(entry.request.type == .primaryEntryPoint)
            if case .object(let value) = entry.request.jsonValue() {
                #expect(value["handler"] == .number(try JSONNumber(rawValue: String(handler.rawValue))))
            } else { Issue.record("Expected entry-point object") }
        }
    }

    /// Invalid names, ordering, duplicate options, nesting, type combinations, caps and thrown builders fail synchronously.
    /// This verifies the ergonomic layer does not bypass the existing complete request validators.
    /// - Throws: Unexpected fixture construction errors fail the test; each invalid command is explicitly asserted.
    @Test func invalidDefinitionsBeforeTransmission() throws {
        let required = try ApplicationCommandOptionCreate(type: .string, name: "required", description: "d", required: true)
        let optional = try ApplicationCommandOptionCreate(type: .string, name: "optional", description: "d")
        #expect(throws: (any Error).self) { try CommandDefinition.slash(name: "Upper", description: "d") }
        #expect(throws: (any Error).self) { try CommandDefinition.slash(name: "valid", description: "") }
        #expect(throws: (any Error).self) { try CommandDefinition.slash(name: "valid", description: "d") { optional; required } }
        #expect(throws: (any Error).self) { try CommandDefinition.slash(name: "valid", description: "d") { required; required } }
        #expect(throws: (any Error).self) { try CommandDefinition.slash(name: "valid", description: "d") {
            for index in 0..<26 { try ApplicationCommandOptionCreate(type: .boolean, name: "option\(index)", description: "d") }
        } }
        let subcommand = try ApplicationCommandOptionCreate(type: .subcommand, name: "sub", description: "d", options: [required])
        let group = try ApplicationCommandOptionCreate(type: .subcommandGroup, name: "group", description: "d", options: [subcommand])
        #expect(try CommandDefinition.slash(name: "valid", description: "d") { group }.request.name == "valid")
        #expect(throws: (any Error).self) { try CommandDefinition.slash(name: "valid", description: "d") { group; optional } }
        for type in [ApplicationCommandType.chatInput, .primaryEntryPoint] {
            #expect(throws: DiscordError.validation(.invalidValue)) { try CommandDefinition.contextMenu(name: "name", type: type) }
        }
        #expect(throws: (any Error).self) { try CommandDefinition.slash(name: "valid", description: "d", defaultMemberPermissions: .value("-1")) }
        #expect(throws: (any Error).self) { try CommandDefinition.slash(name: "valid", description: "d", contexts: []) }
        #expect(throws: (any Error).self) { try CommandDefinition.slash(name: "valid", description: "d", nameLocalizations: .value(["invalid": "name"])) }
        #expect(throws: DiscordError.cancelled) { try CommandDefinition.slash(name: "valid", description: "d") { throw DiscordError.cancelled } }
    }
}
