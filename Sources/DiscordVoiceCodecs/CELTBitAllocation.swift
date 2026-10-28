// File: Sources/DiscordVoiceCodecs/CELTBitAllocation.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

/* Copyright (c) 2007-2008 CSIRO
   Copyright (c) 2007-2009 Xiph.Org Foundation
   Written by Jean-Marc Valin */
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

/// Validation failures before allocation consumes any caller-owned entropy.
public enum CELTBitAllocationError: Error, Sendable, Equatable {
    case invalidFrameSize, invalidChannelCount, invalidBandRange, invalidTrim
    case invalidOffsets, invalidBudget, invalidCodedBandLimit, invalidIntensity
}

/// One ordinary CELT allocation, using the 21-band 48-kHz mode's global band indices.
///
/// Shape budgets are eighth-bits, not pulse counts; recursive PVQ coding still chooses
/// the actual pulse codebooks. Fine precision applies to each channel. Inactive bands
/// are zero in every array. The caller separately owns anti-collapse reservation,
/// dynamic-allocation syntax, energy/shape coding and full-frame bit-budget validation.
public struct CELTBitAllocationResult: Sendable, Equatable {
    public let shapeEighthBits: [Int]
    public let fineEnergyBits: [Int]
    public let finePriorities: [Int]
    public let balanceEighthBits: Int
    public let codedBandEnd: Int
    public let intensityBand: Int
    public let dualStereo: Bool
}

/// Owned RFC 6716 section 4.3.3 ordinary CELT bit allocation and stereo/skip syntax.
///
/// Implements standard caps, allocation-vector interpolation, trim/dynamic offsets,
/// forced and explicit skipping, intensity/dual-stereo reservations, fine-energy
/// precision/priorities and excess balance. No custom mode or extension is supported.
/// Encode uses an explicit caller-selected stopping limit, rather than perceptual
/// analysis or a quality heuristic. Decode implements the mandatory bitstream rules.
///
/// Instances are immutable, contain 21 bounded cap values and start no work. Calls
/// are synchronous, bounded to 21 bands and consume at most 22 entropy operations.
/// A private value copy of the range coder commits only after complete success;
/// validation and entropy failures preserve every caller-owned coding state field.
/// This primitive supplies no PCM, complete Opus codec, PLC, FEC or device access.
public struct CELTBitAllocation: Sendable {
    public let frameSampleCount: Int
    public let channelCount: Int
    public let startBand: Int
    public let endBand: Int
    public let allocationTrim: Int
    public let bandCaps: [Int]
    private let durationIndex: Int

    /// Selects the ordinary allocation mode without reading or emitting entropy.
    /// - Parameters:
    ///   - frameSampleCount: Exactly 120, 240, 480 or 960 samples per channel at 48 kHz.
    ///   - channelCount: One or two coded channels; default one.
    ///   - startBand: First active global band index in `0...20`; default zero.
    ///   - endBand: Exclusive active end in `(startBand + 1)...21`; default 21.
    ///   - allocationTrim: Previously decoded/selected allocation tilt in `0...10`; default five.
    /// - Throws: The matching configuration error before allocating cap storage.
    public init(frameSampleCount: Int, channelCount: Int = 1, startBand: Int = 0,
                endBand: Int = 21, allocationTrim: Int = 5) throws {
        guard let durationIndex = [120, 240, 480, 960].firstIndex(of: frameSampleCount) else {
            throw CELTBitAllocationError.invalidFrameSize
        }
        guard (1...2).contains(channelCount) else { throw CELTBitAllocationError.invalidChannelCount }
        guard (0...20).contains(startBand), endBand > startBand, endBand <= 21 else {
            throw CELTBitAllocationError.invalidBandRange
        }
        guard (0...10).contains(allocationTrim) else { throw CELTBitAllocationError.invalidTrim }
        self.frameSampleCount = frameSampleCount
        self.channelCount = channelCount
        self.startBand = startBand
        self.endBand = endBand
        self.allocationTrim = allocationTrim
        self.durationIndex = durationIndex
        bandCaps = (0..<21).map { band in
            let width = CELTAllocationTables.bandEdges[band + 1] - CELTAllocationTables.bandEdges[band]
            let scale = CELTAllocationTables.capScale[21 * (2 * durationIndex + channelCount - 1) + band]
            return ((scale + 64) * channelCount * (width << durationIndex)) >> 2
        }
    }

