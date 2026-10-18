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

/// A caller-supplied PCM frame or compressed storage budget was invalid.
public enum CELTFrameEncoderError: Error, Sendable, Equatable {
    case invalidSamples, invalidFrameByteCount, entropyBudgetExceeded
}

/// An ordinary owned CELT frame, excluding the enclosing Opus TOC/packing header.
public struct CELTEncodedFrame: Sendable, Equatable {
    public let bytes: Data
    public let finalRange: UInt32
    public let bitsUsed: Int
    public let fractionalBitsUsed: Int
}

/// A basic owned long-block CELT audio encoder with explicit bounded frame storage.
///
/// This encodes normalized PCM through preemphasis, low-overlap analysis, band
/// normalization, envelope quantization, ordinary bit allocation and recursive
/// mono/stereo shape coding. It emits valid ordinary CELT syntax rather than
/// reproducing the reference encoder's perceptual decisions or compressed bytes.
/// Frame duration, coded channels and upper band are fixed for one stream.
///
/// The encoder deliberately selects long blocks, no pitch prefilter, normal
/// spreading and ordinary allocation trim. It implements no transient detector,
/// psychoacoustic rate/distortion search, VBR, DTX, FEC, PLC, SILK or hybrid
/// orchestration. These limitations matter for quality and complete Opus claims.
/// Construction starts no I/O/tasks; exclusive mutable access serializes calls.
/// All input validation and processing are synchronous with bounded per-frame
/// storage. Failed calls preserve the entire previous audio/energy/entropy state.
public struct CELTFrameEncoder: Sendable {
    public let frameSampleCount: Int
    public let channelCount: Int
    public let endBand: Int
    private var analysis: CELTTransformStream
    private var preemphasisMemory: [Float]
    private var previousEnergies: [Float]
    private var seed: UInt32 = 0
    private static let bandMeans: [Float] = [
        103, 100, 92, 85, 81, 77, 72, 70, 78, 75, 73, 71, 78, 74, 69, 72, 70, 74, 76, 71, 60,
    ].map { $0 / 16 }

    /// Creates a fixed-duration, idle ordinary CELT encoding stream.
    /// - Parameters:
    ///   - frameSampleCount: Exactly 120, 240, 480 or 960 samples/channel at 48 kHz.
    ///   - channelCount: Exactly one or two coded channels; default one.
    ///   - endBand: Exclusive upper band in `1...21`; default 21. Standard Opus TOCs
    ///     use 13/17/19/21 for narrow/wide/superwide/full bandwidth respectively.
    /// - Throws: `CELTTransformError` for invalid duration/channels, or
    ///   `CELTBitAllocationError.invalidBandRange` for an invalid upper band.
    public init(frameSampleCount: Int, channelCount: Int = 1, endBand: Int = 21) throws {
        let transform = try CELTTransform(frameSampleCount: frameSampleCount, channelCount: channelCount)
        _ = try CELTBitAllocation(frameSampleCount: frameSampleCount, channelCount: channelCount, endBand: endBand)
        self.frameSampleCount = frameSampleCount
        self.channelCount = channelCount
        self.endBand = endBand
        analysis = CELTTransformStream(transform: transform)
        preemphasisMemory = Array(repeating: 0, count: channelCount)
        previousEnergies = Array(repeating: 0, count: channelCount * 21)
    }

    /// Discards analysis overlap, preemphasis, band prediction and shape noise history.
    /// The next successful frame behaves as on a fresh stream with the same fixed
    /// format. Pending audio tails are discarded; callers own explicit draining.
    public mutating func reset() {
        analysis.reset()
        preemphasisMemory = Array(repeating: 0, count: channelCount)
        previousEnergies = Array(repeating: 0, count: channelCount * 21)
        seed = 0
    }

    /// Encodes one PCM frame into a caller-selected fixed byte budget.
    /// - Parameters:
    ///   - samples: Exactly `frameSampleCount * channelCount` finite interleaved
    ///     normalized samples in `-1...1`, at 48 kHz. Input storage is not retained.
    ///   - frameByteCount: Exact compressed output size in `2...1_275`, excluding
    ///     TOC/packet framing. This is storage/admission policy, not a bitrate target
    ///     or universal quality guarantee. Very small budgets can discard most bands.
    ///   - intra: Request independent coarse envelope prediction; default false.
    ///     Insufficient header budget can force predictive coding as specified.
    /// - Returns: Raw frame bytes and final entropy accounting. A matching standard
    ///   CELT TOC must be added before handing bytes to an Opus packet consumer.
    /// - Throws: `invalidSamples` or `invalidFrameByteCount` before processing;
    ///   component errors or `entropyBudgetExceeded` on encoding failure. No failed
    ///   call advances any stream history. Cancellation is caller-owned between calls.
    public mutating func encode(_ samples: [Float], frameByteCount: Int,
                                intra: Bool = false) throws -> CELTEncodedFrame {
        guard samples.count == frameSampleCount * channelCount,
              samples.allSatisfy({ $0.isFinite && (-1...1).contains($0) }) else {
            throw CELTFrameEncoderError.invalidSamples
        }
        guard (2...1_275).contains(frameByteCount) else { throw CELTFrameEncoderError.invalidFrameByteCount }
        var working = self
        let result = try working.encodeFrame(samples, frameByteCount: frameByteCount, intra: intra)
        self = working
        return result
    }

