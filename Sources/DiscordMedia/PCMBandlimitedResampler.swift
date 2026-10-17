import Foundation

/// An owned, synchronous streaming PCM converter using a finite windowed-sinc low-pass filter.
///
/// Output frame `k` represents input position `k * inputRate / outputRate`. Integer phase
/// and duration remainders keep that position exact across arbitrarily split input blocks,
/// without growing lifetime counters. After `finish()`, the aggregate frame count is exactly
/// `floor(totalInputFrames * outputRate / inputRate)`. Channels are filtered independently.
/// Equal rates bypass filtering and preserve every sample without delay.
///
/// For unequal rates the centered FIR uses a Blackman window and a sinc cutoff at 90% of
/// the lower Nyquist frequency. Its support radius is `ceil(32 / cutoff)`, where `cutoff`
/// is `0.9 * min(1, outputRate / inputRate)` in input-Nyquist units. The wider kernel during
/// downsampling supplies anti-alias filtering. The finite transition band is intentional:
/// this is an approximation to ideal bandlimited interpolation, not a brick-wall filter.
/// Coefficients are normalized per fractional phase to preserve DC. Sinc overshoot is
/// saturated to PCM's normalized `-1...1` range; callers should leave headroom when needed.
/// See [Smith's windowed-sinc derivation](https://ccrma.stanford.edu/~jos/pasp/Windowed_Sinc_Interpolation.html).
///
/// The converter waits for right-hand filter support; it does not insert leading silence or
/// shift output timestamps. Initial/final support uses constant endpoint extension, with
/// right extension performed only by `finish()`. At ordinary boundaries it waits for real
/// samples. It retains at most twice the support radius in densely owned PCM frames. Each
/// call temporarily combines that history with at most one 120ms input block; no source
/// block, task, device, wall clock or I/O is owned. Arithmetic/storage bounds do not grow
/// with stream duration. Work is proportional to output frames times filter support, and
/// is synchronous, without cancellation or suspension. This supplies no hard real-time,
/// device, perceptual-quality or platform qualification guarantee. Copies have independent
/// copy-on-write state; callers must serialize mutation of each value.
public struct PCMBandlimitedResampler: Sendable {
    /// Required source sample rate and mono/stereo layout.
    public let inputFormat: PCMFormat

    /// Destination sample rate, preserving source channel count and order.
    public let outputFormat: PCMFormat

    /// Required future input frames before a centered output frame can be emitted; zero at equal rates.
    public let lookaheadFrames: Int

    /// Exact upper-bound filter lookahead in input-clock units; output timestamps retain their origin.
    public let processingDelay: MediaTime

    /// Maximum retained audio frames after a call, excluding its returned output and temporary workspace.
    public let maximumRetainedFrameCount: Int

    /// Whether finishing closed input admission; reset reopens an empty stream.
    public private(set) var isFinished = false

    /// Current densely owned history; external input capacity and source slices are never retained.
    private var history: [Float] = []

    /// Next output position in output-rate ticks relative to the retained history's first frame.
    private var phase: Int64 = 0

    /// Fractional duration entitlement, always reduced modulo the source sample rate.
    private var admissionRemainder: Int64 = 0

    /// Duration-admitted output frames still awaiting future filter support.
    private var pendingOutputFrames = 0

    /// Normalized sinc cutoff in input-Nyquist units, including transition-band headroom.
    private let cutoff: Double

    /// Number of retained interleaved frames; bounded by `maximumRetainedFrameCount`.
    ///
    /// Reading this value performs no work or mutation and excludes already returned buffers.
    public var retainedFrameCount: Int { history.count / inputFormat.channelCount }

    /// Accounted retained PCM bytes, excluding fixed metadata, allocator overhead and caller output.
    ///
    /// This is a sample-payload accounting measure, not an operating-system RSS measurement.
    public var accountedRetainedBytes: Int { history.count * MemoryLayout<Float>.stride }

