import DiscordLogging
import DiscordTransport
import Foundation
import NIOConcurrencyHelpers
import NIOCore
import NIOHTTP1
import NIOPosix

/// A bounded HTTP/1.1 listener with caller-owned, exactly-once response slots.
///
/// This initial adapter accepts one request per connection and closes after its
/// response. Request and response bodies are buffered only up to explicit byte
/// limits; HTTP upgrades, trailers, `Expect`, TLS termination and keep-alive reuse
/// are outside this adapter. A reverse proxy may provide TLS. It uses NIO's
/// process-owned event-loop singleton, allowing accepted exchanges to outlive the
/// listener without retaining an otherwise-owned event-loop thread per exchange.
public final class NIOHTTPIngress: HTTPIngress, Sendable {
    public let localAddress: DatagramAddress
    private let listener: any Channel
    private let registry: NIOIngressRegistry
    private let input: NIOServiceQueue<NIOIngressAccepted>
    private let cleanup: NIOIngressCleanup

    /// Stores a successfully bound listener and its bounded acceptance state.
    /// - Parameters:
    ///   - listener: Listening socket; accepted sockets have separate ownership.
    ///   - registry: Synchronous connection admission and handoff coordinator.
    ///   - input: Bounded mailbox of complete requests.
    ///   - localAddress: Numeric address, including any assigned ephemeral port.
    private init(listener: any Channel, registry: NIOIngressRegistry,
                 input: NIOServiceQueue<NIOIngressAccepted>, localAddress: DatagramAddress) {
        self.listener = listener
        self.registry = registry
        self.input = input
        self.localAddress = localAddress
        self.cleanup = NIOIngressCleanup(listener: listener, registry: registry)
    }

    /// Binds a numeric local address with bounded sockets, backlog, bodies and metadata.
    ///
    /// The connection limit counts parsing, queued and caller-owned exchanges.
    /// Excess connections are closed immediately. A full acceptance mailbox rejects
    /// the new connection; already accepted requests remain available. No application
    /// handler runs on the listener's event loop. Socket/DNS errors are redacted.
    /// - Parameters:
    ///   - localAddress: Literal IPv4/IPv6 bind address; zero selects an ephemeral port.
    ///   - maximumConnections: Positive aggregate accepted-socket limit, default 128.
    ///   - maximumPendingRequests: Positive complete-request backlog, default 64.
    ///   - maximumBodyBytes: Positive per-request and per-response body bound.
    ///   - maximumHeaderBytes: Positive URI/header byte bound, default 16,384.
    ///   - context: Binding clock/deadline and task cancellation.
    /// - Returns: An owned listener; callers must close accepted responders separately.
    /// - Throws: Invalid configuration/address, cancellation, expiration or redacted I/O failure.
    public static func bind<C: Clock>(
        localAddress: DatagramAddress = .init(host: "127.0.0.1", port: 0),
        maximumConnections: Int = 128,
        maximumPendingRequests: Int = 64,
        maximumBodyBytes: Int = 1_048_576,
        maximumHeaderBytes: Int = 16_384,
        context: TransportContext<C>
    ) async throws -> NIOHTTPIngress where C.Duration == Duration {
        DiscordLog.makeLogger("nio.ingress").trace("Starting local ingress binding", metadata: ["dk.event": "nio.ingress.bind"])
        try context.check()
        guard maximumConnections > 0, maximumPendingRequests > 0,
              maximumBodyBytes > 0, maximumHeaderBytes > 0 else {
            throw NIOServiceFailure.invalidConfiguration
        }
        let address: SocketAddress
        do { address = try SocketAddress(ipAddress: localAddress.host, port: Int(localAddress.port)) }
        catch { throw NIOServiceFailure.invalidAddress }
        let registry = NIOIngressRegistry(maximumConnections: maximumConnections)
        let input = NIOServiceQueue<NIOIngressAccepted>(maximumCount: maximumPendingRequests,
                                                       maximumBytes: maximumPendingRequests)
        let slot = NIOServiceChannelSlot()
        var decoderLimits = NIOHTTPDecoderLimitConfiguration()
        decoderLimits.maxHeaderFieldSize = maximumHeaderBytes
        decoderLimits.maxHeaderListSize = maximumHeaderBytes
        decoderLimits.maxHeaderFieldCount = min(maximumHeaderBytes, 1_024)
        let limits = decoderLimits
        do {
            return try await context.run {
                try await withTaskCancellationHandler {
                    let listener = try await ServerBootstrap(group: MultiThreadedEventLoopGroup.singleton)
                        .serverChannelOption(ChannelOptions.backlog, value: Int32(min(maximumConnections, 1_024)))
                        .serverChannelInitializer { channel in
                            slot.install(channel)
                            return channel.eventLoop.makeCompletedFuture {
                                try channel.pipeline.syncOperations.addHandler(
                                    NIOIngressListenerHandler(input: input, registry: registry))
                            }
                        }
                        .childChannelInitializer { channel in
                            guard registry.register(channel) else {
                                return channel.close().flatMap { channel.eventLoop.makeFailedFuture(TransportFailure.closed) }
                            }
                            channel.closeFuture.whenComplete { _ in registry.remove(channel) }
                            return channel.pipeline.configureHTTPServerPipeline(
                                withPipeliningAssistance: false,
                                withErrorHandling: false,
                                withDecoderLimitConfiguration: limits
                            ).flatMapThrowing {
                                try channel.pipeline.syncOperations.addHandler(NIOIngressRequestHandler(
                                    input: input, maximumBodyBytes: maximumBodyBytes,
                                    maximumHeaderBytes: maximumHeaderBytes))
                            }
                        }.bind(to: address).get()
                    try Task.checkCancellation()
                    guard let host = listener.localAddress?.ipAddress,
                          let port = listener.localAddress?.port, let wirePort = UInt16(exactly: port)
                    else { throw NIOServiceFailure.invalidAddress }
                    DiscordLog.makeLogger("nio.ingress").info("Local ingress bound", metadata: ["dk.event": "nio.ingress.bound"])
                    return NIOHTTPIngress(listener: listener, registry: registry, input: input,
                                          localAddress: .init(host: host, port: wirePort))
                } onCancel: {
                    input.finish()
                    slot.terminate()
                    for channel in registry.terminateUnaccepted() { channel.close(promise: nil) }
                }
            }
        } catch {
            input.finish()
            slot.terminate()
            for channel in registry.terminateUnaccepted() {
                try? await channel.close().get()
            }
            if let listener = slot.installed() { try? await listener.closeFuture.get() }
            throw nioServiceRedacted(error)
        }
    }

