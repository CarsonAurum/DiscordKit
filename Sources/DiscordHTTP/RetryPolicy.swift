// File: Sources/DiscordHTTP/RetryPolicy.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import Foundation

/// Finite retry policy. Endpoint semantics, rather than method names, determine replay safety.
public struct RetryPolicy: Sendable {
    public let maximumAttempts: Int
    public let initialBackoff: Duration
    public let maximumBackoff: Duration

    /// Configures a finite exponential delay and total attempt budget.
    /// - Parameters:
    ///   - maximumAttempts: Positive total exchanges including the first, default three.
    ///   - initialBackoff: Nonnegative first retry delay, default 250 milliseconds.
    ///   - maximumBackoff: Nonnegative exponential cap, default five seconds.
    /// - Precondition: Attempts are in `1...16`; delays are nonnegative and ordered.
    public init(maximumAttempts: Int = 3, initialBackoff: Duration = .milliseconds(250), maximumBackoff: Duration = .seconds(5)) {
        precondition((1...16).contains(maximumAttempts) && initialBackoff >= .zero && maximumBackoff >= initialBackoff)
        self.maximumAttempts = maximumAttempts
        self.initialBackoff = initialBackoff
        self.maximumBackoff = maximumBackoff
    }

    /// Computes a capped retry delay without inspecting untrusted server error text.
    /// - Parameter completedAttempts: Number of completed exchanges, starting at one.
    /// - Returns: Delay before another attempt, or nil when the budget is exhausted.
    public func delay(after completedAttempts: Int) -> Duration? {
        guard completedAttempts > 0, completedAttempts < maximumAttempts else { return nil }
        var delay = initialBackoff
        for _ in 1..<completedAttempts {
            if delay >= maximumBackoff / 2 { return maximumBackoff }
            delay *= 2
        }
        return min(delay, maximumBackoff)
    }
}
