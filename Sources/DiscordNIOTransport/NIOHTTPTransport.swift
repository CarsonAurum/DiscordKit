import DiscordLogging
import Foundation
import DiscordTransport
import NIOCore
import NIOPosix
import NIOHTTP1
import NIOConcurrencyHelpers
import NIOSSL

/// Numeric transport budgets. Admission is fail-fast: there is no hidden waiter
/// queue, endpoint retry, cookie jar, proxy, credential store or redirect follow.
public struct NIOHTTPConfiguration: Sendable {
    public let maximumConnections: Int
    public let maximumConnectionsPerOrigin: Int
    public let maximumRequestBytes: Int
    public let maximumResponseBytes: Int
    public let maximumHeaderBytes: Int
    public let chunkBytes: Int

    /// Validates immutable budgets before threads or sockets are allocated.
    /// - Parameters:
    ///   - maximumConnections: Positive total active plus idle pool slots; default 32.
    ///   - maximumConnectionsPerOrigin: Positive slots per scheme/host/port, at most
    ///     the total; default 8. One HTTP/1.1 exchange occupies a slot through EOF/close.
    ///   - maximumRequestBytes: Nonnegative upload cap; default 8 MiB. Uploads are
    ///     collected within this bound before sending, so producer errors send nothing.
    ///   - maximumResponseBytes: Nonnegative cumulative response-body cap; default 8 MiB.
    ///   - maximumHeaderBytes: Positive request/response field-byte budget; default 32 KiB.
    ///   - chunkBytes: Positive socket read and emitted body chunk bound, default 16 KiB;
    ///     restricted to 1 MiB to keep per-read buffering predictable.
    /// - Throws: `TransportFailure.invalidLimit` for inconsistent or out-of-range budgets.
    public init(maximumConnections: Int = 32, maximumConnectionsPerOrigin: Int = 8,
                maximumRequestBytes: Int = 8_388_608, maximumResponseBytes: Int = 8_388_608,
                maximumHeaderBytes: Int = 32_768, chunkBytes: Int = 16_384) throws {
        guard maximumConnections > 0, maximumConnectionsPerOrigin > 0,
              maximumConnectionsPerOrigin <= maximumConnections,
              maximumRequestBytes >= 0, maximumResponseBytes >= 0,
              maximumHeaderBytes > 0, chunkBytes > 0, chunkBytes <= 1_048_576 else {
            throw TransportFailure.invalidLimit
        }
        self.maximumConnections = maximumConnections
        self.maximumConnectionsPerOrigin = maximumConnectionsPerOrigin
        self.maximumRequestBytes = maximumRequestBytes
        self.maximumResponseBytes = maximumResponseBytes
        self.maximumHeaderBytes = maximumHeaderBytes
        self.chunkBytes = chunkBytes
    }
}

