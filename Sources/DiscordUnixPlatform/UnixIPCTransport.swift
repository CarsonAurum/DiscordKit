import DiscordLogging
#if !os(Windows) && !os(WASI)
import DiscordTransport
import Foundation
import NIOConcurrencyHelpers
import NIOCore
import NIOPosix

/// Fixed, redacted failures for native Unix-domain byte streams.
public enum UnixIPCFailure: Error, Equatable, Sendable {
    case invalidConfiguration
    case invalidPath
    case concurrentWrite
    case inputOverflow
    case ioFailure
}

/// A bounded Unix-domain socket client, independent of Discord RPC framing.
///
/// Each connection owns one event-loop thread and a bounded unread-byte buffer.
/// Writes are ordered by admission, with one active writer and no writer queue.
/// Reading never returns an empty chunk. Peer EOF preserves buffered bytes until
/// consumed; explicit close, overflow and cancellation discard them. This adapter
/// is compiled only for native non-Windows, non-WASI hosts. Windows named pipes
/// require their own qualified implementation and are not emulated by this type.
public final class UnixIPCTransport: IPCTransport, Sendable {
    private let channel: any Channel
    private let input: UnixIPCInput
    private let lifetime: UnixIPCLifetime
    private let slot: UnixIPCChannelSlot
    private let maximumWriteBytes: Int
    private let writing = NIOLockedValueBox(false)

    /// Transfers a successfully connected socket and its cleanup ownership.
    /// - Parameters:
    ///   - channel: Connected local byte-stream channel.
    ///   - input: Bounded single-reader buffer installed before connection.
    ///   - lifetime: Exactly-once channel and event-loop cleanup coordinator.
    ///   - slot: Shared native-submission and terminal-cancellation gate.
    ///   - maximumWriteBytes: Validated positive bound for one admitted write.
    private init(channel: any Channel, input: UnixIPCInput,
                 lifetime: UnixIPCLifetime, slot: UnixIPCChannelSlot, maximumWriteBytes: Int) {
        self.channel = channel
        self.input = input
        self.lifetime = lifetime
        self.slot = slot
        self.maximumWriteBytes = maximumWriteBytes
    }

    /// Opens a native Unix socket at an explicit absolute filesystem path.
    ///
    /// The caller selects the path and owns host/path authorization. No discovery,
    /// file creation, Discord handshake, retries, or fallback to TCP occurs. Paths
    /// are never retained in diagnostics. Cancellation during connect closes any
    /// published socket and awaits event-loop cleanup before returning.
    /// - Parameters:
    ///   - path: Absolute nonempty path without NUL; host socket-path limits apply.
    ///   - maximumBufferedBytes: Positive unread-byte budget, default 1 MiB.
    ///   - maximumWriteBytes: Positive per-write bound, default 1 MiB.
    ///   - context: Monotonic clock, optional deadline, and task cancellation.
    /// - Returns: A connected local stream whose owner must eventually close it.
    /// - Throws: Invalid limits/path, cancellation, expiration, or redacted local I/O failure.
    public static func connect<C: Clock>(
        path: String,
        maximumBufferedBytes: Int = 1_048_576,
        maximumWriteBytes: Int = 1_048_576,
        context: TransportContext<C>
    ) async throws -> UnixIPCTransport where C.Duration == Duration {
        DiscordLog.makeLogger("unix.ipc").trace("Starting Unix IPC connection", metadata: ["dk.event": "unix.ipc.connect"])
        try context.check()
        guard maximumBufferedBytes > 0, maximumWriteBytes > 0 else {
            throw UnixIPCFailure.invalidConfiguration
        }
        guard path.hasPrefix("/"), !path.utf8.contains(0) else { throw UnixIPCFailure.invalidPath }
        do { _ = try SocketAddress(unixDomainSocketPath: path) }
        catch { throw UnixIPCFailure.invalidPath }
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let slot = UnixIPCChannelSlot()
        let input = UnixIPCInput(maximumBytes: maximumBufferedBytes)
        let lifetime = UnixIPCLifetime(group: group, slot: slot)
        do {
            return try await context.run {
                try await withTaskCancellationHandler {
                    let channel = try await ClientBootstrap(group: group)
                        .channelOption(ChannelOptions.recvAllocator, value:
                                       FixedSizeRecvByteBufferAllocator(capacity: min(maximumBufferedBytes, 65_536)))
                        .channelInitializer { channel in
                            slot.install(channel)
                            return channel.eventLoop.makeCompletedFuture {
                                try channel.pipeline.syncOperations.addHandler(UnixIPCHandler(input: input))
                            }
                        }.connect(unixDomainSocketPath: path).get()
                    try Task.checkCancellation()
                    DiscordLog.makeLogger("unix.ipc").info("Unix IPC connected", metadata: ["dk.event": "unix.ipc.connected"])
                    return UnixIPCTransport(channel: channel, input: input, lifetime: lifetime, slot: slot,
                                            maximumWriteBytes: maximumWriteBytes)
                } onCancel: {
                    input.finish(discard: true)
                    slot.terminate()
                }
            }
        } catch {
            input.finish(discard: true)
            await lifetime.close()
            DiscordLog.makeLogger("unix.ipc").debug("Unix IPC connection failed", metadata: ["dk.event": "unix.ipc.failed"])
            throw unixIPCRedacted(error)
        }
    }