    /// Emits explicit skip/stereo decisions and returns the exact resulting allocation.
    /// - Parameters:
    ///   - totalEighthBits: Remaining budget after preceding syntax/reservations, at most 81,600
    ///     eighth-bits (the 1,275-byte ordinary frame bound). Negative values clamp to zero as in
    ///     the reference decoder. The caller must subtract its anti-collapse reserve beforehand.
    ///   - dynamicOffsets: Exactly 21 nonnegative eighth-bit boosts, each at most 81,600;
    ///     default all zero. Only the active range is used. These are already decoded/selected
    ///     boosts, not dynamic-allocation flag counts. Any boosted band prevents skipping it.
    ///   - codedBandLimit: Preferred exclusive coded end in `(startBand + 1)...endBand`;
    ///     nil selects endBand. At each eligible skip flag, stop when the current end is at
    ///     or below this limit. Forced skips can lower the result; boosted bands can raise it.
    ///   - intensityBand: Preferred intensity start in `startBand...endBand`; nil selects endBand.
    ///     Signaling clamps it to the actual coded end; an unreserved field becomes zero.
    ///   - dualStereo: Desired independent stereo shape coding; default false. It becomes false
    ///     for mono, insufficient reserve, or intensity at/below the active starting band.
    ///   - encoder: Frame coder positioned immediately before allocation's skip/stereo syntax.
    /// - Returns: Standard shape/fine allocation, coded end, admitted stereo decisions and balance.
    /// - Throws: The matching validation error or a range-coder error. Failure preserves encoder;
    ///   callers must still ensure their supplied remaining budget matches the enclosing frame.
    public func encode(totalEighthBits: Int, dynamicOffsets: [Int] = Array(repeating: 0, count: 21),
                       codedBandLimit: Int? = nil, intensityBand: Int? = nil, dualStereo: Bool = false,
                       into encoder: inout OpusRangeEncoder) throws -> CELTBitAllocationResult {
        try validate(totalEighthBits: totalEighthBits, dynamicOffsets: dynamicOffsets)
        let limit = codedBandLimit ?? endBand
        guard limit > startBand, limit <= endBand else { throw CELTBitAllocationError.invalidCodedBandLimit }
        let intensity = intensityBand ?? endBand
        guard intensity >= startBand, intensity <= endBand else { throw CELTBitAllocationError.invalidIntensity }
        var coding = CELTAllocationEncoding(encoder: encoder, codedBandLimit: limit,
                                            intensityBand: intensity, dual: dualStereo)
        let result = try allocate(totalEighthBits: max(0, totalEighthBits), offsets: dynamicOffsets, coding: &coding)
        encoder = coding.encoder
        return result
    }

    /// Reads mandatory skip/stereo syntax and derives the exact ordinary allocation.
    /// - Parameters:
    ///   - totalEighthBits: Remaining post-reservation budget, at most 81,600 eighth-bits;
    ///     negative values clamp to zero. Anti-collapse and preceding syntax are caller-owned.
    ///   - dynamicOffsets: Exactly 21 previously decoded boosts, each in `0...81_600`;
    ///     default zero. Values outside the active range are ignored and never retained.
    ///   - decoder: Frame coder positioned at allocation's first possible skip/stereo symbol.
    /// - Returns: Allocation arrays and decoded stereo choices; inactive indices contain zero.
    /// - Throws: `invalidBudget`, `invalidOffsets`, or a range-coder error, preserving decoder.
    ///   Normative zero extension is permitted; a successful primitive call alone does not prove
    ///   that the enclosing packet has enough bits for every subsequent energy/shape symbol.
    public func decode(totalEighthBits: Int, dynamicOffsets: [Int] = Array(repeating: 0, count: 21),
                       from decoder: inout OpusRangeDecoder) throws -> CELTBitAllocationResult {
        try validate(totalEighthBits: totalEighthBits, dynamicOffsets: dynamicOffsets)
        var coding = CELTAllocationDecoding(decoder: decoder)
        let result = try allocate(totalEighthBits: max(0, totalEighthBits), offsets: dynamicOffsets, coding: &coding)
        decoder = coding.decoder
        return result
    }

