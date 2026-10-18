import Foundation

/// Rejections from the bounded CELT transform primitive; no compressed packet is involved.
public enum CELTTransformError: Error, Sendable, Equatable {
    case invalidFrameSize
    case invalidChannelCount
    case invalidSamples
    case invalidCoefficients
}

/// An owned floating-point CELT low-overlap MDCT plan, independent of an Opus codec.
///
/// At the CELT internal rate of 48 kHz, `frameSampleCount` is 120, 240, 480 or 960
/// samples per channel (2.5, 5, 10 or 20 ms). The rising/falling overlap is always
/// 120 samples. The window and coefficient order/normalization follow RFC 6716
/// section 4.3.7 and the libopus 1.6.1 transform: the forward cosine sum is scaled
/// by `2 / frameSampleCount`, and the inverse cosine sum has no additional scale.
/// Sources: [RFC 6716 section 4.3.7](https://www.rfc-editor.org/rfc/rfc6716.html#section-4.3.7)
/// and [official libopus 1.6.1](https://github.com/xiph/opus/tree/v1.6.1/celt).
/// Input/output buffers are interleaved by channel; coefficients are frequency
/// ordered, with channel samples adjacent at each frequency.
///
/// The implementation uses an owned mixed-radix FFT with O(N log N) work and O(N)
/// storage. Its FFT is deliberately independent of libopus's FFT implementation.
/// Arithmetic uses Double internally and returns Float. Results are numerically
/// compatible, not bit exact to float/fixed-point libopus. No pre/de-emphasis,
/// transient decision, band coding, packet parsing, PLC, FEC or rate conversion
/// is provided. Construction starts no background work, tasks or I/O; immutable plans may be
/// shared. See `CELTTransformStream` for independently owned overlap histories.
public struct CELTTransform: Sendable {
    public let frameSampleCount: Int
    public let channelCount: Int
    public static let overlapSampleCount = 120
    private let fftLength: Int
    private let radices: [Int]
    private let permutation: [Int]
    private let twiddleReal: [Double]
    private let twiddleImaginary: [Double]
    private let rotationReal: [Double]
    private let rotationImaginary: [Double]
    private let compactWindow: [Double]

    /// Precomputes a bounded transform and the RFC's power-complementary window.
    /// - Parameters:
    ///   - frameSampleCount: Exactly 120, 240, 480 or 960 samples per channel at
    ///     48 kHz. Other rates require explicit external rate conversion.
    ///   - channelCount: One or two independent interleaved channels; no stereo
    ///     coupling or channel conversion is performed.
    /// - Throws: `invalidFrameSize` or `invalidChannelCount` before allocating
    ///   plan tables. Construction costs O(N log N) bounded permutation work and
    ///   O(N) storage; the largest plan retains fewer than 150 KiB of table values.
    public init(frameSampleCount: Int, channelCount: Int = 1) throws {
        guard [120, 240, 480, 960].contains(frameSampleCount) else {
            throw CELTTransformError.invalidFrameSize
        }
        guard (1...2).contains(channelCount) else { throw CELTTransformError.invalidChannelCount }
        self.frameSampleCount = frameSampleCount
        self.channelCount = channelCount
        let length = frameSampleCount * 4
        self.fftLength = length
        var factors: [Int] = []
        var remainder = length
        for radix in [2, 3, 5] {
            while remainder.isMultiple(of: radix) {
                factors.append(radix)
                remainder /= radix
            }
        }
        self.radices = Array(factors.reversed())
        self.permutation = (0..<length).map { position in
            var remainingPosition = position
            var groupSize = length
            var inputStride = 1
            var inputPosition = 0
            for radix in factors {
                groupSize /= radix
                inputPosition += (remainingPosition / groupSize) * inputStride
                remainingPosition %= groupSize
                inputStride *= radix
            }
            return inputPosition
        }
        self.twiddleReal = (0..<length).map { cos(2 * .pi * Double($0) / Double(length)) }
        self.twiddleImaginary = (0..<length).map { sin(2 * .pi * Double($0) / Double(length)) }
        self.rotationReal = (0..<frameSampleCount).map {
            cos(.pi / Double(frameSampleCount) * (0.5 + Double(frameSampleCount) / 2) * (Double($0) + 0.5))
        }
        self.rotationImaginary = (0..<frameSampleCount).map {
            sin(.pi / Double(frameSampleCount) * (0.5 + Double(frameSampleCount) / 2) * (Double($0) + 0.5))
        }
        let overlap = Self.overlapSampleCount
        let rising = (0..<overlap).map { position in
            let inner = sin(0.5 * .pi * (Double(position) + 0.5) / Double(overlap))
            return sin(0.5 * .pi * inner * inner)
        }
        self.compactWindow = rising + Array(repeating: 1, count: frameSampleCount - overlap) + rising.reversed()
    }

