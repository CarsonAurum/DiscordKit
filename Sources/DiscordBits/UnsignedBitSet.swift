// File: Sources/DiscordBits/UnsignedBitSet.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

/// An unsigned, arbitrary-width set of bits, serialized as a canonical decimal string.
///
/// Storage grows by 32-bit words and never narrows to a machine integer. Zero has no
/// stored words. Leading decimal zeroes are accepted and normalized. This value is
/// suitable for Discord's variable-length permission representation, but does not
/// define permission names, inheritance, or authorization policy.
///
/// Parsing and bit insertion have configurable allocation limits. Set operations
/// are linear in word count; decimal conversion uses quadratic long division.
/// Values have ordinary copy-on-write array semantics and are safe to transfer.
/// See <https://docs.discord.com/developers/topics/permissions> (API v10).
public struct UnsignedBitSet: Sendable, Hashable, Comparable, Codable, CustomStringConvertible {
    /// Validation failures contain no copy of potentially sensitive input.
    public enum ValidationError: Error, Equatable, Sendable {
        case invalidDecimal
        case inputTooLarge
        case invalidLimit
        case invalidBitIndex
    }

    private var words: [UInt32]

    /// Creates a value from a machine integer without loss or allocation for zero.
    /// - Parameter value: Initial unsigned value; defaults to zero.
    public init(_ value: UInt64 = 0) {
        words = value == 0 ? [] : [UInt32(truncatingIfNeeded: value)]
        if value > UInt64(UInt32.max) { words.append(UInt32(value >> 32)) }
    }

    /// Parses nonempty ASCII decimal digits without floating-point conversion.
    ///
    /// Leading zeroes count toward the limit, then disappear from serialization.
    /// Signs, whitespace, Unicode numerals, separators and exponent forms fail.
    /// - Parameters:
    ///   - decimalString: One or more digits in `0...9`.
    ///   - maximumDigits: Positive byte/digit limit; defaults to 16,384. Raise only
    ///     for trusted inputs with a suitable CPU and memory budget.
    /// - Throws: `ValidationError.invalidLimit` for a nonpositive limit,
    ///   `.inputTooLarge` above the limit, or `.invalidDecimal` for invalid syntax.
    public init(decimalString: String, maximumDigits: Int = 16_384) throws {
        guard maximumDigits > 0 else { throw ValidationError.invalidLimit }
        guard decimalString.utf8.count <= maximumDigits else { throw ValidationError.inputTooLarge }
        guard !decimalString.isEmpty else { throw ValidationError.invalidDecimal }
        words = []
        for digit in decimalString.utf8 {
            guard (48...57).contains(digit) else { throw ValidationError.invalidDecimal }
            var carry = UInt64(digit - 48)
            for index in words.indices {
                let product = UInt64(words[index]) * 10 + carry
                words[index] = UInt32(truncatingIfNeeded: product)
                carry = product >> 32
            }
            if carry != 0 { words.append(UInt32(carry)) }
        }
    }

    /// Creates a set from bit positions, ignoring duplicate positions.
    /// - Parameters:
    ///   - bits: Zero-based positions; an empty array creates zero.
    ///   - maximumBit: Inclusive allocation boundary, default 1,048,575.
    /// - Throws: `ValidationError.invalidLimit` for a negative boundary, or
    ///   `.invalidBitIndex` for a position outside `0...maximumBit`.
    public init(bits: [Int], maximumBit: Int = 1_048_575) throws {
        guard maximumBit >= 0 else { throw ValidationError.invalidLimit }
        self.init()
        for bit in bits { try set(bit, to: true, maximumBit: maximumBit) }
    }

    /// Normalizes an internal little-endian word array, removing trailing zeroes.
    /// - Parameter words: Least-significant word first; may be empty or unnormalized.
    private init(words: [UInt32]) {
        self.words = words
        while self.words.last == 0 { self.words.removeLast() }
    }

    /// Whether no bits are set. This query is constant time and has no side effects.
    public var isEmpty: Bool { words.isEmpty }

    /// Number of bits through the highest set bit, or zero for the empty set.
    public var bitWidth: Int {
        guard let last = words.last else { return 0 }
        return (words.count - 1) * 32 + (32 - last.leadingZeroBitCount)
    }

    /// Canonical unsigned decimal digits without leading zeroes; zero is `"0"`.
    ///
    /// Uses base-1,000,000,000 long division and allocates a temporary word array.
    /// No locale, floating-point arithmetic, global state, or I/O is involved.
    public var description: String {
        guard !words.isEmpty else { return "0" }
        var quotient = words
        var chunks: [String] = []
        while !quotient.isEmpty {
            var remainder: UInt64 = 0
            for index in quotient.indices.reversed() {
                let dividend = (remainder << 32) | UInt64(quotient[index])
                quotient[index] = UInt32(dividend / 1_000_000_000)
                remainder = dividend % 1_000_000_000
            }
            chunks.append(String(remainder))
            while quotient.last == 0 { quotient.removeLast() }
        }
        return chunks.reversed().enumerated().map { index, chunk in
            index == 0 ? chunk : String(repeating: "0", count: 9 - chunk.count) + chunk
        }.joined()
    }

