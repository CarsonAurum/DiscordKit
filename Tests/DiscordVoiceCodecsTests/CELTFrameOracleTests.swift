// File: Tests/DiscordVoiceCodecsTests/CELTFrameOracleTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import Foundation
import Testing
@testable import DiscordVoiceCodecs

@Suite("CELT complete frame native interoperability")
struct CELTFrameOracleTests {
    /// Full official Opus entry-point evidence; PCM is compact little-endian float32.
    private struct Fixture: Decodable {
        let input: Input
        let output: [Output]
        let encodedOutput: [Output]
        struct Input: Decodable {
            let c: Int; let frames: [Frame]
        }
        struct Frame: Decodable {
            let n: Int; let end: Int; let bytes: Int; let intra: Bool; let pcm: String
        }
        struct Output: Decodable {
            let raw: [UInt8]; let toc: UInt8; let range: UInt32; let pcm: String
        }
    }

    /// Official restricted-lowdelay opus_encode_float streams are decoded through the
    /// complete owned raw CELT pipeline. This independently covers all durations,
    /// channels and standard bandwidths, predictor/overlap/seed continuity, genuine
    /// transient/TF/anti-collapse decisions, postfilters, silence and format changes.
    /// Exact final arithmetic range plus full scalar PCM prevents self-roundtrip success
    /// from concealing a different syntax or synthesis convention. No native runtime runs.
    @Test func officialEncoderToOwnedDecoder() throws {
        let fixtures = try JSONDecoder().decode([Fixture].self, from: Data(CELTFrameOracleFixtures.json.utf8))
        #expect(fixtures.count == 36)
        var transients = 0, silences = 0, postfilters = 0
        for fixture in fixtures {
            var decoder = try CELTFrameDecoder(channelCount: fixture.input.c)
            let expected = try fixture.output.map { try unpack($0.pcm) }
            let scale = max(1, expected.flatMap { $0 }.map(abs).max() ?? 0)
            #expect(fixture.input.frames.count == fixture.output.count)
            for (index, pair) in zip(fixture.input.frames, fixture.output).enumerated() {
                let (frame, output) = pair
                let decoded = try decoder.decode(Data(output.raw), frameSampleCount: frame.n, endBand: frame.end)
                #expect(decoded.finalRange == output.range)
                #expect(decoded.frameSampleCount == frame.n && decoded.channelCount == fixture.input.c)
                #expect(decoded.bitsUsed <= output.raw.count * 8)
                assertPCM(decoded.samples, expected[index], scale: scale)
                if decoded.isTransient { transients += 1 }
                if decoded.isSilence { silences += 1 }
                var entropy = try OpusRangeDecoder(frame: Data(output.raw))
                let prefix = try CELTFrameHeader(frameSampleCount: frame.n, channelCount: fixture.input.c,
                    endBand: frame.end).decodePrefix(from: &entropy)
                if prefix.postfilter != nil { postfilters += 1 }
                #expect(Int(output.toc & 3) == 0 && Int((output.toc >> 2) & 1) == fixture.input.c - 1)
            }
        }
        #expect(transients > 0 && silences > 0 && postfilters > 0)
    }

    /// Owned deterministic long-block encoding is checked against bytes independently
    /// decoded by official opus_decode_float. Exact final ranges and complete PCM cover
    /// encoding and decoding together without adopting the native codec as a dependency.
    /// Format changes reset the fixed-format encoder and its independent reference decoder.
    @Test func ownedEncoderToOfficialDecoder() throws {
        let fixtures = try JSONDecoder().decode([Fixture].self, from: Data(CELTFrameOracleFixtures.json.utf8))
        for fixture in fixtures {
            var encoder: CELTFrameEncoder?
            var decoder = try CELTFrameDecoder(channelCount: fixture.input.c)
            var format: [Int] = []
            let expected = try fixture.encodedOutput.map { try unpack($0.pcm) }
            let scale = max(1, expected.flatMap { $0 }.map(abs).max() ?? 0)
            for (index, pair) in zip(fixture.input.frames, fixture.encodedOutput).enumerated() {
                let (frame, output) = pair
                if format != [frame.n, frame.end] {
                    encoder = try CELTFrameEncoder(frameSampleCount: frame.n, channelCount: fixture.input.c, endBand: frame.end)
                    decoder = try CELTFrameDecoder(channelCount: fixture.input.c)
                    format = [frame.n, frame.end]
                }
                var current = try #require(encoder)
                let encoded = try current.encode(try unpack(frame.pcm), frameByteCount: frame.bytes, intra: frame.intra)
                encoder = current
                #expect(Array(encoded.bytes) == output.raw && encoded.finalRange == output.range)
                let decoded = try decoder.decode(encoded.bytes, frameSampleCount: frame.n, endBand: frame.end)
                #expect(decoded.finalRange == output.range)
                assertPCM(decoded.samples, expected[index], scale: scale)
            }
        }
    }

    /// Decodes explicitly ordered bytes without unsafe alignment assumptions or host endianness.
    /// - Parameter encoded: Complete base64 of little-endian scalar float32 values.
    /// - Returns: Finite owned PCM values, preserving every fixture bit pattern.
    /// - Throws: A test requirement failure for malformed base64 or partial float words.
    private func unpack(_ encoded: String) throws -> [Float] {
        let data = try #require(Data(base64Encoded: encoded))
        try #require(data.count % 4 == 0)
        return stride(from: 0, to: data.count, by: 4).map { offset in
            let word = UInt32(data[offset]) | UInt32(data[offset + 1]) << 8
                | UInt32(data[offset + 2]) << 16 | UInt32(data[offset + 3]) << 24
            return Float(bitPattern: word)
        }
    }

    /// Checks complete scalar PCM with the independently measured synthesis error budget.
    /// - Parameters:
    ///   - actual: Owned complete interleaved output frame.
    ///   - expected: Official complete interleaved output frame.
    ///   - scale: Maximum of one and the reference stream's absolute PCM peak, preserving
    ///     a consistent tolerance for overlap/postfilter history after dynamic-range changes.
    private func assertPCM(_ actual: [Float], _ expected: [Float], scale: Float) {
        #expect(actual.count == expected.count)
        #expect(zip(actual, expected).allSatisfy { a, e in
            a.isFinite && e.isFinite && abs(a - e) <= 0.000003 * scale + 0.000008 * abs(e)
        })
    }
}
