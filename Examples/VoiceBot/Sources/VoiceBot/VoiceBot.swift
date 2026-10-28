// File: Examples/VoiceBot/Sources/VoiceBot/VoiceBot.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import Foundation
import DiscordMedia
import DiscordVoice
import DiscordVoiceCodecs
import DiscordVoiceCrypto

/// Offline integration example for media and voice protocol components, without a Discord session.
@main struct VoiceBot {
    /// Round-trips synthetic Opus silence through RTP-size protection and a bounded reorder queue.
    /// First checks a bounded bandlimited PCM/resampling timeline, silence activity decisions,
    /// independent synthetic entropy/pulse-codebook symbols, CELT transform/band shapes
    /// and SILK predictor analysis/synthesis. It then encodes/decodes actual ordinary
    /// CELT packets and reconstructs a committed reference SILK packet to exact PCM.
    /// It also checks conservative stereo SILK/hybrid encoding and CELT loss/recovery.
    /// Full codec conformance and native device qualification remain separate.
    /// Uses a fixed, public test-only key that must never be used for real media. No network,
    /// device, authenticated service or background task is created. A separate synthetic DAVE
    /// signaling/media demonstration creates only bounded local MLS and cipher actors. The two transport cipher
    /// instances model one sender and one receive-only peer, never two sending nonce owners.
    /// - Throws: Validation/authentication errors, including any round-trip invariant failure.
    static func main() async throws {
        try await demonstrateMLS()
        try await demonstrateDAVE()
        try await demonstratePortableMedia()
        try demonstrateEntropyCoding()
        try demonstrateCodecComponents()
        try demonstrateCompressedAudio()
        try demonstrateHybridAndLoss()
        let key = Data(0..<32)
        let sender = try VoiceTransportCipher(mode: .aeadXChaCha20Poly1305RTPSize, key: key)
        let receiver = try VoiceTransportCipher(mode: .aeadXChaCha20Poly1305RTPSize, key: key)
        do {
            var packetizer = OpusRTPPacketizer(ssrc: 1, sequence: 65_534, timestamp: .max - 959)
            var playout = try VoiceJitterBuffer(ssrc: 1, nextSequence: 65_534, capacity: 8, maximumBytes: 1024)
            for _ in 0..<5 {
                let packet = try packetizer.silencePacket()
                let plaintext = packet.serialized()
                let length = try RTPPacket.authenticatedHeaderLength(in: plaintext)
                let header = Data(plaintext.prefix(length))
                let encrypted = try await sender.seal(payload: Data(plaintext.dropFirst(length)), authenticatedHeader: header)
                let opened = try await receiver.open(sealedPayload: encrypted, authenticatedHeader: header)
                let received = try RTPPacket(bytes: header + opened)
                _ = try OpusPacket(received.payload)
                try playout.insert(received)
            }
            for _ in 0..<5 {
                guard case .packet = playout.pop() else { throw VoicePacketError.malformedPacket }
            }
            guard playout.bufferedBytes == 0 else { throw VoicePacketError.capacityExceeded }
            print("Five synthetic Opus packets authenticated and drained across RTP rollover.")
            print("Offline MLS/DAVE/transport example only; supervised sessions are independently adopted.")
            await sender.close()
            await receiver.close()
        } catch {
            await sender.close()
            await receiver.close()
            throw error
        }
    }

