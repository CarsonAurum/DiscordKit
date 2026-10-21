import DiscordLogging
import DiscordTransport
import Foundation
import NIOConcurrencyHelpers
import NIOCore
import NIOPosix

/// Redacted failures shared by the bounded native listener and datagram adapters.
public enum NIOServiceFailure: Error, Equatable, Sendable {
    case invalidConfiguration
    case invalidAddress
    case queueOverflow
    case concurrentWrite
    case invalidHTTP
    case duplicateResponse
    case ioFailure
}

/// A native UDP socket preserving complete, including empty, datagrams.
///
/// Each socket owns one event-loop thread. Input is bounded by both message count
/// and byte count. Overflow and oversized input terminate the socket rather than
/// silently dropping or truncating a packet. Sends never retry, resolve DNS, or
/// promise delivery. Native OS limits can be lower than the configured protocol
/// limit; for example, the qualified macOS host limits UDP sends to 9,216 bytes.
/// Such sends fail with a redacted I/O error. Cancellation of an admitted operation
/// closes the socket.
public final class NIODatagramTransport: DatagramTransport, Sendable {
    public let localAddress: DatagramAddress
    private let channel: any Channel
    private let lifetime: NIOServiceLifetime
    private let slot: NIOServiceChannelSlot
    private let input: NIOServiceQueue<Datagram>
    private let maximumDatagramBytes: Int
    private let writing = NIOLockedValueBox(false)

    /// Stores a successfully bound socket; ownership is transferred by `bind`.
    /// - Parameters:
    ///   - channel: Bound native UDP channel with an installed input handler.
    ///   - lifetime: Exactly-once owner of the channel and its event-loop group.
    ///   - slot: Shared submission/cancellation gate closed before group shutdown.
    ///   - input: Bounded, single-reader datagram mailbox.
    ///   - maximumDatagramBytes: Validated maximum payload in bytes.
    ///   - localAddress: Numeric address assigned by the local operating system.
    private init(channel: any Channel, lifetime: NIOServiceLifetime, slot: NIOServiceChannelSlot,
                 input: NIOServiceQueue<Datagram>, maximumDatagramBytes: Int,
                 localAddress: DatagramAddress) {
        self.channel = channel
        self.lifetime = lifetime
        self.slot = slot
        self.input = input
        self.maximumDatagramBytes = maximumDatagramBytes
        self.localAddress = localAddress
    }

    /// Binds a literal IPv4/IPv6 address and allocates a bounded native UDP socket.
    ///
    /// DNS is deliberately excluded, keeping address resolution and its resource
    /// policy explicit above this adapter. Port zero requests an ephemeral port.
    /// Cancellation or deadline expiry during binding releases all owned resources.
    /// - Parameters:
    ///   - localAddress: Numeric local IP and port; defaults to loopback/ephemeral.
    ///   - maximumDatagramBytes: Payload admission limit, from 1 through 65,507
    ///     bytes; the operating system can impose a lower actual send limit.
    ///   - maximumPendingDatagrams: Positive number of complete queued packets.
    ///   - maximumPendingBytes: Positive total payload-byte limit for queued packets.
    ///   - context: Monotonic clock, optional deadline, and task cancellation.
    /// - Returns: A bound socket whose `localAddress` includes the assigned port.
    /// - Throws: Invalid limits/address, cancellation, expiration, or redacted I/O failure.
    public static func bind<C: Clock>(
        localAddress: DatagramAddress = .init(host: "127.0.0.1", port: 0),
        maximumDatagramBytes: Int = 65_507,
        maximumPendingDatagrams: Int = 64,
        maximumPendingBytes: Int = 1_048_576,
        context: TransportContext<C>
    ) async throws -> NIODatagramTransport where C.Duration == Duration {
        DiscordLog.makeLogger("nio.datagram").trace("Starting local datagram binding", metadata: ["dk.event": "nio.datagram.bind"])
        try context.check()
        guard (1...65_507).contains(maximumDatagramBytes), maximumPendingDatagrams > 0,
              maximumPendingBytes > 0 else { throw NIOServiceFailure.invalidConfiguration }
        let address: SocketAddress
        do { address = try SocketAddress(ipAddress: localAddress.host, port: Int(localAddress.port)) }
        catch { throw NIOServiceFailure.invalidAddress }
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let slot = NIOServiceChannelSlot()
        let lifetime = NIOServiceLifetime(group: group, slot: slot)
        let input = NIOServiceQueue<Datagram>(maximumCount: maximumPendingDatagrams,
                                             maximumBytes: maximumPendingBytes)
        do {
            return try await context.run {
                try await withTaskCancellationHandler {
                    let channel = try await DatagramBootstrap(group: group)
                        .channelOption(ChannelOptions.recvAllocator, value:
                                       FixedSizeRecvByteBufferAllocator(capacity: 65_536))
                        .channelInitializer { channel in
                            slot.install(channel)
                            return channel.eventLoop.makeCompletedFuture {
                                try channel.pipeline.syncOperations.addHandler(NIOServiceDatagramHandler(
                                    input: input, maximumDatagramBytes: maximumDatagramBytes))
                            }
                        }.bind(to: address).get()
                    try Task.checkCancellation()
                    guard let host = channel.localAddress?.ipAddress,
                          let port = channel.localAddress?.port, let wirePort = UInt16(exactly: port)
                    else { throw NIOServiceFailure.invalidAddress }
                    DiscordLog.makeLogger("nio.datagram").info("Local datagram bound", metadata: ["dk.event": "nio.datagram.bound"])
                    return NIODatagramTransport(channel: channel, lifetime: lifetime, slot: slot, input: input,
                                                maximumDatagramBytes: maximumDatagramBytes,
                                                localAddress: .init(host: host, port: wirePort))
                } onCancel: {
                    input.finish()
                    slot.terminate()
                }
            }
        } catch {
            input.finish()
            await lifetime.close()
            throw nioServiceRedacted(error)
        }
    }

