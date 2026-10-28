// File: Sources/DiscordLogHandlers/DiscordFileLogHandler.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import Foundation
import Logging

/// Finite storage and serialization limits for an explicitly opened NDJSON output.
public struct DiscordFileLogConfiguration: Sendable, Equatable {
    /// Maximum bytes in each active or retained file, including newline delimiters.
    public let maximumFileBytes: Int
    /// Total owned file slots, including the active file; valid values are `1...1_000`.
    /// Archives outside these configured slots are untouched, including archives from a larger previous configuration.
    public let maximumFiles: Int
    /// Maximum UTF-8 bytes in one encoded record, including its newline.
    public let maximumRecordBytes: Int
    /// Maximum nested metadata containers, including the root dictionary; valid values are `1...64`.
    public let maximumMetadataDepth: Int
    /// Maximum total metadata values, including containers; valid values are `1...100_000`.
    public let maximumMetadataValues: Int

    /// Retains limits for validation when a sink is explicitly opened.
    /// - Parameters:
    ///   - maximumFileBytes: Positive per-file byte limit; defaults to 5 MiB.
    ///   - maximumFiles: Active plus archive count; defaults to three.
    ///   - maximumRecordBytes: Positive record byte limit no larger than the file limit; defaults to 64 KiB.
    ///   - maximumMetadataDepth: Metadata container depth in `1...64`; defaults to 16.
    ///   - maximumMetadataValues: Metadata node count in `1...100_000`; defaults to 1,024.
    public init(
        maximumFileBytes: Int = 5 * 1_024 * 1_024, maximumFiles: Int = 3,
        maximumRecordBytes: Int = 64 * 1_024, maximumMetadataDepth: Int = 16,
        maximumMetadataValues: Int = 1_024
    ) {
        self.maximumFileBytes = maximumFileBytes
        self.maximumFiles = maximumFiles
        self.maximumRecordBytes = maximumRecordBytes
        self.maximumMetadataDepth = maximumMetadataDepth
        self.maximumMetadataValues = maximumMetadataValues
    }

    /// Rejects invalid ranges without opening or modifying any files.
    /// - Throws: `DiscordFileLogError.invalidConfiguration` for invalid finite limits.
    func validate() throws {
        guard maximumFileBytes > 0, (1...1_000).contains(maximumFiles),
              maximumRecordBytes > 0, maximumRecordBytes <= maximumFileBytes,
              (1...64).contains(maximumMetadataDepth),
              (1...100_000).contains(maximumMetadataValues) else {
            throw DiscordFileLogError.invalidConfiguration
        }
    }
}

/// Sanitized file-output failures; cases never contain paths, message content or underlying error descriptions.
public enum DiscordFileLogError: Error, Sendable, Equatable {
    /// At least one configured storage or metadata limit is invalid.
    case invalidConfiguration
    /// The destination is not a local file URL.
    case notFileURL
    /// An owned destination already exists as something other than a regular file.
    case notRegularFile
    /// An existing active or archive file exceeds the configured byte bound.
    case existingFileExceedsLimit
    /// Creating, inspecting or opening an owned file failed.
    case openFailed
    /// The entire encoded record, including newline, would exceed its byte bound.
    case recordTooLarge
    /// Metadata exceeds the configured nesting or node bound.
    case metadataLimitExceeded
    /// A record has a nonfinite timestamp that JSON cannot represent.
    case invalidRecord
    /// Writing failed; the sink becomes terminal to avoid appending after a partial record.
    case writeFailed
    /// Retention or reopening failed; the sink becomes terminal.
    case rotationFailed
    /// A record was submitted after explicit close or a terminal I/O failure.
    case closed
    /// Synchronizing or closing failed; the sink is still terminal.
    case closeFailed
}

/// A synchronized, constant-size diagnostic snapshot; counters saturate at `UInt64.max`.
public struct DiscordFileLogSnapshot: Sendable, Equatable {
    /// Records successfully written since this sink opened.
    public let writtenRecords: UInt64
    /// Records rejected by bounds, closed state or an I/O failure.
    public let droppedRecords: UInt64
    /// Successfully completed active-file rotations.
    public let rotations: UInt64
    /// Observed rejections and I/O errors, including close failures.
    public let failures: UInt64
    /// Current active file's successfully accounted bytes, including pre-existing content.
    public let activeBytes: Int
    /// Whether the sink no longer accepts records.
    public let isClosed: Bool
}

