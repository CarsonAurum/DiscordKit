// File: Sources/DiscordVoiceCodecs/SILKLinearPrediction.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

/// Rejections from the bounded SILK prediction primitives.
public enum SILKPredictionError: Error, Sendable, Equatable {
    case invalidOrder
    case unstableCoefficients
    case invalidHistory
    case invalidSampleCount
    case nonFiniteSample
    case numericalOverflow
    case invalidSampleRate
    case invalidPitchLag
    case invalidLongTermCoefficients
}

/// A validated short-term predictor with SILK's coefficient order and Q12 scale.
///
/// `q12[k] / 4096` predicts the sample at distance `k + 1`. The denominator
/// polynomial is `1 - a[0] z^-1 - ... - a[d-1] z^-d`. NB/MB use order ten and WB
/// uses order sixteen. Validation applies a Double-precision step-down recursion
/// and SILK's intended reflection/gain limits; it does **not** implement the
/// normative fixed-point NLSF conversion, gain test or bandwidth expansion.
/// Values are immutable, contain at most sixteen coefficients and start no work.
public struct SILKLinearPredictionCoefficients: Sendable, Equatable {
    /// Predictor coefficients, without the denominator's leading one, in Q12.
    public let q12: [Int16]
    /// Reflection coefficients with the RFC convention `rc[k] = -a[k][k]`.
    public let reflectionCoefficients: [Double]
    /// Reciprocal of the synthesis filter's impulse-response energy, in `(0, 1]`.
    public let inversePredictionGain: Double

    /// Validates already decoded/quantized LPC coefficients without changing them.
    /// - Parameter q12: Exactly ten (NB/MB) or sixteen (WB) signed Q12 values.
    ///   The coefficient at index zero multiplies the immediately preceding sample.
    /// - Throws: `invalidOrder` for other lengths; `unstableCoefficients` if any
    ///   reflection magnitude exceeds `0.99975`, accumulated inverse prediction
    ///   gain is below `0.0001`, or the floating-point recursion becomes nonfinite.
    ///   These are conservative local checks, not bit-exact libopus classification.
    /// - Complexity: O(order squared) work and O(order) temporary storage. No shared
    ///   state, tasks, I/O, compressed syntax or coefficient quantization is involved.
    public init(q12: [Int16]) throws {
        guard q12.count == 10 || q12.count == 16 else { throw SILKPredictionError.invalidOrder }
        var row = q12.map { Double($0) / 4096 }
        var reflections = Array(repeating: 0.0, count: q12.count)
        var inverseGain = 1.0
        for last in stride(from: q12.count - 1, through: 0, by: -1) {
            let reflection = -row[last]
            guard reflection.isFinite, abs(reflection) <= 0.99975 else {
                throw SILKPredictionError.unstableCoefficients
            }
            reflections[last] = reflection
            let denominator = 1 - reflection * reflection
            inverseGain *= denominator
            guard inverseGain.isFinite, inverseGain >= 0.0001 else {
                throw SILKPredictionError.unstableCoefficients
            }
            if last > 0 {
                var previous = Array(repeating: 0.0, count: last)
                for index in 0..<last {
                    previous[index] = (row[index] - row[last - index - 1] * reflection) / denominator
                }
                row = previous
            }
        }
        self.q12 = q12.map { $0 }
        self.reflectionCoefficients = reflections
        self.inversePredictionGain = inverseGain
    }
}

/// A bounded, caller-driven streaming LPC analysis or all-pole synthesis filter.
///
/// The recurrence follows RFC 6716 section 4.2.7.9.2, using Double arithmetic as
/// allowed for reconstruction. Analysis subtracts the prediction from each input;
/// synthesis adds it to each residual. Synthesis history always stores the full
/// **unclamped** output, including magnitudes above one. Gain normalization, final
/// PCM clipping, rewhitening policy, NLSF decoding and Opus framing belong to the
/// caller; this primitive alone cannot encode or decode a SILK bitstream.
///
/// All storage/work is bounded per call. Values own their history, start no tasks
/// or I/O and have no shared mutable state. Serialize mutation of each value.
public struct SILKShortTermFilter: Sendable {
    /// Whether the filter removes prediction or reconstructs from a residual.
    public enum Direction: Sendable {
        case analysis
        case synthesis
    }

    /// Fixed processing direction; changing direction requires a new filter.
    public let direction: Direction
    /// Current validated predictor; updates preserve history and must retain order.
    public private(set) var coefficients: SILKLinearPredictionCoefficients
    /// Exactly `coefficients.q12.count` prior source/output samples, oldest first.
    public private(set) var history: [Double]
    /// Local allocation/work limit, corresponding to 60 ms at SILK's maximum 16 kHz.
    public static let maximumBlockSamples = 960

