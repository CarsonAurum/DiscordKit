import Foundation

/// A valid Opus packet requests a mode/channel layout outside this CELT-only codec.
public enum CELTPacketCodecError: Error, Sendable, Equatable {
    case unsupportedBandwidth, unsupportedMode, channelCountMismatch, invalidPacketByteCount
}

/// Ordinary single-frame Opus packing over the basic owned CELT encoder.
///
/// This is independently adopted audio coding without transport, device or session
/// ownership. Duration, bandwidth and channels are fixed for a stream. The complete
/// quality/analysis limitations of `CELTFrameEncoder` apply; this is not a SILK/hybrid,
/// multistream, DTX, FEC or complete Opus encoder. Construction starts no work.
public struct CELTPacketEncoder: Sendable {
    public let frameSampleCount: Int
    public let channelCount: Int
    public let bandwidth: OpusBandwidth
    private var encoder: CELTFrameEncoder
    private let toc: UInt8

    /// Validates a standard CELT TOC and creates an idle audio encoder.
    /// - Parameters:
    ///   - frameSampleCount: Exactly 120, 240, 480 or 960 samples/channel at 48 kHz.
    ///   - channelCount: Exactly one or two coded channels; default one.
    ///   - bandwidth: Narrow, wide, superwide or fullband; default fullband.
    ///     Mediumband has no CELT TOC and is explicitly rejected.
    /// - Throws: `unsupportedBandwidth` or the frame encoder's format validation errors.
    public init(frameSampleCount: Int, channelCount: Int = 1, bandwidth: OpusBandwidth = .fullband) throws {
        let band: Int
        let configurationBase: Int
        switch bandwidth {
        case .narrowband: band = 13; configurationBase = 16
        case .wideband: band = 17; configurationBase = 20
        case .superwideband: band = 19; configurationBase = 24
        case .fullband: band = 21; configurationBase = 28
        case .mediumband: throw CELTPacketCodecError.unsupportedBandwidth
        }
        encoder = try CELTFrameEncoder(frameSampleCount: frameSampleCount, channelCount: channelCount, endBand: band)
        self.frameSampleCount = frameSampleCount
        self.channelCount = channelCount
        self.bandwidth = bandwidth
        let duration = frameSampleCount == 120 ? 0 : (frameSampleCount == 240 ? 1 : (frameSampleCount == 480 ? 2 : 3))
        toc = UInt8((configurationBase + duration) << 3 | (channelCount == 2 ? 4 : 0))
    }

    /// Encodes one normalized 48-kHz PCM frame and adds its standard packing-code-zero TOC.
    /// - Parameters:
    ///   - samples: Exactly `frameSampleCount * channelCount` finite interleaved
    ///     samples in `-1...1`. Input is not retained after the synchronous call.
    ///   - packetByteCount: Exact returned size in `3...1_276`, including one TOC byte.
    ///   - intra: Desired independent coarse envelope prediction; default false.
    /// - Returns: A complete structurally valid ordinary Opus packet. Successful calls
    ///   advance the underlying audio history; failed calls leave it unchanged.
    /// - Throws: `invalidPacketByteCount`, PCM validation or frame-coding errors.
    public mutating func encode(_ samples: [Float], packetByteCount: Int,
                                intra: Bool = false) throws -> Data {
        guard (3...1_276).contains(packetByteCount) else { throw CELTPacketCodecError.invalidPacketByteCount }
        let frame = try encoder.encode(samples, frameByteCount: packetByteCount - 1, intra: intra)
        return Data([toc]) + frame.bytes
    }

    /// Discards all analysis/prediction history while preserving the fixed TOC format.
    /// Pending audio tails are lost; callers explicitly drain or reset at discontinuities.
    public mutating func reset() { encoder.reset() }
}

/// Caller-driven CELT-only Opus packet decoding with atomic multi-frame admission.
///
/// All four ordinary packing codes and padding are accepted through `OpusPacket`.
/// Coded channel count is fixed; bandwidth/duration may change between packets.
/// There is no channel conversion, SILK/hybrid transition, FEC or transport ownership.
/// Explicit missing frames and zero/one-byte packed frames use CELT periodic/noise
/// concealment. Short-frame results have zero entropy accounting and final range,
/// with no signaled transient or silence flag. No construction or call starts
/// tasks, device work or I/O; callers serialize mutable access.
public struct CELTPacketDecoder: Sendable {
    public let channelCount: Int
    private var decoder: CELTFrameDecoder
    private var previousFrameSampleCount = 120
    private var previousEndBand = 21

    /// Creates an idle decoder with a fixed coded/output channel layout.
    /// - Parameter channelCount: Exactly one or two channels; default one.
    /// - Throws: `CELTSynthesisError.invalidChannelCount` for another channel count.
    public init(channelCount: Int = 1) throws {
        decoder = try CELTFrameDecoder(channelCount: channelCount)
        self.channelCount = channelCount
    }

