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

/// Admission failures for the owned ordinary mono SILK payload and packet decoder.
public enum SILKMonoDecoderError: Error, Sendable, Equatable {
    case invalidPayloadDuration
    case invalidPayloadSize
    case unsupportedMode
    case unsupportedChannels
    case sampleRateMismatch
}

/// One complete mono SILK payload, including its original internal channel frames.
///
/// The 48kHz output contains exactly 480, 960, 1,920 or 2,880 samples and includes
/// normative mono alignment and decoder-rate resampling. LBRR syntax was skipped;
/// redundancy flags describe availability, not a claim of recovered missing audio.
public struct SILKDecodedPayload: Sendable, Equatable {
    public let pcm48k: [Int16]
    public let frames: [SILKDecodedFrame]
    public let voiceActivity: [Bool]
    public let redundancy: [Bool]
    public let finalRange: UInt32
    public let bitsUsed: Int
}

/// Owned ordinary mono SILK payload decoding at the mandatory 48kHz Opus clock.
///
/// Reads the VAD/LBRR header, skips optional redundant channel syntax, decodes
/// all ordinary internal frames with correct conditional contexts, buffers mono
/// alignment and runs the scalar allpass/FIR decoder resampler. State persists
/// across payload duration changes; explicit rate changes reset the normative histories. No native codec,
/// tasks, I/O or global mutable state are used. Arithmetic adapts libopus 1.6.1
/// dec_API.c, resampler.c, resampler_private_up2_HQ.c and resampler_private_IIR_FIR.c.
///
/// This decoder covers mono SILK payloads plus caller-driven scalar PLC/CNG and
/// selected in-band FEC. Empty compressed payloads are handled explicitly through
/// `conceal`; stereo and complete Opus mode transitions belong to enclosing owners.
/// Reset at a stream discontinuity. Each call is atomic on every error.
public struct SILKMonoDecoder: Sendable {
    public private(set) var sampleRate: Int
    private var channel: SILKFrameDecoder
    private var resampler: SILKDecoderResampler
    private var previousMonoSample: Int16 = 0

    /// Creates a zero-state mono decoder for one internal NB/MB/WB sample rate.
    /// - Parameter sampleRate: Exactly 8,000, 12,000 or 16,000 samples per second.
    /// - Throws: `SILKFrameParameterError.invalidSampleRate` for other rates.
    ///   Allocates only bounded 20ms channel history and fixed resampling memory.
    public init(sampleRate: Int) throws {
        channel = try SILKFrameDecoder(sampleRate: sampleRate, frameDurationMilliseconds: 20)
        self.sampleRate = sampleRate
        resampler = SILKDecoderResampler(sampleRate: sampleRate)
    }

    /// Clears channel, mono alignment and allpass/FIR/delay histories at a discontinuity.
    /// The internal rate remains fixed. Already returned value outputs remain independent.
    public mutating func reset() {
        channel.reset()
        resampler = SILKDecoderResampler(sampleRate: sampleRate)
        previousMonoSample = 0
    }

    /// Changes the internal rate at a genuine SILK stream bandwidth transition.
    /// - Parameter sampleRate: Exactly 8,000, 12,000 or 16,000 Hz. Repeating the
    ///   current rate preserves all state. A different rate resets LPC/LTP and
    ///   resampler memory while preserving scalar gain and mono alignment, following
    ///   `silk_decoder_set_fs`; this is not a complete Opus mode-transition crossfade.
    /// - Throws: `SILKFrameParameterError.invalidSampleRate`; failure changes nothing.
    public mutating func updateSampleRate(_ sampleRate: Int) throws {
        var working = self
        try working.channel.updateSampleRate(sampleRate)
        if sampleRate != self.sampleRate {
            working.resampler = SILKDecoderResampler(sampleRate: sampleRate)
            working.sampleRate = sampleRate
        }
        self = working
    }

