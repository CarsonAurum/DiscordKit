import DiscordMedia
import Foundation

/// Admission failures of the fixed-format, rate-bounded ordinary Opus encoder.
public enum OpusAudioEncoderError: Error, Sendable, Equatable {
    case invalidConfiguration, invalidBitrate, invalidPacketByteLimit, invalidSamples, invalidDTXPolicy
}

/// Explicit conservative silence gating for ordinary Opus discontinuous transmission.
///
/// RMS is measured over all interleaved input samples, without channel cancellation.
/// This is a signal-level policy, not a trained speech/music classifier. Choose a
/// threshold below the quietest wanted content. The RFC 6716 section 2.1.9 refresh
/// interval is fixed at 400ms. Transport clocks continue across suppressed intervals.
public struct OpusDTXPolicy: Sendable, Equatable {
    public let thresholdDBFS: Double
    public let hangoverMilliseconds: Int

    /// Validates a finite silence threshold and bounded talkspurt hangover.
    /// - Parameters:
    ///   - thresholdDBFS: RMS threshold in decibels relative to full scale, inclusive
    ///     `-120...(-20)`; default -80. Equality is inactive. This gate can suppress
    ///     quiet wanted content; applications must choose their own appropriate level.
    ///   - hangoverMilliseconds: Inactive duration retained as ordinary audio after
    ///     activity, inclusive `0...1000`; default 200. Whole frames round it upward.
    /// - Throws: `invalidDTXPolicy` for a nonfinite/out-of-range threshold or hangover.
    ///   The immutable policy owns no tasks, device, clock or external resources.
    public init(thresholdDBFS: Double = -80, hangoverMilliseconds: Int = 200) throws {
        guard thresholdDBFS.isFinite, (-120 ... -20).contains(thresholdDBFS),
              (0...1_000).contains(hangoverMilliseconds) else { throw OpusAudioEncoderError.invalidDTXPolicy }
        self.thresholdDBFS = thresholdDBFS
        self.hangoverMilliseconds = hangoverMilliseconds
    }
}

/// One bounded single-frame ordinary Opus result and its transmission decision.
public struct OpusAudioEncodedPacket: Sendable, Equatable {
    /// Complete single-frame packet. Suppressed intervals contain only their valid TOC.
    public let data: Data
    /// False only for a DTX interval the transport may omit while advancing its clock.
    public let shouldTransmit: Bool
    /// True when the output is a zero-payload DTX interval, not a refresh packet.
    public let isDTX: Bool
    /// Active/refresh packet allocation, including TOC; DTX never banks unused bytes.
    public let packetByteBudget: Int
    /// Arithmetic final range for transmitted audio; zero for a suppressed interval.
    public let finalRange: UInt32
}

