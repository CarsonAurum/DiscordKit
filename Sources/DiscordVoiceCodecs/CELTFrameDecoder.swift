// File: Sources/DiscordVoiceCodecs/CELTFrameDecoder.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

// Energy probability tables and quantization adapted from libopus 1.6.1 celt/quant_bands.c and celt/laplace.c.
// Copyright (c) 2007-2008 CSIRO
// Copyright (c) 2007-2009 Xiph.Org Foundation
// Written by Jean-Marc Valin
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
// - Redistributions of source code must retain the above copyright notice,
//   this list of conditions and the following disclaimer.
// - Redistributions in binary form must reproduce the above copyright notice,
//   this list of conditions and the following disclaimer in the documentation
//   and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
// IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
// ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
// LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
// CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
// SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
// INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
// CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
// ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
// POSSIBILITY OF SUCH DAMAGE.

import Foundation

/// A raw CELT frame could not be admitted or exceeded its physical entropy budget.
public enum CELTFrameDecoderError: Error, Sendable, Equatable {
    case invalidFrame, entropyBudgetExceeded
}

/// One independently owned ordinary CELT frame reconstructed at 48 kHz.
/// Samples are interleaved floating-point PCM, including synthesis delay/history;
/// finite peaks can exceed unity, as with the reference floating-point decoder.
/// This value does not describe an Opus packet, loss concealment or a network session.
public struct CELTDecodedFrame: Sendable, Equatable {
    public let samples: [Float]
    public let frameSampleCount: Int
    public let channelCount: Int
    public let finalRange: UInt32
    /// Actual owned arithmetic usage. Silence retains header usage rather than
    /// the reference decoder's virtual advance to the physical end of the frame.
    public let bitsUsed: Int
    /// Actual eighth-bit usage; the same silence accounting distinction applies.
    public let fractionalBitsUsed: Int
    public let isTransient: Bool
    public let isSilence: Bool
}

/// Caller-driven CELT frame decoding and loss concealment with bounded owned history.
///
/// This composes RFC 6716 sections 4.3.1–4.3.7: segmented flags, coarse/fine/final
/// energies, bit allocation, recursive shapes, anti-collapse and signal synthesis.
/// The output channel count is fixed; coded channels, duration and active bands can change.
/// Entropy and synthesis changes commit together only after the complete frame
/// succeeds. Copying this value creates an independent stream through Swift's
/// value semantics. Calls are synchronous and require exclusive mutable access;
/// construction, reset and decoding start no tasks or I/O.
///
/// Input excludes the Opus TOC/packing bytes. This primitive does not implement
/// SILK, Opus mode transitions, redundant frames or in-band FEC.
/// In particular, zero/one-byte frames require an enclosing loss policy and are
/// rejected here. Component agreement does not establish complete Opus conformance.
public struct CELTFrameDecoder: Sendable {
    public let channelCount: Int
    private var previousEnergies: [Float]
    private var previousLogEnergies: [Float]
    private var previousLogEnergies2: [Float]
    private var synthesis: CELTSynthesis
    private var seed: UInt32 = 0
    private var backgroundLogEnergies = Array(repeating: Float(0), count: 42)
    private var lossDuration = 0

    /// Creates an idle, zero-history decoder without opening devices or allocating tasks.
    /// - Parameter channelCount: Exactly one or two coded/output channels; default one.
    /// - Throws: `CELTSynthesisError.invalidChannelCount` for other channel counts.
    ///   Histories contain at most 42 band energies plus the bounded synthesis state.
    public init(channelCount: Int = 1) throws {
        synthesis = try CELTSynthesis(channelCount: channelCount)
        self.channelCount = channelCount
        previousEnergies = Array(repeating: 0, count: 42)
        previousLogEnergies = Array(repeating: -28, count: 42)
        previousLogEnergies2 = Array(repeating: -28, count: 42)
    }

    /// Discards the complete predictor, anti-collapse, overlap, pitch and deemphasis history.
    /// The next frame behaves as on a newly constructed decoder. This synchronous
    /// operation retains the configured channel count and performs no external cleanup.
    public mutating func reset() {
        previousEnergies = Array(repeating: 0, count: 42)
        previousLogEnergies = Array(repeating: -28, count: 42)
        previousLogEnergies2 = Array(repeating: -28, count: 42)
        synthesis.reset()
        seed = 0
        backgroundLogEnergies = Array(repeating: 0, count: 42)
        lossDuration = 0
    }

