// File: Sources/DiscordVoiceCodecs/OpusAudioDecoder.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

/* Copyright (c) 2010 Xiph.Org Foundation, Skype Limited
   Copyright (c) 2024 Arm Limited
   Written by Jean-Marc Valin and Koen Vos */
/*
   Redistribution and use in source and binary forms, with or without
   modification, are permitted provided that the following conditions
   are met:

   - Redistributions of source code must retain the above copyright
   notice, this list of conditions and the following disclaimer.

   - Redistributions in binary form must reproduce the above copyright
   notice, this list of conditions and the following disclaimer in the
   documentation and/or other materials provided with the distribution.

   THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
   ``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
   LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
   A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER
   OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
   EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
   PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
   PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
   LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
   NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
   SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/


// Ordinary mode orchestration adapted from libopus 1.6.1 src/opus_decoder.c.

import Foundation

/// Caller admission failures for ordinary 48kHz Opus decoding and recovery.
public enum OpusAudioDecoderError: Error, Sendable, Equatable {
    case invalidSampleCount, invalidRedundancy
}

/// One decoded or recovered interval in the normalized, unclipped float domain.
public struct OpusAudioDecodedFrame: Sendable, Equatable {
    public let samples: [Float]
    public let frameSampleCount: Int
    public let channelCount: Int
    /// Actual synthesis mode; nil identifies silence before any coded audio.
    public let mode: OpusMode?
    public let finalRange: UInt32
    public let redundancyByteCount: Int
    public let celtToSilkRedundancy: Bool
}

/// Owned ordinary SILK, CELT and hybrid decoding at the 48kHz Opus clock.
///
/// One SILK owner and one CELT owner preserve prediction across ordinary mode,
/// bandwidth, duration and coded-channel changes. Packet framing, shared entropy,
/// five-millisecond transition redundancy, squared-window fades, explicit PLC and
/// subsequent-packet in-band FEC are coordinated here. The output layout is fixed
/// at construction, independently of each packet's one or two coded channels.
///
/// Every call is synchronous and bounded to 120ms. Mutation must be serialized;
/// copies fork independent histories. Failed calls commit no state. Construction
/// and decoding perform no I/O, device work, native codec calls or task creation.
/// This owner handles ordinary packets, without multistream/container framing,
/// extension enhancement layers, output gain or integer-output soft clipping.
public struct OpusAudioDecoder: Sendable {
    public let channelCount: Int
    public private(set) var finalRange: UInt32 = 0
    /// Most recently returned packet/recovery duration in samples per channel.
    public private(set) var lastPacketDuration: Int = 0
    private var silk: SILKStereoDecoder
    private var celt: CELTFrameDecoder
    private var declaredMode: OpusMode?
    private var declaredFrameSampleCount = 120
    private var codedChannelCount: Int
    private var declaredBandwidth: OpusBandwidth = .fullband
    private var previousMode: OpusMode?
    private var previousRedundancy = false
    private var celtEndBand = 21

    /// Creates idle zero-history owners for a fixed output layout.
    /// - Parameter channelCount: One or two output channels, default one. Coded
    ///   packet channels may change freely without recreating this owner.
    /// - Throws: `CELTSynthesisError.invalidChannelCount` for another layout.
    public init(channelCount: Int = 1) throws {
        guard (1...2).contains(channelCount) else { throw CELTSynthesisError.invalidChannelCount }
        self.channelCount = channelCount
        codedChannelCount = channelCount
        silk = try SILKStereoDecoder(sampleRate: 16_000, outputChannelCount: channelCount)
        celt = try CELTFrameDecoder(channelCount: channelCount)
    }

    /// Discards predictor, resampler, overlap, loss and packet-format history.
    /// The output channel count is retained. Subsequent cold loss returns zeros;
    /// previously returned values and independent copies remain unchanged.
    public mutating func reset() {
        silk.reset()
        celt.reset()
        declaredMode = nil
        declaredFrameSampleCount = 120
        codedChannelCount = channelCount
        declaredBandwidth = .fullband
        previousMode = nil
        previousRedundancy = false
        celtEndBand = 21
        finalRange = 0
        lastPacketDuration = 0
    }

    /// Decodes all packed payloads atomically in wire order.
    /// - Parameter data: Complete ordinary packet with TOC, packing and optional
    ///   padding; parser bounds are 65,536 bytes, 1,275 bytes/payload and 120ms.
    /// - Returns: One result per packed payload. Concatenate `samples` for packet
    ///   audio; every sample uses the fixed output layout at 48kHz. Zero/one-byte
    ///   payloads invoke last-mode loss synthesis using the declared TOC duration.
    /// - Throws: Packet, entropy, synthesis or redundancy validation errors. Even
    ///   failure in the last packed payload preserves every pre-call history.
    public mutating func decode(_ data: Data) throws -> [OpusAudioDecodedFrame] {
        let packet = try OpusPacket(data)
        var working = self
        working.adopt(packet)
        var frames: [OpusAudioDecodedFrame] = []
        for range in packet.frameRanges {
            let payload = Data(packet.data[range])
            if payload.count <= 1 {
                frames.append(try working.loss(frameSampleCount: packet.frameSampleCount))
            } else {
                frames.append(try working.decodePayload(payload, recovering: false))
            }
        }
        working.lastPacketDuration = packet.sampleCount
        self = working
        return frames
    }

    /// Synthesizes an explicitly missing interval from bounded preceding history.
    /// - Parameter frameSampleCount: A positive multiple of 120 through 5,760
    ///   samples/channel, representing 2.5 through 120ms. Default 960 (20ms).
    /// - Returns: Exactly the requested duration, segmented according to the last
    ///   TOC and at most 20ms per PLC operation. Cold loss yields zeros. Final
    ///   range is zero because no compressed syntax is consumed.
    /// - Throws: `invalidSampleCount` or component errors, without state changes.
    public mutating func conceal(frameSampleCount: Int = 960) throws -> OpusAudioDecodedFrame {
        try Self.validateSampleCount(frameSampleCount)
        var working = self
        let result = try working.loss(frameSampleCount: frameSampleCount)
        working.lastPacketDuration = frameSampleCount
        self = working
        return result
    }

    /// Recovers a missing interval from the first payload of a following packet.
    /// - Parameters:
    ///   - data: The following complete ordinary packet, parsed without consuming
    ///     its ordinary audio. Decode it normally after returning the recovered PCM.
    ///   - frameSampleCount: Missing samples/channel, a positive multiple of 120
    ///     through 5,760. Any prefix beyond one payload duration uses PLC.
    /// - Returns: Exact missing-duration PCM. CELT, an insufficient duration, or a
    ///   preceding CELT declaration selects PLC; absent SILK LBRR also selects PLC.
    /// - Throws: Packet, duration, entropy or synthesis errors. All state remains
    ///   unchanged on failure, including the previously declared packet format.
    public mutating func recover(_ data: Data, frameSampleCount: Int) throws -> OpusAudioDecodedFrame {
        try Self.validateSampleCount(frameSampleCount)
        let packet = try OpusPacket(data)
        var working = self
        let result: OpusAudioDecodedFrame
        if frameSampleCount < packet.frameSampleCount || packet.mode == .celt || declaredMode == .celt {
            result = try working.loss(frameSampleCount: frameSampleCount)
        } else {
            var samples: [Float] = []
            if frameSampleCount > packet.frameSampleCount {
                samples = try working.loss(frameSampleCount: frameSampleCount - packet.frameSampleCount).samples
            }
            working.adopt(packet)
            let payload = Data(packet.data[packet.frameRanges[0]])
            let suffix = payload.count <= 1
                ? try working.loss(frameSampleCount: packet.frameSampleCount)
                : try working.decodePayload(payload, recovering: true)
            samples += suffix.samples
            result = working.result(samples: samples, mode: suffix.mode,
                                    redundancyByteCount: 0, celtToSilk: false)
        }
        working.lastPacketDuration = frameSampleCount
        self = working
        return result
    }

    /// Validates an explicit PLC/FEC duration before any state or allocation work.
    /// - Parameter count: Requested 48kHz samples per channel.
    /// - Throws: `invalidSampleCount` unless `count` is a multiple of 120 in 120...5760.
    private static func validateSampleCount(_ count: Int) throws {
        guard (120...5_760).contains(count), count.isMultiple(of: 120) else {
            throw OpusAudioDecoderError.invalidSampleCount
        }
    }

    /// Adopts an already parsed TOC before any payload in the packet is decoded.
    /// - Parameter packet: Structurally valid ordinary packet; no histories change.
    private mutating func adopt(_ packet: OpusPacket) {
        declaredMode = packet.mode
        declaredBandwidth = packet.bandwidth
        declaredFrameSampleCount = packet.frameSampleCount
        codedChannelCount = packet.channelCount
    }

    /// Aggregates bounded PLC chunks, preserving reference short-duration rounding.
    /// - Parameter frameSampleCount: Valid missing duration, or internal 5ms fade prefix.
    /// - Returns: Exactly the requested normalized PCM, with a zero final range.
    /// - Throws: Component errors; public callers operate on a private working copy.
    private mutating func loss(frameSampleCount: Int) throws -> OpusAudioDecodedFrame {
        var samples: [Float] = []
        var remaining = frameSampleCount
        var lastMode: OpusMode?
        while remaining > 0 {
            let mode = previousRedundancy ? OpusMode.celt : previousMode
            var count = min(remaining, declaredFrameSampleCount, 960)
            if mode != nil && count < 960 {
                if count > 480 { count = 480 }
                else if mode != .silk && count > 240 && count < 480 { count = 240 }
            }
            guard let mode else {
                samples += Array(repeating: 0, count: count * channelCount)
                remaining -= count
                continue
            }
            var pcm = Array(repeating: Float(0), count: count * channelCount)
            if mode != .celt {
                if previousMode == .celt { silk.reset() }
                let low = try silk.conceal(durationMilliseconds: max(10, count / 48)).pcm48k
                pcm = low.prefix(count * channelCount).map { Float($0) / 32768 }
            }
            if mode != .silk {
                if mode != previousMode && previousMode != nil && !previousRedundancy { celt.reset() }
                let high = try celt.conceal(frameSampleCount: count,
                    startBand: mode == .hybrid ? 17 : 0, endBand: celtEndBand).samples
                for index in pcm.indices { pcm[index] += high[index] }
            } else if previousMode == .hybrid {
                let tail = try celt.decode(Data([255, 255]), frameSampleCount: 120,
                    endBand: celtEndBand, codedChannelCount: codedChannelCount).samples
                for index in tail.indices { pcm[index] += tail[index] }
            }
            previousMode = mode
            previousRedundancy = false
            samples += pcm
            remaining -= count
            lastMode = mode
        }
        finalRange = 0
        return result(samples: samples, mode: lastMode, redundancyByteCount: 0, celtToSilk: false)
    }

    /// Decodes one nonempty ordinary/FEC payload on the caller's working copy.
    /// - Parameters:
    ///   - payload: Two through 1,275 bytes, including independently coded redundancy.
    ///   - recovering: True consumes only SILK LBRR while CELT uses concealment.
    /// - Returns: One TOC-duration interval with exact main/redundant range XOR.
    /// - Throws: Component errors or invalid redundancy bounds. No external resources
    ///   are touched; public callers discard this copy after any failure.
    private mutating func decodePayload(_ payload: Data, recovering: Bool) throws -> OpusAudioDecodedFrame {
        let mode = declaredMode!
        let count = declaredFrameSampleCount
        var entropy = try OpusRangeDecoder(frame: payload)
        var transition = previousMode != nil && (
            (mode == .celt && previousMode != .celt && !previousRedundancy)
            || (mode != .celt && previousMode == .celt))
        var transitionPCM: [Float] = []
        if transition && mode == .celt {
            transitionPCM = try loss(frameSampleCount: min(240, count)).samples
        }
        var samples = Array(repeating: Float(0), count: count * channelCount)
        var mainRange: UInt32 = 0
        if mode != .celt {
            if previousMode == .celt { silk.reset() }
            let rate: Int
            switch declaredBandwidth {
            case .narrowband: rate = 8_000
            case .mediumband: rate = 12_000
            default: rate = 16_000
            }
            try silk.updateSampleRate(rate)
            let low: [Int16]
            if recovering {
                let recovered = try silk.recoverPayload(payload, durationMilliseconds: count / 48,
                                                        codedChannelCount: codedChannelCount)
                low = recovered.pcm48k
                mainRange = recovered.finalRange
            } else {
                low = try silk.decodePayload(from: &entropy, durationMilliseconds: count / 48,
                                             codedChannelCount: codedChannelCount).pcm48k
                mainRange = entropy.finalRange
            }
            samples = low.map { Float($0) / 32768 }
        }
        var redundancyBytes = 0
        var celtToSilk = false
        if !recovering && mode != .celt && entropy.bitsUsed + 17 + (mode == .hybrid ? 20 : 0) <= payload.count * 8 {
            let redundant = mode == .silk ? true : try entropy.decodeBit(logProbability: 12)
            if redundant {
                celtToSilk = try entropy.decodeBit(logProbability: 1)
                redundancyBytes = mode == .hybrid ? Int(try entropy.decodeUniform(total: 256)) + 2
                    : payload.count - (entropy.bitsUsed + 7) / 8
                guard redundancyBytes >= 2, (payload.count - redundancyBytes) * 8 >= entropy.bitsUsed else {
                    throw OpusAudioDecoderError.invalidRedundancy
                }
                try entropy.reduceStorage(to: payload.count - redundancyBytes)
                mainRange = entropy.finalRange
                transition = false
            }
        }
        if transition && mode != .celt {
            transitionPCM = try loss(frameSampleCount: min(240, count)).samples
        }
        switch declaredBandwidth {
        case .narrowband: celtEndBand = 13
        case .mediumband, .wideband: celtEndBand = 17
        case .superwideband: celtEndBand = 19
        case .fullband: celtEndBand = 21
        }
        let redundant = Data(payload.suffix(redundancyBytes))
        var redundantFrame: CELTDecodedFrame?
        if redundancyBytes > 0 && celtToSilk {
            redundantFrame = try celt.decode(redundant, frameSampleCount: 240,
                endBand: celtEndBand, codedChannelCount: codedChannelCount)
        }
        if mode != .silk {
            if mode != previousMode && previousMode != nil && !previousRedundancy { celt.reset() }
            let high: [Float]
            if recovering {
                let concealed = try celt.conceal(frameSampleCount: min(960, count),
                    startBand: mode == .hybrid ? 17 : 0, endBand: celtEndBand)
                high = concealed.samples
                // FEC carries the CELT PLC random state as its final range.
                // Explicit loss clears that value only at the enclosing Opus layer.
                mainRange = concealed.seed
            } else {
                let decoded = try celt.decode(from: &entropy, frameSampleCount: count,
                    startBand: mode == .hybrid ? 17 : 0, endBand: celtEndBand,
                    codedChannelCount: codedChannelCount)
                high = decoded.samples
                mainRange = decoded.finalRange
            }
            for index in high.indices { samples[index] += high[index] }
        } else if previousMode == .hybrid && !(redundancyBytes > 0 && celtToSilk && previousRedundancy) {
            let tail = try celt.decode(Data([255, 255]), frameSampleCount: 120,
                endBand: celtEndBand, codedChannelCount: codedChannelCount).samples
            for index in tail.indices { samples[index] += tail[index] }
        }
        if redundancyBytes > 0 && !celtToSilk {
            celt.reset()
            redundantFrame = try celt.decode(redundant, frameSampleCount: 240,
                endBand: celtEndBand, codedChannelCount: codedChannelCount)
            let offset = (count - 120) * channelCount
            fade(from: samples, sourceOffset: offset, to: redundantFrame!.samples,
                targetOffset: 120 * channelCount, output: &samples, outputOffset: offset)
        }
        if let redundantFrame, celtToSilk, previousMode != .silk || previousRedundancy {
            samples.replaceSubrange(0..<(120 * channelCount), with: redundantFrame.samples.prefix(120 * channelCount))
            fade(from: redundantFrame.samples, sourceOffset: 120 * channelCount,
                to: samples, targetOffset: 120 * channelCount, output: &samples, outputOffset: 120 * channelCount)
        }
        if transition {
            if count >= 240 {
                samples.replaceSubrange(0..<(120 * channelCount), with: transitionPCM.prefix(120 * channelCount))
                fade(from: transitionPCM, sourceOffset: 120 * channelCount, to: samples,
                    targetOffset: 120 * channelCount, output: &samples, outputOffset: 120 * channelCount)
            } else {
                fade(from: transitionPCM, sourceOffset: 0, to: samples, targetOffset: 0,
                    output: &samples, outputOffset: 0)
            }
        }
        finalRange = payload.count - redundancyBytes <= 1 ? 0 : mainRange ^ (redundantFrame?.finalRange ?? 0)
        previousMode = mode
        previousRedundancy = redundancyBytes > 0 && !celtToSilk
        return result(samples: samples, mode: mode, redundancyByteCount: redundancyBytes, celtToSilk: celtToSilk)
    }

    /// Wraps owned PCM with the current range and fixed output layout.
    /// - Parameters:
    ///   - samples: Complete interleaved PCM, count divisible by output channels.
    ///   - mode: Actual synthesis mode, or nil for cold silence.
    ///   - redundancyByteCount: Independently decoded CELT suffix size, or zero.
    ///   - celtToSilk: Direction flag, meaningful only for nonzero redundancy.
    /// - Returns: Immutable result without additional synthesis or state changes.
    private func result(samples: [Float], mode: OpusMode?, redundancyByteCount: Int,
                        celtToSilk: Bool) -> OpusAudioDecodedFrame {
        OpusAudioDecodedFrame(samples: samples, frameSampleCount: samples.count / channelCount,
            channelCount: channelCount, mode: mode, finalRange: finalRange,
            redundancyByteCount: redundancyByteCount, celtToSilkRedundancy: celtToSilk)
    }

    /// Mixes exactly 120 samples/channel using the normative squared CELT window.
    /// - Parameters:
    ///   - from: Initial interleaved source, permitted to alias pre-mutation output.
    ///   - sourceOffset: First scalar initial-source position.
    ///   - to: Final interleaved source, permitted to alias pre-mutation output.
    ///   - targetOffset: First scalar final-source position.
    ///   - output: Destination with capacity for the complete 2.5ms interval.
    ///   - outputOffset: First scalar destination position. Bounds are guaranteed
    ///     by the admitted 5ms redundant/transition frames and TOC frame duration.
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