    /// Transforms one complete low-overlap analysis window into CELT-ordered coefficients.
    /// - Parameter samples: Exactly `(frameSampleCount + 120) * channelCount` finite
    ///   interleaved samples in `-1...1`. The first 120 frames precede the current
    ///   block; adjacent calls must reuse those frames to obtain continuity. Samples
    ///   are windowed here, so callers must not apply another window.
    /// - Returns: Exactly `frameSampleCount * channelCount` frequency ordered
    ///   coefficients. The caller owns the returned array; no state is retained.
    /// - Throws: `invalidSamples` for wrong size, nonfinite or out-of-range values.
    ///   Validation precedes computation; no tasks, suspension or I/O occur.
    public func forward(_ samples: [Float]) throws -> [Float] {
        let compactCount = frameSampleCount + Self.overlapSampleCount
        guard samples.count == compactCount * channelCount,
              samples.allSatisfy({ $0.isFinite && (-1...1).contains($0) }) else {
            throw CELTTransformError.invalidSamples
        }
        var coefficients = Array(repeating: Float(0), count: frameSampleCount * channelCount)
        let padding = (frameSampleCount - Self.overlapSampleCount) / 2
        for channel in 0..<channelCount {
            var real = Array(repeating: Double(0), count: fftLength)
            var imaginary = real
            for index in 0..<compactCount {
                real[index + padding] = Double(samples[index * channelCount + channel]) * compactWindow[index]
            }
            fft(real: &real, imaginary: &imaginary, inverse: false)
            for bin in 0..<frameSampleCount {
                let frequency = 2 * bin + 1
                let value = real[frequency] * rotationReal[bin] + imaginary[frequency] * rotationImaginary[bin]
                coefficients[bin * channelCount + channel] = Float(value * 2 / Double(frameSampleCount))
            }
        }
        return coefficients
    }

    /// Produces one windowed inverse block before weighted overlap-add.
    /// - Parameter coefficients: Exactly `frameSampleCount * channelCount` finite
    ///   frequency ordered values. Each magnitude must be at most 4, a conservative
    ///   bound containing transforms of normalized PCM; this also prevents overflow
    ///   on hostile primitive inputs. Quantized bands require caller denormalization.
    /// - Returns: `(frameSampleCount + 120) * channelCount` interleaved values. Add
    ///   the last 120 frames of the preceding inverse block to the first 120 frames
    ///   of this block and advance by `frameSampleCount`; `CELTTransformStream`
    ///   performs that ownership. Unmodified floating-point output can exceed unity.
    /// - Throws: `invalidCoefficients` for wrong size, nonfinite or excessive values.
    ///   The plan remains unchanged; execution is synchronous and bounded.
    public func inverse(_ coefficients: [Float]) throws -> [Float] {
        guard coefficients.count == frameSampleCount * channelCount,
              coefficients.allSatisfy({ $0.isFinite && abs($0) <= 4 }) else {
            throw CELTTransformError.invalidCoefficients
        }
        let compactCount = frameSampleCount + Self.overlapSampleCount
        let padding = (frameSampleCount - Self.overlapSampleCount) / 2
        var samples = Array(repeating: Float(0), count: compactCount * channelCount)
        for channel in 0..<channelCount {
            var real = Array(repeating: Double(0), count: fftLength)
            var imaginary = real
            for bin in 0..<frameSampleCount {
                let frequency = 2 * bin + 1
                let value = Double(coefficients[bin * channelCount + channel]) * Double(fftLength) / 2
                real[frequency] = value * rotationReal[bin]
                imaginary[frequency] = value * rotationImaginary[bin]
                real[fftLength - frequency] = real[frequency]
                imaginary[fftLength - frequency] = -imaginary[frequency]
            }
            fft(real: &real, imaginary: &imaginary, inverse: true)
            for index in 0..<compactCount {
                samples[index * channelCount + channel] = Float(real[index + padding] * compactWindow[index])
            }
        }
        return samples
    }

