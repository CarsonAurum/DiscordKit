// File: Tests/DiscordBitsTests/UnsignedBitSetTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import Foundation
import Testing
@testable import DiscordBits

/// Exercises decimal conversion, normalization, set algebra and allocation limits.
@Suite struct UnsignedBitSetTests {
    /// Verifies zero, limb boundaries and large machine values have canonical digits,
    /// numeric ordering and consistent equality/hash semantics after parsing.
    /// - Parameter value: Deterministic machine-integer boundary fixture.
    @Test(arguments: [UInt64](arrayLiteral: 0, 1, 9, 10, UInt64(UInt32.max), 1 << 32, (1 << 53) + 1, UInt64.max))
    func machineValues(_ value: UInt64) throws {
        let bits = UnsignedBitSet(value)
        #expect(bits.description == String(value))
        #expect(try UnsignedBitSet(decimalString: String(value)) == bits)
        #expect(Set([bits, try UnsignedBitSet(decimalString: "000" + String(value))]).count == 1)
        #expect(bits.isEmpty == (value == 0))
        #expect(bits.bitWidth == (64 - value.leadingZeroBitCount))
        #expect(!(bits < bits))
        if value > 0 { #expect(UnsignedBitSet(value - 1) < bits) }
    }

    /// Proves high permission bits at 64, 127 and 255 round-trip beyond UInt64.
    /// - Parameter fixture: Zero-based bit position and independently known decimal power of two.
    @Test(arguments: [
        (0, "1"), (31, "2147483648"), (32, "4294967296"),
        (64, "18446744073709551616"),
        (127, "170141183460469231731687303715884105728"),
        (255, "57896044618658097711785492504343953926634992332820282019728792003956564819968"),
    ])
    func wideValues(_ fixture: (Int, String)) throws {
        let (position, decimal) = fixture
        let bits = try UnsignedBitSet(bits: [position, position])
        #expect(bits.description == decimal)
        #expect(bits == (try UnsignedBitSet(decimalString: decimal)))
        #expect(bits.bitWidth == position + 1)
        #expect(bits.contains(position))
        #expect(!bits.contains(position + 1))
        #expect(!bits.contains(-1))
        #expect(!bits.contains(Int.max))
        let data = try JSONEncoder().encode(bits)
        #expect(String(decoding: data, as: UTF8.self) == "\"\(decimal)\"")
        #expect(try JSONDecoder().decode(UnsignedBitSet.self, from: data) == bits)
    }

    /// Rejects malformed decimal strings rather than accepting signs, spaces or Unicode digits.
    /// - Parameter value: Invalid decimal syntax, including the empty string.
    @Test(arguments: ["", "-1", "+1", " 1", "1 ", "1\n", "1.0", "1e2", "0xFF", "١", "９", "1_0"])
    func malformedDecimals(_ value: String) {
        #expect(throws: UnsignedBitSet.ValidationError.invalidDecimal) {
            try UnsignedBitSet(decimalString: value)
        }
    }

