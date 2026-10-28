// File: Tests/DiscordMLSTests/MLSWireTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import Foundation
import Testing
@testable import DiscordMLS

/// Deterministic presentation-language tests; no sockets, clocks or Discord identities are used.
@Suite struct MLSWireTests {
    /// Exercises all scalar widths, zero/max values, exact network byte order and cursor exhaustion.
    @Test func scalarRoundTrips() throws {
        var writer = MLSWriter()
        writer.write(UInt8(0x12)); writer.write(UInt16(0x3456)); writer.write(UInt32(0x789abcde))
        writer.write(UInt64(0xfedcba9876543210)); writer.write(UInt8.max); writer.write(UInt16.max)
        writer.write(UInt32.max); writer.write(UInt64.max)
        #expect(writer.data.prefix(7) == Data([0x12, 0x34, 0x56, 0x78, 0x9a, 0xbc, 0xde]))
        var reader = try MLSReader(writer.data)
        #expect(try reader.readUInt8() == 0x12); #expect(try reader.readUInt16() == 0x3456)
        #expect(try reader.readUInt32() == 0x789abcde); #expect(try reader.readUInt64() == 0xfedcba9876543210)
        #expect(try reader.readUInt8() == .max); #expect(try reader.readUInt16() == .max)
        #expect(try reader.readUInt32() == .max); #expect(try reader.readUInt64() == .max)
        #expect(reader.isAtEnd); #expect(reader.remainingCount == 0); try reader.requireEnd()
        #expect(throws: MLSError.malformedEncoding) { try reader.readUInt8() }
    }

    /// Checks canonical vector prefix transitions at each supported encoding width.
    /// - Parameter count: Payload bytes around 6-bit and 14-bit length boundaries.
    @Test(arguments: [0, 1, 63, 64, 16_383, 16_384, 65_536])
    func vectorLengthBoundaries(count: Int) throws {
        let payload = Data(repeating: 0xa5, count: count); var writer = MLSWriter()
        try writer.writeVector(payload)
        let header = count < 64 ? 1 : count < 16_384 ? 2 : 4
        #expect(writer.data.count == count + header)
        #expect(writer.data[0] >> 6 == (header == 1 ? 0 : header == 2 ? 1 : 2))
        var reader = try MLSReader(writer.data); #expect(try reader.readVector() == payload); try reader.requireEnd()
    }

    /// Rejects forbidden prefix 11, nonminimal lengths, truncated prefixes and truncated vector bodies.
    /// - Parameter bytes: Deliberately malformed canonical-vector encodings.
    @Test(arguments: [[UInt8](), [0xc0], [0xff], [0x40], [0x80, 0x00], [0x40, 0x00], [0x40, 0x3f], [0x80, 0x00, 0x00, 0x40], [0x80, 0x00, 0x3f, 0xff], [0x03, 0x01, 0x02], [0x40, 0x40, 0]])
    func malformedVector(bytes: [UInt8]) throws {
        var reader = try MLSReader(Data(bytes)); #expect(throws: MLSError.malformedEncoding) { try reader.readVector() }
    }

    /// Covers all fixed-width truncation boundaries and atomic raw-read failure behavior.
    @Test func truncatedScalarsAndRawReads() throws {
        for count in 0..<8 {
            var reader = try MLSReader(Data(repeating: 0xff, count: count))
            #expect(throws: MLSError.malformedEncoding) { try reader.readUInt64() }
            #expect(reader.remainingCount == count)
        }
        for count in 0..<4 {
            var reader = try MLSReader(Data(repeating: 0xff, count: count))
            #expect(throws: MLSError.malformedEncoding) { try reader.readUInt32() }
        }
        for count in 0..<2 {
            var reader = try MLSReader(Data(repeating: 0xff, count: count))
            #expect(throws: MLSError.malformedEncoding) { try reader.readUInt16() }
        }
        var reader = try MLSReader(Data([1, 2, 3]))
        #expect(try reader.readRaw(count: 0).isEmpty)
        #expect(throws: MLSError.malformedEncoding) { try reader.readRaw(count: -1) }
        #expect(throws: MLSError.malformedEncoding) { try reader.readRaw(count: .max) }
        #expect(reader.remainingCount == 3)
        #expect(throws: MLSError.malformedEncoding) { try reader.requireEnd() }
        #expect(try reader.readRaw(count: 3) == Data([1, 2, 3])); try reader.requireEnd()
    }

