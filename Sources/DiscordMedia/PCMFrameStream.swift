import DiscordLogging
/// Failures specific to terminal-aware, single-consumer PCM streaming.
public enum PCMStreamError: Error, Sendable, Equatable {
    /// Another iterator call is already suspended for this stream's next block.
    case concurrentRead
}

/// An atomic view of the payload and reader ownership retained by a PCM stream.
///
/// Counts exclude blocks already transferred to consumer code. Payload accounting covers
/// normalized sample storage, while the independent block bound also covers empty blocks.
public struct PCMFrameStreamSnapshot: Sendable, Equatable {
    public let bufferedBlocks: Int
    public let accountedBytes: Int
    public let hasPendingReader: Bool
    public let isFinished: Bool
}

/// A bounded, terminal-aware PCM sequence and explicit-admission sink.
///
/// Construction starts no tasks or I/O. Unlike ``PCMFrameQueue``, an iterator waits when
/// temporarily empty and returns `nil` only after finish. Every iterator shares one FIFO;
/// overlapping suspended reads fail instead of retaining additional waiters. Writes fail
/// immediately on overflow, leaving pacing, retry and drop decisions to producers.
///
/// Cancelling iteration finishes the entire stream, discards buffered blocks and releases
/// its sole reader. An owner abandoning iteration without cancelling its task must call
/// ``finish(discardingBuffered:)``. No task, device or upstream producer is owned here.
/// Bounds apply to this stream only; applications sharing an aggregate memory budget must
/// coordinate their stream counts and limits separately.
public struct PCMFrameStream: AsyncSequence, PCMSink, Sendable {
    public typealias Element = PCMBuffer

    public let maximumBlocks: Int
    public let maximumBytes: Int
    private let storage: Storage

    /// Creates an empty sequence with independent queued-block and PCM payload limits.
    /// - Parameters:
    ///   - maximumBlocks: Queued block capacity in `1...4096`, including empty blocks;
    ///     defaults to eight. No capacity is allocated until a successful write.
    ///   - maximumBytes: Queued payload capacity in `1...67_108_864` bytes; defaults to
    ///     1,048,576. A single block must fit this limit even when a reader is waiting.
    /// - Throws: `MediaError.invalidCapacity` for an out-of-range limit. Construction
    ///   retains no producer, consumer continuation or asynchronous work.
    public init(maximumBlocks: Int = 8, maximumBytes: Int = 1_048_576) throws {
        guard (1...4_096).contains(maximumBlocks), (1...67_108_864).contains(maximumBytes) else {
            throw MediaError.invalidCapacity
        }
        self.maximumBlocks = maximumBlocks
        self.maximumBytes = maximumBytes
        storage = Storage(maximumBlocks: maximumBlocks, maximumBytes: maximumBytes)
    }

    /// Creates an iterator without reading, reserving a waiter or starting work.
    /// - Returns: An iterator sharing this stream's single-consumer FIFO. Creating
    ///   additional iterators does not copy or replay previously admitted blocks.
    public func makeAsyncIterator() -> AsyncIterator { AsyncIterator(storage: storage) }

    /// Atomically transfers a whole block to a waiting reader or the bounded FIFO.
    /// - Parameter buffer: Immutable normalized PCM; its format is preserved. Streams
    ///   may carry mixed formats, so downstream processors must validate compatibility.
    /// - Throws: `CancellationError` if cancelled before actor admission, `MediaError.closed`
    ///   after finish, or `MediaError.queueFull` if either bound would be exceeded. Failure
    ///   retains no input. Successful admission is not rolled back by later cancellation.
    ///   This method suspends only to enter the actor and never parks a producer.
    public func write(_ buffer: PCMBuffer) async throws { try await storage.write(buffer) }

    /// Stops writes and resolves any waiting reader with end-of-sequence.
    /// - Parameter discardingBuffered: False, the default, preserves FIFO blocks for
    ///   subsequent iteration; true releases them immediately. Repeated calls are safe,
    ///   including a later true call after an earlier draining finish.
    ///   Cleanup ignores caller cancellation and completes after one actor hop.
    public func finish(discardingBuffered: Bool = false) async {
        await storage.finish(discardingBuffered: discardingBuffered)
    }

    /// Reports one coherent view of retained queue and reader state.
    /// - Returns: Bounded counters and lifecycle flags after one actor hop; blocks already
    ///   transferred to consumers are excluded. This does not consume or finish the stream.
    public func snapshot() async -> PCMFrameStreamSnapshot { await storage.snapshot() }

    /// A single-pass iterator sharing the enclosing stream's reader ownership.
    public struct AsyncIterator: AsyncIteratorProtocol, Sendable {
        private let storage: Storage

        /// Binds to existing shared ownership without reserving a read.
        /// - Parameter storage: Stream actor shared by every producer and iterator.
        fileprivate init(storage: Storage) { self.storage = storage }

