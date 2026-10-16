import DiscordTransport
import Foundation

/// A finite, per-test HTTP script. It performs no network requests or implicit retries.
public actor ScriptedHTTPTransport: HTTPTransport {
    public typealias Step = @Sendable (HTTPRequest) async throws -> HTTPResponse
    private let steps: [Step]
    private var index = 0
    public private(set) var executionCount = 0

    /// Stores finite scripted operations, consumed in actor admission order.
    /// - Parameters:
    ///   - steps: Success, failure or cooperative suspended operations.
    ///   - maximumSteps: Positive upper bound, default 1,024.
    /// - Throws: `TestSupportFailure.capacityExceeded` for invalid/exceeded capacity.
    public init(steps: [Step], maximumSteps: Int = 1_024) throws {
        guard maximumSteps > 0, steps.count <= maximumSteps else { throw TestSupportFailure.capacityExceeded }
        self.steps = steps
    }

    /// Executes a single reserved step under the supplied monotonic deadline.
    ///
    /// Request bodies close on every path; failed or late response bodies close too.
    /// Cancellation and expiration are rechecked after response-slot suspension,
    /// before successful ownership transfer. Pre-cancellation/expiration do not
    /// consume a script; admitted steps are never replayed after any failure.
    /// - Parameters:
    ///   - request: Request exposed to one script step; body ownership transfers here.
    ///   - context: Clock/deadline; suspended steps must cooperate with cancellation.
    /// - Returns: Scripted response whose body ownership transfers to the caller.
    /// - Throws: `TransportFailure.scriptExhausted` when no step remains,
    ///   `CancellationError` when cancellation is observed before transfer,
    ///   `TransportFailure.deadlineExceeded` at inclusive expiration, or the
    ///   script's original error. Owned bodies finish cleanup before throwing.
    public func execute<C: Clock>(_ request: HTTPRequest, context: TransportContext<C>) async throws -> HTTPResponse
        where C.Duration == Duration {
        let slot = ResponseSlot()
        var pendingResponse: HTTPResponse?
        do {
            try context.check()
            guard index < steps.count else { throw TransportFailure.scriptExhausted }
            let step = steps[index]
            index += 1
            executionCount += 1
            try await context.run {
                let response = try await step(request)
                await slot.store(response)
                try Task.checkCancellation()
            }
            await request.body?.close()
            try context.check()
            pendingResponse = await slot.take()
            try context.check()
            guard let response = pendingResponse else { throw TransportFailure.scriptExhausted }
            return response
        } catch {
            await request.body?.close()
            await pendingResponse?.body?.close()
            await slot.take()?.body?.close()
            throw error
        }
    }

    /// Holds response ownership across a deadline race until successful transfer.
    private actor ResponseSlot {
        var response: HTTPResponse?

        /// Retains one response until transfer or cleanup after a failed execution.
        /// - Parameter response: Newly produced response, including optional body.
        func store(_ response: HTTPResponse) { self.response = response }

        /// Removes retained ownership; later calls return no value.
        /// - Returns: Previously retained response, or `nil` when already transferred.
        func take() -> HTTPResponse? {
            defer { response = nil }
            return response
        }
    }
}

/// Finite WebSocket input/output storage with exactly-once connection accounting.
public actor ScriptedWebSocketConnection: WebSocketConnection {
    private let incoming: [WebSocketMessage]
    private let maximumMessages: Int
    private let lease: ResourceLease?
    private var index = 0
    private var closed = false
    public private(set) var sent: [WebSocketMessage] = []

    /// Creates a connection with finite input and an independent finite output bound.
    /// - Parameters:
    ///   - incoming: Ordered complete messages; empty means immediate EOF.
    ///   - maximumMessages: Positive input/output message capacity, default 1,024.
    ///   - lease: Optional resource accounting token released at close or receive EOF.
    /// - Throws: Invalid or exceeded capacity.
    public init(incoming: [WebSocketMessage], maximumMessages: Int = 1_024, lease: ResourceLease? = nil) throws {
        guard maximumMessages > 0, incoming.count <= maximumMessages else { throw TestSupportFailure.capacityExceeded }
        self.incoming = incoming; self.maximumMessages = maximumMessages; self.lease = lease
    }

    /// Records one outbound message after validating cancellation/deadline and capacity.
    /// - Parameters:
    ///   - message: Complete output message; text and binary remain distinct.
    ///   - context: Injected monotonic clock and deadline.
    /// - Throws: Cancellation, expiration, closed connection or output capacity overflow.
    public func send<C: Clock>(_ message: WebSocketMessage, context: TransportContext<C>) async throws
        where C.Duration == Duration {
        try context.check()
        guard !closed else { throw TransportFailure.closed }
        guard sent.count < maximumMessages else { throw TestSupportFailure.capacityExceeded }
        sent.append(message)
    }

    /// Consumes messages in admission order, closing at the first EOF read.
    /// - Parameter context: Cancellation and deadline for this immediate pull.
    /// - Returns: A scripted message, or `nil` after EOF or explicit close.
    /// - Throws: Cancellation or expiration before input consumption.
    public func receive<C: Clock>(context: TransportContext<C>) async throws -> WebSocketMessage?
        where C.Duration == Duration {
        try context.check()
        guard !closed else { return nil }
        guard index < incoming.count else { await close(); return nil }
        defer { index += 1 }
        return incoming[index]
    }

    /// Closes once, rejects further sends and releases the optional resource lease.
    /// No background I/O exists; input not consumed before closure is discarded.
    public func close() async {
        closed = true
        await lease?.release()
    }
}

/// An injected WebSocket factory for a single test-owned connection.
public struct ScriptedWebSocketTransport: WebSocketTransport {
    private let connection: any WebSocketConnection

