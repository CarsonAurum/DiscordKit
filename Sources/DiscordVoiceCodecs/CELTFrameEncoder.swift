// Energy probability tables, temporal masking and allocation trim adapted from
// libopus 1.6.1 celt/quant_bands.c, celt/laplace.c and celt/celt_encoder.c.
// Copyright (c) 2007-2008 CSIRO
// Copyright (c) 2007-2010 Xiph.Org Foundation
// Copyright (c) 2008 Gregory Maxwell
// Written by Jean-Marc Valin and Gregory Maxwell
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

/// Explicit selection of owned CELT analysis, independent of the physical byte budget.
///
/// `fixed` preserves the original deterministic long-block/neutral-trim decisions.
/// `adaptive` uses temporal masking to select 2.5-ms transforms on strong onsets,
/// rejects nearly pure low-frequency tones from that detector, and adapts allocation
/// trim to available bitrate and spectral tilt. It does not reproduce libopus's
/// encoder decisions, implement pitch prefilter search or establish perceptual quality.
/// Both policies are synchronous, bounded and introduce no device or task ownership.
public enum CELTEncoderAnalysisPolicy: Sendable, Equatable {
    case fixed, adaptive
}

/// An ordinary owned CELT frame, excluding the enclosing Opus TOC/packing header.
public struct CELTEncodedFrame: Sendable, Equatable {
    public let bytes: Data
    public let finalRange: UInt32
    public let bitsUsed: Int
    public let fractionalBitsUsed: Int
    /// Actual admitted transient flag; false for 2.5-ms frames or insufficient prefix budget.
    public let isTransient: Bool
}

/// An owned CELT audio encoder with explicit bounded storage and analysis policy.
///
/// This encodes normalized PCM through preemphasis, low-overlap analysis, band
/// normalization, envelope quantization, ordinary bit allocation and recursive
/// mono/stereo shape coding. It emits valid ordinary CELT syntax rather than
/// reproducing the reference encoder's perceptual decisions or compressed bytes.
/// Frame duration, coded channels and upper band are fixed for one stream.
///
/// Fixed analysis selects long blocks and neutral allocation trim. Adaptive analysis
/// adds masked onset detection, short-block MDCT/anti-collapse and bitrate/spectral
/// tilt trim. Both select no pitch prefilter and normal spreading, and implement no
/// complete psychoacoustic rate/distortion search, VBR, DTX, FEC, PLC or SILK ownership.
/// Independent packet policies compose bitrate/DTX; perceptual qualification remains
/// separate from syntax and numerical interoperability evidence.
/// Construction starts no I/O/tasks; exclusive mutable access serializes calls.
/// All input validation and processing are synchronous with bounded per-frame
/// storage. Failed calls preserve the entire previous audio/energy/entropy state.
public struct CELTFrameEncoder: Sendable {
    public let frameSampleCount: Int
    public let channelCount: Int
    public let startBand: Int
    public let endBand: Int
    public let analysisPolicy: CELTEncoderAnalysisPolicy
    private let longTransform: CELTTransform
    private let shortTransform: CELTTransform
    private var analysisHistory: [Float]
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
    ///   - startBand: Inclusive lower band in `0...20`; default zero. Hybrid uses 17.
    ///   - endBand: Exclusive upper band in `1...21`; default 21. Standard Opus TOCs
    ///     use 13/17/19/21 for narrow/wide/superwide/full bandwidth respectively.
    ///   - analysisPolicy: Fixed long-block choices by default, or adaptive onset/trim
    ///     analysis. This choice is fixed for the stream and survives `reset()`.
    /// - Throws: `CELTTransformError` for invalid duration/channels, or
    ///   `CELTBitAllocationError.invalidBandRange` for an invalid upper band.
    public init(frameSampleCount: Int, channelCount: Int = 1, startBand: Int = 0, endBand: Int = 21,
                analysisPolicy: CELTEncoderAnalysisPolicy = .fixed) throws {
        let transform = try CELTTransform(frameSampleCount: frameSampleCount, channelCount: channelCount)
        _ = try CELTBitAllocation(frameSampleCount: frameSampleCount, channelCount: channelCount, startBand: startBand, endBand: endBand)
        self.frameSampleCount = frameSampleCount
        self.channelCount = channelCount
        self.startBand = startBand
        self.endBand = endBand
        self.analysisPolicy = analysisPolicy
        longTransform = transform
        shortTransform = try CELTTransform(frameSampleCount: 120, channelCount: channelCount)
        analysisHistory = Array(repeating: 0, count: 120 * channelCount)
        preemphasisMemory = Array(repeating: 0, count: channelCount)
        previousEnergies = Array(repeating: 0, count: channelCount * 21)
    }

