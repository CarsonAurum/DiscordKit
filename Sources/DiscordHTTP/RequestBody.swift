import DiscordCore
import DiscordTransport
import Foundation

/// One ordered query or form field. Repeated names and absent values are preserved.
public struct QueryItem: Sendable, Hashable {
    public let name: String
    public let value: String?

    /// Stores an unescaped field; encoding occurs exactly once at the wire boundary.
    /// - Parameters:
    ///   - name: Field name, including any operation-specific bracket syntax.
    ///   - value: Field value, or `nil` to encode a bare name without `=`.
    public init(name: String, value: String?) { self.name = name; self.value = value }
}

/// A replayable body, materialized or produced by a fresh bounded stream factory.
/// Replayability does not establish mutation retry safety. Factory attempts never
/// share a consumed stream; callers must ensure generated contents are semantically identical.
public struct RequestBody: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// Complete materialized bytes, or empty data for streaming bodies; consult `storedBodyBytes` to distinguish them.
    public let bytes: Data
    public let contentType: String
    private var streamFactory: (@Sendable () throws -> BodyStream)?
    private var streamByteLimit: Int

    /// Whether transmission obtains a fresh producer instead of retained materialized bytes.
    public var isStreaming: Bool { streamFactory != nil }
    /// Complete stored bytes, or `nil` when a factory owns content production.
    public var storedBodyBytes: Data? { isStreaming ? nil : bytes }
    /// Reservation bytes: exact stored size or the full streaming cap; never an optimistic estimate.
    public var accountedBytes: Int { isStreaming ? streamByteLimit : bytes.count }

    /// Validates and retains a materialized body without performing I/O.
    /// - Parameters:
    ///   - bytes: Complete bytes copied by value; empty bodies are permitted.
    ///   - contentType: Nonempty media type without controls.
    ///   - maximumBytes: Positive byte cap, defaulting to 8 MiB.
    /// - Throws: Safe validation errors for invalid limits, media type, or oversized bytes.
    public init(bytes: Data, contentType: String, maximumBytes: Int = 8_388_608) throws {
        guard maximumBytes > 0, !contentType.isEmpty,
              !contentType.unicodeScalars.contains(where: { $0.properties.generalCategory == .control })
        else { throw DiscordError.validation(.invalidValue) }
        guard bytes.count <= maximumBytes else { throw DiscordError.validation(.limitExceeded) }
        self.bytes = bytes; self.contentType = contentType; streamFactory = nil; streamByteLimit = 0
    }

    /// Configures a fresh, total-byte-bounded stream for every admitted attempt.
    /// - Parameters:
    ///   - contentType: Nonempty control-free media type.
    ///   - maximumBytes: Positive hard cap and scheduling-byte reservation for each attempt.
    ///   - factory: Synchronous, nonblocking creator of a new single-consumer stream. Must return
    ///     equivalent content each time and transfer cleanup ownership to the caller. Deferred async
    ///     reads belong inside the returned stream; never return a previously consumed stream.
    /// - Returns: A replayable streaming body; no factory invocation occurs until request construction.
    /// - Throws: Safe validation errors for invalid configuration; factory errors occur when making an attempt.
    public static func stream(contentType: String, maximumBytes: Int,
                              factory: @escaping @Sendable () throws -> BodyStream) throws -> Self {
        var body = try Self(bytes: Data(), contentType: contentType, maximumBytes: maximumBytes)
        body.streamFactory = factory; body.streamByteLimit = maximumBytes
        return body
    }

    /// Serializes an encodable JSON value into a bounded replayable body.
    /// - Parameters:
    ///   - value: JSON-encodable payload; endpoint-specific validation remains the caller's responsibility.
    ///   - maximumBytes: Positive complete-body byte cap, defaulting to 8 MiB.
    /// - Returns: A body with `application/json` media type.
    /// - Throws: Encoder errors or safe size/configuration validation failures.
    public static func json<Value: Encodable>(_ value: Value, maximumBytes: Int = 8_388_608) throws -> Self {
        try Self(bytes: JSONEncoder().encode(value), contentType: "application/json", maximumBytes: maximumBytes)
    }

    /// Encodes ordered fields using UTF-8 form escaping, preserving repeated keys.
    /// - Parameters:
    ///   - fields: Raw names/values; spaces become `+`, literal plus becomes `%2B`.
    ///   - maximumBytes: Positive complete-body byte cap, defaulting to 8 MiB.
    /// - Returns: A materialized `application/x-www-form-urlencoded` body.
    /// - Throws: Safe size or configuration validation failures.
    public static func form(_ fields: [QueryItem], maximumBytes: Int = 8_388_608) throws -> Self {
        let text = fields.map { field in
            let name = percentEncode(field.name).replacingOccurrences(of: "%20", with: "+")
            return field.value.map { name + "=" + percentEncode($0).replacingOccurrences(of: "%20", with: "+") } ?? name
        }.joined(separator: "&")
        return try Self(bytes: Data(text.utf8), contentType: "application/x-www-form-urlencoded", maximumBytes: maximumBytes)
    }

    /// Builds multipart form data with caller-selected, reproducible boundary bytes.
    /// - Parameters:
    ///   - parts: Ordered fields or attachments; duplicate names remain distinct.
    ///   - boundary: ASCII letters, digits, `-`, or `_`, between 1 and 70 bytes. Must not occur in part bytes.
    ///   - maximumBytes: Positive cap including framing, defaulting to 8 MiB.
    /// - Returns: A replayable body containing CRLF framing and the closing boundary.
    /// - Throws: Safe validation failures for unsafe metadata, boundary collisions or excessive size.
    public static func multipart(_ parts: [MultipartPart], boundary: String, maximumBytes: Int = 8_388_608) throws -> Self {
        guard maximumBytes > 0, (1...70).contains(boundary.utf8.count), boundary.utf8.allSatisfy({
            (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95
        }) else { throw DiscordError.validation(.invalidValue) }
        var bytes = Data()
        for part in parts {
            guard part.bytes.range(of: Data(boundary.utf8)) == nil else { throw DiscordError.validation(.invalidValue) }
            var header = "--\(boundary)\r\nContent-Disposition: form-data; name=\"\(part.name)\""
            if let filename = part.filename { header += "; filename=\"\(filename)\"" }
            header += "\r\nContent-Type: \(part.contentType)\r\n\r\n"
            let overhead = header.utf8.count + 2
            guard overhead <= maximumBytes - bytes.count, part.bytes.count <= maximumBytes - bytes.count - overhead
            else { throw DiscordError.validation(.limitExceeded) }
            bytes.append(contentsOf: header.utf8); bytes.append(part.bytes); bytes.append(contentsOf: "\r\n".utf8)
        }
        let closing = Data("--\(boundary)--\r\n".utf8)
        guard closing.count <= maximumBytes - bytes.count else { throw DiscordError.validation(.limitExceeded) }
        bytes.append(closing)
        return try Self(bytes: bytes, contentType: "multipart/form-data; boundary=\(boundary)", maximumBytes: maximumBytes)
    }

    /// Creates a fresh single-consumer stream for one attempt without sharing read state.
    /// - Returns: A stream yielding retained bytes or a fresh bounded producer; close propagates to its source.
    /// - Throws: Factory errors before transmission or positive stream-limit validation failures.
    public func makeStream() throws -> BodyStream {
        if let streamFactory {
            let source = BoundedBodySource(upstream: try streamFactory(), maximumBytes: streamByteLimit)
            return try BodyStream(maximumChunkBytes: streamByteLimit, next: { try await source.next() }, close: { await source.close() })
        }
        let source = MaterializedBody(bytes)
        return try BodyStream(maximumChunkBytes: max(1, bytes.count), next: { await source.next() }, close: { await source.close() })
    }

    /// Conceals body bytes, media type and size during ordinary diagnostics.
    public var description: String { "RequestBody(redacted)" }
    /// Uses the same safe marker for debug formatting.
    public var debugDescription: String { description }
    /// Prevents reflected diagnostics from disclosing retained bytes.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}

/// Applies a hard aggregate cap to a newly created upload producer without buffering ahead.
private actor BoundedBodySource {
    let upstream: BodyStream
    var iterator: BodyStream.AsyncIterator?
    var remaining: Int
    var closed = false
    /// Takes ownership of a fresh producer and stores its hard remaining-byte budget.
    /// - Parameters:
    ///   - upstream: Single-consumer source; cleanup always propagates to it.
    ///   - maximumBytes: Validated positive complete-stream cap.
    init(upstream: BodyStream, maximumBytes: Int) {
        self.upstream = upstream; iterator = upstream.makeAsyncIterator(); remaining = maximumBytes
    }
    /// Pulls without prefetch and rejects a chunk before exceeding the complete-upload cap.
    /// - Returns: One bounded source chunk, or EOF.
    /// - Throws: Producer errors, cancellation, or a safe aggregate-limit failure; wrapper cleanup closes upstream.
    func next() async throws -> Data? {
        guard !closed, var iterator = self.iterator else { return nil }
        self.iterator = nil
        let chunk = try await iterator.next()
        guard !closed else { return nil }
        if let chunk {
            guard chunk.count <= remaining else { throw DiscordError.transport(.limitExceeded) }
            remaining -= chunk.count
            self.iterator = iterator
        }
        return chunk
    }
    /// Discards the iterator and closes the upstream source, including an in-flight read.
    func close() async { closed = true; iterator = nil; await upstream.close() }
}

/// A validated multipart field or binary attachment, without file-system ownership.
public struct MultipartPart: Sendable {
    public let name: String
    public let filename: String?
    public let contentType: String
    public let bytes: Data

    /// Stores bytes and rejects framing injection before multipart serialization.
    /// - Parameters:
    ///   - name: Nonempty form name without controls, quotes or backslashes.
    ///   - filename: Optional filename with the same restrictions; no local file is opened.
    ///   - contentType: Nonempty media type without control characters.
    ///   - bytes: Exact part contents, bounded when assembled into a request body.
    /// - Throws: `DiscordError.validation(.invalidValue)` for unsafe header metadata.
    public init(name: String, filename: String? = nil, contentType: String = "application/octet-stream", bytes: Data) throws {
        guard !name.isEmpty, !contentType.isEmpty,
              [name, filename ?? ""].allSatisfy({ !$0.unicodeScalars.contains(where: {
                  $0.properties.generalCategory == .control || $0 == "\"" || $0 == "\\"
              }) }),
              !contentType.unicodeScalars.contains(where: { $0.properties.generalCategory == .control })
        else { throw DiscordError.validation(.invalidValue) }
        self.name = name; self.filename = filename; self.contentType = contentType; self.bytes = bytes
    }
}

/// Isolates the read cursor of one replay attempt; the body value itself is immutable.
private actor MaterializedBody {
    var bytes: Data?
    /// Retains one attempt's complete bytes without starting transmission.
    /// - Parameter bytes: Bytes to yield once, including an empty body.
    init(_ bytes: Data) { self.bytes = bytes }
    /// Yields the remaining bytes once and then EOF; actor isolation serializes state.
    /// - Returns: Complete bytes on first pull, otherwise `nil`.
    func next() -> Data? { defer { bytes = nil }; return bytes }
    /// Discards any unread bytes; repeated cleanup has no additional effect.
    func close() { bytes = nil }
}

/// Percent-encodes raw UTF-8 using only RFC 3986 unreserved bytes.
/// - Parameter value: Unescaped segment, query component, audit reason or form component.
/// - Returns: ASCII text; slashes, percent signs and delimiters are encoded exactly once.
package func percentEncode(_ value: String) -> String {
    let hex = Array("0123456789ABCDEF".utf8)
    var result = [UInt8]()
    for byte in value.utf8 {
        if (65...90).contains(byte) || (97...122).contains(byte) || (48...57).contains(byte) || [45, 46, 95, 126].contains(byte) {
            result.append(byte)
        } else { result.append(37); result.append(hex[Int(byte >> 4)]); result.append(hex[Int(byte & 15)]) }
    }
    return String(decoding: result, as: UTF8.self)
}
