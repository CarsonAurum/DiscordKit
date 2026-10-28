// File: Sources/DiscordVoiceCodecs/CELTBandQuantizer.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

// Pulse search and spreading adapted from libopus 1.6.1 celt/vq.c.
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

/// Validation errors for one independently quantized CELT shape band.
public enum CELTBandQuantizerError: Error, Sendable, Equatable {
    case invalidDimensions
    case invalidPulseCount
    case invalidBlockCount
    case invalidCoefficients
    case invalidGain
}

/// CELT's four spreading decisions, corresponding to RFC 6716 section 4.3.4.3.
/// The caller obtains this decision from the enclosing codec; it is not encoded here.
public enum CELTSpreading: Int, Sendable, CaseIterable {
    case none = 0
    case light = 1
    case normal = 2
    case aggressive = 3
}

/// One band's signed pulse codeword, reconstructed spectral coefficients and block occupancy.
/// These spectral values are not PCM and contain no band-energy or packet metadata.
public struct CELTQuantizedBand: Sendable, Equatable {
    /// Exactly the quantizer's dimensions, with absolute sum equal to its pulse count.
    public let pulses: [Int]
    /// Unit-energy pulse reconstruction scaled by gain and inverse spreading rotation.
    /// Rounding can slightly perturb the norm; no PCM clipping is applied.
    public let coefficients: [Float]
    /// Bit b is set when contiguous short-transform block b contains a nonzero pulse.
    /// Occupancy is measured before inverse spreading, as required for anti-collapse input.
    public let collapseMask: UInt8
}

/// Owned CELT band-shape pulse search, spreading and normalized entropy reconstruction.
///
/// This implements the floating-point scalar pulse search and exponential rotations from
/// libopus 1.6.1, composed with the exact RFC 6716 signed codebook. Each admitted band fits
/// one UInt32 uniform entropy symbol. Larger codebooks still require recursive band splitting,
/// which is deliberately rejected rather than inventing a different CELT bitstream.
///
/// The enclosing codec must supply normalized coefficients, pulse allocation, gain, spreading
/// and short-block layout. This component does not encode these decisions, quantize energy,
/// implement stereo/theta splitting, folding, anti-collapse synthesis, PLC or produce Opus
/// packets/PCM. Floating-point fixtures are component evidence, not full codec conformance.
/// Construction and calls are synchronous with no I/O, tasks or shared mutation. Search uses
/// O(dimensions * pulseCount) bounded work and O(dimensions) temporary storage; codebook
/// construction has the separately documented table bound. Immutable values are shareable.
public struct CELTBandQuantizer: Sendable {
    public let dimensions: Int
    public let pulseCount: Int
    public let shortBlockCount: Int
    public let spreading: CELTSpreading
    private let codebook: CELTPulseCodebook

    /// Creates one bounded shape-band configuration without consuming entropy or audio.
    /// - Parameters:
    ///   - dimensions: Band coefficients in `2...176`; scalar CELT bands are a separate path.
    ///   - pulseCount: Allocated pulses in `1...128`. Zero-pulse folding requires context
    ///     from adjacent bands and is not represented by this quantizer.
    ///   - shortBlockCount: One, two, four or eight contiguous short blocks, default one;
    ///     must divide dimensions. This is CELT's deinterleaved band layout.
    ///   - spreading: Caller-selected CELT spreading decision, default normal.
    /// - Throws: The corresponding `CELTBandQuantizerError` for invalid configuration,
    ///   or `CELTPulseCodebookError.codebookTooLarge` if recursive splitting is required.
    public init(dimensions: Int, pulseCount: Int, shortBlockCount: Int = 1,
                spreading: CELTSpreading = .normal) throws {
        guard (2...176).contains(dimensions) else { throw CELTBandQuantizerError.invalidDimensions }
        guard (1...128).contains(pulseCount) else { throw CELTBandQuantizerError.invalidPulseCount }
        guard [1, 2, 4, 8].contains(shortBlockCount), dimensions.isMultiple(of: shortBlockCount) else {
            throw CELTBandQuantizerError.invalidBlockCount
        }
        self.codebook = try CELTPulseCodebook(dimensions: dimensions, pulseCount: pulseCount)
        self.dimensions = dimensions
        self.pulseCount = pulseCount
        self.shortBlockCount = shortBlockCount
        self.spreading = spreading
    }

