#if canImport(Darwin)
import DiscordTransport
import Foundation
import os

/// Apple WebSocket adapter with bounded messages, pending writes and live connections.
///
/// Foundation owns frame/control handling and platform handshake negotiation; this
/// adapter adds no Gateway compression policy, retry or reconnection. On watchOS
/// it fails before network work: a
/// generic bot connection does not establish an OS-authorized low-level use case.
/// See Apple's TN3135; supported watch-specific authorization needs a separate adapter.
public struct FoundationWebSocketTransport: WebSocketTransport, TransportResource {
    private let owner: FoundationSession
    public let configuration: FoundationTransportConfiguration

    /// Creates an owned ephemeral session with no connection established yet.
    /// - Parameter configuration: Validated connection, message and queue limits.
    public init(configuration: FoundationTransportConfiguration) {
        self.configuration = configuration
        owner = FoundationSession(configuration: configuration)
    }

    /// Establishes one ws/wss GET connection and waits for the completed upgrade.
    /// - Parameters:
    ///   - request: Upgrade URL and unique valid headers; bodies are rejected and closed.
    ///   - context: Clock/deadline covering admission and the entire upgrade handshake.
    /// - Returns: Caller-owned ordered connection; its slot is retained until close/EOF.
    /// - Throws: Cancellation, deadline, admission, invalid request, redacted native
    ///   failure, closure or `unavailableCapability` on watchOS. Never reconnects.
    public func connectWebSocket<C: Clock>(_ request: HTTPRequest, context: TransportContext<C>) async throws
    -> any WebSocketConnection where C.Duration == Duration {
        #if os(watchOS)
        await request.body?.close()
        throw FoundationTransportFailure.unavailableCapability
        #else
        var identifier: UUID?
        do {
            try context.check()
            let platform = try foundationRequest(request, webSocket: true)
            let reserved = try await owner.reserve { await request.body?.close() }
            identifier = reserved
            let task = owner.session.webSocketTask(with: platform)
            task.maximumMessageSize = configuration.maximumWebSocketMessageBytes
            let handshake = FoundationWebSocketHandshake()
            let delegate = FoundationWebSocketDelegate(handshake: handshake)
            task.delegate = delegate
            let connection = FoundationWebSocketConnection(task: task, delegate: delegate, owner: owner,
                                                         identifier: reserved, configuration: configuration)
            do { try await owner.register(reserved) { await connection.close() } }
            catch { await connection.close(); throw error }
            try await context.run {
                try await withTaskCancellationHandler {
                    task.resume()
                    try await handshake.wait()
                } onCancel: {
                    task.cancel()
                    Task { await handshake.finish(.failure(CancellationError())) }
                }
            }
            return connection
        } catch {
            await request.body?.close()
            if let identifier { await owner.abandon(identifier) }
            throw foundationFailure(error)
        }
        #endif
    }

    /// Cancels every admitted connection and awaits session invalidation exactly once.
    public func close() async { await owner.close() }
}

/// One-shot handshake state supporting callback-before-wait and cancellation races.
private actor FoundationWebSocketHandshake {
    private var result: Result<Void, any Error>?
    private var waiter: CheckedContinuation<Void, any Error>?

    /// Awaits an actual successful HTTP upgrade rather than merely task creation.
    /// - Throws: Upgrade, cancellation or native failure supplied by the delegate.
    func wait() async throws {
        if let result { return try result.get() }
        try await withCheckedThrowingContinuation { waiter = $0 }
    }

    /// Resolves the single handshake waiter once, preserving whichever outcome won.
    /// - Parameter result: Safe success or redacted transport failure.
    func finish(_ result: Result<Void, any Error>) {
        guard self.result == nil else { return }
        self.result = result
        waiter?.resume(with: result)
        waiter = nil
    }
}

/// Bridges upgrade completion and numeric peer closure; native send/receive use Foundation's async APIs.
private final class FoundationWebSocketDelegate: NSObject, URLSessionWebSocketDelegate {
    let handshake: FoundationWebSocketHandshake
    let peerCode = OSAllocatedUnfairLock<Int?>(initialState: nil)

    /// Stores isolated handshake state without retaining request metadata.
    /// - Parameter handshake: One-shot state owned by the connecting operation.
    init(handshake: FoundationWebSocketHandshake) { self.handshake = handshake }

