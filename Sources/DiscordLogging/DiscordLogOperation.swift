// File: Sources/DiscordLogging/DiscordLogOperation.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import Foundation

extension DiscordLog {
    /// Executes synchronous work in a correlated diagnostic scope and preserves its result.
    ///
    /// Emits trace start and exactly one terminal event with monotonic elapsed nanoseconds.
    /// Nested scopes share a trace and receive distinct spans. Errors are rethrown unchanged;
    /// only cancellation/failure categories are logged, never error descriptions. Scope exit
    /// restores the parent's context. This helper does not retry, acknowledge or own work.
    /// - Parameters:
    ///   - subsystem: Fixed dotted logging category.
    ///   - event: Fixed operation event prefix; suffixes are `.started`, `.completed`,
    ///     `.cancelled` or `.failed`. Never supply user-controlled values.
    ///   - operation: Work executed exactly once, synchronously in the caller's context.
    /// - Returns: The operation's unchanged return value.
    /// - Throws: The operation's unchanged error; cancellation is also rethrown.
    public static func withOperation<Value>(
        _ subsystem: String, event: String, operation: () throws -> Value
    ) rethrows -> Value {
        let metadata = operationContext()
        return try $context.withValue(metadata) {
            let scope = OperationScope(logger: makeLogger(subsystem), event: event)
            do {
                let value = try operation()
                scope.complete()
                return value
            } catch {
                scope.fail(error)
                throw error
            }
        }
    }

    /// Executes asynchronous work with correlated child diagnostics and monotonic timing.
    ///
    /// Structured child tasks inherit the scope; detached tasks do not. The caller's actor
    /// isolation is preserved across suspension. Logging introduces no tasks or cancellation
    /// handler, and an operation which ignores cancellation retains its original semantics.
    /// - Parameters:
    ///   - subsystem: Fixed dotted logging category, without the `discordkit.` prefix.
    ///   - event: Fixed event prefix; the helper adds a start and one terminal suffix.
    ///   - isolation: Caller actor isolation, inferred automatically; callers normally omit it.
    ///   - operation: Asynchronous work invoked exactly once with no retry or fallback.
    /// - Returns: The operation's unchanged result.
    /// - Throws: The original operation error, with no error text logged.
    public static func withOperation<Value>(
        _ subsystem: String, event: String,
        isolation: isolated (any Actor)? = #isolation,
        operation: () async throws -> Value
    ) async rethrows -> Value {
        let metadata = operationContext()
        return try await $context.withValue(metadata) {
            let scope = OperationScope(logger: makeLogger(subsystem), event: event)
            do {
                let value = try await operation()
                scope.complete()
                return value
            } catch {
                scope.fail(error)
                throw error
            }
        }
    }

    /// Derives a finite ephemeral correlation scope while preserving application context.
    /// - Returns: Parent metadata plus a trace, a fresh span and an optional parent span.
    ///   UUIDs identify diagnostic work only and are never persistent Discord identifiers.
    private static func operationContext() -> Logger.Metadata {
        var metadata = context
        metadata["dk.trace_id"] = context["dk.trace_id"] ?? .string(UUID().uuidString)
        metadata["dk.parent_span_id"] = context["dk.span_id"]
        metadata["dk.span_id"] = .string(UUID().uuidString)
        return metadata
    }
}

/// Stack-owned operation timing; holds no global or growing diagnostic registry.
private struct OperationScope {
    let logger: Logger
    let event: String
    let start: ContinuousClock.Instant

    /// Captures the monotonic start and emits the scope's first trace event.
    /// - Parameters:
    ///   - logger: Value-semantic logger containing this scope's correlation metadata.
    ///   - event: Fixed operation prefix, supplied by the explicit operation owner.
    init(logger: Logger, event: String) {
        self.logger = logger
        self.event = event
        self.start = ContinuousClock.now
        logger.trace("Operation started", metadata: ["dk.event": .string(event + ".started")])
    }

    /// Emits successful completion without interpreting the operation's returned value.
    /// False or partial results remain the operation owner's responsibility to describe.
    func complete() {
        logger.trace("Operation completed", metadata: [
            "dk.event": .string(event + ".completed"), "dk.outcome": "success",
            "dk.duration_ns": .string(elapsedNanoseconds()),
        ])
    }

    /// Emits a sanitized terminal category and preserves ordinary cancellation severity.
    /// - Parameter error: Original thrown error, inspected only for `CancellationError`.
    ///   Other failures use debug, since the caller determines whether they are terminal.
    func fail(_ error: any Error) {
        let cancelled = error is CancellationError
        logger.log(level: cancelled ? .trace : .debug, "Operation ended", metadata: [
            "dk.event": .string(event + (cancelled ? ".cancelled" : ".failed")),
            "dk.outcome": .string(cancelled ? "cancelled" : "failure"),
            "dk.duration_ns": .string(elapsedNanoseconds()),
        ])
    }

    /// Renders a nonnegative monotonic duration without wall-clock changes or integer overflow.
    /// - Returns: Decimal nanoseconds. Swift's duration components retain full seconds and
    ///   fractional attoseconds; string composition avoids multiplying large second values.
    private func elapsedNanoseconds() -> String {
        let parts = start.duration(to: .now).components
        let fraction = max(0, parts.attoseconds / 1_000_000_000)
        if parts.seconds == 0 { return String(fraction) }
        let digits = String(fraction)
        return String(max(0, parts.seconds)) + String(repeating: "0", count: max(0, 9 - digits.count)) + digits
    }
}