    /// Stores an established scripted connection without acquiring another resource.
    /// - Parameter connection: Connection returned by successful upgrades; caller closes it.
    public init(connection: any WebSocketConnection) { self.connection = connection }

    /// Validates cancellation/deadline and returns the supplied test connection.
    /// - Parameters:
    ///   - request: Upgrade request; a body is rejected and closed.
    ///   - context: Clock/deadline governing this immediate scripted upgrade.
    /// - Returns: The injected connection; repeated upgrades share its ownership.
    /// - Throws: Cancellation, expiration, or a scripted error for a request body.
    public func connectWebSocket<C: Clock>(_ request: HTTPRequest, context: TransportContext<C>) async throws
        -> any WebSocketConnection where C.Duration == Duration {
        do {
            try context.check()
            guard request.body == nil else { throw TestSupportFailure.scripted("WebSocket upgrade body") }
            return connection
        } catch {
            await request.body?.close()
            throw error
        }
    }
}

/// Finite datagram input and output, preserving packet boundaries including empties.
public actor ScriptedDatagramTransport: DatagramTransport {
    private let incoming: [Datagram]
    private let maximumDatagrams: Int
    private var index = 0
    private var closed = false
    public private(set) var sent: [Datagram] = []

    /// Creates an isolated datagram script without sockets or DNS.
    /// - Parameters:
    ///   - incoming: Packets returned in script order, without claiming network ordering.
    ///   - maximumDatagrams: Positive input/output capacity, default 1,024.
    /// - Throws: Invalid or exceeded capacity.
    public init(incoming: [Datagram], maximumDatagrams: Int = 1_024) throws {
        guard maximumDatagrams > 0, incoming.count <= maximumDatagrams else { throw TestSupportFailure.capacityExceeded }
        self.incoming = incoming; self.maximumDatagrams = maximumDatagrams
    }

    /// Records an entire outbound datagram once within the finite output capacity.
    /// - Parameters:
    ///   - datagram: Payload and destination, including valid empty payloads.
    ///   - context: Deadline/cancellation checked before storage mutation.
    /// - Throws: Cancellation, expiration, closed state or capacity overflow.
    public func sendDatagram<C: Clock>(_ datagram: Datagram, context: TransportContext<C>) async throws
        where C.Duration == Duration {
        try context.check()
        guard !closed else { throw TransportFailure.closed }
        guard sent.count < maximumDatagrams else { throw TestSupportFailure.capacityExceeded }
        sent.append(datagram)
    }

    /// Pulls one complete scripted datagram; EOF does not manufacture a zero-byte packet.
    /// - Parameter context: Deadline/cancellation checked before consumption.
    /// - Returns: Scripted packet or `nil` after script exhaustion/close.
    /// - Throws: Cancellation or expiration.
    public func receiveDatagram<C: Clock>(context: TransportContext<C>) async throws -> Datagram?
        where C.Duration == Duration {
        try context.check()
        guard !closed, index < incoming.count else { return nil }
        defer { index += 1 }
        return incoming[index]
    }

    /// Discards unconsumed input and rejects subsequent output; repeated calls are safe.
    public func close() async { closed = true }
}

/// Finite local byte-stream script; reads may split original input chunk boundaries.
public actor ScriptedIPCTransport: IPCTransport {
    private var incoming: Data
    private let maximumWrittenBytes: Int
    private var closed = false
    public private(set) var written = Data()

    /// Stores input and output bounds without opening platform IPC facilities.
    /// - Parameters:
    ///   - incoming: Finite bytes returned by later reads; empty means EOF.
    ///   - maximumWrittenBytes: Positive cumulative output bound, default 65,536.
    /// - Throws: Invalid output capacity.
    public init(incoming: Data, maximumWrittenBytes: Int = 65_536) throws {
        guard maximumWrittenBytes > 0 else { throw TestSupportFailure.capacityExceeded }
        self.incoming = incoming; self.maximumWrittenBytes = maximumWrittenBytes
    }

    /// Appends bytes atomically in actor admission order, bounded cumulatively.
    /// - Parameters:
    ///   - bytes: Output bytes; an empty write succeeds without consuming capacity.
    ///   - context: Deadline/cancellation checked before mutation.
    /// - Throws: Cancellation, expiration, closure or capacity overflow; output is unchanged.
    public func write<C: Clock>(_ bytes: Data, context: TransportContext<C>) async throws
        where C.Duration == Duration {
        try context.check()
        guard !closed else { throw TransportFailure.closed }
        guard bytes.count <= maximumWrittenBytes - written.count else { throw TestSupportFailure.capacityExceeded }
        written.append(bytes)
    }

    /// Consumes a nonempty prefix bounded by the requested read limit.
    /// - Parameters:
    ///   - maximumBytes: Positive limit; zero/negative fail without consuming bytes.
    ///   - context: Deadline/cancellation checked before mutation.
    /// - Returns: Bounded bytes, or `nil` for script EOF/closed ownership.
    /// - Throws: Invalid limit, cancellation or expiration.
    public func read<C: Clock>(maximumBytes: Int, context: TransportContext<C>) async throws -> Data?
        where C.Duration == Duration {
        try context.check()
        guard maximumBytes > 0 else { throw TransportFailure.invalidLimit }
        guard !closed, !incoming.isEmpty else { return nil }
        let chunk = Data(incoming.prefix(maximumBytes))
        incoming.removeFirst(chunk.count)
        return chunk
    }

    /// Discards remaining input and rejects writes. Repeated closure has no further effect.
    public func close() async { closed = true; incoming.removeAll() }
}
