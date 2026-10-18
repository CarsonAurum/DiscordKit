import Foundation
import Testing
@testable import DiscordVoiceCodecs

@Suite("Adaptive stereo SILK decoding and bandwidth transitions")
struct SILKStereoDecoderTests {
    private struct Input: Decodable { let rate: Int; let packets: [[UInt8]] }
    private struct Output: Decodable {
        let pcm: [Int16]
        let ranges: [UInt32]
        let bits: [Int]
        let activity: [[[Bool]]]
        let redundancy: [[[Bool]]]
    }

    /// Compares every sample, header flag and entropy result to independent libopus
    /// SILK API decoding. Fixtures cover all rates/durations, LBRR syntax skipping,
    /// all directed bandwidth transitions, adaptive mono/stereo and mid-only reentry.
    @Test(arguments: silkStereoOracleFixtures.indices)
    func independentPacketPCM(index: Int) throws {
        let fixture = silkStereoOracleFixtures[index]
        let input = try JSONDecoder().decode(Input.self, from: Data(fixture.input.utf8))
        let expected = try JSONDecoder().decode([Output].self, from: Data(fixture.expected.utf8))
        var decoder = try SILKStereoDecoder(sampleRate: input.rate)
        var observedOmittedSide = false
        for (bytes, reference) in zip(input.packets, expected) {
            let packet = try OpusPacket(Data(bytes))
            let output = try decoder.decode(packet)
            #expect(output.pcm48k == reference.pcm)
            #expect(output.pcm48k.count == packet.sampleCount * 2)
            #expect(output.payloads.map(\.finalRange) == reference.ranges)
            #expect(output.payloads.map(\.bitsUsed) == reference.bits)
            #expect(output.payloads.map(\.voiceActivity) == reference.activity)
            #expect(output.payloads.map(\.redundancy) == reference.redundancy)
            #expect(decoder.sampleRate == [8_000, 12_000, 16_000][packet.configuration / 4])
            for payload in output.payloads {
                #expect(payload.midFrames.count == payload.midOnly.count)
                #expect(payload.sideFrames.count == payload.midFrames.count)
                for (frame, midOnly) in zip(payload.sideFrames, payload.midOnly) {
                    if midOnly { #expect(frame == nil); observedOmittedSide = true }
                }
            }
        }
        if index == 4 { #expect(observedOmittedSide) }
    }

    /// All packet packing codes and code-three VBR/padding retain the exact state
    /// progression of raw payload calls. Two 60ms payloads reach 120ms stereo output.
    @Test
    func packingAndMaximumDuration() throws {
        let input = try JSONDecoder().decode(Input.self, from: Data(silkStereoOracleFixtures[0].input.utf8))
        for index in [0, 6] {
            let original = try OpusPacket(Data(input.packets[index]))
            let payload = [UInt8](original.data.subdata(in: original.frameRanges[0]))
            let toc = UInt8(original.configuration << 3) | 4
            let length = encodedLength(payload.count)
            let forms: [[UInt8]] = [
                [toc] + payload, [toc | 1] + payload + payload,
                [toc | 2] + length + payload + payload,
                [toc | 3, 2] + payload + payload,
                [toc | 3, 0x82] + length + payload + payload,
                [toc | 3, 0xc2, 3] + length + payload + payload + [255, 0, 127]
            ]
            for bytes in forms {
                let packet = try OpusPacket(Data(bytes))
                var packed = try SILKStereoDecoder(sampleRate: input.rate)
                var raw = try SILKStereoDecoder(sampleRate: input.rate)
                var expected: [Int16] = []
                for _ in packet.frameRanges {
                    expected += try raw.decodePayload(Data(payload), durationMilliseconds: original.frameSampleCount / 48).pcm48k
                }
                #expect(try packed.decode(packet).pcm48k == expected)
                #expect(expected.count == packet.sampleCount * 2)
                if index == 6 && packet.frameRanges.count == 2 { #expect(expected.count == 11_520) }
            }
        }
    }

    /// Shared hybrid entropy must yield identical SILK results and the same forward
    /// boundary as a raw payload, retaining all entropy state for a later CELT stage.
    /// Invalid admission commits neither stream history nor entropy progression.
    @Test
    func sharedEntropyAdmissionAndAtomicity() throws {
        let input = try JSONDecoder().decode(Input.self, from: Data(silkStereoOracleFixtures[0].input.utf8))
        let packet = try OpusPacket(Data(input.packets[0]))
        let payload = packet.data.subdata(in: packet.frameRanges[0])
        var shared = try SILKStereoDecoder(sampleRate: input.rate)
        var raw = shared
        var entropy = try OpusRangeDecoder(frame: payload)
        let initialRange = entropy.finalRange
        let initialBits = entropy.bitsUsed
        for duration in [0, 5, 15, 80, 120] {
            #expect(throws: SILKMonoDecoderError.invalidPayloadDuration) {
                try shared.decodePayload(from: &entropy, durationMilliseconds: duration, codedChannelCount: 2)
            }
        }
        for channels in [0, 3] {
            #expect(throws: SILKMonoDecoderError.unsupportedChannels) {
                try shared.decodePayload(from: &entropy, durationMilliseconds: 10, codedChannelCount: channels)
            }
        }
        #expect(entropy.finalRange == initialRange)
        #expect(entropy.bitsUsed == initialBits)
        let a = try shared.decodePayload(from: &entropy, durationMilliseconds: 10, codedChannelCount: 2)
        let b = try raw.decodePayload(payload, durationMilliseconds: 10)
        #expect(a == b)
        #expect(entropy.finalRange == b.finalRange)
        #expect(entropy.bitsUsed == b.bitsUsed)
        #expect(try shared.decode(packet) == raw.decode(packet))
    }

    /// Every public validation failure preserves complete decoder ownership. A
    /// malformed second packed frame rolls back successful prior decoding and an
    /// adopted rate change. Reset and value copies retain independent filter state.
    @Test
    func validationResetAndCopies() throws {
        #expect(throws: SILKFrameParameterError.invalidSampleRate) { try SILKStereoDecoder(sampleRate: 48_000) }
        let input = try JSONDecoder().decode(Input.self, from: Data(silkStereoOracleFixtures[0].input.utf8))
        let packet = try OpusPacket(Data(input.packets[0]))
        let payload = packet.data.subdata(in: packet.frameRanges[0])
        var decoder = try SILKStereoDecoder(sampleRate: 16_000)
        for bytes in [Data(), Data(repeating: 0, count: 1_276)] {
            #expect(throws: SILKMonoDecoderError.invalidPayloadSize) { try decoder.decodePayload(bytes, durationMilliseconds: 10) }
        }
        #expect(throws: SILKFrameParameterError.invalidSampleRate) { try decoder.updateSampleRate(24_000) }
        #expect(decoder.sampleRate == 16_000)
        #expect(throws: SILKMonoDecoderError.unsupportedMode) { try decoder.decode(OpusPacket(Data([128, 0]))) }
        let partial = try OpusPacket(Data([6] + encodedLength(payload.count)) + payload)
        #expect(partial.frameRanges[1].isEmpty)
        #expect(throws: SILKMonoDecoderError.invalidPayloadSize) { try decoder.decode(partial) }
        #expect(decoder.sampleRate == 16_000)
        var pristine = try SILKStereoDecoder(sampleRate: 16_000)
        #expect(try decoder.decode(packet) == pristine.decode(packet))
        var copy = decoder
        try decoder.updateSampleRate(decoder.sampleRate)
        #expect(try decoder.decode(packet) == copy.decode(packet))
        decoder.reset()
        pristine.reset()
        #expect(try decoder.decode(packet) == pristine.decode(packet))
    }

    /// Explicit mono bandwidth reconfiguration matches independent stereo-API
    /// decoding of the same mono packets at every directed NB/MB/WB transition.
    /// An unchanged/invalid rate preserves existing mono alignment and filter state.
    @Test
    func monoRateTransitions() throws {
        let fixture = silkStereoOracleFixtures[5]
        let input = try JSONDecoder().decode(Input.self, from: Data(fixture.input.utf8))
        let expected = try JSONDecoder().decode([Output].self, from: Data(fixture.expected.utf8))
        var mono = try SILKMonoDecoder(sampleRate: input.rate)
        for (bytes, output) in zip(input.packets, expected) {
            let packet = try OpusPacket(Data(bytes))
            #expect(packet.channelCount == 1)
            try mono.updateSampleRate([8_000, 12_000, 16_000][packet.configuration / 4])
            var copy = mono
            #expect(throws: SILKFrameParameterError.invalidSampleRate) { try mono.updateSampleRate(0) }
            try mono.updateSampleRate(mono.sampleRate)
            let decoded = try mono.decode(packet)
            #expect(try decoded == copy.decode(packet))
            #expect(decoded.pcm48k == stride(from: 0, to: output.pcm.count, by: 2).map { output.pcm[$0] })
            #expect(stride(from: 0, to: output.pcm.count, by: 2).allSatisfy { output.pcm[$0] == output.pcm[$0 + 1] })
        }
    }

    /// Bandwidth/side prediction resets retain scalar gain but clear LPC/LTP and
    /// establish first-frame interpolation. Invalid reconfiguration is atomic.
    @Test
    func channelPredictionResetSemantics() throws {
        let input = try JSONDecoder().decode(Input.self, from: Data(silkStereoOracleFixtures[5].input.utf8))
        let packet = try OpusPacket(Data(input.packets[0]))
        var entropy = try OpusRangeDecoder(frame: packet.data.subdata(in: packet.frameRanges[0]))
        let vad = try entropy.decodeBit(logProbability: 1)
        #expect(try entropy.decodeBit(logProbability: 1) == false)
        var channel = try SILKFrameDecoder(sampleRate: input.rate, frameDurationMilliseconds: 10)
        _ = try channel.decode(from: &entropy, voiceActivity: vad)
        let gain = channel.previousGainQ16
        let history = channel.outputHistory
        try channel.updateSampleRate(input.rate)
        #expect(channel.outputHistory == history)
        #expect(!channel.isFirstFrameAfterReset)
        #expect(throws: SILKFrameParameterError.invalidSampleRate) { try channel.updateSampleRate(1) }
        #expect(channel.outputHistory == history)
        try channel.updateSampleRate(16_000)
        #expect(channel.sampleRate == 16_000)
        #expect(channel.previousGainQ16 == gain)
        #expect(channel.outputHistory == Array(repeating: 0, count: 320))
        #expect(channel.shortTermHistoryQ14 == Array(repeating: 0, count: 16))
        #expect(channel.previousNormalizedLSFsQ15.count == 16)
        #expect(channel.isFirstFrameAfterReset)
        try channel.resetSidePrediction()
        #expect(channel.previousGainQ16 == gain)
        #expect(channel.isFirstFrameAfterReset)
    }

    /// Normative range zero extension can decode damaged bytes into bounded audio;
    /// this checks all header extremes, rates and durations without claiming validity.
    @Test
    func boundedArbitraryPayloads() throws {
        for rate in [8_000, 12_000, 16_000] {
            for duration in [10, 20, 40, 60] {
                var decoder = try SILKStereoDecoder(sampleRate: rate)
                for byte in [UInt8(0), 1, 63, 127, 128, 191, 254, 255] {
                    let output = try decoder.decodePayload(Data([byte]), durationMilliseconds: duration)
                    #expect(output.pcm48k.count == duration * 96)
                    #expect(output.midFrames.count == (duration == 10 ? 1 : duration / 20))
                    #expect(output.sideFrames.count == output.midFrames.count)
                }
            }
        }
    }

    /// Encodes a normative bounded one/two-byte packet length for packing tests.
    /// - Parameter count: Compressed payload size in zero through 1,275 bytes.
    /// - Returns: One length byte below 252, otherwise two length bytes.
    private func encodedLength(_ count: Int) -> [UInt8] {
        if count < 252 { return [UInt8(count)] }
        let first = 252 + (count & 3)
        return [UInt8(first), UInt8((count - first) / 4)]
    }
}