    /// Rejects upgrade redirects even when this per-task delegate overrides session policy.
    /// - Parameters:
    ///   - session: Owning ephemeral session.
    ///   - task: Redirecting upgrade task; it is never automatically replayed.
    ///   - response: Redirect response, never retained in diagnostics.
    ///   - request: Proposed destination, deliberately rejected to protect headers.
    ///   - completionHandler: Completed exactly once with no redirect request.
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }

    /// Preserves system TLS validation while rejecting HTTP credential challenge retries.
    /// - Parameters:
    ///   - session: Owning ephemeral session without persistent credentials.
    ///   - task: Challenged upgrade task.
    ///   - challenge: Native trust or HTTP authentication challenge.
    ///   - completionHandler: Completed once with default trust evaluation or cancellation.
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
            completionHandler(.performDefaultHandling, nil)
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }

    /// Completes establishment only after Foundation accepts the server upgrade.
    /// - Parameters:
    ///   - session: Owning ephemeral session.
    ///   - webSocketTask: Task whose upgrade has completed.
    ///   - protocol: Negotiated protocol, ignored because this adapter requests none.
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didOpenWithProtocol protocol: String?) {
        Task { await handshake.finish(.success(())) }
    }

    /// Resolves a handshake that failed before upgrade without retaining error details.
    /// - Parameters:
    ///   - session: Owning ephemeral session.
    ///   - task: Failed/finished task.
    ///   - error: Optional native error; only a redacted numeric failure is exported.
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        let failure = error.map { foundationFailure($0) } ?? TransportFailure.closed
        Task { await handshake.finish(.failure(failure)) }
    }

    /// Retains only numeric peer status and resolves a premature close before upgrade.
    /// The synchronized status remains available after connection/session cleanup.
    /// - Parameters:
    ///   - session: Owning ephemeral session.
    ///   - webSocketTask: Closed task.
    ///   - closeCode: Protocol status, not converted into retry policy.
    ///   - reason: Potentially sensitive peer data; deliberately discarded.
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        peerCode.withLock { $0 = closeCode.rawValue }
        Task { await handshake.finish(.failure(TransportFailure.closed)) }
    }
}