    /// Creates a zero-state or explicitly seeded streaming predictor.
    /// - Parameters:
    ///   - direction: Analysis retains input history; synthesis retains output history.
    ///   - coefficients: Previously validated order-ten or order-sixteen LPC values.
    ///   - history: Exactly `order` finite prior samples in chronological order, or
    ///     `nil` for zeros. Samples are normalized signal values, without clipping.
    /// - Throws: `invalidHistory` for incorrect length or `nonFiniteSample` for NaN
    ///   or infinity. Construction allocates only O(order) state and starts no work.
    public init(
        direction: Direction,
        coefficients: SILKLinearPredictionCoefficients,
        history: [Double]? = nil
    ) throws {
        let initial = history ?? Array(repeating: 0, count: coefficients.q12.count)
        guard initial.count == coefficients.q12.count else { throw SILKPredictionError.invalidHistory }
        guard initial.allSatisfy(\.isFinite) else { throw SILKPredictionError.nonFiniteSample }
        self.direction = direction
        self.coefficients = coefficients
        self.history = initial.map { $0 }
    }

    /// Replaces the predictor at a subframe boundary while preserving prior samples.
    /// - Parameter coefficients: A validated predictor with the current order.
    /// - Throws: `invalidOrder` if its order differs. Failure leaves coefficients and
    ///   history unchanged. Changing a predictor does not rewhiten an LTP history;
    ///   callers must perform that separate operation when required by SILK.
    public mutating func updateCoefficients(_ coefficients: SILKLinearPredictionCoefficients) throws {
        guard coefficients.q12.count == self.coefficients.q12.count else { throw SILKPredictionError.invalidOrder }
        self.coefficients = coefficients
    }

    /// Atomically replaces history, or clears it for a decoder/channel reset.
    /// - Parameter history: Exactly `order` finite prior samples, oldest first;
    ///   `nil` resets to zeros. It is copied into owned, bounded state.
    /// - Throws: `invalidHistory` for wrong length or `nonFiniteSample` for NaN or
    ///   infinity. A rejected reset preserves all prior history and coefficients.
    public mutating func reset(history: [Double]? = nil) throws {
        let replacement = history ?? Array(repeating: 0, count: coefficients.q12.count)
        guard replacement.count == coefficients.q12.count else { throw SILKPredictionError.invalidHistory }
        guard replacement.allSatisfy(\.isFinite) else { throw SILKPredictionError.nonFiniteSample }
        self.history = replacement.map { $0 }
    }

    /// Removes or reconstructs LPC prediction while carrying history across chunks.
    /// - Parameter samples: Zero through 960 finite normalized source samples for
    ///   analysis, or gain-normalized residual samples for synthesis. Values outside
    ///   `-1...1` are permitted and are never clipped into recursive state.
    /// - Returns: One Double residual/output per input sample. Empty input returns
    ///   an empty array without changing state. Chunk boundaries do not change the
    ///   recurrence or operation order; retain the same filter between chunks.
    /// - Throws: `invalidSampleCount` above the local bound, `nonFiniteSample` for
    ///   NaN/infinity input, or `numericalOverflow` if prediction or output becomes
    ///   nonfinite. Every failure preserves the entire previous state, even when
    ///   overflow occurs after some samples have been computed.
    /// - Complexity: O(samples * order) work and O(samples + order) temporary storage.
    ///   The call is synchronous, performs no suspension and has no cancellation work.
    public mutating func process(_ samples: [Double]) throws -> [Double] {
        guard samples.count <= Self.maximumBlockSamples else { throw SILKPredictionError.invalidSampleCount }
        guard samples.allSatisfy(\.isFinite) else { throw SILKPredictionError.nonFiniteSample }
        var state = history
        var result: [Double] = []
        result.reserveCapacity(samples.count)
        let order = coefficients.q12.count
        for sample in samples {
            var prediction = 0.0
            for index in 0..<order {
                prediction += state[order - index - 1] * (Double(coefficients.q12[index]) / 4096)
            }
            let output = direction == .analysis ? sample - prediction : sample + prediction
            guard prediction.isFinite, output.isFinite else { throw SILKPredictionError.numericalOverflow }
            result.append(output)
            for index in 0..<(order - 1) { state[index] = state[index + 1] }
            state[order - 1] = direction == .analysis ? sample : output
        }
        history = state
        return result
    }
}
