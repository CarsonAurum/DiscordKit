// File: Tests/DiscordModelsTests/ApplicationCommandModelTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import Foundation
import Testing
@testable import DiscordModels

/// Command response contracts preserve exact IDs, localized data, future variants and bounded unknown payloads.
@Suite struct ApplicationCommandModelTests {
    /// Complete written fields and every nested option/choice field decode without narrowing precision or presence.
    /// - Throws: Unexpected fixture/projection errors fail this test.
    @Test func fullProjection() throws {
        let model = try ApplicationCommand(data: Data(Self.full.utf8))
        #expect(model.id.rawValue == UInt64.max)
        #expect(model.applicationID.rawValue == UInt64.max)
        #expect(model.type == .value(RawValue(.chatInput)))
        #expect(model.guildID == .value(.init(rawValue: 3)))
        #expect(model.name == "test" && model.commandDescription == "description")
        #expect(model.nameLocalizations == .value(["en-US": "test"]))
        #expect(model.descriptionLocalizations == .null)
        #expect(model.nameLocalized == .value("localized") && model.descriptionLocalized == .value("localized description"))
        #expect(model.defaultMemberPermissions == .value("18446744073709551616000"))
        #expect(model.dmPermission == .value(false) && model.defaultPermission == .null && model.nsfw == .value(true))
        #expect(model.integrationTypes == .value([RawValue(.guildInstall), RawValue(rawValue: 999)]))
        #expect(model.contexts == .value([RawValue(.guild), RawValue(.botDM), RawValue(rawValue: 999)]))
        #expect(model.version.rawValue == UInt64.max && model.handler == .value(RawValue(rawValue: 999)))
        let options = try #require(model.options.valueForCommandTest)
        let option = try #require(options.first)
        #expect(option.type == RawValue(.integer) && option.name == "number" && option.optionDescription == "value")
        #expect(option.nameLocalizations == .null && option.descriptionLocalizations == .value(["en-US": "value"]))
        #expect(option.nameLocalized == .value("number") && option.descriptionLocalized == .value("value"))
        #expect(option.required == .value(true) && option.autocomplete == .value(false))
        #expect(option.minValue == .value(try JSONNumber(rawValue: "-9007199254740991")))
        #expect(option.maxValue == .value(try JSONNumber(rawValue: "9007199254740991")))
        #expect(option.minLength == .value(0) && option.maxLength == .value(6000))
        #expect(option.channelTypes == .value([RawValue(.guildText), RawValue(rawValue: 999)]))
        #expect(option.fileTypes == .value(["image", ".PDF"]))
        let choices = try #require(option.choices.valueForCommandTest)
        let choice = try #require(choices.first)
        #expect(choice.name == "large" && choice.nameLocalizations == .null && choice.nameLocalized == .value("large"))
        #expect(choice.value == .number(try JSONNumber(rawValue: "9007199254740991")))
        #expect(choice.jsonValue() == .object(choice.rawFields))
        #expect(model.rawFields["future"] == .array([.number(try JSONNumber(rawValue: "1e999"))]))
        #expect(!String(reflecting: model).contains("localized"))
        #expect(Mirror(reflecting: model).children.count == 1)
        #expect(try ApplicationCommand(data: model.jsonValue().serialized()) == model)
        #expect(try ApplicationCommandOption(data: option.jsonValue().serialized()) == option)
        #expect(try ApplicationCommandChoice(data: choice.jsonValue().serialized()) == choice)
    }

