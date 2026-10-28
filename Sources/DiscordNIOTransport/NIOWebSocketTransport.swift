// File: Sources/DiscordNIOTransport/NIOWebSocketTransport.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordLogging
import Foundation
import DiscordTransport
import NIOCore
import NIOPosix
import NIOHTTP1
import NIOWebSocket
import NIOConcurrencyHelpers
import NIOSSL

/// Explicit WebSocket budgets; control frames are handled independently of reads.
public struct NIOWebSocketConfiguration: Sendable {
    public let maximumConnections: Int
    public let maximumMessageBytes: Int
    public let maximumBufferedMessages: Int
    public let maximumPendingWrites: Int
    public let maximumHeaderBytes: Int

    /// Validates limits without starting network activity.
    /// - Parameters:
    ///   - maximumConnections: Positive total established plus connecting sockets; default 32.
    ///   - maximumMessageBytes: Positive limit for a complete fragmented message and
    ///     individual frame; default 1 MiB, at most UInt32.max per RFC/NIO framing.
    ///   - maximumBufferedMessages: Positive receive-queue count; default 8. Total
    ///     buffered payload bytes are also capped at maximumMessageBytes. Overflow
    ///     closes the connection rather than stalling ping/pong behind consumers.
    ///   - maximumPendingWrites: Positive concurrent application-send reservations
    ///     and, independently, outstanding pong replies; default 8 for each class.
    ///     Reservations above either bound fail immediately. Application payloads
    ///     share `maximumMessageBytes`; each pong is at most 125 bytes. One close
    ///     reply may additionally be outstanding when the connection terminates.
    ///   - maximumHeaderBytes: Positive HTTP upgrade field-byte limit, default 32 KiB.
    /// - Throws: `TransportFailure.invalidLimit` for any invalid budget.
    public init(maximumConnections: Int = 32, maximumMessageBytes: Int = 1_048_576,
                maximumBufferedMessages: Int = 8, maximumPendingWrites: Int = 8,
                maximumHeaderBytes: Int = 32_768) throws {
        guard maximumConnections > 0, maximumMessageBytes > 0,
              maximumMessageBytes <= UInt32.max, maximumBufferedMessages > 0,
              maximumPendingWrites > 0, maximumHeaderBytes > 0 else { throw TransportFailure.invalidLimit }
        self.maximumConnections = maximumConnections
        self.maximumMessageBytes = maximumMessageBytes
        self.maximumBufferedMessages = maximumBufferedMessages
        self.maximumPendingWrites = maximumPendingWrites
        self.maximumHeaderBytes = maximumHeaderBytes
    }
}

