#if !os(Windows) && !os(WASI)
import DiscordLogging
import DiscordTransport
import DiscordTestSupport
import Foundation
import NIOCore
import NIOPosix
import Testing
@testable import DiscordUnixPlatform

/// Native Unix-domain loopback peer modes keep framing outside the adapter.
private enum UnixIPCPeerMode: Sendable, Equatable {
    case echo
    case sendAndClose
    case hold
}

/// A real local socket server, independently owning its listener and event loop.
private struct UnixIPCTestPeer: Sendable {
    let group: MultiThreadedEventLoopGroup
    let channel: any Channel
    let path: String

    /// Binds a unique short temporary socket path, optionally disabling all reads.
    /// - Parameter mode: Echo bytes, send fixture bytes then EOF, or hold reads closed.
    /// - Returns: Owned peer whose cleanup removes its filesystem socket entry.
    /// - Throws: Native bind or pipeline construction failures.
    static func open(mode: UnixIPCPeerMode = .echo) async throws -> UnixIPCTestPeer {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let path = "/tmp/dk-\(UUID().uuidString).sock"
        do {
            let channel = try await ServerBootstrap(group: group)
                .childChannelOption(ChannelOptions.autoRead, value: mode != .hold)
                .childChannelInitializer { channel in
                    channel.eventLoop.makeCompletedFuture {
                        try channel.pipeline.syncOperations.addHandler(UnixIPCEchoHandler(mode: mode))
                    }
                }.bind(unixDomainSocketPath: path).get()
            return UnixIPCTestPeer(group: group, channel: channel, path: path)
        } catch { try? await group.shutdownGracefully(); try? FileManager.default.removeItem(atPath: path); throw error }
    }

    /// Closes listener/children, awaits group shutdown, then removes the socket path.
    func close() async {
        channel.close(promise: nil)
        try? await channel.closeFuture.get()
        try? await group.shutdownGracefully()
        try? FileManager.default.removeItem(atPath: path)
    }
}

/// Native event-loop handler preserving bytes without imposing message framing.
private final class UnixIPCEchoHandler: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer
    let mode: UnixIPCPeerMode

    /// Stores the immutable peer behavior before connection activation.
    /// - Parameter mode: Echo, send-and-close, or never-read behavior.
    init(mode: UnixIPCPeerMode) { self.mode = mode }

    /// Sends a binary fixture before closing when EOF-drain behavior is requested.
    /// - Parameter context: Native accepted socket's event-loop context.
    func channelActive(context: ChannelHandlerContext) {
        if mode == .sendAndClose {
            let channel = context.channel
            context.writeAndFlush(wrapOutboundOut(channel.allocator.buffer(bytes: [0, 1, 128, 255])))
                .whenComplete { _ in channel.close(promise: nil) }
        }
        context.fireChannelActive()
    }

    /// Echoes each native fragment without changing byte order or its content.
    /// - Parameters:
    ///   - context: Sole event-loop owner of outbound write ordering.
    ///   - data: Unframed native stream fragment.
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        if mode == .echo { context.writeAndFlush(wrapOutboundOut(unwrapInboundIn(data)), promise: nil) }
    }
}

/// Native Unix client contract conformance, using unique local socket paths.
@Suite struct UnixIPCAdapterTests {
    /// Creates a failure-bounded context; successful tests synchronize through I/O.
    /// - Returns: Monotonic context expiring ten seconds from creation.
    private func context() -> TransportContext<ContinuousClock> {
        let clock = ContinuousClock()
        return .init(clock: clock, deadline: clock.now.advanced(by: .seconds(10)))
    }

    /// Opens an echo peer and client, awaiting both cleanups on any exit path.
    /// - Parameter body: Test operations that must not retain the client transport.
    /// - Throws: Original socket setup or test operation failure.
    private func withClient(_ body: (UnixIPCTransport) async throws -> Void) async throws {
        let peer = try await UnixIPCTestPeer.open()
        do {
            let client = try await UnixIPCTransport.connect(path: peer.path, context: context())
            do { try await body(client) }
            catch { await client.close(); throw error }
            await client.close()
        } catch { await peer.close(); throw error }
        await peer.close()
    }

