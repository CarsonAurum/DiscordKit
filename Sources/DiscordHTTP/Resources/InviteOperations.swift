// File: Sources/DiscordHTTP/Resources/InviteOperations.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import DiscordModels
import DiscordTransport

/// Explicit bounded Invite workflows using the caller's shared HTTP authority and clock.
/// Construction performs no work, pulls never overlap, and abandoning iteration starts no further polls.
public enum InviteOperations {
    /// Observes asynchronous invite CSV processing with finite, lazy, paced status reads.
    /// - Parameters:
    ///   - code: Exact invitation code; inviter, MANAGE_GUILD or VIEW_AUDIT_LOG authority applies per read.
    ///   - maximumPolls: Finite request budget in 1...10,000, default 100. Exhaustion throws limitExceeded
    ///     on the next pull; the final pending snapshot is still yielded for explicit reconciliation.
    ///   - interval: Positive delay between pulls after a pending snapshot, at most one day; default one second.
    ///     There is no initial sleep, no sleep after completion/failure, and no speculative background timer.
    ///   - context: Injected clock/cancellation domain with optional overall inclusive monotonic deadline.
    ///   - execute: Sequential cooperative executor sharing ordinary credential/rate limits; read reuse is disabled.
    /// - Returns: Lazy one-element status pages. Completed and failed statuses yield once then terminate;
    ///   failed jobs remain inspectable results, not successful processing. Unspecified/future statuses remain
    ///   pending rather than guessing completion. Each new iterator starts an independent observation budget.
    /// - Throws: Invalid configuration/code before I/O; original execution errors, cooperative cancellation,
    ///   deadline expiry or finite-budget errors during iteration. Any thrown error permanently ends that iterator.
    /// No upload is started, no mutation is retried, no rows are fetched, and no progress monotonicity is invented.
    public static func targetUsersJobStatuses<C: Clock>(
        code: String, maximumPolls: Int = 100, interval: Duration = .seconds(1), context: TransportContext<C>,
        execute: @escaping @Sendable (Endpoint<InviteTargetUsersJob>) async throws -> InviteTargetUsersJob
    ) throws -> CursorPagination<InviteTargetUsersJob, Int, C> where C.Duration == Duration {
        guard (1...10_000).contains(maximumPolls), interval > .zero, interval <= .seconds(86_400)
        else { throw DiscordError.validation(.invalidValue) }
        let endpoint = try InviteEndpoints.targetUsersJob(code: code)
        return try CursorPagination(maximumPages: maximumPolls, context: context) { cursor in
            if cursor != nil {
                try await context.clock.sleep(until: context.clock.now.advanced(by: interval), tolerance: nil)
                try context.check()
            }
            let status = try await execute(endpoint)
            let terminal = status.status.knownValue == .completed || status.status.knownValue == .failed
            return CursorPage(items: [status], nextCursor: terminal ? nil : (cursor ?? 0) + 1)
        }
    }
}