/// Owned RFC 6455 client upgrade/framing without Gateway, compression or retries.
/// A bounded receive queue allows ping/pong while application handlers are stalled.
/// Overload is a terminal error, never silent loss. Close the transport to release
/// its event loop; a fresh transport implements explicit network replacement.
public actor NIOWebSocketTransport: WebSocketTransport, TransportResource {
    private let configuration: NIOWebSocketConfiguration
    private let tls: TLSPolicy
    private let group: MultiThreadedEventLoopGroup
    private var attempts: [UUID: NIOConnectionAttempt] = [:]
    private var wires: [UUID: WebSocketWire] = [:]
    private var connecting: [UUID: Task<WebSocketWire, any Error>] = [:]
    private var closed = false
    private var cleanup: Task<Void, Never>?

    /// Creates one owned event-loop thread and full-verification TLS context.
    /// - Parameters:
    ///   - configuration: Explicit connection, message, queue and header limits.
    ///   - tls: Optional explicit private-PKI trust policy; nil uses system roots.
    /// - Throws: Redacted TLS initialization errors; no sockets are opened.
    public init(configuration: NIOWebSocketConfiguration, tls: TLSPolicy? = nil) throws {
        self.configuration = configuration
        self.tls = try tls ?? TLSPolicy()
        group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    }

    /// Opens one ws/wss connection with a validated RFC 6455 handshake.
    /// - Parameters:
    ///   - request: GET upgrade URL, no body, and ordered headers. Host, Connection,
    ///     Upgrade, Sec-WebSocket-* and HTTP framing fields are adapter-owned.
    ///   - context: Deadline/cancellation for connect and upgrade only; each returned
    ///     connection operation has its own context. Failed upgrades never redirect.
    ///     Connecting work is owned and drained before parent event-loop shutdown.
    /// - Returns: Caller-owned connection, sharing this transport's aggregate budget.
    /// - Throws: Invalid request, overload, cancellation/deadline, rejected upgrade,
    ///   invalid TLS trust/hostname or redacted transport error. No request is replayed.
    public func connectWebSocket<C: Clock>(_ request: HTTPRequest, context: TransportContext<C>) async throws
    -> any WebSocketConnection where C.Duration == Duration {
        DiscordLog.makeLogger("nio.websocket").trace("Starting NIO WebSocket connection", metadata: ["dk.event": "nio.websocket.connect"])
        var id: UUID?
        var operation: Task<WebSocketWire, any Error>?
        do {
            try context.check()
            let target = try NIORequestTarget(request, webSocket: true, headerLimit: configuration.maximumHeaderBytes)
            guard !closed else { throw TransportFailure.closed }
            guard attempts.count < configuration.maximumConnections else { throw NIOAdapterFailure.capacityExceeded }
            let token = UUID(); id = token
            let attempt = NIOConnectionAttempt(); attempts[token] = attempt
            let task = Task { [self] in
                try await context.run {
                    try await withTaskCancellationHandler {
                        try await self.open(request, target: target, attempt: attempt)
                    } onCancel: { attempt.cancel() }
                }
            }
            operation = task
            connecting[token] = task
            let wire = try await withTaskCancellationHandler { try await task.value } onCancel: {
                task.cancel()
                attempt.cancel()
            }
            try context.check()
            guard !closed else { throw TransportFailure.closed }
            wires[token] = wire
            connecting.removeValue(forKey: token)
            DiscordLog.makeLogger("nio.websocket").info("NIO WebSocket connected", metadata: ["dk.event": "nio.websocket.connected"])
            return NIOWebSocketConnection(wire: wire, configuration: configuration, attempt: attempt,
                                          release: { await self.release(token) })
        } catch {
            if let id { attempts[id]?.cancel() }
            operation?.cancel()
            if let operation, let wire = try? await operation.value { await wire.close() }
            if let id {
                attempts.removeValue(forKey: id)
                connecting.removeValue(forKey: id)
            }
            if let body = request.body { await body.close() }
            DiscordLog.makeLogger("nio.websocket").debug("NIO WebSocket connection failed", metadata: ["dk.event": "nio.websocket.failed"])
            throw nioWebSocketError(error)
        }
    }

    /// Returns currently reserved connecting/established connection slots.
    /// - Returns: Bounded count; closed peers release slots when their owner closes.
    public func connectionCount() -> Int { attempts.count }

    /// Closes every live/connecting socket, discards retained frame payloads and then
    /// awaits the owned event-loop shutdown. Upgraded wires share the bounded attempt
    /// registry; they are cleared before shutdown even when callers retain connections.
    /// Repeated calls await one cleanup task. Connections become terminal and cannot
    /// migrate implicitly; upstream Gateway code will decide reconnect/resume policy.
    public func close() async {
        if let cleanup { await cleanup.value; return }
        closed = true
        let attempts = Array(attempts.values); self.attempts.removeAll()
        let wires = Array(wires.values); self.wires.removeAll()
        let connecting = Array(connecting.values); self.connecting.removeAll()
        let group = self.group
        let task = Task {
            for attempt in attempts { attempt.cancel() }
            for operation in connecting { operation.cancel() }
            for operation in connecting {
                if let wire = try? await operation.value { await wire.close() }
            }
            for wire in wires { await wire.close() }
            try? await group.shutdownGracefully()
        }
        cleanup = task; await task.value
        DiscordLog.makeLogger("nio.websocket").info("NIO WebSocket transport closed", metadata: ["dk.event": "nio.websocket.closed"])
    }

    /// Removes one caller-owned slot and its wire after connection cleanup completes.
    /// - Parameter id: Unique connection reservation; repeated release is harmless.
    private func release(_ id: UUID) {
        attempts.removeValue(forKey: id)
        wires.removeValue(forKey: id)
    }

    /// Constructs HTTP upgrade handlers and transfers to message parsing on success.
    /// The bodyless GET head and end are queued before the first flush: flushing the
    /// head separately lets a fast peer begin protocol upgrade before the pending HTTP end.
    /// - Parameters:
    ///   - request: Validated application headers and GET method.
    ///   - target: SNI origin and origin-form path/query.
    ///   - attempt: Cancellation latch registered before connect can suspend.
    /// - Returns: Upgraded socket and its event-loop-confined frame state.
    /// - Throws: Native connect/upgrade/TLS errors sanitized at the public boundary.
    private func open(_ request: HTTPRequest, target: NIORequestTarget,
                      attempt: NIOConnectionAttempt) async throws -> WebSocketWire {
        let configuration = self.configuration
        let tls = self.tls
        let promise = group.next().makePromise(of: WebSocketWire.self)
        let completion = WebSocketUpgradeCompletion(promise)
        let bootstrap = ClientBootstrap(group: group)
            .connectTimeout(.seconds(10))
            .channelOption(ChannelOptions.maxMessagesPerRead, value: 1)
            .channelOption(ChannelOptions.recvAllocator, value: FixedSizeRecvByteBufferAllocator(capacity: 16_384))
            .channelInitializer { channel in
                attempt.install(channel)
                return channel.eventLoop.makeCompletedFuture {
                    if target.secure {
                        try channel.pipeline.syncOperations.addHandler(NIOSSLClientHandler(context: tls.context, serverHostname: target.host))
                    }
                    let observer = WebSocketUpgradeObserver(completion: completion)
                    let boundObserver = NIOLoopBound(observer, eventLoop: channel.eventLoop)
                    let upgrader = NIOWebSocketClientUpgrader(maxFrameSize: configuration.maximumMessageBytes) { channel, response in
                        channel.eventLoop.makeCompletedFuture {
                            guard !response.headers.contains(name: "Sec-WebSocket-Extensions"),
                                  !response.headers.contains(name: "Sec-WebSocket-Protocol") else {
                                completion.fail(NIOAdapterFailure.upgradeRejected)
                                channel.close(promise: nil)
                                throw NIOAdapterFailure.upgradeRejected
                            }
                            _ = channel.pipeline.syncOperations.removeHandler(boundObserver.value)
                            let handler = WebSocketWireHandler(configuration: configuration)
                            try channel.pipeline.syncOperations.addHandler(handler)
                            completion.succeed(WebSocketWire(channel: channel, handler: NIOLoopBound(handler, eventLoop: channel.eventLoop), attempt: attempt, peerCode: handler.peerCode))
                        }
                    }
                    var limits = NIOHTTPDecoderLimitConfiguration()
                    limits.maxHeaderFieldSize = configuration.maximumHeaderBytes
                    limits.maxHeaderListSize = configuration.maximumHeaderBytes
                    limits.maxHeaderFieldCount = min(1024, configuration.maximumHeaderBytes)
                    try channel.pipeline.syncOperations.addHTTPClientHandlers(
                        leftOverBytesStrategy: .forwardBytes, decoderLimitConfiguration: limits,
                        withClientUpgrade: ([upgrader], { _ in }))
                    try channel.pipeline.syncOperations.addHandler(observer)
                }
            }
        do {
            let channel = try await bootstrap.connect(host: target.host, port: target.port).get()
            var headers = HTTPHeaders(request.headers.map { ($0.name, $0.value) })
            headers.add(name: "Host", value: target.hostHeader)
            let head = HTTPRequestHead(version: .http1_1, method: .GET, uri: target.path, headers: headers)
            channel.write(HTTPClientRequestPart.head(head), promise: nil)
            try await channel.writeAndFlush(HTTPClientRequestPart.end(nil)).get()
            return try await promise.futureResult.get()
        } catch { completion.fail(NIOAdapterFailure.upgradeRejected); attempt.cancel(); throw error }
    }
}

