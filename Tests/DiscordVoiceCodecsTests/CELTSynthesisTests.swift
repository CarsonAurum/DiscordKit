import Foundation
@testable import DiscordVoiceCodecs
import Testing

/// Complete independent PCM sequences check short/long transforms, overlap and delayed signal filters.
@Suite("CELT ordinary signal synthesis")
struct CELTSynthesisTests {
    /// Every reference sample is compared, including duration/transient changes and all pitch/gain extremes.
    @Test func independentMultiframeSignalVectors() throws {
        let records = try JSONDecoder().decode([SynthesisFixture].self, from: Data(CELTSynthesisOracleFixtures.json.utf8))
        #expect(records.count == 34)
        var samples = 0
        for record in records {
            var synthesis = try CELTSynthesis(channelCount: record.input.channels)
            #expect(synthesis.channelCount == record.input.channels)
            #expect(record.output.count == record.input.frames.count)
            for (frame, encoded) in zip(record.input.frames, record.output) {
                let actual = try synthesize(frame, using: &synthesis)
                let expected = try decodeFloatVector(encoded)
                #expect(actual.count == (120 << frame.lm) * record.input.channels && actual.count == expected.count)
                let scale = max(1, expected.map { abs($0) }.max() ?? 0)
                for (a, e) in zip(actual, expected) {
                    #expect(a.isFinite && abs(a - e) <= 0.000003 * scale + 0.000008 * abs(e))
                }
                samples += actual.count
            }
        }
        #expect(samples > 20_000)
    }