    /// Transfers the next complete request and its response socket to the caller.
    ///
    /// Single-reader reservation rejects concurrent accepts. Cancellation or deadline
    /// expiry of an admitted accept closes this listener and unaccepted connections.
    /// A handoff completed before listener close preserves caller socket ownership.
    /// - Parameter context: Clock/deadline and cancellation for this acceptance.
    /// - Returns: Next exchange, or `nil` after listener shutdown.
    /// - Throws: Concurrent accept, cancellation, expiration, or redacted listener failure.
    public func accept<C: Clock>(context: TransportContext<C>) async throws -> HTTPExchange?
        where C.Duration == Duration {
        try context.check()
        do {
            return try await context.run { [self] in
                try await withTaskCancellationHandler {
                    guard let accepted = try await input.next() else { return nil }
                    guard registry.handoff(accepted.channel) else {
                        await accepted.exchange.responder.close()
                        return nil
                    }
                    return accepted.exchange
                } onCancel: {
                    input.finish()
                    listener.close(promise: nil)
                    for channel in registry.terminateUnaccepted() { channel.close(promise: nil) }
                }
            }
        } catch TransportFailure.concurrentRead {
            throw TransportFailure.concurrentRead
        } catch {
            await close()
            throw nioServiceRedacted(error)
        }
    }

    /// Stops acceptance and awaits cleanup of the listener and unaccepted sockets.
    /// Accepted exchanges remain caller-owned, including after concurrent close calls.
    public func close() async {
        input.finish()
        await cleanup.close()
        DiscordLog.makeLogger("nio.ingress").info("Local HTTP ingress closed", metadata: ["dk.event": "nio.ingress.closed"])
    }
}

/// Couples a queued exchange to its untransferred socket for atomic handoff.
private struct NIOIngressAccepted: Sendable {
    let exchange: HTTPExchange
    let channel: any Channel
}

/// Ends pending acceptance when the native listener fails or closes externally.
private final class NIOIngressListenerHandler: ChannelInboundHandler {
    typealias InboundIn = any Channel
    let input: NIOServiceQueue<NIOIngressAccepted>
    let registry: NIOIngressRegistry

    /// Stores the acceptance mailbox and untransferred socket coordinator.
    /// - Parameters:
    ///   - input: Queue whose waiter must be released when listening terminates.
    ///   - registry: Registry preserving sockets already handed to application code.
    init(input: NIOServiceQueue<NIOIngressAccepted>, registry: NIOIngressRegistry) {
        self.input = input
        self.registry = registry
    }

