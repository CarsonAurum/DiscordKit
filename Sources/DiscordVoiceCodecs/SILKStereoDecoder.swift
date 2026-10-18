/*
Copyright (c) 2006-2011, Skype Limited. All rights reserved.
Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions
are met:
- Redistributions of source code must retain the above copyright notice,
this list of conditions and the following disclaimer.
- Redistributions in binary form must reproduce the above copyright
notice, this list of conditions and the following disclaimer in the
documentation and/or other materials provided with the distribution.
- Neither the name of Internet Society, IETF or IETF Trust, nor the
names of specific contributors, may be used to endorse or promote
products derived from this software without specific prior written
permission.
THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
POSSIBILITY OF SUCH DAMAGE.
*/


import Foundation

/// One complete SILK payload rendered as configured mono/interleaved stereo PCM16.
/// Channel-major activity/redundancy describe the coded mid and optional side;
/// `sideFrames` has one entry per internal frame, nil when the side was omitted.
public struct SILKStereoDecodedPayload: Sendable, Equatable {
    public let pcm48k: [Int16]
    public let midFrames: [SILKDecodedFrame]
    public let sideFrames: [SILKDecodedFrame?]
    public let voiceActivity: [[Bool]]
    public let redundancy: [[Bool]]
    public let midOnly: [Bool]
    public let finalRange: UInt32
    public let bitsUsed: Int
}

/// One mono/stereo-coded SILK packet rendered at 48kHz with the configured channels.
public struct SILKStereoDecodedPacket: Sendable, Equatable {
    public let pcm48k: [Int16]
    public let payloads: [SILKStereoDecodedPayload]
}

/// Owned ordinary SILK decoder with adaptive stereo and internal-rate transitions.
///
/// Implements RFC 6716 section 4.2.8's predictor entropy, eight-millisecond
/// interpolation, mid-only side reset, bounded alignment, LBRR syntax skipping,
/// NB/MB/WB rate changes and mono/stereo channel changes. Output has one or two channels;
/// mono-coded packets duplicate the mid for stereo output, retaining the normative first-frame
/// distinct right resampler when collapsing stereo. Scalar arithmetic adapts
/// libopus 1.6.1 dec_API.c, decoder_set_fs.c and stereo_MS_to_LR.c.
///
/// Scalar PLC/CNG and selected in-band FEC are independently caller-driven;
/// complete Opus mode-transition mixing belongs to a higher-level owner. Construction creates no I/O or tasks.
/// Callers serialize mutation; copies own independent bounded histories, and
/// failed calls preserve both decoder and supplied entropy. Per-call allocations
/// are bounded by at most 120ms per packet and 60ms per compressed payload.
public struct SILKStereoDecoder: Sendable {
    public private(set) var sampleRate: Int
    public let channelCount: Int
    private var mid: SILKFrameDecoder
    private var side: SILKFrameDecoder
    private var leftResampler: SILKDecoderResampler
    private var rightResampler: SILKDecoderResampler
    private var midHistory: [Int16] = [0, 0]
    private var sideHistory: [Int16] = [0, 0]
    private var predictorsQ13: [Int32] = [0, 0]
    private var previousMidOnly = false
    private var previousChannelCount = 0
    private static let predictorCDF: [UInt8] = [
        249, 247, 246, 245, 244, 234, 210, 202, 201, 200, 197, 174, 82,
        59, 56, 55, 54, 46, 22, 12, 11, 10, 9, 7, 0
    ]
    private static let predictorQuantQ13: [Int32] = [
        -13732, -10050, -8266, -7526, -6500, -5000, -2950, -820,
        820, 2950, 5000, 6500, 7526, 8266, 10050, 13732
    ]

