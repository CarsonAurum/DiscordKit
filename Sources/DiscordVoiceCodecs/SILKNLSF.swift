/*
 Copyright (c) 2006-2011, Skype Limited. All rights reserved.
 Copyright (c) 2013, Koen Vos. All rights reserved.
 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions are met:
 - Redistributions of source code must retain the above copyright notice,
   this list of conditions and the following disclaimer.
 - Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.
 - Neither the name of Internet Society, IETF or IETF Trust, nor the names of
   specific contributors, may be used to endorse or promote products derived
   from this software without specific prior written permission.
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

/// Validation failures before bounded SILK frequency-to-predictor reconstruction.
public enum SILKNLSFError: Error, Sendable, Equatable {
    case invalidOrder
    case invalidFrequencies
    case invalidInterpolationWeight
}

/// Owned, fixed-point SILK normalized-line-spectral-frequency to LPC conversion.
///
/// Implements RFC 6716 section 4.2.7.5's cosine interpolation, reordered polynomial
/// expansion, signed coefficient fitting and bounded stability expansion. Arithmetic
/// follows the scalar reference, including two's-complement narrowing and rounded
/// shifts; no native codec is imported. Adapted from libopus 1.6.1 NLSF2A.c,
/// LPC_fit.c, bwexpander_32.c and LPC_inv_pred_gain.c under the notice above.
///
/// This value supplies coefficient reconstruction, not compressed NLSF codebook
/// decoding, encoder frequency analysis, frame synthesis, PLC or a complete codec.
/// Construction is synchronous, has bounded O(order squared) work, starts no tasks
/// or I/O, and retains only dense arrays of ten or sixteen values.
public struct SILKNLSFCoefficients: Sendable, Equatable {
    /// Nondecreasing Q15 normalized angular frequencies, with Nyquist represented by 32768.
    public let q15: [Int16]
    /// Reconstructed signed predictor coefficients in Q12, without the leading one.
    public let lpcQ12: [Int16]
    /// Normative inverse prediction gain in Q30, or zero when the bounded conversion
    /// still fails its gain/stability test. Zero is possible for arbitrary degenerate
    /// input; codebook decoding/stabilization must precede actual frame reconstruction.
    public let inversePredictionGainQ30: Int32

    /// Reconstructs the predictor using at most ten fitting and sixteen stability iterations.
    /// - Parameter q15: Exactly ten (NB/MB) or sixteen (WB) nonnegative, nondecreasing
    ///   Q15 frequencies. Equal values are permitted so malformed/degenerate codebook
    ///   output can be diagnosed through `inversePredictionGainQ30` rather than trap.
    /// - Throws: `invalidOrder` for another count, or `invalidFrequencies` for negative
    ///   or decreasing values. Rejection occurs before polynomial construction.
    public init(q15: [Int16]) throws {
        try Self.validate(q15)
        let order = q15.count
        let ordering = order == 16
            ? [0, 15, 8, 7, 4, 11, 12, 3, 2, 13, 10, 5, 6, 9, 14, 1]
            : [0, 9, 6, 3, 4, 5, 8, 1, 2, 7]
        var cosines = Array(repeating: Int32(0), count: order)
        for index in 0..<order {
            let integer = Int(q15[index]) >> 8
            let fraction = Int32(q15[index]) & 255
            let base = Self.cosineQ12[integer]
            let delta = Self.cosineQ12[integer + 1] - base
            cosines[ordering[index]] = Int32(Self.rounded(Int64(base) * 256 + Int64(delta * fraction), by: 4))
        }
        let even = Self.polynomial(cosines, offset: 0)
        let odd = Self.polynomial(cosines, offset: 1)
        var extended = Array(repeating: Int32(0), count: order)
        for index in 0..<(order / 2) {
            let p = even[index + 1] &+ even[index]
            let q = odd[index + 1] &- odd[index]
            extended[index] = (0 &- q) &- p
            extended[order - index - 1] = q &- p
        }
        var result = Self.fit(&extended)
        var gain = Self.inverseGain(result)
        for iteration in 0..<16 {
            if gain != 0 { break }
            Self.expand(&extended, chirp: 65_536 - (2 << iteration))
            result = extended.map { Int16(truncatingIfNeeded: Self.rounded(Int64($0), by: 5)) }
            gain = Self.inverseGain(result)
        }
        self.q15 = q15.withUnsafeBufferPointer { Array($0) }
        self.lpcQ12 = result
        self.inversePredictionGainQ30 = gain
    }

    /// Interpolates previous/current Q15 frequencies before reconstructing a first-half predictor.
    /// - Parameters:
    ///   - previous: Ten or sixteen sorted frequencies from the preceding frame.
    ///   - current: The same number of sorted current frequencies.
    ///   - weight: Current-frame contribution in quarter units, `0...4`; zero returns
    ///     previous values, four returns current values. Signed shifts round down as SILK.
    /// - Returns: A dense frequency array; neither source's extra reserved capacity is retained.
    /// - Throws: `invalidOrder` for incompatible lengths, `invalidFrequencies` for invalid
    ///   values/order, or `invalidInterpolationWeight` outside the quarter-unit range.
    public static func interpolate(previous: [Int16], current: [Int16], weight: Int) throws -> [Int16] {
        try validate(previous)
        try validate(current)
        guard previous.count == current.count else { throw SILKNLSFError.invalidOrder }
        guard (0...4).contains(weight) else { throw SILKNLSFError.invalidInterpolationWeight }
        return zip(previous, current).map { first, second in
            Int16(Int32(first) + (((Int32(second) - Int32(first)) * Int32(weight)) >> 2))
        }
    }

    /// Classifies an already reconstructed predictor with SILK's exact integer stability test.
    /// - Parameter q12: Ten or sixteen signed Q12 coefficients, first tap first.
    /// - Returns: Inverse gain in Q30 (`1...2^30`) or zero for instability, excessive
    ///   prediction gain, unstable DC response or an overflowing step-down recurrence.
    /// - Throws: `invalidOrder` for an unsupported count. No coefficients are modified.
    public static func inversePredictionGain(q12: [Int16]) throws -> Int32 {
        guard q12.count == 10 || q12.count == 16 else { throw SILKNLSFError.invalidOrder }
        return inverseGain(q12)
    }

    /// Rejects unsupported count and frequency ordering before indexing the fixed cosine table.
    /// - Parameter frequencies: Candidate dense Q15 array; all Int16 maxima remain below Nyquist.
    /// - Throws: `invalidOrder` or `invalidFrequencies`; no state changes or allocations occur.
    private static func validate(_ frequencies: [Int16]) throws {
        guard frequencies.count == 10 || frequencies.count == 16 else { throw SILKNLSFError.invalidOrder }
        var previous: Int16 = 0
        for value in frequencies {
            guard value >= previous else { throw SILKNLSFError.invalidFrequencies }
            previous = value
        }
    }

    /// Applies reference signed rounding with ties toward positive infinity.
    /// - Parameters:
    ///   - value: A bounded Int64 product or coefficient, never Int64.max.
    ///   - bits: Positive right shift in `1...61`, supplied only by internal fixed domains.
    /// - Returns: Rounded arithmetic shift without adding a potentially overflowing half unit.
    private static func rounded(_ value: Int64, by bits: Int) -> Int64 {
        ((value >> (bits - 1)) + 1) >> 1
    }

    /// Expands one parity of reordered Q16 twice-cosine roots into its symmetric polynomial.
    /// - Parameters:
    ///   - cosines: Exactly ten or sixteen reordered Q16 roots.
    ///   - offset: Zero selects even roots, one selects odd roots.
    /// - Returns: Order/2+1 signed Q16 coefficients with reference Int32 narrowing.
    private static func polynomial(_ cosines: [Int32], offset: Int) -> [Int32] {
        let half = cosines.count / 2
        var result = Array(repeating: Int32(0), count: half + 1)
        result[0] = 65_536
        result[1] = 0 &- cosines[offset]
        for index in 1..<half {
            let root = cosines[2 * index + offset]
            result[index + 1] = (result[index - 1] &* 2)
                &- Int32(truncatingIfNeeded: rounded(Int64(root) * Int64(result[index]), by: 16))
            if index > 1 {
                for coefficient in stride(from: index, through: 2, by: -1) {
                    result[coefficient] = result[coefficient] &+ result[coefficient - 2]
                        &- Int32(truncatingIfNeeded: rounded(Int64(root) * Int64(result[coefficient - 1]), by: 16))
                }
            }
            result[1] = result[1] &- root
        }
        return result
    }

    /// Multiplies successive Q17 coefficients by increasing powers of a Q16 chirp.
    /// - Parameters:
    ///   - coefficients: Owned order-ten/sixteen workspace, updated in place.
    ///   - chirp: Initial Q16 bandwidth factor; zero clears every coefficient.
    ///   Every product narrows to reference two's-complement Int32 after arithmetic shifting.
    private static func expand(_ coefficients: inout [Int32], chirp: Int32) {
        var factor = chirp
        let delta = chirp - 65_536
        for index in coefficients.indices {
            coefficients[index] = Int32(truncatingIfNeeded: (Int64(factor) * Int64(coefficients[index])) >> 16)
            if index + 1 < coefficients.count {
                let product = factor &* delta
                factor = factor &+ Int32(rounded(Int64(product), by: 16))
            }
        }
    }

    /// Fits Q17 LPC coefficients into Q12 Int16 using ten bounded bandwidth iterations.
    /// - Parameter coefficients: Polynomial coefficients; adjusted in place on expansion.
    /// - Returns: Rounded Q12 coefficients; after ten expansions remaining excess is saturated
    ///   and written back into the workspace, matching the reference recovery path.
    private static func fit(_ coefficients: inout [Int32]) -> [Int16] {
        for _ in 0..<10 {
            var largest: Int64 = 0
            var position = 0
            for index in coefficients.indices {
                let magnitude = abs(Int64(coefficients[index]))
                if magnitude > largest { largest = magnitude; position = index }
            }
            largest = rounded(largest, by: 5)
            if largest <= 32_767 {
                return coefficients.map { Int16(truncatingIfNeeded: rounded(Int64($0), by: 5)) }
            }
            largest = min(largest, 163_838)
            let chirp = 65_470 - ((largest - 32_767) << 14) / ((largest * Int64(position + 1)) >> 2)
            expand(&coefficients, chirp: Int32(chirp))
        }
        let result = coefficients.map { Int16(clamping: rounded(Int64($0), by: 5)) }
        coefficients = result.map { Int32($0) << 5 }
        return result
    }

    /// Approximates the positive fixed-point reciprocal exactly as SILK's varQ primitive.
    /// - Parameters:
    ///   - value: Positive Q30 denominator from the reflection recurrence, above 32768.
    ///   - resultBits: Requested fixed domain in `46...61`, determined by magnitude.
    /// - Returns: Positive saturated Int32 reciprocal with reference refinement/narrowing.
    private static func reciprocal(_ value: Int32, resultBits: Int) -> Int32 {
        let headroom = value.leadingZeroBitCount - 1
        let normalized = value << headroom
        let first = (Int32.max >> 2) / (normalized >> 16)
        var result = first &<< 16
        let product = Int32((Int64(normalized) * Int64(Int16(truncatingIfNeeded: first))) >> 16)
        let error = ((1 << 29) &- product) &<< 3
        result = result &+ Int32(truncatingIfNeeded: (Int64(error) * Int64(first)) >> 16)
        let shift = 61 - headroom - resultBits
        if shift <= 0 { return Int32(clamping: Int64(result) << -shift) }
        return shift < 32 ? result >> shift : 0
    }

    /// Computes the exact Q30 inverse gain through a bounded Q24 step-down recursion.
    /// - Parameter q12: Validated order-ten/sixteen signed coefficients.
    /// - Returns: Zero for failed DC/reflection/gain/overflow checks, otherwise positive Q30 gain.
    private static func inverseGain(_ q12: [Int16]) -> Int32 {
        if q12.reduce(Int32(0), { $0 + Int32($1) }) >= 4_096 { return 0 }
        var row = q12.map { Int32($0) << 12 }
        var gain: Int32 = 1 << 30
        for last in stride(from: row.count - 1, through: 0, by: -1) {
            let coefficient = row[last]
            guard coefficient <= 16_773_022, coefficient >= -16_773_022 else { return 0 }
            let reflection = (0 &- coefficient) << 7
            let denominator = (1 << 30) - Int32((Int64(reflection) * Int64(reflection)) >> 32)
            gain = Int32(((Int64(gain) * Int64(denominator)) >> 32) << 2)
            if gain < 107_374 { return 0 }
            if last == 0 { break }
            let domain = 32 - denominator.leadingZeroBitCount
            let inverse = reciprocal(denominator, resultBits: domain + 30)
            for index in 0..<((last + 1) >> 1) {
                let first = row[index]
                let second = row[last - index - 1]
                let firstResidual = Int32(clamping: Int64(first) - rounded(Int64(second) * Int64(reflection), by: 31))
                let secondResidual = Int32(clamping: Int64(second) - rounded(Int64(first) * Int64(reflection), by: 31))
                let nextFirst = rounded(Int64(firstResidual) * Int64(inverse), by: domain)
                let nextSecond = rounded(Int64(secondResidual) * Int64(inverse), by: domain)
                guard nextFirst <= Int32.max, nextFirst >= Int32.min,
                      nextSecond <= Int32.max, nextSecond >= Int32.min else { return 0 }
                row[index] = Int32(nextFirst)
                row[last - index - 1] = Int32(nextSecond)
            }
        }
        return gain
    }

    /// Q12 twice-cosine lookup at 129 equally spaced points over zero through Nyquist.
    private static let cosineQ12: [Int32] = [
        8192, 8190, 8182, 8170, 8152, 8130, 8104, 8072, 8034, 7994, 7946, 7896,
        7840, 7778, 7714, 7644, 7568, 7490, 7406, 7318, 7226, 7128, 7026, 6922,
        6812, 6698, 6580, 6458, 6332, 6204, 6070, 5934, 5792, 5648, 5502, 5352,
        5198, 5040, 4880, 4718, 4552, 4382, 4212, 4038, 3862, 3684, 3502, 3320,
        3136, 2948, 2760, 2570, 2378, 2186, 1990, 1794, 1598, 1400, 1202, 1002,
        802, 602, 402, 202, 0, -202, -402, -602, -802, -1002, -1202, -1400,
        -1598, -1794, -1990, -2186, -2378, -2570, -2760, -2948, -3136, -3320,
        -3502, -3684, -3862, -4038, -4212, -4382, -4552, -4718, -4880, -5040,
        -5198, -5352, -5502, -5648, -5792, -5934, -6070, -6204, -6332, -6458,
        -6580, -6698, -6812, -6922, -7026, -7128, -7226, -7318, -7406, -7490,
        -7568, -7644, -7714, -7778, -7840, -7896, -7946, -7994, -8034, -8072,
        -8104, -8130, -8152, -8170, -8182, -8190, -8192,
    ]
}
