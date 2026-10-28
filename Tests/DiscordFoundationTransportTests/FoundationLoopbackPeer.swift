// File: Tests/DiscordFoundationTransportTests/FoundationLoopbackPeer.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

#if canImport(Darwin)
import Foundation
import Network

/// Deterministic local HTTP or WebSocket peer; no Discord host or credentials are used.
actor FoundationLoopbackPeer {
    enum Behavior: Sendable {
        case response(Data)
        case stalledHTTP
        case webSocketEcho
    }

    private let listener: NWListener
    private let behavior: Behavior
    private let queue = DispatchQueue(label: "DiscordKit.FoundationTests.Peer")
    private var connections: [NWConnection] = []
    private var port: UInt16?
    private var readyWaiter: CheckedContinuation<UInt16, any Error>?
    private var requests: [Data] = []
    private var requestWaiter: CheckedContinuation<Data, Never>?
    private var closed = false

    /// Creates an IPv4 loopback listener with an automatically allocated port.
    /// - Parameter behavior: Static HTTP response, stalled HTTP or complete-message echo.
    /// - Throws: Local socket/listener construction failures.
    init(behavior: Behavior) throws {
        self.behavior = behavior
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        if case .webSocketEcho = behavior {
            let options = NWProtocolWebSocket.Options()
            options.autoReplyPing = true
            options.maximumMessageSize = 1_024 * 1_024
            options.setClientRequestHandler(DispatchQueue(label: "DiscordKit.FoundationTests.Upgrade")) { _, _ in
                NWProtocolWebSocket.Response(status: .accept, subprotocol: nil, additionalHeaders: [])
            }
            parameters.defaultProtocolStack.applicationProtocols.insert(options, at: 0)
        }
        listener = try NWListener(using: parameters)
    }

    /// Starts the listener and returns only after its actual port becomes available.
    /// - Returns: IPv4 loopback URL using HTTP or WebSocket according to behavior.
    /// - Throws: Listener startup or URL construction failures.
    func start() async throws -> URL {
        listener.stateUpdateHandler = { state in
            Task { await self.listenerChanged(state) }
        }
        listener.newConnectionHandler = { connection in
            Task { await self.accept(connection) }
        }
        listener.start(queue: queue)
        let value: UInt16
        if let port { value = port }
        else { value = try await withCheckedThrowingContinuation { readyWaiter = $0 } }
        let scheme: String
        if case .webSocketEcho = behavior { scheme = "ws" } else { scheme = "http" }
        return URL(string: "\(scheme)://127.0.0.1:\(value)/test")!
    }

    /// Reports the first complete HTTP request after it has actually reached the peer.
    /// - Returns: Raw local fixture bytes, never real credentials.
    func waitForRequest() async -> Data {
        if let first = requests.first { return first }
        return await withCheckedContinuation { requestWaiter = $0 }
    }

    /// Returns the number of fully received HTTP requests for redirect/replay assertions.
    var requestCount: Int { requests.count }

    /// Returns the latest request for cookie/cache isolation assertions, if any arrived.
    var lastRequest: Data? { requests.last }

    /// Sends a server-originated binary message after the client's upgrade has completed.
    /// - Parameter bytes: Finite fixture message, permitting incoming-limit tests.
    /// - Throws: Missing connection or native send failure.
    func sendWebSocket(_ bytes: Data) async throws {
        guard let connection = connections.first else { throw NWError.posix(.ENOTCONN) }
        let metadata = NWProtocolWebSocket.Metadata(opcode: .binary)
        let context = NWConnection.ContentContext(identifier: "fixture-push", metadata: [metadata])
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            connection.send(content: bytes, contentContext: context, isComplete: true, completion: .contentProcessed { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            })
        }
    }

    /// Sends a numeric private/application close status after a completed upgrade.
    /// - Parameter code: Valid RFC 6455 close code, including Discord's 4000-series statuses.
    /// - Throws: Invalid code, absent accepted socket or native send failure.
    func sendWebSocketClose(_ code: UInt16) async throws {
        guard let connection = connections.first else { throw NWError.posix(.ENOTCONN) }
        let metadata = NWProtocolWebSocket.Metadata(opcode: .close)
        metadata.closeCode = try NWProtocolWebSocket.CloseCode(rawValue: code)
        let context = NWConnection.ContentContext(identifier: "fixture-close", metadata: [metadata])
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            connection.send(content: nil, contentContext: context, isComplete: true, completion: .contentProcessed { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            })
        }
    }

    /// Cancels every accepted connection and the listener; safe to repeat.
    func close() {
        guard !closed else { return }
        closed = true
        for connection in connections { connection.cancel() }
        connections.removeAll()
        listener.stateUpdateHandler = nil
        listener.newConnectionHandler = nil
        listener.cancel()
    }

    /// Completes startup on ready or terminal failure without timing-based polling.
    /// - Parameter state: Native listener state received on the dedicated queue.
    private func listenerChanged(_ state: NWListener.State) {
        switch state {
        case .ready:
            if let raw = listener.port?.rawValue {
                port = raw
                readyWaiter?.resume(returning: raw)
                readyWaiter = nil
            }
        case .failed(let error):
            readyWaiter?.resume(throwing: error)
            readyWaiter = nil
        default: break
        }
    }

    /// Accepts a single local connection and starts bounded fixture reads.
    /// - Parameter connection: Newly accepted socket, owned until peer closure.
    private func accept(_ connection: NWConnection) {
        guard !closed else { connection.cancel(); return }
        connections.append(connection)
        connection.start(queue: queue)
        if case .webSocketEcho = behavior { receiveWebSocket(connection) }
        else { receiveHTTP(connection, prefix: Data()) }
    }

    /// Accumulates at most 64 KiB of fixture request bytes until Content-Length is met.
    /// - Parameters:
    ///   - connection: Accepted socket belonging to this test peer.
    ///   - prefix: Previously received bytes, bounded to small fixture traffic.
    private func receiveHTTP(_ connection: NWConnection, prefix: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4_096) { bytes, _, complete, error in
            Task { await self.receivedHTTP(connection, prefix: prefix, bytes: bytes, complete: complete, error: error) }
        }
    }

    /// Detects a full local request before responding or leaving it intentionally stalled.
    /// - Parameters:
    ///   - connection: Owning socket.
    ///   - prefix: Existing request bytes.
    ///   - bytes: Optional next bounded read.
    ///   - complete: Native EOF marker.
    ///   - error: Native read error; terminal fixture reads are discarded.
    private func receivedHTTP(_ connection: NWConnection, prefix: Data, bytes: Data?, complete: Bool, error: NWError?) {
        var request = prefix
        request.append(bytes ?? Data())
        guard request.count <= 65_536, error == nil else { connection.cancel(); return }
        if let boundary = request.range(of: Data("\r\n\r\n".utf8)) {
            let metadata = String(decoding: request[..<boundary.lowerBound], as: UTF8.self)
            let lengthLine = metadata.components(separatedBy: "\r\n").first { $0.lowercased().hasPrefix("content-length:") }
            let contentLength = lengthLine.flatMap { Int($0.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)) } ?? 0
            if request.count - boundary.upperBound >= contentLength {
                requests.append(request)
                requestWaiter?.resume(returning: request)
                requestWaiter = nil
                if case .response(let response) = behavior {
                    connection.send(content: response, completion: .contentProcessed { _ in })
                }
                return
            }
        }
        if !complete { receiveHTTP(connection, prefix: request) }
    }

    /// Reads one complete WebSocket message without collecting an application queue.
    /// - Parameter connection: Accepted WebSocket connection with automatic ping replies.
    private func receiveWebSocket(_ connection: NWConnection) {
        connection.receiveMessage { bytes, context, _, error in
            guard error == nil, let metadata = context?.protocolMetadata(definition: NWProtocolWebSocket.definition)
                as? NWProtocolWebSocket.Metadata else { return }
            let outgoing = NWProtocolWebSocket.Metadata(opcode: metadata.opcode)
            let reply = NWConnection.ContentContext(identifier: "echo", metadata: [outgoing])
            connection.send(content: bytes, contentContext: reply, isComplete: true,
                            completion: .contentProcessed { _ in })
            if metadata.opcode != .close { Task { await self.receiveWebSocket(connection) } }
        }
    }
}
#endif
