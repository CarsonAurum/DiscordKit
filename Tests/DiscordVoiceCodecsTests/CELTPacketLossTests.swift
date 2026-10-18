import Foundation
import Testing
@testable import DiscordVoiceCodecs

/// Actual independently compressed packets exercise complete energy/pitch/overlap recovery state.
@Suite("CELT compressed packet loss and recovery")
struct CELTPacketLossTests {
    /// Compares full independent PCM and every final range from real reference-encoded
    /// streams whose missing packets were encoded then withheld from both decoders.
    /// Includes mono/stereo, short/long loss bursts, predictive recovery, changing
    /// frame durations and all ordinary bandwidths. The 0.002 absolute plus 0.0001
    /// relative PCM allowance is numerical interoperability rather than conformance.
    @Test func independentCompressedLossAndPredictiveRecovery() throws {
        let records = try JSONDecoder().decode([Record].self,
            from: Data(CELTPacketLossOracleFixtures.json.utf8))
        #expect(records.count == 6)
        var losses = 0
        var received = 0
        var totalSamples = 0
        for record in records {
            var decoder = try CELTPacketDecoder(channelCount: record.channels)
            var endBand = 21
            for frame in record.frames {
                let actual: [Float]
                let finalRange: UInt32
                if frame.lost {
                    let concealed = try decoder.conceal(frameSampleCount: frame.n, endBand: endBand)
                    actual = concealed.samples
                    finalRange = 0
                    losses += 1
                } else {
                    let frames = try decoder.decode(Data(frame.packet))
                    #expect(frames.count == 1)
                    actual = frames.flatMap(\.samples)
                    finalRange = try #require(frames.first).finalRange
                    endBand = frame.end
                    received += 1
                }
                #expect(finalRange == frame.range)
                #expect(actual.count == frame.n * record.channels)
                let reference = try floatVector(frame.pcm)
                #expect(actual.count == reference.count)
                for (value, expected) in zip(actual, reference) {
                    #expect(value.isFinite && abs(value - expected) <= 0.002 + 0.0001 * abs(expected))
                }
                totalSamples += actual.count
            }
        }
        #expect(losses > 100 && received > 40 && totalSamples > 50_000)
    }

    /// A caller requesting a longer missing interval gets the ordinary Opus segmentation
    /// policy based on the last received TOC, preserving exact raw-frame loss histories.
    /// Duration changes then replace that limit; reset restores the 2.5-ms startup limit.
    @Test func missingDurationUsesLastReceivedTOC() throws {
        for priorSize in [120, 240, 480, 960] {
            var encoder = try CELTPacketEncoder(frameSampleCount: priorSize)
            let packet = try encoder.encode((0..<priorSize).map { Float(sin(Double($0) * 0.07)) * 0.3 },
                packetByteCount: 81)
            var decoder = try CELTPacketDecoder()
            var raw = try CELTFrameDecoder()
            _ = try decoder.decode(packet)
            _ = try raw.decode(Data(packet.dropFirst()), frameSampleCount: priorSize)
            var expected: [Float] = []
            for _ in 0..<(960 / priorSize) {
                expected += try raw.conceal(frameSampleCount: priorSize).samples
            }
            #expect(try decoder.conceal(frameSampleCount: 960).samples == expected)
            decoder.reset()
            var fresh = try CELTPacketDecoder()
            #expect(try decoder.conceal(frameSampleCount: 960) == fresh.conceal(frameSampleCount: 960))
        }
    }

    /// A short packet updates the declared duration but retains the last actually decoded
    /// bandwidth. The default explicit loss band also follows that received history.
    @Test func shortPayloadPreservesReceivedBandwidth() throws {
        var encoder = try CELTPacketEncoder(frameSampleCount: 240, bandwidth: .wideband)
        let packet = try encoder.encode((0..<240).map { Float(sin(Double($0) * 0.09)) * 0.2 },
            packetByteCount: 81)
        var decoder = try CELTPacketDecoder()
        var raw = try CELTFrameDecoder()
        _ = try decoder.decode(packet)
        _ = try raw.decode(Data(packet.dropFirst()), frameSampleCount: 240, endBand: 17)
        // The new TOC labels fullband/2.5ms, but there is no compressed bandwidth update.
        let short = try decoder.decode(Data([0xe0]))
        #expect(short.count == 1)
        #expect(short[0].samples == (try raw.conceal(frameSampleCount: 120, endBand: 17).samples))
        let next = try decoder.conceal(frameSampleCount: 240)
        let first = try raw.conceal(frameSampleCount: 120, endBand: 17)
        let second = try raw.conceal(frameSampleCount: 120, endBand: 17)
        #expect(next.samples == first.samples + second.samples)
        #expect(next.bandLogEnergies == second.bandLogEnergies && next.seed == second.seed)
    }

    /// Decodes complete little-endian float32 evidence without alignment assumptions.
    /// - Parameter encoded: Base64-encoded whole IEEE-754 sample words.
    /// - Returns: Every independent sample in reference order.
    /// - Throws: A Swift Testing requirement failure for malformed fixture bytes.
    private func floatVector(_ encoded: String) throws -> [Float] {
        let data = try #require(Data(base64Encoded: encoded))
        #expect(data.count.isMultiple(of: 4))
        return stride(from: 0, to: data.count, by: 4).map { offset in
            let bits = UInt32(data[offset]) | UInt32(data[offset + 1]) << 8
                | UInt32(data[offset + 2]) << 16 | UInt32(data[offset + 3]) << 24
            return Float(bitPattern: bits)
        }
    }

    private struct Record: Decodable {
        let channels: Int
        let frames: [Frame]
    }
    private struct Frame: Decodable {
        let n: Int, end: Int
        let lost: Bool
        let packet: [UInt8]
        let range: UInt32
        let pcm: String
    }
}