    /// Writes one bounded byte chunk once, preserving admitted-write ordering.
    ///
    /// Empty writes succeed on an open socket without adding bytes. A concurrent
    /// writer fails immediately, bounding queued bytes and avoiding hidden tasks.
    /// Once admitted, cancellation/deadline failure closes the entire stream;
    /// bytes already transmitted cannot be retracted and are never replayed.
    /// - Parameters:
    ///   - bytes: Complete chunk, at most `maximumWriteBytes` configured at connect.
    ///   - context: Clock/deadline and cancellation for admission and native completion.
    /// - Throws: Excessive size, concurrent write, closure, cancellation, expiration,
    ///   or redacted socket failure.
    public func write<C: Clock>(_ bytes: Data, context: TransportContext<C>) async throws
        where C.Duration == Duration {
        try context.check()
        guard bytes.count <= maximumWriteBytes else {
            throw TransportFailure.chunkTooLarge(limit: maximumWriteBytes, actual: bytes.count)
        }
        guard writing.withLockedValue({ value in if value { return false }; value = true; return true })
        else { throw UnixIPCFailure.concurrentWrite }
        defer { writing.withLockedValue { $0 = false } }
        DiscordLog.makeLogger("unix.ipc.write").trace("Unix IPC write admitted", metadata: ["dk.event": "unix.ipc.write.admitted", "dk.bytes": .stringConvertible(bytes.count)])
        do {
            try await context.run { [self] in
                try await withTaskCancellationHandler {
                    guard channel.isActive else { throw TransportFailure.closed }
                    try await slot.whileOpen { channel in
                        channel.writeAndFlush(channel.allocator.buffer(bytes: bytes))
                    }
                } onCancel: {
                    input.finish(discard: true)
                    slot.terminate()
                }
            }
            DiscordLog.makeLogger("unix.ipc.write").trace("Unix IPC write completed", metadata: ["dk.event": "unix.ipc.write.completed", "dk.bytes": .stringConvertible(bytes.count)])
        } catch {
            await close()
            throw unixIPCRedacted(error)
        }
    }

    /// Reads a nonempty chunk within the caller's positive upper bound.
    ///
    /// Stream fragmentation is arbitrary; writes need not correspond to reads.
    /// Exactly one read may remain active. Peer EOF drains already buffered bytes
    /// first, whereas explicit close discards them and wakes pending reads with EOF.
    /// - Parameters:
    ///   - maximumBytes: Positive maximum returned bytes; no allocation of this size occurs.
    ///   - context: Clock/deadline and cancellation for this read.
    /// - Returns: A nonempty bounded chunk, or `nil` at EOF/explicit close.
    /// - Throws: Invalid read limit, concurrent read, overflow, cancellation,
    ///   expiration, or redacted socket failure. Admitted failures close the socket.
    public func read<C: Clock>(maximumBytes: Int, context: TransportContext<C>) async throws -> Data?
        where C.Duration == Duration {
        try context.check()
        guard maximumBytes > 0 else { throw TransportFailure.invalidLimit }
        DiscordLog.makeLogger("unix.ipc.read").trace("Unix IPC read waiting", metadata: ["dk.event": "unix.ipc.read.wait", "dk.maximum_bytes": .stringConvertible(maximumBytes)])
        do {
            return try await context.run { [self] in
                try await withTaskCancellationHandler {
                    let bytes = try await input.read(maximumBytes: maximumBytes)
                    DiscordLog.makeLogger("unix.ipc.read").trace("Unix IPC read completed", metadata: ["dk.event": "unix.ipc.read.completed", "dk.bytes": .stringConvertible(bytes?.count ?? 0), "dk.eof": .stringConvertible(bytes == nil)])
                    return bytes
                } onCancel: {
                    input.finish(discard: true)
                    slot.terminate()
                }
            }
        } catch TransportFailure.concurrentRead {
            throw TransportFailure.concurrentRead
        } catch {
            await close()
            throw unixIPCRedacted(error)
        }
    }

