/// A synchronous bounded linear PCM converter with phase continuity across input blocks.
///
/// Input frame zero and output frame zero share an origin. Output frame `k` samples input
/// position `k * inputRate / outputRate`, interpolating independently in each channel. After
/// `finish()`, the total output is exactly `floor(totalInputFrames * outputRate / inputRate)`;
/// incomplete final interpolation uses a held final sample. Block boundaries do not affect
/// either the samples or aggregate count. No anti-alias filter is supplied, so downsampling
/// can alias and this converter does not establish production bandlimited audio quality.
///
/// Only the last input frame and at most one count-deferred output frame are retained, at
/// most four floats for stereo. The latter preserves the original first sample when a very
/// short downsampling block has not yet earned an output frame. Integer phase and admission
/// remainders are relative and bounded independently of stream duration. No source block,
/// lifetime frame counter, timestamp, task, device, network resource or I/O is retained.
/// Values have independent copy-on-write state; callers serialize mutation of each value.
public struct PCMStreamingResampler: Sendable {
    /// Required input rate and channel layout, fixed until a new converter is constructed.
    public let inputFormat: PCMFormat

    /// Destination rate with the input's mono or stereo channel order preserved.
    public let outputFormat: PCMFormat

    /// Whether `finish()` has closed admission; `reset()` opens a fresh empty stream.
    public private(set) var isFinished = false

    /// Final input frame only, densely owned rather than retaining an input block or slice.
    private var lastInputFrame: [Float] = []

    /// One already interpolated frame waiting for the aggregate floor-count admission.
    private var deferredOutputFrame: [Float] = []

    /// Next interpolation position, in output-rate ticks relative to the next input block.
    private var phase: Int64 = 0

    /// Fractional output entitlement, reduced modulo the positive input sample rate.
    private var admissionRemainder: Int64 = 0

    /// Count-admitted frames awaiting a right interpolation endpoint, at most 23 frames.
    private var pendingOutputFrames = 0

    /// Creates an empty converter without starting work or retaining caller-owned resources.
    /// - Parameters:
    ///   - inputFormat: Validated mono/stereo PCM layout required by every input block.
    ///   - outputSampleRate: Destination frames per second in `8_000...192_000`.
    ///     Equal rates are valid and preserve the input samples exactly.
    /// - Throws: `MediaError.invalidFormat` for an unsupported destination sample rate.
    public init(inputFormat: PCMFormat, outputSampleRate: Int) throws {
        self.inputFormat = inputFormat
        self.outputFormat = try PCMFormat(
            sampleRate: outputSampleRate, channelCount: inputFormat.channelCount
        )
    }