    /// Drains a bounded synthetic PCM sequence through bandlimited 24kHz-to-48kHz resampling.
    /// No input/output device or producer task is created. The sample clock checks exact
    /// cumulative duration across chunk boundaries and the resampler's final lookahead.
    /// - Throws: Media validation/admission errors, cancellation or an invariant failure.
    private static func demonstratePortableMedia() async throws {
        let format = try PCMFormat(sampleRate: 24_000, channelCount: 1)
        let stream = try PCMFrameStream(maximumBlocks: 2, maximumBytes: 3_840)
        try await stream.write(PCMBuffer(format: format, samples: Array(repeating: 0.25, count: 480)))
        try await stream.write(PCMBuffer(format: format, samples: Array(repeating: -0.25, count: 480)))
        await stream.finish()
        var resampler = try PCMBandlimitedResampler(inputFormat: format, outputSampleRate: 48_000)
        var clock = try PCMSampleClock(sampleRate: 48_000)
        for try await buffer in stream {
            for output in try resampler.process(buffer) { _ = try clock.advance(by: output.frameCount) }
        }
        for output in try resampler.finish() { _ = try clock.advance(by: output.frameCount) }
        let snapshot = await stream.snapshot()
        guard clock.samplePosition == 1_920, snapshot.accountedBytes == 0,
              snapshot.bufferedBlocks == 0, snapshot.isFinished else {
            throw ExampleFailure.invalidInvariant
        }
        var activity = try PCMSpeechActivityDetector(format: format)
        let decisions = try activity.process(PCMBuffer(format: format, samples: Array(repeating: 0, count: 480)))
        guard decisions.count == 1, decisions.allSatisfy({ !$0.isSpeech }) else {
            throw ExampleFailure.invalidInvariant
        }
        print("Bounded PCM stream filtered to exactly 1,920 frames at 48 kHz; silence rejected by VAD.")
    }

    /// Round-trips synthetic entropy symbols independently of the encoded-Opus RTP example.
    /// Also checks CELT's signed pulse-codebook ordering in isolation. These symbols do not
    /// form a complete SILK/CELT audio frame and are never published as audio.
    /// - Throws: Entropy validation/budget errors or a round-trip invariant failure.
    private static func demonstrateEntropyCoding() throws {
        var encoder = try OpusRangeEncoder(frameByteCount: 8)
        let codebook = try CELTPulseCodebook(dimensions: 4, pulseCount: 3)
        let pulses = [1, -1, 0, 1]
        try encoder.encodeUniform(7, total: 11)
        try encoder.encodeBit(true, logProbability: 2)
        try encoder.encodeRawBits(21, count: 5)
        try codebook.encode(pulses, into: &encoder)
        let bytes = try encoder.finalize()
        var decoder = try OpusRangeDecoder(frame: bytes)
        guard try decoder.decodeUniform(total: 11) == 7,
              try decoder.decodeBit(logProbability: 2),
              try decoder.decodeRawBits(count: 5) == 21,
              try codebook.decode(from: &decoder) == pulses,
              decoder.finalRange == encoder.finalRange else { throw ExampleFailure.invalidInvariant }
        print("Synthetic entropy symbols match their final arithmetic range; no audio codec is implied.")
    }

    /// Exercises owned CELT analysis/overlap and one independently coded spectral band, then
    /// validates SILK short-term analysis/synthesis. All coefficients/contexts are synthetic;
    /// no complete compressed audio syntax, band allocation, SILK parameters or PLC is implied.
    /// - Throws: Transform/predictor/entropy errors or any local reconstruction invariant failure.
    private static func demonstrateCodecComponents() throws {
        let transform = try CELTTransform(frameSampleCount: 240)
        var stream = CELTTransformStream(transform: transform)
        let source = (0..<240).map { Float(0.25 * sin(2 * Double.pi * 440 * Double($0) / 48_000)) }
        let coefficients = try stream.analyze(source)
        let first = try stream.synthesize(coefficients)
        let trailingCoefficients = try stream.analyze(Array(repeating: 0, count: 240))
        let tail = try stream.synthesize(trailingCoefficients)
        let recovered = Array((first + tail).dropFirst(120).prefix(source.count))
        guard zip(source, recovered).allSatisfy({ abs($0 - $1) < 1e-5 }) else {
            throw ExampleFailure.invalidInvariant
        }
        let band = Array(coefficients.prefix(8))
        let norm = sqrt(band.reduce(0.0) { $0 + Double($1) * Double($1) })
        let normalized = band.map { Float(Double($0) / max(1e-15, norm)) }
        let quantizer = try CELTBandQuantizer(dimensions: 8, pulseCount: 4)
        var encoder = try OpusRangeEncoder(frameByteCount: 8)
        let shape = try quantizer.encode(normalized, into: &encoder)
        var decoder = try OpusRangeDecoder(frame: encoder.finalize())
        guard try quantizer.decode(from: &decoder) == shape,
              decoder.finalRange == encoder.finalRange else { throw ExampleFailure.invalidInvariant }

        let predictor = try SILKLinearPredictionCoefficients(q12: [2048] + Array(repeating: 0, count: 9))
        var analysis = try SILKShortTermFilter(direction: .analysis, coefficients: predictor)
        var synthesis = try SILKShortTermFilter(direction: .synthesis, coefficients: predictor)
        let signal = source.map(Double.init)
        let residual = try analysis.process(signal)
        let reconstructed = try synthesis.process(residual)
        guard zip(signal, reconstructed).allSatisfy({ abs($0 - $1) < 1e-12 }) else {
            throw ExampleFailure.invalidInvariant
        }
        print("CELT transform/shape and SILK predictor components checked independently.")
    }