    /// Discards unread input, wakes the reader, and awaits shared native cleanup.
    /// Concurrent and repeated close calls release channel/group ownership once.
    public func close() async {
        input.finish(discard: true)
        await lifetime.close()
        DiscordLog.makeLogger("unix.ipc").info("Unix IPC transport closed", metadata: ["dk.event": "unix.ipc.closed"])
    }
}

/// Bridges synchronous socket events to one async reader using bounded locked state.
final class UnixIPCInput: Sendable {
    /// All mutable byte and continuation ownership is confined to one lock.
    private struct State: Sendable {
        var bytes = Data()
        var closed = false
        var discarded = false
        var failure: (any Error)?
        var reading = false
        var waiter: (Int, CheckedContinuation<Data?, any Error>)?
    }
    private let state = NIOLockedValueBox(State())
    private let maximumBytes: Int

    /// Stores a validated positive unread-byte budget.
    /// - Parameter maximumBytes: Maximum retained bytes across incoming chunks.
    init(maximumBytes: Int) { self.maximumBytes = maximumBytes }

    /// Admits a received chunk, delivering directly when a reader is waiting.
    /// - Parameter bytes: Native received bytes; empty chunks are ignored.
    /// - Returns: Whether admitted; `false` requires the owner to close for overflow.
    func offer(_ bytes: Data) -> Bool {
        guard !bytes.isEmpty else { return true }
        var completion: (CheckedContinuation<Data?, any Error>, Data)?
        let accepted = state.withLockedValue { value in
            guard !value.closed, bytes.count <= maximumBytes - value.bytes.count else { return false }
            value.bytes.append(bytes)
            if let (limit, waiter) = value.waiter {
                let chunk = Data(value.bytes.prefix(limit))
                value.bytes.removeFirst(chunk.count)
                value.waiter = nil
                completion = (waiter, chunk)
            }
            return true
        }
        if let (waiter, chunk) = completion { waiter.resume(returning: chunk) }
        return accepted
    }

    /// Reserves a read and returns buffered bytes or suspends one continuation.
    /// Owner cancellation must call `finish` to interrupt a pending continuation.
    /// - Parameter maximumBytes: Validated positive output limit.
    /// - Returns: Nonempty input bytes, or `nil` after buffered EOF is exhausted.
    /// - Throws: Concurrent reader or the first terminal redacted error.
    func read(maximumBytes: Int) async throws -> Data? {
        let reserved = state.withLockedValue { value in
            if value.reading { return false }
            value.reading = true
            return true
        }
        guard reserved else { throw TransportFailure.concurrentRead }
        defer { state.withLockedValue { $0.reading = false } }
        let chunk: Data? = try await withCheckedThrowingContinuation { continuation in
            let result: Result<Data?, any Error>? = state.withLockedValue { value in
                if let failure = value.failure { return .failure(failure) }
                if !value.bytes.isEmpty {
                    let chunk = Data(value.bytes.prefix(maximumBytes))
                    value.bytes.removeFirst(chunk.count)
                    return .success(chunk)
                }
                if value.closed { return .success(nil) }
                value.waiter = (maximumBytes, continuation)
                return nil
            }
            if let result { continuation.resume(with: result) }
        }
        return try state.withLockedValue { value in
            if let failure = value.failure { throw failure }
            return value.discarded ? nil : chunk
        }
    }

    /// Reserves terminal state and wakes the active reader without per-chunk tasks.
    /// Explicit discard also releases bytes remaining after a previous peer EOF.
    /// - Parameters:
    ///   - error: First redacted terminal error, or `nil` for orderly EOF.
    ///   - discard: Whether buffered input must be discarded rather than drained.
    func finish(_ error: (any Error)? = nil, discard: Bool) {
        let waiter = state.withLockedValue { value -> CheckedContinuation<Data?, any Error>? in
            if discard { value.discarded = true; value.bytes.removeAll() }
            guard !value.closed else { return nil }
            value.closed = true
            value.failure = error
            let pending = value.waiter?.1
            value.waiter = nil
            return pending
        }
        if let error { waiter?.resume(throwing: error) }
        else { waiter?.resume(returning: nil) }
    }
}

/// Publishes the socket before connecting so cancellation cannot miss ownership.
private final class UnixIPCChannelSlot: Sendable {
    /// Lock-protected publication and sticky terminal reservation.
    private struct State: Sendable {
        var channel: (any Channel)?
        var closed = false
    }
    private let state = NIOLockedValueBox(State())

    /// Publishes a channel, closing immediately if cancellation won publication.
    /// - Parameter channel: Newly initialized Unix-domain socket.
    func install(_ channel: any Channel) {
        let closed = state.withLockedValue { value in value.channel = channel; return value.closed }
        if closed { channel.close(promise: nil) }
    }

