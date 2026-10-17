/// Admission failures for caller-driven PCM pacing; no internal waiter queue is retained.
public enum PCMPacingError: Error, Sendable, Equatable {
    case invalidFrameCount
    case concurrentWait
}

/// Monotonic, sample-count-based pacing with at most one caller-owned suspended wait.
///
/// Construction captures the injected clock's current instant and starts no tasks or
/// I/O. The first frame starts immediately; each successful wait reserves the duration
/// of that frame for the following wait. Integer nanosecond remainder is carried
/// between frames, avoiding cumulative truncation drift at rates such as 44,100 Hz.
/// This is scheduling, not a realtime audio callback guarantee. Late frames are reported
/// to the consumer, which owns drop/PLC decisions; the pacer never manufactures PCM.
public actor PCMFramePacer<C: Clock> where C.Duration == Duration {
    public let sampleRate: Int
    public private(set) var isWaiting = false
    private let clock: C
    private var deadline: C.Instant
    private var nanosecondRemainder: Int64 = 0

    /// Creates a local timing origin without acquiring any device or executor resource.
    /// - Parameters:
    ///   - clock: Monotonic clock whose sleep must cooperate with cancellation. Its
    ///     resolution and wakeup accuracy bound actual scheduling precision.
    ///   - sampleRate: PCM sample frames per second in `8_000...192_000`.
    /// - Throws: `MediaError.invalidFormat` for a sample rate outside storage bounds.
    public init(clock: C, sampleRate: Int = 48_000) throws {
        _ = try PCMFormat(sampleRate: sampleRate, channelCount: 1)
        self.clock = clock
        self.sampleRate = sampleRate
        deadline = clock.now
    }

    /// Waits for a frame's start and reserves its duration only after a successful wait.
    ///
    /// Actor admission preserves ordering. Overlapping callers fail immediately rather
    /// than accumulating tasks. Cancellation and clock errors leave the sample schedule
    /// unchanged, including its fractional remainder. A caller retrying that same frame
    /// receives its original scheduled start. No child task or timer is library-owned.
    /// - Parameter frameCount: Positive frame count, at most `floor(sampleRate * .120)`;
    ///   channel count does not affect timing. Empty buffers should be skipped by callers.
    /// - Returns: Nonnegative lateness of this frame in the injected clock's duration domain.
    ///   Zero means the clock reached its scheduled start without observed lateness.
    /// - Throws: `CancellationError`, the clock's original sleep error,
    ///   `PCMPacingError.invalidFrameCount` outside the 120ms bound, or `concurrentWait`
    ///   while another caller is suspended. Failed calls reserve no interval.
    public func wait(frameCount: Int) async throws -> Duration {
        try Task.checkCancellation()
        guard (1...(sampleRate * 120 / 1_000)).contains(frameCount) else {
            throw PCMPacingError.invalidFrameCount
        }
        guard !isWaiting else { throw PCMPacingError.concurrentWait }
        isWaiting = true
        defer { isWaiting = false }
        let start = deadline
        if clock.now < start { try await clock.sleep(until: start, tolerance: .zero) }
        try Task.checkCancellation()
        let numerator = Int64(frameCount) * 1_000_000_000 + nanosecondRemainder
        let nanoseconds = numerator / Int64(sampleRate)
        nanosecondRemainder = numerator % Int64(sampleRate)
        deadline = start.advanced(by: .nanoseconds(nanoseconds))
        return max(.zero, start.duration(to: clock.now))
    }

    /// Starts a fresh timing origin after a seek, long interruption or deliberate discontinuity.
    /// - Throws: `PCMPacingError.concurrentWait` if a wait is in progress. Cancel and
    ///   await that caller first. Success drops fractional timing history without starting work.
    public func reset() throws {
        guard !isWaiting else { throw PCMPacingError.concurrentWait }
        deadline = clock.now
        nanosecondRemainder = 0
    }
}
