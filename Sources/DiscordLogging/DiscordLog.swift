// File: Sources/DiscordLogging/DiscordLog.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

@_exported import Logging

/// Native SwiftLog entry points shared by independently adopted DiscordKit products.
///
/// The application owns `LoggingSystem.bootstrap`, handlers, thresholds and retention.
/// This module starts no tasks, opens no outputs and never bootstraps the process.
/// Trace records individual steps, debug records diagnostic summaries, info records
/// significant lifecycle outcomes and notice records recovery or operational milestones.
/// Warning, error and critical distinguish degradation, terminal failure and lost safety.
public enum DiscordLog {
    /// Application-supplied factory inherited by structured child tasks.
    ///
    /// The default honors SwiftLog's process configuration. Override this task-local
    /// value around an explicit operation or supervised `run` to select a logger
    /// without mutating process state. Detached tasks do not inherit task-local values.
    /// Factories must be concurrency-safe, cheap, and must not log recursively.
    /// No logger is cached during inert subsystem construction.
    @TaskLocal public static var loggerFactory: @Sendable (String) -> Logger = { Logger(label: $0) }

    /// Scoped application context inherited by child operations and structured tasks.
    ///
    /// Values are copied into newly created loggers; existing logger values are unchanged.
    /// Applications must exclude secrets and bound their own metadata. Operation scopes
    /// add ephemeral correlation fields, never Discord user, guild or session identifiers.
    @TaskLocal public static var context: Logger.Metadata = [:]

    /// Optional component threshold policy for this task and its structured children.
    ///
    /// `nil` preserves thresholds returned by the application factory. An explicit policy
    /// replaces the native logger threshold, which also updates multiplex children.
    /// Use a fixed output-level filter to preserve a destination floor. No global state changes.
    @TaskLocal public static var configuration: DiscordLogConfiguration?

    /// Creates a native logger for an operation using the current application factory.
    ///
    /// Metadata and threshold retain SwiftLog value semantics. This method adds only
    /// stable subsystem/component fields and scoped context. A task-local configuration
    /// optionally overrides the factory threshold; otherwise that threshold is preserved.
    /// - Parameter subsystem: Stable dotted component name, such as `http.execution`.
    ///   Library call sites use fixed names rather than user data or credentials.
    /// - Returns: A logger labeled `discordkit.<subsystem>`, with `dk.subsystem` metadata.
    public static func makeLogger(_ subsystem: String) -> Logger {
        var logger = loggerFactory("discordkit.\(subsystem)")
        for (key, value) in context { logger[metadataKey: key] = value }
        logger[metadataKey: "dk.subsystem"] = .string(subsystem)
        logger[metadataKey: "dk.module"] = .string(String(subsystem.prefix { $0 != "." }))
        if let configuration { logger.logLevel = configuration.level(for: subsystem) }
        return logger
    }
}