    /// Reserves terminal ownership and synchronously initiates native close.
    /// Repeated calls do not schedule work onto an already stopped event loop.
    func terminate() {
        state.withLockedValue { value in
            guard !value.closed else { return }
            value.closed = true
            if let channel = value.channel {
                channel.eventLoop.execute { channel.close(promise: nil) }
            }
        }
    }

    /// Atomically admits native submission and registers its async completion.
    /// The terminal gate shares the same lock, so callers paused across shutdown
    /// never queue work or register future callbacks after the event loop stops.
    /// - Parameter operation: Nonblocking work run on the installed socket's loop;
    ///   terminal channel close must resolve the returned future.
    /// - Returns: The operation's unchanged result.
    /// - Throws: `TransportFailure.closed` after termination/before publication,
    ///   or a native failure later redacted at the public adapter boundary.
    func whileOpen<Value: Sendable>(
        _ operation: @escaping @Sendable (any Channel) -> EventLoopFuture<Value>
    ) async throws -> Value {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Value, any Error>) in
            state.withLockedValue { value in
                guard !value.closed, let channel = value.channel else {
                    continuation.resume(throwing: TransportFailure.closed)
                    return
                }
                channel.eventLoop.execute {
                    operation(channel).whenComplete { continuation.resume(with: $0) }
                }
            }
        }
    }

    /// Returns the published channel for awaited teardown.
    /// - Returns: Initialized socket, or `nil` before initializer publication.
    func installed() -> (any Channel)? { state.withLockedValue { $0.channel } }
}

/// Owns exactly one socket and native event-loop group through shared cleanup.
private actor UnixIPCLifetime {
    let group: MultiThreadedEventLoopGroup
    let slot: UnixIPCChannelSlot
    var cleanup: Task<Void, Never>?

    /// Transfers resource ownership to the cleanup coordinator.
    /// - Parameters:
    ///   - group: One-thread group owned exclusively by this connection attempt.
    ///   - slot: Early channel publication and cancellation reservation.
    init(group: MultiThreadedEventLoopGroup, slot: UnixIPCChannelSlot) {
        self.group = group
        self.slot = slot
    }

    /// Initiates close once and awaits channel destruction and group shutdown.
    /// Cleanup remains owned and awaited even when its initiating caller is cancelled.
    func close() async {
        if let cleanup { await cleanup.value; return }
        slot.terminate()
        let group = self.group
        let slot = self.slot
        let task = Task {
            if let channel = slot.installed() { try? await channel.closeFuture.get() }
            try? await group.shutdownGracefully()
        }
        cleanup = task
        await task.value
    }
}

/// Receives native stream chunks on one event loop without spawning message tasks.
private final class UnixIPCHandler: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer
    let input: UnixIPCInput

    /// Stores the bounded input coordinator before connection starts.
    /// - Parameter input: Single-reader mailbox shared with the public transport.
    init(input: UnixIPCInput) { self.input = input }

    /// Copies one native chunk within the aggregate unread-byte budget.
    /// - Parameters:
    ///   - context: Event-loop context used to close on overflow.
    ///   - data: Received bytes; stream message boundaries are deliberately absent.
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        if !input.offer(Data(unwrapInboundIn(data).readableBytesView)) {
            input.finish(UnixIPCFailure.inputOverflow, discard: true)
            context.close(promise: nil)
        }
    }

    /// Preserves buffered bytes at peer EOF before forwarding channel inactivity.
    /// - Parameter context: Closed native channel context.
    func channelInactive(context: ChannelHandlerContext) {
        input.finish(discard: false)
        context.fireChannelInactive()
    }

    /// Discards unread bytes after a redacted native failure and closes the socket.
    /// - Parameters:
    ///   - context: Channel context used for terminal close.
    ///   - error: Raw socket error intentionally excluded from public diagnostics.
    func errorCaught(context: ChannelHandlerContext, error: any Error) {
        input.finish(UnixIPCFailure.ioFailure, discard: true)
        context.close(promise: nil)
    }
}

/// Removes arbitrary local paths and native error strings from public failures.
/// - Parameter error: Original cancellation, contract, or socket failure.
/// - Returns: Preserved typed contract errors or a fixed redacted I/O failure.
private func unixIPCRedacted(_ error: any Error) -> any Error {
    if error is CancellationError || Task.isCancelled { return CancellationError() }
    if let error = error as? TransportFailure { return error }
    if let error = error as? UnixIPCFailure { return error }
    return UnixIPCFailure.ioFailure
}
#endif
