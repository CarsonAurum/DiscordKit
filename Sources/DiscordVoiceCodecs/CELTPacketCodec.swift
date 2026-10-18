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
/// There is no channel conversion, SILK/hybrid transition, packet-loss concealment,
/// FEC or transport ownership. A zero/one-byte frame requires such an enclosing
/// policy and is rejected by the raw frame decoder. No construction or call starts
/// tasks, device work or I/O; callers serialize mutable access.
public struct CELTPacketDecoder: Sendable {
    public let channelCount: Int
    private var decoder: CELTFrameDecoder

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
    ///   ranges and accounting. Concatenate samples in order for the packet's PCM.
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
        var output: [CELTDecodedFrame] = []
        output.reserveCapacity(packet.frameRanges.count)
        for range in packet.frameRanges {
            output.append(try working.decode(Data(packet.data[range]),
                frameSampleCount: packet.frameSampleCount, endBand: band))
        }
        decoder = working
        return output
    }

    /// Discards every predictor, overlap, pitch, anti-collapse and deemphasis history.
    /// This synchronous operation preserves the configured channel count and opens no devices.
    public mutating func reset() { decoder.reset() }
}