    /// Validates finite storage/integer-work bounds before making a private entropy copy.
    /// - Parameters:
    ///   - totalEighthBits: Upper-bounded signed remaining frame budget; negatives are harmless.
    ///   - dynamicOffsets: Required 21-entry nonnegative bounded boost vector.
    /// - Throws: `invalidBudget` or `invalidOffsets` before any entropy operation or retained input copy.
    private func validate(totalEighthBits: Int, dynamicOffsets: [Int]) throws {
        guard totalEighthBits <= 81_600 else { throw CELTBitAllocationError.invalidBudget }
        guard dynamicOffsets.count == 21, dynamicOffsets.allSatisfy({ (0...81_600).contains($0) }) else {
            throw CELTBitAllocationError.invalidOffsets
        }
    }

    /// Applies bounded integer vector search/interpolation followed by normative per-band redistribution.
    /// - Parameters:
    ///   - totalEighthBits: Already validated/clamped nonnegative budget.
    ///   - offsets: Already validated 21-entry boost vector, never retained beyond this call.
    ///   - coding: Private encoder/decoder copy providing only the three signaled allocation decisions.
    /// - Returns: A complete owned allocation, committing no external coder state itself.
    /// - Throws: Coding errors from explicit skips, intensity or dual stereo; private partial work is discarded.
    private func allocate<Coding: CELTAllocationCoding>(totalEighthBits: Int, offsets: [Int],
                                                       coding: inout Coding) throws -> CELTBitAllocationResult {
        let edges = CELTAllocationTables.bandEdges
        let channels = channelCount
        let stereo = channels - 1
        let floor = channels << 3
        var total = totalEighthBits
        let skipReserve = total >= 8 ? 8 : 0
        total -= skipReserve
        var intensityReserve = 0
        var dualReserve = 0
        if channels == 2 {
            intensityReserve = CELTAllocationTables.logFraction[endBand - startBand]
            if intensityReserve > total { intensityReserve = 0 }
            else {
                total -= intensityReserve
                dualReserve = total >= 8 ? 8 : 0
                total -= dualReserve
            }
        }
        var thresholds = Array(repeating: 0, count: 21)
        var trim = thresholds
        for band in startBand..<endBand {
            let width = edges[band + 1] - edges[band]
            thresholds[band] = max(floor, (3 * width << (durationIndex + 3)) >> 4)
            trim[band] = (channels * width * (allocationTrim - 5 - durationIndex)
                           * (endBand - band - 1) * (1 << (durationIndex + 3))) >> 6
            if width << durationIndex == 1 { trim[band] -= floor }
        }
        var low = 1
        var high = 10
        repeat {
            let middle = (low + high) >> 1
            var sum = 0
            var done = false
            for band in (startBand..<endBand).reversed() {
                let width = edges[band + 1] - edges[band]
                var bits = (channels * width * CELTAllocationTables.vectors[middle * 21 + band] << durationIndex) >> 2
                if bits > 0 { bits = max(0, bits + trim[band]) }
                bits += offsets[band]
                if bits >= thresholds[band] || done {
                    done = true
                    sum += min(bits, bandCaps[band])
                } else if bits >= floor { sum += floor }
            }
            if sum > total { high = middle - 1 }
            else { low = middle + 1 }
        } while low <= high
        high = low
        low -= 1
        var lower = Array(repeating: 0, count: 21)
        var delta = lower
        var skipStart = startBand
        for band in startBand..<endBand {
            let width = edges[band + 1] - edges[band]
            var first = (channels * width * CELTAllocationTables.vectors[low * 21 + band] << durationIndex) >> 2
            var second = high >= 11 ? bandCaps[band]
                : (channels * width * CELTAllocationTables.vectors[high * 21 + band] << durationIndex) >> 2
            if first > 0 { first = max(0, first + trim[band]) }
            if second > 0 { second = max(0, second + trim[band]) }
            if low > 0 { first += offsets[band] }
            second += offsets[band]
            if offsets[band] > 0 { skipStart = band }
            lower[band] = first
            delta[band] = max(0, second - first)
        }
        low = 0
        high = 64
        for _ in 0..<6 {
            let middle = (low + high) >> 1
            var sum = 0
            var done = false
            for band in (startBand..<endBand).reversed() {
                let bits = lower[band] + ((middle * delta[band]) >> 6)
                if bits >= thresholds[band] || done {
                    done = true
                    sum += min(bits, bandCaps[band])
                } else if bits >= floor { sum += floor }
            }
            if sum > total { high = middle }
            else { low = middle }
        }
        var bits = Array(repeating: 0, count: 21)
        var sum = 0
        var done = false
        for band in (startBand..<endBand).reversed() {
            var value = lower[band] + ((low * delta[band]) >> 6)
            if value < thresholds[band] && !done { value = value >= floor ? floor : 0 }
            else { done = true }
            value = min(value, bandCaps[band])
            bits[band] = value
            sum += value
        }
        var codedEnd = endBand
        while true {
            let band = codedEnd - 1
            if band <= skipStart {
                total += skipReserve
                break
            }
            let width = edges[codedEnd] - edges[band]
            let span = edges[codedEnd] - edges[startBand]
            let left = total - sum
            let perCoefficient = left / span
            let remainder = left - span * perCoefficient
            let tail = max(remainder - (edges[band] - edges[startBand]), 0)
            var bandBits = bits[band] + perCoefficient * width + tail
            if bandBits >= max(thresholds[band], floor + 8) {
                if try coding.stopSkipping(codedEnd: codedEnd) { break }
                sum += 8
                bandBits -= 8
            }
            sum -= bits[band] + intensityReserve
            if intensityReserve > 0 { intensityReserve = CELTAllocationTables.logFraction[band - startBand] }
            sum += intensityReserve
            if bandBits >= floor { sum += floor; bits[band] = floor }
            else { bits[band] = 0 }
            codedEnd -= 1
        }
        let intensity = intensityReserve > 0 ? try coding.intensity(start: startBand, codedEnd: codedEnd) : 0
        if intensity <= startBand { total += dualReserve; dualReserve = 0 }
        let dual = dualReserve > 0 ? try coding.dualStereo() : false
        let span = edges[codedEnd] - edges[startBand]
        var left = total - sum
        let perCoefficient = left / span
        left -= span * perCoefficient
        for band in startBand..<codedEnd { bits[band] += perCoefficient * (edges[band + 1] - edges[band]) }
        for band in startBand..<codedEnd {
            let extra = min(left, edges[band + 1] - edges[band])
            bits[band] += extra
            left -= extra
        }
        var fine = Array(repeating: 0, count: 21)
        var priorities = fine
        var balance = 0
        for band in startBand..<codedEnd {
            let count = (edges[band + 1] - edges[band]) << durationIndex
            let available = bits[band] + balance
            var excess: Int
            if count > 1 {
                excess = max(available - bandCaps[band], 0)
                bits[band] = available - excess
                let degrees = channels * count + ((channels == 2 && count > 2 && !dual && band < intensity) ? 1 : 0)
                let logProduct = degrees * (CELTAllocationTables.logWidths[band] + (durationIndex << 3))
                var offset = (logProduct >> 1) - degrees * 21
                if count == 2 { offset += (degrees << 3) >> 2 }
                if bits[band] + offset < (degrees * 2) << 3 { offset += logProduct >> 2 }
                else if bits[band] + offset < (degrees * 3) << 3 { offset += logProduct >> 3 }
                fine[band] = (max(0, bits[band] + offset + (degrees << 2)) / degrees) >> 3
                if channels * fine[band] > bits[band] >> 3 { fine[band] = bits[band] >> (stereo + 3) }
                fine[band] = min(fine[band], 8)
                priorities[band] = fine[band] * (degrees << 3) >= bits[band] + offset ? 1 : 0
                bits[band] -= (channels * fine[band]) << 3
            } else {
                excess = max(0, available - floor)
                bits[band] = available - excess
                priorities[band] = 1
            }
            if excess > 0 {
                let extraFine = min(excess >> (stereo + 3), 8 - fine[band])
                fine[band] += extraFine
                let extraBits = (extraFine * channels) << 3
                priorities[band] = extraBits >= excess - balance ? 1 : 0
                excess -= extraBits
            }
            balance = excess
        }
        for band in codedEnd..<endBand {
            fine[band] = bits[band] >> (stereo + 3)
            bits[band] = 0
            priorities[band] = fine[band] < 1 ? 1 : 0
        }
        return CELTBitAllocationResult(shapeEighthBits: bits, fineEnergyBits: fine,
            finePriorities: priorities, balanceEighthBits: balance, codedBandEnd: codedEnd,
            intensityBand: intensity, dualStereo: dual)
    }
}