    /// Discards analysis overlap, preemphasis, band prediction and shape noise history.
    /// The next successful frame behaves as on a fresh stream with the same fixed
    /// format. Pending audio tails are discarded; callers own explicit draining.
    public mutating func reset() {
        analysisHistory = Array(repeating: 0, count: 120 * channelCount)
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
        var entropy = try OpusRangeEncoder(frameByteCount: frameByteCount)
        let result = try working.encodeFrame(samples, into: &entropy, intra: intra)
        self = working
        return result
    }

    /// Appends CELT to a shared arithmetic interval and finalizes its complete frame.
    /// - Parameters:
    ///   - samples: Exactly the fixed interleaved 48kHz frame, finite and within `-1...1`.
    ///   - encoder: Active fixed-size arithmetic encoder after any SILK/redundancy
    ///     header syntax. Its raw bits retain the common physical frame end.
    ///   - intra: Desired independent coarse envelope predictor; default false.
    /// - Returns: Finalized shared bytes, including preceding SILK syntax when used
    ///   for hybrid, and exact final range/bit accounting. Successful calls finalize
    ///   the caller's coder; no further syntax may be appended.
    /// - Throws: Input/storage/component errors, preserving both coder and stream.
    ///   `entropyBudgetExceeded` also rejects an already exhausted shared prefix;
    ///   this encoder does not silently drop PCM or advance silent envelope history.
    ///   This synchronous operation owns bounded histories and starts no I/O or tasks.
    public mutating func encode(_ samples: [Float], into encoder: inout OpusRangeEncoder,
                                intra: Bool = false) throws -> CELTEncodedFrame {
        guard samples.count == frameSampleCount * channelCount,
              samples.allSatisfy({ $0.isFinite && (-1...1).contains($0) }) else {
            throw CELTFrameEncoderError.invalidSamples
        }
        guard (2...1_275).contains(encoder.frameByteCount) else { throw CELTFrameEncoderError.invalidFrameByteCount }
        var working = self
        var entropy = encoder
        let result = try working.encodeFrame(samples, into: &entropy, intra: intra)
        self = working
        encoder = entropy
        return result
    }

    /// Composes complete CELT syntax using admitted long/short analysis on a private copy.
    /// - Parameters:
    ///   - samples: Admitted normalized interleaved PCM for the fixed stream format.
    ///   - encoder: Active shared arithmetic interval with admitted physical storage.
    ///   - intra: Desired independent coarse envelope predictor.
    /// - Returns: Finalized raw CELT frame and exact final range/accounting.
    /// - Throws: Component/entropy errors; the caller discards this private stream copy.
    private mutating func encodeFrame(_ samples: [Float], into encoder: inout OpusRangeEncoder,
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
        let frameByteCount = encoder.frameByteCount
        let header = try CELTFrameHeader(frameSampleCount: frameSampleCount,
                                         channelCount: channelCount, startBand: startBand, endBand: endBand)
        let window = analysisHistory + preemphasized
        let remainingBits = max(0, frameByteCount * 8 - encoder.bitsUsed)
        // Short-block allocation requires enough authority for each channel/block;
        // low-budget frames retain the conservative long transform instead.
        let transient = analysisPolicy == .adaptive && frameSampleCount > 120
            && remainingBits >= 32 + frameSampleCount / 120 * 16 * channelCount
            && detectTransient(window)
        let prefix = try header.encodePrefix(isTransient: transient, into: &encoder)
        guard !prefix.silence else { throw CELTFrameEncoderError.entropyBudgetExceeded }
        let spectrum = try analyze(window, isTransient: prefix.isTransient)
        analysisHistory = Array(preemphasized.suffix(120 * channelCount))
        let envelope = normalize(spectrum)
        let quantizer = try CELTEnergyQuantizer(frameSampleCount: frameSampleCount,
            channelCount: channelCount, startBand: startBand, endBand: endBand)
        var energy = try quantizer.encodeCoarse(target: envelope.logEnergies,
            previous: previousEnergies, intra: intra, into: &encoder)
        let trim = analysisPolicy == .adaptive
            ? allocationTrim(logEnergies: envelope.logEnergies, availableBits: remainingBits,
                             isTransient: prefix.isTransient) : 5
        let fields = try header.encodeAfterCoarse(isTransient: prefix.isTransient,
                                                  allocationTrim: trim, into: &encoder)
        let allocator = try CELTBitAllocation(frameSampleCount: frameSampleCount,
            channelCount: channelCount, startBand: startBand, endBand: endBand, allocationTrim: fields.allocationTrim)
        let allocation = try allocator.encode(totalEighthBits: fields.allocationEighthBits,
                                               dynamicOffsets: fields.dynamicOffsets, into: &encoder)
        energy = try quantizer.encodeFine(energy, bitCounts: allocation.fineEnergyBits, into: &encoder)
        let shapes = try CELTShapeFrameCoding(frameSampleCount: frameSampleCount,
            channelCount: channelCount, startBand: startBand, endBand: endBand,
            transient: prefix.isTransient,
            timeFrequencyChanges: fields.timeFrequencyChanges, spreading: fields.spreading)
        _ = try shapes.encode(envelope.coefficients, allocation: allocation,
            totalEighthBits: frameByteCount * 64 - (fields.antiCollapseReserved ? 8 : 0), seed: seed,
            bandEnergies: envelope.amplitudes, into: &encoder)
        if fields.antiCollapseReserved { try encoder.encodeRawBits(1, count: 1) }
        energy = try quantizer.encodeFinal(energy, fineBitCounts: allocation.fineEnergyBits,
            priorities: allocation.finePriorities, remainingBits: max(0, frameByteCount * 8 - encoder.bitsUsed),
            into: &encoder)
        guard encoder.bitsUsed <= frameByteCount * 8 else { throw CELTFrameEncoderError.entropyBudgetExceeded }
        let bytes = try encoder.finalize()
        previousEnergies = energy.energies
        for channel in 0..<channelCount {
            for band in 0..<21 where band < startBand || band >= endBand { previousEnergies[channel * 21 + band] = 0 }
        }
        seed = encoder.finalRange
        return CELTEncodedFrame(bytes: bytes, finalRange: encoder.finalRange,
            bitsUsed: encoder.bitsUsed, fractionalBitsUsed: encoder.fractionalBitsUsed,
            isTransient: prefix.isTransient)
    }

