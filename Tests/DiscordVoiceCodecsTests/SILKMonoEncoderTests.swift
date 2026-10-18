import Foundation
import Testing
@testable import DiscordVoiceCodecs

@Suite("Owned conservative ordinary SILK PCM encoding")
struct SILKMonoEncoderTests {
    /// Zero scalar cost preserves ordinary encoder pulses exactly; a cost above
    /// every possible PCM16 squared error deterministically admits zero excitation,
    /// including when it lies outside the nearest five-pulse neighborhood.
    @Test func sparseRateDistortionCandidateBounds() throws {
        for rate in [8_000, 12_000, 16_000] {
            for duration in [10, 20] {
                var encoder = try SILKMonoEncoder(sampleRate: rate, frameDurationMilliseconds: duration)
                let pcm = samples(count: encoder.sampleCount, rate: rate, pattern: 1)
                let encoded = try encoder.encode(pcm)
                let coefficients = try SILKNLSFCoefficients(q15: encoded.parameters.normalizedLSFsQ15).lpcQ12
                let ordinary = SILKFrameQuantization.quantize(pcm, coefficients: coefficients,
                    parameters: encoded.parameters, previousGainQ16: 65_536,
                    shortTermHistoryQ14: Array(repeating: 0, count: 16),
                    outputHistory: Array(repeating: 0, count: rate / 50))
                #expect(ordinary == encoded.signedPulses)
                let sparse = SILKFrameQuantization.quantize(pcm, coefficients: coefficients,
                    parameters: encoded.parameters, previousGainQ16: 65_536,
                    shortTermHistoryQ14: Array(repeating: 0, count: 16),
                    outputHistory: Array(repeating: 0, count: rate / 50), ratePenalty: 4_294_967_296)
                #expect(sparse.count == pcm.count && sparse.allSatisfy { $0 == 0 })
            }
        }
    }

    /// A clipped rising harmonic waveform exhausts voiced gain admission at the
    /// sixth frame; ordinary unvoiced fallback fits the same 79-byte ceiling while
    /// retaining exact decoder feedback, active VAD and independently owned state.
    /// The synthesized formula is owned regression material, not a recorded corpus.
    @Test func voicedBudgetUsesBoundedUnvoicedFallback() throws {
        var encoder = try SILKMonoEncoder(sampleRate: 16_000)
        var decoder = try SILKMonoDecoder(sampleRate: 16_000)
        for frame in 0..<6 {
            let pcm = (0..<320).map { index -> Int16 in
                let t = Double(frame * 320 + index) / 16_000
                let envelope = pow(max(0, sin(.pi * t.truncatingRemainder(dividingBy: 0.24) / 0.24)), 2)
                let value = (1...8).reduce(0.0) { $0 + sin(2 * .pi * 100 * Double($1) * t) / Double($1) }
                    * 28_000 * envelope
                return Int16(clamping: Int(value.rounded()))
            }
            var unconstrained = encoder
            var wide = try OpusRangeEncoder(frameByteCount: 1_275)
            let preferred = try unconstrained.encodePayload(pcm, to: &wide)
            var copied = encoder
            var narrow = try OpusRangeEncoder(frameByteCount: 79)
            let output = try encoder.encodePayload(pcm, to: &narrow)
            var copiedEntropy = try OpusRangeEncoder(frameByteCount: 79)
            #expect(try copied.encodePayload(pcm, to: &copiedEntropy) == output)
            #expect(output.bitsUsed <= 632 && output.redundancy == nil)
            if frame == 5 {
                #expect(preferred.parameters.signalType == .voiced && preferred.bitsUsed > 632)
                #expect(output.parameters.signalType == .unvoiced)
            }
            let count = max(2, (narrow.bitsUsed + 7) / 8)
            let packet = try OpusPacket(Data([0x48]) + Data(try narrow.finalize().prefix(count)))
            let decoded = try decoder.decode(packet).payloads[0]
            #expect(decoded.voiceActivity == [true])
            #expect(decoded.frames[0].parameters == output.parameters)
            #expect(decoded.frames[0].pulses.signedPulses == output.signedPulses)
            #expect(decoded.frames[0].pcm == output.reconstructedPCM)
            #expect(decoded.finalRange == output.finalRange)
        }
    }