    /// Initializes two independent bounded channel/filter states without entropy work.
    /// - Parameter sampleRate: Exactly 8,000, 12,000 or 16,000 internal samples/second.
    /// - Parameter outputChannelCount: One for mid-only API output or two for
    ///   interleaved stereo; defaults two. This is independent of coded channels.
    /// - Throws: `SILKFrameParameterError.invalidSampleRate` for other rates, or
    ///   `SILKMonoDecoderError.unsupportedChannels` for another output layout.
    public init(sampleRate: Int, outputChannelCount: Int = 2) throws {
        guard outputChannelCount == 1 || outputChannelCount == 2 else { throw SILKMonoDecoderError.unsupportedChannels }
        channelCount = outputChannelCount
        mid = try SILKFrameDecoder(sampleRate: sampleRate, frameDurationMilliseconds: 20)
        side = try SILKFrameDecoder(sampleRate: sampleRate, frameDurationMilliseconds: 20)
        self.sampleRate = sampleRate
        leftResampler = SILKDecoderResampler(sampleRate: sampleRate)
        rightResampler = SILKDecoderResampler(sampleRate: sampleRate)
    }

    /// Clears all stream state, preserving only the current internal rate.
    /// Existing result values and independently copied decoders remain unchanged.
    public mutating func reset() {
        mid.reset()
        side.reset()
        leftResampler = SILKDecoderResampler(sampleRate: sampleRate)
        rightResampler = SILKDecoderResampler(sampleRate: sampleRate)
        midHistory = [0, 0]
        sideHistory = [0, 0]
        predictorsQ13 = [0, 0]
        previousMidOnly = false
        previousChannelCount = 0
    }

    /// Changes NB/MB/WB bandwidth using the normative internal-rate state reset.
    /// - Parameter sampleRate: Exactly 8,000, 12,000 or 16,000 Hz. Equal rates
    ///   preserve all state. Different rates reset channel prediction/resamplers,
    ///   retaining scalar gains, stereo alignment samples and stereo predictors.
    /// - Throws: `SILKFrameParameterError.invalidSampleRate`; state is atomic.
    public mutating func updateSampleRate(_ sampleRate: Int) throws {
        var working = self
        try working.mid.updateSampleRate(sampleRate)
        try working.side.updateSampleRate(sampleRate)
        if sampleRate != self.sampleRate {
            working.leftResampler = SILKDecoderResampler(sampleRate: sampleRate)
            working.rightResampler = SILKDecoderResampler(sampleRate: sampleRate)
            working.sampleRate = sampleRate
        }
        self = working
    }

    /// Conceals one missing payload using the last successfully coded channel layout.
    /// - Parameter durationMilliseconds: Exactly ten, twenty, forty or sixty;
    ///   default twenty. Initial zero-state loss assumes stereo, yielding silence.
    /// - Returns: Configured-channel PCM16 at 48kHz and internal mid/side frames.
    ///   A preceding mid-only frame keeps side coding omitted while predictor
    ///   unmixing and independent resampler histories continue normatively.
    /// - Throws: `invalidPayloadDuration` or CNG/LPC validation errors. Every
    ///   failure preserves all state. No entropy, I/O, task or device is touched.
    public mutating func conceal(durationMilliseconds: Int = 20) throws -> SILKConcealedPayload {
        guard [10, 20, 40, 60].contains(durationMilliseconds) else { throw SILKMonoDecoderError.invalidPayloadDuration }
        var working = self
        let duration = durationMilliseconds == 10 ? 10 : 20
        try working.mid.updateFrameDuration(milliseconds: duration)
        try working.side.updateFrameDuration(milliseconds: duration)
        let channels = previousChannelCount == 1 ? 1 : 2
        var pcm: [Int16] = []
        var frames: [[[Int16]]] = []
        for _ in 0..<(durationMilliseconds / duration) {
            let mid = try working.mid.concealFrame()
            let side = channels == 2 && !previousMidOnly ? try working.side.concealFrame() : Array(repeating: Int16(0), count: mid.count)
            let left: [Int16]
            let right: [Int16]
            if channelCount == 2 && channels == 2 {
                let unmix = working.unmix(mid: mid, side: side, predictors: working.predictorsQ13)
                left = working.leftResampler.process(unmix.0)
                right = working.rightResampler.process(unmix.1)
            } else {
                let aligned = [working.midHistory[1]] + mid.dropLast()
                working.midHistory = Array(mid.suffix(2))
                left = working.leftResampler.process(aligned)
                right = left
            }
            for index in left.indices {
                pcm.append(left[index])
                if channelCount == 2 { pcm.append(right[index]) }
            }
            frames.append(channels == 1 ? [mid] : [mid, side])
        }
        self = working
        return SILKConcealedPayload(pcm48k: pcm, channelFrames: frames)
    }