    /// Runs the plan's mixed-radix complex FFT with precomputed roots of unity.
    /// - Parameters:
    ///   - real: Exactly `fftLength` real components, replaced with transformed data.
    ///   - imaginary: Matching imaginary components, replaced with transformed data.
    ///   - inverse: Uses positive phase and divides by the length when true;
    ///     otherwise uses the unnormalized negative-phase forward convention.
    /// No validation or shared mutation occurs because only validated callers enter.
    /// Permutation and radix-2/3/5 butterflies cost O(N log N); temporary storage is
    /// O(N), including two permuted arrays and twenty reusable butterfly components.
    private func fft(real: inout [Double], imaginary: inout [Double], inverse: Bool) {
        real = permutation.map { real[$0] }
        imaginary = permutation.map { imaginary[$0] }
        let sign: Double = inverse ? 1 : -1
        var previousSize = 1
        var inputReal = Array(repeating: Double(0), count: 5)
        var inputImaginary = inputReal
        var outputReal = inputReal
        var outputImaginary = inputReal
        for radix in radices {
            let stageSize = previousSize * radix
            let stageRootStride = fftLength / stageSize
            let butterflyRootStride = fftLength / radix
            for base in stride(from: 0, to: fftLength, by: stageSize) {
                for offset in 0..<previousSize {
                    for component in 0..<radix {
                        let index = base + component * previousSize + offset
                        let root = component * offset * stageRootStride
                        let wr = twiddleReal[root]
                        let wi = sign * twiddleImaginary[root]
                        inputReal[component] = real[index] * wr - imaginary[index] * wi
                        inputImaginary[component] = real[index] * wi + imaginary[index] * wr
                    }
                    for frequency in 0..<radix {
                        var sumReal = 0.0
                        var sumImaginary = 0.0
                        for component in 0..<radix {
                            let root = (component * frequency * butterflyRootStride) % fftLength
                            let wr = twiddleReal[root]
                            let wi = sign * twiddleImaginary[root]
                            sumReal += inputReal[component] * wr - inputImaginary[component] * wi
                            sumImaginary += inputReal[component] * wi + inputImaginary[component] * wr
                        }
                        outputReal[frequency] = sumReal
                        outputImaginary[frequency] = sumImaginary
                    }
                    for frequency in 0..<radix {
                        let index = base + frequency * previousSize + offset
                        real[index] = outputReal[frequency]
                        imaginary[index] = outputImaginary[frequency]
                    }
                }
            }
            previousSize = stageSize
        }
        if inverse {
            for index in 0..<fftLength {
                real[index] /= Double(fftLength)
                imaginary[index] /= Double(fftLength)
            }
        }
    }
}

/// Independently owned CELT analysis and synthesis overlap histories.
///
/// Calls process exactly one configured frame and preserve a 120-sample/channel
/// overlap. A forward/inverse pair produces normalized PCM delayed by 120 samples;
/// process a zero frame to recover the final tail. No automatic flush, clipping,
/// packet coding, rate conversion, timing or concurrency ownership is implied.
/// As a mutable Sendable value this supports isolated transfer and value copies;
/// callers must serialize mutation of each stream. Construction starts no work.
public struct CELTTransformStream: Sendable {
    public let transform: CELTTransform
    private var analysisHistory: [Float]
    private var synthesisHistory: [Float]

    /// Creates zero-initialized analysis and synthesis state for an immutable plan.
    /// - Parameter transform: Validated plan; its table storage is shared by Swift
    ///   value semantics, while each stream owns separate histories.
    /// No I/O, background task, suspension or sample processing occurs.
    public init(transform: CELTTransform) {
        self.transform = transform
        self.analysisHistory = Array(repeating: 0, count: CELTTransform.overlapSampleCount * transform.channelCount)
        self.synthesisHistory = analysisHistory
    }

    /// Analyzes a current PCM frame after the preceding 120 owned sample frames.
    /// - Parameter samples: Exactly `frameSampleCount * channelCount` normalized
    ///   finite interleaved samples. Missing input must be supplied explicitly.
    /// - Returns: One frame of interleaved frequency ordered coefficients.
    /// - Throws: `invalidSamples` on any size/value rejection. Histories remain
    ///   unchanged on failure; successful calls replace only analysis history.
    public mutating func analyze(_ samples: [Float]) throws -> [Float] {
        guard samples.count == transform.frameSampleCount * transform.channelCount else {
            throw CELTTransformError.invalidSamples
        }
        let result = try transform.forward(analysisHistory + samples)
        analysisHistory = Array(samples.suffix(analysisHistory.count))
        return result
    }

    /// Inverts one coefficient frame and performs bounded weighted overlap-add.
    /// - Parameter coefficients: One frequency ordered frame accepted by `inverse`.
    /// - Returns: Exactly `frameSampleCount * channelCount` interleaved samples,
    ///   including the previous block's overlap. Output is not clipped to unity.
    /// - Throws: `invalidCoefficients` on rejection, preserving both histories.
    ///   Success replaces only synthesis history; no timing or asynchronous work occurs.
    public mutating func synthesize(_ coefficients: [Float]) throws -> [Float] {
        var block = try transform.inverse(coefficients)
        for index in synthesisHistory.indices { block[index] += synthesisHistory[index] }
        let outputCount = transform.frameSampleCount * transform.channelCount
        let output = Array(block.prefix(outputCount))
        synthesisHistory = Array(block.suffix(synthesisHistory.count))
        return output
    }

    /// Discards both overlap histories and restores deterministic zero startup.
    /// Future analysis/synthesis acts like a new stream with the same plan. This
    /// explicitly loses any pending tail; call with zero PCM first when draining
    /// lossless analysis/synthesis. No coefficients or samples are returned.
    public mutating func reset() {
        analysisHistory = Array(repeating: 0, count: analysisHistory.count)
        synthesisHistory = Array(repeating: 0, count: synthesisHistory.count)
    }
}
