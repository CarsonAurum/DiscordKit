import DiscordTestSupport
import DiscordLogging
import Testing
@testable import DiscordMedia

@Suite("Terminal-aware bounded PCM streams")
struct PCMFrameStreamTests {
    /// Checks default configuration, empty construction state and all capacity extremes.
    /// No producer, reader or task is created by initialization or iterator construction.
    @Test func constructionAndCapacityValidation() async throws {
        let stream = try PCMFrameStream()
        #expect(stream.maximumBlocks == 8)
        #expect(stream.maximumBytes == 1_048_576)
        _ = stream.makeAsyncIterator()
        let initial = await stream.snapshot()
        #expect(initial.bufferedBlocks == 0 && initial.accountedBytes == 0)
        #expect(!initial.hasPendingReader && !initial.isFinished)
        let largest = try PCMFrameStream(maximumBlocks: 4_096, maximumBytes: 67_108_864)
        #expect(largest.maximumBlocks == 4_096 && largest.maximumBytes == 67_108_864)
        for (blocks, bytes) in [(0, 1), (-1, 1), (Int.min, 1), (4_097, 1), (Int.max, 1),
                               (1, 0), (1, -1), (1, Int.min), (1, 67_108_865), (1, Int.max)] {
            #expect(throws: MediaError.invalidCapacity) {
                try PCMFrameStream(maximumBlocks: blocks, maximumBytes: bytes)
            }
        }
    }

    /// Verifies FIFO sink admission, exact byte limits, fail-fast overflow and draining EOF.
    /// Mixed formats retain their original metadata; no conversion is performed by streaming.
    @Test func fifoBudgetsAndDrainingFinish() async throws {
        let first = try PCMBuffer(format: PCMFormat(), samples: [0.25, -0.25])
        let second = try PCMBuffer(format: PCMFormat(sampleRate: 8_000, channelCount: 1), samples: [1, -1])
        let stream = try PCMFrameStream(maximumBlocks: 2, maximumBytes: 16)
        let sink: any PCMSink = stream
        try await sink.write(first)
        try await sink.write(second)
        let full = await stream.snapshot()
        #expect(full.bufferedBlocks == 2 && full.accountedBytes == 16)
        await #expect(throws: MediaError.queueFull) { try await sink.write(first) }
        #expect(await stream.snapshot() == full)
        await stream.finish()
        #expect(await stream.snapshot().isFinished)
        await #expect(throws: MediaError.closed) { try await sink.write(first) }
        var iterator = stream.makeAsyncIterator()
        #expect(try await iterator.next() == first)
        #expect(await stream.snapshot().accountedBytes == 8)
        #expect(try await iterator.next() == second)
        #expect(try await iterator.next() == nil)
        #expect(try await iterator.next() == nil)
        let drained = await stream.snapshot()
        #expect(drained.bufferedBlocks == 0 && drained.accountedBytes == 0)
        #expect(!drained.hasPendingReader && drained.isFinished)
        await stream.finish()
        #expect(await stream.snapshot() == drained)
    }

    /// Exercises the byte bound independently and proves empty blocks consume block capacity.
    /// Every failed admission leaves both counters unchanged, including a maximum PCM block.
    @Test func byteAndEmptyBlockBounds() async throws {
        let format = try PCMFormat()
        let block = try PCMBuffer(format: format, samples: [0, 0])
        let stream = try PCMFrameStream(maximumBlocks: 4, maximumBytes: 7)
        await #expect(throws: MediaError.queueFull) { try await stream.write(block) }
        #expect(await stream.snapshot().accountedBytes == 0)
        #expect(await stream.snapshot().bufferedBlocks == 0)
        let maximum = try PCMBuffer(format: PCMFormat(sampleRate: 192_000),
                                    samples: Array(repeating: 0, count: 46_080))
        await #expect(throws: MediaError.queueFull) { try await stream.write(maximum) }
        let empty = try PCMBuffer(format: format, samples: [])
        let emptyBound = try PCMFrameStream(maximumBlocks: 1, maximumBytes: 1)
        try await emptyBound.write(empty)
        await #expect(throws: MediaError.queueFull) { try await emptyBound.write(empty) }
        #expect(await emptyBound.snapshot().bufferedBlocks == 1)
        #expect(await emptyBound.snapshot().accountedBytes == 0)
        await emptyBound.finish()
        var iterator = emptyBound.makeAsyncIterator()
        #expect(try await iterator.next() == empty)
        #expect(try await iterator.next() == nil)
        await stream.finish(discardingBuffered: true)
    }

    /// Parks one reader deterministically, rejects a second and transfers a whole block.
    /// Additional sequential iterators share the FIFO without duplicating or replaying data.
    @Test func waitingReaderAndSharedIteration() async throws {
        let stream = try PCMFrameStream(maximumBlocks: 1, maximumBytes: 8)
        let first = try PCMBuffer(format: PCMFormat(), samples: [0.5, -0.5])
        let second = try PCMBuffer(format: PCMFormat(), samples: [1, -1])
        let reader = Task {
            var iterator = stream.makeAsyncIterator()
            return try await iterator.next()
        }
        await waitForReader(stream)
        var competing = stream.makeAsyncIterator()
        await #expect(throws: PCMStreamError.concurrentRead) { try await competing.next() }
        #expect(await stream.snapshot().hasPendingReader)
        try await stream.write(first)
        #expect(try await reader.value == first)
        let delivered = await stream.snapshot()
        #expect(delivered.bufferedBlocks == 0 && delivered.accountedBytes == 0)
        #expect(!delivered.hasPendingReader && !delivered.isFinished)
        try await stream.write(second)
        #expect(try await competing.next() == second)
        await stream.finish()
        #expect(try await competing.next() == nil)
    }

    /// Requires direct-to-reader blocks to fit the byte bound and keeps the reader on failure.
    /// A later valid empty block satisfies that same continuation without queued accounting.
    @Test func waitingReaderDoesNotBypassByteBound() async throws {
        let stream = try PCMFrameStream(maximumBlocks: 1, maximumBytes: 7)
        let reader = Task {
            var iterator = stream.makeAsyncIterator()
            return try await iterator.next()
        }
        await waitForReader(stream)
        let block = try PCMBuffer(format: PCMFormat(), samples: [0, 0])
        await #expect(throws: MediaError.queueFull) { try await stream.write(block) }
        let rejected = await stream.snapshot()
        #expect(rejected.hasPendingReader && rejected.accountedBytes == 0)
        #expect(rejected.bufferedBlocks == 0 && !rejected.isFinished)
        let empty = try PCMBuffer(format: PCMFormat(), samples: [])
        try await stream.write(empty)
        #expect(try await reader.value == empty)
        await stream.finish()
    }

    /// Normal finish wakes an idle reader with EOF under both drain and discard policies.
    /// - Parameter discard: Whether finish explicitly discards any buffered payload.
    @Test(arguments: [false, true])
    func finishWakesIdleReader(discard: Bool) async throws {
        let stream = try PCMFrameStream()
        let reader = Task {
            var iterator = stream.makeAsyncIterator()
            return try await iterator.next()
        }
        await waitForReader(stream)
        await stream.finish(discardingBuffered: discard)
        #expect(try await reader.value == nil)
        let terminal = await stream.snapshot()
        #expect(terminal.isFinished && !terminal.hasPendingReader)
        #expect(terminal.bufferedBlocks == 0 && terminal.accountedBytes == 0)
    }

    /// Discard releases queued payloads immediately, including after a draining finish.
    /// Repeated cleanup and finish invoked from a cancelled task remain safe and complete.
    @Test func discardAndCancelledCleanup() async throws {
        let stream = try PCMFrameStream()
        let block = try PCMBuffer(format: PCMFormat(), samples: [0, 0])
        try await stream.write(block)
        await stream.finish()
        #expect(await stream.snapshot().accountedBytes == 8)
        let cleanup = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            await stream.finish(discardingBuffered: true)
        }
        await cleanup.value
        await stream.finish(discardingBuffered: true)
        var iterator = stream.makeAsyncIterator()
        #expect(try await iterator.next() == nil)
        let snapshot = await stream.snapshot()
        #expect(snapshot.isFinished && !snapshot.hasPendingReader)
        #expect(snapshot.bufferedBlocks == 0 && snapshot.accountedBytes == 0)
        await #expect(throws: MediaError.closed) { try await stream.write(block) }
    }

    /// Cancelling a suspended read closes shared iteration and removes its sole continuation.
    /// No timing sleep is used: cancellation occurs only after the pending-reader snapshot.
    @Test func cancellationDuringWaiting() async throws {
        let stream = try PCMFrameStream()
        let reader = Task {
            var iterator = stream.makeAsyncIterator()
            return try await iterator.next()
        }
        await waitForReader(stream)
        reader.cancel()
        await #expect(throws: CancellationError.self) { try await reader.value }
        let cancelled = await stream.snapshot()
        #expect(cancelled.isFinished && !cancelled.hasPendingReader)
        #expect(cancelled.bufferedBlocks == 0 && cancelled.accountedBytes == 0)
        var iterator = stream.makeAsyncIterator()
        #expect(try await iterator.next() == nil)
        let block = try PCMBuffer(format: PCMFormat(), samples: [0, 0])
        await #expect(throws: MediaError.closed) { try await stream.write(block) }
    }

    /// A pre-cancelled write retains nothing, while a pre-cancelled read discards ownership.
    /// The queued block remains available until iteration itself is cancelled.
    @Test func cancellationBeforeAdmission() async throws {
        let stream = try PCMFrameStream()
        let block = try PCMBuffer(format: PCMFormat(), samples: [0.25, -0.25])
        try await stream.write(block)
        let writer = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await stream.write(block)
        }
        await #expect(throws: CancellationError.self) { try await writer.value }
        let retained = await stream.snapshot()
        #expect(retained.bufferedBlocks == 1 && retained.accountedBytes == 8)
        #expect(!retained.isFinished)
        let reader = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            var iterator = stream.makeAsyncIterator()
            return try await iterator.next()
        }
        await #expect(throws: CancellationError.self) { try await reader.value }
        let cancelled = await stream.snapshot()
        #expect(cancelled.bufferedBlocks == 0 && cancelled.accountedBytes == 0)
        #expect(cancelled.isFinished && !cancelled.hasPendingReader)
    }

    /// Competes 32 producers for eight slots and checks exact atomic capacity accounting.
    /// Successful offers all survive until explicitly discarded; no waiting producers remain.
    @Test func concurrentProducerAdmission() async throws {
        let stream = try PCMFrameStream(maximumBlocks: 8, maximumBytes: 64)
        let block = try PCMBuffer(format: PCMFormat(), samples: [0.25, -0.25])
        let outcomes = await withTaskGroup(of: Result<Void, any Error>.self) { group in
            for _ in 0..<32 {
                group.addTask {
                    do { try await stream.write(block); return .success(()) }
                    catch { return .failure(error) }
                }
            }
            var successes = 0
            var fullFailures = 0
            for await result in group {
                switch result {
                case .success: successes += 1
                case .failure(let error):
                    #expect(error as? MediaError == .queueFull)
                    fullFailures += 1
                }
            }
            return (successes, fullFailures)
        }
        #expect(outcomes.0 == 8 && outcomes.1 == 24)
        let full = await stream.snapshot()
        #expect(full.bufferedBlocks == 8 && full.accountedBytes == 64)
        #expect(!full.hasPendingReader && !full.isFinished)
        await stream.finish(discardingBuffered: true)
        let empty = await stream.snapshot()
        #expect(empty.bufferedBlocks == 0 && empty.accountedBytes == 0)
    }

    /// Confirms ordinary `for try await` iteration consumes a finite, ordered PCM sequence.
    /// Empty blocks are yielded as values and never confused with terminal end-of-sequence.
    @Test func asyncSequenceConsumption() async throws {
        let stream = try PCMFrameStream()
        let format = try PCMFormat(channelCount: 1)
        let blocks = try [PCMBuffer(format: format, samples: []),
                          PCMBuffer(format: format, samples: [0.5]),
                          PCMBuffer(format: format, samples: [-0.5])]
        for block in blocks { try await stream.write(block) }
        await stream.finish()
        var received: [PCMBuffer] = []
        for try await block in stream { received.append(block) }
        #expect(received == blocks)
        #expect(await stream.snapshot().accountedBytes == 0)
    }

    /// Yields execution until actor state proves a reader has parked its sole continuation.
    /// - Parameter stream: Active test stream with an already-created reader task.
    ///   This is a scheduling barrier, not a wall-clock delay or timeout assertion.
    private func waitForReader(_ stream: PCMFrameStream) async {
        while !(await stream.snapshot().hasPendingReader) { await Task.yield() }
    }
}

