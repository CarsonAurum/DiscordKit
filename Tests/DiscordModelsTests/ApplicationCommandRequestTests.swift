// File: Tests/DiscordModelsTests/ApplicationCommandRequestTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import Foundation
import Testing
@testable import DiscordModels

/// Command payloads validate complete bounded trees, exact numeric choices, localizations and destructive replacement boundaries.
@Suite struct ApplicationCommandRequestTests {
    /// All command types and writable fields encode with exact null/omission, context, handler and legacy semantics.
    /// - Throws: Unexpected valid construction failures fail this test.
    @Test func commandKindsAndFields() throws {
        let permissions = String(repeating: "9", count: 100)
        let create = try ApplicationCommandCreate(name: "command", description: "description",
            nameLocalizations: .value(["de": "befehl"]), descriptionLocalizations: .null,
            options: [], defaultMemberPermissions: .value(permissions), dmPermission: .null,
            defaultPermission: false, integrationTypes: [.guildInstall, .userInstall],
            contexts: [.guild, .botDM, .privateChannel], nsfw: true)
        guard case .object(let fields) = create.jsonValue() else { Issue.record("object"); return }
        #expect(create.name == "command" && create.type == .chatInput)
        #expect(fields["type"] == .number(try JSONNumber(rawValue: "1")))
        #expect(fields["description_localizations"] == .null && fields["options"] == .array([]))
        #expect(fields["default_member_permissions"] == .string(permissions) && fields["dm_permission"] == .null)
        #expect(fields["default_permission"] == .bool(false) && fields["nsfw"] == .bool(true))
        #expect(fields["integration_types"] == .array([.number(try JSONNumber(rawValue: "0")), .number(try JSONNumber(rawValue: "1"))]))
        #expect(fields["contexts"] == .array([.number(try JSONNumber(rawValue: "0")), .number(try JSONNumber(rawValue: "1")), .number(try JSONNumber(rawValue: "2"))]))
        for kind in [ApplicationCommandType.user, .message] {
            let body = try ApplicationCommandCreate(name: "A Mixed Name", type: kind, description: "")
            #expect(body.type == kind && body.name == "A Mixed Name")
            #expect(!String(reflecting: body).contains("Mixed"))
        }
        for handler in ApplicationCommandHandler.allCases {
            let entry = try ApplicationCommandCreate(name: "Launch App", type: .primaryEntryPoint,
                description: "Start the activity", handler: handler)
            #expect(entry.jsonValue().commandTestFields?["handler"] == .number(try JSONNumber(rawValue: String(handler.rawValue))))
        }
        #expect(try ApplicationCommandModify().jsonValue() == .object([:]))
        let modified = try ApplicationCommandModify(type: .primaryEntryPoint, name: .value("New Launch"),
            description: .value("updated"), nameLocalizations: .null, descriptionLocalizations: .value(["fr": "exemple"]),
            defaultMemberPermissions: .null, dmPermission: .value(false), defaultPermission: true,
            integrationTypes: [.userInstall], contexts: [.privateChannel], nsfw: false, handler: .appHandler)
        #expect(modified.type == .primaryEntryPoint && modified.jsonValue().commandTestFields?["type"] == nil)
        #expect(modified.jsonValue().commandTestFields?["default_member_permissions"] == .null)
        #expect(modified.jsonValue().commandTestFields?["dm_permission"] == .bool(false))
        #expect(modified.jsonValue().commandTestFields?["name_localizations"] == .null)
        #expect(try ApplicationCommandModify(options: []).jsonValue() == .object(["options": .array([])]))
    }

