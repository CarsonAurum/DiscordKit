import DiscordTransport
import DiscordTestSupport
import Testing

/// Real-clock deadline lifecycle regressions with successful ordering driven by gates.
@Suite struct ContinuousDeadlineTests {
    /// Repeated early completion cancels its far-future timer and preserves values.
    /// This exercises timer teardown rather than waiting for the expiration time.
    /// - Throws: Unexpected deadline/cancellation or operation failures.
    @Test func successfulDeadlineRaces() async throws {
        for value in 0..<256 {
            let clock = ContinuousClock()
            let context = TransportContext(clock: clock, deadline: clock.now.advanced(by: .seconds(60)))
            #expect(try await context.run { value } == value)
        }
    }

    /// A caller cancelled after operation admission terminates both deadline and
    /// operation children; no sleeps or wall-time assumptions control the test.
    /// - Throws: Barrier failures or unexpected completion.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func cancellationDuringDeadlineRace() async throws {
        let entered = TestBarrier()
        let pending = TestBarrier()
        let clock = ContinuousClock()
        let task = Task {
            try await TransportContext(clock: clock, deadline: clock.now.advanced(by: .seconds(60))).run {
                entered.open()
                try await pending.wait()
                return 1
            }
        }
        try await entered.wait()
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(pending.waitingCount == 0)
    }

    /// Inclusive expiration rejects work before dispatching it, and an original
    /// operation error cancels the associated far-future deadline without wrapping it.
    /// - Throws: Unexpected setup errors.
    @Test func expirationAndOperationFailure() async throws {
        let clock = ContinuousClock()
        await #expect(throws: TransportFailure.deadlineExceeded) {
            try await TransportContext(clock: clock, deadline: clock.now).run { 1 }
        }
        await #expect(throws: TransportFailure.closed) {
            try await TransportContext(clock: clock, deadline: clock.now.advanced(by: .seconds(60))).run {
                throw TransportFailure.closed
            } as Int
        }
    }
}
