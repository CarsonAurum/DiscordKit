import Foundation
import Testing
@testable import DiscordVoiceCodecs

@Suite("Owned ordinary SILK parameter encoding")
struct SILKFrameParameterEncoderTests {
    private struct Input: Decodable {
        let rate: Int
        let milliseconds: Int
        let vad: Bool
        let lbrr: Bool
        let coding: Int
        let previousGain: Int
        let previousType: Int
        let previousLag: Int16
        let bytes: [UInt8]
    }

    /// Re-encodes all independent libopus index/pulse fixtures byte for byte, including
    /// inactive/unvoiced/voiced categories, conditional gain/pitch and NLSF extensions.
    /// Decoder reconstruction fields are intentionally not a second encoding input.
    @Test(arguments: SILKParameterOracleFixtures.all)
    func reproducesOfficialBytes(_ fixture: SILKParameterOracleFixture) throws {
        let input = try JSONDecoder().decode(Input.self, from: Data(fixture.input.utf8))
        var channel = try SILKFrameParameterDecoder(
            sampleRate: input.rate, frameDurationMilliseconds: input.milliseconds,
            previousGainIndex: input.previousGain,
            previousSignalType: SILKSignalType(rawValue: input.previousType)!,
            previousPitchLagIndex: input.previousLag
        )
        var decoder = try OpusRangeDecoder(frame: Data(input.bytes))
        let parameters = try channel.decode(
            from: &decoder, voiceActivity: input.vad, lowBitrateRedundancy: input.lbrr,
            coding: SILKParameterCoding(rawValue: input.coding)!
        )
        let parameterRange = decoder.finalRange
        let pulses = try SILKPulseCoding.decode(
            from: &decoder, sampleCount: input.rate * input.milliseconds / 1_000,
            signalType: parameters.signalType, quantizationOffset: parameters.quantizationOffset
        )
        var encoder = try OpusRangeEncoder(frameByteCount: input.bytes.count)
        try SILKFrameParameterEncoding.encode(
            parameters, to: &encoder, sampleRate: input.rate,
            frameDurationMilliseconds: input.milliseconds,
            coding: SILKParameterCoding(rawValue: input.coding)!,
            previousSignalType: SILKSignalType(rawValue: input.previousType)!,
            previousPitchLagIndex: input.previousLag
        )
        #expect(encoder.finalRange == parameterRange)
        try SILKPulseCoding.encode(
            pulses.signedPulses, to: &encoder, signalType: parameters.signalType,
            quantizationOffset: parameters.quantizationOffset, rateLevel: pulses.rateLevel
        )
        #expect(encoder.finalRange == decoder.finalRange)
        #expect(try encoder.finalize() == Data(input.bytes))
    }

    /// Covers independent voiced LTP scaling and both conditional lag branches at all
    /// six formats. Relative lag boundaries -8/+11 and out-of-range absolute fallback
    /// round trip through separately initialized entropy decoders exactly.
    @Test
    func voicedPitchContexts() throws {
        for rate in [8_000, 12_000, 16_000] {
            for duration in [10, 20] {
                for coding in SILKParameterCoding.allCases {
                    for previousLag in [Int16(29), 40, 48, 49, 100] {
                        let parameters = makeParameters(rate: rate, duration: duration, voiced: true)
                        var encoder = try OpusRangeEncoder(frameByteCount: 128)
                        try SILKFrameParameterEncoding.encode(
                            parameters, to: &encoder, sampleRate: rate,
                            frameDurationMilliseconds: duration, coding: coding,
                            previousSignalType: .voiced, previousPitchLagIndex: previousLag
                        )
                        var decoder = try OpusRangeDecoder(frame: encoder.finalize())
                        var channel = try SILKFrameParameterDecoder(
                            sampleRate: rate, frameDurationMilliseconds: duration,
                            previousSignalType: .voiced, previousPitchLagIndex: previousLag
                        )
                        let decoded = try channel.decode(from: &decoder, voiceActivity: true, coding: coding)
                        #expect(decoded.pitchLagIndex == parameters.pitchLagIndex)
                        #expect(decoded.pitchContourIndex == parameters.pitchContourIndex)
                        #expect(decoded.periodicityIndex == parameters.periodicityIndex)
                        #expect(decoded.longTermGainIndices == parameters.longTermGainIndices)
                        #expect(decoded.longTermScaleIndex == parameters.longTermScaleIndex)
                        #expect(decoded.normalizedLSFResidualIndices == parameters.normalizedLSFResidualIndices)
                        #expect(decoded.seed == parameters.seed)
                        #expect(encoder.finalRange == decoder.finalRange)
                    }
                }
            }
        }
    }

