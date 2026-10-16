import DiscordTestSupport
import Foundation
import Testing
@testable import DiscordHTTP

/// Virtual-time cache and gated single-flight regressions, independent of Discord or sockets.
@Suite(.timeLimit(.minutes(1)))
struct ReadReuseTests {
    /// Verifies freshness boundaries, tag invalidation, identity isolation and stale fetch fencing.
    @Test func freshnessAndInvalidation() async throws {
        guard #available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *) else { return }
        let clock = ManualClock()
        let cache = ReadCache(clock: clock)
        let identity = RateLimitIdentity()
        let key = HTTPReadKey(identity: identity, representation: "GET /users/@me")
        let foreign = HTTPReadKey(identity: RateLimitIdentity(), representation: "GET /users/@me")
        let generation = await cache.generation()
        await cache.insert(Data([1]), for: key, timeToLive: .seconds(1), tags: ["user"], generation: generation)
        #expect(await cache.value(for: key) == Data([1]))
        #expect(await cache.value(for: foreign) == nil)
        try clock.advance(by: .seconds(1))
        #expect(await cache.value(for: key) == nil)
        await cache.insert(Data([2]), for: key, timeToLive: .seconds(2), tags: ["user"], generation: generation)
        await cache.invalidate(identity: identity, tags: ["application"])
        #expect(await cache.value(for: key) == Data([2]))
        await cache.invalidate(identity: identity, tags: ["user"])
        #expect(await cache.value(for: key) == nil)
        await cache.insert(Data([3]), for: key, timeToLive: .seconds(2), tags: [], generation: generation)
        #expect(await cache.value(for: key) == nil)
        await cache.insert(Data([4]), for: key, timeToLive: .zero, tags: [], generation: await cache.generation())
        #expect(await cache.snapshot().entries == 0)
        #expect(String(reflecting: key) == "HTTPReadKey(redacted)")
        #expect(key.customMirror.children.count == 1)
    }

    /// Exercises per-identity and aggregate LRU budgets, replacement, expiry and disabled retention.
    @Test func cacheBudgets() async {
        guard #available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *) else { return }
        let clock = ManualClock()
        let cache = ReadCache(clock: clock, policy: .init(maximumEntries: 2, maximumBytes: 3,
            maximumEntriesPerIdentity: 1, maximumBytesPerIdentity: 2))
        let a = RateLimitIdentity()
        let first = HTTPReadKey(identity: a, representation: "a")
        let replacement = HTTPReadKey(identity: a, representation: "b")
        let second = HTTPReadKey(identity: RateLimitIdentity(), representation: "c")
        await cache.insert(Data([1, 2]), for: first, timeToLive: .seconds(2), tags: [], generation: 0)
        await cache.insert(Data([3]), for: replacement, timeToLive: .seconds(2), tags: [], generation: 0)
        #expect(await cache.value(for: first) == nil)
        await cache.insert(Data([4, 5]), for: second, timeToLive: .seconds(2), tags: [], generation: 0)
        #expect(await cache.snapshot().bytes == 3)
        await cache.insert(Data([6, 7, 8]), for: first, timeToLive: .seconds(2), tags: [], generation: 0)
        #expect(await cache.snapshot().entries == 2)
        await cache.insert(Data([9, 10]), for: replacement, timeToLive: .seconds(2), tags: [], generation: 0)
        #expect(await cache.value(for: second) == nil)
        #expect(await cache.snapshot().bytes == 2)
        await cache.invalidate(identity: a)
        #expect(await cache.snapshot().entries == 0)
        await cache.removeAll()
        #expect(await cache.generation() == 2)
        let disabled = ReadCache(clock: clock, policy: .init(maximumEntries: 0))
        await disabled.insert(Data(), for: first, timeToLive: .seconds(1), tags: [], generation: 0)
        #expect(await disabled.snapshot().entries == 0)
    }

    /// Oversized representation metadata cannot bypass finite retained-memory budgets.
    @Test func oversizedKeysAreRefused() async throws {
        guard #available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *) else { return }
        let clock = ManualClock()
        let cache = ReadCache(clock: clock)
        let coalescer = RequestCoalescer()
        let key = HTTPReadKey(identity: RateLimitIdentity(), representation: String(repeating: "x", count: 131_073))
        await cache.insert(Data([1]), for: key, timeToLive: .seconds(1), tags: [], generation: 0)
        #expect(await cache.snapshot().entries == 0)
        await #expect(throws: HTTPReadFailure.capacityExceeded) { try await coalescer.run(key: key) { Data() } }
        #expect(await coalescer.snapshot().flights == 0)
    }