/// One complete-message socket with bounded, ordered event-loop writes.
private actor NIOWebSocketConnection: WebSocketSessionConnection {
    private let wire: WebSocketWire
    private let configuration: NIOWebSocketConfiguration
    private let attempt: NIOConnectionAttempt
    private let release: @Sendable () async -> Void
    private var closed = false
    private var writes = 0
    private var writeBytes = 0
    private var cleanup: Task<Void, Never>?

    /// Takes ownership only after a validated upgrade.
    /// - Parameters:
    ///   - wire: Upgraded channel and frame parser.
    ///   - configuration: Immutable payload and pending-write budgets.
    ///   - attempt: Shared shutdown/cancellation latch.
    ///   - release: Removes the parent transport's slot after socket close.
    init(wire: WebSocketWire, configuration: NIOWebSocketConfiguration,
         attempt: NIOConnectionAttempt, release: @escaping @Sendable () async -> Void) {
        self.wire = wire; self.configuration = configuration; self.attempt = attempt; self.release = release
    }

    /// Reserves count/bytes before suspension and enqueues one masked frame in order.
    /// - Parameters:
    ///   - message: UTF-8 text or arbitrary binary data within complete-message limits.
    ///   - context: Admission/write deadline. Cancellation terminates this connection.
    /// - Throws: Closed, oversized/capacity, cancellation/deadline or transport failure.
    func send<C: Clock>(_ message: WebSocketMessage, context: TransportContext<C>) async throws
    where C.Duration == Duration {
        try context.check()
        guard !closed else { throw TransportFailure.closed }
        let bytes: Data; let opcode: WebSocketOpcode
        switch message {
        case .text(let value):
            guard value.utf8.count <= configuration.maximumMessageBytes else { throw NIOAdapterFailure.messageTooLarge }
            bytes = Data(value.utf8); opcode = .text
        case .binary(let value): bytes = value; opcode = .binary
        }
        guard bytes.count <= configuration.maximumMessageBytes else { throw NIOAdapterFailure.messageTooLarge }
        guard writes < configuration.maximumPendingWrites,
              bytes.count <= configuration.maximumMessageBytes - writeBytes else { throw NIOAdapterFailure.capacityExceeded }
        writes += 1; writeBytes += bytes.count
        DiscordLog.makeLogger("nio.websocket.write").trace("NIO WebSocket message admitted", metadata: ["dk.event": "nio.websocket.send.admitted", "dk.bytes": .stringConvertible(bytes.count), "dk.pending": .stringConvertible(writes)])
        defer { writes -= 1; writeBytes -= bytes.count }
        do {
            let wire = self.wire; let attempt = self.attempt
            try await context.run {
                try await withTaskCancellationHandler {
                    try await wire.sendFrame(bytes, opcode: opcode)
                    DiscordLog.makeLogger("nio.websocket.write").trace("NIO WebSocket message sent", metadata: ["dk.event": "nio.websocket.send.completed", "dk.bytes": .stringConvertible(bytes.count)])
                } onCancel: { attempt.cancel() }
            }
        } catch { await close(); throw nioWebSocketError(error) }
    }

    /// Pulls one complete message; frame control work continues without a reader.
    /// - Parameter context: Deadline and cancellation for this one receive operation.
    /// - Returns: Next ordered message, or nil after valid close handshake/EOF or
    ///   explicit owner close, including a receive already pending during that close.
    /// - Throws: Concurrent read, queue/message limits, malformed frames, deadline,
    ///   cancellation or socket failure. Terminal failures close the owned socket.
    func receive<C: Clock>(context: TransportContext<C>) async throws -> WebSocketMessage?
    where C.Duration == Duration {
        try context.check()
        guard !closed else { return nil }
        DiscordLog.makeLogger("nio.websocket.read").trace("NIO WebSocket receive waiting", metadata: ["dk.event": "nio.websocket.receive.wait"])
        let wire = self.wire; let attempt = self.attempt
        do {
            let message = try await context.run {
                try await withTaskCancellationHandler { try await wire.next() } onCancel: { attempt.cancel() }
            }
            guard !closed else { return nil }
            if message == nil { await close() }
            DiscordLog.makeLogger("nio.websocket.read").trace("NIO WebSocket receive completed", metadata: ["dk.event": "nio.websocket.receive.completed", "dk.eof": .stringConvertible(message == nil)])
            return message
        } catch {
            if closed, !Task.isCancelled { return nil }
            if error as? TransportFailure != .concurrentRead { await close() }
            throw nioWebSocketError(error)
        }
    }

    /// Aborts TCP without a normal/going-away close frame, preserving resumable protocol sessions.
    /// Concurrent calls share ordinary close cleanup and release admission exactly once.
    func closeForReconnect() async { await close() }

    /// Reads only the numeric peer status, retained independently of event-loop shutdown.
    /// - Returns: Last valid received close code, or `nil` for an empty/absent peer close.
    func peerCloseCode() async -> Int? { wire.peerCode.withLockedValue { $0 } }

    /// Terminates the socket promptly and releases its budget slot exactly once.
    /// Local close is a transport shutdown, not an unbounded peer-handshake wait.
    /// Concurrent callers await the same closeFuture and parent release operation.
    func close() async {
        if let cleanup { await cleanup.value; return }
        closed = true
        DiscordLog.makeLogger("nio.websocket").trace("NIO WebSocket connection cleanup started", metadata: ["dk.event": "nio.websocket.connection.cleanup", "dk.pending_writes": .stringConvertible(writes), "dk.pending_bytes": .stringConvertible(writeBytes)])
        let wire = self.wire; let release = self.release
        let task = Task {
            await wire.close()
            await release()
        }
        cleanup = task; await task.value
    }
}

