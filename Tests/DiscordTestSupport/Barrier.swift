// File: Tests/DiscordTestSupport/Barrier.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import Foundation
import Synchronization

/// Infrastructure capacity failures; tests choose explicit finite waiter/script bounds.
public enum TestSupportFailure: Error, Equatable, Sendable {
    case capacityExceeded
    case invalidAdvance
    case scripted(String)
}

/// An exactly-once cancellable suspension shared by deterministic support primitives.
@available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
final class Suspension: Sendable {
    private struct State {
        var result: Result<Void, any Error>?
        var continuation: CheckedContinuation<Void, any Error>?
    }
    private let state = Mutex(State())

    /// Waits until resolved; handles cancellation both before and after registration.
    /// - Throws: Cancellation or the failure supplied by the resolver.
    func wait() async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let result: Result<Void, any Error>? = state.withLock { state in
                    if let result = state.result { return result }
                    state.continuation = continuation
                    return nil
                }
                if let result { continuation.resume(with: result) }
                if Task.isCancelled { resolve(.failure(CancellationError())) }
            }
        } onCancel: {
            self.resolve(.failure(CancellationError()))
        }
    }

    /// Publishes the first completion only and resumes outside the mutex.
    /// - Parameter result: Success or failure; later resolutions are ignored.
    func resolve(_ result: Result<Void, any Error>) {
        let continuation = state.withLock { state in
            guard state.result == nil else { return nil as CheckedContinuation<Void, any Error>? }
            state.result = result
            let continuation = state.continuation
            state.continuation = nil
            return continuation
        }
        continuation?.resume(with: result)
    }
}

/// A one-shot bounded gate for controlled suspension, without wall-clock sleeps.
///
/// This development-only primitive uses `Synchronization.Mutex` and therefore has
/// higher OS minima than the portable runtime. Each test should own its own gate.
@available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
public final class TestBarrier: Sendable {
    private struct State {
        var open = false
        var waiters: [UUID: Suspension] = [:]
    }
    private let state = Mutex(State())
    private let maximumWaiters: Int
    private let onWaitScheduled: @Sendable () -> Void

    /// Creates a closed gate with a finite waiter limit.
    /// - Parameters:
    ///   - maximumWaiters: Positive capacity, default 1,024.
    ///   - onWaitScheduled: Synchronous registration hook used to open another test
    ///     gate; must not block or recursively wait on this gate.
    /// - Precondition: The capacity is positive.
    public init(maximumWaiters: Int = 1_024, onWaitScheduled: @escaping @Sendable () -> Void = {}) {
        precondition(maximumWaiters > 0)
        self.maximumWaiters = maximumWaiters
        self.onWaitScheduled = onWaitScheduled
    }

    /// Waits for opening; an already open gate returns without suspension.
    /// - Throws: Cancellation, including pre-cancellation, or capacity overflow.
    ///   Cancelled waiters remove themselves before returning.
    public func wait() async throws {
        try Task.checkCancellation()
        let id = UUID()
        let suspension = Suspension()
        let shouldWait = try state.withLock { state in
            if state.open { return false }
            guard state.waiters.count < maximumWaiters else { throw TestSupportFailure.capacityExceeded }
            state.waiters[id] = suspension
            return true
        }
        guard shouldWait else { return }
        defer { _ = state.withLock { $0.waiters.removeValue(forKey: id) } }
        onWaitScheduled()
        try await suspension.wait()
    }

    /// Opens the gate permanently and releases all registered waiters once.
    /// Repeated calls are harmless; no new waiter queue is retained after opening.
    public func open() {
        let waiters = state.withLock { state in
            state.open = true
            let waiters = Array(state.waiters.values)
            state.waiters.removeAll()
            return waiters
        }
        for waiter in waiters { waiter.resolve(.success(())) }
    }

    /// Returns registered waiters for assertions; this is a synchronous snapshot.
    public var waitingCount: Int {
        state.withLock { $0.waiters.count }
    }
}