    /// Confirms binary bytes, bounded reads, empty writes and sequential write order.
    /// - Parameter limit: Positive caller read bound, including Int.max without huge allocation.
    /// - Throws: Unexpected local stream failures.
    @Test(arguments: [1, 2, 3, Int.max])
    func binaryRoundTrip(limit: Int) async throws {
        try await withClient { (client: UnixIPCTransport) async throws in
            try await client.write(Data(), context: context())
            try await client.write(Data([0, 128]), context: context())
            try await client.write(Data([255, 7]), context: context())
            var received = Data()
            while received.count < 4 {
                let chunk = try #require(try await client.read(maximumBytes: limit, context: context()))
                #expect(!chunk.isEmpty)
                #expect(chunk.count <= limit)
                received.append(chunk)
            }
            #expect(received == Data([0, 128, 255, 7]))
        }
    }


    /// Native echo traces read/write admission and completion without socket paths or transferred content.
    /// - Throws: Unexpected local socket setup, native I/O or cleanup failure.
    @Test func ipcTraceSeparatesReadAndWrite() async throws {
        let recorder = LogRecorder()
        try await DiscordLog.$loggerFactory.withValue({ recorder.makeLogger($0) }) {
            try await withClient { client in
                let payload = Data("PRIVATE_IPC_PAYLOAD".utf8)
                try await client.write(payload, context: context())
                var received = Data()
                while received.count < payload.count {
                    received.append(try #require(try await client.read(maximumBytes: payload.count, context: context())))
                }
                #expect(received == payload)
            }
        }
        let entries = recorder.entries
        #expect(entries.contains { $0.label == "discordkit.unix.ipc.write" && $0.level == .trace && $0.metadata["dk.event"] == "unix.ipc.write.admitted" })
        #expect(entries.contains { $0.label == "discordkit.unix.ipc.read" && $0.metadata["dk.event"] == "unix.ipc.read.completed" })
        #expect(entries.contains { $0.level == .info && $0.metadata["dk.event"] == "unix.ipc.connected" })
        #expect(entries.last?.level == .info && entries.last?.metadata["dk.event"] == "unix.ipc.closed")
        let rendered = String(describing: entries.map { ($0.message, $0.metadata) })
        #expect(!rendered.contains("PRIVATE_IPC_PAYLOAD") && !rendered.contains(".sock"))
    }

    /// Drains data sent immediately before peer EOF without returning empty chunks.
    /// - Throws: Unexpected peer setup or native read failures.
    @Test func bufferedEOF() async throws {
        let peer = try await UnixIPCTestPeer.open(mode: .sendAndClose)
        do {
            let client = try await UnixIPCTransport.connect(path: peer.path, context: context())
            do {
                var bytes = Data()
                while let chunk = try await client.read(maximumBytes: 1, context: context()) { bytes.append(chunk) }
                #expect(bytes == Data([0, 1, 128, 255]))
                #expect(try await client.read(maximumBytes: 1, context: context()) == nil)
            } catch { await client.close(); throw error }
            await client.close()
        } catch { await peer.close(); throw error }
        await peer.close()
    }

    /// Rejects invalid read limits before consuming bytes, preserving connection usability.
    /// - Throws: Unexpected local socket failures.
    @Test func invalidReadAndWriteLimits() async throws {
        let peer = try await UnixIPCTestPeer.open()
        do {
            let client = try await UnixIPCTransport.connect(path: peer.path, maximumWriteBytes: 2, context: context())
            do {
                for limit in [0, -1, Int.min] {
                    await #expect(throws: TransportFailure.invalidLimit) {
                        try await client.read(maximumBytes: limit, context: context())
                    }
                }
                await #expect(throws: TransportFailure.chunkTooLarge(limit: 2, actual: 3)) {
                    try await client.write(Data([1, 2, 3]), context: context())
                }
                try await client.write(Data([7]), context: context())
                #expect(try await client.read(maximumBytes: 1, context: context()) == Data([7]))
            } catch { await client.close(); throw error }
            await client.close()
        } catch { await peer.close(); throw error }
        await peer.close()
    }

    /// Rejects duplicate readers and cancels the registered pending read without sleeps.
    /// - Throws: Unexpected setup or post-close contract failures.
    @Test func concurrentReadAndCancellation() async throws {
        try await withClient { (client: UnixIPCTransport) async throws in
            await withTaskGroup(of: Int.self) { group in
                for _ in 0..<2 {
                    group.addTask {
                        do { _ = try await client.read(maximumBytes: 1, context: .init(clock: ContinuousClock())); return 0 }
                        catch TransportFailure.concurrentRead { return 1 }
                        catch is CancellationError { return 2 }
                        catch { return 3 }
                    }
                }
                #expect(await group.next() == 1)
                group.cancelAll()
                #expect(await group.next() == 2)
            }
            await client.close()
            #expect(try await client.read(maximumBytes: 1, context: context()) == nil)
            await #expect(throws: TransportFailure.closed) { try await client.write(Data(), context: context()) }
        }
    }

    /// Verifies admitted concurrent writes are bounded and cancellation interrupts backpressure.
    /// The peer never reads; a 4 MiB write exceeds native socket buffers. Duplicate
    /// rejection establishes one admitted writer before cancelling its native wait.
    /// - Throws: Unexpected setup or writer failures.
    @Test func concurrentWriteAndCancellation() async throws {
        let peer = try await UnixIPCTestPeer.open(mode: .hold)
        do {
            let client = try await UnixIPCTransport.connect(path: peer.path, maximumWriteBytes: 4_194_304, context: context())
            await withTaskGroup(of: Int.self) { group in
                for _ in 0..<2 {
                    group.addTask {
                        do { try await client.write(Data(repeating: 7, count: 4_194_304),
                                                    context: .init(clock: ContinuousClock())); return 0 }
                        catch UnixIPCFailure.concurrentWrite { return 1 }
                        catch is CancellationError { return 2 }
                        catch { return 3 }
                    }
                }
                #expect(await group.next() == 1)
                group.cancelAll()
                #expect(await group.next() == 2)
            }
            await client.close()
        } catch { await peer.close(); throw error }
        await peer.close()
    }

    /// Repeated/concurrent close releases the native socket and drops buffered bytes.
    /// - Throws: Unexpected socket setup failures.
    @Test func closeIsConcurrentAndIdempotent() async throws {
        try await withClient { (client: UnixIPCTransport) async throws in
            async let first: Void = client.close()
            async let second: Void = client.close()
            _ = await (first, second)
            await client.close()
            #expect(try await client.read(maximumBytes: 8, context: context()) == nil)
            await #expect(throws: TransportFailure.closed) { try await client.write(Data(), context: context()) }
        }
    }

    /// Rejects invalid paths/budgets and returns fixed errors without leaking path text.
    /// - Parameter path: Relative, empty, embedded-NUL or overlong socket path.
    @Test(arguments: ["", "relative.sock", "/tmp/bad\0socket", "/" + String(repeating: "a", count: 512)])
    func invalidPath(path: String) async {
        await #expect(throws: UnixIPCFailure.invalidPath) {
            try await UnixIPCTransport.connect(path: path, context: context())
        }
        await #expect(throws: UnixIPCFailure.invalidConfiguration) {
            try await UnixIPCTransport.connect(path: "/tmp/unused.sock", maximumBufferedBytes: 0, context: context())
        }
        await #expect(throws: UnixIPCFailure.invalidConfiguration) {
            try await UnixIPCTransport.connect(path: "/tmp/unused.sock", maximumWriteBytes: 0, context: context())
        }
    }

    /// Missing endpoints, inclusive expiration and pre-cancellation release connection attempts.
    @Test func connectionFailureDeadlineAndCancellation() async {
        await #expect(throws: UnixIPCFailure.ioFailure) {
            try await UnixIPCTransport.connect(path: "/tmp/dk-missing-\(UUID().uuidString).sock", context: context())
        }
        let clock = ContinuousClock()
        await #expect(throws: TransportFailure.deadlineExceeded) {
            try await UnixIPCTransport.connect(path: "/tmp/unused.sock", context: .init(clock: clock, deadline: clock.now))
        }
        let operation = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await UnixIPCTransport.connect(path: "/tmp/unused.sock", context: .init(clock: ContinuousClock()))
        }
        do { _ = try await operation.value; Issue.record("Expected cancellation before connecting") }
        catch { #expect(error is CancellationError) }
    }

    /// Advances an injected deadline while a read is pending and verifies cleanup.
    /// - Throws: Local setup, barrier or manual-clock failures.
    @Test func deadlineDuringRead() async throws {
        guard #available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *) else { return }
        try await withClient { (client: UnixIPCTransport) async throws in
            let registered = TestBarrier()
            let clock = ManualClock(onSleepScheduled: { registered.open() })
            let operation = Task {
                try await client.read(maximumBytes: 1,
                                      context: .init(clock: clock, deadline: clock.now.advanced(by: .seconds(1))))
            }
            try await registered.wait()
            try clock.advance(by: .seconds(1))
            do { _ = try await operation.value; Issue.record("Expected IPC read deadline") }
            catch { #expect(error as? TransportFailure == .deadlineExceeded) }
            #expect(clock.pendingSleepCount == 0)
            #expect(try await client.read(maximumBytes: 1, context: context()) == nil)
        }
    }
}