/// Sendable event-loop frame reader handle.
private struct WebSocketWire: Sendable {
    let channel: any Channel
    let handler: NIOLoopBound<WebSocketWireHandler>
    let attempt: NIOConnectionAttempt
    let peerCode: NIOLockedValueBox<Int?>
    let discarded = NIOLockedValueBox(false)
    let cleanup = NIOLockedValueBox<Task<Void, Never>?>(nil)

    /// Reserves one reader on the socket's event loop.
    /// - Returns: Queued message or nil for orderly EOF or explicit owner disposal.
    ///   A disposal latch prevents new reads from entering a stopped event loop and
    ///   discards results already handed off before concurrent disposal completed.
    /// - Throws: Concurrent receive, protocol/overflow or network failure.
    func next() async throws -> WebSocketMessage? {
        do {
            let handler = self.handler
            let message = try await whileOpen { channel in
                let promise = channel.eventLoop.makePromise(of: WebSocketMessage?.self)
                handler.value.read(promise)
                return promise.futureResult
            }
            return discarded.withLockedValue({ $0 }) ? nil : message
        } catch {
            if discarded.withLockedValue({ $0 }) { return nil }
            throw error
        }
    }

    /// Writes one already admitted application frame through the lifecycle gate.
    /// - Parameters:
    ///   - bytes: Bounded complete payload whose reservation is owned by the caller.
    ///   - opcode: Text or binary application opcode; client masking is generated here.
    /// - Throws: `TransportFailure.closed` after disposal or native write failure,
    ///   subsequently sanitized by the connection's public operation boundary.
    func sendFrame(_ bytes: Data, opcode: WebSocketOpcode) async throws {
        try await whileOpen { channel in
            var buffer = channel.allocator.buffer(capacity: bytes.count)
            buffer.writeBytes(bytes)
            return channel.writeAndFlush(WebSocketFrame(fin: true, opcode: opcode, maskKey: .random(), data: buffer))
        }
    }

