// File: Sources/DiscordLogHandlers/DiscordLevelFilterLogHandler.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import Logging

/// Preserves an output's minimum severity when a logger's component threshold changes.
///
/// SwiftLog's multiplex threshold setter updates every child. Wrap individual outputs
/// with this adapter to keep, for example, console at info while a file accepts trace.
/// Copies preserve native handler value semantics. The adapter owns no output lifetime,
/// queue, mutable global configuration or background task.
public struct DiscordLevelFilterLogHandler: LogHandler {
    /// Immutable output floor; a logger may raise its threshold but cannot lower this floor.
    public let minimumLevel: Logger.Level
    private var base: any LogHandler

    /// Wraps an existing handler and clamps its current threshold to the output floor.
    /// - Parameters:
    ///   - base: Application-owned output; no log call or metadata-provider evaluation occurs.
    ///   - minimumLevel: Lowest severity this output may emit, even when multiplexing.
    public init(_ base: any LogHandler, minimumLevel: Logger.Level) {
        self.base = base
        self.minimumLevel = minimumLevel
        self.base.logLevel = max(base.logLevel, minimumLevel)
    }

    /// Reads or changes the effective threshold, clamped to this output's fixed floor.
    public var logLevel: Logger.Level {
        /// Returns the native output threshold, which is never below the floor.
        get { max(minimumLevel, base.logLevel) }
        /// Changes this handler copy's threshold while preserving its immutable floor.
        set { base.logLevel = max(newValue, minimumLevel) }
    }

    /// Forwards native metadata with the wrapped handler's value semantics.
    public var metadata: Logger.Metadata {
        /// Returns metadata using the wrapped handler's native getter behavior.
        get { base.metadata }
        /// Replaces metadata on this handler copy only.
        set { base.metadata = newValue }
    }

    /// Forwards the dynamic provider without evaluating it in this adapter.
    public var metadataProvider: Logger.MetadataProvider? {
        /// Returns the wrapped provider; accepted events evaluate it downstream.
        get { base.metadataProvider }
        /// Changes the provider on this handler copy only.
        set { base.metadataProvider = newValue }
    }

    /// Reads or changes a stored metadata value on the wrapped handler copy.
    /// - Parameter key: Exact key; assigning nil removes the stored value.
    /// - Returns: Stored value, excluding dynamic provider and per-call metadata.
    public subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        /// Reads metadata using the wrapped handler's native subscript behavior.
        get { base[metadataKey: key] }
        /// Changes this copy's metadata using native wrapped-handler semantics.
        set { base[metadataKey: key] = newValue }
    }

    /// Forwards accepted events once and skips providers and output work for filtered events.
    /// - Parameter event: Already constructed native event; payload privacy stays with its caller.
    public func log(event: LogEvent) {
        guard event.level >= max(minimumLevel, base.logLevel) else { return }
        base.log(event: event)
    }
}