    /// Wakes acceptance at orderly close and closes every unaccepted connection.
    /// - Parameter context: Listener event-loop context forwarded after cleanup starts.
    func channelInactive(context: ChannelHandlerContext) {
        input.finish()
        for channel in registry.terminateUnaccepted() { channel.close(promise: nil) }
        context.fireChannelInactive()
    }

    /// Publishes a fixed redacted listener failure before native termination.
    /// - Parameters:
    ///   - context: Listener context used for terminal socket close.
    ///   - error: Original operating-system failure, omitted from public diagnostics.
    func errorCaught(context: ChannelHandlerContext, error: any Error) {
        input.finish(NIOServiceFailure.ioFailure)
        context.close(promise: nil)
    }
}

/// Coordinates connection count and caller handoff without per-request tasks.
private final class NIOIngressRegistry: Sendable {
    /// State protected by one lock across the listener and its child event loops.
    private struct State: Sendable {
        var channels: [ObjectIdentifier: (any Channel, Bool)] = [:]
        var closed = false
    }
    private let state = NIOLockedValueBox(State())
    private let maximumConnections: Int

    /// Stores the aggregate socket limit for this listener.
    /// - Parameter maximumConnections: Validated positive active socket count.
    init(maximumConnections: Int) { self.maximumConnections = maximumConnections }

    /// Reserves one connection before HTTP decoder allocation.
    /// - Parameter channel: Newly accepted socket.
    /// - Returns: Whether the socket fits the connection budget and listener is open.
    func register(_ channel: any Channel) -> Bool {
        state.withLockedValue { value in
            guard !value.closed, value.channels.count < maximumConnections else { return false }
            value.channels[ObjectIdentifier(channel)] = (channel, false)
            return true
        }
    }

    /// Atomically transfers a socket unless listener shutdown already reserved it.
    /// - Parameter channel: Socket whose complete exchange was removed from the queue.
    /// - Returns: Whether caller ownership was established before listener closure.
    func handoff(_ channel: any Channel) -> Bool {
        state.withLockedValue { value in
            guard !value.closed, value.channels[ObjectIdentifier(channel)] != nil else { return false }
            value.channels[ObjectIdentifier(channel)] = (channel, true)
            return true
        }
    }

    /// Releases connection admission after native close completes.
    /// - Parameter channel: Closed socket, whether accepted or rejected upstream.
    func remove(_ channel: any Channel) {
        _ = state.withLockedValue { $0.channels.removeValue(forKey: ObjectIdentifier(channel)) }
    }

    /// Reserves listener closure while preserving already transferred sockets.
    /// - Returns: Unaccepted sockets whose native close must be initiated and awaited.
    func terminateUnaccepted() -> [any Channel] {
        state.withLockedValue { value in
            value.closed = true
            return value.channels.values.compactMap { $0.1 ? nil : $0.0 }
        }
    }
}

/// Reserves one listener cleanup task before suspension.
private actor NIOIngressCleanup {
    let listener: any Channel
    let registry: NIOIngressRegistry
    var task: Task<Void, Never>?

    /// Stores listener ownership independently of caller-owned response sockets.
    /// - Parameters:
    ///   - listener: Native listener to close once.
    ///   - registry: Coordinator identifying only unaccepted connections.
    init(listener: any Channel, registry: NIOIngressRegistry) {
        self.listener = listener
        self.registry = registry
    }

    /// Stops the listener and awaits native closure of every unaccepted socket.
    func close() async {
        if let task { await task.value; return }
        let channels = registry.terminateUnaccepted()
        let listener = self.listener
        let cleanup = Task {
            listener.close(promise: nil)
            for channel in channels { channel.close(promise: nil) }
            try? await listener.closeFuture.get()
            for channel in channels { try? await channel.closeFuture.get() }
        }
        task = cleanup
        await cleanup.value
    }
}

/// Owns a bounded in-memory body while preserving BodyStream single-use semantics.
private actor NIOIngressBody {
    var bytes: Data?

    /// Transfers a validated bounded payload to a pull body.
    /// - Parameter bytes: Complete bytes; empty input is valid.
    init(_ bytes: Data) { self.bytes = bytes }

    /// Returns the complete body once, then EOF, without replay.
    /// - Returns: Original bounded bytes, or `nil` after consumption or close.
    func next() -> Data? { defer { bytes = nil }; return bytes }

    /// Releases unconsumed body memory; repeated calls are harmless.
    func close() { bytes = nil }
}

/// Collects one bounded request per socket and disables further request reads.
private final class NIOIngressRequestHandler: ChannelInboundHandler {
    typealias InboundIn = HTTPServerRequestPart
    private let input: NIOServiceQueue<NIOIngressAccepted>
    private let maximumBodyBytes: Int
    private let maximumHeaderBytes: Int
    private var head: HTTPRequestHead?
    private var bytes = Data()
    private var completed = false

