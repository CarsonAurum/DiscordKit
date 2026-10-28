// File: Sources/DiscordHTTP/MessageUpload.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import DiscordTransport
import Foundation

/// Independent per-file and complete-message byte limits; the latter includes all multipart framing.
public struct MessageUploadLimits: Sendable, Hashable {
    public static let `default` = Self()
    public let maximumFileBytes: Int
    public let maximumRequestBytes: Int
    public let maximumChunkBytes: Int

    /// Configures explicit upload bounds without opening files or consulting account/server state.
    /// - Parameters:
    ///   - maximumFileBytes: Positive per-file cap, default 20 MiB from Discord's current default.
    ///     Explicitly select a larger verified server/account allowance when appropriate.
    ///   - maximumRequestBytes: Positive complete request cap, at most Discord's 25 MiB message limit.
    ///   - maximumChunkBytes: Positive maximum yielded content/framing chunk size, default 64 KiB.
    /// Invalid values are retained and safely rejected by `MessageUpload.body` before resource creation.
    public init(maximumFileBytes: Int = 20 * 1_048_576, maximumRequestBytes: Int = 25 * 1_048_576,
                maximumChunkBytes: Int = 65_536) {
        self.maximumFileBytes = maximumFileBytes; self.maximumRequestBytes = maximumRequestBytes
        self.maximumChunkBytes = maximumChunkBytes
    }
}

/// One replayable upload, retaining either materialized bytes or a lazy fresh-stream factory.
///
/// Factories must return semantically identical content for each attempt. Replayability does not
/// make message creation safe to retry after an ambiguous send. Diagnostics conceal all metadata.
public struct MessageUploadFile: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let id: Int
    public let filename: String
    public let contentType: String
    public let maximumBytes: Int
    private let factory: @Sendable () throws -> BodyStream

    /// Retains complete file bytes without accessing the filesystem.
    /// - Parameters:
    ///   - id: Nonnegative `files[n]` placeholder, unique within the request.
    ///   - filename: Nonempty header-safe filename; controls, quotes and backslashes are rejected.
    ///   - contentType: Nonempty control-free media type, default `application/octet-stream`.
    ///   - bytes: Complete file contents; their exact count is the scheduling reservation, including zero.
    /// - Throws: Safe validation errors for unsafe metadata or a negative placeholder.
    public init(id: Int, filename: String, contentType: String = "application/octet-stream", bytes: Data) throws {
        try Self.validate(id: id, filename: filename, contentType: contentType)
        self.id = id; self.filename = filename; self.contentType = contentType; maximumBytes = bytes.count
        factory = {
            let source = MessageUploadStoredSource(bytes: bytes)
            return try BodyStream(maximumChunkBytes: max(1, bytes.count), next: { await source.next() }, close: { await source.close() })
        }
    }

    /// Stores a nonblocking factory which opens a fresh source only when its part is pulled.
    /// - Parameters:
    ///   - id: Unique nonnegative multipart placeholder.
    ///   - filename: Nonempty filename without header injection characters.
    ///   - contentType: Nonempty control-free media type.
    ///   - maximumBytes: Positive hard file cap and conservative reservation, including unknown-length sources.
    ///   - factory: Fresh single-consumer stream creator; ownership transfers to the upload attempt.
    ///     Source reads must honor cancellation and close must unblock an in-flight read. No prefetch occurs.
    /// - Throws: Safe validation errors for unsafe metadata, nonpositive limits or negative IDs.
    public init(id: Int, filename: String, contentType: String = "application/octet-stream", maximumBytes: Int,
                factory: @escaping @Sendable () throws -> BodyStream) throws {
        try Self.validate(id: id, filename: filename, contentType: contentType)
        guard maximumBytes > 0 else { throw DiscordError.validation(.invalidValue) }
        self.id = id; self.filename = filename; self.contentType = contentType
        self.maximumBytes = maximumBytes; self.factory = factory
    }

    /// Creates one fresh attempt's source without consuming it.
    /// - Returns: Independently owned single-consumer stream.
    /// - Throws: Errors from the caller's source factory; no other files are opened eagerly.
    fileprivate func makeStream() throws -> BodyStream { try factory() }

    /// Rejects multipart header injection before any producer is retained.
    /// - Parameters:
    ///   - id: Expected nonnegative multipart placeholder.
    ///   - filename: Expected nonempty header-safe filename.
    ///   - contentType: Expected nonempty control-free media type.
    /// - Throws: A safe invalid-value error for unsupported metadata.
    private static func validate(id: Int, filename: String, contentType: String) throws {
        guard id >= 0, !filename.isEmpty else { throw DiscordError.validation(.invalidValue) }
        _ = try MultipartPart(name: "files[\(id)]", filename: filename, contentType: contentType, bytes: Data())
    }

    /// Conceals filenames, source captures and contents during ordinary formatting.
    public var description: String { "MessageUploadFile(redacted)" }
    /// Uses the same redaction for debug formatting.
    public var debugDescription: String { description }
    /// Prevents reflection from exposing producer closures and retained bytes.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}

