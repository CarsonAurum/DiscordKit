// File: Sources/DiscordLogging/DiscordLogConfiguration.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import Logging

/// Immutable, value-semantic severity thresholds for logical modules and components.
///
/// Matching uses complete dotted components: `http` matches `http.execution`, but
/// does not match `http2`. The longest matching component wins. This policy starts
/// no work and owns no handler, output, global configuration or mutable registry.
public struct DiscordLogConfiguration: Sendable {
    /// Threshold used when no component override matches.
    public let defaultLevel: Logger.Level
    /// Application-owned fixed component prefixes and their minimum severities.
    public let overrides: [String: Logger.Level]

    /// Creates a threshold policy without changing any existing logger.
    /// - Parameters:
    ///   - defaultLevel: Fallback minimum severity; defaults to `.info`.
    ///   - overrides: Exact dotted component prefixes, without `discordkit.`. Empty keys
    ///     never match. Use stable categories rather than identifiers or user input.
    public init(defaultLevel: Logger.Level = .info, overrides: [String: Logger.Level] = [:]) {
        self.defaultLevel = defaultLevel
        self.overrides = overrides
    }

    /// Resolves the most specific threshold using dotted component boundaries.
    /// - Parameter component: Category passed to `DiscordLog.makeLogger`, without its label prefix.
    /// - Returns: The longest matching override, or `defaultLevel`. Lookup is bounded by
    ///   the application's override count and allocates no retained diagnostic state.
    public func level(for component: String) -> Logger.Level {
        var result = defaultLevel
        var matchedLength = 0
        for (prefix, level) in overrides where !prefix.isEmpty {
            if (component == prefix || component.hasPrefix(prefix + ".")), prefix.count > matchedLength {
                result = level
                matchedLength = prefix.count
            }
        }
        return result
    }
}
