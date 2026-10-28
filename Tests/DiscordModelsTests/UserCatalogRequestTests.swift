// File: Tests/DiscordModelsTests/UserCatalogRequestTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import Foundation
import Testing
@testable import DiscordModels

/// Finite, synchronous user and linked-role request validation without token exchange or live Discord traffic.
@Suite struct UserCatalogRequestTests {
    /// Account edits preserve omission/null/value, canonical image syntax and published username restrictions.
    /// - Throws: Unexpected construction errors fail this test; invalid inputs are asserted explicitly.
    @Test func accountEditsAndBoundaries() throws {
        #expect(try UserModify().jsonValue() == .object([:]))
        let request = try UserModify(username: .value("  User name  "), avatar: .null,
            banner: .value("data:image/png;base64,AQ=="))
        #expect(request.jsonValue() == .object(["username": .string("  User name  "), "avatar": .null,
            "banner": .string("data:image/png;base64,AQ==")]))
        for valid in ["ab", String(repeating: "é", count: 32), "emoji😀", "User Name"] {
            #expect(try UserModify(username: .value(valid)).jsonValue() == .object(["username": .string(valid)]))
        }
        #expect(try UserModify(avatar: .value("AQ=="), banner: .null).jsonValue() == .object(["avatar": .string("AQ=="), "banner": .null]))
        #expect(throws: DiscordError.validation(.invalidValue)) { try UserModify(username: .null) }
        for invalid in ["", "a", "   ", String(repeating: "é", count: 33), "everyone", "HERE", "@name", "a#b", "a:b", "a```b", "DiScOrDUser"] {
            #expect(throws: DiscordError.validation(.invalidValue)) { try UserModify(username: .value(invalid)) }
        }
        for image in ["", "not-image", "AQ", "AQ==\n", "data:text/plain;base64,AQ==", "data:image/;base64,AQ==", "data:image/png,AQ=="] {
            #expect(throws: DiscordError.validation(.invalidValue)) { try UserModify(avatar: .value(image)) }
            #expect(throws: DiscordError.validation(.invalidValue)) { try UserModify(banner: .value(image)) }
        }
        #expect(!String(describing: request).contains("User name"))
        #expect(!String(reflecting: request).contains("AQ==")); #expect(request.customMirror.children.count == 1)
    }

    /// DM and legacy group-DM bodies retain exact IDs, ordered participant tokens and distinct nullable nicknames.
    /// All token exposure is explicit and limited to the jsonValue representation.
    /// - Throws: Unexpected request/token construction failures fail this test.
    @Test func directAndGroupDMRequests() throws {
        let recipient = UserID(rawValue: UInt64.max)
        let dm = UserDMCreate(recipientID: recipient)
        #expect(dm.recipientID == recipient)
        #expect(dm.jsonValue() == .object(["recipient_id": .string("18446744073709551615")]))
        let tokens = [try BearerToken("participant-one"), try BearerToken("participant-two")]
        let group = try UserGroupDMCreate(accessTokens: tokens, nicks: [recipient: .value("nickname"), .init(rawValue: 1): .null])
        #expect(group.jsonValue() == .object(["access_tokens": .array([.string("participant-one"), .string("participant-two")]),
            "nicks": .object(["18446744073709551615": .string("nickname"), "1": .null])]))
        #expect(try UserGroupDMCreate(accessTokens: []).jsonValue() == .object(["access_tokens": .array([]), "nicks": .object([:])]))
        #expect(try UserGroupDMCreate(accessTokens: tokens, nicks: [recipient: .value(String(repeating: "a", count: 32))]).jsonValue() != .null)
        #expect(throws: DiscordError.validation(.invalidValue)) { try UserGroupDMCreate(accessTokens: [tokens[0], tokens[0]]) }
        for invalid in ["", String(repeating: "a", count: 33)] {
            #expect(throws: DiscordError.validation(.invalidValue)) { try UserGroupDMCreate(accessTokens: tokens, nicks: [recipient: .value(invalid)]) }
        }
        #expect(throws: DiscordError.validation(.invalidValue)) {
            try UserGroupDMCreate(accessTokens: [BearerToken(String(repeating: "a", count: 152_134))])
        }
        let tooManyTokens = try (0..<1_522).map { try BearerToken("token-\($0)") }
        #expect(throws: DiscordError.validation(.invalidValue)) { try UserGroupDMCreate(accessTokens: tooManyTokens) }
        let names = Dictionary(uniqueKeysWithValues: (0..<1_522).map { (UserID(rawValue: UInt64($0)), Nullable<String>.null) })
        #expect(throws: DiscordError.validation(.invalidValue)) { try UserGroupDMCreate(accessTokens: [], nicks: names) }
        for value in [String(describing: group), String(reflecting: group)] {
            #expect(!value.contains("participant")); #expect(!value.contains("nickname"))
        }
        #expect(group.customMirror.children.count == 1)
        #expect(!String(describing: dm).contains("18446744073709551615"))
    }

    /// Each known metadata comparison type encodes exactly and localizations preserve omission, dictionary null and entry null.
    /// - Parameter type: Every supported linked-role comparison, including date and Boolean variants.
    /// - Throws: Unexpected valid construction errors fail the test.
    @Test(arguments: ApplicationRoleConnectionMetadataType.allCases)
    func metadataRecordEncoding(type: ApplicationRoleConnectionMetadataType) throws {
        let record = try ApplicationRoleConnectionMetadataRecord(type: type, key: "score_09", name: "Score",
            description: "Description", nameLocalizations: .value(["en-US": .value("Score"), "ja": .null]),
            descriptionLocalizations: .null)
        #expect(record.key == "score_09")
        #expect(record.jsonValue() == .object(["type": .number(try JSONNumber(rawValue: String(type.rawValue))),
            "key": .string("score_09"), "name": .string("Score"), "description": .string("Description"),
            "name_localizations": .object(["en-US": .string("Score"), "ja": .null]), "description_localizations": .null]))
        #expect(try Self.record(key: "a").jsonValue() == .object(["type": .number(try JSONNumber(rawValue: "1")),
            "key": .string("a"), "name": .string("Name"), "description": .string("Description")]))
        #expect(!String(describing: record).contains("score_09")); #expect(!String(reflecting: record).contains("Description"))
        #expect(record.customMirror.children.count == 1)
    }

    /// Key grammar, text/localization limits and the five-distinct-definition replacement contract reject malformed data.
    /// Empty replacement and top-level null are intentional distinct clears, never hidden list merging.
    /// - Throws: Unexpected valid fixture construction errors fail this test.
    @Test func metadataDefinitionAndReplacementBounds() throws {
        for key in ["a", "0", "_", String(repeating: "a", count: 50)] { #expect(try Self.record(key: key).key == key) }
        for key in ["", "A", "a-b", "with space", "é", "a/b", String(repeating: "a", count: 51)] {
            #expect(throws: DiscordError.validation(.invalidValue)) { try Self.record(key: key) }
        }
        #expect(try ApplicationRoleConnectionMetadataRecord(type: .booleanEqual, key: "a", name: String(repeating: "é", count: 100), description: String(repeating: "é", count: 200)).key == "a")
        for name in ["", String(repeating: "n", count: 101)] {
            #expect(throws: DiscordError.validation(.invalidValue)) { try ApplicationRoleConnectionMetadataRecord(type: .integerEqual, key: "a", name: name, description: "d") }
        }
        for description in ["", String(repeating: "d", count: 201)] {
            #expect(throws: DiscordError.validation(.invalidValue)) { try ApplicationRoleConnectionMetadataRecord(type: .integerEqual, key: "a", name: "n", description: description) }
        }
        for invalid in ["", String(repeating: "n", count: 101)] {
            #expect(throws: DiscordError.validation(.invalidValue)) {
                try ApplicationRoleConnectionMetadataRecord(type: .integerEqual, key: "a", name: "n", description: "d", nameLocalizations: .value(["en-US": .value(invalid)]))
            }
        }
        for invalid in ["", String(repeating: "d", count: 201)] {
            #expect(throws: DiscordError.validation(.invalidValue)) {
                try ApplicationRoleConnectionMetadataRecord(type: .integerEqual, key: "a", name: "n", description: "d", descriptionLocalizations: .value(["ja": .value(invalid)]))
            }
        }
        #expect(throws: DiscordError.validation(.invalidValue)) {
            try ApplicationRoleConnectionMetadataRecord(type: .integerEqual, key: "a", name: "n", description: "d", nameLocalizations: .value(["future-locale": .null]))
        }
        let localeOverflow = Dictionary(uniqueKeysWithValues: (0..<1_522).map { ("locale\($0)", Nullable<String>.null) })
        #expect(throws: DiscordError.validation(.invalidValue)) {
            try ApplicationRoleConnectionMetadataRecord(type: .integerEqual, key: "a", name: "n", description: "d", nameLocalizations: .value(localeOverflow))
        }
        let records = try (0..<5).map { try Self.record(key: "key_\($0)") }
        #expect(try ApplicationRoleConnectionMetadataUpdate(records: .value(records)).jsonValue() == .array(records.map { $0.jsonValue() }))
        #expect(try ApplicationRoleConnectionMetadataUpdate(records: .value([])).jsonValue() == .array([]))
        #expect(try ApplicationRoleConnectionMetadataUpdate(records: .null).jsonValue() == .null)
        #expect(throws: DiscordError.validation(.invalidValue)) { try ApplicationRoleConnectionMetadataUpdate(records: .value(records + [Self.record(key: "six")])) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try ApplicationRoleConnectionMetadataUpdate(records: .value([records[0], records[0]])) }
    }

    /// User role-connection updates preserve optional clears and stringified metadata without guessing comparison types.
    /// - Throws: Unexpected valid construction errors fail this test; every documented boundary is asserted.
    @Test func userRoleConnectionUpdates() throws {
        #expect(try ApplicationRoleConnectionUpdate().jsonValue() == .object([:]))
        #expect(try ApplicationRoleConnectionUpdate(platformName: .null, platformUsername: .null, metadata: .null).jsonValue() == .object(["platform_name": .null, "platform_username": .null, "metadata": .null]))
        let request = try ApplicationRoleConnectionUpdate(platformName: .value(""), platformUsername: .value("user"), metadata: .value(["score": "123", "date": "2026-10-16T00:00:00Z", "bool": "1"]))
        #expect(request.jsonValue() == .object(["platform_name": .string(""), "platform_username": .string("user"),
            "metadata": .object(["score": .string("123"), "date": .string("2026-10-16T00:00:00Z"), "bool": .string("1")])]))
        #expect(try ApplicationRoleConnectionUpdate(platformName: .value(String(repeating: "é", count: 50)), platformUsername: .value(String(repeating: "é", count: 100)), metadata: .value(["a": String(repeating: "é", count: 100)])).jsonValue() != .null)
        #expect(try ApplicationRoleConnectionUpdate(metadata: .value([:])).jsonValue() == .object(["metadata": .object([:])]))
        #expect(throws: DiscordError.validation(.invalidValue)) { try ApplicationRoleConnectionUpdate(platformName: .value(String(repeating: "x", count: 51))) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try ApplicationRoleConnectionUpdate(platformUsername: .value(String(repeating: "x", count: 101))) }
        for value in ["", String(repeating: "x", count: 101)] {
            #expect(throws: DiscordError.validation(.invalidValue)) { try ApplicationRoleConnectionUpdate(metadata: .value(["a": value])) }
        }
        for key in ["", "Bad", "a-b", String(repeating: "a", count: 51)] {
            #expect(throws: DiscordError.validation(.invalidValue)) { try ApplicationRoleConnectionUpdate(metadata: .value([key: "1"])) }
        }
        let five = Dictionary(uniqueKeysWithValues: (0..<5).map { ("a\($0)", "1") })
        #expect(try ApplicationRoleConnectionUpdate(metadata: .value(five)).jsonValue() != .null)
        let six = Dictionary(uniqueKeysWithValues: (0..<6).map { ("a\($0)", "1") })
        #expect(throws: DiscordError.validation(.invalidValue)) { try ApplicationRoleConnectionUpdate(metadata: .value(six)) }
        #expect(!String(describing: request).contains("2026")); #expect(request.customMirror.children.count == 1)
    }

    /// Builds one ordinary comparison definition to isolate key/count behavior from unrelated fixture choices.
    /// - Parameter key: Caller-selected dictionary key whose validation is exercised through the public initializer.
    /// - Returns: A type-1 metadata definition named Name with an ordinary description and omitted localizations.
    /// - Throws: The initializer's sanitized key/text validation errors; no I/O or mutation occurs.
    static func record(key: String) throws -> ApplicationRoleConnectionMetadataRecord {
        try .init(type: .integerLessThanOrEqual, key: key, name: "Name", description: "Description")
    }
}