    /// Selects emitted LBRR for a genuinely missing active packet, then consumes the
    /// following ordinary packet. All rates/durations preserve exact reconstruction
    /// and independent entropy endpoints. Initial and inactive preceding frames omit
    /// LBRR, reset clears retained redundancy, and failed budgets preserve that frame.
    @Test
    func emittedRedundancySelectionAndAtomicity() throws {
        for rate in [8_000, 12_000, 16_000] {
            for duration in [10, 20] {
                var encoder = try SILKMonoEncoder(sampleRate: rate, frameDurationMilliseconds: duration, enableInBandFEC: true)
                #expect(encoder.enableInBandFEC)
                var ordinary = try SILKMonoDecoder(sampleRate: rate)
                var missing = ordinary
                let pcm = samples(count: encoder.sampleCount, rate: rate, pattern: 1)
                let first = try encoder.encode(pcm)
                #expect(try ordinary.decode(first.packet).payloads[0].redundancy == [false])
                let before = encoder
                var failed = try OpusRangeEncoder(frameByteCount: 1_275)
                #expect(throws: SILKMonoEncoderError.payloadBudgetExceeded) {
                    try encoder.encodePayload(pcm, to: &failed, maximumBits: 1)
                }
                #expect(failed.operationCount == 0)
                var copy = before
                let following = try encoder.encode(pcm.map { $0 / 3 })
                #expect(try copy.encode(pcm.map { $0 / 3 }) == following)
                let payload = Data(following.packet.data[following.packet.frameRanges[0]])
                let recovered = try missing.recoverPayload(payload, durationMilliseconds: duration)
                #expect(recovered.redundancy == [[true]])
                #expect(recovered.channelFrames[0][0]?.parameters == first.parameters)
                #expect(recovered.channelFrames[0][0]?.pulses.signedPulses == first.signedPulses)
                #expect(recovered.channelFrames[0][0]?.pcm == first.reconstructedPCM)
                #expect(try missing.decode(following.packet) == ordinary.decode(following.packet))
                let silence = Array(repeating: Int16(0), count: encoder.sampleCount)
                _ = try encoder.encode(silence)
                let afterSilence = try encoder.encode(pcm)
                var check = try SILKMonoDecoder(sampleRate: rate)
                #expect(try check.decode(afterSilence.packet).payloads[0].redundancy == [false])
                encoder.reset()
                var fresh = try SILKMonoEncoder(sampleRate: rate, frameDurationMilliseconds: duration, enableInBandFEC: true)
                #expect(try encoder.encode(pcm) == fresh.encode(pcm))
            }
        }
    }

    /// Requires real quantized voiced prediction for periodic input in every internal
    /// format, including persistent/restarted histories and a subsequent unvoiced frame.
    /// The ordinary decoder must reproduce every pulse and PCM sample exactly while
    /// tone error stays bounded. Constant and deterministic noise input exercise the
    /// variance/correlation rejection paths rather than manufacturing pitch metadata.
    @Test
    func voicedAnalysisAndExactLongTermFeedback() throws {
        for rate in [8_000, 12_000, 16_000] {
            for duration in [10, 20] {
                var encoder = try SILKMonoEncoder(sampleRate: rate, frameDurationMilliseconds: duration)
                var decoder = try SILKMonoDecoder(sampleRate: rate)
                var voiced = 0
                for frame in 0..<5 {
                    let pcm = (0..<encoder.sampleCount).map {
                        Int16(12_000 * sin(Double(frame * encoder.sampleCount + $0) * 200 * 2 * Double.pi / Double(rate)))
                    }
                    let output = try encoder.encode(pcm)
                    let decoded = try decoder.decode(output.packet).payloads[0].frames[0]
                    #expect(decoded.pcm == output.reconstructedPCM)
                    if output.parameters.signalType == .voiced {
                        voiced += 1
                        #expect(output.parameters.pitchLags.allSatisfy { (rate * 2 / 1_000...rate * 18 / 1_000).contains($0) })
                        #expect(output.parameters.longTermCoefficientsQ7.contains { $0.contains { $0 != 0 } })
                    }
                    let energy = zip(pcm, output.reconstructedPCM).reduce(0.0) {
                        let difference = Double($1.0) - Double($1.1)
                        return $0 + difference * difference
                    }
                    #expect(sqrt(energy / Double(pcm.count)) < 200)
                }
                #expect(voiced >= 3)
                let constant = try encoder.encode(Array(repeating: 1_234, count: encoder.sampleCount))
                #expect(constant.parameters.signalType == .unvoiced)
                var fresh = try SILKMonoEncoder(sampleRate: rate, frameDurationMilliseconds: duration)
                let noise = samples(count: fresh.sampleCount, rate: rate, pattern: 4)
                #expect(try fresh.encode(noise).parameters.signalType == .unvoiced)
                encoder.reset()
                var other = try SILKMonoEncoder(sampleRate: rate, frameDurationMilliseconds: duration)
                #expect(try encoder.encode(noise) == other.encode(noise))
            }
        }
    }

    /// Exercises all six formats over consecutive silence, speech-like tones, clipping
    /// extrema, ramps and deterministic noise. Packets decode through ordinary syntax,
    /// preserving every selected index/pulse, exact reconstruction and entropy endpoint.
    @Test
    func ordinaryPacketsAndPersistentReconstruction() throws {
        for rate in [8_000, 12_000, 16_000] {
            for duration in [10, 20] {
                var encoder = try SILKMonoEncoder(sampleRate: rate, frameDurationMilliseconds: duration)
                var decoder = try SILKMonoDecoder(sampleRate: rate)
                for pattern in 0..<6 {
                    let pcm = samples(count: encoder.sampleCount, rate: rate, pattern: pattern)
                    let encoded = try encoder.encode(pcm)
                    let decoded = try decoder.decode(encoded.packet)
                    let payload = try #require(decoded.payloads.first)
                    let frame = try #require(payload.frames.first)
                    #expect(encoded.packet.mode == .silk)
                    #expect(encoded.packet.channelCount == 1)
                    #expect(encoded.packet.frameSampleCount == duration * 48)
                    #expect(encoded.packet.data.count <= 1_276)
                    #expect(encoded.packet.packingCode == 0)
                    #expect(frame.parameters == encoded.parameters)
                    #expect(frame.pulses.signedPulses == encoded.signedPulses)
                    #expect(frame.pcm == encoded.reconstructedPCM)
                    #expect(payload.finalRange == encoded.finalRange)
                    #expect(payload.bitsUsed == encoded.bitsUsed)
                    #expect(encoded.signedPulses.allSatisfy { (-127...127).contains($0) })
                    #expect(payload.voiceActivity == [pattern != 0])
                    #expect(payload.redundancy == [false])
                    #expect(pattern == 0 ? frame.parameters.signalType == .inactive : frame.parameters.signalType != .inactive)
                    #expect(frame.parameters.normalizedLSFResidualIndices.allSatisfy { $0 == 0 })
                    #expect(frame.parameters.interpolationQ2 == 4)
                }
            }
        }
    }

    /// Checks that this real PCM encoder reconstructs a direct internal-rate tone with
    /// bounded error, rather than returning a constant packet or only entropy syntax.
    /// This deterministic numerical regression is not a perceptual-quality qualification.
    @Test
    func toneFidelityAndSignalDependence() throws {
        for rate in [8_000, 12_000, 16_000] {
            var encoder = try SILKMonoEncoder(sampleRate: rate)
            let pcm = samples(count: encoder.sampleCount, rate: rate, pattern: 1)
            let output = try encoder.encode(pcm)
            let energy = zip(pcm, output.reconstructedPCM).reduce(0.0) { sum, pair in
                let difference = Double(pair.0) - Double(pair.1)
                return sum + difference * difference
            }
            #expect(sqrt(energy / Double(pcm.count)) < 200)
            #expect(output.signedPulses.contains { $0 != 0 })
            #expect(output.reconstructedPCM.max()! > 9_000)
            #expect(output.reconstructedPCM.min()! < -9_000)
            var other = try SILKMonoEncoder(sampleRate: rate)
            #expect(try other.encode(pcm.map { -$0 }).packet.data != output.packet.data)
        }
    }

    /// Proves constructor bounds, exact input admission, owned copies and idempotent
    /// reset. Failed calls consume no gain/synthesis history, permitting identical retries.
    @Test
    func validationResetAndCopyOwnership() throws {
        #expect(throws: SILKFrameParameterError.invalidSampleRate) { try SILKMonoEncoder(sampleRate: 48_000) }
        #expect(throws: SILKFrameParameterError.invalidFrameDuration) { try SILKMonoEncoder(sampleRate: 16_000, frameDurationMilliseconds: 40) }
        for limit in [Int.min, 0, 15, 1_276, Int.max] {
            #expect(throws: SILKMonoEncoderError.invalidPayloadByteLimit) { try SILKMonoEncoder(sampleRate: 16_000, maximumPayloadBytes: limit) }
        }
        var encoder = try SILKMonoEncoder(sampleRate: 16_000)
        let pcm = samples(count: encoder.sampleCount, rate: 16_000, pattern: 1)
        let pristine = encoder
        for count in [0, encoder.sampleCount - 1, encoder.sampleCount + 1, 5_761] {
            #expect(throws: SILKMonoEncoderError.invalidSampleCount) { try encoder.encode(Array(repeating: 0, count: count)) }
            #expect(encoder.previousGainIndex == 0)
        }
        var first = pristine
        #expect(try encoder.encode(pcm) == first.encode(pcm))
        var copy = encoder
        #expect(try copy.encode(pcm) == encoder.encode(pcm))
        encoder.reset()
        encoder.reset()
        var fresh = pristine
        #expect(try encoder.encode(pcm) == fresh.encode(pcm))
        #expect(encoder.previousGainIndex > 0)
    }

    /// Exercises hard payload admission, explicit hybrid reserve, prefix/suffix entropy
    /// composition and atomic errors. A successful shared stream leaves finalization to
    /// its owner and reproduces channel PCM after surrounding symbols are consumed.
    @Test
    func boundedSharedEntropyAndFailureAtomicity() throws {
        var encoder = try SILKMonoEncoder(sampleRate: 16_000)
        let pcm = samples(count: encoder.sampleCount, rate: 16_000, pattern: 1)
        let pristine = encoder
        var entropy = try OpusRangeEncoder(frameByteCount: 256)
        try entropy.encodeBit(true, logProbability: 2)
        let range = entropy.finalRange
        #expect(throws: SILKMonoEncoderError.payloadBudgetExceeded) {
            try encoder.encodePayload(pcm, to: &entropy, maximumBits: 1)
        }
        #expect(encoder.previousGainIndex == 0)
        #expect(entropy.operationCount == 1)
        #expect(entropy.finalRange == range)
        for limit in [0, -1, 2_049, Int.max] {
            #expect(throws: SILKMonoEncoderError.invalidPayloadBitLimit) { try encoder.encodePayload(pcm, to: &entropy, maximumBits: limit) }
            #expect(entropy.operationCount == 1)
        }
        var empty = try OpusRangeEncoder(frameByteCount: 0)
        #expect(throws: SILKMonoEncoderError.invalidPayloadBitLimit) { try encoder.encodePayload(pcm, to: &empty) }
        var limited = try OpusRangeEncoder(frameByteCount: 256, maximumOperations: 1)
        #expect(throws: OpusRangeCodingError.operationLimitExceeded) { try encoder.encodePayload(pcm, to: &limited) }
        #expect(limited.operationCount == 0)
        let result = try encoder.encodePayload(pcm, to: &entropy, maximumBits: 768)
        #expect(result.bitsUsed <= 768)
        try entropy.encodeRawBits(17, count: 5)
        var decoder = try OpusRangeDecoder(frame: entropy.finalize())
        #expect(try decoder.decodeBit(logProbability: 2))
        #expect(try decoder.decodeBit(logProbability: 1))
        #expect(try !decoder.decodeBit(logProbability: 1))
        var channel = try SILKFrameDecoder(sampleRate: 16_000, frameDurationMilliseconds: 20)
        let decoded = try channel.decode(from: &decoder, voiceActivity: true)
        #expect(decoded.pcm == result.reconstructedPCM)
        #expect(decoded.parameters == result.parameters)
        #expect(try decoder.decodeRawBits(count: 5) == 17)
        var fresh = pristine
        var freshEntropy = try OpusRangeEncoder(frameByteCount: 256)
        try freshEntropy.encodeBit(true, logProbability: 2)
        #expect(try fresh.encodePayload(pcm, to: &freshEntropy, maximumBits: 768) == result)
        for rate in [8_000, 12_000, 16_000] {
            var bounded = try SILKMonoEncoder(sampleRate: rate, maximumPayloadBytes: 32)
            var admitted = 0
            for pattern in 0..<6 {
                let before = bounded
                let input = samples(count: bounded.sampleCount, rate: rate, pattern: pattern)
                do {
                    let output = try bounded.encode(input)
                    #expect(output.packet.data.count <= 33)
                    admitted += 1
                } catch SILKMonoEncoderError.payloadBudgetExceeded {
                    var reference = before
                    #expect(throws: SILKMonoEncoderError.payloadBudgetExceeded) { try reference.encode(input) }
                    let silence = Array(repeating: Int16(0), count: bounded.sampleCount)
                    #expect(try bounded.encode(silence) == reference.encode(silence))
                }
            }
            #expect(admitted > 0)
        }
    }

    /// Produces bounded deterministic PCM patterns without timers, devices or randomness.
    /// - Parameters:
    ///   - count: One legal internal frame sample count.
    ///   - rate: Internal sample rate determining tone phase, in hertz.
    ///   - pattern: Zero silence, one tone, two extrema, three ramp, four noise, five DC.
    /// - Returns: Exactly `count` PCM16 values spanning quiet, correlated and extreme input.
    private func samples(count: Int, rate: Int, pattern: Int) -> [Int16] {
        var state = UInt32(7)
        return (0..<count).map { sample in
            switch pattern {
            case 0: return 0
            case 1: return Int16(10_000 * sin(Double(sample) * 440 * 2 * Double.pi / Double(rate)))
            case 2: return sample.isMultiple(of: 2) ? .min : .max
            case 3: return Int16(clamping: (sample * 65_535 / (count - 1)) - 32_768)
            case 4:
                state = state &* 1_664_525 &+ 1_013_904_223
                return Int16(truncatingIfNeeded: state >> 16)
            default: return 1_234
            }
        }
    }
}