/// Fixed-format ordinary SILK/CELT/hybrid encoding with bounded rate and DTX policies.
///
/// Every input frame is normalized 48kHz PCM. SILK explicitly uses an owned
/// bandlimited converter and a bounded startup silence prefix; its delay is
/// `ceil(converter.lookaheadFrames * internalRate / 48000)` internal-rate samples.
/// Mode, duration, bandwidth and layout remain fixed. A different format needs a new
/// owner: automatic mode switching, psychoacoustic equivalence to libopus, multistream
/// and hard realtime guarantees are not provided. CELT analysis is adaptive.
///
/// Ordinary packet allocations use exact fractional bit carry, including TOC but
/// excluding RTP/network headers. They differ by at most one byte and never exceed
/// the fixed cap. SILK raises quantization gain within this allocation, retries
/// oversized voiced models as ordinary unvoiced audio, and rejects audio it still
/// cannot fit after bounded scalar rate-distortion admission. The final sparse
/// excitation policy trades waveform fidelity for the requested finite allocation;
/// no retry silently exceeds the target or drops requested FEC.
/// DTX suppresses transmission after a level gate and hangover, with an ordinary
/// refresh at most every 400ms. Encoding still advances internal analysis on silent
/// frames, so this policy saves bandwidth rather than promising CPU savings. CELT
/// uses an independent envelope on refresh/resumption. Decoder PLC/CNG supplies the
/// omitted intervals; it need not match discarded encoder reconstruction bitwise.
///
/// Construction starts no I/O/tasks and links no native codec. Calls are synchronous;
/// callers serialize mutation, copies fork histories, and every failure preserves
/// codec, resampler, rate-carry and DTX state atomically. Storage stays frame-bounded.
public struct OpusAudioEncoder: Sendable {
    public let mode: OpusMode
    public let bandwidth: OpusBandwidth
    public let frameSampleCount: Int
    public let channelCount: Int
    public let maximumPacketByteCount: Int
    public let dtx: OpusDTXPolicy?
    public let enableInBandFEC: Bool
    /// Current total codec bit target per second, including TOC and excluding RTP.
    public private(set) var targetBitrate: Int
    private var celt: CELTPacketEncoder?
    private var hybrid: OpusHybridEncoder?
    private var mono: SILKMonoEncoder?
    private var stereo: SILKStereoEncoder?
    private var resampler: PCMBandlimitedResampler?
    private var lowSamples: [Int16] = []
    private var rateRemainder = 0
    private var inactiveSampleCount = 0
    private var samplesSinceRefresh = 0
    private var wasSuppressed = false
    private var hasEncodedFrame = false
    private let toc: UInt8
    private let minimumPacketByteCount: Int
    private let lowSampleRate: Int
    private let startupPrefixCount: Int

