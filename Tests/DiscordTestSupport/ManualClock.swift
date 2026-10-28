// File: Tests/DiscordTestSupport/ManualClock.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import Foundation
import Synchronization

/// A monotonic, explicitly advanced Swift clock for deterministic deadline tests.
///
/// Sleepers do not advance time. Advancement resumes due sleepers without waiting
/// for their tasks to run. Cancellation removes registration before sleep returns.
/// The mutex requirement applies only to development support, not runtime products.
@available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
public final class ManualClock: Clock, Sendable {
    /// A clock-local duration offset; compare instants only from the same test clock.
    public struct Instant: InstantProtocol {
        public let offset: Duration

        /// Creates an instant relative to the test's arbitrary zero epoch.
        /// - Parameter offset: Offset from zero; negative values are allowed.
        public init(offset: Duration = .zero) { self.offset = offset }

        /// Adds an offset using Swift Duration's checked arithmetic.
        /// - Parameter duration: Signed offset; arithmetic overflow traps as in Duration.
        /// - Returns: A new instant, leaving this instant unchanged.
        public func advanced(by duration: Duration) -> Self { Self(offset: offset + duration) }

        /// Computes signed elapsed time to another instant in the same time domain.
        /// - Parameter other: Destination instant from this same test clock.
        /// - Returns: Positive, zero or negative elapsed duration.
        public func duration(to other: Self) -> Duration { other.offset - offset }

        /// Orders offsets within one clock domain.
        /// - Parameters:
        ///   - lhs: Earlier candidate.
        ///   - rhs: Later candidate.
        /// - Returns: Whether the left offset precedes the right offset.
        public static func < (lhs: Self, rhs: Self) -> Bool { lhs.offset < rhs.offset }
    }

    private struct Sleeper {
        let deadline: Instant
        let suspension: Suspension
    }
    private struct State {
        var now = Instant()
        var sleepers: [UUID: Sleeper] = [:]
    }
    private let state = Mutex(State())
    private let maximumSleepers: Int
    private let onSleepScheduled: @Sendable () -> Void

    /// Creates a clock at zero without spawning tasks or using system time.
    /// - Parameters:
    ///   - maximumSleepers: Positive finite sleeper capacity; default 1,024.
    ///   - onSleepScheduled: Synchronous hook after registration, before suspension;
    ///     useful for opening a test gate. Must not block or recursively sleep.
    /// - Precondition: The capacity is positive.
    public init(maximumSleepers: Int = 1_024, onSleepScheduled: @escaping @Sendable () -> Void = {}) {
        precondition(maximumSleepers > 0)
        self.maximumSleepers = maximumSleepers
        self.onSleepScheduled = onSleepScheduled
    }

    /// Returns a synchronized snapshot of explicitly advanced time.
    public var now: Instant { state.withLock { $0.now } }

    /// Reports one nanosecond resolution; the clock never advances itself.
    public var minimumResolution: Duration { .nanoseconds(1) }

    /// Returns pending registration count for leak and cancellation assertions.
    public var pendingSleepCount: Int { state.withLock { $0.sleepers.count } }

    /// Suspends until an explicit advance reaches the inclusive deadline.
    /// - Parameters:
    ///   - deadline: Clock-local deadline; past/present deadlines return immediately.
    ///   - tolerance: Accepted for Clock conformance; ignored, never waking early.
    /// - Throws: Cancellation or finite sleeper-capacity overflow. Cancellation wins
    ///   when already set before registration; concurrent completion races are unordered.
    public func sleep(until deadline: Instant, tolerance: Duration? = nil) async throws {
        try Task.checkCancellation()
        let id = UUID()
        let suspension = Suspension()
        let shouldWait = try state.withLock { state in
            if deadline <= state.now { return false }
            guard state.sleepers.count < maximumSleepers else { throw TestSupportFailure.capacityExceeded }
            state.sleepers[id] = Sleeper(deadline: deadline, suspension: suspension)
            return true
        }
        guard shouldWait else { return }
        defer { _ = state.withLock { $0.sleepers.removeValue(forKey: id) } }
        onSleepScheduled()
        try await suspension.wait()
    }

    /// Advances monotonically and resumes all due sleepers exactly once.
    /// - Parameter duration: Nonnegative elapsed time, including zero.
    /// - Throws: `TestSupportFailure.invalidAdvance` for negative movement; no change occurs.
    ///   Duration overflow traps using the standard library's arithmetic semantics.
    public func advance(by duration: Duration) throws {
        guard duration >= .zero else { throw TestSupportFailure.invalidAdvance }
        let due = state.withLock { state in
            state.now = state.now.advanced(by: duration)
            let due = state.sleepers.filter { $0.value.deadline <= state.now }
            for id in due.keys { state.sleepers.removeValue(forKey: id) }
            return due.values.map(\.suspension)
        }
        for suspension in due { suspension.resolve(.success(())) }
    }
}