/// An explicitly owned, bounded, synchronous rotating NDJSON writer.
///
/// All handle, retention and counter state is guarded by one lock. Handler copies
/// share this writer, while their levels and metadata retain value semantics.
/// No queue, task, timer or implicit bootstrap is created. File I/O blocks the
/// calling thread; do not install this output on realtime audio callbacks.
///
/// The application must own the destination and its numbered archive names
/// exclusively. Do not open independent sinks or allow other processes to write
/// those files. The parent directory must already exist. New files request mode
/// 0600 on POSIX hosts; other hosts apply Foundation/platform file permissions.
/// Existing regular files retain their permissions. Symbolic links are rejected
/// during inspection; callers must also protect the directory against replacement.
/// Existing content is appended without parsing or repairing interrupted records.
/// Successful writes describe accepted filesystem writes, not crash durability;
/// an I/O failure can leave a partial final line and makes this sink terminal.
public final class DiscordFileLogSink: @unchecked Sendable {
    /// Immutable storage limits validated before file creation.
    public let configuration: DiscordFileLogConfiguration
    private let url: URL
    private let lock = NSLock()
    private var handle: FileHandle?
    private var bytes: Int = 0
    private var written: UInt64 = 0
    private var dropped: UInt64 = 0
    private var rotationCount: UInt64 = 0
    private var failureCount: UInt64 = 0
    private var deliveringDiagnostic = false
    private let onDiagnostic: (@Sendable (DiscordFileLogError) -> Void)?

    /// Opens an append-only active file after validating every configured archive slot.
    /// - Parameters:
    ///   - url: Local active-file URL in an existing application-owned directory.
    ///   - configuration: Finite storage/serialization bounds; defaults to three 5 MiB files.
    ///   - onDiagnostic: Optional synchronous error observer. Concurrent/recursive callbacks are
    ///     coalesced; snapshots retain every failure. The callback runs outside the writer lock.
    /// - Throws: A sanitized `DiscordFileLogError`; no logging bootstrap is performed.
    ///   Existing files exceeding the requested limit are rejected without truncation.
    public init(
        url: URL, configuration: DiscordFileLogConfiguration = .init(),
        onDiagnostic: (@Sendable (DiscordFileLogError) -> Void)? = nil
    ) throws {
        try configuration.validate()
        guard url.isFileURL else { throw DiscordFileLogError.notFileURL }
        self.url = url
        self.configuration = configuration
        self.onDiagnostic = onDiagnostic
        for index in 0..<configuration.maximumFiles {
            _ = try Self.existingSize(at: Self.archiveURL(base: url, index: index), configuration: configuration)
        }
        bytes = try Self.existingSize(at: url, configuration: configuration) ?? 0
        handle = try Self.open(at: url)
    }

    /// Closes the final handle as a fallback; applications should call `close()` to observe errors.
    deinit {
        try? handle?.close()
    }

