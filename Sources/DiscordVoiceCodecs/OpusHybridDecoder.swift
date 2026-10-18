import Foundation

/// Admission errors specific to ordinary shared-entropy SILK/CELT hybrid decoding.
public enum OpusHybridDecoderError: Error, Sendable, Equatable {
    case unsupportedMode, channelCountMismatch, invalidRedundancy, invalidPayloadSize
}

/// One ordinary hybrid Opus payload at the mandatory 48kHz clock.
public struct OpusHybridDecodedFrame: Sendable, Equatable {
    public let samples: [Float]
    public let frameSampleCount: Int
    public let channelCount: Int
    public let finalRange: UInt32
    public let redundancyByteCount: Int
    public let celtToSilkRedundancy: Bool
}

/// Owned ordinary hybrid decoding with a shared SILK/CELT arithmetic interval.
///
/// SILK reconstructs the low band at 16kHz, resamples to 48kHz, then CELT decodes
/// bands 17 through the signaled superwide/full bandwidth from the same entropy
/// state. Independently coded transition redundancy is excluded from the CELT raw
/// tail and mixed with the normative squared overlap window. No native codec,
/// transport, device, I/O or tasks are selected. Construction starts no work.
///
/// Coded/output channels are fixed. This owner supports hybrid-to-hybrid duration
/// and bandwidth changes, all ordinary packing/padding and transition redundancy
/// within hybrid. It does not yet own SILK-only/CELT-only mode switches, FEC,
/// loss/DTX handling, output channel conversion or complete Opus conformance.
/// Mutable access must be serialized; copies fork independent bounded histories.
public struct OpusHybridDecoder: Sendable {
    public let channelCount: Int
    private var mono: SILKMonoDecoder
    private var stereo: SILKStereoDecoder
    private var celt: CELTFrameDecoder

    /// Creates idle zero-history SILK and CELT owners with no external resources.
    /// - Parameter channelCount: Exactly one or two coded/output channels; default one.
    /// - Throws: `CELTSynthesisError.invalidChannelCount` for another layout.
    public init(channelCount: Int = 1) throws {
        guard (1...2).contains(channelCount) else { throw CELTSynthesisError.invalidChannelCount }
        self.channelCount = channelCount
        mono = try SILKMonoDecoder(sampleRate: 16_000)
        stereo = try SILKStereoDecoder(sampleRate: 16_000)
        celt = try CELTFrameDecoder(channelCount: channelCount)
    }

    /// Discards every SILK/CELT predictor, resampler, overlap and redundancy history.
    /// Pending tails are discarded; the configured channel layout remains unchanged.
    /// This synchronous operation has no external side effects or failure conditions.
    public mutating func reset() {
        mono.reset()
        stereo.reset()
        celt.reset()
    }

    /// Decodes every payload in one ordinary hybrid packet, committing atomically.
    /// - Parameter data: Complete Opus TOC, packing, payloads and optional padding,
    ///   at most 65,536 bytes and 120ms as enforced by `OpusPacket`.
    /// - Returns: Ordered payload results with interleaved normalized 48kHz float
    ///   PCM, exact final range and transition redundancy metadata. PCM may exceed
    ///   unity, matching the floating-point decoder domain without implicit clipping.
    /// - Throws: Packet/parser errors, `unsupportedMode`, `channelCountMismatch`,
    ///   `invalidRedundancy`, `invalidPayloadSize` or component failures. All stream
    ///   histories remain unchanged even if a later packed payload fails. Zero/one
    ///   byte loss/DTX payloads are explicitly rejected, requiring a loss policy.
    public mutating func decode(_ data: Data) throws -> [OpusHybridDecodedFrame] {
        let packet = try OpusPacket(data)
        guard packet.mode == .hybrid else { throw OpusHybridDecoderError.unsupportedMode }
        guard packet.channelCount == channelCount else { throw OpusHybridDecoderError.channelCountMismatch }
        var working = self
        var result: [OpusHybridDecodedFrame] = []
        for range in packet.frameRanges {
            result.append(try working.decodePayload(Data(packet.data[range]),
                frameSampleCount: packet.frameSampleCount,
                endBand: packet.bandwidth == .fullband ? 21 : 19))
        }
        self = working
        return result
    }