    /// Creates one fixed-format owned encoder without device or external work.
    /// - Parameters:
    ///   - mode: Explicit SILK, hybrid or CELT; default CELT.
    ///   - bandwidth: SILK accepts NB/MB/WB, hybrid SWB/FB, CELT NB/WB/SWB/FB;
    ///     default FB. No implicit downgrade changes the requested wire format.
    ///   - frameSampleCount: 48kHz samples/channel; SILK/hybrid accept 480/960,
    ///     CELT additionally accepts 120/240. Default 960 (20ms).
    ///   - channelCount: One or two interleaved channels, default one.
    ///   - targetBitrate: Total codec target `6000...512000` bits/second, default
    ///     64000. Its floor allocation must fit the mode minimum and its ceiling
    ///     must fit `maximumPacketByteCount`; otherwise construction rejects it.
    ///   - maximumPacketByteCount: Hard returned byte cap `3...1276`, default 1276.
    ///     Format minimums are CELT 3, SILK mono 17/stereo 33, and hybrid 65 bytes.
    ///     Passing admission does not guarantee SILK can encode every signal.
    ///   - dtx: Optional validated RMS/hangover policy; nil disables suppression.
    ///   - enableInBandFEC: Prior-active-frame SILK LBRR, default false. CELT rejects
    ///     true because its ordinary coding has no in-band FEC mechanism.
    /// - Throws: `invalidConfiguration`, `invalidPacketByteLimit`, `invalidBitrate`
    ///   or component format/table errors. No partial stream escapes on failure.
    public init(mode: OpusMode = .celt, bandwidth: OpusBandwidth = .fullband,
                frameSampleCount: Int = 960, channelCount: Int = 1,
                targetBitrate: Int = 64_000, maximumPacketByteCount: Int = 1_276,
                dtx: OpusDTXPolicy? = nil, enableInBandFEC: Bool = false) throws {
        guard (1...2).contains(channelCount), [120, 240, 480, 960].contains(frameSampleCount),
              mode == .celt || [480, 960].contains(frameSampleCount),
              mode != .celt || !enableInBandFEC else { throw OpusAudioEncoderError.invalidConfiguration }
        guard (3...1_276).contains(maximumPacketByteCount) else { throw OpusAudioEncoderError.invalidPacketByteLimit }
        let minimum = mode == .celt ? 3 : (mode == .hybrid ? 65 : (channelCount == 1 ? 17 : 33))
        try Self.validateBitrate(targetBitrate, frameSampleCount: frameSampleCount,
                                 minimumBytes: minimum, maximumBytes: maximumPacketByteCount)
        let configuration: Int
        var rate = 0
        var prefix = 0
        switch mode {
        case .celt:
            celt = try CELTPacketEncoder(frameSampleCount: frameSampleCount, channelCount: channelCount,
                                         bandwidth: bandwidth, analysisPolicy: .adaptive)
            let base: Int
            switch bandwidth {
            case .narrowband: base = 16
            case .wideband: base = 20
            case .superwideband: base = 24
            case .fullband: base = 28
            case .mediumband: throw OpusAudioEncoderError.invalidConfiguration
            }
            configuration = base + (frameSampleCount == 120 ? 0 : (frameSampleCount == 240 ? 1 : (frameSampleCount == 480 ? 2 : 3)))
        case .hybrid:
            hybrid = try OpusHybridEncoder(frameSampleCount: frameSampleCount, channelCount: channelCount,
                                           bandwidth: bandwidth, enableInBandFEC: enableInBandFEC, analysisPolicy: .adaptive)
            configuration = (bandwidth == .fullband ? 14 : 12) + (frameSampleCount == 960 ? 1 : 0)
        case .silk:
            switch bandwidth {
            case .narrowband: rate = 8_000
            case .mediumband: rate = 12_000
            case .wideband: rate = 16_000
            default: throw OpusAudioEncoderError.invalidConfiguration
            }
            if channelCount == 1 {
                mono = try SILKMonoEncoder(sampleRate: rate, frameDurationMilliseconds: frameSampleCount / 48,
                                           enableInBandFEC: enableInBandFEC)
            } else {
                stereo = try SILKStereoEncoder(sampleRate: rate, frameDurationMilliseconds: frameSampleCount / 48,
                                               enableInBandFEC: enableInBandFEC)
            }
            let converter = try PCMBandlimitedResampler(inputFormat: PCMFormat(sampleRate: 48_000, channelCount: channelCount),
                                                        outputSampleRate: rate)
            resampler = converter
            prefix = (converter.lookaheadFrames * rate + 47_999) / 48_000
            lowSamples = Array(repeating: 0, count: prefix * channelCount)
            configuration = (rate == 8_000 ? 0 : (rate == 12_000 ? 4 : 8)) + (frameSampleCount == 960 ? 1 : 0)
        }
        self.mode = mode
        self.bandwidth = bandwidth
        self.frameSampleCount = frameSampleCount
        self.channelCount = channelCount
        self.targetBitrate = targetBitrate
        self.maximumPacketByteCount = maximumPacketByteCount
        self.dtx = dtx
        self.enableInBandFEC = enableInBandFEC
        self.minimumPacketByteCount = minimum
        self.lowSampleRate = rate
        self.startupPrefixCount = prefix
        self.toc = UInt8(configuration << 3 | (channelCount == 2 ? 4 : 0))
    }

    /// Changes only the future byte target, retaining signal/FEC and DTX history.
    /// - Parameter bitrate: Total codec bits/second under the initializer's bounds.
    /// - Throws: `invalidBitrate` without mutation when floor/ceiling allocation cannot
    ///   fit this fixed format/cap. Success clears fractional carry and starts a new
    ///   accounting interval; there is no accumulated byte debt or retroactive change.
    public mutating func updateTargetBitrate(_ bitrate: Int) throws {
        try Self.validateBitrate(bitrate, frameSampleCount: frameSampleCount,
                                 minimumBytes: minimumPacketByteCount, maximumBytes: maximumPacketByteCount)
        targetBitrate = bitrate
        rateRemainder = 0
    }