/// Deterministic byte-buffer branches independent of native fragmentation or timing.
@Suite struct UnixIPCInputTests {
    /// Confirms bounded admission, arbitrary read slices, EOF drain and explicit discard.
    /// - Throws: Unexpected mailbox read failures.
    @Test func budgetsSlicesAndEOF() async throws {
        let input = UnixIPCInput(maximumBytes: 3)
        #expect(input.offer(Data()))
        #expect(input.offer(Data([1, 2, 3])))
        #expect(!input.offer(Data([4])))
        #expect(try await input.read(maximumBytes: 1) == Data([1]))
        #expect(input.offer(Data([4])))
        input.finish(discard: false)
        #expect(!input.offer(Data([5])))
        #expect(try await input.read(maximumBytes: 8) == Data([2, 3, 4]))
        #expect(try await input.read(maximumBytes: 8) == nil)
        input.finish(discard: true)
        let discarded = UnixIPCInput(maximumBytes: 1)
        #expect(discarded.offer(Data([7])))
        discarded.finish(discard: false)
        discarded.finish(discard: true)
        #expect(try await discarded.read(maximumBytes: 1) == nil)
        let failed = UnixIPCInput(maximumBytes: 1)
        failed.finish(UnixIPCFailure.inputOverflow, discard: true)
        failed.finish(discard: true)
        await #expect(throws: UnixIPCFailure.inputOverflow) { try await failed.read(maximumBytes: 1) }
    }

    /// Duplicate rejection acts as a reader-registration barrier before direct delivery.
    /// - Throws: Unexpected mailbox failures.
    @Test func directDeliveryAndConcurrentReader() async throws {
        let input = UnixIPCInput(maximumBytes: 2)
        await withTaskGroup(of: Int.self) { group in
            for _ in 0..<2 {
                group.addTask {
                    do { return try await input.read(maximumBytes: 1) == Data([7]) ? 7 : 0 }
                    catch TransportFailure.concurrentRead { return 1 }
                    catch { return 2 }
                }
            }
            #expect(await group.next() == 1)
            #expect(input.offer(Data([7, 8])))
            #expect(await group.next() == 7)
        }
        #expect(try await input.read(maximumBytes: 8) == Data([8]))
        input.finish(discard: true)
    }
}
#endif