    /// Converts the next contiguous PCM block without treating its end as the stream's end.
    ///
    /// A fractional position requiring the next block's first sample is deferred. During
    /// downsampling, one interpolated sample can also wait for sufficient input duration
    /// to satisfy the aggregate floor count. No samples are padded between blocks. Empty
    /// blocks are valid no-ops after format and lifecycle validation. Processing performs
    /// bounded linear synchronous work, has no suspension or cancellation point, and retains
    /// no input storage. At most two newly owned, nonempty output buffers are returned.
    /// - Parameter buffer: The next at-most-120ms block, exactly matching `inputFormat`.
    /// - Returns: Ordered output blocks, each at most 120ms, or an empty array when no output
    ///   is ready. An input block need not immediately produce all its count-admitted frames.
    /// - Throws: `MediaError.closed` after finishing, or `incompatibleBuffers` for a differing
    ///   input format. Both checks precede mutation; rejected blocks leave all state unchanged.
    public mutating func process(_ buffer: PCMBuffer) throws -> [PCMBuffer] {
        guard !isFinished else { throw MediaError.closed }
        guard buffer.format == inputFormat else { throw MediaError.incompatibleBuffers }
        guard buffer.frameCount > 0 else { return [] }

        let inputRate = Int64(inputFormat.sampleRate)
        let outputRate = Int64(outputFormat.sampleRate)
        let channels = inputFormat.channelCount
        let entitlement = admissionRemainder + Int64(buffer.frameCount) * outputRate
        var pending = pendingOutputFrames + Int(entitlement / inputRate)
        var nextPhase = phase
        var deferred = deferredOutputFrame
        var output: [Float] = []
        output.reserveCapacity(pending * channels)

        if pending > 0, !deferred.isEmpty {
            output.append(contentsOf: deferred)
            deferred = []
            pending -= 1
        }

        while deferred.isEmpty {
            // A negative phase can reference only the immediately preceding input frame.
            let lower = nextPhase < 0 ? -1 : Int(nextPhase / outputRate)
            let remainder = nextPhase < 0 ? nextPhase + outputRate : nextPhase % outputRate
            guard lower < buffer.frameCount,
                  remainder == 0 || lower + 1 < buffer.frameCount else { break }
            let weight = Float(remainder) / Float(outputRate)
            let isAdmitted = pending > 0
            if !isAdmitted { deferred.reserveCapacity(channels) }
            for channel in 0..<channels {
                let first = lower == -1
                    ? lastInputFrame[channel] : buffer.samples[lower * channels + channel]
                let second = remainder == 0 ? first : buffer.samples[(lower + 1) * channels + channel]
                let sample = max(-1, min(1, first + (second - first) * weight))
                if isAdmitted { output.append(sample) }
                else { deferred.append(sample) }
            }
            nextPhase += inputRate
            if isAdmitted { pending -= 1 }
        }

        let blocks = try makeBuffers(samples: output)
        lastInputFrame = buffer.samples.withUnsafeBufferPointer { Array($0.suffix(channels)) }
        deferredOutputFrame = deferred
        phase = nextPhase - Int64(buffer.frameCount) * outputRate
        admissionRemainder = entitlement % inputRate
        pendingOutputFrames = pending
        return blocks
    }

    /// Emits the count-admitted tail using the final input frame, then closes the stream.
    ///
    /// The final sample is held only here, never at an ordinary block boundary. An output
    /// sample computed before sufficient duration accrued is discarded, preserving the exact
    /// aggregate floor count even for one-frame downsampling streams. Retained audio and phase
    /// are cleared. Finishing an empty or already finished converter returns an empty array.
    /// This synchronous operation starts no work and has no cancellation or suspension point.
    /// - Returns: Zero or one nonempty at-most-120ms tail block; repeated calls return `[]`.
    /// - Throws: No errors for values created through the validated public API. Internal
    ///   `PCMBuffer` validation errors propagate if its storage invariants are violated.
    public mutating func finish() throws -> [PCMBuffer] {
        guard !isFinished else { return [] }
        var samples: [Float] = []
        samples.reserveCapacity(pendingOutputFrames * inputFormat.channelCount)
        for _ in 0..<pendingOutputFrames {
            samples.append(contentsOf: lastInputFrame)
        }
        let blocks = try makeBuffers(samples: samples)
        reset()
        isFinished = true
        return blocks
    }

    /// Discards all interpolation history and pending output, reopening an empty stream.
    ///
    /// Formats remain fixed. The next input frame becomes a fresh origin; this can introduce
    /// an audible discontinuity and intentionally abandons the previous stream's unflushed
    /// tail. Calling repeatedly or before processing is valid. No work or I/O is started.
    public mutating func reset() {
        lastInputFrame = []
        deferredOutputFrame = []
        phase = 0
        admissionRemainder = 0
        pendingOutputFrames = 0
        isFinished = false
    }

    /// Splits a bounded interleaved output into dense blocks within PCM's 120ms limit.
    /// - Parameter samples: Complete normalized output frames in channel order; at most one
    ///   input block's conversion plus the bounded previously deferred interpolation tail.
    /// - Returns: Ordered nonempty owned buffers, or an empty array for no samples.
    /// - Throws: Propagates `PCMBuffer` validation errors for an internal invariant violation;
    ///   validated input and convex interpolation cannot produce an invalid public result.
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