    /// Discards every codec/converter history, rate remainder and DTX counter.
    /// The fixed format, target and configured policies remain. The next packet is
    /// identical to a fresh owner's corresponding input and always transmittable.
    /// This synchronous, idempotent operation performs no I/O or task work.
    public mutating func reset() {
        celt?.reset()
        hybrid?.reset()
        mono?.reset()
        stereo?.reset()
        resampler?.reset()
        lowSamples = Array(repeating: 0, count: startupPrefixCount * channelCount)
        rateRemainder = 0
        inactiveSampleCount = 0
        samplesSinceRefresh = 0
        wasSuppressed = false
        hasEncodedFrame = false
    }

    /// Encodes one fixed-duration contiguous frame with atomic signal/rate admission.
    /// - Parameter samples: Exactly `frameSampleCount * channelCount` finite normalized
    ///   `-1...1` 48kHz samples, interleaved in channel order. Caller input is not retained.
    /// - Returns: A complete ordinary packet, byte budget and transmission decision.
    ///   On suppressed DTX intervals advance media/RTP time even when omitting `data`.
    ///   A startup packet and periodic inactive refresh are always transmitted.
    /// - Throws: `invalidSamples` before mutation; component range/quantization/budget
    ///   failures when audio cannot fit the requested target. All histories and counters
    ///   roll back, permitting retry after an explicit target update. No suspension,
    ///   asynchronous work, device access, native codec call or network I/O occurs.
    public mutating func encode(_ samples: [Float]) throws -> OpusAudioEncodedPacket {
        guard samples.count == frameSampleCount * channelCount,
              samples.allSatisfy({ $0.isFinite && (-1...1).contains($0) }) else { throw OpusAudioEncoderError.invalidSamples }
        var working = self
        let entitlement = targetBitrate * frameSampleCount + rateRemainder
        let bytes = entitlement / 384_000
        working.rateRemainder = entitlement % 384_000
        var suppress = false
        if let dtx {
            let energy = samples.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(samples.count)
            let inactive = energy <= pow(10, dtx.thresholdDBFS / 10)
            if inactive {
                working.inactiveSampleCount = min(48_000 + frameSampleCount, inactiveSampleCount + frameSampleCount)
                let hangoverSamples = (dtx.hangoverMilliseconds * 48 + frameSampleCount - 1) / frameSampleCount * frameSampleCount
                if working.inactiveSampleCount > hangoverSamples, hasEncodedFrame {
                    working.samplesSinceRefresh = samplesSinceRefresh + frameSampleCount
                    suppress = working.samplesSinceRefresh < 19_200
                }
            } else {
                working.inactiveSampleCount = 0
            }
        }
        let audio = try working.encodeAudio(samples, packetByteCount: bytes,
                                             intra: wasSuppressed && !suppress)
        if !suppress { working.samplesSinceRefresh = 0 }
        working.wasSuppressed = suppress
        working.hasEncodedFrame = true
        self = working
        return OpusAudioEncodedPacket(data: suppress ? Data([toc]) : audio.data, shouldTransmit: !suppress,
                                       isDTX: suppress, packetByteBudget: bytes, finalRange: suppress ? 0 : audio.range)
    }

    /// Checks integer packet allocations without overflow or state changes.
    /// - Parameters:
    ///   - bitrate: Proposed total codec bit target, inclusive 6000...512000.
    ///   - frameSampleCount: Validated fixed 48kHz duration no larger than 960.
    ///   - minimumBytes: This format's minimum complete packet allocation.
    ///   - maximumBytes: Hard complete-packet cap, no larger than 1276.
    /// - Throws: `invalidBitrate` if either alternating fractional allocation is invalid.
    private static func validateBitrate(_ bitrate: Int, frameSampleCount: Int, minimumBytes: Int, maximumBytes: Int) throws {
        guard (6_000...512_000).contains(bitrate) else { throw OpusAudioEncoderError.invalidBitrate }
        let scaled = bitrate * frameSampleCount
        guard scaled / 384_000 >= minimumBytes, (scaled + 383_999) / 384_000 <= maximumBytes
        else { throw OpusAudioEncoderError.invalidBitrate }
    }