    /// One hundred equivalent callers share one exchange; a different scope starts another.
    @Test func hundredReadersAndIndependentScopes() async throws {
        guard #available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *) else { return }
        let coalescer = RequestCoalescer()
        let key = HTTPReadKey(identity: RateLimitIdentity(), representation: "same")
        let gate = TestBarrier()
        let counter = ExchangeCounter()
        let tasks = (0..<100).map { _ in Task {
            try await coalescer.run(key: key) {
                await counter.increment()
                try await gate.wait()
                return Data([42])
            }
        } }
        while await coalescer.snapshot().waiters < 100 { try Task.checkCancellation(); await Task.yield() }
        #expect(await counter.value == 1)
        let foreign = try await coalescer.run(key: .init(identity: RateLimitIdentity(), representation: "same")) {
            await counter.increment()
            return Data([7])
        }
        #expect(foreign == Data([7]))
        gate.open()
        for task in tasks { #expect(try await task.value == Data([42])) }
        #expect(await counter.value == 2)
        #expect(await coalescer.snapshot().flights == 0)
        #expect(await coalescer.snapshot().waiters == 0)
        await coalescer.close()
        await #expect(throws: HTTPReadFailure.closed) { try await coalescer.run(key: key) { Data() } }
    }

    /// Cancelling one subscriber preserves the other; final cancellation awaits operation cleanup.
    @Test func independentCancellationAndClose() async throws {
        guard #available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *) else { return }
        let coalescer = RequestCoalescer()
        let key = HTTPReadKey(identity: RateLimitIdentity(), representation: "cancel")
        let gate = TestBarrier()
        let first = Task { try await coalescer.run(key: key) { try await gate.wait(); return Data([1]) } }
        while await coalescer.snapshot().waiters < 1 { try Task.checkCancellation(); await Task.yield() }
        let second = Task { try await coalescer.run(key: key) { Issue.record("duplicate exchange"); return Data() } }
        while await coalescer.snapshot().waiters < 2 { try Task.checkCancellation(); await Task.yield() }
        first.cancel()
        await #expect(throws: CancellationError.self) { try await first.value }
        #expect(await coalescer.snapshot().waiters == 1)
        gate.open()
        #expect(try await second.value == Data([1]))
        let closedGate = TestBarrier()
        let third = Task { try await coalescer.run(key: key) { try await closedGate.wait(); return Data() } }
        while await coalescer.snapshot().waiters < 1 { try Task.checkCancellation(); await Task.yield() }
        await coalescer.close()
        await #expect(throws: CancellationError.self) { try await third.value }
        #expect(await coalescer.snapshot().waiters == 0)
        #expect(closedGate.waitingCount == 0)
        await coalescer.close()
    }

    /// Bounded admission rejects excess flights/subscribers and propagates original exchange errors.
    @Test func coalescerOverloadAndFailure() async throws {
        guard #available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *) else { return }
        let coalescer = RequestCoalescer(maximumFlights: 1, maximumFlightsPerIdentity: 1,
            maximumWaiters: 1, maximumWaitersPerFlight: 1)
        let key = HTTPReadKey(identity: RateLimitIdentity(), representation: "one")
        let gate = TestBarrier()
        let task = Task { try await coalescer.run(key: key) { try await gate.wait(); return Data() } }
        while await coalescer.snapshot().waiters < 1 { try Task.checkCancellation(); await Task.yield() }
        await #expect(throws: HTTPReadFailure.capacityExceeded) { try await coalescer.run(key: key) { Data() } }
        await #expect(throws: HTTPReadFailure.capacityExceeded) {
            try await coalescer.run(key: .init(identity: key.identity, representation: "other")) { Data() }
        }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await coalescer.snapshot().flights == 0)
        await #expect(throws: HTTPReadFailure.closed) { try await coalescer.run(key: key) { throw HTTPReadFailure.closed } }
        #expect(await coalescer.snapshot().waiters == 0)
    }
}

/// Actor-owned exchange counter used to assert request reduction without race-prone counters.
private actor ExchangeCounter {
    var value = 0
    /// Records one observed physical exchange; actor isolation serializes concurrent starts.
    func increment() { value += 1 }
}