    /// Conceals a missing/DTX payload without consuming compressed entropy.
    /// - Parameter durationMilliseconds: Exactly ten, twenty, forty or sixty;
    ///   default twenty. Longer durations contain successive twenty-millisecond
    ///   internal PLC frames, each retaining scalar attenuation and CNG history.
    /// - Returns: Exact-duration mono 48kHz PCM16 and pre-alignment internal frames.
    /// - Throws: `invalidPayloadDuration` or CNG/LPC validation errors; all state
    ///   commits atomically. No native codec, entropy, device or I/O is used.
    public mutating func conceal(durationMilliseconds: Int = 20) throws -> SILKConcealedPayload {
        guard [10, 20, 40, 60].contains(durationMilliseconds) else { throw SILKMonoDecoderError.invalidPayloadDuration }
        var working = self
        let duration = durationMilliseconds == 10 ? 10 : 20
        try working.channel.updateFrameDuration(milliseconds: duration)
        var output: [Int16] = []
        var frames: [[[Int16]]] = []
        for _ in 0..<(durationMilliseconds / duration) {
            let frame = try working.channel.concealFrame()
            let aligned = [working.previousMonoSample] + frame.dropLast()
            working.previousMonoSample = frame.last!
            output += working.resampler.process(aligned)
            frames.append([frame])
        }
        self = working
        return SILKConcealedPayload(pcm48k: output, channelFrames: frames)
    }

    /// Selects in-band LBRR from a subsequent compressed payload for missing audio.
    /// - Parameters:
    ///   - payload: One through 1,275 compressed bytes, excluding Opus framing.
    ///   - durationMilliseconds: Exactly ten, twenty, forty or sixty milliseconds,
    ///     describing the redundant internal frames carried by this payload.
    /// - Returns: Exact-duration mono 48kHz PCM16, decoded redundant-frame evidence
    ///   or nil for frames concealed because LBRR was absent, and availability flags.
    ///   Entropy evidence stops after LBRR; decode this payload normally afterwards
    ///   to obtain its ordinary current audio. FEC does not guarantee reconstruction
    ///   of the original encoder PCM and does not authenticate compressed bytes.
    /// - Throws: Size/duration admission or channel/CNG/range errors. All state
    ///   commits atomically. Caller selects missing-packet order; no I/O occurs.
    public mutating func recoverPayload(_ payload: Data, durationMilliseconds: Int) throws -> SILKRecoveredPayload {
        guard [10, 20, 40, 60].contains(durationMilliseconds) else { throw SILKMonoDecoderError.invalidPayloadDuration }
        guard (1...1_275).contains(payload.count) else { throw SILKMonoDecoderError.invalidPayloadSize }
        var working = self
        let duration = durationMilliseconds == 10 ? 10 : 20
        let count = durationMilliseconds / duration
        try working.channel.updateFrameDuration(milliseconds: duration)
        var entropy = try OpusRangeDecoder(frame: payload)
        var activity: [Bool] = []
        for _ in 0..<count { activity.append(try entropy.decodeBit(logProbability: 1)) }
        let hasRedundancy = try entropy.decodeBit(logProbability: 1)
        var available = Array(repeating: false, count: count)
        if hasRedundancy {
            let mask = count == 1 ? 1 : try entropy.decodeSymbol(model: OpusProbabilityModel(inverseCDF:
                count == 2 ? [203, 150, 0] : [215, 195, 166, 125, 110, 82, 0])) + 1
            for index in 0..<count { available[index] = mask & (1 << index) != 0 }
        }
        var output: [Int16] = []
        var frames: [[SILKDecodedFrame?]] = []
        for index in 0..<count {
            let decoded: SILKDecodedFrame?
            let pcm: [Int16]
            if available[index] {
                decoded = try working.channel.decode(from: &entropy, voiceActivity: activity[index],
                    lowBitrateRedundancy: true, coding: index > 0 && available[index - 1] ? .conditional : .independent)
                pcm = decoded!.pcm
            } else {
                decoded = nil
                pcm = try working.channel.concealFrame(resetGainIndex: false)
            }
            let aligned = [working.previousMonoSample] + pcm.dropLast()
            working.previousMonoSample = pcm.last!
            output += working.resampler.process(aligned)
            frames.append([decoded])
        }
        self = working
        return SILKRecoveredPayload(pcm48k: output, channelFrames: frames, voiceActivity: [activity],
            redundancy: [available], midOnly: Array(repeating: false, count: count),
            finalRange: entropy.finalRange, bitsUsed: entropy.bitsUsed)
    }

