import Foundation
import Testing
@testable import DiscordVoiceCodecs

/// Verifies adaptive encoder decisions through entropy fields and decoded PCM,
/// rather than exposing private detector or analysis histories for testing.
@Suite("CELT adaptive encoder analysis")
struct CELTEncoderAnalysisTests {
    /// Inputs and expected PCM/ranges originate from an independently compiled
    /// official scalar decoder, with no native library dependency during tests.
    private struct Fixture: Decodable {
        let input: Input
        let encodedOutput: [Output]
        struct Input: Decodable { let c: Int; let frames: [Frame] }
        struct Frame: Decodable {
            let n: Int; let end: Int; let bytes: Int; let intra: Bool; let pcm: String
        }
        struct Output: Decodable {
            let raw: [UInt8]; let range: UInt32; let pcm: String
        }
    }

    /// Exact owned adaptive packets are decoded by the pinned independent official
    /// Opus decoder. Stored PCM checks short-transform ordering/scale, long/short
    /// overlap transitions, trim and anti-collapse across every transient duration
    /// and both layouts. This establishes interoperability, not perceptual quality.
    /// - Throws: Fixture/codec failures invalidate the independent regression.
    @Test func adaptivePacketsToOfficialDecoder() throws {
        let fixtures = try JSONDecoder().decode([Fixture].self, from: Data(CELTAdaptiveOracleFixtures.json.utf8))
        #expect(fixtures.count == 6)
        var transients = 0
        for fixture in fixtures {
            let first = try #require(fixture.input.frames.first)
            var encoder = try CELTFrameEncoder(frameSampleCount: first.n, channelCount: fixture.input.c,
                endBand: first.end, analysisPolicy: .adaptive)
            var decoder = try CELTFrameDecoder(channelCount: fixture.input.c)
            #expect(fixture.input.frames.count == fixture.encodedOutput.count)
            for (input, expected) in zip(fixture.input.frames, fixture.encodedOutput) {
                let encoded = try encoder.encode(try unpack(input.pcm), frameByteCount: input.bytes, intra: input.intra)
                #expect(Array(encoded.bytes) == expected.raw && encoded.finalRange == expected.range)
                let decoded = try decoder.decode(encoded.bytes, frameSampleCount: input.n, endBand: input.end)
                let pcm = try unpack(expected.pcm)
                let scale = max(1, pcm.map(abs).max() ?? 0)
                #expect(decoded.samples.count == pcm.count && decoded.finalRange == expected.range)
                #expect(zip(decoded.samples, pcm).allSatisfy { actual, value in
                    actual.isFinite && value.isFinite && abs(actual - value) <= 3e-6 * scale + 8e-6 * abs(value)
                })
                #expect(decoded.isTransient == encoded.isTransient)
                if encoded.isTransient { transients += 1 }
            }
        }
        #expect(transients >= 12)
    }

    /// A sudden middle-frame impulse in either channel selects real short MDCTs
    /// across all supported durations/bandwidths; entropy accounting and sequential
    /// recovery remain consistent with the complete independent decoder owner.
    /// - Throws: Codec/header failures indicate an admitted syntax regression.
    @Test func transientOnsetsAndOrdinaryRecovery() throws {
        for size in [240, 480, 960] {
            for channels in 1...2 {
                for end in [13, 17, 19, 21] {
                    for onsetChannel in 0..<channels {
                        var encoder = try CELTFrameEncoder(frameSampleCount: size, channelCount: channels,
                            endBand: end, analysisPolicy: .adaptive)
                        var decoder = try CELTFrameDecoder(channelCount: channels)
                        #expect(encoder.analysisPolicy == .adaptive)
                        let silence = Array(repeating: Float(0), count: size * channels)
                        let startup = try encoder.encode(silence, frameByteCount: 160)
                        #expect(!startup.isTransient)
                        _ = try decoder.decode(startup.bytes, frameSampleCount: size, endBand: end)
                        var impulse = silence
                        impulse[(size / 2) * channels + onsetChannel] = 0.8
                        let encoded = try encoder.encode(impulse, frameByteCount: 160)
                        #expect(encoded.isTransient)
                        let decoded = try decoder.decode(encoded.bytes, frameSampleCount: size, endBand: end)
                        #expect(decoded.isTransient && decoded.finalRange == encoded.finalRange)
                        #expect(decoded.bitsUsed == encoded.bitsUsed && decoded.fractionalBitsUsed == encoded.fractionalBitsUsed)
                        #expect(decoded.samples.count == impulse.count && decoded.samples.allSatisfy(\.isFinite))
                        #expect(decoded.samples.contains { abs($0) > 1e-5 })
                        for phase in 0..<4 {
                            let ordinary = tone(size: size, channels: channels, frequency: 440, phase: phase)
                            let next = try encoder.encode(ordinary, frameByteCount: 160)
                            let recovered = try decoder.decode(next.bytes, frameSampleCount: size, endBand: end)
                            #expect(recovered.finalRange == next.finalRange && recovered.samples.allSatisfy(\.isFinite))
                            if phase == 3 { #expect(!next.isTransient) }
                        }
                    }
                }
            }
        }
    }

    /// Very low physical budgets retain long blocks, and LM=0 has no transient
    /// syntax. Silence/tiny noise cannot invent an onset from numerical floors.
    /// - Throws: Coding failures on admitted extreme inputs fail the regression.
    @Test func lowBudgetShortDurationSilenceAndNarrowBand() throws {
        for size in [120, 240, 480, 960] {
            for channels in 1...2 {
                for end in [1, 21] {
                    var encoder = try CELTFrameEncoder(frameSampleCount: size, channelCount: channels,
                        endBand: end, analysisPolicy: .adaptive)
                    var decoder = try CELTFrameDecoder(channelCount: channels)
                    for amplitude: Float in [0, 1e-10, 0.8] {
                        var samples = Array(repeating: Float(0), count: size * channels)
                        samples[(size / 2) * channels + channels - 1] = amplitude
                        let encoded = try encoder.encode(samples, frameByteCount: 2)
                        let decoded = try decoder.decode(encoded.bytes, frameSampleCount: size, endBand: end)
                        #expect(!encoded.isTransient && !decoded.isTransient)
                        #expect(encoded.bytes.count == 2 && encoded.bitsUsed <= 16)
                        #expect(encoded.finalRange == decoded.finalRange && decoded.samples.allSatisfy(\.isFinite))
                    }
                    encoder.reset()
                    let zero = try encoder.encode(Array(repeating: 0, count: size * channels), frameByteCount: 120)
                    #expect(!zero.isTransient)
                }
            }
        }
    }

    /// Pure sustained low-frequency tones remain long blocks after warm overlap,
    /// avoiding their partial-cycle energy valleys being classified as attacks.
    /// - Throws: Fixed-format stream failures indicate analysis/transform regressions.
    @Test func sustainedLowFrequencyTones() throws {
        for size in [240, 480, 960] {
            for channels in 1...2 {
                for frequency: Double in [0, 40, 80, 120, 180, 440] {
                    var encoder = try CELTFrameEncoder(frameSampleCount: size, channelCount: channels,
                        analysisPolicy: .adaptive)
                    for phase in 0..<4 {
                        let encoded = try encoder.encode(tone(size: size, channels: channels,
                            frequency: frequency, phase: phase), frameByteCount: 160)
                        if phase >= 2 { #expect(!encoded.isTransient) }
                    }
                }
            }
        }
    }

    /// Onsets at either frame boundary remain visible through the shared overlap,
    /// and opposing spectral tilts select different allocation directions without
    /// increasing packet storage. These decisions test the analysis behavior rather
    /// than demanding identity with a particular reference encoder policy.
    /// - Throws: Admitted encoding/header failures indicate an analysis regression.
    @Test func boundaryOnsetsAndSpectralTilt() throws {
        for size in [240, 480, 960] {
            for channels in 1...2 {
                for position in [0, size - 1] {
                    var encoder = try CELTFrameEncoder(frameSampleCount: size, channelCount: channels,
                        analysisPolicy: .adaptive)
                    var samples = Array(repeating: Float(0), count: size * channels)
                    samples[position * channels + channels - 1] = 0.8
                    #expect(try encoder.encode(samples, frameByteCount: 160).isTransient)
                }
            }
        }
        var low = try CELTFrameEncoder(frameSampleCount: 960, analysisPolicy: .adaptive)
        var high = low
        let lowFrame = try low.encode(tone(size: 960, channels: 1, frequency: 440, phase: 0), frameByteCount: 160)
        let highFrame = try high.encode(tone(size: 960, channels: 1, frequency: 12_000, phase: 0), frameByteCount: 160)
        let lowTrim = try allocationHeader(lowFrame.bytes, size: 960).allocationTrim
        let highTrim = try allocationHeader(highFrame.bytes, size: 960).allocationTrim
        #expect(lowTrim > highTrim)
        #expect(lowFrame.bytes.count == highFrame.bytes.count)
    }

    /// The adaptive allocation header reacts to actual remaining bitrate while
    /// the fixed policy retains neutral trim. Shared hybrid-style prefix syntax
    /// reduces rate authority without changing the physical frame size.
    /// - Throws: Header parsing/coding errors indicate allocation disagreement.
    @Test func rateAndSharedBudgetAllocationTrim() throws {
        let size = 960
        let silence = Array(repeating: Float(0), count: size)
        var low = try CELTFrameEncoder(frameSampleCount: size, analysisPolicy: .adaptive)
        var high = low
        let lowFrame = try low.encode(silence, frameByteCount: 80)
        let highFrame = try high.encode(silence, frameByteCount: 240)
        let lowTrim = try allocationHeader(lowFrame.bytes, size: size).allocationTrim
        let highTrim = try allocationHeader(highFrame.bytes, size: size).allocationTrim
        #expect(lowTrim + 1 == highTrim)
        var fixed = try CELTFrameEncoder(frameSampleCount: size)
        let fixedFrame = try fixed.encode(silence, frameByteCount: 80)
        #expect(try allocationHeader(fixedFrame.bytes, size: size).allocationTrim == 5)
        var hybrid = try CELTFrameEncoder(frameSampleCount: size, startBand: 17, analysisPolicy: .adaptive)
        var fullHybrid = hybrid
        let fullHybridFrame = try fullHybrid.encode(silence, frameByteCount: 240)
        let fullHybridTrim = try allocationHeader(fullHybridFrame.bytes, size: size, start: 17).allocationTrim
        var shared = try OpusRangeEncoder(frameByteCount: 240)
        for _ in 0..<40 { try shared.encodeRawBits(0, count: 24) }
        let combined = try hybrid.encode(silence, into: &shared)
        var reader = try OpusRangeDecoder(frame: combined.bytes)
        for _ in 0..<40 { #expect(try reader.decodeRawBits(count: 24) == 0) }
        let header = try CELTFrameHeader(frameSampleCount: size, startBand: 17)
        let prefix = try header.decodePrefix(from: &reader)
        let energy = try CELTEnergyQuantizer(frameSampleCount: size, startBand: 17)
        _ = try energy.decodeCoarse(previous: Array(repeating: 0, count: 21), from: &reader)
        let fields = try header.decodeAfterCoarse(isTransient: prefix.isTransient, from: &reader)
        #expect(fields.allocationTrim + 1 == fullHybridTrim && !prefix.isTransient)
    }

    /// Adaptive detector/short overlap state obeys the same all-or-nothing failure,
    /// value-copy and reset contract as fixed encoding, including a throw after
    /// preemphasis and prefix coding when the operation budget is exhausted.
    /// - Throws: Setup/recovery errors indicate a failure-atomicity regression.
    @Test func adaptiveRollbackCopyAndReset() throws {
        var encoder = try CELTFrameEncoder(frameSampleCount: 960, channelCount: 2, analysisPolicy: .adaptive)
        var onset = Array(repeating: Float(0), count: 1920)
        onset[960] = 0.9
        let startup = try encoder.encode(onset, frameByteCount: 160)
        #expect(startup.isTransient)
        var baseline = encoder
        var entropy = try OpusRangeEncoder(frameByteCount: 160, maximumOperations: 3)
        #expect(throws: OpusRangeCodingError.operationLimitExceeded) {
            try encoder.encode(onset, into: &entropy)
        }
        #expect(entropy.operationCount == 0 && entropy.bitsUsed == 1)
        var invalid = onset
        invalid[1919] = .nan
        #expect(throws: CELTFrameEncoderError.invalidSamples) { try encoder.encode(invalid, frameByteCount: 160) }
        #expect(try encoder.encode(onset, frameByteCount: 160) == baseline.encode(onset, frameByteCount: 160))
        encoder.reset()
        #expect(try encoder.encode(onset, frameByteCount: 160) == startup)
    }

    /// A shared arithmetic interval with exactly zero remaining authority describes
    /// implicit silence to a decoder. Rejecting it before any CELT history commit
    /// prevents the encoder from predicting a subsequent audible frame from an
    /// envelope that its peer never received. Both analysis policies reject atomically.
    /// - Throws: Valid setup/recovery errors indicate an entropy-ownership regression.
    @Test func exhaustedSharedPrefixRejectsWithoutAdvancingHistory() throws {
        for policy: CELTEncoderAnalysisPolicy in [.fixed, .adaptive] {
            var encoder = try CELTFrameEncoder(frameSampleCount: 480, analysisPolicy: policy)
            let pcm = tone(size: 480, channels: 1, frequency: 440, phase: 0)
            _ = try encoder.encode(pcm, frameByteCount: 80)
            var control = encoder
            var shared = try OpusRangeEncoder(frameByteCount: 80)
            for _ in 0..<25 { try shared.encodeRawBits(0, count: 25) }
            try shared.encodeRawBits(0, count: 14)
            #expect(shared.bitsUsed == 640)
            let range = shared.finalRange
            let operations = shared.operationCount
            let fraction = shared.fractionalBitsUsed
            #expect(throws: CELTFrameEncoderError.entropyBudgetExceeded) {
                try encoder.encode(pcm, into: &shared)
            }
            #expect(shared.bitsUsed == 640 && shared.finalRange == range
                && shared.operationCount == operations && shared.fractionalBitsUsed == fraction)
            #expect(try encoder.encode(pcm, frameByteCount: 80) == control.encode(pcm, frameByteCount: 80))
        }
    }

    /// Packet policy propagates the analysis choice and exact final range; failed
    /// requests preserve the last successful range, and reset restores zero.
    /// - Throws: Valid packet/frame failures indicate metadata propagation regressions.
    @Test func packetAnalysisAndFinalRange() throws {
        var encoder = try CELTPacketEncoder(frameSampleCount: 960, channelCount: 2, analysisPolicy: .adaptive)
        #expect(encoder.analysisPolicy == .adaptive && encoder.finalRange == 0)
        var pcm = Array(repeating: Float(0), count: 1920)
        pcm[961] = 0.8
        let data = try encoder.encode(pcm, packetByteCount: 161)
        var decoder = try CELTPacketDecoder(channelCount: 2)
        let decoded = try #require(try decoder.decode(data).first)
        #expect(decoded.isTransient && decoded.finalRange == encoder.finalRange)
        let range = encoder.finalRange
        #expect(throws: CELTPacketCodecError.invalidPacketByteCount) { try encoder.encode(pcm, packetByteCount: 2) }
        #expect(throws: CELTFrameEncoderError.invalidSamples) { try encoder.encode([], packetByteCount: 161) }
        #expect(encoder.finalRange == range)
        encoder.reset()
        #expect(encoder.finalRange == 0 && encoder.analysisPolicy == .adaptive)
        #expect(try encoder.encode(pcm, packetByteCount: 161) == data)
    }

    /// Reads actual allocation choices after the full coarse-energy syntax.
    /// - Parameters:
    ///   - data: Encoded mono frame with initial zero coarse-energy history.
    ///   - size: Exact sample count encoded by the caller.
    ///   - start: Inclusive active band, zero by default or 17 for hybrid tests.
    /// - Returns: Actual entropy-admitted allocation fields, including trim.
    /// - Throws: Decoder/header errors propagate as test failures.
    private func allocationHeader(_ data: Data, size: Int, start: Int = 0) throws -> CELTFrameAllocationHeader {
        var decoder = try OpusRangeDecoder(frame: data)
        let header = try CELTFrameHeader(frameSampleCount: size, startBand: start)
        let prefix = try header.decodePrefix(from: &decoder)
        let quantizer = try CELTEnergyQuantizer(frameSampleCount: size, startBand: start)
        _ = try quantizer.decodeCoarse(previous: Array(repeating: 0, count: 21), from: &decoder)
        return try header.decodeAfterCoarse(isTransient: prefix.isTransient, from: &decoder)
    }

    /// Reads independent scalar PCM without alignment or host-endianness assumptions.
    /// - Parameter base64: Complete explicitly little-endian float32 sample bytes.
    /// - Returns: Owned finite input or expected-output samples in their original order.
    /// - Throws: Test requirement failures for malformed base64 or partial float words.
    private func unpack(_ base64: String) throws -> [Float] {
        let data = try #require(Data(base64Encoded: base64))
        try #require(data.count.isMultiple(of: 4))
        return stride(from: 0, to: data.count, by: 4).map { offset in
            let bits = UInt32(data[offset]) | UInt32(data[offset + 1]) << 8
                | UInt32(data[offset + 2]) << 16 | UInt32(data[offset + 3]) << 24
            return Float(bitPattern: bits)
        }
    }

    /// Creates deterministic continuous mono/stereo tones independently of coding.
    /// - Parameters:
    ///   - size: Valid samples/channel in the test stream.
    ///   - channels: One or two channels, with a stable stereo phase offset.
    ///   - frequency: Tone frequency in Hz; zero supplies a constant signal.
    ///   - phase: Consecutive frame index, preserving time across calls.
    /// - Returns: Normalized finite interleaved values within ±0.2.
    private func tone(size: Int, channels: Int, frequency: Double, phase: Int) -> [Float] {
        (0..<(size * channels)).map { index in
            frequency == 0 ? 0.2 : Float(sin(2 * .pi * frequency * Double(index / channels + phase * size) / 48_000
                + Double(index % channels) * 0.7)) * 0.2
        }
    }
}
