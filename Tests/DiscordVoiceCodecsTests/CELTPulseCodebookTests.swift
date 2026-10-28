// File: Tests/DiscordVoiceCodecsTests/CELTPulseCodebookTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import Foundation
import Testing
@testable import DiscordVoiceCodecs

@Suite("CELT integer pulse codebooks")
struct CELTPulseCodebookTests {
    /// Checks published V(N,K) counts independently of the implementation's U recurrence.
    /// Includes zero pulses, unit dimensions and exact signed-codeword counts from RFC 6716.
    @Test func publishedCounts() throws {
        let counts = [
            [1, 2, 2, 2, 2, 2], [1, 4, 8, 12, 16, 20],
            [1, 6, 18, 38, 66, 102], [1, 8, 32, 88, 192, 360],
            [1, 10, 50, 170, 450, 1002], [1, 12, 72, 292, 912, 2364],
        ]
        for (n, row) in counts.enumerated() {
            for (k, count) in row.enumerated() {
                let book = try CELTPulseCodebook(dimensions: n + 1, pulseCount: k)
                #expect(book.dimensions == n + 1 && book.pulseCount == k)
                #expect(book.codewordCount == UInt32(count))
            }
        }
    }

    /// Checks the CELT sign/magnitude ordering against explicit two- and three-dimensional cases.
    /// The assertions prevent a lexicographic but internally invertible substitute enumeration.
    @Test func orderedVectors() throws {
        let two = try CELTPulseCodebook(dimensions: 2, pulseCount: 2)
        let expected = [[2, 0], [1, 1], [1, -1], [0, 2], [0, -2], [-2, 0], [-1, 1], [-1, -1]]
        for (index, vector) in expected.enumerated() {
            #expect(try two.index(of: vector) == UInt32(index))
            #expect(try two.vector(at: UInt32(index)) == vector)
        }
        let three = try CELTPulseCodebook(dimensions: 3, pulseCount: 1)
        let units = [[1, 0, 0], [0, 1, 0], [0, 0, 1], [0, 0, -1], [0, -1, 0], [-1, 0, 0]]
        for (index, vector) in units.enumerated() {
            #expect(try three.vector(at: UInt32(index)) == vector)
        }
    }

    /// Exhaustively checks every codeword in small dimensions/pulse counts, including uniqueness,
    /// L1 norm and both inverse directions, then tests representative large accepted codebooks.
    @Test func exhaustiveBijectionAndLargeBoundaries() throws {
        for n in 1...6 {
            for k in 0...6 {
                let book = try CELTPulseCodebook(dimensions: n, pulseCount: k)
                var seen: Set<[Int]> = []
                for index in 0..<book.codewordCount {
                    let vector = try book.vector(at: index)
                    #expect(vector.count == n && vector.reduce(0) { $0 + abs($1) } == k)
                    #expect(seen.insert(vector).inserted)
                    #expect(try book.index(of: vector) == index)
                }
                #expect(seen.count == Int(book.codewordCount))
            }
        }
        for (n, k) in [(1, 128), (2, 128), (6, 88), (176, 4)] {
            let book = try CELTPulseCodebook(dimensions: n, pulseCount: k)
            for index in [UInt32(0), 1, book.codewordCount / 2, book.codewordCount - 1] {
                let vector = try book.vector(at: index)
                #expect(try book.index(of: vector) == index)
                #expect(vector.reduce(0) { $0 + abs($1) } == k)
            }
        }
    }