    /// Searches a normalized spectral band for a signed integer pulse codeword.
    ///
    /// Applies forward spreading, pyramid projection and greedy squared-correlation search;
    /// strict score comparisons resolve ties toward the first coefficient. A zero/tiny band
    /// deterministically places pulses at the first bin. No source array is retained/modified.
    /// - Parameters:
    ///   - coefficients: Exactly `dimensions` finite values with squared norm at most 1.001.
    ///     Normalization belongs to the enclosing codec; zero is admitted for silence fallback.
    ///   - gain: Finite reconstructed spectral norm in `0...64`, default one. Gain affects
    ///     reconstruction only, never the selected codeword; zero still encodes its shape.
    /// - Returns: Signed pulses, inverse-spread spectral reconstruction and occupancy mask.
    /// - Throws: `invalidCoefficients` or `invalidGain` before any entropy/state mutation.
    public func quantize(_ coefficients: [Float], gain: Float = 1) throws -> CELTQuantizedBand {
        try validateGain(gain)
        guard coefficients.count == dimensions,
              coefficients.allSatisfy({ $0.isFinite }),
              coefficients.reduce(0.0, { $0 + Double($1) * Double($1) }) <= 1.001 else {
            throw CELTBandQuantizerError.invalidCoefficients
        }
        var rotated = coefficients.withUnsafeBufferPointer { Array($0) }
        rotate(&rotated, inverse: false)
        return reconstruct(search(rotated), gain: gain)
    }

    /// Quantizes and writes one shape codeword to the caller's Opus entropy encoder.
    /// - Parameters:
    ///   - coefficients: Normalized spectral band accepted by `quantize(_:gain:)`.
    ///   - gain: Reconstruction norm in `0...64`, default one; not transmitted here.
    ///   - encoder: Caller-owned active encoder; this consumes one uniform coding operation.
    /// - Returns: The locally reconstructed band, identical to a corresponding decoder's result.
    /// - Throws: Band validation errors before encoder mutation, or `OpusRangeCodingError`
    ///   with the encoder's terminal failure, frame-budget and operation-budget semantics.
    public func encode(_ coefficients: [Float], gain: Float = 1,
                       into encoder: inout OpusRangeEncoder) throws -> CELTQuantizedBand {
        let result = try quantize(coefficients, gain: gain)
        try codebook.encode(result.pulses, into: &encoder)
        return result
    }

    /// Reads and reconstructs one shape using exactly the encoder's caller-supplied decisions.
    /// - Parameters:
    ///   - decoder: Caller-owned active range decoder; consumes one uniform operation.
    ///   - gain: Finite reconstruction norm in `0...64`, default one; decoded separately
    ///     by the enclosing codec. An invalid gain leaves the range state untouched.
    /// - Returns: Signed pulses, inverse-spread coefficients and short-block occupancy.
    /// - Throws: `invalidGain` before entropy mutation, or `OpusRangeCodingError` under
    ///   the decoder's corruption/budget rules. This does not validate a whole CELT frame.
    public func decode(from decoder: inout OpusRangeDecoder, gain: Float = 1) throws -> CELTQuantizedBand {
        try validateGain(gain)
        return reconstruct(try codebook.decode(from: &decoder), gain: gain)
    }

    /// Validates gain before processing so malformed caller context cannot consume entropy.
    /// - Parameter gain: Candidate finite nonnegative spectral norm, bounded to 64.
    /// - Throws: `invalidGain` for nonfinite, negative or above-bound values; no side effects.
    private func validateGain(_ gain: Float) throws {
        guard gain.isFinite, (0...64).contains(gain) else { throw CELTBandQuantizerError.invalidGain }
    }

    /// Performs the scalar CELT projected/greedy pulse search with deterministic sign/tie rules.
    /// - Parameter input: Validated, spread band; copied into bounded absolute-value workspaces.
    /// - Returns: Exactly dimensions integer components with L1 norm pulseCount.
    ///   All products/sums are finite under the public normalization/storage bounds.
    private func search(_ input: [Float]) -> [Int] {
        var magnitudes = input.map { abs($0) }
        var pulses = Array(repeating: 0, count: dimensions)
        var doubled = Array(repeating: Float(0), count: dimensions)
        var correlation: Float = 0
        var energy: Float = 0
        var remaining = pulseCount
        if pulseCount > dimensions / 2 {
            var sum = magnitudes.reduce(Float(0), +)
            if !(sum > 1e-15 && sum < 64) {
                magnitudes = Array(repeating: 0, count: dimensions)
                magnitudes[0] = 1
                sum = 1
            }
            let projection = (Float(pulseCount) + 0.8) * (1 / sum)
            for index in 0..<dimensions {
                pulses[index] = Int(floor(projection * magnitudes[index]))
                let value = Float(pulses[index])
                energy += value * value
                correlation += magnitudes[index] * value
                doubled[index] = 2 * value
                remaining -= pulses[index]
            }
        }
        // The pre-search leaves only a bounded greedy tail; the fallback also covers silence.
        if remaining > dimensions + 3 {
            let value = Float(remaining)
            energy += value * value
            energy += value * doubled[0]
            pulses[0] += remaining
            remaining = 0
        }
        for _ in 0..<remaining {
            energy += 1
            var best = 0
            var numerator = correlation + magnitudes[0]
            numerator *= numerator
            var denominator = energy + doubled[0]
            for index in 1..<dimensions {
                var candidate = correlation + magnitudes[index]
                candidate *= candidate
                let candidateEnergy = energy + doubled[index]
                if denominator * candidate > candidateEnergy * numerator {
                    best = index
                    numerator = candidate
                    denominator = candidateEnergy
                }
            }
            correlation += magnitudes[best]
            energy += doubled[best]
            doubled[best] += 2
            pulses[best] += 1
        }
        for index in 0..<dimensions where input[index] < 0 { pulses[index] = -pulses[index] }
        return pulses
    }

