/// A bounded five-tap voiced SILK residual synthesis primitive.
///
/// The tap order and recurrence follow RFC 6716 section 4.2.7.9.1:
/// `res[i] = excitation[i] + sum(res[i - lag + 2 - k] * bQ7[k] / 128)`.
/// Double reconstruction does not reproduce libopus's fixed-point rounding.
/// A single channel owns at most 290 normalized residual history samples.
///
/// The caller supplies *already rewhitened and gain-normalized* history whenever
/// LPC coefficients, gain or LTP scaling require it. This type cannot infer that
/// history from a packet and does not implement pitch/parameter entropy coding,
/// frame gain handling, PLC or the complete SILK encoder/decoder. Construction
/// starts no I/O/tasks; each value owns its state and must be mutated serially.
public struct SILKLongTermSynthesisFilter: Sendable {
    /// Internal SILK channel rate, restricted to NB 8 kHz, MB 12 kHz or WB 16 kHz.
    public let sampleRate: Int
    /// Inclusive final, contour-adjusted pitch-lag range, in channel samples.
    public let pitchLagRange: ClosedRange<Int>
    /// `maximumPitchLag + 2` prior normalized residual samples, oldest first.
    public private(set) var history: [Double]
    /// Local per-call bound, equal to 60 ms at the maximum SILK rate.
    public static let maximumBlockSamples = 960

    /// Creates a voiced predictor with zero or explicitly rewhitened residual state.
    /// - Parameters:
    ///   - sampleRate: Exactly 8,000, 12,000 or 16,000 samples per second.
    ///   - history: `sampleRate * 18 / 1000 + 2` finite residual samples, oldest
    ///     first, or `nil` for zero state. These are unclipped normalized residuals.
    /// - Throws: `invalidSampleRate`, `invalidHistory` for incorrect history length,
    ///   or `nonFiniteSample` for NaN/infinity. No partial state escapes failure.
    /// - Complexity: O(maximumPitchLag) construction/storage, at most 290 samples.
    public init(sampleRate: Int, history: [Double]? = nil) throws {
        guard sampleRate == 8_000 || sampleRate == 12_000 || sampleRate == 16_000 else {
            throw SILKPredictionError.invalidSampleRate
        }
        let maximumLag = sampleRate * 18 / 1000
        let initial = history ?? Array(repeating: 0, count: maximumLag + 2)
        guard initial.count == maximumLag + 2 else { throw SILKPredictionError.invalidHistory }
        guard initial.allSatisfy(\.isFinite) else { throw SILKPredictionError.nonFiniteSample }
        self.sampleRate = sampleRate
        self.pitchLagRange = (sampleRate * 2 / 1000)...maximumLag
        self.history = initial.map { $0 }
    }

    /// Atomically installs rewhitened/gain-adjusted state or clears decoder history.
    /// - Parameter history: Exactly `maximumPitchLag + 2` finite residual values,
    ///   oldest first, or `nil` for all zeros. Rewhitening and LTP scaling are the
    ///   caller's responsibility; do not reuse stale residuals after such changes.
    /// - Throws: `invalidHistory` for wrong length or `nonFiniteSample` for NaN or
    ///   infinity; rejected replacements preserve the complete prior state.
    public mutating func reset(history: [Double]? = nil) throws {
        let replacement = history ?? Array(repeating: 0, count: self.history.count)
        guard replacement.count == self.history.count else { throw SILKPredictionError.invalidHistory }
        guard replacement.allSatisfy(\.isFinite) else { throw SILKPredictionError.nonFiniteSample }
        self.history = replacement.map { $0 }
    }

    /// Adds five-tap pitch prediction to a bounded block of normalized excitation.
    /// - Parameters:
    ///   - excitation: Zero through 960 finite excitation samples, already divided
    ///     by `2^23` when sourced from SILK's Q23 excitation representation.
    ///   - pitchLag: Final contour-adjusted and clamped pitch lag in `pitchLagRange`.
    ///     The minimum delay is always greater than two, so all taps are causal.
    ///   - coefficientsQ7: Exactly five signed Q7 coefficients, in RFC table order.
    ///     Index zero addresses `i - lag + 2`; index four addresses `i - lag - 2`.
    ///     `nil` disables voiced prediction and preserves excitation as the residual.
    /// - Returns: One unclipped residual per excitation sample. Empty input is a
    ///   validated no-op. Retained residual history makes chunking invariant.
    /// - Throws: `invalidSampleCount`, `invalidPitchLag`, incorrect five-tap length
    ///   as `invalidLongTermCoefficients`, `nonFiniteSample`, or `numericalOverflow`
    ///   for nonfinite sums. Every failure preserves the whole prior history.
    /// - Complexity: O(samples * 5 + maximumPitchLag) work using a fixed-capacity
    ///   circular history, and O(samples + maximumPitchLag) temporary storage.
    ///   No tasks or suspension are involved.
    public mutating func process(
        _ excitation: [Double],
        pitchLag: Int,
        coefficientsQ7: [Int8]?
    ) throws -> [Double] {
        guard excitation.count <= Self.maximumBlockSamples else { throw SILKPredictionError.invalidSampleCount }
        guard pitchLagRange.contains(pitchLag) else { throw SILKPredictionError.invalidPitchLag }
        if let coefficientsQ7, coefficientsQ7.count != 5 { throw SILKPredictionError.invalidLongTermCoefficients }
        guard excitation.allSatisfy(\.isFinite) else { throw SILKPredictionError.nonFiniteSample }
        var state = history
        var next = 0
        var result: [Double] = []
        result.reserveCapacity(excitation.count)
        for sample in excitation {
            var prediction = 0.0
            if let coefficientsQ7 {
                for tap in 0..<5 {
                    let position = (next + state.count - pitchLag + 2 - tap) % state.count
                    prediction += state[position] * (Double(coefficientsQ7[tap]) / 128)
                }
            }
            let residual = sample + prediction
            guard prediction.isFinite, residual.isFinite else { throw SILKPredictionError.numericalOverflow }
            result.append(residual)
            state[next] = residual
            next = (next + 1) % state.count
        }
        history = Array(state[next...]) + Array(state[..<next])
        return result
    }
}