    /// Decodes one admitted hybrid payload on a private whole-packet stream copy.
    /// - Parameters:
    ///   - payload: Two through 1,275 dense bytes including any redundancy suffix.
    ///   - frameSampleCount: Exactly 480 or 960 samples/channel, enforced by hybrid TOC.
    ///   - endBand: Exclusive upper hybrid band, 19 or 21 from the packet bandwidth.
    /// - Returns: Mixed low/high-band PCM with the main/redundant ranges XORed.
    /// - Throws: Size, redundancy, shared entropy or synthesis errors. The caller
    ///   discards this working copy on failure; no external state can be modified.
    private mutating func decodePayload(_ payload: Data, frameSampleCount: Int,
                                       endBand: Int) throws -> OpusHybridDecodedFrame {
        guard (2...1_275).contains(payload.count) else { throw OpusHybridDecoderError.invalidPayloadSize }
        var entropy = try OpusRangeDecoder(frame: payload)
        let low: [Int16]
        if channelCount == 1 {
            low = try mono.decodePayload(from: &entropy, durationMilliseconds: frameSampleCount / 48).pcm48k
        } else {
            low = try stereo.decodePayload(from: &entropy, durationMilliseconds: frameSampleCount / 48,
                                           codedChannelCount: 2).pcm48k
        }
        var redundantByteCount = 0
        var celtToSilk = false
        if entropy.bitsUsed + 37 <= payload.count * 8, try entropy.decodeBit(logProbability: 12) {
            celtToSilk = try entropy.decodeBit(logProbability: 1)
            redundantByteCount = Int(try entropy.decodeUniform(total: 256)) + 2
            guard redundantByteCount <= payload.count - 2 else { throw OpusHybridDecoderError.invalidRedundancy }
            try entropy.reduceStorage(to: payload.count - redundantByteCount)
        }
        let redundant = Data(payload.suffix(redundantByteCount))
        var redundantFrame: CELTDecodedFrame?
        if redundantByteCount > 0 && celtToSilk {
            redundantFrame = try celt.decode(redundant, frameSampleCount: 240, endBand: endBand)
        }
        let high = try celt.decode(from: &entropy, frameSampleCount: frameSampleCount,
                                   startBand: 17, endBand: endBand)
        var samples = zip(low, high.samples).map { Float($0.0) / 32768 + $0.1 }
        if redundantByteCount > 0 && !celtToSilk {
            celt.reset()
            redundantFrame = try celt.decode(redundant, frameSampleCount: 240, endBand: endBand)
            let offset = (frameSampleCount - 120) * channelCount
            fade(from: samples, sourceOffset: offset, to: redundantFrame!.samples,
                 targetOffset: 120 * channelCount, output: &samples, outputOffset: offset)
        }
        if let redundantFrame, celtToSilk {
            for index in 0..<(120 * channelCount) { samples[index] = redundantFrame.samples[index] }
            fade(from: redundantFrame.samples, sourceOffset: 120 * channelCount,
                 to: samples, targetOffset: 120 * channelCount,
                 output: &samples, outputOffset: 120 * channelCount)
        }
        return OpusHybridDecodedFrame(samples: samples, frameSampleCount: frameSampleCount,
            channelCount: channelCount, finalRange: high.finalRange ^ (redundantFrame?.finalRange ?? 0),
            redundancyByteCount: redundantByteCount, celtToSilkRedundancy: celtToSilk)
    }

    /// Applies the normative 2.5ms squared CELT window to two interleaved sources.
    /// - Parameters:
    ///   - from: Initial source, containing at least 120 samples after sourceOffset.
    ///   - sourceOffset: First scalar interleaved initial-source position.
    ///   - to: Final source, containing at least 120 samples after targetOffset.
    ///   - targetOffset: First scalar interleaved final-source position.
    ///   - output: Owned result with complete destination capacity; value semantics
    ///     permit either source to alias its pre-mutation contents safely.
    ///   - outputOffset: First scalar interleaved destination position.
    /// Exactly 120 samples per channel are replaced; no allocation escapes or I/O occurs.
    private func fade(from: [Float], sourceOffset: Int, to: [Float], targetOffset: Int,
                      output: inout [Float], outputOffset: Int) {
        for sample in 0..<120 {
            let inner = sin(0.5 * Double.pi * (Double(sample) + 0.5) / 120)
            let window = Float(sin(0.5 * Double.pi * inner * inner))
            let weight = window * window
            for channel in 0..<channelCount {
                let index = sample * channelCount + channel
                output[outputOffset + index] = weight * to[targetOffset + index]
                    + (1 - weight) * from[sourceOffset + index]
            }
        }
    }
}