    /// Reconstructs one complete ordinary CELT frame, committing history atomically.
    /// - Parameters:
    ///   - frame: Owned/copy-on-write compressed bytes excluding Opus TOC/packing;
    ///     exactly 2...1,275 bytes. No external pointer is retained.
    ///   - frameSampleCount: Exactly 120, 240, 480 or 960 samples/channel at 48 kHz.
    ///   - codedChannelCount: One or two coded channels; nil uses the configured output
    ///     layout. Channel conversion retains independent output histories and normative
    ///     two-channel band predictors. Stereo-to-mono suppresses intensity-band phase
    ///     inversion per RFC 8251, then mixes independently denormalized spectra.
    ///   - endBand: Exclusive upper band in `1...21`; default 21. The enclosing TOC
    ///     maps narrow/wide/superwide/full bandwidth to 13/17/19/21 respectively.
    /// - Returns: Exactly `frameSampleCount * channelCount` owned interleaved samples
    ///   and final entropy accounting. Silence reports actual header usage without
    ///   the reference's virtual EOF advance; final range and PCM are unaffected.
    ///   Success replaces the prior stream histories.
    /// - Throws: `invalidFrame` before decoding for an inadmissible byte count;
    ///   configuration, entropy, allocation, shape or synthesis errors otherwise;
    ///   `entropyBudgetExceeded` if syntax consumes more whole bits than physically
    ///   available. Every failure leaves all stream histories unchanged, allowing a
    ///   caller to select its explicit reset/concealment/recovery policy.
    public mutating func decode(_ frame: Data, frameSampleCount: Int,
                                endBand: Int = 21, codedChannelCount: Int? = nil) throws -> CELTDecodedFrame {
        guard (2...1_275).contains(frame.count) else { throw CELTFrameDecoderError.invalidFrame }
        var working = self
        var entropy = try OpusRangeDecoder(frame: frame)
        let result = try working.decodeFrame(from: &entropy, frameSampleCount: frameSampleCount,
                                             startBand: 0, endBand: endBand, codedChannelCount: codedChannelCount ?? channelCount)
        self = working
        return result
    }

    /// Synthesizes one missing CELT interval through normative periodic/noise concealment.
    /// - Parameters:
    ///   - frameSampleCount: Exactly 120, 240, 480 or 960 samples/channel at 48kHz.
    ///   - startBand: First active global band in `0...20`; default zero. Hybrid
    ///     high-band concealment uses 17 and selects the noise path.
    ///   - endBand: Exclusive active band greater than startBand and at most 21.
    /// - Returns: Owned interleaved PCM and explicit concealment diagnostics. Periodic
    ///   prediction uses bounded pitch/LPC state, then long loss fades to envelope-shaped
    ///   noise. This advances signal, energy and random history without consuming bytes.
    /// - Throws: Synthesis format/range errors without changing any history. Construction
    ///   and this synchronous bounded operation start no tasks, device work or I/O.
    /// This is CELT PLC, not SILK concealment, FEC or a full Opus mode-loss policy.
    public mutating func conceal(frameSampleCount: Int, startBand: Int = 0,
                                 endBand: Int = 21) throws -> CELTConcealedFrame {
        var working = self
        let result = try working.synthesis.conceal(frameSampleCount: frameSampleCount,
            bandLogEnergies: Array(previousEnergies.prefix(channelCount * 21)),
            backgroundLogEnergies: Array(backgroundLogEnergies.prefix(channelCount * 21)),
            seed: seed, startBand: startBand, endBand: endBand)
        working.previousEnergies.replaceSubrange(0..<(channelCount * 21), with: result.bandLogEnergies)
        working.seed = result.seed
        working.lossDuration = result.lossDuration
        self = working
        return result
    }

    /// Continues CELT decoding from a shared SILK/CELT arithmetic interval.
    /// - Parameters:
    ///   - decoder: Bounded range decoder after any SILK and redundancy-header syntax.
    ///     Its frame excludes separately coded transition redundancy. Raw bits remain
    ///     anchored at this frame's end; no reinitialization of the arithmetic state occurs.
    ///   - frameSampleCount: Exactly 120, 240, 480 or 960 samples per channel at 48kHz.
    ///   - startBand: Inclusive active global band, `0...20`; hybrid uses 17.
    ///   - endBand: Exclusive active global band greater than startBand and at most 21.
    ///   - codedChannelCount: One or two entropy-coded channels; nil uses the output
    ///     layout. The output remains configured while coded channels may vary per frame.
    /// - Returns: Complete CELT contribution and shared final range/accounting. Hybrid
    ///   callers add the separately decoded SILK contribution at the same sample clock.
    /// - Throws: The ordinary frame/component errors, preserving both this stream and
    ///   the caller's complete arithmetic state. This method performs no I/O or tasks.
    public mutating func decode(from decoder: inout OpusRangeDecoder, frameSampleCount: Int,
                                startBand: Int = 0, endBand: Int = 21,
                                codedChannelCount: Int? = nil) throws -> CELTDecodedFrame {
        guard (2...1_275).contains(decoder.frame.count) else { throw CELTFrameDecoderError.invalidFrame }
        var working = self
        var entropy = decoder
        let result = try working.decodeFrame(from: &entropy, frameSampleCount: frameSampleCount,
                                             startBand: startBand, endBand: endBand,
                                             codedChannelCount: codedChannelCount ?? channelCount)
        self = working
        decoder = entropy
        return result
    }

