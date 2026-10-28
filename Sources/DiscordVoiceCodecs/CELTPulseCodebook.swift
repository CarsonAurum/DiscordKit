// File: Sources/DiscordVoiceCodecs/CELTPulseCodebook.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

/// Rejections from the bounded RFC 6716 section 4.3.4.2 pulse enumeration primitive.
public enum CELTPulseCodebookError: Error, Sendable, Equatable {
    case invalidDimensions
    case invalidPulseCount
    case codebookTooLarge
    case invalidVector
    case invalidIndex
}

/// An exact signed-integer CELT pyramid-vector codebook, not a complete CELT codec.
///
/// Codewords have `dimensions` components and L1 norm `pulseCount`. The ordering follows
/// RFC 6716 section 4.3.4.2: U(N,K) enumerates the nonnegative-first-coordinate boundary,
/// with V(N,K) = U(N,K) + U(N,K+1). This implementation constructs the recurrence from
/// the mathematical definition rather than retaining libopus's precomputed tables.
///
/// Construction bounds dimensions, pulse count and the complete codebook to a 32-bit
/// uniform entropy symbol. Larger CELT bands require recursive splitting by a future
/// band decoder; rejecting them here does not claim to implement that decoder. No
/// gain/shape search, normalization, band allocation, spreading, MDCT, PCM, PLC or FEC
/// is provided. Values own immutable tables, start no I/O/tasks and can be shared.
public struct CELTPulseCodebook: Sendable {
    public let dimensions: Int
    public let pulseCount: Int
    public let codewordCount: UInt32
    private let rows: [[UInt64]]

    /// Builds an exact bounded integer codebook without reading compressed data.
    /// - Parameters:
    ///   - dimensions: Component count in `1...176`, a local primitive-storage bound.
    ///   - pulseCount: Sum of absolute component magnitudes in `0...128`. Zero has one
    ///     all-zero codeword and consumes no entropy symbol.
    /// - Throws: `invalidDimensions`, `invalidPulseCount`, or `codebookTooLarge` when
    ///   the number of codewords exceeds `UInt32.max`. Construct smaller split bands
    ///   rather than reducing counts or wrapping arithmetic. At most 23,010 UInt64
    ///   table elements are allocated; work is O(dimensions * pulseCount).
    public init(dimensions: Int, pulseCount: Int) throws {
        guard (1...176).contains(dimensions) else { throw CELTPulseCodebookError.invalidDimensions }
        guard (0...128).contains(pulseCount) else { throw CELTPulseCodebookError.invalidPulseCount }
        let limit = UInt64(UInt32.max) + 1
        var table = Array(repeating: Array(repeating: UInt64(0), count: pulseCount + 2), count: dimensions + 1)
        table[0][0] = 1
        for n in 1...dimensions {
            for k in 1..<(pulseCount + 2) {
                table[n][k] = min(limit, table[n - 1][k] + table[n][k - 1] + table[n - 1][k - 1])
            }
        }
        let count = pulseCount == 0 ? 1 : table[dimensions][pulseCount] + table[dimensions][pulseCount + 1]
        guard count < limit else { throw CELTPulseCodebookError.codebookTooLarge }
        self.dimensions = dimensions
        self.pulseCount = pulseCount
        self.codewordCount = UInt32(count)
        self.rows = table
    }

    /// Enumerates a complete signed pulse vector in the RFC's CELT codeword order.
    /// - Parameter vector: Exactly `dimensions` components with absolute sum `pulseCount`.
    ///   Extreme integers, including `Int.min`, are rejected without overflowing.
    /// - Returns: Exact zero-based index smaller than `codewordCount`.
    /// - Throws: `invalidVector` on shape/norm mismatch. Validation precedes indexing;
    ///   the immutable codebook is unchanged. Work and temporary storage are O(dimensions).
    public func index(of vector: [Int]) throws -> UInt32 {
        guard vector.count == dimensions else { throw CELTPulseCodebookError.invalidVector }
        var total = 0
        for component in vector {
            guard component >= -pulseCount, component <= pulseCount else {
                throw CELTPulseCodebookError.invalidVector
            }
            total += abs(component)
        }
        guard total == pulseCount else { throw CELTPulseCodebookError.invalidVector }
        guard pulseCount > 0 else { return 0 }
        var remaining = pulseCount
        var result: UInt64 = 0
        for componentIndex in 0..<dimensions {
            let n = dimensions - componentIndex
            let component = vector[componentIndex]
            if component < 0 { result += rows[n][remaining + 1] }
            remaining -= abs(component)
            result += rows[n][remaining]
        }
        return UInt32(result)
    }

    /// Reconstructs the exact signed pulse vector for an RFC-ordered codeword index.
    /// - Parameter index: Zero-based integer smaller than `codewordCount`.
    /// - Returns: `dimensions` owned components with absolute sum `pulseCount`, including
    ///   an all-zero vector for the zero-pulse codebook. No floating-point rounding occurs.
    /// - Throws: `invalidIndex` outside the codebook. No shared state changes; work is
    ///   O(dimensions + pulseCount) with O(dimensions) newly allocated output storage.
    public func vector(at index: UInt32) throws -> [Int] {
        guard index < codewordCount else { throw CELTPulseCodebookError.invalidIndex }
        var result: [Int] = []
        result.reserveCapacity(dimensions)
        var remainder = UInt64(index)
        var remaining = pulseCount
        for n in stride(from: dimensions, through: 1, by: -1) {
            let negative = remainder >= rows[n][remaining + 1]
            if negative { remainder -= rows[n][remaining + 1] }
            let previous = remaining
            while rows[n][remaining] > remainder { remaining -= 1 }
            remainder -= rows[n][remaining]
            let magnitude = previous - remaining
            result.append(negative ? -magnitude : magnitude)
        }
        return result
    }

    /// Writes a validated pulse codeword using the existing Opus uniform range primitive.
    /// - Parameters:
    ///   - vector: Complete codeword accepted by `index(of:)`.
    ///   - encoder: Caller-owned usable entropy encoder. A nonzero-pulse codeword admits
    ///     one coding operation; zero pulses validate the vector and leave it untouched.
    /// - Throws: `invalidVector` before mutation, or `OpusRangeCodingError` with the
    ///   encoder's documented failure/operation/frame-budget semantics. No packet is emitted.
    public func encode(_ vector: [Int], into encoder: inout OpusRangeEncoder) throws {
        let value = try index(of: vector)
        if pulseCount > 0 { try encoder.encodeUniform(value, total: codewordCount) }
    }

    /// Reads one uniform pulse codeword and reconstructs its signed integer components.
    /// - Parameter decoder: Caller-owned usable entropy decoder. Nonzero pulses consume
    ///   one coding operation; zero pulses consume none and return the zero vector.
    /// - Returns: The exact codeword, independent of any CELT band gain or normalization.
    /// - Throws: `OpusRangeCodingError` according to the decoder's state, operation budget
    ///   and corruption checks. Range corruption can invalidate that decoder; discard it.
    ///   Valid decoded indices cannot throw `invalidIndex` from the internal reconstruction.
    public func decode(from decoder: inout OpusRangeDecoder) throws -> [Int] {
        let value = pulseCount == 0 ? 0 : try decoder.decodeUniform(total: codewordCount)
        return try vector(at: value)
    }
}