    /// Recovers missing audio from a subsequent payload's in-band LBRR prefix.
    /// - Parameters:
    ///   - payload: One through 1,275 compressed bytes, excluding Opus framing.
    ///   - durationMilliseconds: Exactly ten, twenty, forty or sixty milliseconds.
    ///   - codedChannelCount: Exactly one or two, default two. Output uses the
    ///     independently configured one/two API channels.
    /// - Returns: Exact-duration configured-channel PCM16; nil channel-frame evidence
    ///   marks absent redundancy or omitted side coding. Ordinary payload audio must
    ///   be decoded in a subsequent normal call. Missing LBRR uses scalar PLC/CNG;
    ///   predictor, conditional and channel-transition policy follow `silk_Decode`.
    /// - Throws: Size/duration/channel or codec errors. Failure preserves all state;
    ///   no native codec, device, task or I/O occurs. Caller orders missing audio.
    public mutating func recoverPayload(
        _ payload: Data, durationMilliseconds: Int, codedChannelCount: Int = 2
    ) throws -> SILKRecoveredPayload {
        guard [10, 20, 40, 60].contains(durationMilliseconds) else { throw SILKMonoDecoderError.invalidPayloadDuration }
        guard codedChannelCount == 1 || codedChannelCount == 2 else { throw SILKMonoDecoderError.unsupportedChannels }
        guard (1...1_275).contains(payload.count) else { throw SILKMonoDecoderError.invalidPayloadSize }
        var working = self
        var entropy = try OpusRangeDecoder(frame: payload)
        let duration = durationMilliseconds == 10 ? 10 : 20
        let count = durationMilliseconds / duration
        try working.mid.updateFrameDuration(milliseconds: duration)
        try working.side.updateFrameDuration(milliseconds: duration)
        if codedChannelCount > working.previousChannelCount {
            working.side = try SILKFrameDecoder(sampleRate: sampleRate, frameDurationMilliseconds: duration)
        }
        if channelCount == 2 && codedChannelCount == 2 && working.previousChannelCount < 2 {
            working.predictorsQ13 = [0, 0]
            working.sideHistory = [0, 0]
            working.rightResampler = working.leftResampler
        }
        var activity = Array(repeating: [Bool](), count: codedChannelCount)
        var hasRedundancy = Array(repeating: false, count: codedChannelCount)
        for channel in 0..<codedChannelCount {
            for _ in 0..<count { activity[channel].append(try entropy.decodeBit(logProbability: 1)) }
            hasRedundancy[channel] = try entropy.decodeBit(logProbability: 1)
        }
        var redundancy = Array(repeating: Array(repeating: false, count: count), count: codedChannelCount)
        for channel in 0..<codedChannelCount where hasRedundancy[channel] {
            let mask = count == 1 ? 1 : try Self.symbol(&entropy, cdf: count == 2 ? [203, 150, 0] : [215, 195, 166, 125, 110, 82, 0]) + 1
            for index in 0..<count { redundancy[channel][index] = mask & (1 << index) != 0 }
        }
        var frames: [[SILKDecodedFrame?]] = []
        var midOnly: [Bool] = []
        var output: [Int16] = []
        for index in 0..<count {
            let stereo = codedChannelCount == 2
            var predictors = working.predictorsQ13
            var onlyMid = false
            if stereo && redundancy[0][index] {
                predictors = try Self.decodePredictors(from: &entropy)
                if !redundancy[1][index] { onlyMid = try Self.symbol(&entropy, cdf: [64, 0]) != 0 }
            }
            if stereo && !onlyMid && working.previousMidOnly { try working.side.resetSidePrediction() }
            let hasSide = !working.previousMidOnly || (stereo && redundancy[1][index])
            let midFrame: SILKDecodedFrame?
            let midPCM: [Int16]
            if redundancy[0][index] {
                midFrame = try working.mid.decode(from: &entropy, voiceActivity: activity[0][index],
                    lowBitrateRedundancy: true,
                    coding: index > 0 && redundancy[0][index - 1] ? .conditional : .independent)
                midPCM = midFrame!.pcm
            } else {
                midFrame = nil
                midPCM = try working.mid.concealFrame(resetGainIndex: false)
            }
            let sideFrame: SILKDecodedFrame?
            let sidePCM: [Int16]
            if stereo && hasSide {
                if redundancy[1][index] {
                    sideFrame = try working.side.decode(from: &entropy, voiceActivity: activity[1][index],
                        lowBitrateRedundancy: true,
                        coding: index > 0 && redundancy[1][index - 1] ? .conditional : .independent)
                    sidePCM = sideFrame!.pcm
                } else {
                    sideFrame = nil
                    sidePCM = try working.side.concealFrame(resetGainIndex: false)
                }
            } else {
                sideFrame = nil
                sidePCM = Array(repeating: 0, count: midPCM.count)
            }
            let left: [Int16]
            let right: [Int16]
            if channelCount == 2 && stereo {
                let unmix = working.unmix(mid: midPCM, side: sidePCM, predictors: predictors)
                left = working.leftResampler.process(unmix.0)
                right = working.rightResampler.process(unmix.1)
            } else {
                let aligned = [working.midHistory[1]] + midPCM.dropLast()
                working.midHistory = Array(midPCM.suffix(2))
                left = working.leftResampler.process(aligned)
                right = channelCount == 2 && working.previousChannelCount == 2 ? working.rightResampler.process(aligned) : left
            }
            for position in left.indices {
                output.append(left[position])
                if channelCount == 2 { output.append(right[position]) }
            }
            working.previousMidOnly = onlyMid
            working.previousChannelCount = codedChannelCount
            frames.append(stereo ? [midFrame, sideFrame] : [midFrame])
            midOnly.append(onlyMid)
        }
        self = working
        return SILKRecoveredPayload(pcm48k: output, channelFrames: frames, voiceActivity: activity,
            redundancy: redundancy, midOnly: midOnly, finalRange: entropy.finalRange, bitsUsed: entropy.bitsUsed)
    }