/// Bounded HTTP/1.1 pooling with a dedicated event loop. Pull bodies stop socket
/// reads until requested. Each instance owns its budgets; deployments must share
/// an instance to impose a common aggregate transport limit. Close it explicitly.
/// Rate coordination, authentication, caching and retries belong above this layer.
public actor NIOHTTPTransport: HTTPTransport, TransportResource {
    private struct Origin: Hashable, Sendable { let host: String; let port: Int; let secure: Bool }
    private struct Lease: Sendable {
        let origin: Origin
        var wire: HTTPWire?
        let attempt: NIOConnectionAttempt
        var upload: BodyStream?
        var operation: Task<HTTPResponse, any Error>?
        var response: BodyStream?
        var cleanup: Task<Void, Never>?
    }
    private let configuration: NIOHTTPConfiguration
    private let tls: TLSPolicy
    private let group: MultiThreadedEventLoopGroup
    private var leases: [UUID: Lease] = [:]
    private var idle: [Origin: [HTTPWire]] = [:]
    private var closed = false
    private var cleanup: Task<Void, Never>?

    /// Creates one owned event-loop thread and a reusable TLS context.
    /// - Parameters:
    ///   - configuration: Validated connection/byte limits; no unbounded queues exist.
    ///   - tls: Optional full-verification trust policy; `nil` uses system trust roots.
    /// - Throws: Redacted TLS configuration errors; no sockets are opened yet.
    public init(configuration: NIOHTTPConfiguration, tls: TLSPolicy? = nil) throws {
        self.configuration = configuration
        self.tls = try tls ?? TLSPolicy()
        group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    }

    /// Sends once, preserving duplicate headers and transferring a single-use pull
    /// body. HTTP redirects are returned unchanged, so secrets never move to another
    /// origin. HTTP/1.1 only; no automatic decompression or replay occurs.
    /// - Parameters:
    ///   - request: Valid http/https URL, token method and caller headers. Host,
    ///     framing and connection headers are adapter-owned and rejected as input.
    ///   - context: Cancellation and inclusive deadline covering upload, headers and
    ///     subsequent response-body reads. Cancelling a read discards that connection.
    /// - Returns: Headers plus bounded body. Caller must consume or close the body
    ///   to release its pool slot; abandoning it without close retains that slot.
    /// - Throws: Cancellation/deadline, invalid input, capacity/byte limits or a
    ///   redacted transport failure. Ambiguous writes are never retried.
    public func execute<C: Clock>(_ request: HTTPRequest, context: TransportContext<C>) async throws -> HTTPResponse
    where C.Duration == Duration {
        DiscordLog.makeLogger("nio.http").trace("Starting NIO HTTP exchange", metadata: ["dk.event": "nio.http.execute"])
        var token: UUID?
        do {
            try context.check()
            let target = try NIORequestTarget(request, headerLimit: configuration.maximumHeaderBytes)
            let reservation = try reserve(target, upload: request.body)
            token = reservation.0
            DiscordLog.makeLogger("nio.http.pool").trace("NIO HTTP connection lease reserved", metadata: ["dk.event": "nio.http.pool.reserved", "dk.reused": .stringConvertible(reservation.1.wire != nil)])
            let id = reservation.0
            let attempt = reservation.1.attempt
            let operation = Task {
                try await context.run { [self] in
                    try await withTaskCancellationHandler {
                        let wire: HTTPWire
                        if let existing = reservation.1.wire { wire = existing }
                        else { wire = try await open(target, attempt: attempt) }
                        try await record(wire, id: id)
                        var upload = Data()
                        if let body = request.body {
                            do {
                                for try await chunk in body {
                                    guard chunk.count <= configuration.maximumRequestBytes - upload.count else {
                                        throw NIOAdapterFailure.requestTooLarge
                                    }
                                    upload.append(chunk)
                                }
                            } catch { await body.close(); throw error }
                            await body.close()
                        }
                        try context.check()
                        try await completeUpload(id)
                        DiscordLog.makeLogger("nio.http.upload").trace("NIO HTTP upload collection completed", metadata: ["dk.event": "nio.http.upload.completed", "dk.bytes": .stringConvertible(upload.count)])
                        let metadata = try await wire.begin(request, target: target, upload: upload)
                        let stream = try await responseStream(id, wire: wire, context: context)
                        DiscordLog.makeLogger("nio.http").debug("NIO HTTP response received", metadata: ["dk.event": "nio.http.response", "http.status": "\(metadata.status)"])
                        return HTTPResponse(status: metadata.status, headers: metadata.headers, body: stream)
                    } onCancel: { attempt.cancel() }
                }
            }
            var lease = reservation.1
            lease.operation = operation
            leases[id] = lease
            return try await withTaskCancellationHandler {
                try await operation.value
            } onCancel: { operation.cancel(); attempt.cancel() }
        } catch {
            if let body = request.body { await body.close() }
            if let token { await discard(token) }
            if closed && !Task.isCancelled { throw TransportFailure.closed }
            DiscordLog.makeLogger("nio.http").debug("NIO HTTP exchange ended without a response", metadata: ["dk.event": "nio.http.failed"])
            throw Self.safe(error)
        }
    }

    /// Returns the current active/idle slot counts for bounded diagnostics and tests.
    /// - Returns: Pool slots, including connecting and caller-owned response bodies.
    public func connectionCounts() -> (active: Int, idle: Int) {
        (leases.count, idle.values.reduce(0) { $0 + $1.count })
    }

    /// Cancels all exchanges, closes pending upload producers and transferred response
    /// bodies, then awaits their native operations before stopping the event loop.
    /// Retained bodies yield EOF after closure. Upload cleanup must unblock an in-flight
    /// pull as required by `BodyStream`; resumed exchanges cannot start further I/O.
    /// Repeated/concurrent callers await the same cleanup. A closed pool cannot restart;
    /// create a fresh instance after network replacement. No replay occurs on recovery.
    public func close() async {
        if let cleanup { await cleanup.value; return }
        closed = true
        let exchanges = Array(leases.keys).compactMap { startDiscard($0) }
        let wires = idle.values.flatMap { $0 }
        idle.removeAll()
        let group = self.group
        let task = Task {
            for exchange in exchanges { await exchange.value }
            leases.removeAll()
            for wire in wires {
                _ = try? await wire.finish()
                try? await wire.channel.close().get()
            }
            try? await group.shutdownGracefully()
        }
        cleanup = task
        await task.value
        DiscordLog.makeLogger("nio.http").info("NIO HTTP transport closed", metadata: ["dk.event": "nio.http.closed"])
    }

    /// Reserves a slot synchronously before any suspension; rejects overload without
    /// retaining callers. Idle origins are evicted when another origin needs capacity.
    /// - Parameters:
    ///   - target: Validated scheme/host/port destination.
    ///   - upload: Single-use request producer, retained until collection completes
    ///     so transport shutdown can interrupt a suspended pull. Nil means no body.
    /// - Returns: Unique lease and an optional reusable channel.
    /// - Throws: Closed pool or aggregate/per-origin capacity exhaustion.
    private func reserve(_ target: NIORequestTarget, upload: BodyStream?) throws -> (UUID, Lease) {
        guard !closed else { throw TransportFailure.closed }
        let origin = Origin(host: target.host.lowercased(), port: target.port, secure: target.secure)
        if var entries = idle.removeValue(forKey: origin) {
            while let wire = entries.popLast() {
                if wire.channel.isActive {
                    if !entries.isEmpty { idle[origin] = entries }
                    let attempt = NIOConnectionAttempt(); attempt.install(wire.channel)
                    let lease = Lease(origin: origin, wire: wire, attempt: attempt, upload: upload)
                    let id = UUID(); leases[id] = lease; return (id, lease)
                }
            }
        }
        let originCount = leases.values.filter { $0.origin == origin }.count
        guard originCount < configuration.maximumConnectionsPerOrigin else { throw NIOAdapterFailure.capacityExceeded }
        if leases.count + idle.values.reduce(0, { $0 + $1.count }) >= configuration.maximumConnections {
            guard let key = idle.keys.first, var entries = idle.removeValue(forKey: key), let evicted = entries.popLast() else {
                throw NIOAdapterFailure.capacityExceeded
            }
            evicted.channel.close(promise: nil)
            if !entries.isEmpty { idle[key] = entries }
        }
        let lease = Lease(origin: origin, wire: nil, attempt: NIOConnectionAttempt(), upload: upload)
        let id = UUID(); leases[id] = lease; return (id, lease)
    }

    /// Attaches a newly connected socket to its already reserved slot.
    /// - Parameters:
    ///   - wire: Channel and event-loop-confined response handler.
    ///   - id: Existing lease token; absent tokens mean pool shutdown won the race.
    /// - Throws: `TransportFailure.closed` if shutdown removed the reservation.
    ///   Closing the newly opened socket is initiated before returning the failure.
    private func record(_ wire: HTTPWire, id: UUID) throws {
        guard var lease = leases[id], !closed, lease.cleanup == nil else {
            wire.channel.close(promise: nil)
            throw TransportFailure.closed
        }
        lease.wire = wire
        leases[id] = lease
    }

    /// Releases the already-closed upload producer before response ownership begins.
    /// Checking admission again prevents a pull released by shutdown from starting
    /// HTTP I/O on the closed channel or retaining its producer through a response.
    /// - Parameter id: Existing exchange reservation.
    /// - Throws: `TransportFailure.closed` if pool shutdown won during collection.
    private func completeUpload(_ id: UUID) throws {
        guard var lease = leases[id], !closed, lease.cleanup == nil else { throw TransportFailure.closed }
        lease.upload = nil
        leases[id] = lease
    }

    /// Atomically replaces exchange-task ownership with a registered pull body.
    /// Shutdown either observes this stream or prevents its construction, so no body
    /// can submit native work after its owning event loop has stopped.
    /// - Parameters:
    ///   - id: Existing reservation whose final headers have arrived.
    ///   - wire: Event-loop-confined parser supplying the bounded body.
    ///   - context: Original deadline retained for subsequent body demands.
    /// - Returns: Single-consumer stream retained by the pool through terminal cleanup.
    /// - Throws: Closed transport or invalid chunk configuration.
    private func responseStream<C: Clock>(_ id: UUID, wire: HTTPWire,
                                          context: TransportContext<C>) throws -> BodyStream
    where C.Duration == Duration {
        guard var lease = leases[id], !closed, lease.cleanup == nil else { throw TransportFailure.closed }
        let attempt = lease.attempt
        let source = HTTPResponseSource(wire: wire, attempt: attempt, context: context,
                                        release: { await self.release(id, wire: wire) })
        let stream = try BodyStream(maximumChunkBytes: configuration.chunkBytes, next: {
            do { return try await source.next() }
            catch { attempt.cancel(); throw Self.safe(error) }
        }, close: { await source.close() })
        lease.operation = nil
        lease.response = stream
        leases[id] = lease
        DiscordLog.makeLogger("nio.http.body").trace("NIO HTTP response body ownership transferred", metadata: ["dk.event": "nio.http.body.transferred"])
        return stream
    }

    /// Connects with validated TLS and bounded decoder/socket read allocations.
    /// - Parameters:
    ///   - target: Origin, SNI hostname and origin-form HTTP target.
    ///   - attempt: Cancellation latch installed before asynchronous TCP connection.
    /// - Returns: Connected HTTP/1.1 channel; TLS completion is verified on first I/O.
    /// - Throws: Native errors, sanitized by the public operation boundary.
    private func open(_ target: NIORequestTarget, attempt: NIOConnectionAttempt) async throws -> HTTPWire {
        DiscordLog.makeLogger("nio.http.connection").trace("NIO HTTP socket connection started", metadata: ["dk.event": "nio.http.connection.started", "dk.tls": .stringConvertible(target.secure)])
        let configuration = self.configuration
        let tls = self.tls
        let result = NIOLockedValueBox<HTTPWire?>(nil)
        let bootstrap = ClientBootstrap(group: group)
            .connectTimeout(.seconds(10))
            .channelOption(ChannelOptions.autoRead, value: false)
            .channelOption(ChannelOptions.maxMessagesPerRead, value: 1)
            .channelOption(ChannelOptions.recvAllocator, value: FixedSizeRecvByteBufferAllocator(capacity: configuration.chunkBytes))
            .channelInitializer { channel in
                attempt.install(channel)
                return channel.eventLoop.makeCompletedFuture {
                    if target.secure {
                        try channel.pipeline.syncOperations.addHandler(NIOSSLClientHandler(context: tls.context, serverHostname: target.host))
                    }
                    var limits = NIOHTTPDecoderLimitConfiguration()
                    limits.maxHeaderFieldSize = configuration.maximumHeaderBytes
                    limits.maxHeaderListSize = configuration.maximumHeaderBytes
                    limits.maxHeaderFieldCount = min(1024, configuration.maximumHeaderBytes)
                    try channel.pipeline.syncOperations.addHTTPClientHandlers(decoderLimitConfiguration: limits)
                    let handler = HTTPWireHandler(configuration: configuration)
                    try channel.pipeline.syncOperations.addHandler(handler)
                    result.withLockedValue { $0 = HTTPWire(channel: channel, handler: NIOLoopBound(handler, eventLoop: channel.eventLoop)) }
                }
            }
        do {
            _ = try await bootstrap.connect(host: target.host, port: target.port).get()
            guard let wire = result.withLockedValue({ $0 }) else { throw NIOAdapterFailure.connectionFailed }
            DiscordLog.makeLogger("nio.http.connection").trace("NIO HTTP socket connected", metadata: ["dk.event": "nio.http.connection.connected"])
            return wire
        } catch { attempt.cancel(); throw error }
    }

    /// Releases body ownership; only a completely parsed response permits reuse.
    /// - Parameters:
    ///   - id: Lease being released exactly once by BodyStream cleanup.
    ///   - wire: Channel with either completed framing or unread/failed input.
    private func release(_ id: UUID, wire: HTTPWire) async {
        guard let current = leases[id], current.cleanup == nil else { return }
        let reusable = (try? await wire.finish()) ?? false
        guard let lease = leases[id], lease.cleanup == nil else { return }
        if reusable && !closed && wire.channel.isActive {
            leases.removeValue(forKey: id)
            idle[lease.origin, default: []].append(wire)
            DiscordLog.makeLogger("nio.http.pool").trace("NIO HTTP parsed connection returned for reuse", metadata: ["dk.event": "nio.http.pool.returned", "dk.active": .stringConvertible(leases.count)])
        } else {
            // Keep the registered stream until socket closure finishes: shutdown
            // must await this same BodyStream cleanup before stopping its loop.
            try? await wire.channel.close().get()
            if leases[id]?.cleanup == nil { leases.removeValue(forKey: id) }
            DiscordLog.makeLogger("nio.http.pool").trace("NIO HTTP connection disposed", metadata: ["dk.event": "nio.http.pool.disposed", "dk.active": .stringConvertible(leases.count)])
        }
    }

    /// Awaits shared failure/shutdown cleanup while retaining its reservation.
    /// A concurrent parent close finds and awaits the same task; native callbacks
    /// therefore always complete before event-loop shutdown.
    /// - Parameter id: Operation token; an already released token requires no work.
    private func discard(_ id: UUID) async {
        guard let task = startDiscard(id) else { return }
        await task.value
        leases.removeValue(forKey: id)
    }

    /// Latches one terminal cleanup task before suspension and cancels native work.
    /// Upload, exchange, response and parser cleanup finish while the event loop is
    /// alive. Response cleanup detects this latch and delegates final wire disposal
    /// here, avoiding recursion through the same stream or cleanup task.
    /// - Parameter id: Live reservation to dispose; absent tokens are already clean.
    /// - Returns: Shared owned cleanup task, or nil for an absent reservation.
    private func startDiscard(_ id: UUID) -> Task<Void, Never>? {
        guard var lease = leases[id] else { return nil }
        if let cleanup = lease.cleanup { return cleanup }
        DiscordLog.makeLogger("nio.http.pool").trace("NIO HTTP exchange cleanup started", metadata: ["dk.event": "nio.http.pool.cleanup", "dk.has_response": .stringConvertible(lease.response != nil)])
        // A transferred stream marks itself closed before interrupting its read;
        // otherwise native cancellation could escape as an error instead of EOF.
        if lease.response == nil { lease.attempt.cancel() }
        lease.operation?.cancel()
        let resources = lease
        let task = Task {
            await resources.upload?.close()
            _ = await resources.operation?.result
            await resources.response?.close()
            resources.attempt.cancel()
            if let wire = resources.wire {
                _ = try? await wire.finish()
                try? await wire.channel.close().get()
            }
        }
        lease.cleanup = task
        leases[id] = lease
        return task
    }

    /// Preserves typed policy/cancellation errors while removing native diagnostics.
    /// - Parameter error: Failure from NIO, TLS or an operation-owned body producer.
    /// - Returns: Safe typed error with no request/response/credential payload.
    private nonisolated static func safe(_ error: any Error) -> any Error {
        if Task.isCancelled { return CancellationError() }
        if error is CancellationError || error is TransportFailure || error is NIOAdapterFailure { return error }
        return NIOAdapterFailure.connectionFailed
    }
}