    /// Missing optional fields remain absent, nullable fields retain null, and unknown integral enums remain readable.
    /// - Throws: Unexpected valid fixture errors fail this test; schema-invalid changes are asserted separately.
    @Test func minimumUnknownAndRecursiveOptions() throws {
        let minimal = try ApplicationCommand(data: Data(Self.minimum.utf8))
        #expect(minimal.type == .absent && minimal.guildID == .absent && minimal.options == .absent)
        #expect(minimal.nameLocalizations == .absent && minimal.contexts == .absent && minimal.defaultMemberPermissions == .null)
        #expect(minimal.handler == .absent && minimal.integrationTypes == .absent)
        let choice = try ApplicationCommandChoice(data: Data(#"{"name":"text","value":"private"}"#.utf8))
        #expect(choice.value == .string("private"))
        #expect(choice.nameLocalizations == .absent && choice.nameLocalized == .absent)
        let option = try ApplicationCommandOption(data: Data(#"{"type":999,"name":"future","description":"future","options":[{"type":1,"name":"sub","description":"sub","options":[]}]}"#.utf8))
        #expect(option.type.knownValue == nil)
        #expect(option.options.valueForCommandTest?.first?.options == .value([]))
        #expect(option.minValue == .absent && option.maxValue == .absent)
        let numeric = try ApplicationCommandChoice(data: Data(#"{"name":"future","value":1.000000000000000000001}"#.utf8))
        #expect(numeric.value == .number(try JSONNumber(rawValue: "1.000000000000000000001")))
        #expect(try ApplicationCommandChoiceValue(value: .number(try JSONNumber(rawValue: "-0"))).jsonValue() == .number(try JSONNumber(rawValue: "-0")))
        #expect(try ApplicationCommandChoiceValue(value: .string("")).jsonValue() == .string(""))
    }

    /// Every missing required command field, null prohibition and incompatible known optional field fails safely.
    /// - Throws: Unexpected parser/setup errors fail this test; all response violations are expected.
    @Test func malformedModels() throws {
        guard case .object(let complete) = try JSONValue.parse(Data(Self.minimum.utf8)) else { Issue.record("fixture"); return }
        for key in ["id", "application_id", "name", "description", "default_member_permissions", "version"] {
            var missing = complete; missing.removeValue(forKey: key)
            #expect(throws: (any Error).self) { try ApplicationCommand(data: JSONValue.object(missing).serialized()) }
        }
        for (key, value) in ["id": JSONValue.string("18446744073709551616"), "type": .number(try JSONNumber(rawValue: "1.5")),
            "name": .null, "options": .null, "contexts": .bool(true), "integration_types": .array([.string("0")]),
            "name_localizations": .array([]), "handler": .number(try JSONNumber(rawValue: "1e999"))] {
            var malformed = complete; malformed[key] = value
            #expect(throws: (any Error).self) { try ApplicationCommand(data: JSONValue.object(malformed).serialized()) }
        }
        for bytes in ["null", "[]", "{}", #"{"name":"x","value":null}"#, #"{"name":"x","value":true}"#, #"{"name":"x","value":[]}"#] {
            #expect(throws: (any Error).self) { try ApplicationCommandChoice(data: Data(bytes.utf8)) }
        }
        for bytes in [#"{"type":3,"name":"x","description":"x","min_value":"1"}"#,
            #"{"type":3,"name":"x","description":"x","choices":[{}]}"#,
            #"{"type":3,"name":"x","description":"x","options":false}"#] {
            #expect(throws: (any Error).self) { try ApplicationCommandOption(data: Data(bytes.utf8)) }
        }
        #expect(throws: (any Error).self) { try ApplicationCommand(data: Data(Self.full.utf8), limits: .init(maximumBytes: 10)) }
        #expect(throws: (any Error).self) { try ApplicationCommand(data: Data(Self.full.utf8), limits: .init(maximumNodes: 5)) }
        #expect(throws: (any Error).self) { try ApplicationCommand(data: Data(Self.full.utf8), limits: .init(maximumDepth: 1)) }
        #expect(throws: (any Error).self) { try ApplicationCommand(data: Data((Self.minimum + Self.minimum).utf8)) }
    }

    /// Command/application permission IDs and guild-derived constants retain all bits and unknown target kinds.
    /// - Throws: Unexpected fixture errors fail the test; required-field and exact-integer errors are expected.
    @Test func permissionProjections() throws {
        let bytes = Data(#"{"id":"18446744073709551615","application_id":"18446744073709551615","guild_id":"3","permissions":[{"id":"2","type":3,"permission":false},{"id":"3","type":1,"permission":true},{"id":"18446744073709551615","type":999,"permission":true}],"future":true}"#.utf8)
        let model = try GuildApplicationCommandPermissions(data: bytes)
        #expect(model.id.rawValue == UInt64.max && model.applicationID.rawValue == UInt64.max && model.guildID.rawValue == 3)
        #expect(model.permissions.count == 3 && model.permissions[0].id.rawValue == 2)
        #expect(!model.permissions[0].permission && model.permissions[1].permission && model.permissions[2].type.knownValue == nil)
        #expect(try GuildApplicationCommandPermissions(data: model.jsonValue().serialized()) == model)
        #expect(try ApplicationCommandPermission(data: model.permissions[0].jsonValue().serialized()) == model.permissions[0])
        #expect(try GuildApplicationCommandPermissions(data: Data(#"{"id":"1","application_id":"1","guild_id":"3","permissions":[]}"#.utf8)).permissions.isEmpty)
        for payload in ["{}", #"{"id":"1","type":1.1,"permission":true}"#, #"{"id":"1","type":1,"permission":null}"#] {
            #expect(throws: (any Error).self) { try ApplicationCommandPermission(data: Data(payload.utf8)) }
        }
        #expect(throws: (any Error).self) { try GuildApplicationCommandPermissions(data: Data(#"{"id":"1","application_id":"1","guild_id":"3","permissions":[{}]}"#.utf8)) }
    }

    /// Independent complete written command fixture with response-only future and localized fields.
    static let full = #"{"id":"18446744073709551615","application_id":"18446744073709551615","version":"18446744073709551615","type":1,"guild_id":"3","name":"test","name_localizations":{"en-US":"test"},"name_localized":"localized","description":"description","description_localizations":null,"description_localized":"localized description","default_member_permissions":"18446744073709551616000","dm_permission":false,"default_permission":null,"nsfw":true,"integration_types":[0,999],"contexts":[0,1,999],"handler":999,"options":[{"type":4,"name":"number","description":"value","name_localizations":null,"description_localizations":{"en-US":"value"},"name_localized":"number","description_localized":"value","required":true,"choices":[{"name":"large","name_localizations":null,"name_localized":"large","value":9007199254740991}],"options":[],"channel_types":[0,999],"min_value":-9007199254740991,"max_value":9007199254740991,"min_length":0,"max_length":6000,"autocomplete":false,"file_types":["image",".PDF"]}],"future":[1e999]}"#
    /// Minimum written command with optional type omitted and required nullable permission field present.
    static let minimum = #"{"id":"1","application_id":"2","name":"test","description":"description","default_member_permissions":null,"version":"3"}"#
}

extension Field {
    /// Extracts test fixture values without changing production presence semantics or adding visibility.
    /// - Returns: The present value, or nil for absent/null so tests must explicitly require it where necessary.
    fileprivate var valueForCommandTest: Value? { if case .value(let value) = self { value } else { nil } }
}