    /// Returns a coherent counter/state observation without retaining any log content.
    /// - Returns: Current saturating counters and active-byte/terminal state.
    public func snapshot() -> DiscordFileLogSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return DiscordFileLogSnapshot(
            writtenRecords: written, droppedRecords: dropped, rotations: rotationCount,
            failures: failureCount, activeBytes: bytes, isClosed: handle == nil
        )
    }

    /// Serializes and writes one complete bounded record synchronously.
    /// - Parameter record: Caller-redacted observation. Metadata description code executes on the caller.
    ///
    /// Oversized/invalid records are dropped without writing a prefix or rotating.
    /// The serializer retains at most `maximumRecordBytes` of output. The writer
    /// serializes concurrent file operations. I/O failure closes admission; no
    /// retries or recursive logging are performed. Errors update counters and the
    /// optional diagnostic callback because SwiftLog's `log` method cannot throw.
    /// Serialization and diagnostic callbacks run outside the filesystem lock;
    /// an overlapping `close()` can finish before this call returns. A record
    /// serialized across close is dropped, and its diagnostic can follow close.
    public func write(_ record: DiscordLogRecord) {
        lock.lock()
        if handle == nil {
            Self.increment(&dropped)
            Self.increment(&failureCount)
            lock.unlock()
            notify(.closed)
            return
        }
        lock.unlock()
        let encoded: Data
        do {
            var encoder = DiscordLogJSONWriter(configuration: configuration)
            encoded = try encoder.encode(record)
        } catch {
            reject((error as? DiscordFileLogError) ?? .invalidRecord)
            return
        }
        var failure: DiscordFileLogError?
        lock.lock()
        if let current = handle {
            do {
                if encoded.count > configuration.maximumFileBytes - bytes {
                    do { try rotate(current) }
                    catch { throw DiscordFileLogError.rotationFailed }
                }
                guard let target = handle else { throw DiscordFileLogError.writeFailed }
                do { try target.write(contentsOf: encoded) }
                catch { throw DiscordFileLogError.writeFailed }
                bytes += encoded.count
                Self.increment(&written)
            } catch {
                failure = (error as? DiscordFileLogError) ?? .writeFailed
                try? handle?.close()
                handle = nil
                Self.increment(&dropped)
                Self.increment(&failureCount)
            }
        } else {
            failure = .closed
            Self.increment(&dropped)
            Self.increment(&failureCount)
        }
        lock.unlock()
        if let failure { notify(failure) }
    }

    /// Synchronizes and closes the shared handle; repeated calls are harmless.
    /// - Throws: `DiscordFileLogError.closeFailed` if synchronization or close fails.
    ///   Admission remains closed after failure; a diagnostic and failure counter are also recorded.
    ///
    /// Waits for filesystem mutations protected by the writer lock, then closes
    /// file admission. It does not join metadata description/serialization work
    /// or diagnostic callbacks outside that lock; those can finish, update drop
    /// counters and deliver diagnostics after this method returns. Applications
    /// must stop and join producers and in-flight log calls before closing when
    /// teardown requires all logging work and callbacks to have finished. Copied
    /// handlers share the closed state and drop later messages.
    public func close() throws {
        var failed = false
        lock.lock()
        if let current = handle {
            handle = nil
            do { try current.synchronize() } catch { failed = true }
            do { try current.close() } catch { failed = true }
            if failed { Self.increment(&failureCount) }
        }
        lock.unlock()
        if failed {
            notify(.closeFailed)
            throw DiscordFileLogError.closeFailed
        }
    }

    /// Counts a serialization rejection without holding a lock during application callbacks.
    /// - Parameter error: Sanitized rejection reason; the supplied record is never retained.
    private func reject(_ error: DiscordFileLogError) {
        lock.lock()
        Self.increment(&dropped)
        Self.increment(&failureCount)
        lock.unlock()
        notify(error)
    }

    /// Calls at most one diagnostic observer at once, suppressing recursive notification loops.
    /// - Parameter error: Sanitized failure; counters remain authoritative when a callback is coalesced.
    private func notify(_ error: DiscordFileLogError) {
        guard let onDiagnostic else { return }
        lock.lock()
        guard !deliveringDiagnostic else { lock.unlock(); return }
        deliveringDiagnostic = true
        lock.unlock()
        onDiagnostic(error)
        lock.lock()
        deliveringDiagnostic = false
        lock.unlock()
    }

    /// Rotates files while the caller holds the writer lock and opens a fresh active file.
    /// - Parameter current: Current active handle; it is closed before filesystem mutations.
    /// - Throws: FileHandle/FileManager failures, translated by the caller into `.rotationFailed`.
    private func rotate(_ current: FileHandle) throws {
        try current.close()
        handle = nil
        let manager = FileManager.default
        let oldest = Self.archiveURL(base: url, index: configuration.maximumFiles - 1)
        if manager.fileExists(atPath: oldest.path) { try manager.removeItem(at: oldest) }
        if configuration.maximumFiles > 1 {
            for index in stride(from: configuration.maximumFiles - 2, through: 0, by: -1) {
                let source = Self.archiveURL(base: url, index: index)
                if manager.fileExists(atPath: source.path) {
                    try manager.moveItem(at: source, to: Self.archiveURL(base: url, index: index + 1))
                }
            }
        }
        handle = try Self.open(at: url)
        bytes = 0
        Self.increment(&rotationCount)
    }

    /// Maps the active slot and numbered archive slots to deterministic sibling URLs.
    /// - Parameters:
    ///   - base: Active-file URL.
    ///   - index: Nonnegative slot; zero means the active file.
    /// - Returns: `base` or its `.N` sibling; no files are inspected or created.
    private static func archiveURL(base: URL, index: Int) -> URL {
        index == 0 ? base : URL(fileURLWithPath: base.path + ".\(index)")
    }

    /// Checks a slot before opening, preserving existing oversized or nonregular destinations.
    /// - Parameters:
    ///   - url: Owned slot to inspect.
    ///   - configuration: Validated per-file byte bound.
    /// - Returns: Existing regular-file byte count, or `nil` when the slot does not exist.
    /// - Throws: Sanitized inspection, file-type or existing-size errors.
    private static func existingSize(at url: URL, configuration: DiscordFileLogConfiguration) throws -> Int? {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular else {
                throw DiscordFileLogError.notRegularFile
            }
            guard let size = attributes[.size] as? NSNumber,
                  size.uint64Value <= UInt64(configuration.maximumFileBytes) else {
                throw DiscordFileLogError.existingFileExceedsLimit
            }
            return size.intValue
        } catch let error as DiscordFileLogError { throw error }
        catch let error as NSError where error.domain == NSCocoaErrorDomain && (error.code == NSFileNoSuchFileError || error.code == NSFileReadNoSuchFileError) {
            return nil
        } catch { throw DiscordFileLogError.openFailed }
    }

    /// Creates a private regular file when needed and positions its handle at the end.
    /// - Parameter url: Already-inspected destination in an existing owned directory.
    /// - Returns: Open write handle owned by the sink.
    /// - Throws: `DiscordFileLogError.openFailed`; partially opened handles are closed.
    private static func open(at url: URL) throws -> FileHandle {
        let manager = FileManager.default
        if !manager.fileExists(atPath: url.path) {
            guard manager.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
                throw DiscordFileLogError.openFailed
            }
        }
        do {
            let result = try FileHandle(forWritingTo: url)
            do { _ = try result.seekToEnd() }
            catch { try? result.close(); throw error }
            return result
        } catch { throw DiscordFileLogError.openFailed }
    }

    /// Saturates an individual diagnostic counter instead of overflowing a long-lived process.
    /// - Parameter value: Counter owned by the caller's critical section.
    private static func increment(_ value: inout UInt64) {
        if value < .max { value += 1 }
    }
}