    /// Sends exactly one complete packet to a numeric address, without retry.
    ///
    /// A second simultaneous writer fails immediately, bounding queued outbound
    /// bytes to one configured packet. Cancellation after admission terminates I/O.
    /// - Parameters:
    ///   - datagram: Complete payload, including zero bytes, and literal destination.
    ///   - context: Clock and optional deadline for this operation.
    /// - Throws: Oversized input, concurrent write, invalid address, cancellation,
    ///   expiration, closure, or redacted socket failure.
    public func sendDatagram<C: Clock>(_ datagram: Datagram, context: TransportContext<C>) async throws
        where C.Duration == Duration {
        try context.check()
        guard datagram.bytes.count <= maximumDatagramBytes else {
            throw TransportFailure.chunkTooLarge(limit: maximumDatagramBytes, actual: datagram.bytes.count)
        }
        let destination: SocketAddress
        do { destination = try SocketAddress(ipAddress: datagram.peer.host, port: Int(datagram.peer.port)) }
        catch { throw NIOServiceFailure.invalidAddress }
        guard writing.withLockedValue({ value in if value { return false }; value = true; return true })
        else { throw NIOServiceFailure.concurrentWrite }
        defer { writing.withLockedValue { $0 = false } }
        do {
            try await context.run { [self] in
                try await withTaskCancellationHandler {
                    guard channel.isActive else { throw TransportFailure.closed }
                    try await slot.whileOpen { channel in
                        let buffer = channel.allocator.buffer(bytes: datagram.bytes)
                        return channel.writeAndFlush(AddressedEnvelope(remoteAddress: destination, data: buffer))
                    }
                } onCancel: {
                    input.finish()
                    slot.terminate()
                }
            }
        } catch {
            await close()
            throw nioServiceRedacted(error)
        }
    }

    /// Receives one complete queued packet; closed sockets return `nil`.
    /// - Parameter context: Clock/deadline and cancellation for the single reader.
    /// - Returns: A complete packet retaining its numeric sender, or `nil` after close.
    /// - Throws: Concurrent read, queue overflow, excessive packet size, cancellation,
    ///   expiration, or redacted I/O failure. Admitted operation failure closes the socket.
    public func receiveDatagram<C: Clock>(context: TransportContext<C>) async throws -> Datagram?
        where C.Duration == Duration {
        try context.check()
        do {
            return try await context.run { [self] in
                try await withTaskCancellationHandler {
                    try await input.next()
                } onCancel: {
                    input.finish()
                    slot.terminate()
                }
            }
        } catch TransportFailure.concurrentRead {
            throw TransportFailure.concurrentRead
        } catch {
            await close()
            throw nioServiceRedacted(error)
        }
    }

    /// Discards pending datagrams and awaits one shared socket/group cleanup.
    /// Pending receives unblock with `nil`; repeated and concurrent calls are safe.
    public func close() async {
        input.finish()
        await lifetime.close()
        DiscordLog.makeLogger("nio.datagram").info("Local datagram transport closed", metadata: ["dk.event": "nio.datagram.closed"])
    }
}

