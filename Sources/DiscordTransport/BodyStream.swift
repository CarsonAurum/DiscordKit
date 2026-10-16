import Foundation

/// A pull-based, single-consumer body with a bounded chunk size and no internal queue.
///
/// The producer is called only on demand. Concurrent reads fail instead of buffering
/// waiters. Cancellation and producer failures close the source. Explicit close
/// discards a result from an in-flight read, including a producer that finishes late.
public struct BodyStream: AsyncSequence, Sendable, TransportResource {
    public typealias Element = Data
    private let storage: Storage

    /// Creates a stream around an adapter-owned source.
    /// - Parameters:
    ///   - maximumChunkBytes: Positive maximum for each yielded chunk, in bytes.
    ///   - next: Pulls one chunk or returns `nil` at EOF. Must honor task cancellation;
    ///     empty chunks are permitted. It must not retain an unbounded upstream queue.
    ///   - close: Releases the source. Called once, including EOF and error paths;
    ///     must unblock a concurrent `next` and must not throw or block an executor.
    /// - Throws: `TransportFailure.invalidLimit` for a nonpositive chunk limit.
    public init(
        maximumChunkBytes: Int,
        next: @escaping @Sendable () async throws -> Data?,
        close: @escaping @Sendable () async -> Void
    ) throws {
        guard maximumChunkBytes > 0 else { throw TransportFailure.invalidLimit }
        storage = Storage(maximumChunkBytes: maximumChunkBytes, next: next, close: close)
    }

    /// Creates an iterator sharing this stream's single-consumer ownership.
    /// - Returns: An iterator; creating another does not duplicate or replay data.
    public func makeAsyncIterator() -> AsyncIterator { AsyncIterator(storage: storage) }

    /// Closes the source once and discards any late in-flight read result.
    /// Concurrent close callers await the same cleanup before returning.
    public func close() async { await storage.close() }

    /// A single-pass iterator. An owner abandoning iteration must close its stream.
    public struct AsyncIterator: AsyncIteratorProtocol, Sendable {
        private let storage: Storage

        /// Binds an iterator to shared stream ownership without reading any bytes.
        /// - Parameter storage: Coordinator shared by every iterator of this stream.
        fileprivate init(storage: Storage) { self.storage = storage }

        /// Pulls one bounded chunk and advances shared stream state.
        /// - Returns: The next chunk, or `nil` after EOF or explicit close.
        /// - Throws: Cancellation, producer errors, oversized chunks, or concurrent read.
        public mutating func next() async throws -> Data? { try await storage.read() }
    }

    /// Coordinates reentrancy without retaining body chunks or queuing readers.
    fileprivate actor Storage {
        let maximumChunkBytes: Int
        let source: @Sendable () async throws -> Data?
        let cleanup: @Sendable () async -> Void
        var reading = false
        var closed = false
        var cleanupTask: Task<Void, Never>?

        /// Stores adapter closures; no source work begins before the first pull.
        /// - Parameters:
        ///   - maximumChunkBytes: Validated positive chunk bound.
        ///   - next: Cooperative producer closure.
        ///   - close: Exactly-once resource cleanup closure.
        init(maximumChunkBytes: Int, next: @escaping @Sendable () async throws -> Data?,
             close: @escaping @Sendable () async -> Void) {
            self.maximumChunkBytes = maximumChunkBytes
            source = next
            cleanup = close
        }

        /// Reserves one read before suspension and rejects stale completion after close.
        /// - Returns: A bounded source chunk, or `nil` for terminal ownership.
        /// - Throws: Source errors, cancellation, limit violations or simultaneous reads.
        func read() async throws -> Data? {
            do { try Task.checkCancellation() } catch { await close(); throw error }
            guard !closed else { return nil }
            guard !reading else { throw TransportFailure.concurrentRead }
            reading = true
            defer { reading = false }
            do {
                let chunk = try await source()
                try Task.checkCancellation()
                guard !closed else { return nil }
                if let chunk, chunk.count > maximumChunkBytes {
                    throw TransportFailure.chunkTooLarge(limit: maximumChunkBytes, actual: chunk.count)
                }
                if chunk == nil { await close() }
                return chunk
            } catch {
                await close()
                throw error
            }
        }

        /// Reserves closure before suspension and awaits one shared cleanup task.
        /// The storage owns and awaits the task; caller cancellation does not cancel
        /// cleanup. Cleanup must finish promptly and must not recursively close this
        /// same stream, which would wait on itself.
        func close() async {
            if let cleanupTask { await cleanupTask.value; return }
            closed = true
            let cleanup = self.cleanup
            let task = Task { await cleanup() }
            cleanupTask = task
            await task.value
        }
    }
}
