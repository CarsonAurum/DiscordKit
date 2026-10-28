// File: Sources/DiscordInteractions/InteractionContext.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import DiscordModels
import Foundation

/// Configured delivery channel. Discord delivers interactions through exactly one channel per application;
/// Gateway delivery still acknowledges through the HTTP callback endpoint, never a Gateway opcode.
public enum InteractionDeliveryMode: Sendable, Equatable {
    case http
    case gateway
}

/// A monotonic clock erased without wall time, detached tasks or unchecked concurrency.
/// Share one value across receipt, admission and response ownership so offsets have one origin.
public struct InteractionClock: Sendable {
    private let read: @Sendable () -> Duration
    private let suspend: @Sendable (Duration) async throws -> Void

    /// Captures a clock-local origin without starting work.
    /// - Parameter clock: Monotonic clock; deterministic clocks work without real-time sleeps.
    public init<C: Clock>(_ clock: C) where C.Duration == Duration {
        let origin = clock.now
        read = { origin.duration(to: clock.now) }
        suspend = { offset in
            let deadline = origin.advanced(by: offset)
            // Match transport deadline ownership: some Apple runtimes retain cancelled native timer records
            // until their scheduled time. Bound continuous timers to a 100 ms checkpoint while preserving
            // injected clocks' deterministic registration/cancellation behavior and original time domain.
            if clock is ContinuousClock, let continuousDeadline = deadline as? ContinuousClock.Instant {
                let continuous = ContinuousClock()
                while continuous.now < continuousDeadline {
                    try Task.checkCancellation()
                    let checkpoint = min(continuousDeadline, continuous.now.advanced(by: .milliseconds(100)))
                    try await continuous.sleep(until: checkpoint, tolerance: nil)
                }
                try Task.checkCancellation()
            } else { try await clock.sleep(until: deadline, tolerance: nil) }
        }
    }

    /// Elapsed monotonic time from this value's captured origin, in seconds with Duration precision.
    public var now: Duration { read() }

    /// Suspends cooperatively until an offset in this exact clock's time domain.
    /// - Parameter deadline: Absolute offset from this clock's origin; past offsets return immediately.
    /// - Throws: Cancellation or the underlying injected clock's failure.
    /// Continuous clocks use 100 ms checkpoints to bound cancelled native timer retention; active long waits
    /// may wake ten times per second. Custom/injected clocks preserve their original sleep behavior.
    public func sleep(until deadline: Duration) async throws { try await suspend(deadline) }

    /// Bounds cooperative asynchronous work and awaits both child tasks before returning.
    /// - Parameters:
    ///   - deadline: Exclusive monotonic deadline in this clock's domain.
    ///   - operation: Work that must honor cancellation; it may have submitted a mutation before timeout.
    /// - Returns: Completed operation result before the deadline.
    /// - Throws: Cancellation, operation failure or `InteractionLifecycleError.deadlineExceeded`.
    ///   Cancellation cannot forcibly terminate a noncooperative injected operation.
    func run<Value: Sendable>(until deadline: Duration,
        operation: @escaping @Sendable () async throws -> Value) async throws -> Value {
        try Task.checkCancellation()
        guard now < deadline else { throw InteractionLifecycleError.deadlineExceeded }
        return try await withThrowingTaskGroup(of: Value.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await self.sleep(until: deadline)
                try Task.checkCancellation()
                throw InteractionLifecycleError.deadlineExceeded
            }
            defer { group.cancelAll() }
            guard let result = try await group.next() else { throw CancellationError() }
            try Task.checkCancellation()
            guard now < deadline else { throw InteractionLifecycleError.deadlineExceeded }
            return result
        }
    }
}

/// Transport-neutral handler input with the complete presence-aware interaction snapshot.
/// Unknown types, resolved resources, locales, entitlements, install owners and submitted values remain
/// in `interaction`; this wrapper never hydrates resources or trusts a permission snapshot as authorization.
public struct InteractionContext: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let interaction: Interaction
    public let deliveryMode: InteractionDeliveryMode
    public let responder: InteractionResponder

    /// Binds a snapshot to its unique response owner without starting tasks or network I/O.
    /// - Parameters:
    ///   - interaction: Authenticated HTTP input or trusted Gateway interaction payload.
    ///   - deliveryMode: Application's selected receipt mode; Gateway responses still use HTTP.
    ///   - responder: Actor for this exact interaction ID, application ID, token and delivery mode.
    /// - Throws: `InteractionLifecycleError.contextMismatch` when response ownership belongs to different input.
    public init(interaction: Interaction, deliveryMode: InteractionDeliveryMode,
        responder: InteractionResponder) throws {
        guard responder.matches(interaction, deliveryMode: deliveryMode) else {
            throw InteractionLifecycleError.contextMismatch
        }
        self.interaction = interaction; self.deliveryMode = deliveryMode; self.responder = responder
    }

    /// Conceals continuation tokens, user content and injected response closures.
    public var description: String { "InteractionContext(redacted)" }
    /// Uses the same safe representation during debugger formatting.
    public var debugDescription: String { description }
    /// Prevents reflective traversal into interaction secrets and response ownership.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}
