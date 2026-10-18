import Foundation
import Testing
@testable import DiscordVoiceCodecs

/// Real owned hybrid packets with independent native selected-LBRR recovery PCM.
@Suite("Owned hybrid FEC independent decoding")
struct OpusHybridFECOracleTests {
    /// Both channels, bandwidths and durations preserve exact native ranges and
    /// complete PCM through missing audio recovered from following owned packets.
    /// Each fixture withholds two packets, selects their actual SILK LBRR, then
    /// decodes the following ordinary audio without consuming that audio twice.
    /// High-band noise concealment also matches within the tighter 3e-6 bound.
    @Test(arguments: opusHybridFECOracleFixtures.indices)
    func independentOwnedLBRRRecovery(index: Int) throws {
        let fixture = try JSONDecoder().decode(Fixture.self,
            from: #require(Data(base64Encoded: opusHybridFECOracleFixtures[index])))
        var decoder = try OpusAudioDecoder(channelCount: fixture.channels)
        var selected = 0
        for (operationIndex, operation) in fixture.operations.enumerated() {
            let bytes = Data(operation.bytes)
            let packet = try OpusPacket(bytes)
            #expect(packet.mode == .hybrid && packet.channelCount == fixture.channels)
            #expect(packet.frameSampleCount == fixture.samples)
            #expect(packet.bandwidth == (fixture.bandwidth == 1105 ? .fullband : .superwideband))
            let pcm: [Float]
            if operation.fec {
                #expect(operation.selectedLBRR)
                selected += 1
                pcm = try decoder.recover(bytes, frameSampleCount: operation.samples).samples
            } else {
                #expect(!operation.selectedLBRR)
                pcm = try decoder.decode(bytes).flatMap(\.samples)
            }
            #expect(decoder.finalRange == operation.range, "operation \(operationIndex)")
            #expect(decoder.lastPacketDuration == fixture.samples)
            #expect(pcm.count == operation.pcm.count && pcm.count == fixture.samples * fixture.channels)
            let matches = zip(pcm, operation.pcm).allSatisfy { actual, expected in
                actual.isFinite && expected.isFinite && abs(actual - expected) <= 3e-6
            }
            #expect(matches, "operation \(operationIndex), FEC \(operation.fec)")
        }
        #expect(selected == 2)
    }

    private struct Fixture: Decodable {
        let channels: Int
        let bandwidth: Int
        let samples: Int
        let operations: [Operation]
    }
    private struct Operation: Decodable {
        let bytes: [UInt8]
        let fec: Bool
        let samples: Int
        let selectedLBRR: Bool
        let pcm: [Float]
        let range: UInt32
    }
}