/// Message-specific JSON/multipart construction with independent file and complete-body admission bounds.
public enum MessageUpload {
    /// Constructs a bounded body while deferring upload-source ownership to each transmitted attempt.
    /// - Parameters:
    ///   - payload: Non-file request JSON object; endpoint request models perform semantic validation.
    ///   - files: At most ten unique file placeholders; empty selects a materialized JSON request.
    ///   - limits: Positive file/request/chunk caps; complete requests may never exceed 25 MiB.
    ///   - boundary: ASCII multipart boundary, 1...70 letters/digits/dashes/underscores; defaults to a
    ///     fresh UUID selected once at body construction and retained unchanged across replay attempts.
    ///     Sources containing this byte sequence are rejected, including matches split across chunks.
    /// - Returns: Replayable body reserving all framing/JSON bytes plus every file's declared cap. Streaming
    ///   bodies produce at most the selected chunk size and open only the current file on demand.
    /// - Throws: Safe validation errors for invalid limits, oversized reservations, metadata/boundary collisions,
    ///   duplicate IDs or a nonobject payload. Runtime source errors/cancellation/actual-byte overruns propagate
    ///   during iteration and close the active source exactly once; unopened sources remain unopened.
    public static func body(payload: JSONValue, files: [MessageUploadFile] = [], limits: MessageUploadLimits = .default,
                            boundary: String = "DiscordKit-" + UUID().uuidString) throws -> RequestBody {
        guard case .object = payload, limits.maximumFileBytes > 0, limits.maximumRequestBytes > 0,
              limits.maximumRequestBytes <= 25 * 1_048_576, limits.maximumChunkBytes > 0,
              files.count <= 10, Set(files.map(\.id)).count == files.count
        else { throw DiscordError.validation(.invalidValue) }
        let bytes = try payload.serialized(limits: JSONLimits(maximumBytes: limits.maximumRequestBytes))
        guard !files.isEmpty else {
            return try RequestBody(bytes: bytes, contentType: "application/json", maximumBytes: limits.maximumRequestBytes)
        }
        guard (1...70).contains(boundary.utf8.count), boundary.utf8.allSatisfy({
            (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95
        }), bytes.range(of: Data(boundary.utf8)) == nil else { throw DiscordError.validation(.invalidValue) }
        var initial = Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"payload_json\"\r\nContent-Type: application/json\r\n\r\n".utf8)
        initial.append(bytes); initial.append(contentsOf: "\r\n".utf8)
        let headers = files.map { Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"files[\($0.id)]\"; filename=\"\($0.filename)\"\r\nContent-Type: \($0.contentType)\r\n\r\n".utf8) }
        let closing = Data("--\(boundary)--\r\n".utf8)
        var reservation = initial.count
        for (file, header) in zip(files, headers) {
            guard file.maximumBytes <= limits.maximumFileBytes else { throw DiscordError.validation(.limitExceeded) }
            for size in [header.count, file.maximumBytes, 2] {
                guard size <= limits.maximumRequestBytes - reservation else { throw DiscordError.validation(.limitExceeded) }
                reservation += size
            }
        }
        guard closing.count <= limits.maximumRequestBytes - reservation else { throw DiscordError.validation(.limitExceeded) }
        reservation += closing.count
        let initialBytes = initial
        return try RequestBody.stream(contentType: "multipart/form-data; boundary=\(boundary)", maximumBytes: reservation) {
            let source = MessageMultipartSource(initial: initialBytes, files: files, headers: headers, closing: closing,
                                                boundary: Data(boundary.utf8), chunkLimit: limits.maximumChunkBytes)
            return try BodyStream(maximumChunkBytes: limits.maximumChunkBytes,
                                  next: { try await source.next() }, close: { await source.close() })
        }
    }
}