    /// Advances the selected bounded codec and returns complete wire bytes/range.
    /// - Parameters:
    ///   - samples: Caller-validated fixed-format 48kHz normalized PCM.
    ///   - packetByteCount: Validated current allocation, including TOC.
    ///   - intra: Independent CELT coarse-envelope request after suppressed audio.
    /// - Returns: Single-frame packet and the exact arithmetic final range. SILK uses
    ///   packet-level padding, never excess internal entropy bytes that an ordinary
    ///   decoder would interpret as implicit CELT transition redundancy.
    /// - Throws: Component quantization/range/resampling errors. The public caller
    ///   performs this work on a copy, so partial local mutation cannot escape.
    private mutating func encodeAudio(_ samples: [Float], packetByteCount: Int, intra: Bool) throws -> (data: Data, range: UInt32) {
        if var encoder = celt {
            let data = try encoder.encode(samples, packetByteCount: packetByteCount, intra: intra)
            celt = encoder
            return (data, encoder.finalRange)
        }
        if var encoder = hybrid {
            let data = try encoder.encode(samples, packetByteCount: packetByteCount, intra: intra)
            hybrid = encoder
            return (data, encoder.finalRange)
        }
        let format = try PCMFormat(sampleRate: 48_000, channelCount: channelCount)
        let converted = try resampler!.process(PCMBuffer(format: format, samples: samples))
        lowSamples.append(contentsOf: converted.flatMap(\.samples).map { Int16(clamping: Int(($0 * 32_768).rounded())) })
        let count = frameSampleCount * lowSampleRate / 48_000 * channelCount
        let pcm = Array(lowSamples.prefix(count))
        lowSamples.removeFirst(count)
        var entropy = try OpusRangeEncoder(frameByteCount: packetByteCount - 1)
        if mono != nil {
            _ = try mono!.encodePayload(pcm, to: &entropy)
        } else {
            _ = try stereo!.encodePayload(pcm, to: &entropy)
        }
        let range = entropy.finalRange
        // SILK has no backward raw-bit section, so the minimum arithmetic prefix
        // is independent of the sizing storage. Extra Opus packet padding belongs
        // outside the entropy frame to avoid signaling transition redundancy.
        let payloadCount = max(2, (entropy.bitsUsed + 7) / 8)
        let payload = Data(try entropy.finalize().prefix(payloadCount))
        return (paddedSILKPacket(payload, packetByteCount: packetByteCount), range)
    }

    /// Pads a minimal ordinary SILK payload to its exact total rate allocation.
    /// - Parameters:
    ///   - payload: Two through 1275 owned arithmetic bytes with no backward raw bits.
    ///   - packetByteCount: Complete target allocation, at least payload.count+1.
    /// - Returns: Code zero when already exact; otherwise packing code three with
    ///   one CBR frame and optional RFC 6716 section 3.2.5 trailing zero padding.
    ///   Continuation 255 consumes one header byte plus 254 padding bytes, so all
    ///   allocation differences are representable without modifying the payload.
    ///   This bounded helper has no state changes, I/O or suspension points.
    private func paddedSILKPacket(_ payload: Data, packetByteCount: Int) -> Data {
        let extra = packetByteCount - payload.count - 1
        if extra == 0 { return Data([toc]) + payload }
        if extra == 1 { return Data([toc | 3, 1]) + payload }
        var remainder = extra - 1
        var lengths: [UInt8] = []
        while remainder > 255 {
            lengths.append(255)
            remainder -= 255
        }
        lengths.append(UInt8(remainder - 1))
        let paddingCount = extra - 1 - lengths.count
        return Data([toc | 3, 0x41]) + Data(lengths) + payload + Data(repeating: 0, count: paddingCount)
    }
}