    /// Registers one operation and its async completion before disposal can start.
    /// Submission shares the cleanup lock, and completion is attached on the native
    /// event loop itself. No caller registers a future callback after releasing the
    /// lifecycle gate, including a caller suspended until after parent shutdown.
    /// - Parameter operation: Nonblocking event-loop work returning an owned future;
    ///   channel close must resolve that future so cleanup can drain pending work.
    /// - Returns: The operation's original result while the wire remains available.
    /// - Throws: `TransportFailure.closed` if disposal won admission, or native failure.
    private func whileOpen<Value: Sendable>(
        _ operation: @escaping @Sendable (any Channel) -> EventLoopFuture<Value>
    ) async throws -> Value {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Value, any Error>) in
            cleanup.withLockedValue { existing in
                guard case nil = existing else {
                    continuation.resume(throwing: TransportFailure.closed)
                    return
                }
                channel.eventLoop.execute {
                    operation(channel).whenComplete { continuation.resume(with: $0) }
                }
            }
        }
    }

    /// Closes the channel and drops retained input through one shared cleanup task.
    /// Parent and connection owners await this same task before event-loop shutdown;
    /// later calls await its Swift result without registering callbacks on a stopped
    /// NIO event loop. Disposing input is latched before suspension, while physical
    /// buffer cleanup and terminal channel close finish before this method returns.
    /// The task captures only native handles and the attempt, avoiding a self-retaining
    /// cycle through the task's synchronized reservation container.
    func close() async {
        let task = cleanup.withLockedValue { existing in
            if let existing { return existing }
            discarded.withLockedValue { $0 = true }
            let channel = self.channel
            let handler = self.handler
            let attempt = self.attempt
            let task = Task {
                attempt.cancel()
                try? await channel.closeFuture.get()
                try? await channel.eventLoop.submit { handler.value.discard() }.get()
            }
            existing = task
            return task
        }
        await task.value
    }

}