/// Per-attempt state for a retained data file; reads are sliced by the multipart owner.
private actor MessageUploadStoredSource {
    var bytes: Data?
    /// Stores immutable file bytes for one attempt.
    /// - Parameter bytes: Complete file contents, including an empty file.
    init(bytes: Data) { self.bytes = bytes }
    /// Yields the complete retained file once; no background task or queue is created.
    /// - Returns: File contents once, then EOF.
    func next() -> Data? { defer { bytes = nil }; return bytes }
    /// Releases any unconsumed retained data; repeated calls are harmless.
    func close() { bytes = nil }
}

/// Serial multipart producer owning only its current file stream and a bounded framing cursor.
private actor MessageMultipartSource {
    let initial: Data
    let files: [MessageUploadFile]
    let headers: [Data]
    let closing: Data
    let boundary: Data
    let chunkLimit: Int
    var stage = 0
    var fileIndex = 0
    var pending: Data?
    var pendingOffset = 0
    var active: BodyStream?
    var iterator: BodyStream.AsyncIterator?
    var remaining = 0
    var suffix = Data()
    var closed = false

    /// Retains immutable framing and replay factories without opening any file sources.
    /// - Parameters:
    ///   - initial: Complete payload_json framing and bytes.
    ///   - files: Ordered files with already admitted hard caps.
    ///   - headers: One validated header per file.
    ///   - closing: Complete terminal boundary.
    ///   - boundary: Forbidden sequence within binary contents.
    ///   - chunkLimit: Positive yielded-chunk limit.
    init(initial: Data, files: [MessageUploadFile], headers: [Data], closing: Data, boundary: Data, chunkLimit: Int) {
        self.initial = initial; self.files = files; self.headers = headers; self.closing = closing
        self.boundary = boundary; self.chunkLimit = chunkLimit
    }

    /// Pulls one bounded framing/content slice without prefetching or opening later files.
    /// - Returns: Next chunk, including legitimate empty source chunks, or EOF.
    /// - Throws: Factory/source errors, cancellation, per-file cap overruns or multipart boundary collisions.
    ///   The enclosing BodyStream owns cleanup on every terminal path.
    func next() async throws -> Data? {
        try Task.checkCancellation()
        while !closed {
            if let pending {
                let count = min(chunkLimit, pending.count - pendingOffset)
                let value = pending.subdata(in: pendingOffset..<(pendingOffset + count))
                pendingOffset += count
                if pendingOffset == pending.count { self.pending = nil; pendingOffset = 0 }
                return value
            }
            switch stage {
            case 0: pending = initial; stage = 1
            case 1:
                if fileIndex == files.count { pending = closing; stage = 4 }
                else { pending = headers[fileIndex]; stage = 2 }
            case 2:
                if active == nil {
                    let stream = try files[fileIndex].makeStream()
                    active = stream; iterator = stream.makeAsyncIterator(); remaining = files[fileIndex].maximumBytes
                    suffix = Data()
                }
                guard var cursor = iterator else { throw DiscordError.transport(.invalidResponse) }
                iterator = nil
                let chunk = try await cursor.next()
                guard !closed else { return nil }
                if let chunk {
                    guard chunk.count <= remaining else { throw DiscordError.transport(.limitExceeded) }
                    remaining -= chunk.count
                    var probe = suffix; probe.append(chunk)
                    guard probe.range(of: boundary) == nil else { throw DiscordError.validation(.invalidValue) }
                    suffix = Data(probe.suffix(max(0, boundary.count - 1)))
                    iterator = cursor; pending = chunk
                } else {
                    active = nil; iterator = nil; suffix = Data(); pending = Data("\r\n".utf8); stage = 3
                }
            case 3: fileIndex += 1; stage = 1
            default: return nil
            }
        }
        return nil
    }

    /// Closes only the currently owned source, discarding all pending framing and future files.
    /// Concurrent close during a suspended file read reaches that source and discards late bytes.
    func close() async {
        closed = true; pending = nil; iterator = nil
        let stream = active; active = nil
        await stream?.close()
    }
}
