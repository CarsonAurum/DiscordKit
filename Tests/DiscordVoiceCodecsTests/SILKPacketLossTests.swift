import Foundation
import Testing
@testable import DiscordVoiceCodecs

@Suite("Scalar SILK PLC, comfort noise and in-band FEC")
struct SILKPacketLossTests {
    private struct Operation: Decodable { let mode: Int; let ms: Int; let packet: [UInt8] }
    private struct Input: Decodable {
        let rate: Int
        let channels: Int
        let generalized: Bool
        let operations: [Operation]
    }
    private struct Output: Decodable {
        let pcm: [Int16]
        let ranges: [UInt32]
        let bits: [Int]
        let redundancy: [[[Bool]]]
    }

    /// Every sample and entropy/header field must match independently built scalar
    /// libopus after normal audio, four consecutive loss durations, FEC with/without
    /// redundancy and normal recovery. Literal fixtures exercise voiced/unvoiced,
    /// inactive CNG training, mid-only stereo and mono/stereo API output conversion.
    @Test(arguments: silkLossOracleFixtures.indices)
    func independentScalarOperations(index: Int) throws {
        let fixture = silkLossOracleFixtures[index]
        let input = try JSONDecoder().decode(Input.self, from: Data(fixture.input.utf8))
        let expected = try JSONDecoder().decode([Output].self, from: Data(fixture.expected.utf8))
        var mono = try SILKMonoDecoder(sampleRate: input.rate)
        var general = try SILKStereoDecoder(sampleRate: input.rate, outputChannelCount: input.channels)
        let useMono = !input.generalized
        for (operation, reference) in zip(input.operations, expected) {
            var pcm: [Int16] = []
            var ranges: [UInt32] = []
            var bits: [Int] = []
            var flags: [[[Bool]]] = []
            if operation.mode == 1 {
                let lost = useMono ? try mono.conceal(durationMilliseconds: operation.ms)
                    : try general.conceal(durationMilliseconds: operation.ms)
                pcm = lost.pcm48k
                #expect(pcm.count == operation.ms * 48 * input.channels)
                #expect(lost.channelFrames.count == (operation.ms == 10 ? 1 : operation.ms / 20))
            } else {
                let packet = try OpusPacket(Data(operation.packet))
                let rate = [8_000, 12_000, 16_000][packet.configuration / 4]
                if useMono { try mono.updateSampleRate(rate) }
                else { try general.updateSampleRate(rate) }
                if operation.mode == 2 {
                    for range in packet.frameRanges {
                        let payload = packet.data.subdata(in: range)
                        let recovered = useMono ? try mono.recoverPayload(payload, durationMilliseconds: packet.frameSampleCount / 48)
                            : try general.recoverPayload(payload, durationMilliseconds: packet.frameSampleCount / 48, codedChannelCount: packet.channelCount)
                        pcm += recovered.pcm48k
                        ranges.append(recovered.finalRange)
                        bits.append(recovered.bitsUsed)
                        flags.append(recovered.redundancy)
                        for frame in recovered.channelFrames.indices {
                            for channel in recovered.redundancy.indices where recovered.redundancy[channel][frame] {
                                #expect(recovered.channelFrames[frame][channel] != nil)
                            }
                        }
                    }
                } else if useMono {
                    let decoded = try mono.decode(packet)
                    pcm = decoded.pcm48k
                    ranges = decoded.payloads.map(\.finalRange)
                    bits = decoded.payloads.map(\.bitsUsed)
                    flags = decoded.payloads.map { [$0.redundancy] }
                } else {
                    let decoded = try general.decode(packet)
                    pcm = decoded.pcm48k
                    ranges = decoded.payloads.map(\.finalRange)
                    bits = decoded.payloads.map(\.bitsUsed)
                    flags = decoded.payloads.map(\.redundancy)
                }
            }
            #expect(pcm == reference.pcm)
            #expect(ranges == reference.ranges)
            #expect(bits == reference.bits)
            #expect(flags == reference.redundancy)
        }
    }

