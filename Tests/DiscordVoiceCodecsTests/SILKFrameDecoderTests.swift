import Foundation
import Testing
@testable import DiscordVoiceCodecs

@Suite("Ordinary compressed SILK channel PCM decoding")
struct SILKFrameDecoderTests {
    private struct InputFrame: Decodable {
        let vad: Bool
        let lbrr: Bool
        let coding: Int
        let bytes: [UInt8]
    }
    private struct Input: Decodable {
        let rate: Int
        let milliseconds: Int
        let frames: [InputFrame]
    }
    private struct Reference: Decodable {
        let pcm: [Int16]
        let lpcState: [Int32]
        let outputHistory: [Int16]
        let nlsfs: [Int16]
        let gain: Int32
        let range: UInt32
        let bits: Int
        let fractional: Int
    }

    /// Matches every PCM sample, recursive state and entropy state against complete
    /// independent scalar decode_parameters/decode_core streams. Covers NB/MB/WB,
    /// 10/20ms, voiced/unvoiced/inactive transitions, gains, quarter interpolation,
    /// mediumband padding, rewhitening and saturation-sensitive persistent history.
    @Test(arguments: SILKFrameOracleFixtures.all)
    func officialScalarPCMStreams(_ fixture: SILKFrameOracleFixture) throws {
        let input = try JSONDecoder().decode(Input.self, from: Data(fixture.input.utf8))
        let expected = try JSONDecoder().decode([Reference].self, from: Data(fixture.expected.utf8))
        #expect(input.frames.count == expected.count)
        var channel = try SILKFrameDecoder(sampleRate: input.rate, frameDurationMilliseconds: input.milliseconds)
        for (index, frame) in input.frames.enumerated() {
            var entropy = try OpusRangeDecoder(frame: Data(frame.bytes))
            let decoded = try channel.decode(from: &entropy, voiceActivity: frame.vad, lowBitrateRedundancy: frame.lbrr, coding: SILKParameterCoding(rawValue: frame.coding)!)
            #expect(decoded.pcm == expected[index].pcm)
            #expect(channel.shortTermHistoryQ14 == expected[index].lpcState)
            #expect(channel.outputHistory == expected[index].outputHistory)
            #expect(channel.previousNormalizedLSFsQ15 == expected[index].nlsfs)
            #expect(channel.previousGainQ16 == expected[index].gain)
            #expect(entropy.finalRange == expected[index].range)
            #expect(entropy.bitsUsed == expected[index].bits)
            #expect(entropy.fractionalBitsUsed == expected[index].fractional)
            #expect(decoded.pcm.count == input.rate * input.milliseconds / 1_000)
            #expect(decoded.pulses.signedPulses.count == decoded.pcm.count)
            #expect(!channel.isFirstFrameAfterReset)
        }
    }

    /// Enforces bounded construction and reset ownership across all six formats;
    /// invalid rates/durations must fail before allocating synthesis state.
    @Test func constructionBoundsAndIdempotentReset() throws {
        for rate in [8_000, 12_000, 16_000] {
            for duration in [10, 20] {
                var channel = try SILKFrameDecoder(sampleRate: rate, frameDurationMilliseconds: duration)
                #expect(channel.sampleRate == rate)
                #expect(channel.frameDurationMilliseconds == duration)
                #expect(channel.outputHistory.count == rate / 50)
                #expect(channel.outputHistory.allSatisfy { $0 == 0 })
                #expect(channel.shortTermHistoryQ14 == Array(repeating: 0, count: 16))
                #expect(channel.previousNormalizedLSFsQ15.count == (rate == 16_000 ? 16 : 10))
                #expect(channel.previousGainQ16 == 65_536)
                #expect(channel.isFirstFrameAfterReset)
                channel.reset()
                channel.reset()
                #expect(channel.outputHistory.count == rate / 50)
                #expect(channel.isFirstFrameAfterReset)
            }
        }
        #expect(throws: SILKFrameParameterError.invalidSampleRate) { try SILKFrameDecoder(sampleRate: 48_000, frameDurationMilliseconds: 20) }
        #expect(throws: SILKFrameParameterError.invalidFrameDuration) { try SILKFrameDecoder(sampleRate: 16_000, frameDurationMilliseconds: 60) }
    }