    /// Stores listener admission and per-request budgets.
    /// - Parameters:
    ///   - input: Mailbox receiving complete requests only.
    ///   - maximumBodyBytes: Maximum full request or response payload.
    ///   - maximumHeaderBytes: Maximum URI and header metadata size in bytes.
    init(input: NIOServiceQueue<NIOIngressAccepted>, maximumBodyBytes: Int, maximumHeaderBytes: Int) {
        self.input = input
        self.maximumBodyBytes = maximumBodyBytes
        self.maximumHeaderBytes = maximumHeaderBytes
    }

    /// Validates metadata, accumulates a bounded body, and offers one complete exchange.
    /// - Parameters:
    ///   - context: Event-loop-confined child socket context.
    ///   - data: Parsed HTTP request head, body fragment, or end marker.
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        guard !completed else { return }
        switch unwrapInboundIn(data) {
        case .head(let value):
            guard head == nil, value.version == .http1_1,
                  value.uri.hasPrefix("/"), !value.uri.hasPrefix("//"),
                  !value.uri.contains("#"), value.uri.utf8.count <= maximumHeaderBytes,
                  !value.headers.contains(name: "expect") else {
                context.close(promise: nil)
                return
            }
            head = value
        case .body(let value):
            guard head != nil, value.readableBytes <= maximumBodyBytes - bytes.count else {
                completed = true
                bytes.removeAll()
                context.close(promise: nil)
                return
            }
            bytes.append(contentsOf: value.readableBytesView)
        case .end(let trailers):
            guard let head, trailers == nil,
                  let url = URL(string: "http://localhost" + head.uri) else {
                context.close(promise: nil)
                return
            }
            completed = true
            let channel = context.channel
            channel.setOption(ChannelOptions.autoRead, value: false).whenFailure { _ in
                channel.close(promise: nil)
            }
            do {
                let body: BodyStream?
                if bytes.isEmpty { body = nil }
                else {
                    let source = NIOIngressBody(bytes)
                    body = try BodyStream(maximumChunkBytes: maximumBodyBytes,
                                          next: { await source.next() }, close: { await source.close() })
                }
                bytes.removeAll()
                self.head = nil
                let responder = NIOIngressResponder(channel: context.channel, maximumBodyBytes: maximumBodyBytes,
                                                     maximumHeaderBytes: maximumHeaderBytes,
                                                     suppressResponseBody: head.method == .HEAD)
                let request = HTTPRequest(method: head.method.rawValue, url: url,
                                          headers: head.headers.map { HTTPHeader(name: $0.name, value: $0.value) },
                                          body: body)
                let accepted = NIOIngressAccepted(exchange: HTTPExchange(request: request, responder: responder),
                                                  channel: context.channel)
                if !input.offer(accepted, bytes: 1) { context.close(promise: nil) }
            } catch { context.close(promise: nil) }
        }
    }

    /// Closes malformed connections without exposing raw request or socket details.
    /// - Parameters:
    ///   - context: Child socket context used for terminal cleanup.
    ///   - error: Decoder/socket failure, deliberately omitted from diagnostics.
    func errorCaught(context: ChannelHandlerContext, error: any Error) {
        bytes.removeAll()
        context.close(promise: nil)
    }
}