    /// Analyzes the admitted block layout with one common, bounded overlap history.
    /// - Parameters:
    ///   - window: Validated half-scaled interleaved preemphasis history plus this frame.
    ///   - isTransient: Actual entropy-admitted short-block choice; false for LM=0.
    /// - Returns: Restored full-scale interleaved coefficients. Short blocks use
    ///   frequency-major/block-minor order, matching RFC 6716 section 4.3.7.
    /// - Throws: Transform validation errors; the public caller discards partial state.
    private func analyze(_ window: [Float], isTransient: Bool) throws -> [Float] {
        guard isTransient else { return try longTransform.forward(window).map { $0 * 2 } }
        let blocks = frameSampleCount / 120
        var spectrum = Array(repeating: Float(0), count: frameSampleCount * channelCount)
        for block in 0..<blocks {
            let offset = block * 120 * channelCount
            let coefficients = try shortTransform.forward(Array(window[offset..<(offset + 240 * channelCount)]))
            for bin in 0..<120 {
                for channel in 0..<channelCount {
                    spectrum[(bin * blocks + block) * channelCount + channel] = coefficients[bin * channelCount + channel] * 2
                }
            }
        }
        return spectrum
    }

    /// Selects strong temporal onsets using the reference float masking model.
    /// - Parameter window: Admitted interleaved preemphasized overlap/current frame.
    /// - Returns: True when any channel exceeds the masking threshold. Near-silent
    ///   channels and near-pure tones below 200Hz do not trigger. This uses bounded
    ///   O(frame samples * channels) scratch/work and retains no additional history.
    /// The detector does not claim reference encoder identity: full tonality analysis,
    /// weak hybrid transients and psychoacoustic corpus calibration remain separate.
    private func detectTransient(_ window: [Float]) -> Bool {
        let inverse: [Int] = [
            255,255,156,110,86,70,59,51,45,40,37,33,31,28,26,25,
            23,22,21,20,19,18,17,16,16,15,15,14,13,13,12,12,
            12,12,11,11,11,10,10,10,9,9,9,9,9,9,8,8,
            8,8,8,7,7,7,7,7,7,6,6,6,6,6,6,6,
            6,6,6,6,6,6,6,6,6,5,5,5,5,5,5,5,
            5,5,5,5,5,4,4,4,4,4,4,4,4,4,4,4,
            4,4,4,4,4,4,4,4,4,4,4,4,4,4,3,3,
            3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,2,
        ]
        let length = window.count / channelCount
        for channel in 0..<channelCount {
            let signal = stride(from: channel, to: window.count, by: channelCount).map { Double(window[$0]) }
            if isLowFrequencyTone(signal) { continue }
            var filtered = Array(repeating: Double(0), count: length)
            var memory0: Double = 0
            var memory1: Double = 0
            for index in 0..<length {
                let value = signal[index]
                let output = memory0 + value
                let previous = memory0
                memory0 = memory0 - value + 0.5 * memory1
                memory1 = value - previous
                if index >= 12 { filtered[index] = output }
            }
            var energies = Array(repeating: Double(0), count: length / 2)
            memory0 = 0
            var total: Double = 0
            for index in energies.indices {
                let energy = filtered[index * 2] * filtered[index * 2]
                    + filtered[index * 2 + 1] * filtered[index * 2 + 1]
                total += energy
                memory0 = energy + 0.9375 * memory0
                energies[index] = 0.0625 * memory0
            }
            guard total > 1e-12 else { continue }
            memory0 = 0
            var maximum: Double = 0
            for index in energies.indices.reversed() {
                memory0 = energies[index] + 0.875 * memory0
                energies[index] = 0.125 * memory0
                maximum = max(maximum, energies[index])
            }
            let mean = sqrt(total * maximum * 0.5 * Double(energies.count))
            let normalization = Double(energies.count) / (1e-30 + mean)
            var unmask = 0
            for index in stride(from: 12, to: energies.count - 5, by: 4) {
                let bucket = Int(min(127, max(0, floor(64 * normalization * (energies[index] + 1e-30)))))
                unmask += inverse[bucket]
            }
            let metric = 64 * unmask * 4 / (6 * (energies.count - 17))
            if metric > 200 { return true }
        }
        return false
    }

