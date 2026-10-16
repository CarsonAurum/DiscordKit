import DiscordTestSupport
import Synchronization

/// Injects clock transitions after a sampled instant or during losing-timer cleanup.
///
/// These hooks model time/cancellation changes at completion boundaries without
/// scheduler-dependent sleeps. Each fixture owns its counter and underlying clock.
@available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
final class CompletionBoundaryClock: Clock, Sendable {
    typealias Instant = ManualClock.Instant
    private let clock: ManualClock
    private let snapshotCount = Mutex(0)
    private let afterSnapshot: @Sendable (Int) -> Void
    private let afterCancelledSleep: @Sendable () -> Void

    /// Stores hooks without sampling or advancing the supplied manual clock.
    /// - Parameters:
    ///   - clock: Per-test time domain used for instants, advancement, and sleepers.
    ///   - afterSnapshot: Receives the one-based sample count after sampling `now`;
    ///     default does nothing. Must be synchronous, bounded, and nonrecursive.
    ///   - afterCancelledSleep: Called when a sleeper throws cancellation, before
    ///     propagating that error; default does nothing. Must not block or sleep.
    init(clock: ManualClock, afterSnapshot: @escaping @Sendable (Int) -> Void = { _ in },
         afterCancelledSleep: @escaping @Sendable () -> Void = {}) {
        self.clock = clock
        self.afterSnapshot = afterSnapshot
        self.afterCancelledSleep = afterCancelledSleep
    }

    /// Samples time before running the hook, modeling a transition after a check's snapshot.
    /// - Returns: The sampled instant even if the hook subsequently advances the clock.
    var now: Instant {
        let instant = clock.now
        let count = snapshotCount.withLock { count in count += 1; return count }
        afterSnapshot(count)
        return instant
    }

    /// Reports the underlying manual clock's one-nanosecond resolution.
    var minimumResolution: Duration { clock.minimumResolution }

    /// Delegates bounded manual suspension and invokes the cancellation-boundary hook.
    /// - Parameters:
    ///   - deadline: Inclusive wake instant in the supplied manual clock's domain.
    ///   - tolerance: Forwarded unchanged; the manual clock never wakes early.
    /// - Throws: Cancellation after its hook runs, or the manual clock's capacity failure.
    func sleep(until deadline: Instant, tolerance: Duration? = nil) async throws {
        do { try await clock.sleep(until: deadline, tolerance: tolerance) }
        catch {
            if error is CancellationError { afterCancelledSleep() }
            throw error
        }
    }
}
