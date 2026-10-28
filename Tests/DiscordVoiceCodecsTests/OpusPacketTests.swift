// File: Tests/DiscordVoiceCodecsTests/OpusPacketTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import Foundation
import Testing
import DiscordMedia
@testable import DiscordVoiceCodecs

@Suite("Owned Opus packet framing")
struct OpusPacketTests {
    /// Exhausts all 32 TOC configurations in both channel modes using a zero-byte frame.
    /// Expected tables are explicit RFC 6716 section 3.1 fixtures, independent of parser code.
    @Test func tocConfigurations() throws {
        let samples = [480, 960, 1_920, 2_880, 480, 960, 1_920, 2_880,
                       480, 960, 1_920, 2_880, 480, 960, 480, 960,
                       120, 240, 480, 960, 120, 240, 480, 960,
                       120, 240, 480, 960, 120, 240, 480, 960]
        let bandwidths: [OpusBandwidth] = [
            .narrowband, .narrowband, .narrowband, .narrowband,
            .mediumband, .mediumband, .mediumband, .mediumband,
            .wideband, .wideband, .wideband, .wideband,
            .superwideband, .superwideband, .fullband, .fullband,
            .narrowband, .narrowband, .narrowband, .narrowband,
            .wideband, .wideband, .wideband, .wideband,
            .superwideband, .superwideband, .superwideband, .superwideband,
            .fullband, .fullband, .fullband, .fullband,
        ]
        for config in 0..<32 {
            for stereo in [false, true] {
                let data = Data([UInt8(config << 3) | (stereo ? 4 : 0)])
                let packet = try OpusPacket(data)
                #expect(packet.configuration == config && packet.packingCode == 0)
                #expect(packet.channelCount == (stereo ? 2 : 1))
                #expect(packet.mode == (config < 12 ? .silk : config < 16 ? .hybrid : .celt))
                #expect(packet.bandwidth == bandwidths[config])
                #expect(packet.frameSampleCount == samples[config] && packet.sampleCount == samples[config])
                #expect(packet.duration == (try MediaTime(value: Int64(samples[config]), timescale: 48_000)))
                #expect(packet.frameRanges == [1..<1] && packet.paddingByteCount == 0)
                #expect(packet.data == data)
            }
        }
    }

    /// Validates every frame-packing code, byte-accurate ranges, VBR and complete zero-frame payloads.
    /// The synthetic frame bytes only test framing and make no entropy-decoder conformance claim.
    @Test func packingCodes() throws {
        let one = try OpusPacket(Data([0xf8, 0xff, 0xfe]))
        #expect(one.frameRanges == [1..<3] && one.sampleCount == 960)
        let twoEqual = try OpusPacket(Data([0xf9, 0x11, 0x12, 0x21, 0x22]))
        #expect(twoEqual.frameRanges == [1..<3, 3..<5] && twoEqual.sampleCount == 1_920)
        let twoVariable = try OpusPacket(Data([0xfa, 1, 0x11, 0x21, 0x22]))
        #expect(twoVariable.frameRanges == [2..<3, 3..<5] && twoVariable.sampleCount == 1_920)
        let threeEqual = try OpusPacket(Data([0xfb, 3, 0x11, 0x21, 0x31]))
        #expect(threeEqual.frameRanges == [2..<3, 3..<4, 4..<5] && threeEqual.sampleCount == 2_880)
        let threeVariable = try OpusPacket(Data([0xfb, 0x83, 1, 2, 0x11, 0x21, 0x22, 0x31, 0x32, 0x33]))
        #expect(threeVariable.frameRanges == [4..<5, 5..<7, 7..<10])
        #expect(Array(threeVariable.data[threeVariable.frameRanges[1]]) == [0x21, 0x22])
        let zeros: [[UInt8]] = [[0xf9], [0xfa, 0], [0xfb, 3], [0xfb, 0x83, 0, 0], [0xfb, 0x81]]
        for bytes in zeros {
            let packet = try OpusPacket(Data(bytes))
            #expect(packet.frameRanges.allSatisfy { $0.isEmpty })
        }
        let maxFrames = try OpusPacket(Data([0x83, 48]))
        #expect(maxFrames.frameRanges.count == 48 && maxFrames.sampleCount == 5_760)
        let longFrames = try OpusPacket(Data([0x19]))
        #expect(longFrames.sampleCount == 5_760 && longFrames.frameRanges.count == 2)
    }