    /// Invalid extreme sizes, arrays and nonfinite inputs are atomic even after nonzero overlap/filter state.
    @Test func malformedInputsPreserveCompleteSignalState() throws {
        for channels in [Int.min, -1, 0, 3, Int.max] {
            #expect(throws: CELTSynthesisError.invalidChannelCount) { try CELTSynthesis(channelCount: channels) }
        }
        var synthesis = try CELTSynthesis()
        let coefficients = (0..<240).map { Float(($0 * 17) % 51 - 25) / 64 }
        let energies = Array(repeating: Float(4), count: 21)
        let filter = try CELTPostfilterParameters(period: 15, gainIndex: 7, tapset: 2)
        _ = try synthesis.synthesize(normalizedCoefficients: coefficients, bandLogEnergies: energies,
                                      frameSampleCount: 240, postfilter: filter)
        var baseline = synthesis
        for channels in [Int.min, -1, 0, 3, Int.max] {
            #expect(throws: CELTSynthesisError.invalidChannelCount) {
                try synthesis.synthesize(normalizedCoefficients: coefficients, bandLogEnergies: energies,
                    frameSampleCount: 240, codedChannelCount: channels)
            }
        }
        #expect(throws: CELTSynthesisError.invalidCoefficients) {
            try synthesis.synthesize(normalizedCoefficients: coefficients, bandLogEnergies: energies,
                frameSampleCount: 240, codedChannelCount: 2)
        }
        #expect(throws: CELTSynthesisError.invalidBandEnergies) {
            try synthesis.synthesize(normalizedCoefficients: coefficients + coefficients, bandLogEnergies: energies,
                frameSampleCount: 240, codedChannelCount: 2)
        }
        for size in [Int.min, -1, 0, 119, 121, 1920, Int.max] {
            #expect(throws: CELTSynthesisError.invalidFrameSize) {
                try synthesis.synthesize(normalizedCoefficients: coefficients, bandLogEnergies: energies, frameSampleCount: size)
            }
        }
        for (start, end) in [(Int.min,21),(-1,21),(0,0),(20,20),(21,21),(0,22),(0,Int.max),(Int.max,Int.min)] {
            #expect(throws: CELTSynthesisError.invalidBandRange) {
                try synthesis.synthesize(normalizedCoefficients: coefficients, bandLogEnergies: energies,
                                          frameSampleCount: 240, startBand: start, endBand: end)
            }
        }
        for count in [0, 1, 239, 241, 1921] {
            #expect(throws: CELTSynthesisError.invalidCoefficients) {
                try synthesis.synthesize(normalizedCoefficients: Array(repeating: 0, count: count),
                                          bandLogEnergies: energies, frameSampleCount: 240)
            }
        }
        for invalid in [Float.nan, .infinity, -.infinity, -4.0001, 4.0001, .greatestFiniteMagnitude] {
            var input = coefficients
            input[239] = invalid
            #expect(throws: CELTSynthesisError.invalidCoefficients) {
                try synthesis.synthesize(normalizedCoefficients: input, bandLogEnergies: energies, frameSampleCount: 240, silence: true)
            }
        }
        for count in [0, 1, 20, 22, 42] {
            #expect(throws: CELTSynthesisError.invalidBandEnergies) {
                try synthesis.synthesize(normalizedCoefficients: coefficients, bandLogEnergies: Array(repeating: 0, count: count), frameSampleCount: 240)
            }
        }
        for invalid in [Float.nan, .infinity, -.infinity, -32_769, 32_769, .greatestFiniteMagnitude] {
            var input = energies
            input[20] = invalid
            #expect(throws: CELTSynthesisError.invalidBandEnergies) {
                try synthesis.synthesize(normalizedCoefficients: coefficients, bandLogEnergies: input, frameSampleCount: 240)
            }
        }
        #expect(throws: CELTSynthesisError.invalidTransient) {
            try synthesis.synthesize(normalizedCoefficients: Array(coefficients.prefix(120)), bandLogEnergies: energies,
                                      frameSampleCount: 120, isTransient: true)
        }
        let actual = try synthesis.synthesize(normalizedCoefficients: coefficients, bandLogEnergies: energies, frameSampleCount: 240)
        let expected = try baseline.synthesize(normalizedCoefficients: coefficients, bandLogEnergies: energies, frameSampleCount: 240)
        #expect(actual == expected)
    }

    /// Value copies fork histories, reset restores startup and silent frames drain the retained signal tail.
    @Test func copyResetSilenceAndChannelIndependence() throws {
        let coefficients = (0..<240).map { Float(($0 * 37) % 101 - 50) / 512 }
        let energies = Array(repeating: Float(4), count: 21)
        var synthesis = try CELTSynthesis()
        let startup = try synthesis.synthesize(normalizedCoefficients: coefficients, bandLogEnergies: energies, frameSampleCount: 240)
        #expect(startup.contains { abs($0) > 0.001 })
        var copy = synthesis
        let continued = try copy.synthesize(normalizedCoefficients: coefficients, bandLogEnergies: energies, frameSampleCount: 240)
        #expect(continued != startup)
        synthesis.reset()
        #expect(try synthesis.synthesize(normalizedCoefficients: coefficients, bandLogEnergies: energies, frameSampleCount: 240) == startup)
        let drained = try synthesis.synthesize(normalizedCoefficients: coefficients, bandLogEnergies: energies, frameSampleCount: 240, silence: true)
        #expect(drained.prefix(120).contains { abs($0) > 0.001 })
        #expect(abs(drained.last ?? 1) < 0.000001)
        var stereo = try CELTSynthesis(channelCount: 2)
        let stereoOutput = try stereo.synthesize(normalizedCoefficients: coefficients + coefficients,
            bandLogEnergies: energies + energies, frameSampleCount: 240)
        for index in 0..<240 {
            #expect(stereoOutput[2 * index] == startup[index] && stereoOutput[2 * index + 1] == startup[index])
        }
    }

    /// The exact exponent floor/cap is bounded and inactive coefficients, including unused high bins, remain silent.
    @Test func exponentAndActiveBandBoundaries() throws {
        let coefficients = Array(repeating: Float(4), count: 960)
        for energy in [Float(-32_768), -60, -50, 32_768] {
            var synthesis = try CELTSynthesis()
            let output = try synthesis.synthesize(normalizedCoefficients: coefficients,
                bandLogEnergies: Array(repeating: energy, count: 21), frameSampleCount: 960, startBand: 20)
            #expect(output.allSatisfy { $0.isFinite })
            if energy <= -60 { #expect(output.allSatisfy { abs($0) < 1e-30 }) }
            if energy == 32_768 { #expect(output.contains { abs($0) > 1 }) }
        }
        var synthesis = try CELTSynthesis()
        var inactive = Array(repeating: Float(0), count: 120)
        inactive[119] = 4
        let output = try synthesis.synthesize(normalizedCoefficients: inactive,
            bandLogEnergies: Array(repeating: 32_768, count: 21), frameSampleCount: 120)
        #expect(output.allSatisfy { abs($0) < 1e-30 })
    }

    /// Every duration and short-block layout supports both conversions while retaining independent output histories.
    /// A changing coded-channel sequence is also compared with two separately owned mono signal histories;
    /// different channel envelopes ensure downmixing happens after denormalization rather than before it.
    /// - Parameter sampleCount: One ordinary 48-kHz CELT frame size in samples per output channel.
    /// - Throws: Input or transform errors would indicate an invalid test setup or implementation regression.
    @Test(arguments: [120, 240, 480, 960])
    func codedChannelConversionAndSwitches(sampleCount: Int) throws {
        for transient in sampleCount == 120 ? [false] : [false, true] {
            var stereo = try CELTSynthesis(channelCount: 2)
            var downmix = try CELTSynthesis()
            var left = try CELTSynthesis()
            var right = try CELTSynthesis()
            let filter = try CELTPostfilterParameters(period: 63, gainIndex: 4, tapset: 1)
            for (frameIndex, codedChannels) in [2, 1, 2, 1, 1, 2].enumerated() {
                let first = (0..<sampleCount).map { Float(($0 * 37 + frameIndex * 11) % 101 - 50) / 512 }
                let second = codedChannels == 1 ? first : first.map { -0.75 * $0 }
                let firstEnergies = Array(repeating: Float(4), count: 21)
                let secondEnergies = codedChannels == 1 ? firstEnergies : Array(repeating: Float(7), count: 21)
                let coefficients = codedChannels == 1 ? first : first + second
                let energies = codedChannels == 1 ? firstEnergies : firstEnergies + secondEnergies
                let silence = frameIndex == 4
                let actual = try stereo.synthesize(normalizedCoefficients: coefficients, bandLogEnergies: energies,
                    frameSampleCount: sampleCount, isTransient: transient, postfilter: filter,
                    silence: silence, codedChannelCount: codedChannels)
                let mixed = try downmix.synthesize(normalizedCoefficients: coefficients, bandLogEnergies: energies,
                    frameSampleCount: sampleCount, isTransient: transient, postfilter: filter,
                    silence: silence, codedChannelCount: codedChannels)
                let leftOutput = try left.synthesize(normalizedCoefficients: first, bandLogEnergies: firstEnergies,
                    frameSampleCount: sampleCount, isTransient: transient, postfilter: filter, silence: silence)
                let rightOutput = try right.synthesize(normalizedCoefficients: second, bandLogEnergies: secondEnergies,
                    frameSampleCount: sampleCount, isTransient: transient, postfilter: filter, silence: silence)
                #expect(actual.count == sampleCount * 2 && mixed.count == sampleCount)
                for sample in 0..<sampleCount {
                    #expect(actual[2 * sample] == leftOutput[sample])
                    #expect(actual[2 * sample + 1] == rightOutput[sample])
                    let expected = 0.5 * leftOutput[sample] + 0.5 * rightOutput[sample]
                    #expect(abs(mixed[sample] - expected) <= 0.00003 + 0.00003 * abs(expected))
                }
                if frameIndex == 1 {
                    #expect((0..<sampleCount).contains { actual[2 * $0] != actual[2 * $0 + 1] })
                }
            }
            stereo.reset()
            var mono = try CELTSynthesis()
            let coefficients = Array(repeating: Float(0.125), count: sampleCount)
            let energies = Array(repeating: Float(4), count: 21)
            let duplicated = try stereo.synthesize(normalizedCoefficients: coefficients, bandLogEnergies: energies,
                frameSampleCount: sampleCount, codedChannelCount: 1)
            let original = try mono.synthesize(normalizedCoefficients: coefficients, bandLogEnergies: energies,
                frameSampleCount: sampleCount)
            for sample in 0..<sampleCount {
                #expect(duplicated[2 * sample] == original[sample] && duplicated[2 * sample + 1] == original[sample])
            }
        }
    }

    /// Applies one reference frame without altering its independent layout or syntax choices.
    /// - Parameters:
    ///   - frame: Literal reference configuration and normalized spectrum/envelope.
    ///   - synthesis: Value-owned history shared only with successive frames in its sequence.
    /// - Returns: Interleaved normalized PCM for every sample/channel.
    /// - Throws: Owned input validation or transform errors, indicating invalid fixture/implementation.
    private func synthesize(_ frame: SynthesisFixture.Frame, using synthesis: inout CELTSynthesis) throws -> [Float] {
        let filter = frame.period == 0 ? nil : try CELTPostfilterParameters(period: frame.period,
            gainIndex: frame.gainIndex, tapset: frame.tapset)
        return try synthesis.synthesize(normalizedCoefficients: frame.coefficients, bandLogEnergies: frame.energies,
            frameSampleCount: 120 << frame.lm, startBand: frame.start, endBand: frame.end,
            isTransient: frame.transient, postfilter: filter, silence: frame.silence,
            codedChannelCount: frame.codedChannelCount)
    }

    /// Reads exact complete little-endian float32 vectors without alignment assumptions or unsafe pointers.
    /// - Parameter encoded: Valid base64 containing a multiple of four bytes of independently emitted PCM.
    /// - Returns: Every reference sample, preserving its exact binary floating-point value.
    /// - Throws: Swift Testing requirement failure for invalid base64/length; fixtures are not regenerated here.
    private func decodeFloatVector(_ encoded: String) throws -> [Float] {
        let data = try #require(Data(base64Encoded: encoded))
        try #require(data.count.isMultiple(of: 4))
        let bytes = Array(data)
        return stride(from: 0, to: bytes.count, by: 4).map { index in
            let bits = UInt32(bytes[index]) | UInt32(bytes[index + 1]) << 8
                | UInt32(bytes[index + 2]) << 16 | UInt32(bytes[index + 3]) << 24
            return Float(bitPattern: bits)
        }
    }
}

/// Literal independent signal contexts and complete base64 PCM vectors, with no native runtime dependency.
private struct SynthesisFixture: Decodable {
    let input: Input
    let output: [String]
    struct Input: Decodable { let channels: Int; let frames: [Frame] }
    struct Frame: Decodable {
        let lm: Int; let start: Int; let end: Int; let transient: Bool
        let period: Int; let gainIndex: Int; let tapset: Int; let silence: Bool
        let coefficients: [Float]; let energies: [Float]
        let codedChannelCount: Int?
    }
}
