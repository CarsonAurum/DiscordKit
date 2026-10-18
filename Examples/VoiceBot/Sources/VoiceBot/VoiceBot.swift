import Foundation
import DiscordMedia
import DiscordVoice
import DiscordVoiceCodecs
import DiscordVoiceCrypto

/// Offline integration example for Phase 12 media/protocol components, without a Discord session.
@main struct VoiceBot {
    /// Round-trips synthetic Opus silence through RTP-size protection and a bounded reorder queue.
    /// First checks a bounded bandlimited PCM/resampling timeline, silence activity decisions,
    /// independent synthetic entropy/pulse-codebook symbols, CELT transform/band shapes
    /// and SILK predictor analysis/synthesis;
    /// these checks neither encode nor decode SILK/CELT audio.
    /// Uses a fixed, public test-only key that must never be used for real media. No network,
    /// device, authentication, DAVE context or background task is created. The two cipher
    /// instances model one sender and one receive-only peer, never two sending nonce owners.
    /// - Throws: Validation/authentication errors, including any round-trip invariant failure.
    static func main() async throws {
        try await demonstratePortableMedia()
        try demonstrateEntropyCoding()
        try demonstrateCodecComponents()
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
            print("Offline transport example only; MLS/DAVE and live voice sessions remain unimplemented.")
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
        print("CELT transform/shape and SILK predictor components checked; complete Opus remains unimplemented.")
    }

    /// Example-local invariant failures, without treating an entropy round trip as voice support.
    private enum ExampleFailure: Error { case invalidInvariant }
}
