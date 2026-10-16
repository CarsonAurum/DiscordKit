import DiscordTestSupport
import DiscordTransport
import Foundation
import Testing

/// Deterministic clocks, gates, reproducible randomness and cleanup accounting.
@Suite("Deterministic support")
struct TestSupportTests {
    /// Exercises instant comparison, signed duration, Clock resolution and monotonic advance.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func clockArithmeticAndImmediateSleep() async throws {
        let clock = ManualClock()
        let zero = clock.now
        let future = zero.advanced(by: .seconds(5))
        #expect(zero < future)
        #expect(zero.duration(to: future) == .seconds(5))
        #expect(future.duration(to: zero) == .seconds(-5))
        #expect(Set([zero, zero, future]).count == 2)
        #expect(clock.minimumResolution == .nanoseconds(1))
        try await clock.sleep(until: zero, tolerance: .seconds(1))
        try await clock.sleep(until: zero.advanced(by: .seconds(-1)))
        try clock.advance(by: .zero)
        #expect(throws: TestSupportFailure.invalidAdvance) { try clock.advance(by: .nanoseconds(-1)) }
        #expect(clock.now == zero)
        try clock.advance(by: .seconds(5))
        #expect(clock.now == future)
        #expect(clock.pendingSleepCount == 0)
    }

    /// Advances only after registration and proves no early wake at the preceding instant.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func clockSuspensionAndCancellation() async throws {
        let scheduled = TestBarrier()
        let clock = ManualClock(onSleepScheduled: { scheduled.open() })
        let task = Task { try await clock.sleep(until: clock.now.advanced(by: .seconds(2))) }
        try await scheduled.wait()
        #expect(clock.pendingSleepCount == 1)
        try clock.advance(by: .seconds(1))
        #expect(clock.pendingSleepCount == 1)
        try clock.advance(by: .seconds(1))
        try await task.value
        #expect(clock.pendingSleepCount == 0)
        let secondScheduled = TestBarrier()
        let second = ManualClock(onSleepScheduled: { secondScheduled.open() })
        let cancel = Task { try await second.sleep(until: second.now.advanced(by: .seconds(5))) }
        try await secondScheduled.wait()
        cancel.cancel()
        await #expect(throws: CancellationError.self) { try await cancel.value }
        #expect(second.pendingSleepCount == 0)
        let before = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await second.sleep(until: second.now)
        }
        await #expect(throws: CancellationError.self) { try await before.value }
    }

    /// Uses the clock registration hook to overflow finite sleeper capacity deterministically.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func clockCapacity() async throws {
        let scheduled = TestBarrier()
        let clock = ManualClock(maximumSleepers: 1, onSleepScheduled: { scheduled.open() })
        let task = Task { try await clock.sleep(until: clock.now.advanced(by: .seconds(1))) }
        try await scheduled.wait()
        await #expect(throws: TestSupportFailure.capacityExceeded) {
            try await clock.sleep(until: clock.now.advanced(by: .seconds(1)))
        }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    /// Confirms known SplitMix64 vectors and repeatability for boundary seeds.
    /// - Parameter seed: Zero, a typical seed, or UInt64's maximum wrapping boundary.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [UInt64(0), UInt64(1), UInt64.max]) func deterministicRandom(_ seed: UInt64) {
        var first = SeededRandom(seed: seed)
        var second = SeededRandom(seed: seed)
        let values = (0..<32).map { _ in first.next() }
        #expect(values == (0..<32).map { _ in second.next() })
        #expect(Set(values).count == values.count)
        if seed == 0 { #expect(values[0] == 0xE220A8397B1DCDAF) }
    }

    /// Opens before waiting and repeats opening; already cancelled tasks still throw.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func barrierOpenAndPreCancellation() async throws {
        let barrier = TestBarrier()
        barrier.open(); barrier.open()
        try await barrier.wait()
        #expect(barrier.waitingCount == 0)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await barrier.wait()
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    /// Controlled registration proves gate overflow, cancellation removal and safe repeated opening.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func barrierSuspensionCapacityAndCancellation() async throws {
        let registered = TestBarrier()
        let barrier = TestBarrier(maximumWaiters: 1, onWaitScheduled: { registered.open() })
        let task = Task { try await barrier.wait() }
        try await registered.wait()
        #expect(barrier.waitingCount == 1)
        await #expect(throws: TestSupportFailure.capacityExceeded) { try await barrier.wait() }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(barrier.waitingCount == 0)
        barrier.open(); barrier.open()
        try await barrier.wait()
        let secondRegistered = TestBarrier()
        let second = TestBarrier(onWaitScheduled: { secondRegistered.open() })
        let waiter = Task { try await second.wait() }
        try await secondRegistered.wait()
        second.open(); second.open()
        try await waiter.value
        #expect(second.waitingCount == 0)
    }

    /// Releasing copies concurrently increments cleanup once per acquisition, including cancellation.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func exactlyOnceResources() async throws {
        let counter = ResourceCounter()
        let first = await counter.acquire()
        let second = await counter.acquire()
        #expect(await counter.snapshot().live == 2)
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<16 { group.addTask { await first.release() } }
        }
        #expect(await counter.snapshot().released == 1)
        let task = Task { withUnsafeCurrentTask { $0?.cancel() }; await second.release() }
        await task.value
        let snapshot = await counter.snapshot()
        #expect(snapshot.acquired == 2)
        #expect(snapshot.released == 2)
        #expect(snapshot.live == 0)
        #expect(await counter.snapshot() == snapshot)
    }
}