    /// Normalizes valid signed pulses, records pre-rotation block occupancy and undoes spreading.
    /// - Parameters:
    ///   - pulses: Internally validated nonzero codeword with the configured dimension and L1 norm.
    ///   - gain: Previously validated finite reconstruction norm.
    /// - Returns: Owned pulse and coefficient arrays; no PCM clipping or state changes occur.
    private func reconstruct(_ pulses: [Int], gain: Float) -> CELTQuantizedBand {
        let energy = pulses.reduce(0.0) { $0 + Double($1 * $1) }
        let scale = Double(gain) / sqrt(energy)
        var coefficients = pulses.map { Float(Double($0) * scale) }
        var mask: UInt8 = 0
        let width = dimensions / shortBlockCount
        for block in 0..<shortBlockCount {
            if pulses[(block * width)..<((block + 1) * width)].contains(where: { $0 != 0 }) {
                mask |= 1 << block
            }
        }
        rotate(&coefficients, inverse: true)
        return CELTQuantizedBand(pulses: pulses, coefficients: coefficients, collapseMask: mask)
    }

    /// Applies CELT's energy-preserving exponential spreading rotation or its exact inverse order.
    /// - Parameters:
    ///   - values: Owned dimensions-sized band, mutated synchronously in place.
    ///   - inverse: True to reverse both the Givens signs and pass ordering after reconstruction.
    /// Dense pulse allocations (2K >= N) and `.none` skip all rotation, as in libopus.
    private func rotate(_ values: inout [Float], inverse: Bool) {
        guard spreading != .none, 2 * pulseCount < dimensions else { return }
        let factor = [15, 10, 5][spreading.rawValue - 1]
        let rotationGain = Float(dimensions) / Float(dimensions + factor * pulseCount)
        let theta = 0.5 * rotationGain * rotationGain
        let c = Float(cos(0.5 * Double.pi * Double(theta)))
        let s = Float(cos(0.5 * Double.pi * Double(1 - theta)))
        var secondStride = 0
        if dimensions >= 8 * shortBlockCount {
            secondStride = 1
            while (secondStride * secondStride + secondStride) * shortBlockCount + shortBlockCount / 4 < dimensions {
                secondStride += 1
            }
        }
        let width = dimensions / shortBlockCount
        for block in 0..<shortBlockCount {
            let offset = block * width
            if inverse {
                if secondStride > 0 {
                    rotatePass(&values, offset: offset, width: width, stride: secondStride, c: s, s: c)
                }
                rotatePass(&values, offset: offset, width: width, stride: 1, c: c, s: s)
            } else {
                rotatePass(&values, offset: offset, width: width, stride: 1, c: c, s: -s)
                if secondStride > 0 {
                    rotatePass(&values, offset: offset, width: width, stride: secondStride, c: s, s: -c)
                }
            }
        }
    }

    /// Executes the forward then reverse triangular Givens sweep for one contiguous short block.
    /// - Parameters:
    ///   - values: Owned full band storage; only the selected block is modified.
    ///   - offset: First coefficient of this block, within the validated dimensions.
    ///   - width: Positive dimensions per block; all pair indices stay within the block.
    ///   - stride: Pair spacing, either one or CELT's rounded square-root secondary stride.
    ///   - c: Cosine-like finite unit rotation coefficient.
    ///   - s: Signed sine-like finite unit rotation coefficient.
    /// Zero-length reverse sweeps are skipped explicitly; storage/work stay bounded.
    private func rotatePass(_ values: inout [Float], offset: Int, width: Int, stride: Int, c: Float, s: Float) {
        for index in 0..<(width - stride) {
            let first = values[offset + index]
            let second = values[offset + index + stride]
            values[offset + index + stride] = c * second + s * first
            values[offset + index] = c * first - s * second
        }
        let last = width - 2 * stride - 1
        if last >= 0 {
            for index in Swift.stride(from: last, through: 0, by: -1) {
                let first = values[offset + index]
                let second = values[offset + index + stride]
                values[offset + index + stride] = c * second + s * first
                values[offset + index] = c * first - s * second
            }
        }
    }
}