    /// Covers one/two-byte VBR length boundaries and the largest legal compressed frame.
    /// - Parameter length: RFC-defined boundary length; second frame is zero-byte DTX.
    @Test(arguments: [0, 1, 251, 252, 253, 254, 255, 256, 1_274, 1_275])
    func variableLengthBoundary(length: Int) throws {
        let encoded: [UInt8]
        if length < 252 {
            encoded = [UInt8(length)]
        } else {
            let first = 252 + (length % 4)
            encoded = [UInt8(first), UInt8((length - first) / 4)]
        }
        let data = Data([0xfa] + encoded + Array(repeating: 0x11, count: length))
        let packet = try OpusPacket(data)
        #expect(packet.frameRanges.map(\.count) == [length, 0])
        #expect(packet.frameRanges[0].lowerBound == 1 + encoded.count)
        let codeThree = try OpusPacket(Data([0xfb, 0x82] + encoded + Array(repeating: 0x11, count: length)))
        #expect(codeThree.frameRanges.map(\.count) == [length, 0])
    }

    /// Verifies zero/nonzero padding, 255 continuation arithmetic and arbitrary trailing bytes.
    /// Bounds are checked against unpadded data, including VBR headers adjacent to padding.
    @Test func paddingAndSlicedData() throws {
        let noPadding = try OpusPacket(Data([0xfb, 0x41, 0, 0x11]))
        #expect(noPadding.paddingByteCount == 0 && noPadding.frameRanges == [3..<4])
        let ordinary = try OpusPacket(Data([0xfb, 0x42, 2, 0x11, 0x22, 0xab, 0xcd]))
        #expect(ordinary.paddingByteCount == 2 && ordinary.frameRanges == [3..<4, 4..<5])
        let continued = try OpusPacket(Data([0xfb, 0x41, 255, 1, 0x11] + Array(repeating: 0x7e, count: 255)))
        #expect(continued.paddingByteCount == 255 && continued.frameRanges == [4..<5])
        let twice = try OpusPacket(Data([0xfb, 0x41, 255, 255, 0] + Array(repeating: 0, count: 508)))
        #expect(twice.paddingByteCount == 508 && twice.frameRanges == [5..<5])
        let vbr = try OpusPacket(Data([0xfb, 0xc2, 1, 1, 0x11, 0x22, 0xff]))
        #expect(vbr.frameRanges == [4..<5, 5..<6] && vbr.paddingByteCount == 1)
        let allPadding = try OpusPacket(Data([0xfb, 0xc1, 2, 0xff, 0xfe]))
        #expect(allPadding.frameRanges == [3..<3] && allPadding.paddingByteCount == 2)
        let original = Data([9, 9, 0xf8, 0x11, 9])
        let slice = original[2..<4]
        let packet = try OpusPacket(slice)
        #expect(packet.data.startIndex == 0 && packet.data == Data([0xf8, 0x11]))
        #expect(packet.frameRanges == [1..<2])
    }