/// A value-semantic SwiftLog handler sharing one explicitly opened rotating file sink.
public struct DiscordFileLogHandler: LogHandler {
    /// Handler-local metadata; copied loggers remain independent.
    public var metadata: Logger.Metadata = [:]
    /// Dynamic context evaluated for accepted calls only.
    public var metadataProvider: Logger.MetadataProvider?
    /// Minimum severity; defaults to `.info`.
    public var logLevel: Logger.Level
    private let label: String
    private let sink: DiscordFileLogSink
    private let now: @Sendable () -> Date

    /// Shares an existing sink without opening files, logging or bootstrapping SwiftLog.
    /// - Parameters:
    ///   - label: Stable logger/subsystem identifier.
    ///   - sink: Explicitly opened sink; closing it closes every sharing handler's admission.
    ///   - logLevel: Minimum severity; defaults to `.info`.
    ///   - metadataProvider: Optional synchronous context provider.
    ///   - now: Injected wall clock; defaults to the current time.
    public init(
        label: String, sink: DiscordFileLogSink, logLevel: Logger.Level = .info,
        metadataProvider: Logger.MetadataProvider? = nil,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.label = label
        self.sink = sink
        self.logLevel = logLevel
        self.metadataProvider = metadataProvider
        self.now = now
    }

    /// Reads or changes only this handler copy's stored metadata.
    /// - Parameter metadataKey: Exact key; assigning `nil` removes it.
    /// - Returns: Stored metadata, excluding dynamic and call values.
    public subscript(metadataKey metadataKey: String) -> Logger.Metadata.Value? {
        /// Returns this copy's stored metadata without consulting dynamic providers.
        get { metadata[metadataKey] }
        /// Changes this copy only; assigning nil removes the stored key.
        set { metadata[metadataKey] = newValue }
    }

    /// Captures and writes one accepted call synchronously, without retries or background work.
    /// - Parameter event: SwiftLog event; direct handler calls are also filtered.
    ///   Error payloads/descriptions are omitted; only their presence is recorded.
    public func log(event: LogEvent) {
        guard event.level >= logLevel else { return }
        sink.write(.capture(
            label: label, event: event, base: metadata, provider: metadataProvider, timestamp: now()
        ))
    }
}