extension PCMFrameStreamTests {
    /// Emits a single lifecycle event on terminal stream ownership, with no initialization or
    /// per-buffer/sample diagnostics and no duplicate event when finish is repeated.
    /// - Throws: Unexpected valid PCM fixture or stream admission failures.
    @Test func structuredLoggingStaysOutsideFrameOperations() async throws {
        let recorder = LogRecorder()
        try await DiscordLog.$loggerFactory.withValue({ recorder.makeLogger($0) }) {
            let stream = try PCMFrameStream()
            var iterator = stream.makeAsyncIterator()
            #expect(recorder.entries.isEmpty)
            let buffer = try PCMBuffer(format: PCMFormat(), samples: [0.123456, -0.123456])
            try await stream.write(buffer)
            #expect(try await iterator.next() == buffer)
            #expect(recorder.entries.isEmpty)
            await stream.finish()
            await stream.finish(discardingBuffered: true)
            #expect(try await iterator.next() == nil)
        }
        #expect(recorder.entries.count == 1)
        #expect(recorder.entries.first?.label == "discordkit.media")
        #expect(recorder.entries.first?.level == .debug)
        #expect(recorder.entries.first?.metadata["dk.event"] == "media.pcm_stream.finished")
        let renderedMetadata = String(describing: recorder.entries.first?.metadata)
        #expect(!renderedMetadata.contains("0.123456"))
    }
}