/// Synchronously bridges NIO event-loop callbacks into one bounded async reader.
/// All mutable storage is protected by NIO's checked Sendable lock container;
/// continuations are resumed outside the lock and no per-message tasks are created.
final class NIOServiceQueue<Element: Sendable>: Sendable {
    /// Storage accessed only while the enclosing lock is held.
    private struct State: Sendable {
        var values: [(Element, Int)] = []
        var bytes = 0
        var reading = false
        var closed = false
        var failure: (any Error)?
        var waiter: CheckedContinuation<Element?, any Error>?
    }
    private let state = NIOLockedValueBox(State())
    private let maximumCount: Int
    private let maximumBytes: Int

    /// Stores validated positive queue budgets without allocating payload buffers.
    /// - Parameters:
    ///   - maximumCount: Maximum retained element count, including empty packets.
    ///   - maximumBytes: Maximum retained payload bytes.
    init(maximumCount: Int, maximumBytes: Int) {
        self.maximumCount = maximumCount
        self.maximumBytes = maximumBytes
    }

    /// Delivers directly to a waiting reader or appends within both queue limits.
    /// - Parameters:
    ///   - element: Value whose ownership transfers only when admitted.
    ///   - bytes: Nonnegative payload size used for aggregate byte admission.
    /// - Returns: Whether accepted; `false` means closed or overflowed and caller
    ///   must release any resources owned by the rejected value.
    func offer(_ element: Element, bytes: Int) -> Bool {
        var waiter: CheckedContinuation<Element?, any Error>?
        let accepted = state.withLockedValue { value in
            guard !value.closed else { return false }
            if let pending = value.waiter {
                waiter = pending
                value.waiter = nil
                return true
            }
            guard value.values.count < maximumCount, bytes <= maximumBytes - value.bytes else { return false }
            value.values.append((element, bytes))
            value.bytes += bytes
            return true
        }
        waiter?.resume(returning: element)
        return accepted
    }

    /// Reserves a single read and suspends without allocating additional waiters.
    /// Cancellation must be bridged by the owning adapter through `finish`.
    /// - Returns: The next value, or `nil` after orderly closure.
    /// - Throws: Concurrent read or the original terminal, redacted adapter error.
    func next() async throws -> Element? {
        let reserved = state.withLockedValue { value in
            if value.reading { return false }
            value.reading = true
            return true
        }
        guard reserved else { throw TransportFailure.concurrentRead }
        defer { state.withLockedValue { $0.reading = false } }
        let element: Element? = try await withCheckedThrowingContinuation { continuation in
            let result: Result<Element?, any Error>? = state.withLockedValue { value in
                if let failure = value.failure { return .failure(failure) }
                if value.closed { return .success(nil) }
                if !value.values.isEmpty {
                    let first = value.values.removeFirst()
                    value.bytes -= first.1
                    return .success(first.0)
                }
                value.waiter = continuation
                return nil
            }
            if let result { continuation.resume(with: result) }
        }
        return try state.withLockedValue { value in
            if let failure = value.failure { throw failure }
            return value.closed ? nil : element
        }
    }

    /// Reserves termination, discards buffered values, and wakes the sole reader.
    /// The first termination wins; later calls cannot replace its failure reason.
    /// - Parameter error: Redacted failure, or `nil` for orderly end of input.
    func finish(_ error: (any Error)? = nil) {
        let waiter = state.withLockedValue { value -> CheckedContinuation<Element?, any Error>? in
            guard !value.closed else { return nil }
            value.closed = true
            value.failure = error
            value.values.removeAll()
            value.bytes = 0
            let pending = value.waiter
            value.waiter = nil
            return pending
        }
        if let error { waiter?.resume(throwing: error) }
        else { waiter?.resume(returning: nil) }
    }
}

/// A lock-protected channel reservation covering cancellation during bootstrap.
final class NIOServiceChannelSlot: Sendable {
    /// Stores the one installed channel and a sticky cancellation/close reservation.
    private struct State: Sendable {
        var channel: (any Channel)?
        var closed = false
    }
    private let state = NIOLockedValueBox(State())

    /// Installs a bootstrap channel or closes it immediately after a cancellation race.
    /// - Parameter channel: Newly created socket, before binding/connection completes.
    func install(_ channel: any Channel) {
        let close = state.withLockedValue { value in
            value.channel = channel
            return value.closed
        }
        if close { channel.close(promise: nil) }
    }

    /// Reserves closure synchronously and interrupts pending NIO future waits.
    /// Later calls do not schedule native work, including after group shutdown.
    func terminate() {
        state.withLockedValue { value in
            guard !value.closed else { return }
            value.closed = true
            if let channel = value.channel {
                channel.eventLoop.execute { channel.close(promise: nil) }
            }
        }
    }