/// An actor reserves its one response before body reads or socket writes suspend.
private actor NIOIngressResponder: HTTPResponder {
    let channel: any Channel
    let maximumBodyBytes: Int
    let maximumHeaderBytes: Int
    let suppressResponseBody: Bool
    var reserved = false
    var activeBody: BodyStream?
    var cleanup: Task<Void, Never>?

    /// Transfers one request's native socket to an exactly-once response slot.
    /// - Parameters:
    ///   - channel: Socket containing a fully parsed single request.
    ///   - maximumBodyBytes: Maximum total response payload bytes.
    ///   - maximumHeaderBytes: Maximum encoded response header metadata bytes.
    ///   - suppressResponseBody: Whether the request was HEAD; drain the supplied
    ///     body and advertise its size while omitting all payload writes.
    init(channel: any Channel, maximumBodyBytes: Int, maximumHeaderBytes: Int, suppressResponseBody: Bool) {
        self.channel = channel
        self.maximumBodyBytes = maximumBodyBytes
        self.maximumHeaderBytes = maximumHeaderBytes
        self.suppressResponseBody = suppressResponseBody
    }

    /// Reserves and sends one bounded HTTP/1.1 response, closing afterward.
    ///
    /// Framing headers are generated from the actual bounded body. Supplied
    /// Content-Length, Transfer-Encoding and Connection fields are replaced;
    /// ordinary duplicate headers retain their order. Informational responses and
    /// upgrades are rejected. Every call takes and closes its supplied body,
    /// including calls rejected as duplicates. Failure never reopens the slot.
    /// HEAD advertises the collected body's size without sending its bytes; 204,
    /// 205 and 304 discard content, with Content-Length omitted for 204 and 304.
    /// - Parameters:
    ///   - response: Final status 200...599, bounded valid headers and optional body.
    ///   - context: Clock/deadline and cancellation for body collection and transmission.
    /// - Throws: Duplicate response, invalid HTTP/body limits, cancellation,
    ///   expiration, closure, or redacted native I/O failure.
    func respond<C: Clock>(_ response: HTTPResponse, context: TransportContext<C>) async throws
        where C.Duration == Duration {
        guard !reserved else {
            await response.body?.close()
            throw NIOServiceFailure.duplicateResponse
        }
        reserved = true
        activeBody = response.body
        let channel = self.channel
        let maximumBodyBytes = self.maximumBodyBytes
        let maximumHeaderBytes = self.maximumHeaderBytes
        let suppressResponseBody = self.suppressResponseBody
        do {
            try await context.run {
                try await withTaskCancellationHandler {
                    guard (200...599).contains(response.status), channel.isActive else {
                        throw NIOServiceFailure.invalidHTTP
                    }
                    var headerBytes = 0
                    var headers = HTTPHeaders()
                    for header in response.headers {
                        guard nioIngressHeaderIsValid(header),
                              header.name.utf8.count <= maximumHeaderBytes - headerBytes else {
                            throw NIOServiceFailure.invalidHTTP
                        }
                        headerBytes += header.name.utf8.count
                        guard header.value.utf8.count <= maximumHeaderBytes - headerBytes else {
                            throw NIOServiceFailure.invalidHTTP
                        }
                        headerBytes += header.value.utf8.count
                        if !["content-length", "transfer-encoding", "connection"].contains(header.name.lowercased()) {
                            headers.add(name: header.name, value: header.value)
                        }
                    }
                    var bytes = Data()
                    if let body = response.body {
                        for try await chunk in body {
                            try Task.checkCancellation()
                            guard chunk.count <= maximumBodyBytes - bytes.count else {
                                throw TransportFailure.chunkTooLarge(limit: maximumBodyBytes,
                                                                      actual: bytes.count + chunk.count)
                            }
                            bytes.append(chunk)
                        }
                    }
                    if [204, 205, 304].contains(response.status) { bytes.removeAll() }
                    if response.status != 204 && response.status != 304 {
                        headers.add(name: "Content-Length", value: String(bytes.count))
                    }
                    headers.add(name: "Connection", value: "close")
                    let head = HTTPResponseHead(version: .http1_1, status: .init(statusCode: response.status), headers: headers)
                    try await channel.writeAndFlush(HTTPServerResponsePart.head(head)).get()
                    if !bytes.isEmpty && !suppressResponseBody {
                        try await channel.writeAndFlush(HTTPServerResponsePart.body(.byteBuffer(channel.allocator.buffer(bytes: bytes)))).get()
                    }
                    try await channel.writeAndFlush(HTTPServerResponsePart.end(nil)).get()
                } onCancel: { channel.close(promise: nil) }
            }
            await response.body?.close()
            await close()
        } catch {
            await response.body?.close()
            await close()
            throw nioServiceRedacted(error)
        }
    }

    /// Abandons the response slot and awaits one shared native socket close.
    /// Closing before response permanently reserves the slot against later sends.
    func close() async {
        reserved = true
        if let cleanup { await cleanup.value; return }
        let channel = self.channel
        let body = activeBody
        activeBody = nil
        let task = Task {
            channel.close(promise: nil)
            await body?.close()
            try? await channel.closeFuture.get()
        }
        cleanup = task
        await task.value
    }
}

/// Validates HTTP token names and field values before the native encoder sees them.
/// - Parameter header: Untrusted outgoing header; its contents are never logged.
/// - Returns: Whether the name is a nonempty ASCII token and the value excludes
///   forbidden controls, including CR/LF; horizontal tab and non-ASCII bytes are allowed.
private func nioIngressHeaderIsValid(_ header: HTTPHeader) -> Bool {
    let token = "!#$%&'*+-.^_`|~"
    return !header.name.isEmpty && header.name.utf8.allSatisfy {
        (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || token.utf8.contains($0)
    } && header.value.utf8.allSatisfy { $0 == 9 || ($0 >= 32 && $0 != 127) }
}
