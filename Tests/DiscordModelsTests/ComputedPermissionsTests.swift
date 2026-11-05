// File: Tests/DiscordModelsTests/ComputedPermissionsTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import Foundation
import Testing
@testable import DiscordModels

/// Computed guild/channel permission responses retain exact bitfields under the shared bounded model contract.
@Suite struct ComputedPermissionsTests {
    /// Zero, leading zeroes and future bits beyond UInt64 preserve their complete decimal spelling.
    /// Unknown nested values retain exact number lexemes, while ordinary diagnostics conceal all payload text.
    /// - Parameter bits: Independently valid decimal permission strings, including the empty permission set.
    /// - Throws: Unexpected parsing/projection/serialization failures fail the test.
    @Test(arguments: ["0", "0008", "184467440737095516161844674407370955161"])
    func exactValuesAndDiagnostics(bits: String) throws {
        let bytes = Data("{\"permissions\":\"\(bits)\",\"future_secret\":{\"text\":\"private-permissions\",\"number\":1.230000000000001e1000}}".utf8)
        let expected = try JSONValue.parse(bytes)
        let parsed = try ComputedPermissions(data: bytes)
        let projected = try ComputedPermissions(value: expected, limits: .default)
        #expect(parsed.permissions == bits)
        #expect(parsed == projected)
        #expect(parsed.jsonValue() == expected)
        #expect(try parsed.jsonValue().serialized() == expected.serialized())
        #expect(parsed.description == "ComputedPermissions(redacted)")
        #expect(!parsed.debugDescription.contains("private-permissions"))
        #expect(!String(reflecting: parsed).contains("private-permissions"))
        #expect(parsed.customMirror.children.count == 1)
        #expect(Mirror(reflecting: parsed).children.count == 1)
        #expect(try ComputedPermissions(data: Data(#"{"permissions":"0"}"#.utf8)).rawFields.count == 1)
    }

    /// Missing/null/wrongly typed fields, nonobject roots and invalid decimal syntax fail without coercion.
    /// - Parameter source: Complete JSON that violates the written required-string permission response contract.
    /// - Throws: Unexpected fixture syntax failures fail the test; sanitized schema failures are asserted.
    @Test(arguments: ComputedPermissionsTests.malformedResponses)
    func malformedSchema(source: String) throws {
        #expect(throws: DiscordError.transport(.invalidResponse)) {
            try ComputedPermissions(data: Data(source.utf8))
        }
        let value = try JSONValue.parse(source)
        #expect(throws: DiscordError.transport(.invalidResponse)) {
            try ComputedPermissions(value: value, limits: .default)
        }
    }

    /// Parser bounds cover unknown content, and malformed/duplicate/trailing documents cannot bypass validation.
    /// - Throws: Unexpected setup/valid-boundary failures fail the test; expected parser errors are asserted.
    @Test func parserBoundsAndSyntax() throws {
        let bytes = Data(#"{"permissions":"0","future":{"nested":[1,2,3]}}"#.utf8)
        #expect(throws: JSONValueError.maximumBytesExceeded) {
            try ComputedPermissions(data: bytes, limits: .init(maximumBytes: bytes.count - 1))
        }
        #expect(throws: JSONValueError.maximumDepthExceeded) {
            try ComputedPermissions(data: bytes, limits: .init(maximumDepth: 1))
        }
        #expect(throws: JSONValueError.maximumNodesExceeded) {
            try ComputedPermissions(data: bytes, limits: .init(maximumNodes: 1))
        }
        #expect(try ComputedPermissions(data: bytes, limits: .init(maximumBytes: bytes.count)).permissions == "0")
        for source in ["{", #"{"permissions":"0","permissions":"1"}"#, #"{"permissions":"0"}{}"#] {
            #expect(throws: JSONValueError.self) { try ComputedPermissions(data: Data(source.utf8)) }
        }
    }

    /// Complete invalid responses covering root shape, required-field presence/type and decimal-string syntax.
    static let malformedResponses = [
        "{}", "null", "[]", "1", "true", #"{"permissions":null}"#,
        #"{"permissions":0}"#, #"{"permissions":true}"#, #"{"permissions":[]}"#,
        #"{"permissions":{}}"#, #"{"permissions":""}"#, #"{"permissions":"-1"}"#,
        #"{"permissions":"+1"}"#, #"{"permissions":" 1"}"#, #"{"permissions":"1 "}"#,
        #"{"permissions":"1.0"}"#, #"{"permissions":"1e3"}"#, #"{"permissions":"１２"}"#
    ]
}