/// Private choice boundary sharing one integer allocator without exposing native entropy or heuristics.
private protocol CELTAllocationCoding {
    /// Reads/writes the one-bit eligible-band stop decision.
    /// - Parameter codedEnd: Current exclusive coded end, strictly above the protected starting band.
    /// - Returns: True to stop skipping; false explicitly skips the current highest band.
    /// - Throws: Range-coder failures without committing the public caller's entropy copy.
    mutating func stopSkipping(codedEnd: Int) throws -> Bool
    /// Reads/writes the uniform intensity start bounded by the actual coded end.
    /// - Parameters:
    ///   - start: First active band.
    ///   - codedEnd: Exclusive last shape-coded band; the uniform alphabet includes this value.
    /// - Returns: Intensity start in the closed start...codedEnd range.
    /// - Throws: Range-coder failures on the private working coder.
    mutating func intensity(start: Int, codedEnd: Int) throws -> Int
    /// Reads/writes the independently reserved dual-stereo bit.
    /// - Returns: Whether the current frame selects independent channel shape coding.
    /// - Throws: Range-coder failures on the private working coder.
    mutating func dualStereo() throws -> Bool
}

/// Encoder decisions retain explicit caller policy; no perceptual state or cross-frame history is inferred.
private struct CELTAllocationEncoding: CELTAllocationCoding {
    var encoder: OpusRangeEncoder
    let codedBandLimit: Int
    let intensityBand: Int
    let dual: Bool