    /// Verifies exact codeword counts and vectors from independently compiled, unmodified
    /// official libopus 1.6.1 cwrs.c, using the pinned reference archive. These forty
    /// cases cover sign ordering, interior codewords, high pulse counts and 176 dimensions.
    /// They verify integer-codebook behavior; decoded-PCM conformance has separate coverage.
    @Test func officialCodewordFixtures() throws {
        let fixtures: [(Int, Int, UInt32, UInt32, [(Int, Int)])] = [
            (2, 2, 8, 0, [(0, 2)]),
            (2, 2, 8, 1, [(0, 1), (1, 1)]),
            (2, 2, 8, 2, [(0, 1), (1, -1)]),
            (2, 2, 8, 4, [(1, -2)]),
            (2, 2, 8, 7, [(0, -1), (1, -1)]),
            (3, 3, 38, 0, [(0, 3)]),
            (3, 3, 38, 1, [(0, 2), (1, 1)]),
            (3, 3, 38, 12, [(0, 1), (1, -1), (2, -1)]),
            (3, 3, 38, 19, [(2, -3)]),
            (3, 3, 38, 37, [(0, -1), (1, -1), (2, -1)]),
            (4, 4, 192, 0, [(0, 4)]),
            (4, 4, 192, 1, [(0, 3), (1, 1)]),
            (4, 4, 192, 64, [(1, 3), (2, 1)]),
            (4, 4, 192, 96, [(3, -4)]),
            (4, 4, 192, 191, [(0, -1), (1, -1), (2, -1), (3, -1)]),
            (6, 8, 20256, 0, [(0, 8)]),
            (6, 8, 20256, 1, [(0, 7), (1, 1)]),
            (6, 8, 20256, 6752, [(0, 1), (1, -1), (2, 1), (4, 1), (5, 4)]),
            (6, 8, 20256, 10128, [(5, -8)]),
            (6, 8, 20256, 20255, [(0, -1), (1, -1), (2, -1), (3, -1), (4, -1), (5, -3)]),
            (8, 12, 2187520, 0, [(0, 12)]),
            (8, 12, 2187520, 1, [(0, 11), (1, 1)]),
            (8, 12, 2187520, 729173, [(0, 1), (1, -2), (2, -2), (4, -6), (6, 1)]),
            (8, 12, 2187520, 1093760, [(7, -12)]),
            (8, 12, 2187520, 2187519, [(0, -1), (1, -1), (2, -1), (3, -1), (4, -1), (5, -1), (6, -1), (7, -5)]),
            (16, 12, 3575055360, 0, [(0, 12)]),
            (16, 12, 3575055360, 1, [(0, 11), (1, 1)]),
            (16, 12, 3575055360, 1191685120, [(1, 1), (3, 1), (5, -2), (8, 1), (9, -1), (11, -2), (13, -2), (14, 2)]),
            (16, 12, 3575055360, 1787527680, [(15, -12)]),
            (16, 12, 3575055360, 3575055359, [(0, -1), (1, -1), (2, -1), (3, -1), (4, -1), (5, -1), (6, -1), (7, -1), (8, -1), (9, -1), (10, -1), (11, -1)]),
            (48, 6, 1091884544, 0, [(0, 6)]),
            (48, 6, 1091884544, 1, [(0, 5), (1, 1)]),
            (48, 6, 1091884544, 363961514, [(8, 2), (16, -1), (18, -1), (28, -1), (43, 1)]),
            (48, 6, 1091884544, 545942272, [(47, -6)]),
            (48, 6, 1091884544, 1091884543, [(0, -1), (1, -1), (2, -1), (3, -1), (4, -1), (5, -1)]),
            (176, 4, 639716352, 0, [(0, 4)]),
            (176, 4, 639716352, 1, [(0, 3), (1, 1)]),
            (176, 4, 639716352, 213238784, [(42, 1), (72, 1), (160, -1), (173, 1)]),
            (176, 4, 639716352, 319858176, [(175, -4)]),
            (176, 4, 639716352, 639716351, [(0, -1), (1, -1), (2, -1), (3, -1)]),
        ]
        for (n, k, count, index, components) in fixtures {
            let book = try CELTPulseCodebook(dimensions: n, pulseCount: k)
            var expected = Array(repeating: 0, count: n)
            for (position, value) in components { expected[position] = value }
            #expect(book.codewordCount == count)
            #expect(try book.vector(at: index) == expected)
            #expect(try book.index(of: expected) == index)
        }
    }

