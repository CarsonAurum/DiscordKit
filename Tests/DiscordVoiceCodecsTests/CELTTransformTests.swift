import Foundation
import Testing
@testable import DiscordVoiceCodecs

/// Verifies CELT transform mathematics, independent libopus evidence and overlap ownership.
@Suite struct CELTTransformTests {
    /// Rejects unsupported transform lengths/channels before retaining any unbounded tables.
    @Test func rejectsInvalidConfiguration() throws {
        for count in [Int.min, -1, 0, 119, 121, 239, 479, 959, 1_920, Int.max] {
            #expect(throws: CELTTransformError.invalidFrameSize) {
                try CELTTransform(frameSampleCount: count)
            }
        }
        for channels in [Int.min, -1, 0, 3, Int.max] {
            #expect(throws: CELTTransformError.invalidChannelCount) {
                try CELTTransform(frameSampleCount: 120, channelCount: channels)
            }
        }
        #expect(CELTTransform.overlapSampleCount == 120)
    }

    /// Exercises every supported length/layout with zero transforms and hostile value rejection.
    /// - Parameters:
    ///   - count: Every ordinary CELT frame length, in internal 48 kHz samples.
    ///   - channels: Independently processed mono/stereo interleaved layout.
    @Test(arguments: [120, 240, 480, 960], [1, 2])
    func silenceAndValidation(count: Int, channels: Int) throws {
        let plan = try CELTTransform(frameSampleCount: count, channelCount: channels)
        #expect(plan.frameSampleCount == count)
        #expect(plan.channelCount == channels)
        let pcm = Array(repeating: Float(0), count: (count + 120) * channels)
        let spectrum = Array(repeating: Float(0), count: count * channels)
        #expect(try plan.forward(pcm) == spectrum)
        #expect(try plan.inverse(spectrum) == pcm)
        for invalid in [[], Array(pcm.dropLast()), pcm + [0]] {
            #expect(throws: CELTTransformError.invalidSamples) { try plan.forward(invalid) }
        }
        for invalid in [[], Array(spectrum.dropLast()), spectrum + [0]] {
            #expect(throws: CELTTransformError.invalidCoefficients) { try plan.inverse(invalid) }
        }
        for value: Float in [.nan, .infinity, -.infinity, 1.0001, -1.0001] {
            var invalid = pcm
            invalid[invalid.count - 1] = value
            #expect(throws: CELTTransformError.invalidSamples) { try plan.forward(invalid) }
        }
        for value: Float in [.nan, .infinity, -.infinity, 4.0001, -4.0001] {
            var invalid = spectrum
            invalid[invalid.count - 1] = value
            #expect(throws: CELTTransformError.invalidCoefficients) { try plan.inverse(invalid) }
        }
        #expect(try plan.forward(pcm) == spectrum)
        #expect(try plan.inverse(spectrum) == pcm)
        #expect(try plan.forward(Array(repeating: -1, count: pcm.count)).allSatisfy(\.isFinite))
        #expect(try plan.forward(Array(repeating: 1, count: pcm.count)).allSatisfy(\.isFinite))
        #expect(try plan.inverse(Array(repeating: -4, count: spectrum.count)).allSatisfy(\.isFinite))
        #expect(try plan.inverse(Array(repeating: 4, count: spectrum.count)).allSatisfy(\.isFinite))
    }

    /// Checks every bin/sample against independently executed official libopus 1.6.1.
    /// Forward scaling/order and inverse zero-state overlap output are checked separately;
    /// no owned forward/inverse round trip is used as the interoperability oracle.
    @Test func officialFloatTransformFixtures() throws {
        for (count, encodedForward, encodedInverse) in CELTTransformOracleFixtures.values {
            let plan = try CELTTransform(frameSampleCount: count)
            let pcm = (0..<(count + 120)).map { Float(($0 * 37 + 11) % 101 - 50) / 64 }
            let spectrum = (0..<count).map { Float(($0 * 37 + 11) % 101 - 50) / 64 }
            let expectedForward = CELTTransformOracleFixtures.decode(encodedForward)
            let expectedInverse = CELTTransformOracleFixtures.decode(encodedInverse)
            #expect(expectedForward.count == count)
            #expect(expectedInverse.count == count)
            let actualForward = try plan.forward(pcm)
            let actualInverse = try plan.inverse(spectrum)
            for index in 0..<count {
                #expect(abs(actualForward[index] - expectedForward[index]) < 0.000_000_2)
                #expect(abs(actualInverse[index] - expectedInverse[index]) < 0.000_03)
            }
        }
        #expect(CELTTransformOracleFixtures.decode("invalid") == [])
        #expect(CELTTransformOracleFixtures.decode("AA==") == [])
    }

    /// Compares selected edge/interior bins with direct RFC cosine sums and exact windowing.
    /// - Parameter count: Every supported frame size; impulse positions cover zero-padding
    ///   boundaries, rising/falling window halves and the flat section when present.
    @Test(arguments: [120, 240, 480, 960])
    func directCosineDefinition(count: Int) throws {
        let plan = try CELTTransform(frameSampleCount: count)
        let padding = (count - 120) / 2
        for position in [0, 59, 60, 119, count, count + 119] {
            var pcm = Array(repeating: Float(0), count: count + 120)
            pcm[position] = 1
            let spectrum = try plan.forward(pcm)
            for bin in [0, 1, count / 2 - 1, count / 2, count - 2, count - 1] {
                let angle = .pi / Double(count) * (Double(position + padding) + 0.5 + Double(count) / 2)
                    * (Double(bin) + 0.5)
                let expected = window(at: position, count: count) * cos(angle) * 2 / Double(count)
                #expect(abs(Double(spectrum[bin]) - expected) < 0.000_000_01)
            }
        }
        let spectrum = (0..<count).map { Float(($0 * 37 + 11) % 101 - 50) / 64 }
        let pcm = try plan.inverse(spectrum)
        for position in [0, 59, 60, 119, count, count + 119] {
            var expected = 0.0
            for bin in 0..<count {
                let angle = .pi / Double(count) * (Double(position + padding) + 0.5 + Double(count) / 2)
                    * (Double(bin) + 0.5)
                expected += Double(spectrum[bin]) * cos(angle)
            }
            expected *= window(at: position, count: count)
            #expect(abs(Double(pcm[position]) - expected) < 0.000_002)
        }
    }

    /// Proves stereo coefficients and samples retain independent channel order and isolation.
    /// - Parameter count: Every supported ordinary CELT frame size.
    @Test(arguments: [120, 240, 480, 960])
    func stereoMatchesIndependentMono(count: Int) throws {
        let stereo = try CELTTransform(frameSampleCount: count, channelCount: 2)
        let mono = try CELTTransform(frameSampleCount: count)
        let left = (0..<(count + 120)).map { Float(($0 * 17) % 71 - 35) / 64 }
        let right = (0..<(count + 120)).map { Float(($0 * 31) % 61 - 30) / 64 }
        let pcm = zip(left, right).flatMap { [$0.0, $0.1] }
        let actual = try stereo.forward(pcm)
        let leftSpectrum = try mono.forward(left)
        let rightSpectrum = try mono.forward(right)
        #expect(actual == zip(leftSpectrum, rightSpectrum).flatMap { [$0.0, $0.1] })
        let leftInverse = try mono.inverse(leftSpectrum)
        let rightInverse = try mono.inverse(rightSpectrum)
        #expect(try stereo.inverse(actual) == zip(leftInverse, rightInverse).flatMap { [$0.0, $0.1] })
    }

    /// Reconstructs several asymmetric frames and a drained tail with exact documented delay.
    /// - Parameters:
    ///   - count: Every frame size, including the 120-sample full-overlap case.
    ///   - channels: Mono/stereo; each channel carries a different deterministic signal.
    @Test(arguments: [120, 240, 480, 960], [1, 2])
    func streamingRoundTripAndDrain(count: Int, channels: Int) throws {
        let plan = try CELTTransform(frameSampleCount: count, channelCount: channels)
        var stream = CELTTransformStream(transform: plan)
        #expect(stream.transform.frameSampleCount == count)
        let input = (0..<(count * channels * 4)).map { Float(($0 * 37 + 11) % 101 - 50) / 64 }
        var output: [Float] = []
        for offset in stride(from: 0, to: input.count, by: count * channels) {
            let spectrum = try stream.analyze(Array(input[offset..<(offset + count * channels)]))
            output += try stream.synthesize(spectrum)
        }
        let tail = try stream.analyze(Array(repeating: 0, count: count * channels))
        output += try stream.synthesize(tail)
        let expected = Array(repeating: Float(0), count: 120 * channels) + input
            + Array(repeating: Float(0), count: (count - 120) * channels)
        #expect(output.count == expected.count)
        #expect(zip(output, expected).allSatisfy { abs($0.0 - $0.1) < 0.000_000_3 })
    }

    /// Verifies failure atomicity, independently advancing histories, value copies and reset.
    /// Both histories are warmed before rejection so a dropped overlap cannot pass as silence.
    @Test func streamOwnershipAndFailureAtomicity() throws {
        let plan = try CELTTransform(frameSampleCount: 240, channelCount: 2)
        let first = (0..<480).map { Float(($0 * 17) % 71 - 35) / 64 }
        let next = (0..<480).map { Float(($0 * 31) % 61 - 30) / 64 }
        var stream = CELTTransformStream(transform: plan)
        let initialSpectrum = try stream.analyze(first)
        _ = try stream.synthesize(initialSpectrum)
        var copy = stream
        #expect(throws: CELTTransformError.invalidSamples) { try stream.analyze([]) }
        #expect(throws: CELTTransformError.invalidSamples) {
            try stream.analyze(Array(repeating: .nan, count: 480))
        }
        #expect(throws: CELTTransformError.invalidCoefficients) { try stream.synthesize([]) }
        #expect(throws: CELTTransformError.invalidCoefficients) {
            try stream.synthesize(Array(repeating: .infinity, count: 480))
        }
        let spectrum = try stream.analyze(next)
        #expect(try copy.analyze(next) == spectrum)
        #expect(try stream.synthesize(spectrum) == copy.synthesize(spectrum))
        let expected = try plan.forward(Array(first.suffix(240)) + next)
        #expect(spectrum == expected)
        var analysisOnly = copy
        var synthesisOnly = copy
        _ = try analysisOnly.analyze(first)
        #expect(try analysisOnly.synthesize(spectrum) == synthesisOnly.synthesize(spectrum))
        var untouchedAnalysis = copy
        _ = try copy.synthesize(spectrum)
        #expect(try copy.analyze(first) == untouchedAnalysis.analyze(first))
        stream.reset()
        var fresh = CELTTransformStream(transform: plan)
        #expect(try stream.analyze(first) == fresh.analyze(first))
        #expect(try stream.synthesize(initialSpectrum) == fresh.synthesize(initialSpectrum))
        stream.reset()
        stream.reset()
        #expect(try stream.analyze(Array(repeating: 0, count: 480)).allSatisfy { $0 == 0 })
        #expect(try stream.synthesize(Array(repeating: 0, count: 480)).allSatisfy { $0 == 0 })
    }

    /// Independently evaluates the specified compact low-overlap Vorbis window.
    /// - Parameters:
    ///   - position: Valid position in `0..<(count + 120)`.
    ///   - count: Supported transform frame length.
    /// - Returns: Rising or mirrored falling slope, or unity in the central flat part.
    private func window(at position: Int, count: Int) -> Double {
        let slope: Int
        if position < 120 { slope = position }
        else if position >= count { slope = count + 119 - position }
        else { return 1 }
        let inner = sin(0.5 * .pi * (Double(slope) + 0.5) / 120)
        return sin(0.5 * .pi * inner * inner)
    }
}