    /// Queues a native operation and attaches its completion before terminal close.
    /// Submission and terminal admission share one lock, so no callback registration
    /// targets a stopped event loop even when the caller resumes after shutdown.
    /// - Parameter operation: Nonblocking event-loop operation; channel close must
    ///   resolve its returned future. No unbounded task or waiter queue is introduced.
    /// - Returns: Original native operation result.
    /// - Throws: `TransportFailure.closed` after termination/before installation,
    ///   or the operation's native failure for sanitization by the adapter boundary.
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

    /// Returns the currently installed socket for awaited cleanup.
    /// - Returns: The channel if bootstrap has reached its initializer, otherwise `nil`.
    func installed() -> (any Channel)? { state.withLockedValue { $0.channel } }
}

/// Owns an isolated event-loop group and awaits exactly one cleanup task.
actor NIOServiceLifetime {
    private let group: MultiThreadedEventLoopGroup
    private let slot: NIOServiceChannelSlot
    private var cleanup: Task<Void, Never>?

    /// Transfers group ownership without starting socket work.
    /// - Parameters:
    ///   - group: Owned native group, never a process singleton.
    ///   - slot: Channel publication and early-cancellation reservation.
    init(group: MultiThreadedEventLoopGroup, slot: NIOServiceChannelSlot) {
        self.group = group
        self.slot = slot
    }

    /// Reserves cleanup before suspension; all callers await the same completion.
    /// NIO close errors during already-closed cleanup are intentionally ignored.
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

/// Maps socket errors to fixed diagnostic values without retaining peer addresses.
/// - Parameter error: Original infrastructure, deadline, or cancellation failure.
/// - Returns: A contract failure preserved verbatim, otherwise a redacted I/O failure.
func nioServiceRedacted(_ error: any Error) -> any Error {
    if error is CancellationError || Task.isCancelled { return CancellationError() }
    if let error = error as? TransportFailure { return error }
    if let error = error as? NIOServiceFailure { return error }
    return NIOServiceFailure.ioFailure
}

/// Converts complete UDP envelopes into the bounded mailbox on the socket event loop.
private final class NIOServiceDatagramHandler: ChannelInboundHandler {
    typealias InboundIn = AddressedEnvelope<ByteBuffer>
    private let input: NIOServiceQueue<Datagram>
    private let maximumDatagramBytes: Int

    /// Retains immutable admission limits and the shared mailbox.
    /// - Parameters:
    ///   - input: Destination for complete received datagrams.
    ///   - maximumDatagramBytes: Maximum accepted payload bytes.
    init(input: NIOServiceQueue<Datagram>, maximumDatagramBytes: Int) {
        self.input = input
        self.maximumDatagramBytes = maximumDatagramBytes
    }

    /// Enqueues one whole datagram, rejecting excess size and aggregate overflow.
    /// - Parameters:
    ///   - context: Socket event-loop context used for terminal close.
    ///   - data: One addressed envelope, including valid zero-byte payloads.
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let envelope = unwrapInboundIn(data)
        let count = envelope.data.readableBytes
        guard count <= maximumDatagramBytes else {
            input.finish(TransportFailure.chunkTooLarge(limit: maximumDatagramBytes, actual: count))
            context.close(promise: nil)
            return
        }
        guard let host = envelope.remoteAddress.ipAddress, let port = envelope.remoteAddress.port,
              let wirePort = UInt16(exactly: port) else {
            input.finish(NIOServiceFailure.invalidAddress)
            context.close(promise: nil)
            return
        }
        let datagram = Datagram(bytes: Data(envelope.data.readableBytesView), peer: .init(host: host, port: wirePort))
        if !input.offer(datagram, bytes: count) {
            input.finish(NIOServiceFailure.queueOverflow)
            context.close(promise: nil)
        }
    }

    /// Ends pending receives when the operating system closes the socket.
    /// - Parameter context: Closed channel context forwarded through the pipeline.
    func channelInactive(context: ChannelHandlerContext) {
        input.finish()
        context.fireChannelInactive()
    }

    /// Publishes a redacted socket failure and closes the native socket.
    /// - Parameters:
    ///   - context: Event-loop context used for closure.
    ///   - error: Raw error deliberately excluded from public diagnostics.
    func errorCaught(context: ChannelHandlerContext, error: any Error) {
        input.finish(NIOServiceFailure.ioFailure)
        context.close(promise: nil)
    }
}