    /// Rejects near-pure low tones which a short masking window can confuse with onsets.
    /// - Parameter signal: One admitted bounded preemphasized channel with at least 240 samples.
    /// - Returns: True when a stable second-order sinusoidal predictor explains all but
    ///   1e-7 of signal energy and its fitted frequency is below 200Hz. Constants also
    ///   qualify. Mixed music, noisy speech and discontinuities normally fail the fit.
    /// The least-squares calculation is synchronous O(N), with no retained state.
    private func isLowFrequencyTone(_ signal: [Double]) -> Bool {
        var correlation: Double = 0
        var power: Double = 0
        var signalPower: Double = 0
        for index in 2..<signal.count {
            correlation += signal[index - 1] * (signal[index] + signal[index - 2])
            power += signal[index - 1] * signal[index - 1]
            signalPower += signal[index] * signal[index]
        }
        guard power > 1e-15 else { return false }
        let coefficient = correlation / power
        guard coefficient >= 2 * cos(2 * .pi * 200 / 48_000), coefficient <= 2.00001 else { return false }
        var residual: Double = 0
        for index in 2..<signal.count {
            let error = signal[index] + signal[index - 2] - coefficient * signal[index - 1]
            residual += error * error
        }
        return residual <= signalPower * 1e-7
    }

    /// Adapts ordinary allocation tilt to available rate and mean-relative spectral slope.
    /// - Parameters:
    ///   - logEnergies: Admitted channel-major 21-band log2 envelopes.
    ///   - availableBits: Remaining physical bit authority at the prefix boundary,
    ///     excluding preceding hybrid syntax; this method never changes output size.
    ///   - isTransient: Actual admitted short-block choice; lowers trim by one on onsets.
    /// - Returns: A validated trim in `0...10`, with neutral high-rate base five and
    ///   low-rate base four. Spectral slope changes the base by at most two. The
    ///   bounded heuristic follows the reference's rate/tilt direction without
    ///   claiming its stereo/tonality/surround optimization or perceived quality.
    private func allocationTrim(logEnergies: [Float], availableBits: Int, isTransient: Bool) -> Int {
        let bitrate = Double(availableBits) * 48_000 / Double(frameSampleCount)
        let base = 4 + min(1, max(0, (bitrate - 64_000) / 16_000))
        let count = endBand - startBand
        var slope: Double = 0
        if count > 1 {
            for channel in 0..<channelCount {
                for band in startBand..<(endBand - 1) {
                    slope += Double(logEnergies[channel * 21 + band]) * Double(2 + 2 * (band - startBand) - count)
                }
            }
            slope /= Double(channelCount * (count - 1) * 6)
        }
        let trim = base - min(2, max(-2, slope)) - (isTransient ? 1 : 0)
        return min(10, max(0, Int(trim.rounded())))
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
            for band in startBand..<endBand {
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