    /// Rejects malformed packets for every public failure category at the structural boundary.
    /// - Parameters:
    ///   - bytes: Synthetic packet with a known RFC 6716 R1...R7 framing violation.
    ///   - failure: Expected deterministic structural error; entropy bytes are never inspected.
    @Test(arguments: [
        ([UInt8](), OpusPacketError.missingTOC),
        ([0xf9, 0], .unequalCBRFrames),
        ([0xfa], .truncatedHeader),
        ([0xfa, 252], .truncatedHeader),
        ([0xfa, 1], .invalidFrameLength),
        ([0xfb], .truncatedHeader),
        ([0xfb, 0], .invalidFrameCount),
        ([0xfb, 7], .excessiveDuration),
        ([0x83, 49], .excessiveDuration),
        ([0xfb, 0x41], .invalidPadding),
        ([0xfb, 0x41, 1], .invalidPadding),
        ([0xfb, 0x41, 255], .invalidPadding),
        ([0xfb, 0x41, 255, 0], .invalidPadding),
        ([0xfb, 2, 0], .unequalCBRFrames),
        ([0xfb, 0x82], .truncatedHeader),
        ([0xfb, 0x82, 252], .truncatedHeader),
        ([0xfb, 0x82, 1], .invalidFrameLength),
        ([0xfb, 0x83, 0], .truncatedHeader),
        ([0xfb, 0xc2, 1, 252, 0], .truncatedHeader),
    ])
    func malformedPacket(bytes: [UInt8], failure: OpusPacketError) {
        #expect(throws: failure) { try OpusPacket(Data(bytes)) }
    }

    /// Checks unencoded/inferred frame-size caps for each packing code and packet admission.
    /// Padding-policy overflow is distinct from otherwise legal individual frame lengths.
    @Test func inferredFrameAndPacketLimits() throws {
        let legal = try OpusPacket(Data([0xf8] + Array(repeating: 0, count: 1_275)))
        #expect(legal.frameRanges == [1..<1_276])
        for bytes in [[0xf8] + Array(repeating: UInt8(0), count: 1_276),
                      [0xf9] + Array(repeating: UInt8(0), count: 2_552),
                      [0xfa, 0] + Array(repeating: UInt8(0), count: 1_276),
                      [0xfb, 1] + Array(repeating: UInt8(0), count: 1_276),
                      [0xfb, 0x81] + Array(repeating: UInt8(0), count: 1_276)] {
            #expect(throws: OpusPacketError.invalidFrameLength) { try OpusPacket(Data(bytes)) }
        }
        #expect(throws: OpusPacketError.packetTooLarge) { try OpusPacket(Data(repeating: 255, count: 65_537)) }
        #expect(throws: OpusPacketError.invalidPadding) { try OpusPacket(Data([0xfb, 0x41] + Array(repeating: 255, count: 65_534))) }
        var paddingHeader = [UInt8](repeating: 255, count: 255)
        paddingHeader.append(253)
        let maximum = Data([0xfb, 0x41] + paddingHeader + Array(repeating: 0, count: 65_023) + Array(repeating: 0x11, count: 255))
        #expect(maximum.count == 65_536)
        let parsed = try OpusPacket(maximum)
        #expect(parsed.paddingByteCount == 65_023 && parsed.frameRanges[0].count == 255)
    }

    /// Exercises a reproducible hostile-byte corpus and validates every successful parse's ranges.
    /// A bounded LCG replaces randomness; this tests robustness without sleeps, sockets or decoders.
    @Test func deterministicMalformedCorpus() throws {
        var state: UInt32 = 0x6716_8251
        for length in 0...32 {
            for _ in 0..<64 {
                var bytes: [UInt8] = []
                for _ in 0..<length {
                    state = state &* 1_664_525 &+ 1_013_904_223
                    bytes.append(UInt8(truncatingIfNeeded: state >> 16))
                }
                do {
                    let packet = try OpusPacket(Data(bytes))
                    #expect((1...48).contains(packet.frameRanges.count))
                    #expect((120...5_760).contains(packet.sampleCount))
                    #expect(packet.sampleCount == packet.frameSampleCount * packet.frameRanges.count)
                    #expect(packet.frameRanges.allSatisfy { $0.lowerBound >= 1 && $0.upperBound <= bytes.count && $0.count <= 1_275 })
                    for pair in zip(packet.frameRanges, packet.frameRanges.dropFirst()) {
                        #expect(pair.0.upperBound == pair.1.lowerBound)
                    }
                    #expect(packet.frameRanges.last?.upperBound == bytes.count - packet.paddingByteCount)
                } catch {
                    #expect(error is OpusPacketError)
                }
            }
        }
    }
}
