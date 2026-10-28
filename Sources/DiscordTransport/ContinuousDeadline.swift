// File: Sources/DiscordTransport/ContinuousDeadline.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

/// Sleeps in the supplied clock domain while bounding cancelled continuous-timer
/// retention on runtimes that keep cancelled sleep records until their scheduled time.
///
/// ContinuousClock waits use checkpoints no farther than 100 milliseconds ahead.
/// This preserves time across system suspension and the precise requested deadline;
/// cancellation may leave a native timer record only until that short checkpoint,
/// rather than retaining operation history for an arbitrarily distant deadline.
/// Active long waits incur at most ten checkpoint wakeups per second. The runtime
/// still owns those short-lived timer records; this is a retention-time bound, not
/// a claim that Foundation or the allocator immediately returns pages to the OS.
/// Injected/custom clocks retain their original sleep and cancellation behavior.
/// - Parameters:
///   - clock: Operation's monotonic clock, never converted through wall/uptime clocks.
///   - deadline: Inclusive deadline in exactly the supplied clock's instant domain.
/// - Throws: Cancellation or an injected clock's original sleep error.
func sleepForTransportDeadline<C: Clock>(clock: C, until deadline: C.Instant) async throws
where C.Duration == Duration {
    if clock is ContinuousClock, let continuousDeadline = deadline as? ContinuousClock.Instant {
        let continuous = ContinuousClock()
        while continuous.now < continuousDeadline {
            try Task.checkCancellation()
            let checkpoint = min(continuousDeadline, continuous.now.advanced(by: .milliseconds(100)))
            try await continuous.sleep(until: checkpoint, tolerance: nil)
        }
        try Task.checkCancellation()
        return
    }
    try await clock.sleep(until: deadline, tolerance: nil)
}