/// Exactly-once cross-event-loop upgrade completion, with synchronized reservation.
private final class WebSocketUpgradeCompletion: Sendable {
    let promise: EventLoopPromise<WebSocketWire>
    let finished = NIOLockedValueBox(false)

    /// Retains the caller's final upgrade promise.
    /// - Parameter promise: Promise safe to resolve from any owning channel event loop.
    init(_ promise: EventLoopPromise<WebSocketWire>) { self.promise = promise }

    /// Transfers an upgraded wire once; a late socket is closed immediately.
    /// - Parameter wire: Successfully upgraded socket and bounded frame parser.
    func succeed(_ wire: WebSocketWire) {
        let first = finished.withLockedValue { value in let first = !value; value = true; return first }
        if first { promise.succeed(wire) } else { wire.channel.close(promise: nil) }
    }

    /// Resolves a failed handshake once, without native credential-bearing errors.
    /// - Parameter error: Safe typed protocol/transport error.
    func fail(_ error: any Error) {
        let first = finished.withLockedValue { value in let first = !value; value = true; return first }
        if first { promise.fail(error) }
    }
}

/// Observes HTTP errors until the upgrader removes this handler on success.
private final class WebSocketUpgradeObserver: ChannelInboundHandler, RemovableChannelHandler {
    typealias InboundIn = HTTPClientResponsePart
    let completion: WebSocketUpgradeCompletion

    /// Stores the exactly-once handshake completion coordinator.
    /// - Parameter completion: Shared result for connect and HTTP/TLS failure paths.
    init(completion: WebSocketUpgradeCompletion) { self.completion = completion }

    /// Rejects an ordinary HTTP response forwarded after an unsuccessful upgrade.
    /// - Parameters:
    ///   - context: Channel closed because no message framing was negotiated.
    ///   - data: Response part; its content is intentionally not exposed in errors.
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        completion.fail(NIOAdapterFailure.upgradeRejected); context.close(promise: nil)
    }

    /// Fails a handshake whose peer closes before upgrade completion.
    /// - Parameter context: Closed channel's owning event loop.
    func channelInactive(context: ChannelHandlerContext) {
        completion.fail(NIOAdapterFailure.upgradeRejected); context.fireChannelInactive()
    }

    /// Sanitizes TLS and HTTP upgrade errors before closing the failed socket.
    /// - Parameters:
    ///   - context: Failing channel context.
    ///   - error: Native error discarded to protect request/response diagnostics.
    func errorCaught(context: ChannelHandlerContext, error: any Error) {
        completion.fail(NIOAdapterFailure.upgradeRejected); context.close(promise: nil)
    }
}