        /// Retrieves the oldest block or waits until a producer writes or finishes.
        /// - Returns: One complete PCM block, including empty blocks, or nil only once
        ///   finished and drained. Repeated terminal calls return nil.
        /// - Throws: `PCMStreamError.concurrentRead` if another call is suspended, or
        ///   `CancellationError` when cancelled before or during iteration. Cancellation
        ///   finishes this shared stream and discards every buffered block before return.
        ///   At most one continuation is retained; no production work is started.
        public mutating func next() async throws -> PCMBuffer? {
            let storage = self.storage
            do {
                let buffer = try await withTaskCancellationHandler {
                    try await storage.read()
                } onCancel: {
                    // Cancellation callbacks cannot await. This short actor hop releases
                    // the sole continuation and owns no producer or user callback work.
                    Task { await storage.cancel() }
                }
                try Task.checkCancellation()
                return buffer
            } catch {
                if Task.isCancelled { await storage.cancel() }
                throw error
            }
        }
    }

    /// Owns bounded FIFO storage and at most one consumer continuation.
    fileprivate actor Storage {
        private let maximumBlocks: Int
        private let maximumBytes: Int
        private var buffers: [PCMBuffer] = []
        private var accountedBytes = 0
        private var finished = false
        private var reading = false
        private var waiter: CheckedContinuation<PCMBuffer?, any Error>?

        /// Stores validated capacities without preallocation or asynchronous work.
        /// - Parameters:
        ///   - maximumBlocks: Validated positive block count limit.
        ///   - maximumBytes: Validated positive PCM payload byte limit.
        init(maximumBlocks: Int, maximumBytes: Int) {
            self.maximumBlocks = maximumBlocks
            self.maximumBytes = maximumBytes
        }

        /// Commits one fail-fast FIFO admission without suspending inside isolation.
        /// - Parameter buffer: Whole block transferred only after all checks succeed.
        /// - Throws: Cancellation, closed-stream or queue-capacity failure. Even direct
        ///   delivery must fit the configured byte limit; failed writes preserve a waiter.
        func write(_ buffer: PCMBuffer) throws {
            try Task.checkCancellation()
            guard !finished else { throw MediaError.closed }
            guard buffers.count < maximumBlocks,
                  buffer.accountedBytes <= maximumBytes - accountedBytes else {
                throw MediaError.queueFull
            }
            if let waiter {
                self.waiter = nil
                waiter.resume(returning: buffer)
            } else {
                buffers.append(buffer)
                accountedBytes += buffer.accountedBytes
            }
        }

        /// Removes one FIFO block or reserves the only permitted suspended read.
        /// - Returns: A transferred block, or nil after normal finish and drain.
        /// - Throws: Cancellation at entry, cancelling the whole stream, or concurrent-read
        ///   failure. While suspended, write, finish or cancellation resolves the continuation.
        ///   Array removal is linear in the configured, bounded block count.
        func read() async throws -> PCMBuffer? {
            do { try Task.checkCancellation() } catch { cancel(); throw error }
            guard !reading else { throw PCMStreamError.concurrentRead }
            if !buffers.isEmpty {
                let buffer = buffers.removeFirst()
                accountedBytes -= buffer.accountedBytes
                return buffer
            }
            guard !finished else { return nil }
            reading = true
            defer { reading = false }
            return try await withCheckedThrowingContinuation { waiter = $0 }
        }

        /// Marks terminal ownership and optionally releases all queued payloads.
        /// - Parameter discardingBuffered: Whether to discard queued blocks immediately.
        ///   Any parked read implies the queue is empty and is completed with normal EOF.
        func finish(discardingBuffered: Bool) {
            if !finished {
                DiscordLog.makeLogger("media").debug("PCM stream finished", metadata: ["dk.event": "media.pcm_stream.finished",
                    "dk.buffered_blocks": .stringConvertible(buffers.count),
                    "dk.discarding": .stringConvertible(discardingBuffered)])
            }
            finished = true
            if discardingBuffered {
                buffers.removeAll(keepingCapacity: false)
                accountedBytes = 0
            }
            if let waiter {
                self.waiter = nil
                waiter.resume(returning: nil)
            }
        }

        /// Cancels shared iteration and releases every retained payload and continuation.
        /// Repeated calls are safe; any suspended reader receives `CancellationError`.
        /// This method never suspends and has no user-owned cleanup callback.
        func cancel() {
            if !finished {
                DiscordLog.makeLogger("media").trace("PCM stream cancelled", metadata: ["dk.event": "media.pcm_stream.cancelled"])
            }
            finished = true
            buffers.removeAll(keepingCapacity: false)
            accountedBytes = 0
            if let waiter {
                self.waiter = nil
                waiter.resume(throwing: CancellationError())
            }
        }

        /// Returns coherent payload accounting and the single-waiter lifecycle flags.
        /// - Returns: A snapshot excluding already-transferred blocks and resumed readers.
        func snapshot() -> PCMFrameStreamSnapshot {
            PCMFrameStreamSnapshot(bufferedBlocks: buffers.count, accountedBytes: accountedBytes,
                                   hasPendingReader: waiter != nil, isFinished: finished)
        }
    }
}
