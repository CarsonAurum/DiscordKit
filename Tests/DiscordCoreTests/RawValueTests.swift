// File: Tests/DiscordCoreTests/RawValueTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import Foundation
import Testing
@testable import DiscordCore

/// Covers recognized/future string and integer wire enum values without claiming future behavior support.
@Suite struct RawValueTests {
    /// Representative string-backed enum with deliberately incomplete future coverage.
    private enum StringKind: String, Sendable { case known }
    /// Representative integer-backed enum, including negative raw values.
    private enum IntegerKind: Int, Sendable { case negative = -1, known = 1 }

    /// String-backed known and unknown enum cases preserve raw values through Codable and hashing.
    /// - Throws: Unexpected fixture coding errors.
    @Test func stringValues() throws {
        let known = RawValue<StringKind>(.known)
        #expect(known.rawValue == "known")
        #expect(known.knownValue == .known)
        #expect(known == RawValue(rawValue: "known"))
        for raw in ["future", "", "🐶", "KNOWN"] {
            let unknown = RawValue<StringKind>(rawValue: raw)
            #expect(unknown.knownValue == nil)
            #expect(unknown.rawValue == raw)
            let data = try JSONEncoder().encode(unknown)
            #expect(try JSONDecoder().decode(RawValue<StringKind>.self, from: data) == unknown)
        }
        #expect(try JSONDecoder().decode(RawValue<StringKind>.self, from: Data("\"known\"".utf8)) == known)
        #expect(Set([known, RawValue(rawValue: "known"), RawValue(rawValue: "future")]).count == 2)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(RawValue<StringKind>.self, from: Data("1".utf8)) }
    }

    /// Integer-backed enums retain negative, zero, extreme, and future values without truncation.
    /// - Parameter raw: An in-range native integer payload, recognized or unknown.
    /// - Throws: Unexpected Codable errors.
    @Test(arguments: [Int.min, -1, 0, 1, 2, Int.max])
    func integerValues(raw: Int) throws {
        let value = RawValue<IntegerKind>(rawValue: raw)
        #expect(value.rawValue == raw)
        #expect(value.knownValue == IntegerKind(rawValue: raw))
        #expect(try JSONDecoder().decode(RawValue<IntegerKind>.self, from: JSONEncoder().encode(value)) == value)
        #expect(RawValue<IntegerKind>(.negative).rawValue == -1)
    }

    /// Null, an unambiguously nonintegral fraction, strings and overflow fail the raw-type decoder.
    /// - Parameter source: A JSON value that cannot decode as a native integer raw value.
    @Test(arguments: ["null", "1.5", "\"1\"", "18446744073709551616"])
    func invalidIntegerValues(source: String) {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(RawValue<IntegerKind>.self, from: Data(source.utf8))
        }
    }

    /// Exact numeric discriminator validation starts from the lossless parser, before a typed raw value exists.
    ///
    /// Near-integer fractions, exponent spellings and out-of-range integers retain
    /// their original tokens. This does not assume a particular Foundation decoder's
    /// rounding behavior; the typed initializer receives only explicitly validated integers.
    /// - Parameter source: A valid JSON number that must not silently become a known integer discriminator.
    /// - Throws: Unexpected parser, serialization or required-number failures.
    @Test(arguments: ["1.000000000000000000001", "1e0", "18446744073709551616"])
    func exactNumericDiscriminators(source: String) throws {
        let tree = try JSONValue.parse(source)
        guard case .number(let number) = tree else {
            Issue.record("Expected an exact numeric discriminator.")
            return
        }
        #expect(number.rawValue == source)
        #expect(String(decoding: try tree.serialized(), as: UTF8.self) == source)
        #expect(Int(number.rawValue) == nil)
        let validated = try #require(Int("1"))
        let known = RawValue<IntegerKind>(rawValue: validated)
        #expect(known.rawValue == validated)
        #expect(known.knownValue == .known)
    }
}