/// Owns each native body read before suspension and joins it during stream cleanup.
/// The registered BodyStream keeps this actor alive until its last event-loop
/// callback finishes, including reads racing transport shutdown.
private actor HTTPResponseSource<C: Clock> where C.Duration == Duration {
    private let wire: HTTPWire
    private let attempt: NIOConnectionAttempt
    private let context: TransportContext<C>
    private let release: @Sendable () async -> Void
    private var reading: Task<Data?, any Error>?
    private var closed = false
    private var cleanup: Task<Void, Never>?

    /// Stores transferred parser ownership without starting a native read.
    /// - Parameters:
    ///   - wire: Connection whose event loop remains alive through this cleanup.
    ///   - attempt: Idempotent cancellation latch for a pending native consumer.
    ///   - context: Original request clock and optional lifetime deadline.
    ///   - release: Returns the lease or disposes its connection after reads finish.
    init(wire: HTTPWire, attempt: NIOConnectionAttempt, context: TransportContext<C>,
         release: @escaping @Sendable () async -> Void) {
        self.wire = wire
        self.attempt = attempt
        self.context = context
        self.release = release
    }

    /// Registers one operation task before it can submit work to the event loop.
    /// - Returns: Bounded native data, or nil at EOF or explicit stream closure.
    ///   A close racing a failed native read discards that failure and yields EOF.
    /// - Throws: Concurrent reads, original cancellation/deadline or native failures.
    func next() async throws -> Data? {
        guard !closed else { return nil }
        guard reading == nil else { throw TransportFailure.concurrentRead }
        let wire = self.wire
        let attempt = self.attempt
        let context = self.context
        let operation = Task {
            try await context.run {
                try await withTaskCancellationHandler {
                    try await wire.next()
                } onCancel: { attempt.cancel() }
            }
        }
        reading = operation
        defer { reading = nil }
        do {
            let value = try await withTaskCancellationHandler {
                try await operation.value
            } onCancel: { operation.cancel(); attempt.cancel() }
            return closed ? nil : value
        } catch {
            if closed { return nil }
            throw error
        }
    }

    /// Closes once, interrupts any native consumer and awaits its terminal callback.
    /// Normal EOF permits pool reuse; closing an in-flight read discards the socket.
    /// Concurrent callers await one shared task, so parent shutdown cannot overtake
    /// either a delayed submission or its callback registration.
    func close() async {
        if let cleanup { await cleanup.value; return }
        closed = true
        let reading = self.reading
        let attempt = self.attempt
        let release = self.release
        let task = Task {
            if let reading {
                reading.cancel()
                attempt.cancel()
                _ = await reading.result
            }
            await release()
        }
        cleanup = task
        await task.value
    }
}