    /// Exercises terminal NLSF extension symbols, maximum absolute/delta gains, every
    /// rate's largest absolute lag, final contour/LTP entries, all independent scales
    /// and ten/twenty-millisecond interpolation boundaries without native runtime work.
    @Test
    func extremeLegalIndices() throws {
        for rate in [8_000, 12_000, 16_000] {
            for duration in [10, 20] {
                for coding in SILKParameterCoding.allCases {
                    for residual in [-10, 10] {
                        for scale in (coding == .independent ? [0, 1, 2] : [0]) {
                            let contourCount = rate == 8_000 ? (duration == 10 ? 3 : 11) : (duration == 10 ? 12 : 34)
                            let parameters = makeParameters(
                                rate: rate, duration: duration, voiced: true,
                                gains: [coding == .conditional ? 40 : 63] + Array(repeating: 40, count: duration / 5 - 1),
                                stage: 31, residuals: Array(repeating: residual, count: rate == 16_000 ? 16 : 10),
                                interpolation: duration == 10 ? 4 : 0, seed: 3,
                                lag: Int16(32 * (rate / 2_000) - 1), contour: contourCount - 1,
                                periodicity: 2, longTermGains: Array(repeating: 31, count: duration / 5), scale: scale
                            )
                            var encoder = try OpusRangeEncoder(frameByteCount: 128)
                            try SILKFrameParameterEncoding.encode(
                                parameters, to: &encoder, sampleRate: rate,
                                frameDurationMilliseconds: duration, coding: coding,
                                previousSignalType: .unvoiced
                            )
                            var entropy = try OpusRangeDecoder(frame: encoder.finalize())
                            var decoder = try SILKFrameParameterDecoder(
                                sampleRate: rate, frameDurationMilliseconds: duration,
                                previousSignalType: .unvoiced
                            )
                            let output = try decoder.decode(from: &entropy, voiceActivity: true, coding: coding)
                            #expect(output.gainIndices == parameters.gainIndices)
                            #expect(output.normalizedLSFResidualIndices == parameters.normalizedLSFResidualIndices)
                            #expect(output.normalizedLSFCodebookIndex == 31)
                            #expect(output.interpolationQ2 == parameters.interpolationQ2)
                            #expect(output.pitchLagIndex == parameters.pitchLagIndex)
                            #expect(output.pitchContourIndex == parameters.pitchContourIndex)
                            #expect(output.longTermGainIndices == parameters.longTermGainIndices)
                            #expect(output.longTermScaleIndex == scale)
                            #expect(output.seed == 3)
                            #expect(entropy.finalRange == encoder.finalRange)
                        }
                    }
                }
            }
        }
    }