    /// Checks exact input limits, normalization and long repeated-division carry paths.
    @Test func decimalLimitsAndLargeValues() throws {
        #expect(try UnsignedBitSet(decimalString: "000000").description == "0")
        #expect(try UnsignedBitSet(decimalString: "9", maximumDigits: 1).description == "9")
        #expect(throws: UnsignedBitSet.ValidationError.inputTooLarge) {
            try UnsignedBitSet(decimalString: "00", maximumDigits: 1)
        }
        let oversizedJSON = Data(("\"" + String(repeating: "1", count: 16_385) + "\"").utf8)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(UnsignedBitSet.self, from: oversizedJSON)
        }
        for limit in [0, -1, Int.min] {
            #expect(throws: UnsignedBitSet.ValidationError.invalidLimit) {
                try UnsignedBitSet(decimalString: "0", maximumDigits: limit)
            }
        }
        for decimal in [String(repeating: "9", count: 2_000), "1" + String(repeating: "0", count: 2_000)] {
            let value = try UnsignedBitSet(decimalString: decimal)
            #expect(value.description == decimal)
            #expect(value.bitWidth > 6_000)
        }
    }

    /// Confirms setting/clearing across limbs, copy independence and transactional failures.
    @Test func mutationAndLimits() throws {
        var bits = try UnsignedBitSet(bits: [0, 64, 127, 255])
        let copy = bits
        try bits.set(255, to: false)
        #expect(bits.bitWidth == 128)
        #expect(copy.bitWidth == 256)
        try bits.set(127, to: false)
        try bits.set(64, to: false)
        #expect(bits == UnsignedBitSet(1))
        try bits.set(0, to: false)
        #expect(bits.isEmpty)
        try bits.set(1_048_575, to: false)
        #expect(bits.isEmpty)
        try bits.set(0, maximumBit: 0)
        #expect(bits == UnsignedBitSet(1))
        for invalid in [-1, Int.min, 1_048_576, Int.max] {
            #expect(throws: UnsignedBitSet.ValidationError.invalidBitIndex) { try bits.set(invalid) }
            #expect(bits == UnsignedBitSet(1))
        }
        #expect(throws: UnsignedBitSet.ValidationError.invalidLimit) { try bits.set(0, maximumBit: -1) }
        #expect(throws: UnsignedBitSet.ValidationError.invalidLimit) { try UnsignedBitSet(bits: [], maximumBit: -1) }
        #expect(throws: UnsignedBitSet.ValidationError.invalidBitIndex) { try UnsignedBitSet(bits: [1], maximumBit: 0) }
        #expect(try UnsignedBitSet(bits: []).isEmpty)
        var expanded = UnsignedBitSet()
        try expanded.set(1_048_576, maximumBit: 1_048_576)
        #expect(expanded.bitWidth == 1_048_577)
    }

    /// Verifies set operations with mixed widths, disjoint bits, empty sets and idempotence.
    @Test func setOperations() throws {
        let left = try UnsignedBitSet(bits: [0, 31, 64, 255])
        let right = try UnsignedBitSet(bits: [0, 127, 255])
        let empty = UnsignedBitSet()
        #expect(left.union(right) == (try UnsignedBitSet(bits: [0, 31, 64, 127, 255])))
        #expect(left.intersection(right) == (try UnsignedBitSet(bits: [0, 255])))
        #expect(left.symmetricDifference(right) == (try UnsignedBitSet(bits: [31, 64, 127])))
        #expect(left.subtracting(right) == (try UnsignedBitSet(bits: [31, 64])))
        #expect(left | right == right | left)
        #expect(left & right == right & left)
        #expect(left ^ right == right ^ left)
        #expect(left ^ left == empty)
        #expect(left.subtracting(left) == empty)
        #expect(left | empty == left)
        #expect(empty | left == left)
        #expect(left & empty == empty)
        #expect(empty & left == empty)
        #expect(left.subtracting(empty) == left)
        #expect(empty.subtracting(left) == empty)
        #expect(empty.isSubset(of: left))
        #expect(!left.isSubset(of: right))
        #expect(left.isSubset(of: left | right))
        #expect(try UnsignedBitSet(bits: [32]) > UnsignedBitSet(UInt64(UInt32.max)))
        #expect(try UnsignedBitSet(bits: [255]) > UnsignedBitSet(bits: [127]))
    }

    /// Compares deterministic two-word algebra to native UInt64 operations as an oracle.
    @Test func machineAlgebraOracle() {
        let fixtures: [UInt64] = [0, 1, 0xAAAAAAAAAAAAAAAA, 0x5555555555555555, UInt64.max]
        for lhs in fixtures {
            for rhs in fixtures {
                let left = UnsignedBitSet(lhs)
                let right = UnsignedBitSet(rhs)
                #expect((left | right).description == String(lhs | rhs))
                #expect((left & right).description == String(lhs & rhs))
                #expect((left ^ right).description == String(lhs ^ rhs))
                #expect(left.subtracting(right).description == String(lhs & ~rhs))
                #expect((left < right) == (lhs < rhs))
            }
        }
    }

    /// Requires JSON strings, bounded digits and canonical re-encoding after leading zeroes.
    /// - Parameter json: Wrong-type or malformed input fixture.
    @Test(arguments: ["null", "1", "true", "[]", "{}", "\"-1\"", "\"\""])
    func decodingFailures(_ json: String) {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(UnsignedBitSet.self, from: Data(json.utf8))
        }
    }
}