    /// Performs the complete pipeline on private signal and arithmetic state copies.
    /// - Parameters:
    ///   - decoder: Shared entropy state with complete bounded physical-frame storage.
    ///   - frameSampleCount: Requested CELT duration, validated by header construction.
    ///   - startBand: First active band, validated before arithmetic mutation.
    ///   - endBand: Exclusive active upper band, validated before arithmetic mutation.
    ///   - codedChannelCount: One or two channels represented by entropy syntax.
    /// - Returns: PCM and exact final arithmetic state after synthesis/history updates.
    /// - Throws: Component or physical-budget failures; callers discard both private copies.
    private mutating func decodeFrame(from decoder: inout OpusRangeDecoder, frameSampleCount: Int,
                                      startBand: Int, endBand: Int, codedChannelCount: Int) throws -> CELTDecodedFrame {
        let outputChannelCount = channelCount
        let channelCount = codedChannelCount
        let header = try CELTFrameHeader(frameSampleCount: frameSampleCount, channelCount: channelCount,
                                         startBand: startBand, endBand: endBand)
        if channelCount == 1 {
            for band in 0..<21 { previousEnergies[band] = max(previousEnergies[band], previousEnergies[21 + band]) }
        }
        let frameByteCount = decoder.frame.count
        let prefix = try header.decodePrefix(from: &decoder)
        var energies: [Float]
        var coefficients: [Float]
        if prefix.silence {
            energies = Array(repeating: -28, count: channelCount * 21)
            coefficients = Array(repeating: 0, count: frameSampleCount * channelCount)
        } else {
            let quantizer = try CELTEnergyQuantizer(frameSampleCount: frameSampleCount,
                channelCount: channelCount, startBand: startBand, endBand: endBand)
            var headerProbe = decoder
            let intra = headerProbe.bitsUsed + 3 <= frameByteCount * 8
                ? try headerProbe.decodeBit(logProbability: 3) : false
            if !intra && lossDuration != 0 {
                recoverEnergyPrediction(frameSampleCount: frameSampleCount, startBand: startBand, endBand: endBand)
            }
            energies = try quantizer.decodeCoarse(previous: Array(previousEnergies.prefix(channelCount * 21)),
                                                   from: &decoder).energies
            let fields = try header.decodeAfterCoarse(isTransient: prefix.isTransient, from: &decoder)
            let allocator = try CELTBitAllocation(frameSampleCount: frameSampleCount,
                channelCount: channelCount, startBand: startBand, endBand: endBand,
                allocationTrim: fields.allocationTrim)
            let allocation = try allocator.decode(totalEighthBits: fields.allocationEighthBits,
                                                   dynamicOffsets: fields.dynamicOffsets, from: &decoder)
            energies = try quantizer.decodeFine(energies: energies,
                                                 bitCounts: allocation.fineEnergyBits, from: &decoder)
            let shapes = try CELTShapeFrameCoding(frameSampleCount: frameSampleCount,
                channelCount: channelCount, startBand: startBand, endBand: endBand, transient: prefix.isTransient,
                timeFrequencyChanges: fields.timeFrequencyChanges, spreading: fields.spreading,
                disableInversion: outputChannelCount == 1)
            let shaped = try shapes.decode(allocation: allocation,
                totalEighthBits: frameByteCount * 64 - (fields.antiCollapseReserved ? 8 : 0),
                seed: seed, from: &decoder)
            coefficients = shaped.coefficients
            let antiCollapse = fields.antiCollapseReserved ? try decoder.decodeRawBits(count: 1) != 0 : false
            energies = try quantizer.decodeFinal(energies: energies, fineBitCounts: allocation.fineEnergyBits,
                priorities: allocation.finePriorities, remainingBits: max(0, frameByteCount * 8 - decoder.bitsUsed),
                from: &decoder)
            if antiCollapse {
                coefficients = try shapes.applyAntiCollapse(coefficients, collapseMasks: shaped.collapseMasks,
                    energies: energies, previous: previousLogEnergies, previous2: previousLogEnergies2,
                    allocation: allocation, seed: shaped.seed)
            }
        }
        guard decoder.bitsUsed <= frameByteCount * 8 else { throw CELTFrameDecoderError.entropyBudgetExceeded }
        let samples = try synthesis.synthesize(normalizedCoefficients: coefficients, bandLogEnergies: energies,
            frameSampleCount: frameSampleCount, startBand: startBand, endBand: endBand, isTransient: prefix.isTransient,
            postfilter: prefix.postfilter, silence: prefix.silence, codedChannelCount: channelCount)
        updateEnergyHistory(energies, isTransient: prefix.isTransient, frameHistoryMultiple: frameSampleCount / 120,
                            startBand: startBand, endBand: endBand, codedChannelCount: channelCount)
        seed = decoder.finalRange
        lossDuration = 0
        return CELTDecodedFrame(samples: samples, frameSampleCount: frameSampleCount,
            channelCount: outputChannelCount, finalRange: decoder.finalRange, bitsUsed: decoder.bitsUsed,
            fractionalBitsUsed: decoder.fractionalBitsUsed, isTransient: prefix.isTransient,
            isSilence: prefix.silence)
    }