    /// Creates an empty converter without starting background work or owning external resources.
    /// - Parameters:
    ///   - inputFormat: Validated source rate and mono/stereo channel order, fixed for this value.
    ///   - outputSampleRate: Destination frames per second in `8_000...192_000`, inclusive.
    ///     Equal rates produce identity conversion with zero retained history and lookahead.
    /// - Throws: `MediaError.invalidFormat` for an unsupported destination rate. Validated rates
    ///   keep filter support, phase arithmetic, per-call output and retained storage bounded.
    public init(inputFormat: PCMFormat, outputSampleRate: Int) throws {
        let output = try PCMFormat(sampleRate: outputSampleRate, channelCount: inputFormat.channelCount)
        let cutoff = 0.9 * min(1, Double(outputSampleRate) / Double(inputFormat.sampleRate))
        let radius = inputFormat.sampleRate == outputSampleRate ? 0 : Int(ceil(32 / cutoff))
        self.inputFormat = inputFormat
        self.outputFormat = output
        self.cutoff = cutoff
        self.lookaheadFrames = radius
        self.maximumRetainedFrameCount = 2 * radius
        self.processingDelay = try MediaTime(value: Int64(radius), timescale: Int32(inputFormat.sampleRate))
    }

    /// Filters the next contiguous block, deferring output that needs future real samples.
    ///
    /// No padding occurs at block boundaries. Empty matching blocks are no-ops. The input
    /// block is not retained, and output is split into nonempty blocks of at most 120ms.
    /// Output count per call can differ from that block's independent conversion because of
    /// filter delay and exact duration carry. Startup may therefore return no output.
    /// - Parameter buffer: The next at-most-120ms block matching `inputFormat` exactly.
    /// - Returns: Ordered, newly owned output blocks; an empty array means no frame is ready.
    /// - Throws: `MediaError.closed` after finishing, or `incompatibleBuffers` for a differing
    ///   rate/channel layout, including an empty mismatched block. Rejection precedes mutation.
    ///   Internal `PCMBuffer` invariant validation errors propagate; normalized input and
    ///   explicit saturation prevent them for values constructed through the public API.
    public mutating func process(_ buffer: PCMBuffer) throws -> [PCMBuffer] {
        guard !isFinished else { throw MediaError.closed }
        guard buffer.format == inputFormat else { throw MediaError.incompatibleBuffers }
        guard buffer.frameCount > 0 else { return [] }
        guard lookaheadFrames > 0 else { return [buffer] }

        let inputRate = Int64(inputFormat.sampleRate)
        let outputRate = Int64(outputFormat.sampleRate)
        let channels = inputFormat.channelCount
        let entitlement = admissionRemainder + Int64(buffer.frameCount) * outputRate
        var pending = pendingOutputFrames + Int(entitlement / inputRate)
        var nextPhase = phase
        var combined = history
        combined.append(contentsOf: buffer.samples)
        let combinedFrames = combined.count / channels
        var samples: [Float] = []
        samples.reserveCapacity(pending * channels)
        while pending > 0 {
            let center = Int(nextPhase / outputRate)
            guard center + lookaheadFrames < combinedFrames else { break }
            appendFilteredFrame(from: combined, phase: nextPhase, to: &samples)
            nextPhase += inputRate
            pending -= 1
        }

        let blocks = try makeBuffers(samples: samples)
        let firstNeeded = Int(nextPhase / outputRate) - lookaheadFrames + 1
        let dropFrames = max(0, min(combinedFrames - 1, firstNeeded))
        history = combined.withUnsafeBufferPointer { Array($0.dropFirst(dropFrames * channels)) }
        phase = nextPhase - Int64(dropFrames) * outputRate
        admissionRemainder = entitlement % inputRate
        pendingOutputFrames = pending
        return blocks
    }