    /// Decodes an entire ordinary mono SILK payload with shared header/entropy state.
    /// - Parameters:
    ///   - payload: Compressed bytes excluding the Opus TOC and frame-packing bytes;
    ///     one through 1,275 bytes. Use `conceal` for empty loss/DTX payloads.
    ///   - durationMilliseconds: Exactly ten, twenty, forty or sixty milliseconds.
    /// - Returns: Exact-duration 48kHz PCM16 plus ordinary frames, header flags and
    ///   final entropy evidence. LBRR data is consumed without synthesizing or selecting it.
    /// - Throws: `SILKMonoDecoderError.invalidPayloadSize`, `invalidPayloadDuration`,
    ///   or an underlying channel/range error. Normative arithmetic zero extension
    ///   means damaged or truncated nonempty syntax can still decode to bounded audio;
    ///   this is not compressed-stream authentication. Failure preserves all state.
    /// - Complexity: Bounded synchronous O(duration * sampleRate * LPCOrder) work,
    ///   at most three internal frames and 2,880 output samples; no suspension or I/O.
    public mutating func decodePayload(_ payload: Data, durationMilliseconds: Int) throws -> SILKDecodedPayload {
        guard [10, 20, 40, 60].contains(durationMilliseconds) else { throw SILKMonoDecoderError.invalidPayloadDuration }
        guard (1...1_275).contains(payload.count) else { throw SILKMonoDecoderError.invalidPayloadSize }
        var entropy = try OpusRangeDecoder(frame: payload)
        return try decodePayload(from: &entropy, durationMilliseconds: durationMilliseconds)
    }

    /// Decodes mono SILK syntax in a shared arithmetic interval for hybrid composition.
    /// - Parameters:
    ///   - decoder: Entropy state at the SILK header. Its full physical frame also
    ///     contains any following CELT syntax and raw tail; those bytes are retained.
    ///   - durationMilliseconds: Exactly ten, twenty, forty or sixty milliseconds.
    /// - Returns: Exact-duration 48kHz PCM16 and SILK accounting at the boundary
    ///   immediately before following redundancy/CELT syntax. No frame is reinitialized.
    /// - Throws: Invalid duration/size or underlying parameter/synthesis/range errors.
    ///   Both signal and arithmetic state remain unchanged on every error. No I/O,
    ///   suspension or task occurs; callers serialize access to mutable stream state.
    public mutating func decodePayload(from decoder: inout OpusRangeDecoder,
                                      durationMilliseconds: Int) throws -> SILKDecodedPayload {
        guard [10, 20, 40, 60].contains(durationMilliseconds) else { throw SILKMonoDecoderError.invalidPayloadDuration }
        guard (1...1_275).contains(decoder.frame.count) else { throw SILKMonoDecoderError.invalidPayloadSize }
        var working = self
        var entropy = decoder
        let internalDuration = durationMilliseconds == 10 ? 10 : 20
        let count = durationMilliseconds / internalDuration
        try working.channel.updateFrameDuration(milliseconds: internalDuration)
        var activity: [Bool] = []
        for _ in 0..<count { activity.append(try entropy.decodeBit(logProbability: 1)) }
        let hasRedundancy = try entropy.decodeBit(logProbability: 1)
        var redundancy = Array(repeating: false, count: count)
        if hasRedundancy {
            let mask: Int
            if count == 1 { mask = 1 }
            else {
                let cdf: [UInt8] = count == 2 ? [203, 150, 0] : [215, 195, 166, 125, 110, 82, 0]
                mask = try entropy.decodeSymbol(model: OpusProbabilityModel(inverseCDF: cdf)) + 1
            }
            for index in 0..<count { redundancy[index] = (mask & (1 << index)) != 0 }
            // Only entropy type/lag history matters when skipping LBRR. Its first
            // present frame is independent; ordinary frame zero overwrites that
            // history independently before any ordinary conditional frame follows.
            var skip = try SILKFrameParameterDecoder(sampleRate: sampleRate, frameDurationMilliseconds: internalDuration)
            for index in 0..<count where redundancy[index] {
                _ = try skip.decodeExcitation(
                    from: &entropy, voiceActivity: activity[index], lowBitrateRedundancy: true,
                    coding: index > 0 && redundancy[index - 1] ? .conditional : .independent
                )
            }
        }
        var frames: [SILKDecodedFrame] = []
        var output: [Int16] = []
        output.reserveCapacity(durationMilliseconds * 48)
        for index in 0..<count {
            let frame = try working.channel.decode(
                from: &entropy, voiceActivity: activity[index], coding: index == 0 ? .independent : .conditional
            )
            var aligned = [working.previousMonoSample]
            aligned.append(contentsOf: frame.pcm.dropLast())
            working.previousMonoSample = frame.pcm.last!
            output.append(contentsOf: working.resampler.process(aligned))
            frames.append(frame)
        }
        self = working
        decoder = entropy
        return SILKDecodedPayload(pcm48k: output, frames: frames, voiceActivity: activity,
                                  redundancy: redundancy, finalRange: entropy.finalRange, bitsUsed: entropy.bitsUsed)
    }
}

