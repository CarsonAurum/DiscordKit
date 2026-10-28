// File: Sources/DiscordTransport/RuntimeCleanupFailure.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

/// Package-only opt-in provenance for supervised cleanup errors; ordinary lower-level public errors stay unchanged.
/// The task-local value is inherited only by owned structured children and creates no tasks or retained queue.
package enum RuntimeCleanupFailureScope {
    @TaskLocal package static var capturesFailures = false
}

/// Preserves original closed cleanup errors until the host unwraps them after joined shutdown.
/// Never supplied to observers; ordinary formatting and reflection conceal the underlying error.
package struct RuntimeCleanupFailure: Error, Sendable, CustomStringConvertible, CustomReflectable {
    package let original: any Error

    /// Captures one already sanitized failure at the actual cleanup operation boundary.
    /// - Parameter original: Closed cleanup error preserved for the owning public caller.
    package init(original: any Error) { self.original = original }

    /// Conceals the original error from dependency diagnostic formatting.
    package var description: String { "RuntimeCleanupFailure(redacted)" }
    /// Prevents ordinary reflection from traversing the original error.
    package var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}
