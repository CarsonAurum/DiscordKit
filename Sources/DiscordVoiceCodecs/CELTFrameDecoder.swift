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

/// Caller-driven, ordinary no-loss CELT frame decoding with bounded owned history.
///
/// This composes RFC 6716 sections 4.3.1–4.3.7: segmented flags, coarse/fine/final
/// energies, bit allocation, recursive shapes, anti-collapse and signal synthesis.
/// The coded channel count is fixed; frame duration and upper band can change.
/// Entropy and synthesis changes commit together only after the complete frame
/// succeeds. Copying this value creates an independent stream through Swift's
/// value semantics. Calls are synchronous and require exclusive mutable access;
/// construction, reset and decoding start no tasks or I/O.
///
/// Input excludes the Opus TOC/packing bytes. This primitive does not implement
/// SILK, hybrid mode transitions, redundant frames, in-band FEC or packet loss.
/// In particular, zero/one-byte frames require an enclosing loss policy and are
/// rejected here. Component agreement does not establish complete Opus conformance.
public struct CELTFrameDecoder: Sendable {
    public let channelCount: Int
    private var previousEnergies: [Float]
    private var previousLogEnergies: [Float]
    private var previousLogEnergies2: [Float]
    private var synthesis: CELTSynthesis
    private var seed: UInt32 = 0

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
    }

    /// Reconstructs one complete ordinary CELT frame, committing history atomically.
    /// - Parameters:
    ///   - frame: Owned/copy-on-write compressed bytes excluding Opus TOC/packing;
    ///     exactly 2...1,275 bytes. No external pointer is retained.
    ///   - frameSampleCount: Exactly 120, 240, 480 or 960 samples/channel at 48 kHz.
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
                                endBand: Int = 21) throws -> CELTDecodedFrame {
        guard (2...1_275).contains(frame.count) else { throw CELTFrameDecoderError.invalidFrame }
        var working = self
        let result = try working.decodeFrame(frame, frameSampleCount: frameSampleCount, endBand: endBand)
        self = working
        return result
    }

    /// Performs the normative ordinary frame pipeline on an already private stream copy.
    /// - Parameters:
    ///   - frame: Admitted bounded raw CELT bytes; every byte remains caller-owned.
    ///   - frameSampleCount: Requested validated-by-component CELT duration.
    ///   - endBand: Requested active bandwidth; preceding bands always start at zero.
    /// - Returns: PCM and exact final arithmetic state after synthesis/history updates.
    /// - Throws: Component or physical-budget failures; callers discard this private copy.
    private mutating func decodeFrame(_ frame: Data, frameSampleCount: Int,
                                      endBand: Int) throws -> CELTDecodedFrame {
        let header = try CELTFrameHeader(frameSampleCount: frameSampleCount, channelCount: channelCount,
                                         endBand: endBand)
        var decoder = try OpusRangeDecoder(frame: frame)
        let prefix = try header.decodePrefix(from: &decoder)
        var energies: [Float]
        var coefficients: [Float]
        if prefix.silence {
            energies = Array(repeating: -28, count: channelCount * 21)
            coefficients = Array(repeating: 0, count: frameSampleCount * channelCount)
        } else {
            let quantizer = try CELTEnergyQuantizer(frameSampleCount: frameSampleCount,
                channelCount: channelCount, endBand: endBand)
            energies = try quantizer.decodeCoarse(previous: Array(previousEnergies.prefix(channelCount * 21)),
                                                   from: &decoder).energies
            let fields = try header.decodeAfterCoarse(isTransient: prefix.isTransient, from: &decoder)
            let allocator = try CELTBitAllocation(frameSampleCount: frameSampleCount,
                channelCount: channelCount, endBand: endBand, allocationTrim: fields.allocationTrim)
            let allocation = try allocator.decode(totalEighthBits: fields.allocationEighthBits,
                                                   dynamicOffsets: fields.dynamicOffsets, from: &decoder)
            energies = try quantizer.decodeFine(energies: energies,
                                                 bitCounts: allocation.fineEnergyBits, from: &decoder)
            let shapes = try CELTShapeFrameCoding(frameSampleCount: frameSampleCount,
                channelCount: channelCount, endBand: endBand, transient: prefix.isTransient,
                timeFrequencyChanges: fields.timeFrequencyChanges, spreading: fields.spreading)
            let shaped = try shapes.decode(allocation: allocation,
                totalEighthBits: frame.count * 64 - (fields.antiCollapseReserved ? 8 : 0),
                seed: seed, from: &decoder)
            coefficients = shaped.coefficients
            let antiCollapse = fields.antiCollapseReserved ? try decoder.decodeRawBits(count: 1) != 0 : false
            energies = try quantizer.decodeFinal(energies: energies, fineBitCounts: allocation.fineEnergyBits,
                priorities: allocation.finePriorities, remainingBits: max(0, frame.count * 8 - decoder.bitsUsed),
                from: &decoder)
            if antiCollapse {
                coefficients = try shapes.applyAntiCollapse(coefficients, collapseMasks: shaped.collapseMasks,
                    energies: energies, previous: previousLogEnergies, previous2: previousLogEnergies2,
                    allocation: allocation, seed: shaped.seed)
            }
        }
        guard decoder.bitsUsed <= frame.count * 8 else { throw CELTFrameDecoderError.entropyBudgetExceeded }
        let samples = try synthesis.synthesize(normalizedCoefficients: coefficients, bandLogEnergies: energies,
            frameSampleCount: frameSampleCount, endBand: endBand, isTransient: prefix.isTransient,
            postfilter: prefix.postfilter, silence: prefix.silence)
        updateEnergyHistory(energies, isTransient: prefix.isTransient, endBand: endBand)
        seed = decoder.finalRange
        return CELTDecodedFrame(samples: samples, frameSampleCount: frameSampleCount,
            channelCount: channelCount, finalRange: decoder.finalRange, bitsUsed: decoder.bitsUsed,
            fractionalBitsUsed: decoder.fractionalBitsUsed, isTransient: prefix.isTransient,
            isSilence: prefix.silence)
    }

    /// Advances the two preceding envelope histories exactly once after successful synthesis.
    /// - Parameters:
    ///   - energies: Current channel-major 21-band envelope, duplicated into the unused
    ///     second channel for mono as required by anti-collapse history semantics.
    ///   - isTransient: Short-block frames retain the minimum recent log envelope;
    ///     ordinary long frames advance both prior frame envelopes.
    ///   - endBand: Exclusive current bandwidth; inactive predictors reset to zero and
    ///     inactive log histories to -28 so a later bandwidth increase has known state.
    /// This bounded synchronous helper cannot fail and owns all resulting array storage.
    private mutating func updateEnergyHistory(_ energies: [Float], isTransient: Bool, endBand: Int) {
        previousEnergies = channelCount == 1 ? energies + energies : energies
        if isTransient {
            for index in 0..<42 { previousLogEnergies[index] = min(previousLogEnergies[index], previousEnergies[index]) }
        } else {
            previousLogEnergies2 = previousLogEnergies
            previousLogEnergies = previousEnergies
        }
        for channel in 0..<2 {
            for band in endBand..<21 {
                let index = channel * 21 + band
                previousEnergies[index] = 0
                previousLogEnergies[index] = -28
                previousLogEnergies2[index] = -28
            }
        }
    }
}
