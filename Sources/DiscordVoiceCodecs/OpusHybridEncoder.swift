import DiscordMedia
import Foundation

/// Admission failures of the bounded basic hybrid encoder.
public enum OpusHybridEncoderError: Error, Sendable, Equatable {
    case invalidDuration, unsupportedBandwidth, invalidSamples, invalidByteBudget
}

/// Basic owned mono/stereo SILK/CELT hybrid encoding at the mandatory 48kHz clock.
///
/// An explicitly adopted bandlimited streaming resampler supplies 16kHz SILK
/// input. The conservative SILK policy selects inactive/unvoiced/voiced spectral models;
/// CELT encodes high bands using long blocks and a shared arithmetic interval.
/// The resampler has 107 samples of 48kHz lookahead, so SILK is deliberately delayed
/// by 108 samples using a 36-sample 16kHz startup prefix. This basic encoder has no perceptual hybrid delay/phase
/// compensation, perceptual noise shaping, transient analysis, DTX or
/// rate-control quality claim. It emits interoperable standard hybrid syntax;
/// complete encoder qualification remains separate from that syntax evidence.
/// Optional FEC retains the preceding active SILK channels for following-packet
/// recovery; the missing CELT high band still requires explicit concealment.
///
/// Duration/bandwidth are fixed, mutation is synchronous and caller-serialized,
/// histories are bounded, copies fork independent streams, and construction starts
/// no tasks, device work or I/O. This owner imports neither Voice nor transport.
public struct OpusHybridEncoder: Sendable {
    public let frameSampleCount: Int
    public let channelCount: Int
    public let bandwidth: OpusBandwidth
    public let enableInBandFEC: Bool
    private var silk: SILKMonoEncoder
    private var stereo: SILKStereoEncoder
    private var celt: CELTFrameEncoder
    private var resampler: PCMBandlimitedResampler
    private var lowSamples: [Int16]
    private let toc: UInt8

    /// Validates the fixed hybrid stream format without acquiring external resources.
    /// - Parameters:
    ///   - frameSampleCount: Exactly 480 or 960 samples/channel at 48kHz.
    ///   - channelCount: Exactly one or two coded/output channels; default one.
    ///   - bandwidth: Superwideband or fullband; defaults to fullband.
    ///   - enableInBandFEC: Default false. True retains preceding active SILK
    ///     channels as next-packet LBRR. Redundancy shares the same explicit budget;
    ///     insufficient capacity rejects atomically instead of omitting that policy.
    /// - Throws: `invalidDuration`, `unsupportedBandwidth`, or component errors.
    public init(frameSampleCount: Int = 960, channelCount: Int = 1, bandwidth: OpusBandwidth = .fullband,
                enableInBandFEC: Bool = false) throws {
        guard [480, 960].contains(frameSampleCount) else { throw OpusHybridEncoderError.invalidDuration }
        guard bandwidth == .superwideband || bandwidth == .fullband else { throw OpusHybridEncoderError.unsupportedBandwidth }
        guard (1...2).contains(channelCount) else { throw CELTSynthesisError.invalidChannelCount }
        self.frameSampleCount = frameSampleCount
        self.channelCount = channelCount
        self.bandwidth = bandwidth
        self.enableInBandFEC = enableInBandFEC
        silk = try SILKMonoEncoder(sampleRate: 16_000, frameDurationMilliseconds: frameSampleCount / 48,
                                   enableInBandFEC: enableInBandFEC)
        stereo = try SILKStereoEncoder(sampleRate: 16_000, frameDurationMilliseconds: frameSampleCount / 48,
                                       enableInBandFEC: enableInBandFEC)
        celt = try CELTFrameEncoder(frameSampleCount: frameSampleCount, channelCount: channelCount, startBand: 17,
                                   endBand: bandwidth == .fullband ? 21 : 19)
        let input = try PCMFormat(sampleRate: 48_000, channelCount: channelCount)
        resampler = try PCMBandlimitedResampler(inputFormat: input, outputSampleRate: 16_000)
        lowSamples = Array(repeating: 0, count: 36 * channelCount)
        let configuration = (bandwidth == .fullband ? 14 : 12) + (frameSampleCount == 960 ? 1 : 0)
        toc = UInt8(configuration << 3 | (channelCount == 2 ? 4 : 0))
    }

    /// Resets all low/high-band analysis and prediction to their initial stream state.
    /// Pending converter/transform tails are discarded; already returned packets remain
    /// independent. No device, task, entropy operation or external resource is touched.
    public mutating func reset() {
        silk.reset()
        stereo.reset()
        celt.reset()
        resampler.reset()
        lowSamples = Array(repeating: 0, count: 36 * channelCount)
    }

    /// Encodes one normalized interleaved frame into standard single-payload hybrid packing.
    /// - Parameters:
    ///   - samples: Exactly `frameSampleCount * channelCount` finite normalized `-1...1` PCM.
    ///   - packetByteCount: Exact returned size including the TOC, in `65...1276`.
    ///     SILK receives at most three quarters of the payload budget; remaining bits
    ///     encode the high band. A budget too small for valid SILK is rejected atomically.
    /// - Returns: Standard Opus hybrid packet including the TOC and shared finalized
    ///   SILK/CELT bytes. Successful calls advance all bounded converter/codec histories.
    /// - Throws: `invalidSamples`, `invalidByteBudget`, or component budget/analysis
    ///   errors. Every failure leaves the full encoder unchanged; callers may retry
    ///   the same input with a larger explicit budget. No asynchronous work occurs.
    public mutating func encode(_ samples: [Float], packetByteCount: Int = 160) throws -> Data {
        guard samples.count == frameSampleCount * channelCount,
              samples.allSatisfy({ $0.isFinite && (-1...1).contains($0) }) else { throw OpusHybridEncoderError.invalidSamples }
        guard (65...1_276).contains(packetByteCount) else { throw OpusHybridEncoderError.invalidByteBudget }
        var working = self
        let format = try PCMFormat(sampleRate: 48_000, channelCount: channelCount)
        let converted = try working.resampler.process(PCMBuffer(format: format, samples: samples))
        working.lowSamples.append(contentsOf: converted.flatMap(\.samples).map { Int16(clamping: Int(($0 * 32768).rounded())) })
        let lowCount = frameSampleCount / 3 * channelCount
        guard working.lowSamples.count >= lowCount else { throw OpusHybridEncoderError.invalidSamples }
        let low = Array(working.lowSamples.prefix(lowCount))
        working.lowSamples.removeFirst(lowCount)
        var entropy = try OpusRangeEncoder(frameByteCount: packetByteCount - 1)
        if channelCount == 1 {
            _ = try working.silk.encodePayload(low, to: &entropy, maximumBits: (packetByteCount - 1) * 6)
        } else {
            _ = try working.stereo.encodePayload(low, to: &entropy, maximumBits: (packetByteCount - 1) * 6)
        }
        if entropy.bitsUsed + 37 <= entropy.frameByteCount * 8 {
            try entropy.encodeBit(false, logProbability: 12)
        }
        let high = try working.celt.encode(samples, into: &entropy)
        self = working
        return Data([toc]) + high.bytes
    }
}