    /// Decodes bounded compressed bytes including their shared SILK header.
    /// - Parameters:
    ///   - payload: One through 1,275 compressed bytes, excluding Opus framing.
    ///   - durationMilliseconds: Exactly ten, twenty, forty or sixty milliseconds.
    ///   - codedChannelCount: One for mono mid syntax, or two for adaptive stereo;
    ///     defaults to two. Output uses the configured channel count in either case.
    /// - Returns: Exact-duration configured-channel PCM16 and channel/entropy evidence.
    /// - Throws: `SILKMonoDecoderError.invalidPayloadSize`, duration/channel errors
    ///   or channel/range errors. Use `conceal` for empty loss/DTX payloads.
    ///   Normative zero extension permits bounded audio from damaged bytes and
    ///   does not authenticate compressed streams. Every failure preserves state.
    public mutating func decodePayload(
        _ payload: Data, durationMilliseconds: Int, codedChannelCount: Int = 2
    ) throws -> SILKStereoDecodedPayload {
        guard (1...1_275).contains(payload.count) else { throw SILKMonoDecoderError.invalidPayloadSize }
        var entropy = try OpusRangeDecoder(frame: payload)
        return try decodePayload(from: &entropy, durationMilliseconds: durationMilliseconds, codedChannelCount: codedChannelCount)
    }

