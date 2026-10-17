import DiscordCore
import DiscordTransport
import Foundation

/// Lossless local RPC dispatch; secrets/user data are hidden from diagnostics.
public struct RPCDispatch: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let name: String
    public let data: JSONValue

    /// Stores an unknown-preserving event without interpreting remote Gateway shapes.
    /// - Parameters:
    ///   - name: Exact event name; unknown future names are retained.
    ///   - data: Event data, including unknown fields and lossless numbers.
    public init(name: String, data: JSONValue) { self.name = name; self.data = data }
    /// Returns a constant marker, hiding event identity and payload.
    public var description: String { "RPCDispatch(redacted)" }
    /// Uses the same secret-safe marker for debug formatting.
    public var debugDescription: String { description }
    /// Prevents reflective expansion of user data and activity join secrets.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}

/// Bounded local RPC v1 session with explicit connect/reconnect and close ownership.
///
/// Construction starts no I/O/tasks. `connect` sends a handshake and awaits READY,
/// then owns one reader and one demand-driven writer. Pending requests and queued
/// events have count/byte caps. Overload fails closed rather than silently losing
/// subscription data. Replies correlate by nonce **and** command. There is no
/// automatic mutation replay, authorization exchange or subscription restoration.
/// Reconnect starts a new generation; callers must authenticate and subscribe again.
/// The application owns this actor and must await `close` before releasing it.
public actor RPCClient<C: Clock> where C.Duration == Duration {
    private struct Pending {
        let command: String
        let frame: RPCFrame
        let event: String?
        let continuation: CheckedContinuation<JSONValue, any Error>
    }
    private let applicationID: ApplicationID
    private let clock: C
    private let connector: any RPCConnector
    private let maximumPendingRequests: Int
    private let maximumPendingBytes: Int
    private let maximumEvents: Int
    private let maximumEventBytes: Int
    private let maximumPayloadBytes: Int
    private var connection: (any RPCConnection)?
    private var connecting = false
    private var startup: Task<(any RPCConnection, JSONValue), any Error>?
    private var generation = UUID()
    private var reader: Task<Void, Never>?
    private var writer: Task<Void, Never>?
    private var pending: [String: Pending] = [:]
    private var outgoing: [String] = []
    private var controls: [RPCFrame] = []
    private var closing: Task<Void, Never>?
    private var pendingBytes = 0
    private var events: [(RPCDispatch, Int)] = []
    private var eventBytes = 0
    private var eventWaiter: (UUID, CheckedContinuation<RPCDispatch?, any Error>)?
    private var terminal: RPCFailure = .notConnected

    /// Configures session budgets without opening a socket or starting background work.
    /// - Parameters:
    ///   - applicationID: Registered local RPC application ID; bot credentials are never accepted.
    ///   - clock: Shared monotonic clock for reader/writer I/O; per-call contexts use this clock domain.
    ///   - connector: Fresh-connection factory for native IPC or approved legacy WebSockets.
    ///   - maximumPendingRequests: Positive request/continuation cap, default 128, at most 65,536.
    ///   - maximumPendingBytes: Positive sum of retained request payload bytes; default 4 MiB.
    ///   - maximumEvents: Positive buffered dispatch count cap, default 128, at most 65,536.
    ///   - maximumEventBytes: Positive buffered event UTF-8 byte cap, default 4 MiB.
    ///   - maximumPayloadBytes: Positive JSON frame cap, default 1 MiB, matching connector bounds.
    /// - Throws: Invalid or unsafe local budgets. No host/access qualification is inferred.
    public init(applicationID: ApplicationID, clock: C, connector: any RPCConnector,
                maximumPendingRequests: Int = 128, maximumPendingBytes: Int = 4_194_304,
                maximumEvents: Int = 128, maximumEventBytes: Int = 4_194_304,
                maximumPayloadBytes: Int = 1_048_576) throws {
        guard applicationID.rawValue != 0, (1...65_536).contains(maximumPendingRequests), (1...65_536).contains(maximumEvents),
              maximumPendingBytes > 0, maximumEventBytes > 0 else { throw RPCFailure.invalidConfiguration }
        _ = try RPCFrameDecoder(maximumPayloadBytes: maximumPayloadBytes)
        self.applicationID = applicationID; self.clock = clock; self.connector = connector
        self.maximumPendingRequests = maximumPendingRequests; self.maximumPendingBytes = maximumPendingBytes
        self.maximumEvents = maximumEvents; self.maximumEventBytes = maximumEventBytes
        self.maximumPayloadBytes = maximumPayloadBytes
    }

    /// Opens a session, handshakes at RPC v1 and validates the READY envelope/version before commands.
    /// - Parameter context: Startup cancellation/deadline; supply a deadline for absent/outdated hosts.
    /// - Returns: READY data, preserving server config/user/unknown fields; not proof of authentication.
    ///   Nested config/user schemas remain raw; use `RPCReady(value:)` when projection validation is required.
    /// - Throws: Already connected/connecting, cancellation, deadline, malformed READY or redacted I/O errors.
    ///   A failed/canceled startup closes its transport and starts no reader task.
    @discardableResult public func connect(context: TransportContext<C>) async throws -> JSONValue {
        try context.check()
        guard connection == nil, !connecting, closing == nil else { throw RPCFailure.alreadyConnected }
        if reader != nil || writer != nil {
            await close()
            try context.check()
            guard connection == nil, !connecting, closing == nil else { throw RPCFailure.alreadyConnected }
        }
        connecting = true; generation = UUID(); let session = generation
        let task = Task { try await self.startSession(session: session, context: context) }
        startup = task
        do {
            let (wire, ready) = try await withTaskCancellationHandler {
                try await task.value
            } onCancel: { task.cancel() }
            try context.check()
            guard connecting, generation == session else { throw RPCFailure.closed }
            connecting = false; startup = nil; terminal = .connectionLost
            reader = Task { await self.readLoop(wire: wire, session: session) }
            return ready
        } catch {
            task.cancel()
            if case .success(let (wire, _)) = await task.result { await wire.close() }
            if generation == session { connecting = false; startup = nil; connection = nil; terminal = .connectionLost }
            throw sanitized(error)
        }
    }

    /// Owns the complete startup operation so close can cancel and await late connection cleanup.
    /// - Parameters:
    ///   - session: Startup generation; superseded work cannot publish a replacement connection.
    ///   - context: Deadline/cancellation covering native open, handshake and READY.
    /// - Returns: Open owned connection and envelope/version-validated v1 READY data.
    ///   Nested configuration/user fields remain raw until explicitly projected through RPCReady.
    /// - Throws: Sanitized startup errors after awaiting any acquired connection's cleanup.
    private func startSession(session: UUID, context: TransportContext<C>) async throws -> (any RPCConnection, JSONValue) {
        var opened: (any RPCConnection)?
        do {
            let wire = try await connector.connect(applicationID: applicationID, context: context)
            opened = wire
            try context.check()
            guard connecting, generation == session else { throw RPCFailure.closed }
            connection = wire
            try await wire.handshake(applicationID: applicationID, context: context)
            while true {
                guard let frame = try await wire.receive(context: context) else { throw RPCFailure.connectionLost }
                try context.check()
                guard frame.payload.count <= maximumPayloadBytes else { throw RPCFailure.frameTooLarge }
                if frame.opcode == .ping { try await wire.send(.init(opcode: .pong, payload: frame.payload), context: context); continue }
                guard frame.opcode == .frame else { throw RPCFailure.malformedFrame }
                let envelope = try decode(frame.payload)
                if envelope["evt"] == .string("ERROR") { throw serverFailure(envelope) }
                guard envelope["cmd"] == .string("DISPATCH"), envelope["evt"] == .string("READY"),
                      envelope["nonce"] == nil || envelope["nonce"] == .null,
                      case .object(let data) = envelope["data"], data["v"] == .number(try JSONNumber(rawValue: "1")) else { throw RPCFailure.invalidPayload }
                return (wire, .object(data))
            }
        } catch {
            if let opened { await opened.close() }
            throw sanitized(error)
        }
    }

    /// Closes the prior generation, rejects its waiters, then opens a fresh session.
    /// - Parameter context: Deadline/cancellation for fresh startup after owned cleanup.
    /// - Returns: New READY data. Authentication/subscriptions must be explicitly restored.
    /// - Throws: Startup errors; old requests are never replayed, including after process restart.
    @discardableResult public func reconnect(context: TransportContext<C>) async throws -> JSONValue {
        await close()
        return try await connect(context: context)
    }

    /// Sends one bounded command and waits for its exact nonce/command response.
    /// - Parameters:
    ///   - request: Typed local RPC request; server enforces scopes and tester/approval access.
    ///   - context: Independent request cancellation/deadline; no deadline permits a bounded indefinite waiter.
    /// - Returns: Response `data`, including explicit null, lossless numbers and unknown fields.
    /// - Throws: Not connected, count/byte overload, invalid payload, numeric server error,
    ///   cancellation/deadline or connection loss. After admission a canceled or lost mutation
    ///   may already have executed; callers must reconcile, never blindly replay it.
    ///   Cancellation removes this caller's waiter/queued write. An already admitted
    ///   native write remains session-owned until completion or explicit client close.
    public func request(_ request: RPCRequest, context: TransportContext<C>) async throws -> JSONValue {
        try context.check()
        let nonce = UUID().uuidString
        var object: [String: JSONValue] = ["cmd": .string(request.command.rawValue), "nonce": .string(nonce), "args": .object(request.arguments)]
        if let event = request.event { object["evt"] = .string(event.rawValue) }
        let payload: Data
        do { payload = try JSONValue.object(object).serialized(limits: .init(maximumBytes: maximumPayloadBytes)) }
        catch { throw RPCFailure.invalidPayload }
        return try await context.run {
            try await withTaskCancellationHandler {
                try await self.enqueue(nonce: nonce, command: request.command.rawValue, event: request.event?.rawValue, payload: payload)
            } onCancel: { Task { await self.cancelRequest(nonce) } }
        }
    }

    /// Pulls one bounded dispatch; exactly one event consumer may wait at a time.
    /// - Parameter context: Consumer cancellation/deadline, independent of the session reader.
    /// - Returns: Next event in wire order; nil after explicit close when no events remain.
    /// - Throws: Concurrent consumer, cancellation, deadline, connection loss or event overflow.
    ///   Canceling an event waiter never closes the RPC session or drops another waiter's data.
    public func nextEvent(context: TransportContext<C>) async throws -> RPCDispatch? {
        try context.check()
        let id = UUID()
        return try await context.run {
            try await withTaskCancellationHandler {
                try await self.takeEvent(id: id)
            } onCancel: { Task { await self.cancelEvent(id) } }
        }
    }

    /// Reports bounded ownership counts without exposing nonces, payloads or identities.
    /// - Returns: Pending requests, retained request bytes, buffered events and event bytes.
    public func resourceCounts() -> (pending: Int, pendingBytes: Int, events: Int, eventBytes: Int) {
        (pending.count, pendingBytes, events.count, eventBytes)
    }

    /// Rejects all waiters, discards queues and awaits reader/writer/transport cleanup.
    /// Cancellation does not skip cleanup. Repeated closure is safe; a later connect is explicit.
    /// Wire CLOSE is not required for disposal and is not sent ahead of pending writes.
    public func close() async {
        if let closing { await closing.value; return }
        let oldReader = reader; let oldWriter = writer; let oldConnection = connection; let oldStartup = startup
        generation = UUID(); connecting = false; connection = nil; reader = nil; writer = nil; startup = nil
        terminal = .closed; rejectPending(.closed)
        events.removeAll(); eventBytes = 0
        eventWaiter?.1.resume(returning: nil); eventWaiter = nil
        oldReader?.cancel(); oldWriter?.cancel(); oldStartup?.cancel()
        let cleanup = Task {
            await oldConnection?.close()
            if let oldStartup, case .success(let (wire, _)) = await oldStartup.result { await wire.close() }
            await oldReader?.value; await oldWriter?.value
        }
        closing = cleanup
        await cleanup.value
        closing = nil
    }

    /// Registers a request atomically before scheduling the sole bounded writer.
    /// - Parameters:
    ///   - nonce: Unique local correlation ID, never reused across generations.
    ///   - command: Exact expected response command.
    ///   - event: Expected subscription event name, nil for ordinary command replies.
    ///   - payload: Already bounded JSON bytes retained until completion/cancellation.
    /// - Returns: Server response data when the continuation is resolved.
    /// - Throws: Pre-admission cancellation, disconnection or local overload.
    private func enqueue(nonce: String, command: String, event: String?, payload: Data) async throws -> JSONValue {
        try Task.checkCancellation()
        guard connection != nil, !connecting else { throw RPCFailure.notConnected }
        guard pending.count < maximumPendingRequests, payload.count <= maximumPendingBytes - pendingBytes else { throw RPCFailure.overloaded }
        return try await withCheckedThrowingContinuation { continuation in
            pending[nonce] = Pending(command: command, frame: .init(opcode: .frame, payload: payload), event: event, continuation: continuation)
            pendingBytes += payload.count; outgoing.append(nonce)
            if writer == nil { let session = generation; writer = Task { await self.writeLoop(session: session) } }
        }
    }

    /// Removes one canceled/timed-out request without touching other callers or replaying bytes.
    /// - Parameter nonce: Exact request ID; stale/duplicate cancellation is a no-op.
    private func cancelRequest(_ nonce: String) {
        if let item = pending.removeValue(forKey: nonce) {
            pendingBytes -= item.frame.payload.count
            outgoing.removeAll { $0 == nonce }
            item.continuation.resume(throwing: CancellationError())
        }
    }

    /// Serializes all request writes; each suspension checks the captured generation.
    /// - Parameter session: Generation owning this writer; stale tasks cannot affect replacements.
    private func writeLoop(session: UUID) async {
        while generation == session, let wire = connection, !controls.isEmpty || !outgoing.isEmpty {
            let frame: RPCFrame
            if !controls.isEmpty { frame = controls.removeFirst() }
            else {
                let nonce = outgoing.removeFirst()
                guard let item = pending[nonce] else { continue }
                frame = item.frame
            }
            do { try await wire.send(frame, context: .init(clock: clock)) }
            catch { await fail(session: session, error: .connectionLost); return }
        }
        if generation == session { writer = nil }
    }

    /// Receives messages independently of command callers and user event processing.
    /// - Parameters:
    ///   - wire: Exclusively owned connection for the captured generation.
    ///   - session: Generation fence preventing old EOF/errors from closing a replacement.
    private func readLoop(wire: any RPCConnection, session: UUID) async {
        do {
            while let frame = try await wire.receive(context: TransportContext(clock: clock)) {
                guard generation == session else { return }
                guard frame.payload.count <= maximumPayloadBytes else { throw RPCFailure.frameTooLarge }
                if frame.opcode == .ping {
                    guard controls.isEmpty else { throw RPCFailure.overloaded }
                    controls.append(.init(opcode: .pong, payload: frame.payload))
                    if writer == nil { writer = Task { await self.writeLoop(session: session) } }
                    continue
                }
                if frame.opcode == .pong { continue }
                guard frame.opcode == .frame else { throw RPCFailure.connectionLost }
                try accept(frame.payload)
            }
            await fail(session: session, error: .connectionLost)
        } catch { await fail(session: session, error: (error as? RPCFailure) ?? .connectionLost) }
    }

    /// Parses a bounded JSON object with fixed failures that never expand peer bytes.
    /// - Parameter payload: Complete JSON UTF-8 document within the local cap.
    /// - Returns: Object members preserving unknown values and numeric lexemes.
    /// - Throws: `.invalidPayload` for malformed/non-object/over-budget JSON.
    private func decode(_ payload: Data) throws -> [String: JSONValue] {
        do {
            guard case .object(let object) = try JSONValue.parse(payload, limits: .init(maximumBytes: maximumPayloadBytes)) else { throw RPCFailure.invalidPayload }
            return object
        } catch { throw RPCFailure.invalidPayload }
    }

    /// Delivers a matched reply or bounded dispatch, rejecting malformed correlation.
    /// - Parameter payload: Complete standard FRAME JSON bytes.
    /// - Throws: Invalid shape/command mismatch or event overload; unknown late nonces are ignored.
    private func accept(_ payload: Data) throws {
        let envelope = try decode(payload)
        guard case .string(let command) = envelope["cmd"] else { throw RPCFailure.invalidPayload }
        if case .string(let nonce) = envelope["nonce"] {
            guard let item = pending[nonce] else { return }
            guard command == item.command, envelope["data"] != nil else { throw RPCFailure.invalidPayload }
            if envelope["evt"] != .string("ERROR") {
                if let event = item.event {
                    guard envelope["evt"] == nil || envelope["evt"] == .null,
                          case .object(let acknowledgement) = envelope["data"],
                          acknowledgement["evt"] == .string(event) else { throw RPCFailure.invalidPayload }
                } else {
                    guard envelope["evt"] == nil || envelope["evt"] == .null else { throw RPCFailure.invalidPayload }
                }
            }
            pending.removeValue(forKey: nonce); pendingBytes -= item.frame.payload.count
            outgoing.removeAll { $0 == nonce }
            if envelope["evt"] == .string("ERROR") { item.continuation.resume(throwing: serverFailure(envelope)) }
            else { item.continuation.resume(returning: envelope["data"]!) }
            return
        }
        guard command == "DISPATCH", case .string(let name) = envelope["evt"], let data = envelope["data"],
              envelope["nonce"] == nil || envelope["nonce"] == .null else { throw RPCFailure.invalidPayload }
        let event = RPCDispatch(name: name, data: data)
        if let waiter = eventWaiter { eventWaiter = nil; waiter.1.resume(returning: event); return }
        guard events.count < maximumEvents, payload.count <= maximumEventBytes - eventBytes else { throw RPCFailure.overloaded }
        events.append((event, payload.count)); eventBytes += payload.count
    }

    /// Extracts only an integer server code; free-form messages are intentionally discarded.
    /// - Parameter envelope: Parsed ERROR response with optional numeric data.code.
    /// - Returns: Safe numeric server failure or invalid-payload failure for malformed codes.
    private func serverFailure(_ envelope: [String: JSONValue]) -> RPCFailure {
        guard case .object(let data) = envelope["data"], case .number(let code) = data["code"], let value = Int(code.rawValue) else { return .invalidPayload }
        return .server(code: value)
    }

    /// Removes/resolves every pending continuation exactly once and clears retained requests.
    /// - Parameter error: Fixed terminal error, shared across this generation's pending requests.
    private func rejectPending(_ error: RPCFailure) {
        let previous = pending; pending.removeAll(); outgoing.removeAll(); controls.removeAll(); pendingBytes = 0
        for item in previous.values { item.continuation.resume(throwing: error) }
    }

    /// Terminates one generation after EOF, malformed data, overflow or a failed write.
    /// - Parameters:
    ///   - session: Fence; stale task failures are ignored.
    ///   - error: Safe terminal reason without peer-controlled descriptions.
    private func fail(session: UUID, error: RPCFailure) async {
        guard generation == session else { return }
        generation = UUID(); terminal = error
        let wire = connection; connection = nil
        reader?.cancel(); writer?.cancel()
        rejectPending(error); events.removeAll(); eventBytes = 0
        eventWaiter?.1.resume(throwing: error); eventWaiter = nil
        await wire?.close()
    }

    /// Takes a queued event or installs the single cancellable consumer continuation.
    /// - Parameter id: Unique waiter ownership token.
    /// - Returns: Event, or nil following explicit close.
    /// - Throws: Cancellation, concurrent consumer or terminal session failure.
    private func takeEvent(id: UUID) async throws -> RPCDispatch? {
        try Task.checkCancellation()
        guard eventWaiter == nil else { throw RPCFailure.concurrentRead }
        if !events.isEmpty { let next = events.removeFirst(); eventBytes -= next.1; return next.0 }
        guard connection != nil, !connecting else {
            if terminal == .closed { return nil }; throw terminal
        }
        return try await withCheckedThrowingContinuation { eventWaiter = (id, $0) }
    }

    /// Cancels only the event continuation belonging to the supplied ownership token.
    /// - Parameter id: Waiter ID; stale cancellation cannot affect a subsequent reader.
    private func cancelEvent(_ id: UUID) {
        guard eventWaiter?.0 == id else { return }
        eventWaiter?.1.resume(throwing: CancellationError()); eventWaiter = nil
    }

    /// Keeps known cancellation/deadline/protocol errors and redacts arbitrary adapter errors.
    /// - Parameter error: Potentially secret-bearing original error.
    /// - Returns: Safe typed failure without an adapter's raw diagnostic text.
    private func sanitized(_ error: any Error) -> any Error {
        if Task.isCancelled || error is CancellationError { return CancellationError() }
        if let failure = error as? RPCFailure { return failure }
        if error as? TransportFailure == .deadlineExceeded { return TransportFailure.deadlineExceeded }
        return RPCFailure.connectionLost
    }
}
