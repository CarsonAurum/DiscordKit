// File: Tests/DiscordCoreTests/JSONValueTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import Foundation
import Testing
@testable import DiscordCore

/// Exercises exact unknown numeric retention, strict JSON syntax, and deterministic resource bounds.
@Suite struct JSONValueTests {
    /// Confirms that valid JSON numbers retain all spelling distinctions and exceed machine numeric ranges safely.
    /// - Parameter spelling: A valid integer, fraction, negative zero, or exponent spelling.
    /// - Throws: Unexpected validation or serialization failures.
    @Test(arguments: ["0", "-0", "1", "-123", "9007199254740993", "18446744073709551616",
                      "123456789012345678901234567890123456789012345678901234567890",
                      "1.2300", "-0.0000000000000000000000000001", "1e1000000", "-12.000E-001", "1E+10"])
    func numericLexemes(spelling: String) throws {
        let number = try JSONNumber(rawValue: spelling)
        #expect(number.rawValue == spelling)
        let tree = try JSONValue.parse(spelling)
        #expect(tree == .number(number))
        #expect(String(decoding: try tree.serialized(), as: UTF8.self) == spelling)
        #expect(Set([number, try JSONNumber(rawValue: spelling)]).count == 1)
    }

    /// Rejects number spellings excluded by RFC 8259 without accepting whitespace or Unicode digits.
    /// - Parameter spelling: Invalid or incomplete numeric input.
    @Test(arguments: ["", "-", "+1", "01", "-01", "00", ".1", "1.", "1e", "1e+", "1e-",
                      "1e1x", "NaN", "Infinity", "-Infinity", " 1", "1 ", "١", "1_000", "--1", "1..2"])
    func invalidNumbers(spelling: String) {
        #expect(throws: JSONValueError.invalidNumber) { try JSONNumber(rawValue: spelling) }
    }

    /// Round-trips a future object variant including large numbers, all JSON categories, and escaped Unicode.
    /// - Throws: Any unexpected parser/writer failure.
    @Test func unknownVariantRoundTrip() throws {
        let source = #"{"type":"future_variant","unknown":{"unsigned":1844674407370955161618446744073709551616,"fraction":1.2300e+900,"negative_zero":-0},"values":[null,true,false,{},[],"\uD83D\uDC36\n\t\\\"/"],"雪":"🐶"}"#
        let tree = try JSONValue.parse(source)
        let serialized = try tree.serialized()
        #expect(try JSONValue.parse(serialized) == tree)
        #expect(try tree.serialized() == serialized)
        if case .object(let object) = tree, case .object(let unknown) = object["unknown"] {
            #expect(unknown["fraction"] == .number(try JSONNumber(rawValue: "1.2300e+900")))
            #expect(unknown["negative_zero"] == .number(try JSONNumber(rawValue: "-0")))
        } else { Issue.record("Expected the unknown object variant to survive parsing.") }
        #expect(try JSONValue.parse(" \t\r\n[ true , false , null ] \n") == .array([.bool(true), .bool(false), .null]))
        #expect(try JSONValue.parse(#"{"z":0,"a":1}"#).serialized() == Data(#"{"a":1,"z":0}"#.utf8))
    }

    /// Rejects malformed document shapes, missing separators, control characters, and trailing values.
    /// - Parameter source: A malformed complete JSON document.
    @Test(arguments: ["", " ", "[", "{", "[1", "{\"a\":", "[1,]", "{\"a\":1,}", "[,1]",
                      "{a:1}", "{\"a\" 1}", "{\"a\":1 \"b\":2}", "[1 2]", "true false", "nullx",
                      "tru", "falsx", "nu", "True", "\"unterminated", "\"escape\\", "\"bad\nline\"",
                      "\"\\q\"", "\"\\uZZZZ\"", "\"\\uD800\"", "\"\\uDC00\"", "01", "1.", "-", "\u{FEFF}null", "\u{00A0}null"])
    func malformedDocuments(source: String) {
        #expect(throws: JSONValueError.self) { try JSONValue.parse(source) }
    }

    /// Invalid UTF-8 and duplicate decoded keys fail explicitly instead of replacing bytes or silently dropping members.
    @Test func invalidUnicodeAndDuplicateKeys() {
        #expect(throws: JSONValueError.self) { try JSONValue.parse(Data([34, 0xFF, 34])) }
        #expect(throws: JSONValueError.duplicateKey(byteOffset: 7)) {
            try JSONValue.parse(#"{"a":0,"a":1}"#)
        }
        #expect(throws: JSONValueError.duplicateKey(byteOffset: 7)) {
            try JSONValue.parse(#"{"a":0,"\u0061":1}"#)
        }
        #expect(throws: JSONValueError.malformed(byteOffset: 0)) { try JSONValue.parse("?") }
        #expect(throws: JSONValueError.malformed(byteOffset: 5)) { try JSONValue.parse("null x") }
    }