    /// Decodes SILK syntax while retaining shared entropy/raw-tail state for hybrid CELT.
    /// - Parameters:
    ///   - decoder: Range decoder positioned at the SILK VAD/LBRR header, retaining
    ///     the complete enclosing compressed payload. Success advances only SILK syntax.
    ///   - durationMilliseconds: Exactly ten, twenty, forty or sixty milliseconds.
    ///   - codedChannelCount: Exactly one or two; output uses the configured output channel count.
    /// - Returns: Complete configured-channel PCM16 plus SILK range/bit evidence at this
    ///   boundary; hybrid callers must continue CELT before treating it as final.
    /// - Throws: Duration/channel admission or channel/range errors. Copies commit
    ///   together only on success. No suspension, native codec, I/O or tasks occur.
    public mutating func decodePayload(
        from decoder: inout OpusRangeDecoder, durationMilliseconds: Int, codedChannelCount: Int
    ) throws -> SILKStereoDecodedPayload {
        guard [10, 20, 40, 60].contains(durationMilliseconds) else { throw SILKMonoDecoderError.invalidPayloadDuration }
        guard codedChannelCount == 1 || codedChannelCount == 2 else { throw SILKMonoDecoderError.unsupportedChannels }
        var working = self
        var entropy = decoder
        let internalDuration = durationMilliseconds == 10 ? 10 : 20
        let count = durationMilliseconds / internalDuration
        try working.mid.updateFrameDuration(milliseconds: internalDuration)
        try working.side.updateFrameDuration(milliseconds: internalDuration)
        if codedChannelCount > working.previousChannelCount {
            working.side = try SILKFrameDecoder(sampleRate: sampleRate, frameDurationMilliseconds: internalDuration)
        }
        if channelCount == 2 && codedChannelCount == 2 && working.previousChannelCount < 2 {
            working.predictorsQ13 = [0, 0]
            working.sideHistory = [0, 0]
            working.rightResampler = working.leftResampler
        }
        var activity = Array(repeating: [Bool](), count: codedChannelCount)
        var hasRedundancy = Array(repeating: false, count: codedChannelCount)
        for channel in 0..<codedChannelCount {
            for _ in 0..<count { activity[channel].append(try entropy.decodeBit(logProbability: 1)) }
            hasRedundancy[channel] = try entropy.decodeBit(logProbability: 1)
        }
        var redundancy = Array(repeating: Array(repeating: false, count: count), count: codedChannelCount)
        for channel in 0..<codedChannelCount where hasRedundancy[channel] {
            let mask = count == 1 ? 1 : try Self.symbol(&entropy, cdf: count == 2 ? [203, 150, 0] : [215, 195, 166, 125, 110, 82, 0]) + 1
            for index in 0..<count { redundancy[channel][index] = mask & (1 << index) != 0 }
        }
        var skip = try (0..<codedChannelCount).map { _ in
            try SILKFrameParameterDecoder(sampleRate: sampleRate, frameDurationMilliseconds: internalDuration)
        }
        for index in 0..<count {
            for channel in 0..<codedChannelCount where redundancy[channel][index] {
                if codedChannelCount == 2 && channel == 0 {
                    _ = try Self.decodePredictors(from: &entropy)
                    if !redundancy[1][index] { _ = try Self.symbol(&entropy, cdf: [64, 0]) }
                }
                _ = try skip[channel].decodeExcitation(
                    from: &entropy, voiceActivity: activity[channel][index], lowBitrateRedundancy: true,
                    coding: index > 0 && redundancy[channel][index - 1] ? .conditional : .independent
                )
            }
        }
        var midFrames: [SILKDecodedFrame] = []
        var sideFrames: [SILKDecodedFrame?] = []
        var midOnly: [Bool] = []
        var output: [Int16] = []
        output.reserveCapacity(durationMilliseconds * 48 * channelCount)
        for index in 0..<count {
            let stereo = codedChannelCount == 2
            let predictors = stereo ? try Self.decodePredictors(from: &entropy) : [0, 0]
            let onlyMid = stereo && !activity[1][index] ? try Self.symbol(&entropy, cdf: [64, 0]) != 0 : false
            if stereo && !onlyMid && working.previousMidOnly { try working.side.resetSidePrediction() }
            let midFrame = try working.mid.decode(from: &entropy, voiceActivity: activity[0][index], coding: index == 0 ? .independent : .conditional)
            var sideFrame: SILKDecodedFrame?
            if stereo && !onlyMid {
                let coding: SILKParameterCoding = index == 0 ? .independent : working.previousMidOnly ? .independentWithoutLTPScaling : .conditional
                sideFrame = try working.side.decode(from: &entropy, voiceActivity: activity[1][index], coding: coding)
            }
            let left: [Int16]
            let right: [Int16]
            if channelCount == 2 && stereo {
                let unmix = working.unmix(mid: midFrame.pcm, side: sideFrame?.pcm ?? Array(repeating: 0, count: midFrame.pcm.count), predictors: predictors)
                left = working.leftResampler.process(unmix.0)
                right = working.rightResampler.process(unmix.1)
            } else {
                let aligned = [working.midHistory[1]] + midFrame.pcm.dropLast()
                working.midHistory = Array(midFrame.pcm.suffix(2))
                left = working.leftResampler.process(aligned)
                if channelCount == 2 && working.previousChannelCount == 2 {
                    right = working.rightResampler.process(aligned)
                } else { right = left }
            }
            for position in left.indices {
                output.append(left[position])
                if channelCount == 2 { output.append(right[position]) }
            }
            working.previousMidOnly = onlyMid
            working.previousChannelCount = codedChannelCount
            midFrames.append(midFrame)
            sideFrames.append(sideFrame)
            midOnly.append(onlyMid)
        }
        let result = SILKStereoDecodedPayload(pcm48k: output, midFrames: midFrames, sideFrames: sideFrames,
            voiceActivity: activity, redundancy: redundancy, midOnly: midOnly,
            finalRange: entropy.finalRange, bitsUsed: entropy.bitsUsed)
        self = working
        decoder = entropy
        return result
    }