    /// Rejects malformed dimensions, index boundaries, frame categories and byte/operation
    /// exhaustion atomically. A caller may retry using the unchanged original entropy state.
    @Test
    func validationAndAtomicFailures() throws {
        let invalid: [(SILKFrameParameters, SILKFrameParameterEncodingError)] = [
            (makeParameters(gains: []), .invalidGainIndices),
            (makeParameters(gains: [64, 4]), .invalidGainIndices),
            (makeParameters(gains: [0, 41]), .invalidGainIndices),
            (makeParameters(stage: 32), .invalidNormalizedLSFIndices),
            (makeParameters(residuals: []), .invalidNormalizedLSFIndices),
            (makeParameters(residuals: Array(repeating: 11, count: 10)), .invalidNormalizedLSFIndices),
            (makeParameters(interpolation: 3), .invalidInterpolation),
            (makeParameters(seed: 4), .invalidSeed),
            (makeParameters(voiced: true, lag: -1), .invalidPitchIndices),
            (makeParameters(voiced: true, contour: 3), .invalidPitchIndices),
            (makeParameters(voiced: true, periodicity: 3), .invalidLongTermIndices),
            (makeParameters(voiced: true, longTermGains: [8, 0]), .invalidLongTermIndices),
            (makeParameters(voiced: true, scale: 3), .invalidLongTermIndices)
        ]
        for (parameters, error) in invalid {
            var encoder = try OpusRangeEncoder(frameByteCount: 128)
            try encoder.encodeBit(true, logProbability: 1)
            let range = encoder.finalRange
            #expect(throws: error) {
                try SILKFrameParameterEncoding.encode(parameters, to: &encoder, sampleRate: 8_000, frameDurationMilliseconds: 10)
            }
            #expect(encoder.operationCount == 1)
            #expect(encoder.finalRange == range)
        }
        for bytes in [0, 1] {
            var encoder = try OpusRangeEncoder(frameByteCount: bytes)
            #expect(throws: OpusRangeCodingError.frameBudgetExceeded) {
                try SILKFrameParameterEncoding.encode(makeParameters(), to: &encoder, sampleRate: 8_000, frameDurationMilliseconds: 10)
            }
            #expect(encoder.operationCount == 0)
        }
        var limited = try OpusRangeEncoder(frameByteCount: 128, maximumOperations: 1)
        #expect(throws: OpusRangeCodingError.operationLimitExceeded) {
            try SILKFrameParameterEncoding.encode(makeParameters(), to: &limited, sampleRate: 8_000, frameDurationMilliseconds: 10)
        }
        #expect(limited.operationCount == 0)
        #expect(throws: SILKFrameParameterError.invalidSampleRate) {
            try SILKFrameParameterEncoding.encode(makeParameters(), to: &limited, sampleRate: 48_000, frameDurationMilliseconds: 10)
        }
        #expect(throws: SILKFrameParameterError.invalidFrameDuration) {
            try SILKFrameParameterEncoding.encode(makeParameters(), to: &limited, sampleRate: 8_000, frameDurationMilliseconds: 40)
        }
    }

    /// Constructs deterministic test indices; optional overrides exercise invalid syntax.
    /// - Parameters:
    ///   - rate: Internal rate selecting ten/sixteen spectral residuals; default 8 kHz.
    ///   - duration: Ten/twenty milliseconds selecting two/four gains; default ten.
    ///   - voiced: Whether valid pitch/LTP syntax is populated; defaults unvoiced.
    ///   - gains: Optional absolute/delta index override, including malformed dimensions.
    ///   - stage: First-stage spectral vector index, default zero.
    ///   - residuals: Optional spectral residual override; defaults all zero.
    ///   - interpolation: Quarter interpolation symbol, default four.
    ///   - seed: Two-bit seed, default zero; invalid values deliberately remain available.
    ///   - lag: Voiced primary pitch index, default forty.
    ///   - contour: Voiced contour index, default zero.
    ///   - periodicity: Voiced LTP codebook category, default zero.
    ///   - longTermGains: Optional LTP index override, default one zero per subframe.
    ///   - scale: Voiced scale symbol, default zero for every coding mode.
    /// - Returns: Indices with empty unencoded reconstruction fields, proving that
    ///   encoding depends only on validated syntax and supplied rate/context.
    private func makeParameters(
        rate: Int = 8_000, duration: Int = 10, voiced: Bool = false,
        gains: [Int]? = nil, stage: Int = 0, residuals: [Int]? = nil,
        interpolation: Int = 4, seed: UInt8 = 0, lag: Int16 = 40,
        contour: Int = 0, periodicity: Int = 0, longTermGains: [Int]? = nil, scale: Int = 0
    ) -> SILKFrameParameters {
        SILKFrameParameters(
            signalType: voiced ? .voiced : .unvoiced, quantizationOffset: .low,
            gainIndices: gains ?? [32] + Array(repeating: 4, count: duration / 5 - 1),
            normalizedLSFCodebookIndex: stage,
            normalizedLSFResidualIndices: residuals ?? Array(repeating: 0, count: rate == 16_000 ? 16 : 10),
            interpolationQ2: interpolation, pitchLagIndex: voiced ? lag : nil,
            pitchContourIndex: voiced ? contour : nil, periodicityIndex: voiced ? periodicity : nil,
            longTermGainIndices: voiced ? (longTermGains ?? Array(repeating: 0, count: duration / 5)) : [],
            longTermScaleIndex: voiced ? scale : nil, seed: seed, gainsQ16: [],
            normalizedLSFsQ15: [], pitchLags: [], longTermCoefficientsQ7: [], longTermScaleQ14: 0
        )
    }
}