/// Event-loop-owned RFC 6455 assembler. Control frames never wait for user reads;
/// complete messages and partial fragmentation share one cumulative byte budget.
private final class WebSocketWireHandler: ChannelInboundHandler {
    typealias InboundIn = WebSocketFrame
    typealias OutboundOut = WebSocketFrame
    let configuration: NIOWebSocketConfiguration
    var messages: [WebSocketMessage] = []
    var queuedBytes = 0
    var fragment = Data()
    var fragmentOpcode: WebSocketOpcode?
    var reader: EventLoopPromise<WebSocketMessage?>?
    var ended = false
    var failure: (any Error)?
    var controlWrites = 0
    let peerCode = NIOLockedValueBox<Int?>(nil)

    /// Retains validated budgets; no application payload is preallocated.
    /// - Parameter configuration: Complete-message and aggregate-buffer limits.
    init(configuration: NIOWebSocketConfiguration) { self.configuration = configuration }

    /// Transfers one queued message or reserves the sole active receiver.
    /// - Parameter promise: Receive result resolved once by read, close or error.
    func read(_ promise: EventLoopPromise<WebSocketMessage?>) {
        if let failure { promise.fail(failure) }
        else if reader != nil { promise.fail(TransportFailure.concurrentRead) }
        else if !messages.isEmpty {
            let value = messages.removeFirst(); queuedBytes -= size(value); promise.succeed(value)
        } else if ended { promise.succeed(nil) }
        else { reader = promise }
    }