    /// Initial scalar PLC has no excitation and must yield exact silence for every
    /// rate, duration and output layout. Long repeated loss remains deterministic;
    /// reset discards random/filter/CNG state, and value copies own independent state.
    @Test
    func initialLossResetCopiesAndBounds() throws {
        for rate in [8_000, 12_000, 16_000] {
            for channels in [1, 2] {
                var decoder = try SILKStereoDecoder(sampleRate: rate, outputChannelCount: channels)
                #expect(decoder.channelCount == channels)
                for duration in [10, 20, 40, 60] {
                    let result = try decoder.conceal(durationMilliseconds: duration)
                    #expect(result.pcm48k.count == duration * 48 * channels)
                    #expect(result.pcm48k.allSatisfy { $0 == 0 })
                }
                var copied = decoder
                for _ in 0..<20 { #expect(try decoder.conceal() == copied.conceal()) }
                decoder.reset()
                let reset = try decoder.conceal()
                #expect(reset.pcm48k.allSatisfy { $0 == 0 })
                var mono = try SILKMonoDecoder(sampleRate: rate)
                #expect(try mono.conceal(durationMilliseconds: 60).pcm48k == Array(repeating: 0, count: 2_880))
            }
        }
    }

    /// Invalid loss/FEC durations, byte bounds and channel layouts cannot advance
    /// synthesis, random or resampler state. Subsequent ordinary PCM proves rollback.
    @Test
    func lossAndFECAdmissionIsAtomic() throws {
        #expect(throws: SILKMonoDecoderError.unsupportedChannels) {
            try SILKStereoDecoder(sampleRate: 8_000, outputChannelCount: 0)
        }
        #expect(throws: SILKMonoDecoderError.unsupportedChannels) {
            try SILKStereoDecoder(sampleRate: 8_000, outputChannelCount: 3)
        }
        let fixture = try JSONDecoder().decode(Input.self, from: Data(silkLossOracleFixtures[0].input.utf8))
        let bytes = try #require(fixture.operations.first { !$0.packet.isEmpty }?.packet)
        let packet = try OpusPacket(Data(bytes))
        let payload = packet.data.subdata(in: packet.frameRanges[0])
        var mono = try SILKMonoDecoder(sampleRate: fixture.rate)
        var stereo = try SILKStereoDecoder(sampleRate: fixture.rate)
        var monoCopy = mono
        var stereoCopy = stereo
        for duration in [0, 5, 15, 80, 120] {
            #expect(throws: SILKMonoDecoderError.invalidPayloadDuration) { try mono.conceal(durationMilliseconds: duration) }
            #expect(throws: SILKMonoDecoderError.invalidPayloadDuration) { try stereo.conceal(durationMilliseconds: duration) }
            #expect(throws: SILKMonoDecoderError.invalidPayloadDuration) { try mono.recoverPayload(payload, durationMilliseconds: duration) }
            #expect(throws: SILKMonoDecoderError.invalidPayloadDuration) { try stereo.recoverPayload(payload, durationMilliseconds: duration) }
        }
        for bytes in [Data(), Data(repeating: 255, count: 1_276)] {
            #expect(throws: SILKMonoDecoderError.invalidPayloadSize) { try mono.recoverPayload(bytes, durationMilliseconds: 20) }
            #expect(throws: SILKMonoDecoderError.invalidPayloadSize) { try stereo.recoverPayload(bytes, durationMilliseconds: 20) }
        }
        for channels in [0, 3] {
            #expect(throws: SILKMonoDecoderError.unsupportedChannels) {
                try stereo.recoverPayload(payload, durationMilliseconds: 20, codedChannelCount: channels)
            }
        }
        #expect(try mono.decode(packet) == monoCopy.decode(packet))
        #expect(try stereo.decode(packet) == stereoCopy.decode(packet))
    }

    /// Missing LBRR must conceal the requested duration instead of producing empty
    /// output. Direct channel concealment also preserves its configured duration.
    @Test
    func absentRedundancyUsesScalarConcealment() throws {
        let input = try JSONDecoder().decode(Input.self, from: Data(silkLossOracleFixtures[0].input.utf8))
        let bytes = try #require(input.operations.first { !$0.packet.isEmpty }?.packet)
        let packet = try OpusPacket(Data(bytes))
        let payload = packet.data.subdata(in: packet.frameRanges[0])
        var fec = try SILKMonoDecoder(sampleRate: input.rate)
        var plc = fec
        let recovered = try fec.recoverPayload(payload, durationMilliseconds: packet.frameSampleCount / 48)
        #expect(recovered.redundancy.allSatisfy { !$0.contains(true) })
        #expect(recovered.channelFrames.allSatisfy { $0.allSatisfy { $0 == nil } })
        #expect(try recovered.pcm48k == plc.conceal(durationMilliseconds: packet.frameSampleCount / 48).pcm48k)
        var channel = try SILKFrameDecoder(sampleRate: 16_000, frameDurationMilliseconds: 10)
        #expect(try channel.concealFrame().count == 160)
        try channel.updateFrameDuration(milliseconds: 20)
        #expect(try channel.concealFrame(resetGainIndex: false).count == 320)
        channel.reset()
        #expect(try channel.concealFrame().allSatisfy { $0 == 0 })
    }
}
