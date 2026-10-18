import Foundation
import Testing
@testable import DiscordVoiceCodecs

/// Full independent native ordinary/mode-spliced/lost/FEC PCM and final-range evidence.
@Suite("Independent ordinary Opus mode and recovery fixtures")
struct OpusAudioOracleTests {
    /// Both fixed layouts match every native interval and exact final range after
    /// coded-channel changes, all modes/durations/bandwidths, both redundancy
    /// directions, direct switches, selected LBRR and short/repeated loss.
    /// Ordinary streams use 3e-6 absolute tolerance. Direct switches synthesize a
    /// preceding 5ms PLC fade; those streams, explicit loss and FEC inherit the
    /// existing scalar CELT PLC bound of .006*max(1,sequence peak)+.0001*abs(sample).
    /// The observed independent maxima are recorded separately by the verifier.
    @Test(arguments: opusAudioOracleFixtures.indices)
    func nativeModeAndRecoveryPCM(index: Int) throws {
        let fixture = try JSONDecoder().decode(Fixture.self,
            from: #require(Data(base64Encoded: opusAudioOracleFixtures[index])))
        var decoder = try OpusAudioDecoder(channelCount: fixture.channels)
        let peak = max(Float(1), fixture.operations.flatMap(\.pcm).map { abs($0) }.max() ?? 0)
        var sawRedundancy = false
        var sawNonzeroFECRange = false
        for (operationIndex, operation) in fixture.operations.enumerated() {
            let samples: [Float]
            switch operation.action {
            case "packet":
                let frames = try decoder.decode(Data(operation.bytes))
                samples = frames.flatMap(\.samples)
                sawRedundancy = sawRedundancy || frames.contains { $0.redundancyByteCount > 0 }
            case "loss":
                samples = try decoder.conceal(frameSampleCount: operation.count).samples
            case "fec":
                samples = try decoder.recover(Data(operation.bytes), frameSampleCount: operation.count).samples
                sawNonzeroFECRange = sawNonzeroFECRange || operation.range != 0
            default:
                Issue.record("Unexpected literal oracle action: \(operation.action)")
                continue
            }
            #expect(samples.count == operation.pcm.count, "operation \(operationIndex)")
            #expect(decoder.finalRange == operation.range, "operation \(operationIndex)")
            let withinTolerance = zip(samples, operation.pcm).allSatisfy { actual, expected in
                let tolerance: Float = fixture.variant == 0 ? 3e-6 : 0.006 * peak + 0.0001 * abs(expected)
                return actual.isFinite && expected.isFinite && abs(actual - expected) <= tolerance
            }
            #expect(withinTolerance, "operation \(operationIndex): \(operation.action)")
        }
        #expect(sawRedundancy)
        if fixture.variant == 2 { #expect(sawNonzeroFECRange) }
    }

    private struct Fixture: Decodable {
        let channels: Int
        let variant: Int
        let operations: [Operation]
    }
    private struct Operation: Decodable {
        let action: String
        let count: Int
        let bytes: [UInt8]
        let range: UInt32
        let pcm: [Float]
    }
}