    /// Decodes complete SILK packet framing and adopts its coded rate/channel count.
    /// - Parameter packet: Structurally validated ordinary SILK-only Opus packet,
    ///   bounded by `OpusPacket` to 120ms. Empty DTX/loss payloads require explicit `conceal` calls.
    /// - Returns: Exactly `packet.sampleCount * channelCount` PCM16 values. Stereo
    ///   coded input rendered as mono uses the decoded mid, not an average of LR.
    /// - Throws: `SILKMonoDecoderError.unsupportedMode` or any payload/channel error.
    ///   All payloads and any bandwidth transition commit atomically on success.
    public mutating func decode(_ packet: OpusPacket) throws -> SILKStereoDecodedPacket {
        guard packet.mode == .silk else { throw SILKMonoDecoderError.unsupportedMode }
        var working = self
        try working.updateSampleRate([8_000, 12_000, 16_000][packet.configuration / 4])
        var pcm: [Int16] = []
        var payloads: [SILKStereoDecodedPayload] = []
        pcm.reserveCapacity(packet.sampleCount * channelCount)
        for range in packet.frameRanges {
            let result = try working.decodePayload(packet.data.subdata(in: range),
                durationMilliseconds: packet.frameSampleCount / 48, codedChannelCount: packet.channelCount)
            pcm.append(contentsOf: result.pcm48k)
            payloads.append(result)
        }
        self = working
        return SILKStereoDecodedPacket(pcm48k: pcm, payloads: payloads)
    }