    /// Decodes every frame of one bounded ordinary CELT Opus packet in wire order.
    /// - Parameter data: Complete Opus packet including TOC/packing/padding, bounded
    ///   by the parser to 65,536 bytes and at most 120 ms of output per channel.
    /// - Returns: One owned PCM result per packed frame, preserving individual final
    ///   ranges and accounting. Zero/one-byte frames select concealment, matching the
    ///   reference ordinary CELT loss rule; their final range and both bit counts are
    ///   zero and transient/silence flags are false because no such syntax was read.
    ///   Concatenate samples in order for the packet's PCM.
    ///   Output is normalized 48-kHz interleaved float PCM and can exceed unity.
    /// - Throws: Parser errors, `unsupportedMode` for SILK/hybrid,
    ///   `channelCountMismatch` or frame-decoder failures. The entire packet is
    ///   atomic: even a failure in its last frame advances no decoder history.
    public mutating func decode(_ data: Data) throws -> [CELTDecodedFrame] {
        let packet = try OpusPacket(data)
        guard packet.mode == .celt else { throw CELTPacketCodecError.unsupportedMode }
        guard packet.channelCount == channelCount else { throw CELTPacketCodecError.channelCountMismatch }
        let band: Int
        switch packet.bandwidth {
        case .narrowband: band = 13
        case .wideband: band = 17
        case .superwideband: band = 19
        case .fullband: band = 21
        case .mediumband: throw CELTPacketCodecError.unsupportedBandwidth
        }
        var working = decoder
        var workingEndBand = previousEndBand
        var output: [CELTDecodedFrame] = []
        output.reserveCapacity(packet.frameRanges.count)
        for range in packet.frameRanges {
            if range.count <= 1 {
                let concealed = try working.conceal(frameSampleCount: packet.frameSampleCount, endBand: workingEndBand)
                output.append(CELTDecodedFrame(samples: concealed.samples, frameSampleCount: packet.frameSampleCount,
                    channelCount: channelCount, finalRange: 0, bitsUsed: 0, fractionalBitsUsed: 0,
                    isTransient: false, isSilence: false))
            } else {
                output.append(try working.decode(Data(packet.data[range]),
                    frameSampleCount: packet.frameSampleCount, endBand: band))
                workingEndBand = band
            }
        }
        decoder = working
        previousFrameSampleCount = packet.frameSampleCount
        previousEndBand = workingEndBand
        return output
    }

    /// Synthesizes one explicitly missing ordinary CELT interval without constructing a packet.
    /// - Parameters:
    ///   - frameSampleCount: Exactly 120, 240, 480 or 960 samples/channel at 48 kHz.
    ///     The caller chooses the missing duration; no packet or wall-clock inference occurs.
    ///   - endBand: Optional exclusive active upper band in 1...21, normally 13/17/19/21
    ///     for narrow/wide/superwide/fullband. Nil uses the last received compressed
    ///     frame's band, or fullband 21 before reception. A missing/short payload does
    ///     not replace the last received bandwidth, matching ordinary Opus PLC.
    /// - Returns: Owned interleaved PCM, updated envelope/seed and explicit periodic/noise
    ///   diagnostics from the final concealed subframe. Following the ordinary Opus packet
    ///   loss policy, intervals longer than the last received TOC frame are synthesized in
    ///   subframes no longer than that duration; the startup duration is 120 samples. This
    ///   matters for LPC fading and recovery when packet duration changes. This advances
    ///   the same history used for subsequent received packets.
    /// - Throws: Synthesis configuration errors before any history changes. The bounded
    ///   synchronous call owns no network, task, timer or device and does not recover FEC.
    public mutating func conceal(frameSampleCount: Int, endBand: Int? = nil) throws -> CELTConcealedFrame {
        guard [120, 240, 480, 960].contains(frameSampleCount) else { throw CELTSynthesisError.invalidFrameSize }
        var working = decoder
        var output: [Float] = []
        output.reserveCapacity(frameSampleCount * channelCount)
        var last: CELTConcealedFrame?
        var remaining = frameSampleCount
        while remaining > 0 {
            let count = min(remaining, previousFrameSampleCount)
            let result = try working.conceal(frameSampleCount: count, endBand: endBand ?? previousEndBand)
            output += result.samples
            last = result
            remaining -= count
        }
        decoder = working
        let final = last!
        return CELTConcealedFrame(samples: output, bandLogEnergies: final.bandLogEnergies,
            seed: final.seed, usesNoise: final.usesNoise, lossDuration: final.lossDuration,
            pitchPeriod: final.pitchPeriod)
    }

    /// Discards every predictor, overlap, pitch, anti-collapse and deemphasis history.
    /// This synchronous operation preserves the configured channel count and opens no devices.
    public mutating func reset() {
        decoder.reset()
        previousFrameSampleCount = 120
        previousEndBand = 21
    }
}
