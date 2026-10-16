import Foundation

/// A local byte stream. Adapters select Unix sockets or named pipes, never Discord framing.
public protocol IPCTransport: TransportResource {
    /// Writes bytes in order with bounded backpressure; empty writes are permitted.
    /// - Parameters:
    ///   - bytes: Bytes to write once; boundaries need not survive reading.
    ///   - context: Deadline and cancellation for write admission and completion.
    /// - Throws: Cancellation, expiration, closure, unsupported-host or local I/O errors.
    func write<C: Clock>(_ bytes: Data, context: TransportContext<C>) async throws
        where C.Duration == Duration

    /// Reads at most a caller-specified positive byte count, with one active reader.
    /// - Parameters:
    ///   - maximumBytes: Positive upper bound; invalid limits fail before reading.
    ///   - context: Deadline and cancellation for this read.
    /// - Returns: A nonempty bounded chunk, or `nil` at EOF; framing belongs upstream.
    /// - Throws: Invalid limit, concurrent read, cancellation, expiration or I/O errors.
    func read<C: Clock>(maximumBytes: Int, context: TransportContext<C>) async throws -> Data?
        where C.Duration == Duration
}