    /// Unicode naming, localized names, required descriptions and strict nullable/type contexts reject unsupported payloads.
    /// - Throws: Fixture construction errors fail the test; invalid names/fields are asserted.
    @Test func namesLocalizationsAndCommandFailures() throws {
        for name in ["normal", "café", "ภาษาไทย", "हिन्दी", "a-b_cʼ", String(repeating: "a", count: 32)] {
            #expect(try ApplicationCommandCreate(name: name, description: "d").name == name)
        }
        for name in ["", "A", "two words", "a.b", "name\n", "🌲", String(repeating: "a", count: 33)] {
            #expect(throws: (any Error).self) { try ApplicationCommandCreate(name: name, description: "d") }
        }
        #expect(throws: DiscordError.validation(.missingValue)) { try ApplicationCommandCreate(name: "valid") }
        for kind in [ApplicationCommandType.user, .message] {
            #expect(throws: (any Error).self) { try ApplicationCommandCreate(name: "Name", type: kind, description: "nonempty") }
            #expect(throws: (any Error).self) { try ApplicationCommandCreate(name: "Name", type: kind, options: []) }
            #expect(throws: (any Error).self) { try ApplicationCommandCreate(name: "Name", type: kind, handler: .appHandler) }
            #expect(throws: (any Error).self) { try ApplicationCommandCreate(name: "Name", type: kind, descriptionLocalizations: .value(["en-US": "text"])) }
        }
        #expect(throws: (any Error).self) { try ApplicationCommandCreate(name: "x", description: "") }
        #expect(throws: (any Error).self) { try ApplicationCommandCreate(name: "x", description: String(repeating: "d", count: 101)) }
        #expect(throws: (any Error).self) { try ApplicationCommandModify(name: .null) }
        #expect(throws: (any Error).self) { try ApplicationCommandModify(description: .null) }
        for dictionary in [["unknown": "valid"], ["en-US": "Upper"], ["de": ""], ["fr": String(repeating: "x", count: 33)]] {
            #expect(throws: (any Error).self) { try ApplicationCommandCreate(name: "valid", description: "valid", nameLocalizations: .value(dictionary)) }
        }
        for permission in ["", "-1", "+1", "01", "1.0", "1e2", String(repeating: "9", count: 1025)] {
            #expect(throws: (any Error).self) { try ApplicationCommandCreate(name: "valid", description: "valid", defaultMemberPermissions: .value(permission)) }
        }
        #expect(try ApplicationCommandCreate(name: "x", description: "x", defaultMemberPermissions: .value("0")).jsonValue().commandTestFields?["default_member_permissions"] == .string("0"))
        #expect(throws: (any Error).self) { try ApplicationCommandCreate(name: "x", description: "x", integrationTypes: []) }
        #expect(throws: (any Error).self) { try ApplicationCommandCreate(name: "x", description: "x", integrationTypes: [.guildInstall, .guildInstall]) }
        #expect(throws: (any Error).self) { try ApplicationCommandCreate(name: "x", description: "x", contexts: []) }
        #expect(throws: (any Error).self) { try ApplicationCommandCreate(name: "x", description: "x", contexts: [.guild, .guild]) }
    }