/// Sendable handle; handler state is touched only inside its owning event loop.
private struct HTTPWire: Sendable {
    let channel: any Channel
    let handler: NIOLoopBound<HTTPWireHandler>

    /// Installs response promises before sending a fully bounded upload.
    /// - Parameters:
    ///   - request: Validated method and non-framing headers.
    ///   - target: Adapter-generated Host and origin-form path/query.
    ///   - upload: Bounded, precollected request bytes; never replayed.
    /// - Returns: Final noninformational response metadata.
    /// - Throws: Wire or response validation errors.
    func begin(_ request: HTTPRequest, target: NIORequestTarget, upload: Data) async throws -> HTTPResponse {
        try await channel.eventLoop.flatSubmit {
            let promise = channel.eventLoop.makePromise(of: HTTPResponse.self)
            guard channel.isActive else {
                promise.fail(TransportFailure.closed)
                return promise.futureResult
            }
            handler.value.begin(promise, method: request.method)
            var headers = HTTPHeaders(request.headers.map { ($0.name, $0.value) })
            headers.add(name: "Host", value: target.hostHeader)
            if request.body != nil { headers.add(name: "Content-Length", value: String(upload.count)) }
            let head = HTTPRequestHead(version: .http1_1, method: HTTPMethod(rawValue: request.method), uri: target.path, headers: headers)
            channel.write(HTTPClientRequestPart.head(head), promise: nil)
            if !upload.isEmpty {
                var buffer = channel.allocator.buffer(capacity: upload.count); buffer.writeBytes(upload)
                channel.write(HTTPClientRequestPart.body(.byteBuffer(buffer)), promise: nil)
            }
            channel.writeAndFlush(HTTPClientRequestPart.end(nil), promise: nil)
            channel.read()
            return promise.futureResult
        }.get()
    }

