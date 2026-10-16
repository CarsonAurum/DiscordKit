import DiscordTestSupport
import DiscordTransport
import Foundation
import Testing

/// Portable transport behavior, clock deadlines, body ownership and reentrant close.
@Suite("Transport contracts")
struct TransportContractTests {
    /// Checks metadata preservation while every standard diagnostic omits credentials.
    /// Duplicate headers, nil bodies and explicit URLs remain directly readable by I/O.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func metadataAndRedaction() throws {
        let secret = "sentinel-transport-credential"
        let headers = [HTTPHeader(name: "Authorization", value: secret), HTTPHeader(name: "X", value: "2")]
        let url = try #require(URL(string: "https://example.invalid/\(secret)?token=\(secret)"))
        let request = HTTPRequest(method: "POST", url: url, headers: headers)
        let response = HTTPResponse(status: 429, headers: headers)
        #expect(request.method == "POST")
        #expect(request.url == url)
        #expect(request.headers == headers)
        #expect(request.body == nil)
        #expect(response.status == 429)
        #expect(response.headers == headers)
        #expect(response.body == nil)
        #expect(headers[0].name == "Authorization")
        #expect(headers[0].value == secret)
        for value in [headers[0] as any Sendable, request as any Sendable, response as any Sendable] {
            #expect(!String(describing: value).contains(secret))
            #expect(!String(reflecting: value).contains(secret))
            #expect(!String(describing: Array(Mirror(reflecting: value).children)).contains(secret))
        }
        #expect(HTTPRequest(method: "GET", url: url).headers.isEmpty)
        #expect(HTTPResponse(status: 204).headers.isEmpty)
    }

    /// Confirms immediate deadlines reject before work and normal results/errors propagate.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func deadlineAndOperationResults() async throws {
        let clock = ManualClock()
        let context = TransportContext(clock: clock)
        #expect(try await context.run { 42 } == 42)
        await #expect(throws: TestSupportFailure.scripted("failure")) {
            try await context.run { throw TestSupportFailure.scripted("failure") } as Int
        }
        #expect(throws: TransportFailure.deadlineExceeded) {
            try TransportContext(clock: clock, deadline: clock.now).check()
        }
        await #expect(throws: TransportFailure.deadlineExceeded) {
            try await TransportContext(clock: clock, deadline: clock.now).run { 5 }
        }
        #expect(clock.pendingSleepCount == 0)
    }

    /// Success and thrown work both cancel and await the losing future-deadline sleeper.
    /// No task advances the manual clock, so timer leakage is visible in its count.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func futureDeadlineOperationCompletion() async throws {
        let clock = ManualClock()
        let context = TransportContext(clock: clock, deadline: clock.now.advanced(by: .seconds(10)))
        #expect(try await context.run { 8 } == 8)
        #expect(clock.pendingSleepCount == 0)
        await #expect(throws: TestSupportFailure.scripted("operation")) {
            try await context.run { throw TestSupportFailure.scripted("operation") } as Int
        }
        #expect(clock.pendingSleepCount == 0)
    }

    /// Advances a deadline only after its sleeper registers, asserting losing-work cleanup.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func deadlineCancelsAndAwaitsOperation() async throws {
        let scheduled = TestBarrier()
        let clock = ManualClock(onSleepScheduled: { scheduled.open() })
        let gate = TestBarrier()
        let counter = ResourceCounter()
        let lease = await counter.acquire()
        let task = Task {
            try await TransportContext(clock: clock, deadline: clock.now.advanced(by: .seconds(2))).run {
                do { try await gate.wait(); await lease.release(); return 7 }
                catch { await lease.release(); throw error }
            }
        }
        try await scheduled.wait()
        try clock.advance(by: .seconds(2))
        await #expect(throws: TransportFailure.deadlineExceeded) { try await task.value }
        let snapshot = await counter.snapshot()
        #expect(snapshot.acquired == 1)
        #expect(snapshot.released == 1)
        #expect(snapshot.live == 0)
        #expect(clock.pendingSleepCount == 0)
        #expect(gate.waitingCount == 0)
    }

    /// Cancels context work while suspended and before entry, leaving no owned sleepers.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func cancellationBeforeAndDuringWork() async throws {
        let entered = TestBarrier()
        let gate = TestBarrier()
        let context = TransportContext(clock: ManualClock())
        let task = Task {
            try await context.run { entered.open(); try await gate.wait(); return true }
        }
        try await entered.wait()
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(gate.waitingCount == 0)
        let before = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await context.run { true }
        }
        await #expect(throws: CancellationError.self) { try await before.value }
    }

    /// Uses a caller-supplied actor source to verify pull order, empty chunks, EOF and cleanup.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func bodyChunksAndEOF() async throws {
        let source = ChunkSource([Data(), Data([1, 2]), Data([3])])
        let counter = ResourceCounter()
        let lease = await counter.acquire()
        let body = try BodyStream(maximumChunkBytes: 2, next: { await source.next() }, close: { await lease.release() })
        var iterator = body.makeAsyncIterator()
        #expect(try await iterator.next() == Data())
        #expect(try await iterator.next() == Data([1, 2]))
        #expect(try await iterator.next() == Data([3]))
        #expect(try await iterator.next() == nil)
        #expect(try await iterator.next() == nil)
        await body.close()
        #expect(await counter.snapshot().released == 1)
    }

    /// Validates positive bounds and rejects oversized producer data, closing exactly once.
    /// - Parameter limit: Nonpositive boundary limit, including the minimum signed integer.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [0, -1, Int.min]) func bodyInvalidLimits(_ limit: Int) throws {
        #expect(throws: TransportFailure.invalidLimit) {
            try BodyStream(maximumChunkBytes: limit, next: { nil }, close: {})
        }
    }

    /// Oversized chunks and producer failures share exactly-once terminal cleanup.
    /// - Parameter producerThrows: Whether the source throws or returns an oversized chunk.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [false, true]) func bodyFailures(_ producerThrows: Bool) async throws {
        let counter = ResourceCounter()
        let lease = await counter.acquire()
        let body = try BodyStream(maximumChunkBytes: 1, next: {
            if producerThrows { throw TestSupportFailure.scripted("producer") }
            return Data([1, 2])
        }, close: { await lease.release() })
        var iterator = body.makeAsyncIterator()
        if producerThrows {
            await #expect(throws: TestSupportFailure.scripted("producer")) { try await iterator.next() }
        } else {
            await #expect(throws: TransportFailure.chunkTooLarge(limit: 1, actual: 2)) { try await iterator.next() }
        }
        #expect(try await iterator.next() == nil)
        await body.close()
        #expect(await counter.snapshot().released == 1)
    }

    /// Holds a read across explicit close and proves a late source result is discarded.
    /// A simultaneous second read is rejected rather than queued or replayed.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func staleReadAndConcurrentClose() async throws {
        let entered = TestBarrier()
        let release = TestBarrier()
        let counter = ResourceCounter()
        let lease = await counter.acquire()
        let body = try BodyStream(maximumChunkBytes: 8, next: {
            entered.open()
            try await release.wait()
            return Data([9])
        }, close: { await lease.release() })
        let task = Task { var iterator = body.makeAsyncIterator(); return try await iterator.next() }
        try await entered.wait()
        var second = body.makeAsyncIterator()
        await #expect(throws: TransportFailure.concurrentRead) { try await second.next() }
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<8 { group.addTask { await body.close() } }
        }
        release.open()
        #expect(try await task.value == nil)
        #expect(try await second.next() == nil)
        #expect(await counter.snapshot().released == 1)
    }

    /// Cancels an active body pull; producer cancellation propagates and closes its source.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func bodyCancellation() async throws {
        let entered = TestBarrier()
        let release = TestBarrier()
        let counter = ResourceCounter()
        let lease = await counter.acquire()
        let body = try BodyStream(maximumChunkBytes: 8, next: {
            entered.open(); try await release.wait(); return Data([1])
        }, close: { await lease.release() })
        let task = Task { var iterator = body.makeAsyncIterator(); return try await iterator.next() }
        try await entered.wait()
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await counter.snapshot().released == 1)
        #expect(release.waitingCount == 0)
    }

    /// A pre-cancelled first read never enters its source, yet releases source ownership.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func bodyPreCancellation() async throws {
        let source = ChunkSource([Data([1])])
        let counter = ResourceCounter()
        let lease = await counter.acquire()
        let body = try BodyStream(maximumChunkBytes: 1, next: { await source.next() }, close: { await lease.release() })
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            var iterator = body.makeAsyncIterator()
            return try await iterator.next()
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await source.next() == Data([1]))
        #expect(await counter.snapshot().released == 1)
        await body.close()
        #expect(await counter.snapshot().released == 1)
    }

    /// Payload enums, datagrams and addresses hide secrets from all default diagnostic paths.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func payloadDiagnosticRedaction() {
        let secret = "sentinel-payload-credential"
        let address = DatagramAddress(host: secret, port: 1)
        let packet = Datagram(bytes: Data(secret.utf8), peer: address)
        let values: [any Sendable] = [WebSocketMessage.text(secret), WebSocketMessage.binary(Data(secret.utf8)), address, packet]
        for value in values {
            #expect(!String(describing: value).contains(secret))
            #expect(!String(reflecting: value).contains(secret))
            #expect(!String(describing: Array(Mirror(reflecting: value).children)).contains(secret))
        }
        #expect(WebSocketMessage.text(secret) == .text(secret))
        #expect(WebSocketMessage.binary(Data([1])) != .text("1"))
        #expect(packet.bytes == Data(secret.utf8))
        #expect(packet.peer.host == secret)
    }

    /// Ensures actor-isolated consumers use the same stream and deadline APIs safely.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @MainActor @Test func mainActorConsumer() async throws {
        let body = try BodyStream(maximumChunkBytes: 1, next: { nil }, close: {})
        var iterator = body.makeAsyncIterator()
        #expect(try await iterator.next() == nil)
        #expect(try await TransportContext(clock: ManualClock()).run { "ok" } == "ok")
    }
}

/// A finite deterministic source used to check public stream behavior through callers.
private actor ChunkSource {
    var chunks: [Data]

    /// Stores input chunks in order; an empty array produces EOF immediately.
    /// - Parameter chunks: Finite source values owned by one test.
    init(_ chunks: [Data]) { self.chunks = chunks }

    /// Removes and returns the first chunk, or `nil` after exhaustion.
    /// - Returns: Next complete chunk; empty chunks remain distinct from EOF.
    func next() -> Data? { chunks.isEmpty ? nil : chunks.removeFirst() }
}