/// Fixed 8/12/16kHz to 48kHz decoder resampling with bounded scalar state.
/// All products and sums follow signed two's-complement scalar SILK arithmetic.
struct SILKDecoderResampler: Sendable {
    private let rate: Int
    private let delay: Int
    private var delaySamples: [Int16]
    private var allpass = Array(repeating: Int32(0), count: 6)
    private var fir = Array(repeating: Int16(0), count: 8)
    private static let fractions: [[Int16]] = [
        [189, -600, 617, 30567], [117, -159, -1070, 29704], [52, 221, -2392, 28276],
        [-4, 529, -3350, 26341], [-48, 758, -3956, 23973], [-80, 905, -4235, 21254],
        [-99, 972, -4222, 18278], [-107, 967, -3957, 15143], [-103, 896, -3487, 11950],
        [-91, 773, -2865, 8798], [-71, 611, -2143, 5784], [-46, 425, -1375, 2996]
    ]

    /// Initializes zero scalar filter and mode-delay memory for an already validated rate.
    /// - Parameter sampleRate: Caller guarantees exactly 8,000, 12,000 or 16,000 Hz.
    init(sampleRate: Int) {
        rate = sampleRate
        delay = sampleRate == 8_000 ? 0 : sampleRate == 12_000 ? 4 : 7
        delaySamples = Array(repeating: 0, count: delay)
    }

    /// Resamples one aligned internal frame while preserving its output-duration count.
    /// - Parameter input: Exactly ten or twenty milliseconds of internal-rate PCM16.
    /// - Returns: Six/four/three times the input count at 48kHz. The first millisecond
    ///   uses the normative rate-dependent delay buffer; later batches are at most 10ms.
    mutating func process(_ input: [Int16]) -> [Int16] {
        let firstCount = rate / 1_000 - delay
        let initial = delaySamples + input.prefix(firstCount)
        var output = interpolate(Array(initial))
        output.append(contentsOf: interpolate(Array(input.dropFirst(firstCount).prefix(input.count - rate / 1_000))))
        delaySamples = Array(input.suffix(delay))
        return output
    }

    /// Applies six allpass stages and twelve-phase symmetric eight-tap interpolation.
    /// - Parameter input: A nonempty integral-millisecond block with at most 20ms samples.
    /// - Returns: Exactly the corresponding 48kHz count, updating six IIR/eight FIR values.
    private mutating func interpolate(_ input: [Int16]) -> [Int16] {
        var output: [Int16] = []
        let increment = (rate * 2 * 65_536 + 47_999) / 48_000
        var start = 0
        while start < input.count {
            let count = min(rate / 100, input.count - start)
            var buffer = fir
            for sample in input[start..<(start + count)] {
                let scaled = Int32(sample) << 10
                buffer.append(allpassBranch(scaled, offset: 0, coefficients: [1746, 14986, -26453]))
                buffer.append(allpassBranch(scaled, offset: 3, coefficients: [6854, 25769, -9994]))
            }
            var position = 0
            while position < count * 131_072 {
                let phase = ((position & 65_535) * 12) >> 16
                let base = position >> 16
                var sum: Int32 = 0
                for tap in 0..<4 {
                    sum = sum &+ Int32(buffer[base + tap]) * Int32(Self.fractions[phase][tap])
                    sum = sum &+ Int32(buffer[base + 4 + tap]) * Int32(Self.fractions[11 - phase][3 - tap])
                }
                output.append(Int16(clamping: ((sum >> 14) &+ 1) >> 1))
                position += increment
            }
            fir = Array(buffer[(count * 2)..<(count * 2 + 8)])
            start += count
        }
        return output
    }

    /// Runs one three-stage Q10 allpass branch with fixed signed Q16 coefficients.
    /// - Parameters:
    ///   - input: One PCM16 input scaled to Q10.
    ///   - offset: Zero for the even branch or three for the odd branch.
    ///   - coefficients: Exactly three normative coefficients, the last negative.
    /// - Returns: Rounded, saturated PCM16; updates exactly three IIR history values.
    private mutating func allpassBranch(_ input: Int32, offset: Int, coefficients: [Int32]) -> Int16 {
        var value = input
        for stage in 0..<3 {
            let difference = value &- allpass[offset + stage]
            let product = Int32(truncatingIfNeeded: (Int64(difference) * Int64(coefficients[stage])) >> 16)
            let correction = stage == 2 ? difference &+ product : product
            let next = allpass[offset + stage] &+ correction
            allpass[offset + stage] = value &+ correction
            value = next
        }
        return Int16(clamping: ((value >> 9) &+ 1) >> 1)
    }
}