    /// Requests one bounded chunk, applying socket backpressure until this demand.
    /// - Returns: Chunk or nil at complete response EOF.
    /// - Throws: Concurrent-read, invalid framing, size or connection failure.
    func next() async throws -> Data? {
        try await channel.eventLoop.flatSubmit {
            let promise = channel.eventLoop.makePromise(of: Data?.self)
            handler.value.read(promise, channel: channel)
            return promise.futureResult
        }.get()
    }

    /// Resets parser ownership only after the complete response boundary.
    /// - Returns: Whether the connection is safe for one subsequent exchange.
    /// - Throws: Event-loop shutdown failure.
    func finish() async throws -> Bool {
        try await channel.eventLoop.submit { handler.value.finish() }.get()
    }
}

/// Bounded event-loop-confined response state. At most one socket read (chunkBytes)
/// is outstanding. Header parsing is capped independently by NIO's decoder.
private final class HTTPWireHandler: ChannelInboundHandler {
    typealias InboundIn = HTTPClientResponsePart
    private let configuration: NIOHTTPConfiguration
    private var headers: EventLoopPromise<HTTPResponse>?
    private var reader: EventLoopPromise<Data?>?
    private var chunks: [Data] = []
    private var queuedBytes = 0
    private var receivedBytes = 0
    private var ended = false
    private var keepAlive = false
    private var failure: (any Error)?
    private var hasHead = false
    private var isHeadRequest = false