    /// Exercises the independently owned ordinary compressed-audio paths without native codecs.
    /// Three synthetic mono 20ms CELT frames are encoded with 161-byte Opus packet budgets
    /// and decoded in order. A separate synthetic NB SILK packet and complete expected PCM
    /// fingerprint originate from unmodified official libopus1.6.1 through the opt-in
    /// mono oracle. The public FNV fingerprint is an example invariant, not authentication.
    /// - Throws: Codec/framing errors or any PCM count/value/reference invariant failure.
    /// No audio is recorded, played, transmitted or decoded through a system codec.
    private static func demonstrateCompressedAudio() throws {
        var encoder = try CELTPacketEncoder(frameSampleCount: 960)
        var decoder = try CELTPacketDecoder()
        var sampleCount = 0
        var energy: Double = 0
        for frame in 0..<3 {
            let source = (0..<960).map { sample in
                Float(0.2 * sin(2 * Double.pi * 440 * Double(frame * 960 + sample) / 48_000))
            }
            let bytes = try encoder.encode(source, packetByteCount: 161)
            let packet = try OpusPacket(bytes)
            let decoded = try decoder.decode(bytes)
            guard packet.mode == .celt, packet.sampleCount == 960, bytes.count == 161,
                  decoded.count == 1, decoded[0].samples.count == 960,
                  decoded[0].samples.allSatisfy(\.isFinite), decoded[0].finalRange != 0 else {
                throw ExampleFailure.invalidInvariant
            }
            sampleCount += decoded[0].samples.count
            energy += decoded[0].samples.reduce(0) { $0 + Double($1) * Double($1) }
        }
        guard sampleCount == 2_880, energy > 1 else { throw ExampleFailure.invalidInvariant }

        let reference = Data([0, 129, 212, 108, 89, 46, 165, 239, 228, 150,
                              168, 83, 126, 156, 68, 45, 176, 89, 247, 128])
        var silk = try SILKMonoDecoder(sampleRate: 8_000)
        let decoded = try silk.decode(OpusPacket(reference))
        var fingerprint: UInt64 = 14_695_981_039_346_656_037
        for sample in decoded.pcm48k {
            let bits = UInt16(bitPattern: sample)
            fingerprint = (fingerprint ^ UInt64(bits & 255)) &* 1_099_511_628_211
            fingerprint = (fingerprint ^ UInt64(bits >> 8)) &* 1_099_511_628_211
        }
        guard decoded.pcm48k.count == 480, fingerprint == 0xba5d8977468a4cfe,
              decoded.payloads.count == 1, decoded.payloads[0].finalRange == 1_960_804_352 else {
            throw ExampleFailure.invalidInvariant
        }
        print("Owned CELT packets produced 2,880 PCM samples; reference SILK packet matched 480 exact 48-kHz samples.")
        print("Ordinary codec paths checked; device, perceptual and live voice qualification remain open.")
    }