    /// Checks a zero-based bit without allocating or changing the set.
    /// - Parameter bit: Position to inspect; negative and beyond-storage positions are unset.
    /// - Returns: Whether that position is set.
    public func contains(_ bit: Int) -> Bool {
        guard bit >= 0, bit / 32 < words.count else { return false }
        return words[bit / 32] & (UInt32(1) << (bit % 32)) != 0
    }

    /// Sets or clears one bit, preserving canonical storage.
    ///
    /// Clearing an absent bit performs no allocation. On failure `self` is unchanged.
    /// - Parameters:
    ///   - bit: Zero-based position in `0...maximumBit`.
    ///   - value: `true` inserts and `false` removes the position; defaults to `true`.
    ///   - maximumBit: Inclusive resource boundary; defaults to 1,048,575.
    /// - Throws: `ValidationError.invalidLimit` for a negative boundary, or
    ///   `.invalidBitIndex` for an out-of-range position.
    public mutating func set(_ bit: Int, to value: Bool = true, maximumBit: Int = 1_048_575) throws {
        guard maximumBit >= 0 else { throw ValidationError.invalidLimit }
        guard bit >= 0, bit <= maximumBit else { throw ValidationError.invalidBitIndex }
        let index = bit / 32
        if value {
            if words.count <= index { words.append(contentsOf: repeatElement(0, count: index + 1 - words.count)) }
            words[index] |= UInt32(1) << (bit % 32)
        } else if index < words.count {
            words[index] &= ~(UInt32(1) << (bit % 32))
            while words.last == 0 { words.removeLast() }
        }
    }

    /// Returns every bit present in either operand; neither operand is modified.
    /// - Parameter other: Another arbitrary-width set, including zero.
    /// - Returns: The bitwise OR, with width equal to the larger operand's width.
    public func union(_ other: Self) -> Self { combining(other, operation: |) }

    /// Returns bits shared by both operands; neither operand is modified.
    /// - Parameter other: Another arbitrary-width set, including zero.
    /// - Returns: The bitwise AND, normalized to remove high zero words.
    public func intersection(_ other: Self) -> Self { combining(other, operation: &) }

    /// Returns bits present in exactly one operand, preserving unknown high bits.
    /// - Parameter other: Another arbitrary-width set, including zero.
    /// - Returns: The bitwise XOR; identical values produce zero.
    public func symmetricDifference(_ other: Self) -> Self { combining(other, operation: ^) }

    /// Removes the other's bits without an infinite-width complement operation.
    /// - Parameter other: Positions to clear; positions absent from `self` are ignored.
    /// - Returns: A new set containing `self & ~other`, bounded by `self`'s width.
    public func subtracting(_ other: Self) -> Self { combining(other) { $0 & ~$1 } }

    /// Checks that all this set's bits occur in another set.
    /// - Parameter other: Candidate superset of any width.
    /// - Returns: `true` for the empty set or when subtraction leaves no set bits.
    public func isSubset(of other: Self) -> Bool { subtracting(other).isEmpty }

    /// Combines padded words using a pure word operation, then restores normalization.
    /// - Parameters:
    ///   - other: Right operand; missing high words are treated as zero.
    ///   - operation: Pure word-level binary operator, invoked once per padded word.
    /// - Returns: A canonical arbitrary-width result in linear time and memory.
    private func combining(_ other: Self, operation: (UInt32, UInt32) -> UInt32) -> Self {
        Self(words: (0..<max(words.count, other.words.count)).map { index in
            operation(index < words.count ? words[index] : 0, index < other.words.count ? other.words[index] : 0)
        })
    }

    /// Orders unsigned values numerically, using high words before low words.
    /// - Parameters:
    ///   - lhs: Left numeric value.
    ///   - rhs: Right numeric value.
    /// - Returns: Whether the left value is strictly smaller; equal values return false.
    public static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.words.count != rhs.words.count { return lhs.words.count < rhs.words.count }
        return lhs.words.reversed().lexicographicallyPrecedes(rhs.words.reversed())
    }

    /// Returns the union using familiar bitwise syntax.
    /// - Parameters:
    ///   - lhs: Left set.
    ///   - rhs: Right set, zero-extended to the left width if necessary.
    /// - Returns: Bits present in either operand.
    public static func | (lhs: Self, rhs: Self) -> Self { lhs.union(rhs) }

    /// Returns the intersection using familiar bitwise syntax.
    /// - Parameters:
    ///   - lhs: Left set.
    ///   - rhs: Right set.
    /// - Returns: Bits present in both operands.
    public static func & (lhs: Self, rhs: Self) -> Self { lhs.intersection(rhs) }

    /// Returns the symmetric difference using familiar bitwise syntax.
    /// - Parameters:
    ///   - lhs: Left set.
    ///   - rhs: Right set.
    /// - Returns: Bits present in exactly one operand.
    public static func ^ (lhs: Self, rhs: Self) -> Self { lhs.symmetricDifference(rhs) }

    /// Decodes a decimal JSON string with the default 16,384-digit resource limit.
    /// - Parameter decoder: Decoder positioned at a single string value.
    /// - Throws: `DecodingError` for nonstrings or invalid/oversized decimal input.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        do { self = try Self(decimalString: value) }
        catch { throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid unsigned bit set") }
    }

    /// Encodes the canonical decimal string, matching Discord API v8+ permissions.
    /// - Parameter encoder: Encoder accepting a single string value.
    /// - Throws: Any error raised by the encoder; no integer narrowing occurs.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}