    /// Enforces matching depth/node/byte definitions on both parse and serialization, including exact boundaries.
    /// - Throws: Unexpected failures for values exactly within each bound.
    @Test func resourceLimitBoundaries() throws {
        let fourBytes = JSONLimits(maximumBytes: 4, maximumDepth: 1, maximumNodes: 1)
        #expect(try JSONValue.parse("null", limits: fourBytes) == .null)
        #expect(try JSONValue.null.serialized(limits: fourBytes) == Data("null".utf8))
        #expect(throws: JSONValueError.maximumBytesExceeded) { try JSONValue.parse(" null", limits: fourBytes) }
        #expect(throws: JSONValueError.maximumBytesExceeded) {
            try JSONValue.parse(Data(" null".utf8), limits: fourBytes)
        }
        #expect(throws: JSONValueError.maximumBytesExceeded) { try JSONValue.string("abcd").serialized(limits: fourBytes) }
        #expect(throws: JSONValueError.maximumBytesExceeded) { try JSONValue.string("\n\n").serialized(limits: fourBytes) }
        #expect(throws: JSONValueError.maximumBytesExceeded) { try JSONValue.string("abcdef").serialized(limits: fourBytes) }

        let oneLevel = JSONLimits(maximumDepth: 1, maximumNodes: 3)
        let flat = JSONValue.array([.null, .bool(true)])
        #expect(try JSONValue.parse("[null,true]", limits: oneLevel) == flat)
        #expect(try JSONValue.parse(flat.serialized(limits: oneLevel)) == flat)
        #expect(try JSONValue.parse("{}", limits: oneLevel) == .object([:]))
        #expect(throws: JSONValueError.maximumDepthExceeded) { try JSONValue.parse("[{}]", limits: oneLevel) }
        #expect(throws: JSONValueError.maximumDepthExceeded) { try JSONValue.array([.object([:])]).serialized(limits: oneLevel) }
        #expect(throws: JSONValueError.maximumDepthExceeded) { try JSONValue.object(["a": .array([])]).serialized(limits: oneLevel) }
        #expect(throws: JSONValueError.maximumNodesExceeded) { try JSONValue.parse("[0,0,0]", limits: oneLevel) }
        #expect(throws: JSONValueError.maximumNodesExceeded) { try JSONValue.array([.null, .null, .null]).serialized(limits: oneLevel) }
        #expect(try JSONValue.parse(#"{"key":0}"#, limits: JSONLimits(maximumNodes: 2)) == .object(["key": .number(try JSONNumber(rawValue: "0"))]))
        #expect(JSONLimits.default == JSONLimits())
    }

    /// Invalid limit configurations produce recoverable errors before malformed data is inspected.
    /// - Parameter limits: A configuration with a nonpositive byte/node count or unsupported depth.
    @Test(arguments: [JSONLimits(maximumBytes: 0), JSONLimits(maximumBytes: -1), JSONLimits(maximumDepth: 0),
                      JSONLimits(maximumDepth: 129), JSONLimits(maximumNodes: 0), JSONLimits(maximumNodes: -1)])
    func invalidLimits(limits: JSONLimits) {
        #expect(throws: JSONValueError.invalidLimits) { try JSONValue.parse("null", limits: limits) }
        #expect(throws: JSONValueError.invalidLimits) { try JSONValue.parse(Data(), limits: limits) }
        #expect(throws: JSONValueError.invalidLimits) { try JSONValue.null.serialized(limits: limits) }
    }

    /// Exercises the maximum configured recursion depth and rejects one additional container deterministically.
    /// - Throws: Unexpected failures at the supported hard depth bound.
    @Test func maximumSupportedDepth() throws {
        let source = String(repeating: "[", count: 128) + "0" + String(repeating: "]", count: 128)
        let limits = JSONLimits(maximumDepth: 128)
        let tree = try JSONValue.parse(source, limits: limits)
        #expect(try tree.serialized(limits: limits) == Data(source.utf8))
        #expect(throws: JSONValueError.maximumDepthExceeded) { try JSONValue.parse("[" + source + "]", limits: limits) }
    }

    /// The Codable bridge preserves all nonnumeric tree categories, including nested unknown objects.
    /// - Parameter source: A JSON document without any numeric payloads.
    /// - Throws: Unexpected Codable or parser failures.
    @Test(arguments: ["null", "true", "false", "\"text🐶\"", "[]", "{}", #"{"a":[null,true,"x"]}"#])
    func codableBridge(source: String) throws {
        let decoded = try JSONDecoder().decode(JSONValue.self, from: Data(source.utf8))
        #expect(try decoded == JSONValue.parse(source))
        let encoded = try JSONEncoder().encode(decoded)
        #expect(try JSONValue.parse(encoded) == decoded)
    }

    /// Every numeric Codable decode fails, including tokens that Foundation silently rounds when asked for an integer.
    ///
    /// Canonical machine integers remain safe to encode; unsupported numeric spellings cannot be normalized silently.
    /// - Throws: Unexpected validation failures when constructing valid JSON number lexemes.
    @Test func codablePrecisionRestrictions() throws {
        for source in ["0", "-1", "0.1", "1e1000", "1e-100000", "1.000000000000000000001",
                       "18446744073709551616", "-9223372036854775809", #"{"nested":1.2}"#, "[1]"] {
            #expect(throws: DecodingError.self) { try JSONDecoder().decode(JSONValue.self, from: Data(source.utf8)) }
        }
        for source in ["-0", "1.0", "1e1", "18446744073709551616", "-9223372036854775809"] {
            let tree = JSONValue.number(try JSONNumber(rawValue: source))
            #expect(throws: EncodingError.self) { try JSONEncoder().encode(tree) }
        }
        for source in ["-9223372036854775808", "9223372036854775807", "18446744073709551615", "9007199254740993"] {
            let tree = try JSONValue.parse(source)
            #expect(try JSONValue.parse(JSONEncoder().encode(tree)) == tree)
        }
        #expect(try JSONNumber(rawValue: "0") != JSONNumber(rawValue: "-0"))
    }
}