    /// Exercises stereo SILK/hybrid coding, CELT concealment and unified mode/recovery ownership.
    /// All PCM is synthetic. The shared hybrid interval is checked through the owned
    /// decoder while independent pinned-oracle comparisons remain in development tests.
    /// - Throws: Codec/admission errors or a duration, channel, finite-value or PCM
    ///   activity invariant failure. No device, network or background task is started.
    private static func demonstrateHybridAndLoss() throws {
        let samples = (0..<1_920).map { index in
            Float(sin(Double(index / 2) * (index % 2 == 0 ? 0.05 : 0.09))) * 0.2
        }
        let internalSamples = (0..<640).map { index in
            Int16(sin(Double(index / 2) * (index % 2 == 0 ? 0.15 : 0.27)) * 8_000)
        }
        var silkEncoder = try SILKStereoEncoder(sampleRate: 16_000)
        var silkDecoder = try SILKStereoDecoder(sampleRate: 16_000)
        let silkPacket = try silkEncoder.encode(internalSamples)
        let silkPCM = try silkDecoder.decode(silkPacket.packet)
        guard silkPCM.pcm48k.count == 1_920,
              silkPCM.pcm48k.contains(where: { $0 != 0 }) else { throw ExampleFailure.invalidInvariant }
        var hybridEncoder = try OpusHybridEncoder(channelCount: 2)
        var hybridDecoder = try OpusHybridDecoder(channelCount: 2)
        let hybridPacket = try hybridEncoder.encode(samples, packetByteCount: 320)
        let hybridPCM = try hybridDecoder.decode(hybridPacket)
        guard hybridPCM.count == 1, hybridPCM[0].samples.count == 1_920,
              hybridPCM[0].samples.allSatisfy({ $0.isFinite }),
              hybridPCM[0].samples.contains(where: { abs($0) > 1e-6 }) else { throw ExampleFailure.invalidInvariant }
        var celtEncoder = try CELTPacketEncoder(frameSampleCount: 960, channelCount: 2)
        var celtDecoder = try CELTPacketDecoder(channelCount: 2)
        let received = try celtEncoder.encode(samples, packetByteCount: 320)
        _ = try celtDecoder.decode(received)
        let missing = try celtDecoder.conceal(frameSampleCount: 960)
        let recovery = try celtEncoder.encode(samples, packetByteCount: 320)
        let recovered = try celtDecoder.decode(recovery)
        guard missing.samples.count == 1_920, missing.samples.allSatisfy({ $0.isFinite }),
              recovered.count == 1, recovered[0].samples.count == 1_920 else { throw ExampleFailure.invalidInvariant }
        var ordinary = try OpusAudioDecoder(channelCount: 2)
        for packet in [silkPacket.packet.data, hybridPacket, received] {
            let decoded = try ordinary.decode(packet)
            guard decoded.flatMap(\.samples).count == 1_920,
                  decoded.allSatisfy({ $0.samples.allSatisfy { $0.isFinite } }) else {
                throw ExampleFailure.invalidInvariant
            }
        }
        let concealed = try ordinary.conceal(frameSampleCount: 960)
        let fecOrPLC = try ordinary.recover(recovery, frameSampleCount: 960)
        let following = try ordinary.decode(recovery)
        guard concealed.samples.count == 1_920, fecOrPLC.samples.count == 1_920,
              following.flatMap(\.samples).count == 1_920 else { throw ExampleFailure.invalidInvariant }
        print("Stereo SILK/hybrid and unified mode transitions decoded; explicit loss/recovery preserved exact duration.")
    }

    /// Shared example-local invariant failures across the media and DAVE demonstrations.
    enum ExampleFailure: Error { case invalidInvariant }
}