    /// Decodes one bounded inverse-CDF symbol using the standard eight-bit model.
    /// - Parameters:
    ///   - entropy: Mutable shared range state; the validated model consumes one symbol.
    ///   - cdf: Nonincreasing normative inverse probabilities, ending in zero.
    /// - Returns: Zero-based symbol index.
    /// - Throws: Model/range errors; enclosing payload copies retain atomicity.
    private static func symbol(_ entropy: inout OpusRangeDecoder, cdf: [UInt8]) throws -> Int {
        try entropy.decodeSymbol(model: OpusProbabilityModel(inverseCDF: cdf))
    }

    /// Reads the joint/coarse/fine adaptive stereo predictor and dequantizes Q13.
    /// - Parameter entropy: Shared state positioned immediately before stereo syntax.
    /// - Returns: Difference predictor and second predictor, each signed Q13.
    /// - Throws: Range/model errors, propagated to the atomic enclosing payload.
    private static func decodePredictors(from entropy: inout OpusRangeDecoder) throws -> [Int32] {
        let joint = try symbol(&entropy, cdf: predictorCDF)
        var values: [Int32] = []
        for channel in 0..<2 {
            let coarse = try symbol(&entropy, cdf: [171, 85, 0]) + 3 * (channel == 0 ? joint / 5 : joint % 5)
            let fine = try symbol(&entropy, cdf: [205, 154, 102, 51, 0])
            let low = predictorQuantQ13[coarse]
            let step = ((predictorQuantQ13[coarse + 1] - low) * 6_554) >> 16
            values.append(low + step * Int32(2 * fine + 1))
        }
        values[0] -= values[1]
        return values
    }

    /// Reconstructs adaptive mid/side into aligned internal-rate left/right PCM16.
    /// - Parameters:
    ///   - mid: One ten/twenty-millisecond decoded mid frame.
    ///   - side: Same count of side samples, or zeros for omitted side coding.
    ///   - predictors: Exactly two decoded signed Q13 predictors.
    /// - Returns: Two frame-length aligned PCM16 arrays. Updates only bounded
    ///   two-sample mid/side history and previous predictors, with scalar saturation.
    private mutating func unmix(mid: [Int16], side: [Int16], predictors: [Int32]) -> ([Int16], [Int16]) {
        let x = midHistory + mid
        var y = sideHistory + side
        midHistory = Array(x[mid.count..<(mid.count + 2)])
        sideHistory = Array(y[mid.count..<(mid.count + 2)])
        let interpolation = 8 * sampleRate / 1_000
        let denominator = Int32(65_536 / interpolation)
        let delta = (0..<2).map { ((Int32(Int16(truncatingIfNeeded: predictors[$0] - predictorsQ13[$0])) * denominator) + 32_768) >> 16 }
        var current = predictorsQ13
        for index in mid.indices {
            if index < interpolation { current[0] += delta[0]; current[1] += delta[1] }
            else { current = predictors }
            let smooth = (Int32(x[index]) + Int32(x[index + 2]) + 2 * Int32(x[index + 1])) << 9
            var sum = Int32(y[index + 1]) << 8
            sum = sum &+ Int32(truncatingIfNeeded: (Int64(smooth) * Int64(Int16(truncatingIfNeeded: current[0]))) >> 16)
            sum = sum &+ Int32(truncatingIfNeeded: (Int64(Int32(x[index + 1]) << 11) * Int64(Int16(truncatingIfNeeded: current[1]))) >> 16)
            y[index + 1] = Int16(clamping: ((sum >> 7) + 1) >> 1)
        }
        predictorsQ13 = predictors
        var left: [Int16] = []
        var right: [Int16] = []
        left.reserveCapacity(mid.count)
        right.reserveCapacity(mid.count)
        for index in mid.indices {
            left.append(Int16(clamping: Int32(x[index + 1]) + Int32(y[index + 1])))
            right.append(Int16(clamping: Int32(x[index + 1]) - Int32(y[index + 1])))
        }
        return (left, right)
    }
}