    /// Every leaf kind validates only its supported fields; numeric choice lexemes and attachment filters remain exact.
    /// - Throws: Unexpected legal boundary failures fail this test.
    @Test func completeOptions() throws {
        for kind in ApplicationCommandOptionType.allCases {
            let option = try ApplicationCommandOptionCreate(type: kind, name: "option", description: "description")
            #expect(option.type == kind && option.name == "option" && option.required == nil)
            #expect(option.jsonValue().commandTestFields?["type"] == .number(try JSONNumber(rawValue: String(kind.rawValue))))
        }
        let choice = try ApplicationCommandChoiceCreate(name: "Name", value: .string(""), nameLocalizations: .value(["fr": "Nom"]))
        let string = try ApplicationCommandOptionCreate(type: .string, name: "text", description: "value",
            nameLocalizations: .null, descriptionLocalizations: .value(["fr": "texte"]), required: true,
            choices: [choice], minLength: 0, maxLength: 6000, autocomplete: false)
        #expect(string.required == true && string.jsonValue().commandTestFields?["choices"] == .array([choice.jsonValue()]))
        for boundary in ["-9007199254740991", "0", "9007199254740991"] {
            let number = try JSONNumber(rawValue: boundary)
            let choice = try ApplicationCommandChoiceCreate(name: "number", value: .number(number), nameLocalizations: .null)
            let option = try ApplicationCommandOptionCreate(type: .integer, name: "integer", description: "value",
                choices: [choice], minValue: number, maxValue: number)
            #expect(option.jsonValue().commandTestFields?["min_value"] == .number(number))
        }
        let number = try JSONNumber(rawValue: "-9007199254740992")
        #expect(try ApplicationCommandOptionCreate(type: .number, name: "number", description: "value",
            minValue: number, maxValue: JSONNumber(rawValue: "9007199254740992"), autocomplete: true).jsonValue().commandTestFields?["autocomplete"] == .bool(true))
        let channel = try ApplicationCommandOptionCreate(type: .channel, name: "channel", description: "value", channelTypes: [.guildText, .guildVoice])
        #expect(channel.jsonValue().commandTestFields?["channel_types"]?.commandTestArray?.count == 2)
        let attachment = try ApplicationCommandOptionCreate(type: .attachment, name: "file", description: "upload", fileTypes: ["image", "video", "audio", ".PDF"])
        #expect(attachment.jsonValue().commandTestFields?["file_types"] == .array([.string("image"), .string("video"), .string("audio"), .string(".PDF")]))
        #expect(try ApplicationCommandChoiceCreate(name: "x", value: .string(String(repeating: "x", count: 100))).jsonValue().commandTestFields?["value"] == .string(String(repeating: "x", count: 100)))
        #expect(throws: (any Error).self) { try ApplicationCommandChoiceCreate(name: "", value: .string("x")) }
        #expect(throws: (any Error).self) { try ApplicationCommandChoiceCreate(name: "x", value: .string(String(repeating: "x", count: 101))) }
    }

    /// Incompatible fields, malformed numeric boundaries and invalid filters fail before any registration request.
    /// - Throws: Unexpected numeric fixture setup errors fail the test; invalid option construction is asserted.
    @Test func optionFailures() throws {
        let text = try ApplicationCommandChoiceCreate(name: "x", value: .string("x"))
        let numeric = try ApplicationCommandChoiceCreate(name: "x", value: .number(JSONNumber(rawValue: "1.5")))
        for kind in [ApplicationCommandOptionType.boolean, .user, .role, .mentionable, .attachment, .channel, .subcommand] {
            #expect(throws: (any Error).self) { try ApplicationCommandOptionCreate(type: kind, name: "x", description: "x", choices: [text]) }
            #expect(throws: (any Error).self) { try ApplicationCommandOptionCreate(type: kind, name: "x", description: "x", autocomplete: false) }
            #expect(throws: (any Error).self) { try ApplicationCommandOptionCreate(type: kind, name: "x", description: "x", minValue: JSONNumber(rawValue: "1")) }
        }
        #expect(throws: (any Error).self) { try ApplicationCommandOptionCreate(type: .string, name: "x", description: "x", choices: [numeric]) }
        #expect(throws: (any Error).self) { try ApplicationCommandOptionCreate(type: .integer, name: "x", description: "x", choices: [text]) }
        #expect(throws: (any Error).self) { try ApplicationCommandOptionCreate(type: .integer, name: "x", description: "x", choices: [numeric]) }
        #expect(throws: (any Error).self) { try ApplicationCommandOptionCreate(type: .string, name: "x", description: "x", choices: [], autocomplete: true) }
        #expect(throws: (any Error).self) { try ApplicationCommandOptionCreate(type: .string, name: "x", description: "x", choices: Array(repeating: text, count: 26)) }
        for spelling in ["9007199254740992", "-9007199254740992", "1.0", "1e0", "1e999"] {
            #expect(throws: (any Error).self) { try ApplicationCommandOptionCreate(type: .integer, name: "x", description: "x", minValue: JSONNumber(rawValue: spelling)) }
        }
        #expect(throws: (any Error).self) { try ApplicationCommandChoiceCreate(name: "x", value: .number(JSONNumber(rawValue: "1e999"))) }
        #expect(throws: (any Error).self) { try ApplicationCommandChoiceCreate(name: "x", value: .number(JSONNumber(rawValue: "9007199254740993"))) }
        for spelling in ["9007199254740992.000000000000001", "9.007199254740993e15", "-9007199254740993"] {
            #expect(throws: (any Error).self) { try ApplicationCommandChoiceCreate(name: "x", value: .number(JSONNumber(rawValue: spelling))) }
        }
        for spelling in ["9.007199254740992e15", "-0e999999999999999999999", "1e-999999999999999999999", "0.00001", "1000e-3"] {
            #expect(try ApplicationCommandChoiceCreate(name: "x", value: .number(JSONNumber(rawValue: spelling))).jsonValue().commandTestFields?["value"] == .number(JSONNumber(rawValue: spelling)))
        }
        #expect(throws: (any Error).self) { try ApplicationCommandOptionCreate(type: .number, name: "x", description: "x", minValue: JSONNumber(rawValue: "2"), maxValue: JSONNumber(rawValue: "1")) }
        for (minimum, maximum) in [(-1, 1), (0, 0), (6001, 6001), (2, 1)] {
            #expect(throws: (any Error).self) { try ApplicationCommandOptionCreate(type: .string, name: "x", description: "x", minLength: minimum, maxLength: maximum) }
        }
        #expect(throws: (any Error).self) { try ApplicationCommandOptionCreate(type: .integer, name: "x", description: "x", minLength: 0) }
        #expect(throws: (any Error).self) { try ApplicationCommandOptionCreate(type: .string, name: "x", description: "x", channelTypes: []) }
        #expect(throws: (any Error).self) { try ApplicationCommandOptionCreate(type: .channel, name: "x", description: "x", channelTypes: [.guildText, .guildText]) }
        for filters in [["invalid"], ["."], [".a/b"], [".a b"], [".a\\b"], [".PDF", ".pdf"], [String(repeating: "a", count: 17)], Array(repeating: "image", count: 11)] {
            #expect(throws: (any Error).self) { try ApplicationCommandOptionCreate(type: .attachment, name: "x", description: "x", fileTypes: filters) }
        }
        #expect(throws: (any Error).self) { try ApplicationCommandOptionCreate(type: .string, name: "x", description: "x", fileTypes: []) }
    }

    /// Group→subcommand→leaf hierarchy, sibling names, ordering and aggregate longest-localized text stay bounded.
    /// - Throws: Unexpected legal hierarchy construction failures fail this test.
    @Test func nestingOrderingAndTextBudget() throws {
        let required = try ApplicationCommandOptionCreate(type: .string, name: "required", description: "r", required: true)
        let optional = try ApplicationCommandOptionCreate(type: .string, name: "optional", description: "o")
        let sub = try ApplicationCommandOptionCreate(type: .subcommand, name: "sub", description: "s", options: [required, optional])
        let group = try ApplicationCommandOptionCreate(type: .subcommandGroup, name: "group", description: "g", options: [sub])
        #expect(try ApplicationCommandCreate(name: "root", description: "r", options: [group, sub]).jsonValue().commandTestFields?["options"]?.commandTestArray?.count == 2)
        #expect(throws: (any Error).self) { try ApplicationCommandCreate(name: "root", description: "r", options: [sub, optional]) }
        #expect(throws: (any Error).self) { try ApplicationCommandCreate(name: "root", description: "r", options: [optional, required]) }
        #expect(throws: (any Error).self) { try ApplicationCommandCreate(name: "root", description: "r", options: [optional, optional]) }
        #expect(throws: (any Error).self) { try ApplicationCommandCreate(name: "root", description: "r", options: Array(repeating: optional, count: 26)) }
        #expect(throws: (any Error).self) { try ApplicationCommandOptionCreate(type: .subcommand, name: "x", description: "x", required: false) }
        #expect(throws: (any Error).self) { try ApplicationCommandOptionCreate(type: .subcommand, name: "x", description: "x", options: [sub]) }
        #expect(throws: (any Error).self) { try ApplicationCommandOptionCreate(type: .subcommandGroup, name: "x", description: "x", options: [group]) }
        #expect(throws: (any Error).self) { try ApplicationCommandOptionCreate(type: .subcommandGroup, name: "x", description: "x", options: [optional]) }
        #expect(throws: (any Error).self) { try ApplicationCommandOptionCreate(type: .boolean, name: "x", description: "x", options: []) }
        let choices = try (0..<25).map { try ApplicationCommandChoiceCreate(name: "choice\($0)", value: .string(String(repeating: "x", count: 100))) }
        let expensive = try (0..<3).map { try ApplicationCommandOptionCreate(type: .string, name: "option\($0)", description: String(repeating: "d", count: 100),
            descriptionLocalizations: .value(["fr": String(repeating: "f", count: 100)]), choices: choices) }
        #expect(throws: DiscordError.validation(.limitExceeded)) { try ApplicationCommandCreate(name: "root", description: "r", options: expensive) }
        let localChoice = try ApplicationCommandChoiceCreate(name: "a", value: .string("x"), nameLocalizations: .value(["fr": String(repeating: "f", count: 100)]))
        let localizedExpensive = try (0..<4).map { try ApplicationCommandOptionCreate(type: .string, name: "option\($0)", description: "r", choices: Array(repeating: localChoice, count: 25)) }
        #expect(throws: DiscordError.validation(.limitExceeded)) { try ApplicationCommandCreate(name: "root", description: "r", options: localizedExpensive) }
    }

    /// Explicit bulk replacement enforces kind quotas, name/type uniqueness, stable IDs and empty destructive semantics.
    /// - Throws: Unexpected valid boundary failures fail this test.
    @Test func bulkBoundariesAndIdentity() throws {
        #expect(try BulkApplicationCommands(commands: []).jsonValue() == .array([]))
        var full: [ApplicationCommandRegistration] = []
        for kind in ApplicationCommandType.allCases {
            let maximum = kind == .chatInput ? 100 : (kind == .primaryEntryPoint ? 1 : 15)
            let entries = try (0..<maximum).map { index in
                ApplicationCommandRegistration(command: try ApplicationCommandCreate(name: "name\(index)", type: kind,
                    description: (kind == .chatInput || kind == .primaryEntryPoint) ? "description" : nil))
            }
            full += entries
            #expect(throws: (any Error).self) { try BulkApplicationCommands(commands: entries + [ApplicationCommandRegistration(command: ApplicationCommandCreate(name: "extra", type: kind, description: kind == .chatInput || kind == .primaryEntryPoint ? "d" : nil))]) }
        }
        #expect(try BulkApplicationCommands(commands: full).commands.count == 131)
        let command = try ApplicationCommandCreate(name: "same", description: "d")
        let entry = ApplicationCommandRegistration(command: command, id: .init(rawValue: UInt64.max))
        #expect(entry.jsonValue().commandTestFields?["id"] == .string("18446744073709551615"))
        #expect(throws: (any Error).self) { try BulkApplicationCommands(commands: [entry, entry]) }
        let otherType = ApplicationCommandRegistration(command: try ApplicationCommandCreate(name: "same", type: .user), id: .init(rawValue: UInt64.max))
        #expect(throws: (any Error).self) { try BulkApplicationCommands(commands: [entry, otherType]) }
        let unique = ApplicationCommandRegistration(command: try ApplicationCommandCreate(name: "same", type: .user))
        #expect(try BulkApplicationCommands(commands: [entry, unique]).commands.count == 2)
    }

    /// Permission payloads preserve every target type, deny flags, UInt64 IDs, 100-entry caps and explicit clearing.
    /// - Throws: Unexpected valid payload encoding failures fail this test.
    @Test func permissionPayloads() throws {
        let entries = try (0..<100).map { index in
            try ApplicationCommandPermissionOverwrite(id: .init(rawValue: UInt64.max - UInt64(index)),
                type: ApplicationCommandPermissionType.allCases[index % 3], permission: index % 2 == 0)
        }
        let request = try ApplicationCommandPermissionsModify(permissions: entries)
        #expect(request.jsonValue().commandTestFields?["permissions"]?.commandTestArray?.count == 100)
        #expect(entries[0].jsonValue().commandTestFields?["id"] == .string("18446744073709551615"))
        #expect(entries[1].jsonValue().commandTestFields?["permission"] == .bool(false))
        #expect(try ApplicationCommandPermissionsModify(permissions: []).jsonValue() == .object(["permissions": .array([])]))
        #expect(throws: (any Error).self) { try ApplicationCommandPermissionsModify(permissions: entries + [entries[0]]) }
        #expect(throws: (any Error).self) { try ApplicationCommandPermissionsModify(permissions: [entries[0], entries[0]]) }
        let role = try ApplicationCommandPermissionOverwrite(id: .init(rawValue: 3), type: .role, permission: true)
        let channel = try ApplicationCommandPermissionOverwrite(id: .init(rawValue: 3), type: .channel, permission: false)
        #expect(try ApplicationCommandPermissionsModify(permissions: [role, channel]).jsonValue().commandTestFields?["permissions"]?.commandTestArray?.count == 2)
    }
}

extension JSONValue {
    /// Extracts an object for concrete wire assertions without weakening the production JSON type.
    /// - Returns: Object fields or nil for another root.
    fileprivate var commandTestFields: [String: JSONValue]? { if case .object(let fields) = self { fields } else { nil } }
    /// Extracts arrays for concrete count/order assertions without serializing through Foundation JSON.
    /// - Returns: Array elements or nil for another root.
    fileprivate var commandTestArray: [JSONValue]? { if case .array(let values) = self { values } else { nil } }
}