    /// Rejects invalid sizes, overflowing codebook counts, indices, norms and extreme integers.
    /// Every rejection preserves immutable codebook and caller-owned entropy state.
    @Test func invalidArguments() throws {
        for n in [Int.min, 0, 177, Int.max] {
            #expect(throws: CELTPulseCodebookError.invalidDimensions) {
                try CELTPulseCodebook(dimensions: n, pulseCount: 1)
            }
        }
        for k in [Int.min, -1, 129, Int.max] {
            #expect(throws: CELTPulseCodebookError.invalidPulseCount) {
                try CELTPulseCodebook(dimensions: 2, pulseCount: k)
            }
        }
        #expect(throws: CELTPulseCodebookError.codebookTooLarge) {
            try CELTPulseCodebook(dimensions: 176, pulseCount: 128)
        }
        let book = try CELTPulseCodebook(dimensions: 2, pulseCount: 1)
        var encoder = try OpusRangeEncoder(frameByteCount: 8)
        for vector in [[], [1], [1, 0, 0], [0, 0], [1, 1], [Int.min, 0], [Int.max, 0], [-2, 1]] {
            #expect(throws: CELTPulseCodebookError.invalidVector) { try book.index(of: vector) }
            #expect(throws: CELTPulseCodebookError.invalidVector) { try book.encode(vector, into: &encoder) }
            #expect(encoder.operationCount == 0)
        }
        for index in [book.codewordCount, UInt32.max] {
            #expect(throws: CELTPulseCodebookError.invalidIndex) { try book.vector(at: index) }
        }
    }

    /// Composes codeword indices with the independently tested Opus range coder, checking
    /// exact range agreement and operation ownership for mixed pulse counts and zero pulses.
    @Test func entropyComposition() throws {
        let books = try [(1, 0), (1, 128), (2, 10), (5, 6), (176, 4)].map {
            try CELTPulseCodebook(dimensions: $0.0, pulseCount: $0.1)
        }
        var encoder = try OpusRangeEncoder(frameByteCount: 64)
        var expected: [[Int]] = []
        var ranges: [UInt32] = []
        for book in books {
            let vector = try book.vector(at: book.codewordCount - 1)
            try book.encode(vector, into: &encoder)
            expected.append(vector)
            ranges.append(encoder.finalRange)
        }
        #expect(encoder.operationCount == 4)
        var decoder = try OpusRangeDecoder(frame: encoder.finalize())
        for (index, book) in books.enumerated() {
            #expect(try book.decode(from: &decoder) == expected[index])
            #expect(decoder.finalRange == ranges[index])
        }
        #expect(decoder.operationCount == 4)
    }

    /// Exercises zero-pulse/no-operation behavior on terminal entropy owners, and propagates
    /// encoder/decoder operation-budget failures without converting them into valid codewords.
    @Test func entropyFailureAndZeroPulseOwnership() throws {
        let zero = try CELTPulseCodebook(dimensions: 176, pulseCount: 0)
        let nonzero = try CELTPulseCodebook(dimensions: 2, pulseCount: 1)
        var encoder = try OpusRangeEncoder(frameByteCount: 8, maximumOperations: 1)
        try nonzero.encode([1, 0], into: &encoder)
        #expect(throws: OpusRangeCodingError.operationLimitExceeded) { try nonzero.encode([0, -1], into: &encoder) }
        let bytes = try encoder.finalize()
        try zero.encode(Array(repeating: 0, count: 176), into: &encoder)
        #expect(throws: OpusRangeCodingError.finalized) { try nonzero.encode([1, 0], into: &encoder) }
        var decoder = try OpusRangeDecoder(frame: bytes, maximumOperations: 1)
        #expect(try nonzero.decode(from: &decoder) == [1, 0])
        #expect(try zero.decode(from: &decoder) == Array(repeating: 0, count: 176))
        #expect(throws: OpusRangeCodingError.operationLimitExceeded) { try nonzero.decode(from: &decoder) }
    }
}