    /// Advances the two preceding envelope histories exactly once after successful synthesis.
    /// - Parameters:
    ///   - energies: Current channel-major 21-band envelope, duplicated into the unused
    ///     second channel for mono as required by anti-collapse history semantics.
    ///   - isTransient: Short-block frames retain the minimum recent log envelope;
    ///     ordinary long frames advance both prior frame envelopes.
    ///   - frameHistoryMultiple: Frame length in 120-sample units, exactly one/two/four/eight.
    ///   - codedChannelCount: One or two coded channels; mono envelopes duplicate
    ///     into both reference history slots independently of the output layout.
    ///   - startBand: Inclusive current bandwidth; lower bands are reset for hybrid.
    ///   - endBand: Exclusive current bandwidth; inactive predictors reset to zero and
    ///     inactive log histories to -28 so a later bandwidth increase has known state.
    /// This bounded synchronous helper cannot fail and owns all resulting array storage.
    private mutating func updateEnergyHistory(_ energies: [Float], isTransient: Bool, frameHistoryMultiple: Int,
                                             startBand: Int, endBand: Int, codedChannelCount: Int) {
        previousEnergies = codedChannelCount == 1 ? energies + energies : energies
        if isTransient {
            for index in 0..<42 { previousLogEnergies[index] = min(previousLogEnergies[index], previousEnergies[index]) }
        } else {
            previousLogEnergies2 = previousLogEnergies
            previousLogEnergies = previousEnergies
        }
        let increment = Float(min(160, lossDuration + frameHistoryMultiple)) * 0.001
        for index in 0..<42 {
            backgroundLogEnergies[index] = min(backgroundLogEnergies[index] + increment, previousEnergies[index])
        }
        for channel in 0..<2 {
            for band in 0..<21 where band < startBand || band >= endBand {
                let index = channel * 21 + band
                previousEnergies[index] = 0
                previousLogEnergies[index] = -28
                previousLogEnergies2[index] = -28
            }
        }
    }
    /// Limits inter-predicted energy after loss before ordinary coarse-energy parsing.
    /// - Parameters:
    ///   - frameSampleCount: Admitted ordinary CELT sample count, selecting duration safety.
    ///   - startBand: Inclusive admitted band; inactive predictors remain untouched here.
    ///   - endBand: Exclusive admitted band. Both channel histories use the same window.
    /// Declining envelopes extrapolate a bounded slope; other envelopes use the recent
    /// minimum. This follows the scalar reference loss-recovery guard and cannot throw.
    private mutating func recoverEnergyPrediction(frameSampleCount: Int, startBand: Int, endBand: Int) {
        let missing = min(10, lossDuration / (frameSampleCount / 120))
        let safety: Float = frameSampleCount == 120 ? 1.5 : (frameSampleCount == 240 ? 0.5 : 0)
        for channel in 0..<2 {
            for band in startBand..<endBand {
                let index = channel * 21 + band
                let energy = previousEnergies[index]
                let previous = previousLogEnergies[index]
                let previous2 = previousLogEnergies2[index]
                if energy < max(previous, previous2) {
                    let slope = min(2, max(previous - energy, (previous2 - energy) * 0.5))
                    previousEnergies[index] = max(-20, energy - max(0, Float(1 + missing) * slope))
                } else {
                    previousEnergies[index] = min(energy, min(previous, previous2))
                }
                previousEnergies[index] -= safety
            }
        }
    }

}