    /// Stores validated numeric limits without allocating network resources.
    /// - Parameter configuration: Per-connection header/chunk/response budgets.
    init(configuration: NIOHTTPConfiguration) { self.configuration = configuration }

    /// Resets state before a new nonpipelined exchange.
    /// - Parameters:
    ///   - promise: Final-header completion, resolved once by parser or close.
    ///   - method: Validated case-sensitive HTTP method. HEAD responses advertise
    ///     representation length without transferring those bytes on the wire.
    func begin(_ promise: EventLoopPromise<HTTPResponse>, method: String) {
        headers = promise; receivedBytes = 0; ended = false; keepAlive = false; hasHead = false; failure = nil
        isHeadRequest = method == "HEAD"
    }

    /// Delivers queued data first; otherwise arms exactly one demand-driven socket read.
    /// - Parameters:
    ///   - promise: One active body consumer; simultaneous consumers fail.
    ///   - channel: Channel whose reads are disabled between demands.
    func read(_ promise: EventLoopPromise<Data?>, channel: any Channel) {
        if let failure { promise.fail(failure) }
        else if reader != nil { promise.fail(TransportFailure.concurrentRead) }
        else if !chunks.isEmpty { let value = chunks.removeFirst(); queuedBytes -= value.count; promise.succeed(value) }
        else if ended { promise.succeed(nil) }
        else { reader = promise; channel.read() }
    }