    /// Composes complete long-block CELT syntax on a private stream copy.
    /// - Parameters:
    ///   - samples: Admitted normalized interleaved PCM for the fixed stream format.
    ///   - frameByteCount: Admitted physical compressed size, excluding Opus headers.
    ///   - intra: Desired independent coarse envelope predictor.
    /// - Returns: Finalized raw CELT frame and exact final range/accounting.
    /// - Throws: Component/entropy errors; the caller discards this private stream copy.
    private mutating func encodeFrame(_ samples: [Float], frameByteCount: Int,
                                      intra: Bool) throws -> CELTEncodedFrame {
        var preemphasized = Array(repeating: Float(0), count: samples.count)
        for frame in 0..<frameSampleCount {
            for channel in 0..<channelCount {
                let index = frame * channelCount + channel
                // A fixed half scale admits the ±1.85 preemphasized domain through
                // the normalized analysis primitive without changing its contract.
                preemphasized[index] = (samples[index] - 0.850006103515625 * preemphasisMemory[channel]) * 0.5
                preemphasisMemory[channel] = samples[index]
            }
        }
        let spectrum = try analysis.analyze(preemphasized).map { $0 * 2 }
        let envelope = normalize(spectrum)
        var encoder = try OpusRangeEncoder(frameByteCount: frameByteCount)
        let header = try CELTFrameHeader(frameSampleCount: frameSampleCount,
                                         channelCount: channelCount, endBand: endBand)
        _ = try header.encodePrefix(into: &encoder)
        let quantizer = try CELTEnergyQuantizer(frameSampleCount: frameSampleCount,
            channelCount: channelCount, endBand: endBand)
        var energy = try quantizer.encodeCoarse(target: envelope.logEnergies,
            previous: previousEnergies, intra: intra, into: &encoder)
        let fields = try header.encodeAfterCoarse(isTransient: false, into: &encoder)
        let allocator = try CELTBitAllocation(frameSampleCount: frameSampleCount,
            channelCount: channelCount, endBand: endBand, allocationTrim: fields.allocationTrim)
        let allocation = try allocator.encode(totalEighthBits: fields.allocationEighthBits,
                                               dynamicOffsets: fields.dynamicOffsets, into: &encoder)
        energy = try quantizer.encodeFine(energy, bitCounts: allocation.fineEnergyBits, into: &encoder)
        let shapes = try CELTShapeFrameCoding(frameSampleCount: frameSampleCount,
            channelCount: channelCount, endBand: endBand,
            timeFrequencyChanges: fields.timeFrequencyChanges, spreading: fields.spreading)
        _ = try shapes.encode(envelope.coefficients, allocation: allocation,
            totalEighthBits: frameByteCount * 64, seed: seed,
            bandEnergies: envelope.amplitudes, into: &encoder)
        energy = try quantizer.encodeFinal(energy, fineBitCounts: allocation.fineEnergyBits,
            priorities: allocation.finePriorities, remainingBits: max(0, frameByteCount * 8 - encoder.bitsUsed),
            into: &encoder)
        guard encoder.bitsUsed <= frameByteCount * 8 else { throw CELTFrameEncoderError.entropyBudgetExceeded }
        let bytes = try encoder.finalize()
        previousEnergies = energy.energies
        for channel in 0..<channelCount {
            for band in endBand..<21 { previousEnergies[channel * 21 + band] = 0 }
        }
        seed = encoder.finalRange
        return CELTEncodedFrame(bytes: bytes, finalRange: encoder.finalRange,
            bitsUsed: encoder.bitsUsed, fractionalBitsUsed: encoder.fractionalBitsUsed)
    }

    /// Computes ordinary 21-band normalized channel-major shapes and mean-relative envelopes.
    /// - Parameter spectrum: Exactly one interleaved frequency-ordered analysis output,
    ///   restored from the analysis half scale into normalized PCM units.
    /// - Returns: Channel-major coefficients, positive linear amplitudes and log2
    ///   amplitudes relative to the RFC's Q4 band means in the 32768-unit signal domain.
    ///   Bands above the configured end are zero and require no coding operations.
    /// This finite O(frame samples * channels) calculation retains no external storage.
    private func normalize(_ spectrum: [Float]) -> (coefficients: [Float], amplitudes: [Float], logEnergies: [Float]) {
        var coefficients = Array(repeating: Float(0), count: spectrum.count)
        var amplitudes = Array(repeating: Float(0), count: channelCount * 21)
        var logs = Array(repeating: Float(0), count: channelCount * 21)
        let multiplier = frameSampleCount / 120
        for channel in 0..<channelCount {
            for band in 0..<endBand {
                let first = CELTAllocationTables.bandEdges[band] * multiplier
                let last = CELTAllocationTables.bandEdges[band + 1] * multiplier
                var squared: Double = 1e-30
                for bin in first..<last {
                    let value = Double(spectrum[bin * channelCount + channel])
                    squared += value * value
                }
                let amplitude = Float(sqrt(squared))
                amplitudes[channel * 21 + band] = amplitude
                logs[channel * 21 + band] = log2(amplitude * 32_768) - Self.bandMeans[band]
                for bin in first..<last {
                    coefficients[channel * frameSampleCount + bin] = spectrum[bin * channelCount + channel] / amplitude
                }
            }
        }
        return (coefficients, amplitudes, logs)
    }
}