    /// A reset after actual audio must reproduce zero-state decoding exactly, while
    /// value copies retain independent recursive/entropy ownership across continuations.
    @Test func resetReproducesFirstFrameAndCopiesAreIndependent() throws {
        let input = try JSONDecoder().decode(Input.self, from: Data(SILKFrameOracleFixtures.all[5].input.utf8))
        let frame = try #require(input.frames.first)
        var channel = try SILKFrameDecoder(sampleRate: input.rate, frameDurationMilliseconds: input.milliseconds)
        var firstEntropy = try OpusRangeDecoder(frame: Data(frame.bytes))
        let first = try channel.decode(from: &firstEntropy, voiceActivity: frame.vad, coding: SILKParameterCoding(rawValue: frame.coding)!)
        var copy = channel
        let history = copy.outputHistory
        var nextEntropy = try OpusRangeDecoder(frame: Data(input.frames[1].bytes))
        _ = try channel.decode(from: &nextEntropy, voiceActivity: input.frames[1].vad, coding: SILKParameterCoding(rawValue: input.frames[1].coding)!)
        #expect(copy.outputHistory == history)
        copy.reset()
        #expect(copy.outputHistory.allSatisfy { $0 == 0 })
        #expect(copy.shortTermHistoryQ14.allSatisfy { $0 == 0 })
        #expect(copy.previousNormalizedLSFsQ15.allSatisfy { $0 == 0 })
        #expect(copy.previousGainQ16 == 65_536)
        var resetEntropy = try OpusRangeDecoder(frame: Data(frame.bytes))
        #expect(try copy.decode(from: &resetEntropy, voiceActivity: frame.vad, coding: SILKParameterCoding(rawValue: frame.coding)!) == first)
        #expect(resetEntropy.finalRange == firstEntropy.finalRange)
    }

    /// Entropy admission failure after prior successful audio must preserve gain,
    /// LPC/LSF/output state and every caller entropy field rather than half-advance.
    @Test func failedDecodePreservesExistingAudioHistory() throws {
        let input = try JSONDecoder().decode(Input.self, from: Data(SILKFrameOracleFixtures.all[3].input.utf8))
        let first = try #require(input.frames.first)
        var channel = try SILKFrameDecoder(sampleRate: input.rate, frameDurationMilliseconds: input.milliseconds)
        var entropy = try OpusRangeDecoder(frame: Data(first.bytes))
        _ = try channel.decode(from: &entropy, voiceActivity: first.vad, coding: SILKParameterCoding(rawValue: first.coding)!)
        let gain = channel.previousGainQ16
        let lpc = channel.shortTermHistoryQ14
        let output = channel.outputHistory
        let nlsfs = channel.previousNormalizedLSFsQ15
        let next = input.frames[1]
        for limit in [1, 4, 20] {
            var failing = try OpusRangeDecoder(frame: Data(next.bytes), maximumOperations: limit)
            let range = failing.finalRange
            #expect(throws: OpusRangeCodingError.operationLimitExceeded) {
                try channel.decode(from: &failing, voiceActivity: next.vad, coding: SILKParameterCoding(rawValue: next.coding)!)
            }
            #expect(channel.previousGainQ16 == gain)
            #expect(channel.shortTermHistoryQ14 == lpc)
            #expect(channel.outputHistory == output)
            #expect(channel.previousNormalizedLSFsQ15 == nlsfs)
            #expect(!channel.isFirstFrameAfterReset)
            #expect(failing.finalRange == range)
            #expect(failing.operationCount == 0)
        }
    }
}