    /// Flushes duration-admitted delayed output with constant extension of the final input frame.
    ///
    /// No extra filter ring-out frames are appended: the final count is the exact floor of
    /// the complete stream duration at the destination rate. Initial left support likewise
    /// uses the first input frame. Finishing releases all retained audio and phase, closes
    /// admission, and is idempotent. Empty and equal-rate streams have no delayed tail.
    /// - Returns: Ordered nonempty at-most-120ms tail buffers, or `[]` for no pending output.
    /// - Throws: Only internal `PCMBuffer` validation errors if storage invariants are violated;
    ///   valid public input and explicit saturation cannot produce invalid output samples.
    public mutating func finish() throws -> [PCMBuffer] {
        guard !isFinished else { return [] }
        var samples: [Float] = []
        samples.reserveCapacity(pendingOutputFrames * inputFormat.channelCount)
        var nextPhase = phase
        for _ in 0..<pendingOutputFrames {
            appendFilteredFrame(from: history, phase: nextPhase, to: &samples)
            nextPhase += Int64(inputFormat.sampleRate)
        }
        let blocks = try makeBuffers(samples: samples)
        reset()
        isFinished = true
        return blocks
    }

    /// Releases filter history and pending output and reopens a stream with a fresh origin.
    ///
    /// Formats and filter design remain fixed. Unflushed output is intentionally discarded;
    /// resetting mid-stream can create an audible discontinuity. Repeated reset is valid,
    /// including before input or after finishing. No external cleanup or I/O is required.
    public mutating func reset() {
        history = []
        phase = 0
        admissionRemainder = 0
        pendingOutputFrames = 0
        isFinished = false
    }

    /// Evaluates one centered normalized FIR frame, extending endpoints only outside retained support.
    ///
    /// Process calls provide complete right support; only finish can request a future sample.
    /// History compaction preserves every potentially nonzero left tap. Negative indices
    /// therefore occur only at stream startup. Double accumulation avoids float reduction
    /// error, and coefficient normalization preserves constants at each fractional phase.
    /// - Parameters:
    ///   - samples: Nonempty complete interleaved history plus any current block.
    ///   - phase: Nonnegative exact output-rate ticks relative to this history's origin.
    ///   - output: Destination array receiving one saturated frame in original channel order.
    private func appendFilteredFrame(from samples: [Float], phase: Int64, to output: inout [Float]) {
        let outputRate = Int64(outputFormat.sampleRate)
        let center = Int(phase / outputRate)
        let fraction = Double(phase % outputRate) / Double(outputRate)
        let channels = inputFormat.channelCount
        let last = samples.count / channels - 1
        var coefficientSum = 0.0
        var left = 0.0
        var right = 0.0
        for offset in (-lookaheadFrames + 1)...lookaheadFrames {
            let distance = Double(offset) - fraction
            let angle = Double.pi * distance / Double(lookaheadFrames)
            let window = 0.42 + 0.5 * cos(angle) + 0.08 * cos(2 * angle)
            let argument = Double.pi * cutoff * distance
            let sinc = abs(argument) < 1e-12 ? 1 : sin(argument) / argument
            let coefficient = cutoff * sinc * window
            let index = max(0, min(last, center + offset)) * channels
            coefficientSum += coefficient
            left += Double(samples[index]) * coefficient
            if channels == 2 { right += Double(samples[index + 1]) * coefficient }
        }
        output.append(Float(max(-1, min(1, left / coefficientSum))))
        if channels == 2 { output.append(Float(max(-1, min(1, right / coefficientSum)))) }
    }

    /// Splits complete normalized output frames into dense blocks within PCM's duration limit.
    /// - Parameter samples: Complete interleaved output produced by the bounded FIR loop.
    /// - Returns: Ordered nonempty buffers, or an empty array for no samples.
    /// - Throws: Propagates `PCMBuffer` validation failures for an internal invariant violation.
    private func makeBuffers(samples: [Float]) throws -> [PCMBuffer] {
        let maximumSamples = outputFormat.sampleRate * 120 / 1_000 * outputFormat.channelCount
        var blocks: [PCMBuffer] = []
        for start in stride(from: 0, to: samples.count, by: maximumSamples) {
            let end = min(samples.count, start + maximumSamples)
            blocks.append(try PCMBuffer(format: outputFormat, samples: Array(samples[start..<end])))
        }
        return blocks
    }
}