    /// Verifies constructor/aggregate budgets before allocation and unchanged writers on overflow.
    @Test func budgetsAndSlicedInput() throws {
        #expect(throws: MLSError.invalidConfiguration) { try MLSReader(Data(), maximumBytes: 0) }
        #expect(throws: MLSError.capacityExceeded) { try MLSReader(Data(count: 5), maximumBytes: 4) }
        var writer = MLSWriter(maximumBytes: 4); try writer.writeVector(Data([1, 2, 3]))
        let before = writer.data
        #expect(throws: MLSError.capacityExceeded) { try writer.writeVector(Data()) }
        #expect(writer.data == before)
        #expect(throws: MLSError.capacityExceeded) { try writer.writeRaw(Data([5])) }
        #expect(writer.data == before)
        var invalid = MLSWriter(maximumBytes: 0)
        #expect(throws: MLSError.capacityExceeded) { try invalid.writeVector(Data()) }
        #expect(throws: MLSError.capacityExceeded) { try invalid.writeRaw(Data()) }
        var lengthOverflow = try MLSReader(Data([0x40, 0x40]), maximumBytes: 8)
        #expect(throws: MLSError.capacityExceeded) { try lengthOverflow.readVector() }
        let backing = Data([0xff, 0xff]) + before
        var sliced = try MLSReader(backing.dropFirst(2)); #expect(try sliced.readVector() == Data([1, 2, 3]))
        try sliced.requireEnd()
    }

    /// Preserves unknown extension bytes, empty vectors and order; duplicate types cannot be admitted.
    @Test func extensionRoundTripsAndBounds() throws {
        let first = try MLSExtension(type: 0xfafa, data: Data([1, 2, 3]))
        let second = try MLSExtension(type: 0xffff, data: Data())
        var reader = try MLSReader(MLSExtension.encodeList([first, second]))
        #expect(try MLSExtension.decodeList(&reader) == [first, second]); try reader.requireEnd()
        var empty = try MLSReader(MLSExtension.encodeList([])); #expect(try MLSExtension.decodeList(&empty).isEmpty)
        #expect(throws: MLSError.malformedEncoding) { try MLSExtension.encodeList([first, first]) }
        #expect(throws: MLSError.capacityExceeded) { try MLSExtension(type: 1, data: Data(count: 65_537)) }
        #expect(throws: MLSError.capacityExceeded) { try MLSExtension.encodeList(Array(repeating: first, count: 129)) }
        var duplicateBody = MLSWriter(); try duplicateBody.writeRaw(first.encoded()); try duplicateBody.writeRaw(first.encoded())
        var duplicate = MLSWriter(); try duplicate.writeVector(duplicateBody.data)
        var duplicateReader = try MLSReader(duplicate.data)
        #expect(throws: MLSError.malformedEncoding) { try MLSExtension.decodeList(&duplicateReader) }
        let largest = try MLSExtension(type: 1, data: Data(count: 65_536))
        #expect(try largest.encoded().count == 65_542)
    }

    /// Asserts explicit version/suite and stable context encoding, including epoch-zero empty transcript.
    @Test func contextRoundTrips() throws {
        let extensionValue = try MLSExtension(type: 0xfafa, data: Data([9]))
        let context = try MLSGroupContext(groupID: Data([1]), epoch: .max, treeHash: Data(repeating: 2, count: 32),
                                          confirmedTranscriptHash: Data(repeating: 3, count: 32), extensions: [extensionValue])
        let bytes = try context.encoded()
        #expect(bytes.prefix(4) == Data([0, 1, 0, 2])); #expect(try MLSGroupContext.decode(bytes) == context)
        let zero = try MLSGroupContext(groupID: Data([1]), epoch: 0, treeHash: Data(count: 32), confirmedTranscriptHash: Data())
        #expect(try MLSGroupContext.decode(zero.encoded()) == zero)
        for count in 0..<bytes.count { #expect(throws: (any Error).self) { try MLSGroupContext.decode(bytes.prefix(count)) } }
        #expect(throws: MLSError.malformedEncoding) { try MLSGroupContext.decode(bytes + Data([0])) }
        var version = bytes; version[1] = 2
        #expect(throws: MLSError.unsupportedVersion) { try MLSGroupContext.decode(version) }
        var suite = bytes; suite[3] = 1
        #expect(throws: MLSError.unsupportedCipherSuite) { try MLSGroupContext.decode(suite) }
    }

    /// Rejects empty/oversized group IDs and invalid hash sizes while allowing provisional empty transcripts.
    @Test func contextInvalidFields() throws {
        for id in [Data(), Data(count: 256)] {
            #expect(throws: MLSError.invalidConfiguration) {
                try MLSGroupContext(groupID: id, epoch: 0, treeHash: Data(count: 32), confirmedTranscriptHash: Data())
            }
        }
        for size in [0, 31, 33] {
            #expect(throws: MLSError.invalidConfiguration) {
                try MLSGroupContext(groupID: Data([1]), epoch: 0, treeHash: Data(count: size), confirmedTranscriptHash: Data())
            }
        }
        let provisional = try MLSGroupContext(groupID: Data([1]), epoch: 1, treeHash: Data(count: 32), confirmedTranscriptHash: Data())
        #expect(try MLSGroupContext.decode(provisional.encoded()) == provisional)
        #expect(throws: MLSError.invalidConfiguration) {
            try MLSGroupContext(groupID: Data([1]), epoch: 0, treeHash: Data(count: 32), confirmedTranscriptHash: Data([1]))
        }
    }
}