/// Serializes bounded writes and permits one outstanding receive, with terminal cancellation.
private actor FoundationWebSocketConnection: WebSocketSessionConnection {
    private let task: URLSessionWebSocketTask
    private let delegate: FoundationWebSocketDelegate
    private let owner: FoundationSession
    private let identifier: UUID
    private let configuration: FoundationTransportConfiguration
    private var closed = false
    private var closeTask: Task<Void, Never>?
    private var reading = false
    private var writing = false
    private var writers: [CheckedContinuation<Void, any Error>] = []

    /// Transfers one admitted task and keeps its per-task handshake delegate alive.
    /// - Parameters:
    ///   - task: Platform task with a configured incoming message ceiling.
    ///   - delegate: Delegate retained for the full connection lifetime.
    ///   - owner: Session admission coordinator.
    ///   - identifier: Resource slot released exactly once at terminal close.
    ///   - configuration: Message and pending-writer limits.
    init(task: URLSessionWebSocketTask, delegate: FoundationWebSocketDelegate,
         owner: FoundationSession, identifier: UUID, configuration: FoundationTransportConfiguration) {
        self.task = task
        self.delegate = delegate
        self.owner = owner
        self.identifier = identifier
        self.configuration = configuration
    }

    /// Validates and serializes a complete message without an unbounded writer queue.
    /// Cancellation/deadline closes the connection and unblocks all pending writers.
    /// - Parameters:
    ///   - message: Text measured in UTF-8 bytes, or binary data, within the configured cap.
    ///   - context: Clock/deadline including bounded writer admission and native send.
    /// - Throws: Cancellation, deadline, closed, queue admission, message limit or native failure.
    func send<C: Clock>(_ message: WebSocketMessage, context: TransportContext<C>) async throws
    where C.Duration == Duration {
        try context.check()
        let platform: URLSessionWebSocketTask.Message
        let count: Int
        switch message {
        case .text(let text): platform = .string(text); count = text.utf8.count
        case .binary(let bytes): platform = .data(bytes); count = bytes.count
        }
        guard count <= configuration.maximumWebSocketMessageBytes else {
            throw FoundationTransportFailure.messageLimitExceeded(limit: configuration.maximumWebSocketMessageBytes)
        }
        let task = self.task
        do {
            try await context.run {
                try await withTaskCancellationHandler {
                    try await self.acquireWrite()
                    do { try await task.send(platform) }
                    catch { await self.releaseWrite(); throw error }
                    await self.releaseWrite()
                } onCancel: {
                    task.cancel(with: .protocolError, reason: nil)
                    task.cancel()
                    Task { await self.closeForReconnect() }
                }
            }
        } catch {
            if error as? FoundationTransportFailure != .admissionRejected { await closeForReconnect() }
            throw foundationFailure(error)
        }
    }

    /// Reserves the current write or queues within the configured per-connection count.
    /// - Throws: Closure or immediate admission failure when the bounded queue is full.
    private func acquireWrite() async throws {
        guard !closed else { throw TransportFailure.closed }
        if !writing { writing = true; return }
        guard writers.count < configuration.maximumConcurrentOperations else {
            throw FoundationTransportFailure.admissionRejected
        }
        try await withCheckedThrowingContinuation { writers.append($0) }
        try Task.checkCancellation()
        guard !closed else { throw TransportFailure.closed }
    }

    /// Transfers writer ownership in FIFO order without retaining completed messages.
    private func releaseWrite() {
        if writers.isEmpty { writing = false }
        else { writers.removeFirst().resume() }
    }

    /// Pulls one complete native message, rejecting simultaneous readers immediately.
    /// Peer status is copied before local cleanup even when the delegate callback is pending.
    /// - Parameter context: Injected deadline and cancellation for this read only.
    /// - Returns: Ordered text/binary message, or `nil` after a normal/going-away peer close.
    /// - Throws: Concurrent read, cancellation, deadline, closure, size or native failure.
    func receive<C: Clock>(context: TransportContext<C>) async throws -> WebSocketMessage?
    where C.Duration == Duration {
        try context.check()
        guard !closed else { return nil }
        guard !reading else { throw TransportFailure.concurrentRead }
        reading = true
        defer { reading = false }
        let task = self.task
        do {
            let message = try await context.run {
                try await withTaskCancellationHandler {
                    try await task.receive()
                } onCancel: {
                    task.cancel(with: .protocolError, reason: nil)
                    task.cancel()
                }
            }
            guard !closed else { return nil }
            switch message {
            case .string(let text):
                guard text.utf8.count <= configuration.maximumWebSocketMessageBytes else {
                    throw FoundationTransportFailure.messageLimitExceeded(limit: configuration.maximumWebSocketMessageBytes)
                }
                return .text(text)
            case .data(let bytes):
                guard bytes.count <= configuration.maximumWebSocketMessageBytes else {
                    throw FoundationTransportFailure.messageLimitExceeded(limit: configuration.maximumWebSocketMessageBytes)
                }
                return .binary(bytes)
            @unknown default: throw FoundationTransportFailure.invalidResponse
            }
        } catch {
            let ownedFailure = error is CancellationError || error is TransportFailure || error is FoundationTransportFailure
            let status = task.closeCode.rawValue
            if !ownedFailure, !Task.isCancelled, !closed, (1_000...4_999).contains(status),
               ![1_004, 1_005, 1_006, 1_015].contains(status) {
                delegate.peerCode.withLock { if $0 == nil { $0 = status } }
            }
            let orderly = !ownedFailure && !Task.isCancelled && (task.closeCode == .normalClosure || task.closeCode == .goingAway)
            let nativeError = error as NSError
            let oversized = task.closeCode == .messageTooBig || (error as? URLError)?.code == .dataLengthExceedsMaximum
                || (nativeError.domain == NSPOSIXErrorDomain && nativeError.code == Int(EMSGSIZE))
            await closeForReconnect()
            if orderly { return nil }
            if oversized { throw FoundationTransportFailure.messageLimitExceeded(limit: configuration.maximumWebSocketMessageBytes) }
            throw foundationFailure(error)
        }
    }

    /// Unblocks native I/O and all queued writers, then releases aggregate admission.
    /// Repeated callers are harmless; the session owner separately awaits invalidation.
    func close() async { await finishClose(code: .goingAway) }

    /// Ends I/O using protocol-error closure rather than session-invalidating 1000/1001.
    /// Foundation owns the actual frame/abort; cleanup releases the admission slot once.
    func closeForReconnect() async { await finishClose(code: .protocolError) }

    /// Reports peer close status captured by the native delegate or receive failure path.
    /// - Returns: Peer numeric code after a received close frame, or `nil` for abrupt/local abort.
    func peerCloseCode() async -> Int? { delegate.peerCode.withLock { $0 } }

    /// Serializes terminal cleanup and discards pending writers before releasing admission.
    /// - Parameter code: Local going-away or protocol-error code, excluding close reasons.
    private func finishClose(code: URLSessionWebSocketTask.CloseCode) async {
        if let closeTask { await closeTask.value; return }
        closed = true
        task.cancel(with: code, reason: nil)
        task.cancel()
        let pending = writers
        writers.removeAll()
        for writer in pending { writer.resume(throwing: TransportFailure.closed) }
        let owner = self.owner
        let identifier = self.identifier
        let cleanup = Task { await owner.release(identifier) }
        closeTask = cleanup
        await cleanup.value
    }
}
#endif
