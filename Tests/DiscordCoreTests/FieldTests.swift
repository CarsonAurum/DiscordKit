// File: Tests/DiscordCoreTests/FieldTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import Foundation
import Testing
@testable import DiscordCore

/// Verifies optional request presence and required nullable response semantics independently.
@Suite struct FieldTests {
    /// A partial object deliberately using container helpers to preserve omitted fields.
    private struct Patch: Codable, Equatable {
        let name: Field<String>
        enum CodingKeys: String, CodingKey { case name }

        /// Creates a deterministic test patch without endpoint-specific nullability validation.
        /// - Parameter name: The field state to encode and compare.
        init(name: Field<String>) { self.name = name }

        /// Decodes presence through the production keyed helper.
        /// - Parameter decoder: A JSON object decoder containing an optional name.
        /// - Throws: Container or non-string payload errors.
        init(from decoder: any Decoder) throws {
            name = try decoder.container(keyedBy: CodingKeys.self).decodeField(String.self, forKey: .name)
        }

        /// Encodes presence through the production keyed helper.
        /// - Parameter encoder: The destination JSON object encoder.
        /// - Throws: Container or field encoding errors.
        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeField(name, forKey: .name)
        }
    }

    /// A complete response whose name must be present, even when explicitly null.
    private struct Response: Codable, Equatable {
        let name: Nullable<String>
    }

    /// A deterministic payload failure used to verify error propagation rather than only JSON type mismatches.
    private enum PayloadError: Error { case expected }

    /// A payload that always throws the same error from its coding operations.
    private enum ThrowingPayload: Codable {
        case value

        /// Rejects any supplied payload with the deterministic test error.
        /// - Parameter decoder: Unused payload decoder, intentionally never inspected.
        /// - Throws: `PayloadError.expected` on every invocation.
        init(from decoder: any Decoder) throws { throw PayloadError.expected }

        /// Fails before writing payload bytes to verify that callers propagate errors unchanged.
        /// - Parameter encoder: Unused destination encoder.
        /// - Throws: `PayloadError.expected` on every invocation.
        func encode(to encoder: any Encoder) throws { throw PayloadError.expected }
    }

    /// A request wrapper exercising absence and errors with the same throwing associated type.
    private struct FailurePatch: Encodable {
        let name: Field<ThrowingPayload>
        enum CodingKeys: String, CodingKey { case name }

        /// Encodes presence without invoking the payload for omitted or null fields.
        /// - Parameter encoder: Destination object encoder.
        /// - Throws: `PayloadError.expected` only for a present non-null payload, or container errors.
        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeField(name, forKey: .name)
        }
    }

    /// Omission, null, empty, and nonempty strings round-trip without conflating states.
    /// - Parameters:
    ///   - field: The request-field state under test.
    ///   - expectedJSON: The exact expected one-key or empty JSON object.
    /// - Throws: Unexpected encoding, decoding, or fixture-parsing failures.
    @Test(arguments: [
        (Field<String>.absent, "{}"), (.null, #"{"name":null}"#),
        (.value(""), #"{"name":""}"#), (.value("new name"), #"{"name":"new name"}"#),
    ])
    func requestPresence(field: Field<String>, expectedJSON: String) throws {
        let patch = Patch(name: field)
        let data = try JSONEncoder().encode(patch)
        #expect(try JSONValue.parse(data) == JSONValue.parse(expectedJSON))
        #expect(try JSONDecoder().decode(Patch.self, from: data) == patch)
        #expect(Set([field, field]).count == 1)
    }

    /// Non-string values are rejected by the payload decoder rather than mapped to absent/null.
    @Test func invalidRequestPayload() {
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(Patch.self, from: Data(#"{"name":7}"#.utf8)) }
        #expect(Field<String>.absent != .null)
        #expect(Field<String>.null != .value(""))
    }

    /// Complete responses accept explicit null or a typed value and reject missing or malformed fields.
    /// - Throws: Unexpected errors decoding valid response fixtures or encoding retained values.
    @Test func requiredNullableResponse() throws {
        let null = try JSONDecoder().decode(Response.self, from: Data(#"{"name":null}"#.utf8))
        let value = try JSONDecoder().decode(Response.self, from: Data(#"{"name":"ok"}"#.utf8))
        #expect(null.name == .null)
        #expect(value.name == .value("ok"))
        #expect(try JSONValue.parse(JSONEncoder().encode(null)) == .object(["name": .null]))
        #expect(try JSONValue.parse(JSONEncoder().encode(value)) == .object(["name": .string("ok")]))
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(Response.self, from: Data("{}".utf8)) }
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(Response.self, from: Data(#"{"name":false}"#.utf8)) }
        #expect(Set([Nullable<String>.null, .value("ok"), .null]).count == 2)
    }

    /// Payload errors propagate, while absent/null states bypass payload coding entirely.
    /// - Throws: Unexpected errors encoding/decoding states that should not inspect the payload.
    @Test func payloadErrorPropagation() throws {
        #expect(try JSONValue.parse(JSONEncoder().encode(FailurePatch(name: .absent))) == .object([:]))
        #expect(try JSONValue.parse(JSONEncoder().encode(FailurePatch(name: .null))) == .object(["name": .null]))
        #expect(throws: PayloadError.expected) { try JSONEncoder().encode(FailurePatch(name: .value(.value))) }
        #expect(throws: PayloadError.expected) { try JSONEncoder().encode(Nullable<ThrowingPayload>.value(.value)) }
        #expect(throws: PayloadError.expected) {
            try JSONDecoder().decode(Nullable<ThrowingPayload>.self, from: Data("true".utf8))
        }
        let null = try JSONDecoder().decode(Nullable<ThrowingPayload>.self, from: Data("null".utf8))
        #expect(try JSONEncoder().encode(null) == Data("null".utf8))
    }
}
