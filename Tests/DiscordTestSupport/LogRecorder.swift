// File: Tests/DiscordTestSupport/LogRecorder.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import Foundation
import DiscordLogging

/// Bounded native SwiftLog capture for deterministic tests without global bootstrap.
public final class LogRecorder: @unchecked Sendable {
    /// An admitted event with rendered message and native SwiftLog metadata.
    public struct Entry: Sendable {
        public let label: String
        public let level: Logger.Level
        public let message: String
        public let metadata: Logger.Metadata
    }

    private let lock = NSLock()
    private var storage: [Entry] = []
    private let maximumEntries: Int

    /// Creates finite capture storage; all mutable storage is protected by `lock`.
    /// - Parameter maximumEntries: Nonnegative retained event bound; excess events drop.
    public init(maximumEntries: Int = 1_024) {
        precondition(maximumEntries >= 0)
        self.maximumEntries = maximumEntries
    }

    /// Returns a synchronized snapshot in emission order, up to the configured bound.
    public var entries: [Entry] { lock.withLock { storage } }

    /// Creates a native logger with trace enabled for task-local test injection.
    /// - Parameter label: Stable subsystem label supplied by the library.
    /// - Returns: A fresh value-semantic logger sharing this recorder's bounded storage.
    public func makeLogger(_ label: String) -> Logger {
        Logger(label: label, factory: { RecordHandler(label: $0, recorder: self) })
    }

    /// Appends one materialized entry under the lock without calling external code.
    /// - Parameter entry: Already materialized message and merged metadata.
    fileprivate func append(_ entry: Entry) {
        lock.withLock { if storage.count < maximumEntries { storage.append(entry) } }
    }
}

/// Value-semantic handler with shared synchronized output, matching SwiftLog's contract.
private struct RecordHandler: LogHandler {
    let label: String
    let recorder: LogRecorder
    var logLevel: Logger.Level = .trace
    var metadata: Logger.Metadata = [:]
    var metadataProvider: Logger.MetadataProvider?

    /// Reads or changes metadata on this handler copy only.
    /// - Parameter metadataKey: Metadata field name.
    /// - Returns: The stored value, or `nil` if absent.
    subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        /// Returns this copy's stored metadata without consulting dynamic providers.
        get { metadata[key] }
        /// Changes this copy only; assigning nil removes the stored key.
        set { metadata[key] = newValue }
    }

    /// Captures an admitted event with base, provider and call metadata precedence.
    /// - Parameter event: Native SwiftLog event; arbitrary attached errors are omitted.
    func log(event: LogEvent) {
        var merged = metadata
        merged.merge(metadataProvider?.get() ?? [:], uniquingKeysWith: { _, newer in newer })
        merged.merge(event.metadata ?? [:], uniquingKeysWith: { _, newer in newer })
        recorder.append(.init(label: label, level: event.level, message: event.message.description, metadata: merged))
    }
}