    /// Discards buffered bytes and reports safe keep-alive reuse after parsed EOF.
    /// - Returns: True only after valid final-response framing with keep-alive.
    func finish() -> Bool {
        let reuse = ended && failure == nil && keepAlive
        chunks.removeAll(); queuedBytes = 0
        reader?.succeed(nil); reader = nil
        return reuse
    }

    /// Interprets final headers, bounded body chunks and terminal response framing.
    /// - Parameters:
    ///   - context: Sole event-loop owner of this parser state.
    ///   - data: One decoded response part; informational headers do not transfer ownership.
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        switch unwrapInboundIn(data) {
        case .head(let head):
            if (100..<200).contains(head.status.code) { return }
            guard !hasHead, head.status.code >= 200 else { fail(NIOAdapterFailure.invalidResponse, context: context); return }
            hasHead = true; keepAlive = head.isKeepAlive
            // HEAD and 304 Content-Length describe a selected representation;
            // their responses contain no message body to charge against this cap.
            if !isHeadRequest, head.status != .notModified,
               let value = head.headers.first(name: "content-length"),
               let count = UInt64(value), count > UInt64(configuration.maximumResponseBytes) {
                fail(NIOAdapterFailure.responseTooLarge, context: context); return
            }
            headers?.succeed(HTTPResponse(status: Int(head.status.code), headers: head.headers.map { HTTPHeader(name: $0.name, value: $0.value) }))
            headers = nil
        case .body(let buffer):
            guard hasHead, buffer.readableBytes <= configuration.maximumResponseBytes - receivedBytes else {
                fail(NIOAdapterFailure.responseTooLarge, context: context); return
            }
            receivedBytes += buffer.readableBytes
            // TLS may emit a plaintext record larger than the socket read allocator;
            // split output and bound the queued record to 64 KiB plus one read.
            guard buffer.readableBytes <= 65_536 + configuration.chunkBytes - queuedBytes else {
                fail(NIOAdapterFailure.responseTooLarge, context: context); return
            }
            let bytes = Data(buffer.readableBytesView)
            for offset in stride(from: 0, to: bytes.count, by: configuration.chunkBytes) {
                let chunk = bytes.subdata(in: offset..<min(bytes.count, offset + configuration.chunkBytes))
                if let reader { self.reader = nil; reader.succeed(chunk) }
                else { chunks.append(chunk); queuedBytes += chunk.count }
            }
        case .end:
            if hasHead { ended = true; reader?.succeed(nil); reader = nil }
        }
    }

    /// Continues reading only while headers or a body consumer require more input.
    /// - Parameter context: Channel whose autoRead is disabled.
    func channelReadComplete(context: ChannelHandlerContext) {
        if headers != nil || reader != nil { context.read() }
        context.fireChannelReadComplete()
    }

    /// Fails truncated responses while allowing an EOF-framed final response to finish.
    /// - Parameter context: Closed channel's event-loop context.
    func channelInactive(context: ChannelHandlerContext) {
        if !ended { fail(NIOAdapterFailure.connectionFailed, context: context) }
        context.fireChannelInactive()
    }

    /// Sanitizes native errors and terminates parser promises exactly once.
    /// - Parameters:
    ///   - context: Channel to close after failure.
    ///   - error: Native failure, intentionally omitted from public diagnostics.
    func errorCaught(context: ChannelHandlerContext, error: any Error) {
        fail(NIOAdapterFailure.connectionFailed, context: context)
    }

    /// Latches a terminal failure, drops retained bytes and resolves pending consumers.
    /// - Parameters:
    ///   - error: Redacted typed failure safe for public diagnostics.
    ///   - context: Sole owner of promises and channel cleanup.
    private func fail(_ error: any Error, context: ChannelHandlerContext) {
        guard failure == nil else { return }
        failure = error; headers?.fail(error); headers = nil; reader?.fail(error); reader = nil
        chunks.removeAll(); queuedBytes = 0; context.close(promise: nil)
    }
}
