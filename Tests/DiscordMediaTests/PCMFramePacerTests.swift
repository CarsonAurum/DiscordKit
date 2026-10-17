import DiscordMedia
import DiscordTestSupport
import Testing

/// Exercises pacing with a manually advanced clock; no wall-clock sleeps or devices are used.
@Suite("PCM sample pacing")
struct PCMFramePacerTests {
    /// The first frame is immediate, a subsequent frame suspends and overlapping calls fail.
    /// Explicit clock advancement proves exact deadlines and removal of the sole sleeper.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func admissionAndFrameTiming() async throws {
        let scheduled = TestBarrier()
        let clock = ManualClock(onSleepScheduled: { scheduled.open() })
        let pacer = try PCMFramePacer(clock: clock)
        #expect(await pacer.sampleRate == 48_000)
        #expect(try await pacer.wait(frameCount: 960) == .zero)
        let second = Task { try await pacer.wait(frameCount: 960) }
        try await scheduled.wait()
        #expect(await pacer.isWaiting)
        #expect(clock.pendingSleepCount == 1)
        await #expect(throws: PCMPacingError.concurrentWait) { try await pacer.wait(frameCount: 1) }
        await #expect(throws: PCMPacingError.concurrentWait) { try await pacer.reset() }
        try clock.advance(by: .milliseconds(19))
        #expect(clock.pendingSleepCount == 1)
        try clock.advance(by: .milliseconds(1))
        #expect(try await second.value == .zero)
        #expect(clock.pendingSleepCount == 0)
        #expect(await !pacer.isWaiting)
    }

    /// Cancellation before admission and during sleep consumes no interval and releases the clock.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func cancellationAndRetry() async throws {
        let scheduled = TestBarrier()
        let clock = ManualClock(onSleepScheduled: { scheduled.open() })
        let pacer = try PCMFramePacer(clock: clock)
        let before = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await pacer.wait(frameCount: 960)
        }
        await #expect(throws: CancellationError.self) { try await before.value }
        #expect(try await pacer.wait(frameCount: 960) == .zero)
        let waiting = Task { try await pacer.wait(frameCount: 960) }
        try await scheduled.wait()
        waiting.cancel()
        await #expect(throws: CancellationError.self) { try await waiting.value }
        #expect(clock.pendingSleepCount == 0)
        #expect(await !pacer.isWaiting)
        try clock.advance(by: .milliseconds(20))
        #expect(try await pacer.wait(frameCount: 960) == .zero)
        #expect(clock.pendingSleepCount == 0)
    }

    /// Late callers observe lateness; reset begins a new immediate schedule at the same rate.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func latenessAndReset() async throws {
        let clock = ManualClock()
        let pacer = try PCMFramePacer(clock: clock, sampleRate: 8_000)
        #expect(try await pacer.wait(frameCount: 80) == .zero)
        try clock.advance(by: .milliseconds(25))
        #expect(try await pacer.wait(frameCount: 80) == .milliseconds(15))
        try await pacer.reset()
        #expect(try await pacer.wait(frameCount: 960) == .zero)
        #expect(clock.pendingSleepCount == 0)
    }

    /// Fractional nanoseconds accumulate to exactly one second at 44,100Hz without early drift.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func fractionalNanosecondCarry() async throws {
        let clock = ManualClock()
        let pacer = try PCMFramePacer(clock: clock, sampleRate: 44_100)
        // Run late so no test task needs a timer for each of 44,100 samples.
        try clock.advance(by: .seconds(1))
        for _ in 0..<44_100 { _ = try await pacer.wait(frameCount: 1) }
        #expect(try await pacer.wait(frameCount: 1) == .zero)
        #expect(clock.pendingSleepCount == 0)
    }

    /// Rejects all invalid counts without changing the first-frame origin or creating a sleeper.
    /// - Parameter count: Zero, negative, over-120ms and overflow-prone frame counts.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [0, -1, 5_761, Int.min, Int.max])
    func invalidFrameCounts(count: Int) async throws {
        let clock = ManualClock()
        let pacer = try PCMFramePacer(clock: clock)
        await #expect(throws: PCMPacingError.invalidFrameCount) { try await pacer.wait(frameCount: count) }
        #expect(try await pacer.wait(frameCount: 5_760) == .zero)
        #expect(clock.pendingSleepCount == 0)
    }

    /// Invalid rate admission is independent of clock scheduling or construction side effects.
    /// - Parameter rate: Invalid lower, upper and extreme rate values.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [7_999, 192_001, Int.min, Int.max])
    func invalidRates(rate: Int) {
        #expect(throws: MediaError.invalidFormat) { try PCMFramePacer(clock: ManualClock(), sampleRate: rate) }
    }

    /// An injected sleep failure leaves timing and fractional accounting untouched for retry.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func clockFailure() async throws {
        let clock = ManualClock()
        let failing = FailingClock(base: clock)
        let pacer = try PCMFramePacer(clock: failing)
        _ = try await pacer.wait(frameCount: 960)
        await #expect(throws: TestSupportFailure.scripted("clock")) { try await pacer.wait(frameCount: 960) }
        #expect(await !pacer.isWaiting)
        try clock.advance(by: .milliseconds(20))
        #expect(try await pacer.wait(frameCount: 960) == .zero)
    }

    /// Uses the manual time domain while failing every attempted sleep deterministically.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    private struct FailingClock: Clock {
        let base: ManualClock

        /// Reads the injected clock's current instant without creating another time domain.
        var now: ManualClock.Instant { base.now }

        /// Uses the base clock's one-nanosecond resolution.
        var minimumResolution: Duration { base.minimumResolution }

        /// Throws a fixture failure for every requested deadline; it never registers a timer.
        /// - Parameters:
        ///   - deadline: Ignored base-clock deadline.
        ///   - tolerance: Ignored caller tolerance.
        /// - Throws: `TestSupportFailure.scripted("clock")` unconditionally.
        func sleep(until deadline: ManualClock.Instant, tolerance: Duration?) async throws {
            throw TestSupportFailure.scripted("clock")
        }
    }
}