    /// Validates and assembles incoming frames, handling ping/pong/close immediately.
    /// Valid peer close codes survive local disposal; reasons are validated then discarded.
    /// - Parameters:
    ///   - context: Sole owner of frame state and ordered control responses.
    ///   - data: Decoded server frame. Masked server frames and reserved bits fail.
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        guard !ended, failure == nil else { return }
        let frame = unwrapInboundIn(data)
        guard frame.maskKey == nil, !frame.rsv1, !frame.rsv2, !frame.rsv3 else {
            fail(NIOAdapterFailure.invalidFrame, channel: context.channel); return
        }
        let payload = frame.unmaskedData
        if frame.opcode == .ping || frame.opcode == .pong || frame.opcode == .connectionClose {
            guard frame.fin, payload.readableBytes <= 125 else { fail(NIOAdapterFailure.invalidFrame, channel: context.channel); return }
            if frame.opcode == .ping {
                guard context.channel.isWritable, controlWrites < configuration.maximumPendingWrites else {
                    fail(NIOAdapterFailure.capacityExceeded, channel: context.channel); return
                }
                controlWrites += 1
                let bound = NIOLoopBound(self, eventLoop: context.eventLoop)
                let channel = context.channel
                context.writeAndFlush(wrapOutboundOut(WebSocketFrame(fin: true, opcode: .pong, maskKey: .random(), data: payload)))
                    .whenComplete { result in
                        bound.value.controlWrites -= 1
                        if case .failure = result { bound.value.fail(NIOAdapterFailure.connectionFailed, channel: channel) }
                    }
            } else if frame.opcode == .connectionClose {
                guard validClose(payload) else { fail(NIOAdapterFailure.invalidFrame, channel: context.channel); return }
                if let code: UInt16 = payload.getInteger(at: payload.readerIndex) {
                    peerCode.withLockedValue { $0 = Int(code) }
                }
                ended = true; reader?.succeed(nil); reader = nil
                let channel = context.channel
                context.writeAndFlush(wrapOutboundOut(WebSocketFrame(fin: true, opcode: .connectionClose, maskKey: .random(), data: payload)))
                    .whenComplete { _ in channel.close(promise: nil) }
            }
            return
        }
        guard frame.opcode == .text || frame.opcode == .binary || frame.opcode == .continuation,
              (frame.opcode == .continuation) == (fragmentOpcode != nil) else {
            fail(NIOAdapterFailure.invalidFrame, channel: context.channel); return
        }
        guard payload.readableBytes <= configuration.maximumMessageBytes - fragment.count,
              payload.readableBytes <= configuration.maximumMessageBytes - queuedBytes - fragment.count else {
            fail(NIOAdapterFailure.messageTooLarge, channel: context.channel); return
        }
        if fragmentOpcode == nil { fragmentOpcode = frame.opcode }
        fragment.append(contentsOf: payload.readableBytesView)
        if frame.fin {
            let value: WebSocketMessage
            if fragmentOpcode == .text {
                guard let text = String(data: fragment, encoding: .utf8) else { fail(NIOAdapterFailure.invalidFrame, channel: context.channel); return }
                value = .text(text)
            } else { value = .binary(fragment) }
            fragment = Data(); fragmentOpcode = nil
            if let reader { self.reader = nil; reader.succeed(value) }
            else {
                guard messages.count < configuration.maximumBufferedMessages else { fail(NIOAdapterFailure.capacityExceeded, channel: context.channel); return }
                messages.append(value); queuedBytes += size(value)
            }
        }
    }

    /// Distinguishes a clean close handshake from a truncated TCP stream.
    /// - Parameter context: Closed socket context; queued messages remain readable.
    func channelInactive(context: ChannelHandlerContext) {
        if !ended { fail(NIOAdapterFailure.connectionFailed, channel: context.channel) }
        context.fireChannelInactive()
    }

    /// Terminates malformed framing/network work with a redacted public error.
    /// - Parameters:
    ///   - context: Socket to close and pending reader to fail.
    ///   - error: Native decoder/transport error, omitted from diagnostics.
    func errorCaught(context: ChannelHandlerContext, error: any Error) {
        fail(NIOAdapterFailure.invalidFrame, channel: context.channel)
    }

    /// Discards all retained input when explicit owner closure ends the stream.
    /// Any pending consumer is resumed exactly once with terminal EOF.
    func discard() {
        ended = true; messages.removeAll(); fragment = Data(); fragmentOpcode = nil; queuedBytes = 0
        reader?.succeed(nil); reader = nil
    }

    /// Counts UTF-8 bytes consistently with complete-message write limits.
    /// - Parameter message: Complete text/binary value already validated.
    /// - Returns: Number of payload bytes, excluding protocol framing.
    private func size(_ message: WebSocketMessage) -> Int {
        switch message { case .text(let text): text.utf8.count; case .binary(let bytes): bytes.count }
    }

    /// Validates close code and UTF-8 reason per RFC 6455 without logging the reason.
    /// - Parameter payload: Unmasked close payload, at most 125 bytes.
    /// - Returns: Whether the payload is empty or carries a legal code and reason.
    private func validClose(_ payload: ByteBuffer) -> Bool {
        if payload.readableBytes == 0 { return true }
        guard payload.readableBytes >= 2, let code: UInt16 = payload.getInteger(at: payload.readerIndex),
              ((1000...1014).contains(code) && ![1004, 1005, 1006].contains(code)) || (3000...4999).contains(code),
              let reason = payload.getBytes(at: payload.readerIndex + 2, length: payload.readableBytes - 2) else { return false }
        return String(bytes: reason, encoding: .utf8) != nil
    }

    /// Latches failure, drops retained payloads and completes a pending reader once.
    /// - Parameters:
    ///   - error: Safe typed protocol/overflow/network failure.
    ///   - channel: Owning socket used for prompt teardown on its event loop.
    private func fail(_ error: any Error, channel: any Channel) {
        guard failure == nil else { return }
        failure = error; messages.removeAll(); fragment = Data(); queuedBytes = 0
        reader?.fail(error); reader = nil; channel.close(promise: nil)
    }
}

/// Removes native diagnostics while preserving cancellation and typed policy errors.
/// - Parameter error: Original I/O or caller-context error.
/// - Returns: A public failure with no URLs, headers, payloads or certificate paths.
private func nioWebSocketError(_ error: any Error) -> any Error {
    if Task.isCancelled { return CancellationError() }
    if error is CancellationError || error is TransportFailure || error is NIOAdapterFailure { return error }
    return NIOAdapterFailure.connectionFailed
}
