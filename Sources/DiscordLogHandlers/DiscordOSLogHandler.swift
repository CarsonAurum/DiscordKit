// File: Sources/DiscordLogHandlers/DiscordOSLogHandler.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

#if canImport(OSLog)
import Foundation
import Logging
import OSLog
import os

/// SwiftLog output for Apple's unified logging system on macOS, iOS and other Apple platforms.
///
/// All seven SwiftLog levels remain visible in the severity field. Unified logging
/// maps trace/debug to debug, info to info, notice/warning to default, error to error,
/// and critical to fault. The entire dynamic payload uses explicit private privacy;
/// only the fixed severity spelling is public. Error objects/descriptions are omitted.
/// Construction selects an OSLog category but starts no tasks or global bootstrap.
public struct DiscordOSLogHandler: LogHandler {
    /// Handler-local metadata with independent value semantics.
    public var metadata: Logging.Logger.Metadata = [:]
    /// Optional synchronous context provider.
    public var metadataProvider: Logging.Logger.MetadataProvider?
    /// Minimum accepted SwiftLog severity; defaults to `.info`.
    public var logLevel: Logging.Logger.Level
    private let label: String
    private let output: os.Logger

    /// Selects an explicitly owned unified-logging subsystem/category without emitting a record.
    /// - Parameters:
    ///   - label: Stable logger label and default OSLog category.
    ///   - subsystem: Unified-logging subsystem; defaults to `DiscordKit`.
    ///   - category: Explicit category override; `nil` uses `label`.
    ///   - logLevel: Minimum SwiftLog severity; defaults to `.info`.
    ///   - metadataProvider: Optional dynamic metadata context, evaluated for accepted records only.
    public init(
        label: String, subsystem: String = "DiscordKit", category: String? = nil,
        logLevel: Logging.Logger.Level = .info,
        metadataProvider: Logging.Logger.MetadataProvider? = nil
    ) {
        self.label = label
        self.logLevel = logLevel
        self.metadataProvider = metadataProvider
        self.output = os.Logger(subsystem: subsystem, category: category ?? label)
    }

    /// Reads or changes only this handler copy's base metadata.
    /// - Parameter metadataKey: Exact metadata key; assigning `nil` removes it.
    /// - Returns: Stored metadata, excluding provider/call values.
    public subscript(metadataKey metadataKey: String) -> Logging.Logger.Metadata.Value? {
        /// Returns this copy's stored metadata without consulting dynamic providers.
        get { metadata[metadataKey] }
        /// Changes this copy only; assigning nil removes the stored key.
        set { metadata[metadataKey] = newValue }
    }

    /// Maps every SwiftLog level to its documented unified-logging severity.
    /// - Parameter level: Original SwiftLog level; it remains separately included in emitted records.
    /// - Returns: The corresponding Apple unified-logging severity.
    public static func unifiedLevel(for level: Logging.Logger.Level) -> OSLogType {
        switch level {
        case .trace, .debug: .debug
        case .info: .info
        case .notice, .warning: .default
        case .error: .error
        case .critical: .fault
        }
    }

    /// Emits the dynamic message, label, context and location with explicit private privacy.
    /// - Parameter event: SwiftLog event. Direct calls are filtered before provider/rendering work.
    ///   Error payloads are omitted; their presence is included in the private observation.
    public func log(event: LogEvent) {
        guard event.level >= logLevel else { return }
        let record = DiscordLogRecord.capture(
            label: label, event: event, base: metadata, provider: metadataProvider, timestamp: Date()
        )
        let payload = "[\(record.label)] \(record.message) \(record.metadata) source=\(record.source) file=\(record.file) function=\(record.function) line=\(record.line) hasError=\(record.hasError)"
        output.log(level: Self.unifiedLevel(for: record.level), "[\(record.level.rawValue, privacy: .public)] \(payload, privacy: .private)")
    }
}
#endif