    /// Signals the caller's chosen stopping limit whenever the mandatory threshold permits a flag.
    /// - Parameter codedEnd: Current exclusive coded end after any earlier forced/explicit skips.
    /// - Returns: True when this end is at or below the preferred limit.
    /// - Throws: Range-coder failure; the public call discards this private coder on error.
    mutating func stopSkipping(codedEnd: Int) throws -> Bool {
        let stop = codedEnd <= codedBandLimit
        try encoder.encodeBit(stop, logProbability: 1)
        return stop
    }

    /// Clamps and encodes the caller-selected intensity boundary.
    /// - Parameters:
    ///   - start: First active band, already validated not above the desired boundary.
    ///   - codedEnd: Actual coded end, possibly lowered by forced skips.
    /// - Returns: The admitted boundary in start...codedEnd.
    /// - Throws: Range-coder failure on the private working copy.
    mutating func intensity(start: Int, codedEnd: Int) throws -> Int {
        let value = min(intensityBand, codedEnd)
        try encoder.encodeUniform(UInt32(value - start), total: UInt32(codedEnd + 1 - start))
        return value
    }

    /// Signals the desired independent-stereo bit after the allocator reserves it.
    /// - Returns: The desired bit exactly as encoded.
    /// - Throws: Range-coder failure on the private working copy.
    mutating func dualStereo() throws -> Bool {
        try encoder.encodeBit(dual, logProbability: 1)
        return dual
    }
}

/// Decoder decisions read only mandatory symbols; no encoder quality heuristic affects reconstruction.
private struct CELTAllocationDecoding: CELTAllocationCoding {
    var decoder: OpusRangeDecoder

    /// Reads the eligible-band skip terminator.
    /// - Parameter codedEnd: Current coded end; it determines eligibility in the shared allocator.
    /// - Returns: The decoded stop flag.
    /// - Throws: Decoder operation/state failure; the public coder remains unchanged.
    mutating func stopSkipping(codedEnd: Int) throws -> Bool { try decoder.decodeBit(logProbability: 1) }

    /// Reads the intensity boundary from the exact bounded uniform alphabet.
    /// - Parameters:
    ///   - start: First active global band index.
    ///   - codedEnd: Actual exclusive coded end including any protected boosted band.
    /// - Returns: Decoded boundary in start...codedEnd.
    /// - Throws: Decoder operation/state failure on the private working copy.
    mutating func intensity(start: Int, codedEnd: Int) throws -> Int {
        start + Int(try decoder.decodeUniform(total: UInt32(codedEnd + 1 - start)))
    }

    /// Reads the reserved independent-stereo bit.
    /// - Returns: Decoded dual-stereo selection.
    /// - Throws: Decoder operation/state failure on the private working copy.
    mutating func dualStereo() throws -> Bool { try decoder.decodeBit(logProbability: 1) }
}
